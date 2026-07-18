#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import time
import tomllib
import urllib.request


REPO = Path(__file__).resolve().parents[1]
CACHE = Path.home() / ".cache" / "mixtar" / "mwm"
GRAPHICS_CACHE = Path.home() / ".cache" / "mixtar" / "graphics"
LOCK_PATH = REPO / "Release" / "P4.mwm.lock.config"
GRAPHICS_LOCK_PATH = REPO / "Release" / "P4.graphics.lock.config"
EXPECTED_LOADER = "/System/Libraries/Loader/ld-linux-x86-64.so.2"


def run(command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_remove(path: Path, parent: Path) -> None:
    resolved = path.resolve()
    allowed = parent.resolve()
    if resolved == allowed or allowed not in resolved.parents:
        raise RuntimeError(f"Refusing to remove unsafe path: {resolved}")
    if path.exists():
        shutil.rmtree(path)


def download(component: dict[str, object]) -> Path:
    archives = CACHE / "archives"
    archives.mkdir(parents=True, exist_ok=True)
    destination = archives / str(component["archive"])
    expected = str(component["sha256"])
    if destination.exists() and sha256(destination) == expected:
        return destination
    if destination.exists():
        destination.unlink()
    temporary = destination.with_suffix(destination.suffix + ".part")
    print(f"Downloading {component['url']}", flush=True)
    with urllib.request.urlopen(str(component["url"]), timeout=120) as source:
        with temporary.open("wb") as target:
            shutil.copyfileobj(source, target)
    actual = sha256(temporary)
    if actual != expected:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"SHA-256 mismatch for {destination.name}: {actual}")
    temporary.replace(destination)
    return destination


def source_patch(component: dict[str, object]) -> tuple[Path, str] | None:
    relative = component.get("patch")
    expected = component.get("patch_sha256")
    if relative is None and expected is None:
        return None
    if not isinstance(relative, str) or not isinstance(expected, str):
        raise RuntimeError("Component patch and patch_sha256 must be specified together")
    path = (REPO / relative).resolve()
    repo = REPO.resolve()
    if repo not in path.parents or not path.is_file():
        raise RuntimeError(f"Component patch is missing or outside the repository: {relative}")
    actual = sha256(path)
    if actual != expected:
        raise RuntimeError(f"SHA-256 mismatch for {relative}: {actual}")
    return path, actual


def apply_source_patch(component: dict[str, object], destination: Path) -> None:
    details = source_patch(component)
    if details is None:
        return
    patch, digest = details
    marker = destination / f".mixtar-patch-{digest}"
    if marker.is_file():
        return
    run(["patch", "-p1", "--forward", "--batch", "-i", str(patch)], cwd=destination)
    marker.write_text(digest + "\n", encoding="ascii")


def extract(component: dict[str, object], archive: Path) -> Path:
    sources = CACHE / "sources"
    sources.mkdir(parents=True, exist_ok=True)
    destination = sources / str(component["source_dir"])
    if destination.is_dir():
        details = source_patch(component)
        if details is None:
            return destination
        _, digest = details
        marker = destination / f".mixtar-patch-{digest}"
        if marker.is_file():
            return destination
        stale_markers = list(destination.glob(".mixtar-patch-*"))
        if stale_markers:
            safe_remove(destination, sources)
        else:
            apply_source_patch(component, destination)
            return destination

    temporary = Path(tempfile.mkdtemp(prefix="extract-", dir=sources))
    try:
        with tarfile.open(archive, "r:*") as bundle:
            root = temporary.resolve()
            members = bundle.getmembers()
            for member in members:
                target = (temporary / member.name).resolve()
                if target != root and root not in target.parents:
                    raise RuntimeError(f"Unsafe archive member: {member.name}")
            bundle.extractall(temporary, members=members, filter="data")
        candidate = temporary / str(component["source_dir"])
        if not candidate.is_dir():
            directories = [item for item in temporary.iterdir() if item.is_dir()]
            if len(directories) != 1:
                raise RuntimeError(f"Cannot identify source root in {archive}")
            candidate = directories[0]
        candidate.replace(destination)
        apply_source_patch(component, destination)
    finally:
        if temporary.exists():
            safe_remove(temporary, sources)
    return destination


def copy_files(source: Path, destination: Path, pattern: str = "*.h") -> None:
    destination.mkdir(parents=True, exist_ok=True)
    if not source.is_dir():
        return
    for item in source.glob(pattern):
        if item.is_file():
            shutil.copy2(item, destination / item.name)


def graphics_source(lock: dict[str, object], name: str) -> Path:
    component = next(
        (source for source in lock["sources"] if source["id"] == name),
        None,
    )
    if component is None:
        raise RuntimeError(f"Graphics lock does not contain source: {name}")
    prefix = f"{name.replace('_', '-')}-{component['version']}-{str(component['sha256'])[:8]}"
    candidate = GRAPHICS_CACHE / "sources" / prefix
    if candidate.is_dir():
        return candidate
    matches = sorted((GRAPHICS_CACHE / "sources").glob(prefix + "*"))
    if len(matches) != 1:
        raise RuntimeError(f"Cannot locate graphics source cache for {name}")
    return matches[0]


def seed_development_sysroot(stage: Path, graphics_stage: Path, graphics_key: str,
                             graphics_lock: dict[str, object]) -> None:
    shutil.copytree(graphics_stage / "System", stage / "System", dirs_exist_ok=True)
    headers = stage / "System" / "Development" / "Headers"

    wayland = graphics_source(graphics_lock, "wayland")
    wayland_build = GRAPHICS_CACHE / "build" / graphics_key / "wayland" / "src"
    for directory in (wayland / "src", wayland / "cursor", wayland / "egl", wayland_build):
        copy_files(directory, headers)

    libdrm = graphics_source(graphics_lock, "libdrm")
    copy_files(libdrm, headers)
    copy_files(libdrm, headers / "libdrm")
    if (libdrm / "include" / "drm").is_dir():
        shutil.copytree(libdrm / "include" / "drm", headers / "drm", dirs_exist_ok=True)
        shutil.copytree(libdrm / "include" / "drm", headers / "libdrm", dirs_exist_ok=True)

    mesa = graphics_source(graphics_lock, "mesa")
    shutil.copytree(mesa / "include", headers, dirs_exist_ok=True)
    shutil.copy2(mesa / "src" / "gbm" / "main" / "gbm.h", headers / "gbm.h")

    scanner = wayland_build / "wayland-scanner"
    commands = stage / "System" / "Commands"
    commands.mkdir(parents=True, exist_ok=True)
    shutil.copy2(scanner, commands / "wayland-scanner")
    (commands / "wayland-scanner").chmod(0o755)

    protocols = graphics_source(graphics_lock, "wayland-protocols")
    protocols_headers = GRAPHICS_CACHE / "build" / graphics_key / "wayland-protocols" / "include"
    if not protocols_headers.is_dir():
        raise RuntimeError("Generated wayland-protocols headers are missing from the graphics cache")
    protocols_component = next(
        source for source in graphics_lock["sources"]
        if source["id"] == "wayland-protocols"
    )
    pkgconfig = stage / "System" / "Libraries" / "Graphics" / "pkgconfig"
    pkgconfig.mkdir(parents=True, exist_ok=True)
    (pkgconfig / "wayland-protocols.pc").write_text("\n".join([
        f"prefix={protocols}",
        f"includedir={protocols_headers}",
        "pkgdatadir=${prefix}",
        "",
        "Name: Wayland Protocols",
        "Description: Wayland protocol specifications",
        f"Version: {protocols_component['version']}",
        "Cflags: -I${includedir}",
        "",
    ]), encoding="utf-8")


def refresh_pkgconfig(stage: Path) -> Path:
    host = stage / "HostPkgConfig"
    safe_remove(host, stage)
    host.mkdir(parents=True)
    system = stage / "System"
    for source in sorted(system.rglob("*.pc")):
        content = source.read_text(encoding="utf-8")
        content = content.replace("/System", str(system))
        target = host / source.name
        if target.exists() and target.read_text(encoding="utf-8") != content:
            raise RuntimeError(f"Conflicting pkg-config file: {source.name}")
        target.write_text(content, encoding="utf-8")
    return host


def configure_build(name: str, source: Path, build_root: Path, stage: Path,
                    environment: dict[str, str], jobs: int, options: list[str],
                    target: str | None = None) -> None:
    marker = stage / f".built-{name}"
    if marker.is_file():
        print(f"+ reuse {name}", flush=True)
        return
    build = build_root / name
    if build.exists():
        safe_remove(build, build_root)
    command = [
        "meson", "setup", str(build), str(source),
        "--prefix=/System",
        "--libdir=Libraries/Graphics",
        "--includedir=Development/Headers",
        "--buildtype=release",
        "--wrap-mode=nodownload",
        "-Db_lto=true",
        "-Db_ndebug=true",
    ] + options
    run(command, env=environment)
    compile_command = ["meson", "compile", "-C", str(build), "-j", str(jobs)]
    if target:
        compile_command.append(target)
    run(compile_command, env=environment)
    install_environment = environment.copy()
    install_environment["DESTDIR"] = str(stage)
    run(["meson", "install", "-C", str(build), "--no-rebuild"], env=install_environment)
    marker.write_text("complete\n", encoding="ascii")


def readelf(path: Path) -> dict[str, object]:
    program = subprocess.run(["readelf", "-W", "-l", str(path)], check=True,
                             text=True, capture_output=True).stdout
    dynamic = subprocess.run(["readelf", "-W", "-d", str(path)], check=True,
                             text=True, capture_output=True).stdout
    interpreter_match = re.search(r"\[Requesting program interpreter: ([^\]]+)\]", program)
    rpath_match = re.search(r"\((?:RPATH|RUNPATH)\).*\[([^\]]*)\]", dynamic)
    return {
        "interpreter": interpreter_match.group(1) if interpreter_match else "",
        "needed": re.findall(r"Shared library: \[([^\]]+)\]", dynamic),
        "rpath": rpath_match.group(1) if rpath_match else "",
    }


def is_elf(path: Path) -> bool:
    if not path.is_file():
        return False
    with path.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def copy_runtime_closure(mwm_binary: Path, dev_stage: Path, graphics_root: Path,
                         platform_runtime: Path, runtime_root: Path) -> list[str]:
    graphics_destination = runtime_root / "System" / "Libraries" / "Graphics"
    system_destination = runtime_root / "System" / "Libraries"
    graphics_destination.mkdir(parents=True, exist_ok=True)
    system_destination.mkdir(parents=True, exist_ok=True)
    graphics_names = {item.name for item in graphics_root.rglob("*") if item.is_file()}
    available: dict[str, Path] = {}
    for item in (dev_stage / "System").rglob("*"):
        if item.is_file():
            available.setdefault(item.name, item)
    for item in platform_runtime.iterdir():
        if item.is_file():
            available.setdefault(item.name, item)

    copied: list[str] = []
    queue = [mwm_binary]
    inspected: set[Path] = set()
    while queue:
        current = queue.pop(0)
        resolved = current.resolve()
        if resolved in inspected:
            continue
        inspected.add(resolved)
        for needed in readelf(current)["needed"]:
            existing = any((directory / needed).is_file() for directory in (
                graphics_destination,
                system_destination,
                runtime_root / "System" / "Libraries" / "Loader",
            ))
            if needed in graphics_names or existing:
                continue
            source = available.get(needed)
            if source is None:
                raise RuntimeError(f"MWM runtime dependency is missing: {needed}")
            destination = system_destination if source.parent == platform_runtime else graphics_destination
            target = destination / needed
            shutil.copy2(source.resolve(), target)
            target.chmod(source.resolve().stat().st_mode & 0o777)
            copied.append(needed)
            if is_elf(target):
                queue.append(target)
    return sorted(copied)


def copy_license(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise RuntimeError(f"License file is missing: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def deterministic_tar(root: Path, destination: Path, epoch: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(destination, "w", format=tarfile.PAX_FORMAT, dereference=True) as bundle:
        for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
            relative = path.relative_to(root).as_posix()
            info = bundle.gettarinfo(str(path), arcname=relative)
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = epoch
            if path.is_file():
                with path.open("rb") as stream:
                    bundle.addfile(info, stream)
            else:
                bundle.addfile(info)


def stage_runtime(lock: dict[str, object], sources: dict[str, Path], dev_stage: Path,
                  graphics_root: Path, build_key: str, jobs: int, seconds: int) -> None:
    output_base = REPO / "out" / "Product" / "MWMStack"
    root = output_base / "Root"
    output_base.mkdir(parents=True, exist_ok=True)
    safe_remove(root, output_base)
    root.mkdir(parents=True)

    overlay = REPO / "Product" / "MWM" / "Overlay"
    shutil.copytree(overlay, root, dirs_exist_ok=True)
    for executable in (
        root / "System" / "Core" / "Graphics" / "start-graphics",
        root / "System" / "Configuration" / "OpenRC" / "init.d" / "mixtar-graphics",
    ):
        executable.chmod(0o755)

    installed_mwm = dev_stage / "System" / "Core" / "Graphics" / "MWM"
    runtime_mwm = root / "System" / "Core" / "Graphics" / "MWM"
    runtime_mwm.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(installed_mwm, runtime_mwm)
    runtime_mwm.chmod(0o755)

    keyboard_source = dev_stage / "System" / "Configuration" / "Keyboard" / "xkeyboard-config-2"
    keyboard_target = root / "System" / "Configuration" / "Keyboard" / "xkeyboard-config-2"
    shutil.copytree(keyboard_source, keyboard_target, dirs_exist_ok=True)

    platform_runtime = REPO / "Root" / "System" / "Terminal" / "ZSH" / "Runtime"
    loader_source = platform_runtime / "ld-linux-x86-64.so.2"
    loader_target = root / EXPECTED_LOADER.lstrip("/")
    loader_target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(loader_source, loader_target)
    loader_target.chmod(0o755)
    copied_libraries = copy_runtime_closure(
        runtime_mwm, dev_stage, graphics_root, platform_runtime, root,
    )
    canonical_libc = root / "System" / "Libraries" / "libc.so.6"
    if readelf(canonical_libc)["interpreter"] != EXPECTED_LOADER:
        run(["patchelf", "--set-interpreter", EXPECTED_LOADER, str(canonical_libc)])

    licenses = root / "System" / "Licenses" / "MWM"
    copy_license(sources["pixman"] / "COPYING", licenses / "Pixman.txt")
    copy_license(sources["xkbcommon"] / "LICENSE", licenses / "Libxkbcommon.txt")
    copy_license(sources["xkeyboard_config"] / "COPYING", licenses / "XkeyboardConfig.txt")
    copy_license(sources["wlroots"] / "LICENSE", licenses / "Wlroots.txt")
    copy_license(sources["wlroots"] / "tinywl" / "LICENSE", licenses / "MWM-CC0.txt")
    copy_license(Path("/usr/share/doc/libc6/copyright"), licenses / "Glibc.txt")

    links = [path for path in root.rglob("*") if path.is_symlink()]
    hardlinks = [path for path in root.rglob("*") if path.is_file() and path.stat().st_nlink > 1]
    if links or hardlinks:
        raise RuntimeError(f"Runtime layout contains links: symlinks={len(links)} hardlinks={len(hardlinks)}")

    graphics_files = {item.name for item in graphics_root.rglob("*") if item.is_file()}
    runtime_files = {item.name for item in root.rglob("*") if item.is_file()}
    combined_names = graphics_files | runtime_files
    elf_records: list[dict[str, object]] = []
    invalid_interpreters: list[str] = []
    missing: dict[str, list[str]] = {}
    for path in sorted((item for item in root.rglob("*") if is_elf(item)), key=lambda item: item.as_posix()):
        metadata = readelf(path)
        relative = "/" + path.relative_to(root).as_posix()
        if metadata["interpreter"] and metadata["interpreter"] != EXPECTED_LOADER:
            invalid_interpreters.append(relative)
        absent = [name for name in metadata["needed"] if name not in combined_names]
        if absent:
            missing[relative] = absent
        elf_records.append({
            "path": relative,
            "sha256": sha256(path),
            **metadata,
        })
    if invalid_interpreters or missing:
        raise RuntimeError(f"Invalid MWM ELF graph: interpreters={invalid_interpreters} missing={missing}")

    report = {
        "schema": "mixtar.mwm-elf.v1",
        "loader": EXPECTED_LOADER,
        "library_path": "/System/Libraries/Graphics:/System/Libraries",
        "files": elf_records,
    }
    report_path = REPO / "Output" / "P4" / "MWM.elf.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    epoch = int(lock["source_date_epoch"])
    archive = REPO / "Output" / "P4" / "MixtarRVS-1.1-MWM-x86_64.overlay.tar"
    deterministic_tar(root, archive, epoch)
    files = sorted(item for item in root.rglob("*") if item.is_file())
    total_bytes = sum(item.stat().st_size for item in files)
    manifest = REPO / "Output" / "P4" / "MixtarRVS-1.1-MWM-x86_64.manifest.config"
    mddm = tomllib.loads(
        (overlay / "System" / "Configuration" / "Graphics" / "MDDM.config").read_text(encoding="utf-8")
    )
    component_lines = []
    for name, component in lock["components"].items():
        component_lines.extend([
            f"[components.{name}]",
            f'version = "{component["version"]}"',
            f'sha256 = "{component["sha256"]}"',
            "",
        ])
    manifest.write_text("\n".join([
        "[product]",
        'name = "MixtarRVS"',
        'version = "1.1-MWM"',
        'architecture = "x86_64"',
        f'build_key = "{build_key}"',
        "",
        "[artifacts.root]",
        f"files = {len(files)}",
        f"bytes = {total_bytes}",
        "symlinks = 0",
        "hardlinks = 0",
        "",
        "[artifacts.overlay]",
        f'path = "{archive.relative_to(REPO).as_posix()}"',
        f'sha256 = "{sha256(archive)}"',
        "",
        *component_lines,
        "[runtime]",
        f"elf_files = {len(elf_records)}",
        f"private_libraries = {len(copied_libraries)}",
        f'backend = "{mddm["backend"]}"',
        f'renderer = "{mddm["renderer"]}"',
        f'allocator = "{mddm["allocator"]}"',
        f'x11 = {str(bool(mddm["allow_x11"])).lower()}',
        f'xwayland = {str(bool(mddm["allow_xwayland"])).lower()}',
        "",
    ]), encoding="utf-8")

    build_json = {
        "schema": "mixtar.mwm-build.v1",
        "stack_key": build_key,
        "source_date_epoch": epoch,
        "jobs": jobs,
        "build_seconds": seconds,
        "prefix": "/System",
        "runtime_libraries": copied_libraries,
    }
    (output_base / "Build.json").write_text(
        json.dumps(build_json, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"MWM runtime staged: files={len(files)} bytes={total_bytes} elf={len(elf_records)}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build and stage the Mixtar MWM stack")
    parser.add_argument("--jobs", type=int, default=0)
    parser.add_argument("--force", action="store_true")
    arguments = parser.parse_args()

    lock_bytes = LOCK_PATH.read_bytes()
    lock = tomllib.loads(lock_bytes.decode("utf-8"))
    graphics_lock = tomllib.loads(GRAPHICS_LOCK_PATH.read_text(encoding="utf-8"))
    graphics_build = json.loads((REPO / "out" / "Product" / "GraphicsStack" / "Build.json").read_text())
    graphics_key = str(graphics_build["stack_key"])
    graphics_stage = GRAPHICS_CACHE / "stage" / graphics_key
    graphics_root = REPO / "Output" / "P4" / "GraphicsRoot"
    if not graphics_stage.is_dir() or not graphics_root.is_dir():
        raise RuntimeError("Build the P4 graphics stack before MWM.")

    components = lock["components"]
    sources: dict[str, Path] = {}
    for name, component in components.items():
        archive = download(component)
        sources[name] = extract(component, archive)

    digest = hashlib.sha256(lock_bytes)
    digest.update(b"mwm-build-recipe-v2")
    digest.update(graphics_key.encode("ascii"))
    build_inputs = [
        REPO / "Product" / "MWM" / "mwm.c",
        REPO / "Product" / "MWM" / "meson.build",
    ]
    for source_file in build_inputs:
        digest.update(source_file.read_bytes())
    build_key = digest.hexdigest()[:16]
    build_root = CACHE / "build" / build_key
    dev_stage = CACHE / "stage" / build_key
    marker = dev_stage / ".complete"
    jobs = arguments.jobs if arguments.jobs > 0 else max(1, os.cpu_count() or 1)
    started = time.monotonic()

    if arguments.force:
        safe_remove(build_root, CACHE / "build")
        safe_remove(dev_stage, CACHE / "stage")

    if not marker.is_file():
        build_root.mkdir(parents=True, exist_ok=True)
        dev_stage.mkdir(parents=True, exist_ok=True)
        seed_marker = dev_stage / ".seeded"
        if not seed_marker.is_file():
            seed_development_sysroot(dev_stage, graphics_stage, graphics_key, graphics_lock)
            seed_marker.write_text("complete\n", encoding="ascii")
        host_pc = refresh_pkgconfig(dev_stage)
        system = dev_stage / "System"
        environment = os.environ.copy()
        environment.update({
            "SOURCE_DATE_EPOCH": str(lock["source_date_epoch"]),
            "PKG_CONFIG_LIBDIR": str(host_pc),
            "PKG_CONFIG_PATH": "",
            "PATH": f"{system / 'Commands'}:{environment.get('PATH', '')}",
            "LD_LIBRARY_PATH": f"{system / 'Libraries' / 'Graphics'}:{system / 'Libraries'}",
            "CFLAGS": "-O2 -pipe -fPIC -fno-plt -ffunction-sections -fdata-sections -fstack-protector-strong -D_FORTIFY_SOURCE=2",
            "LDFLAGS": (
                f"-L{system / 'Libraries' / 'Graphics'} -L{system / 'Libraries'} "
                f"-Wl,-rpath-link,{system / 'Libraries' / 'Graphics'} "
                f"-Wl,-rpath-link,{system / 'Libraries'} -Wl,-O1,--as-needed,--gc-sections,-z,relro,-z,now"
            ),
        })

        configure_build("pixman", sources["pixman"], build_root, dev_stage, environment, jobs, [
            "-Dtests=disabled", "-Ddemos=disabled", "-Dgtk=disabled",
            "-Dlibpng=disabled", "-Dopenmp=disabled",
        ])
        host_pc = refresh_pkgconfig(dev_stage)
        environment["PKG_CONFIG_LIBDIR"] = str(host_pc)

        configure_build("xkeyboard-config", sources["xkeyboard_config"], build_root, dev_stage,
                        environment, jobs, [
            "--datadir=Configuration/Keyboard", "-Dnls=false",
            "-Dxorg-rules-symlinks=false", "-Dcompat-rules=true",
        ])

        configure_build("xkbcommon", sources["xkbcommon"], build_root, dev_stage, environment, jobs, [
            "-Denable-tools=false", "-Denable-x11=false", "-Denable-docs=false",
            "-Denable-wayland=false", "-Denable-xkbregistry=false",
            "-Denable-bash-completion=false",
            "-Dxkb-config-root=/System/Configuration/Keyboard/xkeyboard-config-2",
            "-Dxkb-config-extra-path=/System/Configuration/Keyboard/Extensions",
            "-Dx-locale-root=/System/Configuration/Locale",
            "-Ddefault-rules=evdev", "-Ddefault-model=pc105", "-Ddefault-layout=us",
        ], target="xkbcommon")
        host_pc = refresh_pkgconfig(dev_stage)
        environment["PKG_CONFIG_LIBDIR"] = str(host_pc)

        configure_build("wlroots", sources["wlroots"], build_root, dev_stage, environment, jobs, [
            "-Ddefault_library=shared", "-Dexamples=false", "-Dxwayland=disabled",
            "-Dxcb-errors=disabled", "-Dbackends=", "-Drenderers=gles2",
            "-Dallocators=gbm", "-Dsession=disabled", "-Dcolor-management=disabled",
            "-Dlibliftoff=disabled", "-Dauto_features=disabled", "-Db_ndebug=false",
        ])
        host_pc = refresh_pkgconfig(dev_stage)
        environment["PKG_CONFIG_LIBDIR"] = str(host_pc)

        configure_build("mwm", REPO / "Product" / "MWM", build_root, dev_stage, environment, jobs, [])
        marker.write_text(build_key + "\n", encoding="ascii")

    elapsed = int(time.monotonic() - started)
    stage_runtime(lock, sources, dev_stage, graphics_root, build_key, jobs, elapsed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
