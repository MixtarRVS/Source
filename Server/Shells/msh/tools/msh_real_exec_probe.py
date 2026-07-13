#!/usr/bin/env python3
"""Probe msh's true-exec path without disturbing the normal eval harness.

`msh_cli eval` must keep printing a status marker for the differential tools.
This probe uses `eval-real-exec`, which enables the internal real-exec flag.
On POSIX-native builds a successful exec replaces the shell process; on hosted
Windows builds the AILang runtime intentionally falls back to run-and-return.
Both modes must return the target status and honor exec redirections.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


MIXTAR_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"


def run_msh(msh: Path, script: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(msh), "eval-real-exec", script],
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def target_exit_script(status: int) -> str:
    if os.name == "nt":
        return f"exec cmd /C exit {status}"
    return f"exec sh -c 'exit {status}'"


def target_redir_script() -> str:
    if os.name == "nt":
        return "exec cmd /C echo real > real_exec_probe.out"
    return "exec sh -c 'printf real' > real_exec_probe.out"


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe msh real exec mode.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="msh-real-exec-") as raw:
        cwd = Path(raw)
        status_proc = run_msh(args.msh, target_exit_script(9), cwd)
        if status_proc.returncode != 9:
            print("real-exec status probe failed", file=sys.stderr)
            print(f"returncode={status_proc.returncode}", file=sys.stderr)
            print(status_proc.stdout, file=sys.stderr)
            print(status_proc.stderr, file=sys.stderr)
            return 1

        redir_proc = run_msh(args.msh, target_redir_script(), cwd)
        if redir_proc.returncode != 0:
            print("real-exec redirection probe failed", file=sys.stderr)
            print(f"returncode={redir_proc.returncode}", file=sys.stderr)
            print(redir_proc.stdout, file=sys.stderr)
            print(redir_proc.stderr, file=sys.stderr)
            return 1

        out_path = cwd / "real_exec_probe.out"
        if not out_path.exists():
            print("real-exec redirection probe did not create output", file=sys.stderr)
            return 1
        text = out_path.read_text(encoding="utf-8").replace("\r\n", "\n")
        if text != "real\n" and text != "real":
            print("real-exec redirection probe wrote unexpected output", file=sys.stderr)
            print(repr(text), file=sys.stderr)
            return 1

    print("msh real exec probe: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
