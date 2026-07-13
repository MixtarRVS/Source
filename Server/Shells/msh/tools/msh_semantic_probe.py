#!/usr/bin/env python3
"""Focused semantic regression probe for MixtarRVS msh.

This is not a POSIX conformance suite. It verifies the subset that msh claims
to implement today and, when WSL is available, compares status behavior against
the host POSIX shell.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

from msh_semantic_cases import (
    default_msh_path,
    diagnostic_cases,
    known_gap_cases,
    output_cases,
    parser_cases,
    run_msh_ast,
    run_msh_eval,
    run_msh_state,
    shell_path,
    run_wsl_status,
    state_cases,
    status_cases,
    stdout_without_status,
    wsl_available,
)


def assert_status_cases(msh: Path, use_wsl: bool) -> list[str]:
    failures: list[str] = []
    for case in status_cases():
        msh_status, msh_out, msh_err = run_msh_eval(msh, case.script)
        expected = case.status
        if use_wsl:
            expected, _, _ = run_wsl_status(case.script)
        if msh_status != expected:
            failures.append(
                f"{case.name}: expected status {expected}, got {msh_status}\n"
                f"  script: {case.script}\n"
                f"  stdout: {msh_out!r}\n"
                f"  stderr: {msh_err!r}"
            )
    return failures


def assert_parser_cases(msh: Path) -> list[str]:
    failures: list[str] = []
    for case in parser_cases():
        proc = run_msh_ast(msh, case.script)
        parsed = proc.returncode == 0
        if parsed != case.should_parse:
            want = "parse" if case.should_parse else "fail"
            got = "parsed" if parsed else "failed"
            failures.append(
                f"{case.name}: expected {want}, got {got}\n"
                f"  script: {case.script}\n"
                f"  stdout: {proc.stdout!r}\n"
                f"  stderr: {proc.stderr!r}"
            )
    return failures


def assert_output_cases(msh: Path, tempdir: Path) -> list[str]:
    failures: list[str] = []
    for case in output_cases(tempdir):
        status, stdout, stderr = run_msh_eval(msh, case.script, cwd=tempdir)
        actual = stdout_without_status(stdout)
        if status != case.status or actual != case.stdout:
            failures.append(
                f"{case.name}: expected status/stdout {case.status}/{case.stdout!r}, "
                f"got {status}/{actual!r}\n"
                f"  script: {case.script}\n"
                f"  raw stdout: {stdout!r}\n"
                f"  stderr: {stderr!r}"
            )
    return failures


def assert_diagnostic_cases(msh: Path, tempdir: Path) -> list[str]:
    failures: list[str] = []
    for case in diagnostic_cases(tempdir):
        status, stdout, stderr = run_msh_eval(msh, case.script, cwd=tempdir)
        stderr_matches = stderr == case.stderr_contains if case.stderr_exact else case.stderr_contains in stderr
        if status != case.status or not stderr_matches:
            failures.append(
                f"{case.name}: expected status/stderr {case.status}/{case.stderr_contains!r}, "
                f"got {status}/{stderr!r}\n"
                f"  script: {case.script}\n"
                f"  stdout: {stdout!r}"
            )
    return failures


def assert_state_cases(msh: Path, tempdir: Path) -> list[str]:
    failures: list[str] = []
    for case in state_cases(tempdir):
        status, values, stdout, stderr = run_msh_state(msh, case.script, cwd=tempdir)
        if status != case.status:
            failures.append(
                f"{case.name}: expected status {case.status}, got {status}\n"
                f"  script: {case.script}\n"
                f"  stdout: {stdout!r}\n"
                f"  stderr: {stderr!r}"
            )
            continue
        for key, value in case.vars.items():
            if values.get(key) != value:
                failures.append(
                    f"{case.name}: expected {key}={value!r}, got {values.get(key)!r}\n"
                    f"  script: {case.script}\n"
                    f"  state: {values!r}"
                )
        for key in case.absent:
            if key in values:
                failures.append(
                    f"{case.name}: expected {key} to be absent, got {values[key]!r}\n"
                    f"  script: {case.script}\n"
                    f"  state: {values!r}"
                )
    return failures


def assert_redirection_only(msh: Path, tempdir: Path) -> list[str]:
    failures: list[str] = []
    targets = [
        (">", tempdir / "redir-created.txt", 0),
        (">>", tempdir / "redir-appended.txt", 0),
        ("<>", tempdir / "redir-read-write.txt", 0),
    ]
    for op, target, expected in targets:
        status, stdout, stderr = run_msh_eval(msh, f"{op} {target.name}", cwd=tempdir)
        if status != expected or not target.exists():
            failures.append(
                f"redirection-only {op} failed: "
                f"status={status}, exists={target.exists()}, stdout={stdout!r}, stderr={stderr!r}"
            )
    missing_status, missing_out, missing_err = run_msh_eval(msh, "< __missing_input__", cwd=tempdir)
    if missing_status == 0:
        failures.append(
            "redirection-only missing input unexpectedly succeeded: "
            f"stdout={missing_out!r}, stderr={missing_err!r}"
        )
    compound_targets = [
        ("group stdout redirection", "{ command -v true; } > group-out.txt", tempdir / "group-out.txt", "true"),
        ("subshell stdout redirection", "( command -v true ) > subshell-out.txt", tempdir / "subshell-out.txt", "true"),
        ("printf stdout redirection", "printf 'x\\n' > printf-out.txt", tempdir / "printf-out.txt", "x\n"),
        ("command printf stdout redirection", "command printf 'x\\n' > command-printf-out.txt", tempdir / "command-printf-out.txt", "x\n"),
        ("command export stdout redirection", "export A=one; command export -p > command-export-out.txt", tempdir / "command-export-out.txt", "export A='one'\n"),
        ("pwd stdout redirection", "pwd > pwd-out.txt", tempdir / "pwd-out.txt", shell_path(tempdir) + "\n"),
        ("if trailing redirection", "if true; then command -v true; fi > if-out.txt", tempdir / "if-out.txt", "true"),
        ("while trailing redirection", "while true; do command -v true; break; done > while-out.txt", tempdir / "while-out.txt", "true"),
        ("for trailing redirection", "for x in a; do command -v true; done > for-out.txt", tempdir / "for-out.txt", "true"),
        ("case trailing redirection", "case x in x) command -v true;; esac > case-out.txt", tempdir / "case-out.txt", "true"),
        ("function definition redirection", "f() { command -v true; } > function-out.txt; f", tempdir / "function-out.txt", "true"),
        ("exec redirection-only create", "exec > exec-only.txt", tempdir / "exec-only.txt", ""),
    ]
    for name, script, target, prefix in compound_targets:
        status, stdout, stderr = run_msh_eval(msh, script, cwd=tempdir)
        content = target.read_text(encoding="utf-8") if target.exists() else ""
        if status != 0 or not target.exists() or not content.startswith(prefix):
            failures.append(
                f"{name} failed: status={status}, exists={target.exists()}, "
                f"content={content!r}, stdout={stdout!r}, stderr={stderr!r}"
            )
    return failures


def inspect_known_gaps(msh: Path, use_wsl: bool) -> tuple[int, list[str]]:
    closed = 0
    notes: list[str] = []
    if not use_wsl:
        return closed, ["known gap probes skipped without WSL sh"]
    for case in known_gap_cases():
        msh_status, msh_out, msh_err = run_msh_eval(msh, case.script)
        wsl_status, _, _ = run_wsl_status(case.script)
        if msh_status == wsl_status:
            closed += 1
            notes.append(f"closed? {case.name}: now matches WSL status {wsl_status}")
        else:
            notes.append(
                f"open: {case.name}: msh={msh_status}, wsl={wsl_status}; {case.why}"
            )
    return closed, notes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--msh", type=Path, default=default_msh_path())
    parser.add_argument("--no-wsl", action="store_true")
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2

    use_wsl = (not args.no_wsl) and wsl_available()
    failures: list[str] = []
    state_count = 0
    gap_notes: list[str] = []
    gap_closed = 0
    with tempfile.TemporaryDirectory(prefix="msh-semantic-") as raw:
        tempdir = Path(raw)
        state_count = len(state_cases(tempdir))
        failures.extend(assert_parser_cases(msh))
        failures.extend(assert_status_cases(msh, use_wsl))
        failures.extend(assert_output_cases(msh, tempdir))
        failures.extend(assert_diagnostic_cases(msh, tempdir))
        failures.extend(assert_state_cases(msh, tempdir))
        failures.extend(assert_redirection_only(msh, tempdir))
        gap_closed, gap_notes = inspect_known_gaps(msh, use_wsl)

    if failures:
        print("msh semantic probe: FAILED")
        for failure in failures:
            print(f"\n- {failure}")
        return 1

    source = "WSL sh differential" if use_wsl else "local expected-status only"
    print(f"msh semantic probe: ok ({source})")
    print(f"parser cases: {len(parser_cases())}")
    print(f"status cases: {len(status_cases())}")
    with tempfile.TemporaryDirectory(prefix="msh-output-count-") as raw_count:
        print(f"output cases: {len(output_cases(Path(raw_count)))}")
    with tempfile.TemporaryDirectory(prefix="msh-diagnostic-count-") as raw_diag:
        print(f"diagnostic cases: {len(diagnostic_cases(Path(raw_diag)))}")
    print(f"state cases: {state_count}")
    print("redirection-only cases: 15")
    print(f"known gap probes: {len(known_gap_cases())} ({gap_closed} unexpectedly matched)")
    for note in gap_notes:
        print(f"  {note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
