#!/usr/bin/env python3
"""Assemble the audited MixtarRVS 1.1 graphical root archive from existing P4 layers."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[1]
CORE_STEM = "MixtarRVS-1.0-Core-x86_64"
GRAPHICAL_STEM = "MixtarRVS-1.1-Graphical-x86_64"
PRESERVE_CORE = {"System/Libraries/libc.so.6"}
FORBIDDEN_TOP_LEVEL = {
    "bin", "boot", "dev", "etc", "home", "lib", "lib64", "opt",
    "proc", "run", "sbin", "srv", "sys", "tmp", "usr", "var",
}
REQUIRED_PATHS = (
    "System/Core/Graphics/MWM",
    "System/Core/Graphics/start-graphics",
    "System/UX/Workbench/Workbench",
    "System/Configuration/Graphics/MDDM.config",
    "System/Configuration/OpenRC/init.d/mixtar-graphics",
)


class AssemblyError(RuntimeError):
    pass


def repository_path(value: str, *, output: bool = False) -> Path:
    logical = Path(os.path.abspath(REPO / value))
    try:
        relative = logical.relative_to(REPO)
    except ValueError as error:
        raise AssemblyError(f"Path escapes the repository: {value}") from error
    if not relative.parts:
        raise AssemblyError("Repository root cannot be an input or output path")
    physical = logical.resolve(strict=False)
    physical_anchor = (REPO / relative.parts[0]).resolve(strict=False)
    try:
        physical.relative_to(physical_anchor)
    except ValueError as error:
        raise AssemblyError(f"Path escapes repository area {relative.parts[0]}: {value}") from error
    if output and len(relative.parts) < 2:
        raise AssemblyError(f"Top-level repository area cannot be an output: {value}")
    return physical


def repository_relative(path: Path) -> Path:
    physical = path.resolve(strict=False)
    for area in ("Output", "out", "Product", "System", "Release", "Root", "Kernel"):
        anchor = (REPO / area).resolve(strict=False)
        try:
            suffix = physical.relative_to(anchor)
        except ValueError:
            continue
        return Path(area) / suffix
    raise AssemblyError(f"Cannot map physical path back into repository: {path}")


def require_directory(path: Path, label: str) -> Path:
    if path.is_symlink() or not path.is_dir():
        raise AssemblyError(f"{label} is missing or is not a physical directory: {path}")
    return path


def require_file(path: Path, label: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise AssemblyError(f"{label} is missing or is not a physical file: {path}")
    return path


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def same_regular_file(left: Path, right: Path) -> bool:
    left_stat = left.stat()
    right_stat = right.stat()
    return (
        left_stat.st_size == right_stat.st_size
        and stat.S_IMODE(left_stat.st_mode) == stat.S_IMODE(right_stat.st_mode)
        and digest(left) == digest(right)
    )


def safe_extract(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    base = destination.resolve()
    with tarfile.open(archive, mode="r:*") as source:
        members = source.getmembers()
        for member in members:
            name = member.name.removeprefix("./")
            if not name or name == ".":
                continue
            target = (base / name).resolve(strict=False)
            try:
                target.relative_to(base)
            except ValueError as error:
                raise AssemblyError(f"Core archive path escapes root: {member.name}") from error
            if member.islnk():
                raise AssemblyError(f"Core archive hard link is forbidden: {member.name}")
            if member.issym():
                link = Path(member.linkname)
                link_target = (target.parent / link).resolve(strict=False)
                try:
                    link_target.relative_to(base)
                except ValueError as error:
                    raise AssemblyError(
                        f"Core archive symbolic link escapes root: {member.name} -> {member.linkname}"
                    ) from error
            if (member.ischr() or member.isblk() or member.isfifo()) and not name.startswith(
                "System/Devices/"
            ):
                raise AssemblyError(f"Special file outside System/Devices: {member.name}")
        source.extractall(base, members=members, filter=lambda member, path: member)


def merge_layer(source: Path, destination: Path, layer: str, report: dict[str, object]) -> None:
    identical = report.setdefault("identical", [])
    preserved = report.setdefault("preserved", [])
    copied = report.setdefault("copied", {})

    for item in sorted(source.rglob("*"), key=lambda path: path.relative_to(source).as_posix()):
        relative = item.relative_to(source)
        logical = relative.as_posix()
        target = destination / relative
        target_present = target.exists() or target.is_symlink()

        if item.is_symlink():
            link_target = os.readlink(item)
            if target_present:
                if target.is_symlink() and os.readlink(target) == link_target:
                    identical.append(logical)
                    continue
                raise AssemblyError(f"Conflicting symbolic link from {layer}: {logical}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(link_target, target_is_directory=item.is_dir())
            copied[layer] = int(copied.get(layer, 0)) + 1
            continue

        if item.is_dir():
            if target_present and not target.is_dir():
                raise AssemblyError(f"Directory collides with non-directory from {layer}: {logical}")
            target.mkdir(parents=True, exist_ok=True)
            continue

        if not item.is_file():
            raise AssemblyError(f"Unsupported filesystem object in {layer}: {logical}")

        if target_present:
            if logical in PRESERVE_CORE:
                preserved.append(logical)
                continue
            if target.is_file() and not target.is_symlink() and same_regular_file(item, target):
                identical.append(logical)
                continue
            raise AssemblyError(f"Non-identical layer collision from {layer}: {logical}")

        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)
        copied[layer] = int(copied.get(layer, 0)) + 1


def update_identity(root: Path) -> None:
    identity = require_file(
        root / "System/Configuration/Product/Identity.config",
        "Product identity",
    )
    text = identity.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'(?m)^(version\s*=\s*)"(?:1\.0|1\.0-Core)"(\s*(?:#.*)?)$',
        r'\1"1.1"\2',
        text,
        count=1,
    )
    if count != 1:
        raise AssemblyError("Unexpected product identity version count")
    identity.write_text(updated, encoding="utf-8", newline="\n")


def enable_graphics_service(root: Path) -> None:
    service = require_file(
        root / "System/Configuration/OpenRC/init.d/mixtar-graphics",
        "mixtar-graphics OpenRC service",
    )
    destination = root / "System/Configuration/OpenRC/runlevels/default/mixtar-graphics"
    if destination.exists() or destination.is_symlink():
        if destination.is_file() and not destination.is_symlink() and same_regular_file(service, destination):
            return
        raise AssemblyError("Conflicting mixtar-graphics default-runlevel entry")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(service, destination)


def validate_root(root: Path) -> None:
    present_forbidden = sorted(name for name in FORBIDDEN_TOP_LEVEL if (root / name).exists())
    if present_forbidden:
        raise AssemblyError(
            "FHS paths leaked into the public Mixtar root: " + ", ".join(present_forbidden)
        )
    for logical in REQUIRED_PATHS:
        require_file(root / logical, f"Required graphical runtime file {logical}")
    runlevel = root / "System/Configuration/OpenRC/runlevels/default/mixtar-graphics"
    if runlevel.is_symlink() or not runlevel.is_file():
        raise AssemblyError("mixtar-graphics is not physically enabled in the default runlevel")
    hardlinks = [
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and not path.is_symlink() and path.stat().st_nlink != 1
    ]
    if hardlinks:
        raise AssemblyError("Hard links are forbidden in GraphicalRoot: " + ", ".join(hardlinks[:8]))


def deterministic_tar(root: Path, archive: Path, epoch: int) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    temporary = archive.with_name(f".{archive.name}.tmp")
    if temporary.exists() or temporary.is_symlink():
        if temporary.is_dir():
            raise AssemblyError(f"Archive temporary path is unexpectedly a directory: {temporary}")
        temporary.unlink()

    with tarfile.open(temporary, mode="w", format=tarfile.PAX_FORMAT, dereference=False) as output:
        for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
            logical = path.relative_to(root).as_posix()
            info = output.gettarinfo(str(path), arcname=logical)
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = epoch
            info.pax_headers = {}
            if info.isreg():
                with path.open("rb") as stream:
                    output.addfile(info, stream)
            else:
                output.addfile(info)

    temporary.replace(archive)


def rewrite_product_section(text: str) -> str:
    lines = text.splitlines()
    section = ""
    for index, line in enumerate(lines):
        match = re.match(r"^\s*\[([^]]+)\]\s*$", line)
        if match:
            section = match.group(1)
            continue
        if section != "product":
            continue
        key = re.match(r"^(\s*)([A-Za-z0-9_-]+)(\s*=\s*)(.*)$", line)
        if not key:
            continue
        name = key.group(2)
        value = key.group(4)
        if name == "version":
            comment = ""
            if " #" in value:
                _, comment = value.split(" #", 1)
                comment = " #" + comment
            lines[index] = f'{key.group(1)}{name}{key.group(3)}"1.1"{comment}'
        elif name in {"edition", "profile"} and re.match(r'^"Core"\s*(?:#.*)?$', value):
            lines[index] = f'{key.group(1)}{name}{key.group(3)}"Graphical"'
    return "\n".join(lines) + "\n"


def derive_image_config(base_config: Path, output_config: Path, archive: Path) -> None:
    text = base_config.read_text(encoding="utf-8")
    if CORE_STEM not in text:
        raise AssemblyError(f"Core image stem is absent from base contract: {CORE_STEM}")
    text = text.replace(CORE_STEM, GRAPHICAL_STEM)
    text = text.replace("Output/P4/CoreRoot", "Output/P4/GraphicalRoot")
    text = rewrite_product_section(text)
    document = tomllib.loads(text)
    output = document.get("output")
    if not isinstance(output, dict):
        raise AssemblyError("Derived graphical contract has no [output] table")
    root_archive = output.get("root_archive")
    expected_archive = repository_relative(archive).as_posix()
    if root_archive != expected_archive:
        raise AssemblyError(
            f"Derived root archive mismatch: expected {expected_archive}, found {root_archive!r}"
        )
    if not isinstance(document.get("image"), dict):
        raise AssemblyError("Derived graphical contract has no [image] table")
    output_config.parent.mkdir(parents=True, exist_ok=True)
    output_config.write_text(text, encoding="utf-8", newline="\n")


def root_statistics(root: Path) -> tuple[int, int, int, int]:
    files = directories = symlinks = total_bytes = 0
    for path in root.rglob("*"):
        if path.is_symlink():
            symlinks += 1
        elif path.is_dir():
            directories += 1
        elif path.is_file():
            files += 1
            total_bytes += path.stat().st_size
    return files, directories, symlinks, total_bytes


def required_table(document: dict[str, object], name: str) -> dict[str, object]:
    value = document.get(name)
    if not isinstance(value, dict):
        raise AssemblyError(f"Missing [{name}] table in release input")
    return value


def required_string(values: dict[str, object], name: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or not value:
        raise AssemblyError(f"Missing string value in release input: {name}")
    return value


def root_contract_path(root: Path, value: str) -> Path:
    logical = Path(value.lstrip("/"))
    if not logical.parts or any(part in {"", ".", ".."} for part in logical.parts):
        raise AssemblyError(f"Invalid Mixtar contract path: {value}")
    return root.joinpath(*logical.parts)


def collect_manifest_evidence(root: Path, base_config: Path) -> dict[str, str]:
    with base_config.open("rb") as stream:
        config = tomllib.load(stream)
    contracts = required_table(config, "contracts")
    executor = required_table(config, "executor")
    zsh = required_table(config, "zsh")
    base = required_table(config, "base")

    identity_path = require_file(
        root_contract_path(root, required_string(contracts, "identity")),
        "Product identity for graphical manifest",
    )
    with identity_path.open("rb") as stream:
        identity = tomllib.load(stream)
    identity_product = required_table(identity, "product")

    release_path = require_file(
        repository_path(required_string(base, "release_lock")),
        "Release lock for graphical manifest",
    )
    with release_path.open("rb") as stream:
        release = tomllib.load(stream)
    release_zsh = required_table(release, "zsh")

    executor_path = require_file(
        root_contract_path(root, required_string(executor, "install_path")),
        "Executor for graphical manifest",
    )
    zsh_path = require_file(
        root_contract_path(root, required_string(zsh, "bundle")) / "Program" / "zsh",
        "zsh for graphical manifest",
    )
    return {
        "product_id": required_string(identity_product, "id"),
        "executor_runtime": required_string(executor, "runtime"),
        "executor_sha256": digest(executor_path),
        "zsh_version": required_string(release_zsh, "version"),
        "zsh_sha256": digest(zsh_path),
    }

def write_manifest(
    archive: Path,
    manifest: Path,
    report: dict[str, object],
    statistics: tuple[int, int, int, int],
    epoch: int,
    evidence: dict[str, str],
) -> None:
    files, directories, symlinks, total_bytes = statistics
    copied = report.get("copied", {})
    identical = report.get("identical", [])
    preserved = sorted(set(report.get("preserved", [])))
    lines = [
        "schema = 1",
        "",
        "[product]",
        f'id = "{evidence["product_id"]}"',
        'name = "MixtarRVS"',
        'version = "1.1"',
        'profile = "Graphical"',
        'architecture = "x86_64"',
        "",
        "[inputs]",
        f'core_archive = "Output/P4/{CORE_STEM}.root.tar"',
        'graphics = "Output/P4/GraphicsRoot"',
        'mddm = "out/Product/MWMStack/Root"',
        "",
        "[merge]",
        f'core_preserved = {len(preserved)}',
        f'identical_collisions = {len(identical)}',
        f'mddm_files_added = {int(copied.get("mddm", 0))}',
        f'graphics_files_added = {int(copied.get("graphics", 0))}',
        "preserved_paths = [" + ", ".join(f'"{path}"' for path in preserved) + "]",
        "",
        "[components.executor]",
        f'runtime = "{evidence["executor_runtime"]}"',
        f'sha256 = "{evidence["executor_sha256"]}"',
        "",
        "[components.zsh]",
        f'version = "{evidence["zsh_version"]}"',
        f'sha256 = "{evidence["zsh_sha256"]}"',
        "",
        "[artifacts.root]",
        f'archive = "{repository_relative(archive).as_posix()}"',
        f'archive_sha256 = "{digest(archive)}"',
        "",
        "[output]",
        'materialized_root = false',
        f'archive = "{repository_relative(archive).as_posix()}"',
        f'archive_sha256 = "{digest(archive)}"',
        f'files = {files}',
        f'directories = {directories}',
        f'symlinks = {symlinks}',
        f'bytes = {total_bytes}',
        f'source_date_epoch = {epoch}',
        "",
    ]
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def assemble(options: argparse.Namespace) -> tuple[Path, Path, Path]:
    core_archive = require_file(repository_path(options.core_archive), "Core root archive")
    graphics = require_directory(repository_path(options.graphics_root), "Graphics root")
    mddm = require_directory(repository_path(options.mddm_root), "MDDM root")
    archive = repository_path(options.archive, output=True)
    manifest = repository_path(options.manifest, output=True)
    base_config = require_file(repository_path(options.base_config), "Base image contract")
    output_config = repository_path(options.output_config, output=True)
    report: dict[str, object] = {"copied": {}}

    native_parent = os.environ.get("MIXTAR_NATIVE_TMPDIR")
    with tempfile.TemporaryDirectory(prefix="mixtar-graphical-", dir=native_parent) as temporary:
        root = Path(temporary) / "Root"
        safe_extract(core_archive, root)
        merge_layer(mddm, root, "mddm", report)
        merge_layer(graphics, root, "graphics", report)
        update_identity(root)
        enable_graphics_service(root)
        validate_root(root)
        statistics = root_statistics(root)
        evidence = collect_manifest_evidence(root, base_config)
        deterministic_tar(root, archive, options.source_date_epoch)
        write_manifest(
            archive,
            manifest,
            report,
            statistics,
            options.source_date_epoch,
            evidence,
        )

    derive_image_config(base_config, output_config, archive)
    return archive, manifest, output_config


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--core-archive",
        default=f"Output/P4/{CORE_STEM}.root.tar",
    )
    parser.add_argument("--graphics-root", default="Output/P4/GraphicsRoot")
    parser.add_argument("--mddm-root", default="out/Product/MWMStack/Root")
    parser.add_argument(
        "--archive",
        default=f"Output/P4/{GRAPHICAL_STEM}.root.tar",
    )
    parser.add_argument(
        "--manifest",
        default=f"Output/P4/{GRAPHICAL_STEM}.manifest.config",
    )
    parser.add_argument("--base-config", default="Product/Core.config")
    parser.add_argument("--output-config", default="out/Product/Graphical.config")
    parser.add_argument(
        "--source-date-epoch",
        type=int,
        default=int(os.environ.get("SOURCE_DATE_EPOCH", "1784160000")),
    )
    options = parser.parse_args()

    try:
        outputs = assemble(options)
    except (AssemblyError, OSError, shutil.Error, tarfile.TarError, tomllib.TOMLDecodeError) as error:
        print(f"MixtarRVS graphical root assembly failed: {error}", file=sys.stderr)
        return 1

    for path in outputs:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())