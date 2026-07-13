#!/usr/bin/env python3
"""Generated matrix runners for the msh finish-line gate."""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

from msh_tool_process import run_tool_cmd


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_COMMAND_TIMEOUT_SECONDS = 300


@dataclass
class CommandResult:
    name: str
    command: list[str]
    status: int
    stdout: str
    stderr: str


@dataclass
class MatrixSummary:
    ok: bool
    matches: int
    total: int


MATRIX_TOOLS = {
    "special-builtin": (
        MSH_DIR / "tools" / "msh_special_builtin_matrix.py",
        "msh-special-builtin-matrix.json",
        "msh-special-builtin-matrix.md",
        "msh-special-builtin-matrix-current.txt",
    ),
    "command-search": (
        MSH_DIR / "tools" / "msh_command_search_matrix.py",
        "msh-command-search-matrix.json",
        "msh-command-search-matrix.md",
        "msh-command-search-matrix-current.txt",
    ),
    "fd-process": (
        MSH_DIR / "tools" / "msh_fd_process_matrix.py",
        "msh-fd-process-matrix.json",
        "msh-fd-process-matrix.md",
        "msh-fd-process-matrix-current.txt",
    ),
    "issue8-fd": (
        MSH_DIR / "tools" / "msh_issue8_fd_matrix.py",
        "msh-issue8-fd-matrix.json",
        "msh-issue8-fd-matrix.md",
        "msh-issue8-fd-matrix-current.txt",
    ),
    "signal-trap": (
        MSH_DIR / "tools" / "msh_signal_trap_matrix.py",
        "msh-signal-trap-matrix.json",
        "msh-signal-trap-matrix.md",
        "msh-signal-trap-matrix-current.txt",
    ),
    "regular-builtin": (
        MSH_DIR / "tools" / "msh_regular_builtin_matrix.py",
        "msh-regular-builtin-matrix.json",
        "msh-regular-builtin-matrix.md",
        "msh-regular-builtin-matrix-current.txt",
    ),
}


def command_timeout_seconds() -> int:
    raw = os.environ.get("MSH_FINISH_COMMAND_TIMEOUT_SECONDS", "")
    if not raw:
        return DEFAULT_COMMAND_TIMEOUT_SECONDS
    try:
        value = int(raw)
    except ValueError:
        return DEFAULT_COMMAND_TIMEOUT_SECONDS
    return value if value > 0 else DEFAULT_COMMAND_TIMEOUT_SECONDS


def run_command(name: str, command: list[str]) -> CommandResult:
    proc = run_tool_cmd(
        command,
        MIXTAR_ROOT,
        timeout=command_timeout_seconds(),
        label=name,
        tee_stderr=True,
    )
    return CommandResult(name, command, proc.returncode, proc.stdout, proc.stderr)


def combined_output(result: CommandResult) -> str:
    text = result.stdout
    if result.stderr:
        if text and not text.endswith("\n"):
            text += "\n"
        text += result.stderr
    return text


def save_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def summarize_matrix_rows(result: CommandResult, json_path: Path) -> MatrixSummary:
    if not json_path.exists():
        return MatrixSummary(False, 0, 0)
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        rows = []
    total = len(rows)
    matches = sum(
        1 for row in rows if isinstance(row, dict) and row.get("matches") is True
    )
    return MatrixSummary(result.status == 0 and total > 0 and matches == total, matches, total)


def run_matrix(
    matrix_name: str, msh: Path, reference_shell: str = "wsl-sh"
) -> tuple[CommandResult, MatrixSummary]:
    tool, json_name, report_name, current_name = MATRIX_TOOLS[matrix_name]
    json_path = REPORT_DIR / json_name
    report_path = REPORT_DIR / report_name
    command = [
        sys.executable,
        str(tool),
        "--msh",
        str(msh),
        "--strict",
        "--json-report",
        str(json_path),
        "--report",
        str(report_path),
        "--reference-shell",
        reference_shell,
    ]
    if matrix_name == "special-builtin":
        command.append("--progress")
    result = run_command(current_name, command)
    save_text(REPORT_DIR / current_name, combined_output(result))
    return result, summarize_matrix_rows(result, json_path)


def run_special_builtin_matrix(
    msh: Path, reference_shell: str = "wsl-sh"
) -> tuple[CommandResult, MatrixSummary]:
    return run_matrix("special-builtin", msh, reference_shell)


def run_command_search_matrix(
    msh: Path, reference_shell: str = "wsl-sh"
) -> tuple[CommandResult, MatrixSummary]:
    return run_matrix("command-search", msh, reference_shell)


def run_fd_process_matrix(
    msh: Path, reference_shell: str = "wsl-sh"
) -> tuple[CommandResult, MatrixSummary]:
    return run_matrix("fd-process", msh, reference_shell)


def run_issue8_fd_matrix(
    msh: Path, reference_shell: str = "wsl-bash-posix"
) -> tuple[CommandResult, MatrixSummary]:
    return run_matrix("issue8-fd", msh, reference_shell)


def run_signal_trap_matrix(
    msh: Path, reference_shell: str = "wsl-sh"
) -> tuple[CommandResult, MatrixSummary]:
    return run_matrix("signal-trap", msh, reference_shell)


def run_regular_builtin_matrix(
    msh: Path, reference_shell: str = "wsl-sh"
) -> tuple[CommandResult, MatrixSummary]:
    return run_matrix("regular-builtin", msh, reference_shell)
