#!/usr/bin/env python3
"""Verify Mixtar native data persistence across two boots."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPOSITORY_ROOT / "Output" / "P1"
WRITE_ARGUMENT = "mixtar.p2.persistence=write"
VERIFY_ARGUMENT = "mixtar.p2.persistence=verify"
WRITE_MARKER = "MixtarRVS: P2 persistence markers written"
VERIFY_MARKER = "MixtarRVS: P2 persistence verified"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Boot one Mixtar disk twice and verify persistent native paths."
    )
    result.add_argument(
        "--manifest",
        type=Path,
        help="P1 manifest; defaults to the only manifest in Output/P1.",
    )
    result.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Directory for the qcow2 overlay, logs and result.",
    )
    result.add_argument(
        "--wsl-distro",
        default=os.environ.get("MIXTAR_WSL_DISTRO", "Debian"),
        help="WSL distribution containing qemu-system-x86_64 and qemu-img.",
    )
    result.add_argument("--timeout", type=int, default=90, help="Seconds per boot.")
    return result


def locate_manifest(explicit: Path | None) -> Path:
    if explicit is not None:
        path = explicit if explicit.is_absolute() else REPOSITORY_ROOT / explicit
        if not path.is_file():
            raise FileNotFoundError(f"manifest does not exist: {path}")
        return path.resolve()

    candidates = sorted(DEFAULT_OUTPUT.glob("*.manifest.json"))
    if len(candidates) != 1:
        raise RuntimeError(
            f"expected one P1 manifest in {DEFAULT_OUTPUT}, found {len(candidates)}"
        )
    return candidates[0].resolve()


def artifact_path(manifest: dict[str, Any], *keys: str) -> Path:
    value: Any = manifest
    for key in keys:
        value = value[key]
    path = Path(value)
    if not path.is_absolute():
        path = REPOSITORY_ROOT / path
    if not path.is_file():
        raise FileNotFoundError(f"artifact does not exist: {path}")
    return path.resolve()


def wsl_command(executable: str, distro: str, *arguments: str) -> list[str]:
    return [executable, "-d", distro, "--", *arguments]


def to_wsl_path(executable: str, distro: str, path: Path) -> str:
    completed = subprocess.run(
        wsl_command(executable, distro, "wslpath", "-a", str(path)),
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def run_boot(
    *,
    executable: str,
    distro: str,
    kernel: str,
    overlay: str,
    argument: str,
    marker: str,
    timeout: int,
    log_path: Path,
) -> dict[str, Any]:
    command = wsl_command(
        executable,
        distro,
        "qemu-system-x86_64",
        "-machine",
        "q35,accel=tcg",
        "-cpu",
        "max",
        "-m",
        "2048",
        "-smp",
        "2",
        "-display",
        "none",
        "-monitor",
        "none",
        "-serial",
        "stdio",
        "-no-reboot",
        "-net",
        "none",
        "-kernel",
        kernel,
        "-append",
        f"console=ttyS0 panic=-1 {argument}",
        "-drive",
        f"file={overlay},format=qcow2,if=virtio,cache=writeback",
    )

    timed_out = False
    output = ""
    exit_code: int | None = None
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    )
    try:
        output, _ = process.communicate(timeout=timeout)
        exit_code = process.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        process.kill()
        output, _ = process.communicate()
        exit_code = process.returncode

    log_path.write_text(output, encoding="utf-8")
    marker_found = marker in output
    return {
        "argument": argument,
        "exit_code": exit_code,
        "log": str(log_path.relative_to(REPOSITORY_ROOT)),
        "marker_found": marker_found,
        "passed": not timed_out and exit_code == 0 and marker_found,
        "timed_out": timed_out,
    }


def main() -> int:
    arguments = parser().parse_args()
    manifest_path = locate_manifest(arguments.manifest)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    disk_path = artifact_path(manifest, "artifacts", "disk", "path")
    kernel_path = artifact_path(manifest, "kernel", "source")

    output = arguments.output
    if not output.is_absolute():
        output = REPOSITORY_ROOT / output
    output.mkdir(parents=True, exist_ok=True)

    wsl = shutil.which("wsl.exe") or shutil.which("wsl")
    if wsl is None:
        raise RuntimeError("wsl.exe is required for the P2 persistence test")

    overlay_path = output / "Qemu-p2-persistence.qcow2"
    result_path = output / "Qemu-p2-persistence.json"
    if overlay_path.exists():
        overlay_path.unlink()

    disk_wsl = to_wsl_path(wsl, arguments.wsl_distro, disk_path)
    kernel_wsl = to_wsl_path(wsl, arguments.wsl_distro, kernel_path)
    overlay_wsl = to_wsl_path(wsl, arguments.wsl_distro, overlay_path)

    subprocess.run(
        wsl_command(
            wsl,
            arguments.wsl_distro,
            "qemu-img",
            "create",
            "-f",
            "qcow2",
            "-F",
            "raw",
            "-b",
            disk_wsl,
            overlay_wsl,
        ),
        check=True,
    )

    write_phase = run_boot(
        executable=wsl,
        distro=arguments.wsl_distro,
        kernel=kernel_wsl,
        overlay=overlay_wsl,
        argument=WRITE_ARGUMENT,
        marker=WRITE_MARKER,
        timeout=arguments.timeout,
        log_path=output / "Qemu-p2-persistence-write.log",
    )

    verify_phase: dict[str, Any]
    if write_phase["passed"]:
        verify_phase = run_boot(
            executable=wsl,
            distro=arguments.wsl_distro,
            kernel=kernel_wsl,
            overlay=overlay_wsl,
            argument=VERIFY_ARGUMENT,
            marker=VERIFY_MARKER,
            timeout=arguments.timeout,
            log_path=output / "Qemu-p2-persistence-verify.log",
        )
    else:
        verify_phase = {
            "argument": VERIFY_ARGUMENT,
            "passed": False,
            "skipped": True,
        }

    result = {
        "manifest": str(manifest_path.relative_to(REPOSITORY_ROOT)),
        "overlay": str(overlay_path.relative_to(REPOSITORY_ROOT)),
        "passed": write_phase["passed"] and verify_phase["passed"],
        "phases": {
            "verify": verify_phase,
            "write": write_phase,
        },
        "schema": "mixtar.p2-persistence.v1",
    }
    result_path.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    if result["passed"]:
        print("P2_PERSISTENCE_OK")
        return 0

    print(json.dumps(result, indent=2, sort_keys=True), file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())