from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


def _wsl_executable() -> str:
    executable = shutil.which("wsl.exe")
    if executable is None:
        raise RuntimeError("wsl.exe is required for Linux image backends")
    return executable


def linux_path(path: Path) -> str:
    result = subprocess.run(
        [_wsl_executable(), "--exec", "wslpath", "-a", "-u", str(path.resolve())],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(f"wslpath failed: {result.stderr.strip()}")
    return result.stdout.strip()


def run_wsl(arguments: list[str], timeout: int = 120) -> str:
    result = subprocess.run(
        [_wsl_executable(), "--exec", *arguments],
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"WSL command failed: {detail}")
    return result.stdout
