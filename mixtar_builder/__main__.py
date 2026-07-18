from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .builder import BuildError, build, inspect_profile


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mixtar-build",
        description="Build a deterministic MixtarRVS filesystem artifact.",
    )
    subcommands = parser.add_subparsers(dest="command", required=True)
    build_command = subcommands.add_parser("build", help="Build one profile")
    build_command.add_argument("profile", type=Path, help="Path to a TOML profile")
    inspect_command = subcommands.add_parser("inspect", help="Inspect one profile")
    inspect_command.add_argument("profile", type=Path, help="Path to a TOML profile")
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        if args.command == "inspect":
            report = inspect_profile(args.profile)
            readiness = report["readiness"]
            print(f"System: {report['system']}")
            print(f"Target: {report['target']}")
            print(f"Components: {len(report['components'])}")
            print(f"Required roles: {', '.join(readiness['required_roles']) or 'none'}")
            print(
                f"Available roles: {', '.join(readiness['available_roles']) or 'none'}"
            )
            print(f"Missing roles: {', '.join(readiness['missing_roles']) or 'none'}")
            print(f"Ready: {'yes' if readiness['ready'] else 'no'}")
            return 0 if readiness["ready"] else 1
        result = build(args.profile)
    except (BuildError, OSError, ValueError) as error:
        print(f"mixtar-build: error: {error}", file=sys.stderr)
        return 1

    print(f"Artifact: {result.artifact}")
    print(f"Manifest: {result.manifest}")
    print(f"Initramfs: {result.initramfs}")
    if result.uki is not None:
        print(f"UKI: {result.uki}")
    print(f"ESP image: {result.esp_image}")
    print(f"Root image: {result.root_image}")
    print(f"Disk image: {result.disk_image}")
    print(f"Files: {result.file_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
