#!/usr/bin/env python3
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def qemu_command(root: Path, action: str) -> list[str]:
    artifact = (
        root
        / f"Server/Rootfs/Generated/corev07-efi-build/MixtarRVS-0.9-{action}-test.efi"
    )
    if not artifact.exists():
        raise SystemExit(f"missing EFI artifact: {artifact}")
    accel = "tcg"
    cpu = "max"
    if Path("/dev/kvm").exists():
        accel = "kvm"
        cpu = "host"
    return [
        "qemu-system-x86_64",
        "-machine",
        f"q35,accel={accel}",
        "-cpu",
        cpu,
        "-m",
        "512M",
        "-smp",
        "2",
        "-kernel",
        str(artifact),
        "-net",
        "none",
        "-display",
        "none",
        "-serial",
        "stdio",
        "-no-reboot",
    ]


def read_output(proc: subprocess.Popen[bytes], output: bytearray) -> None:
    assert proc.stdout is not None
    while True:
        chunk = proc.stdout.read(1)
        if not chunk:
            return
        output.extend(chunk)


def text(output: bytearray) -> str:
    return output.decode("utf-8", "replace")


def wait_for(output: bytearray, needle: str, timeout_seconds: float) -> None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if needle in text(output):
            return
        time.sleep(0.05)
    raise RuntimeError(f"timeout waiting for {needle!r}")


def send(proc: subprocess.Popen[bytes], data: bytes) -> None:
    assert proc.stdin is not None
    proc.stdin.write(data)
    proc.stdin.flush()


def stop(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except Exception:
        proc.terminate()


def fail(proc: subprocess.Popen[bytes], output: bytearray, message: str) -> int:
    stop(proc)
    print(f"boot-qemu-pid1-safety-smoke: failed: {message}", file=sys.stderr)
    print(text(output)[-5000:], file=sys.stderr)
    return 1


def main() -> int:
    root = repo_root()
    log_dir = root / "Server/Rootfs/Generated/boot"
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / "boot-qemu-pid1-safety-smoke.log"
    case_logs: list[str] = []
    for action in ("reboot", "poweroff"):
        output = bytearray()
        proc = subprocess.Popen(
            qemu_command(root, action),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        threading.Thread(target=read_output, args=(proc, output), daemon=True).start()
        try:
            wait_for(output, "MixtarRVS Init: headless core ready", 45)
            expected = f"{action} requested"
            wait_for(output, expected, 5)
            deadline = time.monotonic() + 10
            while proc.poll() is None and time.monotonic() < deadline:
                time.sleep(0.1)
            if proc.poll() is None:
                return fail(proc, output, f"{action} did not terminate QEMU")
            current = text(output)
            if "Attempted to kill init" in current:
                return fail(proc, output, f"PID1 died during {action}")
            if "Kernel panic" in current:
                return fail(proc, output, f"kernel panic during {action}")
            case_logs.append(f"=== {action} ===\n{current}")
        except Exception as exc:
            return fail(proc, output, f"{action}: {exc}")
        finally:
            stop(proc)

    log.write_text("\n".join(case_logs), encoding="utf-8", errors="replace")
    print("boot-qemu-pid1-safety-smoke: ok (reboot, poweroff)")
    print(f"boot-qemu-pid1-safety-smoke: log={log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
