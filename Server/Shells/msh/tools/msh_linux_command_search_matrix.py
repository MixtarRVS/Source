#!/usr/bin/env python3
"""Compare Linux-native command-search diagnostics against /bin/sh."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_JSON = REPORT_DIR / "msh-linux-command-search-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-linux-command-search-matrix.md"
RUN_TIMEOUT_SECONDS = 10
DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    script: str
    compare_stderr: bool = True
    reference_shell: str = "wsl-sh"


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def write_script(path: Path, text: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    path.chmod(mode)


def setup_case_dir(root: Path) -> None:
    blocked = root / "blocked"
    later = root / "later"
    blocked.mkdir(parents=True, exist_ok=True)
    later.mkdir(parents=True, exist_ok=True)
    write_script(blocked / "probe", "printf 'blocked\\n'\n", 0o644)
    write_script(later / "probe", "printf 'later\\n'\n", 0o755)
    write_script(root / "noexec", "printf 'noexec\\n'\n", 0o644)
    write_script(root / "plain", "printf 'plain\\n'\n", 0o755)
    write_script(root / "reader", "read X\nprintf 'got:%s\\n' \"$X\"\n", 0o755)
    write_script(blocked / "source_probe", "printf 'blocked-source\\n'\n", 0o333)
    write_script(later / "source_probe", "printf 'later-source\\n'\n", 0o444)
    write_script(root / "unreadable_source", "printf 'hidden\\n'\n", 0o000)
    (root / "asdir").mkdir(exist_ok=True)


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
    proc = subprocess.run(
        [str(msh), "eval", case.script],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=RUN_TIMEOUT_SECONDS,
        check=False,
    )
    parsed = parse_msh_stdout(proc.stdout, proc.returncode)
    return RunResult(parsed.status, parsed.stdout, proc.stderr)


def run_reference_shell(case: MatrixCase, cwd: Path) -> RunResult:
    script = cwd / "case.sh"
    script.write_text(case.script, encoding="utf-8", newline="\n")
    if case.reference_shell == "wsl-bash-posix":
        argv = ["bash", "--posix", str(script)]
    else:
        argv = ["/bin/sh", str(script)]
    proc = subprocess.run(
        argv,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=RUN_TIMEOUT_SECONDS,
        check=False,
    )
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase("path-permission", "path-skips-nonexec-to-later", "PATH=blocked:later; probe"),
        MatrixCase("path-permission", "path-only-nonexec-command", "PATH=blocked; probe"),
        MatrixCase("path-permission", "command-v-only-nonexec", "PATH=blocked; command -v probe; printf '<%s>\\n' $?"),
        MatrixCase("path-permission", "command-V-only-nonexec", "PATH=blocked; command -V probe; printf '<%s>\\n' $?"),
        MatrixCase("path-permission", "type-only-nonexec", "PATH=blocked; type probe; printf '<%s>\\n' $?"),
        MatrixCase("explicit-permission", "explicit-nonexec", "./noexec"),
        MatrixCase("explicit-permission", "command-explicit-nonexec", "command ./noexec"),
        MatrixCase("explicit-permission", "pipeline-left-nonexec", "./noexec | :"),
        MatrixCase("explicit-permission", "pipeline-tail-nonexec", "printf x | ./noexec"),
        MatrixCase("explicit-directory", "explicit-directory", "./asdir; printf '<%s>\\n' $?"),
        MatrixCase("explicit-directory", "command-explicit-directory", "command ./asdir; printf '<%s>\\n' $?"),
        MatrixCase("script-fallback", "path-text-script", "PATH=.; plain"),
        MatrixCase("script-fallback", "explicit-text-script", "./plain"),
        MatrixCase("script-fallback", "command-p-explicit-text-script", "command -p ./plain"),
        MatrixCase("script-fallback", "exec-explicit-text-script", "exec ./plain; printf bad"),
        MatrixCase("script-fallback", "pipeline-text-script-consumer", "printf 'pipe-script\\n' | ./reader"),
        MatrixCase(
            "dot-permission",
            "dot-skips-unreadable-path-candidate",
            "PATH=blocked:later; . source_probe",
            reference_shell="wsl-bash-posix",
        ),
        MatrixCase("dot-permission", "dot-explicit-unreadable", ". ./unreadable_source"),
    ]


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(ref.stderr):
        return False
    return True


def run_case(msh: Path, case: MatrixCase, root: Path, progress: bool) -> dict[str, object]:
    if progress:
        print(f"[command-search-linux] {case.group}/{case.name}", file=sys.stderr, flush=True)
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{case.group}-{case.name}")
    case_root = root / safe
    msh_dir = case_root / "msh"
    ref_dir = case_root / "sh"
    setup_case_dir(msh_dir)
    setup_case_dir(ref_dir)
    msh_result = run_msh(msh, case, msh_dir)
    ref = run_reference_shell(case, ref_dir)
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
        "reference_shell": case.reference_shell,
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
        "# msh Linux Command-Search Matrix",
        "",
        (
            "Generated by `msh_linux_command_search_matrix.py` against WSL "
            "reference shells. Most cases use `/bin/sh`; the dot-source "
            "readable-`PATH` search case uses `bash --posix` because WSL "
            "`/bin/sh` stops at an unreadable candidate even though "
            "POSIX.1-2024 specifies failure only if no readable file is found."
        ),
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
                f"- {row['reference_shell']}: status `{ref['status']}`, stdout `{ref['stdout']!r}`, stderr `{ref['normalized_stderr']!r}`",
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_summary(rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh linux command-search matrix: {matches}/{total} match WSL reference shells")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["reference"]
        print(f"- {row['group']}/{row['name']}")
        print(f"  script: {row['script']!r}")
        print(f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}")
        print(f"  {row['reference_shell']}: status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the Linux command-search matrix.")
    parser.add_argument("--msh", type=Path, required=True)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--progress", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if os.name == "nt":
        print("msh_linux_command_search_matrix.py must run on Linux/WSL")
        return 2
    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-linux-command-search-matrix-") as raw:
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
