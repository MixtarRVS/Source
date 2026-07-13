#!/usr/bin/env python3
"""Fast Mixtar msh gate: strict build, WSL parity, and speed smoke."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

from msh_tool_process import run_tool_cmd


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_AILANG_ROOT = MIXTAR_ROOT.parent / "AILang-Pure"
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
TMP_DIR = MIXTAR_ROOT / "Server" / "Generated" / "tmp" / "msh-smoke-gate"
MSH_SOURCE = MSH_DIR / "msh_cli.ail"
POSIX_SUITE = MSH_DIR / "suites" / "posix-core"
SUITE_TOOL = MSH_DIR / "tools" / "msh_posix_suite.py"
PERF_TOOL = MSH_DIR / "tools" / "msh_perf_compare.py"
DEFAULT_WINDOWS_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_LINUX_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli"


SMOKE_CASES = (
    "status/empty.sh",
    "status/and-or-status.sh",
    "grammar/for-loop.sh",
    "grammar/function-call.sh",
    "grammar/case-alternatives.sh",
    "expansion/arithmetic.sh",
    "expansion/backquote-substitution.sh",
    "expansion/quoted-at-standalone.sh",
    "pipeline/pipeline-status.sh",
    "pipeline/printf-read-pipeline.sh",
    "redirection/stdout-redirection.sh",
    "redirection/here-document.sh",
    "builtin/command-double-dash.sh",
    "builtin/eval.sh",
    "builtin/trap-double-dash-exit.sh",
    "builtin/command-v-special-builtin.sh",
    "printf/integer-flags.sh",
    "process/trap-exit-last-status.sh",
)


SHELLS = (
    "wsl-sh",
    "wsl-bash-posix",
    "wsl-zsh-sh",
)


@dataclass
class StepResult:
    name: str
    status: int
    command: list[str]
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.status == 0


def run_step(
    name: str,
    command: list[str],
    cwd: Path,
    timeout: int,
    env: dict[str, str] | None = None,
) -> StepResult:
    proc = run_tool_cmd(command, cwd, env, timeout=timeout, label=name, tee_stderr=True)
    return StepResult(name, proc.returncode, command, proc.stdout, proc.stderr)


def to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    raw = resolved.as_posix()
    if drive and raw[1:3] == ":/":
        return f"/mnt/{drive}{raw[2:]}"
    return raw


def sh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\"'\"'") + "'"


def ensure_dirs() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    (MIXTAR_ROOT / "out" / "server").mkdir(parents=True, exist_ok=True)


def checked_ailang_root(raw: str) -> Path:
    root = Path(raw).resolve()
    compiler = root / "ailang.py"
    if not compiler.exists():
        raise SystemExit(f"AILang compiler not found: {compiler}")
    return root


def build_windows(
    ailang_root: Path,
    msh: Path,
    timeout: int,
    skip: bool,
) -> list[StepResult]:
    if skip:
        return []
    compiler = ailang_root / "ailang.py"
    return [
        run_step(
            "strict-check-windows",
            [sys.executable, str(compiler), str(MSH_SOURCE), "--check", "-W"],
            ailang_root,
            timeout,
        ),
        run_step(
            "build-windows",
            [
                sys.executable,
                str(compiler),
                str(MSH_SOURCE),
                "--backend=c",
                "-O2",
                "-o",
                str(msh),
            ],
            ailang_root,
            timeout,
        ),
    ]


def build_linux(
    ailang_root: Path,
    msh: Path,
    timeout: int,
    skip: bool,
) -> list[StepResult]:
    if skip:
        return []
    command = (
        f"cd {sh_quote(to_wsl_path(ailang_root))} && "
        f"python3 ailang.py {sh_quote(to_wsl_path(MSH_SOURCE))} --check -W && "
        f"python3 ailang.py {sh_quote(to_wsl_path(MSH_SOURCE))} "
        f"--backend=c -O2 -o {sh_quote(to_wsl_path(msh))}"
    )
    return [
        run_step(
            "build-linux-wsl",
            ["wsl.exe", "--exec", "sh", "-c", command],
            ailang_root,
            timeout,
        )
    ]


def materialize_smoke_suite() -> Path:
    suite = TMP_DIR / "suite"
    if suite.exists():
        shutil.rmtree(suite)
    for rel in SMOKE_CASES:
        src = POSIX_SUITE / rel
        if not src.exists():
            raise SystemExit(f"smoke source case missing: {src}")
        dst = suite / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(src.read_text(encoding="utf-8-sig"), encoding="utf-8", newline="\n")
    return suite


def run_suite_for_shell(
    linux_msh: Path,
    suite: Path,
    shell: str,
    timeout: int,
) -> tuple[StepResult, dict[str, object]]:
    json_path = REPORT_DIR / f"msh-smoke-{shell}.json"
    report_path = REPORT_DIR / f"msh-smoke-{shell}.md"
    command = [
        sys.executable,
        str(SUITE_TOOL),
        "--msh",
        str(linux_msh),
        "--msh-wsl",
        "--suite",
        str(suite),
        "--strict",
        "--strict-shell",
        shell,
        "--strict-shell-only",
        "--progress",
        "--json-report",
        str(json_path),
        "--report",
        str(report_path),
    ]
    result = run_step(f"suite-{shell}", command, MIXTAR_ROOT, timeout)
    payload: dict[str, object] = {"shell": shell, "total": 0, "matches": 0}
    if json_path.exists():
        rows = json.loads(json_path.read_text(encoding="utf-8"))
        matches = 0
        available = 0
        for row in rows:
            shell_row = row.get("shells", {}).get(shell, {})
            if shell_row.get("available"):
                available += 1
            if shell_row.get("matches_msh"):
                matches += 1
        payload.update({"total": len(rows), "available": available, "matches": matches})
    return result, payload


def run_perf(linux_msh: Path, rounds: int, timeout: int, skip: bool) -> StepResult | None:
    if skip:
        return None
    command = [
        "wsl.exe",
        "--exec",
        "python3",
        to_wsl_path(PERF_TOOL),
        "--msh",
        to_wsl_path(linux_msh),
        "--rounds",
        str(rounds),
        "--warmup",
        "1",
        "--timeout",
        "20",
        "--shells",
        "msh,wsl-sh,wsl-bash-posix,wsl-zsh-sh",
        "--report-dir",
        to_wsl_path(REPORT_DIR),
    ]
    return run_step("perf-wsl", command, MIXTAR_ROOT, timeout)


def load_perf_summary() -> dict[str, object]:
    path = REPORT_DIR / "msh-wsl-performance.json"
    if not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    cases = payload.get("cases", [])
    summary: dict[str, object] = {"cases": len(cases)}
    ratios: list[float] = []
    for row in cases:
        shells = row.get("shells", {})
        msh = shells.get("msh", {})
        base = float(msh.get("median_ms", 0.0) or 0.0)
        if base <= 0:
            continue
        for name in ("wsl-sh", "wsl-bash-posix", "wsl-zsh-sh"):
            other = shells.get(name, {})
            value = float(other.get("median_ms", 0.0) or 0.0)
            if value > 0:
                ratios.append(round(base / value, 3))
    if ratios:
        summary["msh_vs_reference_median_ratio"] = round(sum(ratios) / len(ratios), 3)
    return summary


def write_reports(payload: dict[str, object]) -> None:
    json_path = REPORT_DIR / "msh-smoke-gate.json"
    md_path = REPORT_DIR / "msh-smoke-gate.md"
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# msh Smoke Gate",
        "",
        "Fast routine gate for strict AILang build health, WSL reference behavior, and speed smoke.",
        "",
        f"- Overall: `{'PASS' if payload.get('ok') else 'FAIL'}`",
        f"- AILang root: `{payload.get('ailang_root')}`",
        f"- Windows msh: `{payload.get('windows_msh')}`",
        f"- Linux msh: `{payload.get('linux_msh')}`",
        "",
        "## Build",
        "",
        "| step | status |",
        "| --- | ---: |",
    ]
    for step in payload.get("steps", []):
        lines.append(f"| `{step['name']}` | `{step['status']}` |")
    lines.extend(["", "## WSL Shell Parity", "", "| shell | matches |", "| --- | ---: |"])
    for row in payload.get("suite", []):
        lines.append(
            f"| `{row['shell']}` | `{row['matches']}/{row['available']}` |"
        )
    perf = payload.get("performance", {})
    lines.extend(["", "## Performance", ""])
    if perf:
        ratio = perf.get("msh_vs_reference_median_ratio", "n/a")
        lines.append(f"- Cases: `{perf.get('cases', 0)}`")
        lines.append(f"- Mean `msh/reference` median ratio: `{ratio}`")
        lines.append("- Details: `Server/Generated/reports/msh-wsl-performance.md`")
    else:
        lines.append("- Not run or no report produced.")
    lines.extend(["", "## Case Source", ""])
    lines.append("The smoke suite is generated from selected files in `suites/posix-core`.")
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"json: {json_path}")
    print(f"report: {md_path}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ailang-root", default=str(DEFAULT_AILANG_ROOT))
    parser.add_argument("--windows-msh", type=Path, default=DEFAULT_WINDOWS_MSH)
    parser.add_argument("--linux-msh", type=Path, default=DEFAULT_LINUX_MSH)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--no-perf", action="store_true")
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--timeout", type=int, default=180)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    ensure_dirs()
    ailang_root = checked_ailang_root(args.ailang_root)
    windows_msh = args.windows_msh.resolve()
    linux_msh = args.linux_msh.resolve()
    steps: list[StepResult] = []
    steps.extend(build_windows(ailang_root, windows_msh, args.timeout, args.no_build))
    steps.extend(build_linux(ailang_root, linux_msh, args.timeout, args.no_build))
    if args.no_build:
        steps.append(StepResult("build-skipped", 0, [], "", ""))
    suite = materialize_smoke_suite()
    suite_steps: list[StepResult] = []
    suite_summary: list[dict[str, object]] = []
    for shell in SHELLS:
        step, summary = run_suite_for_shell(linux_msh, suite, shell, args.timeout)
        suite_steps.append(step)
        suite_summary.append(summary)
    perf_step = run_perf(linux_msh, args.rounds, args.timeout, args.no_perf)
    all_steps = [*steps, *suite_steps]
    if perf_step is not None:
        all_steps.append(perf_step)
    elif args.no_perf:
        all_steps.append(StepResult("perf-skipped", 0, [], "", ""))
    payload = {
        "ok": all(step.ok for step in all_steps),
        "ailang_root": str(ailang_root),
        "windows_msh": str(windows_msh),
        "linux_msh": str(linux_msh),
        "steps": [asdict(step) for step in all_steps],
        "suite": suite_summary,
        "performance": {} if args.no_perf else load_perf_summary(),
    }
    write_reports(payload)
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
