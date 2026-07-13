#!/usr/bin/env python3
"""Refresh and report the current msh profile gates."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from msh_tool_process import run_tool_cmd
from msh_finish_matrices import (
    MatrixSummary,
    run_command_search_matrix,
    run_fd_process_matrix,
    run_issue8_fd_matrix,
    run_regular_builtin_matrix,
    run_signal_trap_matrix,
    run_special_builtin_matrix,
)


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_AILANG_ROOT = MIXTAR_ROOT.parent / "AILang-Pure"
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_LINUX_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli"
MSH_SOURCE = MSH_DIR / "msh_cli.ail"
DIFF_TOOL = MSH_DIR / "tools" / "msh_shell_diff.py"
POSIX_SUITE_TOOL = MSH_DIR / "tools" / "msh_posix_suite.py"
POSIX_STRESS_SUITE = MSH_DIR / "suites" / "posix-stress"
POSIX_EXTERNAL_SEED_SUITE = MSH_DIR / "suites" / "posix-external-seed"
POSIX_EXTERNAL_SMOOSH_SUITE = MSH_DIR / "suites" / "posix-external-smoosh"
POSIX_EXTERNAL_SMOOSH_TOOLS_SUITE = MSH_DIR / "suites" / "posix-external-smoosh-tools"
DEFAULT_USERLAND_TOOL_PATH = MIXTAR_ROOT / "Server" / "Userland" / "Generated" / "targets" / "linux-x64" / "bin"
SEMANTIC_TOOL = MSH_DIR / "tools" / "msh_semantic_probe.py"
BLOCKER_TOOL = MSH_DIR / "tools" / "msh_blocker_probe.py"
REAL_EXEC_TOOL = MSH_DIR / "tools" / "msh_real_exec_probe.py"
COMMAND_SEARCH_TOOL = MSH_DIR / "tools" / "msh_command_search_probe.py"
INVOCATION_TOOL = MSH_DIR / "tools" / "msh_invocation_probe.py"
LINUX_COMMAND_SEARCH_TOOL = MSH_DIR / "tools" / "msh_linux_command_search_probe.py"
LINUX_COMMAND_SEARCH_MATRIX_TOOL = MSH_DIR / "tools" / "msh_linux_command_search_matrix.py"
LINUX_REDIRECTION_MATRIX_TOOL = MSH_DIR / "tools" / "msh_linux_redirection_matrix.py"
LINUX_ARBITRARY_FD_MATRIX_TOOL = MSH_DIR / "tools" / "msh_linux_arbitrary_fd_matrix.py"
LINUX_SIGNAL_WAIT_MATRIX_TOOL = MSH_DIR / "tools" / "msh_linux_signal_wait_matrix.py"
LINUX_TEST_PREDICATE_TOOL = MSH_DIR / "tools" / "msh_linux_test_predicate_probe.py"
LINUX_PRINTF_BYTE_TOOL = MSH_DIR / "tools" / "msh_linux_printf_byte_probe.py"
LINUX_JOB_CONTROL_TOOL = MSH_DIR / "tools" / "msh_job_control_probe.py"
LINUX_FD_GRAPH_TOOL = MSH_DIR / "tools" / "msh_linux_fd_graph_probe.py"
LINUX_INTERACTIVE_TOOL = MSH_DIR / "tools" / "msh_interactive_probe.py"
COMMAND_SEARCH_MATRIX_TOOL = MSH_DIR / "tools" / "msh_command_search_matrix.py"
FD_PROCESS_MATRIX_TOOL = MSH_DIR / "tools" / "msh_fd_process_matrix.py"
ISSUE8_FD_MATRIX_TOOL = MSH_DIR / "tools" / "msh_issue8_fd_matrix.py"
SIGNAL_TRAP_MATRIX_TOOL = MSH_DIR / "tools" / "msh_signal_trap_matrix.py"
REGULAR_MATRIX_TOOL = MSH_DIR / "tools" / "msh_regular_builtin_matrix.py"
SPECIAL_MATRIX_TOOL = MSH_DIR / "tools" / "msh_special_builtin_matrix.py"
DEFAULT_COMMAND_TIMEOUT_SECONDS = 300
DEFAULT_MAX_SECONDS = 1800
WSL_PREFLIGHT_TIMEOUT_SECONDS = 5
DEFAULT_TRACE_HEARTBEAT_SECONDS = "15"
FINISH_WALL_DEADLINE = 0.0
FINISH_BASE_COMMAND_TIMEOUT = DEFAULT_COMMAND_TIMEOUT_SECONDS
LOCAL_REFERENCE_SHELLS = (
    ("msys-dash", Path(r"C:\msys64\usr\bin\dash.exe")),
    ("git-dash", Path(r"C:\Program Files\Git\usr\bin\dash.exe")),
    ("git-sh", Path(r"C:\Program Files\Git\bin\sh.exe")),
)


@dataclass
class CommandResult:
    name: str
    command: list[str]
    status: int
    stdout: str
    stderr: str


@dataclass
class ShellDiff:
    total: int
    available: int
    matches: int


@dataclass
class SemanticSummary:
    ok: bool
    parser: int
    status: int
    output: int
    diagnostic: int
    state: int
    redirection_only: int


@dataclass
class BlockerSummary:
    ok: bool
    closed: int
    open: int


def finish_command_timeout_seconds() -> int:
    raw = os.environ.get("MSH_FINISH_COMMAND_TIMEOUT_SECONDS", "")
    if not raw:
        return DEFAULT_COMMAND_TIMEOUT_SECONDS
    try:
        value = int(raw)
    except ValueError:
        return DEFAULT_COMMAND_TIMEOUT_SECONDS
    return value if value > 0 else DEFAULT_COMMAND_TIMEOUT_SECONDS


def finish_wall_remaining_seconds(default: int) -> int:
    if FINISH_WALL_DEADLINE <= 0:
        return default
    remaining = FINISH_WALL_DEADLINE - time.monotonic()
    if remaining <= 0:
        return 1
    bounded = int(remaining)
    if bounded <= 0:
        bounded = 1
    return min(default, bounded)


def finish_current_child_timeout_seconds() -> int:
    return finish_wall_remaining_seconds(FINISH_BASE_COMMAND_TIMEOUT)


def finish_refresh_child_timeout_env() -> None:
    os.environ["MSH_FINISH_COMMAND_TIMEOUT_SECONDS"] = str(finish_current_child_timeout_seconds())


def finish_wall_check(stage: str) -> None:
    if FINISH_WALL_DEADLINE <= 0:
        return
    if time.monotonic() < FINISH_WALL_DEADLINE:
        return
    print(f"msh finish-line: wall-clock limit reached before {stage}", file=sys.stderr)
    raise SystemExit(124)


def run_command(name: str, command: list[str], env: dict[str, str] | None = None) -> CommandResult:
    return run_command_in(name, command, MIXTAR_ROOT, env)


def run_command_in(
    name: str,
    command: list[str],
    cwd: Path,
    env: dict[str, str] | None = None,
) -> CommandResult:
    run_env = finish_tool_env(env)
    proc = run_tool_cmd(
        command,
        cwd,
        run_env,
        timeout=finish_current_child_timeout_seconds(),
        label=name,
        tee_stderr=True,
    )
    return CommandResult(name, command, proc.returncode, proc.stdout, proc.stderr)


def combined_output(result: CommandResult) -> str:
    if result.stderr.strip():
        return result.stdout + ("\n" if result.stdout and not result.stdout.endswith("\n") else "") + result.stderr
    return result.stdout


def save_text(path: Path, text: str) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def finish_tool_env(env: dict[str, str] | None = None) -> dict[str, str]:
    result = dict(env) if env is not None else {}
    result.setdefault("MSH_TOOL_TRACE", os.environ.get("MSH_TOOL_TRACE", "1"))
    result.setdefault(
        "MSH_TOOL_HEARTBEAT_SECONDS",
        os.environ.get("MSH_TOOL_HEARTBEAT_SECONDS", DEFAULT_TRACE_HEARTBEAT_SECONDS),
    )
    return result


def announce_step(text: str) -> None:
    finish_wall_check(text)
    finish_refresh_child_timeout_env()
    print(f"[msh-finish] {text}", flush=True)


def run_wsl_preflight() -> CommandResult:
    command = ["wsl.exe", "--exec", "sh", "-c", "echo ok"]
    proc = run_tool_cmd(
        command,
        MIXTAR_ROOT,
        env=finish_tool_env(),
        timeout=finish_wall_remaining_seconds(WSL_PREFLIGHT_TIMEOUT_SECONDS),
    )
    result = CommandResult("msh-wsl-preflight.txt", command, proc.returncode, proc.stdout, proc.stderr)
    save_text(REPORT_DIR / "msh-wsl-preflight.txt", combined_output(result))
    return result


def wsl_preflight_ok(result: CommandResult) -> bool:
    return result.status == 0 and result.stdout == "ok\n"


def local_reference_shell() -> str:
    for name, path in LOCAL_REFERENCE_SHELLS:
        if path.exists():
            return name
    return ""


def local_reference_args(shell_name: str, include_extensions: bool = False, compare_stderr: bool = False) -> list[str]:
    args = [
        "--baseline-only",
        "--include-local-shells",
        "--no-wsl-shells",
        "--strict-shell",
        shell_name,
    ]
    if include_extensions:
        args.append("--include-extensions")
    if compare_stderr:
        args.append("--compare-stderr")
    return args


def local_suite_reference_args(shell_name: str) -> list[str]:
    return [
        "--include-local-shells",
        "--no-wsl-shells",
        "--strict-shell",
        shell_name,
    ]


def ailang_root_from_args(raw_root: str | None) -> Path:
    if raw_root:
        return Path(raw_root).resolve()
    env_root = os.environ.get("AILANG_ROOT")
    if env_root:
        return Path(env_root).resolve()
    return DEFAULT_AILANG_ROOT.resolve()


def sh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\"'\"'") + "'"


def to_wsl_path(path: Path) -> str:
    original = path.as_posix()
    if re.match(r"^/mnt/[A-Za-z]/", original):
        return original
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    raw = resolved.as_posix()
    if drive and raw[1:3] == ":/":
        return f"/mnt/{drive}{raw[2:]}"
    return raw


def preserve_wsl_path_or_resolve(path: Path) -> Path:
    if re.match(r"^/mnt/[A-Za-z]/", path.as_posix()):
        return path
    return path.resolve()


def run_source_build(msh: Path, ailang_root: Path) -> list[CommandResult]:
    compiler = ailang_root / "ailang.py"
    check = run_command_in(
        "msh-build-check.txt",
        [sys.executable, str(compiler), str(MSH_SOURCE), "--check"],
        ailang_root,
    )
    save_text(REPORT_DIR / "msh-build-check.txt", combined_output(check))
    if check.status != 0:
        return [check]
    msh.parent.mkdir(parents=True, exist_ok=True)
    build = run_command_in(
        "msh-build-current.txt",
        [sys.executable, str(compiler), str(MSH_SOURCE), "--backend=c", "-O2", "-o", str(msh)],
        ailang_root,
    )
    save_text(REPORT_DIR / "msh-build-current.txt", combined_output(build))
    return [check, build]


def run_wsl_source_build(linux_msh: Path, ailang_root: Path) -> CommandResult:
    command_text = (
        f"cd {sh_quote(to_wsl_path(ailang_root))} && "
        f"python3 ailang.py {sh_quote(to_wsl_path(MSH_SOURCE))} "
        f"--backend=c -O2 -o {sh_quote(to_wsl_path(linux_msh))}"
    )
    result = run_command_in(
        "msh-build-linux-current.txt",
        ["wsl.exe", "--exec", "sh", "-c", command_text],
        ailang_root,
    )
    save_text(REPORT_DIR / "msh-build-linux-current.txt", combined_output(result))
    return result


def run_shell_diff(msh: Path, extra_args: list[str], report_name: str) -> tuple[CommandResult, list[dict[str, object]]]:
    command = [sys.executable, str(DIFF_TOOL), "--msh", str(msh), "--json", "--progress", *extra_args]
    result = run_command(report_name, command)
    save_text(REPORT_DIR / report_name, result.stdout)
    if result.status != 0:
        return result, []
    try:
        rows = json.loads(result.stdout)
    except json.JSONDecodeError:
        rows = []
    return result, rows


def run_posix_suite(msh: Path, extra_args: list[str] | None = None) -> tuple[CommandResult, list[dict[str, object]]]:
    json_path = REPORT_DIR / "msh-posix-suite-current.json"
    report_path = REPORT_DIR / "msh-posix-suite-current.md"
    command = [
        sys.executable,
        str(POSIX_SUITE_TOOL),
        "--msh",
        str(msh),
        "--strict",
        "--baseline-only",
        "--progress",
        *(extra_args or []),
        "--json-report",
        str(json_path),
        "--report",
        str(report_path),
    ]
    result = run_command("msh-posix-suite-current.txt", command)
    save_text(REPORT_DIR / "msh-posix-suite-current.txt", combined_output(result))
    if not json_path.exists():
        return result, []
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        rows = []
    return result, rows


def run_posix_stress_suite(msh: Path, extra_args: list[str] | None = None) -> tuple[CommandResult, list[dict[str, object]]]:
    json_path = REPORT_DIR / "msh-posix-stress-suite.json"
    report_path = REPORT_DIR / "msh-posix-stress-suite.md"
    command = [
        sys.executable,
        str(POSIX_SUITE_TOOL),
        "--msh",
        str(msh),
        "--suite",
        str(POSIX_STRESS_SUITE),
        "--strict",
        "--baseline-only",
        "--progress",
        *(extra_args or []),
        "--json-report",
        str(json_path),
        "--report",
        str(report_path),
    ]
    result = run_command("msh-posix-stress-suite-current.txt", command)
    save_text(REPORT_DIR / "msh-posix-stress-suite-current.txt", combined_output(result))
    if not json_path.exists():
        return result, []
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        rows = []
    return result, rows


def run_posix_external_seed_suite(msh: Path, extra_args: list[str] | None = None) -> tuple[CommandResult, list[dict[str, object]]]:
    json_path = REPORT_DIR / "msh-posix-external-seed-suite.json"
    report_path = REPORT_DIR / "msh-posix-external-seed-suite.md"
    command = [
        sys.executable,
        str(POSIX_SUITE_TOOL),
        "--msh",
        str(msh),
        "--suite",
        str(POSIX_EXTERNAL_SEED_SUITE),
        "--strict",
        "--baseline-only",
        "--progress",
        *(extra_args or []),
        "--json-report",
        str(json_path),
        "--report",
        str(report_path),
    ]
    result = run_command("msh-posix-external-seed-suite-current.txt", command)
    save_text(REPORT_DIR / "msh-posix-external-seed-suite-current.txt", combined_output(result))
    if not json_path.exists():
        return result, []
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        rows = []
    return result, rows


def run_posix_external_smoosh_suite(msh: Path, extra_args: list[str] | None = None) -> tuple[CommandResult, list[dict[str, object]]]:
    json_path = REPORT_DIR / "msh-posix-external-smoosh-suite.json"
    report_path = REPORT_DIR / "msh-posix-external-smoosh-suite.md"
    command = [
        sys.executable,
        str(POSIX_SUITE_TOOL),
        "--msh",
        str(msh),
        "--suite",
        str(POSIX_EXTERNAL_SMOOSH_SUITE),
        "--strict",
        "--baseline-only",
        "--progress",
        *(extra_args or []),
        "--json-report",
        str(json_path),
        "--report",
        str(report_path),
    ]
    result = run_command("msh-posix-external-smoosh-suite-current.txt", command)
    save_text(REPORT_DIR / "msh-posix-external-smoosh-suite-current.txt", combined_output(result))
    if not json_path.exists():
        return result, []
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        rows = []
    return result, rows


def run_posix_external_smoosh_tools_suite(msh: Path) -> tuple[CommandResult, list[dict[str, object]]]:
    json_path = REPORT_DIR / "msh-posix-external-smoosh-tools-suite.json"
    report_path = REPORT_DIR / "msh-posix-external-smoosh-tools-suite.md"
    command = [
        sys.executable,
        str(POSIX_SUITE_TOOL),
        "--msh",
        str(msh),
        "--msh-wsl",
        "--msh-tool-path",
        str(DEFAULT_USERLAND_TOOL_PATH),
        "--suite",
        str(POSIX_EXTERNAL_SMOOSH_TOOLS_SUITE),
        "--strict",
        "--baseline-only",
        "--progress",
        "--json-report",
        str(json_path),
        "--report",
        str(report_path),
    ]
    result = run_command("msh-posix-external-smoosh-tools-suite-current.txt", command)
    save_text(REPORT_DIR / "msh-posix-external-smoosh-tools-suite-current.txt", combined_output(result))
    if not json_path.exists():
        return result, []
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        rows = []
    return result, rows


def summarize_diff(rows: list[dict[str, object]], shell_name: str = "wsl-sh") -> ShellDiff:
    total = len(rows)
    available = 0
    matches = 0
    for row in rows:
        shells = row.get("shells", {})
        shell = shells.get(shell_name, {}) if isinstance(shells, dict) else {}
        if not isinstance(shell, dict):
            continue
        if shell.get("available") is True:
            available += 1
            if shell.get("matches_msh") is True:
                matches += 1
    return ShellDiff(total, available, matches)


def extract_count(pattern: str, text: str) -> int:
    match = re.search(pattern, text)
    if not match:
        return 0
    return int(match.group(1))


def run_semantic(msh: Path, no_wsl: bool) -> tuple[CommandResult, SemanticSummary]:
    command = [sys.executable, str(SEMANTIC_TOOL), "--msh", str(msh)]
    if no_wsl:
        command.append("--no-wsl")
    result = run_command("msh-semantic-current.txt", command)
    text = combined_output(result)
    save_text(REPORT_DIR / "msh-semantic-current.txt", text)
    summary = SemanticSummary(
        ok=result.status == 0 and "msh semantic probe: ok" in text,
        parser=extract_count(r"parser cases: (\d+)", text),
        status=extract_count(r"status cases: (\d+)", text),
        output=extract_count(r"output cases: (\d+)", text),
        diagnostic=extract_count(r"diagnostic cases: (\d+)", text),
        state=extract_count(r"state cases: (\d+)", text),
        redirection_only=extract_count(r"redirection-only cases: (\d+)", text),
    )
    return result, summary


def run_blockers(msh: Path, no_wsl: bool) -> tuple[CommandResult, BlockerSummary]:
    command = [sys.executable, str(BLOCKER_TOOL), "--msh", str(msh), "--strict"]
    if no_wsl:
        command.append("--no-wsl")
    result = run_command("msh-blockers-current.txt", command)
    text = combined_output(result)
    save_text(REPORT_DIR / "msh-blockers-current.txt", text)
    match = re.search(r"msh blocker probe: (\d+) closed, (\d+) open", text)
    closed = int(match.group(1)) if match else 0
    open_count = int(match.group(2)) if match else 0
    return result, BlockerSummary(result.status == 0 and open_count == 0, closed, open_count)


def run_leak_selftest(msh: Path) -> CommandResult:
    result = run_command("msh-leak-current.txt", [str(msh), "selftest-leak"], {"AILANG_LEAK_REPORT": "1"})
    save_text(REPORT_DIR / "msh-leak-current.txt", combined_output(result))
    return result


def run_real_exec_probe(msh: Path) -> CommandResult:
    result = run_command("msh-real-exec-current.txt", [sys.executable, str(REAL_EXEC_TOOL), "--msh", str(msh)])
    save_text(REPORT_DIR / "msh-real-exec-current.txt", combined_output(result))
    return result


def run_command_search_probe(msh: Path) -> CommandResult:
    result = run_command("msh-command-search-current.txt", [sys.executable, str(COMMAND_SEARCH_TOOL), "--msh", str(msh)])
    save_text(REPORT_DIR / "msh-command-search-current.txt", combined_output(result))
    return result


def run_invocation_probe(msh: Path) -> CommandResult:
    result = run_command("msh-invocation-current.txt", [sys.executable, str(INVOCATION_TOOL), "--msh", str(msh)])
    save_text(REPORT_DIR / "msh-invocation-current.txt", combined_output(result))
    return result


def run_linux_command_search_probe(linux_msh: Path) -> CommandResult:
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(LINUX_COMMAND_SEARCH_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
    ]
    result = run_command("msh-linux-command-search-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-command-search-current.txt", combined_output(result))
    return result


def run_linux_command_search_matrix(linux_msh: Path) -> tuple[CommandResult, MatrixSummary]:
    json_path = REPORT_DIR / "msh-linux-command-search-matrix.json"
    report_path = REPORT_DIR / "msh-linux-command-search-matrix.md"
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(LINUX_COMMAND_SEARCH_MATRIX_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
        "--json-report",
        to_wsl_path(json_path),
        "--report",
        to_wsl_path(report_path),
        "--progress",
        "--strict",
    ]
    result = run_command("msh-linux-command-search-matrix-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-command-search-matrix-current.txt", combined_output(result))
    if result.status != 0 or not json_path.exists():
        return result, MatrixSummary(False, 0, 0)
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return result, MatrixSummary(False, 0, 0)
    total = len(rows)
    matches = sum(1 for row in rows if row.get("matches") is True)
    return result, MatrixSummary(matches == total, matches, total)


def run_linux_redirection_matrix(linux_msh: Path) -> tuple[CommandResult, MatrixSummary]:
    json_path = REPORT_DIR / "msh-linux-redirection-matrix.json"
    report_path = REPORT_DIR / "msh-linux-redirection-matrix.md"
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(LINUX_REDIRECTION_MATRIX_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
        "--json-report",
        to_wsl_path(json_path),
        "--report",
        to_wsl_path(report_path),
        "--progress",
        "--strict",
    ]
    result = run_command("msh-linux-redirection-matrix-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-redirection-matrix-current.txt", combined_output(result))
    if result.status != 0 or not json_path.exists():
        return result, MatrixSummary(False, 0, 0)
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return result, MatrixSummary(False, 0, 0)
    total = len(rows)
    matches = sum(1 for row in rows if row.get("matches") is True)
    return result, MatrixSummary(matches == total, matches, total)


def run_linux_arbitrary_fd_matrix(linux_msh: Path) -> tuple[CommandResult, MatrixSummary]:
    json_path = REPORT_DIR / "msh-linux-arbitrary-fd-matrix.json"
    report_path = REPORT_DIR / "msh-linux-arbitrary-fd-matrix.md"
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(LINUX_ARBITRARY_FD_MATRIX_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
        "--json-report",
        to_wsl_path(json_path),
        "--report",
        to_wsl_path(report_path),
        "--progress",
        "--strict",
    ]
    result = run_command("msh-linux-arbitrary-fd-matrix-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-arbitrary-fd-matrix-current.txt", combined_output(result))
    if result.status != 0 or not json_path.exists():
        return result, MatrixSummary(False, 0, 0)
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return result, MatrixSummary(False, 0, 0)
    total = len(rows)
    matches = sum(1 for row in rows if row.get("matches") is True)
    return result, MatrixSummary(matches == total, matches, total)


def run_linux_signal_wait_matrix(linux_msh: Path) -> tuple[CommandResult, MatrixSummary]:
    json_path = REPORT_DIR / "msh-linux-signal-wait-matrix.json"
    report_path = REPORT_DIR / "msh-linux-signal-wait-matrix.md"
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(LINUX_SIGNAL_WAIT_MATRIX_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
        "--json-report",
        to_wsl_path(json_path),
        "--report",
        to_wsl_path(report_path),
        "--strict",
    ]
    result = run_command("msh-linux-signal-wait-matrix-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-signal-wait-matrix-current.txt", combined_output(result))
    if result.status != 0 or not json_path.exists():
        return result, MatrixSummary(False, 0, 0)
    try:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return result, MatrixSummary(False, 0, 0)
    total = len(rows)
    matches = sum(1 for row in rows if row.get("matches") is True)
    return result, MatrixSummary(matches == total, matches, total)


def run_linux_test_predicate_probe(linux_msh: Path) -> CommandResult:
    json_path = REPORT_DIR / "msh-linux-test-predicate.json"
    report_path = REPORT_DIR / "msh-linux-test-predicate.md"
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(LINUX_TEST_PREDICATE_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
        "--strict",
        "--json-report",
        to_wsl_path(json_path),
        "--report",
        to_wsl_path(report_path),
    ]
    result = run_command("msh-linux-test-predicate-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-test-predicate-current.txt", combined_output(result))
    return result


def run_linux_printf_byte_probe(linux_msh: Path) -> CommandResult:
    json_path = REPORT_DIR / "msh-linux-printf-byte.json"
    report_path = REPORT_DIR / "msh-linux-printf-byte.md"
    command = ["wsl.exe", "--exec", "python3", to_wsl_path(LINUX_PRINTF_BYTE_TOOL), "--msh", to_wsl_path(linux_msh), "--strict", "--json-report", to_wsl_path(json_path), "--report", to_wsl_path(report_path)]
    result = run_command("msh-linux-printf-byte-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-printf-byte-current.txt", combined_output(result))
    return result


def run_linux_job_control_probe(linux_msh: Path) -> CommandResult:
    report_path = REPORT_DIR / "msh-linux-job-control.md"
    command = ["wsl.exe", "--exec", "python3", to_wsl_path(LINUX_JOB_CONTROL_TOOL), "--msh", to_wsl_path(linux_msh), "--report", to_wsl_path(report_path)]
    result = run_command("msh-linux-job-control-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-job-control-current.txt", combined_output(result))
    return result


def run_linux_fd_graph_probe(linux_msh: Path) -> CommandResult:
    json_path = REPORT_DIR / "msh-linux-fd-graph.json"
    report_path = REPORT_DIR / "msh-linux-fd-graph.md"
    command = ["wsl.exe", "--exec", "python3", to_wsl_path(LINUX_FD_GRAPH_TOOL), "--msh", to_wsl_path(linux_msh), "--strict", "--json-report", to_wsl_path(json_path), "--report", to_wsl_path(report_path)]
    result = run_command("msh-linux-fd-graph-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-fd-graph-current.txt", combined_output(result))
    return result


def run_linux_interactive_probe(linux_msh: Path) -> CommandResult:
    report_path = REPORT_DIR / "msh-linux-interactive.md"
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(LINUX_INTERACTIVE_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
        "--report",
        to_wsl_path(report_path),
    ]
    result = run_command("msh-linux-interactive-current.txt", command)
    save_text(REPORT_DIR / "msh-linux-interactive-current.txt", combined_output(result))
    return result


def line_guard() -> tuple[bool, list[tuple[int, Path]]]:
    over: list[tuple[int, Path]] = []
    for path in MSH_DIR.glob("*.ail"):
        lines = len(path.read_text(encoding="utf-8").splitlines())
        if lines > 800:
            over.append((lines, path))
    return len(over) == 0, sorted(over, reverse=True)


def gate_text(ok: bool) -> str:
    return "PASS" if ok else "BLOCKED"


def linux_probe_state(result: CommandResult | None) -> str:
    if result is None:
        return "SKIPPED"
    return "PASS" if result.status == 0 else "FAIL"


def write_finish_report(
    build_results: list[CommandResult],
    reference_shell: str,
    reference_mode: str,
    strict: ShellDiff,
    posix_suite: ShellDiff,
    posix_stress_suite: ShellDiff,
    posix_external_seed_suite: ShellDiff,
    posix_external_smoosh_suite: ShellDiff,
    posix_external_smoosh_tools_suite: ShellDiff,
    extensions: ShellDiff,
    stderr_diff: ShellDiff,
    special_matrix: MatrixSummary,
    command_matrix: MatrixSummary,
    fd_matrix: MatrixSummary,
    issue8_fd_matrix: MatrixSummary,
    signal_matrix: MatrixSummary,
    regular_matrix: MatrixSummary,
    semantic: SemanticSummary,
    blockers: BlockerSummary,
    real_exec: CommandResult,
    command_search: CommandResult,
    invocation: CommandResult,
    linux_command_search: CommandResult | None,
    linux_command_search_matrix: MatrixSummary,
    linux_redirection_matrix: MatrixSummary,
    linux_arbitrary_fd_matrix: MatrixSummary,
    linux_signal_wait_matrix: MatrixSummary,
    linux_test_predicate: CommandResult | None,
    linux_printf_byte: CommandResult | None,
    linux_job_control: CommandResult | None,
    linux_fd_graph: CommandResult | None,
    linux_interactive: CommandResult | None,
    leak: CommandResult,
    line_ok: bool,
    over_lines: list[tuple[int, Path]],
) -> bool:
    build_ok = all(result.status == 0 for result in build_results)
    build_state = "SKIPPED"
    if build_results:
        build_state = "PASS" if build_ok else "FAIL"
    core_checks = [
        ("source rebuild", build_ok),
        ("strict shell diff", strict.total > 0 and strict.available == strict.total and strict.matches == strict.total),
        ("posix core suite", posix_suite.total > 0 and posix_suite.available == posix_suite.total and posix_suite.matches == posix_suite.total),
        ("posix stress suite", posix_stress_suite.total > 0 and posix_stress_suite.available == posix_stress_suite.total and posix_stress_suite.matches == posix_stress_suite.total),
        ("external seed suite", posix_external_seed_suite.total > 0 and posix_external_seed_suite.available == posix_external_seed_suite.total and posix_external_seed_suite.matches == posix_external_seed_suite.total),
        ("external Smoosh suite", posix_external_smoosh_suite.total > 0 and posix_external_smoosh_suite.available == posix_external_smoosh_suite.total and posix_external_smoosh_suite.matches == posix_external_smoosh_suite.total),
        ("tools-backed Smoosh suite", posix_external_smoosh_tools_suite.total > 0 and posix_external_smoosh_tools_suite.available == posix_external_smoosh_tools_suite.total and posix_external_smoosh_tools_suite.matches == posix_external_smoosh_tools_suite.total),
        ("special-builtin matrix", special_matrix.ok),
        ("command-search matrix", command_matrix.ok),
        ("fd/process matrix", fd_matrix.ok),
        ("Issue 8 fd matrix", linux_command_search is None or issue8_fd_matrix.ok),
        ("signal/trap matrix", signal_matrix.ok),
        ("regular-builtin matrix", regular_matrix.ok),
        ("semantic probe", semantic.ok),
        ("blocker probe", blockers.ok),
        ("real exec probe", real_exec.status == 0),
        ("command-search probe", command_search.status == 0),
        ("shell invocation probe", invocation.status == 0),
        ("Linux command-search probe", linux_command_search is None or linux_command_search.status == 0),
        ("Linux command-search matrix", linux_command_search is None or linux_command_search_matrix.ok),
        ("Linux redirection matrix", linux_command_search is None or linux_redirection_matrix.ok),
        ("Linux arbitrary-fd/process matrix", linux_command_search is None or linux_arbitrary_fd_matrix.ok),
        ("Linux signal/wait matrix", linux_command_search is None or linux_signal_wait_matrix.ok),
        ("Linux filesystem/profile probe", linux_test_predicate is None or linux_test_predicate.status == 0),
        ("Linux printf byte probe", linux_printf_byte is None or linux_printf_byte.status == 0),
        ("Linux job-control probe", linux_job_control is None or linux_job_control.status == 0),
        ("Linux fd graph probe", linux_fd_graph is None or linux_fd_graph.status == 0),
        ("Linux interactive pty probe", linux_interactive is None or linux_interactive.status == 0),
        ("leak selftest", leak.status == 0),
        ("line guard", line_ok),
    ]
    core_blockers = [name for name, ok in core_checks if not ok]
    core_ok = len(core_blockers) == 0
    lines = [
        "# msh Profile Gate",
        "",
        "Generated by `msh_finish_line.py`.",
        "Routine shell-diff gates use `--baseline-only`; bash/zsh comparison remains an opt-in observational run.",
        f"Current reference mode: `{reference_mode}` using `{reference_shell}`.",
        "",
        "## Gates",
        "",
        f"- `msh-core`: {gate_text(core_ok)}",
        "- `msh-posix-candidate`: BLOCKED",
        "- `/System/Shells/msh` eligibility: BLOCKED",
        "",
        "## Current Evidence",
        "",
        f"- Source rebuild: `{build_state}`",
        f"- Strict reference shell functional diff (`{reference_shell}`): `{strict.matches}/{strict.total}`",
        f"- File-based POSIX core suite: `{posix_suite.matches}/{posix_suite.total}`",
        f"- Generated POSIX stress suite: `{posix_stress_suite.matches}/{posix_stress_suite.total}`",
        f"- External-style POSIX seed suite: `{posix_external_seed_suite.matches}/{posix_external_seed_suite.total}`",
        f"- Imported Smoosh POSIX slice: `{posix_external_smoosh_suite.matches}/{posix_external_smoosh_suite.total}`",
        f"- Tools-backed broad Smoosh slice: `{posix_external_smoosh_tools_suite.matches}/{posix_external_smoosh_tools_suite.total}`",
        f"- Generated special-builtin matrix: `{special_matrix.matches}/{special_matrix.total}`",
        f"- Generated command-search matrix: `{command_matrix.matches}/{command_matrix.total}`",
        f"- Generated fd/process matrix: `{fd_matrix.matches}/{fd_matrix.total}`",
        f"- POSIX Issue 8 multi-digit fd matrix: `{issue8_fd_matrix.matches}/{issue8_fd_matrix.total}`",
        f"- Generated signal/trap matrix: `{signal_matrix.matches}/{signal_matrix.total}`",
        f"- Generated regular-builtin matrix: `{regular_matrix.matches}/{regular_matrix.total}`",
        f"- Extension-inclusive reference diff (`{reference_shell}`): `{extensions.matches}/{extensions.total}`",
        f"- Stderr-sensitive reference diff (`{reference_shell}`): `{stderr_diff.matches}/{stderr_diff.total}`",
        f"- Semantic probe: `{'PASS' if semantic.ok else 'FAIL'}`",
        f"- Semantic corpus: parser `{semantic.parser}`, status `{semantic.status}`, output `{semantic.output}`, diagnostic `{semantic.diagnostic}`, state `{semantic.state}`, redirection-only `{semantic.redirection_only}`",
        f"- Blocker probe: `{blockers.closed} closed / {blockers.open} open`",
        f"- Real exec probe: `{'PASS' if real_exec.status == 0 else 'FAIL'}`",
        f"- Command-search probe: `{'PASS' if command_search.status == 0 else 'FAIL'}`",
        f"- Shell invocation probe: `{'PASS' if invocation.status == 0 else 'FAIL'}`",
        f"- Linux-native command-search probe: `{linux_probe_state(linux_command_search)}`",
        f"- Linux-native command-search diagnostic matrix: `{linux_command_search_matrix.matches}/{linux_command_search_matrix.total}`",
        f"- Linux-native redirection diagnostic matrix: `{linux_redirection_matrix.matches}/{linux_redirection_matrix.total}`",
        f"- Linux-native arbitrary-fd/process matrix: `{linux_arbitrary_fd_matrix.matches}/{linux_arbitrary_fd_matrix.total}`",
        f"- Linux-native signal/wait matrix: `{linux_signal_wait_matrix.matches}/{linux_signal_wait_matrix.total}`",
        f"- Linux-native filesystem/profile probe: `{linux_probe_state(linux_test_predicate)}`",
        f"- Linux-native printf byte probe: `{linux_probe_state(linux_printf_byte)}`",
        f"- Linux-native job-control probe: `{linux_probe_state(linux_job_control)}`",
        f"- Linux-native fd graph probe: `{linux_probe_state(linux_fd_graph)}`",
        f"- Linux-native interactive pty probe: `{linux_probe_state(linux_interactive)}`",
        f"- Leak selftest: `{'PASS' if leak.status == 0 else 'FAIL'}`",
        f"- Line guard: `{'PASS' if line_ok else 'FAIL'}`",
    ]
    if core_blockers:
        lines.extend([
            "",
            "## Core Blocking Checks",
            "",
            *[f"- {name}" for name in core_blockers],
        ])
    lines.extend([
        "",
        "## Candidate Blockers",
        "",
        "- Broader POSIX signal semantics beyond the current Linux-native signal/wait and stopped/continued job-control probes.",
        "- External POSIX shell-language suite expansion beyond the current `posix-core`, generated `posix-stress`, external-style seed, imported Smoosh, and tools-backed broad Smoosh gates.",
        "- Exact special-builtin fatal/non-fatal matrix beyond the generated special-builtin matrix.",
        f"- Broader redirection diagnostic wording beyond the current {linux_redirection_matrix.total}-case Linux-native matrix and fd/process coverage.",
        "- Broader arbitrary-fd/process corpus beyond the hosted fd/process matrix, Linux-native fd graph probe, and generated arbitrary-fd matrix.",
        "- Broader interactive shell and terminal job-control profile beyond the current Linux-native pty probes.",
        "",
        "## Gate Interpretation",
        "",
        "`msh-core` is a checkpoint for current Mixtar boot/userland scripts.",
        "It is not a final shell finish line and it is not a complete POSIX `sh` compatibility claim.",
        "`msh-posix-candidate` remains the next serious target: close exact error matrices, process/fd inheritance, broader signal/job-control semantics, and expand the file-based/generated/imported POSIX suites into a conformance-sized corpus.",
        "",
    ])
    failed_builds = [result for result in build_results if result.status != 0]
    if failed_builds:
        lines.extend(["## Build Failures", ""])
        for result in failed_builds:
            lines.extend(
                [
                    f"### {result.name}",
                    "",
                    "```text",
                    " ".join(result.command),
                    "```",
                    "",
                ]
            )
            output = combined_output(result).rstrip()
            if output:
                lines.extend(["```text", output, "```", ""])
    if over_lines:
        lines.extend(["## Files Over 800 Lines", ""])
        for count, path in over_lines:
            lines.append(f"- `{count}` lines: `{path}`")
        lines.append("")
    path = REPORT_DIR / "msh-finish-line.md"
    save_text(path, "\n".join(lines))
    print(f"msh profile gate: msh-core {gate_text(core_ok)}")
    if core_blockers:
        print("core blockers: " + ", ".join(core_blockers))
    print(f"source rebuild: {build_state}")
    print(f"strict {reference_shell}: {strict.matches}/{strict.total}")
    print(f"posix suite: {posix_suite.matches}/{posix_suite.total}")
    print(f"posix stress suite: {posix_stress_suite.matches}/{posix_stress_suite.total}")
    print(f"posix external seed suite: {posix_external_seed_suite.matches}/{posix_external_seed_suite.total}")
    print(f"posix external smoosh suite: {posix_external_smoosh_suite.matches}/{posix_external_smoosh_suite.total}")
    print(f"posix external smoosh tools suite: {posix_external_smoosh_tools_suite.matches}/{posix_external_smoosh_tools_suite.total}")
    print(f"special builtin matrix: {special_matrix.matches}/{special_matrix.total}")
    print(f"command search matrix: {command_matrix.matches}/{command_matrix.total}")
    print(f"fd/process matrix: {fd_matrix.matches}/{fd_matrix.total}")
    print(f"issue8 fd matrix: {issue8_fd_matrix.matches}/{issue8_fd_matrix.total}")
    print(f"signal/trap matrix: {signal_matrix.matches}/{signal_matrix.total}")
    print(f"regular builtin matrix: {regular_matrix.matches}/{regular_matrix.total}")
    print(f"semantic: {'PASS' if semantic.ok else 'FAIL'}")
    print(f"blockers: {blockers.closed} closed / {blockers.open} open")
    print(f"real exec: {'PASS' if real_exec.status == 0 else 'FAIL'}")
    print(f"command search: {'PASS' if command_search.status == 0 else 'FAIL'}")
    print(f"shell invocation: {'PASS' if invocation.status == 0 else 'FAIL'}")
    print(f"linux command search: {linux_probe_state(linux_command_search)}")
    print(f"linux command-search diagnostic matrix: {linux_command_search_matrix.matches}/{linux_command_search_matrix.total}")
    print(f"linux redirection diagnostic matrix: {linux_redirection_matrix.matches}/{linux_redirection_matrix.total}")
    print(f"linux arbitrary-fd/process matrix: {linux_arbitrary_fd_matrix.matches}/{linux_arbitrary_fd_matrix.total}")
    print(f"linux signal/wait matrix: {linux_signal_wait_matrix.matches}/{linux_signal_wait_matrix.total}")
    print(f"linux filesystem/profile: {linux_probe_state(linux_test_predicate)}")
    print(f"linux printf bytes: {linux_probe_state(linux_printf_byte)}")
    print(f"linux job-control: {linux_probe_state(linux_job_control)}")
    print(f"linux fd graph: {linux_probe_state(linux_fd_graph)}")
    print(f"linux interactive pty: {linux_probe_state(linux_interactive)}")
    print(f"leak: {'PASS' if leak.status == 0 else 'FAIL'}")
    print(f"line guard: {'PASS' if line_ok else 'FAIL'}")
    print(f"report: {path}")
    return core_ok


def skipped_diff(report_name: str) -> list[dict[str, object]]:
    save_text(REPORT_DIR / report_name, "[]\n")
    return []


def main() -> int:
    global FINISH_WALL_DEADLINE
    global FINISH_BASE_COMMAND_TIMEOUT
    parser = argparse.ArgumentParser(description="Refresh and report msh profile gates.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--linux-msh", type=Path, default=DEFAULT_LINUX_MSH)
    parser.add_argument("--no-wsl", action="store_true")
    parser.add_argument("--no-build", action="store_true", help="Test the existing --msh binary without rebuilding it first.")
    parser.add_argument("--ailang-root", help="Path to AILang-Pure. Defaults to sibling repo or AILANG_ROOT.")
    parser.add_argument(
        "--command-timeout",
        type=int,
        default=int(os.environ.get("MSH_FINISH_COMMAND_TIMEOUT_SECONDS", str(DEFAULT_COMMAND_TIMEOUT_SECONDS))),
        help="Per-tool timeout in seconds. Defaults to 300.",
    )
    parser.add_argument(
        "--max-seconds",
        type=int,
        default=int(os.environ.get("MSH_FINISH_MAX_SECONDS", str(DEFAULT_MAX_SECONDS))),
        help="Whole finish-line wall-clock cap in seconds. Use 0 to disable.",
    )
    args = parser.parse_args()

    os.environ.setdefault("MSH_TOOL_TRACE", "1")
    os.environ.setdefault("MSH_TOOL_HEARTBEAT_SECONDS", "20")
    FINISH_BASE_COMMAND_TIMEOUT = args.command_timeout if args.command_timeout > 0 else DEFAULT_COMMAND_TIMEOUT_SECONDS
    os.environ["MSH_FINISH_COMMAND_TIMEOUT_SECONDS"] = str(FINISH_BASE_COMMAND_TIMEOUT)
    if args.max_seconds > 0:
        FINISH_WALL_DEADLINE = time.monotonic() + args.max_seconds
        announce_step(f"using whole-run cap {args.max_seconds}s and per-tool cap {args.command_timeout}s")
    else:
        FINISH_WALL_DEADLINE = 0.0
        announce_step(f"using no whole-run cap and per-tool cap {args.command_timeout}s")

    msh = args.msh.resolve()
    linux_msh = preserve_wsl_path_or_resolve(args.linux_msh)
    ailang_root = ailang_root_from_args(args.ailang_root)
    build_results: list[CommandResult] = []
    if not args.no_build:
        announce_step("building Windows msh")
        build_results = run_source_build(msh, ailang_root)
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2

    no_wsl = args.no_wsl
    reference_shell = "wsl-sh"
    reference_mode = "wsl"
    if not no_wsl:
        announce_step("checking WSL preflight")
        wsl_preflight = run_wsl_preflight()
        if not wsl_preflight_ok(wsl_preflight):
            print(
                "msh finish-line: WSL preflight failed; running local reference evidence. "
                "See Server/Generated/reports/msh-wsl-preflight.txt.",
                file=sys.stderr,
            )
            no_wsl = True
    linux_test_predicate: CommandResult | None = None
    linux_command_search: CommandResult | None = None
    linux_command_search_matrix = MatrixSummary(False, 0, 0)
    linux_redirection_matrix = MatrixSummary(False, 0, 0)
    linux_arbitrary_fd_matrix = MatrixSummary(False, 0, 0)
    linux_signal_wait_matrix = MatrixSummary(False, 0, 0)
    linux_printf_byte: CommandResult | None = None
    linux_job_control: CommandResult | None = None
    linux_fd_graph: CommandResult | None = None
    linux_interactive: CommandResult | None = None

    if no_wsl:
        reference_shell = local_reference_shell()
        reference_mode = "local-fallback"
        if reference_shell:
            local_args = local_reference_args(reference_shell)
            local_suite_args = local_suite_reference_args(reference_shell)
            announce_step(f"running local shell diff against {reference_shell}")
            _, strict_rows = run_shell_diff(msh, local_args, "msh-shell-diff-current.json")
            announce_step("running local POSIX core suite")
            _, posix_suite_rows = run_posix_suite(msh, local_suite_args)
            announce_step("running local POSIX stress suite")
            _, posix_stress_suite_rows = run_posix_stress_suite(msh, local_suite_args)
            announce_step("running local POSIX external seed suite")
            _, posix_external_seed_suite_rows = run_posix_external_seed_suite(msh, local_suite_args)
            announce_step("running local POSIX external Smoosh suite")
            _, posix_external_smoosh_suite_rows = run_posix_external_smoosh_suite(msh, local_suite_args)
            posix_external_smoosh_tools_suite_rows = skipped_diff("msh-posix-external-smoosh-tools-suite.json")
            announce_step("running generated local special-builtin matrix")
            _, special_matrix = run_special_builtin_matrix(msh, reference_shell)
            announce_step("running generated local command-search matrix")
            _, command_matrix = run_command_search_matrix(msh, reference_shell)
            announce_step("running generated local fd/process matrix")
            _, fd_matrix = run_fd_process_matrix(msh, reference_shell)
            issue8_fd_matrix = MatrixSummary(False, 0, 0)
            announce_step("running generated local signal/trap matrix")
            _, signal_matrix = run_signal_trap_matrix(msh, reference_shell)
            announce_step("running generated local regular-builtin matrix")
            _, regular_matrix = run_regular_builtin_matrix(msh, reference_shell)
            announce_step("running local extension-inclusive shell diff")
            _, extension_rows = run_shell_diff(
                msh,
                local_reference_args(reference_shell, include_extensions=True),
                "msh-shell-diff-current-with-extensions.json",
            )
            announce_step("running local stderr-sensitive shell diff")
            _, stderr_rows = run_shell_diff(
                msh,
                local_reference_args(reference_shell, compare_stderr=True),
                "msh-shell-diff-current-stderr.json",
            )
        else:
            reference_shell = "none"
            reference_mode = "unavailable"
            strict_rows = skipped_diff("msh-shell-diff-current.json")
            posix_suite_rows = skipped_diff("msh-posix-suite-current.json")
            posix_stress_suite_rows = skipped_diff("msh-posix-stress-suite.json")
            posix_external_seed_suite_rows = skipped_diff("msh-posix-external-seed-suite.json")
            posix_external_smoosh_suite_rows = skipped_diff("msh-posix-external-smoosh-suite.json")
            posix_external_smoosh_tools_suite_rows = skipped_diff("msh-posix-external-smoosh-tools-suite.json")
            special_matrix = MatrixSummary(False, 0, 0)
            command_matrix = MatrixSummary(False, 0, 0)
            fd_matrix = MatrixSummary(False, 0, 0)
            issue8_fd_matrix = MatrixSummary(False, 0, 0)
            signal_matrix = MatrixSummary(False, 0, 0)
            regular_matrix = MatrixSummary(False, 0, 0)
            extension_rows = skipped_diff("msh-shell-diff-current-with-extensions.json")
            stderr_rows = skipped_diff("msh-shell-diff-current-stderr.json")
    else:
        if not args.no_build:
            announce_step("building Linux msh in WSL")
            build_results.append(run_wsl_source_build(linux_msh, ailang_root))
        announce_step("running strict WSL shell diff")
        _, strict_rows = run_shell_diff(msh, ["--baseline-only"], "msh-shell-diff-current.json")
        announce_step("running POSIX core suite")
        _, posix_suite_rows = run_posix_suite(msh)
        announce_step("running POSIX stress suite")
        _, posix_stress_suite_rows = run_posix_stress_suite(msh)
        announce_step("running POSIX external seed suite")
        _, posix_external_seed_suite_rows = run_posix_external_seed_suite(msh)
        announce_step("running POSIX external Smoosh suite")
        _, posix_external_smoosh_suite_rows = run_posix_external_smoosh_suite(msh)
        announce_step("running tools-backed broad Smoosh suite")
        _, posix_external_smoosh_tools_suite_rows = run_posix_external_smoosh_tools_suite(linux_msh)
        announce_step("running generated special-builtin matrix")
        _, special_matrix = run_special_builtin_matrix(msh)
        announce_step("running generated command-search matrix")
        _, command_matrix = run_command_search_matrix(msh)
        announce_step("running generated fd/process matrix")
        _, fd_matrix = run_fd_process_matrix(msh)
        announce_step("running POSIX Issue 8 multi-digit fd matrix")
        _, issue8_fd_matrix = run_issue8_fd_matrix(msh)
        announce_step("running generated signal/trap matrix")
        _, signal_matrix = run_signal_trap_matrix(msh)
        announce_step("running generated regular-builtin matrix")
        _, regular_matrix = run_regular_builtin_matrix(msh)
        announce_step("running extension-inclusive shell diff")
        _, extension_rows = run_shell_diff(msh, ["--baseline-only", "--include-extensions"], "msh-shell-diff-current-with-extensions.json")
        announce_step("running stderr-sensitive shell diff")
        _, stderr_rows = run_shell_diff(msh, ["--baseline-only", "--compare-stderr"], "msh-shell-diff-current-stderr.json")
        announce_step("running Linux command-search probe")
        linux_command_search = run_linux_command_search_probe(linux_msh)
        announce_step("running Linux command-search diagnostic matrix")
        _, linux_command_search_matrix = run_linux_command_search_matrix(linux_msh)
        announce_step("running Linux redirection diagnostic matrix")
        _, linux_redirection_matrix = run_linux_redirection_matrix(linux_msh)
        announce_step("running Linux arbitrary-fd/process matrix")
        _, linux_arbitrary_fd_matrix = run_linux_arbitrary_fd_matrix(linux_msh)
        announce_step("running Linux signal/wait matrix")
        _, linux_signal_wait_matrix = run_linux_signal_wait_matrix(linux_msh)
        announce_step("running Linux filesystem/profile probe")
        linux_test_predicate = run_linux_test_predicate_probe(linux_msh)
        announce_step("running Linux printf-byte probe")
        linux_printf_byte = run_linux_printf_byte_probe(linux_msh)
        announce_step("running Linux job-control probe")
        linux_job_control = run_linux_job_control_probe(linux_msh)
        announce_step("running Linux fd-graph probe")
        linux_fd_graph = run_linux_fd_graph_probe(linux_msh)
        announce_step("running Linux interactive pty probe")
        linux_interactive = run_linux_interactive_probe(linux_msh)
    announce_step("running semantic probe")
    _, semantic = run_semantic(msh, no_wsl)
    announce_step("running blocker probe")
    _, blockers = run_blockers(msh, no_wsl)
    announce_step("running real-exec probe")
    real_exec = run_real_exec_probe(msh)
    announce_step("running command-search probe")
    command_search = run_command_search_probe(msh)
    announce_step("running invocation probe")
    invocation = run_invocation_probe(msh)
    announce_step("running leak selftest")
    leak = run_leak_selftest(msh)
    announce_step("running line guard and writing report")
    line_ok, over_lines = line_guard()
    core_ok = write_finish_report(
        build_results,
        reference_shell,
        reference_mode,
        summarize_diff(strict_rows, reference_shell),
        summarize_diff(posix_suite_rows, reference_shell),
        summarize_diff(posix_stress_suite_rows, reference_shell),
        summarize_diff(posix_external_seed_suite_rows, reference_shell),
        summarize_diff(posix_external_smoosh_suite_rows, reference_shell),
        summarize_diff(posix_external_smoosh_tools_suite_rows, reference_shell),
        summarize_diff(extension_rows, reference_shell),
        summarize_diff(stderr_rows, reference_shell),
        special_matrix,
        command_matrix,
        fd_matrix,
        issue8_fd_matrix,
        signal_matrix,
        regular_matrix,
        semantic,
        blockers,
        real_exec,
        command_search,
        invocation,
        linux_command_search,
        linux_command_search_matrix,
        linux_redirection_matrix,
        linux_arbitrary_fd_matrix,
        linux_signal_wait_matrix,
        linux_test_predicate,
        linux_printf_byte,
        linux_job_control,
        linux_fd_graph,
        linux_interactive,
        leak,
        line_ok,
        over_lines,
    )
    return 0 if core_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
