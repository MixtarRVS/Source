#!/usr/bin/env python3
"""Linux-native POSIX filesystem/profile probe for msh.

Windows-hosted gates can prove syntax and false cases for most predicates, but
block devices, character devices, FIFOs, Unix sockets, and set-id mode bits need
a POSIX host. Logical/physical `cd` symlink behavior also needs a real POSIX
filesystem. Run this inside WSL/Linux against a Linux-built msh executable.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


RUN_TIMEOUT_SECONDS = 30


@dataclass(frozen=True)
class ProbeCase:
    name: str
    script: str


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def sh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\"'\"'") + "'"


def parse_msh(proc: subprocess.CompletedProcess[str]) -> RunResult:
    lines = proc.stdout.splitlines(keepends=True)
    if lines and lines[-1].startswith("status="):
        raw = lines[-1].strip()[7:]
        try:
            status = int(raw)
        except ValueError:
            status = proc.returncode
        return RunResult(status, "".join(lines[:-1]), proc.stderr)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def run_cmd(argv: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            argv,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=RUN_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        if stderr:
            stderr += "\n"
        stderr += f"timeout after {RUN_TIMEOUT_SECONDS}s"
        return subprocess.CompletedProcess(argv, 124, stdout, stderr)


def run_msh(msh: Path, script: str, cwd: Path) -> RunResult:
    return parse_msh(run_cmd([str(msh), "eval", script], cwd))


def run_sh(script: str, cwd: Path) -> RunResult:
    script_path = cwd / "case.sh"
    script_path.write_text(script, encoding="utf-8", newline="\n")
    proc = run_cmd(["/bin/sh", str(script_path)], cwd)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def find_block_device() -> str:
    for raw in ("/dev/loop0", "/dev/sda", "/dev/vda", "/dev/nvme0n1"):
        path = Path(raw)
        if path.exists():
            return raw
    return ""


def status_case(name: str, expression: str) -> ProbeCase:
    return ProbeCase(name, f"test {expression}; printf '<%s>\\n' $?")


def bracket_status_case(name: str, expression: str) -> ProbeCase:
    return ProbeCase(name, f"[ {expression} ]; printf '<%s>\\n' $?")


def cases(root: Path) -> list[ProbeCase]:
    regular = root / "regular"
    regular.write_text("x\n", encoding="utf-8")
    directory = root / "directory"
    directory.mkdir()
    real_dir = root / "real"
    real_dir.mkdir()
    link_dir = root / "link-dir"
    link_dir.symlink_to(real_dir, target_is_directory=True)
    fifo = root / "fifo"
    os.mkfifo(fifo)
    link = root / "link"
    link.symlink_to(regular)
    link_file = root / "link-file"
    link_file.symlink_to(regular)
    dangling = root / "dangling-link"
    dangling.symlink_to(root / "missing-target")
    setuid_file = root / "setuid"
    setuid_file.write_text("x\n", encoding="utf-8")
    setuid_file.chmod(0o4755)
    setgid_file = root / "setgid"
    setgid_file.write_text("x\n", encoding="utf-8")
    setgid_file.chmod(0o2755)

    sock_path = root / "sock"
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(str(sock_path))
    sock.close()

    out = [
        status_case("character device true", "-c /dev/null"),
        status_case("directory true", f"-d {sh_quote(str(directory))}"),
        status_case("fifo true", f"-p {sh_quote(str(fifo))}"),
        status_case("socket true", f"-S {sh_quote(str(sock_path))}"),
        status_case("symbolic link -L true", f"-L {sh_quote(str(link))}"),
        status_case("symbolic link -h true", f"-h {sh_quote(str(link))}"),
        status_case("symlink to file -e true", f"-e {sh_quote(str(link_file))}"),
        status_case("symlink to file -f true", f"-f {sh_quote(str(link_file))}"),
        status_case("symlink to directory -e true", f"-e {sh_quote(str(link_dir))}"),
        status_case("symlink to directory -d true", f"-d {sh_quote(str(link_dir))}"),
        status_case("dangling symlink -L true", f"-L {sh_quote(str(dangling))}"),
        status_case("dangling symlink -e false", f"-e {sh_quote(str(dangling))}"),
        status_case("setuid true", f"-u {sh_quote(str(setuid_file))}"),
        status_case("setgid true", f"-g {sh_quote(str(setgid_file))}"),
        status_case("terminal stdout false in noninteractive probe", "-t 1"),
        status_case("regular is not char", f"-c {sh_quote(str(regular))}"),
        status_case("regular is not fifo", f"-p {sh_quote(str(regular))}"),
        status_case("regular is not socket", f"-S {sh_quote(str(regular))}"),
        bracket_status_case("bracket fifo true", f"-p {sh_quote(str(fifo))}"),
        bracket_status_case("bracket socket true", f"-S {sh_quote(str(sock_path))}"),
        ProbeCase(
            "cd default logical PWD preserves symlink",
            f"cd {sh_quote(str(link_dir))}\nprintf '<%s>\\n' \"$PWD\"\npwd -L\npwd -P",
        ),
        ProbeCase(
            "cd -P canonicalizes symlink PWD",
            f"cd {sh_quote(str(link_dir))}\ncd -P .\nprintf '<%s>\\n' \"$PWD\"\npwd -P",
        ),
        ProbeCase(
            "cd -L keeps logical symlink PWD",
            f"cd {sh_quote(str(link_dir))}\ncd -L .\nprintf '<%s>\\n' \"$PWD\"\npwd -P",
        ),
        ProbeCase(
            "cd - returns previous logical symlink PWD",
            f"cd {sh_quote(str(link_dir))}\ncd ..\ncd -\nprintf '<%s>\\n' \"$PWD\"",
        ),
        ProbeCase(
            "cd -L absolute symlink keeps target spelling",
            f"cd -L {sh_quote(str(link_dir))}\nprintf '<%s>\\n' \"$PWD\"\npwd -P",
        ),
        ProbeCase(
            "umask 077 applies to redirection create",
            "rm -f u077\numask 077\n: > u077\nstat -c '<%a>' u077",
        ),
        ProbeCase(
            "umask 000 applies to redirection create",
            "rm -f u000\numask 000\n: > u000\nstat -c '<%a>' u000",
        ),
        ProbeCase(
            "umask 027 applies to append create",
            "rm -f u027\numask 027\nprintf x >> u027\nstat -c '<%a>' u027",
        ),
        ProbeCase(
            "umask 077 applies to read-write create",
            "rm -f urw\numask 077\n: <> urw\nstat -c '<%a>' urw",
        ),
        ProbeCase(
            "umask 077 applies through builtin redirection",
            "rm -f ucmd\numask 077\nprintf x > ucmd\nstat -c '<%a>' ucmd",
        ),
    ]
    block = find_block_device()
    if block:
        out.append(status_case("block device true", f"-b {sh_quote(block)}"))
    return out


def run_case(msh: Path, case: ProbeCase, root: Path) -> dict[str, object]:
    msh_result = run_msh(msh, case.script, root)
    ref = run_sh(case.script, root)
    matches = (
        msh_result.status == ref.status
        and msh_result.stdout == ref.stdout
        and msh_result.stderr == ref.stderr
    )
    return {
        "name": case.name,
        "script": case.script,
        "matches": matches,
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
        },
        "sh": {
            "status": ref.status,
            "stdout": ref.stdout,
            "stderr": ref.stderr,
        },
    }


def write_reports(rows: list[dict[str, object]], json_path: Path, md_path: Path) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    lines = [
        "# msh Linux Filesystem/Profile Probe",
        "",
        "Generated by `msh_linux_test_predicate_probe.py` against Linux `/bin/sh`.",
        "",
        f"- Overall: `{matches}/{total}`",
        "",
        "## Mismatches",
        "",
    ]
    mismatches = [row for row in rows if row["matches"] is not True]
    if not mismatches:
        lines.extend(["No mismatches.", ""])
    for row in mismatches:
        msh = row["msh"]
        sh = row["sh"]
        lines.extend(
            [
                f"### {row['name']}",
                "",
                "```sh",
                str(row["script"]).rstrip(),
                "```",
                "",
                f"- msh: status `{msh['status']}`, stdout `{msh['stdout']!r}`, stderr `{msh['stderr']!r}`",
                f"- sh: status `{sh['status']}`, stdout `{sh['stdout']!r}`, stderr `{sh['stderr']!r}`",
                "",
            ]
        )
    md_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Linux-native filesystem/profile probe.")
    parser.add_argument("--msh", required=True, type=Path)
    parser.add_argument("--json-report", type=Path, default=Path("Server/Generated/reports/msh-linux-test-predicate.json"))
    parser.add_argument("--report", type=Path, default=Path("Server/Generated/reports/msh-linux-test-predicate.md"))
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    if os.name == "nt":
        print("msh_linux_test_predicate_probe.py must run on Linux/WSL", file=sys.stderr)
        return 2
    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="msh-linux-test-") as raw:
        root = Path(raw)
        rows = []
        for case in cases(root):
            rows.append(run_case(msh, case, root))

    write_reports(rows, args.json_report, args.report)
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh linux filesystem/profile probe: {matches}/{total} match /bin/sh")
    if args.strict and matches != total:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
