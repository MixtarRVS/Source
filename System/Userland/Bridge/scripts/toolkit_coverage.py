#!/usr/bin/env python3
"""Generate Mixtar Toolkit coverage from manifests and generated artifacts."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


REPORT = Path("System/Userland/Generated/reports/toolkit-certified-coverage.md")
MANIFEST = Path("System/Userland/Manifests/selected-tools.json")
COMMAND_COVERAGE = Path("System/Userland/Generated/reports/command-coverage.md")
REPORTS_DIR = Path("System/Userland/Generated/reports")
CERT_DIR = Path("System/Userland/Generated/certification")
TARGET_DIR = Path("System/Userland/Generated/targets/linux-x64/bin")


@dataclass(frozen=True)
class ToolState:
    name: str
    manifest: dict
    has_gap: bool
    has_cert: bool
    has_target: bool
    hosted: bool
    common: bool
    generated_only: bool

    @property
    def phase(self) -> str:
        return str(self.manifest.get("phase", "generated-only"))

    @property
    def upstream(self) -> str:
        preferred = self.manifest.get("preferred_upstream")
        fallback = self.manifest.get("fallback_upstream")
        if preferred and fallback:
            return f"{preferred}, fallback {fallback}"
        if preferred:
            return str(preferred)
        if fallback:
            return f"fallback {fallback}"
        if self.generated_only:
            return "generated artifact"
        return "unspecified"

    @property
    def primary_upstream(self) -> str:
        explicit = self.manifest.get("source") or self.manifest.get("preferred_upstream")
        if explicit:
            return str(explicit)

        paths = []
        raw_paths = self.manifest.get("source_paths", [])
        raw_upstream = self.manifest.get("upstream", [])
        if isinstance(raw_paths, list):
            paths.extend(str(p) for p in raw_paths)
        if isinstance(raw_upstream, list):
            paths.extend(str(p) for p in raw_upstream)

        has_openbsd = any("OpenBSD/" in p or p.startswith("OpenBSD") for p in paths)
        has_freebsd = any("FreeBSD/" in p or p.startswith("FreeBSD") or p.startswith("bin/") or p.startswith("usr.bin/") for p in paths)
        if has_openbsd:
            return "openbsd"
        if has_freebsd:
            return "freebsd"
        if self.generated_only:
            return "generated"
        return "unspecified"

    @property
    def has_freebsd_fallback(self) -> bool:
        return str(self.manifest.get("fallback_upstream", "")) == "freebsd"

    @property
    def tier(self) -> str:
        tier = self.manifest.get("certification_tier")
        if tier:
            return str(tier)
        if self.hosted:
            return "explicit-hosted"
        if self.phase == "toolkit-mirror-probe":
            return "probe"
        return "core/legacy"

    @property
    def status(self) -> str:
        if self.hosted:
            return "hosted-placeholder"
        if self.has_cert and self.has_target:
            return "source-certified"
        if self.has_cert:
            return "cert-no-target"
        if self.phase == "toolkit-mirror-probe":
            return "probe-only"
        if self.has_target:
            return "target-no-cert"
        return "open"

    @property
    def blocker(self) -> str:
        if self.hosted:
            return "explicit-only adapter; needs real upstream port or permanent deferral"
        if self.phase == "toolkit-mirror-probe":
            return "mirrored candidate only; needs recipe, bridge fixes, and certification"
        if not self.has_cert:
            return "missing certification report"
        if not self.has_target:
            return "missing generated executable"
        return "none for current smoke tier"


def find_repo_root() -> Path:
    candidates = [Path.cwd(), Path(__file__).resolve()]
    candidates.extend(Path.cwd().parents)
    candidates.extend(Path(__file__).resolve().parents)
    for candidate in candidates:
        root = candidate if candidate.is_dir() else candidate.parent
        if (root / MANIFEST).is_file():
            return root
    raise SystemExit("toolkit-coverage: cannot locate MixtarRVS repository root")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def parse_common_commands(text: str) -> set[str]:
    marker = "## Common To FreeBSD, OpenBSD, And Debian"
    start = text.find(marker)
    if start < 0:
        return set()
    rest = text[start + len(marker) :]
    end = rest.find("\n## ")
    body = rest[:end] if end >= 0 else rest
    words: list[str] = []
    for chunk in body.replace("\n", " ").split(","):
        word = chunk.strip().strip("`")
        if word and " " not in word:
            words.append(word)
    return set(words)


def markdown_list(items: Iterable[str]) -> str:
    values = sorted(set(items))
    if not values:
        return "_none_"
    return "`" + "`, `".join(values) + "`"


def table_rows(states: Iterable[ToolState]) -> str:
    lines = [
        "| Tool | Status | Upstream | Tier | Common | Target | Cert | Gap | Blocker |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for state in sorted(states, key=lambda s: (s.status, s.name)):
        lines.append(
            "| `{name}` | {status} | {upstream} | {tier} | {common} | {target} | {cert} | {gap} | {blocker} |".format(
                name=state.name,
                status=state.status,
                upstream=state.upstream,
                tier=state.tier,
                common="yes" if state.common else "no",
                target="yes" if state.has_target else "no",
                cert="yes" if state.has_cert else "no",
                gap="yes" if state.has_gap else "no",
                blocker=state.blocker,
            )
        )
    return "\n".join(lines)


def load_states(root: Path) -> list[ToolState]:
    manifest_text = read_text(root / MANIFEST)
    manifest_data = json.loads(manifest_text) if manifest_text else {"tools": {}}
    manifest_tools: dict[str, dict] = manifest_data.get("tools", {})

    gap_reports = {p.name[: -len("-gap.md")]: p for p in (root / REPORTS_DIR).glob("*-gap.md")}
    cert_reports = {p.stem: p for p in (root / CERT_DIR).glob("*.md")}
    targets = {p.name for p in (root / TARGET_DIR).iterdir() if p.is_file()} if (root / TARGET_DIR).is_dir() else set()
    common = parse_common_commands(read_text(root / COMMAND_COVERAGE))

    all_names = set(manifest_tools) | set(gap_reports) | set(cert_reports) | targets
    states: list[ToolState] = []
    for name in sorted(all_names):
        if name.endswith("_probe"):
            continue
        gap_text = read_text(gap_reports[name]) if name in gap_reports else ""
        hosted = "hosted Linux adapter" in gap_text or "Bridge/scripts/hosted_common" in gap_text
        states.append(
            ToolState(
                name=name,
                manifest=manifest_tools.get(name, {}),
                has_gap=name in gap_reports,
                has_cert=name in cert_reports,
                has_target=name in targets,
                hosted=hosted,
                common=name in common,
                generated_only=name not in manifest_tools,
            )
        )
    return states


def write_report(root: Path, states: list[ToolState]) -> Path:
    common = {s.name for s in states if s.common}
    source_certified = {s.name for s in states if s.status == "source-certified"}
    openbsd_source_certified = {s.name for s in states if s.status == "source-certified" and s.primary_upstream == "openbsd"}
    openbsd_clean_source_certified = {s.name for s in states if s.status == "source-certified" and s.primary_upstream == "openbsd" and not s.has_freebsd_fallback}
    freebsd_primary_source_certified = {s.name for s in states if s.status == "source-certified" and s.primary_upstream == "freebsd" and not s.has_freebsd_fallback}
    freebsd_fallback_source_certified = {s.name for s in states if s.status == "source-certified" and s.has_freebsd_fallback}
    unspecified_source_certified = {
        s.name
        for s in states
        if s.status == "source-certified" and s.primary_upstream not in {"openbsd", "freebsd"} and not s.has_freebsd_fallback
    }
    hosted = {s.name for s in states if s.hosted}
    probe_only = {s.name for s in states if s.status == "probe-only"}
    open_items = {s.name for s in states if s.status in {"open", "cert-no-target", "target-no-cert"}}
    common_source_certified = common & source_certified
    non_common_source_certified = source_certified - common
    represented_common = common & (source_certified | hosted | probe_only | open_items)
    missing_common = common - represented_common
    manifest_only = {s.name for s in states if s.phase == "toolkit-mirror-probe"}
    generated_only = {s.name for s in states if s.generated_only}

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    out = root / REPORT
    out.parent.mkdir(parents=True, exist_ok=True)
    body = f"""# Toolkit Certified Coverage

Generated by `Toolkit/Bridge/scripts/toolkit_coverage.py`.

Generated at: `{now}`

## Summary

- Coverage universe: `{len(states)}` command/tool entries from manifest, gap reports, certification reports, and generated targets.
- Common FreeBSD/OpenBSD/Debian command names represented here: `{len(common)}`.
- Common command names not represented: `{len(missing_common)}`.
- Source-certified executable tools: `{len(source_certified)}`.
- OpenBSD-primary source-certified tools: `{len(openbsd_source_certified)}`.
- OpenBSD-primary source-certified tools without FreeBSD fallback metadata: `{len(openbsd_clean_source_certified)}`.
- FreeBSD-primary source-certified tools: `{len(freebsd_primary_source_certified)}`.
- OpenBSD-preferred tools with FreeBSD fallback metadata: `{len(freebsd_fallback_source_certified)}`.
- Source-certified tools with unspecified upstream metadata: `{len(unspecified_source_certified)}`.
- Common source-certified command names: `{len(common_source_certified)}`.
- Extra source-certified BSD command names outside the common comparison: `{len(non_common_source_certified)}`.
- Hosted placeholders: `{len(hosted)}`.
- Probe-only mirrored candidates: `{len(probe_only)}`.
- Open or inconsistent entries: `{len(open_items)}`.
- Generated-only entries not in `selected-tools.json`: `{len(generated_only)}`.

## Policy

The bridge is complete only for the documented smoke surface of each certified
tool. Do not invent Mixtar-specific command behavior for an upstream command
name. Either preserve the OpenBSD/FreeBSD contract, keep an explicit hosted
placeholder, or defer the command.

## Source-Certified Tools

{markdown_list(source_certified)}

## OpenBSD-Primary Source-Certified Tools

These are the commands that count toward the OpenBSD-first userland target:

{markdown_list(openbsd_source_certified)}

OpenBSD-primary, no FreeBSD fallback metadata:

{markdown_list(openbsd_clean_source_certified)}

## FreeBSD Primary Or Fallback Source-Certified Tools

These are useful compatibility ports, but they do not count as OpenBSD-first
completion unless the manifest later moves them to OpenBSD source:

Primary FreeBSD:

{markdown_list(freebsd_primary_source_certified)}

OpenBSD-preferred with FreeBSD fallback metadata:

{markdown_list(freebsd_fallback_source_certified)}

Unspecified upstream metadata:

{markdown_list(unspecified_source_certified)}

## Extra Source-Certified BSD Tools

These are already source-certified, but they were not part of the exact
FreeBSD/OpenBSD/Debian common-name set:

{markdown_list(non_common_source_certified)}

## Hosted Placeholders

{markdown_list(hosted)}

## Probe-Only Candidates

{markdown_list(probe_only)}

## Common Names Missing Representation

{markdown_list(missing_common)}

## Manifest Mirror-Probe Queue

These are known mirrored candidates that need recipes, compatibility fixes, and
certification before promotion:

{markdown_list(manifest_only)}

## Generated-Only Entries

These exist as generated reports/certifications/targets but are not currently
tracked in `selected-tools.json`. Either add them to the manifest or remove the
stale artifacts:

{markdown_list(generated_only)}

## Next Work Queue

1. Keep Tier A stable: repair source-certified regressions before expanding.
2. Convert hosted placeholders only when the upstream source can be preserved unchanged.
3. Promote probe-only candidates one at a time through strict build, smoke test, upstream-derived tests, and certification.
4. Treat kernel/auth/terminal/block-device tools as deferred until the rootfs and runtime services prove those surfaces.

## Per-Tool State

{table_rows(states)}
"""
    out.write_text(body, encoding="utf-8", newline="\n")
    return out


def main() -> int:
    root = find_repo_root()
    states = load_states(root)
    report = write_report(root, states)
    print(f"toolkit coverage report: {report.relative_to(root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
