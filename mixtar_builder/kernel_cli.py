"""Command-line interface for MixtarRVS kernel source and build operations."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from .kernel_build import build_linux_kernel
from .kernel_source import prepare_kernel_source


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mixtar-kernel",
        description="Prepare and compile a Linux kernel for MixtarRVS.",
    )
    parser.add_argument("--cache", type=Path, default=Path("Cache/Kernel"))
    parser.add_argument("--wsl-distro", required=True)
    parser.add_argument("--version", default="stable")
    parser.add_argument("--archive-url")
    parser.add_argument("--archive-sha256")
    parser.add_argument("--patch", action="append", type=Path, default=[])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("prepare", help="Download, verify and patch kernel sources")
    build = commands.add_parser("build", help="Compile and export a cached kernel")
    build.add_argument(
        "--config", type=Path, default=Path("Kernel/x86_64-mixtar.config")
    )
    build.add_argument("--wsl-cache-home", required=True)
    build.add_argument("--source-date-epoch", required=True, type=int)
    build.add_argument("--output", type=Path, default=Path("Output/Kernel"))
    build.add_argument("--jobs", type=int, default=1)
    build.add_argument("--compiler-cache", action="store_true")
    build.add_argument("--compiler-cache-size", default="20GiB")
    build.add_argument("--initramfs", type=Path)
    build.add_argument("--module-signing-key", type=Path)
    build.add_argument("--module-signing-certificate", type=Path)
    return parser


def main() -> int:
    """Run one kernel preparation or compilation command."""
    arguments = _parser().parse_args()
    source = prepare_kernel_source(
        arguments.cache,
        distribution=arguments.wsl_distro,
        version=arguments.version,
        patches=tuple(arguments.patch),
        archive_url=arguments.archive_url,
        archive_sha256=arguments.archive_sha256,
    )
    result: dict[str, object]
    if arguments.command == "prepare":
        result = {
            "archive_sha256": source.archive_sha256,
            "cache_key": source.cache_key,
            "source": str(source.source),
            "version": source.version,
        }
    else:
        build = build_linux_kernel(
            source,
            arguments.config,
            arguments.output,
            distribution=arguments.wsl_distro,
            native_cache_home=arguments.wsl_cache_home,
            source_date_epoch=arguments.source_date_epoch,
            jobs=arguments.jobs,
            compiler_cache=arguments.compiler_cache,
            compiler_cache_size=arguments.compiler_cache_size,
            embedded_initramfs=arguments.initramfs,
            module_signing_key=arguments.module_signing_key,
            module_signing_certificate=arguments.module_signing_certificate,
        )
        result = {
            "cache_key": build.cache_key,
            "cached": build.cached,
            "executable": str(build.executable),
            "modules": str(build.modules),
            "manifest": str(build.manifest),
            "module_sdk": str(build.module_sdk),
            "module_symvers": str(build.module_symvers),
            "version": build.version,
        }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
