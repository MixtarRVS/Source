#!/usr/bin/env python3
"""Linux-native command-search and mixed-pipeline probe for msh.

This probe must run on a POSIX host, normally WSL. It verifies behavior that a
Windows-hosted msh binary cannot prove, especially chmod-sensitive PATH lookup.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def body_without_marker(stdout: str) -> str:
    lines = stdout.splitlines(keepends=True)
    if lines and lines[-1].startswith("status="):
        return "".join(lines[:-1])
    return stdout


def run_msh(msh: Path, source: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(msh), "eval", source],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def write_script(path: Path, text: str, mode: int) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)


def expect_case(
    msh: Path,
    cwd: Path,
    name: str,
    source: str,
    want_status: int,
    want_stdout: str | None = None,
    want_stderr: str | None = None,
) -> int:
    proc = run_msh(msh, source, cwd)
    body = body_without_marker(proc.stdout)
    ok = proc.returncode == want_status
    if want_stdout is not None and body != want_stdout:
        ok = False
    if want_stderr is not None and want_stderr not in proc.stderr:
        ok = False
    if ok:
        return 0
    print(f"[FAIL] {name}", file=sys.stderr)
    print(f"  source: {source}", file=sys.stderr)
    print(f"  status: got {proc.returncode}, want {want_status}", file=sys.stderr)
    print(f"  stdout body: {body!r}", file=sys.stderr)
    print(f"  stderr: {proc.stderr!r}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--msh", required=True, type=Path)
    args = parser.parse_args()

    if os.name == "nt":
        print("msh_linux_command_search_probe.py must run on Linux/WSL", file=sys.stderr)
        return 2

    msh = args.msh.resolve()
    with tempfile.TemporaryDirectory(prefix="msh-linux-search-") as tmp:
        root = Path(tmp)
        blocked = root / "blocked"
        later = root / "later"
        blocked.mkdir()
        later.mkdir()
        write_script(blocked / "probe", "printf 'blocked\\n'\n", 0o644)
        write_script(later / "probe", "printf 'later\\n'\n", 0o755)
        write_script(root / "noexec", "printf 'noexec\\n'\n", 0o644)
        write_script(root / "plain", "printf 'plain\\n'\n", 0o755)
        write_script(root / "reader", "read X\nprintf 'got:%s\\n' \"$X\"\n", 0o755)
        garbage = root / "garbage"
        garbage.write_bytes(b"\x7fBAD\x00\x01")
        garbage.chmod(0o755)
        write_script(root / "curpath", "printf 'curpath\\n'\n", 0o755)
        write_script(blocked / "order", "printf 'first\\n'\n", 0o755)
        write_script(later / "order", "printf 'second\\n'\n", 0o755)
        (blocked / "asdir").mkdir()
        write_script(later / "asdir", "printf 'later-dir-skip\\n'\n", 0o755)
        write_script(later / "suppressed", "printf 'path-function\\n'\n", 0o755)
        write_script(blocked / "source_probe", "printf 'blocked-source\\n'\n", 0o333)
        write_script(later / "source_probe", "printf 'later-source\\n'\n", 0o444)
        write_script(root / "unreadable_source", "printf 'hidden\\n'\n", 0o000)

        failures = 0
        failures += expect_case(
            msh,
            root,
            "PATH first executable wins",
            f"PATH={blocked}:{later}; order",
            0,
            "first\n",
        )
        failures += expect_case(
            msh,
            root,
            "PATH skips directory candidate and runs later executable",
            f"PATH={blocked}:{later}; asdir",
            0,
            "later-dir-skip\n",
        )
        failures += expect_case(
            msh,
            root,
            "empty PATH searches current directory",
            "PATH=; curpath",
            0,
            "curpath\n",
        )
        failures += expect_case(
            msh,
            root,
            "command suppresses function and finds PATH command",
            f"PATH={later}; suppressed() {{ printf 'function\\n'; }}; command suppressed",
            0,
            "path-function\n",
        )
        failures += expect_case(
            msh,
            root,
            "dot PATH skips unreadable source candidate and reads later candidate",
            f"PATH={blocked}:{later}; . source_probe",
            0,
            "later-source\n",
        )
        failures += expect_case(
            msh,
            root,
            "explicit unreadable dot source fails with permission denied",
            ". ./unreadable_source",
            2,
            "",
            "Permission denied",
        )
        failures += expect_case(
            msh,
            root,
            "PATH skips non-executable and runs later executable",
            f"PATH={blocked}:{later}; probe",
            0,
            "later\n",
        )
        failures += expect_case(
            msh,
            root,
            "command -v reports executable later PATH candidate",
            f"PATH={blocked}:{later}; command -v probe",
            0,
            f"{later / 'probe'}\n",
        )
        failures += expect_case(
            msh,
            root,
            "command -v ignores only non-executable PATH candidate",
            f"PATH={blocked}; command -v probe; printf '<%s>\\n' $?",
            0,
            "<127>\n",
        )
        failures += expect_case(
            msh,
            root,
            "command -V reports only non-executable PATH candidate as not found",
            f"PATH={blocked}; command -V probe; printf '<%s>\\n' $?",
            0,
            "probe: not found\n<127>\n",
        )
        failures += expect_case(
            msh,
            root,
            "type reports only non-executable PATH candidate as not found",
            f"PATH={blocked}; type probe; printf '<%s>\\n' $?",
            0,
            "probe: not found\n<127>\n",
        )
        failures += expect_case(
            msh,
            root,
            "only non-executable PATH candidate is not runnable",
            f"PATH={blocked}; probe",
            127,
            "",
            "Permission denied",
        )
        failures += expect_case(
            msh,
            root,
            "explicit non-executable path is permission denied",
            "./noexec",
            126,
            "",
            "Permission denied",
        )
        failures += expect_case(
            msh,
            root,
            "mixed shell-local to external pipeline feeds stdin",
            "printf hello | grep hello >/dev/null",
            0,
            "",
        )
        failures += expect_case(
            msh,
            root,
            "explicit stdin redirection overrides mixed pipeline input",
            "printf no > input.txt; printf yes | grep no < input.txt >/dev/null",
            0,
            "",
        )
        failures += expect_case(
            msh,
            root,
            "PATH executable text script fallback",
            f"PATH={root}; plain",
            0,
            "plain\n",
        )
        failures += expect_case(
            msh,
            root,
            "explicit executable text script fallback",
            "./plain",
            0,
            "plain\n",
        )
        failures += expect_case(
            msh,
            root,
            "runtime ENOEXEC fallback through command -p explicit path",
            "command -p ./plain",
            0,
            "plain\n",
        )
        failures += expect_case(
            msh,
            root,
            "command -p executes default-path sh despite caller PATH",
            "PATH=/definitely_missing\ncommand -p sh -c 'exit 7'\nprintf '<%s>\\n' $?",
            0,
            "<7>\n",
        )
        failures += expect_case(
            msh,
            root,
            "runtime ENOEXEC fallback through exec explicit path",
            "exec ./plain; printf bad",
            0,
            "plain\n",
        )
        failures += expect_case(
            msh,
            root,
            "text script producer in pipeline runs through msh fallback",
            "./plain | grep plain >/dev/null",
            0,
            "",
        )
        failures += expect_case(
            msh,
            root,
            "text script consumer in pipeline reads msh-fed stdin",
            "printf 'pipe-script\\n' | ./reader",
            0,
            "got:pipe-script\n",
        )
        failures += expect_case(
            msh,
            root,
            "explicit executable binary garbage returns exec format status",
            "./garbage",
            126,
            "",
            "Exec format error",
        )
        failures += expect_case(
            msh,
            root,
            "PATH executable binary garbage returns exec format status",
            "PATH=.; garbage",
            126,
            "",
            "Exec format error",
        )
        failures += expect_case(
            msh,
            root,
            "command -p executable binary garbage returns exec format status",
            "command -p ./garbage",
            126,
            "",
            "Exec format error",
        )
        failures += expect_case(
            msh,
            root,
            "non-tail non-executable pipeline stage reports permission but tail decides status",
            "./noexec | cat",
            0,
            "",
            "Permission denied",
        )
        failures += expect_case(
            msh,
            root,
            "tail non-executable pipeline stage returns permission status",
            "printf x | ./noexec",
            126,
            "",
            "Permission denied",
        )
        failures += expect_case(
            msh,
            root,
            "external child inherits saved logical stdout fd",
            "exec 4>&1\n"
            "exec > out\n"
            "exec 3>&1\n"
            "printf 'A\\n'\n"
            "sh -c 'printf \"B\\n\" >&3'\n"
            "exec >&4\n"
            "exec < out\n"
            "read A\n"
            "read B\n"
            "printf '%s:%s\\n' \"$A\" \"$B\"",
            0,
            "A:B\n",
        )
        failures += expect_case(
            msh,
            root,
            "mixed pipeline child inherits saved logical stdout fd",
            "exec 4>&1\n"
            "exec > out\n"
            "exec 3>&1\n"
            "printf 'A\\n' | sh -c 'cat >/dev/null; printf \"B\\n\" >&3'\n"
            "exec >&4\n"
            "exec < out\n"
            "read A\n"
            "read B\n"
            "printf '%s:%s\\n' \"$A\" \"$B\"",
            0,
            "B:\n",
        )
        failures += expect_case(
            msh,
            root,
            "external child inherits saved logical stdin fd",
            "printf 'A\\n' > in\n"
            "exec < in\n"
            "exec 3<&0\n"
            "sh -c 'read X <&3; printf \"%s\\n\" \"$X\"'",
            0,
            "A\n",
        )
        failures += expect_case(
            msh,
            root,
            "external child inherits consumed persistent stdin offset",
            "printf 'A\\nB\\nC\\n' > in\n"
            "exec < in\n"
            "read A\n"
            "cat",
            0,
            "B\nC\n",
        )
        failures += expect_case(
            msh,
            root,
            "external child inherits consumed saved logical stdin fd",
            "printf 'A\\nB\\nC\\n' > in\n"
            "exec < in\n"
            "exec 3<&0\n"
            "read A\n"
            "sh -c 'read X <&3; printf \"%s\\n\" \"$X\"'",
            0,
            "B\n",
        )
        failures += expect_case(
            msh,
            root,
            "external child advances saved logical stdin fd offset",
            "printf 'A\\nB\\nC\\n' > in\n"
            "exec < in\n"
            "exec 3<&0\n"
            "sh -c 'read X <&3'\n"
            "read Y <&3\n"
            "printf '%s\\n' \"$Y\"",
            0,
            "B\n",
        )
        failures += expect_case(
            msh,
            root,
            "native child reads chained stdin fd7 and advances fd6",
            "printf 'A\\nB\\n' > in\n"
            "exec 6<in\n"
            "exec 7<&6\n"
            "sh -c 'read X <&7; printf \"%s\\n\" \"$X\"'\n"
            "read Y <&6\n"
            "printf '<%s>\\n' \"$Y\"",
            0,
            "A\n<B>\n",
        )
        failures += expect_case(
            msh,
            root,
            "pipeline child reads chained stdin fd7 and advances fd6",
            "printf 'A\\nB\\n' > in\n"
            "exec 6<in\n"
            "exec 7<&6\n"
            "printf ignored | sh -c 'cat >/dev/null; read X <&7; printf \"%s\\n\" \"$X\"'\n"
            "read Y <&6\n"
            "printf '<%s>\\n' \"$Y\"",
            0,
            "A\n<B>\n",
        )
        failures += expect_case(
            msh,
            root,
            "native child writes chained stdout fd7 shared with fd6",
            "exec 6>out\n"
            "exec 7>&6\n"
            "sh -c 'printf A >&7'\n"
            "printf B >&6\n"
            "exec 6>&-\n"
            "exec 7>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"",
            0,
            "<AB>\n",
        )
        failures += expect_case(
            msh,
            root,
            "pipeline child writes chained stdout fd7 shared with fd6",
            "exec 6>out\n"
            "exec 7>&6\n"
            "printf ignored | sh -c 'cat >/dev/null; printf A >&7'\n"
            "printf B >&6\n"
            "exec 6>&-\n"
            "exec 7>&-\n"
            "read X < out\n"
            "printf '<%s>\\n' \"$X\"",
            0,
            "<AB>\n",
        )
    if failures:
        print(f"linux command-search probe: FAIL ({failures})", file=sys.stderr)
        return 1
    print("linux command-search probe: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
