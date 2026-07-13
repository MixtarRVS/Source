#!/usr/bin/env python3
"""Materialize the broad tools-backed Smoosh suite for msh.

This uses the full broad Smoosh probe JSON plus the current stale-failure
classification JSON. Cases are copied only when they already match the WSL
reference or have a documented harness-only adjustment.
"""

from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_BROAD_JSON = REPORT_DIR / "msh-smoosh-all-wsl-msh-tools-probe.json"
DEFAULT_CLASSIFICATION_JSON = REPORT_DIR / "msh-broad-smoosh-classification-current-linux-tools.json"
DEFAULT_SUITE = MSH_DIR / "suites" / "posix-external-smoosh-tools"
SOURCE_LICENSE = MSH_DIR / "suites" / "posix-external-smoosh" / "SMOOSH_LICENSE.txt"

HARNESS_FIXED_CASES = {
    "semantics.simple.link": "file-run-mode",
}

STDOUT_NORMALIZED_CASES = {
    "builtin.cd.pwd",
}

CURRENT_FOCUSED_MATCH_CASES = {
    "semantics.dot.glob": "current focused WSL match",
}

PROFILE_EXCLUDED_CASES = {
    "builtin.jobs": "job_control_profile",
}

PROFILE_EXCLUDED_NAME_FRAGMENTS = {
    "nonposix": "non_posix_extension",
}

INCLUDED_CLASSIFICATION_BUCKETS = {
    "now_matches_current_reference",
    "reference_harness_artifact",
}


def load_json(path: Path) -> list[dict[str, object]]:
    return json.loads(path.read_text(encoding="utf-8"))


def stale_wsl_match(row: dict[str, object]) -> bool:
    shells = row.get("shells", {})
    shell = shells.get("wsl-sh", {}) if isinstance(shells, dict) else {}
    if not isinstance(shell, dict):
        return False
    return shell.get("available") is True and shell.get("matches_msh") is True


def classification_by_name(rows: list[dict[str, object]]) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for row in rows:
        result[str(row.get("name", ""))] = row
    return result


def case_name(row: dict[str, object]) -> str:
    return str(row.get("name", ""))


def case_category(row: dict[str, object]) -> str:
    return str(row.get("category", "root")) or "root"


def case_path(row: dict[str, object]) -> Path:
    return Path(str(row.get("path", "")))


def replace_metadata(text: str, key: str, value: str) -> str:
    marker = f"# msh-{key}: "
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith(marker):
            lines[index] = marker + value
            return "\n".join(lines) + ("\n" if text.endswith("\n") else "")
        if not line.startswith("#"):
            lines.insert(index, marker + value)
            return "\n".join(lines) + ("\n" if text.endswith("\n") else "")
    lines.append(marker + value)
    return "\n".join(lines) + "\n"


def normalized_script(name: str, text: str) -> str:
    if name in STDOUT_NORMALIZED_CASES:
        text = replace_metadata(text, "stdout", "cwd-normalized")
    if HARNESS_FIXED_CASES.get(name) == "file-run-mode":
        text = replace_metadata(text, "run", "file")
    return text


def profile_excluded_bucket(name: str) -> str:
    if name in PROFILE_EXCLUDED_CASES:
        return PROFILE_EXCLUDED_CASES[name]
    lowered = name.lower()
    for fragment, bucket in PROFILE_EXCLUDED_NAME_FRAGMENTS.items():
        if fragment in lowered:
            return bucket
    return ""


def include_reason(row: dict[str, object], classified: dict[str, dict[str, object]]) -> str:
    name = case_name(row)
    if profile_excluded_bucket(name):
        return ""
    if name in CURRENT_FOCUSED_MATCH_CASES:
        return CURRENT_FOCUSED_MATCH_CASES[name]
    if stale_wsl_match(row):
        return "stale broad probe matched WSL reference"
    classification = classified.get(name)
    if not classification:
        return ""
    bucket = str(classification.get("bucket", ""))
    if bucket == "reference_harness_artifact" and name not in HARNESS_FIXED_CASES:
        return ""
    if bucket in INCLUDED_CLASSIFICATION_BUCKETS:
        return bucket
    return ""


def excluded_bucket(row: dict[str, object], classified: dict[str, dict[str, object]]) -> str:
    profile_bucket = profile_excluded_bucket(case_name(row))
    if profile_bucket:
        return profile_bucket
    classification = classified.get(case_name(row))
    if classification:
        return str(classification.get("bucket", "unknown"))
    return "not-currently-gated"


def clean_suite(target: Path) -> None:
    resolved = target.resolve()
    allowed = (MSH_DIR / "suites").resolve()
    if allowed not in resolved.parents:
        raise RuntimeError(f"refusing to clean target outside msh suites: {resolved}")
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)


def write_case(target: Path, row: dict[str, object]) -> None:
    name = case_name(row)
    src = case_path(row)
    if not src.exists():
        raise FileNotFoundError(src)
    dst = target / case_category(row) / src.name
    dst.parent.mkdir(parents=True, exist_ok=True)
    text = src.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    dst.write_text(normalized_script(name, text), encoding="utf-8", newline="\n")


def write_readme(
    target: Path,
    broad_json: Path,
    classification_json: Path,
    included: list[tuple[dict[str, object], str]],
    excluded: list[tuple[dict[str, object], str]],
) -> None:
    excluded_counts = Counter(bucket for _, bucket in excluded)
    lines = [
        "# msh posix-external-smoosh-tools suite",
        "",
        "Generated by `tools/msh_materialize_smoosh_tools_suite.py`.",
        "",
        "This suite contains original broad Smoosh shell-language cases that",
        "are currently gateable against WSL `/bin/sh` when Linux `msh` runs",
        "under WSL with the converted Mixtar userland tool directory prepended",
        "to `PATH`.",
        "",
        f"Broad probe JSON: `{broad_json}`",
        f"Classification JSON: `{classification_json}`",
        f"Included cases: `{len(included)}`",
        "",
        "Harness metadata adjustments:",
        "",
        "- `builtin.cd.pwd`: `# msh-stdout: cwd-normalized` because the",
        "  original case intentionally prints the per-shell temporary cwd.",
        "- `semantics.simple.link`: `# msh-run: file` because eval-mode",
        "  reference wrapping creates a visible `case.sh` that changes `ls`.",
        "",
        "Excluded broad cases:",
        "",
    ]
    for bucket, count in sorted(excluded_counts.items()):
        lines.append(f"- `{bucket}`: `{count}`")
    lines.extend(["", "## Cases", ""])
    for row, reason in included:
        path = case_path(row)
        lines.append(f"- `{case_category(row)}/{path.name}`; reason: `{reason}`")
    target.joinpath("README.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def materialize(broad_json: Path, classification_json: Path, target: Path) -> tuple[int, int]:
    broad = load_json(broad_json)
    classified = classification_by_name(load_json(classification_json))
    included: list[tuple[dict[str, object], str]] = []
    excluded: list[tuple[dict[str, object], str]] = []
    for row in broad:
        reason = include_reason(row, classified)
        if reason:
            included.append((row, reason))
        else:
            excluded.append((row, excluded_bucket(row, classified)))
    clean_suite(target)
    for row, _ in included:
        write_case(target, row)
    if SOURCE_LICENSE.exists():
        shutil.copyfile(SOURCE_LICENSE, target / "SMOOSH_LICENSE.txt")
    write_readme(target, broad_json, classification_json, included, excluded)
    return len(included), len(excluded)


def main() -> int:
    parser = argparse.ArgumentParser(description="Materialize the broad tools-backed Smoosh suite.")
    parser.add_argument("--broad-json", type=Path, default=DEFAULT_BROAD_JSON)
    parser.add_argument("--classification-json", type=Path, default=DEFAULT_CLASSIFICATION_JSON)
    parser.add_argument("--suite", type=Path, default=DEFAULT_SUITE)
    args = parser.parse_args()
    included, excluded = materialize(args.broad_json.resolve(), args.classification_json.resolve(), args.suite.resolve())
    print(f"materialized {included} cases into {args.suite}")
    print(f"excluded {excluded} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
