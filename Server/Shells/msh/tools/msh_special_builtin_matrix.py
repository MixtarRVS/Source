#!/usr/bin/env python3
"""Probe POSIX special-builtin error behavior against WSL /bin/sh.

The permanent posix-core suite is hand-authored. This tool generates a broader
matrix so gaps can be discovered before promoting cases into the suite.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from msh_tool_process import run_tool_cmd
from msh_matrix_reference import local_reference_shell_names, run_local_reference_shell
import tempfile
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_JSON = REPORT_DIR / "msh-special-builtin-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-special-builtin-matrix.md"
RUN_TIMEOUT_SECONDS = 10
WSL_DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
_WSL_AVAILABLE: bool | None = None


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    script: str
    compare_stderr: bool = True


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


def wrap_script(wrapper: str, body: str) -> str:
    if wrapper == "direct":
        return body
    if wrapper == "eval":
        escaped = body.replace("'", "'\\''")
        return f"eval '{escaped}'"
    if wrapper == "command":
        return "command " + body
    if wrapper == "command-eval":
        escaped = body.replace("'", "'\\''")
        return f"command eval '{escaped}'"
    raise ValueError(wrapper)


def after(script: str) -> str:
    return script + "\nprintf 'after\\n'\n"


def matrix_cases() -> list[MatrixCase]:
    wrappers = ("direct", "eval", "command", "command-eval")
    definitions = [
        ("colon-redir-missing-input", ": < definitely_missing_file"),
        ("colon-redir-create-fail", ": > __missing_dir__/out"),
        ("dot-missing", ". definitely_missing_file"),
        ("break-invalid", "break bad"),
        ("break-zero", "break 0"),
        ("break-negative", "break -1"),
        ("break-extra-operands", "break 1 2"),
        ("continue-invalid", "continue bad"),
        ("continue-zero", "continue 0"),
        ("continue-negative", "continue -1"),
        ("continue-extra-operands", "continue 1 2"),
        ("return-invalid", "return bad"),
        ("exit-invalid", "exit bad"),
        ("export-invalid", "export 1BAD=1"),
        ("export-invalid-name", "export 1BAD"),
        ("readonly-invalid", "readonly 1BAD=1"),
        ("readonly-invalid-name", "readonly 1BAD"),
        ("set-invalid-option", "set -Z"),
        ("set-invalid-long-option", "set -o definitely_missing_option"),
        ("shift-negative", "shift -1"),
        ("shift-nonnumeric", "shift bad"),
        ("shift-too-many", "shift 99"),
        ("times-extra", "times extra >/dev/null"),
        ("trap-invalid-option", "trap -z"),
        ("trap-invalid-signal", "trap 'printf trap' definitely_missing_signal"),
        ("trap-invalid-numeric-signal", "trap 'printf trap' 999999999999999999999"),
        ("unset-invalid-option", "unset -z"),
        ("unset-invalid-name", "unset 1BAD"),
    ]
    missing_input_defs = [
        ("dot-redir-missing-input", ". < definitely_missing_file"),
        ("eval-redir-missing-input", "eval true < definitely_missing_file"),
        ("exec-redir-missing-input", "exec < definitely_missing_file"),
        ("export-redir-missing-input", "export < definitely_missing_file"),
        ("readonly-redir-missing-input", "readonly < definitely_missing_file"),
        ("set-redir-missing-input", "set -- x < definitely_missing_file"),
        ("shift-redir-missing-input", "set -- x\nshift < definitely_missing_file"),
        ("times-redir-missing-input", "times < definitely_missing_file"),
        ("trap-redir-missing-input", "trap < definitely_missing_file"),
        ("unset-redir-missing-input", "unset A < definitely_missing_file"),
    ]
    create_fail_defs = [
        ("dot-redir-create-fail", "printf 'A=ok\\n' > source.sh\n. ./source.sh > __missing_dir__/out"),
        ("eval-redir-create-fail", "eval true > __missing_dir__/out"),
        ("exec-redir-create-fail", "exec > __missing_dir__/out"),
        ("export-redir-create-fail", "export > __missing_dir__/out"),
        ("readonly-redir-create-fail", "readonly > __missing_dir__/out"),
        ("set-redir-create-fail", "set -- x > __missing_dir__/out"),
        ("shift-redir-create-fail", "set -- x\nshift > __missing_dir__/out"),
        ("times-redir-create-fail", "times > __missing_dir__/out"),
        ("trap-redir-create-fail", "trap > __missing_dir__/out"),
        ("unset-redir-create-fail", "unset A > __missing_dir__/out"),
    ]
    bad_dup_defs = [
        ("colon-redir-bad-dup", ": >&9"),
        ("dot-redir-bad-dup", ". >&9"),
        ("eval-redir-bad-dup", "eval true >&9"),
        ("exec-redir-bad-dup", "exec >&9"),
        ("export-redir-bad-dup", "export >&9"),
        ("readonly-redir-bad-dup", "readonly >&9"),
        ("set-redir-bad-dup", "set -- x >&9"),
        ("shift-redir-bad-dup", "set -- x\nshift >&9"),
        ("times-redir-bad-dup", "times >&9"),
        ("trap-redir-bad-dup", "trap >&9"),
        ("unset-redir-bad-dup", "unset A >&9"),
    ]
    nonnumeric_dup_defs = [
        ("colon-redir-nonnumeric-dup", ": >&bad"),
        ("eval-redir-nonnumeric-dup", "eval true >&bad"),
        ("exec-redir-nonnumeric-dup", "exec >&bad"),
        ("export-redir-nonnumeric-dup", "export >&bad"),
        ("readonly-redir-nonnumeric-dup", "readonly >&bad"),
        ("set-redir-nonnumeric-dup", "set -- x >&bad"),
        ("shift-redir-nonnumeric-dup", "set -- x\nshift >&bad"),
        ("times-redir-nonnumeric-dup", "times >&bad"),
        ("trap-redir-nonnumeric-dup", "trap >&bad"),
        ("unset-redir-nonnumeric-dup", "unset A >&bad"),
    ]
    noclobber_defs = [
        ("colon-redir-noclobber", "printf old > out\nset -C\n: > out"),
        ("eval-redir-noclobber", "printf old > out\nset -C\neval true > out"),
        ("exec-redir-noclobber", "printf old > out\nset -C\nexec > out"),
        ("export-redir-noclobber", "printf old > out\nset -C\nexport > out"),
        ("readonly-redir-noclobber", "printf old > out\nset -C\nreadonly > out"),
        ("set-redir-noclobber", "printf old > out\nset -C\nset -- x > out"),
        ("shift-redir-noclobber", "printf old > out\nset -C\nset -- x\nshift > out"),
        ("times-redir-noclobber", "printf old > out\nset -C\ntimes > out"),
        ("trap-redir-noclobber", "printf old > out\nset -C\ntrap > out"),
        ("unset-redir-noclobber", "printf old > out\nset -C\nunset A > out"),
    ]
    definitions.extend(missing_input_defs)
    definitions.extend(create_fail_defs)
    definitions.extend(bad_dup_defs)
    definitions.extend(nonnumeric_dup_defs)
    definitions.extend(noclobber_defs)
    cases: list[MatrixCase] = []
    for name, body in definitions:
        for wrapper in wrappers:
            script = after(wrap_script(wrapper, body))
            cases.append(MatrixCase(name, wrapper, script))
    expansion_error_defs = [
        ("eval-param-error-arg", "unset A; : ${A:?boom}"),
        ("eval-bad-substitution-arg", "A=abc; : ${A:1}"),
        ("eval-nonnumeric-arith-arg", "A=B; : $((A+1))"),
        ("eval-readonly-arith-assign", "readonly A=1; : $((A=2))"),
        ("eval-divzero-arith-arg", "A=1; : $((1/0))"),
    ]
    for name, body in expansion_error_defs:
        for wrapper in ("direct", "eval", "command", "command-eval"):
            cases.append(MatrixCase(name, wrapper, after(wrap_script(wrapper, body))))
    special_operand_templates = [
        ("colon", ": {operand}"),
        ("dot", ". {operand}"),
        ("break", "break {operand}"),
        ("continue", "continue {operand}"),
        ("eval", "eval {operand}"),
        ("exec", "exec {operand}"),
        ("exit", "exit {operand}"),
        ("export", "export {operand}"),
        ("readonly", "readonly {operand}"),
        ("return", "return {operand}"),
        ("set", "set -- {operand}"),
        ("shift", "shift {operand}"),
        ("times", "times {operand}"),
        ("trap", "trap {operand} TERM"),
        ("unset", "unset {operand}"),
    ]
    special_operand_errors = [
        ("param-error", "${__MSH_SPECIAL_MATRIX_UNSET:?boom}"),
        ("bad-substitution", "${__MSH_SPECIAL_MATRIX_UNSET:1}"),
        ("divzero-arith", "$((1/0))"),
    ]
    for command_name, template in special_operand_templates:
        for error_name, operand in special_operand_errors:
            body = template.replace("{operand}", operand)
            for wrapper in wrappers:
                cases.append(
                    MatrixCase(
                        f"{command_name}-operand-{error_name}",
                        wrapper,
                        after(wrap_script(wrapper, body)),
                    )
                )
    assignment_persistence_defs = [
        ("assignment-persists-colon", "unset A; A=one :; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-break", "unset A; for x in 1; do A=one break; done; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-continue", "unset A; for x in 1; do A=one continue; done; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-eval", "unset A; A=one eval true; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-exec", "unset A; A=one exec; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-export", "unset A B; A=one export B=two; printf '<%s:%s:%s>\\n' \"${A:-}\" \"${B:-}\" $?"),
        ("assignment-persists-readonly", "unset A B; A=one readonly B=two; printf '<%s:%s:%s>\\n' \"${A:-}\" \"${B:-}\" $?"),
        ("assignment-persists-return", "unset A; f(){ A=one return 0; }; f; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-set", "unset A; A=one set -- x; printf '<%s:%s:%s>\\n' \"${A:-}\" \"$#\" $?"),
        ("assignment-persists-shift", "unset A; set -- x; A=one shift; printf '<%s:%s:%s>\\n' \"${A:-}\" \"$#\" $?"),
        ("assignment-persists-times", "unset A; A=one times >/dev/null; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-trap", "unset A; A=one trap; printf '<%s:%s>\\n' \"${A:-}\" $?"),
        ("assignment-persists-unset", "A=old; B=keep; A=one unset B; printf '<%s:%s:%s>\\n' \"${A:-}\" \"${B:-}\" $?"),
        ("assignment-persists-dot", "unset A B; printf 'B=$A\\n' > source.sh; A=one . ./source.sh; printf '<%s:%s:%s>\\n' \"${A:-}\" \"${B:-}\" $?"),
    ]
    for name, body in assignment_persistence_defs:
        for wrapper in wrappers:
            script = wrap_script(wrapper, body)
            cases.append(MatrixCase(name, wrapper, script))
    command_suppression_defs = [
        ("command-suppresses-assignment-colon", 'unset A; A=one command :; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("command-suppresses-assignment-break", 'unset A; for x in 1; do A=one command break; done; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("command-suppresses-assignment-continue", 'unset A; for x in 1; do A=one command continue; done; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("command-suppresses-assignment-dot", 'unset A B; printf "B=$A\\n" > source.sh; A=one command . ./source.sh; printf "<%s:%s:%s>\\n" "${A-unset}" "${B-unset}" "$?"'),
        ("command-suppresses-assignment-eval", 'unset A B; A=one command eval "B=${A-unset}"; printf "<%s:%s:%s>\\n" "${A-unset}" "${B-unset}" "$?"'),
        ("command-suppresses-assignment-exec", 'unset A; A=one command exec; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("command-suppresses-assignment-export", 'unset A B; A=one command export B=two; printf "<%s:%s:%s>\\n" "${A-unset}" "${B-unset}" "$?"'),
        ("command-suppresses-assignment-readonly", 'unset A B; A=one command readonly B=two; printf "<%s:%s:%s>\\n" "${A-unset}" "${B-unset}" "$?"'),
        ("command-suppresses-assignment-return", 'unset A; f(){ A=one command return 0; }; f; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("command-suppresses-assignment-set", 'unset A; A=one command set -- x; printf "<%s:%s:%s>\\n" "${A-unset}" "$#" "$?"'),
        ("command-suppresses-assignment-shift", 'unset A; set -- x; A=one command shift; printf "<%s:%s:%s>\\n" "${A-unset}" "$#" "$?"'),
        ("command-suppresses-assignment-times", 'unset A; A=one command times >/dev/null; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("command-suppresses-assignment-trap", 'unset A; A=one command trap; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("command-suppresses-assignment-unset", 'A=old; B=keep; A=one command unset B; printf "<%s:%s:%s>\\n" "${A-unset}" "${B-unset}" "$?"'),
    ]
    for name, body in command_suppression_defs:
        cases.append(MatrixCase(name, "command", body))
    valid_behavior_defs = [
        ("dot-no-operand", ".; printf '<%s>\\n' $?"),
        ("dot-dashdash-no-operand", ". --; printf '<%s>\\n' $?"),
        ("trap-noargs", "trap; printf '<%s>\\n' $?"),
        ("trap-reset", "trap 'printf hit' INT; trap INT; trap; printf '<%s>\\n' $?"),
        ("readonly-p-extra", "readonly A=one; readonly -p A; printf '<%s>\\n' $?"),
    ]
    for name, body in valid_behavior_defs:
        for wrapper in wrappers:
            script = wrap_script(wrapper, body)
            cases.append(MatrixCase(name, wrapper, script))
    more_valid_defs = [
        ("export-lone-dash", "export -"),
        ("readonly-lone-dash", "readonly -"),
        ("unset-double-dash", 'A=one; unset -- A; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("unset-v-mode", 'A=one; unset -v A; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("unset-fv-combined", 'A=one; f(){ printf bad; }; unset -fv A f; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("unset-vf-combined", 'A=one; f(){ printf bad; }; unset -vf A f; printf "<%s:%s>\\n" "${A-unset}" "$?"'),
        ("set-dashdash-clears-positionals", 'set -- a b; set --; printf "<%s:%s>\\n" "$#" "$?"'),
        ("set-f-dashdash-positional", 'set -f -- a b; printf "<%s:%s:%s>\\n" "$#" "$1" "$?"'),
        ("set-plain-positionals", 'set a b; printf "<%s:%s:%s>\\n" "$#" "$1" "$?"'),
        ("shift-zero", 'set -- a b; shift 0; printf "<%s:%s:%s>\\n" "$#" "$1" "$?"'),
        ("shift-extra-operands", 'set -- a b; shift 1 2; printf "<%s:%s:%s>\\n" "$#" "$1" "$?"'),
        ("eval-no-operands", 'eval; printf "<%s>\\n" $?'),
        ("eval-multiple-operands", 'eval "A=one" "printf \\"<%s>\\\\n\\" \\"\\$A\\""'),
        ("trap-dash-reset", 'trap "printf bad" INT; trap - INT; trap; printf "<%s>\\n" $?'),
        ("trap-double-dash-action", 'trap -- "printf exit" EXIT; trap'),
        ("dot-double-dash-source", 'printf "A=ok\\n" > source.sh; . -- ./source.sh; printf "<%s:%s>\\n" "$A" "$?"'),
        ("dot-path-source", 'printf "A=ok\\n" > source.sh; . ./source.sh; printf "<%s:%s>\\n" "$A" "$?"'),
    ]
    for name, body in more_valid_defs:
        for wrapper in wrappers:
            cases.append(MatrixCase(name, wrapper, after(wrap_script(wrapper, body))))
    limited_valid_defs = [
        ("unset-f-mode", 'f(){ printf bad; }; unset -f f; printf "<%s>\\n" "$?"'),
        ("return-extra-operands", 'f(){ return 7 8; }; f; printf "<%s>\\n" $?'),
        ("return-negative", 'f(){ return -1; }; f; printf "<%s>\\n" $?'),
        ("return-too-large", 'f(){ return 999999999999999999999999; }; f; printf "<%s>\\n" $?'),
    ]
    for name, body in limited_valid_defs:
        for wrapper in ("direct", "eval", "command-eval"):
            cases.append(MatrixCase(name, wrapper, after(wrap_script(wrapper, body))))
    exit_valid_defs = [
        ("exit-extra-operands", "exit 7 8"),
        ("exit-negative", "exit -1"),
        ("exit-too-large", "exit 999999999999999999999999"),
    ]
    for name, body in exit_valid_defs:
        for wrapper in wrappers:
            cases.append(MatrixCase(name, wrapper, wrap_script(wrapper, body)))
    assignment_defs = [
        ("readonly-assignment-colon", "readonly A=old\nA=new :"),
        ("readonly-assignment-dot", "printf 'A=ok\\n' > source.sh\nreadonly A=old\nA=new . ./source.sh"),
        ("readonly-assignment-break", "readonly A=old\nA=new break"),
        ("readonly-assignment-continue", "readonly A=old\nA=new continue"),
        ("readonly-assignment-eval", "readonly A=old\nA=new eval true"),
        ("readonly-assignment-export", "readonly A=old\nexport A=new"),
        ("readonly-assignment-readonly", "readonly A=old\nreadonly A=new"),
        ("readonly-assignment-exec", "readonly A=old\nA=new exec"),
        ("readonly-assignment-exit", "readonly A=old\nA=new exit 0"),
        ("readonly-assignment-return", "readonly A=old\nA=new return"),
        ("readonly-assignment-set", "readonly A=old\nA=new set -- x"),
        ("readonly-assignment-shift", "set -- x\nreadonly A=old\nA=new shift"),
        ("readonly-assignment-times", "readonly A=old\nA=new times >/dev/null"),
        ("readonly-assignment-trap", "readonly A=old\nA=new trap 'printf x' EXIT"),
        ("readonly-assignment-unset", "readonly A=old\nA=new unset B"),
    ]
    for name, body in assignment_defs:
        for wrapper in ("direct", "command"):
            cases.append(MatrixCase(name, wrapper, after(wrap_script(wrapper, body))))
        for wrapper in ("eval", "command-eval"):
            cases.append(MatrixCase(name, wrapper, after(wrap_script(wrapper, body))))
    eval_parse_defs = [
        ("eval-parse-error-if", "eval 'if'; printf after"),
        ("eval-parse-error-for", "eval 'for x'; printf after"),
        ("eval-parse-error-case", "eval 'case x in'; printf after"),
        ("eval-parse-error-subshell", "eval '(printf x'; printf after"),
        ("command-eval-parse-error-if", "command eval 'if'; printf after"),
        ("command-eval-parse-error-for", "command eval 'for x'; printf after"),
        ("command-eval-parse-error-case", "command eval 'case x in'; printf after"),
        ("command-eval-parse-error-subshell", "command eval '(printf x'; printf after"),
    ]
    for name, body in eval_parse_defs:
        cases.append(MatrixCase(name, "parse-error", body))
    eval_readonly_unset_defs = [
        (
            "eval-readonly-unset-v-fatal",
            "no-trailing-newline",
            "eval 'readonly A=old\nunset -v A'",
        ),
        (
            "eval-readonly-unset-v-fatal",
            "trailing-newline",
            "eval 'readonly A=old\nunset -v A'\n",
        ),
        (
            "eval-readonly-unset-v-fatal",
            "following-newline-command",
            "eval 'readonly A=old\nunset -v A'\nprintf after\n",
        ),
        (
            "eval-readonly-unset-v-fatal",
            "following-semicolon-command",
            "eval 'readonly A=old\nunset -v A'; printf after",
        ),
        (
            "command-eval-readonly-unset-v-nonfatal",
            "following-newline-command",
            "readonly A=old\ncommand eval 'unset -v A'\nprintf after\n",
        ),
    ]
    for group, name, body in eval_readonly_unset_defs:
        cases.append(MatrixCase(group, name, body))
    return cases


def run_case(msh: Path, case: MatrixCase, root: Path, reference_shell: str, progress: bool) -> dict[str, object]:
    if progress:
        print(f"[special-builtin] {case.group}/{case.name}", file=sys.stderr, flush=True)
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
        "# msh Special Builtin Matrix",
        "",
        "Generated by `msh_special_builtin_matrix.py` against WSL `/bin/sh`.",
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
    print(f"msh special builtin matrix: {matches}/{total} match wsl-sh")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["wsl_sh"]
        print(f"- {row['group']}/{row['name']}")
        print(f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}")
        print(f"  sh:  status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the msh special-builtin error matrix.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--reference-shell", choices=local_reference_shell_names(), default="wsl-sh")
    parser.add_argument("--progress", action="store_true")
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-special-matrix-") as raw:
        root = Path(raw)
        rows = [run_case(msh, case, root, args.reference_shell, args.progress) for case in matrix_cases()]
    write_json(args.json_report, rows)
    write_markdown(args.report, rows)
    print_summary(rows)
    if args.strict and any(row["matches"] is not True for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
