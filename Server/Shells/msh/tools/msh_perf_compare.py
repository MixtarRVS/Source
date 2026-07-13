#!/usr/bin/env python3
"""Compare msh runtime speed against WSL shells.

Run from WSL for useful numbers:

    python3 Server/Shells/msh/tools/msh_perf_compare.py

The benchmark intentionally uses small POSIX-sh scripts with no output. It is a
microbenchmark, not a conformance test.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
MIXTAR_ROOT = SCRIPT_DIR.parents[3]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli"


CASES: list[tuple[str, str]] = [
    ("startup_colon", ":\n"),
    (
        "arith_loop_1000",
        "i=0\nwhile [ $i -lt 1000 ]; do\n  i=$((i + 1))\ndone\n",
    ),
    (
        "function_loop_1000",
        "f() { :; }\ni=0\nwhile [ $i -lt 1000 ]; do\n  f\n  i=$((i + 1))\ndone\n",
    ),
    (
        "case_loop_1000",
        "i=0\nwhile [ $i -lt 1000 ]; do\n"
        "  case abc in a*) : ;; *) exit 1 ;; esac\n"
        "  i=$((i + 1))\n"
        "done\n",
    ),
    (
        "param_expansion_1000",
        "i=0\nx=abcdef\nwhile [ $i -lt 1000 ]; do\n"
        "  y=${x#?}${x%?}${x:-fallback}\n"
        "  i=$((i + 1))\n"
        "done\n",
    ),
    (
        "command_sub_50",
        "i=0\nwhile [ $i -lt 50 ]; do\n"
        "  x=$(printf x)\n"
        "  i=$((i + 1))\n"
        "done\n",
    ),
    (
        "pipeline_cat_50",
        "i=0\nwhile [ $i -lt 50 ]; do\n"
        "  printf 'x\\n' | cat >/dev/null\n"
        "  i=$((i + 1))\n"
        "done\n",
    ),
]


def shell_specs(selected: str) -> list[tuple[str, list[str]]]:
    specs = [
        ("msh", []),
        ("wsl-sh", ["sh"]),
        ("wsl-bash-posix", ["bash", "--posix"]),
        ("wsl-bash", ["bash"]),
        ("wsl-zsh-sh", ["zsh", "--emulate", "sh"]),
    ]
    if not selected:
        return specs
    wanted = {item.strip() for item in selected.split(",") if item.strip()}
    return [spec for spec in specs if spec[0] in wanted]


def command_for(name: str, argv: list[str], msh: Path, script: Path) -> list[str]:
    if name == "msh":
        return [str(msh), str(script)]
    return [*argv, str(script)]


def available(name: str, argv: list[str], msh: Path) -> bool:
    if name == "msh":
        return msh.exists() and os.access(msh, os.X_OK)
    return shutil.which(argv[0]) is not None


def run_once(command: list[str], cwd: Path, timeout: float) -> tuple[float, int, str, str]:
    start = time.perf_counter_ns()
    try:
        proc = subprocess.run(
            command,
            cwd=str(cwd),
            env={**os.environ, "LC_ALL": "C", "PATH": "/usr/bin:/bin"},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        elapsed = (time.perf_counter_ns() - start) / 1_000_000.0
        out = exc.stdout if isinstance(exc.stdout, str) else ""
        err = exc.stderr if isinstance(exc.stderr, str) else ""
        return elapsed, 124, out, err + "\ntimeout"
    elapsed = (time.perf_counter_ns() - start) / 1_000_000.0
    return elapsed, proc.returncode, proc.stdout, proc.stderr


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    return float(statistics.median(values))


def bench_case(
    name: str,
    body: str,
    specs: list[tuple[str, list[str]]],
    msh: Path,
    rounds: int,
    warmup: int,
    timeout: float,
    root: Path,
) -> dict[str, object]:
    script = root / f"{name}.sh"
    script.write_text(body, encoding="utf-8", newline="\n")
    rows: dict[str, object] = {}
    for shell_name, argv in specs:
        if not available(shell_name, argv, msh):
            rows[shell_name] = {"available": False, "error": "not available"}
            continue
        command = command_for(shell_name, argv, msh, script)
        timings: list[float] = []
        errors: list[str] = []
        for index in range(warmup + rounds):
            elapsed, status, stdout, stderr = run_once(command, root, timeout)
            if status != 0 or stdout or stderr:
                errors.append(
                    f"status={status} stdout={stdout!r} stderr={stderr!r}"
                )
                break
            if index >= warmup:
                timings.append(elapsed)
        rows[shell_name] = {
            "available": True,
            "rounds": len(timings),
            "median_ms": round(median(timings), 3),
            "best_ms": round(min(timings), 3) if timings else 0.0,
            "mean_ms": round(statistics.fmean(timings), 3) if timings else 0.0,
            "errors": errors,
        }
    return {"case": name, "shells": rows}


def add_relative(rows: list[dict[str, object]]) -> None:
    for row in rows:
        shells = row["shells"]
        assert isinstance(shells, dict)
        msh_row = shells.get("msh", {})
        if not isinstance(msh_row, dict):
            continue
        base = float(msh_row.get("median_ms", 0.0) or 0.0)
        if base <= 0.0:
            continue
        for shell_row in shells.values():
            if not isinstance(shell_row, dict):
                continue
            value = float(shell_row.get("median_ms", 0.0) or 0.0)
            if value > 0.0:
                shell_row["vs_msh"] = round(value / base, 3)


def write_markdown(path: Path, rows: list[dict[str, object]]) -> None:
    names = ["msh", "wsl-sh", "wsl-bash-posix", "wsl-bash", "wsl-zsh-sh"]
    lines = [
        "# msh WSL Performance Compare",
        "",
        "Values are median milliseconds per script execution. `vs_msh` is shell median divided by msh median; values below 1.0 are faster than msh.",
        "",
        "| case | " + " | ".join(names) + " |",
        "| --- | " + " | ".join(["---:"] * len(names)) + " |",
    ]
    for row in rows:
        shells = row["shells"]
        assert isinstance(shells, dict)
        cells = [str(row["case"])]
        for name in names:
            shell_row = shells.get(name)
            if not isinstance(shell_row, dict) or not shell_row.get("available"):
                cells.append("n/a")
                continue
            if shell_row.get("errors"):
                cells.append("error")
                continue
            cells.append(
                f"{shell_row.get('median_ms')} ms ({shell_row.get('vs_msh')}x)"
            )
        lines.append("| " + " | ".join(cells) + " |")
    lines.extend(
        [
            "",
            "Notes:",
            "- Run inside WSL; do not compare these numbers with PowerShell-hosted timings.",
            "- Scripts intentionally produce no output, so this measures shell parsing/evaluation/process overhead.",
            "- This is not a POSIX conformance result.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--msh", default=str(DEFAULT_MSH))
    parser.add_argument("--rounds", type=int, default=15)
    parser.add_argument("--warmup", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--shells", default="")
    parser.add_argument("--report-dir", default=str(REPORT_DIR))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report_dir = Path(args.report_dir)
    report_dir.mkdir(parents=True, exist_ok=True)
    specs = shell_specs(args.shells)
    msh = Path(args.msh).resolve()
    with tempfile.TemporaryDirectory(prefix="msh-perf-") as temp:
        root = Path(temp)
        rows = [
            bench_case(
                name,
                body,
                specs,
                msh,
                args.rounds,
                args.warmup,
                args.timeout,
                root,
            )
            for name, body in CASES
        ]
    add_relative(rows)
    payload = {
        "msh": str(msh),
        "rounds": args.rounds,
        "warmup": args.warmup,
        "cases": rows,
    }
    json_path = report_dir / "msh-wsl-performance.json"
    md_path = report_dir / "msh-wsl-performance.md"
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    write_markdown(md_path, rows)
    print(f"json: {json_path}")
    print(f"report: {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
