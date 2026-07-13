# msh POSIX Shell Interpreter

`msh` is the MixtarRVS Server shell identity.

The compatibility contract is:

```text
msh = MixtarRVS SHell
language = POSIX sh
default behavior = strict POSIX-sh behavior
extensions = none by default
```

Progress is tracked in [POSIX_ROADMAP.md](POSIX_ROADMAP.md). Any future `msh`
behavior change must update that roadmap in the same patch.

The release model is intentionally split:

```text
msh-core
  useful non-interactive shell profile
  C/POSIX locale only
  byte/ASCII pathname ordering only
  no job-control or interactive-shell promise
  top-level EXIT traps, shell-side self-signal traps, and hosted native
  trapped-signal dispatch where the host runtime supports it

msh-posix-candidate
  non-interactive POSIX sh candidate
  streaming alias timing, special-builtin error policy, trap execution,
  and external conformance testing required

msh-posix-certified-profile
  documented POSIX profile with no known blockers
  eligible to become /System/Shells/msh
```

The current implementation is staged. It recognizes:

```text
simple commands
assignment words before command names
quoted words
redirections: < > >> << <<- <> <& >& >|
pipelines: |
pipeline negation: !
subshell compound commands: (...)
trailing redirections on subshell commands
brace group compound commands: { list; }
trailing redirections on brace group commands
if compound commands: if/then/elif/else/fi
loop compound commands: while/until do/done
for compound commands: for name in words; do list; done
case compound commands: case word in pattern) list ;; esac
optional leading ( before case item patterns
trailing redirections on if/while/until/for/case AST nodes
function definitions: name() compound-command
and/or lists: && ||
sequences: ;
background marker: &
comments starting with unquoted # at token boundary
backslash-newline line continuation
token source line/column metadata for diagnostics
diagnostic source-location sidecar for textual AST nodes
linebreaks after compound openers and before compound bodies
```

The current implementation also includes the first expansion/builtin slice:

```text
tilde expansion for ~ and ~/...
parameter expansion for $name and ${name}
parameter default/alternate/error operators
parameter length and shell-pattern prefix/suffix removal
special parameters $? and $$
positional parameters $1 through $9, $#, $*, $@
command substitution for $(...) and legacy backquotes through msh evaluator capture
command-substitution close scanning across nested $(...), $((...)), ${...}, and backquotes
arithmetic expansion for $((...))
arithmetic shift/bitwise operators <<, >>, &, ^, and | plus assignment operators =, +=, -=, *=, /=, %=, <<=, >>=, &=, ^=, and |= with state mutation
pathname expansion for simple * ? [] patterns and ASCII POSIX bracket classes
quote removal and IFS field splitting with whitespace/non-whitespace distinction
quote provenance for mixed quoted/unquoted words
stateful quoted `$@` and `$*` expansion
here-document body capture with quoted-delimiter expansion suppression
internal str_array field storage for expanded words
internal last-status tracking for `$?` during script evaluation
top-level `EXIT` trap execution
special/regular builtin classification
pure status builtins: :, true, false
stateful export and readonly for simple names and name=value operands
stateful set -- positional parameter replacement
cd with process cwd change plus PWD/OLDPWD updates
eval reparsing in current shell state
`.` explicit file sourcing in current shell state
function-local positional parameter scope
basic special builtin success handling: times, trap
shell option metadata through set -e/+e and set -o/+o
alias/unalias metadata storage
trap metadata storage
job table metadata storage
source stack push/pop metadata for . execution
break and continue control metadata for loops
return control metadata for functions
exit control metadata for non-interactive evaluator stop
basic set -e / +e errexit sequence enforcement
stateful unset
stateful shift
hash regular builtin for the current no-cache profile
shell-local POSIX echo regular builtin with -n, escape decoding, and \c stop behavior
```

It now executes external simple commands and external pipelines through native
argv handoff and native redirection helpers. Normal shell execution must not
fall back to host shell command-line reconstruction.

The first evaluator slice executes status-only AST safely:

```text
:
true
false
!
;
&&
||
if/then/elif/else/fi
while/until do/done
for name in words; do list; done
case word in pattern) list ;; esac
name() compound-command
groups and subshells for status propagation
case branch selection with shell patterns and | alternatives
function definition storage and simple function invocation
assignment-only commands mutate shell variables
assignment words before special builtins mutate shell variables, including
eval, set, trap, unset, shift, times, exec without a command, and
loop/function control builtins
last status feeds subsequent `$?` expansion
readonly variables reject later shell assignments
exported names are passed to native simple external commands
assignment words before native external commands are exported to the child
environment and restored in the parent shell
new shell entries default `IFS` internally while ignoring environment `IFS`
set -- replaces positional parameters
cd changes process cwd and updates PWD/OLDPWD
eval reparses and executes arguments in current shell state
`.` sources explicit files in current shell state and tracks source stack metadata
return inside an explicit sourced file exits the sourced file with that status
function calls restore caller positional parameters after return
return exits function bodies with the requested status
exit stops subsequent evaluator commands with the requested status
break/continue affect while/until/for bodies, including numeric nested-loop levels
functions override regular pure-status builtins in the current command-search
blocker probe
if branch variable changes follow shell execution rules
while/until loop condition and body state follow shell execution rules
for loop variable assignment and body state follow shell execution rules
unset removes shell variables
subshell variable changes do not escape
external simple command execution through native argv handoff
external pipeline execution through native argv handoff
compound/function pipeline status and subshell state isolation
shell-local `printf | read` pipeline dataflow proof
native redirections for < > >> << <<- <> <& >& >|
redirection-only commands create/open file targets in the current evaluator
redirection-only `exec` persists shell-local stdout/stdin for `printf`, `read`,
functions, groups, `if`, `while`, `for`, and `case`; simple native external
commands plus native external pipelines inherit that stdout/stdin metadata
here-documents feed stdin through native redirection helpers
missing explicit path commands return 127
directory command attempts return 126 before native launch or script fallback
command -- executes the currently supported builtin subset
printf covers the current POSIX string/integer/fixed-float/scientific-float
and general-float conversion slice, including standard length modifiers for
supported conversions
extensionless script files found through explicit shell PATH execute through
msh in isolated shell state, including text-script producer and consumer
pipeline stages
native process runtime exposes raw ENOEXEC for path-qualified failed execs so
msh, not libc `/bin/sh`, owns text-script fallback and bad-format rejection
non-interactive background lists spawn asynchronously through a child `msh` AST
evaluator, record real child PID/status metadata, expose `$!`, support `jobs`
polling, support `jobs -p`, `jobs %N`, and string job references in the
Linux-native probe, support `wait $!`, spawn monitor-mode simple background
commands and native external pipelines into separate process groups, deliver
`kill %pipeline` to the pipeline process group, and resume foreground jobs with
terminal process-group handoff/restoration in the Linux-native probe; terminal
Ctrl-Z on a monitor-mode foreground external command records a stopped job and
uses a SIGTTOU-guarded process-group restore to keep the shell alive, and
stopped foreground jobs can complete through both `fg` and `bg`/`wait` in the
Linux pty probe; full login-shell interactive job-control remains pending
trapped current-process signals install hosted native handlers where the
AILang runtime supports them and drain into the shell trap/status dispatcher
simulated subshell `kill $$` defers signal delivery to the parent shell trap
context, and shell-local pipeline stages run their own `EXIT` traps without
mutating the parent trap table
real-exec profile mode uses AILang process replacement for `exec cmd`, while
the normal `eval` harness keeps marker-preserving emulation for differential
tests
```

Still pending for POSIX-grade shell-script behavior:

```text
locale/collation pattern classes beyond the C/POSIX profile
POSIX equivalence classes and collating symbols
parser-native AST node span storage
streaming parse/eval for full POSIX read-unit behavior in every compound context
runtime enforcement for every shell option
full parser-stream alias substitution in every compound context
broader login-shell job control beyond the current Linux-native process-group
and stopped-job probe
complete interactive/job-control signal exit-status matrix
break/continue invalid-context diagnostics
full arbitrary fd mutation beyond the currently covered saved fd3/fd4 slices
and fd5/fd6/fd7 shell-local/native-child/mixed-pipeline duplication-chain
slice plus fd8/fd9 Linux-native process graphs and Windows-hosted logical fd
subshell-close isolation
broader mixed external-to-shell pipeline stdout/stdin dataflow
full builtin execution semantics
```

Current validation:

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Shells\msh\msh_cli.ail --check
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Shells\msh\msh_cli.ail --backend=c -O2 -o out\server\msh_cli.exe
out\server\msh_cli.exe selftest
python Server\Shells\msh\tools\msh_semantic_probe.py
python Server\Shells\msh\tools\msh_blocker_probe.py
python Server\Shells\msh\tools\msh_shell_diff.py --strict --baseline-only
python Server\Shells\msh\tools\msh_posix_suite.py --strict --baseline-only
python Server\Shells\msh\tools\msh_posix_suite.py --suite Server\Shells\msh\suites\posix-stress --strict --baseline-only
python Server\Shells\msh\tools\msh_special_builtin_matrix.py --strict
python Server\Shells\msh\tools\msh_command_search_matrix.py --strict
python Server\Shells\msh\tools\msh_fd_process_matrix.py --strict
python Server\Shells\msh\tools\msh_signal_trap_matrix.py --strict
python Server\Shells\msh\tools\msh_invocation_probe.py --msh out\server\msh_cli.exe
python Server\Shells\msh\tools\msh_smoke_gate.py --rounds 3
python Server\Shells\msh\tools\msh_finish_line.py
wsl sh -lc 'cd /mnt/c/Users/V/source/repos/MixtarRVS && python3 Server/Shells/msh/tools/msh_linux_command_search_probe.py --msh out/server/msh_cli_linux'
wsl sh -lc 'cd /mnt/c/Users/V/source/repos/MixtarRVS && python3 Server/Shells/msh/tools/msh_linux_fd_graph_probe.py --msh out/server/msh_cli_linux --strict'
```

`tools/msh_semantic_probe.py` is a focused regression gate, not a full POSIX
conformance suite. It checks the currently claimed evaluator subset and compares
status behavior against WSL `sh` when available.

`tools/msh_blocker_probe.py` is the executable hard-blocker tracker. It is
non-strict by default so open POSIX blockers remain visible without blocking
routine development.

`tools/msh_smoke_gate.py` is the fast routine gate. It performs strict AILang
checks, rebuilds Windows and WSL/Linux `msh_cli`, generates an 18-case smoke
suite from `suites/posix-core`, compares it against WSL `sh`, `bash --posix`,
and `zsh --emulate sh`, then runs the WSL performance smoke. It writes
`Server/Generated/reports/msh-smoke-gate.md` plus JSON evidence.

`tools/msh_shell_diff.py` is the WSL differential harness. The routine gate uses `--baseline-only` so WSL `/bin/sh` remains the fast source of truth. By default it checks
the POSIX-profile corpus against WSL `sh`, observes `bash --posix`, plain
`bash`, and `zsh --emulate sh`, and excludes opt-in extension cases such as C
`printf` length modifiers. Use `--include-extensions` to compare those
non-portable extensions.

`tools/msh_posix_suite.py` is the file-based POSIX suite runner. The routine gate uses `--baseline-only` for the same reason. It executes
ordinary `.sh` files from `suites/posix-core`, compares them with WSL `/bin/sh`,
and writes generated Markdown/JSON reports. It currently has 493/493 matches against WSL `/bin/sh`. This is the current gate that can
grow into imported external conformance suites without embedding cases in
Python source. Reference-shell timeout results are retried before being
reported, so transient WSL stalls do not get recorded as shell mismatches.
The finish-line runner emits trace, per-case progress, and heartbeat output by default so long WSL-backed gates no longer look silent.

`tools/msh_generate_posix_stress_suite.py` generates a broader shell-only
stress suite under `suites/posix-stress`. The suite intentionally avoids
depending on missing Mixtar userland tools such as external `sh`, `cat`, or
full GNU-style utility sets; those belong in system-layout/userland gates. The
generated stress suite currently has 259/259 WSL `/bin/sh` matches and is part
of `msh_finish_line.py`. Recent coverage includes multiline command
substitution, braced positionals beyond `$9`, heredoc backslash-newline
joining, source-fd retarget offset restoration, `errexit` AND/OR contexts,
`trap 0`, return-outside-function status/diagnostic behavior, readonly
assignment fatality around special builtins, background group/pipeline `$!`
wait behavior, and overlapping function-call redirection/body-`exec` fd
restoration. It also covers POSIX `printf` numeric character operands, star
width/precision, sign/alternate formatting, `\c` stop behavior, `read` cooked
and raw backslash-newline handling, final-variable separator preservation,
empty-input `read` status, logical/physical `cd`/`pwd` option slices,
readonly arithmetic assignment / compound-assignment abort behavior, arithmetic
shift/bitwise operators, precedence, and compound assignments, invalid
nonnumeric/octal arithmetic variable-value abort behavior, and textual
parameter/command-substitution expansion before arithmetic parsing.

`suites/posix-external-seed` is the first external-style conformance harness
seed. It uses ordinary `.sh` files and the same `tools/msh_posix_suite.py`
runner as imported suites should use later. It currently has 26/26 WSL
`/bin/sh` matches and is part of `msh_finish_line.py`. This is not a
certification corpus; it is the wired gate where larger imported POSIX
shell-language suites should land.

`tools/msh_import_smoosh_suite.py` imports a conservative allowlist from the
MIT-licensed Smoosh shell test corpus into `suites/posix-external-smoosh`.
The imported slice intentionally excludes cases that need broad POSIX userland
utilities, interactive mode, job control, or known non-POSIX behavior. It
currently has 163/163 WSL `/bin/sh` matches and is part of
`msh_finish_line.py`.
`msh_cli` also accepts POSIX-style recursive shell invocation for the covered
non-interactive profile: leading shell options before `-c`, no-operand stdin
execution, `-i` stdin execution for non-tty input, `-s` stdin execution with
positional operands, and existing path operands as shell scripts.
`tools/msh_invocation_probe.py` gates those invocation forms and is included in
the finish-line profile.
`tools/msh_interactive_probe.py` gates the current Linux pty-backed interactive
slice: expanded PS1/PS2 prompts, persistent state, EOF/EXIT-trap behavior,
continuation prompts for quotes/compound commands/pipelines, default SIGINT at
the prompt producing status 130, and trapped SIGINT at the prompt preserving
status like WSL `/bin/sh`, explicit `exit 130`, and terminal Ctrl-C
interrupting a foreground external command while keeping the shell alive with
`$?=130`, plus terminal Ctrl-\ interrupting a foreground external command
while keeping the shell alive with `$?=131`. It also covers terminal Ctrl-Z
stopping a monitor-mode foreground external command, listing the stopped job,
killing it by job reference, completing it through `fg`, and completing it
through `bg` plus `wait`. This is not yet a full interactive or job-control
claim.
The current Smoosh slice includes `$*` edge cases for empty `IFS`, embedded
unquoted `$*`, `${var=$*}` assignment-word expansion, shell-local `echo`,
and newly unlocked `command`, `eval`, `trap`, `unset`, arithmetic, tilde,
return, subshell, lexical `break`/`continue`, alias/export/source cases,
redirection/trap-inheritance slices, pattern-removal, null-IFS empty-field
suppression, dot-source `return`, export listing, signal-name `kill`,
readonly assignment failure, fatal direct `eval` parse errors, case
exit-status preservation, command-substitution newline preservation,
`errexit` carryover, heredoc escaping, redirection close/from/to behavior,
tilde separator expansion, `set -u` edge cases, external temporary
assignment export, shell startup `IFS` defaulting with environment `IFS`
ignored, `exec true`, source-state mutation, `sh -c` argument-zero behavior,
heredoc backslash expansion, quoted/unquoted tilde behavior, bracket pattern
edge cases, non-interactive expansion fatal exits, child-shell `PPID`,
background `$!` tracking for simple commands and pipelines, child-shell
non-interactive expansion error exits, and selected
expansion/parser cases. The latest import also covers sourceable `set`
quoting, noclobber `-C`, backquote/`PPID`, whitespace and non-whitespace `IFS`
splitting, colon-separated tilde expansion, missing script-file invocation
diagnostics, builtin exit-status overwrite behavior, `set -m` acceptance,
parse-error shell-file handling, background stdin isolation without job
control, quoted-adjacent globbing with host-valid names, signal kill/wait
status, async trap inheritance, wait-after-kill behavior, deterministic
background command ordering through `wait`, and `times` write-failure status
when stdout is closed by a pipeline reader.

`tools/msh_broad_smoosh_classify.py` classifies the broader non-gating Smoosh
probe. The normal no-tool-path report reruns the stale failures against current
`msh` and splits them into `4` now-fixed cases, `11` cases blocked by missing
Mixtar userland tools, and `3` job-control/interactive cases. A local discovery
run with `--msh-tool-path C:\msys64\usr\bin` exposes `5` shell-semantic
candidates after host tools are available. This keeps the next
`msh-posix-candidate` work focused on real shell behavior instead of missing
external utilities.

`tools/msh_special_builtin_matrix.py` generates a focused special-builtin
fatal/nonfatal matrix for direct, `eval`, `command`, and `command eval` paths.
It currently has 500/500 WSL `/bin/sh` matches and is part of `msh_finish_line.py`.
The matrix includes direct `A=one command <special-builtin>` assignment
side-effect suppression, direct/`eval` fatal readonly-assignment failures,
`command`/`command eval` nonfatal readonly-assignment failures, and assignment
persistence for the current POSIX special-builtin set.

`tools/msh_command_search_matrix.py` generates a hosted-safe command-search
matrix for reserved words, aliases, functions, special builtins, regular
builtins, explicit shell `PATH`, default-path lookup, explicit pathnames,
directory execution diagnostics, invalid `command` option forms, lookup
option delimiters/repetition, empty `PATH` components, unset-`PATH` source
lookup, multi-operand lookup, alias/function precedence, and missing-command
diagnostics. It currently has 170/170 WSL `/bin/sh` matches and is part of
`msh_finish_line.py`. The matrix also covers regular-builtin function
shadowing and WSL-matched rejection of special/reserved function names. The
current non-interactive profile does not implement history-editing `fc`;
lookup and execution now report it as missing instead of falling through to a
host utility.

Windows-hosted `msh_cli.exe` does not claim native execution of Linux default
utilities such as `/usr/bin/sh`; `command -p -v/-V sh` lookup is covered, while
actual `command -p sh ...` execution belongs to the Linux-native/default-path
profile and is covered by `msh_linux_command_search_probe.py`.

`tools/msh_fd_process_matrix.py` generates a hosted-safe fd/process matrix for
persistent fd metadata, compound redirections, shell-local pipelines,
left-to-right ordering, noclobber, heredocs, fd8/fd9 shell-local graphs,
compound/function/subshell fd redirections, background redirections,
redirection-only commands, read-write `<>`, pipeline builtin output/dataflow,
and redirection error cases. It currently has 157/157 WSL `/bin/sh` matches
and is part of
`msh_finish_line.py`. The matrix includes command-local input duplication
followed by retargeting the source fd, successful `<>` create/no-truncate and
shared-offset read/write behavior, command-local plus compound-command
`3<>file` restoration, pipeline output/dataflow for output-producing builtins,
single-digit fd8/fd9 heredoc duplication, command/function/group/subshell
stderr-close isolation after persistent `exec 2>&fd`, and stderr-sensitive
missing-parent plus directory redirection diagnostics, so duplicated stdin
offsets, read/write offsets, pipeline builtin output, persistent stderr
metadata restoration, and common redirection failures match WSL `/bin/sh`.

`tools/msh_signal_trap_matrix.py` generates a hosted-safe non-interactive
signal/trap matrix for `EXIT`, trap listing/reset/ignore, shell-side
self-signals, subshell `kill $$` parent-trap deferral, pipeline-stage `EXIT`
traps, command-wrapped trap/kill, diagnostic-status, `kill -l`
signal/exit-status mapping, and background wait cases. It currently has 72/72
WSL `/bin/sh` matches and is part of `msh_finish_line.py`. It does not claim
exact untrapped process-termination encoding or interactive job-control `jobs`
formatting. The separate Linux pty probe covers default/trapped SIGINT at a
prompt and terminal Ctrl-C for a foreground external command, terminal Ctrl-\
for a foreground external command, plus terminal Ctrl-Z stopped-job recovery
and `fg`/`bg` completion for a monitor-mode foreground external command. It
does compare exact normalized `kill` diagnostic bodies for the covered
missing-operand, bad-signal, illegal-pid, and invalid signal-exit-status cases.

`tools/msh_regular_builtin_matrix.py` generates a stderr-sensitive regular
builtin diagnostics matrix for `alias`, `unalias`, `cd`, `jobs`, `wait`,
`getopts`, `echo`, `printf`, `umask`, `ulimit`, `read`, `hash`, `type`,
`command`, `test`, `[`, `true`, `false`, and `kill`. It currently has
213/213 WSL `/bin/sh` matches and is part
of `msh_finish_line.py`. The current slice covers explicit-operand `getopts`,
manual `OPTIND` reset in the middle of an option cluster, invalid `OPTIND`
fatality, zero/plus/out-of-range `OPTIND` handling, grouped required
arguments, scan termination on `+` and non-option operands, `OPTARG`
preservation after end-of-scan, empty/colon-only optstrings, `read`
option-delimiter handling, repeated `-r`, readonly assignment failures,
backslash-escaped IFS delimiters, read EOF assignment including `/dev/null`,
whitespace collapse, non-whitespace `IFS` empty fields, cooked/raw
backslash-newline behavior, printf dynamic formatting,
symbolic `umask` mutation, file-size
`ulimit` query/mutation and error behavior, `test`/`[` expression diagnostics,
string length predicates, logical/grouping precedence, integer comparisons,
signed 64-bit integer boundary and overflow diagnostics, illegal `-t` operand
diagnostics, core file primaries, regular-file negative type
predicates for `-b`/`-c`/`-p`/`-S`, regular-file set-id and symlink
predicates for `-u`/`-g`/`-L`/`-h`, file identity, missing-file `-nt`/`-ot`
behavior, triple negation, empty grouped expressions, missing string operands, unknown unary/binary operators, shell-local `echo` option/escape/redirection behavior, multi-operand
`hash`, and multi-name `command -V`.

`tools/msh_linux_printf_byte_probe.py` runs inside WSL/Linux and compares raw
stdout bytes against `/bin/sh` for NUL-producing `printf` cases. It currently
has 8/8 matches and covers direct stdout, file redirection, and
shell-local-to-external pipeline handoff for byte-safe NUL output.

`tools/msh_linux_test_predicate_probe.py` is a Linux-native WSL gate for POSIX
filesystem behavior that Windows-hosted runs cannot prove. It currently has
31/31 Linux `/bin/sh` matches for character devices, block devices when
present, directories, FIFOs, Unix sockets, symlinks, dangling symlinks,
setuid/setgid mode bits, noninteractive `-t`, bracket-form predicate dispatch,
and symlink-backed `cd -L/-P` logical/physical `PWD` behavior. It is part of
`msh_finish_line.py` when WSL is healthy.

`tools/msh_linux_command_search_probe.py` is a Linux-native WSL gate for
behavior that a Windows-hosted binary cannot prove: chmod-sensitive `PATH`
lookup, only-non-executable `PATH` lookup through `command -v`, `command -V`,
and `type`, executable text-script fallback, runtime-level ENOEXEC fallback through
`command -p ./script` and `exec ./script`, executable binary garbage rejection,
text-script producer/consumer pipeline fallback, mixed shell-local to external
pipeline stdin, saved logical stdout/stdin fd3 inheritance into Linux-native
child processes, post-child saved stdin fd3 offset reconciliation after native
child reads, Linux-native fd5/fd6/fd7 child and mixed-pipeline fd-to-fd chains,
permission diagnostics/status for non-executable pipeline stages, dot-source
`PATH` lookup that skips unreadable candidates, and explicit unreadable
dot-source diagnostics. It also proves that `command -p sh -c ...` executes
through the Linux default path even when caller `PATH` is unusable.

`tools/msh_linux_fd_graph_probe.py` is a Linux-native WSL differential gate for
wider fd/process graphs. It currently has 21/21 WSL `/bin/sh` matches for fd8
and fd9 inheritance, duplicated input/output offsets, command-local and
compound redirections reaching external children, append behavior, mixed
pipeline fd chains, persistent current-stdin offset sharing through external
children, persistent here-doc stdin/fd inheritance into external children, and
subshell fd-close isolation from the parent shell.

Current probe coverage:

```text
parser accept/reject cases
status behavior compared against WSL sh when available
command output checks for supported lookup builtins
stateful parameter, positional, branch, loop, function, and subshell checks
redirection-only file open/create checks
known-gap probes that report unresolved POSIX behavior without hiding it
hard-blocker probes for alias timing, command search, EXIT traps, persistent
exec fds, and background execution; the current blocker probe has 6 closed
cases and 0 open cases
Linux-native command-search/process probes for chmod, only-non-executable
`PATH` lookup through `command -v`, `command -V`, and `type`, text-script fallback,
runtime ENOEXEC fallback, exec-format rejection, text-script pipeline fallback,
and non-tail/tail pipeline permission behavior
including saved logical stdout fd3 inheritance into external children and mixed
shell-local-to-external pipeline children plus file-backed saved logical stdin
fd3 inheritance into external children, including consumed input offsets and
post-child offset reconciliation after native child reads, plus fd5/fd6/fd7
native-child and mixed-pipeline fd-to-fd sharing
Linux-native fd graph cases for fd8/fd9 output/input sharing, append mode,
command-local and compound redirections reaching external children,
persistent current-stdin and here-doc fd inheritance into external children,
and subshell fd-close isolation
WSL shell differential cases for status, grammar, expansion, redirection,
pipelines, builtins, process behavior, and printf; the current POSIX-profile
corpus has 134/134 matches against WSL sh, and the file-based posix-core suite
has 493/493 matches against WSL sh, including normalized stderr diagnostic
cases, bad duplicated-fd redirection failures, dot-without-operand no-op behavior, dot `--` option-delimiter behavior,
`command . --` option-delimiter behavior, PATH-unset dot current-directory source lookup,
extra operands to `break`/`continue`, `trap -- action SIGNAL`, omitted-action `trap SIGNAL` / `trap -- SIGNAL`
reset behavior, `trap -l`
illegal-option handling, missing-action `trap` status-zero behavior, invalid
`trap` signal status-one behavior, `export --`, `readonly --`, `set -f --`
option/positional splitting, lone `export -` / `readonly -` bad-name
diagnostics, double-quoted ordinary backslash preservation,
double-quoted command substitution with quoted words inside the substitution,
parameter alternate/default/assignment expansion, empty-IFS and empty-field behavior,
glob no-match and byte-sorted matches, trailing compound redirections,
function positional/status behavior, and background wait/redirection cases,
`printf` raw `%s` operands versus `%b` escape decoding, `unset --`, `unset -v`, `unset -f`, combined
`unset -fv` / `unset -vf` option parsing, direct/`command`/`eval`/`command eval`
coverage for `times` extra operands, `unset -z`, `shift` extra operands, and
`trap -l`, direct/`command` extra operands for `return` and `exit`,
direct/`command`/`eval`/`command eval` `set` plain operands, `set` option-plus-operand forms,
WSL-compatible `command -v` / `command -V` combined-option precedence
options, direct special-builtin assignment persistence for `:`, `.`, `break`,
`continue`, `eval`, `exec`, `export`, `readonly`, and `return`, `command`
suppression of special-builtin assignment side effects, and `hash`
regular-builtin lookup/execution cases, combined `command -pv/-pV/-Vp` default-path lookup, invalid
`command -pz`, lone `command -` command-name behavior, `export -p` / `readonly -p` with extra operands, direct/`command`
invalid `set -o` names,
direct/`command` negative `shift` counts, direct/`command` readonly assignment
failures, ignored self-signals, numeric self-signal traps, trap-action status
preservation, trap-action `exit` control, saved logical stdout fd
duplication through fd3 after `exec >file`, saved logical stdin fd duplication
through fd3 after `exec <file`, fd5/fd6/fd7 output chains, duplicated input-fd
offset sharing through `7<&6`, plus
temporary assignment visibility through `command eval` and `command .`,
temporary assignment restoration through `command unset`, `command export`,
`command readonly`, `command :`, `command exec`, `command trap`,
`command times`, `command set`, `command shift`, `command break`,
`command continue`, `command return`, invalid `command exit`,
missing-source `command .`, regular `read` temporary assignment
visibility/restoration, external temporary-assignment export/restoration inside
command substitution, assignment-only command-substitution status plus
`errexit`, fatal direct and `eval`-wrapped special-builtin errors,
nonfatal selected `command` / `command eval` special-builtin errors,
WSL-compatible direct/`eval`/`command eval` outside-loop `break`/`continue`,
POSIX default-path `command -p -v/-V sh` lookup, and
explicit directory path lookup/execution through direct, `command`,
`command -v`, `command -V`, and `type`, current-directory permission-denied diagnostics for direct, `command`, and pipeline-stage execution, `command` alias-execution
suppression, mixed `type` missing-name status, special/reserved function-name
rejection, generated command-search matrix
coverage for 168 hosted-safe reserved-word/alias/function/builtin/PATH/default-path/explicit-path/diagnostic/function-name cases, and
pipeline output for `echo`, `printf`, `pwd`, `command -v/-V`, `type`,
`alias`, `export -p`, `readonly -p`, `set`, `umask`, `times`, `trap`,
`jobs`, `kill -l`, `ulimit`, `hash`, function/grouped `umask`, and trap
reset/preservation cases, plus
arbitrary fd open/close redirection cases, plus noclobber, force-clobber, and
noclobber special-builtin fatal/nonfatal redirection cases, special-builtin redirection failure matrix cases for `readonly`, `set`, `shift`, `times`, `trap`, and `unset`, plus `set` option side-effect cases for `+u`, `+o nounset`, `+o noglob`, `+o allexport`, `+o noclobber`, `command set -a/+a`, `command set -u/+u`, `command set -f`, `command set -C/+C`, `command set -o/+o noclobber`, `set -n`, `set -x` xtrace for default, empty, and explicit `PS4`, and `set -v` / `set -o verbose` verbose read-unit output.
The stderr-sensitive strict corpus also has 134/134 diagnostic-body
matches after normalizing shell-specific diagnostic prefixes.
```


