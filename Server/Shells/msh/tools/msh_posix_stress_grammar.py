#!/usr/bin/env python3
"""POSIX stress cases for msh."""

from __future__ import annotations

from msh_posix_stress_common import StressCase


def grammar_cases() -> list[StressCase]:
    return [
        StressCase("grammar", "nested if in while with break", """
i=0
while true; do
    i=$((i + 1))
    if [ "$i" -eq 2 ]; then
        printf done
        break
    fi
done
"""),
        StressCase("grammar", "case with fallthrough-like alternatives", """
for v in ax by cz; do
    case "$v" in
        a*|b*) printf X;;
        *) printf Z;;
    esac
done
"""),
        StressCase("grammar", "function with nested group and subshell", """
f() {
    { printf A; (printf B); printf C; }
}
f
"""),
        StressCase("grammar", "function definition newline before body", """
f()
{
    printf ok
}
f
"""),
        StressCase("grammar", "nested function definition execution", """
f() { g() { printf inner; }; g; }
f
"""),
        StressCase("grammar", "case leading paren multiple patterns", """
case b in
    (a|b) printf match;;
    (*) printf miss;;
esac
"""),
        StressCase("grammar", "case empty pattern list miss", """
case x in
    '') printf empty;;
    x) printf x;;
esac
"""),
        StressCase("grammar", "for no in iterates positionals", """
set -- a b
for x do
    printf '<%s>' "$x"
done
printf '\\n'
"""),
        StressCase("grammar", "for explicit empty list", """
for x in; do
    printf bad
done
printf ok
"""),
        StressCase("grammar", "pipeline negation with group", """
! { false; } | true
printf '<%s>\\n' "$?"
"""),
        StressCase("grammar", "compound redirection around case", """
case x in
    x) printf A;;
esac > out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("grammar", "linebreaks before then do and in", """
if
    true
then
    for x
    in a b
    do
        printf "$x"
    done
fi
"""),
        StressCase("grammar", "function implicit for over arguments", """
set -- ax by
f() {
    for x
    do
        case "$x" in
            a*) printf A;;
            b*) printf B;;
        esac
    done
}
f "$@"
"""),
        StressCase("grammar", "until loop continue inside if", """
i=0
until [ "$i" -ge 3 ]; do
    i=$((i + 1))
    if [ "$i" -eq 2 ]; then
        continue
    fi
    printf "$i"
done
"""),
        StressCase("grammar", "function call redirection", """
f() { printf A; }
f > out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("grammar", "redirection before command name", """
> out printf A
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("grammar", "function return in conditional", """
f() { return 4; }
if f; then
    printf bad
else
    printf '<%s>\\n' "$?"
fi
"""),
        StressCase("grammar", "alias same read unit not active", """
alias hi='printf bad'; hi
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias before function body active", """
alias hi='printf ok'
f() { hi; }
f
"""),
        StressCase("grammar", "nested case inside function loop", """
f() {
    for x in "$@"; do
        case "$x" in
            a*) printf A;;
            b*) printf B;;
            *) printf Z;;
        esac
    done
}
f ax by cz
"""),
        StressCase("grammar", "case action after pattern newline", """
case x in
    x)
        printf match;;
esac
"""),
        StressCase("grammar", "alias before if body active", """
alias hi='printf ok'
if true; then
    hi
fi
"""),
        StressCase("grammar", "alias inside if body not active same compound", """
if true; then
    alias hi='printf ok'
    hi
fi
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias before for body active", """
alias hi='printf ok'
for x in 1; do
    hi
done
"""),
        StressCase("grammar", "alias before single line for body active", """
alias hi='printf ok'
for x in 1; do hi; done
"""),
        StressCase("grammar", "alias inside for body not active same compound", """
for x in 1; do
    alias hi='printf ok'
    hi
done
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias reserved then not expanded", """
alias then='printf bad'
if true; then printf ok; fi
"""),
        StressCase("grammar", "alias condition after if active", """
alias yes='true'
if yes; then printf ok; fi
"""),
        StressCase("grammar", "alias after bang active", """
alias no='false'
! no
printf ':'
printf "$?"
"""),
        StressCase("grammar", "alias before case action active", """
alias hi='printf ok'
case x in
    x) hi;;
esac
"""),
        StressCase("grammar", "alias inside case action not active same compound", """
case x in
    x) alias hi='printf ok'; hi;;
esac
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias after heredoc read unit active", """
alias hi='printf ok'
read X <<EOF
x
EOF
hi
"""),
        StressCase("grammar", "alias in function body defined inside function not active", """
f() { alias hi='printf ok'; hi; }
f
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias before while body active", """
alias hi='printf ok'
while true; do
    hi
    break
done
"""),
        StressCase("grammar", "alias inside while body not active", """
while true; do
    alias hi='printf ok'
    hi
    break
done
""", stderr="normalized"),
        StressCase("grammar", "alias before until body active", """
alias hi='printf ok'
until false; do
    hi
    break
done
"""),
        StressCase("grammar", "alias inside until body not active", """
until false; do
    alias hi='printf ok'
    hi
    break
done
""", stderr="normalized"),
        StressCase("grammar", "alias before group body active", """
alias hi='printf ok'
{ hi; }
"""),
        StressCase("grammar", "alias inside group body not active", """
{ alias hi='printf ok'; hi; }
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias before subshell body active", """
alias hi='printf ok'
( hi )
"""),
        StressCase("grammar", "alias inside subshell body not active", """
( alias hi='printf ok'; hi )
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias after andor same read unit inactive", """
alias hi='printf bad' && hi
""", stderr="normalized", status="nonzero"),
        StressCase("grammar", "alias after newline andor active", """
alias hi='printf ok'
true && hi
"""),
        StressCase("grammar", "while compound input redirection", """
printf 'a\\nb\\n' > in
while read X; do
    printf '<%s>' "$X"
done < in
printf '\\n'
"""),
        StressCase("grammar", "while redirection preserves variable after loop", """
printf 'a\\nb\\n' > in
last=
while read x; do
    last=$x
done < in
printf '<%s>\\n' "$last"
"""),
        StressCase("grammar", "until compound output redirection", """
i=0
until [ "$i" -ge 2 ]; do
    i=$((i+1))
    printf "$i"
done > out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("grammar", "if elif newline parsing", """
if false
then
    printf bad
elif true
then
    printf ok
else
    printf bad
fi
"""),
        StressCase("grammar", "and or newline continuation", """
false ||
printf ok
true &&
printf done
"""),
        StressCase("grammar", "case esac redirection append", """
printf old > out
case x in
    x) printf new;;
esac >> out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("grammar", "nested function while case", """
f() {
    while [ $# -gt 0 ]; do
        case "$1" in
            a) printf A;;
            b) printf B;;
        esac
        shift
    done
}
f a b
"""),
        StressCase("grammar", "brace group after newline redirection", """
{
    printf A
    printf B
} > out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("grammar", "subshell redirection preserves parent state", """
X=outer
( X=inner; printf "$X" > out )
printf '<%s:' "$X"
read Y < out
printf '%s>\\n' "$Y"
"""),
        StressCase("grammar", "for linebreak before do no in", """
set -- a b
for x
do
    printf "$x"
done
"""),
        StressCase("grammar", "empty compound branch", """
if true; then :; else :; fi
while false; do :; done
until true; do :; done
printf ok
"""),
        StressCase("grammar", "case newline before esac", """
case x in
    x) printf ok;;

esac
"""),
    ]
