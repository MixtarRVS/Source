#!/usr/bin/env python3
"""Linux pseudo-terminal probe for msh interactive mode."""

from __future__ import annotations

import argparse
import os
import pty
import signal
import select
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


TIMEOUT_SECONDS = 5.0


@dataclass(frozen=True)
class ProbeCase:
    name: str
    input_bytes: bytes
    expected_status: int
    required_output: tuple[str, ...]


@dataclass(frozen=True)
class SignalProbeCase:
    name: str
    before_signal: bytes
    after_signal: bytes
    signal_number: int
    expected_status: int
    required_output: tuple[str, ...]


@dataclass(frozen=True)
class TerminalControlCase:
    name: str
    before_control: bytes
    after_control: bytes
    control_bytes: bytes
    expected_status: int
    required_output: tuple[str, ...]


@dataclass(frozen=True)
class ProbeResult:
    case: ProbeCase | SignalProbeCase | TerminalControlCase
    status: int
    output: str
    ok: bool


def drain_master(master: int, output: bytearray, deadline: float) -> None:
    while time.time() < deadline:
        readable, _, _ = select.select([master], [], [], 0.1)
        if master in readable:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            output.extend(chunk)


def run_pty_case(msh: Path, case: ProbeCase) -> ProbeResult:
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        [str(msh), "-i"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)
    os.write(master, case.input_bytes)
    output = bytearray()
    deadline = time.time() + TIMEOUT_SECONDS
    while time.time() < deadline:
        drain_master(master, output, time.time() + 0.1)
        if proc.poll() is not None:
            break
    if proc.poll() is None:
        try:
            status = proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            proc.kill()
            status = 124
    else:
        status = proc.returncode
    try:
        os.close(master)
    except OSError:
        pass
    text = output.decode("utf-8", "replace")
    ok = status == case.expected_status and all(piece in text for piece in case.required_output)
    return ProbeResult(case, status, text, ok)


def run_pty_signal_case(msh: Path, case: SignalProbeCase) -> ProbeResult:
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        [str(msh), "-i"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)
    output = bytearray()
    drain_master(master, output, time.time() + 0.5)
    if case.before_signal:
        os.write(master, case.before_signal)
        drain_master(master, output, time.time() + 0.5)
    proc.send_signal(case.signal_number)
    os.write(master, b"\n")
    drain_master(master, output, time.time() + 0.5)
    if case.after_signal:
        os.write(master, case.after_signal)
    deadline = time.time() + TIMEOUT_SECONDS
    while time.time() < deadline:
        drain_master(master, output, time.time() + 0.1)
        if proc.poll() is not None:
            break
    if proc.poll() is None:
        try:
            status = proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            proc.kill()
            status = 124
    else:
        status = proc.returncode
    try:
        os.close(master)
    except OSError:
        pass
    text = output.decode("utf-8", "replace")
    ok = status == case.expected_status and all(piece in text for piece in case.required_output)
    return ProbeResult(case, status, text, ok)


def run_pty_terminal_control_case(msh: Path, case: TerminalControlCase) -> ProbeResult:
    pid, master = pty.fork()
    if pid == 0:
        os.execv(str(msh), [str(msh), "-i"])
    output = bytearray()
    drain_master(master, output, time.time() + 0.5)
    if case.before_control:
        os.write(master, case.before_control)
        drain_master(master, output, time.time() + 0.5)
    os.write(master, case.control_bytes)
    drain_master(master, output, time.time() + 0.8)
    if case.after_control:
        os.write(master, case.after_control)
    status = 124
    deadline = time.time() + TIMEOUT_SECONDS
    while time.time() < deadline:
        drain_master(master, output, time.time() + 0.1)
        try:
            got_pid, wait_status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            status = 0
            break
        if got_pid == pid:
            if os.WIFEXITED(wait_status):
                status = os.WEXITSTATUS(wait_status)
            elif os.WIFSIGNALED(wait_status):
                status = 128 + os.WTERMSIG(wait_status)
            else:
                status = 126
            break
    if status == 124:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    try:
        os.close(master)
    except OSError:
        pass
    text = output.decode("utf-8", "replace")
    ok = status == case.expected_status and all(piece in text for piece in case.required_output)
    return ProbeResult(case, status, text, ok)


def cases() -> list[ProbeCase]:
    return [
        ProbeCase(
            "exit-status",
            b"exit 7\n",
            7,
            ("$ ", "exit 7"),
        ),
        ProbeCase(
            "explicit-exit-signal-like-status",
            b"exit 130\n",
            130,
            ("$ ", "exit 130"),
        ),
        ProbeCase(
            "state-prompts-and-exit-trap",
            b"PS1='PROMPT> '\nA=42\necho \"$A\"\ntrap 'echo bye:$?' EXIT\nfalse\n\x04",
            1,
            ("$ ", "PROMPT> ", "42", "bye:1"),
        ),
        ProbeCase(
            "quote-continuation",
            b"PS2='more> '\necho 'left\nright'\nexit $?\n",
            0,
            ("more> ", "left", "right"),
        ),
        ProbeCase(
            "compound-continuation",
            b"PS2='more> '\nif true\nthen\n echo compound\nfi\nexit $?\n",
            0,
            ("more> ", "compound"),
        ),
        ProbeCase(
            "pipeline-continuation",
            b"PS2='more> '\nprintf x |\ncat\nexit $?\n",
            0,
            ("more> ", "x"),
        ),
        ProbeCase(
            "prompt-expansion",
            b"A=one\nPS1='$A> '\nPS2='$A-more> '\nA=two\necho 'left\nright'\nexit $?\n",
            0,
            ("one> ", "two> ", "two-more> ", "left", "right"),
        ),
    ]


def signal_cases() -> list[SignalProbeCase]:
    return [
        SignalProbeCase(
            "sigint-status-at-prompt",
            b"",
            b"echo status:$?\nexit 0\n",
            signal.SIGINT,
            0,
            ("status:130",),
        ),
        SignalProbeCase(
            "sigint-trap-at-prompt",
            b"trap 'echo trap:$?' INT\n",
            b"echo status:$?\nexit 0\n",
            signal.SIGINT,
            0,
            ("trap:0", "status:0"),
        ),
    ]


def terminal_control_cases() -> list[TerminalControlCase]:
    return [
        TerminalControlCase(
            "terminal-ctrl-c-foreground-command",
            b"sleep 5\n",
            b"echo status:$?\nexit 0\n",
            b"\x03",
            0,
            ("status:130",),
        ),
        TerminalControlCase(
            "terminal-ctrl-backslash-foreground-command",
            b"sleep 5\n",
            b"echo qstatus:$?\nexit 0\n",
            b"\x1c",
            0,
            ("qstatus:131",),
        ),
        TerminalControlCase(
            "terminal-ctrl-z-foreground-job",
            b"set -m\nsleep 5\n",
            b"jobs\nkill -KILL %1\nexit 0\n",
            b"\x1a",
            0,
            ("Stopped", "sleep 5"),
        ),
        TerminalControlCase(
            "terminal-ctrl-z-fg-completes",
            b"set -m\nsleep 1\n",
            b"fg\necho fgstatus:$?\nexit 0\n",
            b"\x1a",
            0,
            ("sleep 1", "fgstatus:0"),
        ),
        TerminalControlCase(
            "terminal-ctrl-z-bg-wait-completes",
            b"set -m\nsleep 1\n",
            b"bg\nwait\necho bgstatus:$?\nexit 0\n",
            b"\x1a",
            0,
            ("sleep 1", "bgstatus:0"),
        ),
    ]


def write_report(path: Path, results: list[ProbeResult]) -> None:
    passed = sum(1 for result in results if result.ok)
    lines = [
        "# msh Linux Interactive Probe",
        "",
        "Generated by `msh_interactive_probe.py`.",
        "",
        f"Summary: `{passed}/{len(results)}`",
        "",
    ]
    for result in results:
        state = "PASS" if result.ok else "FAIL"
        lines.extend(
            [
                f"## {result.case.name}",
                "",
                f"- state: `{state}`",
                f"- status: `{result.status}`",
                "",
                "```text",
                result.output.rstrip(),
                "```",
                "",
            ]
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Linux pty-backed msh interactive checks.")
    parser.add_argument("--msh", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if os.name == "nt":
        print("msh interactive probe must run on POSIX/WSL", file=sys.stderr)
        return 2
    results = [run_pty_case(args.msh, case) for case in cases()]
    results.extend(run_pty_signal_case(args.msh, case) for case in signal_cases())
    results.extend(run_pty_terminal_control_case(args.msh, case) for case in terminal_control_cases())
    if args.report:
        write_report(args.report, results)
    passed = sum(1 for result in results if result.ok)
    print(f"msh linux interactive probe: {passed}/{len(results)}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
