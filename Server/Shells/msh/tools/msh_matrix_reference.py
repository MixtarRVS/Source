#!/usr/bin/env python3
"""Reference-shell helpers for generated msh matrix tools."""

from __future__ import annotations

import subprocess
from pathlib import Path

from msh_tool_process import run_tool_cmd


LOCAL_REFERENCE_SHELLS: dict[str, Path] = {
    "msys-dash": Path(r"C:\msys64\usr\bin\dash.exe"),
    "git-dash": Path(r"C:\Program Files\Git\usr\bin\dash.exe"),
    "git-sh": Path(r"C:\Program Files\Git\bin\sh.exe"),
}


def local_reference_shell_names() -> list[str]:
    return ["wsl-sh", *LOCAL_REFERENCE_SHELLS.keys()]


def local_reference_shell_path(name: str) -> Path | None:
    path = LOCAL_REFERENCE_SHELLS.get(name)
    if path is None or not path.exists():
        return None
    return path


def run_local_reference_shell(
    shell_name: str, cwd: Path, script: str, timeout: int
) -> subprocess.CompletedProcess[str]:
    shell = local_reference_shell_path(shell_name)
    if shell is None:
        return subprocess.CompletedProcess(
            [shell_name],
            127,
            "",
            f"{shell_name} unavailable\n",
        )
    script_path = cwd / "case.sh"
    script_path.write_text(script, encoding="utf-8", newline="\n")
    return run_tool_cmd([str(shell), str(script_path)], cwd, timeout=timeout)
