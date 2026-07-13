#!/usr/bin/env python3
"""Differential shell runner for msh against WSL shells.

This is a discovery harness, not a POSIX certification suite. The primary
baseline is WSL /bin/sh. Bash and zsh profiles are observational so practical
shell behavior can be compared without silently changing the msh target.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TypedDict

from msh_tool_process import run_tool_cmd


@dataclass(frozen=True)
class DiffCase:
    category: str
    name: str
    script: str
    status_mode: str = "exact"
    profile: str = "posix"


@dataclass(frozen=True)
class ShellSpec:
    name: str
    argv: tuple[str, ...]
    baseline: bool = False
    runner: str = "wsl"


@dataclass(frozen=True)
class RunResult:
    status: int
    stdout: str
    stderr: str
    available: bool = True


class MshResultJson(TypedDict):
    status: int
    stdout: str
    stderr: str


class ShellResultJson(TypedDict):
    available: bool
    matches_msh: bool
    status: int
    stdout: str
    stderr: str


class DiffResultJson(TypedDict):
    category: str
    name: str
    profile: str
    status_mode: str
    script: str
    msh: MshResultJson
    shells: dict[str, ShellResultJson]


_WSL_DIAG_PREFIX_RE = re.compile(r"^.*case\.sh: \d+: ")
RUN_TIMEOUT_SECONDS = 10
REFERENCE_TIMEOUT_RETRIES = 2
_SHELL_AVAILABILITY: dict[tuple[str, ...], bool] = {}


def default_msh_path() -> Path:
    here = Path(__file__).resolve()
    repo_root = here.parents[4]
    return repo_root / "out" / "server" / "msh_cli.exe"


def windows_to_wsl_path(path: Path) -> str:
    resolved = path.resolve()
    drive = resolved.drive.rstrip(":").lower()
    rest = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    return f"/mnt/{drive}{rest}"


def run_cmd(
    argv: list[str], cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    return run_tool_cmd(argv, cwd, timeout=RUN_TIMEOUT_SECONDS)


def parse_msh(stdout: str, returncode: int) -> RunResult:
    marker = re.search(r"status=(-?\d+)\r?\n?$", stdout)
    if marker is not None:
        return RunResult(int(marker.group(1)), stdout[: marker.start()], "")
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
    return RunResult(status, text, "")


def local_shell_specs() -> list[ShellSpec]:
    candidates = [
        ShellSpec(
            "git-dash", (r"C:\Program Files\Git\usr\bin\dash.exe",), runner="local"
        ),
        ShellSpec("git-sh", (r"C:\Program Files\Git\bin\sh.exe",), runner="local"),
        ShellSpec(
            "git-bash-posix",
            (r"C:\Program Files\Git\usr\bin\bash.exe", "--posix"),
            runner="local",
        ),
        ShellSpec("msys-dash", (r"C:\msys64\usr\bin\dash.exe",), runner="local"),
        ShellSpec("msys-sh", (r"C:\msys64\usr\bin\sh.exe",), runner="local"),
        ShellSpec(
            "msys-bash-posix",
            (r"C:\msys64\usr\bin\bash.exe", "--posix"),
            runner="local",
        ),
    ]
    return [spec for spec in candidates if Path(spec.argv[0]).exists()]


def shell_specs(
    baseline_only: bool = False,
    include_local: bool = False,
    include_wsl: bool = True,
    strict_shell_only: str = "",
) -> list[ShellSpec]:
    specs = [
        ShellSpec("wsl-sh", ("sh",), True),
        ShellSpec("wsl-bash-posix", ("bash", "--posix")),
        ShellSpec("wsl-bash", ("bash",)),
        ShellSpec("wsl-zsh-sh", ("zsh", "--emulate", "sh")),
    ]
    if not include_wsl:
        specs = []
    if include_local:
        specs.extend(local_shell_specs())
    if strict_shell_only:
        return [spec for spec in specs if spec.name == strict_shell_only]
    if baseline_only:
        baseline = [spec for spec in specs if spec.baseline]
        if include_local:
            baseline.extend(local_shell_specs())
        if not include_wsl:
            baseline = [spec for spec in baseline if spec.runner != "wsl"]
        return baseline
    return specs


def shell_available(spec: ShellSpec) -> bool:
    cached = _SHELL_AVAILABILITY.get(spec.argv)
    if cached is not None:
        return cached
    if spec.runner == "local":
        proc = run_cmd([*spec.argv, "-c", "exit 0"])
    else:
        proc = run_cmd(["wsl.exe", "--exec", spec.argv[0], "-c", "exit 0"])
    available = proc.returncode == 0
    _SHELL_AVAILABILITY[spec.argv] = available
    return available


def write_script(path: Path, script: str) -> None:
    path.write_text(script, encoding="utf-8", newline="\n")


def run_msh(msh: Path, case: DiffCase, cwd: Path) -> RunResult:
    proc = run_cmd([str(msh), "eval", case.script], cwd=cwd)
    parsed = parse_msh(proc.stdout, proc.returncode)
    return RunResult(parsed.status, parsed.stdout, proc.stderr)


def run_wsl_shell(spec: ShellSpec, case: DiffCase, cwd: Path) -> RunResult:
    if not shell_available(spec):
        return RunResult(127, "", f"{spec.argv[0]} not available", False)
    script_path = cwd / "case.sh"
    if spec.runner == "local":
        body = "cd " + sh_quote(str(cwd)) + " || exit 125\n" + case.script
        write_script(script_path, body)
        proc = run_cmd([*spec.argv, str(script_path)])
        return RunResult(proc.returncode, proc.stdout, proc.stderr)
    body = "cd " + windows_to_wsl_path(cwd) + " || exit 125\n" + case.script
    write_script(script_path, body)
    wsl_script = windows_to_wsl_path(script_path)
    proc = run_cmd(["wsl.exe", "--exec", *spec.argv, wsl_script])
    return RunResult(proc.returncode, proc.stdout, proc.stderr)


def is_timeout_result(result: RunResult) -> bool:
    return result.status == 124 and "timeout after" in result.stderr


def run_reference_shell(spec: ShellSpec, case: DiffCase, cwd: Path) -> RunResult:
    result = run_wsl_shell(spec, case, cwd)
    attempt = 0
    while is_timeout_result(result) and attempt < REFERENCE_TIMEOUT_RETRIES:
        result = run_wsl_shell(spec, case, cwd)
        attempt += 1
    return result


def sh_quote(text: str) -> str:
    return "'" + text.replace("'", "'\\''") + "'"


def status_matches(left: int, right: int, mode: str) -> bool:
    if mode == "nonzero":
        return left != 0 and right != 0
    return left == right


def results_match(
    left: RunResult, right: RunResult, case: DiffCase, compare_stderr: bool
) -> bool:
    if not status_matches(left.status, right.status, case.status_mode):
        return False
    if left.stdout != right.stdout:
        return False
    if compare_stderr and normalize_stderr(left.stderr) != normalize_stderr(
        right.stderr
    ):
        return False
    return True


def normalize_stderr(stderr: str) -> str:
    if not stderr:
        return ""
    lines: list[str] = []
    for line in stderr.splitlines():
        line = _WSL_DIAG_PREFIX_RE.sub("", line)
        if line.startswith("msh: "):
            line = line[5:]
        lines.append(line)
    text = "\n".join(lines)
    if stderr.endswith("\n"):
        text += "\n"
    return text


def normalize(result: RunResult, compare_stderr: bool) -> tuple[int, str, str]:
    stderr = normalize_stderr(result.stderr) if compare_stderr else ""
    return result.status, result.stdout, stderr


def diff_cases() -> list[DiffCase]:
    return [
        DiffCase("status", "empty", ""),
        DiffCase("status", "false status", "false"),
        DiffCase("status", "sequence status", "false; true"),
        DiffCase("status", "and-or status", "false || true; true && false"),
        DiffCase(
            "grammar",
            "if elif",
            "if false; then printf bad; elif true; then printf ok; fi",
        ),
        DiffCase("grammar", "for loop", "for x in a b; do printf $x; done"),
        DiffCase(
            "grammar",
            "for implicit positionals semicolon",
            "set -- a b; for x; do printf [$x]; done",
        ),
        DiffCase(
            "grammar",
            "for implicit positionals no semicolon",
            "set -- a b; for x do printf [$x]; done",
        ),
        DiffCase(
            "grammar",
            "case alternatives",
            "case z in x|y) printf bad;; z) printf ok;; esac",
        ),
        DiffCase("grammar", "function call", "f() { printf ok; }; f"),
        DiffCase("grammar", "subshell isolation", "A=outer; (A=inner); printf $A"),
        DiffCase("expansion", "parameter default", "printf ${UNSET-default}"),
        DiffCase("expansion", "parameter assign", "printf ${A:=set}; printf :$A"),
        DiffCase("expansion", "parameter length", "A=abcd; printf ${#A}"),
        DiffCase("expansion", "pattern trim", "A=abcabc; printf ${A#a*}:${A%%c}"),
        DiffCase("expansion", "arithmetic", "printf $((2 + 3 * 4))"),
        DiffCase(
            "expansion",
            "arithmetic comparison",
            "printf $((2 < 3)):$((2 >= 3)):$((2==2)):$((2!=2))",
        ),
        DiffCase(
            "expansion",
            "arithmetic logical",
            "printf $((1 && 2)):$((0 || 4)):$((!0)):$((!5))",
        ),
        DiffCase(
            "expansion", "arithmetic ternary", "printf $((0 ? 2 : 3)):$((1 ? 2 : 3))"
        ),
        DiffCase(
            "expansion",
            "arithmetic precedence",
            "printf $((1 + 2 > 2 && 5 == 5 ? 8 : 9))",
        ),
        DiffCase(
            "expansion", "arithmetic assignment", "A=1; printf $((A=7)); printf :$A"
        ),
        DiffCase(
            "expansion",
            "arithmetic plus assignment",
            "A=1; printf $((A+=2)); printf :$A",
        ),
        DiffCase(
            "expansion",
            "arithmetic compound assignment",
            "A=8; printf $((A-=3)):$((A*=2)):$((A/=5)):$((A%=2)); printf :$A",
        ),
        DiffCase(
            "expansion",
            "arithmetic increment extension",
            "A=1; printf $((A++)); printf :$A; printf :$((++A)); printf :$A",
            "exact",
            "extension",
        ),
        DiffCase(
            "expansion",
            "arithmetic decrement extension",
            "A=3; printf $((A--)); printf :$A; printf :$((--A)); printf :$A",
            "exact",
            "extension",
        ),
        DiffCase(
            "expansion",
            "arithmetic comma extension",
            "A=1; printf $((A=1,A+=2,A*3)); printf :$A",
            "exact",
            "extension",
        ),
        DiffCase("expansion", "command substitution", "A=$(printf ok); printf $A"),
        DiffCase(
            "expansion",
            "command substitution inherits state",
            "A=ok; B=$(printf $A); printf $B",
        ),
        DiffCase(
            "expansion",
            "nested command substitution",
            "A=$(printf $(printf ok)); printf $A",
        ),
        DiffCase(
            "expansion",
            "command substitution skips arithmetic close",
            "A=$(printf $((1 + 2))); printf $A",
        ),
        DiffCase(
            "expansion",
            "command substitution skips parameter close",
            "A='right)'; B=$(printf ${A}); printf $B",
        ),
        DiffCase("expansion", "backquote substitution", "A=`printf ok`; printf $A"),
        DiffCase(
            "expansion",
            "backquote substitution inherits state",
            "A=ok; B=`printf $A`; printf $B",
        ),
        DiffCase(
            "expansion",
            "quoted at standalone",
            'set -- a b; for x in "$@"; do printf [$x]; done',
        ),
        DiffCase(
            "expansion", "quoted star first IFS", 'set -- a b; IFS=,; printf "$*"'
        ),
        DiffCase(
            "expansion",
            "ifs non-whitespace",
            "IFS=,; set -- a,b,,c; printf [$1][$2][$3][$4]",
        ),
        DiffCase(
            "expansion", "pathname basic", "printf x > glob-a; set -- glob-*; printf $1"
        ),
        DiffCase(
            "expansion",
            "pathname bracket caret literal",
            "printf x > a; printf x > b; set -- [^a]; printf $1",
        ),
        DiffCase(
            "expansion",
            "pathname ASCII sort",
            "printf x > sort-glob-a; printf x > sort-glob-B; printf x > sort-glob-c; set -- sort-glob-*; printf $1:$2:$3",
        ),
        DiffCase(
            "expansion",
            "pathname equivalence class C locale",
            "printf x > eq-a; set -- eq-[[=a=]]; printf $1",
            "exact",
            "extension",
        ),
        DiffCase(
            "expansion",
            "pathname collating symbol C locale",
            "printf x > co-a; set -- co-[[.a.]]; printf $1",
            "exact",
            "extension",
        ),
        DiffCase(
            "redirection",
            "stdout redirection",
            "printf ok > out; read A < out; printf $A",
        ),
        DiffCase(
            "redirection",
            "append redirection",
            "printf a > out; printf b >> out; read A < out; printf $A",
        ),
        DiffCase("redirection", "here document", "read A <<EOF\nok\nEOF\nprintf $A"),
        DiffCase(
            "redirection",
            "quoted here document",
            "A=bad; read B <<'EOF'\n$A\nEOF\nprintf $B",
        ),
        DiffCase(
            "redirection", "dash here document", "read B <<-EOF\n\tgood\nEOF\nprintf $B"
        ),
        DiffCase(
            "redirection",
            "while here document",
            "while read x; do printf [$x]; done <<EOF\na\nb\nEOF",
        ),
        DiffCase(
            "redirection",
            "group here document",
            "{ read x; printf [$x]; } <<EOF\na\nEOF",
        ),
        DiffCase(
            "redirection",
            "quoted group here document",
            "A=bad; { read x; printf [$x]; } <<'EOF'\n$A\nEOF",
        ),
        DiffCase(
            "redirection",
            "missing input redirection continues",
            "cat < definitely_missing_file; printf after",
        ),
        DiffCase(
            "redirection",
            "special builtin missing input redirection aborts",
            "export A=1 < definitely_missing_file; printf after",
        ),
        DiffCase(
            "redirection",
            "external output redirection failure before lookup",
            "definitely_missing > __missing_dir__/out",
        ),
        DiffCase(
            "redirection",
            "builtin output redirection failure",
            "printf ok > __missing_dir__/out",
        ),
        DiffCase(
            "pipeline",
            "printf read pipeline",
            "printf 'ok\\n' | read A; printf ${A-unset}",
        ),
        DiffCase(
            "pipeline",
            "while read pipeline output",
            "printf 'a\\nb\\n' | while read x; do printf [$x]; done",
        ),
        DiffCase(
            "pipeline",
            "group read pipeline output",
            "printf 'a\\n' | { read x; printf [$x]; }",
        ),
        DiffCase("pipeline", "pipeline status", "true | false"),
        DiffCase(
            "pipeline", "missing pipeline left status", "definitely_missing | true"
        ),
        DiffCase(
            "pipeline", "missing pipeline tail status", "true | definitely_missing"
        ),
        DiffCase("builtin", "alias next read unit", "alias hi='printf ok'\nhi"),
        DiffCase("builtin", "alias list quoting", "alias aa='printf ok'; alias"),
        DiffCase(
            "builtin", "alias named query quoting", "alias aa='printf ok'; alias aa"
        ),
        DiffCase(
            "builtin", "command -v alias quoting", "alias aa='printf ok'; command -v aa"
        ),
        DiffCase("builtin", "readonly failure", "readonly A=one; A=two; printf bad"),
        DiffCase(
            "builtin",
            "export readonly failure",
            "readonly A=one; export A=two; printf bad",
        ),
        DiffCase(
            "builtin", "unset readonly failure", "readonly A=one; unset A; printf bad"
        ),
        DiffCase(
            "builtin",
            "set noglob",
            "printf x > glob-a; set -f; set -- glob-*; printf $1",
        ),
        DiffCase(
            "builtin", "errexit and-list left", "set -e; false && printf bad; printf ok"
        ),
        DiffCase("builtin", "errexit inverted pipeline", "set -e; ! true; printf ok"),
        DiffCase("builtin", "shift", "set -- a b c; shift 2; printf $1:$#"),
        DiffCase("builtin", "eval", "eval 'A=ok'; printf $A"),
        DiffCase(
            "builtin",
            "type output redirection",
            'type : definitely_missing true > out; S=$?; read A B C < out; printf "$S:$A:$B"',
        ),
        DiffCase("builtin", "trap listing quote", "trap 'printf x' EXIT; trap"),
        DiffCase(
            "builtin",
            "trap output redirection",
            "trap 'printf x' EXIT; trap > out; read A B C < out; printf \"$A\"",
        ),
        DiffCase(
            "builtin",
            "export output redirection",
            'export A=1; export -p > out; read X Y < out; printf "$X"',
        ),
        DiffCase(
            "builtin",
            "readonly output redirection",
            'readonly A=1; readonly -p > out; read X Y < out; printf "$X"',
        ),
        DiffCase("builtin", "set output redirection", "A=1; set > out; printf ok"),
        DiffCase("builtin", "xtrace default ps4 command", "set -x; printf ok"),
        DiffCase("builtin", "xtrace empty ps4 command", "PS4=; set -x; printf ok"),
        DiffCase(
            "builtin",
            "xtrace ps4 simple command",
            "PS4='TRACE: '; set -x; printf '<%s>\\n' ok",
        ),
        DiffCase(
            "builtin",
            "xtrace ps4 assignment only",
            "PS4='TRACE: '; set -x; A=1; printf '<%s>\\n' \"$A\"",
        ),
        DiffCase(
            "builtin",
            "xtrace ps4 command assignment",
            "PS4='TRACE: '; set -x; A=1 printf '<%s>\\n' ok",
        ),
        DiffCase(
            "builtin",
            "xtrace disable traced",
            "PS4='TRACE: '; set -x; set +x; printf ok",
        ),
        DiffCase(
            "builtin",
            "verbose prints next input line",
            "printf before\\n\nset -v\nprintf after\\n\nset +v\nprintf end\\n",
        ),
        DiffCase(
            "builtin",
            "verbose same line enables next line only",
            "set -v; printf after\\n\nprintf end\\n",
        ),
        DiffCase(
            "builtin",
            "verbose same line disable suppresses next",
            "set -v; set +v\nprintf end\\n",
        ),
        DiffCase(
            "builtin",
            "verbose long option form",
            "set -o verbose\nprintf after\\n\nset +o verbose\nprintf end\\n",
        ),
        DiffCase("builtin", "umask output redirection", "umask > out; printf ok"),
        DiffCase("builtin", "times output redirection", "times > out; printf ok"),
        DiffCase("builtin", "trap exit", "trap 'printf done' EXIT; :"),
        DiffCase("process", "kill zero self", "kill -0 $$; printf $?"),
        DiffCase(
            "process",
            "kill trapped term self",
            "trap 'printf term' TERM; kill -TERM $$; printf done",
        ),
        DiffCase("process", "wait true background", "true & wait $!; printf $?"),
        DiffCase(
            "process", "wait false background status", "false & wait $!; printf $?"
        ),
        DiffCase("printf", "integer flags", "printf '[%+d][%05d][%#x]' 7 7 255"),
        DiffCase("printf", "float fixed", "printf '[%.2f][%08.2f]' 1.995 -1.5"),
        DiffCase("printf", "float scientific", "printf '[%.2e][%.2G]' 12.5 12.5"),
        DiffCase(
            "printf",
            "length modifiers",
            "printf '[%lld][%Lf]' 7 1.5",
            "exact",
            "extension",
        ),
        DiffCase(
            "grammar",
            "if trailing redirection",
            "if true; then printf ok; fi > out; read A < out; printf $A",
        ),
        DiffCase(
            "grammar",
            "while false status",
            "while false; do printf bad; done; printf ok",
        ),
        DiffCase(
            "grammar",
            "until one iteration",
            'A=0; until test "$A" = 1; do A=1; printf ok; done',
        ),
        DiffCase(
            "grammar", "for empty in list", "for x in; do printf bad; done; printf ok"
        ),
        DiffCase(
            "grammar",
            "case multi pattern",
            "case abc in a*) printf A;; *c) printf C;; esac",
        ),
        DiffCase(
            "grammar",
            "case no match status",
            "case abc in z) printf bad;; esac; printf :$?",
        ),
        DiffCase("grammar", "brace group status", "{ false; }; printf :$?"),
        DiffCase("grammar", "function return status", "f(){ false; }; f; printf :$?"),
        DiffCase(
            "grammar", "function local positional", 'f(){ printf "$1:$#"; }; f a b'
        ),
        DiffCase(
            "grammar",
            "subshell redirection",
            "(printf ok) > out; read A < out; printf $A",
        ),
        DiffCase(
            "expansion", "parameter alternate set", "A=yes; printf ${A:+alt}:${B:+alt}"
        ),
        DiffCase(
            "expansion", "parameter default null colon", "A=; printf ${A:-alt}:${A-alt}"
        ),
        DiffCase("expansion", "parameter assign null colon", "A=; printf ${A:=set}:$A"),
        DiffCase("expansion", "parameter assign no colon", "A=; printf ${A=set}:$A"),
        DiffCase(
            "expansion",
            "parameter remove suffix small",
            "A=abcabc; printf ${A%c*}:${A%%b*}",
        ),
        DiffCase(
            "expansion",
            "parameter remove prefix large",
            "A=abcabc; printf ${A##*b}:${A#*b}",
        ),
        DiffCase(
            "expansion",
            "command substitution trims newlines",
            'A=$(printf "a\\n\\n"); printf "<$A>"',
        ),
        DiffCase(
            "expansion",
            "quoted command substitution preserves spaces",
            'A="$(printf "a b")"; printf "<$A>"',
        ),
        DiffCase(
            "expansion",
            "unquoted command substitution splits",
            'set -- $(printf "a b"); printf "$1:$2:$#"',
        ),
        DiffCase(
            "expansion",
            "ifs whitespace split",
            'IFS=" \t\n"; set -- a  b; printf "$1:$2:$#"',
        ),
        DiffCase(
            "expansion",
            "ifs empty disables split",
            'IFS=; set -- a b; printf "$1:$2:$#"',
        ),
        DiffCase(
            "expansion",
            "quoted empty parameter field",
            'A=; set -- "$A"; printf "$#:<$1>"',
        ),
        DiffCase(
            "expansion", "unquoted empty drops field", 'A=; set -- $A x; printf "$#:$1"'
        ),
        DiffCase(
            "expansion", "glob no match literal", 'set -- no_such_glob_*; printf "$1"'
        ),
        DiffCase(
            "expansion",
            "glob sorted two",
            'printf x > g-b; printf x > g-a; set -- g-*; printf "$1:$2"',
        ),
        DiffCase(
            "redirection",
            "left to right redirect order",
            "printf old > out; printf new > out 2>&1; read A < out; printf $A",
        ),
        DiffCase("pipeline", "not pipeline status", "! false | true; printf :$?"),
        DiffCase(
            "pipeline",
            "pipeline with function producer",
            "f(){ printf ok; }; f | read A; printf ${A-unset}",
        ),
        DiffCase(
            "pipeline",
            "pipeline function consumer isolated",
            "printf ok | f(){ read A; printf $A; }; printf :${A-unset}",
        ),
        DiffCase("builtin", "pwd physical option", "pwd -P >/dev/null; printf $?"),
        DiffCase("builtin", "readonly print one", "readonly A=1; readonly -p A"),
        DiffCase(
            "builtin",
            "set positional after options",
            'set -f -- a b; printf "$1:$2:$#"',
        ),
        DiffCase("builtin", "set plain operands", 'set a b; printf "$1:$2:$#"'),
        DiffCase(
            "builtin",
            "unset function leaves var",
            'A=1; f(){ printf bad; }; unset -f f; printf "$A"',
        ),
        DiffCase(
            "builtin",
            "unset var leaves function",
            "A=1; f(){ printf ok; }; unset -v A; f; printf :${A-unset}",
        ),
        DiffCase("builtin", "eval preserves status", "eval false; printf :$?"),
        DiffCase("builtin", "command eval status", "command eval false; printf :$?"),
        DiffCase(
            "builtin",
            "trap reset omitted action",
            'trap "printf bad" INT; trap INT; trap',
        ),
        DiffCase(
            "builtin", "trap dash reset", 'trap "printf bad" INT; trap - INT; trap'
        ),
        DiffCase("builtin", "hash no operand status", "hash; printf :$?"),
        DiffCase(
            "process",
            "background assignment isolation",
            "A=outer; A=inner true & wait $!; printf $A",
        ),
        DiffCase(
            "process",
            "background redirection",
            "true > bgout & wait $!; test -f bgout; printf $?",
        ),
    ]


def selected_cases(category: str, include_extensions: bool) -> list[DiffCase]:
    cases = diff_cases()
    if not include_extensions:
        cases = [case for case in cases if case.profile == "posix"]
    if not category:
        return cases
    return [case for case in cases if case.category == category]


def run_case(
    msh: Path,
    case: DiffCase,
    root: Path,
    compare_stderr: bool,
    baseline_only: bool,
    include_local: bool,
    include_wsl: bool,
    strict_shell_only: str,
) -> DiffResultJson:
    case_root = root / re.sub(r"[^A-Za-z0-9_.-]+", "_", case.name)
    msh_dir = case_root / "msh"
    ref_root = case_root / "ref"
    msh_dir.mkdir(parents=True, exist_ok=True)
    ref_root.mkdir(parents=True, exist_ok=True)
    msh_result = run_msh(msh, case, msh_dir)
    shells: dict[str, ShellResultJson] = {}
    for spec in shell_specs(
        baseline_only, include_local, include_wsl, strict_shell_only
    ):
        shell_dir = ref_root / spec.name
        shell_dir.mkdir(parents=True, exist_ok=True)
        result = run_reference_shell(spec, case, shell_dir)
        shells[spec.name] = {
            "available": result.available,
            "matches_msh": results_match(msh_result, result, case, compare_stderr),
            "status": result.status,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    return {
        "category": case.category,
        "name": case.name,
        "profile": case.profile,
        "status_mode": case.status_mode,
        "script": case.script,
        "msh": {
            "status": msh_result.status,
            "stdout": msh_result.stdout,
            "stderr": msh_result.stderr,
        },
        "shells": shells,
    }


def print_progress(index: int, total: int, case: DiffCase) -> None:
    print(
        f"[msh-shell-diff] {index}/{total} {case.category}/{case.name}",
        file=sys.stderr,
        flush=True,
    )


def print_text_report(
    results: list[DiffResultJson],
    strict_shell: str,
    baseline_only: bool,
    include_local: bool,
    include_wsl: bool,
    strict_shell_only: str,
) -> None:
    total = len(results)
    baseline_matches = 0
    for row in results:
        shells = row["shells"]
        baseline = shells.get(strict_shell)
        if baseline is None:
            continue
        if baseline.get("matches_msh") is True:
            baseline_matches += 1
    print(f"msh shell diff: {baseline_matches}/{total} match {strict_shell}")
    for spec in shell_specs(
        baseline_only, include_local, include_wsl, strict_shell_only
    ):
        matches = 0
        available = 0
        for row in results:
            shell = row["shells"][spec.name]
            if shell["available"]:
                available += 1
                if shell["matches_msh"]:
                    matches += 1
        print(f"  {spec.name}: {matches}/{available} matches")
    for row in results:
        shell = row["shells"][strict_shell]
        if shell["available"] and not shell["matches_msh"]:
            print("")
            print(f"- {row['category']}/{row['name']}")
            print(f"  script: {row['script']!r}")
            print(
                f"  msh: status={row['msh']['status']} stdout={row['msh']['stdout']!r}"
            )
            print(
                f"  {strict_shell}: status={shell['status']} stdout={shell['stdout']!r}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--msh", type=Path, default=default_msh_path())
    parser.add_argument("--category", default="")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--strict-shell", default="wsl-sh")
    parser.add_argument("--compare-stderr", action="store_true")
    parser.add_argument("--include-extensions", action="store_true")
    parser.add_argument("--baseline-only", action="store_true")
    parser.add_argument("--include-local-shells", action="store_true")
    parser.add_argument("--no-wsl-shells", action="store_true")
    parser.add_argument("--strict-shell-only", action="store_true")
    parser.add_argument("--progress", action="store_true")
    args = parser.parse_args()

    msh = args.msh.resolve()
    if not msh.exists():
        print(f"msh executable not found: {msh}", file=sys.stderr)
        return 2
    strict_shell_only = args.strict_shell if args.strict_shell_only else ""
    with tempfile.TemporaryDirectory(prefix="msh-shell-diff-") as raw:
        root = Path(raw)
        cases = selected_cases(args.category, args.include_extensions)
        results: list[DiffResultJson] = []
        total = len(cases)
        for index, case in enumerate(cases, 1):
            if args.progress:
                print_progress(index, total, case)
            results.append(
                run_case(
                    msh,
                    case,
                    root,
                    args.compare_stderr,
                    args.baseline_only,
                    args.include_local_shells,
                    not args.no_wsl_shells,
                    strict_shell_only,
                )
            )
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print_text_report(
            results,
            args.strict_shell,
            args.baseline_only,
            args.include_local_shells,
            not args.no_wsl_shells,
            strict_shell_only,
        )
    if args.strict:
        for row in results:
            shell = row["shells"][args.strict_shell]
            if shell["available"] and not shell["matches_msh"]:
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
