#!/usr/bin/env python3
"""Compare hosted-safe msh fd/process behavior against WSL /bin/sh.

Linux-native external-child fd inheritance is covered by
msh_linux_fd_graph_probe.py. This matrix stays safe for the Windows-hosted
finish-line gate by using shell builtins, functions, groups, subshells,
pipelines, and files only.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from msh_tool_process import run_tool_cmd
from msh_matrix_reference import local_reference_shell_names, run_local_reference_shell
import tempfile
from dataclasses import dataclass
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
MIXTAR_ROOT = Path(__file__).resolve().parents[4]
REPORT_DIR = MIXTAR_ROOT / "Server" / "Generated" / "reports"
DEFAULT_MSH = MIXTAR_ROOT / "out" / "server" / "msh_cli.exe"
DEFAULT_JSON = REPORT_DIR / "msh-fd-process-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-fd-process-matrix.md"
RUN_TIMEOUT_SECONDS = 10
WSL_DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
_WSL_AVAILABLE: bool | None = None


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    script: str
    compare_stderr: bool = False


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def run_cmd(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return run_tool_cmd(argv, cwd, timeout=RUN_TIMEOUT_SECONDS)


def wsl_available() -> bool:
    global _WSL_AVAILABLE
    if _WSL_AVAILABLE is not None:
        return _WSL_AVAILABLE
    proc = run_cmd(["wsl.exe", "--exec", "sh", "-c", "echo ok"])
    _WSL_AVAILABLE = proc.returncode == 0 and proc.stdout == "ok\n"
    return _WSL_AVAILABLE


def windows_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def parse_msh(stdout: str, stderr: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], stderr)
    lines: list[str] = []
    status = returncode
    for line in stdout.splitlines():
        if line.startswith("status="):
            try:
                status = int(line[7:])
            except ValueError:
                status = returncode
        else:
            lines.append(line)
    text = "\n".join(lines)
    if text:
        text += "\n"
    return RunResult(status, text, stderr)


def normalize_stderr(stderr: str) -> str:
    if not stderr:
        return ""
    lines: list[str] = []
    for line in stderr.splitlines():
        line = WSL_DIAG_PREFIX_RE.sub("", line)
        if line.startswith("msh: "):
            line = line[5:]
        lines.append(line)
    text = "\n".join(lines)
    if stderr.endswith("\n"):
        text += "\n"
    return text


def run_msh(msh: Path, case: MatrixCase, cwd: Path) -> RunResult:
    proc = run_cmd([str(msh), "eval", case.script], cwd=cwd)
    return parse_msh(proc.stdout, proc.stderr, proc.returncode)


def run_wsl_sh(case: MatrixCase, cwd: Path) -> RunResult:
    if not wsl_available():
        return RunResult(127, "", "wsl unavailable\n")
    script_path = cwd / "case.sh"
    body = "cd " + windows_to_wsl_path(cwd) + " || exit 125\n" + case.script
    script_path.write_text(body, encoding="utf-8", newline="\n")
    proc = run_cmd(["wsl.exe", "--exec", "sh", windows_to_wsl_path(script_path)])
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase("persistent", "stdout-redirect-persists", "exec 3>&1\nexec > out\nprintf A\nprintf B\nexec >&3\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("persistent", "stdout-append-persists", "printf Z > out\nexec 3>&1\nexec >> out\nprintf A\nexec >&3\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("persistent", "stdin-redirect-persists", "printf 'A\\nB\\n' > in\nexec < in\nread A\nread B\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("persistent", "restore-stdin-from-saved-fd", "printf 'A\\nB\\n' > in\nexec < in\nexec 3<&0\nread A\nread B <&3\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("stdout-fds", "fd3-output", "exec 3> out\nprintf A >&3\nprintf B >&3\nexec 3>&-\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("stdout-fds", "fd4-duplicates-fd3", "exec 3> out\nexec 4>&3\nprintf A >&4\nprintf B >&3\nexec 3>&-\nexec 4>&-\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("stdout-fds", "fd4-survives-fd3-close", "exec 3> out\nexec 4>&3\nexec 3>&-\nprintf A >&4\nexec 4>&-\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("stdout-fds", "fd5-fd6-fd7-chain", "exec 5> out\nexec 6>&5\nexec 7>&6\nprintf A >&7\nprintf B >&5\nexec 5>&-\nexec 6>&-\nexec 7>&-\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("stdout-fds", "append-fd3", "printf Z > out\nexec 3>> out\nprintf A >&3\nexec 3>&-\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("stdout-fds", "fd3-close-fails-later-write", "exec 3> out\nexec 3>&-\nprintf A >&3\nprintf 's=%s\\n' $?\nread X < out\nprintf '<%s>\\n' \"$X\"", True),
        MatrixCase("stdout-fds", "fd3-to-stdout-restore-command-local", "exec 3> out\nprintf A 1>&3\nprintf B\nexec 3>&-\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("stdin-fds", "fd3-input-offset", "printf 'A\\nB\\n' > in\nexec 3< in\nread A <&3\nread B <&3\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("stdin-fds", "fd4-duplicates-fd3-offset", "printf 'A\\nB\\n' > in\nexec 3< in\nexec 4<&3\nread A <&3\nread B <&4\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("stdin-fds", "fd4-survives-fd3-close", "printf 'A\\nB\\n' > in\nexec 3< in\nexec 4<&3\nexec 3<&-\nread A <&4\nprintf '<%s>\\n' \"$A\""),
        MatrixCase("stdin-fds", "fd6-fd7-chain-offset", "printf 'A\\nB\\nC\\n' > in\nexec 6< in\nexec 7<&6\nread A <&7\nread B <&6\nread C <&7\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$C\""),
        MatrixCase("stdin-fds", "closed-input-fd-fails-read", "exec 3<&-\nread A <&3\nprintf 's=%s:%s\\n' $? \"$A\"", True),
        MatrixCase("stdin-fds", "input-dup-local-redirection-restores", "printf 'A\\n' > in\nprintf 'B\\n' > main\nexec 3< in\nexec < main\nread A <&3\nread B\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("stdin-fds", "command-local-input-override-restores-persistent", "printf 'A\\nB\\n' > outer\nprintf 'I\\n' > inner\nexec 3< outer\nread I <&3 3< inner\nread O <&3\nprintf '<%s:%s>\\n' \"$I\" \"$O\""),
        MatrixCase("compound", "group-stdout-redirection", "{ printf A; printf B; } > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "function-stdout-redirection", "f() { printf A; printf B; }\nf > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "if-trailing-redirection", "if true; then printf A; fi > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "while-trailing-redirection", "i=0\nwhile [ $i -lt 2 ]; do printf A; i=$((i+1)); done > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "for-trailing-redirection", "for x in A B; do printf $x; done > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "case-trailing-redirection", "case x in x) printf A;; esac > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "subshell-close-does-not-leak", "exec 3> out\n(exec 3>&-)\nprintf A >&3\nexec 3>&-\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "group-fd3-local-redirection", "{ printf A >&3; printf B >&3; } 3> out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("compound", "command-local-fd3-overrides-restores", "exec 3> outer\n{ printf I >&3; } 3> inner\nprintf O >&3\nexec 3>&-\nread A < inner\nread B < outer\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("compound", "function-local-fd3-overrides-restores", "exec 3> outer\nf() { printf I >&3; }\nf 3> inner\nprintf O >&3\nexec 3>&-\nread A < inner\nread B < outer\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("compound", "if-input-redirection", "printf 'A\\n' > in\nif read X; then printf '<%s>\\n' \"$X\"; fi < in"),
        MatrixCase("compound", "while-input-redirection", "printf 'A\\nB\\n' > in\nwhile read X; do printf '<%s>' \"$X\"; done < in\nprintf '\\n'"),
        MatrixCase("compound", "for-input-redirection", "printf 'A\\n' > in\nfor x in one; do read X; printf '<%s:%s>\\n' \"$x\" \"$X\"; done < in"),
        MatrixCase("compound", "case-input-redirection", "printf 'A\\n' > in\ncase x in x) read X; printf '<%s>\\n' \"$X\";; esac < in"),
        MatrixCase("compound", "subshell-output-isolation", "(printf I) > inner\nprintf O > outer\nread A < inner\nread B < outer\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("compound", "group-nested-redirection", "exec 3> outer\n{ { printf I >&3; } 3> inner; printf O >&3; }\nexec 3>&-\nread A < inner\nread B < outer\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("pipeline", "group-read-pipeline", "printf 'A\\n' | { read X; printf '<%s>\\n' \"$X\"; }"),
        MatrixCase("pipeline", "while-read-pipeline", "printf 'A\\nB\\n' | while read X; do printf '<%s>' \"$X\"; done\nprintf '\\n'"),
        MatrixCase("pipeline", "pipeline-variable-isolation", "printf 'A\\n' | read X\nprintf '<%s>\\n' \"${X-unset}\""),
        MatrixCase("pipeline", "pipeline-stage-fd-redirection", "printf ignored | { read X; printf A >&3; } 3> out\nread Y < out\nprintf '<%s>\\n' \"$Y\""),
        MatrixCase("pipeline", "pipeline-subsequent-fd-write", "exec 3> out\nprintf ignored | { read X; printf A >&3; }\nprintf B >&3\nexec 3>&-\nread Y < out\nprintf '<%s>\\n' \"$Y\""),
        MatrixCase("pipeline", "pipeline-right-output-redirection", "printf A | { read X; printf '%s' \"$X\"; } > out\nread Y < out\nprintf '<%s>\\n' \"$Y\""),
        MatrixCase("pipeline", "pipeline-left-output-redirection", "{ printf A; } > out | :\nread Y < out\nprintf '<%s>\\n' \"$Y\""),
        MatrixCase("stderr-fds", "stderr-persistent-redirect-restore", "exec 3>&2\nexec 2> err\nprintf E >&2\nexec 2>&3\nexec 3>&-\nread X < err\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("stderr-fds", "stderr-command-local-redirect", "printf E >&2 2> err\nread X < err\nprintf '<%s>\\n' \"$X\"", True),
        MatrixCase("stderr-fds", "stderr-left-right-redirect-before-dup", "exec 4> err\nprintf E 2> other 2>&4\nexec 4>&-\nread A < err\nread B < other\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("stderr-fds", "stderr-left-right-dup-before-redirect", "exec 4> err\nprintf E 2>&4 2> other\nexec 4>&-\nread A < err\nread B < other\nprintf '<%s:%s>\\n' \"$A\" \"$B\""),
        MatrixCase("background", "background-redirection-create", ": > out &\nwait\nif [ -f out ]; then printf '<yes>\\n'; else printf '<no>\\n'; fi"),
        MatrixCase("ordering", "left-to-right-dup-before-redirect", "exec 3>&1\nprintf A > out 1>&3\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("ordering", "left-to-right-redirect-before-dup", "exec 3>&1\nprintf A 1>&3 > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("ordering", "truncate-before-later-bad-fd", "printf old > out\n: > out >&9\nprintf 's=%s\\n' $?\nread X < out\nprintf '<%s>\\n' \"$X\"", True),
        MatrixCase("ordering", "force-clobber-overrides-noclobber", "printf old > out\nset -C\nprintf new >| out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("ordering", "noclobber-failure-keeps-file", "printf old > out\nset -C\n: > out\nprintf 's=%s\\n' $?\nread X < out\nprintf '<%s>\\n' \"$X\"", True),
        MatrixCase("redirection-only", "fd-open-without-command", "3> out\nprintf A > out2\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("redirection-only", "fd-close-without-command", "exec 3> out\n3>&-\nprintf A >&3\nprintf 's=%s\\n' $?", True),
        MatrixCase('stdout-fds', 'fd8-output', 'exec 8> out\nprintf A >&8\nexec 8>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdout-fds', 'fd8-fd9-chain', 'exec 8> out\nexec 9>&8\nprintf A >&9\nprintf B >&8\nexec 8>&-\nexec 9>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdout-fds', 'fd9-survives-fd8-close', 'exec 8> out\nexec 9>&8\nexec 8>&-\nprintf A >&9\nexec 9>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdout-fds', 'fd3-reopen-truncates', 'exec 3> out\nprintf old >&3\nexec 3> out\nprintf new >&3\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdout-fds', 'fd3-reopen-append', 'exec 3> out\nprintf A >&3\nexec 3>> out\nprintf B >&3\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdout-fds', 'command-local-close-does-not-close-persistent', 'exec 3> out\nprintf X 3>&-\nprintf A >&3\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdout-fds', 'command-local-fd3-overrides-persistent', 'exec 3> outer\nprintf I >&3 3> inner\nprintf O >&3\nexec 3>&-\nread A < inner\nread B < outer\nprintf \'<%s:%s>\\n\' "$A" "$B"', False),
        MatrixCase('stdout-fds', 'duplicate-persistent-stdout-after-redirect', 'exec > out\nexec 3>&1\nprintf A >&3\nprintf B\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdout-fds', 'restore-stdout-from-fd3-after-command-local', 'exec 3>&1\nprintf A > out\nprintf B >&3\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stdin-fds', 'fd8-input-offset', 'printf \'A\\nB\\n\' > in\nexec 8< in\nread A <&8\nread B <&8\nprintf \'<%s:%s>\\n\' "$A" "$B"', False),
        MatrixCase('stdin-fds', 'fd8-fd9-chain-offset', 'printf \'A\\nB\\nC\\n\' > in\nexec 8< in\nexec 9<&8\nread A <&9\nread B <&8\nread C <&9\nprintf \'<%s:%s:%s>\\n\' "$A" "$B" "$C"', False),
        MatrixCase('stdin-fds', 'command-local-close-input-does-not-close-persistent', 'printf \'A\\nB\\n\' > in\nexec 3< in\nread X 3<&-\nread A <&3\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('stdin-fds', 'function-local-close-input-does-not-close-persistent', 'printf \'A\\nB\\n\' > in\nexec 3< in\nf(){ read X 3<&-; }\nf\nread A <&3\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('stdin-fds', 'group-local-close-input-does-not-close-persistent', 'printf \'A\\nB\\n\' > in\nexec 3< in\n{ read X 3<&-; }\nread A <&3\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('stdin-fds', 'subshell-close-input-does-not-close-persistent', 'printf \'A\\nB\\n\' > in\nexec 3< in\n(read X 3<&-)\nread A <&3\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('stdin-fds', 'fd-reopen-resets-offset', 'printf \'A\\nB\\n\' > in\nexec 3< in\nread A <&3\nexec 3< in\nread B <&3\nprintf \'<%s:%s>\\n\' "$A" "$B"', False),
        MatrixCase('compound', 'subshell-fd3-local-output', '(printf A >&3) 3> out\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('compound', 'subshell-fd3-override-parent-restores', 'exec 3> outer\n(printf I >&3) 3> inner\nprintf O >&3\nexec 3>&-\nread A < inner\nread B < outer\nprintf \'<%s:%s>\\n\' "$A" "$B"', False),
        MatrixCase('compound', 'while-fd3-output-redirection', 'i=0\nwhile [ $i -lt 2 ]; do printf A >&3; i=$((i+1)); done 3> out\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('compound', 'for-fd3-output-redirection', 'for x in A B; do printf $x >&3; done 3> out\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('compound', 'case-fd3-output-redirection', 'case x in x) printf A >&3;; esac 3> out\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('compound', 'if-fd3-output-redirection', 'if true; then printf A >&3; fi 3> out\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('compound', 'function-input-fd3', 'printf \'A\\n\' > in\nf(){ read X <&3; printf \'<%s>\\n\' "$X"; }\nf 3< in', False),
        MatrixCase('compound', 'group-input-fd3', 'printf \'A\\n\' > in\n{ read X <&3; printf \'<%s>\\n\' "$X"; } 3< in', False),
        MatrixCase('compound', 'subshell-input-fd3', 'printf \'A\\n\' > in\n(read X <&3; printf \'<%s>\\n\' "$X") 3< in', False),
        MatrixCase('compound', 'function-redirection-status', 'f(){ printf A; return 7; }\nf > out\nprintf \'s=%s\\n\' $?\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('compound', 'group-redirection-status', '{ printf A; false; } > out\nprintf \'s=%s\\n\' $?\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('compound', 'subshell-redirection-status', '(printf A; false) > out\nprintf \'s=%s\\n\' $?\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('pipeline', 'pipeline-left-fd3-redirection', '{ printf A >&3; } 3> out | :\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('pipeline', 'pipeline-right-fd3-redirection', 'printf A | { read X; printf $X >&3; } 3> out\nread Y < out\nprintf \'<%s>\\n\' "$Y"', False),
        MatrixCase('pipeline', 'pipeline-function-right-fd3-redirection', 'f(){ read X; printf $X >&3; }\nprintf A | f 3> out\nread Y < out\nprintf \'<%s>\\n\' "$Y"', False),
        MatrixCase('pipeline', 'pipeline-left-persistent-fd3', 'exec 3> out\n{ printf A >&3; } | :\nprintf B >&3\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('pipeline', 'pipeline-read-no-parent-mutation', 'printf \'A\\n\' | { read X; }; printf \'<%s>\\n\' "${X-unset}"', False),
        MatrixCase('pipeline', 'pipeline-command-local-redir-status', 'printf A | { read X; printf $X; false; } > out\nprintf \'s=%s\\n\' $?\nread Y < out\nprintf \'<%s>\\n\' "$Y"', False),
        MatrixCase('pipeline-builtins', 'echo-pipe-read', 'echo hi | read X; printf "<%s>\\n" "$X"', False),
        MatrixCase('pipeline-builtins', 'printf-pipe-read', 'printf hi | read X; printf "<%s>\\n" "$X"', False),
        MatrixCase('pipeline-builtins', 'pwd-pipe-read', 'pwd | read X; case "$X" in "" ) printf empty;; *) printf nonempty;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'command-v-pipe-read', 'command -v true | read X; printf "<%s>\\n" "$X"', False),
        MatrixCase('pipeline-builtins', 'command-V-pipe-read', 'command -V true | read X; case "$X" in *true*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'type-pipe-read', 'type true | read X; case "$X" in *true*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'alias-pipe-read', 'alias a=hi; alias | read X; case "$X" in *a*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'export-p-pipe-read', 'export A=1; export -p | read X; case "$X" in *export*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'readonly-p-pipe-read', 'readonly A=1; readonly -p | read X; case "$X" in *readonly*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'set-pipe-read', 'A=1; set | read X; case "$X" in *=*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'umask-pipe-read', 'umask | read X; case "$X" in ???) printf yes;; *) printf no:$X;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'times-pipe-read', 'times | read X; case "$X" in *m*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'trap-pipe-read', 'trap -- "echo x" EXIT; trap | read X; case "$X" in *trap*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'jobs-pipe-read', ': & jobs | read X; wait; case "$X" in *[0-9]*) printf yes;; "") printf empty;; *) printf other;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'kill-l-pipe-read', 'kill -l | read X; case "$X" in *HUP*) printf yes;; *) printf no;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'ulimit-pipe-read', 'ulimit | read X; case "$X" in "") printf empty;; *) printf nonempty;; esac; printf "\\n"', False),
        MatrixCase('pipeline-builtins', 'hash-pipe-read', 'hash | read X; printf "<%s>\\n" "$X"', False),
        MatrixCase('pipeline-builtins', 'read-pipe-no-parent-mutation', 'printf "a\\n" | read X; printf "<%s>\\n" "${X-unset}"', False),
        MatrixCase('heredoc', 'read-heredoc', 'read X <<EOF\nA\nEOF\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('heredoc', 'read-heredoc-fd3', 'read X <&3 3<<EOF\nA\nEOF\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('heredoc', 'function-heredoc', 'f(){ read X; printf \'<%s>\\n\' "$X"; }\nf <<EOF\nA\nEOF', False),
        MatrixCase('heredoc', 'group-heredoc', '{ read X; printf \'<%s>\\n\' "$X"; } <<EOF\nA\nEOF', False),
        MatrixCase('heredoc', 'heredoc-tabs-strip', 'read X <<-EOF\n\tA\nEOF\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('heredoc', 'quoted-heredoc-no-expand', 'A=x\nread X <<\'EOF\'\n$A\nEOF\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('heredoc', 'persistent-stdin-heredoc', 'exec <<EOF\nA\nEOF\nread X\nprintf \'<%s:%s>\\n\' "$X" "$?"', False),
        MatrixCase('heredoc', 'persistent-fd3-heredoc', 'exec 3<<EOF\nA\nEOF\nread A <&3\nprintf \'<%s:%s>\\n\' "$A" "$?"', False),
        MatrixCase('heredoc', 'fd3-heredoc-duplicate-offset', 'exec 3<<EOF\nA\nB\nEOF\nexec 4<&3\nread A <&3\nread B <&4\nprintf \'<%s:%s>\\n\' "$A" "$B"', False),
        MatrixCase('heredoc', 'persistent-fd3-quoted-heredoc', 'X=bad\nexec 3<<\'EOF\'\n$X\nEOF\nread A <&3\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('heredoc', 'persistent-fd3-strip-tabs-heredoc', 'exec 3<<-EOF\n\tA\nEOF\nread A <&3\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('heredoc', 'persistent-fd9-heredoc', 'exec 9<<EOF\nA\nEOF\nread A <&9\nprintf \'<%s:%s>\\n\' "$A" "$?"', False),
        MatrixCase('heredoc', 'fd8-fd9-heredoc-duplicate-offset', 'exec 8<<EOF\nA\nB\nEOF\nexec 9<&8\nread A <&8\nread B <&9\nprintf \'<%s:%s>\\n\' "$A" "$B"', False),
        MatrixCase('heredoc', 'multiple-heredocs-last-stdin-wins', 'read X <<A <<B\nfirst\nA\nsecond\nB\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('heredoc', 'heredoc-fd-dup-after-open', 'read X 3<<EOF <&3\nA\nEOF\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('heredoc', 'read-local-heredoc-restores-stdin', 'printf \'outer\\n\' > in\nexec < in\nread X <<EOF\ninner\nEOF\nread Y\nprintf \'<%s:%s>\\n\' "$X" "$Y"', False),
        MatrixCase('heredoc', 'group-local-heredoc-restores-stdin', 'printf \'outer\\n\' > in\nexec < in\n{ read X; printf \'<%s>\' "$X"; } <<EOF\ninner\nEOF\nread Y\nprintf \'<%s>\\n\' "$Y"', False),
        MatrixCase('heredoc', 'function-local-heredoc-restores-stdin', 'printf \'outer\\n\' > in\nexec < in\nf(){ read X; printf \'<%s>\' "$X"; }\nf <<EOF\ninner\nEOF\nread Y\nprintf \'<%s>\\n\' "$Y"', False),
        MatrixCase('stderr-fds', 'fd4-duplicates-stderr', 'exec 4> err\nprintf E >&4\nexec 4>&-\nread X < err\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('stderr-fds', 'stderr-to-fd4-chain', 'exec 4> err\nexec 2>&4\nprintf E >&2\nexec 4>&-\nread X < err\nprintf \'<%s>\\n\' "$X"', True),
        MatrixCase('stderr-fds', 'command-local-stderr-does-not-persist', 'exec 4> err1\nprintf E >&2 2> err2\nprintf F >&4\nexec 4>&-\nread A < err1\nread B < err2\nprintf \'<%s:%s>\\n\' "$A" "$B"', True),
        MatrixCase('stderr-fds', 'command-local-close-stderr-does-not-persist', 'exec 4> err\nexec 2>&4\nprintf X 2>&-\nprintf E >&2\nexec 2>&-\nexec 4>&-\nread X < err\nprintf \'<%s>\\n\' "$X"', True),
        MatrixCase('stderr-fds', 'function-local-close-stderr-does-not-persist', 'exec 4> err\nexec 2>&4\nf(){ printf X 2>&-; }\nf\nprintf E >&2\nexec 2>&-\nexec 4>&-\nread X < err\nprintf \'<%s>\\n\' "$X"', True),
        MatrixCase('stderr-fds', 'group-local-close-stderr-does-not-persist', 'exec 4> err\nexec 2>&4\n{ printf X 2>&-; }\nprintf E >&2\nexec 2>&-\nexec 4>&-\nread X < err\nprintf \'<%s>\\n\' "$X"', True),
        MatrixCase('stderr-fds', 'subshell-close-stderr-does-not-persist', 'exec 4> err\nexec 2>&4\n(printf X 2>&-)\nprintf E >&2\nexec 2>&-\nexec 4>&-\nread X < err\nprintf \'<%s>\\n\' "$X"', True),
        MatrixCase('ordering', 'fd-dup-after-command-local-open', 'exec 3> outer\nprintf A 3> inner 4>&3 >&4\nexec 3>&-\nread I < inner\nread O < outer\nprintf \'<%s:%s>\\n\' "$I" "$O"', False),
        MatrixCase('ordering', 'fd-dup-before-command-local-open', 'exec 3> outer\nprintf A 4>&3 3> inner >&4\nexec 3>&-\nread I < inner\nread O < outer\nprintf \'<%s:%s>\\n\' "$I" "$O"', False),
        MatrixCase('ordering', 'input-dup-left-to-right', 'printf \'A\\n\' > a\nprintf \'B\\n\' > b\nexec 3< a\nread X 3< b <&3\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('ordering', 'input-dup-before-local-open', 'printf \'A\\n\' > a\nprintf \'B\\n\' > b\nexec 3< a\nread X <&3 3< b\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('ordering', 'stdout-close-local-restores', 'printf X >&-\nprintf A > out\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('ordering', 'stdin-close-local-restores', 'printf \'A\\n\' > in\nexec < in\nread X <&-\nread A\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('ordering', 'stderr-close-local-restores', 'exec 4> err\nexec 2>&4\nprintf X >&2 2>&-\nprintf E >&2\nexec 2>&-\nexec 4>&-\nread X < err\nprintf \'<%s>\\n\' "$X"', True),
        MatrixCase('redirection-only', 'output-create-with-assignment', 'A=ok > out\nprintf \'<%s>\' "$A"\nif [ -f out ]; then printf \':yes\\n\'; else printf \':no\\n\'; fi', False),
        MatrixCase('redirection-only', 'input-open-with-assignment', 'printf \'A\\n\' > in\nA=ok < in\nprintf \'<%s>\\n\' "$A"', False),
        MatrixCase('redirection-only', 'close-fd-without-command-does-not-close-persistent', 'exec 3> out\n3>&-\nprintf A >&3\nprintf \'s=%s\\n\' $?\nread X < out\nprintf \'<%s>\\n\' "$X"', True),
        MatrixCase('redirection-only', 'readonly-redirect-fd3-does-not-leak', 'exec 3> outer\nreadonly A 3> inner\nprintf O >&3\nexec 3>&-\nread I < inner\nread O < outer\nprintf \'<%s:%s>\\n\' "$I" "$O"', False),
        MatrixCase('readwrite', 'create-redirection-only', '<> new\nprintf "s=%s:" $?\nif [ -f new ]; then printf yes; else printf no; fi\nprintf "\\n"', False),
        MatrixCase('readwrite', 'no-truncate', 'printf old > f\n<> f\nread X < f\nprintf "<%s>\\n" "$X"', False),
        MatrixCase('readwrite', 'fd3-write-readback', 'printf old > f\nexec 3<> f\nprintf X >&3\nexec 3>&-\nread X < f\nprintf "<%s>\\n" "$X"', False),
        MatrixCase('readwrite', 'fd3-read-then-write-offset', 'printf "A\\nB\\n" > f\nexec 3<> f\nread A <&3\nprintf X >&3\nexec 3>&-\nread L1 < f\nread L2 < f\nprintf "<%s:%s:%s>\\n" "$A" "$L1" "$L2"', False),
        MatrixCase('readwrite', 'command-local-restores', 'printf old > outer\nprintf inner > inner\nexec 3<> outer\nprintf X >&3 3<> inner\nprintf Y >&3\nexec 3>&-\nread A < inner\nread B < outer\nprintf "<%s:%s>\\n" "$A" "$B"', False),
        MatrixCase('readwrite', 'compound-local', 'printf old > outer\nprintf inner > inner\nexec 3<> outer\n{ printf X >&3; } 3<> inner\nprintf Y >&3\nexec 3>&-\nread A < inner\nread B < outer\nprintf "<%s:%s>\\n" "$A" "$B"', False),
        MatrixCase('readwrite', 'input-output-same-fd', 'printf "A\\nB\\n" > f\nexec 3<> f\nread A <&3\nprintf C >&3\nread B < f\nprintf "<%s:%s>\\n" "$A" "$B"', False),
        MatrixCase('readwrite', 'two-writes-same-fd', 'printf old > f\nexec 3<> f\nprintf A >&3\nprintf B >&3\nexec 3>&-\nread X < f\nprintf "<%s>\\n" "$X"', False),
        MatrixCase('readwrite', 'read-after-write-same-fd', 'printf "AB\\n" > f\nexec 3<> f\nprintf X >&3\nread R <&3\nprintf "<%s>\\n" "$R"', False),
        MatrixCase('readwrite', 'dup-readwrite-fd-shares-offset', 'printf "A\\nB\\n" > f\nexec 3<> f\nexec 4<&3\nread A <&3\nprintf X >&4\nexec 3>&-\nexec 4>&-\nread L1 < f\nread L2 < f\nprintf "<%s:%s:%s>\\n" "$A" "$L1" "$L2"', False),
        MatrixCase('readwrite', 'subshell-readwrite-local-restores', 'printf outer > outer\nprintf inner > inner\nexec 3<> outer\n(printf X >&3) 3<> inner\nprintf Y >&3\nexec 3>&-\nread A < inner\nread B < outer\nprintf "<%s:%s>\\n" "$A" "$B"', False),
        MatrixCase('redirection-error', 'missing-input', "< missing\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'missing-parent-input', "< missing/child\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'missing-parent-output', "> missing/child\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'output-to-directory', "> .\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'append-to-directory', ">> .\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'force-clobber-directory', ">| .\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'readwrite-directory', "<> .\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'readwrite-missing-parent', "<> missing/child\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'bad-input-dup', "3<&9\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'bad-output-dup', "3>&9\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'nonnumeric-input-dup', "3<&x\nprintf 's=%s\\n' $?", True),
        MatrixCase('redirection-error', 'nonnumeric-output-dup', "3>&x\nprintf 's=%s\\n' $?", True),
        MatrixCase('background', 'background-function-redirection', 'f(){ printf A; }\nf > out &\nwait\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('background', 'background-group-redirection', '{ printf A; } > out &\nwait\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('background', 'background-status-wait-specific', 'sleepy(){ printf A > out; }\nsleepy &\np=$!\nwait $p\nprintf \'s=%s\\n\' $?\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('background', 'background-inherits-persistent-fd', 'exec 3> out\n{ printf A >&3; } &\nwait\nprintf B >&3\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
        MatrixCase('background', 'background-fd-close-does-not-leak-parent', 'exec 3> out\n(exec 3>&-) &\nwait\nprintf A >&3\nexec 3>&-\nread X < out\nprintf \'<%s>\\n\' "$X"', False),
    ]


def run_reference_sh(case: MatrixCase, cwd: Path, reference_shell: str) -> RunResult:
    if reference_shell == "wsl-sh":
        return run_wsl_sh(case, cwd)
    proc = run_local_reference_shell(reference_shell, cwd, case.script, RUN_TIMEOUT_SECONDS)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def rows_match(case: MatrixCase, msh_result: RunResult, ref: RunResult) -> bool:
    if msh_result.status != ref.status or msh_result.stdout != ref.stdout:
        return False
    if case.compare_stderr and normalize_stderr(msh_result.stderr) != normalize_stderr(ref.stderr):
        return False
    return True


def run_case(msh: Path, case: MatrixCase, root: Path, reference_shell: str) -> dict[str, object]:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", f"{case.group}-{case.name}")
    case_root = root / safe
    msh_dir = case_root / "msh"
    ref_dir = case_root / reference_shell
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_dir.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir)
    ref = run_reference_sh(case, ref_dir, reference_shell)
    match = rows_match(case, msh_result, ref)
    return {
        "group": case.group,
        "name": case.name,
        "script": case.script,
        "compare_stderr": case.compare_stderr,
        "matches": match,
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
            "normalized_stderr": normalize_stderr(msh_result.stderr),
        },
        "reference_shell": reference_shell,
        "wsl_sh": {
            "status": ref.status,
            "stdout": ref.stdout,
            "stderr": ref.stderr,
            "normalized_stderr": normalize_stderr(ref.stderr),
        },
    }


def write_json(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")


def write_markdown(path: Path, rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    groups: dict[str, tuple[int, int]] = {}
    for row in rows:
        key = str(row["group"])
        done, count = groups.get(key, (0, 0))
        groups[key] = (done + (1 if row["matches"] is True else 0), count + 1)
    lines = [
        "# msh FD/Process Matrix",
        "",
        "Generated by `msh_fd_process_matrix.py` against WSL `/bin/sh`.",
        "",
        "## Summary",
        "",
        f"- Overall: `{matches}/{total}`",
    ]
    for key in sorted(groups):
        done, count = groups[key]
        lines.append(f"- `{key}`: `{done}/{count}`")
    lines.extend(["", "## Mismatches", ""])
    mismatches = [row for row in rows if row["matches"] is not True]
    if not mismatches:
        lines.append("No mismatches.")
        lines.append("")
    for row in mismatches:
        msh = row["msh"]
        ref = row["wsl_sh"]
        lines.extend([
            f"### {row['group']}/{row['name']}",
            "",
            "```sh",
            str(row["script"]).rstrip(),
            "```",
            "",
            f"- msh: status `{msh['status']}`, stdout `{msh['stdout']!r}`, stderr `{msh['normalized_stderr']!r}`",
            f"- wsl-sh: status `{ref['status']}`, stdout `{ref['stdout']!r}`, stderr `{ref['normalized_stderr']!r}`",
            "",
        ])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def print_summary(rows: list[dict[str, object]]) -> None:
    total = len(rows)
    matches = sum(1 for row in rows if row["matches"] is True)
    print(f"msh fd/process matrix: {matches}/{total} match wsl-sh")
    for row in rows:
        if row["matches"] is True:
            continue
        msh = row["msh"]
        ref = row["wsl_sh"]
        print(f"- {row['group']}/{row['name']}")
        print(f"  script: {row['script']!r}")
        print(f"  msh: status={msh['status']} stdout={msh['stdout']!r} stderr={msh['normalized_stderr']!r}")
        print(f"  sh:  status={ref['status']} stdout={ref['stdout']!r} stderr={ref['normalized_stderr']!r}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the msh fd/process matrix.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--reference-shell", choices=local_reference_shell_names(), default="wsl-sh")
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}")
        return 2
    with tempfile.TemporaryDirectory(prefix="msh-fd-process-matrix-") as raw:
        root = Path(raw)
        rows = [run_case(msh, case, root, args.reference_shell) for case in matrix_cases()]
    write_json(args.json_report, rows)
    write_markdown(args.report, rows)
    print_summary(rows)
    if args.strict and any(row["matches"] is not True for row in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
