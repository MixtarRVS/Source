#!/usr/bin/env python3
"""Stage and audit the symlink-free MixtarRVS graphical product overlay."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import tomllib


REPOSITORY = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = (REPOSITORY / "Output").absolute()
NEEDED = re.compile(r"Shared library: \[([^]]+)]")
INTERPRETER = re.compile(r"\[Requesting program interpreter: ([^]]+)]")
RUNTIME_RPATH = "/System/Libraries/Graphics:/System/Libraries"
WORKBENCH_RPATH = f"/System/UX/Workbench:{RUNTIME_RPATH}"


class StageError(RuntimeError):
    pass


def repository_path(value: str) -> Path:
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = REPOSITORY / candidate
    path = candidate.absolute()
    try:
        path.relative_to(REPOSITORY)
    except ValueError as error:
        raise StageError(f"Path escapes repository: {value}") from error
    return path


def output_path(value: str) -> Path:
    path = repository_path(value)
    try:
        path.relative_to(OUTPUT_ROOT)
    except ValueError as error:
        raise StageError(f"Artifact must be below Output/: {value}") from error
    return path


def logical_path(root: Path, value: str) -> Path:
    logical = PurePosixPath(value.lstrip("/"))
    if not logical.parts or any(part in {"", ".", ".."} for part in logical.parts):
        raise StageError(f"Invalid Mixtar path: {value}")
    return root.joinpath(*logical.parts)


def load_toml(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise StageError(f"Required file does not exist: {path}")
    with path.open("rb") as stream:
        document = tomllib.load(stream)
    if document.get("schema") != 1:
        raise StageError(f"Unsupported config schema: {path}")
    return document


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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def is_elf(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    with path.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def reject_links(root: Path) -> None:
    if root.is_symlink() or not root.is_dir():
        raise StageError(f"Expected a physical directory: {root}")
    for path in root.rglob("*"):
        if path.is_symlink():
            raise StageError(f"Graphical overlay contains a symbolic link: {path}")


def copy_regular(source: Path, destination: Path, executable: bool = False) -> None:
    if source.is_symlink() or not source.is_file():
        raise StageError(f"Expected a physical file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    mode = stat.S_IMODE(source.stat().st_mode)
    if executable:
        mode |= stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    os.chmod(destination, mode)


def run_tool(
    arguments: list[str], *, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        check=True,
        text=True,
        capture_output=capture,
    )


def expected_rpath(path: Path) -> str:
    if path.name == "Workbench" and path.parent.name == "Workbench":
        return WORKBENCH_RPATH
    return RUNTIME_RPATH


def patch_elf(path: Path, loader: str) -> None:
    run_tool(["patchelf", "--set-rpath", expected_rpath(path), str(path)])
    interpreter = subprocess.run(
        ["patchelf", "--print-interpreter", str(path)],
        text=True,
        capture_output=True,
    )
    if interpreter.returncode == 0 and interpreter.stdout.strip():
        run_tool(["patchelf", "--set-interpreter", loader, str(path)])


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        metadata = path.lstat()
        mode = stat.S_IMODE(metadata.st_mode)
        digest.update(relative + b"\0" + f"{mode:o}".encode("ascii") + b"\0")
        if stat.S_ISREG(metadata.st_mode):
            digest.update(b"F" + sha256(path).encode("ascii") + b"\0")
        elif stat.S_ISDIR(metadata.st_mode):
            digest.update(b"D\0")
        else:
            raise StageError(f"Unsupported node in graphical overlay: {path}")
    return digest.hexdigest()


def write_deterministic_tar(root: Path, destination: Path, epoch: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
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
            if path.is_file():
                with path.open("rb") as stream:
                    package.addfile(info, stream)
            else:
                package.addfile(info)
    os.replace(temporary, destination)


def replace_output(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    for path in (temporary, destination):
        if path.exists():
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
    shutil.copytree(source, temporary, symlinks=False)
    os.replace(temporary, destination)


def write_fontconfig(root: Path) -> None:
    target = logical_path(root, "System/Configuration/Fonts/fonts.conf")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/System/Fonts</dir>
  <cachedir>/System/State/FontCache</cachedir>
  <alias><family>sans-serif</family><prefer><family>Noto Sans</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>Noto Sans Mono</family></prefer></alias>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
  </match>
</fontconfig>
""",
        encoding="utf-8",
        newline="\n",
    )


def write_launcher(root: Path) -> None:
    target = logical_path(root, "System/UX/Workbench/Launch")
    target.write_text(
        """#!/System/Terminal/POSIX/sh
export FONTCONFIG_FILE=/System/Configuration/Fonts/fonts.conf
export FONTCONFIG_PATH=/System/Configuration/Fonts
export LIBGL_DRIVERS_PATH=/System/Libraries/Graphics/dri
exec /System/UX/Workbench/Workbench "$@"
""",
        encoding="utf-8",
        newline="\n",
    )
    os.chmod(target, 0o755)


def read_elf(path: Path) -> tuple[list[str], str | None, str]:
    dynamic = run_tool(["readelf", "-d", str(path)], capture=True).stdout
    program = run_tool(["readelf", "-l", str(path)], capture=True).stdout
    needed = sorted(NEEDED.findall(dynamic))
    match = INTERPRETER.search(program)
    interpreter = match.group(1) if match else None
    rpath = run_tool(["patchelf", "--print-rpath", str(path)], capture=True).stdout.strip()
    return needed, interpreter, rpath


def library_index(*roots: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if path.is_file() and not path.is_symlink():
                result.setdefault(path.name, path)
    return result


def audit_elf(root: Path, base_root: Path, loader: str) -> dict[str, object]:
    overlay_libraries = logical_path(root, "System/Libraries/Graphics")
    base_libraries = logical_path(base_root, "System/Libraries")
    workbench = logical_path(root, "System/UX/Workbench")
    index = library_index(overlay_libraries, base_libraries, workbench)
    required = {
        "libEGL.so.1", "libGLESv2.so.2", "libgbm.so.1", "libfontconfig.so.1",
        "libfreetype.so.6", "libharfbuzz.so.0", "libwayland-client.so.0",
    }
    missing_required = sorted(required - index.keys())
    if missing_required:
        raise StageError(f"Required graphical libraries missing: {', '.join(missing_required)}")

    gallium_libraries = sorted(overlay_libraries.glob("libgallium-*.so"))
    if len(gallium_libraries) != 1:
        raise StageError(
            "Exactly one versioned Mesa libgallium runtime is required"
        )

    egl_needed, _, _ = read_elf(overlay_libraries / "libEGL.so.1")
    if gallium_libraries[0].name not in egl_needed:
        raise StageError("Mesa EGL is not linked to the staged libgallium runtime")

    records: list[dict[str, object]] = []
    unresolved: list[str] = []
    for path in sorted(item for item in root.rglob("*") if is_elf(item)):
        needed, interpreter, rpath = read_elf(path)
        relative = "/" + path.relative_to(root).as_posix()
        if interpreter is not None and interpreter != loader:
            raise StageError(f"Invalid ELF interpreter in {relative}: {interpreter}")
        required_rpath = expected_rpath(path)
        if rpath != required_rpath:
            raise StageError(f"Invalid ELF RPATH in {relative}: {rpath}")
        for dependency in needed:
            if dependency not in index:
                unresolved.append(f"{relative}: {dependency}")
        records.append(
            {
                "path": relative,
                "sha256": sha256(path),
                "interpreter": interpreter,
                "rpath": rpath,
                "needed": needed,
            }
        )
    if unresolved:
        raise StageError("Unresolved ELF dependencies: " + "; ".join(unresolved))
    return {
        "schema": "mixtar.graphics-elf.v1",
        "loader": loader,
        "library_path": RUNTIME_RPATH,
        "files": records,
    }


def extract_core_libraries(archive: Path, destination: Path) -> None:
    prefix = "System/Libraries/"
    destination_root = destination.resolve()
    with tarfile.open(archive, "r:*") as source:
        members = []
        for member in source.getmembers():
            name = member.name.removeprefix("./")
            if name != "System/Libraries" and not name.startswith(prefix):
                continue
            target = (destination_root / name).resolve(strict=False)
            try:
                target.relative_to(destination_root)
            except ValueError as error:
                raise StageError(f"Core archive library escapes root: {member.name}") from error
            if member.ischr() or member.isblk() or member.isfifo():
                raise StageError(f"Unsupported Core library object: {member.name}")
            members.append(member)
        if not members:
            raise StageError(f"Core archive contains no {prefix} tree: {archive}")
        source.extractall(destination_root, members=members, filter="data")

def stage(config_path: Path) -> tuple[Path, Path, Path, Path]:
    document = load_toml(config_path)
    product = table(document, "product")
    base = table(document, "base")
    workbench = table(document, "workbench")
    stack = table(document, "stack")
    output = table(document, "output")

    base_root = repository_path(string_value(base, "core_root"))
    base_archive = repository_path(string_value(base, "core_archive"))
    lock_path = repository_path(string_value(base, "release_lock"))
    lock = load_toml(lock_path)
    release = table(lock, "release")
    stack_root = repository_path(string_value(stack, "build_directory")) / "Root"
    publish = repository_path(string_value(workbench, "publish_directory"))
    root_output = output_path(string_value(output, "root_directory"))
    archive_output = output_path(string_value(output, "root_archive"))
    manifest_output = output_path(string_value(output, "manifest"))
    elf_output = output_path(string_value(output, "elf_report"))
    loader = string_value(stack, "loader")

    if os.name == "nt":
        raise StageError("Graphics staging must run on Linux or WSL")
    if not base_root.is_dir() and not base_archive.is_file():
        raise StageError(
            f"Core product base is missing: root={base_root}, archive={base_archive}"
        )
    reject_links(stack_root)

    temporary_parent = Path(tempfile.mkdtemp(prefix=".mixtar-graphics-"))
    staged_root = temporary_parent / "Root"
    try:
        audit_base_root = base_root
        if not audit_base_root.is_dir():
            audit_base_root = temporary_parent / "Core"
            extract_core_libraries(base_archive, audit_base_root)
        shutil.copytree(stack_root, staged_root, symlinks=False)
        installed = logical_path(staged_root, string_value(workbench, "install_path"))
        installed.mkdir(parents=True, exist_ok=True)
        copy_regular(publish / string_value(workbench, "binary"), installed / "Workbench", True)
        copy_regular(publish / "libSkiaSharp.so", installed / "libSkiaSharp.so")
        copy_regular(publish / "libHarfBuzzSharp.so", installed / "libHarfBuzzSharp.so")
        write_fontconfig(staged_root)
        write_launcher(staged_root)

        identity = logical_path(staged_root, "System/Configuration/Product/Graphics.config")
        identity.parent.mkdir(parents=True, exist_ok=True)
        identity.write_text(
            "schema = 1\n\n"
            "[product]\n"
            f"id = {quote(string_value(product, 'id'))}\n"
            f"name = {quote(string_value(product, 'name'))}\n"
            f"version = {quote(string_value(product, 'version'))}\n"
            f"architecture = {quote(string_value(product, 'architecture'))}\n"
            f"interface = {quote(string_value(product, 'interface'))}\n",
            encoding="utf-8",
            newline="\n",
        )

        for path in staged_root.rglob("*"):
            if is_elf(path):
                patch_elf(path, loader)

        reject_links(staged_root)
        elf_report = audit_elf(staged_root, audit_base_root, loader)
        tree_hash = tree_digest(staged_root)
        payload_bytes = sum(
            path.stat().st_size for path in staged_root.rglob("*") if path.is_file()
        )
        epoch = release.get("source_date_epoch")
        if not isinstance(epoch, int) or isinstance(epoch, bool):
            raise StageError("Invalid release source_date_epoch")
        write_deterministic_tar(staged_root, archive_output, epoch)
        replace_output(staged_root, root_output)
    finally:
        if temporary_parent.exists():
            shutil.rmtree(temporary_parent)

    elf_output.parent.mkdir(parents=True, exist_ok=True)
    temporary_elf = elf_output.with_name(elf_output.name + ".tmp")
    temporary_elf.write_text(
        json.dumps(elf_report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    os.replace(temporary_elf, elf_output)

    sources = lock.get("sources")
    assert isinstance(sources, list)
    manifest_lines = [
        "schema = 1", "", "[product]",
        f"id = {quote(string_value(product, 'id'))}",
        f"version = {quote(string_value(product, 'version'))}",
        f"architecture = {quote(string_value(product, 'architecture'))}",
        "", "[runtime]", 'interface = "wayland-only"',
        'framework = "Avalonia 12.1.0"', 'runtime = "stable .NET 10 Native AOT"',
        f"loader = {quote(loader)}", "", "[artifacts.root]",
        f"tree_sha256 = {quote(tree_hash)}",
        f"payload_bytes = {payload_bytes}",
        f"archive = {quote(string_value(output, 'root_archive'))}",
        f"archive_sha256 = {quote(sha256(archive_output))}",
        f"elf_report = {quote(string_value(output, 'elf_report'))}",
        f"elf_report_sha256 = {quote(sha256(elf_output))}",
    ]
    for source in sources:
        assert isinstance(source, dict)
        name = string_value(source, "id").replace("-", "_")
        manifest_lines.extend(
            [
                "", f"[components.{name}]",
                f"version = {quote(string_value(source, 'version'))}",
                f"source_sha256 = {quote(string_value(source, 'sha256'))}",
            ]
        )
    manifest_output.parent.mkdir(parents=True, exist_ok=True)
    temporary_manifest = manifest_output.with_name(manifest_output.name + ".tmp")
    temporary_manifest.write_text(
        "\n".join(manifest_lines) + "\n", encoding="utf-8", newline="\n"
    )
    os.replace(temporary_manifest, manifest_output)
    return root_output, archive_output, manifest_output, elf_output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="Product/Graphics.config")
    options = parser.parse_args()
    try:
        artifacts = stage(repository_path(options.config))
    except (
        OSError,
        StageError,
        subprocess.CalledProcessError,
        tarfile.TarError,
        tomllib.TOMLDecodeError,
    ) as error:
        print(f"MixtarRVS graphics staging failed: {error}", file=sys.stderr)
        return 1
    for artifact in artifacts:
        print(artifact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
