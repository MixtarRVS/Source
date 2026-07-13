#!/usr/bin/env python3
"""Run Linux-native job-control probes for msh.

These cases must run under WSL/Linux because Windows-hosted process APIs cannot
represent POSIX stopped/continued child state.
"""

from __future__ import annotations

import argparse
import subprocess
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
SUITE_DIR = MSH_DIR / "suites" / "posix-job-control"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli"
RUN_TIMEOUT_SECONDS = 12


@dataclass(frozen=True)
class ProbeResult:
    name: str
    status: int
    stdout: str
    stderr: str


def to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    raw = resolved.as_posix()
    if drive and raw[1:3] == ":/":
        return f"/mnt/{drive}{raw[2:]}"
    return raw


def sh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\"'\"'") + "'"


def run_case(msh: Path, case: Path) -> ProbeResult:
    work = MIXTAR_ROOT / "Server" / "Generated" / "tmp" / "msh-job-control" / case.stem
    work.mkdir(parents=True, exist_ok=True)
    command = (
        f"cd {sh_quote(to_wsl_path(work))} && "
        f"timeout {RUN_TIMEOUT_SECONDS} {sh_quote(to_wsl_path(msh))} "
        f"{sh_quote(to_wsl_path(case))}"
    )
    proc = subprocess.run(
        ["wsl.exe", "--exec", "sh", "-c", command],
        cwd=str(MIXTAR_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=RUN_TIMEOUT_SECONDS + 5,
    )
    return ProbeResult(case.stem, proc.returncode, proc.stdout, proc.stderr)


def write_reports(results: list[ProbeResult], report: Path) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["# msh Linux Job-Control Probe", ""]
    ok = True
    for result in results:
        if result.status != 0:
            ok = False
        state = "PASS" if result.status == 0 else "FAIL"
        lines.extend([f"## {result.name}", "", f"- status: `{result.status}`", f"- result: `{state}`", ""])
        if result.stdout:
            lines.extend(["stdout:", "", "```text", result.stdout.rstrip(), "```", ""])
        if result.stderr:
            lines.extend(["stderr:", "", "```text", result.stderr.rstrip(), "```", ""])
    lines.insert(2, f"Overall: `{'PASS' if ok else 'FAIL'}`")
    lines.insert(3, "")
    report.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Linux-native msh job-control probes.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--report", type=Path, default=REPORT_DIR / "msh-linux-job-control.md")
    args = parser.parse_args()
    cases = sorted(SUITE_DIR.glob("*.sh"))
    results = [run_case(args.msh, case) for case in cases]
    write_reports(results, args.report)
    passed = sum(1 for result in results if result.status == 0)
    print(f"linux job-control probe: {passed}/{len(results)}")
    print(f"report: {args.report}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
