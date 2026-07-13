#!/usr/bin/env python3
"""Linux-native arbitrary-fd/process matrix for msh.

This must run on Linux/WSL. It compares msh with `bash --posix` because
multi-digit fd prefixes are part of the POSIX Issue 8 target, while many
legacy `/bin/sh` implementations only reliably cover fd 0..9.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_JSON = REPORT_DIR / "msh-linux-arbitrary-fd-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-linux-arbitrary-fd-matrix.md"
RUN_TIMEOUT_SECONDS = 10
FD_LIST = (3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 19)
DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    fd: int
    script: str
    compare_stderr: bool = False


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def child_print(fd: int, text: str) -> str:
    return f"bash --posix -c 'printf {text} >&{fd}'"


def child_read(fd: int, template: str = '"<%s>\\n"') -> str:
    return f"bash --posix -c 'read X <&{fd}; printf {template} \"$X\"'"


def close_output(fd: int) -> str:
    return f"exec {fd}>&-"


def close_input(fd: int) -> str:
    return f"exec {fd}<&-"


def safe_name(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", text)


def normalize_stderr(stderr: str) -> str:
    lines: list[str] = []
    for line in stderr.splitlines():
        line = DIAG_PREFIX_RE.sub("", line)
        if line.startswith("msh: "):
            line = line[5:]
        lines.append(line)
    out = "\n".join(lines)
    if stderr.endswith("\n"):
        out += "\n"
    return out


def text_from_pipe(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return value.decode("utf-8", errors="replace")


def run_cmd(argv: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
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
        stdout, stderr = proc.communicate(timeout=RUN_TIMEOUT_SECONDS)
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
        stderr += f"timeout after {RUN_TIMEOUT_SECONDS}s"
        return subprocess.CompletedProcess(argv, 124, stdout, stderr)


def parse_msh_stdout(stdout: str, returncode: int, stderr: str) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], stderr)
    return RunResult(returncode, stdout, stderr)


def run_msh(msh: Path, case: MatrixCase, cwd: Path) -> RunResult:
    env = os.environ.copy()
    env["AILANG_LEAK_REPORT"] = "0"
    try:
        proc = subprocess.run(
            [str(msh), "eval", case.script],
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            timeout=RUN_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stderr = text_from_pipe(exc.stderr)
        if stderr:
            stderr += "\n"
        stderr += f"timeout after {RUN_TIMEOUT_SECONDS}s"
        return RunResult(124, text_from_pipe(exc.stdout), stderr)
    return parse_msh_stdout(proc.stdout, proc.returncode, proc.stderr)


def run_ref(case: MatrixCase, cwd: Path) -> RunResult:
    script = cwd / "case.sh"
    script.write_text(case.script, encoding="utf-8", newline="\n")
    proc = run_cmd(["bash", "--posix", str(script)], cwd)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(ref.stderr):
        return False
    return True


def read_out_script() -> str:
    return "read X < out\nprintf '<%s>\\n' \"$X\"\n"


def fd_cases(fd: int) -> list[MatrixCase]:
    dup = 18 if fd == 19 else 19
    cases = [
        MatrixCase(
            "persistent-output",
            "child-and-parent-share-output-offset",
            fd,
            f"exec {fd}>out\n{child_print(fd, 'A')}\nprintf B >&{fd}\n{close_output(fd)}\n{read_out_script()}",
        ),
        MatrixCase(
            "command-local-output",
            "command-local-redirection-reaches-child",
            fd,
            f"{child_print(fd, 'A')} {fd}>out\n{read_out_script()}",
        ),
        MatrixCase(
            "group-output",
            "group-redirection-reaches-child-and-parent",
            fd,
            f"{{ {child_print(fd, 'A')}; printf B >&{fd}; }} {fd}>out\n{read_out_script()}",
        ),
        MatrixCase(
            "pipeline-output",
            "pipeline-stage-redirection-reaches-child",
            fd,
            f"printf ignored | bash --posix -c 'cat >/dev/null; printf A >&{fd}' {fd}>out\n{read_out_script()}",
        ),
        MatrixCase(
            "append-output",
            "append-shares-output-offset",
            fd,
            f"printf Z > out\nexec {fd}>>out\n{child_print(fd, 'A')}\nprintf B >&{fd}\n{close_output(fd)}\n{read_out_script()}",
        ),
        MatrixCase(
            "dup-output",
            "duplicate-survives-source-close",
            fd,
            f"exec {fd}>out\nexec {dup}>&{fd}\n{close_output(fd)}\n{child_print(dup, 'A')}\nprintf B >&{dup}\nexec {dup}>&-\n{read_out_script()}",
        ),
        MatrixCase(
            "subshell-isolation",
            "subshell-close-does-not-leak",
            fd,
            f"exec {fd}>out\n(exec {fd}>&-)\nprintf A >&{fd}\n{close_output(fd)}\n{read_out_script()}",
        ),
        MatrixCase(
            "persistent-input",
            "child-advances-input-offset",
            fd,
            f"printf 'A\\nB\\n' > in\nexec {fd}<in\n{child_read(fd)}\nread Y <&{fd}\nprintf '<%s>\\n' \"$Y\"\n{close_input(fd)}\n",
        ),
        MatrixCase(
            "command-local-input",
            "command-local-input-does-not-touch-parent",
            fd,
            f"printf 'A\\nB\\n' > in\n{child_read(fd)} {fd}<in\nread Y < in\nprintf '<%s>\\n' \"$Y\"\n",
        ),
        MatrixCase(
            "dup-input",
            "duplicate-input-survives-source-close",
            fd,
            f"printf 'A\\nB\\n' > in\nexec {fd}<in\nexec {dup}<&{fd}\n{close_input(fd)}\n{child_read(dup)}\nread Y <&{dup}\nprintf '<%s>\\n' \"$Y\"\nexec {dup}<&-\n",
        ),
        MatrixCase(
            "heredoc-input",
            "persistent-heredoc-feeds-child-and-parent",
            fd,
            f"exec {fd}<<EOF\nA\nB\nEOF\n{child_read(fd)}\nread Y <&{fd}\nprintf '<%s>\\n' \"$Y\"\n{close_input(fd)}\n",
        ),
        MatrixCase(
            "readwrite",
            "read-then-write-shares-offset",
            fd,
            f"printf 'A\\nB\\n' > rw\nexec {fd}<>rw\nread X <&{fd}\nprintf C >&{fd}\nexec {fd}>&-\ncat rw\n",
        ),
        MatrixCase(
            "readwrite",
            "dup-readwrite-fd-shares-offset",
            fd,
            f"printf 'A\\nB\\n' > rw\nexec {fd}<>rw\nexec {dup}<&{fd}\nread X <&{fd}\nprintf C >&{dup}\nexec {fd}>&-\nexec {dup}>&-\ncat rw\n",
        ),
    ]
    return cases


def matrix_cases() -> list[MatrixCase]:
    out: list[MatrixCase] = []
    for fd in FD_LIST:
        out.extend(fd_cases(fd))
    return out


def run_case(msh: Path, case: MatrixCase, root: Path, progress: bool) -> dict[str, object]:
    if progress:
        print(f"[arbitrary-fd] fd{case.fd} {case.group}/{case.name}", file=sys.stderr, flush=True)
    case_root = root / safe_name(f"{case.group}-{case.name}-fd{case.fd}")
    msh_dir = case_root / "msh"
    ref_dir = case_root / "bash-posix"
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_dir.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir)
    ref = run_ref(case, ref_dir)
    return {
        "group": case.group,
        "name": case.name,
        "fd": case.fd,
        "script": case.script,
        "compare_stderr": case.compare_stderr,
        "matches": rows_match(case, msh_result, ref),
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
            "normalized_stderr": normalize_stderr(msh_result.stderr),
        },
        "reference_shell": "bash --posix",
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
        "# msh Linux Arbitrary FD Matrix",
        "",
        "Generated by `msh_linux_arbitrary_fd_matrix.py` against WSL `bash --posix`.",
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
                f"### fd {row['fd']} {row['group']}/{row['name']}",
                "",
                "```sh",
                str(row["script"]).rstrip(),
                "```",
                "",
                f"- msh: status `{msh['status']}`, stdout `{msh['stdout']!r}`, stderr `{msh['normalized_stderr']!r}`",
                f"- bash --posix: status `{ref['status']}`, stdout `{ref['stdout']!r}`, stderr `{ref['normalized_stderr']!r}`",
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_summary(rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh linux arbitrary fd matrix: {matches}/{total} match bash --posix")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["reference"]
        print(f"- fd {row['fd']} {row['group']}/{row['name']}")
        print(f"  script: {row['script']!r}")
        print(f"  msh:  status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}")
        print(f"  ref:  status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Linux arbitrary-fd/process matrix.")
    parser.add_argument("--msh", type=Path, required=True)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--progress", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if os.name == "nt":
        print("msh_linux_arbitrary_fd_matrix.py must run on Linux/WSL")
        return 2
    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-linux-arbitrary-fd-matrix-") as raw:
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
