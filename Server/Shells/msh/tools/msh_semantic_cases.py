#!/usr/bin/env python3
"""Case catalog for msh_semantic_probe.py."""

from __future__ import annotations

import sys
import subprocess
import re
from dataclasses import dataclass
from pathlib import Path

from msh_tool_process import run_tool_cmd

RUN_TIMEOUT_SECONDS = 10

@dataclass(frozen=True)
class StatusCase:
    name: str
    script: str
    status: int | None = None


@dataclass(frozen=True)
class StateCase:
    name: str
    script: str
    status: int
    vars: dict[str, str]
    absent: tuple[str, ...] = ()


@dataclass(frozen=True)
class ParserCase:
    name: str
    script: str
    should_parse: bool


@dataclass(frozen=True)
class OutputCase:
    name: str
    script: str
    status: int
    stdout: str


@dataclass(frozen=True)
class DiagnosticCase:
    name: str
    script: str
    status: int
    stderr_contains: str
    stderr_exact: bool = False


@dataclass(frozen=True)
class GapCase:
    name: str
    script: str
    why: str


def default_msh_path() -> Path:
    here = Path(__file__).resolve()
    repo_root = here.parents[4]
    return repo_root / "out" / "server" / "msh_cli.exe"


def run_cmd(argv: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return run_tool_cmd(argv, cwd, timeout=RUN_TIMEOUT_SECONDS)


def parse_msh_status(stdout: str, returncode: int) -> int:
    for line in stdout.splitlines():
        if line.startswith("status="):
            try:
                return int(line[7:])
            except ValueError:
                break
    return returncode


def parse_state(stdout: str) -> tuple[int, dict[str, str]]:
    status = 999
    values: dict[str, str] = {}
    for line in stdout.splitlines():
        if line.startswith("status="):
            status = int(line[7:])
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return status, values


def shell_path(path: Path) -> str:
    """Return the shell-visible POSIX-style path used by msh on hosted builds."""
    return str(path).replace("\\", "/")


def run_msh_eval(msh: Path, script: str, cwd: Path | None = None) -> tuple[int, str, str]:
    proc = run_cmd([str(msh), "eval", script], cwd=cwd)
    return parse_msh_status(proc.stdout, proc.returncode), proc.stdout, proc.stderr


def run_msh_ast(msh: Path, script: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return run_cmd([str(msh), "ast", script], cwd=cwd)


def stdout_without_status(stdout: str) -> str:
    trimmed = re.sub(r"status=-?[0-9]+\n\Z", "", stdout)
    if trimmed != stdout:
        return trimmed
    lines: list[str] = []
    for line in stdout.splitlines():
        if not line.startswith("status="):
            lines.append(line)
    if not lines:
        return ""
    return "\n".join(lines) + "\n"


def run_msh_state(msh: Path, script: str, cwd: Path | None = None) -> tuple[int, dict[str, str], str, str]:
    proc = run_cmd([str(msh), "eval-state", script], cwd=cwd)
    status, values = parse_state(proc.stdout)
    return status, values, proc.stdout, proc.stderr


def wsl_available() -> bool:
    proc = run_cmd(["wsl.exe", "--exec", "sh", "-c", "exit 0"])
    return proc.returncode == 0


def run_wsl_status(script: str) -> tuple[int, str, str]:
    proc = run_cmd(["wsl.exe", "--exec", "sh", "-c", script])
    return proc.returncode, proc.stdout, proc.stderr


def status_cases() -> list[StatusCase]:
    return [
        StatusCase("empty script", "", 0),
        StatusCase("colon status", ":", 0),
        StatusCase("true status", "true", 0),
        StatusCase("false status", "false", 1),
        StatusCase("sequence keeps last status", "false; true", 0),
        StatusCase("sequence failing last status", "true; false", 1),
        StatusCase("or-list status", "false || true", 0),
        StatusCase("or-list skips right", "true || false", 0),
        StatusCase("and-list status", "true && false", 1),
        StatusCase("and-list skips right", "false && true", 1),
        StatusCase("pipeline bang", "! false", 0),
        StatusCase("pipeline bang true", "! true", 1),
        StatusCase("if then branch", "if true; then true; else false; fi", 0),
        StatusCase("if else branch", "if false; then false; else true; fi", 0),
        StatusCase("if elif branch", "if false; then false; elif true; then true; else false; fi", 0),
        StatusCase("if newline grammar", "if false\nthen false\nelif true\nthen true\nelse false\nfi", 0),
        StatusCase("while false", "while false; do true; done", 0),
        StatusCase("until true", "until true; do false; done", 0),
        StatusCase("until break", "until false; do break; done", 0),
        StatusCase("for loop status", "for x in a b; do true; done", 0),
        StatusCase("for empty in-list", "for x in; do false; done", 0),
        StatusCase("for implicit positional list", "for x do true; done", 0),
        StatusCase("case match status", "case x in y) false;; x) true;; esac", 0),
        StatusCase("case alternative match", "case z in x|y) false;; z) true;; *) false;; esac", 0),
        StatusCase("case optional leading paren", "case x in (x) true;; esac", 0),
        StatusCase("case no match", "case z in x) false;; esac", 0),
        StatusCase("subshell isolates failure status", "( false )", 1),
        StatusCase("subshell last status", "( false; true )", 0),
        StatusCase("brace group status", "{ true; false; }", 1),
        StatusCase("brace group last status", "{ false; true; }", 0),
        StatusCase("command double dash builtin true", "command -- true", 0),
        StatusCase("command double dash builtin false", "command -- false", 1),
        StatusCase("command double dash special colon", "command -- :", 0),
        StatusCase("command double dash cd", "command -- cd .", 0),
        StatusCase("command double dash umask", "command -- umask", 0),
        StatusCase("nested command builtin status", "command command true", 0),
        StatusCase("command printf builtin status", "command printf 'x\\n'", 0),
        StatusCase("command read pipeline status", "printf 'x\\n' | command read A", 0),
        StatusCase("command default path option builtin", "command -p true", 0),
        StatusCase("command default path option double dash", "command -p -- true", 0),
        StatusCase("command v without operand", "command -v", 0),
        StatusCase("command V without operand", "command -V", 0),
        StatusCase("command p without operand", "command -p", 0),
        StatusCase("type missing name", "type definitely_not_msh_known", 127),
        StatusCase("unalias all clears aliases", "alias aa=true; unalias -a; alias aa", 1),
        StatusCase("compound pipeline right status", "{ true; } | false", 1),
        StatusCase("compound pipeline ignores left status", "{ false; } | true", 0),
        StatusCase("function pipeline right status", "f() { true; }; f | false", 1),
        StatusCase("function pipeline ignores left status", "f() { false; }; f | true", 0),
        StatusCase("shell-node pipeline printf read", "{ printf 'x\\n'; } | read A", 0),
        StatusCase("alias applies during eval parse", "alias ok=true; eval ok", 0),
        StatusCase("auto PPID is not negative", "case $PPID in -*) false;; *) true;; esac", 0),
        StatusCase("special builtin function name is invalid", "set() { A=bad; }; set -- one; A=$1", 2),
    ]


def state_cases(tempdir: Path) -> list[StateCase]:
    cd_root = tempdir / "roots"
    cd_target = cd_root / "target"
    cd_target.mkdir(parents=True, exist_ok=True)
    cd_dash_dir = tempdir / "cd-dash-redir"
    cd_dash_dir.mkdir(exist_ok=True)
    cd_dash_dir = tempdir / "cd-dash-redir"
    cd_dash_dir.mkdir(exist_ok=True)
    source_file = tempdir / "source-return.sh"
    source_file.write_text("A=before\nreturn 5\nA=bad\n", encoding="utf-8")
    source_path = str(source_file).replace("\\", "/")
    source_false = tempdir / "source-false.sh"
    source_false.write_text("false\n", encoding="utf-8")
    source_false_path = str(source_false).replace("\\", "/")
    source_path_file = tempdir / "dot-source"
    source_path_file.write_text("A=from-path\nreturn 6\n", encoding="utf-8")
    path_script = tempdir / "path-script"
    path_script.write_text("A=inner\nexit 7\n", encoding="utf-8")
    if sys.platform != "win32":
        path_script.chmod(0o755)
    read_input = tempdir / "read-input.txt"
    read_input.write_bytes(b"from-file\n")
    read_input_empty = tempdir / "read-input-empty.txt"
    read_input_empty.write_bytes(b"")
    read_input_nonl = tempdir / "read-input-nonl.txt"
    read_input_nonl.write_bytes(b"partial")
    read_input_two = tempdir / "read-input-two.txt"
    read_input_two.write_bytes(b"one\ntwo\n")
    read_input_wide = tempdir / "read-input-wide.txt"
    read_input_wide.write_bytes(b"one two three four\n")
    read_input_one = tempdir / "read-input-one.txt"
    read_input_one.write_bytes(b"solo\n")
    read_input_csv = tempdir / "read-input-csv.txt"
    read_input_csv.write_bytes(b"a,b,c\n")
    read_input_escape = tempdir / "read-input-escape.txt"
    read_input_escape.write_bytes(b"a\\ b\n")
    read_input_continue = tempdir / "read-input-continue.txt"
    read_input_continue.write_bytes(b"left\\\nright\n")
    glob_file = tempdir / "glob-a"
    glob_file.write_text("glob\n", encoding="utf-8")
    if sys.platform == "win32":
        emitter = tempdir / "emitline.cmd"
        emitter.write_text("@echo x\n", encoding="utf-8")
        emitter_script = "emitline.cmd"
        filter_script = "findstr x"
        failer = tempdir / "failcmd.cmd"
        failer.write_text("@exit /B 7\n", encoding="utf-8")
        failer_script = "failcmd.cmd"
    else:
        emitter = tempdir / "emitline"
        emitter.write_text("#!/bin/sh\nprintf 'x\\n'\n", encoding="utf-8")
        emitter.chmod(0o755)
        emitter_script = "./emitline"
        filter_script = "grep x"
        failer = tempdir / "failcmd"
        failer.write_text("#!/bin/sh\nexit 7\n", encoding="utf-8")
        failer.chmod(0o755)
        failer_script = "./failcmd"
    cmd_dir = tempdir / "cmd-dir"
    cmd_dir.mkdir(exist_ok=True)
    exec_error_cases = [
        StateCase("missing explicit path status", "./missing-command-for-status; A=$?", 0, {"A": "127"}),
        StateCase("directory explicit path status", "./cmd-dir; A=$?", 0, {"A": "126"}),
        StateCase("directory PATH command status", "PATH=.; cmd-dir; A=$?", 0, {"A": "127"}),
        StateCase("directory pipeline tail status", "true | ./cmd-dir; A=$?", 0, {"A": "126"}),
    ]
    if sys.platform != "win32":
        noexec = tempdir / "noexec"
        noexec.write_bytes(b"\x00\x01not-a-script\n")
        noexec.chmod(0o644)
        exec_error_cases.append(
            StateCase("permission denied explicit path status", "./noexec; A=$?", 0, {"A": "126"})
        )
        exec_error_cases.append(
            StateCase("permission denied pipeline tail status", "true | ./noexec; A=$?", 0, {"A": "126"})
        )
    return [
        StateCase("assignment overwrites", "A=1; A=2", 0, {"A": "2"}),
        StateCase("errexit stops sequence", "set -e; false; A=bad", 1, {}, ("A",)),
        StateCase("errexit disabled continues", "set +e; false; A=ok", 0, {"A": "ok"}),
        StateCase("noexec skips assignment", "set -n; A=bad", 0, {}, ("A",)),
        StateCase("noexec skips failing command", "set -n; false; A=bad", 0, {}, ("A",)),
        StateCase("pathname expansion active by default", "set -- glob-*; A=$1", 0, {"A": "glob-a"}),
        StateCase("noglob suppresses pathname expansion", "set -f; set -- glob-*; A=$1", 0, {"A": "glob-*"}),
        StateCase("nounset simple parameter aborts", "set -u; A=$UNSET; B=bad", 2, {}, ("A", "B")),
        StateCase("nounset positional parameter aborts", "set -u; set --; A=$1; B=bad", 2, {}, ("A", "B")),
        StateCase("nounset default operator continues", "set -u; A=${UNSET-default}; B=ok", 0, {"A": "default", "B": "ok"}),
        StateCase("nounset pattern removal aborts", "set -u; A=${UNSET#x}; B=bad", 2, {}, ("A", "B")),
        StateCase("nounset at-star parameters continue", 'set -u; A="$@"; B=$*; C=ok', 0, {"A": "", "B": "", "C": "ok"}),
        StateCase("function overrides cd regular builtin", "cd() { A=function; }; cd; B=$A", 0, {"A": "function", "B": "function"}),
        StateCase("function overrides alias regular builtin", "alias() { A=function; }; alias; B=$A", 0, {"A": "function", "B": "function"}),
        StateCase("while break exits loop", "while true; do break; A=bad; done; A=ok", 0, {"A": "ok"}, ("bad",)),
        StateCase("for continue skips body tail", "for x in a b; do continue; A=bad; done; A=ok", 0, {"x": "b", "A": "ok"}),
        StateCase("break numeric exits nested loops", "for x in a b; do for y in 1 2; do A=$x$y; break 2; done; A=bad; done; B=$A", 0, {"x": "a", "y": "1", "A": "a1", "B": "a1"}, ("bad",)),
        StateCase("continue numeric resumes outer loop", "for x in a b; do A=$x; for y in 1 2; do continue 2; A=bad; done; A=bad2; done; B=$A", 0, {"x": "b", "y": "1", "A": "b", "B": "b"}, ("bad",)),
        StateCase("function return status", "f() { return 7; A=bad; }; f; A=$?", 0, {"A": "7"}),
        StateCase("dot source return status", f". {source_path}; B=$?", 0, {"A": "before", "B": "5"}),
        StateCase("command dot source return status", f"command . {source_path}; B=$?", 0, {"A": "before", "B": "5"}),
        StateCase("dot source false status", f". {source_false_path}; B=$?", 0, {"B": "1"}),
        StateCase("dot source PATH search", "PATH=.; . dot-source; B=$?", 0, {"A": "from-path", "B": "6"}),
        StateCase("dot no operand is no-op", ".; A=ok", 0, {"A": "ok"}),
        StateCase("dot missing file aborts noninteractive", ". ./missing-dot-source; A=bad", 2, {}, ("A",)),
        StateCase("command eval mutates state", "command eval 'A=ok'; B=$A", 0, {"A": "ok", "B": "ok"}),
        StateCase("parameter default mutation", '${A:=ok}; B=$A', 0, {"A": "ok", "B": "ok"}),
        StateCase("parameter error stops command", '${A:?missing}; B=bad', 2, {}, ("B",)),
        StateCase("quoted star uses first IFS", 'set -- a b; IFS=,; A="$*"', 0, {"A": "a,b"}),
        StateCase("default unset parameter", "B=${A-default}", 0, {"B": "default"}),
        StateCase("default null with colon", "A=; B=${A:-default}", 0, {"A": "", "B": "default"}),
        StateCase("default null without colon", "A=; B=${A-default}", 0, {"A": "", "B": ""}),
        StateCase("assign unset parameter", "B=${A=default}; C=$A", 0, {"A": "default", "B": "default", "C": "default"}),
        StateCase("alternate set parameter", "A=x; B=${A+yes}; C=${A:+yes}", 0, {"A": "x", "B": "yes", "C": "yes"}),
        StateCase("alternate null parameter", "A=; B=${A+yes}; C=${A:+yes}", 0, {"A": "", "B": "yes", "C": ""}),
        StateCase("parameter length", "A=abcd; B=${#A}", 0, {"A": "abcd", "B": "4"}),
        StateCase("parameter prefix suffix trim", "A=abcabc; B=${A#a*}; C=${A##a*}; D=${A%c}; E=${A%%c}", 0, {"B": "bcabc", "C": "", "D": "abcab", "E": "abcab"}),
        StateCase("arithmetic postfix increment rejected", "A=1; B=$((A++)); C=$A", 2, {"A": "1"}, ("B", "C")),
        StateCase("arithmetic repeated unary plus", "A=1; B=$((++A)); C=$A", 0, {"A": "1", "B": "1", "C": "1"}),
        StateCase("arithmetic postfix decrement rejected", "A=3; B=$((A--)); C=$A", 2, {"A": "3"}, ("B", "C")),
        StateCase("arithmetic repeated unary minus", "A=3; B=$((--A)); C=$A", 0, {"A": "3", "B": "3", "C": "3"}),
        StateCase("arithmetic comma expression rejected", "A=1; B=$((A=1,A+=2,A*3)); C=$A", 2, {"A": "1"}, ("B", "C")),
        StateCase("shift updates positionals", 'set -- a b c; shift; A=$1; B=$#; C="$@"', 0, {"A": "b", "B": "2", "C": "b c"}),
        StateCase("shift numeric updates positionals", 'set -- a b c; shift 2; A=$1; B=$#', 0, {"A": "c", "B": "1"}),
        StateCase("shift too many aborts noninteractive", 'set -- a; shift 2; S=$?; A=$#; B=$1', 2, {}, ("S", "A", "B")),
        StateCase("shift invalid operand aborts noninteractive", 'set -- a; shift x; S=$?; A=$#; B=$1', 2, {}, ("S", "A", "B")),
        StateCase("getopts parses first positional option", "set -- -a; getopts a opt; S=$?; O=$opt; I=$OPTIND", 0, {"S": "0", "O": "a", "I": "2"}),
        StateCase("getopts parses clustered options", "set -- -ab; getopts ab opt; A=$opt; I1=$OPTIND; getopts ab opt; B=$opt; I2=$OPTIND", 0, {"A": "a", "I1": "2", "B": "b", "I2": "2"}),
        StateCase("getopts parses inline argument", "set -- -ofile; getopts o: opt; O=$opt; A=$OPTARG; I=$OPTIND", 0, {"O": "o", "A": "file", "I": "2"}),
        StateCase("getopts parses next argument", "set -- -o file; getopts o: opt; O=$opt; A=$OPTARG; I=$OPTIND", 0, {"O": "o", "A": "file", "I": "3"}),
        StateCase("getopts end status", "set -- file; getopts a opt; S=$?; I=$OPTIND", 0, {"S": "1", "I": "1"}),
        StateCase("getopts explicit arg list", "getopts ab opt -b; S=$?; O=$opt; I=$OPTIND", 0, {"S": "0", "O": "b", "I": "2"}),
        StateCase("command getopts mutates state", "set -- -a; command getopts a opt; O=$opt; I=$OPTIND", 0, {"O": "a", "I": "2"}),
        StateCase("getopts invalid option state", "set -- -z; getopts a opt; S=$?; O=$opt; I=$OPTIND", 0, {"S": "0", "O": "?", "I": "2"}),
        StateCase("getopts silent missing argument", "set -- -o; getopts :o: opt; O=$opt; A=$OPTARG; I=$OPTIND", 0, {"O": ":", "A": "o", "I": "2"}),
        StateCase("kill self signal trap dispatch", "trap 'A=term' TERM; kill -TERM $$; B=$A", 0, {"A": "term", "B": "term"}),
        StateCase("command kill self signal trap dispatch", "trap 'A=int' INT; command kill -s INT $$; B=$A", 0, {"A": "int", "B": "int"}),
        StateCase("unset readonly aborts noninteractive", "readonly A=one; unset A; S=$?; B=$A", 2, {"A": "one"}, ("S", "B")),
        StateCase("set invalid option aborts noninteractive", "set -o definitely-not-posix; A=bad", 2, {}, ("A",)),
        StateCase("export invalid name aborts noninteractive", "export 1BAD; A=bad", 2, {}, ("A",)),
        StateCase("export readonly aborts noninteractive", "readonly A=one; export A=two; B=bad", 2, {"A": "one"}, ("B",)),
        StateCase("readonly invalid name aborts noninteractive", "readonly 1BAD; A=bad", 2, {}, ("A",)),
        StateCase("readonly reassignment aborts noninteractive", "readonly A=one; readonly A=two; B=bad", 2, {"A": "one"}, ("B",)),
        StateCase("special readonly assignment aborts", "readonly A=one; A=two export; B=bad", 2, {"A": "one"}, ("B",)),
        StateCase("special redirection failure aborts", ": < missing-redir-for-special; A=bad", 2, {}, ("A",)),
        StateCase("special redirection word no field split", "A='one two'; : > $A; B=ok", 0, {"A": "one two", "B": "ok"}),
        StateCase("regular builtin redirection word no field split", "A='one two'; true > $A; B=$?", 0, {"A": "one two", "B": "0"}),
        StateCase("redirection-only word no field split", "A='one two'; > $A; B=$?", 0, {"A": "one two", "B": "0"}),
        StateCase("subshell state isolation", "A=outer; ( A=inner ); B=$A", 0, {"A": "outer", "B": "outer"}),
        StateCase("group state persists", "A=outer; { A=inner; }; B=$A", 0, {"A": "inner", "B": "inner"}),
        StateCase("subshell redirection keeps isolation", "A=outer; ( A=inner; command -v true ) > subshell-state.txt; B=$A", 0, {"A": "outer", "B": "outer"}),
        StateCase("group redirection keeps state", "A=outer; { A=inner; command -v true; } > group-state.txt; B=$A", 0, {"A": "inner", "B": "inner"}),
        StateCase("if state branch", "if true; then A=ok; else A=bad; fi", 0, {"A": "ok"}),
        StateCase("case state branch", "case x in x) A=ok;; *) A=bad;; esac", 0, {"A": "ok"}),
        StateCase("for loop final state", "for x in a b; do A=$x; done", 0, {"x": "b", "A": "b"}),
        StateCase("compound pipeline state isolation", "A=outer; { A=inner; } | true; B=$A", 0, {"A": "outer", "B": "outer"}),
        StateCase("function pipeline state isolation", "A=outer; f() { A=inner; }; f | true; B=$A", 0, {"A": "outer", "B": "outer"}),
        StateCase("shell-node pipeline read state isolation", "A=outer; { printf 'x\\n'; } | read A; B=$A", 0, {"A": "outer", "B": "outer"}),
        StateCase("background records numeric async pid", "true & P=$!; case $P in ''|*[!0123456789]*) OK=bad;; *) OK=pid;; esac", 0, {"OK": "pid"}),
        StateCase("wait returns recorded background status", "false & P=$!; wait $P; S=$?; case $P in ''|*[!0123456789]*) OK=bad;; *) OK=pid;; esac", 0, {"OK": "pid", "S": "1"}),
        StateCase("wait unknown pid status", "wait 999999; S=$?", 0, {"S": "127"}),
        StateCase("command wait returns recorded status", "false & P=$!; command wait $P; S=$?; case $P in ''|*[!0123456789]*) OK=bad;; *) OK=pid;; esac", 0, {"OK": "pid", "S": "1"}),
        StateCase("command set updates positionals", "command set -- a b; A=$1; B=$#", 0, {"A": "a", "B": "2"}),
        StateCase("command shift updates positionals", "set -- a b; command shift; A=$1; B=$#", 0, {"A": "b", "B": "1"}),
        StateCase("command export mutates state", "command export A=one; B=$A", 0, {"A": "one", "B": "one"}),
        StateCase("command export restores temporary assignment", "A=old; A=one command export A; B=$A", 0, {"A": "old", "B": "old"}),
        StateCase("command export assignment operand restores temporary assignment", "A=old; A=one command export A=two; B=$A", 0, {"A": "old", "B": "old"}),
        StateCase("command readonly mutates state", "command readonly A=one; B=$A", 0, {"A": "one", "B": "one"}),
        StateCase("command readonly restores temporary assignment", "A=old; A=one command readonly A; B=$A", 0, {"A": "old", "B": "old"}),
        StateCase("command restores unrelated temporary assignment", "A=old; A=one command :; B=$A", 0, {"A": "old", "B": "old"}),
        StateCase("command unset mutates state", "A=one; command unset A; B=${A-missing}", 0, {"B": "missing"}, ("A",)),
        StateCase("command unset restores temporary assignment", "A=old; A=one command unset A; B=$A", 0, {"A": "old", "B": "old"}),
        StateCase("command alias mutates state", "command alias ca=true; command alias ca", 0, {}),
        StateCase("command trap mutates state", "command trap '' INT; command trap | read X", 0, {}, ("X",)),
        StateCase("external pipeline read dataflow isolation", f"{emitter_script} | read A", 0, {}, ("A",)),
        StateCase("group external pipeline read dataflow", f"{{ {emitter_script}; }} | read A", 0, {}, ("A",)),
        StateCase("function external pipeline read dataflow", f"f() {{ {emitter_script}; }}; f | read A", 0, {}, ("A",)),
        StateCase("multi-stage external pipeline read dataflow", f"{emitter_script} | {filter_script} | read A", 0, {}, ("A",)),
        StateCase("group multi-stage external pipeline read dataflow", f"{{ {emitter_script} | {filter_script}; }} | read A", 0, {}, ("A",)),
        StateCase("command lookup pipeline read dataflow", "command -v true | read A", 0, {}, ("A",)),
        StateCase("alias named pipeline read dataflow", "alias aa=bb; alias aa | read A", 0, {}, ("A",)),
        StateCase("set print pipeline read dataflow", "A=one; set | read X", 0, {"A": "one"}, ("X",)),
        StateCase("export print pipeline read dataflow", "export A=one; export -p | read X", 0, {"A": "one"}, ("X",)),
        StateCase("readonly print pipeline read dataflow", "readonly A=one; readonly -p | read X", 0, {"A": "one"}, ("X",)),
        StateCase("trap print pipeline read dataflow", "trap '' INT; trap | read X", 0, {}, ("X",)),
        StateCase("cdpath changes directory", "CDPATH=roots; cd target", 0, {"CDPATH": "roots", "PWD": shell_path(cd_target)}),
        StateCase("cdpath output is pipe isolated", "CDPATH=roots; cd target | read X", 0, {"CDPATH": "roots"}, ("X", "PWD")),
        StateCase("captured external status controls and-list", f"{{ {failer_script} && {emitter_script}; }} | read A", 1, {}, ("A",)),
        StateCase("exec command stops sequence", f"exec {failer_script}; A=bad", 7, {}, ("A",)),
        StateCase("command exec command stops sequence", f"command exec {failer_script}; A=bad", 7, {}, ("A",)),
        StateCase("PATH shell script execution", "A=outer; PATH=.; path-script; C=$?; B=$A", 0, {"A": "outer", "B": "outer", "C": "7"}),
        StateCase("alias eval assignment", "alias setA='A=ok'; eval setA", 0, {"A": "ok"}),
        StateCase("read redirected stdin", "read A < read-input.txt", 0, {"A": "from-file"}),
        StateCase("read empty redirected stdin fails and clears", "read A < read-input-empty.txt; S=$?", 0, {"A": "", "S": "1"}),
        StateCase("read unterminated line fails with data", "read A < read-input-nonl.txt; S=$?", 0, {"A": "partial", "S": "1"}),
        StateCase("read persistent exec stdin reaches eof", "exec < read-input-two.txt; read A; S1=$?; read B; S2=$?; read C; S3=$?", 0, {"A": "one", "S1": "0", "B": "two", "S2": "0", "C": "", "S3": "1"}),
        StateCase("read multiple redirected vars", "read A B C < read-input-wide.txt", 0, {"A": "one", "B": "two", "C": "three four"}),
        StateCase("read missing redirected vars empty", "read A B < read-input-one.txt", 0, {"A": "solo", "B": ""}),
        StateCase("read preserves final var delimiters", "IFS=,; read A B < read-input-csv.txt", 0, {"A": "a", "B": "b,c"}),
        StateCase("read default backslash escape", "read A < read-input-escape.txt", 0, {"A": "a b"}),
        StateCase("read raw mode preserves backslash", "read -r A < read-input-escape.txt", 0, {"A": "a\\ b"}),
        StateCase("read default backslash newline continuation", "read A < read-input-continue.txt", 0, {"A": "leftright"}),
        StateCase("read raw mode stops before continuation newline", "read -r A < read-input-continue.txt", 0, {"A": "left\\"}),
        StateCase("read invalid variable fails", "read 1BAD < read-input.txt", 2, {}, ("1BAD",)),
        StateCase("read invalid option fails", "read -z A < read-input.txt", 2, {}, ("A",)),
    ] + exec_error_cases


def parser_cases() -> list[ParserCase]:
    return [
        ParserCase("fd-prefixed leading redirection", "2>file true", True),
        ParserCase("fd-prefixed trailing redirection", "true 2>file", True),
        ParserCase("compound linebreak grammar", "if true\nthen\n{ true; }\nfi", True),
        ParserCase("while newline grammar", "while false\ndo\ntrue\ndone", True),
        ParserCase("for implicit positional grammar", "for x\ndo true\ndone", True),
        ParserCase("case optional leading paren grammar", "case x in (x) true;; esac", True),
        ParserCase("invalid if missing command", "if then", False),
        ParserCase("invalid if missing fi", "if true; then true", False),
        ParserCase("invalid for variable", "for 1 in a; do true; done", False),
        ParserCase("invalid case missing esac", "case x in x) true;;", False),
        ParserCase("invalid special-builtin function name", "export() { true; }", False),
    ]


def output_cases(tempdir: Path) -> list[OutputCase]:
    lookup_script = tempdir / "path-lookup"
    lookup_script.write_text("exit 0\n", encoding="utf-8")
    if sys.platform != "win32":
        lookup_script.chmod(0o755)
    lookup_dir = tempdir / "cmd-dir"
    lookup_dir.mkdir(exist_ok=True)
    lookup_first = tempdir / "path-first"
    lookup_second = tempdir / "path-second"
    lookup_first.mkdir(exist_ok=True)
    lookup_second.mkdir(exist_ok=True)
    (lookup_first / "path-pick").mkdir(exist_ok=True)
    path_pick_later = lookup_second / "path-pick"
    path_pick_later.write_text("printf 'later\\n'\n", encoding="utf-8")
    if sys.platform != "win32":
        path_pick_later.chmod(0o755)
    cd_root = tempdir / "roots"
    cd_target = cd_root / "target"
    cd_target.mkdir(parents=True, exist_ok=True)
    if sys.platform == "win32":
        env_emitter = tempdir / "emit-env-output.cmd"
        env_emitter.write_text("@echo %MSH_PIPE_ENV%\n", encoding="utf-8")
        env_pipe_script = "export MSH_PIPE_ENV=from-pipeline; emit-env-output.cmd | findstr from-pipeline"
    else:
        env_emitter = tempdir / "emit-env-output"
        env_emitter.write_text("#!/bin/sh\nprintf '%s\\n' \"$MSH_PIPE_ENV\"\n", encoding="utf-8")
        env_emitter.chmod(0o755)
        env_pipe_script = "export MSH_PIPE_ENV=from-pipeline; ./emit-env-output | grep from-pipeline"
    host_path_cases: list[OutputCase] = []
    if sys.platform == "win32":
        host_path_cases = [
            OutputCase("command lookup empty PATH ignores host cmd", "PATH=; command -v cmd", 127, ""),
            OutputCase("type empty PATH ignores host cmd", "PATH=; type cmd", 127, "cmd: not found\n"),
        ]
    cases = [
        OutputCase("pwd builtin current directory", "pwd", 0, shell_path(tempdir) + "\n"),
        OutputCase("pwd logical option current directory", "pwd -L", 0, shell_path(tempdir) + "\n"),
        OutputCase("pwd physical option current directory", "pwd -P", 0, shell_path(tempdir) + "\n"),
        OutputCase("command lookup pwd builtin", "command -v pwd", 0, "pwd\n"),
        OutputCase("type pwd builtin", "type pwd", 0, "pwd is a shell builtin\n"),
        OutputCase("pwd pipe capture", "pwd | read A", 0, ""),
        OutputCase("command lookup true", "command -v true", 0, "true\n"),
        OutputCase("command verbose true baseline", "command -V true", 0, "true is a shell builtin\n"),
        OutputCase("command verbose special builtin", "command -V export", 0, "export is a special shell builtin\n"),
        OutputCase("command verbose function", "vf() { :; }; command -V vf", 0, "vf is a shell function\n"),
        OutputCase("command lookup alias", "alias ll='ls -l'; command -v ll", 0, "alias ll='ls -l'\n"),
        OutputCase("command verbose alias", "alias ll='ls -l'; command -V ll", 0, "ll is an alias for ls -l\n"),
        OutputCase("command default path lookup true", "command -p -v true", 0, "true\n"),
        OutputCase("nested command lookup true", "command command -v true", 0, "true\n"),
        OutputCase("command type regular builtin", "command type true", 0, "true is a shell builtin\n"),
        OutputCase("command set output", "A=one; command set", 0, "A='one'\n"),
        OutputCase("command export output", "command export A=one; command export -p", 0, "export A='one'\n"),
        OutputCase("command readonly output", "command readonly A=one; command readonly -p", 0, "readonly A='one'\n"),
        OutputCase("command alias output", "command alias ca=bb; command alias ca", 0, "ca='bb'\n"),
        OutputCase("command trap output", "command trap cleanup INT; command trap", 0, "trap -- 'cleanup' INT\n"),
        OutputCase("command times output", "command times", 0, "0m0.000000s 0m0.000000s\n0m0.000000s 0m0.000000s\n"),
        OutputCase("times ignores extra operands", "times x >/dev/null; printf '%s\\n' after", 0, "after\n"),
        OutputCase("command umask symbolic output", "umask 022; command umask -S", 0, "u=rwx,g=rx,o=rx\n"),
        OutputCase("jobs no jobs output", "jobs", 0, ""),
        OutputCase("jobs reports completed background", "true & P=$!; wait $P; jobs", 0, "[1] + Done(0) true\n"),
        OutputCase("jobs verbose reports completed background", "false & P=$!; wait $P; jobs -l > jobs.out; read A < jobs.out; case $A in *'Done(1)'*) printf 'ok\n';; *) printf 'bad\n';; esac", 0, "ok\n"),
        OutputCase("kill list signal number", "kill -l 15", 0, "TERM\n"),
        OutputCase("command printf output", "command printf '[%s]\\n' ok", 0, "[ok]\n"),
        OutputCase("command substitution stdout redirection avoids capture", "x=$(printf hi >&2); printf '<%s>\\n' \"$x\"", 0, "<>\n"),
        OutputCase("command substitution resumes capture after stderr redirection", "x=$(printf hi >&2; printf ok); printf '<%s>\\n' \"$x\"", 0, "<ok>\n"),
        OutputCase("zero positional count", "printf '<%s>\\n' \"$#\"", 0, "<0>\n"),
        OutputCase("set positional count", "set -- a b; printf '<%s>\\n' \"$#\"", 0, "<2>\n"),
        OutputCase("bare dollar before non-parameter char is literal", "printf '<%s>\\n' \"$ \"", 0, "<$ >\n"),
        OutputCase("quoted empty positional field", "A=; set -- \"$A\" x; printf '<%s><%s>\\n' \"$#\" \"$1\"", 0, "<2><>\n"),
        OutputCase("pathname ASCII sort C locale", "printf x > sort-glob-a; printf x > sort-glob-B; printf x > sort-glob-c; set -- sort-glob-*; printf '%s\\n' $1:$2:$3", 0, "sort-glob-B:sort-glob-a:sort-glob-c\n"),
        OutputCase("pathname equivalence class profiled literal", "printf x > eq-a; set -- eq-[[=a=]]; printf '%s\\n' $1", 0, "eq-[[=a=]]\n"),
        OutputCase("pathname collating symbol profiled literal", "printf x > co-a; set -- co-[[.a.]]; printf '%s\\n' $1", 0, "co-[[.a.]]\n"),
        OutputCase("type regular builtin", "type true", 0, "true is a shell builtin\n"),
        OutputCase("type special builtin", "type export", 0, "export is a special shell builtin\n"),
        OutputCase("type function", "tf() { :; }; type tf", 0, "tf is a shell function\n"),
        OutputCase("type alias", "alias ta='echo ok'; type ta", 0, "ta is an alias for echo ok\n"),
        OutputCase("type missing output", "type definitely_missing", 127, "definitely_missing: not found\n"),
        OutputCase("type keeps checking after missing", "type -z true", 127, "-z: not found\ntrue is a shell builtin\n"),
        OutputCase("command lookup PATH script", "PATH=.; command -v path-lookup", 0, "./path-lookup\n"),
        OutputCase("command verbose PATH script", "PATH=.; command -V path-lookup", 0, "path-lookup is ./path-lookup\n"),
        OutputCase("command lookup skips PATH directory", "PATH=.; command -v cmd-dir; printf '%s\\n' $?", 0, "127\n"),
        OutputCase("command verbose skips PATH directory", "PATH=.; command -V cmd-dir; printf '%s\\n' $?", 0, "cmd-dir: not found\n127\n"),
        OutputCase("command default path ignores shell PATH script", "PATH=.; command -p -v path-lookup", 127, ""),
        OutputCase("type PATH script", "PATH=.; type path-lookup", 0, "path-lookup is ./path-lookup\n"),
        OutputCase("type skips PATH directory", "PATH=.; type cmd-dir >/dev/null; printf '%s\\n' $?", 0, "127\n"),
        OutputCase("PATH directory skip finds later script", "PATH=path-first:path-second; path-pick", 0, "later\n"),
        OutputCase("command lookup empty PATH current directory", "PATH=; command -v path-lookup", 0, "path-lookup\n"),
        OutputCase("type empty PATH current directory", "PATH=; type path-lookup", 0, "path-lookup is path-lookup\n"),
        OutputCase("alias eval command lookup", "alias ct='command -v true'; eval ct", 0, "true\n"),
        OutputCase("alias list all", "alias aa=bb; alias", 0, "aa='bb'\n"),
        OutputCase("alias query named", "alias aa=bb; alias aa", 0, "aa='bb'\n"),
        OutputCase("set prints variables", "B=two; A='one two'; set", 0, "A='one two'\nB='two'\n"),
        OutputCase("export print marked variables", "export B=two; export A='one two'; export EMPTY=; export UNSET; export -p", 0, "export A='one two'\nexport B='two'\nexport EMPTY=''\nexport UNSET\n"),
        OutputCase("readonly print marked variables", "readonly B=two; readonly A='one two'; readonly EMPTY=; readonly UNSET; readonly -p", 0, "readonly A='one two'\nreadonly B='two'\nreadonly EMPTY=''\nreadonly UNSET\n"),
        OutputCase("trap list stored actions", "trap cleanup INT; trap", 0, "trap -- 'cleanup' INT\n"),
        OutputCase("trap numeric signal canonicalization", "trap cleanup 2; trap", 0, "trap -- 'cleanup' INT\n"),
        OutputCase("trap zero signal canonicalization", "trap cleanup 0; trap", 0, "trap -- 'cleanup' EXIT\n"),
        OutputCase("cdpath prints selected directory", "CDPATH=roots; cd target", 0, shell_path(cd_target) + "\n"),
        OutputCase("cd dash honors command redirection", "cd cd-dash-redir; cd - > got; cd cd-dash-redir; read -r A < got; printf '<%s>\\n' \"$A\"", 0, "<" + shell_path(tempdir) + ">\n"),
        OutputCase("persistent stdout keeps open-time path across cd", "exec 3>&1; exec > got; cd cd-dash-redir; printf 'x\\n'; cd ..; exec 1>&3; read -r A < got; printf '<%s>\\n' \"$A\"", 0, "<x>\n"),
        OutputCase("saved host stdout fd bypasses pipeline capture", "exec 3>&1; (printf 'hi\\n' >&3) | true", 0, "hi\n"),
        OutputCase("function redirection expansion state before assignment", "show() { printf 'got %s\\n' \"${EFF-unset}\"; }; unset x; EFF=${x=assign} show 2>${x=redir}; printf '%s\\n' \"${EFF-unset after function call}\"; if [ -f redir ]; then printf 'redir exists\\n'; fi", 0, "got redir\nunset after function call\nredir exists\n"),
        OutputCase("umask symbolic set", "umask u=rwx,g=rx,o=; umask", 0, "0027\n"),
        OutputCase("umask symbolic add", "umask 077; umask g+w; umask", 0, "0057\n"),
        OutputCase("umask symbolic copy set", "umask 077; umask g=u; umask", 0, "0007\n"),
        OutputCase("umask symbolic copy add", "umask 077; umask o+u; umask", 0, "0070\n"),
        OutputCase("umask symbolic copy remove", "umask 000; umask o-u; umask", 0, "0007\n"),
        OutputCase("umask symbolic output after set", "umask 777; umask u=rw,g=r,o=; umask -S", 0, "u=rw,g=r,o=\n"),
        OutputCase("umask symbolic setuid no-op add", "umask 000; umask u+s; umask", 0, "0000\n"),
        OutputCase("umask symbolic setgid no-op add", "umask 000; umask g+s; umask", 0, "0000\n"),
        OutputCase("umask symbolic setuid clear class", "umask 000; umask u=s; umask", 0, "0700\n"),
        OutputCase("umask symbolic setgid clear class", "umask 000; umask g=s; umask", 0, "0070\n"),
        OutputCase("umask symbolic no-who set special clears all", "umask 000; umask =s; umask", 0, "0777\n"),
        OutputCase("printf string format reuse", "printf '%s\\n' a b", 0, "a\nb\n"),
        OutputCase("printf mixed conversions", "printf '%d %s %%\\n' 7 ok", 0, "7 ok %\n"),
        OutputCase("printf char conversion", "printf '%c\\n' abc", 0, "a\n"),
        OutputCase("printf numeric bases", "printf '%o %x %X\\n' 10 255 255", 0, "12 ff FF\n"),
        OutputCase("printf b conversion escapes", "printf '%b\\n' 'a\\nb'", 0, "a\nb\n"),
        OutputCase("printf octal escape", "printf '\\0101\\n'", 0, "A\n"),
        OutputCase("printf plain octal escape", "printf '\\101\\n'", 0, "A\n"),
        OutputCase("printf b plain octal escape", "printf '%b\\n' '\\101'", 0, "A\n"),
        OutputCase("printf missing string operand", "printf '%s\\n'", 0, "\n"),
        OutputCase("printf string field width", "printf '[%5s]\\n' x", 0, "[    x]\n"),
        OutputCase("printf string left alignment", "printf '[%-5s]\\n' x", 0, "[x    ]\n"),
        OutputCase("printf decimal zero padding", "printf '[%05d]\\n' 7", 0, "[00007]\n"),
        OutputCase("printf signed zero padding", "printf '[%05d]\\n' -7", 0, "[-0007]\n"),
        OutputCase("printf signed flags", "printf '[%+d][% d]\\n' 7 7", 0, "[+7][ 7]\n"),
        OutputCase("printf integer precision", "printf '[%.5d]\\n' 7", 0, "[00007]\n"),
        OutputCase("printf integer width precision", "printf '[%8.5d]\\n' 7", 0, "[   00007]\n"),
        OutputCase("printf alternate integer forms", "printf '[%#.0o][%#o][%#x][%#X]\\n' 0 8 255 255", 0, "[0][010][0xff][0XFF]\n"),
        OutputCase("printf integer length modifiers rejected", "printf '[%hd][%hhd][%ld][%lld][%jd][%zd][%td]\\n' 7 8 9 10 11 12 13", 2, "["),
        OutputCase("printf fixed float defaults", "printf '[%f][%.2f]\\n' 1.5 1.5", 0, "[1.500000][1.50]\n"),
        OutputCase("printf fixed float width padding", "printf '[%8.2f][%08.2f]\\n' 1.5 -1.5", 0, "[    1.50][-0001.50]\n"),
        OutputCase("printf fixed float sign alternate", "printf '[%+.0f][%#.0f]\\n' 1.5 1", 0, "[+2][1.]\n"),
        OutputCase("printf fixed float rounding", "printf '[%.2f][%.2f]\\n' 1.994 1.995", 0, "[1.99][2.00]\n"),
        OutputCase("printf float length modifiers rejected", "printf '[%Lf][%Le][%LG]\\n' 1.5 1.5 12.5", 2, "["),
        OutputCase("printf scientific float defaults", "printf '[%e][%.2E]\\n' 12.5 12.5", 0, "[1.250000e+01][1.25E+01]\n"),
        OutputCase("printf scientific float rounding carry", "printf '[%.2e]\\n' 9.995", 0, "[1.00e+01]\n"),
        OutputCase("printf general float fixed form", "printf '[%g][%.4g]\\n' 12.500 12.500", 0, "[12.5][12.5]\n"),
        OutputCase("printf general float scientific form", "printf '[%.3g][%.3G]\\n' 12345 0.0001234", 0, "[1.23e+04][0.000123]\n"),
        OutputCase("printf string precision", "printf '[%.3s]\\n' abcdef", 0, "[abc]\n"),
        OutputCase("printf b precision after escapes", "printf '[%.3b]\\n' 'a\\nbc'", 0, "[a\nb]\n"),
        OutputCase("printf dynamic string width", "printf '[%*s]\\n' 5 x", 0, "[    x]\n"),
        OutputCase("printf negative dynamic width", "printf '[%*s]\\n' -5 x", 0, "[x    ]\n"),
        OutputCase("printf dynamic string precision", "printf '[%.*s]\\n' 3 abcdef", 0, "[abc]\n"),
        OutputCase("printf dynamic width precision", "printf '[%*.*s]\\n' 6 3 abcdef", 0, "[   abc]\n"),
        OutputCase("printf c escape stops current format", "printf 'a\\cb\\n'; printf '\\n'", 0, "a\n"),
        OutputCase("printf b escape stops current format", "printf 'a%bb\\n' 'x\\cy'; printf '\\n'", 0, "ax\n"),
        OutputCase("noexec skips command output", "set -n; command -v true", 0, ""),
        OutputCase("native pipeline receives exported env", env_pipe_script, 0, "from-pipeline\n"),
    ]
    return cases + host_path_cases


def diagnostic_cases(tempdir: Path) -> list[DiagnosticCase]:
    diag_dir = tempdir / "diag-dir"
    diag_dir.mkdir(exist_ok=True)
    cases = [
        DiagnosticCase("return outside function/source is silent", "return", 0, "", True),
        DiagnosticCase("break invalid level", "while true; do break x; done", 2, "break: Illegal number: x"),
        DiagnosticCase("shift invalid operand", "shift x", 2, "shift: Illegal number: x"),
        DiagnosticCase("unset readonly variable", "readonly A=one; unset A", 2, "unset: A: is read only"),
        DiagnosticCase("umask invalid mask", "umask bad", 2, "umask: Illegal mode: bad"),
        DiagnosticCase("export invalid name", "export 1BAD", 2, "export: 1BAD: bad variable name"),
        DiagnosticCase("export invalid option", "export -z", 2, "export: Illegal option -z"),
        DiagnosticCase("readonly invalid name", "readonly 1BAD", 2, "readonly: 1BAD: bad variable name"),
        DiagnosticCase("readonly assignment to readonly", "readonly A=one; readonly A=two", 2, "readonly: A: is read only"),
        DiagnosticCase("umask invalid symbolic permission", "umask u+z", 2, "umask: Illegal mode: u+z"),
        DiagnosticCase("umask invalid sticky permission", "umask u+t", 2, "umask: Illegal mode: u+t"),
        DiagnosticCase("set invalid option name", "set -o definitely-not-posix", 2, "set: Illegal option -o definitely-not-posix"),
        DiagnosticCase("trap lone invalid signal", "trap cleanup", 1, "trap: cleanup: bad trap"),
        DiagnosticCase("trap rejects SIG prefix", "trap cleanup SIGINT", 1, "trap: SIGINT: bad trap"),
        DiagnosticCase("unalias missing operand", "unalias", 0, ""),
        DiagnosticCase("read missing variable diagnostic", "read", 2, "read: arg count"),
        DiagnosticCase("read invalid option diagnostic", "read -z A", 2, "read: Illegal option -z"),
        DiagnosticCase("read invalid variable diagnostic", "read 1BAD", 2, "read: 1BAD: bad variable name"),
        DiagnosticCase("pwd invalid option", "pwd -z", 2, "pwd: Illegal option -z"),
        DiagnosticCase("wait invalid pid", "wait nope", 2, "wait: Illegal number: nope"),
        DiagnosticCase("getopts missing operand", "getopts", 2, "getopts: Usage: getopts optstring var [arg...]"),
        DiagnosticCase("getopts bad variable name", "getopts a 1BAD", 2, "getopts: 1BAD: bad variable name"),
        DiagnosticCase("getopts invalid option diagnostic", "set -- -z; getopts a opt", 0, "Illegal option -z"),
        DiagnosticCase("getopts missing argument diagnostic", "set -- -o; getopts o: opt", 0, "No arg for -o option"),
        DiagnosticCase("jobs invalid option", "jobs -z", 2, "jobs: Illegal option -z"),
        DiagnosticCase("bg no current job", "bg", 127, "bg: No such job: %"),
        DiagnosticCase("fg no current job", "fg", 127, "fg: No such job: %"),
        DiagnosticCase("kill job ref without monitor", "kill %1", 1, "kill: no such process"),
        DiagnosticCase("kill missing operand", "kill", 2, "kill: Usage: kill [-s sigspec | -signum | -sigspec] [pid | job]... or\nkill -l [exitstatus]"),
        DiagnosticCase("kill missing pid after signal option", "kill -s TERM", 2, "kill: Usage: kill [-s sigspec | -signum | -sigspec] [pid | job]... or\nkill -l [exitstatus]"),
        DiagnosticCase("kill list invalid exit status", "kill -l nope", 2, "kill: Illegal number: nope"),
        DiagnosticCase("kill bad signal", "kill -s NOPE $$", 2, "kill: invalid signal number or name: NOPE"),
        DiagnosticCase("kill invalid pid", "kill -TERM nope", 2, "kill: Illegal number: nope"),
        DiagnosticCase("kill no such process", "kill -TERM 999999", 1, "kill: no such process"),
        DiagnosticCase("command invalid option", "command -z true", 2, "command: Illegal option -z"),
        DiagnosticCase("command export invalid option", "command export -z", 2, "export: Illegal option -z"),
        DiagnosticCase("command readonly persists readonly without temporary assignment", "command readonly A=one; A=two", 2, "A: is read only"),
        DiagnosticCase("command read invalid option", "command read -z A", 2, "read: Illegal option -z"),
        DiagnosticCase("command substitution stdout redirect emits stderr", "x=$(printf hi >&2); printf '<%s>\\n' \"$x\"", 0, "hi"),
        DiagnosticCase("printf invalid directive", "printf '%q\\n' x", 2, "printf: %q: invalid directive"),
        DiagnosticCase("printf invalid numeric operand", "printf '%d\\n' x", 1, "printf: x: expected numeric value"),
        DiagnosticCase("dot missing source file", ". ./missing-dot-source", 2, ".: cannot open ./missing-dot-source: No such file"),
        DiagnosticCase("nounset simple diagnostic", "set -u; echo $UNSET", 2, "UNSET: parameter not set"),
        DiagnosticCase("nounset positional diagnostic", "set -u; echo $1", 2, "1: parameter not set"),
        DiagnosticCase("missing command diagnostic", "definitely_missing", 127, "definitely_missing: not found"),
        DiagnosticCase("missing explicit path diagnostic", "./definitely_missing", 127, "./definitely_missing: not found"),
        DiagnosticCase("missing pipeline left diagnostic", "definitely_missing | true", 0, "definitely_missing: not found"),
        DiagnosticCase("missing pipeline tail diagnostic", "true | definitely_missing", 127, "definitely_missing: not found"),
        DiagnosticCase("directory explicit path diagnostic", "./diag-dir", 126, "./diag-dir: Permission denied"),
        DiagnosticCase("directory PATH diagnostic", "PATH=.; diag-dir", 127, "diag-dir: Permission denied"),
        DiagnosticCase("directory pipeline left diagnostic", "./diag-dir | true", 0, "./diag-dir: Permission denied"),
        DiagnosticCase("directory pipeline tail diagnostic", "true | ./diag-dir", 126, "./diag-dir: Permission denied"),
        DiagnosticCase("missing input redirection diagnostic", "cat < definitely_missing_file", 2, "cannot open definitely_missing_file"),
        DiagnosticCase("builtin output redirection diagnostic", "printf ok > __missing_dir__/out", 2, "cannot create __missing_dir__/out"),
        DiagnosticCase("special builtin redirection diagnostic", "export A=1 < definitely_missing_file; printf after", 2, "cannot open definitely_missing_file"),
    ]
    if sys.platform != "win32":
        noexec = tempdir / "diag-noexec"
        noexec.write_bytes(b"\x00\x01not-a-script\n")
        noexec.chmod(0o644)
        cases.append(DiagnosticCase("permission denied explicit path diagnostic", "./diag-noexec", 126, "./diag-noexec: Permission denied"))
        cases.append(DiagnosticCase("permission denied pipeline tail diagnostic", "true | ./diag-noexec", 126, "./diag-noexec: Permission denied"))
        unreadable_source = tempdir / "diag-unreadable-source"
        unreadable_source.write_text("printf should-not-run\n", encoding="utf-8")
        unreadable_source.chmod(0o000)
        cases.append(DiagnosticCase("dot unreadable source diagnostic", f". {shell_path(unreadable_source)}", 2, ".: cannot open "))
    return cases


def known_gap_cases() -> list[GapCase]:
    return []
