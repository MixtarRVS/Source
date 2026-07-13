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


def qemu_command(root: Path) -> list[str]:
    kernel = root / "Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu"
    initrd = root / "Server/Rootfs/Generated/mixtar-ail-native-initramfs.cpio.gz"
    if not kernel.exists():
        raise SystemExit(f"missing kernel: {kernel}")
    if not initrd.exists():
        raise SystemExit(f"missing initramfs: {initrd}")
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
        "768M",
        "-smp",
        "2",
        "-kernel",
        str(kernel),
        "-initrd",
        str(initrd),
        "-append",
        "console=ttyS0 earlyprintk=serial panic=-1 devtmpfs.mount=0 rdinit=/System/Init/MixtarRVS",
        "-netdev",
        "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22",
        "-device",
        "e1000e,netdev=net0",
        "-nographic",
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


def wait_for_any(output: bytearray, needles: list[str], timeout_seconds: float) -> str:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        current = text(output)
        for needle in needles:
            if needle in current:
                return needle
        time.sleep(0.05)
    raise RuntimeError(f"timeout waiting for one of {needles!r}")


def stop(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except Exception:
        proc.terminate()


def fail(proc: subprocess.Popen[bytes], output: bytearray, message: str) -> int:
    stop(proc)
    print(f"boot-qemu-networking-ssh-smoke: failed: {message}", file=sys.stderr)
    print(text(output)[-7000:], file=sys.stderr)
    return 1


def ssh_probe(root: Path) -> subprocess.CompletedProcess[str]:
    key = root / "Server/Rootfs/Generated/mixtar-ssh-test-key"
    if not key.exists():
        raise RuntimeError(f"missing SSH test key: {key}")
    runtime_key = Path("/tmp/mixtar-ssh-test-key-smoke")
    runtime_key.write_bytes(key.read_bytes())
    runtime_key.chmod(0o600)
    return subprocess.run(
        [
            "ssh",
            "-i",
            str(runtime_key),
            "-p",
            "2222",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "vxz@127.0.0.1",
            "/System/Userland/echo",
            "SSH_OK",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=8,
    )


def main() -> int:
    root = repo_root()
    log_dir = root / "Server/Rootfs/Generated/boot"
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / "boot-qemu-networking-ssh-smoke.log"
    output = bytearray()
    proc = subprocess.Popen(
        qemu_command(root),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    threading.Thread(target=read_output, args=(proc, output), daemon=True).start()
    try:
        wait_for(output, "Server listening", 60)
        last = ""
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            result = ssh_probe(root)
            last = result.stdout
            if result.returncode == 0 and "SSH_OK" in result.stdout:
                current = text(output)
                if "Attempted to kill init" in current:
                    return fail(proc, output, "PID1 died during SSH smoke")
                log.write_text(current + "\n--- ssh ---\n" + result.stdout, encoding="utf-8", errors="replace")
                print("boot-qemu-networking-ssh-smoke: ok")
                print(f"boot-qemu-networking-ssh-smoke: log={log}")
                return 0
            time.sleep(1)
        return fail(proc, output, f"ssh probe failed: {last}")
    except Exception as exc:
        return fail(proc, output, str(exc))
    finally:
        stop(proc)


if __name__ == "__main__":
    raise SystemExit(main())
