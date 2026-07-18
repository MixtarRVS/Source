#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Iterable, Sequence

LOGIN_MARKER = "MIXTAR_P2_LOGIN_OK"
SERVICES_MARKER = "MIXTAR_P2_SERVICES_OK"
HISTORY_MARKER = "MIXTAR_P2_HISTORY_TOKEN"
PERSISTENCE_MARKER = "MIXTAR_P2_HISTORY_OK"
PLATFORM_MARKER = "MixtarRVS: P2 platform services ready"
SHUTDOWN_MARKER = 'PID1: Received "poweroff"'


class ConsoleTimeout(RuntimeError):
    pass


class QemuConsole:
    def __init__(self, command: Sequence[str]) -> None:
        self.command = list(command)
        self.process: subprocess.Popen[bytes] | None = None
        self.output = ""
        self.condition = threading.Condition()
        self.reader: threading.Thread | None = None

    def start(self) -> None:
        self.process = subprocess.Popen(
            self.command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
        self.reader = threading.Thread(target=self._read_output, daemon=True)
        self.reader.start()

    def _read_output(self) -> None:
        assert self.process is not None
        assert self.process.stdout is not None
        descriptor = self.process.stdout.fileno()
        while True:
            chunk = os.read(descriptor, 4096)
            if not chunk:
                break
            decoded = chunk.decode("utf-8", errors="replace")
            sys.stdout.write(decoded)
            sys.stdout.flush()
            with self.condition:
                self.output += decoded
                self.condition.notify_all()

    def expect_any(self, needles: Iterable[str], timeout: float) -> str:
        choices = tuple(needles)
        deadline = time.monotonic() + timeout
        with self.condition:
            while True:
                for needle in choices:
                    if needle in self.output:
                        return needle
                if self.process is not None and self.process.poll() is not None:
                    raise RuntimeError(
                        f"QEMU exited with {self.process.returncode} before "
                        f"producing any of {choices!r}"
                    )
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise ConsoleTimeout(
                        f"timeout waiting for {choices!r}; console tail:\n"
                        + self.output[-5000:]
                    )
                self.condition.wait(min(remaining, 0.25))

    def expect(self, needle: str, timeout: float) -> None:
        self.expect_any((needle,), timeout)

    def send_line(self, value: str) -> None:
        assert self.process is not None
        assert self.process.stdin is not None
        for byte in value.encode("utf-8") + b"\r\n":
            self.process.stdin.write(bytes((byte,)))
            self.process.stdin.flush()
            time.sleep(0.01)

    def wait(self, timeout: float) -> int:
        assert self.process is not None
        return self.process.wait(timeout=timeout)

    def close(self) -> None:
        if self.process is None or self.process.poll() is not None:
            return
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)


def existing_file(value: str) -> Path:
    path = Path(value).expanduser().resolve()
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"file does not exist: {path}")
    return path


def qemu_command(args: argparse.Namespace, disk: Path) -> list[str]:
    command = [
        args.qemu,
        "-machine",
        f"{args.machine},accel={args.accelerator}",
        "-cpu",
        "max",
        "-m",
        str(args.memory),
        "-smp",
        str(args.cpus),
        "-drive",
        f"if=pflash,format=raw,unit=0,readonly=on,file={args.firmware}",
        "-drive",
        f"if=pflash,format=raw,unit=1,file={args.firmware_vars}",
        "-drive",
        f"file={disk},format={args.disk_format},if=virtio,cache=unsafe",
        "-netdev",
        "user,id=mixtarnet",
        "-device",
        "virtio-net-pci,netdev=mixtarnet",
        "-display",
        "none",
        "-serial",
        "stdio",
        "-monitor",
        "none",
        "-no-reboot",
    ]
    command.extend(args.qemu_arg)
    return command


def ensure_clean_exit(console: QemuConsole, timeout: float) -> None:
    code = console.wait(timeout)
    if code != 0:
        raise RuntimeError(f"QEMU exited with status {code}")


def first_boot(args: argparse.Namespace, disk: Path, password: str) -> str:
    console = QemuConsole(qemu_command(args, disk))
    console.start()
    try:
        console.expect(PLATFORM_MARKER, args.boot_timeout)
        console.expect(
            "MixtarRVS: set the password for the first administrator.",
            args.boot_timeout,
        )
        console.expect_any(("New password:", "Enter new password:"), args.prompt_timeout)
        console.send_line(password)
        console.expect_any(
            ("Retype password:", "Retype new password:"),
            args.prompt_timeout,
        )
        console.send_line(password)
        console.expect("MixtarRVS: first account ready", args.prompt_timeout)
        console.expect("login:", args.prompt_timeout)
        console.send_line("Administrator")
        console.expect("Password:", args.prompt_timeout)
        console.send_line(password)
        console.expect("root@MixtarRVS", args.prompt_timeout)
        console.send_line(
            "bb=/System/Core/BusyBox/busybox; p2_ok=1; "
            "/System/Core/Platform/system-services log MIXTAR_P2_LOG_PROBE; $bb sleep 1; "
            "$bb grep -q 'ready = true' /System/State/Platform/P2.config || p2_ok=0; "
            "$bb grep -q 'ready = true' /System/State/Time/Clock.config || p2_ok=0; "
            "$bb grep -q 'ready = true' /System/State/Logging/System.config || p2_ok=0; "
            "$bb grep -q 'manager = \"mdev\"' /System/State/Devices/Manager.config || p2_ok=0; "
            "$bb grep -q 'ready = true' /System/State/Volumes/Status.config || p2_ok=0; "
            "$bb grep -q 'state = \"bound\"' /System/State/Network/Primary.config || p2_ok=0; "
            "$bb grep -q 'dns = \"ready\"' /System/State/Network/Primary.config || p2_ok=0; "
            "$bb grep -q '^nameserver ' /System/Runtime/Network/resolv.conf || p2_ok=0; "
            "$bb grep -q 'applied = true' /System/State/OpenZFS/Tuning.config || p2_ok=0; "
            "$bb grep -q ' /Volumes/' /System/Processes/mounts || p2_ok=0; "
            "$bb grep -q MIXTAR_P2_LOG_PROBE /System/Logs/System/messages || p2_ok=0; "
            "print -s -- " + HISTORY_MARKER + "; fc -W \"$HISTFILE\"; "
            "p2_marker=MIXTAR_P2_SERVICES_; "
            "if (( p2_ok )); then print -r -- \"${p2_marker}OK\"; else print -r -- \"${p2_marker}FAILED\"; $bb cat /System/State/Network/Primary.config 2>/System/Devices/null; $bb cat /System/Runtime/Network/resolv.conf 2>/System/Devices/null; $bb cat /System/Runtime/Network/eth0.udhcpc.log 2>/System/Devices/null; fi; "
            "login_marker=MIXTAR_P2_LOGIN_; "
            "print -r -- \"${login_marker}OK:$ZSH_VERSION:$HISTFILE\"; "
            "/System/Init/openrc-shutdown -p now"
        )
        console.expect(SERVICES_MARKER, args.prompt_timeout)
        console.expect(LOGIN_MARKER, args.prompt_timeout)
        console.expect(SHUTDOWN_MARKER, args.shutdown_timeout)
        ensure_clean_exit(console, args.shutdown_timeout)
        return console.output
    finally:
        console.close()


def second_boot(args: argparse.Namespace, disk: Path, password: str) -> str:
    console = QemuConsole(qemu_command(args, disk))
    console.start()
    try:
        console.expect(PLATFORM_MARKER, args.boot_timeout)
        console.expect("login:", args.boot_timeout)
        console.send_line("Superuser")
        console.expect("Password:", args.prompt_timeout)
        console.send_line(password)
        console.expect("root@MixtarRVS", args.prompt_timeout)
        console.send_line(
            "bb=/System/Core/BusyBox/busybox; p2_ok=1; "
            "$bb grep -q " + HISTORY_MARKER + " \"$HISTFILE\" || p2_ok=0; "
            "$bb grep -q '^shutdown_epoch = [1-9]' /System/State/Time/Clock.config || p2_ok=0; "
            "$bb grep -q 'P2 platform services stopping' /System/Logs/System/messages || p2_ok=0; "
            "$bb grep -q 'dns = \"ready\"' /System/State/Network/Primary.config || p2_ok=0; "
            "p2_marker=MIXTAR_P2_HISTORY_; "
            "if (( p2_ok )); then print -r -- \"${p2_marker}OK\"; "
            "else print -r -- \"${p2_marker}FAILED\"; "
            "$bb cat \"$HISTFILE\"; "
            "$bb cat /System/State/Time/Clock.config; "
            "$bb cat /System/Logs/System/messages; "
            "$bb cat /System/State/Network/Primary.config; "
            "$bb cat /System/Runtime/Network/resolv.conf; fi; "
            "/System/Init/openrc-shutdown -p now"
        )
        console.expect(PERSISTENCE_MARKER, args.prompt_timeout)
        console.expect(SHUTDOWN_MARKER, args.shutdown_timeout)
        ensure_clean_exit(console, args.shutdown_timeout)
        return console.output
    finally:
        console.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Exercise all Mixtar P2 services, account setup, aliases, "
            "zsh/GRML, networking, storage, and persistence."
        )
    )
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--firmware", required=True, type=existing_file)
    parser.add_argument("--firmware-vars", required=True, type=existing_file)
    parser.add_argument("--disk", required=True, type=existing_file)
    parser.add_argument("--disk-format", default="raw")
    parser.add_argument("--machine", default="q35")
    parser.add_argument("--accelerator", default="tcg")
    parser.add_argument("--memory", type=int, default=2048)
    parser.add_argument("--cpus", type=int, default=2)
    parser.add_argument("--boot-timeout", type=float, default=240.0)
    parser.add_argument("--prompt-timeout", type=float, default=90.0)
    parser.add_argument("--shutdown-timeout", type=float, default=60.0)
    parser.add_argument("--work-directory", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--in-place", action="store_true")
    parser.add_argument("--keep-disk", action="store_true")
    parser.add_argument("--qemu-arg", action="append", default=[])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    password = secrets.token_hex(16) + "Aa1!"
    temporary = tempfile.TemporaryDirectory(
        prefix="mixtar-p2-console-",
        dir=args.work_directory,
    )
    work_directory = Path(temporary.name)
    test_disk = args.disk if args.in_place else work_directory / args.disk.name
    if not args.in_place:
        shutil.copyfile(args.disk, test_disk)

    firmware_vars = work_directory / args.firmware_vars.name
    shutil.copyfile(args.firmware_vars, firmware_vars)
    args.firmware_vars = firmware_vars

    try:
        boot_one = first_boot(args, test_disk, password)
        boot_two = second_boot(args, test_disk, password)
        report_path = args.report or args.disk.parent / "Qemu-p2.json"
        report_path = report_path.expanduser().resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        boot_one_path = report_path.with_name("Qemu-p2-boot1.log")
        boot_two_path = report_path.with_name("Qemu-p2-boot2.log")
        boot_one_path.write_text(boot_one, encoding="utf-8")
        boot_two_path.write_text(boot_two, encoding="utf-8")
        report = {
            "schema": "mixtar.p2-qemu.v1",
            "passed": True,
            "boots": 2,
            "markers": {
                "platform_services": PLATFORM_MARKER in boot_one and PLATFORM_MARKER in boot_two,
                "first_login": LOGIN_MARKER in boot_one,
                "services": SERVICES_MARKER in boot_one,
                "persistence": PERSISTENCE_MARKER in boot_two,
                "controlled_shutdown": SHUTDOWN_MARKER in boot_one and SHUTDOWN_MARKER in boot_two,
            },
            "logs": [str(boot_one_path), str(boot_two_path)],
            "source_disk": str(args.disk),
        }
        report_path.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print("MIXTAR_P2_CONSOLE_OK")
        print(report_path)
        if args.keep_disk and not args.in_place:
            destination = Path.cwd() / f"{args.disk.stem}-p2-tested{args.disk.suffix}"
            shutil.copyfile(test_disk, destination)
            print(f"Test disk retained at {destination}")
        return 0
    finally:
        temporary.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())