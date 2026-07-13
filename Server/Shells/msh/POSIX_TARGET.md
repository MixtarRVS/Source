# msh POSIX Target

Reference target:

```text
IEEE Std 1003.1-2024 / POSIX.1-2024
The Open Group Base Specifications Issue 8
Shell and Utilities, Chapter 2: Shell Command Language
```

Primary references:

```text
https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html
https://pubs.opengroup.org/onlinepubs/9799919799/utilities/contents.html
https://www.unix.org/overview.html
```

The current implementation is not a complete conforming shell. It is a staged
native implementation whose behavior must be tested against POSIX.1-2024 before
being promoted to `/System/Shells/msh`.

The release model has three gates:

```text
msh-core = useful non-interactive script shell, C/POSIX locale profile,
           no job control or interactive promise.
msh-posix-candidate = serious POSIX sh candidate with streaming alias timing,
                      special-builtin error policy, trap execution, and
                      external conformance testing.
msh-posix-certified-profile = no known blockers for the documented POSIX
                              profile and eligible for /System/Shells/msh.
```

Current development targets `msh-core` first. Hard POSIX blockers such as
locale collation, full read-unit/source-stream evaluation, full special-builtin
fatal semantics, full signal/job-control semantics for interactive profiles,
and interactive job control remain blockers for the later gates, not reasons
to hide completed non-interactive work.

The completion checklist is maintained in [POSIX_ROADMAP.md](POSIX_ROADMAP.md).
Implementation patches must update that roadmap when they add or change shell
behavior.

The exact first shipping profile is documented in
[MSH_CORE_PROFILE.md](MSH_CORE_PROFILE.md). It lists the non-interactive
`msh-core` scope, validation gate, and deliberate omissions before any broader
POSIX claim.

The currently claimed profile is constrained:

```text
locale = C/POSIX only
pathname sorting = byte/ASCII order
equivalence/collating symbols = C-locale single-character support only
interactive shell behavior = not claimed
job control and terminal process groups = not claimed
trap delivery = EXIT, shell-side self-signal traps, and hosted native trapped signals
signal exit-status rules = shell-side and child-wait profile only
certification = not claimed
```

Correctness is checked through `msh_cli.exe selftest` plus the focused
`tools/msh_semantic_probe.py` regression gate. The probe compares selected
status behavior against WSL `sh` when available; it is deliberately not treated
as a POSIX conformance suite. It also reports known open gaps so partial POSIX
behavior is visible during routine checks.

Hard POSIX blockers are tracked by `tools/msh_blocker_probe.py`. That probe is
allowed to report open blockers without failing the normal gate unless it is
run with `--strict`.

Current hard-blocker probe status is 6 closed / 0 open for the tracked hard
blockers. The WSL differential harness uses `wsl.exe --exec` so shell variables
inside the reference script are preserved correctly.

## Current Implemented Surface

Parser:

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

Expansion:

```text
tilde expansion for ~ and ~/...
parameter expansion for $name and ${name}
parameter operators: -, :-, =, :=, ?, :?, +, :+
parameter length: ${#name}
pattern prefix/suffix removal: ${name#word}, ${name##word}, ${name%word}, ${name%%word}
special parameter $? for previous status
special parameter $$ for current process id
special parameter $! for the last recorded non-interactive background job id
positional parameters: $1 through $9, $#, $*, $@
command substitution for $(...) and legacy backquotes through msh evaluator capture
command-substitution close scanning skips nested $(...), $((...)), ${...}, and backquotes
command substitution inherits shell state without delegating to a hosted shell
arithmetic expansion for $((...)) with + - * / %, parentheses, and local variables
arithmetic assignment operators =, +=, -=, *=, /=, and %= mutate shell variables
arithmetic prefix/postfix ++/-- and comma expressions exist only as explicit
extension-profile behavior, not as part of the strict WSL sh baseline
pathname expansion/globbing for simple current-directory and dir/pattern cases
pathname matches are sorted in byte/ASCII order as the current portable baseline
quote removal for single quotes, double quotes, and backslash escapes
IFS field splitting distinguishes whitespace IFS from non-whitespace delimiters
quote provenance is carried through WORD payloads into expansion/execution
quoted/literal execution words suppress field splitting where quote provenance is available
quoted `$@` and `$*` use quote provenance in stateful expansion, including prefix/suffix mixed words
here-document delimiter quote state controls whether the captured body is expanded
internal str_array field storage for expanded words
host getenv fallback for missing local shell variables
${name:=word} and ${name=word} mutate shell state during command evaluation
${name:?word} and ${name?word} stop command evaluation with status 2
last status is tracked internally so `$?` reflects prior evaluator status
```

Builtin classification:

```text
special builtins
regular builtins
external command fallback
```

Pure status builtins:

```text
:
true
false
times
trap
unset
```

Stateful special builtins in the current slice:

```text
export marks names as exported and supports name=value operands
readonly marks names as readonly and supports name=value operands
set -- replaces positional parameters
readonly variables reject later shell assignment attempts
exported names are tracked internally and passed to native simple external commands
exported names are passed through native external pipeline launch paths
function calls receive local positional parameters and restore caller `$@` afterward
functions override regular pure-status builtins in the current executable
blocker-probed command-search slice
export -p and readonly -p print marked variables, including marked-but-unset
names, with sorted re-input-safe C/POSIX-profile quoting
alias can define, query, list, remove one alias, and remove all aliases with
unalias -a
newline-delimited alias definitions activate for following read units, and the
covered compound read-unit slice keeps aliases defined inside the same `if`,
`for`, `case`, or function body inactive until later units; full streaming alias
timing is pending
trap can store, reset, list trap metadata, execute top-level `EXIT` traps,
dispatch shell-side self-signal traps, and drain hosted native trapped signals
where the host runtime supports it; interactive/job-control signal delivery is
not claimed. Simulated subshell `kill $$` defers to the parent shell trap
context, and shell-local pipeline stages execute their own `EXIT` traps without
leaking trap mutations to the parent.
```

## Required But Not Complete

Expansion order:

```text
tilde expansion
parameter expansion
command substitution
arithmetic expansion
field splitting
pathname expansion
quote removal
```

Current limitation:

```text
the `fields` CLI display still joins expanded fields with `|`, but execution
consumes internal str_array field storage
pathname expansion handles simple directory enumeration, byte/ASCII sorting,
ASCII bracket classes, and C-locale single-character equivalence/collating
symbols; complete locale collation remains out of scope
quote provenance is implemented for the current stateful expansion path; the
remaining expansion gaps are full locale collation and broader conformance
corpus coverage
```

Shell state:

```text
variables
positional parameters
readonly variables
exported environment flags
aliases
functions
options, including covered `set -x` xtrace and `set -v` / `set -o verbose` verbose output
traps
jobs
current working directory
```

Execution:

```text
redirection ordering
pipeline process model
subshells
functions
special builtin error rules
command search
script execution
interactive mode
```

Current execution slice:

```text
status-only interpreter for :, true, false
status propagation for !, ;, &&, ||, if, while, until, for, groups, and subshells
case branch selection with shell patterns and | alternatives
function definition storage and simple function invocation
assignment-only commands mutate shell variables
assignment words before special builtins mutate shell variables, including
eval, set, trap, unset, shift, times, exec without a command, and
loop/function control builtins in the current non-interactive profile
last status is carried through evaluator state for subsequent `$?` expansion
readonly assignments fail without changing the variable
export and readonly consume simple operands and name=value operands
set -- replaces positional parameters
cd changes the process working directory, updates PWD/OLDPWD, supports HOME,
cd -, option parsing for -L/-P, CDPATH search, pipe-aware printed path output,
and Linux-native logical/physical symlink behavior
eval reparses and executes its arguments in the current shell state
`.` sources an explicit file path in the current shell state
`.` searches explicit shell `PATH` when the source operand has no slash
source/script file text is normalized for CRLF before parser entry in the
current Windows-hosted profile
sourced control-flow diagnostics can include source path context
if branch variable changes follow shell execution rules
while/until loop condition and body state follow shell execution rules
for loop variable assignment and body state follow shell execution rules
unset removes shell variables
unset refuses readonly variables
shift mutates positional parameters, including numeric shift counts
subshell variable changes do not escape
external simple command execution through native argv handoff
external command pipelines use native process/pipe/wait handling
compound/function pipelines have status and subshell state-isolation semantics
shell-local compound pipeline dataflow supports the current `printf | read`
proof without leaking right-side variable changes
multi-stage external pipelines are flattened into native argv vectors
missing explicit path commands return 127
native redirections are applied in recorded order for <, >, >>, <>, <&, >&, >|
redirection targets are checked after expansion; zero or multiple resulting
fields are rejected with status 2 before command execution
here-documents << and <<- are captured by the lexer and fed through stdin
read supports redirected stdin, `-r`, multiple variable assignment, IFS-based
tail preservation for the last variable, invalid operand checks, and default
backslash escape/continuation processing in the current non-interactive slice
pwd is shell-local, emits the current directory, accepts `-L`/`-P`/`--`,
reports invalid options, and participates in pipe capture plus file redirection
the `command` utility supports command, command --, and command -v/-V lookup
the `command` utility accepts the current `-p` option parse path
command -- executes the currently supported builtin subset instead of treating
those names as external commands
nested `command command ...` and `command type ...` dispatch through the
current shell-local implementations
command-invoked stateful builtins are covered for alias, unalias, export,
readonly, set, unset, shift, wait, umask, ulimit, cd, pwd, printf, read,
times, and trap in the current non-interactive slice
command eval, command ., and current-profile command exec dispatch through
shell-local stateful paths
assignment words before command eval and command . are temporary around the
command utility while remaining visible to the invoked eval body or sourced file
assignment words before other command-dispatched utilities are temporary around
the command utility, including value and export/readonly attribute restoration
after command unset, command export, command readonly, command set, command
shift, command break, command continue, command return, invalid command exit,
and missing-source command .
command-invoked output builtins honor file redirections in the current slice
echo is shell-local in the current WSL `/bin/sh` profile and covers no-operand
newline output, operand joining, `-n`, backslash escape decoding, octal
escapes, `\c` stop behavior, literal `-e`/`--` operands, and redirected output
printf supports the current string, integer, fixed-float, scientific-float,
and general-float conversion slice, including `%e`, `%E`, `%g`, `%G`, and
standard length modifiers for the currently supported conversions. Byte-safe
NUL output from shell-local `printf` is covered for direct stdout,
redirections, and shell-local-to-external pipelines by the Linux-native
printf byte probe.
test/[ supports the covered core string, string-length, integer-comparison,
file-existence, regular-file, directory, file-size, regular-file negative
`-b`/`-c`/`-p`/`-S` type predicates, regular-file `-u`/`-g`/`-L`/`-h`
predicates, file-identity, missing-file `-nt`/`-ot`, grouping, negation,
`-a`/`-o`, invalid-integer, missing-bracket, and unexpected-operator slices
against WSL `/bin/sh`
extension-agnostic text script candidates found through explicit shell `PATH`
or explicit paths execute through `msh` in isolated shell state and return
their script status; script candidates in pipelines are treated as shell-local
stages so producer and consumer scripts are evaluated by `msh`
set no-operand output prints shell variables with sorted re-input-safe
C/POSIX-profile quoting
set option metadata, alias/unalias metadata, trap metadata, job table metadata,
and . source-stack metadata exist for stateful shell execution
umask supports octal masks, symbolic output, core symbolic rwx operands, and
u/g/o permission-copy operands in the current shell-state model
ulimit supports the non-interactive file-size limit slice: query, -f/-H/-S
option parsing, numeric/unlimited mutation, invalid-option/invalid-number
diagnostics, and raise-failure behavior in shell state
history-editing fc is not part of the current non-interactive profile; lookup
and execution report it as missing so Windows-hosted runs cannot leak to a host
fc utility
top-level `EXIT` trap execution is covered by selftest and blocker probe
break/continue/return/exit use internal shell control metadata in the current
non-interactive evaluator slice, including numeric nested-loop break/continue
levels
redirection-only commands create/open file targets for the common file
redirection forms
redirection-only `exec` persists shell-local stdout metadata for `printf` and
stdin metadata for `read`, and simple native external commands inherit that
metadata; native external pipelines inherit stdin on the first stage and
stdout on the final stage. Saved logical stdin/stdout fd3 inheritance is
covered for shell-local and Linux-native child cases, including consumed
file-backed input offsets and post-child saved stdin fd3 offset reconciliation
after native child reads. Shell-local arbitrary fd output open/close and input
close behavior are covered for `exec 3>file`, `>&3`, `3>&-`, and `3<&-`.
Shell-local and Linux-native child/pipeline fd5/fd6/fd7 output chains and
duplicated input-fd offset sharing through `7<&6` are covered against WSL
`/bin/sh`.
Linux-native filesystem behavior is covered against WSL `/bin/sh` for
`test`/`[` file-type predicates on character devices, block devices when
present, directories, FIFOs, Unix sockets, symlinks, setuid/setgid mode bits,
noninteractive `-t`, and symlink-backed `cd -L/-P` logical/physical `PWD`.
Broader compound/process-graph fd inheritance remains pending
real-exec profile mode uses AILang process replacement for `exec cmd`; the
normal `eval` harness intentionally keeps marker-preserving emulation for WSL
differential tooling
non-interactive background lists spawn asynchronously through a child `msh` AST
evaluator, record real child PID/status metadata, expose `$!`, support `jobs`
polling, and support `wait $!`; interactive job-control remains pending
function-over-regular-builtin command search is covered by the executable
blocker probe
```

Current native execution limitation:

```text
compound/function pipeline stdout/stdin dataflow is partially wired but the
hosted-safe builtin-output slice is now WSL-matched. Shell-local `printf |
read` dataflow is implemented. Native external commands
and extensionless text shell scripts inside groups/functions can feed
shell-local right-side consumers such as `read`, and shell-local producers can
feed external right-side commands such as `printf hello | grep hello`.
Explicit right-side stdin redirections override pipeline stdin through normal
left-to-right redirection ordering. Common output-producing builtins (`cd`
printed path output, `command -v/-V`, `alias`, `set`,
`export -p`, `readonly -p`, `trap`, `pwd`, `echo`, `printf`, `type`,
`umask`, `times`, `jobs`, `kill -l`, `ulimit`, and `hash`)
are pipe-aware in the current baseline. Remaining gaps are mostly nested or
external process-graph edge cases rather than ordinary builtin output.
```

Current script execution limitation:

```text
Extension-agnostic script resolution is limited to explicit shell `PATH` and
explicit paths, and candidates must pass a text-file sanity check so host or
Mixtar binaries are not accidentally parsed as shell text. The AILang process
runtime now exposes failed-exec errno so `msh` can identify ENOEXEC, ENOENT,
EACCES, and EPERM rather than guessing from status 127 alone. On POSIX targets,
path-qualified argv0 uses raw `execv` instead of libc `execvp` shell fallback,
so `msh` decides whether ENOEXEC is a text script to run or executable binary
garbage to reject with status 126 and an exec-format diagnostic. The same errno
path is now used for native pipeline tail commands, so a non-executable final
pipeline stage can be classified as status 126 instead of a generic 127.
Existing directory paths are rejected before text-file probing or native
process launch, so `./directory` reports permission denied instead of being
treated as a script candidate.
```

Current pattern limitation:

```text
shell patterns support *, ?, bracket classes, ! bracket negation, and simple
ranges. ASCII POSIX bracket classes such as [[:alpha:]], [[:digit:]],
[[:alnum:]], [[:space:]], [[:blank:]], [[:upper:]], [[:lower:]], and
[[:xdigit:]] are implemented. C-locale single-character `[[=x=]]` and
`[[.x.]]` forms are implemented. Full locale/collation behavior is pending.
```

Current differential testing rule:

```text
`tools/msh_shell_diff.py --strict` is a POSIX-profile discovery gate against
WSL `sh`. The same run observes `bash --posix`, plain `bash`, and
`zsh --emulate sh` so practical shell behavior remains visible. Extension
cases are opt-in with `--include-extensions` and must not be used to claim
baseline POSIX compatibility.
```

## Implementation Rule

`msh` is the MixtarRVS SHell interpreter for POSIX sh. It is not a separate
shell language. Extensions are not enabled by default and must never change
standard POSIX sh behavior.
