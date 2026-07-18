from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import tomllib
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from .ext4 import write_ext4
from .fat import write_fat32
from .gpt import write_gpt_disk
from .initramfs import write_initramfs
from .uki import write_uki

MARKER_FILE = ".mixtar-keep"
MANIFEST_NAME = "manifest.json"
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
COMPONENT_ROLES = {"efi", "efi-stub", "file", "init", "kernel"}
COMPONENT_FORMATS = {"elf", "opaque", "pe"}
ELF_MACHINES = {
    "aarch64": 183,
    "arm": 40,
    "i386": 3,
    "i586": 3,
    "riscv64": 243,
    "x86_64": 62,
}
PE_MACHINES = {
    "aarch64": 0xAA64,
    "arm": 0x01C4,
    "i386": 0x014C,
    "i586": 0x014C,
    "x86_64": 0x8664,
}


class BuildError(RuntimeError):
    pass


@dataclass(frozen=True)
class Component:
    name: str
    source: Path
    source_name: str
    destination: str
    sha256: str
    role: str
    file_format: str
    architecture: str
    mode: str
    uid: int
    gid: int


@dataclass(frozen=True)
class Profile:
    path: Path
    repository: Path
    name: str
    version: str
    architecture: str
    machine: str
    source: Path
    output: Path
    allowed_roots: tuple[str, ...]
    boot_paths: dict[str, str]
    nodes: tuple[dict[str, Any], ...]
    components: tuple[Component, ...]
    requirements: dict[str, bool]
    efi_mountpoint: str
    uki_enabled: bool
    uki_command_line: str
    efi_size_mib: int
    efi_label: str
    root_size_mib: int
    root_label: str


@dataclass(frozen=True)
class Staging:
    root: Path
    esp: Path


@dataclass(frozen=True)
class BuildResult:
    artifact: Path
    manifest: Path
    initramfs: Path
    uki: Path | None
    esp_image: Path
    root_image: Path
    disk_image: Path
    file_count: int


def _table(data: dict[str, Any], name: str) -> dict[str, Any]:
    value = data.get(name)
    if not isinstance(value, dict):
        raise BuildError(f"missing [{name}] table")
    return value


def _text(table: dict[str, Any], key: str) -> str:
    value = table.get(key)
    if not isinstance(value, str) or not value.strip():
        raise BuildError(f"missing or invalid value: {key}")
    return value.strip()


def _boolean(table: dict[str, Any], key: str) -> bool:
    value = table.get(key)
    if not isinstance(value, bool):
        raise BuildError(f"missing or invalid boolean value: {key}")
    return value


def _integer(table: dict[str, Any], key: str) -> int:
    value = table.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise BuildError(f"missing or invalid positive integer value: {key}")
    return value


def _safe_relative(value: str, key: str) -> Path:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise BuildError(f"{key} must be a safe relative path")
    return path


def _system_path(value: str, key: str, allowed_roots: tuple[str, ...]) -> str:
    path = PurePosixPath(value)
    if not path.is_absolute() or ".." in path.parts:
        raise BuildError(f"{key} must be an absolute Mixtar path")
    parts = path.parts
    if len(parts) < 2 or parts[1] not in allowed_roots:
        raise BuildError(f"{key} is outside the allowed Mixtar roots")
    return path.as_posix()


def _load_nodes(
    filesystem: dict[str, Any], allowed_roots: tuple[str, ...]
) -> tuple[dict[str, Any], ...]:
    raw_nodes = filesystem.get("nodes", [])
    if not isinstance(raw_nodes, list):
        raise BuildError("filesystem.nodes must be an array of tables")

    nodes: list[dict[str, Any]] = []
    paths: set[str] = set()
    for index, raw in enumerate(raw_nodes):
        if not isinstance(raw, dict):
            raise BuildError(f"filesystem.nodes[{index}] must be a table")
        path = _system_path(
            _text(raw, "path"), f"filesystem.nodes[{index}].path", allowed_roots
        )
        node_type = _text(raw, "type")
        if node_type != "character":
            raise BuildError(f"unsupported node type at {path}: {node_type}")
        if path in paths:
            raise BuildError(f"duplicate filesystem node: {path}")

        major = raw.get("major")
        minor = raw.get("minor")
        uid = raw.get("uid", 0)
        gid = raw.get("gid", 0)
        mode = raw.get("mode", "0600")
        if not all(
            isinstance(value, int) and value >= 0 for value in (major, minor, uid, gid)
        ):
            raise BuildError(f"invalid device numbers or ownership at {path}")
        if (
            not isinstance(mode, str)
            or len(mode) != 4
            or any(char not in "01234567" for char in mode)
        ):
            raise BuildError(f"invalid mode at {path}: {mode!r}")

        paths.add(path)
        nodes.append(
            {
                "path": path,
                "type": node_type,
                "major": major,
                "minor": minor,
                "mode": mode,
                "uid": uid,
                "gid": gid,
            }
        )
    return tuple(sorted(nodes, key=lambda node: node["path"]))


def _load_components(
    data: dict[str, Any], repository: Path, allowed_roots: tuple[str, ...]
) -> tuple[Component, ...]:
    raw_components = data.get("component", [])
    if not isinstance(raw_components, list):
        raise BuildError("component must be an array of tables")

    components: list[Component] = []
    names: set[str] = set()
    destinations: set[str] = set()
    unique_roles: set[str] = set()
    for index, raw in enumerate(raw_components):
        if not isinstance(raw, dict):
            raise BuildError(f"component[{index}] must be a table")
        name = _text(raw, "name")
        source_name = _safe_relative(_text(raw, "source"), f"component[{index}].source")
        destination = _system_path(
            _text(raw, "destination"),
            f"component[{index}].destination",
            allowed_roots,
        )
        expected_hash = _text(raw, "sha256").lower()
        role = _text(raw, "role").lower()
        file_format = _text(raw, "format").lower()
        architecture = _text(raw, "architecture").lower()
        mode = raw.get("mode", "0644")
        uid = raw.get("uid", 0)
        gid = raw.get("gid", 0)
        if len(expected_hash) != 64 or any(
            character not in "0123456789abcdef" for character in expected_hash
        ):
            raise BuildError(f"component {name!r} has an invalid SHA-256")
        if role not in COMPONENT_ROLES:
            raise BuildError(f"component {name!r} has an unsupported role: {role}")
        if file_format not in COMPONENT_FORMATS:
            raise BuildError(
                f"component {name!r} has an unsupported format: {file_format}"
            )
        if architecture not in {*ELF_MACHINES, "any"}:
            raise BuildError(
                f"component {name!r} has an unsupported architecture: {architecture}"
            )
        if (
            not isinstance(mode, str)
            or len(mode) != 4
            or any(character not in "01234567" for character in mode)
        ):
            raise BuildError(f"component {name!r} has an invalid mode: {mode!r}")
        if not all(isinstance(value, int) and value >= 0 for value in (uid, gid)):
            raise BuildError(f"component {name!r} has invalid ownership")
        if name in names:
            raise BuildError(f"duplicate component name: {name}")
        if destination in destinations:
            raise BuildError(f"duplicate component destination: {destination}")
        if role in {"efi", "init", "kernel"} and role in unique_roles:
            raise BuildError(f"duplicate boot component role: {role}")

        names.add(name)
        destinations.add(destination)
        if role in {"efi", "init", "kernel"}:
            unique_roles.add(role)
        components.append(
            Component(
                name=name,
                source=repository / source_name,
                source_name=source_name.as_posix(),
                destination=destination,
                sha256=expected_hash,
                role=role,
                file_format=file_format,
                architecture=architecture,
                mode=mode,
                uid=uid,
                gid=gid,
            )
        )
    return tuple(sorted(components, key=lambda component: component.name))


def load_profile(profile_path: Path) -> Profile:
    path = profile_path.resolve()
    if not path.is_file():
        raise BuildError(f"profile does not exist: {path}")

    with path.open("rb") as stream:
        data = tomllib.load(stream)

    system = _table(data, "system")
    target = _table(data, "target")
    layout = _table(data, "layout")
    output = _table(data, "output")
    boot = _table(data, "boot")
    filesystem = _table(data, "filesystem")
    requirements = _table(data, "requirements")
    volumes = _table(data, "volumes")
    efi_volume = _table(volumes, "efi")
    root_volume = _table(volumes, "root")
    uki = _table(data, "uki")
    roots = layout.get("allowed_roots")
    if (
        not isinstance(roots, list)
        or not roots
        or not all(isinstance(x, str) for x in roots)
    ):
        raise BuildError("layout.allowed_roots must be a non-empty string array")
    if len(set(roots)) != len(roots):
        raise BuildError("layout.allowed_roots contains duplicates")
    for root in roots:
        if not root or "/" in root or "\\" in root or root in {".", ".."}:
            raise BuildError(f"invalid root directory name: {root!r}")

    allowed_roots = tuple(roots)
    boot_paths = {
        "efi": _system_path(_text(boot, "efi"), "boot.efi", allowed_roots),
        "init": _system_path(_text(boot, "init"), "boot.init", allowed_roots),
        "kernel_directory": _system_path(
            _text(boot, "kernel_directory"), "boot.kernel_directory", allowed_roots
        ),
        "console": _system_path(_text(boot, "console"), "boot.console", allowed_roots),
    }
    repository = path.parent.parent
    return Profile(
        path=path,
        repository=repository,
        name=_text(system, "name"),
        version=_text(system, "version"),
        architecture=_text(target, "architecture"),
        machine=_text(target, "machine"),
        source=repository / _safe_relative(_text(layout, "source"), "layout.source"),
        output=repository
        / _safe_relative(_text(output, "directory"), "output.directory"),
        allowed_roots=allowed_roots,
        boot_paths=boot_paths,
        nodes=_load_nodes(filesystem, allowed_roots),
        components=_load_components(data, repository, allowed_roots),
        requirements={
            "bootable": _boolean(requirements, "bootable"),
            "require_efi": _boolean(requirements, "require_efi"),
            "require_init": _boolean(requirements, "require_init"),
            "require_kernel": _boolean(requirements, "require_kernel"),
        },
        efi_mountpoint=_system_path(
            _text(efi_volume, "mountpoint"), "volumes.efi.mountpoint", allowed_roots
        ),
        uki_enabled=_boolean(uki, "enabled"),
        uki_command_line=_text(uki, "command_line"),
        efi_size_mib=_integer(efi_volume, "size_mib"),
        efi_label=_text(efi_volume, "label"),
        root_size_mib=_integer(root_volume, "size_mib"),
        root_label=_text(root_volume, "label"),
    )


def _validate_layout(profile: Profile) -> None:
    if not profile.source.is_dir():
        raise BuildError(f"layout source does not exist: {profile.source}")

    entries = list(profile.source.iterdir())
    files = sorted(entry.name for entry in entries if entry.is_file())
    if files:
        raise BuildError(f"files are not allowed directly in Root: {', '.join(files)}")

    actual = {entry.name for entry in entries if entry.is_dir()}
    allowed = set(profile.allowed_roots)
    unexpected = sorted(actual - allowed)
    missing = sorted(allowed - actual)
    if unexpected:
        raise BuildError(f"unexpected root directories: {', '.join(unexpected)}")
    if missing:
        raise BuildError(f"missing root directories: {', '.join(missing)}")


def _copy_tree(profile: Profile, staging: Staging) -> None:
    for root in profile.allowed_roots:
        destination = staging.root / root
        destination.mkdir(parents=True)
        shutil.copytree(
            profile.source / root,
            destination,
            dirs_exist_ok=True,
            ignore=shutil.ignore_patterns(MARKER_FILE, "__pycache__"),
        )


def _validate_elf(component: Component) -> None:
    header = component.source.read_bytes()[:20]
    if len(header) < 20 or header[:4] != b"\x7fELF":
        raise BuildError(f"component {component.name!r} is not an ELF file")
    if header[5] == 1:
        machine = int.from_bytes(header[18:20], "little")
    elif header[5] == 2:
        machine = int.from_bytes(header[18:20], "big")
    else:
        raise BuildError(f"component {component.name!r} has invalid ELF byte order")
    expected = ELF_MACHINES.get(component.architecture)
    if expected is not None and machine != expected:
        raise BuildError(
            f"component {component.name!r} ELF architecture mismatch: "
            f"expected machine {expected}, got {machine}"
        )


def _validate_pe(component: Component) -> None:
    data = component.source.read_bytes()
    if len(data) < 64 or data[:2] != b"MZ":
        raise BuildError(f"component {component.name!r} is not a PE/COFF file")
    pe_offset = int.from_bytes(data[0x3C:0x40], "little")
    if pe_offset + 6 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise BuildError(f"component {component.name!r} has an invalid PE signature")
    machine = int.from_bytes(data[pe_offset + 4 : pe_offset + 6], "little")
    expected = PE_MACHINES.get(component.architecture)
    if expected is not None and machine != expected:
        raise BuildError(
            f"component {component.name!r} PE architecture mismatch: "
            f"expected machine {expected}, got {machine}"
        )


def _validate_component_binary(component: Component) -> None:
    if component.file_format == "elf":
        _validate_elf(component)
    elif component.file_format == "pe":
        _validate_pe(component)


def _logical_target(
    profile: Profile, staging: Staging, system_path: str
) -> tuple[str, Path]:
    logical = PurePosixPath(system_path)
    mountpoint = PurePosixPath(profile.efi_mountpoint)
    try:
        relative_efi = logical.relative_to(mountpoint)
    except ValueError:
        relative_root = Path(*logical.parts[1:])
        return "Root", staging.root / relative_root
    if relative_efi == PurePosixPath("."):
        return "ESP", staging.esp
    return "ESP", staging.esp.joinpath(*relative_efi.parts)


def _install_components(profile: Profile, staging: Staging) -> list[dict[str, Any]]:
    installed: list[dict[str, Any]] = []
    for component in profile.components:
        if not component.source.is_file():
            raise BuildError(
                f"component source does not exist: {component.source_name}"
            )
        actual_hash = _sha256(component.source)
        if actual_hash != component.sha256:
            raise BuildError(
                f"component {component.name!r} SHA-256 mismatch: "
                f"expected {component.sha256}, got {actual_hash}"
            )
        _validate_component_binary(component)
        expected_destination = {
            "efi": profile.boot_paths["efi"],
            "init": profile.boot_paths["init"],
        }.get(component.role)
        if (
            expected_destination is not None
            and component.destination != expected_destination
        ):
            raise BuildError(
                f"component role {component.role!r} must target {expected_destination}"
            )
        if component.role in {"efi", "init"} and not int(component.mode, 8) & 0o111:
            raise BuildError(f"component role {component.role!r} must be executable")
        volume, destination = _logical_target(profile, staging, component.destination)
        if destination.exists():
            raise BuildError(
                f"component destination already exists: {component.destination}"
            )
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(component.source, destination)
        installed.append(
            {
                "name": component.name,
                "source": component.source_name,
                "destination": component.destination,
                "sha256": actual_hash,
                "size": destination.stat().st_size,
                "role": component.role,
                "format": component.file_format,
                "architecture": component.architecture,
                "mode": component.mode,
                "uid": component.uid,
                "gid": component.gid,
                "volume": volume,
            }
        )
    return installed


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _readiness(profile: Profile) -> dict[str, Any]:
    available_roles = {component.role for component in profile.components}
    if profile.uki_enabled and {"efi-stub", "kernel"} <= available_roles:
        available_roles.add("efi")
    required_roles = {
        role
        for role in ("efi", "init", "kernel")
        if profile.requirements[f"require_{role}"] or profile.requirements["bootable"]
    }
    missing_roles = sorted(required_roles - available_roles)
    return {
        "bootable_requested": profile.requirements["bootable"],
        "ready": not missing_roles,
        "required_roles": sorted(required_roles),
        "available_roles": sorted(available_roles),
        "missing_roles": missing_roles,
    }


def _enforce_requirements(profile: Profile) -> dict[str, Any]:
    readiness = _readiness(profile)
    if readiness["missing_roles"]:
        missing = ", ".join(readiness["missing_roles"])
        raise BuildError(f"profile requirements are not satisfied; missing: {missing}")
    return readiness


def inspect_profile(profile_path: Path) -> dict[str, Any]:
    profile = load_profile(profile_path)
    _validate_layout(profile)
    readiness = _readiness(profile)
    return {
        "system": f"{profile.name} {profile.version}",
        "target": f"{profile.machine} / {profile.architecture}",
        "source": str(profile.source),
        "output": str(profile.output),
        "components": [
            {
                "name": component.name,
                "role": component.role,
                "source": component.source_name,
                "source_present": component.source.is_file(),
                "destination": component.destination,
            }
            for component in profile.components
        ],
        "boot": profile.boot_paths,
        "nodes": list(profile.nodes),
        "volumes": {"ESP": {"mountpoint": profile.efi_mountpoint}},
        "uki": {"enabled": profile.uki_enabled},
        "readiness": readiness,
    }


def _volume_manifest(
    staging: Path,
    components: list[dict[str, Any]],
    volume: str,
    efi_mountpoint: str,
) -> dict[str, Any]:
    directories = sorted(
        PurePosixPath(path.relative_to(staging).as_posix()).as_posix()
        for path in staging.rglob("*")
        if path.is_dir()
    )
    component_metadata = {}
    for item in components:
        if item["volume"] != volume:
            continue
        destination = PurePosixPath(item["destination"])
        if volume == "ESP":
            relative = destination.relative_to(efi_mountpoint).as_posix()
        else:
            relative = destination.as_posix().lstrip("/")
        component_metadata[relative] = item
    files = []
    for path in sorted((path for path in staging.rglob("*") if path.is_file())):
        relative_path = PurePosixPath(path.relative_to(staging).as_posix()).as_posix()
        metadata = component_metadata.get(relative_path, {})
        files.append(
            {
                "path": relative_path,
                "size": path.stat().st_size,
                "sha256": _sha256(path),
                "mode": metadata.get("mode", "0644"),
                "uid": metadata.get("uid", 0),
                "gid": metadata.get("gid", 0),
            }
        )
    return {"directories": directories, "files": files}


def _manifest(
    profile: Profile, staging: Staging, components: list[dict[str, Any]]
) -> dict[str, Any]:
    volumes = {
        "Root": _volume_manifest(
            staging.root, components, "Root", profile.efi_mountpoint
        ),
        "ESP": _volume_manifest(staging.esp, components, "ESP", profile.efi_mountpoint),
    }
    contracts = {}
    for name, system_path in sorted(profile.boot_paths.items()):
        volume, staged_path = _logical_target(profile, staging, system_path)
        contracts[name] = {
            "path": system_path,
            "present": staged_path.exists(),
            "kind": "directory" if name == "kernel_directory" else "file",
            "volume": volume,
        }

    return {
        "schema": 1,
        "builder": "mixtar-builder/0.12.0",
        "system": {"name": profile.name, "version": profile.version},
        "target": {"architecture": profile.architecture, "machine": profile.machine},
        "boot": contracts,
        "components": components,
        "layout": {"nodes": list(profile.nodes)},
        "volumes": volumes,
    }


def _zip_info(name: str, directory: bool, mode: str = "0644") -> zipfile.ZipInfo:
    archive_name = name.rstrip("/") + ("/" if directory else "")
    info = zipfile.ZipInfo(archive_name, ZIP_TIMESTAMP)
    info.create_system = 3
    info.compress_type = zipfile.ZIP_DEFLATED
    permissions = 0o755 if directory else int(mode, 8)
    info.external_attr = (permissions & 0xFFFF) << 16
    return info


def _write_archive(
    staging: Staging, manifest: dict[str, Any], destination: Path
) -> None:
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode(
        "utf-8"
    )
    with zipfile.ZipFile(destination, "w") as archive:
        for volume_name, volume in manifest["volumes"].items():
            volume_root = staging.root if volume_name == "Root" else staging.esp
            archive.writestr(_zip_info(volume_name, True), b"")
            for directory in volume["directories"]:
                archive.writestr(_zip_info(f"{volume_name}/{directory}", True), b"")
            for item in volume["files"]:
                archive.writestr(
                    _zip_info(f"{volume_name}/{item['path']}", False, item["mode"]),
                    (volume_root / item["path"]).read_bytes(),
                )
        archive.writestr(_zip_info(MANIFEST_NAME, False), manifest_bytes)


def _component_for_role(profile: Profile, role: str) -> Component:
    matches = [component for component in profile.components if component.role == role]
    if len(matches) != 1:
        raise BuildError(f"UKI requires exactly one component with role {role!r}")
    return matches[0]


def _build_uki(
    profile: Profile, staging: Staging, initramfs: Path
) -> tuple[Path | None, dict[str, Any] | None]:
    if not profile.uki_enabled:
        return None, None
    stub = _component_for_role(profile, "efi-stub")
    kernel = _component_for_role(profile, "kernel")
    _, destination = _logical_target(profile, staging, profile.boot_paths["efi"])
    os_release = (
        f"NAME={profile.name}\n"
        f"ID=mixtarrvs\n"
        f"VERSION_ID={profile.version}\n"
        f"PRETTY_NAME={profile.name} {profile.version}\n"
    )
    try:
        artifact = write_uki(
            stub.source,
            kernel.source,
            initramfs,
            destination,
            os_release,
            profile.uki_command_line,
        )
    except (OSError, RuntimeError, ValueError) as error:
        raise BuildError(str(error)) from error
    generated = {
        "name": "mixtar-uki",
        "source": "generated",
        "destination": profile.boot_paths["efi"],
        "sha256": artifact["sha256"],
        "size": artifact["size"],
        "role": "efi",
        "format": "pe",
        "architecture": profile.architecture,
        "mode": "0755",
        "uid": 0,
        "gid": 0,
        "volume": "ESP",
    }
    return destination, {"artifact": artifact, "component": generated}


def build(profile_path: Path) -> BuildResult:
    profile = load_profile(profile_path)
    _validate_layout(profile)
    profile.output.mkdir(parents=True, exist_ok=True)
    stem = f"{profile.name}-{profile.version}-{profile.machine}-{profile.architecture}"
    artifact = profile.output / f"{stem}.zip"
    manifest_path = profile.output / f"{stem}.manifest.json"
    initramfs_path = profile.output / f"{stem}.initramfs.cpio.gz"
    esp_image_path = profile.output / f"{stem}.esp.fat"
    root_image_path = profile.output / f"{stem}.root.ext4"
    disk_image_path = profile.output / f"{stem}.disk.img"
    uki_path = None

    with tempfile.TemporaryDirectory(prefix="mixtar-build-") as temporary:
        temporary_root = Path(temporary)
        staging = Staging(root=temporary_root / "Root", esp=temporary_root / "ESP")
        staging.root.mkdir()
        staging.esp.mkdir()
        _copy_tree(profile, staging)
        components = _install_components(profile, staging)
        preliminary = _manifest(profile, staging, components)
        initramfs_artifact = write_initramfs(
            staging.root,
            preliminary["volumes"]["Root"],
            preliminary["layout"]["nodes"],
            initramfs_path,
        )
        uki_path, uki_result = _build_uki(profile, staging, initramfs_path)
        if uki_result is not None:
            components.append(uki_result["component"])
        readiness = _enforce_requirements(profile)
        manifest = _manifest(profile, staging, components)
        manifest["readiness"] = readiness
        manifest["artifacts"] = {"initramfs": initramfs_artifact}
        if uki_result is not None:
            manifest["artifacts"]["uki"] = uki_result["artifact"]
        manifest["artifacts"]["esp"] = write_fat32(
            staging.esp,
            manifest["volumes"]["ESP"],
            esp_image_path,
            profile.efi_size_mib,
            profile.efi_label,
        )
        manifest["artifacts"]["root"] = write_ext4(
            staging.root,
            manifest["volumes"]["Root"],
            manifest["layout"]["nodes"],
            root_image_path,
            profile.root_size_mib,
            profile.root_label,
            f"{profile.name}:{profile.version}",
        )
        manifest["artifacts"]["disk"] = write_gpt_disk(
            esp_image_path,
            root_image_path,
            disk_image_path,
            f"{profile.name}:{profile.version}",
            profile.root_label,
        )
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        _write_archive(staging, manifest, artifact)

    return BuildResult(
        artifact=artifact,
        manifest=manifest_path,
        initramfs=initramfs_path,
        uki=uki_path,
        esp_image=esp_image_path,
        root_image=root_image_path,
        disk_image=disk_image_path,
        file_count=sum(len(volume["files"]) for volume in manifest["volumes"].values()),
    )
