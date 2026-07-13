#!/usr/bin/env python3
"""Common helpers for generated POSIX stress cases."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class StressCase:
    category: str
    name: str
    script: str
    profile: str = "posix"
    stderr: str = "off"
    status: str = "exact"
    run: str = "eval"
    args: str = ""


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def header(case: StressCase) -> str:
    return "\n".join(
        [
            f"# msh-category: {case.category}",
            f"# msh-name: {case.name}",
            f"# msh-profile: {case.profile}",
            f"# msh-status: {case.status}",
            f"# msh-stderr: {case.stderr}",
            f"# msh-run: {case.run}",
            f"# msh-args: {case.args}",
            "",
        ]
    )


def write_case(root: Path, case: StressCase) -> None:
    path = root / case.category / f"{slug(case.name)}.sh"
    path.parent.mkdir(parents=True, exist_ok=True)
    body = case.script.strip("\n") + "\n"
    path.write_text(header(case) + body, encoding="utf-8", newline="\n")
