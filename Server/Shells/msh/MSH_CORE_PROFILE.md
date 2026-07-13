# msh-core Profile

`msh-core` is the first useful MixtarRVS shell profile. It is a
non-interactive script shell profile, not a full POSIX-conforming shell claim.

Reference target:

```text
IEEE Std 1003.1-2024 / POSIX.1-2024
The Open Group Base Specifications Issue 8
Shell Command Language
```

## Scope

`msh-core` covers:

```text
non-interactive scripts
C/POSIX locale baseline
byte/ASCII pathname ordering only
native argv/fd execution for normal external commands
native argv/fd pipeline execution
exported environment handoff for simple commands and external pipelines
stateful variables, positional parameters, functions, aliases, and core builtins
real file redirections for common command and compound-command paths
focused regression and leak validation
```

## Implemented Surface

Execution:

```text
simple external commands use native argv handoff
external pipelines use native pipe/wait handling
multi-stage external pipelines are flattened into argv/count vectors
exported variables are passed to native simple commands
exported variables are passed to native external pipeline launch paths
shell scripts found through explicit PATH are executed by msh in isolated state
shell-local right-side pipeline consumers such as read receive captured pipeline data
non-interactive background lists spawn through a child `msh` AST evaluator,
record real child PID/status metadata, expose `$!`, support `jobs` polling,
and support `wait $!`
command-invoked shell-local builtins use in-process dispatch for the current
non-interactive subset, including file redirection for output-producing builtins
saved logical stdin/stdout fd3 inheritance works for shell-local and
Linux-native child cases, including consumed file-backed input offsets and
post-child saved stdin fd3 offset reconciliation after native child reads
```

State:

```text
shell variables
exported variables
readonly enforcement for normal assignment/export/readonly paths
positional parameters and shift
function-local positional scope
subshell isolation
source-file state mutation
alias storage/list/remove
trap metadata storage/list/reset
top-level EXIT trap execution
native pending-signal hooks for trapped current-process signals where the host
runtime exposes them
```

Builtins:

```text
[
.
:
alias
break
cd
command
continue
echo
eval
exec
exit
export
false
getopts
hash
jobs
kill
printf
pwd
read
readonly
return
set
shift
test
times
trap
true
type
ulimit
umask
unalias
unset
wait
```

The above list means the builtin has a useful current implementation. It does
not mean every POSIX diagnostic, option, fatal-error rule, or interactive rule
is complete.

## Deliberate Omissions

`msh-core` does not claim:

```text
interactive shell behavior
line editing or history
history-editing fc
job control
terminal process group management
locale-aware collation
locale-aware pathname equivalence classes or collating symbols beyond the
C/POSIX single-character profile
same-read-unit POSIX alias timing
interactive/job-control signal semantics
interactive job-control semantics for background jobs
complete special-builtin fatal/non-fatal error matrix
complete command-search diagnostic matrix
complete redirection diagnostic wording
full POSIX conformance-suite pass
UNIX/POSIX certification
```

## Profile Constraints

The current profile is intentionally narrow:

```text
Locale:
  LC_ALL, LC_COLLATE, LC_CTYPE, and LANG do not change shell semantics yet.
  Pattern bracket classes are ASCII/C-locale classes.
  Pathname expansion is sorted by byte/ASCII order.
  Single-character C/POSIX equivalence classes and collating symbols are
  accepted, for example `[[=a=]]` and `[[.a.]]`.
  Locale-aware multi-character collating elements remain out of scope.

Interactivity:
  msh-core is non-interactive only.
  Prompts, line editing, history, terminal process groups, and job control are
  out of scope.

Signals and traps:
  Top-level EXIT trap execution is in scope.
  Shell-side pending signal dispatch is in scope for current-profile paths,
  including `kill -SIGNAL $$` trap delivery and default `128 + signal` status.
  Simulated subshell `kill $$` defers delivery to the parent shell trap context,
  and shell-local pipeline stages execute their own EXIT traps without mutating
  the parent trap table.
  Native OS signal hooks into that dispatcher are in scope for trapped
  current-process signals where the host runtime supports them. Interactive
  job-control signal semantics remain out of scope.

Compatibility claim:
  msh-core is POSIX-profiled, not POSIX-certified.
  It must not be advertised as a complete POSIX sh implementation.

Exec replacement:
  The normal `msh_cli eval` harness keeps an emulated exec path so comparison
  tools can parse the final `status=` marker. The real-exec profile flag uses
  AILang `process_exec_replace_argv_env_redirs`, which replaces the current
  process on POSIX hosts and falls back to run-and-return on Windows hosts.
  `msh_cli eval-real-exec` and the tranche real-exec probe cover the current
  target-status and redirection behavior.
```

## Hard Blockers Before POSIX Candidate

The next profile, `msh-posix-candidate`, must close:

```text
streaming parse/eval for exact alias timing
central POSIX error policy table
special builtin fatal/non-fatal behavior
broader signal semantics for interactive/job-control profiles
exact command-search/redirection diagnostic wording matrix
full redirection ambiguity and error semantics
broader process-graph fd inheritance
broader parser/expansion/builtin/redirection differential corpus
conformance-suite expansion beyond the starter file-based posix-core gate
```

## Validation Gate

Before claiming `msh-core` for a build, run the tranche gate:

```text
python C:\Users\V\source\repos\MixtarRVS\tools\mixtar_tranche.py
```

Then refresh the profile-gate report:

```text
python C:\Users\V\source\repos\MixtarRVS\Server\Shells\msh\tools\msh_finish_line.py
```

The finish-line report is written to:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Generated\reports\msh-finish-line.md
```

The manual equivalent is:

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Shells\msh\msh_cli.ail --check
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Shells\msh\msh_cli.ail --backend=c -O2 -o out\server\msh_cli.exe
$env:AILANG_LEAK_REPORT=1
out\server\msh_cli.exe selftest
python Server\Shells\msh\tools\msh_signal_trap_matrix.py --strict
python Server\Shells\msh\tools\msh_shell_diff.py --strict
python Server\Shells\msh\tools\msh_posix_suite.py --strict
python Server\Shells\msh\tools\msh_semantic_probe.py --msh out\server\msh_cli.exe --no-wsl
```

The POSIX suite gate writes:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Generated\reports\msh-posix-suite.md
C:\Users\V\source\repos\MixtarRVS\Server\Generated\reports\msh-posix-suite.json
```
