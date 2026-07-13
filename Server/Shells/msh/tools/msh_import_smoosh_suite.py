#!/usr/bin/env python3
"""Import a conservative Smoosh POSIX shell test slice for msh.

The imported cases stay as ordinary .sh files so `msh_posix_suite.py` remains
the only comparison runner. This importer deliberately avoids Smoosh cases that
need broad POSIX userland utilities, interactive mode, job control, or known
non-POSIX extensions; those belong in later Mixtar userland/system gates.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


MSH_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SUITE = MSH_DIR / "suites" / "posix-external-smoosh"
DEFAULT_REPO = "https://github.com/mgree/smoosh.git"

SMOOSH_ALLOWLIST = (
    "benchmark.fact5.test",
    "benchmark.while.test",
    "builtin.alias.empty.test",
    "builtin.break.lexical.test",
    "builtin.break.nonlexical.test",
    "builtin.cd.pwd.test",
    "builtin.command.ec.test",
    "builtin.command.exec.test",
    "builtin.command.keyword.test",
    "builtin.command.nospecial.test",
    "builtin.command.special.assign.test",
    "builtin.continue.lexical.test",
    "builtin.continue.nonlexical.test",
    "builtin.dot.break.test",
    "builtin.dot.nonexistent.test",
    "builtin.dot.path.test",
    "builtin.dot.return.test",
    "builtin.echo.exitcode.test",
    "builtin.eval.test",
    "builtin.eval.break.test",
    "builtin.eval.trap.test",
    "builtin.exec.badredir.test",
    "builtin.exec.noargs.ec.test",
    "builtin.exec.true.test",
    "builtin.exit0.test",
    "builtin.exitcode.test",
    "builtin.export.test",
    "builtin.export.override.test",
    "builtin.export.unset.test",
    "builtin.falsetrue.test",
    "builtin.kill0.test",
    "builtin.kill0_+5.test",
    "builtin.kill.signame.test",
    "builtin.printf.repeat.test",
    "builtin.pwd.exitcode.test",
    "builtin.readonly.assign.noninteractive.test",
    "builtin.set.quoted.test",
    "builtin.set.-m.test",
    "builtin.special.redir.error.test",
    "builtin.source.nonexistent.earlyexit.test",
    "builtin.source.nonexistent.test",
    "builtin.source.setvar.test",
    "builtin.test.bigint.test",
    "builtin.times.ioerror.test",
    "builtin.trap.chained.test",
    "builtin.trap.exit3.test",
    "builtin.trap.exit.subshell.test",
    "builtin.trap.exitcode.test",
    "builtin.trap.false.test",
    "builtin.trap.kill.undef.test",
    "builtin.trap.nested.test",
    "builtin.trap.noexit.test",
    "builtin.trap.redirect.test",
    "builtin.trap.return.test",
    "builtin.trap.subshell.false.exit.test",
    "builtin.trap.subshell.false.test",
    "builtin.trap.subshell.loud.test",
    "builtin.trap.subshell.loud2.test",
    "builtin.trap.subshell.quiet.test",
    "builtin.trap.subshell.true.ec1.test",
    "builtin.trap.subshell.truefalse.test",
    "builtin.trap.supershell.test",
    "builtin.unset.test",
    "parse.emptyvar.test",
    "parse.eval.error.test",
    "parse.error.test",
    "semantics.arith.assign.multi.test",
    "semantics.arith.modernish.test",
    "semantics.arith.pos.test",
    "semantics.arith.var.space.test",
    "semantics.arithmetic.bool_to_num.test",
    "semantics.arithmetic.tilde.test",
    "semantics.-C.test",
    "semantics.assign.noglob.test",
    "semantics.assign.visible.test",
    "semantics.background.pid.test",
    "semantics.background.pipe.pid.test",
    "semantics.backtick.exit.test",
    "semantics.backtick.fds.test",
    "semantics.backtick.ppid.test",
    "semantics.case.escape.modernish.test",
    "semantics.case.escape.quotes.test",
    "semantics.case.ec.test",
    "semantics.command.argv0.test",
    "semantics.command-subst.test",
    "semantics.command-subst.newline.test",
    "semantics.defun.ec.test",
    "semantics.empty.test",
    "semantics.errexit.subshell.test",
    "semantics.errexit.trap.test",
    "semantics.errexit.carryover.test",
    "semantics.error.noninteractive.test",
    "semantics.expansion.quotes.adjacent.test",
    "semantics.expansion.heredoc.backslash.test",
    "semantics.escaping.backslash.test",
    "semantics.escaping.backslash.modernish.test",
    "semantics.escaping.heredoc.dollar.test",
    "semantics.escaping.newline.test",
    "semantics.escaping.quote.test",
    "semantics.escaping.single.test",
    "semantics.eval.makeadder.test",
    "semantics.evalorder.fun.test",
    "semantics.expansion.substring.test",
    "semantics.for.readonly.test",
    "semantics.fun.error.restore.test",
    "semantics.ifs.combine.ws.test",
    "semantics.background.nojobs.stdin.test",
    "semantics.background.test",
    "semantics.kill.traps.test",
    "semantics.length.test",
    "semantics.no-command-subst.test",
    "semantics.pattern.modernish.test",
    "semantics.pattern.bracket.quoted.test",
    "semantics.pattern.hyphen.test",
    "semantics.pattern.rightbracket.test",
    "semantics.pipe.chained.test",
    "semantics.quote.backslash.test",
    "semantics.quote.tilde.test",
    "semantics.redir.fds.test",
    "semantics.redir.close.test",
    "semantics.redir.from.test",
    "semantics.redir.indirect.test",
    "semantics.redir.nonregular.test",
    "semantics.redir.to.test",
    "semantics.redir.toomany.test",
    "semantics.return.and.test",
    "semantics.return.if.test",
    "semantics.return.not.test",
    "semantics.return.or.test",
    "semantics.return.trap.test",
    "semantics.return.while.test",
    "semantics.splitting.ifs.test",
    "semantics.subshell.redirect.test",
    "semantics.subshell.return.test",
    "semantics.subshell.return2.test",
    "semantics.subshell.break.test",
    "semantics.substring.quotes.test",
    "semantics.tilde.no-exp.test",
    "semantics.tilde.quoted.prefix.test",
    "semantics.tilde.quoted.test",
    "semantics.tilde.sep.test",
    "semantics.tilde.colon.test",
    "semantics.tilde.test",
    "semantics.traps.async.test",
    "semantics.traps.inherit.test",
    "semantics.var.alt.nullifs.test",
    "semantics.var.alt.null.test",
    "semantics.var.builtin.nonspecial.test",
    "semantics.var.ifs.sep.test",
    "semantics.var.star.emptyifs.test",
    "semantics.var.star.format.test",
    "semantics.var.unset.nofield.test",
    "semantics.var.dashu.test",
    "semantics.varassign.test",
    "semantics.var.format.tilde.test",
    "semantics.variable.escape.length.test",
    "semantics.while.test",
    "semantics.wait.alreadydead.test",
    "semantics.noninteractive.expansion.exit.test",
    "sh.-c.arg0.test",
    "sh.env.ppid.test",
    "sh.file.weirdness.test",
    "sh.set.ifs.test",
)

SMOOSH_FILE_MODE = (
    "semantics.expansion.substring.test",
    "semantics.substring.quotes.test",
)

SMOOSH_BODY_OVERRIDES: dict[str, str] = {
    # Keep the shell-language behavior while avoiding broad external utility
    # dependencies in the imported gate.
    "benchmark.fact5.test": """fact() {
  n=$1
  if [ "$n" -le 0 ]
  then echo 1
  else echo $((n * $(fact $((n-1)) ) ))
  fi
}
fact 5
""",
    "benchmark.while.test": """x=0
while [ $x -lt 50 ]
do
    : $((x+=1))
done
echo $x
""",
    "builtin.cd.pwd.test": """pwd -P >/dev/null
orig=$(pwd)
[ "$orig" = "$PWD" ] || exit 1
cd .
[ "$orig" = "$PWD" ] || exit 2
[ "$(pwd)" = "$PWD" ] || exit 3
echo ok
""",
    "builtin.dot.path.test": """set -e
printf 'echo path-dot-ok\\n' >scr2
PATH=/definitely/not/here:.
. scr2
""",
    "builtin.dot.return.test": """printf '%s\\n' 'echo always' '(exit 47)' 'return' 'echo never' >scr
. ./scr
[ $? -eq 47 ] || exit 1
echo done
""",
    "builtin.export.unset.test": """set -e
unset x
export x
case "$(export -p)" in
  *"export x"*) echo ok ;;
  *) exit 1 ;;
esac
""",
    "builtin.export.test": """printf '%s\\n' 'echo ${var-unset}' >scr
$TEST_SHELL scr
var=hi
$TEST_SHELL scr
var=here $TEST_SHELL scr
export var=bye
$TEST_SHELL scr
""",
    "builtin.exitcode.test": """high_exit() {
    return 42
}

COMMANDS=": true false pwd echo times eval set trap command umask alias unalias wait read test [ printf kill getopts"

echo Leaking commands:
for command in $COMMANDS; do
    high_exit
    $command </dev/null >/dev/null 2>/dev/null
    rc=$?
    if [ "$rc" -eq 42 ]; then
        echo "$command"
    fi
done
""",
    "builtin.set.quoted.test": """myvar='a b c'
set >all
while IFS= read -r line; do
  case $line in
    myvar=*) printf '%s\\n' "$line" >scr ;;
  esac
done <all
. ./scr
printf '%s\\n' $myvar
""",
    "builtin.times.ioerror.test": """exec 3>&1
(
  trap "" PIPE
  i=0
  while [ "$i" -lt 10000 ]; do
    i=$((i + 1))
  done
  command times
  echo ?=$? >&3
) | :
""",
    "builtin.kill.signame.test": """set -e
seen=0
trap 'seen=1' TERM
kill $$
[ "$seen" -eq 1 ] || exit 1
echo plain kill

seen=0
kill -TERM $$
[ "$seen" -eq 1 ] || exit 2
echo named \\(-TERM\\)

seen=0
kill -15 $$
[ "$seen" -eq 1 ] || exit 3
echo numbered \\(-15\\)
""",
    "parse.eval.error.test": """printf '%s\\n' 'eval "if"' 'echo lived' >scr
$TEST_SHELL scr && exit 1
exit 0
""",
    "parse.error.test": """printf '%s\\n' ')' >scr
$TEST_SHELL scr || echo sh ok
$TEST_SHELL -c '. ./scr' || echo dot ok
""",
    "semantics.-C.test": """: >out
set -o noclobber
printf x >out
[ $? -gt 0 ] || exit 2
""",
    "semantics.background.pid.test": """$TEST_SHELL -c 'printf "%s\\n" "$$" >pid.out' &
bgpid=$!
wait "$bgpid"
IFS= read -r childpid <pid.out
[ "$bgpid" -eq "$childpid" ] && echo ok
""",
    "semantics.background.pipe.pid.test": """printf x | $TEST_SHELL -c 'IFS= read -r x; printf "%s\\n" "$$" >pid.out' &
bgpid=$!
wait "$bgpid"
IFS= read -r childpid <pid.out
[ "$bgpid" -eq "$childpid" ] && echo ok
""",
    "semantics.background.nojobs.stdin.test": """printf '%s\\n' 'set +m' 'exec <in' 'read ignored &' 'wait' 'read parent' 'printf "%s\\n" "$parent"' >scr
printf '%s\\n' illegible >in
$TEST_SHELL scr
""",
    "semantics.background.test": """echo hi
$TEST_SHELL -c 'echo derp' >bg.out &
echo bye
wait
read bg <bg.out
echo "$bg"
""",
    "semantics.backtick.ppid.test": """set -e
$TEST_SHELL -c 'echo $PPID' >pid1
$TEST_SHELL -c 'echo $PPID' >pid2
read a <pid1
read b <pid2
[ "$a" = "$b" ] || exit 2
printf '%s\\n' pid1=pid2
(echo $PPID) >ppid
read c <ppid
[ "$PPID" = "$c" ] || exit 3
printf '%s\\n' ppid=subshell
""",
    "semantics.error.noninteractive.test": """# msh-stderr: normalized
$TEST_SHELL -c 'echo before; ${MSH_UNSET_FOR_ERROR:?z}; echo after'
printf 'status=%s\\n' "$?"
""",
    "semantics.escaping.quote.test": """set -e
for c in '"' '#' '%' '&' "'" '(' ')' '*' '+' ',' '-' '.' '/' ':' \\
         ';' '<' '=' '>' '?' '@' '[' ']' '^' '_' '{' '|' '}' '~' ' '
do
        x=`printf '%s' "$c"`
        printf '%s\\n' "$c"
        [ "$c" = "$x" ]
done
echo done
""",
    "semantics.expansion.quotes.adjacent.test": """: >ab
: >ac
echo a*
echo "a"*
echo 'a'*
""",
    "builtin.source.setvar.test": """set -e
printf '%s\\n' 'x=5' >to_source
source ./to_source
echo ${x?:unset}
[ "$x" -eq 5 ]
""",
    "semantics.case.ec.test": """(exit 3)
echo $?
case a in
    ( b ) (exit 4) ;;
    ( * ) ;;
esac
echo $?

(exit 5)
case a$(echo $?>ec) in
    ( b ) (exit 6) ;;
esac
echo $?
read ec_value <ec
[ "$ec_value" = "5" ] || exit 2

false
case a in
    ( a ) echo visible $? ;;
esac

false
case a in
    ( b ) (exit 6) ;;
esac
echo $?
""",
    "semantics.command-subst.newline.test": """while IFS= read -r line
do
    printf '%s\\n' "$line"
done <<END
1
$(echo "")
2
END
""",
    "semantics.errexit.carryover.test": """set -e
putsn() { echo "$@"; }
false && true
putsn "It should be executed"
false && true
echo hello
""",
    "semantics.escaping.heredoc.dollar.test": """while IFS= read -r line
do
    printf '%s\\n' "$line"
done <<EOF
echo \\\\\\$var
EOF
while IFS= read -r line
do
    printf '%s\\n' "$line"
done <<'EOF'
echo \\\\\\$var
EOF
""",
    "semantics.escaping.single.test": """while IFS= read -r line
do
    printf '%s\\n' "$line"
done <<weirdo
line one
line two
"line".\\${PATH}.\\'three\\'\\\\x\\
line four
weirdo
""",
    "semantics.expansion.heredoc.backslash.test": """while IFS= read -r line
do
    printf '%s\\n' "$line"
done <<EOF
an escaped \\\\[bracket]
should \\\\ work just fine
EOF
while IFS= read -r line
do
    printf '%s\\n' "$line"
done <<EOF
exit \\$?
EOF
""",
    "semantics.ifs.combine.ws.test": """unset IFS
echo `printf '%b' '\\n\\tx\\n\\n          5\\n 12\\t '`
IFS=$(printf '%b' ' \\n\\t')
echo `printf '%b' '\\n\\tx\\n\\n          5\\n 12\\t '`
""",
    "semantics.kill.traps.test": """$TEST_SHELL -c 'while :; do :; done' &
pid=$!
kill "$pid"
[ "$?" -eq 0 ] || exit 1
wait "$pid"
[ "$?" -ge 128 ] || exit 2
""",
    "semantics.pattern.hyphen.test": """: >file-
: >filea
echo file[-123]
echo file[123-]
echo file[[.-.]]
echo file[[=-=]]
echo file[!-123]
echo file[[:alpha:]]
echo file[a-z]
""",
    "semantics.pattern.rightbracket.test": """: >file]
: >filea
echo file[]123]
echo file[[.].]]
echo file[[=]=]]
echo file[!]123]
echo file[[:alpha:]]
echo file[a-z]
""",
    "semantics.redir.from.test": """set -e
echo hi >file
[ -s file ]
read x <file
[ "$x" = "hi" ]
""",
    "semantics.redir.to.test": """set -e
echo hi >file
[ -s file ]
read x <file
[ "$x" = "hi" ]
""",
    "semantics.redir.toomany.test": """c="echo hi"
n=3
while [ "$n" -le 10 ]
do
        c="{ $c; echo hi; } >file_$n"
        n=$((n + 1))
done
eval "$c" 2>err
[ -e err ] && ! [ -s err ] || exit 2
""",
    "semantics.splitting.ifs.test": """IFS="-,"
echo `printf '%s\\n' '-,1-,-2,-,3,-'`
""",
    "semantics.tilde.colon.test": """tilde=~
printf 'var=:~\\n[ "$var" = ":%s" ]\\n' "$tilde" >test_script
$TEST_SHELL test_script
""",
    "semantics.wait.alreadydead.test": """$TEST_SHELL -c 'while :; do :; done' &
pid=$!
kill "$pid"
echo kill ec: $?
wait "$pid"
echo wait ec: $?
""",
    "sh.file.weirdness.test": """$TEST_SHELL nonesuch
printf '%s\\n' 'echo works' >scr
$TEST_SHELL scr
$TEST_SHELL ./scr
""",
    "semantics.tilde.quoted.test": """HOME="weird    times"
printf '%s\\n' ~
: >a1
: >a2
: >a3
HOME='a*'
printf '%s\\n' ~
""",
    "semantics.tilde.test": """echo ~ >tilde.out
var=~
echo $var > var.out
[ -s tilde.out ] && [ -s var.out ] || exit 1
read t <tilde.out
read v <var.out
[ "$t" = "$v" ] && [ "$t" != "~" ]
""",
    "sh.-c.arg0.test": """printf '%s\\n' 'echo "i am $0, hear me roar"' >scr
$TEST_SHELL -c '. "$0"' ./scr
""",
    "sh.env.ppid.test": """inner=$($TEST_SHELL -c 'printf "%s" "$PPID"')
[ "$inner" -eq "$$" ] && echo ok
""",
    "sh.set.ifs.test": """printf '%s\\n' 'printf %s "$IFS"' >show_ifs
$TEST_SHELL show_ifs || exit 1
export IFS=123
$TEST_SHELL show_ifs || exit 1
IFS=abc $TEST_SHELL show_ifs || exit 1
""",
}


def adapt_case_body(name: str, body: str) -> str:
    override = SMOOSH_BODY_OVERRIDES.get(name)
    if override is not None:
        return override
    if name == "builtin.kill0_+5.test":
        # The original `$$+5` is valid for one process namespace, but this
        # gate compares Windows-hosted msh against WSL sh. Use a stable
        # nonexistent PID so the case tests kill -0 failure, not PID collision.
        body = body.replace("$(($$+5))", "999999999")
    if name == "semantics.evalorder.fun.test":
        body = body.replace(
            "[ -f assign ] && echo assign exists && rm assign",
            "[ -f assign ] && echo assign exists",
        )
        body = body.replace(
            "[ -f redir ] && echo redir exists && rm redir",
            "[ -f redir ] && echo redir exists",
        )
    return body


def run(command: list[str], cwd: Path | None = None) -> None:
    subprocess.run(command, cwd=str(cwd) if cwd else None, check=True)


def fetch_repo(repo: str, work_root: Path) -> Path:
    target = work_root / "smoosh"
    run(["git", "clone", "--depth", "1", repo, str(target)])
    return target


def case_category(name: str) -> str:
    return name.split(".", 1)[0]


def case_target_name(name: str) -> str:
    return name.removesuffix(".test") + ".sh"


def case_run_mode(name: str) -> str:
    if name in SMOOSH_FILE_MODE:
        return "file"
    return "eval"


def write_case(source_root: Path, target_root: Path, name: str) -> None:
    source_path = source_root / "tests" / "shell" / name
    if not source_path.exists():
        raise FileNotFoundError(f"Smoosh case not found: {source_path}")
    category = case_category(name)
    target_dir = target_root / category
    target_dir.mkdir(parents=True, exist_ok=True)
    body = source_path.read_text(encoding="utf-8", errors="replace")
    body = adapt_case_body(name, body)
    text = (
        f"# msh-source: smoosh/tests/shell/{name}\n"
        "# msh-profile: posix\n"
        f"# msh-run: {case_run_mode(name)}\n"
        + body
    )
    (target_dir / case_target_name(name)).write_text(text, encoding="ascii", errors="ignore", newline="\n")


def write_readme(target_root: Path, repo: str, source_root: Path) -> None:
    lines = [
        "# msh posix-external-smoosh suite",
        "",
        "Imported by `tools/msh_import_smoosh_suite.py`.",
        "",
        f"Source repository: `{repo}`",
        f"Source checkout used during import: `{source_root.name}`",
        "",
        "This is a conservative Smoosh shell-language slice for the current",
        "`msh-core` profile. Cases needing broad POSIX utilities, interactive",
        "mode, job control, or known non-POSIX behavior are intentionally not",
        "imported yet.",
        "",
        f"Imported cases: `{len(SMOOSH_ALLOWLIST)}`.",
        "",
        "## Cases",
        "",
    ]
    for name in SMOOSH_ALLOWLIST:
        lines.append(f"- `tests/shell/{name}`")
    lines.append("")
    (target_root / "README.md").write_text("\n".join(lines), encoding="utf-8", newline="\n")


def copy_license(source_root: Path, target_root: Path) -> None:
    license_path = source_root / "LICENSE"
    if license_path.exists():
        shutil.copyfile(license_path, target_root / "SMOOSH_LICENSE.txt")


def import_suite(source_root: Path, target_root: Path, repo: str, clean: bool) -> int:
    if clean and target_root.exists():
        shutil.rmtree(target_root)
    target_root.mkdir(parents=True, exist_ok=True)
    for name in SMOOSH_ALLOWLIST:
        write_case(source_root, target_root, name)
    write_readme(target_root, repo, source_root)
    copy_license(source_root, target_root)
    return len(SMOOSH_ALLOWLIST)


def main() -> int:
    parser = argparse.ArgumentParser(description="Import a conservative Smoosh POSIX shell test slice.")
    parser.add_argument("--source", type=Path, help="Existing local Smoosh checkout.")
    parser.add_argument("--suite", type=Path, default=DEFAULT_SUITE)
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--no-clean", action="store_true")
    args = parser.parse_args()

    suite = args.suite.resolve()
    if args.source:
        source = args.source.resolve()
        count = import_suite(source, suite, args.repo, not args.no_clean)
    else:
        with tempfile.TemporaryDirectory(prefix="msh-smoosh-import-") as raw:
            source = fetch_repo(args.repo, Path(raw))
            count = import_suite(source, suite, args.repo, not args.no_clean)
    print(f"imported {count} Smoosh cases into {suite}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
