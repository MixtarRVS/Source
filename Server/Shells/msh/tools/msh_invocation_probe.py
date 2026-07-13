#!/usr/bin/env python3
"""Probe POSIX shell invocation forms that file suites cannot express."""

from __future__ import annotations

import argparse
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Case:
    name: str
    args: tuple[str, ...]
    stdin: str
    stdout: str
    status: int = 0


CASES = (
    Case("stdin-default", (), "echo stdin-ok\n", "stdin-ok\n"),
    Case("stdin-interactive-option", ("-i",), "echo interactive-ok\n", "interactive-ok\n"),
    Case("stdin-script-option-args", ("-s", "one", "two"), "echo ${1}-${2}\n", "one-two\n"),
    Case("double-dash-stdin", ("--",), "echo dashdash-ok\n", "dashdash-ok\n"),
)


def normalize(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def run_case(msh: Path, case: Case) -> tuple[bool, str]:
    proc = subprocess.run(
        [str(msh), *case.args],
        input=case.stdin,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    stdout = normalize(proc.stdout)
    if proc.returncode != case.status or stdout != case.stdout:
        return (
            False,
            f"{case.name}: got status={proc.returncode} stdout={stdout!r} stderr={proc.stderr!r}",
        )
    return True, case.name


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe msh shell invocation forms.")
    parser.add_argument("--msh", type=Path, required=True)
    args = parser.parse_args()

    failures: list[str] = []
    for case in CASES:
        ok, detail = run_case(args.msh, case)
        print(("PASS " if ok else "FAIL ") + detail)
        if not ok:
            failures.append(detail)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
