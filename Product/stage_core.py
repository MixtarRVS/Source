#!/usr/bin/env python3
"""Create a deterministic MixtarRVS 1.0 Core root from M1 plus Product/Root."""

from __future__ import annotations

import argparse
import hashlib
import os
import posixpath
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile
import tomllib


REPOSITORY = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = (REPOSITORY / "Output").absolute()


class StageError(RuntimeError):
    pass


def repository_path(value: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = REPOSITORY / candidate
    path = candidate.absolute()
    try:
        relative = path.relative_to(REPOSITORY)
    except ValueError as error:
        raise StageError(f"Path escapes the repository: {value}") from error

    allowed_output = (REPOSITORY / "Output").absolute()
    current = REPOSITORY
    for part in relative.parts:
        current /= part
        is_junction = getattr(current, "is_junction", None)
        is_reparse = current.is_symlink() or (is_junction is not None and is_junction())
        if not is_reparse or current == allowed_output:
            continue
        target = current.resolve()
        try:
            target.relative_to(REPOSITORY)
        except ValueError as error:
            raise StageError(f"Path crosses an external reparse point: {value}") from error
    return path
def output_path(value: str) -> Path:
    path = repository_path(value)
    try:
        path.relative_to(OUTPUT_ROOT)
    except ValueError as error:
        raise StageError(f"Generated artifact must be below Output/: {value}") from error
    return path


def logical_path(root: Path, value: str) -> Path:
    logical = PurePosixPath(value.lstrip("/"))
    if not logical.parts or any(part in {"", ".", ".."} for part in logical.parts):
        raise StageError(f"Invalid Mixtar path: {value}")
    return root.joinpath(*logical.parts)


def table(document: dict[str, object], name: str) -> dict[str, object]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise StageError(f"Missing [{name}] table")
    return value


def string_value(values: dict[str, object], name: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or not value:
        raise StageError(f"Missing string value: {name}")
    return value


def integer_value(values: dict[str, object], name: str) -> int:
    value = values.get(name)
    if not isinstance(value, int) or isinstance(value, bool):
        raise StageError(f"Missing integer value: {name}")
    return value


def load_toml(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise StageError(f"Required file does not exist: {path}")
    with path.open("rb") as stream:
        return tomllib.load(stream)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def assert_native_executor(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise StageError(f"Executor is not a regular file: {path}")
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) < 20 or header[:4] != b"\x7fELF":
        raise StageError("Executor is not an ELF executable")
    if header[4] != 2 or header[5] != 1:
        raise StageError("Executor must be little-endian ELF64")
    if int.from_bytes(header[16:18], "little") not in {2, 3}:
        raise StageError("Executor must be ET_EXEC or ET_DYN")
    if int.from_bytes(header[18:20], "little") != 62:
        raise StageError("Executor must target x86_64")


def reject_overlay_links(root: Path) -> None:
    if root.is_symlink() or not root.is_dir():
        raise StageError(f"Product overlay is not a physical directory: {root}")
    for directory, directories, files in os.walk(root, followlinks=False):
        parent = Path(directory)
        for name in [*directories, *files]:
            candidate = parent / name
            if candidate.is_symlink():
                raise StageError(f"Product overlay contains a symbolic link: {candidate}")


def rootfs_filter(
    member: tarfile.TarInfo, destination: str
) -> tarfile.TarInfo | None:
    name = PurePosixPath(member.name)
    if name.is_absolute() or ".." in name.parts:
        raise StageError(f"Unsafe path in base root archive: {member.name}")

    if member.issym():
        target = PurePosixPath(member.linkname)
        if target.is_absolute():
            target = PurePosixPath(*target.parts[1:])
            if not target.parts or ".." in target.parts:
                raise StageError(f"Unsafe link in base root archive: {member.name}")
            start = name.parent.as_posix() or "."
            member = member.replace(
                linkname=posixpath.relpath(target.as_posix(), start=start),
                deep=False,
            )
    elif member.islnk():
        target = PurePosixPath(member.linkname)
        if target.is_absolute():
            target = PurePosixPath(*target.parts[1:])
            if not target.parts or ".." in target.parts:
                raise StageError(f"Unsafe hardlink in base root archive: {member.name}")
            member = member.replace(linkname=target.as_posix(), deep=False)

    if member.ischr() or member.isblk() or member.isfifo():
        destination_root = Path(destination).resolve()
        extracted_path = destination_root.joinpath(*name.parts).resolve()
        try:
            extracted_path.relative_to(destination_root)
        except ValueError as error:
            raise StageError(
                f"Special archive member escapes destination: {member.name}"
            ) from error
        return member

    try:
        filtered = tarfile.data_filter(member, destination)
    except tarfile.FilterError as error:
        raise StageError(f"Unsafe archive member {member.name}: {error}") from error
    if filtered is None:
        return None
    return filtered.replace(mode=member.mode, deep=False)


def extract_base(archive: Path, destination: Path) -> None:
    if archive.is_symlink() or not archive.is_file():
        raise StageError(f"Base root archive does not exist: {archive}")
    with tarfile.open(archive, "r:*") as package:
        package.extractall(destination, filter=rootfs_filter)


def copy_regular(source: Path, destination: Path, executable: bool = False) -> None:
    if source.is_symlink() or not source.is_file():
        raise StageError(f"Expected a physical file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    mode = stat.S_IMODE(source.stat().st_mode)
    if executable:
        mode |= stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    os.chmod(destination, mode)


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        metadata = path.lstat()
        node_mode = metadata.st_mode
        mode = stat.S_IMODE(node_mode)
        digest.update(relative + b"\0" + f"{mode:o}".encode("ascii") + b"\0")
        if stat.S_ISLNK(node_mode):
            digest.update(b"L" + os.readlink(path).encode("utf-8") + b"\0")
        elif stat.S_ISREG(node_mode):
            digest.update(b"F" + sha256(path).encode("ascii") + b"\0")
        elif stat.S_ISDIR(node_mode):
            digest.update(b"D\0")
        elif stat.S_ISCHR(node_mode):
            device = f"{os.major(metadata.st_rdev)}:{os.minor(metadata.st_rdev)}"
            digest.update(b"C" + device.encode("ascii") + b"\0")
        elif stat.S_ISBLK(node_mode):
            device = f"{os.major(metadata.st_rdev)}:{os.minor(metadata.st_rdev)}"
            digest.update(b"B" + device.encode("ascii") + b"\0")
        elif stat.S_ISFIFO(node_mode):
            digest.update(b"P\0")
        else:
            raise StageError(f"Unsupported node in product root: {path}")
    return digest.hexdigest()


def write_deterministic_tar(root: Path, destination: Path, epoch: int) -> None:
    temporary = destination.with_name(destination.name + ".tmp")
    temporary.unlink(missing_ok=True)
    with tarfile.open(temporary, "w", format=tarfile.PAX_FORMAT) as package:
        for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
            arcname = path.relative_to(root).as_posix()
            info = package.gettarinfo(str(path), arcname)
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = epoch
            if path.is_file() and not path.is_symlink():
                with path.open("rb") as stream:
                    package.addfile(info, stream)
            else:
                package.addfile(info)
    os.replace(temporary, destination)


def inspection_ignore(directory: str, names: list[str]) -> set[str]:
    ignored: set[str] = set()
    for name in names:
        mode = (Path(directory) / name).lstat().st_mode
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode) or stat.S_ISLNK(mode)):
            ignored.add(name)
    return ignored


def replace_output(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    for path in (temporary, destination):
        if path.exists() or path.is_symlink():
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            else:
                path.unlink()
    shutil.copytree(
        source,
        temporary,
        symlinks=True,
        ignore=inspection_ignore,
    )
    os.replace(temporary, destination)


def quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_identity(root: Path, product: dict[str, object]) -> None:
    identity = logical_path(root, "System/Configuration/Product/Identity.config")
    identity.parent.mkdir(parents=True, exist_ok=True)
    content = (
        "schema = 1\n\n"
        "[product]\n"
        f"id = {quote(string_value(product, 'id'))}\n"
        f"name = {quote(string_value(product, 'name'))}\n"
        f"version = {quote(string_value(product, 'version'))}\n"
        f"architecture = {quote(string_value(product, 'architecture'))}\n"
        f"base_release = {quote(string_value(product, 'base_release'))}\n"
        f"interface = {quote(string_value(product, 'interface'))}\n"
        f"language = {quote(string_value(product, 'language'))}\n"
    )
    identity.write_text(content, encoding="utf-8", newline="\n")


def stage(document: dict[str, object]) -> tuple[Path, Path, Path]:
    product = table(document, "product")
    base = table(document, "base")
    executor = table(document, "executor")
    overlay = table(document, "overlay")
    zsh = table(document, "zsh")
    runtime = table(document, "runtime")
    output = table(document, "output")

    base_archive = repository_path(string_value(base, "root_archive"))
    release_lock = repository_path(string_value(base, "release_lock"))
    overlay_root = repository_path(string_value(overlay, "root"))
    executor_binary = (
        repository_path(string_value(executor, "publish_directory"))
        / string_value(executor, "binary")
    )
    zsh_template = repository_path(string_value(zsh, "template"))
    root_output = output_path(string_value(output, "root_directory"))
    archive_output = output_path(string_value(output, "root_archive"))
    manifest_output = output_path(string_value(output, "manifest"))

    release = load_toml(release_lock)
    zsh_release = table(release, "zsh")
    zsh_version = string_value(zsh_release, "version")
    assert_native_executor(executor_binary)
    reject_overlay_links(overlay_root)
    if zsh_template.is_symlink() or not zsh_template.is_file():
        raise StageError(f"Missing zsh APX template: {zsh_template}")

    if os.name == "nt":
        raise StageError("Core root staging must run on Linux or WSL")
    root_output.parent.mkdir(parents=True, exist_ok=True)
    temporary_parent = Path(
        tempfile.mkdtemp(prefix=".mixtar-core-")
    )
    staged_root = temporary_parent / "Root"
    staged_root.mkdir()
    try:
        extract_base(base_archive, staged_root)
        shutil.copytree(overlay_root, staged_root, dirs_exist_ok=True, symlinks=False)

        installed_executor = logical_path(
            staged_root, string_value(executor, "install_path")
        )
        copy_regular(executor_binary, installed_executor, executable=True)

        zsh_source = logical_path(staged_root, string_value(zsh, "source"))
        zsh_bundle = logical_path(staged_root, string_value(zsh, "bundle"))
        copy_regular(zsh_source, zsh_bundle / "Program/zsh", executable=True)
        descriptor = zsh_template.read_text(encoding="utf-8").replace(
            "@ZSH_VERSION@", zsh_version
        )
        if "@ZSH_VERSION@" in descriptor:
            raise StageError("zsh APX template was not rendered")
        (zsh_bundle / "zsh.config").write_text(
            descriptor, encoding="utf-8", newline="\n"
        )

        service_source = logical_path(staged_root, string_value(runtime, "service"))
        service_runlevel = logical_path(
            staged_root, string_value(runtime, "runlevel")
        )
        copy_regular(service_source, service_runlevel, executable=True)
        write_identity(staged_root, product)

        tree_hash = tree_digest(staged_root)
        installed_zsh_hash = sha256(
            logical_path(staged_root, string_value(zsh, "bundle")) / "Program/zsh"
        )
        archive_output.parent.mkdir(parents=True, exist_ok=True)
        write_deterministic_tar(
            staged_root,
            archive_output,
            integer_value(product, "source_date_epoch"),
        )
        if bool(output.get("materialize_root", True)):
            replace_output(staged_root, root_output)
    finally:
        if temporary_parent.exists():
            shutil.rmtree(temporary_parent)

    manifest = (        "schema = 1\n\n"
        "[product]\n"
        f"id = {quote(string_value(product, 'id'))}\n"
        f"version = {quote(string_value(product, 'version'))}\n"
        f"architecture = {quote(string_value(product, 'architecture'))}\n\n"
        "[base]\n"
        f"archive = {quote(string_value(base, 'root_archive'))}\n"
        f"sha256 = {quote(sha256(base_archive))}\n\n"
        "[components.executor]\n"
        f"runtime = {quote(string_value(executor, 'runtime'))}\n"
        f"sha256 = {quote(sha256(executor_binary))}\n\n"
        "[components.zsh]\n"
        f"version = {quote(zsh_version)}\n"
        f"sha256 = {quote(installed_zsh_hash)}\n\n"
        "[artifacts.root]\n"
        f"tree_sha256 = {quote(tree_hash)}\n"
        f"archive = {quote(string_value(output, 'root_archive'))}\n"
        f"archive_sha256 = {quote(sha256(archive_output))}\n"
    )
    manifest_output.parent.mkdir(parents=True, exist_ok=True)
    temporary_manifest = manifest_output.with_name(manifest_output.name + ".tmp")
    temporary_manifest.write_text(manifest, encoding="utf-8", newline="\n")
    os.replace(temporary_manifest, manifest_output)
    return root_output, archive_output, manifest_output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Product/Core.config")
    options = parser.parse_args()
    try:
        config = repository_path(options.config)
        document = load_toml(config)
        if document.get("schema") != 1:
            raise StageError("Unsupported Product/Core.config schema")
        root, archive, manifest = stage(document)
    except (OSError, StageError, tarfile.TarError, tomllib.TOMLDecodeError) as error:
        print(f"MixtarRVS Core staging failed: {error}", file=sys.stderr)
        return 1
    print(f"Staged root: {root}")
    print(f"Root archive: {archive}")
    print(f"Manifest: {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
