#!/usr/bin/env python3
"""POSIX stress cases for msh."""

from __future__ import annotations

from msh_posix_stress_common import StressCase


def expansion_cases() -> list[StressCase]:
    return [
        StressCase("expansion", "parameter default empty and set", """
unset A
B=
printf '<%s><%s><%s>\\n' "${A:-x}" "${B:-y}" "${B-y}"
"""),
        StressCase("expansion", "parameter assign mutates state", """
unset A
printf '<%s>' "${A:=value}"
printf '<%s>\\n' "$A"
"""),
        StressCase("expansion", "readonly parameter assign unset aborts", """
readonly A
printf '<%s>\\n' "${A:=value}"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "readonly parameter assign empty aborts", """
A=
readonly A
printf '<%s>\\n' "${A:=value}"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "parameter alternate set and unset", """
A=1
unset B
printf '<%s><%s>\\n' "${A:+yes}" "${B:+no}"
"""),
        StressCase("expansion", "prefix suffix trim patterns", """
A=abcabc
printf '<%s><%s><%s><%s>\\n' "${A#a*}" "${A##a*}" "${A%b*}" "${A%%b*}"
"""),
        StressCase("expansion", "quoted at between words", """
set -- 'a b' c
for x in pre"$@"post; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "ifs non-whitespace splitting", """
IFS=:
set -- a::b:
for x in $1; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "nested command substitution in word", """
printf '<%s>\\n' "a$(printf b$(printf c))d"
"""),
        StressCase("expansion", "backquote command substitution quoted", """
printf '<%s>\\n' "`printf 'a b'`"
"""),
        StressCase("expansion", "pathname expansion sorted byte order", """
> pb
> pa
for x in p?; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "parameter length in quoted word", """
A=abcd
printf '<%s>\\n' "len=${#A}"
"""),
        StressCase("expansion", "quoted star and at separation", """
set -- 'a b' c
printf '<%s>' "$*"
for x in "$@"; do
    printf '[%s]' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "command substitution strips trailing newlines", """
X=$(printf 'a\\n\\n')
printf '<%s>\\n' "$X"
"""),
        StressCase("expansion", "parameter error aborts command", """
unset A
printf '%s\\n' "${A:?boom}"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "bad substring substitution aborts", """
A=abc
printf '<%s>\\n' "${A:1}"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "bad replacement substitution aborts", """
A=abc
printf '<%s>\\n' "${A/b/x}"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "readonly arithmetic assignment aborts", """
A=1
readonly A
printf '<%s>\\n' "$((A=2))"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "readonly arithmetic compound assignment aborts", """
A=1
readonly A
printf '<%s>\\n' "$((A+=2))"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "arithmetic nonnumeric variable aborts", """
A=B
B=4
printf '<%s>\\n' "$((A+1))"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "arithmetic invalid octal variable aborts", """
A=08
printf '<%s>\\n' "$((A+1))"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "arithmetic parameter expands to variable name", """
A=B
B=4
printf '<%s>\\n' "$(( $A + 1 ))"
"""),
        StressCase("expansion", "arithmetic braced parameter expands to variable name", """
A=B
B=4
printf '<%s>\\n' "$(( ${A} + 1 ))"
"""),
        StressCase("expansion", "arithmetic parameter text keeps precedence", """
A='1+2*3'
printf '<%s>\\n' "$(( $A * 2 ))"
"""),
        StressCase("expansion", "arithmetic command substitution keeps expression text", """
printf '<%s>\\n' "$(( $(printf 1+2) * 2 ))"
"""),
        StressCase("expansion", "arithmetic command substitution expands variable name", """
B=4
printf '<%s>\\n' "$(( $(printf B) + 1 ))"
"""),
        StressCase("expansion", "arithmetic parameter invalid octal aborts", """
A=08
printf '<%s>\\n' "$(( $A + 1 ))"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "arithmetic shift operators", """
printf '<%s:%s>\\n' "$((1<<3))" "$((16>>2))"
"""),
        StressCase("expansion", "arithmetic bitwise operators", """
printf '<%s:%s:%s>\\n' "$((7&3))" "$((4|1))" "$((7^3))"
"""),
        StressCase("expansion", "arithmetic shift precedence", """
printf '<%s:%s>\\n' "$((1+2<<2))" "$((8>>1+1))"
"""),
        StressCase("expansion", "arithmetic bitwise precedence", """
printf '<%s:%s>\\n' "$((1|2&0))" "$((1^3&1))"
"""),
        StressCase("expansion", "arithmetic shift assignments", """
A=1
B=16
printf '<%s:%s:%s:%s>\\n' "$((A<<=3))" "$A" "$((B>>=2))" "$B"
"""),
        StressCase("expansion", "arithmetic bitwise assignments", """
A=7
B=7
C=4
printf '<%s:%s:%s:%s:%s:%s>\\n' "$((A&=3))" "$A" "$((B^=3))" "$B" "$((C|=1))" "$C"
"""),
        StressCase("expansion", "pathname expansion suppressed by noglob", """
> ga
> gb
set -f
for x in g?; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "default word command substitution", """
unset A
printf '<%s>\\n' "${A:-$(printf x)}"
"""),
        StressCase("expansion", "quoted default word suppresses splitting", """
unset A
B='x y'
for x in "${A:-$B}"; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "unquoted default word splits", """
unset A
B='x y'
for x in ${A:-$B}; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "nested parameter default word", """
unset A B
printf '<%s>\\n' "${A:-${B:-x}}"
"""),
        StressCase("expansion", "positional ten braced", """
set -- 1 2 3 4 5 6 7 8 9 ten
printf '<%s>\\n' "${10}"
"""),
        StressCase("expansion", "command substitution internal newlines quoted", """
X=$(printf 'a\\nb\\n')
printf '<%s>\\n' "$X"
"""),
        StressCase("expansion", "command substitution unquoted newline splitting", """
X=$(printf 'a\\nb\\n')
for x in $X; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "parameter trim path suffix", """
A=/one/two/file.txt
printf '<%s><%s>\\n' "${A%/*}" "${A##*/}"
"""),
        StressCase("expansion", "empty ifs disables splitting", """
IFS=
A='a b c'
for x in $A; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "empty quoted at produces no fields", """
set --
for x in "$@"; do
    printf X
done
printf '<%s>\\n' "$#"
"""),
        StressCase("expansion", "empty unquoted at produces no fields", """
set --
for x in $@; do
    printf X
done
printf '<%s>\\n' "$#"
"""),
        StressCase("expansion", "nounset named parameter aborts", """
set -u
printf '%s\\n' "$MISSING"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "parameter error without message", """
unset A
printf '%s\\n' "${A?}"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "colon assign treats empty as unset", """
A=
printf '<%s>' "${A:=x}"
printf '<%s>\\n' "$A"
"""),
        StressCase("expansion", "noncolon assign leaves empty set", """
A=
printf '<%s>' "${A=x}"
printf '<%s>\\n' "$A"
"""),
        StressCase("expansion", "alternate word command substitution", """
A=1
unset B
printf '<%s><%s>\\n' "${A:+$(printf yes)}" "${B:+$(printf no)}"
"""),
        StressCase("expansion", "parameter plus nested command substitution", """
A=1
printf '<%s>\\n' "${A:+$(printf 'x y')}"
"""),
        StressCase("expansion", "quoted command substitution strips only trailing newlines", """
X=$(printf 'a\\n\\nb\\n\\n')
printf '<%s>\\n' "$X"
"""),
        StressCase("expansion", "unquoted command substitution drops empty fields", """
X=$(printf 'a\\n\\nb\\n')
for x in $X; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "colon error empty parameter aborts", """
A=
printf '%s\\n' "${A:?empty}"
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("expansion", "noncolon error empty parameter does not abort", """
A=
printf '<%s>\\n' "${A?empty}"
"""),
        StressCase("expansion", "ifs whitespace trimming", """
IFS=' '
set -- '  a  b  '
for x in $1; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "ifs mixed whitespace and colon", """
IFS=' :'
set -- ' a:: b :'
for x in $1; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "quoted empty parameter preserves field", """
A=
set -- "$A" x
printf '<%s><%s>\\n' "$#" "$1"
"""),
        StressCase("expansion", "unquoted dollar star with nonwhite ifs", """
set -- 'a:b' c
IFS=:
for x in $*; do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("expansion", "script dollar zero basename", """
printf '<%s>\\n' "${0##*/}"
""", run="file"),
        StressCase("expansion", "script positional arguments", """
printf '<%s><%s><%s><%s>\\n' "${0##*/}" "$#" "$1" "$2"
""", run="file", args="one 'two words'"),
    ]
