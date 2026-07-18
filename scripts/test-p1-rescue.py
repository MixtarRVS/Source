from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
import tomllib
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
OUTPUT = REPOSITORY / "Output" / "P1"


def find_qemu() -> Path:
    discovered = shutil.which("qemu-system-x86_64")
    candidates = [
        Path(discovered) if discovered else None,
        Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
        / "qemu"
        / "qemu-system-x86_64.exe",
    ]
    for candidate in candidates:
        if candidate and candidate.is_file():
            return candidate
    raise RuntimeError("qemu-system-x86_64 was not found")


def find_kernel() -> Path:
    root = OUTPUT / "Kernel" / "System" / "Kernel" / "Linux"
    kernels = sorted(root.glob("*/MixtarRVS"))
    if len(kernels) != 1:
        raise RuntimeError(f"expected one P1 kernel under {root}, found {len(kernels)}")
    return kernels[0]


def stop(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def main() -> int:
    layout = tomllib.loads(
        (REPOSITORY / "Root" / "System" / "Configuration" / "Layout.config").read_text(
            encoding="utf-8"
        )
    )
    timeout = int(layout["boot"]["qemu_timeout_seconds"])
    qemu = find_qemu()
    kernel = find_kernel()
    log_path = OUTPUT / "Qemu-zfs-rescue.log"
    report_path = OUTPUT / "Qemu-zfs-rescue.json"
    command = [
        str(qemu),
        "-machine",
        "q35,accel=tcg",
        "-cpu",
        "max",
        "-smp",
        "2",
        "-m",
        "1024",
        "-kernel",
        str(kernel),
        "-append",
        "console=ttyS0,115200n8 mixtar.zfs.rescue-test=1",
        "-display",
        "none",
        "-serial",
        "stdio",
        "-monitor",
        "none",
        "-no-reboot",
    ]
    started = time.monotonic()
    process = subprocess.Popen(
        command,
        cwd=REPOSITORY,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert process.stdin is not None
    assert process.stdout is not None
    data = bytearray()
    rescue_ready = threading.Event()

    def read_console() -> None:
        while True:
            chunk = process.stdout.read(1)
            if not chunk:
                return
            data.extend(chunk)
            if b"MixtarRVS: ZFS bootstrap failed" in data and data.endswith(b"\n# "):
                rescue_ready.set()

    reader = threading.Thread(target=read_console, name="mixtar-rescue-console", daemon=True)
    reader.start()
    timed_out = False
    try:
        if not rescue_ready.wait(timeout=timeout):
            timed_out = True
        else:
            for character in b"echo MixtarRVS: ZFS rescue command ok\npoweroff -f\n":
                process.stdin.write(bytes((character,)))
                process.stdin.flush()
                time.sleep(0.02)
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                timed_out = True
    finally:
        stop(process)
        reader.join(timeout=5)
        log_path.write_bytes(data)

    markers = {
        "bootstrap_failed": b"MixtarRVS: ZFS bootstrap failed" in data,
        "rescue_shell": b"BusyBox v" in data,
        "console_command": b"MixtarRVS: ZFS rescue command ok" in data,
        "poweroff": b"reboot: Power down" in data,
    }
    passed = not timed_out and process.returncode == 0 and all(markers.values())
    report = {
        "schema": "mixtar.p1-zfs-rescue.v1",
        "passed": passed,
        "exit_code": process.returncode,
        "timed_out": timed_out,
        "duration_seconds": round(time.monotonic() - started, 3),
        "markers": markers,
        "kernel": kernel.relative_to(REPOSITORY).as_posix(),
        "raw_log": log_path.relative_to(REPOSITORY).as_posix(),
    }
    report_path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if not passed:
        missing = ", ".join(name for name, present in markers.items() if not present)
        raise RuntimeError(f"QEMU ZFS rescue test failed; missing markers: {missing}")
    print("QEMU_ZFS_RESCUE_OK")
    print(report_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
