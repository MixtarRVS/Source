"""Linux kernel compilation in a native WSL filesystem with artifact caching."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from .kernel_source import PreparedKernelSource

BUILD_CONTRACT = "mixtar-kernel-build-v6"


class KernelBuildError(RuntimeError):
    """Raised when the WSL kernel build fails."""


@dataclass(frozen=True)
class KernelBuildResult:
    version: str
    executable: Path
    system_map: Path
    configuration: Path
    modules: Path
    module_sdk: Path
    module_symvers: Path
    manifest: Path
    cache_key: str
    cached: bool


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _windows_to_wsl(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    suffix = resolved.as_posix().split(":", 1)[-1]
    return f"/mnt/{drive}{suffix}"


def _run(
    wsl: str,
    distribution: str,
    command: list[str],
    timeout: int = 3600,
) -> subprocess.CompletedProcess[str]:
    process = subprocess.run(
        [wsl, "-d", distribution, "--", *command],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if process.returncode:
        detail = process.stderr.strip() or process.stdout.strip()
        raise KernelBuildError(f"WSL command failed ({command[0]}): {detail}")
    return process


def _sync_source(
    wsl: str,
    distribution: str,
    source: PreparedKernelSource,
    native_source: str,
) -> None:
    marker = f"{native_source}/.mixtar-source.json"
    status = subprocess.run(
        [
            wsl,
            "-d",
            distribution,
            "--",
            "/usr/bin/grep",
            "-Fxq",
            source.cache_key,
            marker,
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if status.returncode == 0:
        return
    _run(wsl, distribution, ["/bin/mkdir", "-p", native_source], timeout=30)
    _run(
        wsl,
        distribution,
        [
            "/usr/bin/rsync",
            "-a",
            "--delete",
            f"{_windows_to_wsl(source.source)}/",
            f"{native_source}/",
        ],
    )
    _run(
        wsl,
        distribution,
        [
            "/bin/sh",
            "-c",
            f"printf '%s\\n' '{source.cache_key}' > '{marker}'",
        ],
        timeout=30,
    )


def _build_key(
    source: PreparedKernelSource,
    architecture: str,
    baseline: str,
    fragment: Path,
    source_date_epoch: int,
    embedded_initramfs: Path | None,
    module_signing_certificate: Path | None,
) -> str:
    material = "\n".join(
        (
            BUILD_CONTRACT,
            source.cache_key,
            architecture,
            baseline,
            _sha256(fragment),
            str(source_date_epoch),
            _sha256(embedded_initramfs) if embedded_initramfs else "no-initramfs",
            _sha256(module_signing_certificate) if module_signing_certificate else "unsigned-modules",
        )
    ).encode("ascii")
    return hashlib.sha256(material).hexdigest()[:20]


def build_linux_kernel(
    source: PreparedKernelSource,
    fragment: Path,
    output: Path,
    *,
    native_cache_home: str,
    distribution: str,
    source_date_epoch: int,
    architecture: str = "x86_64",
    baseline: str = "tinyconfig",
    jobs: int = 0,
    compiler_cache: bool = False,
    compiler_cache_size: str = "20GiB",
    embedded_initramfs: Path | None = None,
    module_signing_key: Path | None = None,
    module_signing_certificate: Path | None = None,
) -> KernelBuildResult:
    """Compile and export a cached Linux kernel using the WSL toolchain."""
    if architecture != "x86_64":
        raise KernelBuildError(f"unsupported kernel architecture: {architecture}")
    fragment = fragment.resolve()
    if not fragment.is_file():
        raise KernelBuildError(f"kernel configuration fragment is missing: {fragment}")
    wsl = shutil.which("wsl.exe")
    if not wsl:
        raise KernelBuildError("Linux kernel compilation requires WSL")

    if source_date_epoch < 0:
        raise KernelBuildError("source date epoch must be non-negative")
    if jobs < 1:
        raise KernelBuildError("kernel build jobs must be positive")
    if compiler_cache and not compiler_cache_size:
        raise KernelBuildError("compiler cache size must not be empty")
    if embedded_initramfs is not None:
        embedded_initramfs = embedded_initramfs.resolve()
        if not embedded_initramfs.is_file():
            raise KernelBuildError(
                f"embedded initramfs is missing: {embedded_initramfs}"
            )
    if (module_signing_key is None) != (module_signing_certificate is None):
        raise KernelBuildError("module signing key and certificate must be supplied together")
    if module_signing_key is not None and module_signing_certificate is not None:
        module_signing_key = module_signing_key.resolve()
        module_signing_certificate = module_signing_certificate.resolve()
        if not module_signing_key.is_file() or not module_signing_certificate.is_file():
            raise KernelBuildError("module signing material is missing")
    build_timestamp = datetime.fromtimestamp(
        source_date_epoch, tz=timezone.utc
    ).strftime("%Y-%m-%d %H:%M:%S UTC")
    key = _build_key(
        source,
        architecture,
        baseline,
        fragment,
        source_date_epoch,
        embedded_initramfs,
        module_signing_certificate,
    )
    cache_parts = native_cache_home.split("/")
    if (
        not native_cache_home.startswith("/")
        or native_cache_home == "/"
        or any(part in (".", "..") for part in cache_parts)
    ):
        raise KernelBuildError("native cache home must be an absolute WSL path")
    native_root = f"{native_cache_home.rstrip('/')}/mixtar/kernel"
    native_compiler_cache = f"{native_cache_home.rstrip('/')}/ccache"
    native_source = f"{native_root}/sources/current-{architecture}"
    native_build = f"{native_root}/builds/current-{architecture}"
    native_build_key = f"{native_build}/.mixtar-build-key"
    native_image = f"{native_build}/arch/x86/boot/bzImage"
    native_modules_order = f"{native_build}/modules.order"
    native_signing_certificate = f"{native_build}/mixtar-module-signing.pem"
    _sync_source(wsl, distribution, source, native_source)
    if compiler_cache:
        _run(
            wsl,
            distribution,
            ["/usr/bin/test", "-x", "/usr/bin/ccache"],
            timeout=30,
        )

    image_status = subprocess.run(
        [
            wsl,
            "-d",
            distribution,
            "--",
            "/usr/bin/test",
            "-s",
            native_image,
            "-a",
            "-f",
            native_modules_order,
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    key_status = subprocess.run(
        [
            wsl,
            "-d",
            distribution,
            "--",
            "/usr/bin/grep",
            "-Fxq",
            key,
            native_build_key,
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    cached = image_status.returncode == 0 and key_status.returncode == 0
    make_environment = (
        [
            "/usr/bin/env",
            f"CCACHE_DIR={native_compiler_cache}",
            f"CCACHE_MAXSIZE={compiler_cache_size}",
        ]
        if compiler_cache
        else []
    )
    make = [
        *make_environment,
        "/usr/bin/make",
        "-C",
        native_source,
        f"O={native_build}",
        "ARCH=x86",
        f"KBUILD_BUILD_TIMESTAMP={build_timestamp}",
        "KBUILD_BUILD_USER=mixtar",
        "KBUILD_BUILD_HOST=builder",
        "KBUILD_BUILD_VERSION=1",
    ]
    if compiler_cache:
        make.extend(("CC=ccache gcc", "HOSTCC=ccache gcc"))
    if not cached:
        _run(wsl, distribution, ["/bin/mkdir", "-p", native_build], timeout=30)
        native_fragment = f"{native_build}/mixtar.config"
        _run(
            wsl,
            distribution,
            ["/bin/cp", _windows_to_wsl(fragment), native_fragment],
            timeout=30,
        )
        if module_signing_certificate is not None:
            _run(
                wsl,
                distribution,
                ["/bin/cp", _windows_to_wsl(module_signing_certificate), native_signing_certificate],
                timeout=30,
            )
            _run(
                wsl,
                distribution,
                [
                    "/bin/sh",
                    "-c",
                    (
                        "printf '%s\\n' "
                        "'CONFIG_MODULE_SIG=y' "
                        "'CONFIG_MODULE_SIG_FORCE=y' "
                        "'# CONFIG_MODULE_SIG_ALL is not set' "
                        "'CONFIG_MODULE_SIG_SHA256=y' "
                        "'CONFIG_MODULE_SIG_HASH=\"sha256\"' "
                        f"'CONFIG_SYSTEM_TRUSTED_KEYS=\"{native_signing_certificate}\"' "
                        "'CONFIG_SYSTEM_REVOCATION_KEYS=\"\"' "
                        f">> '{native_fragment}'"
                    ),
                ],
                timeout=30,
            )
        if embedded_initramfs is not None:
            native_initramfs = f"{native_build}/mixtar-initramfs.cpio"
            _run(
                wsl,
                distribution,
                [
                    "/bin/cp",
                    _windows_to_wsl(embedded_initramfs),
                    native_initramfs,
                ],
                timeout=120,
            )
            _run(
                wsl,
                distribution,
                [
                    "/bin/sh",
                    "-c",
                    (
                        "printf '%s\\n' "
                        f"'CONFIG_INITRAMFS_SOURCE=\"{native_initramfs}\"' "
                        f"'CONFIG_INITRAMFS_ROOT_UID=0' "
                        f"'CONFIG_INITRAMFS_ROOT_GID=0' >> '{native_fragment}'"
                    ),
                ],
                timeout=30,
            )
        _run(wsl, distribution, [*make, baseline])
        merge = f"{native_source}/scripts/kconfig/merge_config.sh"
        _run(
            wsl,
            distribution,
            [
                "/bin/sh",
                merge,
                "-m",
                "-O",
                native_build,
                f"{native_build}/.config",
                native_fragment,
            ],
        )
        _run(wsl, distribution, [*make, "olddefconfig"])
        parallelism = jobs if jobs > 0 else 1
        _run(
            wsl,
            distribution,
            [*make, f"-j{parallelism}", "bzImage", "modules"],
        )
        _run(
            wsl,
            distribution,
            [
                "/bin/sh",
                "-c",
                f"printf '%s\\n' '{key}' > '{native_build_key}'",
            ],
            timeout=30,
        )

    release = _run(
        wsl,
        distribution,
        [
            "/usr/bin/make",
            "-s",
            "-C",
            native_source,
            f"O={native_build}",
            "ARCH=x86",
            f"KBUILD_BUILD_TIMESTAMP={build_timestamp}",
            "KBUILD_BUILD_USER=mixtar",
            "KBUILD_BUILD_HOST=builder",
            "KBUILD_BUILD_VERSION=1",
            "kernelrelease",
        ],
        timeout=60,
    ).stdout.strip()
    destination = output / "System" / "Kernel" / "Linux" / release
    destination.mkdir(parents=True, exist_ok=True)
    executable = destination / "MixtarRVS"
    system_map = destination / "System.map"
    configuration = destination / "Kernel.config"
    modules = destination / "Modules"
    exports = (
        (native_image, executable),
        (f"{native_build}/System.map", system_map),
        (f"{native_build}/.config", configuration),
    )
    for native_path, host_path in exports:
        _run(
            wsl,
            distribution,
            ["/bin/cp", native_path, _windows_to_wsl(host_path)],
            timeout=60,
        )
    native_modules = f"{native_build}/mixtar-modules/{release}"
    _run(
        wsl,
        distribution,
        ["/bin/rm", "-rf", native_modules],
        timeout=30,
    )
    _run(
        wsl,
        distribution,
        [
            *make,
            "modules_install",
            f"MODLIB={native_modules}",
            "INSTALL_MOD_STRIP=1",
            "DEPMOD=/bin/true",
        ],
    )
    if module_signing_key is not None and module_signing_certificate is not None:
        sign_script = Path(__file__).resolve().parent.parent / "scripts" / "sign-kernel-modules.sh"
        _run(
            wsl,
            distribution,
            [
                "/bin/bash",
                _windows_to_wsl(sign_script),
                f"{native_build}/scripts/sign-file",
                _windows_to_wsl(module_signing_key),
                _windows_to_wsl(module_signing_certificate),
                native_modules,
            ],
        )
    if modules.exists():
        shutil.rmtree(modules)
    modules.mkdir(parents=True)
    _run(
        wsl,
        distribution,
        [
            "/usr/bin/rsync",
            "-a",
            "--delete",
            f"{native_modules}/",
            f"{_windows_to_wsl(modules)}/",
        ],
    )
    module_sdk = modules / "Development"
    export_script = Path(__file__).resolve().parent.parent / "scripts" / "export-kernel-sdk.sh"
    _run(
        wsl,
        distribution,
        [
            "/bin/bash",
            _windows_to_wsl(export_script),
            native_source,
            native_build,
            _windows_to_wsl(module_sdk),
        ],
    )
    module_symvers = module_sdk / "Module.symvers"
    if not module_symvers.is_file():
        raise KernelBuildError("external module SDK has no Module.symvers")
    host_modules = _windows_to_wsl(modules)
    _run(wsl, distribution, ["/bin/rm", "-f", f"{host_modules}/build", f"{host_modules}/source"], timeout=30)
    _run(wsl, distribution, ["/bin/ln", "-s", "Development", f"{host_modules}/build"], timeout=30)
    _run(wsl, distribution, ["/bin/ln", "-s", "Development", f"{host_modules}/source"], timeout=30)
    module_files = sorted(path for path in modules.rglob("*.ko*") if path.is_file())
    if not module_files:
        raise KernelBuildError("kernel configuration produced no installable modules")
    manifest = destination / "Build.json"
    manifest.write_text(
        json.dumps(
            {
                "architecture": architecture,
                "archive_url": source.archive_url,
                "archive_sha256": source.archive_sha256,
                "build": {
                    "compiler_cache": compiler_cache,
                    "compiler_cache_size": compiler_cache_size,
                    "jobs": jobs,
                },
                "cache_key": key,
                "configuration_sha256": _sha256(configuration),
                "executable_sha256": _sha256(executable),
                "modules": [
                    {
                        "path": path.relative_to(modules).as_posix(),
                        "sha256": _sha256(path),
                        "size": path.stat().st_size,
                    }
                    for path in module_files
                ],
                "patch_sha256": source.patch_sha256,
                "source_timings_seconds": {
                    name: round(value, 6) for name, value in source.timings.items()
                },
                "source_cached": source.cached,
                "module_sdk": {
                    "path": module_sdk.relative_to(output).as_posix(),
                    "module_symvers_sha256": _sha256(module_symvers),
                },
                "module_signatures_required": module_signing_certificate is not None,
                "release": release,
                "source_cache_key": source.cache_key,
                "source_date_epoch": source_date_epoch,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return KernelBuildResult(
        release,
        executable,
        system_map,
        configuration,
        modules,
        module_sdk,
        module_symvers,
        manifest,
        key,
        cached,
    )
