#!/usr/bin/env python3
"""Build the production DRM/KMS profile of the existing Mixtar MWM stack."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tarfile
import time
import tomllib
import urllib.request
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
LOCK_PATH = REPO / "Release" / "P4.mddm.lock.config"
MWM_LOCK_PATH = REPO / "Release" / "P4.mwm.lock.config"
GRAPHICS_BUILD_JSON = REPO / "out" / "Product" / "GraphicsStack" / "Build.json"
MWM_BUILD_JSON = REPO / "out" / "Product" / "MWMStack" / "Build.json"
BASE_MWM_ROOT = REPO / "out" / "Product" / "MWMStack" / "Root"
GRAPHICS_ROOT = REPO / "out" / "Product" / "GraphicsStack" / "Root"
OUTPUT_DIR = REPO / "Output" / "P4"
LOCAL_ARCHIVES = REPO / "out" / "Product" / "MDDMSources"
PRODUCTION_CONFIG = (
    REPO
    / "Product"
    / "MWM"
    / "Overlay"
    / "System"
    / "Configuration"
    / "Graphics"
    / "MDDM.production.config"
)
MWM_SOURCE = REPO / "Product" / "MWM"
SOURCE_DATE_EPOCH_DEFAULT = 1784160000
RECIPE_ID = b"mddm-build-recipe-v2"
TARGET_RPATH = "/System/Libraries/Graphics:/System/Libraries"
TARGET_INTERPRETER = "/System/Libraries/Loader/ld-linux-x86-64.so.2"


def log(message: str) -> None:
    print(f"[MDDM] {message}", flush=True)


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    capture: bool = False,
) -> str:
    log("+ " + " ".join(str(item) for item in command))
    result = subprocess.run(
        [str(item) for item in command],
        cwd=str(cwd) if cwd else None,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    return result.stdout if capture else ""


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def safe_reset(path: Path, anchor: Path) -> None:
    resolved = path.resolve()
    resolved_anchor = anchor.resolve()
    if resolved == resolved_anchor or resolved_anchor not in resolved.parents:
        raise RuntimeError(f"Refusing to reset path outside {resolved_anchor}: {resolved}")
    if resolved.exists():
        shutil.rmtree(resolved)
    resolved.mkdir(parents=True, exist_ok=True)


def safe_remove_tree(path: Path, anchor: Path) -> None:
    resolved = path.resolve()
    resolved_anchor = anchor.resolve()
    if resolved == resolved_anchor or resolved_anchor not in resolved.parents:
        raise RuntimeError(f"Refusing to remove path outside {resolved_anchor}: {resolved}")
    if resolved.exists():
        shutil.rmtree(resolved)


def load_json(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise RuntimeError(f"Required build metadata is missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def load_lock() -> tuple[dict[str, object], list[dict[str, str]]]:
    data = tomllib.loads(LOCK_PATH.read_text(encoding="utf-8"))
    sources = data.get("sources")
    if not isinstance(sources, list) or not sources:
        raise RuntimeError(f"No sources in {LOCK_PATH}")
    normalized: list[dict[str, str]] = []
    required = ("id", "version", "archive", "url", "sha256")
    optional = ("patch", "patch_sha256")
    for source in sources:
        if not isinstance(source, dict) or not all(key in source for key in required):
            raise RuntimeError(f"Invalid source entry in {LOCK_PATH}: {source!r}")
        entry = {key: str(source[key]) for key in required}
        present = [key for key in optional if key in source]
        if len(present) == 1:
            raise RuntimeError(
                f"Source entry needs both patch and patch_sha256 in {LOCK_PATH}: {source!r}"
            )
        for key in present:
            entry[key] = str(source[key])
        normalized.append(entry)
    return data, normalized


def require_tools() -> None:
    tools = ["cc", "make", "meson", "ninja", "patch", "pkg-config", "patchelf", "readelf"]
    missing = [tool for tool in tools if shutil.which(tool) is None]
    if missing:
        raise RuntimeError("Missing WSL build tools: " + ", ".join(missing))


def ensure_archive(source: dict[str, str], archive_dir: Path, refresh: bool) -> Path:
    destination = archive_dir / source["archive"]
    candidates = (destination, LOCAL_ARCHIVES / source["archive"])
    if not refresh:
        for candidate in candidates:
            if candidate.is_file() and digest(candidate) == source["sha256"]:
                if candidate != destination:
                    shutil.copy2(candidate, destination)
                return destination

    temporary = destination.with_suffix(destination.suffix + ".part")
    temporary.unlink(missing_ok=True)
    request = urllib.request.Request(
        source["url"], headers={"User-Agent": "MixtarRVS-builder/1.0"}
    )
    log(f"Downloading {source['id']} {source['version']}")
    with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output)
    actual = digest(temporary)
    if actual != source["sha256"]:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(
            f"SHA-256 mismatch for {source['archive']}: {actual} != {source['sha256']}"
        )
    temporary.replace(destination)
    return destination


def extract_source(source: dict[str, str], archive: Path, source_dir: Path) -> Path:
    patch_path: Path | None = None
    suffix = source["sha256"][:8]
    if "patch" in source:
        patch_path = REPO / source["patch"]
        if patch_path.is_symlink() or not patch_path.is_file():
            raise RuntimeError(f"Source patch is missing: {patch_path}")
        actual = digest(patch_path)
        if actual != source["patch_sha256"]:
            raise RuntimeError(
                f"SHA-256 mismatch for {source['patch']}: {actual} != {source['patch_sha256']}"
            )
        suffix += f"-{source['patch_sha256'][:8]}"
    destination = source_dir / f"{source['id']}-{source['version']}-{suffix}"
    marker = destination / ".mixtar-source.json"
    if marker.is_file():
        return destination

    unpack = destination.with_name(destination.name + ".unpack")
    safe_reset(unpack, source_dir)
    with tarfile.open(archive, "r:*") as package:
        roots = {
            Path(member.name).parts[0]
            for member in package.getmembers()
            if member.name and Path(member.name).parts
        }
        package.extractall(unpack, filter="data")
    directories = [entry for entry in unpack.iterdir() if entry.is_dir()]
    safe_remove_tree(destination, source_dir)
    if len(roots) == 1 and len(directories) == 1:
        directories[0].replace(destination)
        safe_remove_tree(unpack, source_dir)
    else:
        unpack.replace(destination)
    if patch_path is not None:
        run(["patch", "-p1", "-i", str(patch_path)], cwd=destination)
    marker.write_text(
        json.dumps(
            {
                "id": source["id"],
                "version": source["version"],
                "sha256": source["sha256"],
                "patch_sha256": source.get("patch_sha256", ""),
            },
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return destination


def pc_directories(graphics_build: Path, mwm_build: Path, host_pc: Path) -> list[Path]:
    return [
        host_pc,
        graphics_build / "wayland" / "meson-uninstalled",
        graphics_build / "wayland-protocols" / "meson-uninstalled",
        graphics_build / "libdrm" / "meson-uninstalled",
        graphics_build / "mesa" / "meson-uninstalled",
        mwm_build / "pixman" / "meson-uninstalled",
        mwm_build / "xkbcommon" / "meson-uninstalled",
        mwm_build / "xkeyboard-config" / "meson-uninstalled",
    ]


def refresh_host_pc(devroot: Path, host_pc: Path) -> None:
    safe_reset(host_pc, host_pc.parent)
    target_pc = devroot / "System" / "Libraries" / "pkgconfig"
    if not target_pc.is_dir():
        return
    host_prefix = (devroot / "System").as_posix()
    for source in sorted(target_pc.glob("*.pc")):
        output: list[str] = []
        for line in source.read_text(encoding="utf-8").splitlines():
            if line.startswith("prefix="):
                line = f"prefix={host_prefix}"
            else:
                line = line.replace("=/System", "=${prefix}")
                line = line.replace("-I/System", "-I${prefix}")
                line = line.replace("-L/System", "-L${prefix}")
            output.append(line)
        (host_pc / source.name).write_text(
            "\n".join(output) + "\n",
            encoding="utf-8",
        )


def build_environment(
    jobs: int,
    source_date_epoch: int,
    pkg_dirs: list[Path],
    native_pc: Path,
) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "SOURCE_DATE_EPOCH": str(source_date_epoch),
            "LC_ALL": "C.UTF-8",
            "TZ": "UTC",
            "PKG_CONFIG_PATH": ":".join(
                [str(native_pc), *(str(path) for path in pkg_dirs)]
            ),
            "PKG_CONFIG_PATH_FOR_BUILD": ":".join(
                [str(native_pc), *(str(path) for path in pkg_dirs[1:])]
            ),
            "CFLAGS": "-O2 -pipe -fno-plt -ffunction-sections -fdata-sections",
            "LDFLAGS": "-Wl,--as-needed -Wl,--gc-sections",
            "MAKEFLAGS": f"-j{jobs}",
            "NINJA_STATUS": "[%f/%t %es] ",
        }
    )
    if shutil.which("ccache"):
        env["CC"] = "ccache cc"
    return env


def meson_component(
    name: str,
    source: Path,
    build_root: Path,
    devroot: Path,
    env: dict[str, str],
    jobs: int,
    options: list[str],
) -> Path:
    build = build_root / name
    marker = build / ".mixtar-complete"
    if marker.is_file():
        log(f"Using cached {name}")
        return build
    safe_reset(build, build_root)
    run(
        [
            "meson",
            "setup",
            str(build),
            str(source),
            "--buildtype=release",
            "--prefix=/System",
            "--libdir=Libraries",
            "--includedir=Development/Include",
            "--auto-features=disabled",
            *options,
        ],
        env=env,
    )
    run(["meson", "compile", "-C", str(build), "-j", str(jobs)], env=env)
    install_env = env.copy()
    install_env["DESTDIR"] = str(devroot)
    run(["meson", "install", "-C", str(build), "--no-rebuild"], env=install_env)
    marker.write_text("complete\n", encoding="ascii")
    return build


def build_hwdata(source: Path, devroot: Path, native_pc: Path, version: str) -> None:
    hardware = devroot / "System" / "Resources" / "Hardware"
    hardware.mkdir(parents=True, exist_ok=True)
    for name in ("pnp.ids", "pci.ids", "usb.ids"):
        candidate = source / name
        if not candidate.is_file():
            raise RuntimeError(f"hwdata is missing {name}")
        shutil.copy2(candidate, hardware / name)
    native_pc.mkdir(parents=True, exist_ok=True)
    (native_pc / "hwdata.pc").write_text(
        "\n".join(
            [
                f"pkgdatadir={source.as_posix()}",
                "",
                "Name: hwdata",
                "Description: Hardware identification databases",
                f"Version: {version}",
                "",
            ]
        ),
        encoding="ascii",
    )


def build_native_wayland_scanner(native_pc: Path, graphics_build: Path) -> None:
    scanner = graphics_build / "wayland" / "src" / "wayland-scanner"
    if not scanner.is_file():
        raise RuntimeError(f"Cached wayland-scanner is missing: {scanner}")
    (native_pc / "wayland-scanner.pc").write_text(
        "\n".join(
            [
                f"wayland_scanner={scanner.as_posix()}",
                "",
                "Name: Wayland Scanner",
                "Description: Wayland protocol scanner",
                "Version: 1.25.0",
                "",
            ]
        ),
        encoding="ascii",
    )

def _expand_pc_variables(value: str, variables: dict[str, str]) -> str:
    for _ in range(len(variables) + 1):
        expanded = value
        for name, replacement in variables.items():
            expanded = expanded.replace("${" + name + "}", replacement)
        if expanded == value:
            break
        value = expanded
    return value


def _write_sanitized_pc(source: Path, destination: Path) -> None:
    variables: dict[str, str] = {}
    output: list[str] = []
    removed: list[str] = []
    for line in source.read_text(encoding="utf-8").splitlines():
        equals = line.find("=")
        colon = line.find(":")
        if equals > 0 and (colon < 0 or equals < colon):
            name, value = line.split("=", 1)
            if name.strip() == name and " " not in name:
                variables[name] = _expand_pc_variables(value, variables)
        if line.startswith("Cflags:"):
            kept: list[str] = []
            for flag in line.removeprefix("Cflags:").strip().split():
                expanded = _expand_pc_variables(flag, variables)
                if flag.startswith("-I") and not Path(expanded[2:]).is_dir():
                    removed.append(expanded[2:])
                    continue
                kept.append(flag)
            line = "Cflags: " + " ".join(kept)
        output.append(line)
    destination.write_text("\n".join(output) + "\n", encoding="ascii")
    if removed:
        log(f"Sanitized {source.name}: removed {len(removed)} stale include paths")


def build_cached_pc_adapters(
    native_pc: Path,
    graphics_build: Path,
    nested_mwm_build: Path,
) -> None:
    adapters = {
        "libdrm.pc": graphics_build / "libdrm" / "meson-uninstalled" / "libdrm-uninstalled.pc",
        "egl.pc": graphics_build / "mesa" / "meson-uninstalled" / "egl-uninstalled.pc",
        "gbm.pc": graphics_build / "mesa" / "meson-uninstalled" / "gbm-uninstalled.pc",
        "glesv2.pc": graphics_build / "mesa" / "meson-uninstalled" / "glesv2-uninstalled.pc",
        "xkbcommon.pc": nested_mwm_build / "xkbcommon" / "meson-uninstalled" / "xkbcommon-uninstalled.pc",
    }
    for name, source in adapters.items():
        if not source.is_file():
            raise RuntimeError(f"Cached pkg-config input is missing: {source}")
        _write_sanitized_pc(source, native_pc / name)


def stage_wayland_protocol_headers(devroot: Path, graphics_build: Path) -> None:
    source = graphics_build / "wayland-protocols" / "include" / "wayland-protocols"
    destination = devroot / "System" / "Development" / "Include" / "wayland-protocols"
    if not source.is_dir():
        raise RuntimeError(f"Cached Wayland protocol headers are missing: {source}")
    if destination.exists():
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination)
    log(f"Staged {sum(1 for path in destination.iterdir() if path.is_file())} Wayland enum headers")


def build_libudev_zero(
    source: Path,
    build_root: Path,
    devroot: Path,
    env: dict[str, str],
    jobs: int,
) -> None:
    build = build_root / "libudev-zero"
    marker = build / ".mixtar-complete"
    if marker.is_file():
        log("Using cached libudev-zero")
        return
    safe_reset(build, build_root)
    work = build / "source"
    shutil.copytree(source, work, symlinks=True)
    variables = [
        "PREFIX=/System",
        "LIBDIR=/System/Libraries",
        "SHAREDIR=/System/Resources",
        "INCLUDEDIR=/System/Development/Include",
        "PKGCONFIGDIR=/System/Libraries/pkgconfig",
        "USB_IDS_PATH=/System/Resources/Hardware/usb.ids",
    ]
    run(["make", "-C", str(work), f"-j{jobs}", *variables], env=env)
    run(
        ["make", "-C", str(work), *variables, f"DESTDIR={devroot}", "install"],
        env=env,
    )
    marker.write_text("complete\n", encoding="ascii")


def build_mtdev(
    source: Path,
    build_root: Path,
    devroot: Path,
    env: dict[str, str],
    jobs: int,
) -> None:
    build = build_root / "mtdev"
    marker = build / ".mixtar-complete"
    if marker.is_file():
        log("Using cached mtdev")
        return
    safe_reset(build, build_root)
    run(
        [
            str(source / "configure"),
            "--prefix=/System",
            "--libdir=/System/Libraries",
            "--includedir=/System/Development/Include",
            "--disable-static",
        ],
        cwd=build,
        env=env,
    )
    run(["make", f"-j{jobs}"], cwd=build, env=env)
    install_env = env.copy()
    install_env["DESTDIR"] = str(devroot)
    run(["make", "install"], cwd=build, env=install_env)
    marker.write_text("complete\n", encoding="ascii")


def copy_physical(source: Path, destination: Path) -> None:
    resolved = source.resolve(strict=True)
    if not resolved.is_file():
        raise RuntimeError(f"Expected file is missing: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(resolved, destination)


def copy_physical_tree(source: Path, destination: Path) -> None:
    if not source.is_dir():
        return
    for item in sorted(source.rglob("*")):
        relative = item.relative_to(source)
        target = destination / relative
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif item.is_file() or item.is_symlink():
            copy_physical(item, target)


def find_license(source: Path, candidates: tuple[str, ...]) -> Path:
    for name in candidates:
        candidate = source / name
        if candidate.is_file():
            return candidate
    raise RuntimeError(f"No license file found in {source}")


def is_elf(path: Path) -> bool:
    if not path.is_file() or path.is_symlink():
        return False
    with path.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def elf_interpreter(path: Path) -> str | None:
    output = run(["readelf", "-l", str(path)], capture=True)
    marker = "Requesting program interpreter: "
    for line in output.splitlines():
        if marker in line:
            return line.split(marker, 1)[1].rstrip("]")
    return None


def elf_needed(path: Path) -> list[str]:
    output = run(["readelf", "-d", str(path)], capture=True)
    needed: list[str] = []
    for line in output.splitlines():
        if "(NEEDED)" in line and "[" in line:
            needed.append(line.split("[", 1)[1].split("]", 1)[0])
    return sorted(needed)


def patch_runtime_elf(path: Path) -> None:
    run(["patchelf", "--set-rpath", TARGET_RPATH, str(path)])
    if elf_interpreter(path) is not None:
        run(["patchelf", "--set-interpreter", TARGET_INTERPRETER, str(path)])


def stage_runtime(
    stage_root: Path,
    devroot: Path,
    sources: dict[str, Path],
    stack_root: Path,
) -> list[Path]:
    safe_reset(stage_root, stage_root.parent)
    shutil.copytree(BASE_MWM_ROOT, stage_root, dirs_exist_ok=True, symlinks=False)
    shutil.copytree(
        MWM_SOURCE / "Overlay",
        stage_root,
        dirs_exist_ok=True,
        symlinks=False,
    )
    for executable in (
        stage_root / "System" / "Core" / "Graphics" / "start-graphics",
        stage_root
        / "System"
        / "Configuration"
        / "OpenRC"
        / "init.d"
        / "mixtar-graphics",
    ):
        if not executable.is_file():
            raise RuntimeError(f"MWM runtime overlay is missing: {executable}")
        executable.chmod(0o755)
        # Shell scripts are baked into a signed image; a parse error is only
        # discovered after a full rebuild and boot unless it is caught here.
        with executable.open("rb") as stream:
            if stream.read(2) == b"#!":
                run(["sh", "-n", str(executable)])

    graphics_lib = stage_root / "System" / "Libraries" / "Graphics"
    graphics_lib.mkdir(parents=True, exist_ok=True)
    expected_libraries = (
        "libudev.so.1",
        "libevdev.so.2",
        "libmtdev.so.1",
        "libinput.so.10",
        "libseat.so.1",
        "libdisplay-info.so.3",
        "libwlroots-0.20.so",
    )
    staged_elfs: list[Path] = []
    for name in expected_libraries:
        source = devroot / "System" / "Libraries" / name
        destination = graphics_lib / name
        copy_physical(source, destination)
        staged_elfs.append(destination)

    mwm = devroot / "System" / "Core" / "Graphics" / "MWM"
    if not mwm.is_file():
        matches = list(stack_root.rglob("MWM"))
        if len(matches) != 1:
            raise RuntimeError("Could not locate the production MWM executable")
        mwm = matches[0]
    mwm_target = stage_root / "System" / "Core" / "Graphics" / "MWM"
    copy_physical(mwm, mwm_target)
    staged_elfs.append(mwm_target)

    seatd_matches = list((devroot / "System").rglob("seatd"))
    seatd_matches = [path for path in seatd_matches if path.is_file() and is_elf(path)]
    if seatd_matches:
        seatd_target = stage_root / "System" / "Core" / "Seat" / "SeatD"
        copy_physical(seatd_matches[0], seatd_target)
        staged_elfs.append(seatd_target)

    input_root = stage_root / "System" / "Resources" / "Input"
    copy_physical_tree(
        devroot / "System" / "Resources" / "Input",
        input_root,
    )
    for path in sorted(input_root.rglob("*")):
        if is_elf(path):
            staged_elfs.append(path)
    copy_physical_tree(
        devroot / "System" / "Resources" / "Hardware",
        stage_root / "System" / "Resources" / "Hardware",
    )

    config_dir = stage_root / "System" / "Configuration" / "Graphics"
    config_dir.mkdir(parents=True, exist_ok=True)
    current_config = config_dir / "MDDM.config"
    if current_config.is_file():
        shutil.copy2(current_config, config_dir / "MDDM.nested.config")
    shutil.copy2(PRODUCTION_CONFIG, current_config)

    licenses = stage_root / "System" / "Licenses" / "MDDM"
    licenses.mkdir(parents=True, exist_ok=True)
    license_map = {
        "LibudevZero.txt": ("libudev-zero", ("LICENSE",)),
        "Seatd.txt": ("seatd", ("LICENSE",)),
        "LibdisplayInfo.txt": ("libdisplay-info", ("LICENSE", "COPYING")),
        "Libinput.txt": ("libinput", ("COPYING", "LICENSE")),
        "Libevdev.txt": ("libevdev", ("COPYING", "LICENSE")),
        "Mtdev.txt": ("mtdev", ("COPYING", "LICENSE")),
        "Hwdata.txt": ("hwdata", ("LICENSE", "COPYING")),
    }
    for output_name, (source_id, candidates) in license_map.items():
        shutil.copy2(find_license(sources[source_id], candidates), licenses / output_name)

    for path in staged_elfs:
        patch_runtime_elf(path)
    for name in expected_libraries:
        run(["patchelf", "--set-soname", name, str(graphics_lib / name)])
    return staged_elfs


def audit_runtime(stage_root: Path) -> list[dict[str, object]]:
    inode_owner: dict[tuple[int, int], Path] = {}
    for path in sorted(stage_root.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"Runtime contains a symbolic link: {path}")
        if path.is_file():
            info = path.stat()
            key = (info.st_dev, info.st_ino)
            if key in inode_owner:
                raise RuntimeError(f"Runtime contains a hard link: {path} == {inode_owner[key]}")
            inode_owner[key] = path

    available: set[str] = set()
    for root in (stage_root, GRAPHICS_ROOT):
        for path in root.rglob("*"):
            if path.is_file() and is_elf(path):
                available.add(path.name)

    report: list[dict[str, object]] = []
    for path in sorted(stage_root.rglob("*")):
        if not is_elf(path):
            continue
        interpreter = elf_interpreter(path)
        if interpreter is not None and interpreter != TARGET_INTERPRETER:
            raise RuntimeError(f"Invalid ELF interpreter in {path}: {interpreter}")
        needed = elf_needed(path)
        missing = [name for name in needed if name not in available]
        if missing:
            raise RuntimeError(f"Unresolved ELF dependencies for {path}: {', '.join(missing)}")
        report.append(
            {
                "path": "/" + path.relative_to(stage_root).as_posix(),
                "interpreter": interpreter,
                "needed": needed,
                "sha256": digest(path),
            }
        )
    return report


def deterministic_tar(root: Path, destination: Path, epoch: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.unlink(missing_ok=True)
    with tarfile.open(temporary, "w", format=tarfile.GNU_FORMAT) as archive:
        for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
            relative = path.relative_to(root).as_posix()
            info = archive.gettarinfo(str(path), arcname=relative)
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = epoch
            if path.is_dir():
                info.mode = 0o755
                archive.addfile(info)
            else:
                executable = bool(path.stat().st_mode & stat.S_IXUSR)
                info.mode = 0o755 if executable else 0o644
                with path.open("rb") as stream:
                    archive.addfile(info, stream)
    temporary.replace(destination)


def publish(
    stage_root: Path,
    stack_key: str,
    base_mwm_key: str,
    jobs: int,
    elapsed: float,
    epoch: int,
    elf_report: list[dict[str, object]],
) -> None:
    product = REPO / "out" / "Product" / "MWMStack"
    final_root = product / "Root"
    replacement = product / "Root.production"
    safe_reset(replacement, product)
    shutil.copytree(stage_root, replacement, dirs_exist_ok=True, symlinks=False)
    safe_remove_tree(final_root, product)
    replacement.replace(final_root)

    metadata = {
        "schema": "mixtar.mwm-build.v2",
        "stack_key": stack_key,
        "base_mwm_key": base_mwm_key,
        "source_date_epoch": epoch,
        "jobs": jobs,
        "build_seconds": round(elapsed, 3),
        "prefix": "/System",
        "backends": ["drm", "libinput", "wayland", "headless"],
        "renderers": ["gles2", "pixman"],
        "allocators": ["gbm", "shm"],
        "session": "libseat",
        "udev_compatibility": "libudev-zero",
    }
    (product / "Build.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    encoded_report = json.dumps(elf_report, indent=2, sort_keys=True) + "\n"
    (OUTPUT_DIR / "MWM.elf.json").write_text(encoded_report, encoding="utf-8")
    (OUTPUT_DIR / "MDDM.elf.json").write_text(encoded_report, encoding="utf-8")

    artifact = OUTPUT_DIR / "MixtarRVS-1.1-MWM-x86_64.overlay.tar"
    deterministic_tar(final_root, artifact, epoch)
    files = [path for path in final_root.rglob("*") if path.is_file()]
    manifest = OUTPUT_DIR / "MixtarRVS-1.1-MWM-x86_64.manifest.config"
    manifest.write_text(
        "\n".join(
            [
                'schema = "mixtar.release-manifest.v1"',
                'product = "MixtarRVS"',
                'version = "1.1"',
                'architecture = "x86_64"',
                'profile = "MWM-DRM"',
                f'build_key = "{stack_key}"',
                f'archive = "{artifact.name}"',
                f'archive_sha256 = "{digest(artifact)}"',
                f"files = {len(files)}",
                f"bytes = {sum(path.stat().st_size for path in files)}",
                f"elf_files = {len(elf_report)}",
                "links = 0",
                'backend = "drm"',
                'renderer = "gles2"',
                'allocator = "gbm"',
                'session = "libseat"',
                'input = "libinput"',
                "x11 = false",
                "xwayland = false",
                "",
            ]
        ),
        encoding="ascii",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=0)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    require_tools()

    lock, source_entries = load_lock()
    graphics_metadata = load_json(GRAPHICS_BUILD_JSON)
    mwm_metadata = load_json(MWM_BUILD_JSON)
    if not BASE_MWM_ROOT.is_dir() or not GRAPHICS_ROOT.is_dir():
        raise RuntimeError("Graphics and nested MWM roots must be built first")

    jobs = args.jobs if args.jobs > 0 else max(1, os.cpu_count() or 1)
    epoch = int(lock.get("source_date_epoch", SOURCE_DATE_EPOCH_DEFAULT))
    base_mwm_key = str(mwm_metadata.get("base_mwm_key", mwm_metadata.get("stack_key", "")))
    if not base_mwm_key:
        raise RuntimeError("The base MWM build key is missing")
    key_material = hashlib.sha256()
    for path in (
        LOCK_PATH,
        MWM_LOCK_PATH,
        MWM_SOURCE / "mwm.c",
        MWM_SOURCE / "meson.build",
    ):
        key_material.update(path.read_bytes())
    key_material.update(RECIPE_ID)
    key_material.update(str(graphics_metadata.get("stack_key", "")).encode())
    key_material.update(base_mwm_key.encode())
    stack_key = key_material.hexdigest()[:16]

    cache = Path.home() / ".cache" / "mixtar" / "mddm"
    archive_dir = cache / "archives"
    source_dir = cache / "sources"
    build_root = cache / "build" / stack_key
    devroot = cache / "development" / stack_key
    stage_root = cache / "stage" / stack_key
    host_pc = build_root / "host-pkgconfig"
    native_pc = build_root / "native-pkgconfig"
    for directory in (archive_dir, source_dir, build_root, devroot, stage_root):
        directory.mkdir(parents=True, exist_ok=True)
    if args.refresh:
        safe_reset(build_root, cache / "build")
        safe_reset(devroot, cache / "development")
        safe_reset(stage_root, cache / "stage")
    devroot.mkdir(parents=True, exist_ok=True)

    sources: dict[str, Path] = {}
    versions: dict[str, str] = {}
    for entry in source_entries:
        archive = ensure_archive(entry, archive_dir, args.refresh)
        sources[entry["id"]] = extract_source(entry, archive, source_dir)
        versions[entry["id"]] = entry["version"]

    graphics_key = str(graphics_metadata["stack_key"])
    graphics_build = Path.home() / ".cache" / "mixtar" / "graphics" / "build" / graphics_key
    nested_mwm_build = Path.home() / ".cache" / "mixtar" / "mwm" / "build" / base_mwm_key
    wlroots_source = Path.home() / ".cache" / "mixtar" / "mwm" / "sources" / "wlroots-0.20.2"
    for required in (graphics_build, nested_mwm_build, wlroots_source):
        if not required.exists():
            raise RuntimeError(f"Required cached build input is missing: {required}")

    build_hwdata(sources["hwdata"], devroot, native_pc, versions["hwdata"])
    build_native_wayland_scanner(native_pc, graphics_build)
    build_cached_pc_adapters(native_pc, graphics_build, nested_mwm_build)
    stage_wayland_protocol_headers(devroot, graphics_build)
    refresh_host_pc(devroot, host_pc)
    pkg_dirs = pc_directories(graphics_build, nested_mwm_build, host_pc)
    env = build_environment(jobs, epoch, pkg_dirs, native_pc)
    started = time.monotonic()

    build_libudev_zero(sources["libudev-zero"], build_root, devroot, env, jobs)
    refresh_host_pc(devroot, host_pc)
    build_mtdev(sources["mtdev"], build_root, devroot, env, jobs)
    refresh_host_pc(devroot, host_pc)
    meson_component(
        "libevdev",
        sources["libevdev"],
        build_root,
        devroot,
        env,
        jobs,
        ["-Dtests=disabled", "-Dtools=disabled", "-Ddocumentation=disabled"],
    )
    refresh_host_pc(devroot, host_pc)
    meson_component(
        "libinput",
        sources["libinput"],
        build_root,
        devroot,
        env,
        jobs,
        [
            "--datadir=Resources/Input",
            "--sysconfdir=Configuration",
            "--libexecdir=Core/Input",
            "--bindir=Commands",
            "--mandir=Documentation/Manual",
            "-Dudev-dir=/System/Resources/Input/Udev",
            "-Dlibwacom=false",
            "-Ddebug-gui=false",
            "-Dtests=false",
            "-Dinstall-tests=false",
            "-Ddocumentation=false",
            "-Dzshcompletiondir=no",
        ],
    )
    refresh_host_pc(devroot, host_pc)
    meson_component(
        "seatd",
        sources["seatd"],
        build_root,
        devroot,
        env,
        jobs,
        [
            "--bindir=Core/Seat",
            "--mandir=Documentation/Manual",
            "-Dlibseat-logind=disabled",
            "-Dlibseat-seatd=enabled",
            "-Dlibseat-builtin=enabled",
            "-Dserver=enabled",
            "-Dexamples=disabled",
            "-Dman-pages=disabled",
            "-Ddefaultpath=/Runtime/Seats/seatd.sock",
        ],
    )
    refresh_host_pc(devroot, host_pc)
    meson_component(
        "libdisplay-info",
        sources["libdisplay-info"],
        build_root,
        devroot,
        env,
        jobs,
        [],
    )
    refresh_host_pc(devroot, host_pc)

    wlroots_build = meson_component(
        "wlroots-production",
        wlroots_source,
        build_root,
        devroot,
        env,
        jobs,
        [
            "-Dbackends=drm,libinput",
            "-Drenderers=gles2",
            "-Dallocators=gbm",
            "-Dsession=enabled",
            "-Dxwayland=disabled",
            "-Dexamples=false",
            "-Dxcb-errors=disabled",
            "-Dlibliftoff=disabled",
            "-Dcolor-management=disabled",
            "-Db_ndebug=false",
        ],
    )
    refresh_host_pc(devroot, host_pc)

    production_pc = wlroots_build / "meson-uninstalled"
    env["PKG_CONFIG_PATH"] = ":".join([str(production_pc), env["PKG_CONFIG_PATH"]])
    mwm_build = meson_component(
        "mwm-production",
        MWM_SOURCE,
        build_root,
        devroot,
        env,
        jobs,
        ["--bindir=Core/Graphics", "-Db_ndebug=false"],
    )

    staged_elfs = stage_runtime(stage_root, devroot, sources, mwm_build)
    if not staged_elfs:
        raise RuntimeError("No production MDDM ELF files were staged")
    elf_report = audit_runtime(stage_root)
    elapsed = time.monotonic() - started
    publish(stage_root, stack_key, base_mwm_key, jobs, elapsed, epoch, elf_report)
    log(
        f"Production MWM complete: key={stack_key} jobs={jobs} "
        f"seconds={elapsed:.1f} elf={len(elf_report)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
