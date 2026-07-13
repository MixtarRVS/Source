#!/usr/bin/env python3
"""POSIX stress cases for msh."""

from __future__ import annotations

from msh_posix_stress_common import StressCase


def process_cases() -> list[StressCase]:
    return [
        StressCase("process", "background false wait status", """
false &
pid=$!
wait "$pid"
printf '<%s>\\n' "$?"
"""),
        StressCase("process", "background true wait status", """
true &
pid=$!
wait "$pid"
printf '<%s>\\n' "$?"
"""),
        StressCase("process", "exit trap preserves last status", """
trap 'printf "<%s>\\n" "$?"' EXIT
false
"""),
        StressCase("process", "subshell trap does not alter parent", """
trap 'printf parent' EXIT
(trap 'printf sub' EXIT)
printf main
"""),
        StressCase("process", "subshell parent exit trap not inherited", """
trap 'echo bye' EXIT
(echo hi)
echo $(echo hi)
"""),
        StressCase("process", "subshell trap list resets parent action", """
trap 'echo bye' EXIT
(trap)
(trap 'echo so long' EXIT; trap)
(trap)
"""),
        StressCase("process", "command substitution local exit trap runs", """
foo=$(trap 'echo bar' EXIT)
printf '[%s]\\n' "$foo"
"""),
        StressCase("process", "subshell variable isolation", """
A=parent
(A=child; printf '<%s>' "$A")
printf '<%s>\\n' "$A"
"""),
        StressCase("process", "exit trap action controls status", """
trap 'exit 7' EXIT
false
""", status="exact"),
        StressCase("process", "negated pipeline status", """
! false | true
printf '<%s>\\n' "$?"
"""),
        StressCase("process", "errexit ignores negated pipeline", """
set -e
! false
printf ok
"""),
        StressCase("process", "function return status", """
f() { return 6; }
f
printf '<%s>\\n' "$?"
"""),
        StressCase("process", "function in pipeline isolates assignment", """
A=outer
f() { A=inner; printf x; }
f | read X
printf '<%s><%s>\\n' "$X" "$A"
"""),
        StressCase("process", "errexit ignores if test", """
set -e
if false; then
    printf bad
fi
printf ok
"""),
        StressCase("process", "errexit ignores function used as if test", """
set -e
f() { false; printf ok; }
if f; then
    printf done
fi
"""),
        StressCase("process", "errexit ignores function used as while test", """
set -e
f() { false; printf ok; }
while f; do
    printf bad
    break
done
printf done
"""),
        StressCase("process", "errexit ignores left side and list", """
set -e
false && printf bad
printf ok
"""),
        StressCase("process", "errexit ignores left side or list", """
set -e
false || printf ok
"""),
        StressCase("process", "errexit aborts simple after or list", """
set -e
true || printf bad
false
printf after
""", status="nonzero"),
        StressCase("process", "errexit aborts failing pipeline tail", """
set -e
true | false
printf after
""", status="nonzero"),
        StressCase("process", "errexit aborts subshell failure", """
set -e
(false)
printf after
""", status="nonzero"),
        StressCase("process", "errexit aborts function body failure", """
set -e
f() { false; printf after; }
f
printf end
""", status="nonzero"),
        StressCase("process", "errexit ignores while test", """
set -e
while false; do
    printf bad
done
printf ok
"""),
        StressCase("process", "subshell exit status", """
(exit 5)
printf '<%s>\\n' "$?"
"""),
        StressCase("process", "kill list pipes into read", """
kill -l | while read A B C; do
    case "$A$B$C" in
        ?*) printf '<seen>\\n'; break;;
    esac
done
"""),
        StressCase("process", "trap listing pipes into read", """
trap '' TERM
trap | while read A B C; do
    case "$A $B $C" in
        *TERM*) printf '<seen>\\n'; break;;
    esac
done
"""),
        StressCase("process", "export listing pipes into read", """
export PIPE_A=ok
export -p | while read A B C; do
    case "$A $B $C" in
        *PIPE_A*) printf '<seen>\\n'; break;;
    esac
done
"""),
        StressCase("process", "type output pipes into read", """
type printf | while read A B C; do
    case "$A $B $C" in
        *printf*) printf '<seen>\\n'; break;;
    esac
done
"""),
        StressCase("process", "command verbose pipes into read", """
command -V printf | while read A B C; do
    case "$A $B $C" in
        *printf*) printf '<seen>\\n'; break;;
    esac
done
"""),
        StressCase("process", "background group pid wait", """
{ printf X > out; } &
pid=$!
wait "$pid"
read X < out
printf '<%s>\\n' "$?"
printf '<%s>\\n' "$X"
"""),
        StressCase("process", "background pipeline pid wait", """
printf X | read X &
pid=$!
wait "$pid"
printf '<%s>\\n' "$?"
"""),
        StressCase("process", "wait multiple operands returns last status", """
false & p1=$!
true & p2=$!
wait "$p1" "$p2"
printf '<%s>\\n' "$?"
"""),
        StressCase("process", "wait unknown pid diagnostic", """
wait 999999
printf after
""", stderr="normalized"),
        StressCase("process", "last background pid updates after failure", """
false & p1=$!
true & p2=$!
[ "$p1" = "$p2" ] && printf same || printf different
wait "$p1" 2>/dev/null
wait "$p2" 2>/dev/null
"""),
    ]
