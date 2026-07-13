#!/usr/bin/env python3
"""Focused command-search probes for hosted msh profiles."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
RUN_TIMEOUT_SECONDS = 10


@dataclass(frozen=True)
class ProbeCase:
    name: str
    script: str
    status: int
    stdout_contains: str = ""
    stderr_contains: str = ""


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def parse_msh(stdout: str, stderr: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], stderr)
    status = returncode
    lines: list[str] = []
    for line in stdout.splitlines():
        if line.startswith("status="):
            try:
                status = int(line[7:])
            except ValueError:
                status = returncode
        else:
            lines.append(line)
    text = "\n".join(lines)
    if text:
        text += "\n"
    return RunResult(status, text, stderr)


def run_msh(msh: Path, script: str, cwd: Path) -> RunResult:
    proc = subprocess.run(
        [str(msh), "eval", script],
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=RUN_TIMEOUT_SECONDS,
    )
    return parse_msh(proc.stdout, proc.stderr, proc.returncode)


def host_external_case() -> tuple[str, str, str]:
    if os.name == "nt":
        if shutil.which("where") is not None:
            return "where", "cmd", "cmd"
        if shutil.which("where.exe") is not None:
            return "where.exe", "cmd", "cmd"
    else:
        if shutil.which("env") is not None:
            return "env", "", "PATH="
    raise RuntimeError("no suitable host external command found for command -p probe")


def cases() -> list[ProbeCase]:
    command, arg, expected_output = host_external_case()
    arg_suffix = f" {arg}" if arg else ""
    return [
        ProbeCase(
            "command -p runs default-path external",
            f"PATH=/definitely_missing; command -p {command}{arg_suffix}",
            0,
            expected_output,
        ),
        ProbeCase(
            "plain command obeys poisoned shell PATH",
            f"PATH=/definitely_missing; command {command}{arg_suffix}",
            127,
            "",
            f"{command}: not found",
        ),
        ProbeCase(
            "command -p -v reports default-path external",
            f"PATH=/definitely_missing; command -p -v {command}",
            0,
            command,
        ),
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe msh command-search behavior that depends on the host default path.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="msh-command-search-") as raw:
        cwd = Path(raw)
        for case in cases():
            try:
                result = run_msh(msh, case.script, cwd)
            except subprocess.TimeoutExpired:
                failures.append(f"{case.name}: timed out after {RUN_TIMEOUT_SECONDS}s")
                continue
            if result.status != case.status:
                failures.append(
                    f"{case.name}: expected status {case.status}, got {result.status}\n"
                    f"  script: {case.script}\n"
                    f"  stdout: {result.stdout!r}\n"
                    f"  stderr: {result.stderr!r}"
                )
                continue
            if case.stdout_contains and case.stdout_contains not in result.stdout:
                failures.append(
                    f"{case.name}: stdout missing {case.stdout_contains!r}\n"
                    f"  script: {case.script}\n"
                    f"  stdout: {result.stdout!r}"
                )
            if case.stderr_contains and case.stderr_contains not in result.stderr:
                failures.append(
                    f"{case.name}: stderr missing {case.stderr_contains!r}\n"
                    f"  script: {case.script}\n"
                    f"  stderr: {result.stderr!r}"
                )
    if failures:
        print("msh command-search probe: FAILED")
        for failure in failures:
            print("\n- " + failure)
        return 1
    print(f"msh command-search probe: ok ({len(cases())} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
