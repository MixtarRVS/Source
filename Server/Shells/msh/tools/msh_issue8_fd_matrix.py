#!/usr/bin/env python3
"""Compare POSIX.1-2024 multi-digit fd redirections against bash --posix."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from msh_tool_process import run_tool_cmd


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_JSON = REPORT_DIR / "msh-issue8-fd-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-issue8-fd-matrix.md"
RUN_TIMEOUT_SECONDS = 10
DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
_BASH_POSIX_AVAILABLE: bool | None = None


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


def wsl_bash_posix_available() -> bool:
    global _BASH_POSIX_AVAILABLE
    if _BASH_POSIX_AVAILABLE is not None:
        return _BASH_POSIX_AVAILABLE
    proc = run_cmd(["wsl.exe", "--exec", "bash", "--posix", "-c", "echo ok"])
    _BASH_POSIX_AVAILABLE = proc.returncode == 0 and proc.stdout == "ok\n"
    return _BASH_POSIX_AVAILABLE


def windows_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def parse_msh(stdout: str, stderr: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], stderr)
    return RunResult(returncode, stdout, stderr)


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


def run_msh(msh: Path, case: MatrixCase, cwd: Path) -> RunResult:
    proc = run_cmd([str(msh), "eval", case.script], cwd=cwd)
    return parse_msh(proc.stdout, proc.stderr, proc.returncode)


def run_bash_posix(case: MatrixCase, cwd: Path) -> RunResult:
    if not wsl_bash_posix_available():
        return RunResult(127, "", "wsl bash --posix unavailable\n")
    script_path = cwd / "case.sh"
    body = "cd " + windows_to_wsl_path(cwd) + " || exit 125\n" + case.script
    script_path.write_text(body, encoding="utf-8", newline="\n")
    proc = run_cmd(
        ["wsl.exe", "--exec", "bash", "--posix", windows_to_wsl_path(script_path)]
    )
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase(
            "multi-digit-output",
            "fd10-output",
            "exec 10> out\nprintf A >&10\nexec 10>&-\nread X < out\nprintf '<%s>\\n' \"$X\"",
        ),
        MatrixCase(
            "multi-digit-output",
            "fd10-fd11-chain",
            "exec 10> out\nexec 11>&10\nprintf A >&11\nprintf B >&10\nexec 10>&-\nexec 11>&-\nread X < out\nprintf '<%s>\\n' \"$X\"",
        ),
        MatrixCase(
            "multi-digit-input",
            "fd10-input-offset",
            "printf 'A\\nB\\n' > in\nexec 10< in\nexec 11<&10\nread A <&10\nread B <&11\nprintf '<%s:%s>\\n' \"$A\" \"$B\"",
        ),
        MatrixCase(
            "multi-digit-readwrite",
            "fd10-readwrite-shared-offset",
            "printf 'A\\nB\\n' > f\nexec 10<> f\nexec 11<&10\nread A <&10\nprintf X >&11\nexec 10>&-\nexec 11>&-\nread L1 < f\nread L2 < f\nprintf '<%s:%s:%s>\\n' \"$A\" \"$L1\" \"$L2\"",
        ),
        MatrixCase(
            "multi-digit-heredoc",
            "fd10-heredoc",
            "exec 10<<EOF\nA\nEOF\nread A <&10\nprintf '<%s>\\n' \"$A\"",
        ),
        MatrixCase(
            "multi-digit-local",
            "command-local-fd10-restores",
            "exec 10> outer\nprintf I >&10 10> inner\nprintf O >&10\nexec 10>&-\nread A < inner\nread B < outer\nprintf '<%s:%s>\\n' \"$A\" \"$B\"",
        ),
        MatrixCase(
            "multi-digit-local",
            "group-local-fd10-restores",
            "exec 10> outer\n{ printf I >&10; } 10> inner\nprintf O >&10\nexec 10>&-\nread A < inner\nread B < outer\nprintf '<%s:%s>\\n' \"$A\" \"$B\"",
        ),
        MatrixCase(
            "multi-digit-pipeline",
            "pipeline-fd10-right-stage",
            "printf A | { read X; printf \"$X\" >&10; } 10> out\nread Y < out\nprintf '<%s>\\n' \"$Y\"",
        ),
    ]


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(ref.stderr):
        return False
    return True


def run_case(msh: Path, case: MatrixCase, root: Path) -> dict[str, object]:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{case.group}-{case.name}")
    case_root = root / safe
    msh_dir = case_root / "msh"
    ref_dir = case_root / "bash-posix"
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_dir.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir)
    ref = run_bash_posix(case, ref_dir)
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
        "reference_shell": "wsl-bash-posix",
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
        "# msh POSIX Issue 8 FD Matrix",
        "",
        "Generated by `msh_issue8_fd_matrix.py` against WSL `bash --posix`.",
        "This covers POSIX.1-2024 redirection prefixes with one or more digits.",
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
                f"- wsl-bash-posix: status `{ref['status']}`, stdout `{ref['stdout']!r}`, stderr `{ref['normalized_stderr']!r}`",
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_summary(rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh issue8 fd matrix: {matches}/{total} match wsl-bash-posix")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["reference"]
        print(f"- {row['group']}/{row['name']}")
        print(f"  script: {row['script']!r}")
        print(f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}")
        print(f"  ref: status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the msh POSIX Issue 8 fd matrix.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--reference-shell", default="wsl-bash-posix")
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-issue8-fd-matrix-") as raw:
        root = Path(raw)
        rows = [run_case(msh, case, root) for case in matrix_cases()]
    write_json(args.json_report, rows)
    write_markdown(args.report, rows)
    print_summary(rows)
    if args.strict and any(row["matches"] is not True for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
