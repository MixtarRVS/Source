#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent


def poweroff_boot(command: list[str], timeout: int, log: Path) -> tuple[int, bytes]:
    try:
        result = subprocess.run(
            command, cwd=REPOSITORY, check=False, capture_output=True,
            timeout=timeout,
        )
        data = result.stdout + result.stderr
        code = result.returncode
    except subprocess.TimeoutExpired as error:
        data = (error.stdout or b"") + (error.stderr or b"")
        code = -1
    log.write_bytes(data)
    return code, data


def boot_until(command: list[str], marker: bytes, timeout: int, log: Path) -> bytes:
    process = subprocess.Popen(
        command, cwd=REPOSITORY, stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    captured = bytearray()
    lock = threading.Lock()
    def reader() -> None:
        assert process.stdout is not None
        while block := process.stdout.read(1):
            with lock:
                captured.extend(block)
    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    deadline = time.monotonic() + timeout
    found = False
    while time.monotonic() < deadline and process.poll() is None:
        with lock:
            found = marker in captured
        if found:
            break
        time.sleep(0.05)
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    thread.join(timeout=2)
    with lock:
        data = bytes(captured)
    log.write_bytes(data)
    if not found and marker not in data:
        raise RuntimeError(f"boot marker was not observed: {marker!r}")
    return data


def direct_command(qemu: Path, kernel: Path, disk: Path, update: Path | None, append: str) -> list[str]:
    command = [
        str(qemu), "-machine", "q35,accel=tcg", "-cpu", "max", "-smp", "2",
        "-m", "1024", "-kernel", str(kernel), "-append", append,
        "-drive", f"if=virtio,format=raw,file={disk}",
    ]
    if update is not None:
        command.extend(("-drive", f"if=virtio,format=raw,readonly=on,file={update}"))
    command.extend(("-display", "none", "-serial", "stdio", "-monitor", "none", "-no-reboot"))
    return command


def ovmf_command(qemu: Path, code: Path, variables: Path, disk: Path) -> list[str]:
    return [
        str(qemu), "-machine", "q35,accel=tcg", "-cpu", "max", "-smp", "2",
        "-m", "1024",
        "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={code}",
        "-drive", f"if=pflash,format=raw,unit=1,file={variables}",
        "-drive", f"if=virtio,format=raw,file={disk}",
        "-display", "none", "-serial", "stdio", "-monitor", "none", "-no-reboot",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Test Mixtar M1 update and recovery")
    parser.add_argument("--qemu", type=Path, required=True)
    parser.add_argument("--firmware", type=Path, required=True)
    parser.add_argument("--firmware-vars", type=Path, required=True)
    parser.add_argument("--disk", type=Path, required=True)
    parser.add_argument("--efi-a", type=Path, required=True)
    parser.add_argument("--recovery-efi", type=Path, required=True)
    parser.add_argument("--update", type=Path, required=True)
    parser.add_argument("--corrupt-update", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=240)
    arguments = parser.parse_args()
    report: dict[str, object] = {
        "schema": "mixtar.m1-update-recovery-test.v1",
        "passed": False,
        "markers": {},
    }
    try:
        for path in (
            arguments.qemu, arguments.firmware, arguments.firmware_vars,
            arguments.disk, arguments.efi_a, arguments.recovery_efi,
            arguments.update, arguments.corrupt_update,
        ):
            if not path.is_file():
                raise RuntimeError(f"required test input is missing: {path}")
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mixtar-p3-") as temporary:
            work = Path(temporary)
            corrupt_disk = work / "corrupt.disk.img"
            update_disk = work / "update.disk.img"
            shutil.copyfile(arguments.disk, corrupt_disk)
            shutil.copyfile(arguments.disk, update_disk)
            append_update = "console=ttyS0,115200n8 mixtar.p3.update=1"
            code, corrupt_data = poweroff_boot(
                direct_command(arguments.qemu, arguments.efi_a, corrupt_disk, arguments.corrupt_update, append_update),
                arguments.timeout,
                arguments.report.with_name("Qemu-p3-corrupt.log"),
            )
            corrupt_ok = (
                code == 0
                and b"MixtarRVS: update rejected: root archive hash mismatch" in corrupt_data
                and b"MixtarRVS: corrupted update safely rejected" in corrupt_data
            )
            if not corrupt_ok:
                raise RuntimeError("corrupted update did not reach the root archive hash gate")
            code, update_data = poweroff_boot(
                direct_command(arguments.qemu, arguments.efi_a, update_disk, arguments.update, append_update),
                arguments.timeout,
                arguments.report.with_name("Qemu-p3-update.log"),
            )
            update_ok = code == 0 and b"MixtarRVS: update installed slot M1-B" in update_data
            if not update_ok:
                raise RuntimeError("valid update was not installed")
            vars_b = work / "vars-b.fd"
            shutil.copyfile(arguments.firmware_vars, vars_b)
            boot_b = boot_until(
                ovmf_command(arguments.qemu, arguments.firmware, vars_b, update_disk),
                b"MixtarRVS: update slot accepted M1-B", arguments.timeout,
                arguments.report.with_name("Qemu-p3-slot-b.log"),
            )
            code, recovery_data = poweroff_boot(
                direct_command(
                    arguments.qemu, arguments.recovery_efi, update_disk, None,
                    "console=ttyS0,115200n8 mixtar.recovery=rollback",
                ),
                arguments.timeout,
                arguments.report.with_name("Qemu-p3-recovery.log"),
            )
            recovery_ok = code == 0 and b"MixtarRVS: recovery restored mixtar/ROOT/M1-A" in recovery_data
            vars_a = work / "vars-a.fd"
            shutil.copyfile(arguments.firmware_vars, vars_a)
            boot_a = boot_until(
                ovmf_command(arguments.qemu, arguments.firmware, vars_a, update_disk),
                b"MixtarRVS: boot slot M1-A", arguments.timeout,
                arguments.report.with_name("Qemu-p3-rollback.log"),
            )
            markers = {
                "corrupt_update_rejected": corrupt_ok,
                "valid_update_installed": update_ok,
                "slot_b_booted_via_ovmf": b"MixtarRVS: boot slot M1-B" in boot_b,
                "slot_b_accepted": b"MixtarRVS: update slot accepted M1-B" in boot_b,
                "recovery_rollback": recovery_ok,
                "slot_a_restored_via_ovmf": b"MixtarRVS: boot slot M1-A" in boot_a,
            }
            report["markers"] = markers
            report["passed"] = all(markers.values())
            report["tested_disk_copy"] = True
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    arguments.report.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if not report["passed"]:
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1
    print("MIXTAR_P3_UPDATE_RECOVERY_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
