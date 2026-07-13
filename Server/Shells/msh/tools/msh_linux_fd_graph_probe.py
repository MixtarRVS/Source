#!/usr/bin/env python3
"""Linux-native fd/process graph differential probe for msh.

This must run on Linux/WSL. It compares msh with /bin/sh for wider fd graphs
that Windows-hosted tests cannot prove.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


RUN_TIMEOUT_SECONDS = 30


@dataclass(frozen=True)
class FdCase:
    name: str
    script: str
    compare_stderr: bool = False


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def body_without_marker(stdout: str) -> str:
    lines = stdout.splitlines(keepends=True)
    if lines and lines[-1].startswith("status="):
        return "".join(lines[:-1])
    return stdout


def parse_msh(proc: subprocess.CompletedProcess[str]) -> RunResult:
    lines = proc.stdout.splitlines(keepends=True)
    if lines and lines[-1].startswith("status="):
        marker = lines[-1].strip()[7:]
        try:
            status = int(marker)
        except ValueError:
            status = proc.returncode
        return RunResult(status, "".join(lines[:-1]), proc.stderr)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def run_cmd(argv: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            argv,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=RUN_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        if stderr:
            stderr += "\n"
        stderr += f"timeout after {RUN_TIMEOUT_SECONDS}s"
        return subprocess.CompletedProcess(argv, 124, stdout, stderr)


def run_msh(msh: Path, source: str, cwd: Path) -> RunResult:
    proc = run_cmd([str(msh), "eval", source], cwd)
    return parse_msh(proc)


def run_sh(source: str, cwd: Path) -> RunResult:
    script = cwd / "case.sh"
    script.write_text(source, encoding="utf-8", newline="\n")
    proc = run_cmd(["/bin/sh", str(script)], cwd)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def normalize_stderr(text: str) -> str:
    lines: list[str] = []
    for line in text.splitlines():
        if line.startswith("msh: "):
            line = line[5:]
        if ": " in line and line.split(": ", 1)[0].endswith("case.sh"):
            line = line.split(": ", 1)[1]
        lines.append(line)
    out = "\n".join(lines)
    if text.endswith("\n"):
        out += "\n"
    return out


def rows_match(case: FdCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(ref.stderr):
        return False
    return True


def cases() -> list[FdCase]:
    return [
        FdCase(
            "fd8 external child and parent share output offset",
            "exec 8>out\n"
            "sh -c 'printf A >&8'\n"
            "printf B >&8\n"
            "exec 8>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "fd9 duplicate survives fd8 close",
            "exec 8>out\n"
            "exec 9>&8\n"
            "exec 8>&-\n"
            "sh -c 'printf A >&9'\n"
            "printf B >&9\n"
            "exec 9>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "fd8 external child advances input offset",
            "printf 'A\\nB\\nC\\n' > in\n"
            "exec 8<in\n"
            "sh -c 'read X <&8; printf \"%s\\n\" \"$X\"'\n"
            "read Y <&8\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "fd9 duplicate input survives fd8 close",
            "printf 'A\\nB\\n' > in\n"
            "exec 8<in\n"
            "exec 9<&8\n"
            "exec 8<&-\n"
            "sh -c 'read X <&9; printf \"%s\\n\" \"$X\"'\n"
            "read Y <&9\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "function and external child share fd8 output",
            "exec 8>out\n"
            "f() { printf A >&8; sh -c 'printf B >&8'; }\n"
            "f\n"
            "printf C >&8\n"
            "exec 8>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "group trailing fd8 redirection reaches external child",
            "{ sh -c 'printf A >&8'; printf B >&8; } 8>out\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "subshell fd close does not leak to parent",
            "exec 8>out\n"
            "(exec 8>&-)\n"
            "printf A >&8\n"
            "exec 8>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "command-local fd8 redirection reaches external child",
            "sh -c 'printf A >&8' 8>out\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "pipeline-stage fd8 redirection reaches external child",
            "printf ignored | sh -c 'cat >/dev/null; printf A >&8' 8>out\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "pipeline child writes fd9 duplicate after fd8 close",
            "exec 8>out\n"
            "exec 9>&8\n"
            "exec 8>&-\n"
            "printf ignored | sh -c 'cat >/dev/null; printf A >&9'\n"
            "printf B >&9\n"
            "exec 9>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "append fd8 preserves existing content",
            "printf Z > out\n"
            "exec 8>>out\n"
            "sh -c 'printf A >&8'\n"
            "printf B >&8\n"
            "exec 8>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "command-local fd8 input feeds external child only",
            "printf 'A\\nB\\n' > in\n"
            "sh -c 'read X <&8; printf \"%s\\n\" \"$X\"' 8<in\n"
            "read Y < in\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "persistent current stdin file external child advances",
            "printf 'A\\nB\\n' > in\n"
            "exec < in\n"
            "sh -c 'read X; printf \"<%s>\\n\" \"$X\"'\n"
            "read Y\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "persistent stdin heredoc feeds external child",
            "exec <<EOF\n"
            "A\n"
            "B\n"
            "EOF\n"
            "sh -c 'read X; printf \"<%s>\\n\" \"$X\"'\n"
            "read Y\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "persistent fd8 heredoc feeds external child",
            "exec 8<<EOF\n"
            "A\n"
            "B\n"
            "EOF\n"
            "sh -c 'read X <&8; printf \"<%s>\\n\" \"$X\"'\n"
            "read Y <&8\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "fd8 heredoc duplicate feeds external child",
            "exec 8<<EOF\n"
            "A\n"
            "B\n"
            "EOF\n"
            "exec 9<&8\n"
            "sh -c 'read X <&9; printf \"<%s>\\n\" \"$X\"'\n"
            "read Y <&8\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "pipeline right external reads persistent fd8 heredoc",
            "exec 8<<EOF\n"
            "A\n"
            "EOF\n"
            "printf ignored | sh -c 'cat >/dev/null; read X <&8; printf \"<%s>\\n\" \"$X\"'\n",
        ),
        FdCase(
            "subshell closes fd8 heredoc without parent leak",
            "exec 8<<EOF\n"
            "A\n"
            "EOF\n"
            "(exec 8<&-)\n"
            "read X <&8\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "command-local fd8 heredoc external child only",
            "sh -c 'read X <&8; printf \"<%s>\\n\" \"$X\"' 8<<EOF\n"
            "A\n"
            "EOF\n"
            "read Y <<EOF\n"
            "B\n"
            "EOF\n"
            "printf '<%s>\\n' \"$Y\"\n",
        ),
        FdCase(
            "append fd8 duplicate external child chain",
            "printf Z > out\n"
            "exec 8>>out\n"
            "exec 9>&8\n"
            "sh -c 'printf A >&9'\n"
            "printf B >&8\n"
            "exec 8>&-\n"
            "exec 9>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
        FdCase(
            "mixed nested group external fd8 output",
            "exec 8>out\n"
            "{ sh -c 'printf A >&8'; { sh -c 'printf B >&8'; }; }\n"
            "printf C >&8\n"
            "exec 8>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"\n",
        ),
    ]


def run_case(msh: Path, case: FdCase, root: Path) -> dict[str, object]:
    case_dir = root / case.name.replace(" ", "-").replace("/", "-")
    msh_dir = case_dir / "msh"
    sh_dir = case_dir / "sh"
    msh_dir.mkdir(parents=True)
    sh_dir.mkdir(parents=True)
    msh_result = run_msh(msh, case.script, msh_dir)
    ref = run_sh(case.script, sh_dir)
    ok = rows_match(case, msh_result, ref)
    return {
        "name": case.name,
        "script": case.script,
        "matches": ok,
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
            "normalized_stderr": normalize_stderr(msh_result.stderr),
        },
        "sh": {
            "status": ref.status,
            "stdout": ref.stdout,
            "stderr": ref.stderr,
            "normalized_stderr": normalize_stderr(ref.stderr),
        },
    }


def write_reports(rows: list[dict[str, object]], json_path: Path, md_path: Path) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    lines = [
        "# msh Linux FD Graph Probe",
        "",
        "Generated by `msh_linux_fd_graph_probe.py` against Linux `/bin/sh`.",
        "",
        f"- Overall: `{matches}/{total}`",
        "",
        "## Mismatches",
        "",
    ]
    mismatches = [row for row in rows if row["matches"] is not True]
    if not mismatches:
        lines.append("No mismatches.")
        lines.append("")
    for row in mismatches:
        msh = row["msh"]
        sh = row["sh"]
        lines.extend([
            f"### {row['name']}",
            "",
            "```sh",
            str(row["script"]).rstrip(),
            "```",
            "",
            f"- msh: status `{msh['status']}`, stdout `{msh['stdout']!r}`, stderr `{msh['normalized_stderr']!r}`",
            f"- sh: status `{sh['status']}`, stdout `{sh['stdout']!r}`, stderr `{sh['normalized_stderr']!r}`",
            "",
        ])
    md_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_summary(rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh linux fd graph probe: {matches}/{total} match /bin/sh")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        sh = row["sh"]
        print(f"- {row['name']}", file=sys.stderr)
        print(f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}", file=sys.stderr)
        print(f"  sh:  status={sh['status']} stdout={sh['stdout']!r} stderr={sh['normalized_stderr']!r}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Linux-native fd graph differential probe.")
    parser.add_argument("--msh", required=True, type=Path)
    parser.add_argument("--json-report", type=Path, default=Path("Server/Generated/reports/msh-linux-fd-graph.json"))
    parser.add_argument("--report", type=Path, default=Path("Server/Generated/reports/msh-linux-fd-graph.md"))
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if os.name == "nt":
        print("msh_linux_fd_graph_probe.py must run on Linux/WSL", file=sys.stderr)
        return 2
    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-linux-fd-graph-") as raw:
        root = Path(raw)
        rows = [run_case(msh, case, root) for case in cases()]
    write_reports(rows, args.json_report, args.report)
    print_summary(rows)
    if args.strict and any(row["matches"] is not True for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
