#!/usr/bin/env python3
"""Compare hosted-safe msh signal/trap behavior against WSL /bin/sh.

This matrix stays inside the non-interactive profile: shell-side traps,
self-signals, EXIT handling, signal-listing helpers, and background wait status.
It deliberately does not claim terminal job-control semantics.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from msh_tool_process import run_tool_cmd
from msh_matrix_reference import local_reference_shell_names, run_local_reference_shell
import tempfile
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_JSON = REPORT_DIR / "msh-signal-trap-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-signal-trap-matrix.md"
RUN_TIMEOUT_SECONDS = 10
WSL_DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
_WSL_AVAILABLE: bool | None = None


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    script: str
    compare_stderr: bool = False
    compare_status: bool = True


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def run_cmd(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return run_tool_cmd(argv, cwd, timeout=RUN_TIMEOUT_SECONDS)


def wsl_available() -> bool:
    global _WSL_AVAILABLE
    if _WSL_AVAILABLE is not None:
        return _WSL_AVAILABLE
    proc = run_cmd(["wsl.exe", "--exec", "sh", "-c", "echo ok"])
    _WSL_AVAILABLE = proc.returncode == 0 and proc.stdout == "ok\n"
    return _WSL_AVAILABLE


def windows_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def parse_msh(stdout: str, stderr: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], stderr)
    lines: list[str] = []
    status = returncode
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


def normalize_stderr(stderr: str) -> str:
    if not stderr:
        return ""
    lines: list[str] = []
    for line in stderr.splitlines():
        line = WSL_DIAG_PREFIX_RE.sub("", line)
        if line.startswith("msh: "):
            line = line[5:]
        lines.append(line)
    text = "\n".join(lines)
    if stderr.endswith("\n"):
        text += "\n"
    return text


def run_msh(msh: Path, case: MatrixCase, cwd: Path) -> RunResult:
    proc = run_cmd([str(msh), "eval", case.script], cwd=cwd)
    return parse_msh(proc.stdout, proc.stderr, proc.returncode)


def run_wsl_sh(case: MatrixCase, cwd: Path) -> RunResult:
    if not wsl_available():
        return RunResult(127, "", "wsl unavailable\n")
    script_path = cwd / "case.sh"
    body = "cd " + windows_to_wsl_path(cwd) + " || exit 125\n" + case.script
    script_path.write_text(body, encoding="utf-8", newline="\n")
    proc = run_cmd(["wsl.exe", "--exec", "sh", windows_to_wsl_path(script_path)])
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase("exit", "exit-trap-runs", "trap 'printf exit' EXIT\n:"),
        MatrixCase("exit", "exit-trap-sees-last-status", "trap 'printf <%s> \"$?\"' EXIT\nfalse"),
        MatrixCase("exit", "exit-trap-controls-status", "trap 'exit 7' EXIT\n:"),
        MatrixCase("exit", "exit-trap-after-explicit-exit", "trap 'printf done' EXIT\nexit 3"),
        MatrixCase("exit", "exit-trap-reset", "trap 'printf bad' EXIT\ntrap - EXIT\n:"),
        MatrixCase("exit", "exit-zero-alias-reset-by-exit", "trap 'printf bad' 0\ntrap - EXIT\n:"),
        MatrixCase("exit", "exit-exit-alias-reset-by-zero", "trap 'printf bad' EXIT\ntrap - 0\n:"),
        MatrixCase("exit", "exit-trap-ignored", "trap '' EXIT\n:"),
        MatrixCase("exit", "exit-zero-ignore", "trap '' 0\n:"),
        MatrixCase("exit", "exit-trap-colon-preserves-status", "trap ':' EXIT\nfalse"),
        MatrixCase("exit", "exit-trap-return-preserves-status", "trap 'return 7' EXIT\nfalse"),
        MatrixCase("exit", "exit-trap-return-aborts-action", "trap 'return 7; printf bad' EXIT\n:"),
        MatrixCase("listing", "trap-lists-action", "trap 'printf x' INT\ntrap"),
        MatrixCase("listing", "trap-numeric-canonical-list", "trap 'printf x' 2\ntrap"),
        MatrixCase("listing", "trap-zero-canonical-list", "trap 'printf x' 0\ntrap"),
        MatrixCase("listing", "trap-reset-removes-action", "trap 'printf x' INT\ntrap - INT\ntrap"),
        MatrixCase("listing", "trap-ignore-lists-empty-action", "trap '' TERM\ntrap"),
        MatrixCase("listing", "trap-double-dash-action", "trap -- 'printf x' TERM\ntrap"),
        MatrixCase("listing", "trap-omitted-action-resets", "trap 'printf x' TERM\ntrap TERM\ntrap"),
        MatrixCase("listing", "trap-multi-signal-list", "trap 'printf x' INT TERM\ntrap"),
        MatrixCase("listing", "trap-multi-signal-reset-one", "trap 'printf x' INT TERM\ntrap - INT\ntrap"),
        MatrixCase("listing", "trap-multi-signal-reset-all", "trap 'printf x' INT TERM\ntrap - INT TERM\ntrap"),
        MatrixCase("listing", "trap-numeric-reset-by-name", "trap 'printf x' 15\ntrap - TERM\ntrap"),
        MatrixCase("listing", "trap-name-reset-by-numeric", "trap 'printf x' TERM\ntrap - 15\ntrap"),
        MatrixCase("listing", "trap-empty-multiple-list", "trap '' INT TERM\ntrap"),
        MatrixCase("listing", "trap-empty-multiple-reset-one", "trap '' INT TERM\ntrap - INT\ntrap"),
        MatrixCase("listing", "trap-reset-two-keeps-third", "trap 'printf x' HUP INT TERM\ntrap - HUP INT\ntrap"),
        MatrixCase("self-signal", "trapped-term-continues", "trap 'printf T' TERM\nkill -TERM $$\nprintf done"),
        MatrixCase("self-signal", "trapped-int-continues", "trap 'printf I' INT\nkill -INT $$\nprintf done"),
        MatrixCase("self-signal", "trapped-hup-continues", "trap 'printf H' HUP\nkill -HUP $$\nprintf done"),
        MatrixCase("self-signal", "trapped-quit-continues", "trap 'printf Q' QUIT\nkill -QUIT $$\nprintf done"),
        MatrixCase("self-signal", "trapped-usr2-continues", "trap 'printf U' USR2\nkill -USR2 $$\nprintf done"),
        MatrixCase("self-signal", "numeric-trapped-int", "trap 'printf N' 2\nkill -INT $$\nprintf done"),
        MatrixCase("self-signal", "ignored-term-continues", "trap '' TERM\nkill -TERM $$\nprintf done"),
        MatrixCase("self-signal", "trap-action-sees-status", "trap 'printf <%s> \"$?\"' TERM\nfalse\nkill -TERM $$\nprintf <%s> \"$?\""),
        MatrixCase("self-signal", "trap-action-exit-controls", "trap 'exit 6' TERM\nkill -TERM $$\nprintf bad"),
        MatrixCase("self-signal", "kill-s-term-triggers-trap", "trap 'printf T' TERM\nkill -s TERM $$\nprintf done"),
        MatrixCase("self-signal", "kill-dash-term-triggers-trap", "trap 'printf T' TERM\nkill -TERM $$\nprintf done"),
        MatrixCase("self-signal", "kill-dash-number-two-triggers-trap", "trap 'printf I' INT\nkill -2 $$\nprintf done"),
        MatrixCase("self-signal", "kill-numeric-term-triggers-trap", "trap 'printf T' TERM\nkill -15 $$\nprintf done"),
        MatrixCase("self-signal", "two-trapped-terms-run-twice", "trap 'printf T' TERM\nkill -TERM $$\nkill -TERM $$\nprintf done"),
        MatrixCase("self-signal", "trap-action-reset-itself", "trap 'trap - TERM; printf A' TERM\nkill -TERM $$\nprintf B"),
        MatrixCase("self-signal", "default-term-exits", "kill -TERM $$\nprintf bad", compare_status=False),
        MatrixCase("self-signal", "reset-term-default-exits", "trap 'printf bad' TERM\ntrap - TERM\nkill -TERM $$\nprintf bad", compare_status=False),
        MatrixCase("self-signal", "kill-zero-self", "kill -0 $$\nprintf <%s> \"$?\""),
        MatrixCase("subshell", "subshell-exit-trap-does-not-affect-parent", "trap 'printf P' EXIT\n(trap 'printf S' EXIT)\nprintf M"),
        MatrixCase("subshell", "subshell-term-trap-is-local", "trap 'printf P' TERM\n(trap 'printf S' TERM; kill -TERM $$)\nkill -TERM $$"),
        MatrixCase("subshell", "subshell-ignored-trap-local", "trap 'printf P' TERM\n(trap '' TERM; kill -TERM $$; printf S)\nkill -TERM $$"),
        MatrixCase("pipeline", "pipeline-trap-action-reset", "trap 'printf P' TERM\nprintf x | { trap - TERM; trap; }\nkill -TERM $$"),
        MatrixCase("pipeline", "pipeline-ignored-trap-reset", "trap '' TERM\nprintf x | { trap; }\nprintf done"),
        MatrixCase("pipeline", "pipeline-exit-trap-preserved", "trap 'printf P' EXIT\nprintf x | { read X; trap 'printf S' EXIT; }\nprintf M"),
        MatrixCase("command", "command-trap-mutates", "command trap 'printf C' TERM\nkill -TERM $$\nprintf done"),
        MatrixCase("command", "command-kill-triggers-trap", "trap 'printf K' USR1\ncommand kill -s USR1 $$\nprintf done"),
        MatrixCase("command", "command-kill-zero", "command kill -0 $$\nprintf <%s> \"$?\""),
        MatrixCase("diagnostic", "trap-invalid-signal", "trap 'printf x' NOSUCH\nprintf after", True),
        MatrixCase("diagnostic", "trap-rejects-sig-prefix", "trap 'printf x' SIGINT\nprintf after", True),
        MatrixCase("diagnostic", "trap-invalid-option", "trap -z\nprintf after", True),
        MatrixCase("diagnostic", "kill-missing-operand", "kill\nprintf after", True),
        MatrixCase("diagnostic", "kill-bad-signal", "kill -s NOSUCH $$\nprintf after", True),
        MatrixCase("diagnostic", "kill-invalid-pid", "kill -TERM nope\nprintf after", True),
        MatrixCase("diagnostic", "kill-list-term", "kill -l 15"),
        MatrixCase("diagnostic", "kill-list-zero-invalid", "kill -l 0", True),
        MatrixCase("diagnostic", "kill-list-65-invalid", "kill -l 65", True),
        MatrixCase("diagnostic", "kill-list-99-invalid", "kill -l 99", True),
        MatrixCase("diagnostic", "kill-list-status-129", "kill -l 129"),
        MatrixCase("diagnostic", "kill-list-status-130", "kill -l 130"),
        MatrixCase("diagnostic", "kill-list-status-143", "kill -l 143"),
        MatrixCase("diagnostic", "kill-list-status-192", "kill -l 192"),
        MatrixCase("diagnostic", "kill-list-rtmax", "kill -l 64"),
        MatrixCase("background", "wait-true-status", "true &\npid=$!\nwait $pid\nprintf <%s> \"$?\""),
        MatrixCase("background", "wait-false-status", "false &\npid=$!\nwait $pid\nprintf <%s> \"$?\""),
        MatrixCase("background", "wait-all-status", "false &\ntrue &\nwait\nprintf <%s> \"$?\""),
    ]


def run_reference_sh(case: MatrixCase, cwd: Path, reference_shell: str) -> RunResult:
    if reference_shell == "wsl-sh":
        return run_wsl_sh(case, cwd)
    proc = run_local_reference_shell(reference_shell, cwd, case.script, RUN_TIMEOUT_SECONDS)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if case.compare_status and msh_result.status != ref.status:
        return False
    if msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(ref.stderr):
        return False
    return True


def run_case(msh: Path, case: MatrixCase, root: Path, reference_shell: str) -> dict[str, object]:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{case.group}-{case.name}")
    case_root = root / safe
    msh_dir = case_root / "msh"
    ref_dir = case_root / reference_shell
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_dir.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir)
    ref = run_reference_sh(case, ref_dir, reference_shell)
    match = rows_match(case, msh_result, ref)
    return {
        "group": case.group,
        "name": case.name,
        "script": case.script,
        "compare_stderr": case.compare_stderr,
        "compare_status": case.compare_status,
        "matches": match,
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
            "normalized_stderr": normalize_stderr(msh_result.stderr),
        },
        "reference_shell": reference_shell,
        "wsl_sh": {
            "status": ref.status,
            "stdout": ref.stdout,
            "stderr": ref.stderr,
            "normalized_stderr": normalize_stderr(ref.stderr),
        },
    }


def write_json(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")


def write_markdown(path: Path, rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    groups: dict[str, tuple[int, int]] = {}
    for row in rows:
        key = str(row["group"])
        done, count = groups.get(key, (0, 0))
        groups[key] = (done + (1 if row["matches"] is True else 0), count + 1)
    lines = [
        "# msh Signal/Trap Matrix",
        "",
        "Generated by `msh_signal_trap_matrix.py` against WSL `/bin/sh`.",
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
        lines.append("No mismatches.")
        lines.append("")
    for row in mismatches:
        msh = row["msh"]
        ref = row["wsl_sh"]
        lines.extend([
            f"### {row['group']}/{row['name']}",
            "",
            "```sh",
            str(row["script"]).rstrip(),
            "```",
            "",
            f"- msh: status `{msh['status']}`, stdout `{msh['stdout']!r}`, stderr `{msh['normalized_stderr']!r}`",
            f"- wsl-sh: status `{ref['status']}`, stdout `{ref['stdout']!r}`, stderr `{ref['normalized_stderr']!r}`",
            "",
        ])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_summary(rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh signal/trap matrix: {matches}/{total} match wsl-sh")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["wsl_sh"]
        print(f"- {row['group']}/{row['name']}")
        print(f"  script: {row['script']!r}")
        print(f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}")
        print(f"  sh:  status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the msh signal/trap matrix.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--reference-shell", choices=local_reference_shell_names(), default="wsl-sh")
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-signal-trap-matrix-") as raw:
        root = Path(raw)
        rows = [run_case(msh, case, root, args.reference_shell) for case in matrix_cases()]
    write_json(args.json_report, rows)
    write_markdown(args.report, rows)
    print_summary(rows)
    if args.strict and any(row["matches"] is not True for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
