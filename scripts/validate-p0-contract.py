#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Iterable

from mixtar_config import DEFAULT_CONFIG, load_config


REPO_ROOT = Path(__file__).resolve().parent.parent
SELF = Path(__file__).resolve()
TEXT_SUFFIXES = {
    ".c",
    ".config",
    ".h",
    ".in",
    ".json",
    ".patch",
    ".ps1",
    ".py",
    ".sh",
    ".toml",
}
HOST_SCAN_ROOTS = (
    "Scripts",
    "Root",
    "Kernel",
    "Patches",
    "Profiles",
    "mixtar_builder",
    "Release",
    "Tests",
)
HOST_PATTERNS = {
    "windows-user-profile": re.compile(r"[A-Za-z]:\\Users\\"),
    "wsl-windows-user-profile": re.compile(r"/mnt/[A-Za-z]/Users/"),
    "specific-linux-home": re.compile(r"/home/(?!\*)(?:[A-Za-z0-9._-]+)(?:/|$)"),
    "legacy-repository-name": re.compile(r"MixtarRVS_Debian_Edition"),
}
PUBLIC_FHS = re.compile(
    r"(?<![A-Za-z0-9_])/(?:proc|sys|dev|run|usr|etc|lib|var)(?:/|\b)"
)
FORBIDDEN_ROOT_NAMES = {"proc", "sys", "dev", "run", "usr", "etc", "lib", "var"}


def text_lines(path: Path) -> list[str] | None:
    if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {"Makefile"}:
        return None
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return None


def source_files(root: Path) -> Iterable[Path]:
    if root.is_file():
        yield root
        return
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.resolve() != SELF:
            yield path


def violation(path: Path, line: int, rule: str, text: str) -> dict[str, object]:
    return {
        "path": path.relative_to(REPO_ROOT).as_posix(),
        "line": line,
        "rule": rule,
        "text": text.strip(),
    }


def audit_host_paths() -> tuple[int, list[dict[str, object]]]:
    checked = 0
    violations: list[dict[str, object]] = []
    for relative_root in HOST_SCAN_ROOTS:
        for path in source_files(REPO_ROOT / relative_root):
            lines = text_lines(path)
            if lines is None:
                continue
            checked += 1
            for number, line in enumerate(lines, 1):
                for rule, pattern in HOST_PATTERNS.items():
                    if pattern.search(line):
                        violations.append(violation(path, number, rule, line))
    return checked, violations


def audit_runtime_roots() -> tuple[int, list[dict[str, object]]]:
    checked = 0
    violations: list[dict[str, object]] = []
    root = REPO_ROOT / "Root"
    for path in source_files(root):
        relative = path.relative_to(root)
        if relative.parts and relative.parts[0].lower() in FORBIDDEN_ROOT_NAMES:
            violations.append(violation(path, 0, "forbidden-runtime-root", relative.as_posix()))
        lines = text_lines(path)
        if lines is None:
            continue
        checked += 1
        for number, line in enumerate(lines, 1):
            if PUBLIC_FHS.search(line):
                violations.append(violation(path, number, "public-fhs-runtime-path", line))
    return checked, violations


def audit_patch_additions() -> tuple[int, list[dict[str, object]]]:
    checked = 0
    violations: list[dict[str, object]] = []
    for path in sorted((REPO_ROOT / "Patches").rglob("*.patch")):
        checked += 1
        lines = path.read_text(encoding="utf-8").splitlines()
        for number, line in enumerate(lines, 1):
            if line.startswith("+") and not line.startswith("+++") and PUBLIC_FHS.search(line[1:]):
                violations.append(violation(path, number, "public-fhs-patch-addition", line))
    return checked, violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the Mixtar P0 path contract")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    try:
        load_config(args.config.resolve())
        host_checked, host_violations = audit_host_paths()
        runtime_checked, runtime_violations = audit_runtime_roots()
        patches_checked, patch_violations = audit_patch_additions()
        violations = host_violations + runtime_violations + patch_violations
        report = {
            "schema": "mixtar.p0-contract-report.v1",
            "passed": not violations,
            "layout_config": args.config.resolve().relative_to(REPO_ROOT).as_posix(),
            "checks": {
                "host_files": host_checked,
                "runtime_files": runtime_checked,
                "patches": patches_checked,
            },
            "violations": violations,
        }
        payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(payload, encoding="utf-8")
        if violations:
            for item in violations:
                print(
                    f"{item['path']}:{item['line']}: {item['rule']}: {item['text']}",
                    file=sys.stderr,
                )
            return 1
        print("P0_CONTRACT_OK")
        return 0
    except (OSError, ValueError, KeyError) as error:
        print(f"P0 contract validation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
