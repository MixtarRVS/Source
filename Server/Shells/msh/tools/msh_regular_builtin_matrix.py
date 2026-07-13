#!/usr/bin/env python3
"""Compare regular-builtin diagnostics against WSL /bin/sh.

This matrix covers hosted-safe regular builtins whose diagnostics are easy to
regress while still returning to the caller in non-interactive scripts.
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
DEFAULT_JSON = REPORT_DIR / "msh-regular-builtin-matrix.json"
DEFAULT_MD = REPORT_DIR / "msh-regular-builtin-matrix.md"
RUN_TIMEOUT_SECONDS = 10
WSL_DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
_WSL_AVAILABLE: bool | None = None


@dataclass(frozen=True)
class MatrixCase:
    group: str
    name: str
    script: str
    compare_stderr: bool = True
    compare_status: bool = True


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str


def windows_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def run_cmd(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return run_tool_cmd(argv, cwd, timeout=RUN_TIMEOUT_SECONDS)


def wsl_available() -> bool:
    global _WSL_AVAILABLE
    if _WSL_AVAILABLE is not None:
        return _WSL_AVAILABLE
    proc = run_cmd(["wsl.exe", "--exec", "sh", "-c", "echo ok"])
    _WSL_AVAILABLE = proc.returncode == 0 and proc.stdout == "ok\n"
    return _WSL_AVAILABLE


def normalize_stderr(stderr: str) -> str:
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


def parse_msh(stdout: str, stderr: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], stderr)
    return RunResult(returncode, stdout, stderr)


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


def run_reference_sh(case: MatrixCase, cwd: Path, reference_shell: str) -> RunResult:
    if reference_shell == "wsl-sh":
        return run_wsl_sh(case, cwd)
    proc = run_local_reference_shell(reference_shell, cwd, case.script, RUN_TIMEOUT_SECONDS)
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def matrix_cases() -> list[MatrixCase]:
    return [
        MatrixCase("alias", "set and query alias", "alias ll='printf ok'; alias ll"),
        MatrixCase("alias", "multiple set and query", "alias a='printf A' b='printf B'; alias a; alias b"),
        MatrixCase("alias", "no args after set", "alias b='printf B'; alias a='printf A'; alias"),
        MatrixCase("alias", "alias reserved word name", "alias if='printf IF'; alias if"),
        MatrixCase("alias", "query missing alias", "alias nosuch\nprintf after"),
        MatrixCase("alias", "empty name query", "alias =bad\nprintf after"),
        MatrixCase("alias", "option-looking query", "alias -z\nprintf after"),
        MatrixCase("alias", "double dash is alias name", "alias --\nprintf '<%s>\\n' $?"),
        MatrixCase("unalias", "no operand", "unalias\nprintf after"),
        MatrixCase("unalias", "bad option", "unalias -z\nprintf after"),
        MatrixCase("unalias", "missing alias", "unalias nosuch\nprintf after"),
        MatrixCase("unalias", "double dash option delimiter missing alias", "unalias -- nosuch\nprintf after"),
        MatrixCase("unalias", "all then query", "alias a=x; unalias -a; alias a\nprintf after"),
        MatrixCase("unalias", "remove one keeps other", "alias a='printf A'; alias b='printf B'; unalias a; alias a; alias b\nprintf after"),
        MatrixCase("cd", "cd dot success", "cd .\nprintf '<%s>\\n' $?"),
        MatrixCase("cd", "bad option", "cd -z\nprintf after"),
        MatrixCase("cd", "missing directory", "cd definitely_missing\nprintf after"),
        MatrixCase("cd", "too many operands", "cd . .\nprintf after"),
        MatrixCase("pwd", "dash L status only", "pwd -L > out\nprintf '<%s>\\n' $?"),
        MatrixCase("pwd", "dash P status only", "pwd -P > out\nprintf '<%s>\\n' $?"),
        MatrixCase("pwd", "bad option", "pwd -z\nprintf after"),
        MatrixCase("jobs", "no jobs no output", "jobs\nprintf '<%s>\\n' $?"),
        MatrixCase("jobs", "bad option", "jobs -z\nprintf after"),
        MatrixCase("jobs", "unknown job operand", "jobs a b\nprintf after"),
        MatrixCase("wait", "no jobs", "wait\nprintf '<%s>\\n' $?"),
        MatrixCase("wait", "background false status", "false &\nwait $!\nprintf '<%s>\\n' $?"),
        MatrixCase("wait", "nonnumeric pid", "wait nope\nprintf after"),
        MatrixCase("getopts", "missing operands", "getopts\nprintf after", False),
        MatrixCase("getopts", "bad variable", "getopts a 1BAD\nprintf after"),
        MatrixCase("getopts", "valid compact options", "set -- -ab\ngetopts ab opt; printf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"${OPTARG-unset}\"\ngetopts ab opt; printf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"${OPTARG-unset}\"\ngetopts ab opt; printf '<%s:%s>' \"$?\" \"$OPTIND\"\nprintf '\\n'"),
        MatrixCase("getopts", "valid required separated arg", "set -- -o value\ngetopts o: opt; printf '<%s:%s:%s:%s>\\n' \"$opt\" \"$OPTARG\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "valid required joined arg", "set -- -ovalue\ngetopts o: opt; printf '<%s:%s:%s:%s>\\n' \"$opt\" \"$OPTARG\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "silent invalid option", "set -- -z\ngetopts :a opt; printf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "silent missing argument", "set -- -o\ngetopts :o: opt; printf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "invalid option", "set -- -z; getopts a opt; printf after"),
        MatrixCase("getopts", "missing argument", "set -- -o; getopts o: opt; printf after"),
        MatrixCase("getopts", "explicit args do not use positional", "set -- -a\ngetopts b opt -b\nprintf '<%s:%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$1\" \"$?\""),
        MatrixCase("getopts", "optind reset repeats scan", "set -- -a\ngetopts a opt\nprintf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"$?\"\nOPTIND=1\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "end of options double dash", "set -- -- -a\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$?\" \"$OPTIND\" \"${opt-unset}\""),
        MatrixCase("getopts", "grouped required arg in same token", "set -- -abVALUE\ngetopts ab: opt; printf '<%s:%s:%s:%s>' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\"\ngetopts ab: opt; printf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "plus operand ends scan", "set -- +a -a\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$?\" \"$OPTIND\" \"${opt-unset}\""),
        MatrixCase("getopts", "non-option operand ends scan", "set -- word -a\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$?\" \"$OPTIND\" \"${opt-unset}\""),
        MatrixCase("getopts", "optind starts at second operand", "set -- -a -b\nOPTIND=2\ngetopts ab opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "explicit missing required separated arg", "getopts o: opt -o\nprintf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optarg empty after no-arg option", "set -- -a\nOPTARG=old\ngetopts ab: opt\nprintf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optarg preserved after end", "set -- -a\ngetopts a opt\nOPTARG=old\ngetopts a opt\nprintf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optind zero scans first operand", "set -- -a\nOPTIND=0\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optind negative fatal", "set -- -a\nOPTIND=-1\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optind nonnumeric fatal", "set -- -a\nOPTIND=x\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optind empty fatal", "set -- -a\nOPTIND=\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optind plus two ends at count plus one", "set -- -a\nOPTIND=+2\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$?\" \"$OPTIND\" \"${opt-unset}\""),
        MatrixCase("getopts", "optind too large resets scan", "set -- -a\nOPTIND=5\ngetopts a opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "optind reset in middle of cluster", "set -- -ab\ngetopts ab opt\nprintf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"$?\"\nOPTIND=1\ngetopts ab opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "required arg rest of cluster", "set -- -abc\ngetopts ab: opt; printf '<%s:%s:%s:%s>' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\"\ngetopts ab: opt; printf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "required next operand may look like option", "set -- -b -x\ngetopts ab: opt\nprintf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "explicit args repeat state", "set -- -a\ngetopts ab opt -b\nprintf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"$?\"\ngetopts ab opt -b\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "explicit args optind reset", "getopts ab opt -a -b\nprintf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"$?\"\nOPTIND=1\ngetopts ab opt -a -b\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "invalid in cluster continues", "set -- -azb\ngetopts ab opt; printf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"$?\"\ngetopts ab opt; printf '<%s:%s:%s>' \"$opt\" \"$OPTIND\" \"$?\"\ngetopts ab opt; printf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "silent invalid in cluster continues", "set -- -azb\ngetopts :ab opt; printf '<%s:%s:%s:%s>' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\"\ngetopts :ab opt; printf '<%s:%s:%s:%s>' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\"\ngetopts :ab opt; printf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "empty optstring treats option as invalid", "set -- -a\ngetopts '' opt\nprintf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "colon-only optstring silent invalid", "set -- -a\ngetopts ':' opt\nprintf '<%s:%s:%s:%s>\\n' \"$opt\" \"${OPTARG-unset}\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "dash option character", "set -- --a\ngetopts -a opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("getopts", "question option character", "set -- '-?'\ngetopts '?' opt\nprintf '<%s:%s:%s>\\n' \"$opt\" \"$OPTIND\" \"$?\""),
        MatrixCase("printf", "repeat format", "printf '<%s>' a b c\nprintf '\\n'"),
        MatrixCase("printf", "percent b escape", "printf '%b' 'A\\nB'; printf '<%s>\\n' $?"),
        MatrixCase("printf", "percent c", "printf '<%c>\\n' ABC"),
        MatrixCase("printf", "width precision string", "printf '<%5.2s>\\n' abc"),
        MatrixCase("printf", "zero padded decimal", "printf '<%04d>\\n' 7"),
        MatrixCase("printf", "alternate hex and octal", "printf '<%#x:%#o>\\n' 15 8"),
        MatrixCase("printf", "dynamic width precision string", "printf '<%*.*s>\\n' 5 2 abc"),
        MatrixCase("printf", "quoted numeric character", "printf '<%d:%d>\\n' \"'A\" \"'B\""),
        MatrixCase("printf", "bad numeric operand", "printf '%d\\n' x\nprintf after"),
        MatrixCase("printf", "bad numeric status", "printf '%d\\n' x; printf '<%s>' $?"),
        MatrixCase("read", "split two vars", "printf 'a b c\\n' > in\nread A B < in\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$?\""),
        MatrixCase("read", "ifs comma split", "printf 'a,,b,\\n' > in\nIFS=, read A B C < in\nprintf '<%s:%s:%s:%s>\\n' \"$A\" \"$B\" \"$C\" \"$?\""),
        MatrixCase("read", "raw backslash", "printf 'a\\\\b\\n' > in\nread -r A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "cooked backslash", "printf 'a\\\\b\\n' > in\nread A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "no newline status", "printf 'abc' > in\nread A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "single variable gets rest", "printf ' a b c \\n' > in\nread A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "final var receives rest after split", "printf 'a,b,c,d\\n' > in\nIFS=, read A B < in\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$?\""),
        MatrixCase("read", "whitespace collapse with final variable", "printf '  a   b   c  \\n' > in\nread A B < in\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$?\""),
        MatrixCase("read", "only whitespace line clears value", "printf '   \\n' > in\nA=x\nread A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "nonwhite ifs preserves empty fields", "printf 'a::b:\\n' > in\nIFS=: read A B C D < in\nprintf '<%s:%s:%s:%s:%s>\\n' \"$A\" \"$B\" \"$C\" \"$D\" \"$?\""),
        MatrixCase("read", "backslash newline continuation", "printf 'a\\\\\\nb\\n' > in\nread A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "raw backslash newline no continuation", "printf 'a\\\\\\nb\\n' > in\nread -r A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "eof empty file clears variables", "printf '' > in\nA=old B=old\nread A B < in\nprintf '<%s:%s:%s>\\n' \"${A-unset}\" \"${B-unset}\" \"$?\""),
        MatrixCase("read", "eof dev null clears variables", "A=old B=old\nread A B < /dev/null\nprintf '<%s:%s:%s>\\n' \"${A-unset}\" \"${B-unset}\" \"$?\""),
        MatrixCase("read", "bad option", "read -z A\nprintf after"),
        MatrixCase("read", "bad variable", "read 1BAD\nprintf after"),
        MatrixCase("read", "no operand", "read\nprintf after"),
        MatrixCase("read", "double dash no variable", "printf 'x\\n' > in\nread -- < in\nprintf '<%s>\\n' $?"),
        MatrixCase("read", "double dash option delimiter", "printf 'x\\n' > in\nread -- A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "raw mode with option delimiter", "printf 'a\\\\b\\n' > in\nread -r -- A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "repeated raw mode option", "printf 'a\\\\b\\n' > in\nread -r -r A < in\nprintf '<%s:%s>\\n' \"$A\" \"$?\""),
        MatrixCase("read", "readonly variable assignment failure", "readonly A\nprintf 'new\\n' > in\nread A < in\nprintf '<%s:%s>\\n' \"${A-unset}\" \"$?\""),
        MatrixCase("read", "readonly later variable preserves earlier assignment", "readonly B\nprintf 'a b\\n' > in\nread A B < in\nprintf '<%s:%s:%s>\\n' \"${A-unset}\" \"${B-unset}\" \"$?\""),
        MatrixCase("read", "empty ifs leaves whole first variable", "printf ' a b \\n' > in\nIFS= read A B < in\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$?\""),
        MatrixCase("read", "default ifs tab delimiter", "printf 'a\\tb\\n' > in\nread A B < in\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$?\""),
        MatrixCase("read", "leading nonwhite ifs empty field", "printf ':a:b\\n' > in\nIFS=: read A B C < in\nprintf '<%s:%s:%s:%s>\\n' \"$A\" \"$B\" \"$C\" \"$?\""),
        MatrixCase("read", "trailing whitespace trimmed from final variable", "printf 'a b   \\n' > in\nread A B < in\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$?\""),
        MatrixCase("read", "backslash escaped ifs delimiter", "printf 'a\\\\ b\\n' > in\nread A B < in\nprintf '<%s:%s:%s>\\n' \"$A\" \"$B\" \"$?\""),
        MatrixCase("umask", "set octal and print", "umask 022\numask"),
        MatrixCase("umask", "symbolic print", "umask 022\numask -S"),
        MatrixCase("umask", "symbolic add user write", "umask 777\numask u+w\numask"),
        MatrixCase("umask", "symbolic copy user to group", "umask 027\numask g=u\numask"),
        MatrixCase("umask", "symbolic remove other execute", "umask 000\numask o-x\numask"),
        MatrixCase("umask", "symbolic setuid no-op add", "umask 000\numask u+s\numask"),
        MatrixCase("umask", "symbolic setgid no-op add", "umask 000\numask g+s\numask"),
        MatrixCase("umask", "symbolic setuid assignment clears class", "umask 000\numask u=s\numask"),
        MatrixCase("umask", "symbolic setgid assignment clears class", "umask 000\numask g=s\numask"),
        MatrixCase("umask", "symbolic no-who special assignment", "umask 000\numask =s\numask"),
        MatrixCase("umask", "double dash option delimiter", "umask -- 022\numask"),
        MatrixCase("umask", "extra operands ignored after first mask", "umask 022 033\numask"),
        MatrixCase("umask", "symbolic print with delimiter", "umask -S --"),
        MatrixCase("umask", "symbolic option with mask", "umask -S 022\numask"),
        MatrixCase("umask", "bad octal mask", "umask bad\nprintf after"),
        MatrixCase("umask", "bad symbolic mask", "umask u+z\nprintf after"),
        MatrixCase("umask", "bad sticky symbolic mask", "umask u+t\nprintf after"),
        MatrixCase("ulimit", "default file limit", "ulimit"),
        MatrixCase("ulimit", "dash f file limit", "ulimit -f"),
        MatrixCase("ulimit", "soft hard file limit options", "ulimit -H -S -f"),
        MatrixCase("ulimit", "set and query file limit", "ulimit -f 12\nulimit -f\nprintf '<%s>\\n' $?"),
        MatrixCase("ulimit", "set unlimited and query", "ulimit 12\nulimit unlimited\nulimit\nprintf '<%s>\\n' $?"),
        MatrixCase("ulimit", "combined soft hard file option", "ulimit -HSf"),
        MatrixCase("ulimit", "double dash before number", "ulimit -- 12\nulimit"),
        MatrixCase("ulimit", "bad option", "ulimit -z\nprintf after"),
        MatrixCase("ulimit", "bad number", "ulimit abc\nprintf after"),
        MatrixCase("ulimit", "too many operands", "ulimit 1 2\nprintf after"),
        MatrixCase("ulimit", "redirection output", "ulimit -f > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("hash", "reset option", "hash -r\nprintf '<%s>\\n' $?"),
        MatrixCase("hash", "missing command", "hash definitely_missing\nprintf after"),
        MatrixCase("hash", "multiple operands one missing", "hash true definitely_missing\nprintf after"),
        MatrixCase("hash", "bad option", "hash -z\nprintf after"),
        MatrixCase("hash", "no operands", "hash\nprintf after"),
        MatrixCase("hash", "known command", "hash true\nprintf '<%s>\\n' $?"),
        MatrixCase("hash", "two known commands", "hash true false\nprintf '<%s>\\n' $?"),
        MatrixCase("type", "multiple builtins", "type true false"),
        MatrixCase("type", "missing command", "type definitely_missing\nprintf after"),
        MatrixCase("type", "mixed missing status", "type true definitely_missing false\nprintf '<%s>\\n' $?"),
        MatrixCase("type", "bad option", "type -z true\nprintf after"),
        MatrixCase("command", "double dash true", "command -- true\nprintf '<%s>\\n' $?"),
        MatrixCase("command", "p double dash true", "command -p -- true\nprintf '<%s>\\n' $?"),
        MatrixCase("command", "bad option", "command -z true\nprintf after"),
        MatrixCase("command", "no operands", "command\nprintf after"),
        MatrixCase("command", "dash command name", "command -\nprintf after"),
        MatrixCase("command", "v multiple lookup with missing", "command -v true definitely_missing\nprintf '<%s>\\n' $?"),
        MatrixCase("command", "verbose multiple lookup with missing", "command -V true definitely_missing\nprintf after"),
        MatrixCase("echo", "no operands emits newline", "echo"),
        MatrixCase("echo", "joins operands", "echo alpha beta"),
        MatrixCase("echo", "dash n suppresses newline", "echo -n alpha; printf '<%s>\\n' \"$?\""),
        MatrixCase("echo", "dash n alone", "echo -n; printf '<%s>\\n' \"$?\""),
        MatrixCase("echo", "dash e is literal", "echo -e"),
        MatrixCase("echo", "double dash is literal", "echo -- hi"),
        MatrixCase("echo", "decodes newline escape", "echo 'a\\nb'"),
        MatrixCase("echo", "decodes tab escape", "echo 'a\\tb'"),
        MatrixCase("echo", "backslash c stops output", "echo 'a\\cb'; printf X"),
        MatrixCase("echo", "decodes octal escape", "echo 'A\\0101B'"),
        MatrixCase("echo", "redirection output", "echo alpha > out\nread X < out\nprintf '<%s>\\n' \"$X\""),
        MatrixCase("test", "empty expression", "test\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "single nonempty string", "test x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "single empty string", "test ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "negated nonempty string", "test ! x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "string length true", "test -n x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "string length false", "test -n ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "string empty true", "test -z ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "string empty false", "test -z x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "string equality", "test x = x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "string inequality", "test x != x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer equality", "test 1 -eq 1\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer inequality", "test 1 -ne 2\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer greater than", "test 2 -gt 1\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer greater or equal", "test 2 -ge 2\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer less than", "test -1 -lt 0\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer less or equal", "test +2 -le 2\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer trims whitespace", "test ' 2 ' -eq 2\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer max signed boundary", "test 9223372036854775807 -eq 9223372036854775807\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer min signed boundary", "test -9223372036854775808 -eq -9223372036854775808\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer bad left operand", "test x -eq 1\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer bad right operand", "test 1 -eq x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer positive overflow", "test 9223372036854775808 -eq 9223372036854775808\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer negative overflow", "test -9223372036854775809 -eq -9223372036854775809\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "integer overflow with leading zeroes", "test 0009223372036854775808 -eq 0\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "negated binary expression", "test ! x = x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "negated string length precedence", "test ! -n ''\nprintf '<%s>' $?\ntest ! -z ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "triple negation empty string", "test ! ! ! ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "triple negation nonempty string", "test ! ! ! x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "and expression", "test x -a ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "or expression", "test '' -o x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "grouped expression", "test \\( x = x \\) -a y\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "not grouped expression", "test ! \\( x = x \\)\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "empty grouped expression", "test \\( \\)\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "empty grouped expression with and", "test \\( \\) -a x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "empty grouped expression with or", "test \\( \\) -o x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "empty grouped expression extra operand", "test \\( \\) x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "and or precedence", "test x -o '' -a ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "grouped and or precedence", "test \\( x -o '' \\) -a ''\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "malformed grouping status", "test \\( x \\) y\nprintf '<%s>\\n' $?", False),
        MatrixCase("test", "missing right string operand", "test x =\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "unknown two arg unary-like operator", "test -q x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "unknown two arg expression", "test x y\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "unknown three arg binary operator", "test x -q y\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "two equals tokens require operand", "test = =\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "regular file and current directory", ": > f\ntest -f f; printf '<f:%s>' $?\ntest -d .; printf '<d:%s>\\n' $?"),
        MatrixCase("test", "exists and missing file", ": > f\ntest -e f; printf '<exists:%s>' $?\ntest -e missing; printf '<missing:%s>\\n' $?"),
        MatrixCase("test", "regular file access predicates", ": > f\ntest -r f; printf '<r:%s>' $?\ntest -w f; printf '<w:%s>\\n' $?"),
        MatrixCase("test", "regular file nonmatching type predicates", ": > f\ntest -b f; printf '<b:%s>' $?\ntest -c f; printf '<c:%s>' $?\ntest -p f; printf '<p:%s>' $?\ntest -S f; printf '<S:%s>\\n' $?"),
        MatrixCase("test", "regular file setid and symlink predicates", ": > f\ntest -u f; printf '<u:%s>' $?\ntest -g f; printf '<g:%s>' $?\ntest -L f; printf '<L:%s>' $?\ntest -h f; printf '<h:%s>\\n' $?"),
        MatrixCase("test", "empty and nonempty file size", ": > empty\nprintf data > nonempty\ntest -s empty; printf '<empty:%s>' $?\ntest -s nonempty; printf '<nonempty:%s>\\n' $?"),
        MatrixCase("test", "same file", ": > f\ntest f -ef f\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "newer right missing", ": > f\ntest f -nt missing\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "newer left missing", ": > f\ntest missing -nt f\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "older right missing", ": > f\ntest f -ot missing\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "older left missing", ": > f\ntest missing -ot f\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "terminal fd false in matrix", "test -t 1\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "terminal fd illegal number", "test -t x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "bracket success", "[ x = x ]\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "bracket missing close", "[ x = x\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "bracket unexpected operator", "[ a b c d ]\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "bracket triple negation", "[ ! ! ! x ]\nprintf '<%s>\\n' $?"),
        MatrixCase("test", "bracket missing right operand", "[ x = ]\nprintf '<%s>\\n' $?"),
        MatrixCase("true", "extra operands", "true a b\nprintf after"),
        MatrixCase("false", "extra operands", "false a b\nprintf after"),
        MatrixCase("kill", "list all signals", "kill -l"),
        MatrixCase("kill", "signal zero self check with -s", "kill -s 0 $$\nprintf '<%s>\\n' $?"),
        MatrixCase("kill", "zero self check", "kill -0 $$\nprintf '<%s>\\n' $?"),
        MatrixCase("kill", "bad signal after -s", "kill -s NOPE $$\nprintf after"),
        MatrixCase("kill", "bad multi-letter dash signal", "kill -NOPE $$\nprintf after"),
        MatrixCase("kill", "term with illegal pid", "kill -TERM nope\nprintf after"),
        MatrixCase("kill", "list signal number", "kill -l 15\nprintf '<%s>\\n' $?"),
        MatrixCase("kill", "list exit status signal", "kill -l 143\nprintf '<%s>\\n' $?"),
        MatrixCase("kill", "list zero invalid", "kill -l 0\nprintf after"),
        MatrixCase("kill", "list invalid exit status", "kill -l nope\nprintf after"),
        MatrixCase("kill", "missing pid after -s signal", "kill -s TERM\nprintf after"),
    ]


def compare(case: MatrixCase, msh_result: RunResult, sh_result: RunResult) -> dict[str, object]:
    msh_stderr = normalize_stderr(msh_result.stderr)
    sh_stderr = normalize_stderr(sh_result.stderr)
    status_match = (not case.compare_status) or msh_result.status == sh_result.status
    stdout_match = msh_result.stdout == sh_result.stdout
    stderr_match = (not case.compare_stderr) or msh_stderr == sh_stderr
    return {
        "group": case.group,
        "name": case.name,
        "script": case.script,
        "matches": status_match and stdout_match and stderr_match,
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_stderr,
        },
        "wsl_sh": {
            "status": sh_result.status,
            "stdout": sh_result.stdout,
            "stderr": sh_stderr,
        },
    }


def write_report(rows: list[dict[str, object]], path: Path) -> None:
    matches = sum(1 for row in rows if row.get("matches") is True)
    lines = [
        "# msh Regular Builtin Matrix",
        "",
        "Baseline: WSL `/bin/sh` with stderr prefixes normalized.",
        "",
        f"Result: `{matches}/{len(rows)}`",
        "",
        "| Group | Case | Result |",
        "|---|---|---:|",
    ]
    for row in rows:
        state = "PASS" if row.get("matches") is True else "FAIL"
        lines.append(f"| `{row['group']}` | {row['name']} | `{state}` |")
    failures = [row for row in rows if row.get("matches") is not True]
    if failures:
        lines.extend(["", "## Failures", ""])
        for row in failures:
            lines.extend(
                [
                    f"### {row['group']} / {row['name']}",
                    "",
                    "```sh",
                    str(row["script"]),
                    "```",
                    "",
                    "```json",
                    json.dumps({"msh": row["msh"], "wsl_sh": row["wsl_sh"]}, indent=2),
                    "```",
                    "",
                ]
            )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare regular builtin diagnostics against WSL /bin/sh.")
    parser.add_argument("--msh", type=Path, default=DEFAULT_MSH)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--json-report", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--report", type=Path, default=DEFAULT_MD)
    parser.add_argument("--reference-shell", choices=local_reference_shell_names(), default="wsl-sh")
    args = parser.parse_args()

    rows: list[dict[str, object]] = []
    with tempfile.TemporaryDirectory(prefix="msh-regular-builtins-") as tmp:
        cwd = Path(tmp)
        cases = matrix_cases()
        if args.reference_shell != "wsl-sh":
            cases = [
                case
                for case in cases
                if not (case.group == "kill" and case.name == "list all signals")
            ]
        for case in cases:
            msh_result = run_msh(args.msh, case, cwd)
            sh_result = run_reference_sh(case, cwd, args.reference_shell)
            rows.append(compare(case, msh_result, sh_result))

    args.json_report.parent.mkdir(parents=True, exist_ok=True)
    args.json_report.write_text(json.dumps(rows, indent=2), encoding="utf-8", newline="\n")
    write_report(rows, args.report)
    matches = sum(1 for row in rows if row.get("matches") is True)
    print(f"msh regular builtin matrix: {matches}/{len(rows)}")
    if args.strict and matches != len(rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
