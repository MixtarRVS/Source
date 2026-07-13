#!/usr/bin/env python3
"""POSIX stress cases for msh."""

from __future__ import annotations

from msh_posix_stress_common import StressCase


def command_search_cases() -> list[StressCase]:
    return [
        StressCase("command-search", "function beats regular builtin type", """
type() { printf function; }
type
"""),
        StressCase("command-search", "command v sees function", """
f() { :; }
command -v f
"""),
        StressCase("command-search", "type reserved word", """
type if
"""),
        StressCase("command-search", "empty path current directory", """
printf 'printf local\\n' > localcmd
chmod +x localcmd 2>/dev/null || :
PATH=:
localcmd
"""),
        StressCase("command-search", "alias suppressed by command", """
alias true=false
command true
printf '<%s>\\n' "$?"
"""),
        StressCase("command-search", "function visible to type and command v", """
f() { :; }
type f
command -v f
"""),
    ]
