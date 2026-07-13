# msh POSIX Roadmap

This is the living checklist for making `msh` a POSIX `sh` implementation.
Every feature patch that changes parser, expansion, execution, builtin, or
state behavior must update this file in the same change.

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
```

## Status Legend

```text
[x] implemented and covered by msh selftest or external regression test
[/] partially implemented; usable, but known semantic gaps remain
[ ] not implemented yet
[?] needs verification against POSIX text or a conformance suite
```

## Current Estimate

```text
Rough overall POSIX shell completion: 78-82%
Usable non-interactive shell subset: 90-94%
Certifiable POSIX-sh readiness: 55-60%
```

The gap is mostly semantic exactness, not syntax volume.

## Current Profile Gate

The current practical checkpoint is `msh-core`: a non-interactive,
C/POSIX-locale shell profile for Mixtar boot scripts, userland scripts, and
early system integration. This is not the final shell finish line and must not
be read as a full POSIX `sh` claim.

Current gate evidence:

- latest finish-line gate: `msh-core PASS`
- reference mode: `wsl` using `wsl-sh`
- WSL preflight is currently healthy after resetting the stuck WSL client
  processes
- WSL-native shell-diff refresh uses `tools/msh_wsl_shell_diff.sh` from inside
  one WSL process against WSL `sh`, `bash --posix`, `bash`, and
  `zsh --emulate sh`
- latest WSL-native shell-diff result against Linux ELF `out/server/msh_cli`:
  WSL `sh` `134/134`, `bash --posix` `123/134`, `bash` `117/134`,
  `zsh --emulate sh` `123/134`
- latest finish-line refresh ran the bounded no-rebuild gate with
  `--command-timeout 180` and `--max-seconds 1200` after rebuilding both the
  Windows and WSL/Linux `msh_cli` binaries separately
- strict reference shell functional diff (`wsl-sh`): `134/134`
- file-based POSIX core suite: `493/493`
- generated POSIX stress suite: `261/261`
- external-style POSIX seed suite: `26/26`
- imported Smoosh POSIX slice: `163/163`
- tools-backed broad Smoosh slice: `175/175` using Linux `msh` in WSL with
  `Server/Userland/Generated/targets/linux-x64/bin` prepended to `PATH`
- additional current-reference Smoosh probe: `10/10` against WSL `/bin/sh`,
  covering `exec true`, external temporary-assignment export,
  shell startup `IFS` defaulting with environment `IFS` ignored, readonly
  assignment failure, parse-error recovery, `source` state mutation,
  `sh -c` `$0`, heredoc backslash expansion, quoted/unquoted tilde cases,
  bracket pattern edge cases, `errexit` carryover, non-interactive expansion
  exits, duplicated-fd close errors, tilde assignment separators, async trap
  inheritance/ignore behavior, and `set -u` arithmetic/parameter edge cases
- POSIX-style shell invocation now accepts leading shell options before `-c`,
  executes command text from stdin for no-operand shells, supports `-i` stdin
  execution without prompts in non-tty input, supports a Linux pty-backed
  interactive loop with PS1/PS2 prompts, persistent state, EOF handling, EXIT
  trap delivery, quote continuation, compound-command continuation, and
  pipeline continuation, supports `-s` stdin execution with positional
  operands, and treats any existing path operand as a script file, not only
  `.sh` names
- generated special-builtin matrix: `771/771`
- generated command-search matrix: `170/170`
- generated fd/process matrix: `169/169`
- POSIX Issue 8 multi-digit fd matrix: `8/8` against WSL `bash --posix`
- generated signal/trap matrix: `72/72`
- generated regular-builtin matrix: `233/233`
- Linux-native filesystem/profile probe: `31/31`
- Linux-native printf byte probe: `8/8`
- Linux-native stopped/continued job-control probe: `12/12`
- Linux-native fd graph probe: `21/21`
- Linux-native arbitrary-fd/process matrix: `143/143` against WSL
  `bash --posix`
- Linux-native signal/wait matrix: `78/78` against WSL `/bin/sh`
- Linux-native interactive pty probe: `14/14`
- extension-inclusive reference diff (`wsl-sh`): `140/140`
- stderr-sensitive reference diff (`wsl-sh`): `134/134`
- semantic probe: parser `11`, status `53`, output `117`, diagnostic `55`,
  state `129`, redirection-only `15`
- latest compatibility fixes covered by semantic/Smoosh/Linux-native gates:
  unreadable explicit dot-source files now fail safely with status `2` and
  `Permission denied`, dot-source `PATH` lookup skips unreadable candidates and
  continues to later readable candidates, real symlink-backed `test` predicates
  match WSL `/bin/sh`, and shell-local builtin output inside command
  substitution now respects stdout/stderr fd routing including indirect
  `2>&1` capture; the imported
  Smoosh gate now also covers sourceable `set` quoting, noclobber `-C`,
  backquote/`PPID` behavior, whitespace-IFS command substitution, non-whitespace
  IFS splitting, colon-separated tilde expansion, missing script-file
  invocation diagnostics, shell builtin exit-status overwrite behavior,
  `set -m` acceptance, parse-error shell-file handling, background stdin isolation without job control including direct external `cmd &` spawned after persistent `exec <file`, quoted-adjacent globbing with host-valid names,
  deterministic background command ordering through `wait`, signal kill/wait
  status, async trap inheritance, wait-after-kill behavior, `kill -0`
  no-such-process status `1`, and `times` write-failure status when stdout is closed by a pipeline reader,
  path-invariant `cd`/`pwd`/`PWD` consistency, broad shell-escaping quote
  cases without external utility dependencies, and command/function/group
  stderr-close isolation after persistent `exec 2>&fd`; Linux/WSL stdio save
  fds are now kept above the user-visible fd range so compound redirections
  such as `{ ...; } 4>out` cannot overwrite internal saved stdout/stderr;
  Linux-native `fd<>file` metadata now preserves shared read/write offsets for
  shell-local reads followed by shell-local writes, including duplicated
  read/write fds; shell-local pipeline finalization now skips empty persistent
  stdout writes and uses fd-state-aware writes, so a mixed pipeline child using
  a saved logical stdout fd such as `exec >out; exec 3>&1; ... >&3` cannot have
  its output erased by an empty captured pipeline flush; native external
  pipeline preflight now models a failed non-tail stage as EOF into the tail
  command, matching WSL `/bin/sh` for fallback cases such as missing-command
  pipeline stages in `||` lists; simple-command preflight diagnostics for
  missing commands now obey command-local stderr redirections including
  `2>file`, `2>&1`, `2>&-`, and command-substitution capture ordering
- hard blocker probe: `6 closed / 0 open`
- real exec probe: `PASS`
- command-search probe: `PASS`
- Linux-native command-search diagnostic matrix: `18/18` against WSL reference
  shells (`/bin/sh` for dash-compatible cases, `bash --posix` for POSIX
  dot-source readable-`PATH` search)
- Linux-native redirection diagnostic matrix: `92/92` against WSL `/bin/sh`
- Linux-native arbitrary-fd/process matrix: `143/143` against WSL
  `bash --posix`, covering fd `3..12` and `19` inheritance, duplication,
  close isolation, command-local/group/pipeline redirection, append, input
  offsets, heredoc-backed fds, and read/write `<>` shared-offset cases
- Linux-native signal/wait matrix: `78/78` against WSL `/bin/sh`, covering
  signaled-child wait status, repeated waits, `wait` after kill, `kill -0`
  live/dead PID behavior, unknown-pid wait status, multi-operand wait status,
  mixed background-child wait ordering, no-child and invalid-pid `wait`
  status, explicit child exit statuses, no-operand `wait` status retention,
  kill option forms, missing/invalid kill operands, stable async `INT`/`QUIT`
  ignore behavior after background-job startup, async-list status,
  `$!` refresh behavior, self-signal traps for `TERM`, `INT`, `HUP`, `QUIT`, and `USR1`,
  ignored self-signals for `TERM`, `INT`, `HUP`, `QUIT`, and `USR1`, and
  real `-c` invocation plus script-file invocation termination for `TERM`,
  `INT`, `HUP`, `QUIT`, and `USR1`, ignored self-signal behavior for those
  signals, and `EXIT` trap behavior after `trap -` reset, ignored traps,
  numeric `kill` operands, or trap action status preservation
- shell invocation probe: `PASS`
- leak selftest: `PASS`
- 800-line guard: `PASS`
- `msh_finish_line.py` now gates generated matrix tools against WSL `/bin/sh`
  when WSL is healthy, rebuilds the Linux-native `msh` ELF, and gates POSIX
  `test` file-type predicates, `cd -L/-P` symlink behavior, dot-source
  readability behavior, and Linux-native stopped/continued job-control
  behavior, the 175-case tools-backed broad Smoosh slice, plus the generated Linux
  arbitrary-fd/process and signal/wait matrices, that
  Windows-hosted runs cannot prove; local fallback is kept only as an
  emergency host mode. The latest bounded refresh used `--no-build --command-timeout 180 --max-seconds 1200` after separate Windows and WSL/Linux rebuilds.
- `msh_finish_line.py` now prints each major gate before running it and routes
  child tools through the shared process-tree timeout runner, so a stuck WSL
  child is reported as a timeout instead of leaving an invisible long-running
  process behind; the long special-builtin, Linux redirection, and Linux
  arbitrary-fd matrices also expose per-case `--progress` output on stderr so
  broad runs show movement between major gates
- `msh_finish_line.py` now exposes `--command-timeout` and `--max-seconds`;
  the default whole-run cap is 30 minutes and matrix tools use the shared
  process-tree runner instead of raw `subprocess.run`, so broad POSIX evidence
  cannot silently stack unbounded per-case stalls
- `msh_posix_suite.py` retries reference-shell timeout results before
  recording them, so transient WSL stalls do not create false POSIX failures
- `msh_shell_diff.py` also retries transient reference-shell timeout results,
  exposes per-case `--progress`, and has a strict-verifier-clean typed result
  model with no suppression comments; the current stderr-sensitive report was
  regenerated through Python UTF-8 file I/O, parses as UTF-8, and proves
  `134/134` WSL `/bin/sh` matches without relying on PowerShell redirection
- strict POSIX profile fixes now reject postfix arithmetic increment/decrement,
  reject comma arithmetic expressions, treat apparent prefix `++A` / `--A` as
  repeated unary `+` / `-`, profile C-locale equivalence/collating glob syntax
  as literal under the current WSL `/bin/sh` reference, and reject shell
  `printf` length modifiers such as `%lld` / `%Lf`; the semantic probe and
  extension-inclusive WSL diff cover this profile
- WSL matrix profiling deliberately avoids platform-specific output traps:
  volatile `times` CPU totals are redirected out of exact-output matrix cases,
  unset-`PATH` current-directory dot lookup remains WSL/Mixtar profile
  evidence, and platform signal-list spelling remains WSL-only evidence

Run the profile gate with:

```text
python C:\Users\V\source\repos\MixtarRVS\Server\Shells\msh\tools\msh_finish_line.py
```

This writes:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Generated\reports\msh-finish-line.md
```

Run the fast smoke gate with:

```text
python C:\Users\V\source\repos\MixtarRVS\Server\Shells\msh\tools\msh_smoke_gate.py --rounds 3
```

This rebuilds Windows and WSL/Linux `msh_cli` from strict AILang, runs an
18-case POSIX-core smoke slice against WSL `sh`, `bash --posix`, and
`zsh --emulate sh`, runs the WSL performance smoke, and writes:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Generated\reports\msh-smoke-gate.md
```

Run the WSL-native performance baseline with:

```text
wsl.exe --exec python3 /mnt/c/Users/V/source/repos/MixtarRVS/Server/Shells/msh/tools/msh_perf_compare.py --rounds 30 --warmup 5
```

This writes:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Generated\reports\msh-wsl-performance.md
```

Current performance baseline: `msh` is slower than WSL `sh`, `bash`, and `zsh`
on pure interpreter-heavy shell loops, but is roughly competitive on
process-heavy pipeline work. This is optimization guidance, not conformance
evidence.

The current `perf` hotspot report is:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Generated\reports\msh-wsl-perf-hotspots.md
```

It shows that the main slowdown is string/runtime state overhead (`strlen`,
`malloc`, `free`, `ailang_strcat`, `strstr`, `strcmp`), not Linux process
overhead or arithmetic itself.

The next serious target is `msh-posix-candidate`, which remains blocked by
evidence breadth rather than by the current hard-blocker probe. The remaining
candidate blockers are broader POSIX signal semantics beyond the current
Linux-native signal/wait and stopped/continued job-control probes, external
POSIX shell-language suite expansion beyond the current `posix-core`,
generated `posix-stress`, external-style seed, imported Smoosh, and
tools-backed broad Smoosh gates, broader special-builtin fatal/non-fatal
matrices beyond the generated
771-case matrix, broader redirection diagnostic wording, broader
arbitrary-fd/process graphs beyond the current hosted/Linux-native matrices,
and broader interactive shell/terminal job-control profile coverage. The
latest broad Smoosh classifier reruns the stale failures against current `msh`
and can also rerun a current reference shell for stale-reference validation.
With the Linux `msh` ELF, the Mixtar generated userland tool path, and WSL
`/bin/sh` as the current reference, `12` stale failures now match the current
reference shell, `1` is a reference-harness artifact, `1` remains a
current-reference timeout, `1` depends on a non-POSIX absolute helper
(`/readdir`), and `3` remain job-control/interactive formatting/profile cases.
Those 12 current-reference matches are now materialized as
`suites/posix-external-smoosh-tools` and gated by `msh_finish_line.py` as
`175/175` with the generated Mixtar userland tool directory on `PATH`.
No shell-semantic candidate remains in that broad classifier. The previous
shell-semantic candidates
`builtin.times.ioerror` and `semantics.background.pipe.pid` are now covered as
current-reference matches after simulated broken-pipe write status for
shell-local producers and last-stage PID tracking for background pipelines.
The Linux-native job-control probe now covers 12 cases for stopped-job polling,
`SIGCONT`-based `bg`/`fg`, monitor-mode background process-group spawning for
simple commands and native external pipelines, pipeline-group `kill %job`
delivery, foreground `fg` terminal handoff/restoration, stopped-aware waits,
`jobs -p`, explicit `jobs %N` operands, POSIX-style `jobs %string` /
`jobs %?string` references including ambiguous reference diagnostics,
current/previous `jobs` markers (`+`/`-`), `bg %+`, and `wait` clearing stale
job numbers. It also covers the broad Smoosh-style case where a plain `wait`
consumes old `%1`/`%2` slots before a later monitor-mode `kill %1 %2`, while
retaining repeated `wait $pid` status compatibility through an internal hidden
wait-status cache. The
Linux-native fd graph probe now covers 21 child/process fd-inheritance and
offset-sharing cases against WSL `/bin/sh`. The Linux-native interactive pty
probe now covers `-i` exit status, expanded PS1/PS2 prompting, persistent
state, EOF, quote continuation, compound-command continuation, pipeline
continuation, top-level EXIT trap delivery, explicit `exit 130`, default
SIGINT-at-prompt status `130`, trapped SIGINT-at-prompt action/status
preservation, terminal Ctrl-C interrupting a foreground external command while
leaving the interactive shell alive with `$?=130`, terminal Ctrl-\ interrupting
a foreground external command while leaving the interactive shell alive with
`$?=131`, terminal Ctrl-Z stopping a foreground external command, recording it
as a stopped job, regaining the terminal with a SIGTTOU-guarded process-group
restore, and resuming stopped jobs through `fg` and `bg`/`wait` to normal
completion. The process wait path ignores continue notifications and waits for
the next stop/exit status so resumed jobs do not leak a transient `-1` status.
The Linux-native signal/wait matrix covers 78 WSL `/bin/sh` comparisons for
signaled child wait status, repeated waits, `wait` after kill, `kill -0`
live/dead PID behavior, unknown-pid wait status, multi-operand wait status,
mixed background-child wait ordering, no-child and invalid-pid `wait` status,
self-contained child exit statuses, no-operand `wait` status retention,
kill option forms, missing/invalid kill operands, async-list status, `$!`
refresh behavior, stable async `INT`/`QUIT` ignore behavior after
background-job startup,
self-signal traps and ignored self-signals for `TERM`, `INT`, `HUP`, `QUIT`,
and `USR1`, and real shell invocation termination by default self-signals after
trap reset or numeric/name `kill` operands across both `-c` and script-file
invocation paths, plus script-file ignored-signal behavior and `EXIT` trap
preservation/reset/status behavior.
The largest open
buckets are now broader interactive/job-control behavior if claimed, deeper
arbitrary-fd and process-graph coverage beyond the generated 143-case matrix,
full diagnostic wording matrices, and a larger
external conformance corpus.

Compatibility comes before optimization. `msh` performance work is only valid
after the affected POSIX behavior is represented in the local suites and passes
against the selected WSL `/bin/sh` reference profile.

## Release Gates

These gates prevent the hard POSIX blockers from hiding useful progress.
`msh-core` may ship as a useful non-interactive shell profile before the full
POSIX candidate is ready. Only the final profile can be described as
POSIX-compatible without qualification.

### Gate 1: `msh-core`

Scope:

```text
non-interactive scripts
C/POSIX locale only
no job control
no interactive line editing
native argv/fd execution only
no host shell command-line reconstruction for normal execution
```

Required:

- [x] Parser proof for common POSIX shell grammar.
- [x] Expansion proof for common script cases.
- [x] Native simple external command execution.
- [x] Native external pipeline execution.
- [x] Real fd redirections for files, heredocs, and common compound commands.
- [x] Core stateful builtins: `.`, `alias`, `unalias`, `cd`, `command`, `eval`,
  `export`, `getopts`, `hash`, `jobs`, `kill`, `readonly`, `read`, `set --`,
  `shift`, `trap` metadata, `type`, `unset`, and `wait`.
- [x] Function, subshell, loop, branch, case, and positional-parameter state proofs.
- [x] Leak-clean selftest.
- [x] Focused semantic regression probe.
- [x] Exported environment handoff through every native pipeline launch path.
- [/] Special builtin fatal/error semantics for non-interactive scripts:
  assignment failures and redirection failures attached to special builtins now
  abort the current non-interactive evaluator; the full operand/error matrix is
  still pending.
- [/] Exact command-not-found / permission-denied distinction: simple native external
  command execution maps missing commands to 127 and permission failures to 126
  through captured exec errno; native pipeline tail permission failures now use
  the same errno path. Missing simple commands and missing explicit paths now
  emit stderr diagnostics, and missing pipeline stages emit diagnostics while
  preserving tail-status behavior. Explicit directory paths return 126 and emit permission-denied diagnostics
  before native launch or script fallback; unqualified directory entries found
  through `PATH` are skipped as non-commands and return status 127 with permission-denied diagnostics when no later command wins.
  Explicit shell `PATH` now owns lookup, including empty-path
  current-directory semantics without falling through to the host `PATH`;
  `command -p -v` skips caller `PATH` script lookup, and `command -p`
  external execution uses the hosted default path while plain `command` still
  obeys the shell `PATH`. Broader search-order cases remain pending.
- [/] Redirection errors with exact status/message profile: failing special
  builtin redirections now return non-zero and abort non-interactive evaluation;
  ambiguous targets, missing input/create failures, bad duplicated-fd sources,
  and bad duplicated-fd targets return status 2 before execution and emit
  stderr diagnostics. Full POSIX wording coverage remains pending.
- [x] Document the exact `msh-core` profile and deliberate omissions in `MSH_CORE_PROFILE.md`.

### Gate 2: `msh-posix-candidate`

Scope:

```text
serious POSIX sh candidate for external conformance testing
non-interactive correctness first
interactive/job-control work may still be scoped separately
```

Required:

- [/] Streaming parse/eval mode for full POSIX read-unit behavior: newline-delimited
  alias activation, current hard-blocker `exec <file` behavior, and the covered
  `if`/`for`/`case`/function-definition read-unit alias timing slice are
  implemented; verbose-mode read-unit evaluation now keeps quoted multiline
  eval operands in one unit, including readonly `unset -v` fatality before a
  following command; full parser-stream alias timing for every compound context
  remains pending.
- [/] Central POSIX error policy table for parser, expansion, redirection, and special builtin failures: `msh_errors.ail` owns shared status constants and special-builtin consequences; assignment/redirection failures plus selected operand/context errors are covered, parser diagnostics now emit WSL-compatible `eval:` syntax errors for the covered direct and `command eval` parse-error cases, and the generated WSL `/bin/sh` special-builtin matrix passes `771/771`; conformance-sized matrix coverage remains pending.
- [/] Full special builtin fatal/non-fatal matrix for non-interactive scripts:
  assignment failures, redirection failures, direct `set` option errors,
  direct `shift` errors, direct invalid `unset`, `unset` readonly errors,
  dot-source failures, direct `export`/`readonly` operand errors, direct
  `exec` redirection failures, and direct `:` redirection failures now abort
  the current evaluator; `command export`/`readonly`/`set`/`shift`/`unset`
  operand errors, `command eval` wrapping selected special-builtin errors,
  `command .` / `command eval .` missing-source errors, and `command :` / `command exec`
  redirection failures are covered as non-fatal
  command-utility errors against WSL `/bin/sh`. Dot with no operand,
  direct/`command` trap missing-action no-op behavior, extra operands to
  `break`/`continue`, direct/`command` readonly assignment failures,
  direct/`command` invalid `set -o` names, and direct/`command` negative
  `shift` counts are covered against WSL `/bin/sh`. `eval`-wrapped
  `export`/`readonly` invalid-name diagnostics, `set -Z` diagnostics,
  `shift`, readonly `unset`, dot-source failure, invalid numeric
  `exit`/`return`/`break`/`continue`, and `trap` invalid-signal diagnostics
  are covered with normalized stderr against WSL `/bin/sh`. `command break`,
  `command continue`, `command return`, `command exit`, and `command eval`
  wrappers for invalid numeric control operands are covered for the current
  nonfatal utility-error slice. Valid `break`/`continue` outside a loop are
  covered as WSL-compatible nonfatal no-ops for direct, `eval`, and
  `command eval` paths. Real `exit` and top-level `return` through
  `command eval` still stop evaluation. Readonly violations use the current
  WSL-sh status-2 profile. Dot with no operand, dot `--`, and `command . --` are covered as successful
  no-ops or option-delimited source execution; PATH-unset dot source lookup
  is covered for the current directory. Extra operands to `break`/`continue`
  are covered as ignored after the first operand, `trap -- action SIGNAL`, omitted-action `trap SIGNAL` and
  `trap -- SIGNAL` reset behavior, `trap -l` illegal-option
  fatality, missing-action `trap` status-zero behavior, invalid `trap`
  signal status-one behavior, `export --`, `readonly --`, `set -f --`
  option/positional splitting, lone `export -` / `readonly -` bad-name
  diagnostics, double-quoted ordinary backslash preservation,
  `printf` raw `%s` operands versus `%b` escape decoding, `unset --`, `unset -v`, `unset -f`,
  combined `unset -fv` / `unset -vf` option parsing, repeated `command -v` /
  `command -V` lookup options, and `export -p` / `readonly -p` with extra
  operands are covered against WSL `/bin/sh`. Combined and separate `command`
  `-v` / `-V` option forms are covered with `-V` verbose lookup precedence.
  Direct, `command`, `eval`, and
  `command eval` paths are covered for `times` extra operands, `unset -z`,
  invalid `unset` names, WSL-compatible `shift` extra operands, and `trap -l`;
  direct and `command` extra-operand behavior is covered for `return` and
  `exit`, and numeric edge cases are covered for `break 0`, negative
  `break`/`continue`/`shift`, nonnumeric `shift`, negative or too-large
  `return`/`exit`, and too-large numeric `trap` operands. Direct,
  `command`, `eval`, and `command eval` `set` plain-operand positional
  updates are covered, as are `set` option-plus-operand and single-dash
  operand forms. Assignment-only commands now
  return the status of the last command substitution, external temporary
  assignments inside command substitution are exported to child utilities and
  restored afterward, and `set -e` aborts
  on `X=$(false)` in the covered WSL `/bin/sh` slice. Noclobber redirection
  failures are covered for direct `:`, `eval`, `exec`, and `export` as fatal
  special-builtin errors, and for `command :`, `command eval`, `command exec`,
  `command export`, and redirection-only commands as nonfatal utility errors.
  Missing-input redirection failures are also covered across direct, `command`,
  `eval`, and `command eval` forms for `readonly`, `set`, `shift`, `times`,
  `trap`, and `unset`, matching WSL `/bin/sh` fatal/nonfatal behavior. The
  generated WSL `/bin/sh` matrix covers 771 total direct, `eval`, `command`,
  and `command eval` fatal/nonfatal status/stdout/stderr cases, including
  missing-input redirection failures, bad duplicated-fd failures,
  nonnumeric duplicated-fd syntax, noclobber failures, eval-context
  redirection diagnostics, multi-line quoted `eval` source,
  output-create redirection failures,
  command-exec stdout failure behavior, assignment persistence before
  special builtins, `command` assignment suppression, readonly-assignment
  failures before special builtins, dot no-op forms, trap reset/listing no-op behavior,
  `readonly -p` extra-operand behavior, lone-dash `export`/`readonly`,
  `unset` mode parsing, `set --` / `set -f --` / plain `set` operands,
  `shift 0` and extra operands, invalid `unset` names, numeric
  `break`/`continue`/`shift`/`return`/`exit` edge cases, `eval` zero/multiple
  operands, `trap -` / `trap --`, dot-source `--`, `exit`/`return` extra
  operands, and operand field-expansion parameter-error, bad-substitution, and
  division-by-zero behavior for every POSIX special builtin across direct,
  `eval`, `command`, and `command eval` forms; the remaining
  conformance-sized special-builtin error table is still pending.
- [x] `EXIT` trap execution for top-level non-interactive evaluator exit is
  covered by selftest and blocker probe.
- [/] Non-interactive signal trap dispatch: signal names and numeric traps are
  canonicalized, invalid `SIG*` operands are rejected, signal-derived status
  helpers are covered, shell-side pending-signal trap dispatch is covered by
  selftest, and `kill -SIGNAL $$` dispatches current-shell traps through the
  evaluator. Ignored self-signals, numeric self-signal traps, trap-action
  status preservation, and trap-action `exit` control are covered against WSL
  `/bin/sh`. Ordinary subshells now reset inherited caught traps while
  preserving ignored traps, and command substitutions reset inherited caught
  traps while still running `EXIT` traps installed inside the substitution;
  focused local regressions cover both behaviors pending the next WSL-backed
  suite refresh. Simulated subshell `kill $$` now defers the signal to the parent
  shell trap context, matching WSL `/bin/sh` for the covered action-trap and
  ignored-trap slices. Pipeline subshell trap reset is covered for action traps,
  ignored traps, pipeline-stage `EXIT` trap execution, and parent `EXIT` trap
  preservation. The generated signal/trap matrix gates 72 non-interactive cases
  against WSL `/bin/sh`, including `EXIT`/`0` alias reset behavior, top-level
  `return` inside `EXIT` traps preserving the original status, multi-signal
  trap listing/reset behavior, repeated self-signal trap dispatch, `kill -s`
  and numeric signal dispatch, and Linux/WSL-style `kill -l` exit-status
  mapping. Hosted native signal hooks now install for trapped
  current-process signals and drain into the same pending dispatcher; broader
  interactive/job-control signal semantics remain pending.
- [/] Exact command search order and diagnostics matrix: alias-aware
  `command -v`, verbose `command -V`, `type`, function-over-regular-builtin,
  special builtin, regular builtin, explicit shell `PATH`, and script lookup are
  covered in the current probes. Empty `PATH` current-directory behavior and
  host-`PATH` non-leakage are covered by semantic tests, and directories
  found through unqualified `PATH` lookup are skipped by execution, `command -v`, `command -V`, and `type`; `command -p -v`
  uses default/host lookup instead of caller `PATH`, and a focused host-aware
  probe covers actual `command -p` external execution. POSIX-target lookup now
  uses executable-permission-aware `file_can_execute()` checks so
  non-executable `PATH` entries are skipped and cannot trigger text-script
  fallback on non-Windows builds; `msh_linux_command_search_probe.py` proves
  the chmod-sensitive behavior against a Linux-native WSL build, including
  `command -v`, `command -V`, and `type` on an only-non-executable `PATH`
  candidate; the same Linux-native probe covers dot-source `PATH` lookup
  skipping unreadable candidates and explicit unreadable dot-source diagnostics.
  The generated WSL-backed command-search matrix now gates 170
  hosted-safe cases across reserved words, aliases, functions, special
  builtins, regular builtins, explicit shell `PATH`, default-path lookup,
  explicit pathnames, empty `PATH` components, unset-`PATH` source lookup,
  multi-operand lookup, directory execution diagnostics, and invalid `command`
  option forms, plus regular-builtin function shadowing, alias-before-function
  lookup precedence, `[`/`test`/`read`/`printf`/`pwd` builtin lookup,
  complete POSIX special-builtin lookup naming, broader POSIX regular-builtin
  lookup naming, function shadowing of the regular `command` builtin,
  empty `--` lookup operands, missing-parent explicit pathname diagnostics,
  and special/reserved function-name rejection. Combined `command` option clusters such as `-pv`, `-pV`, and
  `-Vp`, invalid clusters such as `-pz`, and lone `command -` command-name
  behavior are covered against WSL `/bin/sh`. Lookup for POSIX reserved words through `command -v`, `command -V`, and `type` now
  matches WSL `/bin/sh`, explicit existing regular pathnames are reported
  by lookup even when they are not executable, explicit directory path lookup
  through `command -v`, `command -V`, and `type` reports the pathname, and
  actually executing an explicit directory path returns 126 with
  permission-denied diagnostics. The current non-interactive profile does not
  implement history-editing `fc`, and WSL-backed lookup/execution cases now
  prove it is reported as missing instead of leaking to a host `fc` utility.
  The Linux-native command-search diagnostic matrix gates 18/18 chmod,
  explicit-path, ENOEXEC text-script fallback, pipeline fallback, directory,
  and dot-source permission cases against WSL reference shells. It uses
  WSL `/bin/sh` for dash-compatible cases and `bash --posix` for the POSIX
  dot-source readable-`PATH` search rule because WSL `/bin/sh` stops at an
  unreadable candidate where POSIX.1-2024 specifies failure only when no
  readable file is found.
  The AILang
  POSIX runtime now exposes raw ENOEXEC for path-qualified argv0 instead of
  letting libc run `/bin/sh`; `msh` owns text-script fallback and rejects
  executable binary garbage with status 126 / exec-format diagnostics in the
  covered explicit, `PATH`, and `command -p` cases. Broader redirection
  diagnostic wording and POSIX ordering corners outside the current generated
  matrices remain pending.
- [/] Full redirection ambiguity detection after expansion: redirection targets
  now expand to fields before execution and zero/multiple fields return status
  2; the Linux-native redirection diagnostic matrix gates 92/92 WSL `/bin/sh`
  matches for missing input, redirection-only failures, regular/special/exec
  redirection failure consequences, missing output parents across output,
  append, force-output, and read/write forms, directory output, special/exec
  output-failure abort behavior, bad fd duplication including fd-2 diagnostic
  suppression, command-local stdin/stdout/stderr close restoration, persistent
  `exec` fd-close behavior, noclobber, force overwrite, append, ambiguous
  empty/multi-field targets, quoted empty and space-containing targets,
  single/multiple glob-expanded targets, left-to-right stdout/stderr ordering,
  heredoc/input ordering, and multi-digit
  fd prefixes, compound-command fd restoration, compound-command
  missing-input/output/dup-fd failure continuation for `if`, `while`, `for`,
  and `case`, `>` offset tracking, `>>`
  append behavior, duplicated stdout/stderr offset sharing, command-not-found
  preflight diagnostic routing through stderr file/stdout/closed-stderr
  redirections, command substitution `2>&1` capture, successful `<>`
  create/no-truncate/shared-offset cases, and closed-stdout write-failure
  status/diagnostics for `printf`, `echo`, `pwd`, `alias`, `export -p`,
  `readonly -p`, `set`, `umask`, `trap`, `type`, `command -v`, and `kill -l`.
  Broader locale-sensitive
  differential coverage remains pending.
- [/] Full builtin diagnostics for invalid context, invalid operands, and readonly violations:
  stderr diagnostics now exist for invalid `break`, `continue`, `return`,
  `shift`, `unset`, `umask`, `export`, `readonly`, `set`, `times`, `trap`,
  `wait`, `getopts`, `jobs`, `printf`, and `unalias` cases and are covered by
  the semantic probe. The generated regular-builtin matrix gates 233 exact
  WSL `/bin/sh` status/stdout/stderr cases for `alias`, `unalias`, `cd`,
  `pwd`, `jobs`, `wait`, `getopts`, `echo`, `printf`, `read`, `umask`,
  `ulimit`, `hash`, `type`, `command`, `test`, `[`, `true`, `false`, and
  `kill`; broader regular-builtin
  operand/error matrices remain pending. The latest slice also covers
  `getopts` explicit operands, `OPTIND` reset, invalid `OPTIND` fatality,
  plus-signed/zero/out-of-range `OPTIND` handling, `--` end-of-options,
  grouped required arguments, `+` operands, non-option operand termination,
  `OPTARG` preservation at end-of-scan, clustered invalid-option continuation,
  empty/colon-only optstrings, and non-silent missing-argument `OPTARG`
  unsetting; `alias --` as an alias-name query, `unalias --` as an option
  delimiter, `read` option-delimiter handling, repeated `-r`, readonly
  assignment failures with prior-assignment preservation, backslash-escaped
  IFS delimiters, single-variable tail capture, final-variable rest capture,
  empty-file EOF assignment, whitespace collapse, non-whitespace `IFS` empty
  fields, cooked/raw backslash-newline behavior, and Windows-host-safe
  `/dev/null` EOF handling;
  `printf` zero padding, alternate integer forms, dynamic width/precision,
  argument reordering, and quoted numeric character operands; symbolic `umask`
  add/copy/remove forms plus POSIX-compatible setuid/setgid symbolic no-op
  handling; `umask --` delimiters, `umask -S --`, `umask -S mask`, and
  extra-mask operand behavior; non-interactive file-size `ulimit` query,
  mutation, combined `-HSf` options, `--` numeric delimiters, redirection,
  invalid option, invalid number, and raise-failure behavior; `hash`
  known-command operands; mixed `type` and `command -v` lookup status; `kill`
  `-s 0`, invalid `-s`, invalid multi-letter dash-signal operands, signal
  listing by signal and exit status, and illegal pid operands;
  `test`/`[` core string/integer/file primaries plus invalid integer,
  string-length predicates, precedence for `!`, `-a`, `-o`, grouping and
  malformed grouping status, signed and whitespace-padded integer operands,
  every current integer comparison operator, signed 64-bit boundary
  acceptance/rejection, leading-zero overflow rejection, and `-t` illegal
  operand diagnostics, regular-file negative type
  predicates for `-b`/`-c`/`-p`/`-S`, regular-file set-id and symlink
  predicates for `-u`/`-g`/`-L`/`-h`, file identity, missing-file `-nt`/`-ot`
  behavior, triple negation, empty grouped expressions, missing string operands, unknown unary/binary operators, grouping, missing-bracket, and unexpected-operator diagnostics;
  multi-operand `hash` failure; and multi-name `command -V` output.
  Shell-local `echo` is now implemented as a regular builtin, with WSL
  `/bin/sh` matrix parity for no operands, operand joining, `-n`, backslash
  escape decoding, octal escapes, `\c` newline suppression, literal
  non-option operands such as `-e` and `--`, and output redirection.
- [/] Broader parser, expansion, builtin, redirection, and pipeline differential corpora:
  WSL shell diff now covers 124 POSIX-profile cases, including implicit
  `for name` positional iteration, direct output builtin redirection,
  re-input-safe alias output, readonly violation status, compound-command
  heredoc input, while/group pipeline reads, POSIX bracket `^` literal
  behavior, arithmetic comparison/logical/conditional/assignment operators,
  parameter alternate/default/assignment expansion, quoted command
  substitution with quoted inner words, empty-IFS and empty-field behavior,
  trailing compound redirections, function positional/status behavior,
  background wait/redirection cases, stderr diagnostic bodies, and `errexit`
  suppression for AND/OR and `!` contexts; a true conformance-sized corpus
  remains pending.
- [/] External POSIX shell-language test suite selected and wired into CI/manual gate:
  a file-based `posix-core` suite and generated shell-only `posix-stress`
  suite plus `posix-external-seed` and the imported Smoosh allowlist slice are
  wired into the finish report. The Smoosh slice is now 157 strict WSL
  `/bin/sh` matches after importing newly unlocked shell-language cases for
  `echo`, `command`, `eval`, `trap`, `unset`, arithmetic, tilde, return,
  subshell, pattern-removal, empty-IFS null-field suppression, lexical
  `break`/`continue`, alias/export/source cases, additional trap inheritance
  and redirection slices, empty-parameter parse errors, inherited `EXIT` trap
  suppression in subshells, dot-source `return`, export listing, signal-name
  `kill`, readonly assignment failure, fatal direct `eval` parse errors, case
  exit-status preservation, command-substitution newline preservation,
  `errexit` carryover, heredoc escaping, redirection close/from/to behavior,
  tilde separator expansion, `set -u` edge cases, external temporary
  assignment export, shell startup `IFS` defaulting with environment `IFS`
  ignored, `exec true`, source-state mutation, `sh -c` argument-zero
  behavior, heredoc backslash expansion, quoted/unquoted tilde behavior,
  bracket pattern edge cases, non-interactive expansion fatal exits, and
  child-shell `PPID`, background `$!` tracking for simple commands and
  pipelines, child-shell non-interactive expansion error exit behavior, and
  selected expansion semantics. The non-gating broad Smoosh probe currently reports
  `154/186` matches against WSL `/bin/sh`, with no stack-overflow failures
  remaining after the EXIT-trap recursion guard and pipeline-redirection
  precedence fixes. `tools/msh_broad_smoosh_classify.py` reruns the stale
  failures against current `msh`; with the normal no-tool-path profile it
  classifies them with the Linux `msh` ELF, Mixtar generated userland tool
  path, and current WSL `/bin/sh` reference: `12` cases now match the current
  reference, `1` is a reference-harness artifact, `1` remains a
  current-reference timeout, `1` depends on a non-POSIX absolute helper
  (`/readdir`), and `3` remain job-control/interactive formatting/profile
  cases. No shell-semantic candidate remains in the current broad classifier.
  `semantics.error.noninteractive`,
  `builtin.times.ioerror`, and `semantics.background.pipe.pid` are now covered
  as current-reference matches.
  `builtin.cd.pwd` is now covered as fixed after POSIX-style `PWD`/`pwd`
  path presentation and logical `cd ..` handling.
  Importing or mirroring a conformance-sized external corpus remains pending.

### Gate 3: `msh-posix-certified-profile`

Scope:

```text
no known POSIX shell-language blockers
eligible to become /System/Shells/msh
profile limitations documented before any compatibility claim
```

Required:

- [x] Locale/collation story is implemented or explicitly constrained by a documented profile: `msh-core` is C/POSIX-locale only.
- [x] Locale-aware pathname sorting, bracket classes, equivalence classes, and
  collating symbols are implemented or profiled out: current profile uses
  byte/ASCII sorting, ASCII bracket classes, and C-locale single-character
  equivalence/collating-symbol matching; full locale collation is not claimed.
- [x] Interactive behavior is implemented or explicitly excluded from the
  claimed profile: current `msh-core` profile is non-interactive only, while a
  Linux pty smoke probe now covers basic `-i` prompt/state/EOF behavior.
- [x] Job control and terminal process-group behavior are implemented or
  explicitly excluded from the claimed profile: current `msh-core` profile
  excludes both; Linux-native probes cover stopped-job bookkeeping and resume
  paths, foreground terminal process-group handoff/restoration, and stopped
  foreground-job recovery, not full login-shell terminal behavior.
- [/] Signal exit-status rules are implemented for the shell-side signal helper
  profile: canonical signals map to `128 + signo` and pending default signal
  dispatch records that status. Ignored traps preserve command status,
  non-control trap actions preserve the interrupted command status, and trap
  actions that invoke shell control such as `exit` control the resulting status
  in the covered non-interactive self-signal slice. The generated signal/trap
  matrix compares the claimed trapped/ignored/deferred behavior with WSL
  `/bin/sh`; the Linux-native signal/wait matrix also compares signaled child
  wait status, repeated waits, `wait` after kill, `kill -0` live/dead PID
  behavior, unknown-pid and invalid-pid wait status, no-child `wait` status,
  multi-operand wait status, mixed background-child wait ordering, trapped and
  ignored self-signals for `TERM`, `INT`, `HUP`, `QUIT`, and `USR1`, and real
  shell-invocation default self-termination against WSL `/bin/sh`. Real `-c` and script-file
  invocation preserve default-signal process semantics by resetting the native
  signal disposition and re-raising the signal when evaluation returns
  `signal_exit`; hosted `eval` remains a status-oriented test mode. Hosted
  native trapped-signal delivery drains into the same dispatcher, and the Linux
  interactive pty probe now covers
  default and trapped SIGINT-at-prompt behavior, terminal Ctrl-C for a
  foreground external command, terminal Ctrl-\ for a foreground external
  command, and terminal Ctrl-Z stopped-job recovery plus `fg` and `bg`/`wait`
  completion. Broader interactive job-control status behavior is still pending.
- [x] Trap delivery is complete for the claimed profile: current profile claims
  top-level `EXIT` trap execution, shell-side self-signal trap dispatch,
  ignored self-signal handling, trap-action status preservation, trap-action
  `exit` control, subshell `kill $$` parent-trap deferral, pipeline-stage
  `EXIT` trap execution, and hosted native trapped-signal dispatch. The
  generated signal/trap matrix covers 72 WSL `/bin/sh` comparisons for this
  non-interactive profile. Interactive/job-control trap semantics are not
  claimed.
- [/] External conformance suite passes for the claimed profile: the starter
  file-based `posix-core` suite, generated shell-only `posix-stress` suite,
  external-style `posix-external-seed` suite, and imported Smoosh allowlist
  slice pass for the current WSL-backed gate; the imported Smoosh slice is
  `163/163` against WSL `/bin/sh`. The broad Smoosh probe is
  `154/186` against last-known WSL `/bin/sh` evidence and is used as a
  non-gating gap finder. The broad classifier reports split the stale failures
  into current-reference match, external-helper, reference-harness artifact,
  shell-semantic, timeout, and job-control/interactive buckets so shell-semantic
  work is not mixed with userland availability or harness artifacts; the current
  WSL-backed broad classifier has no remaining shell-semantic bucket. A broader
  conformance-sized corpus remains pending.
- [x] Documentation states exact POSIX profile and every deliberate deviation for `msh-core`.
- [ ] `msh` is eligible to become `/System/Shells/msh`.

## Update Rule

- [x] Keep every `.ail` source file below 800 lines.
- [x] Run `msh_cli.exe selftest` with `AILANG_LEAK_REPORT=1` after behavior changes.
- [x] Run AILang routine checks after compiler/runtime changes.
- [ ] Add a roadmap checkbox or update an existing one for every new `msh` behavior.
- [ ] Add a selftest or external regression for every completed checkbox.
- [ ] Do not mark a feature `[x]` unless it survives leak reporting.
- [ ] Do not call `msh` POSIX-compatible without qualifying the remaining gaps.

## Phase 1: Tokenization And Quote Provenance

- [x] Recognize words, operators, redirections, comments, and line continuations.
- [x] Recognize single quotes, double quotes, and backslash escapes.
- [x] Capture here-document bodies for `<<` and `<<-`.
- [x] Preserve enough quote behavior for simple quote removal.
- [x] Preserve quote provenance per word segment through lexer, parser, expansion, and execution.
- [x] Preserve whether `$@`, `$*`, command substitutions, and parameter expansions were quoted.
- [x] Preserve here-document delimiter quote state so expansion suppression can be exact.
- [x] Add tests for mixed quoted/unquoted words such as `a"$b"c`, `"$@"x`, and `x"$@"y`.

Completion gate:

```text
The executor can distinguish literal text, quoted expansion text, and unquoted
expansion text without guessing from the original raw string.
```

## Phase 2: Parser And AST

- [x] Parse simple commands.
- [x] Parse assignment words before command names.
- [x] Parse redirections: `<`, `>`, `>>`, `<<`, `<<-`, `<>`, `<&`, `>&`, `>|`.
- [x] Parse fd-prefixed redirections such as `2>file`.
- [x] Parse pipelines and `!`.
- [x] Parse `&&`, `||`, `;`, and `&`.
- [x] Parse subshells: `( list )`.
- [x] Parse brace groups: `{ list; }`.
- [x] Parse `if`, `while`, `until`, `for`, `case`, and `name() compound-command`.
- [x] Parse POSIX `for name; do ...` and `for name do ...` implicit positional-parameter iteration.
- [x] Parse POSIX optional leading `(` before `case` item patterns.
- [/] Parse nested compound commands in common cases.
- [x] Preserve trailing redirections on `if`, `while`, `until`, `for`, and `case` AST nodes.
- [x] Preserve token source line/column metadata for diagnostics.
- [/] Preserve exact source locations on every AST node: a diagnostic sidecar now maps textual AST nodes to source line/column; native AST node spans are still pending.
- [/] Parse all POSIX grammar edge cases for linebreaks, reserved words, and compound redirections: linebreaks after compound openers and before bodies now parse; full grammar differential coverage is still pending.
- [x] Add negative parser tests for malformed shell grammar.

Completion gate:

```text
Parser accepts valid POSIX shell grammar and rejects invalid grammar without
falling back to hosted shell behavior.
```

## Phase 3: Expansion Engine

- [x] Tilde expansion for `~` and `~/...`.
- [x] Parameter expansion for `$name` and `${name}`.
- [x] Special parameters: `$?`, `$$`, `$#`, `$*`, `$@`, `$!`.
- [x] Positional parameters: `$1` through `$9`.
- [x] Parameter operators: `-`, `:-`, `=`, `:=`, `?`, `:?`, `+`, `:+`.
- [x] `${name:=word}` and `${name=word}` mutate shell state during command evaluation.
- [x] `${name:?word}` and `${name?word}` stop command evaluation with status 2.
- [x] Parameter length: `${#name}`.
- [x] Prefix/suffix removal: `${name#word}`, `${name##word}`, `${name%word}`, `${name%%word}`.
- [x] Arithmetic expansion for `$((...))`.
- [x] Arithmetic precedence for unary `+`, unary `-`, unary `!`, multiplicative, additive, shift `<<`/`>>`, relational, equality, bitwise `&`/`^`/`|`, logical `&&`/`||`, and conditional `?:` operators.
- [x] Arithmetic assignment operators `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `<<=`, `>>=`, `&=`, `^=`, and `|=` mutate shell variables in the stateful expansion path.
- [x] Arithmetic extension/profile decision for prefix/postfix increment and comma expressions:
      implemented as explicit `msh` arithmetic extensions, covered by the
      semantic probe and extension-profile WSL differential corpus, and not
      claimed as part of the strict WSL `/bin/sh` POSIX-profile baseline.
- [x] Command substitution for `$(...)`.
- [x] Command substitution for legacy backquotes.
- [x] IFS splitting distinguishes whitespace IFS from non-whitespace IFS.
- [x] Basic quote removal.
- [x] Basic pathname expansion for `*`, `?`, ranges, and bracket expressions.
- [x] ASCII POSIX bracket classes: `[[:alpha:]]`, `[[:digit:]]`, `[[:alnum:]]`, `[[:space:]]`, `[[:blank:]]`, `[[:upper:]]`, `[[:lower:]]`, `[[:xdigit:]]`.
- [x] POSIX bracket negation uses `[!... ]`; `^` is treated as a literal character.
- [x] Pathname matches are sorted by byte/ASCII order as the current portable baseline.
- [x] Quoted/literal execution words suppress field splitting in the stateful expansion path.
- [x] `$@` and `$*` use quote provenance in the stateful expansion path.
- [x] Exact quoted `$@` behavior for standalone and prefix/suffix mixed words.
- [x] Exact quoted `$*` behavior with first IFS character.
- [x] Exact mixed word splitting and joining for quoted `$@`/`$*` expansion segments.
- [x] Nested command substitution edge cases: close scanning skips `${...}`,
      nested `$(...)`, `$((...))`, and backquotes; WSL differential cases cover
      nested substitution, arithmetic/parameter close skipping, and quoted
      command substitutions whose bodies contain quoted words, plus external
      temporary-assignment export/restoration inside command substitution.
- [x] Here-document expansion/suppression for quoted and unquoted delimiters.
- [x] C/POSIX-locale pathname equivalence classes and collating symbols for
      single-character symbols such as `[[=a=]]` and `[[.a.]]`; full
      locale-aware multi-character collating elements are profiled out.
- [x] Locale-aware sorting/collation is explicitly constrained to byte/ASCII
      order for the current C/POSIX-locale profile and covered by WSL/semantic
      tests.

Completion gate:

```text
Expansion passes a POSIX shell expansion test suite without relying on command
line reconstruction or hosted shell expansion.
```

## Phase 4: Shell State

- [x] Store shell variables.
- [x] Mutate assignment-only commands.
- [x] Mutate assignment words before special builtins.
  - [x] Assignment persistence is covered for the previously separate
        special-builtin dispatch paths: `eval`, `set`, `trap`, `unset`,
        `shift`, `times`, `exec` without a command, and loop/function
        control builtins.
- [x] Store function bodies.
- [x] Store and shift positional parameters.
- [x] Implement `set --` positional parameter replacement.
- [x] Keep subshell variable changes local.
- [x] Track last status in evaluator paths for `$?` expansion in subsequent command and assignment evaluation.
- [/] Implement exported environment state.
  - [x] Track exported names in shell state.
  - [x] Support `export name` and `export name=value`.
  - [x] Pass exported shell variables to simple native external commands.
  - [x] Print marked variables through `export -p` / no-operand `export`
        with sorted, re-input-safe C/POSIX-profile quoting.
  - [x] Pass exported shell variables through every native pipeline launch path.
  - [x] Export assignment words before native external utilities to the child
        environment while restoring the parent shell state afterward.
  - [x] Initialize a default shell `IFS` for new shell entries while ignoring
        any inherited environment `IFS`, matching POSIX shell startup behavior
        for the covered non-interactive profile.
- [x] Implement readonly variable enforcement for shell assignments and `export`/`readonly` assignment operands.
- [/] Implement shell options: short and long option names share canonical
  state; `set -e`, `+e`, `set -o/+o option`, and `set -o` / `set +o`
  printing work for the current recognized option set. Basic `errexit`
  sequence enforcement, AND/OR-list suppression, `!` suppression, `noglob`,
  `noclobber`, `noexec`, core `nounset` parameter diagnostics, `+u`, `+f`,
  `+a`, `+C`, `+o nounset`, `+o noglob`, `+o allexport`, `+o noclobber`, and `command set`
  option side effects are covered against WSL `/bin/sh`. `xtrace` simple-command
  tracing is covered for default, empty, and explicit `PS4`, assignment-only
  commands, command-local assignments, and `set +x`; `verbose` mode emits
  non-interactive input read units before evaluation after `set -v` /
  `set -o verbose` until `set +v` / `set +o verbose`; interactive `monitor`
  semantics remain pending.
- [/] Implement aliases.
  - [x] Store aliases through `alias name=value`.
  - [x] Query named aliases through `alias name`.
  - [x] List all aliases through no-operand `alias`.
  - [x] Remove named aliases through `unalias name`.
  - [x] Remove all aliases through `unalias -a`.
  - [x] Conservative command-leading substitution works for eval-time parsing.
  - [x] Recursive expansion is bounded.
  - [x] Named alias query output is pipe-aware.
  - [x] No-operand and named alias output shell-quotes values in the current
        C/POSIX profile so the output is suitable for re-input.
  - [/] Same-read-unit POSIX alias timing: newline-delimited alias definitions
        affect following read units, and the covered `if`/`for`/`case`/
        function-definition slice keeps aliases defined inside the same compound
        read unit inactive until later units; full parser-stream alias timing for
        every compound context remains pending.
- [/] Implement traps.
  - [x] Store `trap action SIGNAL` metadata.
  - [x] Reset stored trap metadata through `trap - SIGNAL`.
  - [x] List stored trap metadata through no-operand `trap`.
- [x] Execute stored `EXIT` trap at top-level evaluator exit.
- [x] Dispatch stored signal traps for current-shell self signals such as
      `kill -TERM $$` in the non-interactive profile.
- [/] Signal delivery and deferred execution: shell-side pending-signal state,
  trap/default dispatch, hosted native signal hooks, and semantic self-signal
  probes are implemented for the non-interactive profile; interactive
  job-control signal semantics remain pending.
- [x] Implement job table state and current-profile `jobs` listing over
  completed non-interactive background metadata.
- [/] Implement current shell input/source stack.
  - [x] Push source path metadata during `.` execution.
  - [x] Pop source path metadata after normal source completion.
  - [x] Pop source path metadata after sourced `return`.
  - [x] Resolve `.` operands through explicit shell `PATH` when no slash is present.
  - [x] Normalize CRLF file text before source/script parsing for the current
        Windows-hosted profile.
  - [/] Surface source stack in diagnostics: sourced control-flow diagnostics
        include source path context; broader runtime/expansion diagnostics still
        need location plumbing.
- [x] Implement function-local positional parameter scope.

Completion gate:

```text
State changes match POSIX shell scoping rules for scripts, functions,
subshells, assignments, and special builtins.
```

## Phase 5: Builtins

- [x] Classify special builtins, regular builtins, and external commands.
- [x] Implement pure status behavior for `:`, `true`, and `false`.
- [x] Implement stateful `unset`.
- [x] Implement stateful `shift`.
- [x] Implement `hash` for the current no-cache regular-builtin profile.
  - [x] Direct `hash`, `hash -r`, `hash -- name`, explicit path operands,
        functions, special builtins, regular builtins, and missing-name /
        invalid-option diagnostics match WSL `/bin/sh`.
  - [x] `hash` is visible through `command hash`, `command -v hash`,
        `command -V hash`, and `type hash`.
- [/] Implement `command`.
  - [x] `command name` executes supported builtin/external command path.
  - [x] `command -- name` handles explicit end-of-options.
  - [x] `command -v name` performs alias/function/builtin/PATH lookup in the current slice.
  - [x] `command -V name` emits verbose alias/function/special-builtin/regular-builtin lookup text.
  - [x] `command -p name` and `command -p -- name` parse and execute.
  - [x] `command -p name` runs default-path external utilities even when the
        shell `PATH` is poisoned, while plain `command name` still obeys the
        shell `PATH`.
  - [x] `command -p -v name` parses and performs default-path lookup without
        caller `PATH` script leakage.
  - [x] Hosted Windows profile boundary is explicit: `command -p -v/-V sh`
        reports the POSIX default shell utility path, but actually executing
        Linux `/usr/bin/sh` through Windows-hosted `msh_cli.exe` is not claimed.
  - [x] Missing operands for `command -v` / `command -V` return success with no output.
  - [x] Invalid command options return status 2 and emit a diagnostic.
  - [x] Nested `command command ...` dispatch works for the current slice.
  - [x] `command type ...` dispatch works for the current slice.
  - [x] Stateful builtin dispatch is covered for `alias`, `unalias`,
        `export`, `readonly`, `set`, `unset`, `shift`, `wait`, `umask`,
        `cd`, `pwd`, `printf`, `read`, `times`, `trap`, `getopts`, `jobs`,
        `hash`, and `kill`.
  - [x] `command eval`, `command .`, and current-profile `command exec`
        dispatch through shell-local stateful paths.
  - [x] `command eval` applies command-local redirections, including
        WSL-matched nonfatal redirection failure status.
  - [x] Assignment words before `command eval` and `command .` are temporary
        around the `command` utility but visible to the invoked `eval` body or
        sourced file; effects created inside the body still persist.
  - [x] Assignment words before other `command`-dispatched utilities are
        temporary around the `command` utility; WSL-matched coverage includes
        restoring original variable values and export/readonly attributes after
        `command unset`, `command export`, and `command readonly`.
  - [x] Output redirection is covered for command-invoked output builtins in
        the current slice.
  - [x] Direct output redirection is covered for `type`, `trap`, `export -p`,
        `readonly -p`, `set`, `umask`, and `times` in the current WSL
        differential corpus.
  - [x] `command export`/`readonly`/`set`/`shift` operand errors return the
        utility error status without aborting following non-interactive
        commands in the covered WSL `/bin/sh` slice.
  - [x] True `command exec` process replacement is wired through AILang
        `process_exec_replace_argv_env_redirs` when the real-exec profile flag
        is enabled; `eval-real-exec` covers target status and redirection.
  - [x] Explicit text-script operands such as `command ./script` and
        `command -p ./script` use the same `msh` script fallback as normal
        execution, including command-local output redirection.
  - [x] `command break`, `command continue`, `command return`, and
        `command exit` match WSL `/bin/sh` for the current out-of-context,
        normal-control, and invalid numeric operand slices.
  - [x] Assignment words before `command set`, `command shift`,
        `command break`, `command continue`, `command return`, invalid
        `command exit`, and missing-source `command .` are temporary around
        the `command` utility in the WSL `/bin/sh` differential suite.
  - [/] Special-builtin-property suppression is now covered for direct
        `A=one command <special-builtin>` assignment side effects across the
        current POSIX special-builtin set, plus existing nonfatal
        command-wrapped special-builtin error paths; broader conformance
        wording remains under the Gate 2 error matrix.
- [/] Implement `type`.
  - [x] Reports aliases.
  - [x] Reports functions.
  - [x] Reports special builtins.
  - [x] Reports regular builtins.
  - [x] Missing names return 127 in the current WSL differential baseline.
  - [x] Missing-name output and continued multi-name probing match the current WSL baseline.
  - [x] Explicit shell `PATH` script wording is covered for `type` and
        `command -V`.
  - [x] Empty `PATH` current-directory lookup and Windows-host `PATH`
        non-leakage are covered by the semantic probe.
  - [ ] Full host executable PATH wording remains pending.
- [x] Implement `.` source execution.
  - [x] Source explicit paths.
  - [x] Source names found through explicit shell `PATH`.
  - [x] Keep sourced variable changes in the current shell.
  - [x] Honor `return` status from sourced files.
  - [x] Preserve status from sourced files whose final command is a regular
        builtin, including CRLF-normalized file content.
  - [x] Current WSL-profile source diagnostics are covered for missing explicit
        paths, missing `PATH`-searched names, explicit unreadable source files,
        and `PATH` lookup that must skip unreadable candidates.
- [/] Implement stateful `export` and `readonly`.
  - [x] Support simple names.
  - [x] Support `name=value` operands.
  - [x] Reject invalid options.
  - [x] Enforce readonly assignment failures.
  - [x] Readonly assignment/export/readonly/unset violations return status 2
        in the current WSL-sh differential profile.
  - [x] Print marked and marked-but-unset variables through `export -p`
        and `readonly -p`.
  - [x] Re-input-safe C/POSIX-profile quoting and deterministic ordering for `-p` output.
- [x] Implement stateful `alias`/`unalias` storage.
- [x] Implement no-operand `alias` listing and `unalias -a`.
- [/] Implement stateful `trap` storage and listing.
- [/] Implement `times`: emits the WSL-compatible two-line `0m0.000000s`
  timing shape and returns success; real accumulated shell/child CPU accounting
  remains pending.
- [/] Implement full `break`.
  - [x] One-level loop break works.
  - [x] Numeric nested-loop break levels work.
  - [x] Subshell boundary behavior matches WSL `/bin/sh` for the covered slice:
        `break` can affect lexical loops inside the subshell, but cannot escape
        into the parent shell loop.
  - [x] Invalid-context status and non-interactive abort behavior work.
  - [x] Invalid numeric operand status and abort behavior work.
  - [x] Baseline stderr diagnostic emission is covered.
  - [ ] Reference-shell wording review remains pending.
- [/] Implement full `continue`.
  - [x] One-level loop continue works.
  - [x] Numeric nested-loop continue levels work.
  - [x] Subshell boundary behavior matches WSL `/bin/sh` for the covered slice:
        `continue` can affect lexical loops inside the subshell, but cannot
        escape into the parent shell loop.
  - [x] Invalid-context status and non-interactive abort behavior work.
  - [x] Invalid numeric operand status and abort behavior work.
  - [x] Baseline stderr diagnostic emission is covered.
  - [ ] Reference-shell wording review remains pending.
- [/] Implement full `cd`: HOME, `cd -`, `PWD`/`OLDPWD`, `-L`/`-P` option
  parsing, `CDPATH` search, command-local redirection of printed directory
  output, pipe-aware printed directory output, and Linux-native
  physical/logical symlink behavior work; exact diagnostics remain pending.
- [/] Implement full `eval`.
  - [x] Command-local output redirections apply to the evaluated body instead
        of leaking evaluated stdout to the caller.
- [/] Implement full `exec`: command form runs the target, returns its status,
  and stops subsequent non-interactive evaluation in marker-preserving eval
  mode; the real-exec profile uses AILang `execvp`/replacement where the host
  supports it and falls back to run-and-return on Windows. No-argument
  redirection-only form validates/creates targets and persists shell-local
  stdin/stdout metadata for `read`/`printf`; simple native external commands
  inherit persistent stdin/stdout metadata, and native external pipelines
  inherit persistent stdin on the first stage plus persistent stdout on the
  final stage. Shell-local command redirections and Linux-native external
  children preserve saved logical stdout/stdin fd metadata such as
  `exec >out; exec 3>&1; printf x >&3` and
  `exec >out; exec 3>&1; sh -c 'printf x >&3'`; shell-local reads also
  preserve duplicated logical stdin offsets for `exec <in; exec 3<&0`.
  POSIX builds use real `dup2` for saved fd-to-fd chains, so Linux-native
  children and pipeline children share fd5/fd6/fd7 input/output offsets after
  redirections such as `exec 6<in; exec 7<&6`. Linux-native fd8/fd9 graph
  tests now cover duplicate offset sharing, command-local and compound
  redirections reaching external children, append behavior, mixed pipeline fd
  chains, persistent current-stdin offset sharing through external children,
  persistent here-doc stdin/fd inheritance into external children, and subshell
  fd-close isolation. Broader process-graph fd inheritance remains pending.
- [/] Implement full `exit`: non-interactive evaluator stops subsequent commands and returns the requested status; process termination and interactive semantics remain pending.
- [/] Implement full `export`.
  - [x] Mark names exported.
  - [x] Assign and mark `name=value`.
  - [x] Print exported and exported-but-unset variables.
  - [x] Re-input-safe C/POSIX-profile `export -p` quoting and ordering.
- [/] Implement full `readonly`.
  - [x] Mark names readonly.
  - [x] Assign and mark `name=value`.
  - [x] Print readonly and readonly-but-unset variables.
  - [x] Prevent later assignment and unset.
  - [x] Readonly reassignment and readonly `unset` use the current WSL-sh
        status-2 profile.
  - [x] Re-input-safe C/POSIX-profile `readonly -p` quoting and ordering.
- [/] Implement full `return`: function and explicit dot-script return status
  works; invalid top-level context now returns status 2 and aborts
  non-interactive evaluation; baseline stderr diagnostic emission is covered.
  Reference-shell wording review remains pending.
- [/] Implement `read`.
  - [x] Read one line from redirected stdin.
  - [x] Read pipe-fed input in the shell-local pipeline proof.
  - [x] Read multiple records from shell-local pipeline and compound heredoc inputs without resetting the input offset.
  - [x] Assign multiple variables.
  - [x] Preserve remaining text for the final variable.
  - [x] Apply IFS whitespace/non-whitespace behavior for the current assignment path.
  - [x] Temporary assignment words are visible during regular `read` execution
        and are restored afterwards, including `IFS=: read A B` and
        `A=value read A`.
  - [x] Support `-r`.
  - [x] Process default backslash escapes and backslash-newline continuation.
  - [x] Reject invalid options and invalid variable names.
  - [x] Empty input returns failure and assigns empty variables.
  - [x] Unterminated final lines return failure while preserving assigned data.
  - [x] Persistent `exec <file` input offsets reach EOF with correct status.
  - [x] Missing variable, invalid option, and invalid variable diagnostics are covered.
  - [ ] Signal-interrupted and interactive read behavior remain pending.
- [x] Implement `pwd` for the current non-interactive profile.
  - [x] Direct stdout emits the current directory.
  - [x] `-L`, `-P`, and `--` are accepted.
  - [x] Invalid option diagnostics return status 2.
  - [x] `command -v pwd` and `type pwd` classify it as a shell builtin.
  - [x] Pipe capture and file redirection are covered by semantic probes.
- [/] Implement `printf`: shell-local output works for direct stdout,
  redirection, and pipe capture; `%s`, `%b`, `%c`, `%d`, `%i`, `%u`, `%o`,
  `%x`, `%X`, `%%`, format reuse, common backslash escapes, and octal escapes
  are covered by probes. Field width, `-` left alignment, numeric zero padding,
  string/`%b` precision, dynamic `*` width/precision, negative dynamic width,
  integer precision, signed numeric flags (`+` and space), alternate octal/hex
  forms (`#`), sign-aware zero padding, and `\c` stop-output behavior are
  covered by probes. Fixed decimal `%f`/`%F` formatting covers default and
  explicit precision, rounding, sign flags, width, zero padding, and alternate
  decimal-point output. Scientific/general `%e`/`%E`/`%g`/`%G` conversions
  cover common decimal inputs, rounding carry, fixed/scientific selection, and
  upper/lower exponent markers. Length modifiers `h`, `hh`, `l`, `ll`, `j`,
  `z`, `t`, and `L` are accepted for the currently supported integer and
  floating conversions. Byte-safe NUL output through direct stdout,
  redirection, and shell-local-to-external pipelines is covered by the
  Linux-native printf byte probe. Invalid directive status/diagnostics are
  covered for the current formatter. Hex floating conversions, NaN/Inf
  handling, wide character/string semantics, and full POSIX format language
  remain pending.
- [/] Implement full `set`.
  - [x] `set --` replaces positional parameters.
  - [x] No-operand `set` prints current shell variables with sorted,
        re-input-safe C/POSIX-profile quoting.
  - [x] `set -e` / `set +e` metadata and basic non-interactive sequence enforcement work.
  - [x] `set -e` suppresses non-interactive exit for failed AND/OR-list
        left-hand commands and `!` inverted commands in the current WSL
        differential corpus.
  - [x] `set -e` exits on failing assignment-only command substitution such
        as `X=$(false)`.
  - [x] `set -o option` / `set +o option` metadata works for recognized options.
  - [x] `set -C`, `set +C`, and `set -o noclobber` block or allow `>`
        redirection while `>|` force-clobbers, matching WSL `/bin/sh`.
  - [x] `set -o` and `set +o` print the recognized option set.
  - [x] `set -f` suppresses pathname expansion and `set +f` / `set +o noglob`
        re-enable pathname expansion.
  - [x] `set -a`, `set +a`, `set -o allexport`, and `set +o allexport`
        control exported assignment state in the covered non-interactive profile.
  - [x] `set -u`, `set +u`, `set -o nounset`, and `set +o nounset` control
        unset-parameter diagnostics in the covered non-interactive profile.
  - [x] `command set` preserves option side effects for the covered
        `allexport`, `nounset`, `noglob`, and `noclobber` slice.
  - [x] `set -n` parses but skips subsequent execution, including a later
        `set +n` in the same non-interactive input.
  - [x] `set -x` xtrace emits WSL-compatible simple-command traces for default,
        empty, and explicit `PS4`, assignment-only commands, command-local
        assignments, and `set +x`.
  - [x] `set -v` / `set -o verbose` emits WSL-compatible non-interactive input
        read-unit text for following lines and stops after `set +v` /
        `set +o verbose`.
  - [ ] Interactive `monitor` option semantics remain pending.
- [/] Implement `getopts`.
  - [x] Maintains `OPTIND` and `OPTARG`.
  - [x] Parses positional parameters and explicit operand lists.
  - [x] Handles clustered options, inline option arguments, and next-argument
        option arguments.
  - [x] Handles invalid options and missing arguments, including silent
        optstring mode.
  - [x] Matches WSL `/bin/sh` for manual `OPTIND` reset in the middle of an
        option cluster, invalid `OPTIND` fatality, zero/plus/out-of-range
        `OPTIND` handling, end-of-scan `OPTARG` preservation, and empty,
        colon-only, dash, and question-mark optstrings in the generated
        regular-builtin matrix.
  - [ ] Broader conformance-sized `getopts` corpus and locale-specific
        diagnostic wording remain pending.
- [/] Implement `jobs`.
  - [x] No-operand `jobs` lists shell-local completed and running
        non-interactive background metadata.
  - [x] `jobs -l` includes the shell-local job id/pid field.
  - [x] `jobs -p` emits process ids for matching jobs.
  - [x] Explicit `jobs %N` operands select individual jobs in the Linux-native
        job-control probe.
  - [x] `%string` and `%?string` job references are covered for `jobs`, with
        ambiguous references rejected in the Linux-native job-control probe.
  - [x] Current and previous jobs are marked with `+` and `-`, and `%%`, `%+`,
        `%-`, and `bg %+` are covered in the Linux-native job-control probe.
  - [x] Running external jobs are polled and displayed as running until they
        complete.
  - [x] Invalid option diagnostics are covered.
  - [/] Full login-shell job-control behavior remains pending; monitor-mode
        background process groups, current/previous markers, `fg` terminal
        handoff/restoration, and stopped-aware waits are covered by the
        Linux-native job-control probe.
- [/] Implement `kill`.
  - [x] `kill -l`, `kill -l NUMBER`, and invalid non-decimal `kill -l`
        operands are covered against WSL `/bin/sh`.
  - [x] `kill -SIGNAL $$` and `kill -s SIGNAL $$` dispatch stored shell traps
        for the current non-interactive shell process.
  - [x] `kill -SIGNAL pid` delivers to real child/peer process handles through
        the AILang process runtime in the current hosted profile.
  - [x] Missing operand, invalid signal, invalid pid, and no-such-process
        diagnostics are covered; no-such-process status is `1`, matching WSL
        `/bin/sh`, bash, and zsh for `kill -0`/dead PID cases.
  - [x] Native OS signal hooks for trapped current-process signals drain into
        the shell-side trap/status dispatcher in the hosted profile.
- [/] Implement full `trap`.
  - [x] Store trap actions.
  - [x] Reset trap actions.
  - [x] List stored trap actions with re-input-safe shell quoting in the
        current C/POSIX profile.
- [/] Execute trap actions on signal/event delivery: `EXIT` traps run through
  the public evaluator, shell-side pending-signal traps run through the
  internal dispatcher, and hosted native trapped signals drain into that
  dispatcher; interactive/job-control trap semantics remain pending.
- [/] Implement full `umask`: no-operand octal output, octal mask write,
  normalized shell-state storage, `-S` symbolic output, core symbolic mask
  operands (`u/g/o/a` with `+`, `-`, `=` and `rwx`), and symbolic copy forms
  such as `g=u`, `o+u`, and `o-u` work; host process umask is now applied to
  shell-local redirection-created files through the Linux-native
  filesystem/profile probe; symbolic `s` is accepted as a permission-neutral
  setuid/setgid form matching WSL `/bin/sh`, while sticky `t` remains rejected
  as an illegal mode.
- [/] Implement full `wait`: no-operand waits all known running
  non-interactive background jobs and returns success when no failures occur;
  background jobs record real child PIDs, `$!` expands to the last spawned PID,
  `wait $!` waits for that child or returns the recorded status, unknown ids
  return 127, and invalid pid operands return status 2 with diagnostics.
  Basic monitor-mode job references are now parsed for `kill %N`, `bg`, `fg`,
  `jobs %N`, `jobs %%`, `jobs %+`, `jobs %-`, and `jobs %string` /
  `jobs %?string`; `jobs -p` emits matching process ids, ambiguous job
  references are rejected, current/previous jobs are marked with `+`/`-`, job
  display uses simple command text instead of internal AST text, and
  Linux-native stopped jobs are detected, resumed by `bg`/`fg`, and kept out of
  stale `%1/%2` slots after `wait`. Monitor-mode simple background commands are
  spawned into their own
  process group, native external background pipelines are spawned into a shared
  process group, `kill %pipeline` delivers to the pipeline group, and `fg`
  performs terminal process-group handoff/restoration around a stopped-aware
  wait in the Linux-native probe. Full login-shell interactive job-control
  integration remains pending.
- [/] Implement special builtin error semantics: assignment and redirection
  failures, selected operand/context errors, and dot-source failures now use the
  central non-interactive exit consequence; the remaining POSIX special-builtin
  matrix remains pending.

Completion gate:

```text
All POSIX special builtins and regular shell builtins behave correctly in
scripts and affect shell state where required.
```

## Phase 6: Native Execution

- [x] Execute external simple commands through native argv handoff.
- [x] Pass exported shell variables to native simple external commands.
- [x] Pass exported shell variables to native external pipeline commands.
- [x] Execute external command pipelines through native pipe/wait handling.
- [x] Flatten multi-stage external pipelines into native argv vectors.
- [x] Apply persistent `exec` stdin/stdout metadata to native external pipelines:
      stdin is injected into the first stage, stdout into the final stage, and
      explicit command redirections override it by normal left-to-right order.
- [x] Return 127 for missing explicit path commands.
- [x] Apply native redirections in recorded order for `<`, `>`, `>>`, `<>`, `<&`, `>&`, `>|`.
- [x] Feed here-document bodies through stdin.
- [/] Command search supports builtin/function/PATH probing in the current slice.
  - [x] Aliases are discovered by `command -v`, verbose `command -V`, and `type`.
  - [x] Functions are discovered by command lookup.
  - [x] Functions override regular pure-status builtins in execution search
        order for the current blocker-probed slice.
  - [x] Special and regular builtins are discovered by command lookup.
  - [x] Extensionless text shell scripts are discovered through explicit shell `PATH`.
  - [x] Native command existence probing exists for direct names and `PATH`
        entries without calling a hosted shell.
  - [x] POSIX-target native probing uses executable-permission checks for
        direct names and `PATH` entries.
  - [x] Native argv execution resolves shell-state `PATH` entries before
        process launch, instead of relying on the parent process environment.
  - [x] Unqualified `PATH` directory entries are skipped as non-commands;
        if no later command wins they report status 127 with permission wording,
        while explicit directory paths still report permission-denied status 126.
  - [x] Explicit directory path lookup through `command -v`, `command -V`,
        and `type` reports the path, while actual direct or `command` execution
        returns status 126 with permission-denied diagnostics.
  - [x] `command` suppresses alias execution while lookup utilities still
        report aliases, matching the WSL `/bin/sh` covered slice.
  - [x] `command -p` actual external execution uses the hosted default path and
        is covered by `msh_command_search_probe.py`.
  - [x] Explicit text-script fallback under `command` and `command -p` is
        covered against WSL `/bin/sh`.
  - [ ] Exact POSIX search order and diagnostics matrix remains pending.
- [x] Run shell scripts found by command search with `msh`: extension-agnostic text script candidates found through explicit shell `PATH` or explicit paths execute in isolated shell state and return status; native errno-driven ENOEXEC detection is wired through the AILang process runtime. POSIX-target script fallback requires executable permission and cannot bypass a non-executable text candidate on non-Windows builds. Script candidates in pipelines are classified as shell-local stages so producer and consumer scripts are evaluated by `msh` rather than libc shell fallback.
- [x] Bridge simple external-command stdout into shell-local right-side pipeline commands such as `external | read`.
- [x] Feed shell-local pipeline output into external right-side commands such as `printf hello | grep hello`; explicit right-side stdin redirections still override the pipe input.
- [x] Capture native external pipeline stdout for mixed shell-local consumers such as `external | external | read`.
- [/] Execute compound commands inside pipelines natively: status, subshell state isolation, shell-local `printf`, shell-local `while read`, shell-local grouped `read`, `cd` printed output, `command -v/-V`, `alias`, `set`, `umask`, `times`, `readonly -p`, ignored-trap listing, action-trap reset, parent `EXIT` trap preservation, external command stdout, extensionless shell-script stdout, and multi-stage external pipeline stdout are covered; the current hosted-safe pipeline-builtin output slice is WSL-matched; broader nested/external process-graph coverage remains pending.
- [/] Execute functions inside pipelines natively: status, subshell state isolation, shell-local `printf`, `cd` printed output, `command -v/-V`, `alias`, `set`, `umask`, `readonly -p`, ignored-trap listing, action-trap reset, external command stdout, extensionless shell-script stdout, and multi-stage external pipeline stdout are covered; the current hosted-safe pipeline-builtin output slice is WSL-matched; broader nested/external process-graph coverage remains pending.
- [x] Execute shell-local `read` from redirected stdin for regular file inputs.
- [/] Implement async/background execution for `&`: non-interactive background
  lists spawn through a child `msh` AST evaluator, record real child PID/status
  metadata, expose `$!`, support polling through `jobs`, support `wait $!`, and
  cover builtins, functions, groups, redirections, and compound lists in the
  current fd/process matrix. Basic monitor-mode `kill %N`, `bg`, and `fg`
  dispatch exists over the shell job table, and the Linux-native job-control
  probe covers stopped-job polling plus `SIGCONT` resume paths. Terminal
  process groups and full interactive job-control behavior remain pending.
- [/] Implement exact exit status rules for signals: shell-side signal status
  mapping uses `128 + signal`, and child wait status normalizes signaled exits
  to `128 + signal` where the host exposes that information. Hosted native
  trapped signals drain into the shell dispatcher; broader
  interactive/job-control signal status behavior remains pending.
- [/] Implement exact command search order for aliases, special builtins,
  functions, builtins, PATH, and scripts: alias lookup, verbose lookup,
  type lookup, shell-state PATH argv resolution, empty-path current-directory
  behavior, host-PATH non-leakage, unqualified `PATH` directory skipping,
  `command -p -v` default-path lookup, `command -p` external execution, and the function-over-regular-builtin
  blocker are covered; executable binary garbage rejection and text-script
  producer/consumer pipeline fallback are covered by the Linux-native probe;
  the generated WSL-backed command-search matrix covers 170 hosted-safe lookup,
  dispatch, explicit-path, option, `PATH`, alias/function precedence, special/reserved
  function-name rejection, and diagnostic cases; broader
  chmod-sensitive and exhaustive diagnostics remain pending.

Completion gate:

```text
No normal shell execution path uses hosted `system(...)` or host shell command
line reconstruction.
```

## Phase 7: Redirections And File Descriptors

- [x] Parse and preserve redirection order.
- [x] Apply common file redirections.
- [x] Apply append, clobber, force-clobber, and noclobber redirections.
- [x] Apply duplicated input/output redirections in the current runtime.
- [x] Capture and feed here-documents.
- [/] Preserve and restore fd state around builtins and compound commands.
  - [x] Save and restore stdio around group redirection.
  - [x] Save and restore stdio around subshell redirection.
  - [x] Save and restore stdio around shell-local `printf` / `read`.
  - [x] Save and restore stdio around command-invoked output builtins in the
        current slice.
  - [x] Tested function/group/subshell/if/while/for/case stdout redirection.
  - [x] Persistent `exec` fd metadata works for shell-local stdin/stdout and
        simple native external commands in the current non-interactive evaluator.
  - [x] Persistent `exec` fd metadata works for native external pipelines:
        stdin feeds the first stage and stdout captures the final stage.
  - [x] Persistent `exec` stdout metadata routes shell-local output helpers
        used by `type`, `alias`, `trap`, `umask`, `cd`, `jobs`, `kill -l`,
        `set`, `export -p`, and `readonly -p`.
  - [x] Persistent `exec` stderr redirection captures shell diagnostics and
        shell-local fd2 output in the current non-interactive profile.
  - [x] Arbitrary fd duplication/restoration for stderr such as `exec 4>&2`,
        `exec 2>file`, and `exec 2>&4` is covered by file-suite tests.
  - [x] Heredoc temp files are cleaned after stdio restoration and covered by
        selftest, including the Windows-hosted fd lifetime case.
  - [x] Hosted fd/process matrix covers 169 WSL-matched persistent-fd,
        compound-redirection, shell-local pipeline, redirection-ordering,
        noclobber, heredoc, stderr-fd, fd8/fd9 shell-local, background,
        redirection-error, read-write `<>`, pipeline builtin output/dataflow,
        and redirection-only cases,
        including exact diagnostics for missing-parent input/output
        redirections, directory output redirections, `<>` read/write
        failures, and WSL-matched `<>` create/no-truncate/shared-offset
        behavior through command-local and compound-command fd restoration,
        plus command/function/group/subshell stderr-close isolation after a
        persistent logical `exec 2>&fd` mapping.
- [/] Apply redirections to functions, groups, subshells, loops, and conditionals.
  - [x] Groups.
  - [x] Subshells.
  - [x] Function-definition trailing redirection.
  - [x] `if`.
  - [x] `while`.
  - [x] `for`.
  - [x] `case`.
  - [x] Compound-command heredoc redirection feeds groups and loops through the same decoded heredoc body path as simple commands.
  - [x] Persistent `exec` stdin/stdout effects are covered for shell-local
        functions, groups, `if`, `while`, `for`, and `case` in the current
        non-interactive profile.
- [/] Implement redirection-only command behavior: file redirections create/open
  targets, and `exec` redirection-only persists shell-local stdin/stdout metadata;
  simple native external commands, native external pipelines, and shell-local
  output helpers inherit the metadata; saved logical stdout through fd3 is
  covered for shell-local command redirections, Linux-native external child
  commands, and Linux-native mixed shell-local-to-external pipelines. Arbitrary
  shell-local output fd opens and closes such as `exec 3>file`, `>&3`, and
  `3>&-` are covered against WSL `/bin/sh`. Simulated subshell execution now
  snapshots/restores real fds 3..63, so subshell fd closes such as
  `(exec 8>&-)` do not leak into the parent shell. Saved
  logical stdin through fd3 is covered for shell-local duplicated-input reads,
  and Linux-native child processes inherit file-backed saved stdin fds,
  including consumed input offsets at child launch time and post-child offset
  reconciliation after native children consume duplicated stdin fd3.
  Shell-local fd5/fd6/fd7 output chains and duplicated input-fd offset sharing
  through `7<&6` are covered against WSL `/bin/sh`. Closed arbitrary input fds
  such as `3<&-` are covered in the shell-local profile, and the Linux fd graph
  probe covers fd8/fd9 child/process sharing plus persistent file and here-doc
  stdin/fd inheritance into external children, while the generated hosted
  fd/process matrix covers 169 shell-local process/fd cases, including
  persistent `exec` here-doc stdin/fd handling and command-local input
  duplication followed by retargeting the source fd, such as
  `read I <&3 3< inner`, with WSL-matched open-file-description offset
  restoration, successful `<>` read/write fd offset sharing and local
  command/compound fd restoration, and WSL-matched pipeline dataflow for
  `echo`, `printf`, `pwd`, `command -v/-V`, `type`, `alias`, `export -p`,
  `readonly -p`, `set`, `umask`, `times`, `trap`, `jobs`, `kill -l`,
  `ulimit`, `hash`, and pipeline-local `read`, plus command/function/group/
  subshell stderr-close restoration after persistent `exec 2>&fd`. The
  Linux-native arbitrary-fd matrix covers fd `3..12` and `19` inheritance,
  duplication, close isolation, command-local/group/pipeline redirection,
  append, input offsets, heredoc-backed fds, and read/write `<>` shared-offset cases against WSL `bash --posix`;
  deeper nested process-graph coverage remains pending.
- [/] Validate ambiguous redirect errors after expansion: field-split ambiguous
  targets now return status 2 before execution and emit an ambiguous-redirect
  diagnostic; full POSIX differential coverage remains pending.
- [/] Validate redirection failure status and special builtin consequences:
  redirection-only open failures, builtin output create failures, external
  command redirection failures, and failing special-builtin redirections return
  status 2 and emit diagnostics; special-builtin failures abort non-interactive
  evaluation. Missing-input redirection failures are covered across direct,
  `command`, `eval`, and `command eval` forms for `readonly`, `set`, `shift`,
  `times`, `trap`, and `unset`. Bad duplicated-fd failures are covered for direct special
  builtins, `command`-wrapped special builtins, redirection-only commands,
  `exec`, `command exec`, and left-to-right truncation-before-failure ordering.
  Noclobber failures are covered for direct special builtins, `eval`-wrapped
  special builtins, `command`-wrapped special builtins, and redirection-only
  commands against WSL `/bin/sh`. Nonnumeric duplicated-fd targets are covered for regular commands, special builtins, `command`-wrapped specials, and redirection-only commands against WSL `/bin/sh`.
  Broader fd/open error matrix remains pending.

Completion gate:

```text
Every command node can receive redirections with exact POSIX ordering and error
behavior.
```

## Phase 8: Interactive Shell

- [/] Prompt handling: Linux pty probe covers expanded PS1 prompt output and
  expanded PS2 continuation prompt output to the terminal stream; broader
  prompt escape/display behavior remains pending.
- [/] Interactive input loop: `msh -i` reads and evaluates one line at a time
  with persistent shell state in a Linux pty; quote, compound-command, and
  pipeline continuation are covered, while broader interactive recovery
  matrices remain pending.
- [x] EOF handling is covered by Linux pty probe, including final EXIT trap
  delivery and last-status preservation.
- [/] Signal behavior for interactive mode: Linux pty probe covers default
  SIGINT at a prompt setting `$?` to `130`, trapped SIGINT at a prompt running
  the trap action while preserving `$?`, explicit `exit 130`, terminal Ctrl-C
  interrupting a foreground external command while keeping the shell alive with
  `$?=130`, and terminal Ctrl-\ interrupting a foreground external command
  while keeping the shell alive with `$?=131`; broader job-control signal
  behavior remains pending.
- [/] Job control: Linux-native stopped-job polling, monitor-mode background
  process groups for simple commands and native external pipelines, `kill`
  delivery to pipeline process groups, `bg`/`fg` resume paths, `fg` completion
  after terminal Ctrl-Z, `bg`/`wait` completion after terminal Ctrl-Z, and
  `wait` stale-job cleanup are covered by a non-login pty-style probe; full
  login-shell monitor mode remains pending.
- [/] Terminal process group handling: `fg` hands the terminal to the resumed
  job process group and restores the shell process group in the Linux-native
  probe; startup/session ownership and full interactive login-shell behavior
  remain pending.
- [ ] Optional line editing.
- [ ] Optional history.

Completion gate:

```text
`msh` can be used as an interactive login shell without breaking script
semantics.
```

## Phase 9: Diagnostics And Errors

- [/] Parser failures return status 2.
- [/] Parameter expansion errors return status 2 in the current evaluator.
- [/] Source locations for parser and expansion diagnostics: parser AST source-map sidecar exists; expansion/runtime diagnostics still need location plumbing.
- [/] POSIX-consistent fatal/non-fatal error behavior for interactive and non-interactive shells: parameter expansion errors, special-builtin assignment failures, and special-builtin redirection failures stop the current non-interactive evaluator; `command eval` now distinguishes fatal operand field-expansion errors from WSL-compatible nonfatal eval-script expansion errors for selected parameter, bad-substitution, nonnumeric arithmetic, readonly arithmetic, and division-by-zero cases; full interactive/special-builtin matrix remains pending.
- [/] Redirection errors with exact messages and status: special-builtin
  redirection failures now have fatal non-interactive status behavior; missing
  input, create failure, bad operator, and ambiguous-target diagnostics are
  covered in the current probes. Full POSIX wording matrix remains pending.
- [/] Special builtin error consequences: assignment and redirection failures
  are implemented; operand/context errors remain pending.
- [/] Command not found and permission denied distinctions for simple native
  external commands and native pipeline tail commands; missing simple command
  diagnostics and missing pipeline-stage diagnostics are covered. Directory
  command attempts return 126 and emit permission-denied diagnostics before
  native execution or script fallback; broader search-order reporting remains
  pending.

Completion gate:

```text
Error behavior is deterministic, testable, and follows POSIX where POSIX
specifies the result.
```

## Phase 10: Conformance Testing

- [x] `msh_cli.exe selftest` exists.
- [x] Leak-report validation is required for `msh` behavior changes.
- [x] Tranche runner exists: `python tools/mixtar_tranche.py` rebuilds `msh`, runs WSL shell differentials, semantic/blocker probes, leak selftest, and the shell line guard.
- [x] AILang god-object audit remains clean under the 800-line rule.
- [x] Near-limit shell modules are split into focused helpers: `msh_printf_base.ail`, `msh_lexer_helpers.ail`, `msh_exec_fds_core.ail`, and `msh_exec_ast_helpers.ail` keep `printf`, lexer, fd metadata, and shared AST string helpers below the line guard.
- [x] Focused semantic regression probe exists for the currently claimed evaluator subset.
- [x] Executable blocker probe exists for hard POSIX blockers that must not be
      hidden by roadmap optimism.
- [x] WSL shell differential harness exists for POSIX-profile behavior against
      WSL `sh`, `bash --posix`, plain `bash`, and `zsh --emulate sh`.
- [x] File-based POSIX core suite harness exists:
      `tools/msh_posix_suite.py` discovers ordinary `.sh` cases under
      `suites/posix-core`, compares them with WSL `/bin/sh`, writes generated
      reports, and runs as part of `tools/mixtar_tranche.py`.
- [x] Generated POSIX stress suite exists:
      `tools/msh_generate_posix_stress_suite.py` writes shell-only stress cases
      under `suites/posix-stress`; `tools/msh_finish_line.py` gates the suite
      through `tools/msh_posix_suite.py`. The current WSL-backed strict result
      is `261/261` POSIX-profile matches from the generated corpus.
      The current corpus includes parameter-error stderr routing,
      command-local function redirection, and `EXIT` trap `exit N` final-status
      coverage. It also covers function temporary-assignment visibility,
      standalone empty `"$@"`, heredoc expansion suppression, leading
      redirections before command/function names, function input redirection,
      function status/isolation behavior, invalid-name `export`/`readonly`
      consequences through direct, `eval`, `command`, and `command eval`
      paths, direct/`command` invalid `set` options, readonly arithmetic
      assignment and compound-assignment aborts, invalid nonnumeric and octal
      arithmetic variable values, textual parameter and command-substitution
      expansion before arithmetic parsing, and bad-fd redirection
      consequences including `eval:` diagnostic context and left-to-right
      truncation-before-failure ordering. It also covers readonly `unset`
      consequences through direct, `eval`, `command`, and `command eval`
      paths, closed-fd output failures, and nonnumeric duplicated-fd syntax
      through direct and `command` special-builtin paths. It now also covers
      alias read-unit timing for aliases defined before compound bodies, aliases
      defined inside the same `if`/`for`/`while`/`until`/`case`/group/subshell
      compound body, alias activation after a newline before `&&`, heredoc-
      separated alias activation, reserved-word alias suppression, aliases
      after same-line `if`/`then`/`do`/`!` command-position openers,
      function-body alias non-activation, compound
      input/output redirections for loops and groups, `elif` linebreak parsing,
      AND/OR line continuation, append redirection around `case`, nested
      function/while/case parsing, and subshell redirection state isolation.
      The current tranche adds WSL-backed coverage for arithmetic shift and
      bitwise operators, their precedence, and compound assignments, plus
      multiline command substitution storage/splitting, nested default-word expansion, braced
      positional parameters beyond `$9`, empty-IFS suppression, path trim
      expansion, leading-parenthesis `case` patterns, implicit-positionals
      `for`, explicit-empty `for in`, negated grouped pipelines, heredoc
      command substitution and backslash-newline joining, source-fd retarget
      offset restoration, `errexit` AND/OR-list contexts, logical `cd ..`,
      noisy `getopts` missing-argument behavior, and `trap 0`.
      The next tranche adds WSL-backed POSIX `printf` numeric character
      operands, backslash-newline format preservation, star width/precision,
      sign/alternate formatting, `\c` stop behavior, `read` cooked/raw
      backslash-newline behavior, final-variable separator preservation,
      empty-input `read` status, `cd -`, `cd -P`, `pwd -L`, and `pwd -P`;
      the Linux-native filesystem/profile probe now adds real symlink-backed
      checks for default logical `cd`, `cd -L`, `cd -P`, and `cd -`.
      This tranche adds WSL-backed coverage for function definitions whose
      body starts after a linebreak, plus `errexit` suppression through shell
      functions evaluated as `if` and `while` conditions.
      The latest tranche also covers unquoted `$*` splitting with
      non-whitespace and empty `IFS`, embedded unquoted `$*` field generation,
      `${var=$*}` assignment-word expansion, and script-file `$0` basename
      expansion through the suite runner's `msh-run: file` mode. File-mode
      suite metadata now also supports `msh-args`, and the stress suite covers
      script positional arguments through `$#`, `$1`, and `$2`.
      Pipe-aware builtin-output coverage now includes `kill -l`, `trap`,
      `export -p`, `type`, and `command -V` feeding `read` through pipelines.
      Shell-local pipeline capture now masks inherited persistent `exec`
      stdout metadata before stage-local redirections are applied, so
      command-local pipeline redirections override persistent shell stdout in
      the covered WSL-compatible slice.
      The latest tranche adds WSL-backed coverage for `return` outside a
      function/sourced script through direct `eval` and `command eval`,
      readonly-assignment fatality before special builtins versus nonfatal
      command-wrapped/regular-builtin paths, background group/pipeline `$!`
      wait behavior, multi-operand and unknown-pid `wait`, command-local fd
      restoration when function-call redirections overlap body `exec` fd
      changes, persistent function-body `exec` on unrelated fds, group `exec`
      fd close persistence, and case linebreaks before `esac`.
      Shell-local POSIX `echo` now covers `-n`, escape decoding, `\c`, and
      `/dev/null`/`/dev/full` exit-code parity in the imported Smoosh gate;
      the generated regular-builtin matrix also covers no-operand output,
      operand joining, literal `-e` / `--`, octal escapes, and redirected
      output.
      Parameter pattern removal now preserves quoted pattern metacharacters
      inside `${...}` and handles escaped backslash suffixes in imported
      Smoosh script-file cases.
- [x] Generated special-builtin matrix exists:
      `tools/msh_special_builtin_matrix.py` generates direct, `eval`,
      `command`, and `command eval` fatal/nonfatal cases for selected POSIX
      special-builtin errors. It currently compares 771 cases against WSL
      `/bin/sh`, including direct and `command eval` parse-error diagnostics,
      eval readonly `unset -v` fatality across newline/semicolon boundaries,
      and operand field-expansion parameter-error, bad-substitution, and
      division-by-zero behavior for every POSIX special builtin across direct,
      `eval`, `command`, and `command eval` forms; it runs as part of
      `tools/msh_finish_line.py`.
- [x] Generated command-search matrix exists:
      `tools/msh_command_search_matrix.py` compares 170 hosted-safe lookup,
      dispatch, explicit-path, default-path, option, empty-`PATH`,
      alias/function precedence, special/reserved function-name rejection, and
      diagnostic cases against WSL `/bin/sh` and runs as part of
      `tools/msh_finish_line.py`.
- [x] Generated fd/process matrix exists:
      `tools/msh_fd_process_matrix.py` compares 169 hosted-safe persistent-fd,
      compound-redirection, shell-local pipeline, heredoc, stderr-fd,
      redirection-ordering, noclobber, redirection-error, read-write `<>`,
      pipeline-builtin output/dataflow, background, and redirection-only cases
      against WSL `/bin/sh` and runs as part of
      `tools/msh_finish_line.py`. Its stderr-sensitive redirection-error slice
      covers missing-parent input/output failures, directory create/append/
      force-clobber failures, and `<>` read/write directory/missing-parent
      failures; its read-write slice covers `<>` create/no-truncate,
      fd3 read/write shared offsets, and command-local plus compound-command
      restoration; its pipeline-builtin slice covers output/dataflow for
      `echo`, `printf`, `pwd`, `command -v/-V`, `type`, `alias`, `export -p`,
      `readonly -p`, `set`, `umask`, `times`, `trap`, `jobs`, `kill -l`,
      `ulimit`, `hash`, and pipeline-local `read`; its stderr-fd slice covers
      command/function/group/subshell stderr-close isolation after persistent
      `exec 2>&fd`.
- [x] POSIX Issue 8 multi-digit fd matrix exists:
      `tools/msh_issue8_fd_matrix.py` compares 8 one-or-more-digit fd-prefix
      redirection cases against WSL `bash --posix`, covering fd10/fd11 output,
      input-offset sharing, read/write `<>` offset sharing, heredocs,
      command-local/group-local restoration, and pipeline-stage fd routing.
      This is tracked separately because WSL `/bin/sh` rejects `10>file`
      even though POSIX.1-2024 permits one or more digits before a
      redirection operator.
- [x] Generated signal/trap matrix exists:
      `tools/msh_signal_trap_matrix.py` compares 72 hosted-safe
      non-interactive `EXIT`, trap listing/reset/ignore, shell-side
      self-signal, subshell `kill $$`, pipeline trap, command-wrapped trap/kill,
      diagnostic-status, `kill -l` signal/exit-status mapping, and background
      wait cases against WSL `/bin/sh` and runs as part of
      `tools/msh_finish_line.py`. It deliberately does not
      claim exact untrapped process-termination encoding or interactive
      job-control `jobs` formatting. Exact `kill` diagnostic bodies for the
      covered missing-operand, bad-signal, illegal-pid, and invalid
      signal-exit-status cases are compared against WSL `/bin/sh`.
- [x] Focused trap recursion regressions are covered:
      inherited active `EXIT` trap actions are not recursively re-entered by
      subshells created from the same trap body, while subshells that install a
      new `EXIT` action can still run it. The focused Smoosh trap probe passes
      3/3, and the imported Smoosh gate is now 163/163 in the WSL-backed
      finish-line gate. Additional imported cases cover ordinary subshell reset
      of inherited parent `EXIT` traps, parent trap listing suppression in
      subshells, local `EXIT` traps captured by command substitution, and
      direct `eval` parse-error fatality in non-interactive scripts.
- [x] Current blocker probe status: 6 closed / 0 open for the tracked hard
      blockers: alias read-unit activation, function-over-regular-builtin
      search, top-level `EXIT` trap, persistent `exec` stdin/stdout, and
      background list execution.
- [/] Add a POSIX expansion test corpus: semantic probe covers parameter defaults/assignment/error, `$#` zero and populated positional counts, quoted empty positional fields, `$*`, `$@`, shift, pattern trim, stateful assignment expansion, line-anchored variable lookup when internal metadata contains `NAME=` substrings, and explicit `msh` arithmetic extension behavior for prefix/postfix `++`/`--` plus comma expressions; WSL shell diff covers arithmetic expansion with blanks, comparison, equality, logical operators, conditional `?:`, arithmetic assignment operators, assignment-word command substitution, nested command substitution, arithmetic/parameter close skipping inside command substitution, backquote substitution, quoted `$@`, quoted `$*`, IFS splitting, pathname expansion with `set -f`, and the extension-profile arithmetic cases separately from the strict POSIX-profile corpus; imported Smoosh now covers quoted pattern metacharacters inside `${name#word}`, escaped backslash pattern suffixes, and unquoted empty expansion suppression when `IFS` is null, dependency-free recursive function arithmetic, while-loop arithmetic, dot PATH search, and nested redirection-depth behavior; broader corpus remains pending.
- [/] Add a POSIX parser test corpus: semantic probe covers common valid/invalid grammar cases, imported Smoosh now covers direct `eval` parse-error fatality in non-interactive scripts, and the generated special-builtin matrix covers WSL-compatible direct and `command eval` syntax-error diagnostics for incomplete `if`, `for`, `case`, and subshell forms; full parser corpus remains pending.
- [/] Add a builtin behavior test corpus: semantic probe covers core status/control builtins, including numeric `break`/`continue`, invalid-context diagnostics, invalid operand diagnostics, readonly `unset`, invalid `umask`, invalid `export`/`readonly`, invalid `command` option diagnostics, invalid `printf` directive diagnostics, invalid `pwd` option diagnostics, diagnostics for `set`, `times`, `trap`, `wait`, `getopts`, `jobs`, `kill`, and `unalias`, readonly violation status-2 behavior, numeric `trap` signal canonicalization, rejected `SIG*` trap operands, shell-side self-signal trap dispatch, non-interactive fatal consequences for selected direct special-builtin failures, and file-suite coverage for nonfatal `command export`/`readonly`/`set`/`shift`/`unset` operand errors plus `command eval` suppression for selected special-builtin errors; normalized-stderr file-suite cases now cover `eval`/`command eval` diagnostics for invalid `export`, invalid `readonly`, invalid `set`, direct/`command` invalid `trap`, and invalid numeric `exit`/`return`/`break`/`continue`; file-suite status/output cases now cover fatal `eval` wrappers for invalid `export`, invalid `readonly`, invalid `set`, too-large `shift`, readonly `unset`, direct/`command`/`eval`/`command eval` `times` extra operands, `unset -z`, WSL-compatible `shift` extra operands, `trap -l`, direct/`command` extra operands for `return` and `exit`, direct/`command`/`eval`/`command eval` `set` plain operands, `set` option-plus-operand forms, and single-dash operand handling, nonfatal `command eval` missing-source behavior, and temporary assignment restoration for `command set`, `command shift`, `command break`, `command continue`, `command return`, invalid `command exit`, and missing-source `command .`; the generated regular-builtin matrix now covers 233 WSL `/bin/sh` cases including additional `getopts` `OPTIND` state/fatality, unusual-optstring behavior, `read` readonly/escaped-delimiter behavior, POSIX-compatible `umask` symbolic `s` handling, and `test`/`[` historical argc/parser edge diagnostics; full builtin corpus remains pending.
- [/] Add command-output tests: semantic probe covers supported alias/function/
  builtin `command -v/-V`, missing-operand `command -v/-V`, `type`, type
  missing-name output, pipe-aware lookup output, `command --`
  builtin status behavior, `pwd` output/classification/capture, core and copy-form symbolic `umask` output, and the current
  `jobs` output, `kill -l` output, `getopts` state behavior, and current
  `printf` integer/string conversion, escape, flag, static-and-dynamic-width,
  precision, alternate-form, length modifiers, fixed-decimal float,
  scientific/general float, invalid-directive, and stop-output slice; broader
  output corpus remains pending. WSL shell diff additionally covers direct
  output redirection for `type`, `trap`, `export -p`, `readonly -p`, `set`,
  `umask`, and `times`, plus closed-stdout write-failure status/diagnostics
  for `alias`, `export -p`, `readonly -p`, `set`, `umask`, `trap`, `type`,
  `command -v`, and `kill -l`; re-input-safe alias listing and named alias
  query output remain covered.
- [/] Add command-search tests: semantic probe covers shell `PATH`
  extensionless script execution, empty-path current-directory lookup,
  Windows-host `PATH` non-leakage, explicit directory-as-command status/diagnostics,
  unqualified `PATH` directory skipping for execution/lookup, `command -p -v` / `command -p -V`
  default-path lookup for the POSIX `sh` utility, `command -p` external execution,
  alias-aware lookup, `type`, WSL-normalized file-suite stderr diagnostics for
  missing simple commands, missing explicit paths, and missing non-tail/tail
  pipeline stages, `command -V` missing-name output, WSL-compatible verbose
  function wording, and blocker probe covers functions overriding
  regular builtins; selftest covers Windows-hosted shell-state PATH native
  resolution. AILang C-backend tests cover `access(path, mode)` and
  `file_can_execute(path)` as the primitive needed for Linux-native
  non-executable `PATH` checks, Linux default-path `command -p sh -c` execution, and `msh_linux_command_search_probe.py`
  verifies chmod-based lookup behavior, only-non-executable `PATH` lookup
  through `command -v`, `command -V`, and `type`, executable text-script fallback, and
  runtime-level ENOEXEC fallback through `command -p ./script` / `exec ./script`,
  explicit/`PATH`/`command -p` executable binary garbage rejection with
  exec-format diagnostics, text-script producer/consumer pipeline fallback,
  plus non-executable pipeline-stage status/diagnostics, saved logical
  stdout/stdin fd3 inheritance end to end on WSL, fd5/fd6/fd7 native-child
  plus mixed-pipeline duplication chains, and fd8/fd9 graph behavior through
  `msh_linux_fd_graph_probe.py`. The file-based suite covers
  reserved-word lookup, POSIX default-path `sh` lookup, explicit
  non-executable regular path lookup, explicit directory path lookup/execution, current-directory
  permission-denied diagnostics for direct, `command`, and pipeline-stage
  execution, `command` alias-execution suppression, mixed `type` missing-name status, direct special-builtin assignment persistence for `:`, `.`, `export`, and `readonly`, and `hash` regular-builtin
  lookup/execution through direct, `command`, `command -v`, `command -V`,
  and `type`. The generated command-search matrix now gates 170 additional
  WSL `/bin/sh` comparisons for reserved-word lookup, alias/function lookup
  and suppression, special/regular builtin lookup, PATH ordering, directory
  skipping, empty-path current-directory execution, host-PATH non-leakage,
  unset-`PATH` dot-source lookup, repeated/mixed `command -v/-V` lookup
  options, `--` option delimiters, `command -p` default-path lookup, invalid
  `command` option diagnostics, regular-builtin function shadowing,
  alias-before-function lookup precedence, bracket/test/read/printf/pwd
  builtin lookup, special `set`/`shift`/`return`/`exit` and
  `export`/`readonly`/`times`/`trap`/`unset` lookup, regular
  `alias`/`unalias`/`command`/`type`/`jobs`/`wait`/`kill`/`umask`/`bg`/`fg`/`getopts`
  lookup, function shadowing of the regular `command` builtin, empty `--`
  lookup operands, special/reserved function-name rejection, explicit
  regular/directory path lookup, explicit path execution, multi-operand
  lookup, and missing-command/missing-path diagnostics.
  Broader lookup/error matrix remains pending.
- [/] Add redirection/fd tests: semantic probe covers redirection-only create/open/failure cases, group/subshell/function stdout redirection, shell-local `printf >file`, command-invoked output builtin redirection, direct `type`/`trap`/`export -p`/`readonly -p`/`set`/`umask`/`times` output redirection through WSL shell diff, `pwd >file`, `read <file`, state/isolation across compound redirection, trailing if/while/for/case redirection, and `exec` redirection-only create; selftest and blocker probe cover persistent `exec` stdin/stdout, selftest covers simple native external-command plus native external-pipeline stdin/stdout inheritance, and file-suite cases cover WSL-normalized stderr for missing input redirection, output create failure, noclobber create failure, force-clobber override, special-builtin redirection aborts, direct special-builtin redirection failures for `:`, `eval`, `exec`, and `export`, nonfatal `command :` / `command eval` / `command exec` / `command export` redirection failures, missing-input redirection failure matrix coverage for direct/`command`/`eval`/`command eval` forms of `readonly`, `set`, `shift`, `times`, `trap`, and `unset`, output-create failure matrix coverage for special builtins, redirection-only noclobber failure, bad duplicated-fd sources for direct special builtins, `command`-wrapped special builtins, redirection-only commands, `exec`, `command exec`, and left-to-right truncation-before-failure ordering, persistent `exec` stdin/stdout through functions, groups, and compound `if`/`while`/`for`/`case` paths, persistent stdout for `type`, `alias`, `trap`, `umask`, `export -p`, `readonly -p`, `set`, and `kill -l`, persistent stderr diagnostics/fd2 output and fd4 stderr restoration, saved logical stdout duplication through fd3 after `exec >file`, saved logical stdin duplication through fd3 after `exec <file`, shell-local fd5/fd6/fd7/fd8/fd9 output and input chains, heredoc-to-fd cases, persistent `exec` here-doc stdin/fd handling, shell-local duplicated input-fd offset sharing through `7<&6`, Linux-native child-process stdout fd3 inheritance, Linux-native child-process file-backed stdin fd3 inheritance, post-child saved stdin fd3 offset reconciliation after a native child read, Linux-native fd5/fd6/fd7 child/pipeline fd-to-fd sharing, and the generated fd/process matrix covers 169 hosted-safe process/fd cases, including missing-parent and directory redirection diagnostics, command-local fd restoration for functions/groups/subshells, compound input and fd redirections, stderr redirection, pipeline-side output/fd redirection, pipeline builtin output/dataflow, background redirection creation, redirection-only assignment cases, successful `<>` create/no-truncate and shared-offset read/write behavior, single-digit fd8/fd9 heredoc duplication, command/function/group/subshell stderr-close isolation after persistent `exec 2>&fd`, and redirection-error diagnostics. Command-local input duplication followed by retargeting the source fd (`read I <&3 3< inner`) is covered with WSL-matched duplicated-fd offset restoration, and command-local plus compound-command `3<>file` restoration preserves the correct read/write offsets; function-call redirection restoration now covers overlapping body `exec` fd mutation without leaking the function-local fd state; saved host stdout fd bypass through shell-local pipeline capture and left-to-right compound stderr/stdout ordering (`2>&1 >file`) are covered by current semantic/POSIX-suite regressions; the Linux-native redirection diagnostic matrix now also covers quoted empty/space redirection targets, single/multiple glob-expanded redirection targets, shell-builtin stdout/stderr left-to-right redirection ordering, heredoc/input redirection ordering, missing-parent append/force/read-write failures, special/exec output-failure abort behavior, command-local stdin/stdout/stderr close restoration, persistent `exec` fd-close behavior, fd9 append/read-write failure diagnostics, compound-command fd restoration, compound-command missing-input/output/dup-fd failure continuation for `if`, `while`, `for`, and `case`, `>` offset tracking, `>>` append behavior, duplicated stdout/stderr offset sharing, and `12/12` closed-stdout write-failure cases for direct output builtins plus listing builtins; the Issue 8 fd matrix covers fd10/fd11 one-or-more-digit redirection prefixes for output, input, read/write, heredoc, local restoration, and pipeline routing against WSL `bash --posix`; deeper nested process-graph coverage beyond the generated fd/process, fd-graph, and arbitrary-fd matrices remains pending.
- [/] Add pipeline/subshell/function tests: semantic probe covers subshell/function state plus compound/function pipeline status, isolation, shell-local `printf | read`, `pwd | read`, `cd` printed-output isolation, `command -v | read`, `alias | read`, `set | read`, `export -p | read`, `readonly -p | read`, ignored `trap | read`, simple external-to-shell `external | read`, native exported environment handoff into external pipelines, compound/function external and extensionless-shell-script capture, and multi-stage external pipeline capture; file-suite cases cover `umask`, `times`, `alias`, `set`, `readonly -p`, function `umask`, grouped `umask`, and pipeline trap reset/preservation through grouped readers; Linux-native probe covers shell-local producer to external consumer stdin, text-script producer/consumer pipeline fallback, non-executable native pipeline-stage diagnostics/status, saved fd3 inheritance into mixed shell-local-to-external pipeline children, and fd7 chained stdin/stdout inheritance in mixed pipeline children; the current hosted-safe output-builtin pipe slice is WSL-matched; broader nested/external process-graph coverage remains pending.
- [x] Add locale/collation profile tests: semantic probe covers byte/ASCII
      sorting plus C-locale single-character equivalence/collating-symbol
      matching; strict WSL differential covers byte/ASCII sorting, while the
      non-WSL C-locale symbol cases remain in the semantic probe because WSL
      `/bin/sh` does not expand those constructs.
- [/] Add differential testing against a known POSIX shell for non-extension cases: semantic probe compares selected status cases against WSL `sh`, blocker probe tracks hard gaps, `msh_shell_diff.py --strict --baseline-only` currently has 134/134 POSIX-profile matches against WSL `sh`, the file-based `posix-core` suite has 493/493 WSL matches, the generated shell-only `posix-stress` suite has 261/261 WSL matches, and the tools-backed broad Smoosh slice has 175/175 WSL matches with the generated Mixtar userland tool directory prepended to `PATH`. `tools/msh_wsl_shell_diff.sh` provides the preferred WSL-native refresh path, avoiding per-case `wsl.exe` launches and comparing against WSL `sh`, `bash --posix`, `bash`, and `zsh --emulate sh` from inside one WSL process. Covered areas include normalized diagnostic stderr cases, eval and command-eval redirection cases, explicit text-script execution through `command` / `command -p` plus command-local redirection, special-builtin assignment-persistence cases, fatal direct and `eval`-wrapped special-builtin errors, nonfatal selected `command` and `command eval` special-builtin errors, direct and `command eval` output redirection plus nonfatal `command eval` redirection failure, noclobber special-builtin fatal/nonfatal redirection cases, explicit `command ./script` / `command -p ./script` text-script fallback, WSL-compatible direct/`eval`/`command eval` outside-loop `break`/`continue` behavior, temporary assignment visibility through `command eval` / `command .`, temporary assignment restoration through `command unset` / `command export` / `command readonly` / `command :` / `command exec` / `command trap` / `command times` / `command set` / `command shift` / `command break` / `command continue` / `command return` / invalid `command exit` / missing-source `command .`, regular `read` temporary assignment visibility/restoration, assignment-only command-substitution status, external temporary-assignment export/restoration inside command substitution, readonly parameter-assignment expansion aborts for unset and empty readonly variables, readonly arithmetic assignment and compound-assignment aborts, arithmetic shift/bitwise operators and compound assignments, invalid nonnumeric and octal arithmetic variable values, textual parameter and command-substitution expansion before arithmetic parsing, unsupported parameter operators such as `${name:offset}` and `${name/pat/repl}` aborting as bad substitutions, and `errexit`, POSIX default-path `command -p -v/-V sh` lookup, combined `command -pv/-pV/-Vp` default-path lookup, invalid `command -pz`, lone `command -` command-name behavior, explicit directory path lookup/execution through direct, `command`, `command -v`, `command -V`, and `type`, current-directory permission-denied diagnostics for direct, `command`, and pipeline-stage execution, `command` alias-execution suppression, mixed `type` missing-name status, pipeline output for `umask`, `times`, `alias`, `set`, `readonly -p`, function/grouped `umask`, and trap reset/preservation cases, arbitrary fd open/close redirection cases, noclobber and force-clobber redirection cases, bad duplicated-fd redirection failures, dot-without-operand no-op behavior, dot `--` / `command . --` option-delimiter behavior, PATH-unset dot current-directory source lookup, extra operands to `break`/`continue`, `trap -- action SIGNAL`, omitted-action `trap SIGNAL` / `trap -- SIGNAL` reset behavior, `trap -l` illegal-option handling, missing-action `trap` status-zero behavior, invalid `trap` signal status-one behavior, `export --`, `readonly --`, `set -f --` option/positional splitting, `set` plain operands and option-plus-operand positional updates, lone `export -` / `readonly -` bad-name diagnostics, double-quoted ordinary backslash preservation, `printf` raw `%s` operands versus `%b` escape decoding, `unset --`, `unset -v`, `unset -f`, combined `unset -fv` / `unset -vf` option parsing, direct/`command`/`eval`/`command eval` `times` extra operands, `unset -z`, WSL-compatible `shift` extra operands, `trap -l`, direct/`command` extra operands for `return` and `exit`, repeated and mixed `command -v/-V` lookup options with verbose precedence, `export -p` / `readonly -p` with extra operands, direct/`command` invalid `set -o` names, direct/`command` negative `shift` counts, direct/`command` readonly assignment failures, ignored self-signals, numeric self-signal traps, trap-action status preservation, trap-action `exit` control, fd5/fd6/fd7 duplication chains, direct special-builtin assignment persistence for `:`, `.`, `export`, and `readonly`, `hash` regular-builtin lookup/execution cases, expanded alias read-unit timing around `while`, `until`, groups, and subshells, broader compound-command redirection/linebreak grammar, and `set` option side-effect cases for `+u`, `+o nounset`, `+o noglob`, `+o allexport`, `+o noclobber`, `command set -a/+a`, `command set -u/+u`, `command set -f`, `command set -C/+C`, `command set -o/+o noclobber`, `set -n`, `set -x` xtrace for default, empty, and explicit `PS4`, `set -v` / `set -o verbose` verbose read-unit output, and special-builtin redirection failure matrix cases for `readonly`, `set`, `shift`, `times`, `trap`, and `unset`; broader differential corpus remains pending.

Completion gate:

```text
The test suite can show which POSIX requirements pass, fail, or are explicitly
out of scope for the current milestone.
```

