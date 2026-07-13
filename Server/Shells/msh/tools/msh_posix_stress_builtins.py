#!/usr/bin/env python3
"""POSIX stress cases for msh."""

from __future__ import annotations

from msh_posix_stress_common import StressCase


def builtin_cases() -> list[StressCase]:
    return [
        StressCase("builtin", "read with custom ifs and rest field", """
printf 'a:b:c\\n' > in
IFS=:
read A B < in
printf '<%s><%s>\\n' "$A" "$B"
"""),
        StressCase("builtin", "getopts clustered options", """
set -- -ab value
while getopts ab opt; do
    printf '<%s>' "$opt"
done
printf '<%s>\\n' "$OPTIND"
"""),
        StressCase("builtin", "getopts missing arg noisy mode", """
set -- -a
while getopts a: opt; do
    printf '<%s:%s>' "$opt" "$OPTARG"
done
printf '<%s>\\n' "$OPTIND"
""", stderr="normalized"),
        StressCase("builtin", "readonly rejects later assignment", """
readonly A=1
A=2
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "export assignment visible to command", """
export A=seen
printf '<%s>\\n' "$A"
"""),
        StressCase("builtin", "command suppresses function execution", """
printf() { :; }
command printf 'ok\\n'
"""),
        StressCase("builtin", "hash reset succeeds", """
hash -r
printf '<%s>\\n' "$?"
"""),
        StressCase("builtin", "cd logical dotdot updates pwd", """
pwd > start
mkdir -p d/sub
cd d/sub
cd ..
pwd > now
read A < start
read B < now
case "$B" in
    "$A"/d) printf ok;;
    *) printf bad;;
esac
"""),
        StressCase("builtin", "cd dash outputs new pwd", """
pwd > start
mkdir -p d
cd d
cd - > got
read A < start
read B < got
case "$B" in
    "$A") printf ok;;
    *) printf bad;;
esac
"""),
        StressCase("builtin", "cd physical option accepted", """
cd -P .
printf '<%s>\\n' $?
"""),
        StressCase("builtin", "pwd logical physical options accepted", """
pwd -L > a
pwd -P > b
printf '<%s>\\n' $?
"""),
        StressCase("builtin", "set positional after options", """
set -f -- a b
printf '<%s><%s><%s>\\n' "$1" "$2" "$-"
"""),
        StressCase("builtin", "verbose eval quoted newline read unit", """
set -v
eval 'printf ok
printf done'; printf after
"""),
        StressCase("builtin", "verbose eval readonly unset aborts", """
set -v
eval 'readonly A=old
unset -v A'; printf after
""", status="nonzero"),
        StressCase("builtin", "trap reset and listing", """
trap 'printf bad' TERM
trap - TERM
trap
printf done
"""),
        StressCase("builtin", "trap zero alias exit", """
trap 'printf bye' 0
exit 0
"""),
        StressCase("builtin", "dot return exposes status", """
printf 'A=ok\\nreturn 7\\n' > src
. ./src
printf '<%s:%s>\\n' "$A" "$?"
"""),
        StressCase("builtin", "shift updates positional count", """
set -- a b c
shift 2
printf '<%s:%s>\\n' "$1" "$#"
"""),
        StressCase("builtin", "alias newline activation", """
alias hi='printf ok'
hi
"""),
        StressCase("builtin", "read raw preserves backslash", """
printf 'a\\\\b\\n' > in
read -r X < in
printf '<%s>\\n' "$X"
"""),
        StressCase("builtin", "read raw with option delimiter", """
printf 'a\\\\b\\n' > in
read -r -- X < in
printf '<%s>\\n' "$X"
"""),
        StressCase("builtin", "read backslash newline joins lines", """
printf '%s\\n%s\\n' 'a\\' 'b' > in
read X < in
printf '<%s>\\n' "$X"
"""),
        StressCase("builtin", "read raw backslash newline does not join", """
printf '%s\\n%s\\n' 'a\\' 'b' > in
read -r X < in
printf '<%s>\\n' "$X"
"""),
        StressCase("builtin", "read final var preserves separators", """
printf 'a:b:c:d\\n' > in
IFS=:
read A B < in
printf '<%s><%s>\\n' "$A" "$B"
"""),
        StressCase("builtin", "read empty input status", """
: > in
read A < in
printf '<%s><%s>\\n' "$?" "$A"
"""),
        StressCase("builtin", "printf numeric single quote char", """
printf '<%d><%x><%o>\\n' "'A" "'A" "'A"
"""),
        StressCase("builtin", "printf numeric double quote char", """
printf '<%d><%X>\\n' '"A' '"A'
"""),
        StressCase("builtin", "printf escaped alert in format", """
X=$(printf '\\a')
printf '<%s>\\n' "${#X}"
"""),
        StressCase("builtin", "printf format octal escape", """
printf '\\101\\n'
"""),
        StressCase("builtin", "printf format octal escape stops at three digits", """
printf '\\1012\\n'
"""),
        StressCase("builtin", "printf escaped alert in percent b", """
X=$(printf '%b' '\\a')
printf '<%s>\\n' "${#X}"
"""),
        StressCase("builtin", "printf backslash c stops all output", """
printf '%b' 'A\\cB' C
printf '<after>\\n'
"""),
        StressCase("builtin", "printf star width and precision", """
printf '<%*.*s>\\n' 6 3 abcdef
"""),
        StressCase("builtin", "printf negative star width", """
printf '<%*s>\\n' -5 a
"""),
        StressCase("builtin", "printf alternate octal zero precision", """
printf '<%#.0o><%.0o>\\n' 0 0
"""),
        StressCase("builtin", "printf sign and zero padding", """
printf '<%+05d><% 05d>\\n' 7 7
"""),
        StressCase("builtin", "printf unsigned negative decimal", """
printf '<%u>\\n' -1
"""),
        StressCase("builtin", "printf unsigned negative base forms", """
printf '<%x><%X><%o>\\n' -1 -1 -1
"""),
        StressCase("builtin", "printf positional string arguments", """
printf '<%2$s:%1$s>\\n' one two
""", profile="extension"),
        StressCase("builtin", "printf positional dynamic width", """
printf '<%2$*1$s>\\n' 5 x
""", profile="extension"),
        StressCase("builtin", "printf positional dynamic precision", """
printf '<%3$.*2$s>\\n' ignored 3 abcdef
""", profile="extension"),
        StressCase("builtin", "function temporary assignment visibility", """
A=outer
f() { printf '<%s>' "$A"; }
A=inner f
printf '<%s>\\n' "$A"
"""),
        StressCase("builtin", "command double dash executes builtin", """
printf() { :; }
command -- printf 'ok\\n'
"""),
        StressCase("builtin", "command readonly violation nonfatal", """
A=1
readonly A
command readonly A=2
printf after
""", stderr="normalized"),
        StressCase("builtin", "direct shift too many aborts", """
set -- a b
shift 3
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command shift too many nonfatal", """
set -- a b
command shift 3
printf after
""", stderr="normalized"),
        StressCase("builtin", "unset function reveals builtin", """
printf() { :; }
unset -f printf
printf ok
"""),
        StressCase("builtin", "readonly listing redirection", """
readonly A=1
readonly -p > out
read X < out
case "$X" in
    *A*) printf ok;;
    *) printf bad;;
esac
"""),
        StressCase("builtin", "trap self signal action", """
trap 'printf T' USR1
kill -USR1 $$
printf A
"""),
        StressCase("builtin", "wait all background jobs", """
false &
wait
printf '<%s>\\n' "$?"
"""),
        StressCase("builtin", "test and operator", """
[ foo -a bar ]
printf '<%s>\\n' "$?"
"""),
        StressCase("builtin", "test or operator", """
[ '' -o bar ]
printf '<%s>\\n' "$?"
"""),
        StressCase("builtin", "test grouped negation", """
[ ! \\( '' -o foo \\) ]
printf '<%s>\\n' "$?"
"""),
        StressCase("builtin", "test repeated negation unary", """
[ ! ! -n foo ]
printf '<%s>\\n' "$?"
""", profile="extension"),
        StressCase("builtin", "test repeated negation empty", """
[ ! ! '' ]
printf '<%s>\\n' "$?"
""", profile="extension"),
        StressCase("builtin", "direct export invalid name aborts", """
export 1BAD=value
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command export invalid name nonfatal", """
command export 1BAD=value
printf after
""", stderr="normalized"),
        StressCase("builtin", "eval export invalid name aborts", """
eval 'export 1BAD=value'
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command eval export invalid name nonfatal", """
command eval 'export 1BAD=value'
printf after
""", stderr="normalized"),
        StressCase("builtin", "direct readonly invalid name aborts", """
readonly 1BAD=value
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command readonly invalid name nonfatal", """
command readonly 1BAD=value
printf after
""", stderr="normalized"),
        StressCase("builtin", "direct set invalid option aborts", """
set -Z
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command set invalid option nonfatal", """
command set -Z
printf after
""", stderr="normalized"),
        StressCase("builtin", "direct unset readonly aborts", """
readonly A=1
unset A
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command unset readonly nonfatal", """
readonly A=1
command unset A
printf after
""", stderr="normalized"),
        StressCase("builtin", "eval unset readonly aborts", """
readonly A=1
eval 'unset A'
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command eval unset readonly nonfatal", """
readonly A=1
command eval 'unset A'
printf after
""", stderr="normalized"),
        StressCase("builtin", "readonly assignment before colon aborts", """
readonly A
A=x :
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command readonly assignment before colon nonfatal", """
readonly A
A=x command :
printf after
""", stderr="normalized"),
        StressCase("builtin", "readonly assignment before regular builtin nonfatal", """
readonly A
A=x echo hi
printf after
""", stderr="normalized"),
        StressCase("builtin", "eval return outside function aborts", """
eval 'return 7'
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("builtin", "command eval return outside function nonfatal", """
command eval 'return 7'
printf after
""", stderr="normalized"),
    ]
