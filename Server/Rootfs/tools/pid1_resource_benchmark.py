#!/usr/bin/env python3
"""Benchmark Mixtar C PID1 against the AILang PID1 candidate."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Case:
    name: str
    script: str
    log: str
    env: dict[str, str]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    next_env = os.environ.copy()
    if env:
        next_env.update(env)
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=next_env,
        text=True,
        capture_output=True,
        check=False,
    )


def parse_elapsed(value: str) -> float:
    value = value.strip()
    parts = value.split(":")
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    if len(parts) == 2:
        return int(parts[0]) * 60 + float(parts[1])
    return float(value)


def parse_time_verbose(stderr: str) -> dict[str, float]:
    metrics: dict[str, float] = {}
    patterns = {
        "user_s": r"User time \(seconds\):\s*([0-9.]+)",
        "sys_s": r"System time \(seconds\):\s*([0-9.]+)",
        "max_rss_kb": r"Maximum resident set size \(kbytes\):\s*([0-9]+)",
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, stderr)
        if match:
            metrics[key] = float(match.group(1))
    match = re.search(r"Percent of CPU this job got:\s*([0-9.]+)%", stderr)
    if match:
        metrics["cpu_percent"] = float(match.group(1))
    match = re.search(r"Elapsed \(wall clock\) time .*:\s*([0-9:.]+)", stderr)
    if match:
        metrics["time_wall_s"] = parse_elapsed(match.group(1))
    shell_patterns = {
        "time_wall_s": r"^real\s+([0-9.]+)$",
        "user_s": r"^user\s+([0-9.]+)$",
        "sys_s": r"^sys\s+([0-9.]+)$",
    }
    for key, pattern in shell_patterns.items():
        match = re.search(pattern, stderr, re.MULTILINE)
        if match:
            metrics[key] = float(match.group(1))
    return metrics


def proc_children(pid: int) -> list[int]:
    path = Path(f"/proc/{pid}/task/{pid}/children")
    try:
        text = path.read_text(encoding="ascii").strip()
    except OSError:
        return []
    if not text:
        return []
    return [int(part) for part in text.split() if part.isdigit()]


def proc_tree(pid: int) -> list[int]:
    seen: set[int] = set()
    stack = [pid]
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        stack.extend(proc_children(current))
    return list(seen)


def rss_kb(pid: int) -> int:
    path = Path(f"/proc/{pid}/status")
    try:
        for line in path.read_text(encoding="ascii", errors="ignore").splitlines():
            if line.startswith("VmRSS:"):
                parts = line.split()
                if len(parts) >= 2 and parts[1].isdigit():
                    return int(parts[1])
    except OSError:
        return 0
    return 0


def monitor_peak_rss(pid: int, stop: threading.Event, out: dict[str, int]) -> None:
    peak = 0
    while not stop.is_set():
        total = sum(rss_kb(child) for child in proc_tree(pid))
        if total > peak:
            peak = total
        time.sleep(0.02)
    total = sum(rss_kb(child) for child in proc_tree(pid))
    out["max_rss_kb"] = max(peak, total, out.get("max_rss_kb", 0))


def run_timed(cmd: str, cwd: Path, env: dict[str, str]) -> tuple[int, str, str, float, int]:
    next_env = os.environ.copy()
    next_env.update(env)
    wrapped = "TIMEFORMAT=$'real\\t%3R\\nuser\\t%3U\\nsys\\t%3S'; time " + cmd
    started = time.perf_counter()
    proc = subprocess.Popen(
        ["bash", "-lc", wrapped],
        cwd=cwd,
        env=next_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    stop = threading.Event()
    peak: dict[str, int] = {}
    thread = threading.Thread(target=monitor_peak_rss, args=(proc.pid, stop, peak), daemon=True)
    thread.start()
    stdout, stderr = proc.communicate()
    stop.set()
    thread.join(timeout=1)
    wall = time.perf_counter() - started
    return proc.returncode, stdout, stderr, wall, peak.get("max_rss_kb", 0)


def parse_kernel_time(line: str) -> float | None:
    match = re.match(r"\[\s*([0-9.]+)\]", line)
    if not match:
        return None
    return float(match.group(1))


def parse_boot_log(path: Path) -> dict[str, float | str | bool]:
    data: dict[str, float | str | bool] = {
        "has_boot_ok": False,
        "has_poweroff": False,
        "has_graphical_ok": False,
    }
    if not path.exists():
        data["log_missing"] = True
        return data

    init_time = None
    power_time = None
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            stamp = parse_kernel_time(line)
            if "Run /init as init process" in line or "Run /System/Init/Mixtar" in line:
                init_time = stamp
            if "reboot: Power down" in line:
                power_time = stamp
            if "boot-smoke: ok" in line:
                data["has_boot_ok"] = True
            if "smoke: powering off after boot proof" in line:
                data["has_poweroff"] = True
            if "desktop-wayland: ok" in line or "desktop-x11-smoke: ok" in line:
                data["has_graphical_ok"] = True
    if init_time is not None:
        data["kernel_pid1_start_s"] = init_time
    if power_time is not None:
        data["kernel_powerdown_s"] = power_time
    if init_time is not None and power_time is not None:
        data["kernel_pid1_to_powerdown_s"] = power_time - init_time
    return data


def run_case(case: Case, root: Path) -> dict[str, object]:
    rc, stdout, stderr, wall, max_rss = run_timed(f"bash {case.script}", root, case.env)
    metrics: dict[str, object] = {
        "case": case.name,
        "rc": rc,
        "python_wall_s": wall,
        "stdout": stdout.strip(),
        "max_rss_kb": max_rss,
    }
    parsed_time = parse_time_verbose(stderr)
    if "max_rss_kb" in parsed_time:
        parsed_time["max_rss_kb"] = max(float(max_rss), parsed_time["max_rss_kb"])
    if "cpu_percent" not in parsed_time:
        user_s = parsed_time.get("user_s")
        sys_s = parsed_time.get("sys_s")
        wall_s = parsed_time.get("time_wall_s")
        if user_s is not None and sys_s is not None and wall_s:
            parsed_time["cpu_percent"] = ((user_s + sys_s) / wall_s) * 100.0
    metrics.update(parsed_time)
    metrics["max_rss_kb"] = max(float(max_rss), float(metrics.get("max_rss_kb", 0)))
    metrics.update(parse_boot_log(root / case.log))
    if rc != 0:
        metrics["stderr_tail"] = "\n".join(stderr.splitlines()[-20:])
    return metrics


def stat_size(path: Path) -> int | None:
    if not path.exists():
        return None
    return path.stat().st_size


def binary_size_metrics(root: Path) -> dict[str, object]:
    base = root / "Server/Rootfs/Generated/initramfs-root/System/Init"
    out = root / "Server/Rootfs/Generated/tmp/pid1-benchmark"
    out.mkdir(parents=True, exist_ok=True)
    metrics: dict[str, object] = {}
    for name in ("Mixtar", "MixtarCxx", "MixtarAil"):
        src = base / name
        metrics[f"{name}_bytes"] = stat_size(src)
        stripped = out / f"{name}.stripped"
        if src.exists() and shutil.which("strip"):
            shutil.copy2(src, stripped)
            strip_proc = run(["strip", str(stripped)], root)
            if strip_proc.returncode == 0:
                metrics[f"{name}_stripped_bytes"] = stripped.stat().st_size
        if src.exists() and shutil.which("size"):
            size_proc = run(["size", str(src)], root)
            if size_proc.returncode == 0:
                metrics[f"{name}_size_output"] = size_proc.stdout.strip()
    metrics["text_initramfs_bytes"] = stat_size(root / "Server/Rootfs/Generated/mixtar-initramfs.cpio.gz")
    metrics["graphical_initramfs_bytes"] = stat_size(root / "Server/Rootfs/Generated/mixtar-graphical-initramfs.cpio.gz")
    return metrics


def mean(values: list[float]) -> float | None:
    if not values:
        return None
    return statistics.fmean(values)


def summarize(samples: list[dict[str, object]]) -> dict[str, dict[str, float | int | None]]:
    grouped: dict[str, list[dict[str, object]]] = {}
    for sample in samples:
        grouped.setdefault(str(sample["case"]), []).append(sample)
    summary: dict[str, dict[str, float | int | None]] = {}
    fields = [
        "time_wall_s",
        "python_wall_s",
        "user_s",
        "sys_s",
        "max_rss_kb",
        "cpu_percent",
        "kernel_pid1_start_s",
        "kernel_powerdown_s",
        "kernel_pid1_to_powerdown_s",
    ]
    for name, rows in grouped.items():
        item: dict[str, float | int | None] = {"runs": len(rows), "failures": sum(1 for row in rows if row.get("rc") != 0)}
        for field in fields:
            vals = [float(row[field]) for row in rows if isinstance(row.get(field), (int, float))]
            item[f"avg_{field}"] = mean(vals)
            if vals:
                item[f"min_{field}"] = min(vals)
                item[f"max_{field}"] = max(vals)
        if item.get("avg_cpu_percent") is None:
            user_s = item.get("avg_user_s")
            sys_s = item.get("avg_sys_s")
            wall_s = item.get("avg_time_wall_s")
            if user_s is not None and sys_s is not None and wall_s:
                item["avg_cpu_percent"] = ((user_s + sys_s) / wall_s) * 100.0
        summary[name] = item
    return summary


def fmt(value: object, digits: int = 3) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def write_report(path: Path, result: dict[str, object]) -> None:
    summary = result["summary"]
    sizes = result["sizes"]
    samples = result["samples"]
    lines = [
        "# Mixtar PID1 Resource Benchmark",
        "",
        f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S %z')}",
        "",
        "## Binary And Image Size",
        "",
        "| Item | Bytes |",
        "|---|---:|",
    ]
    for key in (
        "Mixtar_bytes",
        "MixtarCxx_bytes",
        "MixtarAil_bytes",
        "Mixtar_stripped_bytes",
        "MixtarCxx_stripped_bytes",
        "MixtarAil_stripped_bytes",
        "text_initramfs_bytes",
        "graphical_initramfs_bytes",
    ):
        lines.append(f"| `{key}` | {fmt(sizes.get(key), 0)} |")

    lines += [
        "",
        "## Average Runtime Metrics",
        "",
        "| Case | Runs | Failures | Wall s | User s | Sys s | Max RSS KiB | CPU % | Kernel PID1->Poweroff s |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for case, row in sorted(summary.items()):
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{case}`",
                    fmt(row.get("runs"), 0),
                    fmt(row.get("failures"), 0),
                    fmt(row.get("avg_time_wall_s")),
                    fmt(row.get("avg_user_s")),
                    fmt(row.get("avg_sys_s")),
                    fmt(row.get("avg_max_rss_kb"), 0),
                    fmt(row.get("avg_cpu_percent"), 1),
                    fmt(row.get("avg_kernel_pid1_to_powerdown_s")),
                ]
            )
            + " |"
        )

    lines += ["", "## Raw Samples", "", "```json", json.dumps(samples, indent=2, sort_keys=True), "```", ""]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--text-runs", type=int, default=5)
    parser.add_argument("--graphical-runs", type=int, default=3)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--report", default="Server/Generated/reports/pid1-resource-benchmark.md")
    parser.add_argument("--json", default="Server/Generated/reports/pid1-resource-benchmark.json")
    args = parser.parse_args()

    root = repo_root()
    if args.build:
        for script in ("Server/Rootfs/scripts/build_initramfs.sh", "Server/Rootfs/scripts/build_graphical_initramfs.sh"):
            proc = run(["bash", script], root)
            if proc.returncode != 0:
                print(proc.stdout)
                print(proc.stderr)
                return proc.returncode

    cases = [
        Case("text-c", "Server/Rootfs/scripts/boot_qemu_smoke.sh", "Server/Rootfs/Generated/boot/boot-smoke.log", {}),
        Case("text-cxx", "Server/Rootfs/scripts/boot_qemu_cxx_smoke.sh", "Server/Rootfs/Generated/boot/boot-cxx-smoke.log", {}),
        Case("text-ail", "Server/Rootfs/scripts/boot_qemu_ail_smoke.sh", "Server/Rootfs/Generated/boot/boot-ail-smoke.log", {}),
        Case("graphical-c", "Server/Rootfs/scripts/boot_qemu_graphical_smoke.sh", "Server/Rootfs/Generated/boot/boot-graphical-smoke.log", {"MIXTAR_QEMU_DISPLAY": "none"}),
        Case("graphical-cxx", "Server/Rootfs/scripts/boot_qemu_cxx_graphical_smoke.sh", "Server/Rootfs/Generated/boot/boot-cxx-graphical-smoke.log", {"MIXTAR_QEMU_DISPLAY": "none"}),
        Case("graphical-ail", "Server/Rootfs/scripts/boot_qemu_ail_graphical_smoke.sh", "Server/Rootfs/Generated/boot/boot-ail-graphical-smoke.log", {}),
    ]

    samples: list[dict[str, object]] = []
    for case in cases:
        runs = args.graphical_runs if case.name.startswith("graphical") else args.text_runs
        for idx in range(runs):
            sample = run_case(case, root)
            sample["iteration"] = idx + 1
            samples.append(sample)
            print(f"{case.name} #{idx + 1}: rc={sample['rc']} wall={fmt(sample.get('time_wall_s'))} rss={fmt(sample.get('max_rss_kb'), 0)}")
            if sample["rc"] != 0:
                return int(sample["rc"])

    result = {
        "samples": samples,
        "summary": summarize(samples),
        "sizes": binary_size_metrics(root),
    }
    json_path = root / args.json
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    write_report(root / args.report, result)
    print(f"report={root / args.report}")
    print(f"json={json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
