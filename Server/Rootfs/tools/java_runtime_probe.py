#!/usr/bin/env python3
"""Measure Java runtime footprint and cold start for Mixtar feasibility.

This is intentionally not a PID1 boot benchmark. A JVM-based PID1 needs a
runtime image and kernel-facing syscall strategy, so this probe measures the
runtime cost that would be added before that design is considered viable.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path


JAVA_SOURCE = """\
public final class MixtarJavaProbe {
    public static void main(String[] args) throws Exception {
        long started = System.nanoTime();
        String target = System.getenv().getOrDefault("MIXTAR_TARGET", "smoke");
        if (!"smoke".equals(target)) {
            throw new IllegalStateException("unexpected target: " + target);
        }
        Process process = new ProcessBuilder("/bin/true").start();
        int rc = process.waitFor();
        if (rc != 0) {
            throw new IllegalStateException("child failed: " + rc);
        }
        long elapsed = System.nanoTime() - started;
        System.out.println("MixtarJavaProbe ok ns=" + elapsed);
    }
}
"""


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def run(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    next_env = os.environ.copy()
    if env:
        next_env.update(env)
    return subprocess.run(cmd, cwd=cwd, env=next_env, text=True, capture_output=True, check=False)


def proc_children(pid: int) -> list[int]:
    try:
        text = Path(f"/proc/{pid}/task/{pid}/children").read_text(encoding="ascii").strip()
    except OSError:
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
    try:
        for line in Path(f"/proc/{pid}/status").read_text(encoding="ascii", errors="ignore").splitlines():
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
        peak = max(peak, total)
        time.sleep(0.005)
    out["max_rss_kb"] = max(peak, sum(rss_kb(child) for child in proc_tree(pid)))


def run_timed(cmd: list[str], cwd: Path, env: dict[str, str]) -> dict[str, object]:
    next_env = os.environ.copy()
    next_env.update(env)
    started = time.perf_counter()
    proc = subprocess.Popen(
        cmd,
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
    return {
        "rc": proc.returncode,
        "stdout": stdout,
        "stderr": stderr,
        "wall_s": time.perf_counter() - started,
        "max_rss_kb": peak.get("max_rss_kb", 0),
    }


def require_tool(name: str) -> str | None:
    return shutil.which(name)


def dir_size(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        if item.is_file():
            total += item.stat().st_size
    return total


def write_report(path: Path, result: dict[str, object]) -> None:
    lines = [
        "# Java Runtime Probe",
        "",
        f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S %z')}",
        "",
        "This is a JVM/runtime feasibility probe, not a native PID1 boot benchmark.",
        "",
        "## Availability",
        "",
    ]
    for key, value in result["availability"].items():
        lines.append(f"- `{key}`: `{value}`")
    lines += [
        "",
        "## Size",
        "",
        "| Item | Bytes |",
        "|---|---:|",
    ]
    for key, value in result["sizes"].items():
        lines.append(f"| `{key}` | {value} |")
    lines += [
        "",
        "## JVM Cold Start Samples",
        "",
        "| Run | Wall s | User s | Sys s | Max RSS KiB |",
        "|---:|---:|---:|---:|---:|",
    ]
    for idx, sample in enumerate(result["jvm_samples"], start=1):
        lines.append(
            f"| {idx} | {sample.get('wall_s', 'n/a')} | {sample.get('user_s', 'n/a')} | "
            f"{sample.get('sys_s', 'n/a')} | {sample.get('max_rss_kb', 'n/a')} |"
        )
    native_samples = result.get("native_samples", [])
    if native_samples:
        lines += [
            "",
            "## Native Image Cold Start Samples",
            "",
            "| Run | Wall s | Max RSS KiB |",
            "|---:|---:|---:|",
        ]
        for idx, sample in enumerate(native_samples, start=1):
            lines.append(f"| {idx} | {sample.get('wall_s', 'n/a')} | {sample.get('max_rss_kb', 'n/a')} |")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    root = repo_root()
    out = root / "Server/Rootfs/Generated/tmp/java-runtime-probe"
    report = root / "Server/Generated/reports/java-runtime-probe.md"
    json_report = root / "Server/Generated/reports/java-runtime-probe.json"
    runs = int(os.environ.get("MIXTAR_JAVA_PROBE_RUNS", "5"))
    out.mkdir(parents=True, exist_ok=True)

    availability = {
        "java": require_tool("java") or "missing",
        "javac": require_tool("javac") or "missing",
        "jlink": require_tool("jlink") or "missing",
        "native-image": require_tool("native-image") or "missing",
    }
    if "missing" in (availability["java"], availability["javac"], availability["jlink"]):
        result = {"availability": availability, "sizes": {}, "jvm_samples": [], "native_samples": []}
        write_report(report, result)
        json_report.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
        print(f"report={report}")
        return 0

    src = out / "MixtarJavaProbe.java"
    src.write_text(JAVA_SOURCE, encoding="utf-8")
    compile_proc = run(["javac", str(src)], out)
    if compile_proc.returncode != 0:
        print(compile_proc.stdout)
        print(compile_proc.stderr)
        return compile_proc.returncode

    image = out / "runtime-java-base"
    if image.exists():
        shutil.rmtree(image)
    jlink_proc = run(
        [
            "jlink",
            "--add-modules",
            "java.base",
            "--strip-debug",
            "--no-header-files",
            "--no-man-pages",
            "--compress",
            "zip-6",
            "--output",
            str(image),
        ],
        out,
    )
    if jlink_proc.returncode != 0:
        print(jlink_proc.stdout)
        print(jlink_proc.stderr)
        return jlink_proc.returncode

    java_bin = image / "bin/java"
    jvm_samples = []
    env = {"MIXTAR_TARGET": "smoke"}
    for _idx in range(runs):
        sample = run_timed([str(java_bin), "-cp", str(out), "MixtarJavaProbe"], out, env=env)
        if sample["rc"] != 0:
            print(sample["stdout"])
            print(sample["stderr"])
            return int(sample["rc"])
        jvm_samples.append({"wall_s": sample["wall_s"], "max_rss_kb": sample["max_rss_kb"]})

    native_samples = []
    native_bin = out / "MixtarJavaProbeNative"
    if availability["native-image"] != "missing":
        if native_bin.exists():
            native_bin.unlink()
        native_proc = run(
            [
                "native-image",
                "--no-fallback",
                "-cp",
                str(out),
                "MixtarJavaProbe",
                "-o",
                str(native_bin),
            ],
            out,
        )
        if native_proc.returncode != 0:
            print(native_proc.stdout)
            print(native_proc.stderr)
            return native_proc.returncode
        for _idx in range(runs):
            sample = run_timed([str(native_bin)], out, env=env)
            if sample["rc"] != 0:
                print(sample["stdout"])
                print(sample["stderr"])
                return int(sample["rc"])
            native_samples.append({"wall_s": sample["wall_s"], "max_rss_kb": sample["max_rss_kb"]})

    sizes = {
        "jlink_java_base_runtime_bytes": dir_size(image),
        "MixtarJavaProbe_class_bytes": (out / "MixtarJavaProbe.class").stat().st_size,
    }
    if native_bin.exists():
        sizes["MixtarJavaProbeNative_bytes"] = native_bin.stat().st_size
        stripped = out / "MixtarJavaProbeNative.stripped"
        if shutil.which("strip"):
            shutil.copy2(native_bin, stripped)
            strip_proc = run(["strip", str(stripped)], out)
            if strip_proc.returncode == 0:
                sizes["MixtarJavaProbeNative_stripped_bytes"] = stripped.stat().st_size
    result = {
        "availability": availability,
        "sizes": sizes,
        "jvm_samples": jvm_samples,
        "native_samples": native_samples,
    }
    write_report(report, result)
    json_report.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print(f"report={report}")
    print(f"json={json_report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
