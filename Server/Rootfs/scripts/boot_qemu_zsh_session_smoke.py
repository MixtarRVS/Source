#!/usr/bin/env python3
import os
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def session_command(root: Path) -> list[str]:
    rootfs = root / "Server/Rootfs/Generated/corev07-root"
    if not rootfs.is_dir():
        raise SystemExit(f"missing staged root: {rootfs}")
    required = {name: shutil.which(name) for name in ("chroot", "env", "script", "sudo")}
    missing = [name for name, path in required.items() if path is None]
    if missing:
        raise SystemExit(f"missing host tools: {', '.join(missing)}")
    environment = (
        "PATH=/System/Shells:/System/Userland",
        "LD_LIBRARY_PATH=/System/Shells/Runtime",
        "TERM=linux",
        "TERMINFO=/System/Shells/Terminfo",
        "HOME=/Users/PersistenceProbe",
        "USER=vxz",
        "LOGNAME=vxz",
        "MIXTAR_SYSTEM_NAME=MixtarRVS",
    )
    command = " ".join(
        [
            shlex.quote(required["env"]),
            "-i",
            *(shlex.quote(item) for item in environment),
            shlex.quote(required["chroot"]),
            "--userspec=1000:1000",
            shlex.quote(str(rootfs)),
            "/System/Shells/zsh",
            "-i",
        ]
    )
    return [required["sudo"], "-n", required["script"], "-qfec", command, "/dev/null"]


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


def wait_for_line(output: bytearray, expected: str, timeout_seconds: float) -> None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        lines = [line.strip() for line in text(output).replace("\r", "").splitlines()]
        if expected in lines:
            return
        time.sleep(0.05)
    raise RuntimeError(f"timeout waiting for exact line {expected!r}")


def send(proc: subprocess.Popen[bytes], data: bytes) -> None:
    assert proc.stdin is not None
    proc.stdin.write(data)
    proc.stdin.flush()


def fail(proc: subprocess.Popen[bytes], output: bytearray, message: str) -> int:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    except Exception:
        proc.terminate()
    print(f"corev08-zsh-input-smoke: failed: {message}", file=sys.stderr)
    print(text(output)[-5000:], file=sys.stderr)
    return 1


def main() -> int:
    root = repo_root()
    log_dir = root / "Server/Rootfs/Generated/boot"
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / "boot-qemu-zsh-session-smoke.log"
    output = bytearray()
    proc = subprocess.Popen(
        session_command(root),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    reader = threading.Thread(target=read_output, args=(proc, output), daemon=True)
    reader.start()
    try:
        wait_for(output, "vxz@MixtarRVS", 30)
        send(proc, b"echo READY\n")
        wait_for(output, "READY", 5)
        send(proc, b"echo $ZSH_VERSION\n")
        wait_for(output, "5.9", 5)
        send(proc, b"print -r -- $PATH\n")
        wait_for_line(output, "/System/Shells:/System/Userland", 5)
        send(proc, b"whence -p reboot\n")
        wait_for_line(output, "/System/Userland/reboot", 5)
        send(proc, b"find / -maxdepth 1 | sort\n")
        for entry in ["/Applications", "/System", "/Temporary", "/Users", "/Volumes"]:
            wait_for(output, entry, 5)
        current = text(output)
        if "\n/dev\n" in current or "\n/root\n" in current:
            return fail(proc, output, "legacy root path visible")
        send(proc, b"pri\t")
        time.sleep(1.0)
        current = text(output)
        for bad in ["/dev/null", "_path_files", "_pick_variant"]:
            if bad in current:
                return fail(proc, output, f"completion leaked {bad}")
        send(proc, b"\x03")
        time.sleep(0.5)
        send(proc, b"sleep 20\n")
        time.sleep(1.0)
        send(proc, b"\x03")
        time.sleep(0.5)
        send(proc, b"echo CTRL_C_OK\n")
        wait_for(output, "CTRL_C_OK", 5)
        send(proc, b"echo HIST_OK\n")
        wait_for(output, "HIST_OK", 5)
        send(proc, b"\x1b[A\n")
        time.sleep(1.0)
        if text(output).count("HIST_OK") < 2:
            return fail(proc, output, "history up-arrow did not replay last command")
        send(proc, b"echo BACKSPACE_X\x7fOK\n")
        wait_for_line(output, "BACKSPACE_OK", 5)
        send(proc, b"echo CTRLH_X\x08OK\n")
        wait_for_line(output, "CTRLH_OK", 5)
        send(proc, b"echo LEFT_R\x1b[DOK\n")
        wait_for_line(output, "LEFT_OKR", 5)
        send(proc, b"echo RIGHX\x1b[DT\x1b[C\x7f\n")
        wait_for_line(output, "RIGHT", 5)
        send(proc, b"echo DELETE_X\x1b[D\x1b[3~\n")
        wait_for_line(output, "DELETE_", 5)
        send(proc, b"echo HIST_OLDER\n")
        wait_for_line(output, "HIST_OLDER", 5)
        send(proc, b"echo HIST_NEWER\n")
        wait_for_line(output, "HIST_NEWER", 5)
        send(proc, b"\x1b[A\x1b[A\x1b[B\n")
        time.sleep(1.0)
        if [line.strip() for line in text(output).replace("\r", "").splitlines()].count("HIST_NEWER") < 2:
            return fail(proc, output, "down-arrow did not return to newer history entry")
        function_keys = (
            b"\x1b[[A\x1b[[B\x1b[[C\x1b[[D\x1b[[E"
            b"\x1bOP\x1bOQ\x1bOR\x1bOS\x1b[15~"
            b"\x1b[17~\x1b[18~\x1b[19~\x1b[20~\x1b[21~\x1b[23~\x1b[24~"
        )
        send(proc, b"echo FKEY_OK" + function_keys + b"\n")
        wait_for_line(output, "FKEY_OK", 5)
        send(proc, b"exit\n")
        deadline = time.monotonic() + 5
        while proc.poll() is None and time.monotonic() < deadline:
            time.sleep(0.1)
        if proc.poll() is None:
            return fail(proc, output, "ZSH did not exit from pseudo-terminal")
        current = text(output)
        log.write_text(current, encoding="utf-8", errors="replace")
        print("corev08-zsh-input-smoke: ok")
        print(f"corev08-zsh-input-smoke: log={log}")
        return 0
    except Exception as exc:
        return fail(proc, output, str(exc))
    finally:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except Exception:
                proc.terminate()


if __name__ == "__main__":
    raise SystemExit(main())
