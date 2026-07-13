#!/usr/bin/env python3
"""Executable probes for known POSIX blockers in msh.

This is intentionally separate from msh_semantic_probe.py. These probes run
real msh scripts and compare them with WSL /bin/sh when available, but open
blockers are reported instead of failing the normal gate.
"""

from __future__ import annotations

import argparse
import re
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from msh_tool_process import run_tool_cmd

RUN_TIMEOUT_SECONDS = 10

@dataclass(frozen=True)
class Probe:
    name: str
    script: str
    why: str
    file: str = ""


@dataclass(frozen=True)
class Result:
    name: str
    closed: bool
    reason: str
    msh_status: int
    ref_status: int
    msh_stdout: str
    ref_stdout: str
    msh_file: str
    ref_file: str


def default_msh_path() -> Path:
    here = Path(__file__).resolve()
    repo_root = here.parents[4]
    return repo_root / "out" / "server" / "msh_cli.exe"


def run_cmd(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return run_tool_cmd(argv, cwd, timeout=RUN_TIMEOUT_SECONDS)


def parse_msh(stdout: str, returncode: int) -> tuple[int, str]:
    status = returncode
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        status = int(marker.group(1))
        return status, stdout[: marker.start()]
    lines: list[str] = []
    for line in stdout.splitlines():
        if line.startswith("status="):
            try:
                status = int(line[7:])
            except ValueError:
                status = returncode
        else:
            lines.append(line)
    text = ""
    if lines:
        text = "\n".join(lines) + "\n"
    return status, text


def wsl_available() -> bool:
    proc = run_cmd(["wsl.exe", "--exec", "sh", "-c", "exit 0"])
    return proc.returncode == 0


def windows_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def run_msh(msh: Path, script: str, cwd: Path) -> tuple[int, str]:
    proc = run_cmd([str(msh), "eval", script], cwd=cwd)
    return parse_msh(proc.stdout, proc.returncode)


def run_wsl(script: str, cwd: Path) -> tuple[int, str]:
    wsl_cwd = shlex.quote(windows_to_wsl_path(cwd))
    proc = run_cmd(["wsl.exe", "--exec", "sh", "-c", f"cd {wsl_cwd} && {script}"])
    return proc.returncode, proc.stdout


def read_probe_file(cwd: Path, name: str) -> str:
    if not name:
        return ""
    path = cwd / name
    if not path.exists():
        return "<missing>"
    return path.read_text(encoding="utf-8", errors="replace")


def probes() -> list[Probe]:
    return [
        Probe(
            "same-read-unit alias activation",
            "alias hi='printf hi\\n'\nhi",
            "POSIX alias timing is read-time; msh still expands aliases before execution.",
        ),
        Probe(
            "function overrides regular builtin",
            "true() { false; }\ntrue",
            "Command search order must honor functions before regular builtins.",
        ),
        Probe(
            "EXIT trap execution",
            "trap 'printf done > exit.out' EXIT; :",
            "trap metadata exists, but EXIT/event delivery is not complete.",
            "exit.out",
        ),
        Probe(
            "persistent exec output redirection",
            "exec > exec.out; printf 'ok\\n'",
            "exec redirection-only currently validates/creates files but does not mutate shell fds.",
            "exec.out",
        ),
        Probe(
            "persistent exec input redirection",
            "printf 'x\\n' > in.txt; exec < in.txt; read A; printf $A > read.out",
            "persistent fd mutation is required before read can consume exec-provided stdin.",
            "read.out",
        ),
        Probe(
            "background command execution",
            "printf bg > bg.out &\nwait",
            "BACKGROUND nodes are parsed, but async execution/job wait semantics are not complete.",
            "bg.out",
        ),
    ]


def run_probe(msh: Path, probe: Probe, root: Path, use_wsl: bool) -> Result:
    msh_dir = root / "msh"
    ref_dir = root / "ref"
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_dir.mkdir(parents=True, exist_ok=True)

    msh_status, msh_stdout = run_msh(msh, probe.script, msh_dir)
    msh_file = read_probe_file(msh_dir, probe.file)

    if use_wsl:
        ref_status, ref_stdout = run_wsl(probe.script, ref_dir)
        ref_file = read_probe_file(ref_dir, probe.file)
    else:
        ref_status = msh_status
        ref_stdout = msh_stdout
        ref_file = msh_file

    closed = (
        msh_status == ref_status
        and msh_stdout == ref_stdout
        and msh_file == ref_file
    )
    return Result(
        probe.name,
        closed,
        probe.why,
        msh_status,
        ref_status,
        msh_stdout,
        ref_stdout,
        msh_file,
        ref_file,
    )


def print_result(result: Result) -> None:
    state = "closed" if result.closed else "open"
    print(f"- [{state}] {result.name}")
    if result.closed:
        return
    print(f"  why: {result.reason}")
    print(f"  msh: status={result.msh_status} stdout={result.msh_stdout!r} file={result.msh_file!r}")
    print(f"  ref: status={result.ref_status} stdout={result.ref_stdout!r} file={result.ref_file!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--msh", type=Path, default=default_msh_path())
    parser.add_argument("--no-wsl", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2

    use_wsl = (not args.no_wsl) and wsl_available()
    if not use_wsl:
        print("msh blocker probe: WSL unavailable; running msh-only smoke mode")

    results: list[Result] = []
    with tempfile.TemporaryDirectory(prefix="msh-blockers-") as raw:
        root = Path(raw)
        for idx, probe in enumerate(probes()):
            results.append(run_probe(msh, probe, root / str(idx), use_wsl))

    closed = sum(1 for item in results if item.closed)
    open_count = len(results) - closed
    source = "WSL sh differential" if use_wsl else "msh-only"
    print(f"msh blocker probe: {closed} closed, {open_count} open ({source})")
    for result in results:
        print_result(result)

    if args.strict and open_count > 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
