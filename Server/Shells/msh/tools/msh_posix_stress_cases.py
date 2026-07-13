#!/usr/bin/env python3
"""Generated POSIX stress case catalog for msh."""

from __future__ import annotations

from msh_posix_stress_builtins import builtin_cases
from msh_posix_stress_command_search import command_search_cases
from msh_posix_stress_common import StressCase, write_case
from msh_posix_stress_expansion import expansion_cases
from msh_posix_stress_grammar import grammar_cases
from msh_posix_stress_process import process_cases
from msh_posix_stress_redirections import redirection_cases


def cases() -> list[StressCase]:
    out: list[StressCase] = []
    for group in (
        grammar_cases(),
        expansion_cases(),
        builtin_cases(),
        redirection_cases(),
        process_cases(),
        command_search_cases(),
    ):
        out.extend(group)
    return out
