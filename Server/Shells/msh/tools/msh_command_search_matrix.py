#!/usr/bin/env python3
"""Compare msh command-search behavior against WSL /bin/sh.

This matrix is intentionally hosted-safe. Unix chmod-sensitive behavior stays
in msh_linux_command_search_probe.py because Windows temp files do not provide
reliable execute-bit evidence for WSL.
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
DEFAULT_JSON = REPORT_DIR / "msh-command-search-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-command-search-matrix.md"
RUN_TIMEOUT_SECONDS = 10
WSL_DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
_WSL_AVAILABLE: bool | None = None


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    script: str
    compare_stderr: bool = False


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


def write_script(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def setup_case_dir(root: Path) -> None:
    (root / "bin1").mkdir(parents=True, exist_ok=True)
    (root / "bin2").mkdir(parents=True, exist_ok=True)
    (root / "adir").mkdir(parents=True, exist_ok=True)
    (root / "bin1" / "asdir").mkdir(parents=True, exist_ok=True)
    write_script(root / "bin1" / "foo", "printf 'bin1\\n'\n")
    write_script(root / "bin2" / "foo", "printf 'bin2\\n'\n")
    write_script(root / "bin2" / "asdir", "printf 'dir-skip\\n'\n")
    write_script(root / "bin1" / "aa", "printf 'path-aa\\n'\n")
    write_script(root / "bin1" / "ff", "printf 'path-ff\\n'\n")
    write_script(root / "curpath", "printf 'curpath\\n'\n")
    write_script(root / "plain", "printf 'plain\\n'\n")


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase("reserved", "command-v-if", "command -v if"),
        MatrixCase("reserved", "command-V-if", "command -V if"),
        MatrixCase("reserved", "type-if", "type if"),
        MatrixCase("alias", "command-v-alias", "alias aa='printf alias\\n'; command -v aa"),
        MatrixCase("alias", "command-V-alias", "alias aa='printf alias\\n'; command -V aa"),
        MatrixCase("alias", "type-alias", "alias aa='printf alias\\n'; type aa"),
        MatrixCase("alias", "command-exec-suppresses-alias", "PATH=bin1; alias aa='printf alias\\n'; command aa"),
        MatrixCase("alias", "command-v-alias-before-function", "alias x='printf alias'; x(){ printf fn; }; command -v x"),
        MatrixCase("alias", "command-V-alias-before-function", "alias x='printf alias'; x(){ printf fn; }; command -V x"),
        MatrixCase("alias", "type-alias-before-function", "alias x='printf alias'; x(){ printf fn; }; type x"),
        MatrixCase("function", "command-v-function", "ff() { printf 'fn\\n'; }; command -v ff"),
        MatrixCase("function", "command-V-function", "ff() { printf 'fn\\n'; }; command -V ff"),
        MatrixCase("function", "type-function", "ff() { printf 'fn\\n'; }; type ff"),
        MatrixCase("function", "type-multiple-alias-function-path", "PATH=bin1\nalias aa='printf alias'\nff(){ :; }\ntype aa ff foo"),
        MatrixCase("function", "command-v-multiple-mixed", "PATH=bin1\nalias aa='printf alias'\nff(){ :; }\ncommand -v aa ff foo"),
        MatrixCase("function", "command-exec-suppresses-function", "PATH=bin1; ff() { printf 'fn\\n'; }; command ff"),
        MatrixCase("function", "function-shadows-regular-printf", "printf(){ :; }; printf ok; echo after"),
        MatrixCase("function", "function-shadows-regular-cd", "cd(){ printf 'fn-cd\\n'; }; cd"),
        MatrixCase("function", "function-shadows-regular-command", "command(){ printf fn; }; command"),
        MatrixCase("function", "function-named-command-shadows-command-lookup", "command(){ printf fn; }; command command -v command"),
        MatrixCase("alias", "alias-shadows-regular-printf", "alias printf='echo alias'; printf ok"),
        MatrixCase("function-name", "function-name-special-colon-invalid", ":(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-dot-invalid", ".(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-break-invalid", "break(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-continue-invalid", "continue(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-eval-invalid", "eval(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-exec-invalid", "exec(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-exit-invalid", "exit(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-export-invalid", "export(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-readonly-invalid", "readonly(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-return-invalid", "return(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-set-invalid", "set(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-shift-invalid", "shift(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-times-invalid", "times(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-trap-invalid", "trap(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-special-unset-invalid", "unset(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-bang-invalid", "!(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-case-invalid", "case(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-do-invalid", "do(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-done-invalid", "done(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-elif-invalid", "elif(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-else-invalid", "else(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-esac-invalid", "esac(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-fi-invalid", "fi(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-for-invalid", "for(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-if-invalid", "if(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-in-invalid", "in(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-then-invalid", "then(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-until-invalid", "until(){ :; }; printf ok"),
        MatrixCase("function-name", "function-name-reserved-while-invalid", "while(){ :; }; printf ok"),
        MatrixCase("builtin", "special-command-v-colon", "command -v :"),
        MatrixCase("builtin", "special-command-V-colon", "command -V :"),
        MatrixCase("builtin", "special-type-colon", "type :"),
        MatrixCase("builtin", "regular-command-v-printf", "command -v printf"),
        MatrixCase("builtin", "regular-command-V-printf", "command -V printf"),
        MatrixCase("builtin", "regular-type-printf", "type printf"),
        MatrixCase("builtin", "regular-command-v-bracket", "command -v ["),
        MatrixCase("builtin", "regular-command-V-bracket", "command -V ["),
        MatrixCase("builtin", "regular-type-bracket", "type ["),
        MatrixCase("builtin", "regular-command-v-test-echo-read", "command -v test echo read"),
        MatrixCase("builtin", "regular-command-V-test-echo-read", "command -V test echo read"),
        MatrixCase("builtin", "regular-type-test-echo-read", "type test echo read"),
        MatrixCase("builtin", "regular-command-v-read-printf-pwd", "command -v read printf pwd"),
        MatrixCase("builtin", "regular-command-V-read-printf-pwd", "command -V read printf pwd"),
        MatrixCase("builtin", "regular-type-read-printf-pwd", "type read printf pwd"),
        MatrixCase("builtin", "regular-command-v-alias-unalias-command-type", "command -v alias unalias command type"),
        MatrixCase("builtin", "regular-command-V-alias-unalias-command-type", "command -V alias unalias command type"),
        MatrixCase("builtin", "regular-type-alias-unalias-command-type", "type alias unalias command type"),
        MatrixCase("builtin", "regular-command-v-jobs-wait-kill-umask", "command -v jobs wait kill umask"),
        MatrixCase("builtin", "regular-command-V-jobs-wait-kill-umask", "command -V jobs wait kill umask"),
        MatrixCase("builtin", "regular-type-jobs-wait-kill-umask", "type jobs wait kill umask"),
        MatrixCase("builtin", "regular-command-v-bg-fg-getopts", "command -v bg fg getopts"),
        MatrixCase("builtin", "regular-command-V-bg-fg-getopts", "command -V bg fg getopts"),
        MatrixCase("builtin", "regular-type-bg-fg-getopts", "type bg fg getopts"),
        MatrixCase("builtin", "regular-command-v-command", "command -v command"),
        MatrixCase("builtin", "regular-command-V-command", "command -V command"),
        MatrixCase("builtin", "regular-type-command", "type command"),
        MatrixCase("path", "first-path-entry-wins", "PATH=bin1:bin2; foo"),
        MatrixCase("path", "command-v-first-path-entry", "PATH=bin1:bin2; command -v foo"),
        MatrixCase("path", "command-V-first-path-entry", "PATH=bin1:bin2; command -V foo"),
        MatrixCase("path", "type-first-path-entry", "PATH=bin1:bin2; type foo"),
        MatrixCase("path", "path-directory-is-skipped", "PATH=bin1:bin2; asdir"),
        MatrixCase("path", "command-v-directory-is-skipped", "PATH=bin1:bin2; command -v asdir"),
        MatrixCase("path", "empty-path-current-directory", "PATH=; curpath"),
        MatrixCase("path", "host-path-does-not-leak", "PATH=/definitely_missing; command -v sh; printf 's=%s\\n' $?"),
        MatrixCase("default-path", "command-p-v-sh", "PATH=/definitely_missing; command -p -v sh"),
        MatrixCase("default-path", "command-p-V-sh", "PATH=/definitely_missing; command -p -V sh"),
        MatrixCase("default-path", "command-pv-sh", "PATH=/definitely_missing; command -pv sh"),
        MatrixCase("default-path", "command-pV-sh", "PATH=/definitely_missing; command -pV sh"),
        MatrixCase("default-path", "command-Vp-sh", "PATH=/definitely_missing; command -Vp sh"),
        MatrixCase("options", "invalid-option-cluster", "command -pz sh; printf 's=%s\\n' $?", True),
        MatrixCase("options", "lone-dash-name", "command -; printf 's=%s\\n' $?", True),
        MatrixCase("options", "command-v-no-operand", "command -v; printf 's=%s\\n' $?"),
        MatrixCase("options", "command-V-no-operand", "command -V; printf 's=%s\\n' $?"),
        MatrixCase("options", "command-double-dash-printf", "command -- printf ok"),
        MatrixCase("options", "command-v-double-dash-printf", "command -v -- printf"),
        MatrixCase("options", "command-V-double-dash-printf", "command -V -- printf"),
        MatrixCase("options", "command-v-double-dash-no-operand", "command -v --; printf 's=%s\\n' $?"),
        MatrixCase("options", "command-V-double-dash-no-operand", "command -V --; printf 's=%s\\n' $?"),
        MatrixCase("options", "command-repeated-v", "command -v -v printf"),
        MatrixCase("options", "command-repeated-V", "command -V -V printf"),
        MatrixCase("options", "command-mixed-vV", "command -v -V printf"),
        MatrixCase("options", "command-mixed-Vv", "command -V -v printf"),
        MatrixCase("explicit", "command-v-explicit-file", "command -v ./plain"),
        MatrixCase("explicit", "command-V-explicit-file", "command -V ./plain"),
        MatrixCase("explicit", "type-explicit-file", "type ./plain"),
        MatrixCase("explicit", "command-v-explicit-file-empty-path", "PATH=; command -v ./plain"),
        MatrixCase("explicit", "command-V-explicit-file-empty-path", "PATH=; command -V ./plain"),
        MatrixCase("explicit", "type-explicit-file-empty-path", "PATH=; type ./plain"),
        MatrixCase("explicit", "execute-explicit-file", "./plain"),
        MatrixCase("explicit", "command-execute-explicit-file", "command ./plain"),
        MatrixCase("explicit", "command-v-explicit-directory", "command -v ./adir"),
        MatrixCase("explicit", "command-V-explicit-directory", "command -V ./adir"),
        MatrixCase("explicit", "type-explicit-directory", "type ./adir"),
        MatrixCase("diagnostic", "execute-explicit-directory", "./adir; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "command-execute-explicit-directory", "command ./adir; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "missing-command", "PATH=; definitely_missing; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "missing-explicit-path", "./definitely_missing; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "missing-explicit-parent-path", "./missing/child; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "command-missing-explicit-parent-path", "command ./missing/child; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "type-mixed-status", "type : definitely_missing; printf 's=%s\\n' $?", False),
        MatrixCase("path", "path-leading-empty-current", "PATH=:bin1; curpath"),
        MatrixCase("path", "path-trailing-empty-current", "PATH=bin1:; curpath"),
        MatrixCase("path", "path-middle-empty-current-after-miss", "PATH=bin2::bin1; curpath"),
        MatrixCase("path", "path-middle-empty-after-hit", "PATH=bin1::bin2; foo"),
        MatrixCase("path", "path-empty-component-command-v", "PATH=:bin1; command -v curpath"),
        MatrixCase("path", "path-empty-component-command-V", "PATH=:bin1; command -V curpath"),
        MatrixCase("path", "path-empty-component-type", "PATH=:bin1; type curpath"),
        MatrixCase("path", "path-unset-no-host-leak", "unset PATH; command -v sh; printf 's=%s\\n' $?"),
        MatrixCase("path", "path-unset-dot-source-current", "printf 'A=ok\\n' > localdot; unset PATH; . localdot; printf \"$A\""),
        MatrixCase("builtin", "command-v-cd", "command -v cd"),
        MatrixCase("builtin", "command-V-cd", "command -V cd"),
        MatrixCase("builtin", "type-cd", "type cd"),
        MatrixCase("builtin", "command-v-hash", "command -v hash"),
        MatrixCase("builtin", "command-V-hash", "command -V hash"),
        MatrixCase("builtin", "type-hash", "type hash"),
        MatrixCase("builtin", "command-v-ulimit", "command -v ulimit"),
        MatrixCase("builtin", "command-V-ulimit", "command -V ulimit"),
        MatrixCase("builtin", "type-ulimit", "type ulimit"),
        MatrixCase("builtin", "command-v-true-false", "command -v true false"),
        MatrixCase("builtin", "command-V-true-false", "command -V true false"),
        MatrixCase("builtin", "type-true-false", "type true false"),
        MatrixCase("special", "command-v-eval-exec", "command -v eval exec"),
        MatrixCase("special", "command-V-eval-exec", "command -V eval exec"),
        MatrixCase("special", "type-eval-exec", "type eval exec"),
        MatrixCase("special", "command-v-dot-break-continue", "command -v . break continue"),
        MatrixCase("special", "command-V-dot-break-continue", "command -V . break continue"),
        MatrixCase("special", "type-dot-break-continue", "type . break continue"),
        MatrixCase("special", "command-v-set-shift-return-exit", "command -v set shift return exit"),
        MatrixCase("special", "command-V-set-shift-return-exit", "command -V set shift return exit"),
        MatrixCase("special", "type-set-shift-return-exit", "type set shift return exit"),
        MatrixCase("special", "command-v-export-readonly-times-trap-unset", "command -v export readonly times trap unset"),
        MatrixCase("special", "command-V-export-readonly-times-trap-unset", "command -V export readonly times trap unset"),
        MatrixCase("special", "type-export-readonly-times-trap-unset", "type export readonly times trap unset"),
        MatrixCase("alias", "alias-not-visible-to-command-exec", "PATH=bin1; alias foo='printf alias\\n'; command foo"),
        MatrixCase("alias", "alias-visible-to-type-before-path", "PATH=bin1; alias foo='printf alias\\n'; type foo"),
        MatrixCase("function", "function-shadows-path-exec", "PATH=bin1; foo(){ printf fn; }; foo"),
        MatrixCase("function", "command-skips-function-to-path", "PATH=bin1; foo(){ printf fn; }; command foo"),
        MatrixCase("diagnostic", "command-v-missing", "PATH=; command -v definitely_missing; printf 's=%s\\n' $?"),
        MatrixCase("diagnostic", "command-V-missing", "PATH=; command -V definitely_missing; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "type-missing", "PATH=; type definitely_missing; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "command-missing", "PATH=; command definitely_missing; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "plain-missing", "PATH=; definitely_missing; printf 's=%s\\n' $?", True),
        MatrixCase("diagnostic", "command-v-fc-missing", "command -v fc; printf 's=%s\\n' $?"),
        MatrixCase("diagnostic", "command-V-fc-missing", "command -V fc; printf 's=%s\\n' $?", False),
        MatrixCase("diagnostic", "type-fc-missing", "type fc; printf 's=%s\\n' $?", False),
        MatrixCase("explicit", "command-v-dotdot-file", "command -v bin1/foo"),
        MatrixCase("explicit", "command-V-dotdot-file", "command -V bin1/foo"),
        MatrixCase("explicit", "type-dotdot-file", "type bin1/foo"),
        MatrixCase("explicit", "execute-dotdot-file", "bin1/foo"),
    ]


def run_reference_sh(case: MatrixCase, cwd: Path, reference_shell: str) -> RunResult:
    if reference_shell == "wsl-sh":
        return run_wsl_sh(case, cwd)
    proc = run_local_reference_shell(reference_shell, cwd, case.script, RUN_TIMEOUT_SECONDS)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
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
    setup_case_dir(msh_dir)
    setup_case_dir(ref_dir)
    msh_result = run_msh(msh, case, msh_dir)
    ref = run_reference_sh(case, ref_dir, reference_shell)
    match = rows_match(case, msh_result, ref)
    return {
        "group": case.group,
        "name": case.name,
        "script": case.script,
        "compare_stderr": case.compare_stderr,
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
        "# msh Command Search Matrix",
        "",
        "Generated by `msh_command_search_matrix.py` against WSL `/bin/sh`.",
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
    print(f"msh command-search matrix: {matches}/{total} match wsl-sh")
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
    parser = argparse.ArgumentParser(description="Generate the msh command-search matrix.")
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
    cases = matrix_cases()
    if args.reference_shell != "wsl-sh":
        cases = [
            case
            for case in cases
            if not (case.group == "path" and case.name == "path-unset-dot-source-current")
        ]
    with tempfile.TemporaryDirectory(prefix="msh-command-search-matrix-") as raw:
        root = Path(raw)
        rows = [run_case(msh, case, root, args.reference_shell) for case in cases]
    write_json(args.json_report, rows)
    write_markdown(args.report, rows)
    print_summary(rows)
    if args.strict and any(row["matches"] is not True for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
