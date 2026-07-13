# MixtarRVS Agent Guide

Updated: 22.05.2026

This repo is the landing zone for MixtarRVS/RVS, the completed AILang 1.8 Phase
1 serious-app proof, and the new MixtarRVS Server source-of-truth track.

## What This Project Is

MixtarRVS now has two explicit layers of meaning:

```text
RVS:
  current working bridge/lab around real FreeBSD targets

MixtarRVS Server:
  strategic source-of-truth track
  Linux kernel only
  selectable Mixtar-compatible kernel profiles
  hypervisor-first kernel profile
  low-latency/RTOS-like options where measured
  no GNU userland identity
  native /System, /Applications, /Programs, /Users layout
  POSIX paths retained as compatibility aliases
  AILang-built system tools/runtime
  OpenBSD-first Toolkit, FreeBSD fallback/reference
```

The current working scope remains the RVS **FreeBSD utility environment**:

The first useful version should provide:

- `rvs.exe` on Windows
- a managed FreeBSD VM
- `rvs-agentd` inside the FreeBSD guest
- `rvs-sh` as an optional user/login shell
- native `.ail` execution inside FreeBSD

The old appbox experiment is archived. The new Server track is not that old
experiment; it is a deliberate Linux-kernel/non-GNU/AIl userland proof.

The design borrows from:

- GoboLinux: organized system hierarchy
- AmigaOS: human-readable assigns and device-like names
- macOS/NeXTSTEP: visible `/Applications` and `/System` style concepts
- BSD: predictable base-vs-applications contract

But MixtarRVS should not copy any one system directly.

## What This Project Is Not

- Not a new OS from scratch.
- Not a WSL clone.
- Not a fork of WSL.
- Not a blind rewrite of all FreeBSD userland at once.
- Not a new package manager first.
- Not a desktop skin only.
- Not a replacement kernel or full VM stack yet.

## Active Architecture

Strategic Server architecture:

```text
Hardware
  Linux kernel only
    Mixtar/AIl runtime bridge
      AILang compiler/runtime
      AILang script runner
      AILang system tools
      OpenBSD/FreeBSD command behavior references
```

Current implemented RVS architecture:

```text
Windows host:
  rvs.exe
    start | stop | status | run | shell

FreeBSD guest:
  real FreeBSD kernel and base system
  /usr/local/sbin/rvs-agentd
  /usr/local/bin/rvs-sh (optional later user shell)
  /usr/local/bin/ailang
```

Implementation ladder:

```text
v0: QEMU/Hyper-V VM + SSH or TCP command bridge
v1: persistent rvs-agentd command protocol
v2: rvs-sh and .ail execution inside FreeBSD
v3: HCS lifecycle control and ISO attach/detach
v4: native TCP-framed PTY or Hyper-V socket transport if practical
v5: Mixtar layout, .apx apps, desktop integration
server: Linux-kernel/non-GNU Mixtar userland proof
```

WSL source may be studied for architecture, but do not fork it. WSL guest
components are Linux-specific and are not a FreeBSD base.

## Critical Design Rule

RVS keeps FreeBSD intact.

```text
FreeBSD provides kernel, base userland, pkg, rc.d, jails, network stack.
MixtarRVS provides host bridge, AILang shell/runtime, app model, and UX policy.
```

Do not replace `/bin/sh`. FreeBSD scripts and boot tooling expect it. `rvs-sh`
may become a user/login shell after smoke tests.

MixtarRVS Server is different:

```text
Linux kernel provides hardware/process/memory/syscall reality.
GNU userland is not the system identity.
OpenBSD userland source is the preferred clean upstream input.
FreeBSD remains fallback and breadth/reference input.
AILang translation/wrapper layer adapts clean OpenBSD/FreeBSD source to Linux.
AILang implementations prove freestanding/native systems viability where direct
native tools are simpler.
```

Do not start Server by porting ZFS, jails, bhyve, FreeBSD networking, or OpenBSD
Wi-Fi. Those are postponed until the AILang userland and runtime proof works.

Do not make SELinux or systemd a phase blocker. The first Server security model
is:

```text
pledge -> seccomp
unveil -> Landlock
capabilities + no_new_privs
namespaces + cgroups + rlimits
```

The first init model is AILang-owned minimal init/supervisor or OpenRC-style
init. Systemd is postponed.

The Server rootfs layout policy is:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Rootfs\LAYOUT_POLICY.md
```

Native Server paths are the identity:

```text
/System/Kernel
/System/Runtime
/System/Tools
/System/SystemTools
/System/Shells
/Users
```

Old Unix paths must remain as compatibility aliases:

```text
/bin -> /System/Tools
/sbin -> /System/SystemTools
/usr/bin -> /System/Tools
/usr/sbin -> /System/SystemTools
/home -> /Users
```

Do not delete compatibility paths. They are needed for scripts, shebangs, and
build systems. Do not make them the visible Mixtar identity.

Server shell identity is:

```text
/System/Shells/msh
```

`rvs-sh` is the older FreeBSD/RVS lab shell name. Do not use it as the Server
shell name.

Do not implement a custom namespace, drive-letter root model, or VMS/Amiga-style
logical-volume resolver in the current Server line. Keep normal POSIX paths
available underneath and make Mixtar different through `/System`,
`/Applications`, `.apx`, `msh`, service tools, and UI policy.

Postponed until after a useful bootable base exists:

```text
System:
Programs:
A:/
C:/
custom path resolver
custom filesystem semantics
```

## Upstream Source Rule

Never modify mirrored OpenBSD or FreeBSD source files in place.

Mixtar adaptations must live outside the upstream tree:

```text
compatibility headers
compatibility libraries
AILang-generated glue
translation manifests
build recipes
behavior tests
update reports
```

The executable guard for this policy is:

```text
.\out\server\toolkit_build.exe verify-upstream
```

It checks `Server/Userland/Manifests/upstream-integrity.sha256` and fails if any
mirrored OpenBSD/FreeBSD source file was edited, added, or removed. Refresh that
manifest only after an intentional upstream import:

```text
.\out\server\toolkit_build.exe refresh-upstream-manifest
```

When OpenBSD or FreeBSD updates its source, record the upstream revision,
refresh the integrity manifest, rebuild affected tools, rerun behavior tests,
and publish the Mixtar update note. Do not hide changes in a patched upstream
source copy.

Read before touching FreeBSD-derived work:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Userland\References\TOOLKIT_MIRROR.md
C:\Users\V\source\repos\MixtarRVS\Server\Runtime\TRANSLATION_LAYER.md
C:\Users\V\source\repos\MixtarRVS\Server\Kernel\KERNEL_SECURITY_PROFILE.md
```

## Command Surface Rule

`rvs` is the management tool, not the normal userland prefix.

Normal FreeBSD tools should run inside the guest, not be rewritten in AILang
first.

For the Server Toolkit, `toolkit_build all`, `toolkit_build tier-a`, and
`toolkit_build source` mean source-ported Tier A only. Hosted placeholders must
stay explicit-only and must not be counted as Tier A coverage.

Do not invent replacement command semantics. A command derived from OpenBSD or
FreeBSD must match that upstream userland's behavior as closely as the Bridge
allows. If it cannot be made honest yet, keep it as a blocker/deferred item
instead of creating a new Mixtar-flavored command with the same name.

Allowed:

```text
rvs start
rvs status
rvs run uname -a
rvs shell
```

Target guest use:

```text
uname -a
ls /
pkg --version
./hello.ail
```

Do not design the user experience around `rvs ls`. The host form is
`rvs run ls ...`; inside the guest, use normal FreeBSD command names.

## Start Here

Read these in order:

1. `C:\Users\V\source\repos\MixtarRVS\PHASE_1_PROOF.md`
2. `C:\Users\V\source\repos\MixtarRVS\MixtarRVS_PLAN.MD`
3. `C:\Users\V\source\repos\MixtarRVS\Server\Userland\TIER_A_PROOF.md`
4. `C:\Users\V\source\repos\MixtarRVS\Server\Rootfs\LAYOUT_POLICY.md`
5. `C:\Users\V\source\repos\MixtarRVS\ROADMAP.md`
6. `C:\Users\V\source\repos\MixtarRVS\Information.md`
7. `C:\Users\V\source\repos\MixtarRVS\docs\FREEBSD_BRIDGE_MODEL.md`
8. `C:\Users\V\source\repos\MixtarRVS\docs\FREEBSD_GUEST_AUDIT.md`
9. `C:\Users\V\source\repos\MixtarRVS\docs\BUNDLE_MODEL.md`
10. `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\experimental\gtk4-desktop\Mixtar_Roadmap.md`
11. `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\Directions.md`
12. `C:\Users\V\source\repos\AILang-Pure\RELEASE_1_7.md`
13. `C:\Users\V\source\repos\AILang-Pure\ROADMAP.md`

Useful exact old-note locations:

- GoboLinux/Mixtar inversion:
  `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\experimental\gtk4-desktop\Mixtar_Roadmap.md`
- Human-readable symlink map:
  `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\Directions.md`
- Original user wording about `/Applications`, `/System`, `.app`/`.apx`, and
  Amiga-like paths:
  `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\pl convo.md`
- Long historical chat containing GoboLinux/macOS/NixOS/Amiga/Haiku comparison:
  `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\last_chat.md`

## AILang Context

AILang compiler/runtime repo:

```text
C:\Users\V\source\repos\AILang-Pure
```

Current relevant state:

- AILang 1.7.0 is the optimizer-proof freeze.
- AILang 1.8.0 is the RVS serious-app proof line.
- C backend and LLVM AOT are both important.
- MixtarRVS/RVS completed Phase 1 of that proof: host manager, FreeBSD command
  bridge, persistent agent, normal-user execution, and profile lifecycle basics.
- The exact Phase 1 proof snapshot is recorded in
  `C:\Users\V\source\repos\MixtarRVS\PHASE_1_PROOF.md`.

Before changing AILang itself, prove the app need in this repo. Do not add
language syntax because it feels convenient.

## First Engineering Target

The FreeBSD bridge proof is already the completed Phase 1 target:

```text
rvs start
rvs status
rvs run uname -a
rvs run ./hello.ail
rvs shell
```

The next source-of-truth target is the Server proof:

```text
Server/Userland toolkit
  no GNU command dependency as identity
  clean mirrored FreeBSD Toolkit source
  AILang translation/wrapper layer
  AILang implementations
  OpenBSD/FreeBSD behavior comparison
  C and LLVM backend validation
  freestanding/runtime-surface accounting
```

The next practical target is smaller and more user-visible:

```text
Mixtar identity slice:
  /System/Shells/msh
  /Applications generator
  service/system CLI surface
  layout bootstrap + verifier
```

Do this before expanding the Toolkit again. Repair Toolkit regressions when they
block the identity slice, but do not chase full BSD command coverage as the main
project driver.

Expected active layout:

```text
MixtarRVS/
  ROADMAP.md
  AGENTS.md
  DIRECTION.md
  MixtarRVS_PLAN.MD
  docs/
  Server/          # strategic Linux-kernel/non-GNU/AIl userland work
  rvs-host/         # Windows host manager
  rvs-agentd/       # FreeBSD guest daemon
  rvs-sh/           # FreeBSD user/login shell
  Workstation/      # FreeBSD-side session/layout/UI/login work
  archive/
    legacy-*/       # old applet experiments
```

Current Workstation start:

```text
Workstation/session/mixtar-session.ail
Workstation/layout/mixtar-layout.ail
```

This is the first FreeBSD-side Mixtar session layer. It uses system paths:

```text
/usr/local/etc/mixtar
/usr/local/share/mixtar
/var/db/mixtar
/var/run/mixtar
```

Do not move this state into `/home`. User-local configuration can come later,
but the Mixtar system identity belongs under FreeBSD system locations.

Before running any root bootstrap, inspect the non-destructive tools:

```text
mixtar-session contract
mixtar-session plan
mixtar-session check
```

`mixtar-session uninstall-plan` is documentation only. It must not delete
anything automatically at this stage.

For the visible layout layer, use the same non-destructive sequence:

```text
mixtar-layout contract
mixtar-layout plan
mixtar-layout check
```

`mixtar-layout init` is root-only and must not overwrite existing non-link
top-level paths.

Mixtar service identity:

```text
user:  mixtar
group: mixtar
home:  /var/db/mixtar
shell: /usr/sbin/nologin
```

This is a hidden/service user, not a human login account and not a second root.
It should own Mixtar service/runtime state. `mixtar-session init` creates it
when run deliberately as root on FreeBSD.

Keep implementation files based on responsibility, not `part1`/`part2`.

Prefer AILang `match` for fixed command dispatch and state selection. Use
range constraints/loops where they express numeric intent. Do not write long
`if op == ...` chains unless a backend limitation is documented by validation.

## Current Hyper-V Boundary

The active host path uses AILang-owned HCS/Win32 ABI calls. Do not reintroduce
PowerShell or shell-script brokers for VM lifecycle work.

Current implemented operations:

```text
rvs install
rvs start --backend hyperv
rvs stop --backend hyperv
rvs status --backend hyperv
rvs attach-iso --backend hyperv
rvs detach-iso --backend hyperv
```

`rvs install` writes an HCS create document and includes the staged provision ISO
as a read-only SCSI attachment when the ISO exists. `attach-iso` and
`detach-iso` write HCS modify documents and call `HcsModifyComputeSystem`.

Mutating Hyper-V operations require elevation. Normal non-elevated runs should
stop before HCS mutation and print the exact command to rerun. `--elevate`
relaunches RVS through Windows UAC using AILang's direct `ShellExecuteW`
binding:

```text
rvs install --elevate
rvs start --backend hyperv --elevate
rvs attach-iso --backend hyperv --elevate
```

Normal guest user setup is part of install/user reconciliation:

```text
rvs install --user v
rvs install --elevate --user v
```

Root SSH is a bootstrap/admin channel only. The normal steady state is
`ssh.user` and `default_user` pointing at a non-root FreeBSD user with the RVS
SSH public key installed. Do not store plaintext passwords in config.

Do not add PowerShell or script fallback for this. Actual VM creation and live
ISO attach success must still be validated from an elevated process or a user in
Hyper-V Administrators.

## Current Shell Transport

`rvs shell --backend agent` is implemented as a pragmatic PTY path over SSH
`-tt`:

```text
ssh -tt ... /usr/local/sbin/rvs-agentd shell
```

If that fails, it falls back to the guest account's normal SSH login shell.
Do not require `rvs-sh` for the default interactive shell path.

The persistent TCP agent remains command-oriented. Native TCP-framed PTY
streaming is future work and should not be confused with the current shell path.

## Safety Rules

- No destructive tools against host or guest roots.
- Every mutating command needs dry-run behavior first where practical.
- Verify resolved absolute paths stay inside the intended staging root during
  tests when working on filesystem mapping.
- Do not delete user data.
- Do not alter FreeBSD system shell configuration automatically.
- Do not overwrite manual `/Applications` entries unless explicitly forced later.
- Prefer idempotent operations.
- Keep generated files under `out/`, test fixtures, or disposable VM images.

## Windows Defender / Probe Hygiene

Do not use long inline PowerShell probes that read the RVS agent token, scan
multiple hosts, open raw TCP sockets, and send root command payloads. Windows
Defender can classify that command-line shape as ClickFix/trojan-like behavior
even when the repository binary is not the detected resource.

Use one of these instead:

- `rvs.exe ...` for normal host/guest validation.
- `ssh` for direct FreeBSD inspection when a key is already installed.
- `out/rvs/rvs-transport-probe.exe --config rvs-host/config.<mode>.json`
  for AILang-native one-profile transport checks.
- `python tools/rvs_transport_probe.py --config rvs-host/config.<mode>.json`
  only as a readable fallback when debugging the AILang probe itself.
- A checked-in, readable helper script under `tools/` for any repeated probe.

Temporary HTTP bootstrap folders and `fetch ... | sh` notes belong under `out/`
only and should be deleted after use. Do not leave bootstrap web payloads active
or treat them as part of the source tree.

## Expected Repository Layout

Proposed first layout:

```text
MixtarRVS/
  ROADMAP.md
  AGENTS.md
  DIRECTION.md
  Information.md
  rvs-host/
    managed/
      cli.ail
      start.ail
      stop.ail
      status.ail
      run.ail
      shell.ail
      version.ail
      local_backend.ail
      ssh_backend.ail
      state.ail
      json_parser.ail
      response.ail
  rvs-agentd/
  rvs-sh/
  Workstation/
  archive/
    legacy-20260512-222704/
  docs/
    BUNDLE_MODEL.md
    FREEBSD_BRIDGE_MODEL.md
```

Adjust if the implementation proves a better split, but keep names based on
responsibility, not `part1`/`part2`.

## Implementation Order

1. Pick v0 VM backend: Hyper-V if practical, QEMU if faster to prove.
2. Boot a FreeBSD guest manually.
3. Establish host-to-guest reachability through SSH or TCP.
4. Implement `rvs status`.
5. Implement `rvs start` and `rvs stop`.
6. Implement `rvs run <command>`.
7. Add `rvs-agentd` only after command relay works.
8. Add `rvs-sh` and `.ail` execution inside FreeBSD.
9. Benchmark cold start, warm command overhead, and agent overhead.
10. Run AILang leak/routine checks for host and guest artifacts.

## Validation Expectations

`--check` is only a parser/diagnostic gate. It is not enough. AILang can accept
source in `--check` mode while a real backend still fails during C/LLVM lowering
or native compilation.

For every edited AILang source file, run the check gate against the edited file:

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py <file.ail> --check
```

For every edited executable entrypoint, also run real backend gates. The exact
source paths depend on the current implementation, but the output names should
follow this convention:

```text
# C backend native build
python C:\Users\V\source\repos\AILang-Pure\ailang.py <host_entry.ail> --backend=c -o out\rvs\rvs.exe

# LLVM native build, when a compatible LLVM/clang toolchain is available
python C:\Users\V\source\repos\AILang-Pure\ailang.py <host_entry.ail> --backend=llvm --native-toolchain=clang -o out\rvs\rvs-llvm.exe

# JIT smoke, when the program shape can run without extra host setup
python C:\Users\V\source\repos\AILang-Pure\ailang.py <host_entry.ail> --jit-json
```

When investigating C backend quality, inspect and compile the generated C with
strict flags where practical:

```text
# First build once to generate out\generated\c_backend\*.c
python C:\Users\V\source\repos\AILang-Pure\ailang.py <host_entry.ail> --backend=c -o out\rvs\rvs.exe

# Then compile the generated C manually with strict diagnostics.
# Use the actual generated file path printed by the compiler.
gcc -std=c23 -Wall -Wextra -Werror -pedantic -O3 <generated.c> -o out\rvs\rvs-strict.exe
clang -std=c23 -Wall -Wextra -Werror -pedantic -O3 <generated.c> -o out\rvs\rvs-strict-clang.exe
```

If strict C flags fail because AILang intentionally emits a compiler extension,
document the exact warning and decide whether the compiler or this project needs
the fix. Do not call the backend clean just because `--check` passed.

For AILang compiler changes:

```text
cd C:\Users\V\source\repos\AILang-Pure
python tools\quickcheck.py
python -m pytest -q
python tools\god_object_audit.py --max-file-lines 750
```

Add WSL sanitizer/Valgrind only when runtime/codegen behavior changes, not for
docs-only edits.

## Shell Compatibility Rule

Do not replace FreeBSD `/bin/sh`. FreeBSD boot scripts and system tools depend
on it.

`rvs-sh` is allowed to become a user/login shell:

```text
/usr/local/bin/rvs-sh
```

`rvs-sh` should execute normal FreeBSD tools first, then add native `.ail`
execution. Unsupported POSIX shell syntax may delegate to `/bin/sh` until a real
need exists.

## Host Native vs Guest Native

Do not confuse the host manager and guest tools:

```text
Windows host:  rvs.exe
FreeBSD guest: rvs-agentd, rvs-sh, ailang, ailang-run
```

A single binary that is both a normal Windows `.exe` and a normal FreeBSD ELF is
not the target. The target is one source implementation compiled per OS/backend
with the same protocol behavior.

## AILang First Rule

RVS policy, command routing, config decisions, and user-facing CLI behavior
should be written in AILang by default.

Host shell-script adapters are banned from the active RVS tree.

Windows host work must be implemented as:

- AILang source.
- Native Windows/Hyper-V/HCS ABI bindings reachable from AILang.
- FreeBSD-side AILang/FreeBSD binaries for guest operations.

Do not reintroduce host script brokers, installers, serial helpers, or VM
lifecycle wrappers.

Do not turn RVS into a CPU emulator or replacement hypervisor. The active
architecture is an AILang-owned control plane around a real FreeBSD VM, with
native Windows/Hyper-V/HCS ABI calls where host lifecycle control is needed.

## Naming Notes

Use `MixtarRVS` for the system identity.

Avoid:

- `Subsystem for FreeBSD`
- `FreeBSD clone`
- `WSL for BSD`

Those names imply technical claims the first version will not satisfy.

Chosen command name:

- `rvs` (Windows: `rvs.exe`)

Do not settle naming by aesthetics alone. Prefer the name that makes CLI usage
clear.

## Open Questions

- The first executable is `rvs` (`rvs.exe` on Windows).
- Should v0 use Hyper-V first or QEMU first?
- Should v0 command relay use SSH first or a tiny TCP `rvs-agentd` first?
- How should the FreeBSD image be created, imported, and stored?
- What is the minimal FreeBSD bootstrap script for AILang, `rvs-agentd`, and
  `rvs-sh`?
- Should Mixtar `.apx` bundles exist in v0.1 or wait until after normal app
  bridge/shell proof works?
- Mixtar `.apx` bundle shape is defined in `docs/BUNDLE_MODEL.md`;
  implementation can wait.

Do not block Phase 1 on these unless a decision is required by code.

## Engineering Constraints

- One source file must stay under `750` lines of code, including comments.
- Keep implementations self-explanatory: clear names, small functions, minimal
  branching, and explicit validation paths.
- Apply the spirit of "NASA 10 rules" where feasible (defensive coding, checks,
  no hidden state, simple interfaces, and early error return).
- For each edited AILang file, run `python C:\Users\V\source\repos\AILang-Pure\ailang.py <file> --check`
  before merging changes.








