#!/usr/bin/env python3
"""Compare Linux-native signal/wait status behavior against WSL /bin/sh."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TypedDict

from msh_tool_process import run_tool_cmd

MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_JSON = REPORT_DIR / "msh-linux-signal-wait-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-linux-signal-wait-matrix.md"
RUN_TIMEOUT_SECONDS = 15
DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
ASYNC_SIGNAL_NOTIFICATIONS = {
    "hangup",
    "killed",
    "quit",
    "terminated",
    "user defined signal 1",
}


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    script: str
    compare_stderr: bool = True
    invoke_shell: bool = False
    invoke_script: bool = False


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


class RunResultJson(TypedDict):
    status: int
    stdout: str
    stderr: str
    normalized_stderr: str


class MatrixResultJson(TypedDict):
    group: str
    name: str
    script: str
    compare_stderr: bool
    matches: bool
    msh: RunResultJson
    reference_shell: str
    reference: RunResultJson


def normalize_stderr(stderr: str) -> str:
    lines: list[str] = []
    for line in stderr.splitlines():
        line = DIAG_PREFIX_RE.sub("", line)
        if line.startswith("msh: "):
            line = line[5:]
        normalized = line.strip().lower()
        if normalized == "":
            continue
        if normalized in ASYNC_SIGNAL_NOTIFICATIONS:
            continue
        lines.append(normalized)
    text = "\n".join(lines)
    if lines:
        text += "\n"
    return text


def parse_msh_stdout(stdout: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], "")
    return RunResult(returncode, stdout, "")


def run_msh(msh: Path, case: MatrixCase, cwd: Path) -> RunResult:
    env = os.environ.copy()
    env["AILANG_LEAK_REPORT"] = "0"
    argv = [str(msh), "eval", case.script]
    if case.invoke_shell:
        argv = [str(msh), "-c", case.script]
    if case.invoke_script:
        script = cwd / "msh-case.sh"
        script.write_text(case.script + "\n", encoding="utf-8", newline="\n")
        argv = [str(msh), str(script)]
    proc = run_tool_cmd(
        argv,
        cwd,
        env=env,
        timeout=RUN_TIMEOUT_SECONDS,
        label=f"signal-wait:msh:{case.group}/{case.name}",
    )
    if case.invoke_shell:
        return RunResult(proc.returncode, proc.stdout, proc.stderr)
    parsed = parse_msh_stdout(proc.stdout, proc.returncode)
    return RunResult(parsed.status, parsed.stdout, proc.stderr)


def run_sh(case: MatrixCase, cwd: Path) -> RunResult:
    script = cwd / "case.sh"
    script.write_text(case.script, encoding="utf-8", newline="\n")
    proc = run_tool_cmd(
        ["/bin/sh", str(script)],
        cwd,
        timeout=RUN_TIMEOUT_SECONDS,
        label=f"signal-wait:sh:{case.group}/{case.name}",
    )
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase(
            "wait-signal",
            "wait-term-status",
            'sleep 5 & p=$!\nkill -TERM "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-signal",
            "wait-int-status",
            'sleep 0.2 & p=$!\nsleep 0.05\nkill -INT "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-signal",
            "wait-hup-status",
            'sleep 5 & p=$!\nkill -HUP "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-signal",
            "wait-quit-status",
            'sleep 0.2 & p=$!\nsleep 0.05\nkill -QUIT "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-signal",
            "wait-usr1-status",
            'sleep 5 & p=$!\nkill -USR1 "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-signal",
            "wait-kill-status",
            'sleep 5 & p=$!\nkill -KILL "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-after",
            "wait-killed-pid-twice",
            'sleep 5 & p=$!\nkill -TERM "$p"\nwait "$p"\na=$?\nwait "$p"\nprintf \'<%s:%s>\' "$a" "$?"',
        ),
        MatrixCase(
            "wait-after",
            "wait-all-after-signaled-child",
            'sleep 5 & p=$!\nkill -TERM "$p"\nwait\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-after", "wait-with-no-known-children", "wait\nprintf '<%s>' \"$?\""
        ),
        MatrixCase(
            "wait-after", "wait-unknown-pid-status", "wait 999999\nprintf '<%s>' \"$?\""
        ),
        MatrixCase(
            "wait-after", "wait-invalid-pid-status", "wait nope\nprintf '<%s>' \"$?\""
        ),
        MatrixCase(
            "wait-after", "wait-zero-pid-status", "wait 0\nprintf '<%s>' \"$?\""
        ),
        MatrixCase(
            "wait-after",
            "wait-current-shell-pid-status",
            "wait $$\nprintf '<%s>' \"$?\"",
        ),
        MatrixCase(
            "wait-after",
            "wait-all-clears-known-pid",
            '( exit 3 ) & p=$!\nwait\na=$?\nwait "$p"\nprintf \'<%s:%s>\' "$a" "$?"',
        ),
        MatrixCase(
            "wait-exit",
            "wait-exit-zero-explicit",
            '( exit 0 ) & p=$!\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-exit",
            "wait-exit-one-explicit",
            '( exit 1 ) & p=$!\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-exit",
            "wait-exit-127-explicit",
            '( exit 127 ) & p=$!\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-exit",
            "wait-exit-255-explicit",
            '( exit 255 ) & p=$!\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-exit",
            "wait-multiple-unknown-last",
            '( exit 3 ) & p=$!\nwait "$p" 999999\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-exit",
            "wait-multiple-unknown-first",
            '( exit 3 ) & p=$!\nwait 999999 "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-order",
            "wait-two-exit-children-last-status",
            '( exit 3 ) & p1=$!\n( exit 7 ) & p2=$!\nwait "$p1" "$p2"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "wait-order",
            "wait-two-children-last-signaled",
            '( exit 3 ) & p1=$!\nsleep 5 & p2=$!\nkill -TERM "$p2"\nwait "$p1" "$p2"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-zero",
            "kill-zero-live-background",
            'sleep 1 & p=$!\nkill -0 "$p"\na=$?\nkill -TERM "$p"\nwait "$p"\nprintf \'<%s:%s>\' "$a" "$?"',
        ),
        MatrixCase(
            "kill-zero",
            "kill-zero-after-wait",
            'sleep 5 & p=$!\nkill -TERM "$p"\nwait "$p"\nkill -0 "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-options",
            "kill-s-term-child",
            'sleep 5 & p=$!\nkill -s TERM "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-options",
            "kill-s-kill-child",
            'sleep 5 & p=$!\nkill -s KILL "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-options",
            "kill-s-numeric-term-child",
            'sleep 5 & p=$!\nkill -s 15 "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-options",
            "kill-s-numeric-kill-child",
            'sleep 5 & p=$!\nkill -s 9 "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-options",
            "kill-dash-numeric-term-child",
            'sleep 5 & p=$!\nkill -15 "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-options",
            "kill-dash-numeric-kill-child",
            'sleep 5 & p=$!\nkill -9 "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "kill-options", "kill-missing-pid", "kill -TERM\nprintf '<%s>' \"$?\""
        ),
        MatrixCase(
            "kill-options",
            "kill-invalid-signal-name",
            "kill -s NOPE $$\nprintf '<%s>' \"$?\"",
        ),
        MatrixCase(
            "kill-options",
            "kill-nonnumeric-pid",
            "kill -TERM nope\nprintf '<%s>' \"$?\"",
        ),
        MatrixCase(
            "async-status",
            "background-list-status-zero-after-false",
            'false\nsleep 0.1 & p=$!\na=$?\nwait "$p"\nprintf \'<%s:%s>\' "$a" "$?"',
        ),
        MatrixCase(
            "async-status",
            "last-background-pid-changes",
            'sleep 0.2 & p1=$!\nsleep 0.1 & p2=$!\nif [ "$p1" = "$p2" ]; then printf same; else printf different; fi\nwait "$p1" "$p2"',
        ),
        MatrixCase(
            "wait-order",
            "wait-two-children-one-signaled",
            'sleep 5 & p1=$!\n( exit 7 ) & p2=$!\nkill -TERM "$p1"\nwait "$p1"\na=$?\nwait "$p2"\nprintf \'<%s:%s>\' "$a" "$?"',
        ),
        MatrixCase(
            "wait-order",
            "wait-explicit-running-then-signaled",
            'sleep 5 & p=$!\nkill -TERM "$p"\nwait "$p"\nprintf \'<%s>\' "$?"',
        ),
        MatrixCase(
            "shell-signal", "kill-zero-self", "kill -0 $$\nprintf '<%s>' \"$?\""
        ),
        MatrixCase(
            "shell-signal",
            "trap-term-self-continues",
            "trap 'printf trap' TERM\nkill -TERM $$\nprintf ':<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "trap-term-self-exits",
            "trap 'printf trap; exit 7' TERM\nkill -TERM $$\nprintf after",
        ),
        MatrixCase(
            "shell-signal",
            "ignore-term-self",
            "trap '' TERM\nkill -TERM $$\nprintf 'alive:<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "ignore-int-self",
            "trap '' INT\nkill -INT $$\nprintf 'alive:<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "ignore-hup-self",
            "trap '' HUP\nkill -HUP $$\nprintf 'alive:<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "ignore-quit-self",
            "trap '' QUIT\nkill -QUIT $$\nprintf 'alive:<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "ignore-usr1-self",
            "trap '' USR1\nkill -USR1 $$\nprintf 'alive:<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "trap-hup-self",
            "trap 'printf hup' HUP\nkill -HUP $$\nprintf ':<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "trap-int-self",
            "trap 'printf int' INT\nkill -INT $$\nprintf ':<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "trap-quit-self",
            "trap 'printf quit' QUIT\nkill -QUIT $$\nprintf ':<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-signal",
            "trap-usr1-self",
            "trap 'printf usr1' USR1\nkill -USR1 $$\nprintf ':<%s>' \"$?\"",
        ),
        MatrixCase(
            "shell-termination",
            "trap-reset-term-default",
            "trap 'printf trapped' TERM\ntrap - TERM\nkill -TERM $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-ignore-then-reset-term",
            "trap '' TERM\ntrap - TERM\nkill -TERM $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-numeric-term-self",
            "kill -15 $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-s-numeric-term-self",
            "kill -s 15 $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-kill-self-invocation",
            "kill -KILL $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-dash-kill-self-invocation",
            "kill -9 $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-s-kill-self-invocation",
            "kill -s KILL $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-kill-still-terminates-invocation",
            "trap 'printf bad' KILL\nkill -KILL $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "ignore-kill-still-terminates-invocation",
            "trap '' KILL\nkill -KILL $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-int-self-invocation",
            "kill -INT $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-hup-self-invocation",
            "kill -HUP $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-quit-self-invocation",
            "kill -QUIT $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "kill-usr1-self-invocation",
            "kill -USR1 $$\nprintf after",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-ignore-term-self-invocation",
            "trap '' TERM\nkill -TERM $$\nprintf 'alive:%s' $?",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-ignore-int-self-invocation",
            "trap '' INT\nkill -INT $$\nprintf 'alive:%s' $?",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-ignore-hup-self-invocation",
            "trap '' HUP\nkill -HUP $$\nprintf 'alive:%s' $?",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-ignore-quit-self-invocation",
            "trap '' QUIT\nkill -QUIT $$\nprintf 'alive:%s' $?",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-ignore-usr1-self-invocation",
            "trap '' USR1\nkill -USR1 $$\nprintf 'alive:%s' $?",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-empty-exit-ignored-invocation",
            "trap '' EXIT\nexit 7",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-reset-exit-invocation",
            "trap 'printf exit' EXIT\ntrap - EXIT\nexit 7",
            True,
            True,
        ),
        MatrixCase(
            "shell-termination",
            "trap-exit-status-in-action-invocation",
            "trap 'printf exit:$?' EXIT\nfalse",
            True,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-reset-term-default",
            "trap 'printf trapped' TERM\ntrap - TERM\nkill -TERM $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-ignore-then-reset-term",
            "trap '' TERM\ntrap - TERM\nkill -TERM $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-numeric-term-self",
            "kill -15 $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-s-numeric-term-self",
            "kill -s 15 $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-kill-self",
            "kill -KILL $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-dash-kill-self",
            "kill -9 $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-s-kill-self",
            "kill -s KILL $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-kill-still-terminates",
            "trap 'printf bad' KILL\nkill -KILL $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-ignore-kill-still-terminates",
            "trap '' KILL\nkill -KILL $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-int-self",
            "kill -INT $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-hup-self",
            "kill -HUP $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-quit-self",
            "kill -QUIT $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-kill-usr1-self",
            "kill -USR1 $$\nprintf after",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-ignore-term-self",
            "trap '' TERM\nkill -TERM $$\nprintf 'alive:%s' $?",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-ignore-int-self",
            "trap '' INT\nkill -INT $$\nprintf 'alive:%s' $?",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-ignore-hup-self",
            "trap '' HUP\nkill -HUP $$\nprintf 'alive:%s' $?",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-ignore-quit-self",
            "trap '' QUIT\nkill -QUIT $$\nprintf 'alive:%s' $?",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-ignore-usr1-self",
            "trap '' USR1\nkill -USR1 $$\nprintf 'alive:%s' $?",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-empty-exit-ignored",
            "trap '' EXIT\nexit 7",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-reset-exit",
            "trap 'printf exit' EXIT\ntrap - EXIT\nexit 7",
            True,
            False,
            True,
        ),
        MatrixCase(
            "script-termination",
            "script-trap-exit-status-in-action",
            "trap 'printf exit:$?' EXIT\nfalse",
            True,
            False,
            True,
        ),
    ]


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(
        ref.stderr
    ):
        return False
    return True


def run_case(
    msh: Path, case: MatrixCase, root: Path, progress: bool
) -> MatrixResultJson:
    if progress:
        print(f"[signal-wait] {case.group}/{case.name}", file=sys.stderr, flush=True)
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{case.group}-{case.name}")
    case_root = root / safe
    msh_dir = case_root / "msh"
    ref_dir = case_root / "sh"
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_dir.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir)
    ref = run_sh(case, ref_dir)
    return {
        "group": case.group,
        "name": case.name,
        "script": case.script,
        "compare_stderr": case.compare_stderr,
        "matches": rows_match(case, msh_result, ref),
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
            "normalized_stderr": normalize_stderr(msh_result.stderr),
        },
        "reference_shell": "wsl-sh",
        "reference": {
            "status": ref.status,
            "stdout": ref.stdout,
            "stderr": ref.stderr,
            "normalized_stderr": normalize_stderr(ref.stderr),
        },
    }


def write_json(path: Path, rows: list[MatrixResultJson]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")


def write_markdown(path: Path, rows: list[MatrixResultJson]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    groups: dict[str, tuple[int, int]] = {}
    for row in rows:
        key = str(row["group"])
        done, count = groups.get(key, (0, 0))
        groups[key] = (done + (1 if row["matches"] is True else 0), count + 1)
    lines = [
        "# msh Linux Signal/Wait Matrix",
        "",
        "Generated by `msh_linux_signal_wait_matrix.py` against WSL `/bin/sh`.",
        "",
        "## Summary",
        "",
        f"- Overall: `{matches}/{total}`",
    ]
    for key in sorted(groups):
        done, count = groups[key]
        lines.append(f"- `{key}`: `{done}/{count}`")
    lines.extend(["", "## Mismatches", ""])
    mismatches = [row for row in rows if row["matches"] is not True]
    if not mismatches:
        lines.extend(["No mismatches.", ""])
    for row in mismatches:
        msh = row["msh"]
        ref = row["reference"]
        lines.extend(
            [
                f"### {row['group']}/{row['name']}",
                "",
                "```sh",
                str(row["script"]).rstrip(),
                "```",
                "",
                f"- msh: status `{msh['status']}`, stdout `{msh['stdout']!r}`, stderr `{msh['normalized_stderr']!r}`",
                f"- wsl-sh: status `{ref['status']}`, stdout `{ref['stdout']!r}`, stderr `{ref['normalized_stderr']!r}`",
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_summary(rows: list[MatrixResultJson]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh linux signal/wait matrix: {matches}/{total} match wsl-sh")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["reference"]
        print(f"- {row['group']}/{row['name']}")
        print(f"  script: {row['script']!r}")
        print(
            f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}"
        )
        print(
            f"  sh:  status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the Linux signal/wait status matrix."
    )
    parser.add_argument("--msh", type=Path, required=True)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--progress", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if os.name == "nt":
        print("msh_linux_signal_wait_matrix.py must run on Linux/WSL")
        return 2
    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-linux-signal-wait-matrix-") as raw:
        root = Path(raw)
        rows = [run_case(msh, case, root, args.progress) for case in matrix_cases()]
    write_json(args.json_report, rows)
    write_markdown(args.report, rows)
    print_summary(rows)
    if args.strict and any(row["matches"] is not True for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
