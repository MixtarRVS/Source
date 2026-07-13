#!/usr/bin/env python3
"""Shared process runner for msh test tools."""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path


def _text(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return value.decode("utf-8", errors="replace")


def _terminate_process_tree(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    if os.name == "nt":
        try:
            subprocess.run(
                [_windows_taskkill_path(), "/PID", str(proc.pid), "/T", "/F"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
                check=False,
            )
            return
        except (OSError, subprocess.TimeoutExpired):
            pass
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
            return
        except OSError:
            pass
    try:
        proc.kill()
    except OSError:
        pass


def _windows_taskkill_path() -> str:
    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    return str(Path(system_root) / "System32" / "taskkill.exe")


def _truthy(value: str | None) -> bool:
    if value is None:
        return False
    return value.lower() in ("1", "true", "yes", "on")


def _preview(argv: list[str]) -> str:
    text = " ".join(argv)
    if len(text) > 240:
        return text[:237] + "..."
    return text


def _trace_enabled(env: dict[str, str] | None = None) -> bool:
    if env is not None and "MSH_TOOL_TRACE" in env:
        return _truthy(env.get("MSH_TOOL_TRACE"))
    return _truthy(os.environ.get("MSH_TOOL_TRACE"))


def _heartbeat_seconds(env: dict[str, str] | None = None) -> float:
    if env is not None and "MSH_TOOL_HEARTBEAT_SECONDS" in env:
        raw = env.get("MSH_TOOL_HEARTBEAT_SECONDS", "20")
    else:
        raw = os.environ.get("MSH_TOOL_HEARTBEAT_SECONDS", "20")
    try:
        value = float(raw)
    except ValueError:
        return 20.0
    return value if value > 0 else 20.0


def _trace_line(label: str, message: str) -> None:
    print(f"[msh-run:{label}] {message}", file=sys.stderr, flush=True)


def _read_stream(
    pipe,
    chunks: list[str],
    echo,
) -> None:
    try:
        for chunk in iter(pipe.readline, ""):
            chunks.append(chunk)
            if echo is not None:
                echo.write(chunk)
                echo.flush()
    finally:
        pipe.close()


def _run_with_tee(
    proc: subprocess.Popen[str],
    argv: list[str],
    timeout: int,
    label: str,
    trace: bool,
    tee_stderr: bool,
    heartbeat_seconds: float,
) -> subprocess.CompletedProcess[str]:
    start = time.monotonic()
    out_chunks: list[str] = []
    err_chunks: list[str] = []
    stdout_thread = threading.Thread(
        target=_read_stream, args=(proc.stdout, out_chunks, None)
    )
    stderr_echo = sys.stderr if tee_stderr else None
    stderr_thread = threading.Thread(
        target=_read_stream, args=(proc.stderr, err_chunks, stderr_echo)
    )
    stdout_thread.start()
    stderr_thread.start()
    next_beat = start + heartbeat_seconds
    deadline = start + timeout
    while True:
        if proc.poll() is not None:
            break
        now = time.monotonic()
        if now >= deadline:
            _terminate_process_tree(proc)
            stdout_thread.join(timeout=5)
            stderr_thread.join(timeout=5)
            stderr = "".join(err_chunks)
            if stderr:
                stderr += "\n"
            stderr += f"timeout after {timeout}s"
            if trace:
                _trace_line(label, f"timeout elapsed={now - start:.1f}s")
            return subprocess.CompletedProcess(argv, 124, "".join(out_chunks), stderr)
        if trace and now >= next_beat:
            _trace_line(label, f"still running elapsed={now - start:.1f}s")
            next_beat = now + heartbeat_seconds
        time.sleep(0.1)
    stdout_thread.join(timeout=5)
    stderr_thread.join(timeout=5)
    if trace:
        _trace_line(
            label,
            f"done status={proc.returncode} elapsed={time.monotonic() - start:.1f}s",
        )
    return subprocess.CompletedProcess(
        argv, proc.returncode, "".join(out_chunks), "".join(err_chunks)
    )


def run_tool_cmd(
    argv: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: int = 10,
    label: str | None = None,
    tee_stderr: bool = False,
) -> subprocess.CompletedProcess[str]:
    proc_env = None
    if env is not None:
        proc_env = os.environ.copy()
        proc_env.update(env)
    trace = _trace_enabled(proc_env)
    heartbeat_seconds = _heartbeat_seconds(proc_env)
    trace_label = label or Path(argv[0]).name
    if trace:
        _trace_line(trace_label, f"start timeout={timeout}s cmd={_preview(argv)}")
    try:
        if os.name != "nt":
            proc = subprocess.Popen(
                argv,
                cwd=str(cwd) if cwd is not None else None,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=proc_env,
                start_new_session=True,
            )
        else:
            proc = subprocess.Popen(
                argv,
                cwd=str(cwd) if cwd is not None else None,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=proc_env,
            )
    except OSError as exc:
        return subprocess.CompletedProcess(argv, 127, "", str(exc))
    if tee_stderr:
        return _run_with_tee(
            proc, argv, timeout, trace_label, trace, tee_stderr, heartbeat_seconds
        )
    start = time.monotonic()
    next_beat = start + heartbeat_seconds
    deadline = start + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(argv, timeout)
            try:
                stdout, stderr = proc.communicate(
                    timeout=min(heartbeat_seconds, remaining)
                )
                if trace:
                    _trace_line(
                        trace_label,
                        f"done status={proc.returncode} elapsed={time.monotonic() - start:.1f}s",
                    )
                return subprocess.CompletedProcess(
                    argv, proc.returncode, stdout, stderr
                )
            except subprocess.TimeoutExpired:
                if time.monotonic() >= deadline:
                    raise
                if trace and time.monotonic() >= next_beat:
                    _trace_line(
                        trace_label,
                        f"still running elapsed={time.monotonic() - start:.1f}s",
                    )
                    next_beat = time.monotonic() + heartbeat_seconds
    except subprocess.TimeoutExpired as exc:
        _terminate_process_tree(proc)
        stdout = _text(exc.stdout)
        stderr = _text(exc.stderr)
        if stderr:
            stderr += "\n"
        stderr += f"timeout after {timeout}s"
        if trace:
            _trace_line(trace_label, f"timeout elapsed={time.monotonic() - start:.1f}s")
        return subprocess.CompletedProcess(argv, 124, stdout, stderr)
