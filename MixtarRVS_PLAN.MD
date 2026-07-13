# MixtarRVS Plan

Updated: 22.05.2026

This document is the architecture source of truth for MixtarRVS after the RVS
Phase 1 proof.

It is intentionally separate from `ROADMAP.md`.

- `ROADMAP.md` tracks the current implementation.
- `PHASE_1_PROOF.md` records what already works.
- This file defines the strategic architecture.

## Strategic Decision

MixtarRVS Server is now the first-class source-of-truth track.

The system target is no longer "FreeBSD guest with Mixtar tools" as the final
shape. That remains the bridge/proof. The strategic system target is:

```text
Hardware
  Linux kernel only
    no GNU userland
    no GNU coreutils as the system identity
    no systemd as the architectural center
      Mixtar/AIl Runtime
        AILang compiler/runtime
        AILang shell-script runner
        AILang system tools
        OpenBSD-first Toolkit compatibility layer
        FreeBSD fallback/reference compatibility layer
```

The immediate reason is AILang, not aesthetics:

```text
AILang must prove freestanding/native systems usefulness.
```

That proof should happen by building the tools that normally make an operating
system usable: command execution, init/orchestration, shell-script execution,
filesystem tools, process tools, networking tools, service tools, and validation.

## Current Anchor

RVS Phase 1 still matters.

```text
Windows host:
  rvs.exe
    manages and talks to FreeBSD

FreeBSD target:
  real FreeBSD installation
  SSH transport
  optional rvs-agentd transport
  AILang-built host and guest tooling
```

RVS proved that AILang can manage a real OS boundary. Keep RVS stable as a lab,
bootstrap bridge, and FreeBSD comparison environment.

But RVS is not the final Server architecture.

## Kernel/Userland Boundary

The key technical boundary is the kernel ABI.

```text
Program
  calls libc / runtime APIs

libc/runtime
  translates those calls into kernel syscalls

kernel
  owns drivers, processes, memory, filesystems, networking
```

Consequences:

- A Linux kernel understands Linux syscalls.
- FreeBSD binaries expect FreeBSD syscall/libc behavior.
- FreeBSD source code can be compiled for a Linux-kernel system only through a compatibility/translation layer.
- FreeBSD binaries cannot simply be copied onto a Linux kernel and expected to
  run natively.
- AILang can sit above the kernel as native compiled code, a script runner, and
  eventually a freestanding runtime, but it is not ring 0 by itself.

The Server track therefore means:

```text
Use the Linux kernel for hardware/process/memory/driver reality.
Build the Mixtar userland above it without GNU as the identity.
Use clean OpenBSD userland source as the preferred Toolkit input where
practical. Use FreeBSD as fallback and breadth/reference input.
Put all FreeBSD-to-Linux adaptation in Mixtar/AIl wrappers, generated glue,
compatibility libraries, and build rules.
```

## Server Architecture

### Layer View

```text
Hardware
  CPU, RAM, disks, NICs, GPUs, USB, ACPI, firmware

Boot
  UEFI boot manager / Mixtar boot presentation later
  initially use existing clean boot flow

Kernel
  Linux kernel only
  no GNU userland requirement
  no FreeBSD kernel in the strategic Server base
  hypervisor-first configuration
  low-latency/RTOS-like profile where measurement proves need
  seccomp/Landlock/capabilities as the first security layer
  SELinux optional later, not a phase blocker

Mixtar Runtime Bridge
  minimal libc/syscall bridge where required
  AILang runtime
  native process/filesystem/network primitives

Mixtar Core Userland
  AILang init/orchestrator candidate
  AILang command runner
  AILang shell-script runner
  AILang-native tools
  clean OpenBSD-first source compatibility path
  FreeBSD fallback/reference compatibility path
  OpenBSD/FreeBSD behavior comparison tests

Mixtar System Layer
  services
  package/install policy later
  validation/audit
  system profiles
  future desktop/workstation layer
```

### Hard Rule

The Server edition should not start by importing FreeBSD subsystems wholesale.

No compiler toolchain (and no compiler executable) may be placed in `/System/Userland`
or `/System/Tools`. All compiler and toolchain binaries must live only under:

```text
/System/Compilers/<name>/<version>/
```

Do not start with:

```text
ZFS
jails
bhyve
FreeBSD kernel
FreeBSD rc.d as-is
full FreeBSD network stack
OpenBSD Wi-Fi stack
```

Those can be research or demand-driven ports later.

Start with:

```text
bootable Linux-kernel base
minimal non-GNU rootfs
AILang runtime/compiler
AILang command runner
clean OpenBSD-first Toolkit command semantics
FreeBSD fallback/reference comparison
freestanding validation
```

## Kernel, Init, And Security Profile

Server is hypervisor-first, so the Linux kernel profile must include
virtualization and isolation from the beginning. It should not become a custom
kernel rewrite.

Immediate policy:

```text
init:
  AILang-owned minimal init/supervisor or OpenRC-style init first
  systemd postponed

security:
  pledge compatibility -> Linux seccomp
  unveil compatibility -> Linux Landlock
  privilege policy     -> capabilities + no_new_privs
  service isolation    -> namespaces + cgroups + rlimits
  SELinux              -> optional later, not required now

latency:
  low-latency Linux kernel profile first
  PREEMPT_RT only for measured real-time workloads
  no RTOS claim without boot/runtime latency measurements
```

Canonical profile document:

```text
Server/Kernel/KERNEL_SECURITY_PROFILE.md
```

## Kernel Profile Model

The Server kernel should be selectable through named Mixtar-compatible profiles,
not treated as an arbitrary file that can be swapped without consequences.

Native layout:

```text
/System/Kernel/
  Profiles/
    workstation/
      vmlinuz
      initramfs.img
      modules/
      config
      profile.json
    server/
      vmlinuz
      initramfs.img
      modules/
      config
      profile.json
    realtime/
      vmlinuz
      initramfs.img
      modules/
      config
      profile.json
    debug/
      vmlinuz
      initramfs.img
      modules/
      config
      profile.json
  Current -> Profiles/server
```

The bootloader loads:

```text
/System/Kernel/Current/vmlinuz
/System/Kernel/Current/initramfs.img
```

The runtime-visible contract is:

```text
/System/Runtime/kernel-profile.json
```

A kernel is Mixtar-compatible only if it passes the declared profile contract:
required syscalls, filesystem layout, init protocol, security features, device
support, module availability, and runtime expectations.

## Server Rootfs Layout

The native Server layout makes Mixtar paths the system identity and keeps old
Unix paths as compatibility aliases.

Native paths:

```text
/Applications
/Programs
/System
/System/Kernel
/System/Runtime
/System/Tools
/System/SystemTools
/System/Shells
/System/Libraries
/System/Config
/System/Resources
/System/Logs
/Users
/Volumes
/Temporary
```

Compatibility paths:

```text
/init      -> /System/SystemTools/init
/bin       -> /System/Tools
/sbin      -> /System/SystemTools
/usr/bin   -> /System/Tools
/usr/sbin  -> /System/SystemTools
/lib       -> /System/Libraries
/usr/lib   -> /System/Libraries
/etc       -> /System/Config
/usr/share -> /System/Resources
/var/log   -> /System/Logs
/run       -> /System/Runtime/run
/var/run   -> /System/Runtime/run
/tmp       -> /Temporary
/home      -> /Users
```

`/dev`, `/proc`, and `/sys` remain normal Linux mountpoints. Mixtar can expose
readable views:

```text
/System/Devices  -> /dev
/System/Process  -> /proc
/System/Hardware -> /sys
```

This keeps old scripts working while allowing native Mixtar software to use the
cleaner layout.

### Namespace Decision

Do not build a custom namespace, drive-letter system, or VMS/Amiga-style
logical-volume resolver in the first Server line.

For now:

```text
Kernel and third-party software see normal POSIX paths.
Mixtar-native software uses readable /System, /Applications, /Programs, /Users.
Old Unix paths remain compatibility aliases.
```

Ideas such as `System:`, `Programs:`, `A:/`, `C:/`, or per-application logical
volumes are postponed. They can return later as an `msh`/AILang path-resolution
feature after the base system is bootable and useful.

Canonical layout policy:

```text
Server/Rootfs/LAYOUT_POLICY.md
```

## OpenBSD/FreeBSD Source Role

OpenBSD userland source is the preferred Toolkit input where it can be built and
certified cleanly. FreeBSD remains the fallback and breadth/reference source.

The mirrored source trees contain classic system/user command source directories
such as:

```text
cat
chmod
cp
date
dd
echo
expr
hostname
kill
ln
ls
mkdir
mv
ps
pwd
rm
rmdir
sh
sleep
stty
sync
test
timeout
```

Use these source trees as clean upstream input, not as blind binary drops and
not as local forks.

Hard rule:

```text
Never modify mirrored OpenBSD or FreeBSD source files in place.
```

Required adaptation model:

```text
clean OpenBSD/FreeBSD source
  + Mixtar/AIl translation metadata
  + compatibility headers
  + compatibility libraries
  + Runtime/LibC AILang-owned behavior
  + build rules
  + generated glue
    -> Linux-kernel Mixtar binary
```

When upstream OpenBSD or FreeBSD changes:

```text
record upstream revision
regenerate manifest
rerun behavior tests
rebuild affected tools
record translation gaps or behavior drift
serve the update as a Mixtar update note
```

All Mixtar changes belong outside the upstream source tree.

Runtime behavior that starts to look like libc belongs in:

```text
Server/Runtime/LibC
```

This is the AILang-first Mixtar LibC direction. It is not a fork of OpenBSD
libc, FreeBSD libc, musl, or glibc. It is the stable place for bridge behavior
that would otherwise become scattered C shims.

This rule is enforced by an integrity manifest:

```text
Server/Userland/Manifests/upstream-integrity.sha256
```

Normal validation must run:

```text
.\out\server\toolkit_build.exe verify-upstream
```

Only after an intentional upstream import should the manifest be refreshed:

```text
.\out\server\toolkit_build.exe refresh-upstream-manifest
```

Detailed policy:

```text
Server/Userland/References/TOOLKIT_MIRROR.md
Server/Runtime/TRANSLATION_LAYER.md
```

Default Toolkit target:

```text
Tier A = source-ported only.
`toolkit_build all`, `toolkit_build tier-a`, and `toolkit_build source`
must exclude Linux-hosted placeholders.
```

Hosted adapters are allowed only as explicit temporary blockers for commands
that still need deeper bridge, kernel, privilege, terminal, or service work.
They do not count as Tier A coverage.

Command policy:

```text
Do not create new semantics for existing userland command names.
If a command comes from OpenBSD or FreeBSD, its Mixtar target is upstream
behavior through the Bridge, not a redesigned Mixtar command.
```

If parity is not feasible yet, keep the command out of Tier A and mark it as a
blocker. Repair the Bridge, tests, or compatibility layer later.

Reference:

```text
https://github.com/openbsd/src
https://github.com/freebsd/freebsd-src/tree/main/bin
https://cgit.freebsd.org/src/tree/bin
```

## AILang Role

AILang should become the Mixtar systems language.

In the Server track, AILang has four roles:

```text
compiler
  builds Mixtar-native tools and generated glue

translator/generator
  turns clean OpenBSD/FreeBSD source manifests into Linux-compatible build adapters

script runner
  runs .ail system scripts with native-speed AOT/JIT paths

update orchestrator
  detects upstream OpenBSD/FreeBSD source changes, rebuilds affected tools, and reports
  behavior drift
```

AILang is not "the server" by itself. MixtarRVS Server is the operating
environment. AILang is the compiler/runtime/translation control layer inside it.

Priority proof:

```text
AILang compiles freestanding enough to build essential system tools.
AILang can run .ail scripts natively as shell scripts.
AILang can AOT/JIT cache scripts when useful.
AILang can produce small, strict, inspectable native binaries.
AILang can be trusted under long-running service workloads.
```

AILang should provide:

```text
system_open
system_read
system_write
system_list_dir
system_stat
system_exec
system_spawn
system_wait
system_env
system_socket
system_time
system_mount_view later
```

The AILang compiler/runtime should be installable inside Mixtar Server as a
built-in tool, not a random external development package.

## Userland Strategy

Userland here means the base Toolkit above the kernel, not only standalone
commands.

It includes:

```text
mirrored FreeBSD toolkit source
compatibility headers
compatibility libraries
generated wrappers
build manifests
behavior tests
Mixtar-owned tools
AILang script runner integration
```

There are three tiers.

### Tier 1: Direct AILang Implementations

Tools simple enough to write directly in AILang:

```text
echo
pwd
true
false
cat
mkdir
rmdir
rm basic
cp basic
mv basic
hostname
sleep
test subset
```

Goal:

```text
Prove AILang native command viability and freestanding runtime behavior.
```

### Tier 2: Clean OpenBSD/FreeBSD Source Through Translation Layer

Tools where upstream BSD semantics matter and source should remain clean:

```text
ls
chmod
ln
date
expr
kill
sync
stty subset
ps subset
```

Goal:

```text
Compile clean OpenBSD/FreeBSD source against Mixtar compatibility wrappers
without modifying upstream files.
```

### Tier 3: Keep External Until Demand Exists

Tools/subsystems too large to rewrite early:

```text
sh full POSIX behavior
pax
dd complete behavior
network stack tools
package management
filesystem utilities requiring kernel-specific behavior
```

Goal:

```text
Do not drown the project before the base proves itself.
```

## Shell-Script Runner

The strategic shell idea is not "write a fake shell because it looks nice".

It is:

```text
.ail files are first-class system scripts.
AILang can run them immediately.
AILang can compile/cache them when useful.
AILang can call normal tools.
AILang can replace fragile shell glue with typed native logic.
```

This does not require a full POSIX shell on day one.

Server shell identity:

```text
/System/Shells/msh
```

`msh` is MixtarShell. It is the first-class Mixtar shell and AILang script
entry path. POSIX shells can be built later as compatibility tools, but they are
not the Server identity.

Minimum useful behavior:

```text
#!/System/Tools/ailang-run
print "hello"
rc = system_exec("ls", "/")
return rc
```

Later behavior:

```text
Mixtar shell can delegate POSIX shell syntax to a compatibility shell.
Mixtar native scripts use AILang syntax and compile to native code.
```

## Networking Stack Decision

Desired long-term identity:

```text
FreeBSD-like network quality
OpenBSD-like Wi-Fi sanity/security
Linux kernel hardware support
```

Practical rule:

```text
Do not port network stacks first.
```

Reason:

- The Linux kernel already owns drivers and networking in the Server track.
- Porting a network stack is kernel work, not userland polish.
- It would delay the AILang proof by years.

Postpone:

```text
FreeBSD network stack ideas
OpenBSD Wi-Fi ideas
custom packet/firewall layer
```

First implement:

```text
network status tools
socket APIs in AILang
service health checks
basic DNS/HTTP/TCP client/server tools
```

## What Is Postponed

These are valid ambitions but not starting points:

```text
custom namespace / logical-volume resolver
drive-letter-style root model
VMS/Amiga-style path syntax
FreeBSD ZFS port
FreeBSD jails port
FreeBSD bhyve port
FreeBSD network stack port
OpenBSD Wi-Fi stack port
custom package manager
custom desktop environment
custom kernel
custom hypervisor
CPU emulator
```

They become valid only after:

```text
Mixtar Server boots.
AILang tools run.
AILang scripts run.
The base userland is useful.
Routine validation is clean.
```

## Workstation Relationship

Workstation becomes a layer above Server, not the source of truth.

```text
MixtarRVS Server
  Linux kernel-only base
  AILang/Mixtar userland
  command/runtime/service layer

MixtarRVS Workstation
  session
  layout
  /Applications
  .apx bundles
  desktop/login/launcher
```

The existing FreeBSD Workstation/session work is still useful as a design lab,
but the strategic Workstation should eventually sit on the Mixtar Server base.

## Next Direction: Mixtar Identity Slice

The next work should make Mixtar feel like Mixtar without inventing a whole new
kernel, filesystem, or package universe first.

Start with a small usable identity slice:

```text
msh
  first-class Mixtar shell entrypoint
  runs commands
  runs .ail scripts
  keeps POSIX shell compatibility delegated instead of reimplemented first

/Applications
  generated visible app view
  later accepts .apx bundles
  does not replace package management yet

system/service tools
  list/start/stop/status logs
  simple service manifests
  no systemd clone

layout bootstrap
  creates /System, /Applications, /Programs, /Users
  creates compatibility aliases
  verifies the layout without deleting user data
```

This is the first user-visible Mixtar layer. The BSD-derived Toolkit remains a
compatibility/base utility layer, not the identity of the system.

## RVS Relationship

RVS remains useful for three reasons:

```text
1. It proves AILang can manage a real OS from Windows.
2. It provides a FreeBSD behavior reference machine.
3. It gives a place to compare Mixtar tools against real FreeBSD tools.
```

RVS should not expand forever.

Keep it focused:

```text
connect
run
shell
validate
copy/test tools
compare behavior
```

Do not turn RVS into the final OS.

## Build Targets

### Target 0: Host Lab

```text
Windows or FreeBSD host
  build AILang tools
  run command tests
  compare with FreeBSD tools
```

### Target 1: Linux Kernel VM

```text
minimal Linux kernel
minimal initramfs/rootfs
no GNU coreutils
AILang runtime copied in
first AILang init/test command
```

### Target 2: Mixtar Core Rootfs

```text
/System/Tools/ailang
/System/Tools/ailang-run
/System/Tools/echo
/System/Tools/cat
/System/Tools/pwd
/System/Tools/ls
/System/Shells/msh
/System/SystemTools/init
/System/Kernel
/System/Config
/System/Runtime
/Users
/Applications

Compatibility aliases:
  /bin -> /System/Tools
  /sbin -> /System/SystemTools
  /usr/bin -> /System/Tools
  /usr/sbin -> /System/SystemTools
  /home -> /Users
```

### Target 3: Bootable Server Image

```text
UEFI boots Linux kernel
Mixtar init starts
AILang scripts run
basic tools work
network comes up
SSH or Mixtar remote agent works
```

## Near-Term Implementation Plan

### Phase S0: Freeze Current RVS As Lab

Goal:

```text
Keep current RVS working and stop it from absorbing the whole project.
```

Tasks:

- Keep `rvs validate` green where practical.
- Use RVS to reach FreeBSD reference machines.
- Use RVS to copy and compare AILang tools.
- Do not add large new RVS-only features unless they support Server proof.

### Phase S1: Freestanding AILang Proof

Goal:

```text
AILang builds and runs tiny freestanding-style system programs.
```

Tasks:

- Define freestanding support matrix.
- Build minimal `ailang-run` or equivalent runner.
- Add no-libc or minimal-libc smoke programs where realistic.
- Validate C and LLVM output.
- Track memory/data leak behavior on completed exits.

Acceptance:

```text
AILang can produce a tiny native command that does not depend on the full host
runtime model beyond explicitly allowed system calls/runtime stubs.
```

### Phase S2: First AILang Userland Tools

Goal:

```text
Build a tiny non-GNU base toolkit.
```

Start with:

```text
echo
pwd
cat
true
false
mkdir
rmdir
rm basic
cp basic
mv basic
```

For each command:

```text
AILang implementation
OpenBSD/FreeBSD behavior reference notes
unit tests
native C backend build
LLVM build where available
leakcheck on normal completion
simple performance measurement
```

### Phase S3: OpenBSD/FreeBSD Behavior Comparison

Goal:

```text
Use the selected upstream BSD source as the behavior oracle.
```

Tasks:

- Run command against real FreeBSD through RVS where FreeBSD is the reference.
- Run command against an OpenBSD reference where OpenBSD behavior is the
  selected upstream.
- Run Mixtar/AIl command locally or inside VM.
- Compare stdout/stderr/exit code for selected cases.
- Record intentional divergences.

### Phase S4: Minimal Linux-Kernel Rootfs

Goal:

```text
Boot a kernel with Mixtar userland, not GNU userland.
```

Tasks:

- [x] Build or obtain a minimal Linux kernel/initramfs path.
- [x] Create rootfs with AILang runtime and first tools.
- [x] Boot in VM first.
- [x] Run first command from Mixtar init.
- Bring up basic console and networking later.

### Phase S5: Mixtar Init / Orchestrator

Goal:

```text
AILang starts becoming the system control layer.
```

Tasks:

- Define service file format.
- Start a few known services.
- Capture logs.
- Handle clean shutdown.
- Expose status.

Do not copy systemd. Keep it smaller and explicit.

## Validation Requirements

Every AILang command/tool added to Server must have:

```text
--check gate
C backend build
LLVM build when supported
completed-exit leakcheck
behavior tests
FreeBSD comparison where applicable
basic runtime measurement
```

Every command must define:

```text
supported flags
unsupported flags
intentional divergences from FreeBSD
required syscalls/runtime features
```

## Names And Layout

Recommended strategic repo layout:

```text
MixtarRVS/
  MixtarRVS_PLAN.MD
  ROADMAP.md
  PHASE_1_PROOF.md

  Server/
    Kernel/
      notes/
    Rootfs/
      layout/
      initramfs/
    Userland/
      Toolkit/
        bin/
        usr.bin/
      Manifests/
      Generated/
      Tools/
        echo/
        cat/
        pwd/
        ls/
      Tests/
      References/
    Runtime/
    Init/

  Workstation/
    session/
    layout/
    shell/
    desktop/

  rvs-host/
  rvs-agentd/
  tools/
  docs/
```

Keep names responsibility-based. Do not create `part1`, `part2`, or vague
catch-all modules.

## Decision Tree

If the task proves AILang can build system tools:

```text
Put it under Server/Userland or Server/Runtime.
```

If the task manages FreeBSD access from Windows:

```text
Keep it under RVS.
```

If the task is about visual identity, `/Applications`, `.apx`, login, desktop:

```text
Put it under Workstation.
```

If the task requires kernel drivers, custom networking stack, Wi-Fi stack, ZFS,
jails, or bhyve:

```text
Postpone unless a specific measured need exists.
```

## Final Position

MixtarRVS Server is the source-of-truth track:

```text
Linux kernel only.
No GNU userland as identity.
OpenBSD-first command behavior, with FreeBSD fallback/reference behavior.
AILang implementations where possible.
AILang script runner/compiler built into the system.
```

RVS remains the working bridge and FreeBSD reference lab.

Workstation becomes the user-facing layer after Server has a useful base.

The next serious proof is not another VM manager feature. It is:

```text
Can AILang build a tiny, useful, non-GNU, BSD-behavior userland on top of a
Linux kernel, with clean validation and native speed?
```








