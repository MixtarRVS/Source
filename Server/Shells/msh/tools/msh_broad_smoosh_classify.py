#!/usr/bin/env python3
"""Classify non-gating broad Smoosh mismatches for msh.

The broad Smoosh probe intentionally includes cases outside the current
`msh-core` gate. This tool turns the old all-in failure count into a useful
triage report: cases already fixed by current msh, cases blocked by missing
Mixtar userland tools, job-control/interactive cases, and remaining shell
semantic candidates.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import msh_posix_suite as suite  # noqa: E402


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_JSON = REPORT_DIR / "msh-smoosh-all-wsl-msh-tools-probe.json"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_REPORT = REPORT_DIR / "msh-broad-smoosh-classification.md"
DEFAULT_JSON_REPORT = REPORT_DIR / "msh-broad-smoosh-classification.json"

KNOWN_EXTERNAL_TOOLS = {
    "awk",
    "cat",
    "chmod",
    "cp",
    "date",
    "dd",
    "diff",
    "dirname",
    "env",
    "grep",
    "head",
    "ln",
    "ls",
    "mkdir",
    "mkfifo",
    "mv",
    "printf",
    "readlink",
    "rm",
    "rmdir",
    "script",
    "sed",
    "sleep",
    "sort",
    "tail",
    "touch",
    "tr",
    "wc",
}

JOB_CONTROL_MARKERS = {
    "fg",
    "bg",
    "set -m",
    "set +m",
    "kill %",
    "jobs -",
    "jobs ",
}

VOLATILE_PATH_OUTPUT_CASES = {
    "builtin.cd.pwd",
}

SHELL_BUILTIN_NAMES = {
    ".",
    ":",
    "[",
    "alias",
    "break",
    "case",
    "cd",
    "command",
    "continue",
    "do",
    "done",
    "echo",
    "elif",
    "else",
    "esac",
    "eval",
    "exec",
    "exit",
    "export",
    "false",
    "fi",
    "for",
    "getopts",
    "hash",
    "if",
    "in",
    "jobs",
    "kill",
    "printf",
    "pwd",
    "read",
    "readonly",
    "return",
    "set",
    "shift",
    "test",
    "then",
    "times",
    "trap",
    "true",
    "type",
    "umask",
    "unalias",
    "unset",
    "until",
    "wait",
    "while",
}


@dataclass(frozen=True)
class CurrentRun:
    status: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class ReferenceRun:
    name: str
    status: int
    stdout: str
    stderr: str
    available: bool


def load_rows(path: Path) -> list[dict[str, object]]:
    return json.loads(path.read_text(encoding="utf-8"))


def stale_wsl(row: dict[str, object]) -> dict[str, object]:
    shells = row.get("shells", {})
    if not isinstance(shells, dict):
        return {}
    shell = shells.get("wsl-sh", {})
    return shell if isinstance(shell, dict) else {}


def row_is_stale_failure(row: dict[str, object]) -> bool:
    shell = stale_wsl(row)
    return bool(shell.get("available")) and not bool(shell.get("matches_msh"))


def case_root_for(path: Path) -> Path:
    # Broad Smoosh paths have shape .../msh-smoosh-all-probe/<category>/<case>.sh.
    if len(path.parents) >= 2:
        return path.parents[1]
    return path.parent


def run_current_msh(
    msh: Path,
    row: dict[str, object],
    root: Path,
    tool_path: Path | None,
    msh_wsl: bool,
) -> CurrentRun | None:
    raw_path = row.get("path", "")
    path = Path(str(raw_path))
    if not path.exists():
        return None
    case = suite.load_case(path, case_root_for(path))
    case_dir = root / suite.safe_dir_name(case)
    case_dir.mkdir(parents=True, exist_ok=True)
    result = suite.run_msh(msh, case, case_dir, msh_wsl, tool_path)
    return CurrentRun(result.status, result.stdout, result.stderr)


def reference_spec(shell_name: str) -> suite.ShellSpec | None:
    if not shell_name:
        return None
    specs = suite.shell_specs(
        baseline_only=False,
        include_local=True,
        include_wsl=True,
        strict_shell_only=shell_name,
    )
    if not specs:
        return None
    return specs[0]


def run_current_reference(
    shell_name: str,
    row: dict[str, object],
    root: Path,
    tool_path: Path | None,
) -> ReferenceRun | None:
    spec = reference_spec(shell_name)
    if spec is None:
        return None
    raw_path = row.get("path", "")
    path = Path(str(raw_path))
    if not path.exists():
        return None
    case = suite.load_case(path, case_root_for(path))
    case_dir = root / ("ref-" + suite.safe_dir_name(case))
    case_dir.mkdir(parents=True, exist_ok=True)
    result = suite.run_wsl_shell(spec, case, case_dir, tool_path)
    return ReferenceRun(shell_name, result.status, result.stdout, result.stderr, result.available)


def matches_stale_wsl(row: dict[str, object], current: CurrentRun | None) -> bool:
    if current is None:
        return False
    shell = stale_wsl(row)
    status_mode = str(row.get("status_mode", "exact"))
    if not suite.status_matches(current.status, int(shell.get("status", 0)), status_mode):
        return False
    if str(row.get("name", "")) in VOLATILE_PATH_OUTPUT_CASES and current.stderr == "":
        return True
    return current.stdout == str(shell.get("stdout", ""))


def run_timed_out(status: int, stderr: str) -> bool:
    return status == 124 or "timeout after" in stderr


def matches_reference(row: dict[str, object], current: CurrentRun | None, reference: ReferenceRun | None) -> bool:
    if current is None or reference is None or not reference.available:
        return False
    if run_timed_out(current.status, current.stderr) or run_timed_out(reference.status, reference.stderr):
        return False
    status_mode = str(row.get("status_mode", "exact"))
    if not suite.status_matches(current.status, reference.status, status_mode):
        return False
    if str(row.get("name", "")) in VOLATILE_PATH_OUTPUT_CASES and current.stderr == "":
        return True
    return current.stdout == reference.stdout


def reference_timed_out(reference: ReferenceRun | None) -> bool:
    if reference is None or not reference.available:
        return False
    return run_timed_out(reference.status, reference.stderr)


def read_script(row: dict[str, object]) -> str:
    path = Path(str(row.get("path", "")))
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def case_run_mode(row: dict[str, object]) -> str:
    path = Path(str(row.get("path", "")))
    if not path.exists():
        return ""
    return suite.load_case(path, case_root_for(path)).run_mode


def without_reference_case_script(text: str) -> str:
    lines = text.splitlines(keepends=True)
    out = "".join(line for line in lines if line.rstrip("\r\n") != "case.sh")
    return out


def reference_harness_artifact(
    row: dict[str, object],
    current: CurrentRun | None,
    reference: ReferenceRun | None,
) -> bool:
    if current is None or reference is None or not reference.available:
        return False
    if case_run_mode(row) != "eval":
        return False
    status_mode = str(row.get("status_mode", "exact"))
    if not suite.status_matches(current.status, reference.status, status_mode):
        return False
    if current.stderr != reference.stderr:
        return False
    return current.stdout == without_reference_case_script(reference.stdout)


def missing_tools_from_stderr(stderr: str) -> set[str]:
    tools: set[str] = set()
    for match in re.finditer(r"msh:\s+([^:\s]+):\s+not found", stderr):
        name = match.group(1)
        if name not in {"-c"}:
            tools.add(name)
    return tools


def external_tools_from_script(script: str) -> set[str]:
    tools: set[str] = set()
    for tool in KNOWN_EXTERNAL_TOOLS:
        pattern = r"(?<![A-Za-z0-9_.-])" + re.escape(tool) + r"(?![A-Za-z0-9_.-])"
        if re.search(pattern, script) and tool not in SHELL_BUILTIN_NAMES:
            tools.add(tool)
    if "/readdir" in script:
        tools.add("/readdir")
    return tools


def has_job_control(row: dict[str, object], script: str, current: CurrentRun | None) -> bool:
    name = str(row.get("name", ""))
    if "monitor" in name or "job" in name:
        return True
    haystack = script
    if current is not None:
        haystack += "\n" + current.stderr + "\n" + current.stdout
    return any(marker in haystack for marker in JOB_CONTROL_MARKERS)


def has_timeout_reference(row: dict[str, object]) -> bool:
    shell = stale_wsl(row)
    return int(shell.get("status", 0)) == 124 or "timeout after" in str(shell.get("stderr", ""))


def classify(
    row: dict[str, object],
    current: CurrentRun | None,
    reference: ReferenceRun | None,
) -> tuple[str, list[str], list[str], list[str]]:
    script = read_script(row)
    notes: list[str] = []
    required_tools = external_tools_from_script(script)
    missing_tools: set[str] = set()
    if current is not None:
        missing_tools = missing_tools_from_stderr(current.stderr)
    if current is None:
        return "missing_source_case", [], [], ["case source path is missing"]
    if reference is not None and not reference.available:
        notes.append(f"current reference shell `{reference.name}` is unavailable")
    elif reference_timed_out(reference):
        notes.append(f"current reference shell `{reference.name}` timed out")
    elif matches_reference(row, current, reference):
        return "now_matches_current_reference", sorted(required_tools), [], [
            f"current msh status/stdout matches current `{reference.name}` reference"
        ]
    elif reference_harness_artifact(row, current, reference):
        return "reference_harness_artifact", sorted(required_tools), [], [
            "eval-mode reference wrapper creates a case.sh file visible to path-listing tests"
        ]
    if matches_stale_wsl(row, current):
        return "now_fixed", sorted(required_tools), [], ["current msh status/stdout matches stale WSL reference"]
    if reference is None and has_timeout_reference(row):
        notes.append("stale WSL reference timed out; rerun needed before treating as failure")
    if has_job_control(row, script, current):
        return "job_control_or_interactive", sorted(required_tools), sorted(missing_tools), notes
    if missing_tools:
        if all(tool.startswith("/") for tool in missing_tools):
            return "external_helper_unavailable", sorted(required_tools), sorted(missing_tools), [
                "case depends on a non-POSIX absolute helper outside the Mixtar userland path"
            ]
        if current.stdout == str(stale_wsl(row).get("stdout", "")):
            notes.append("shell stdout now matches; status/stderr blocked by missing userland")
        return "missing_userland_tools", sorted(required_tools), sorted(missing_tools), notes
    if reference_timed_out(reference):
        return "current_reference_timeout", sorted(required_tools), [], notes
    if reference is None and has_timeout_reference(row):
        return "stale_reference_timeout", sorted(required_tools), [], notes
    return "shell_semantic_candidate", sorted(required_tools), [], notes


def classify_rows(
    rows: list[dict[str, object]],
    msh: Path,
    tool_path: Path | None,
    reference_shell: str,
    msh_wsl: bool,
) -> list[dict[str, object]]:
    failures = [row for row in rows if row_is_stale_failure(row)]
    classified: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="msh-broad-smoosh-classify-") as raw:
        root = Path(raw)
        for row in failures:
            current = run_current_msh(msh, row, root, tool_path, msh_wsl)
            reference = run_current_reference(reference_shell, row, root, tool_path)
            bucket, required_tools, missing_tools, notes = classify(row, current, reference)
            shell = stale_wsl(row)
            current_data = None
            if current is not None:
                current_data = {
                    "status": current.status,
                    "stdout": current.stdout,
                    "stderr": current.stderr,
                }
            reference_data = None
            if reference is not None:
                reference_data = {
                    "name": reference.name,
                    "available": reference.available,
                    "status": reference.status,
                    "stdout": reference.stdout,
                    "stderr": reference.stderr,
                }
            classified.append(
                {
                    "category": row.get("category", ""),
                    "name": row.get("name", ""),
                    "bucket": bucket,
                    "required_tools": required_tools,
                    "missing_tools": missing_tools,
                    "notes": notes,
                    "path": row.get("path", ""),
                    "current": current_data,
                    "reference": reference_data,
                    "stale_wsl": {
                        "status": shell.get("status"),
                        "stdout": shell.get("stdout", ""),
                        "stderr": shell.get("stderr", ""),
                    },
                }
            )
    return classified


def short_text(value: str, limit: int = 90) -> str:
    text = value.replace("\n", "\\n")
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def markdown_report(source: Path, classified: list[dict[str, object]], reference_shell: str) -> str:
    counts = Counter(str(row["bucket"]) for row in classified)
    lines = [
        "# msh Broad Smoosh Classification",
        "",
        "Generated from the last broad Smoosh JSON plus a current `msh` rerun.",
        "This is a triage report, not a POSIX conformance result.",
        "",
        f"Source JSON: `{source}`",
    ]
    if reference_shell:
        lines.append(f"Current reference shell: `{reference_shell}`")
    lines.extend(["", "## Summary", ""])
    for bucket, count in sorted(counts.items()):
        lines.append(f"- `{bucket}`: `{count}`")
    lines.extend(["", "## Cases", ""])
    for row in classified:
        current = row.get("current") or {}
        reference = row.get("reference") or {}
        stale = row.get("stale_wsl") or {}
        required_tools = ", ".join(row.get("required_tools") or [])
        missing_tools = ", ".join(row.get("missing_tools") or [])
        notes = "; ".join(row.get("notes") or [])
        lines.append(f"### {row['name']}")
        lines.append("")
        lines.append(f"- bucket: `{row['bucket']}`")
        if required_tools:
            lines.append(f"- required external tools: `{required_tools}`")
        if missing_tools:
            lines.append(f"- missing tools reported by msh: `{missing_tools}`")
        if notes:
            lines.append(f"- notes: {notes}")
        if isinstance(current, dict):
            lines.append(f"- current msh status/stdout: `{current.get('status')}` `{short_text(str(current.get('stdout', '')))} `")
            stderr = str(current.get("stderr", ""))
            if stderr:
                lines.append(f"- current msh stderr: `{short_text(stderr)}`")
        if isinstance(reference, dict) and reference:
            lines.append(
                f"- current reference `{reference.get('name')}` status/stdout: "
                f"`{reference.get('status')}` `{short_text(str(reference.get('stdout', '')))} `"
            )
            ref_stderr = str(reference.get("stderr", ""))
            if ref_stderr:
                lines.append(f"- current reference stderr: `{short_text(ref_stderr)}`")
        if isinstance(stale, dict):
            lines.append(f"- stale WSL status/stdout: `{stale.get('status')}` `{short_text(str(stale.get('stdout', '')))} `")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify broad Smoosh mismatches for msh.")
    parser.add_argument("--input", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--msh-wsl", action="store_true", help="Run the msh target through WSL instead of as a local Windows process.")
    parser.add_argument("--msh-tool-path", type=Path, default=None)
    parser.add_argument("--reference-shell", default="", help="Optional current reference shell name, e.g. msys-dash.")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON_REPORT)
    args = parser.parse_args()

    rows = load_rows(args.input)
    tool_path = args.msh_tool_path.resolve() if args.msh_tool_path is not None else None
    classified = classify_rows(rows, args.msh, tool_path, args.reference_shell, args.msh_wsl)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.json_report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(markdown_report(args.input, classified, args.reference_shell), encoding="utf-8", newline="\n")
    args.json_report.write_text(json.dumps(classified, indent=2), encoding="utf-8", newline="\n")
    counts = Counter(str(row["bucket"]) for row in classified)
    print(f"classified {len(classified)} broad Smoosh stale failures")
    for bucket, count in sorted(counts.items()):
        print(f"{bucket}: {count}")
    print(f"report: {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
