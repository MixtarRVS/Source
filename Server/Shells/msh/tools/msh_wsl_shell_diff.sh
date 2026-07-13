#!/usr/bin/env sh
# Run the msh shell-diff corpus from inside WSL.
#
# This avoids launching `wsl.exe` once per test case. Invoke it from WSL:
#
#   sh Server/Shells/msh/tools/msh_wsl_shell_diff.sh
#
# Or from Windows with one WSL process:
#
#   wsl.exe --exec sh /mnt/c/Users/V/source/repos/MixtarRVS/Server/Shells/msh/tools/msh_wsl_shell_diff.sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MIXTAR_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../../.." && pwd)
export MSH_WSL_SCRIPT_DIR="$SCRIPT_DIR"
export MSH_WSL_MIXTAR_ROOT="$MIXTAR_ROOT"

if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
elif command -v python >/dev/null 2>&1; then
    PYTHON=python
else
    echo "msh_wsl_shell_diff.sh: python3/python is required inside WSL" >&2
    exit 127
fi

exec "$PYTHON" - "$@" <<'PY'
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict
from pathlib import Path


SCRIPT_DIR = Path(os.environ["MSH_WSL_SCRIPT_DIR"]).resolve()
MIXTAR_ROOT = Path(os.environ["MSH_WSL_MIXTAR_ROOT"]).resolve()
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
WORK_ROOT = MIXTAR_ROOT / "Server" / "Generated" / "tmp" / "msh-wsl-shell-diff"
DEFAULT_MSH_EXE = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_MSH_ELF = MIXTAR_ROOT / "out" / "server" / "msh_cli"
DIFF_MODULE = SCRIPT_DIR / "msh_shell_diff.py"


def load_diff_module():
    sys.path.insert(0, str(SCRIPT_DIR))
    spec = importlib.util.spec_from_file_location("msh_shell_diff", DIFF_MODULE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {DIFF_MODULE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["msh_shell_diff"] = module
    spec.loader.exec_module(module)
    return module


DIFF = load_diff_module()
DiffCase = DIFF.DiffCase
RunResult = DIFF.RunResult
results_match = DIFF.results_match
_SHELL_AVAILABILITY: dict[tuple[str, ...], bool] = {}


def default_msh() -> Path:
    if DEFAULT_MSH_ELF.exists():
        return DEFAULT_MSH_ELF
    return DEFAULT_MSH_EXE


def shell_specs(selected: str) -> list[tuple[str, list[str]]]:
    specs = [
        ("wsl-sh", ["sh"]),
        ("wsl-bash-posix", ["bash", "--posix"]),
        ("wsl-bash", ["bash"]),
        ("wsl-zsh-sh", ["zsh", "--emulate", "sh"]),
    ]
    if selected:
        wanted = {item.strip() for item in selected.split(",") if item.strip()}
        specs = [spec for spec in specs if spec[0] in wanted]
    return specs


def shell_available(argv: list[str], timeout: int) -> bool:
    key = tuple(argv)
    cached = _SHELL_AVAILABILITY.get(key)
    if cached is not None:
        return cached
    if shutil.which(argv[0]) is None:
        _SHELL_AVAILABILITY[key] = False
        return False
    try:
        proc = subprocess.run(
            [*argv, "-c", "exit 0"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        _SHELL_AVAILABILITY[key] = False
        return False
    available = proc.returncode == 0
    _SHELL_AVAILABILITY[key] = available
    return available


def text_from_pipe(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return value.decode("utf-8", errors="replace")


def run_cmd(argv: list[str], cwd: Path, timeout: int) -> subprocess.CompletedProcess[str]:
    try:
        proc = subprocess.Popen(
            argv,
            cwd=str(cwd),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except OSError as exc:
        return subprocess.CompletedProcess(argv, 127, "", str(exc))
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
        return subprocess.CompletedProcess(argv, proc.returncode, stdout, stderr)
    except subprocess.TimeoutExpired as exc:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            try:
                proc.kill()
            except OSError:
                pass
        try:
            stdout_after, stderr_after = proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            stdout_after, stderr_after = "", ""
        stdout = text_from_pipe(exc.stdout) + text_from_pipe(stdout_after)
        stderr = text_from_pipe(exc.stderr) + text_from_pipe(stderr_after)
        if stderr:
            stderr += "\n"
        stderr += f"timeout after {timeout}s"
        return subprocess.CompletedProcess(argv, 124, stdout, stderr)


def parse_msh(stdout: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], "")
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
    return RunResult(status, text, "")


def write_script(path: Path, script: str) -> None:
    path.write_text(script, encoding="utf-8", newline="\n")


def run_msh(msh: Path, case: DiffCase, cwd: Path, timeout: int) -> RunResult:
    proc = run_cmd([str(msh), "eval", case.script], cwd, timeout)
    parsed = parse_msh(proc.stdout, proc.returncode)
    return RunResult(parsed.status, parsed.stdout, proc.stderr)


def run_shell(name: str, argv: list[str], case: DiffCase, cwd: Path, timeout: int) -> RunResult:
    if not shell_available(argv, timeout):
        return RunResult(127, "", f"{argv[0]} not available", False)
    script_path = cwd / "case.sh"
    body = "cd " + DIFF.sh_quote(str(cwd)) + " || exit 125\n" + case.script
    write_script(script_path, body)
    proc = run_cmd([*argv, str(script_path)], cwd, timeout)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def safe_name(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", text)


def selected_cases(category: str, include_extensions: bool):
    cases = DIFF.diff_cases()
    if not include_extensions:
        cases = [case for case in cases if case.profile == "posix"]
    if category:
        cases = [case for case in cases if case.category == category]
    return cases


def run_case(
    msh: Path,
    case: DiffCase,
    root: Path,
    specs: list[tuple[str, list[str]]],
    timeout: int,
    compare_stderr: bool,
    progress: bool,
    index: int,
    total: int,
):
    if progress:
        print(f"[msh-wsl-diff] {index}/{total} {case.category}/{case.name}", file=sys.stderr, flush=True)
    started = time.monotonic()
    case_root = root / safe_name(case.category + "-" + case.name)
    msh_dir = case_root / "msh"
    ref_root = case_root / "ref"
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_root.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir, timeout)
    shells: dict[str, dict[str, object]] = {}
    for name, argv in specs:
        shell_dir = ref_root / name
        shell_dir.mkdir(parents=True, exist_ok=True)
        result = run_shell(name, argv, case, shell_dir, timeout)
        shells[name] = {
            "available": result.available,
            "matches_msh": results_match(msh_result, result, case, compare_stderr),
            "status": result.status,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    return {
        "category": case.category,
        "name": case.name,
        "profile": case.profile,
        "status_mode": case.status_mode,
        "script": case.script,
        "elapsed_seconds": round(time.monotonic() - started, 3),
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
        },
        "shells": shells,
    }


def summarize(rows: list[dict[str, object]], specs: list[tuple[str, list[str]]]) -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {}
    for name, _argv in specs:
        matches = 0
        available = 0
        for row in rows:
            shell = row["shells"][name]  # type: ignore[index]
            if shell["available"]:
                available += 1
                if shell["matches_msh"]:
                    matches += 1
        out[name] = (matches, available)
    return out


def write_markdown(path: Path, rows: list[dict[str, object]], summary: dict[str, tuple[int, int]]) -> None:
    lines = [
        "# msh WSL Shell Diff",
        "",
        "Generated by `msh_wsl_shell_diff.sh` inside WSL.",
        "",
        "## Summary",
        "",
    ]
    for name, (matches, available) in summary.items():
        lines.append(f"- `{name}`: `{matches}/{available}`")
    timed_out = [
        row
        for row in rows
        if row["msh"]["status"] == 124  # type: ignore[index]
        or any(shell.get("status") == 124 for shell in row["shells"].values())  # type: ignore[union-attr]
    ]
    if timed_out:
        lines.append(f"- timeouts: `{len(timed_out)}`")
    lines.extend(["", "## Mismatches", ""])
    any_mismatch = False
    for row in rows:
        for shell_name, shell in row["shells"].items():  # type: ignore[union-attr]
            if shell.get("available") and not shell.get("matches_msh"):
                any_mismatch = True
                lines.append(f"### {row['category']}/{row['name']} vs `{shell_name}`")
                lines.append("")
                lines.append(f"- msh: `{row['msh']['status']}` `{repr(row['msh']['stdout'])}`")  # type: ignore[index]
                lines.append(f"- {shell_name}: `{shell['status']}` `{repr(shell['stdout'])}`")
                if shell.get("stderr"):
                    lines.append(f"- {shell_name} stderr: `{repr(shell['stderr'])}`")
                lines.append("")
    if not any_mismatch:
        lines.append("No mismatches for available selected shells.")
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run msh shell diff inside WSL.")
    parser.add_argument("--msh", default=str(default_msh()))
    parser.add_argument("--category", default="")
    parser.add_argument("--include-extensions", action="store_true")
    parser.add_argument("--compare-stderr", action="store_true")
    parser.add_argument("--shells", default="")
    parser.add_argument("--timeout", type=int, default=10)
    parser.add_argument("--progress", action="store_true")
    parser.add_argument("--json-report", default=str(REPORT_DIR / "msh-wsl-shell-diff.json"))
    parser.add_argument("--report", default=str(REPORT_DIR / "msh-wsl-shell-diff.md"))
    parser.add_argument("--list-shells", action="store_true")
    args = parser.parse_args()

    specs = shell_specs(args.shells)
    if args.list_shells:
        for name, argv in specs:
            state = "available" if shell_available(argv, args.timeout) else "missing"
            print(f"{name}: {state} ({' '.join(argv)})")
        return 0

    msh = Path(args.msh)
    if not msh.exists():
        print(f"msh_wsl_shell_diff.sh: missing msh executable: {msh}", file=sys.stderr)
        return 2

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    if WORK_ROOT.exists():
        shutil.rmtree(WORK_ROOT)
    WORK_ROOT.mkdir(parents=True, exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix="run-", dir=str(WORK_ROOT)))
    try:
        cases = selected_cases(args.category, args.include_extensions)
        rows = []
        total = len(cases)
        for index, case in enumerate(cases, start=1):
            rows.append(
                run_case(
                    msh,
                    case,
                    temp_root,
                    specs,
                    args.timeout,
                    args.compare_stderr,
                    args.progress,
                    index,
                    total,
                )
            )
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)
    summary = summarize(rows, specs)

    json_path = Path(args.json_report)
    report_path = Path(args.report)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(rows, indent=2), encoding="utf-8", newline="\n")
    write_markdown(report_path, rows, summary)

    for name, (matches, available) in summary.items():
        print(f"{name}: {matches}/{available}")
    print(f"json: {json_path}")
    print(f"report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
