#!/usr/bin/env python3
"""File-based POSIX shell suite runner for msh.

This is the bridge between the internal msh probes and larger external shell
test suites. Cases are ordinary .sh files with optional metadata comments at
the top of the file:

    # msh-profile: posix
    # msh-status: exact
    # msh-stdout: exact
    # msh-stderr: off
    # msh-run: eval
    # msh-args: one "two words"

The default baseline is WSL /bin/sh. Other WSL shells are observational.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
from msh_tool_process import run_tool_cmd
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_SUITE = MSH_DIR / "suites" / "posix-core"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_REPORT = REPORT_DIR / "msh-posix-suite.md"
DEFAULT_JSON = REPORT_DIR / "msh-posix-suite.json"
RUN_TIMEOUT_SECONDS = 10
REFERENCE_TIMEOUT_RETRIES = 2
DEFAULT_WSL_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
_WSL_DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
_WSL_COMMAND_DIAG_PREFIX_RE = re.compile(r"^(?:sh|dash|bash|zsh): \d+: ")
STDERR_OFF = "off"
STDERR_RAW = "raw"
STDERR_NORMALIZED = "normalized"
STDOUT_EXACT = "exact"
STDOUT_CWD_NORMALIZED = "cwd-normalized"
_SHELL_AVAILABILITY: dict[tuple[str, ...], bool] = {}


@dataclass(frozen=True)
class ShellSpec:
    name: str
    argv: tuple[str, ...]
    baseline: bool = False
    runner: str = "wsl"


@dataclass(frozen=True)
class SuiteCase:
    category: str
    name: str
    path: Path
    script: str
    profile: str = "posix"
    status_mode: str = "exact"
    stdout_mode: str = STDOUT_EXACT
    stderr_mode: str = STDERR_OFF
    run_mode: str = "eval"
    script_args: tuple[str, ...] = ()


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str
    available: bool = True


def local_shell_specs() -> list[ShellSpec]:
    candidates = [
        ShellSpec("git-dash", (r"C:\Program Files\Git\usr\bin\dash.exe",), runner="local"),
        ShellSpec("git-sh", (r"C:\Program Files\Git\bin\sh.exe",), runner="local"),
        ShellSpec("git-bash-posix", (r"C:\Program Files\Git\usr\bin\bash.exe", "--posix"), runner="local"),
        ShellSpec("msys-dash", (r"C:\msys64\usr\bin\dash.exe",), runner="local"),
        ShellSpec("msys-sh", (r"C:\msys64\usr\bin\sh.exe",), runner="local"),
        ShellSpec("msys-bash-posix", (r"C:\msys64\usr\bin\bash.exe", "--posix"), runner="local"),
    ]
    return [spec for spec in candidates if Path(spec.argv[0]).exists()]


def shell_specs(
    baseline_only: bool = False,
    include_local: bool = False,
    include_wsl: bool = True,
    strict_shell_only: str = "",
) -> list[ShellSpec]:
    specs = [
        ShellSpec("wsl-sh", ("sh",), True),
        ShellSpec("wsl-bash-posix", ("bash", "--posix")),
        ShellSpec("wsl-bash", ("bash",)),
        ShellSpec("wsl-zsh-sh", ("zsh", "--emulate", "sh")),
    ]
    if not include_wsl:
        specs = []
    if include_local:
        specs.extend(local_shell_specs())
    if strict_shell_only:
        return [spec for spec in specs if spec.name == strict_shell_only]
    if baseline_only:
        baseline = [spec for spec in specs if spec.baseline]
        if include_local:
            baseline.extend(local_shell_specs())
        if not include_wsl:
            baseline = [spec for spec in baseline if spec.runner != "wsl"]
        return baseline
    return specs


def run_cmd(
    argv: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return run_tool_cmd(argv, cwd, env, timeout=RUN_TIMEOUT_SECONDS)


def windows_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def path_to_wsl(path: Path) -> str:
    if path.drive:
        return windows_to_wsl_path(path)
    return str(path).replace("\\", "/")


def sh_quote(text: str) -> str:
    return shlex.quote(text)


def shell_available(spec: ShellSpec) -> bool:
    cached = _SHELL_AVAILABILITY.get(spec.argv)
    if cached is not None:
        return cached
    if spec.runner == "local":
        proc = run_cmd([*spec.argv, "-c", "exit 0"])
    else:
        proc = run_cmd(["wsl.exe", "--exec", spec.argv[0], "-c", "exit 0"])
    available = proc.returncode == 0
    _SHELL_AVAILABILITY[spec.argv] = available
    return available


def parse_bool(value: str, default: bool) -> bool:
    if value.lower() in ("1", "true", "yes", "on"):
        return True
    if value.lower() in ("0", "false", "no", "off"):
        return False
    return default


def parse_stderr_mode(metadata: dict[str, str]) -> str:
    value = metadata.get("stderr", "").lower()
    if value in (STDERR_OFF, STDERR_RAW, STDERR_NORMALIZED):
        return value
    legacy = metadata.get("compare_stderr", "").lower()
    if legacy == STDERR_NORMALIZED:
        return STDERR_NORMALIZED
    if parse_bool(legacy, False):
        return STDERR_RAW
    return STDERR_OFF


def parse_stdout_mode(metadata: dict[str, str]) -> str:
    value = metadata.get("stdout", "").lower()
    if value == STDOUT_CWD_NORMALIZED:
        return STDOUT_CWD_NORMALIZED
    return STDOUT_EXACT


def parse_run_mode(metadata: dict[str, str]) -> str:
    value = metadata.get("run", "eval").lower()
    if value == "file":
        return "file"
    return "eval"


def parse_script_args(metadata: dict[str, str], path: Path) -> tuple[str, ...]:
    value = metadata.get("args", "").strip()
    if not value:
        return ()
    try:
        return tuple(shlex.split(value))
    except ValueError as exc:
        raise ValueError(f"invalid msh-args in {path}: {exc}") from exc


def read_metadata(lines: list[str]) -> dict[str, str]:
    metadata: dict[str, str] = {}
    pattern = re.compile(r"^#\s*msh-([A-Za-z0-9_-]+):\s*(.*?)\s*$")
    for line in lines:
        if not line.startswith("#"):
            break
        match = pattern.match(line)
        if match:
            metadata[match.group(1).replace("-", "_")] = match.group(2)
    return metadata


def load_case(path: Path, root: Path) -> SuiteCase:
    script = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    metadata = read_metadata(script.splitlines())
    rel = path.relative_to(root)
    category = metadata.get("category") or (rel.parts[0] if len(rel.parts) > 1 else "root")
    name = metadata.get("name") or path.stem
    return SuiteCase(
        category=category,
        name=name,
        path=path,
        script=script,
        profile=metadata.get("profile", "posix"),
        status_mode=metadata.get("status", "exact"),
        stdout_mode=parse_stdout_mode(metadata),
        stderr_mode=parse_stderr_mode(metadata),
        run_mode=parse_run_mode(metadata),
        script_args=parse_script_args(metadata, path),
    )


def discover_cases(root: Path, include_extensions: bool) -> list[SuiteCase]:
    cases = [load_case(path, root) for path in sorted(root.rglob("*.sh"))]
    if include_extensions:
        return cases
    return [case for case in cases if case.profile == "posix"]


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


def parse_msh_file(stdout: str, stderr: str, returncode: int) -> RunResult:
    return RunResult(returncode, stdout, stderr)


def wsl_tool_path_value(tool_path: Path | None) -> str:
    if tool_path is None:
        return DEFAULT_WSL_PATH
    return path_to_wsl(tool_path) + ":" + DEFAULT_WSL_PATH


def shell_spec_script_arg(spec: ShellSpec, arg: str) -> str:
    if spec.runner == "local" and Path(arg).drive:
        return local_shell_command_path(Path(arg))
    return arg


def shell_spec_command(spec: ShellSpec) -> str:
    return " ".join(sh_quote(shell_spec_script_arg(spec, arg)) for arg in spec.argv)


def suite_env(test_shell: str, test_util: str = "") -> dict[str, str]:
    return {
        "TEST_SHELL": test_shell,
        "TEST_UTIL": test_util,
    }


def local_msh_env(msh: Path, tool_path: Path | None) -> dict[str, str]:
    env = suite_env(local_shell_command_path(msh))
    if tool_path is not None:
        env["PATH"] = str(tool_path.resolve()) + os.pathsep + os.environ.get("PATH", "")
    return env


def local_shell_command_path(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/")


def local_shell_path_entry(path: Path) -> str:
    raw = str(path.resolve()).replace("\\", "/")
    if len(raw) >= 2 and raw[1] == ":":
        return "/" + raw[0].lower() + raw[2:]
    return raw


def local_shell_tool_prefix(tool_path: Path | None) -> str:
    if tool_path is None:
        return ""
    return "PATH=" + sh_quote(local_shell_path_entry(tool_path)) + ":$PATH\nexport PATH\n"


def wsl_env_args(test_shell: str, tool_path: Path | None, test_util: str = "") -> list[str]:
    return [
        "PATH=" + wsl_tool_path_value(tool_path),
        "TEST_SHELL=" + test_shell,
        "TEST_UTIL=" + test_util,
    ]


def run_msh_wsl(msh: Path, case: SuiteCase, cwd: Path, tool_path: Path | None) -> RunResult:
    wsl_msh = path_to_wsl(msh)
    wsl_cwd = windows_to_wsl_path(cwd)
    env_args = wsl_env_args(wsl_msh, tool_path)
    if case.run_mode == "file":
        script_path = cwd / "case.sh"
        script_path.write_text(case.script, encoding="utf-8", newline="\n")
        proc = run_cmd(
            ["wsl.exe", "--cd", wsl_cwd, "--exec", "env", *env_args, wsl_msh, "case.sh", *case.script_args]
        )
        return parse_msh_file(proc.stdout, proc.stderr, proc.returncode)
    proc = run_cmd(["wsl.exe", "--cd", wsl_cwd, "--exec", "env", *env_args, wsl_msh, "eval", case.script])
    return parse_msh(proc.stdout, proc.stderr, proc.returncode)


def run_msh(msh: Path, case: SuiteCase, cwd: Path, msh_wsl: bool, tool_path: Path | None) -> RunResult:
    if msh_wsl:
        return run_msh_wsl(msh, case, cwd, tool_path)
    env = local_msh_env(msh, tool_path)
    if case.run_mode == "file":
        script_path = cwd / "case.sh"
        script_path.write_text(case.script, encoding="utf-8", newline="\n")
        proc = run_cmd([str(msh), "case.sh", *case.script_args], cwd=cwd, env=env)
        return parse_msh_file(proc.stdout, proc.stderr, proc.returncode)
    proc = run_cmd([str(msh), "eval", case.script], cwd=cwd, env=env)
    return parse_msh(proc.stdout, proc.stderr, proc.returncode)


def run_wsl_shell(spec: ShellSpec, case: SuiteCase, cwd: Path, tool_path: Path | None) -> RunResult:
    if not shell_available(spec):
        return RunResult(127, "", f"{spec.argv[0]} not available", False)
    script_path = cwd / "case.sh"
    test_shell = shell_spec_command(spec)
    if spec.runner == "local":
        local_cwd = local_shell_command_path(cwd)
        path_prefix = local_shell_tool_prefix(tool_path)
        if case.run_mode == "file":
            script_path.write_text(case.script, encoding="utf-8", newline="\n")
            script_argv = " ".join(sh_quote(arg) for arg in case.script_args)
            if script_argv:
                script_argv = " " + script_argv
            inner = (
                "cd " + sh_quote(local_cwd)
                + " || exit 125; " + path_prefix.replace("\n", "; ")
                + "TEST_SHELL=" + sh_quote(test_shell)
                + "; export TEST_SHELL; TEST_UTIL=; export TEST_UTIL; exec "
                + test_shell + " ./case.sh" + script_argv
            )
            proc = run_cmd([*spec.argv, "-c", inner])
            return RunResult(proc.returncode, proc.stdout, proc.stderr)
        body = (
            "cd " + sh_quote(local_cwd)
            + " || exit 125\n" + path_prefix
            + "TEST_SHELL=" + sh_quote(test_shell)
            + "\nexport TEST_SHELL\nTEST_UTIL=\nexport TEST_UTIL\n"
            + case.script
        )
        script_path.write_text(body, encoding="utf-8", newline="\n")
        proc = run_cmd([*spec.argv, str(script_path)])
        return RunResult(proc.returncode, proc.stdout, proc.stderr)
    if case.run_mode == "file":
        script_path.write_text(case.script, encoding="utf-8", newline="\n")
        shell_argv = test_shell
        script_argv = " ".join(sh_quote(arg) for arg in case.script_args)
        if script_argv:
            script_argv = " " + script_argv
        inner = (
            "cd " + sh_quote(windows_to_wsl_path(cwd))
            + " || exit 125; TEST_SHELL=" + sh_quote(test_shell)
            + "; export TEST_SHELL; TEST_UTIL=; export TEST_UTIL; exec "
            + shell_argv + " ./case.sh" + script_argv
        )
        proc = run_cmd(["wsl.exe", "--exec", *spec.argv, "-c", inner])
        return RunResult(proc.returncode, proc.stdout, proc.stderr)
    body = (
        "cd " + windows_to_wsl_path(cwd)
        + " || exit 125\nTEST_SHELL=" + sh_quote(test_shell)
        + "\nexport TEST_SHELL\nTEST_UTIL=\nexport TEST_UTIL\n"
        + case.script
    )
    script_path.write_text(body, encoding="utf-8", newline="\n")
    proc = run_cmd(["wsl.exe", "--exec", "env", *wsl_env_args(test_shell, tool_path), *spec.argv, windows_to_wsl_path(script_path)])
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def status_matches(left: int, right: int, mode: str) -> bool:
    if mode == "nonzero":
        return left != 0 and right != 0
    return left == right


def results_match(left: RunResult, right: RunResult, case: SuiteCase) -> bool:
    if not status_matches(left.status, right.status, case.status_mode):
        return False
    if stdout_for_compare(left.stdout, case.stdout_mode) != stdout_for_compare(right.stdout, case.stdout_mode):
        return False
    if stderr_for_compare(left.stderr, case.stderr_mode) != stderr_for_compare(right.stderr, case.stderr_mode):
        return False
    return True


def is_timeout_result(result: RunResult) -> bool:
    return result.status == 124 and "timeout after" in result.stderr


def run_reference_shell(spec: ShellSpec, case: SuiteCase, cwd: Path, tool_path: Path | None) -> RunResult:
    result = run_wsl_shell(spec, case, cwd, tool_path)
    attempt = 0
    while is_timeout_result(result) and attempt < REFERENCE_TIMEOUT_RETRIES:
        result = run_wsl_shell(spec, case, cwd, tool_path)
        attempt += 1
    return result


def normalize_stderr(stderr: str) -> str:
    if not stderr:
        return ""
    lines: list[str] = []
    for line in stderr.splitlines():
        line = _WSL_DIAG_PREFIX_RE.sub("", line)
        line = _WSL_COMMAND_DIAG_PREFIX_RE.sub("", line)
        if line.startswith("msh: "):
            line = line[5:]
        lines.append(line)
    text = "\n".join(lines)
    if stderr.endswith("\n"):
        text += "\n"
    return text


def normalize_stdout(stdout: str) -> str:
    if not stdout:
        return ""
    text = re.sub(
        r"/mnt/[A-Za-z]/[^ \t\r\n]*/msh-posix-suite-[^/ \t\r\n]+/[^/ \t\r\n]+/(?:msh|ref/[A-Za-z0-9_.-]+)",
        "<case-cwd>",
        stdout,
    )
    text = re.sub(
        r"[A-Za-z]:[/\\][^ \t\r\n]*/msh-posix-suite-[^/\\ \t\r\n]+[/\\][^/\\ \t\r\n]+[/\\](?:msh|ref[/\\][A-Za-z0-9_.-]+)",
        "<case-cwd>",
        text,
    )
    return text


def stdout_for_compare(stdout: str, mode: str) -> str:
    if mode == STDOUT_CWD_NORMALIZED:
        return normalize_stdout(stdout)
    return stdout


def stderr_for_compare(stderr: str, mode: str) -> str:
    if mode == STDERR_RAW:
        return stderr
    if mode == STDERR_NORMALIZED:
        return normalize_stderr(stderr)
    return ""


def safe_dir_name(case: SuiteCase) -> str:
    raw = f"{case.category}-{case.name}"
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", raw)


def run_case(
    msh: Path,
    case: SuiteCase,
    root: Path,
    baseline_only: bool,
    include_local: bool,
    include_wsl: bool,
    strict_shell_only: str,
    msh_wsl: bool,
    tool_path: Path | None,
) -> dict[str, object]:
    case_root = root / safe_dir_name(case)
    msh_dir = case_root / "msh"
    ref_root = case_root / "ref"
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_root.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir, msh_wsl, tool_path)
    shells: dict[str, dict[str, object]] = {}
    for spec in shell_specs(baseline_only, include_local, include_wsl, strict_shell_only):
        shell_dir = ref_root / spec.name
        shell_dir.mkdir(parents=True, exist_ok=True)
        result = run_reference_shell(spec, case, shell_dir, tool_path)
        shells[spec.name] = {
            "available": result.available,
            "matches_msh": results_match(msh_result, result, case),
            "status": result.status,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    return {
        "category": case.category,
        "name": case.name,
        "profile": case.profile,
        "status_mode": case.status_mode,
        "stdout_mode": case.stdout_mode,
        "stderr_mode": case.stderr_mode,
        "run_mode": case.run_mode,
        "script_args": list(case.script_args),
        "path": str(case.path),
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
        },
        "shells": shells,
    }


def print_progress(index: int, total: int, case: SuiteCase) -> None:
    print(
        f"[msh-posix-suite] {index}/{total} {case.category}/{case.name}",
        file=sys.stderr,
        flush=True,
    )


def baseline_count(results: list[dict[str, object]], strict_shell: str) -> tuple[int, int, int]:
    total = len(results)
    available = 0
    matches = 0
    for row in results:
        shells = row.get("shells", {})
        shell = shells.get(strict_shell, {}) if isinstance(shells, dict) else {}
        if not isinstance(shell, dict):
            continue
        if shell.get("available") is True:
            available += 1
            if shell.get("matches_msh") is True:
                matches += 1
    return total, available, matches


def shell_counts(
    results: list[dict[str, object]],
    baseline_only: bool,
    include_local: bool,
    include_wsl: bool,
    strict_shell_only: str,
) -> list[tuple[str, int, int]]:
    counts: list[tuple[str, int, int]] = []
    for spec in shell_specs(baseline_only, include_local, include_wsl, strict_shell_only):
        available = 0
        matches = 0
        for row in results:
            shell = row["shells"][spec.name]  # type: ignore[index]
            if shell["available"]:
                available += 1
                if shell["matches_msh"]:
                    matches += 1
        counts.append((spec.name, matches, available))
    return counts


def write_json(path: Path, results: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


def write_markdown(
    path: Path,
    results: list[dict[str, object]],
    strict_shell: str,
    suite: Path,
    baseline_only: bool,
    include_local: bool,
    include_wsl: bool,
    strict_shell_only: str,
) -> None:
    total, available, matches = baseline_count(results, strict_shell)
    lines = [
        "# msh POSIX Suite Report",
        "",
        f"Suite: `{suite}`",
        "",
        "## Summary",
        "",
        f"- Baseline `{strict_shell}`: `{matches}/{available}` available matches, `{total}` total cases",
    ]
    for name, count, avail in shell_counts(results, baseline_only, include_local, include_wsl, strict_shell_only):
        lines.append(f"- `{name}`: `{count}/{avail}`")
    lines.extend(["", "## Failures", ""])
    failures = 0
    for row in results:
        shell = row["shells"][strict_shell]  # type: ignore[index]
        if not shell["available"] or shell["matches_msh"]:
            continue
        failures += 1
        msh = row["msh"]  # type: ignore[assignment]
        lines.extend(
            [
                f"### {row['category']}/{row['name']}",
                "",
                f"- Path: `{row['path']}`",
                f"- msh: status `{msh['status']}`, stdout `{msh['stdout']!r}`",
                f"- {strict_shell}: status `{shell['status']}`, stdout `{shell['stdout']!r}`",
                f"- msh stderr: `{msh['stderr']!r}`",
                f"- {strict_shell} stderr: `{shell['stderr']!r}`",
                "",
            ]
        )
    if failures == 0:
        lines.append("No baseline failures.")
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_report(
    results: list[dict[str, object]],
    strict_shell: str,
    baseline_only: bool,
    include_local: bool,
    include_wsl: bool,
    strict_shell_only: str,
) -> None:
    total, available, matches = baseline_count(results, strict_shell)
    print(f"msh POSIX suite: {matches}/{available} match {strict_shell} ({total} cases)")
    for name, count, avail in shell_counts(results, baseline_only, include_local, include_wsl, strict_shell_only):
        print(f"  {name}: {count}/{avail}")
    for row in results:
        shell = row["shells"][strict_shell]  # type: ignore[index]
        if shell["available"] and not shell["matches_msh"]:
            msh = row["msh"]  # type: ignore[assignment]
            print("")
            print(f"- {row['category']}/{row['name']}")
            print(f"  path: {row['path']}")
            print(f"  msh: status={msh['status']} stdout={msh['stdout']!r}")
            print(f"  {strict_shell}: status={shell['status']} stdout={shell['stdout']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run file-based POSIX shell cases against msh and WSL shells.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--msh-wsl", action="store_true", help="Run the msh executable through WSL instead of as a Windows process.")
    parser.add_argument("--msh-tool-path", type=Path, default=None, help="Tool directory to prepend to PATH for the msh process.")
    parser.add_argument("--suite", type=Path, default=DEFAULT_SUITE)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--strict-shell", default="wsl-sh")
    parser.add_argument("--include-extensions", action="store_true")
    parser.add_argument("--baseline-only", action="store_true")
    parser.add_argument("--include-local-shells", action="store_true")
    parser.add_argument("--no-wsl-shells", action="store_true")
    parser.add_argument("--strict-shell-only", action="store_true")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--progress", action="store_true")
    args = parser.parse_args()

    msh = args.msh.resolve()
    tool_path = args.msh_tool_path.resolve() if args.msh_tool_path is not None else None
    suite = args.suite.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2
    if not suite.exists():
        print(f"suite directory not found: {suite}", file=sys.stderr)
        return 2
    cases = discover_cases(suite, args.include_extensions)
    if not cases:
        print(f"no .sh cases found in suite: {suite}", file=sys.stderr)
        return 2
    strict_shell_only = args.strict_shell if args.strict_shell_only else ""
    raw = tempfile.mkdtemp(prefix="msh-posix-suite-")
    root = Path(raw)
    try:
        results = []
        total = len(cases)
        for index, case in enumerate(cases, 1):
            if args.progress:
                print_progress(index, total, case)
            results.append(
                run_case(
                msh,
                case,
                root,
                args.baseline_only,
                args.include_local_shells,
                not args.no_wsl_shells,
                strict_shell_only,
                args.msh_wsl,
                tool_path,
            )
            )
    finally:
        pass
    write_json(args.json_report, results)
    write_markdown(
        args.report,
        results,
        args.strict_shell,
        suite,
        args.baseline_only,
        args.include_local_shells,
        not args.no_wsl_shells,
        strict_shell_only,
    )
    print_report(
        results,
        args.strict_shell,
        args.baseline_only,
        args.include_local_shells,
        not args.no_wsl_shells,
        strict_shell_only,
    )
    if args.msh_wsl and os.path.exists(raw):
        # WSL-mode cases can create names that are reserved on Windows, such as
        # `NUL`; let WSL remove what the Windows runtime cannot unlink.
        run_cmd(["wsl.exe", "--exec", "rm", "-rf", windows_to_wsl_path(root)])
    if os.path.exists(raw):
        shutil.rmtree(raw, ignore_errors=True)
    if args.strict:
        total, available, matches = baseline_count(results, args.strict_shell)
        if available != total or matches != total:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
