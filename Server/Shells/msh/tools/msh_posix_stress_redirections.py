#!/usr/bin/env python3
"""POSIX stress cases for msh."""

from __future__ import annotations

from msh_posix_stress_common import StressCase


def redirection_cases() -> list[StressCase]:
    return [
        StressCase("redirection", "subshell fd close isolation", """
exec 8>out
(exec 8>&-)
printf A >&8
exec 8>&-
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "fd duplicate output chain", """
exec 8>out
exec 9>&8
printf A >&9
printf B >&8
exec 9>&-
exec 8>&-
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "input duplicate shared offset", """
printf 'one\\ntwo\\n' > in
exec 8<in
exec 9<&8
read A <&8
read B <&9
printf '<%s><%s>\\n' "$A" "$B"
"""),
        StressCase("redirection", "group fd redirection reaches shell local commands", """
{ printf A >&8; printf B >&8; } 8>out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "command local input fd", """
printf 'word\\n' > in
read X <&8 8<in
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "command local input source fd retarget preserves offset", """
printf 'A\\nB\\n' > outer
printf 'I\\n' > inner
exec 3< outer
read I <&3 3< inner
read O <&3
printf '<%s:%s>\\n' "$I" "$O"
"""),
        StressCase("redirection", "brace group local input source fd retarget preserves offset", """
printf 'A\\nB\\n' > outer
printf 'I\\n' > inner
exec 3< outer
{ read I <&3 3< inner; }
read O <&3
printf '<%s:%s>\\n' "$I" "$O"
"""),
        StressCase("redirection", "left to right stderr original stdout", """
{ printf out; printf err >&2; } 2>&1 >out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "left to right stderr joins redirected stdout", """
{ printf 'out\\n'; printf 'err\\n' >&2; } >out 2>&1
exec 8<out
read A <&8
read B <&8
exec 8<&-
printf '<%s><%s>\\n' "$A" "$B"
"""),
        StressCase("redirection", "append fd preserves existing content", """
printf X > out
exec 8>>out
printf Y >&8
exec 8>&-
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "here document tab stripping", """
read X <<-EOF
	value
EOF
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "quoted heredoc suppresses expansion", """
A=value
read X <<'EOF'
$A
EOF
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "plain heredoc expands parameter", """
A=value
read X <<EOF
$A
EOF
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "heredoc command substitution expands", """
read X <<EOF
$(printf A)
EOF
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "heredoc backslash newline handling", """
read X <<EOF
a\\
b
EOF
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "function input redirection", """
printf 'word\\n' > in
f() { read X; printf '<%s>\\n' "$X"; }
f < in
"""),
        StressCase("redirection", "redirection before function call", """
f() { printf A; }
> out f
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "redirection word no field splitting", """
A='a b'
: > $A
if [ -f 'a b' ]; then
    printf ok
else
    printf bad
fi
"""),
        StressCase("redirection", "quoted redirect with spaces", """
A='x y'
: > "$A"
if [ -f 'x y' ]; then
    printf ok
else
    printf bad
fi
"""),
        StressCase("redirection", "command eval redirected output", """
command eval 'printf A' > out
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "readonly redirection failure aborts", """
readonly < missing
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("redirection", "command readonly redirection failure nonfatal", """
command readonly < missing
printf after
""", stderr="normalized"),
        StressCase("redirection", "bad input fd on regular command", """
printf ok <&9
printf after
""", stderr="normalized"),
        StressCase("redirection", "special builtin bad output fd aborts", """
: >&9
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("redirection", "command special bad output fd nonfatal", """
command : >&9
printf after
""", stderr="normalized"),
        StressCase("redirection", "eval special bad output fd aborts", """
eval ': >&9'
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("redirection", "command eval bad output fd nonfatal", """
command eval ': >&9'
printf after
""", stderr="normalized"),
        StressCase("redirection", "redirection only bad output fd nonfatal", """
>&9
printf after
""", stderr="normalized"),
        StressCase("redirection", "left to right truncates before later bad fd", """
printf old > out
: > out >&9
printf after
read X < out
printf '<%s>\\n' "$X"
""", stderr="normalized", status="nonzero"),
        StressCase("redirection", "command left to right truncates before bad fd", """
printf old > out
command : > out >&9
printf after
read X < out
printf '<%s>\\n' "$X"
""", stderr="normalized"),
        StressCase("redirection", "closed output fd regular command nonfatal", """
exec 8>out
exec 8>&-
printf A >&8
printf after
""", stderr="normalized"),
        StressCase("redirection", "closed output fd special aborts", """
exec 8>out
exec 8>&-
: >&8
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("redirection", "nonnumeric output fd syntax aborts", """
: >&bad
printf after
""", stderr="normalized", status="nonzero"),
        StressCase("redirection", "command nonnumeric output fd nonfatal", """
command : >&bad
printf after
""", stderr="normalized"),
        StressCase("redirection", "group exec fd close persists", """
exec 8>out
{ exec 8>&-; }
printf A >&8
printf after
""", stderr="normalized"),
        StressCase("redirection", "function exec fd open persists", """
f() { exec 8>out; }
f
printf A >&8
exec 8>&-
read X < out
printf '<%s>\\n' "$X"
"""),
        StressCase("redirection", "function redirection restores exec fd inside", """
f() { exec 8>inner; printf I >&8; }
f 8>temp
printf O >&8
exec 8>&-
read A < inner
read B < temp
printf '<%s:%s>\\n' "$A" "$B"
""", stderr="normalized"),
        StressCase("redirection", "exec duplicate stdout before retarget", """
exec 8>&1
printf A >&8 >out
read X < out
printf '<%s>\\n' "$X"
"""),
    ]
