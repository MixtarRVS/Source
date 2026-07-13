#!/usr/bin/env python3
"""Compare redirection diagnostics and statuses against WSL /bin/sh."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from msh_tool_process import run_tool_cmd


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_JSON = REPORT_DIR / "msh-linux-redirection-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-linux-redirection-matrix.md"
RUN_TIMEOUT_SECONDS = 10
DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")


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


def setup_case_dir(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / "existing").write_text("old\n", encoding="utf-8", newline="\n")
    (root / "input").write_text("input\n", encoding="utf-8", newline="\n")
    (root / "asdir").mkdir(exist_ok=True)
    (root / "readonly").write_text("locked\n", encoding="utf-8", newline="\n")
    (root / "readonly").chmod(0o444)


def normalize_stderr(stderr: str) -> str:
    lines: list[str] = []
    for line in stderr.splitlines():
        line = DIAG_PREFIX_RE.sub("", line)
        if line.startswith("msh: "):
            line = line[5:]
        lines.append(line)
    text = "\n".join(lines)
    if stderr.endswith("\n"):
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
    proc = run_tool_cmd(
        [str(msh), "eval", case.script],
        cwd,
        env=env,
        timeout=RUN_TIMEOUT_SECONDS,
        label=f"redirection:msh:{case.group}/{case.name}",
    )
    parsed = parse_msh_stdout(proc.stdout, proc.returncode)
    return RunResult(parsed.status, parsed.stdout, proc.stderr)


def run_sh(case: MatrixCase, cwd: Path) -> RunResult:
    script = cwd / "case.sh"
    script.write_text(case.script, encoding="utf-8", newline="\n")
    proc = run_tool_cmd(
        ["/bin/sh", str(script)],
        cwd,
        timeout=RUN_TIMEOUT_SECONDS,
        label=f"redirection:sh:{case.group}/{case.name}",
    )
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def builtin_stdout_stderr_script(redirs: str) -> str:
    return "{ printf O; printf E >&2; } " + redirs + "\nread X < out\nprintf '<%s>' \"$X\""


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase("missing-input", "simple-input-missing", ": < missing"),
        MatrixCase("missing-input", "redir-only-input-missing", "< missing; printf after"),
        MatrixCase("missing-input", "regular-input-missing-continues", "printf ok < missing; printf after"),
        MatrixCase("missing-input", "function-input-missing-continues", "f(){ printf body; }\nf < missing; printf after"),
        MatrixCase("missing-input", "group-input-missing-continues", "{ printf body; } < missing; printf after"),
        MatrixCase("missing-input", "subshell-input-missing-continues", "(printf body) < missing; printf after"),
        MatrixCase("missing-input", "if-input-missing-continues", "if true; then printf body; fi < missing; printf after"),
        MatrixCase("missing-input", "while-input-missing-continues", "while false; do printf body; done < missing; printf after"),
        MatrixCase("missing-input", "for-input-missing-continues", "for x in a; do printf body; done < missing; printf after"),
        MatrixCase("missing-input", "case-input-missing-continues", "case x in x) printf body;; esac < missing; printf after"),
        MatrixCase("missing-input", "special-input-missing-aborts", "export A=1 < missing; printf after"),
        MatrixCase("missing-input", "exec-input-missing-aborts", "exec < missing; printf after"),
        MatrixCase("bad-output", "missing-parent-output", ": > missing/out"),
        MatrixCase("bad-output", "missing-parent-append-output", ": >> missing/out"),
        MatrixCase("bad-output", "missing-parent-force-output", ": >| missing/out"),
        MatrixCase("bad-output", "missing-parent-read-write", ": <> missing/out"),
        MatrixCase("bad-output", "regular-missing-parent-output-continues", "printf ok > missing/out; printf after"),
        MatrixCase("bad-output", "function-missing-parent-output-continues", "f(){ printf body; }\nf > missing/out; printf after"),
        MatrixCase("bad-output", "group-missing-parent-output-continues", "{ printf body; } > missing/out; printf after"),
        MatrixCase("bad-output", "subshell-missing-parent-output-continues", "(printf body) > missing/out; printf after"),
        MatrixCase("bad-output", "if-missing-parent-output-continues", "if true; then printf body; fi > missing/out; printf after"),
        MatrixCase("bad-output", "while-missing-parent-output-continues", "while false; do printf body; done > missing/out; printf after"),
        MatrixCase("bad-output", "for-missing-parent-output-continues", "for x in a; do printf body; done > missing/out; printf after"),
        MatrixCase("bad-output", "case-missing-parent-output-continues", "case x in x) printf body;; esac > missing/out; printf after"),
        MatrixCase("bad-output", "special-missing-parent-output-aborts", "export A=1 > missing/out; printf after"),
        MatrixCase("bad-output", "exec-missing-parent-output-aborts", "exec > missing/out; printf after"),
        MatrixCase("bad-output", "directory-output", ": > asdir"),
        MatrixCase("bad-output", "directory-append-output", ": >> asdir"),
        MatrixCase("bad-output", "directory-force-output", ": >| asdir"),
        MatrixCase("bad-output", "directory-read-write", ": <> asdir"),
        MatrixCase("bad-dup", "bad-dup-word", ": 2>&bad"),
        MatrixCase("bad-dup", "bad-dup-closed-fd", ": 2>&9"),
        MatrixCase("bad-dup", "regular-bad-dup-continues", "printf ok >&9; printf after"),
        MatrixCase("bad-dup", "function-bad-dup-continues", "f(){ printf body; }\nf >&9; printf after"),
        MatrixCase("bad-dup", "group-bad-dup-continues", "{ printf body; } >&9; printf after"),
        MatrixCase("bad-dup", "subshell-bad-dup-continues", "(printf body) >&9; printf after"),
        MatrixCase("bad-dup", "if-bad-dup-continues", "if true; then printf body; fi >&9; printf after"),
        MatrixCase("bad-dup", "while-bad-dup-continues", "while false; do printf body; done >&9; printf after"),
        MatrixCase("bad-dup", "for-bad-dup-continues", "for x in a; do printf body; done >&9; printf after"),
        MatrixCase("bad-dup", "case-bad-dup-continues", "case x in x) printf body;; esac >&9; printf after"),
        MatrixCase("bad-dup", "input-bad-dup-word", ": <&bad"),
        MatrixCase("bad-dup", "input-bad-dup-closed-fd", ": <&9"),
        MatrixCase("bad-dup", "input-bad-dup-after-close", "exec 3<&-\n: <&3"),
        MatrixCase("bad-dup", "output-bad-dup-closed-fd-after-close", "exec 3>&-\n: >&3"),
        MatrixCase("fd-close", "command-local-close-stdout-restores", ": 1>&-\nprintf after"),
        MatrixCase("fd-close", "command-local-close-stderr-restores", ": 2>&-\nprintf after >&2"),
        MatrixCase("fd-close", "command-local-close-stdin-restores", "printf input > input2\n: 0<&-\nread A < input2\nprintf '<%s>' \"$A\""),
        MatrixCase("fd-close", "redirection-only-close-fd3-nonfatal", "exec 3> out\n3>&-\nprintf after"),
        MatrixCase("fd-close", "exec-close-fd3-persists", "exec 3> out\nexec 3>&-\nprintf A >&3\nprintf '<%s>' \"$?\""),
        MatrixCase("noclobber", "noclobber-existing", "set -C; : > existing"),
        MatrixCase("noclobber", "redir-only-noclobber-existing", "set -C; > existing; printf after"),
        MatrixCase("noclobber", "regular-noclobber-existing-continues", "set -C; printf ok > existing; printf after"),
        MatrixCase("noclobber", "function-noclobber-existing-continues", "set -C; f(){ printf body; }\nf > existing; printf after"),
        MatrixCase("noclobber", "noclobber-force-existing", "set -C; : >| existing; printf ok"),
        MatrixCase("noclobber", "noclobber-append-existing", "set -C; : >> existing; printf ok"),
        MatrixCase("ambiguous", "empty-target", "A=; : > $A"),
        MatrixCase("ambiguous", "quoted-empty-target", "A=; : > \"$A\""),
        MatrixCase("ambiguous", "multi-field-target", "A='one two'; : > $A"),
        MatrixCase("ambiguous", "quoted-space-target", "A='one two'; : > \"$A\"; printf ok"),
        MatrixCase("ambiguous", "multi-glob-target", ": > glob_a; : > glob_b\n: > glob_*"),
        MatrixCase("ambiguous", "single-glob-target", ": > glob_one\n: > glob_*; printf ok"),
        MatrixCase("ordering", "stdout-stderr-left-to-right-split", builtin_stdout_stderr_script("2>&1 > out")),
        MatrixCase("ordering", "stdout-stderr-left-to-right-join", builtin_stdout_stderr_script("> out 2>&1")),
        MatrixCase("ordering", "heredoc-overridden-by-later-input", "read A <<EOF < input\nhere\nEOF\nprintf '<%s>' \"$A\""),
        MatrixCase("ordering", "input-overridden-by-later-heredoc", "read A < input <<EOF\nhere\nEOF\nprintf '<%s>' \"$A\""),
        MatrixCase("ordering", "truncate-before-command-not-found", "printf old > out\nmissing_cmd > out\nprintf 's=%s\\n' $?\nread X < out\nprintf '<%s>' \"$X\""),
        MatrixCase("ordering", "append-before-command-not-found", "printf old > out\nmissing_cmd >> out\nprintf 's=%s\\n' $?\nread X < out\nprintf '<%s>' \"$X\""),
        MatrixCase("ordering", "command-not-found-stderr-file", "rm -f err\ndefinitely_missing 2> err\nS=$?\n[ -s err ]\nE=$?\nprintf '<%s:%s>' \"$S\" \"$E\""),
        MatrixCase("ordering", "command-not-found-stderr-stdout", "OUT=$(definitely_missing 2>&1)\nS=$?\n[ -n \"$OUT\" ]\nE=$?\nprintf '<%s:%s>' \"$S\" \"$E\""),
        MatrixCase("ordering", "command-not-found-stderr-closed", "definitely_missing 2>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("read-write", "read-write-create", ": <> rw\n[ -f rw ]\nprintf '<%s>' \"$?\""),
        MatrixCase("read-write", "read-write-existing-no-truncate", "printf 'old\\n' > rw\n: <> rw\nread A < rw\nprintf '<%s>' \"$A\""),
        MatrixCase("read-write", "read-write-offset-after-read", "printf 'old\\n' > rw\nexec 3<> rw\nread A <&3\nprintf X >&3\nexec 3>&-\nexec 4< rw\nread B <&4\nread C <&4\nprintf '<%s:%s:%s>' \"$A\" \"$B\" \"$C\""),
        MatrixCase("read-write", "redir-only-read-write-create", "<> rw\n[ -f rw ]\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "printf-stdout-closed", "printf out 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "echo-stdout-closed", "echo out 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "pwd-stdout-closed", "pwd 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "alias-list-stdout-closed", "alias foo=bar\nalias 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "export-list-stdout-closed", "export A=1\nexport -p 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "readonly-list-stdout-closed", "readonly A=1\nreadonly -p 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "set-list-stdout-closed", "A=1\nset 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "umask-list-stdout-closed", "umask 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "trap-list-stdout-closed", "trap 'printf x' INT\ntrap 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "type-stdout-closed", "type echo 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "command-v-stdout-closed", "command -v echo 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("write-failure", "kill-list-stdout-closed", "kill -l 1>&-\nprintf '<%s>' \"$?\""),
        MatrixCase("fd-prefix", "fd9-missing-input", ": 9< missing"),
        MatrixCase("fd-prefix", "fd9-missing-parent-output", ": 9> missing/out"),
        MatrixCase("fd-prefix", "fd9-append-missing-parent-output", ": 9>> missing/out"),
        MatrixCase("fd-prefix", "fd9-read-write-missing-parent-output", ": 9<> missing/out"),
        MatrixCase("fd-prefix", "fd9-dup-stdout-to-file", "printf old > out\n: 9>&1 > out\nprintf after\nread X < out\nprintf '<%s>' \"$X\""),
        MatrixCase("fd-prefix", "fd9-close-is-local", ": 9>&-\nprintf after"),
    ]


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(ref.stderr):
        return False
    return True


def run_case(msh: Path, case: MatrixCase, root: Path, progress: bool) -> dict[str, object]:
    if progress:
        print(f"[redirection] {case.group}/{case.name}", file=sys.stderr, flush=True)
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{case.group}-{case.name}")
    case_root = root / safe
    msh_dir = case_root / "msh"
    ref_dir = case_root / "sh"
    setup_case_dir(msh_dir)
    setup_case_dir(ref_dir)
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
        "# msh Linux Redirection Matrix",
        "",
        "Generated by `msh_linux_redirection_matrix.py` against WSL `/bin/sh`.",
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


def print_summary(rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh linux redirection matrix: {matches}/{total} match wsl-sh")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["reference"]
        print(f"- {row['group']}/{row['name']}")
        print(f"  script: {row['script']!r}")
        print(f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}")
        print(f"  sh:  status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the Linux redirection diagnostic matrix.")
    parser.add_argument("--msh", type=Path, required=True)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--progress", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if os.name == "nt":
        print("msh_linux_redirection_matrix.py must run on Linux/WSL")
        return 2
    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-linux-redirection-matrix-") as raw:
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
