# MixtarRVS Roadmap

Updated: 22.05.2026

## Project Identity

MixtarRVS is a tinkerer's operating environment, not a FreeBSD clone and not a
WSL clone.

The completed Phase 1 goal was:

```text
MixtarRVS = FreeBSD-based environment + AILang shell/runtime + Windows host bridge
```

The new source-of-truth Server goal is:

```text
MixtarRVS Server = Linux kernel only + no GNU userland identity
                  + AILang system runtime/tools
                  + OpenBSD-first Toolkit behavior
                  + FreeBSD fallback/reference behavior
```

This project is also the proposed **AILang 1.8 serious-app proof**. AILang 1.6
proved C/ABI compatibility. AILang 1.7 proved optimizer/validation discipline.
MixtarRVS should prove that AILang can build and maintain a real systems
application, not just benchmarks.

Status: **AILang 1.8 Phase 1 is complete**. RVS now proves that AILang can build
the Windows host manager, talk to a real FreeBSD guest, run tools through a
persistent agent path, keep normal-user execution working, and maintain basic
profile lifecycle tools with clean checked memory behavior.

Status: **Server Userland Tier A is complete for the narrow common-command
slice**. The current source-ported toolkit proof is recorded in:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Userland\TIER_A_PROOF.md
```

Detailed proof snapshot:

```text
C:\Users\V\source\repos\MixtarRVS\PHASE_1_PROOF.md
```

Longer architecture decision map:

```text
C:\Users\V\source\repos\MixtarRVS\MixtarRVS_PLAN.MD
```

This is not a full WSL parity claim and not the final Server architecture.
Native Hyper-V socket/PTY shell, `\\wsl$`-style filesystem integration,
first-run polish, and production-grade profile registry behavior remain RVS
follow-up work only if they support the larger Server proof.

## Current Decision

MixtarRVS pivots to a **Server-first source-of-truth**.

The strategic Server shape is:

```text
Hardware:
  real machine or VM

Kernel:
  Linux kernel only
  selectable through Mixtar-compatible profiles
  use Linux for hardware/process/memory/driver reality
  hypervisor-first profile
  low-latency/RTOS-like options where measured
  seccomp/Landlock/capabilities before SELinux

Userland:
  no GNU userland as the identity
  native layout under /System, /Applications, /Programs, and /Users
  POSIX/Linux paths retained as compatibility aliases
  AILang runtime/compiler/script runner
  AILang-native system tools
  clean OpenBSD Toolkit source as preferred upstream input
  FreeBSD source as fallback and breadth/reference input
  Mixtar/AIl translation layer for FreeBSD-to-Linux adaptation
```

Postponed:

```text
custom namespace / logical-volume resolver
drive-letter-style root model
VMS/Amiga-style path syntax
FreeBSD ZFS
FreeBSD jails
FreeBSD bhyve
FreeBSD network stack
OpenBSD Wi-Fi stack
custom kernel
custom hypervisor
systemd as PID 1
mandatory SELinux policy
```

These can be researched later only after the AILang Userland/runtime proof
works.

The already completed RVS shape remains the lab and bridge:

Use a real FreeBSD VM or physical FreeBSD target as the reference environment.
Do not rebuild FreeBSD base userland inside RVS itself; AILang command/userland
work belongs under the Server track.

The v0 shape is:

```text
Windows:
  rvs.exe
    start | stop | status | run | shell
    AILang host manager

Windows native boundary:
  direct Hyper-V/HCS ABI bindings from AILang
  no host shell-script broker

FreeBSD guest:
  real FreeBSD kernel and base system
  /usr/local/sbin/rvs-agentd
  /usr/local/bin/rvs-sh (optional later user shell)
  /usr/local/bin/ailang
```

`rvs-host/rvs.ail` is intentionally a small launcher only; all command
dispatch and back-end behavior lives in `rvs-host/managed/`.

FreeBSD provides:

```text
kernel
base userland
network stack
filesystem behavior
pkg
rc.d
jails
bhyve
security model
```

AILang/Mixtar provides:

```text
rvs.exe host manager
rvs-agentd command bridge
rvs-sh optional login/user shell
.ail script execution
.apx application model
human-readable layout and UI policy later
```

The previous AILang-native applet/userland work is legacy and has been archived
under:

```text
C:\Users\V\source\repos\MixtarRVS\archive\legacy-20260512-222704
```

Use it as reference only. Do not continue that path unless the FreeBSD bridge
proves a specific need.

Validation rule:

- `rvs run <cmd>` must execute the real FreeBSD command inside the guest.
- `rvs shell` must enter the FreeBSD guest through the normal FreeBSD login
  shell first. `rvs-sh` is optional later work, not a v0 dependency.
- `.ail` files must run inside FreeBSD through AILang.
- `/bin/sh` must not be replaced; `rvs-sh` is a user/login shell.

### Profiles

Host profile:

- `rvs.exe` runs on Windows first.
- It is the normal-user client for VM lifecycle, command relay, terminal relay,
  and status output.
- A privileged RVS broker owns Hyper-V start/stop/status/IP operations.
- v0 may use SSH or a TCP agent before HCS/Hyper-V socket work.

Guest profile:

- runs inside real FreeBSD
- provides `rvs-agentd`, `rvs-sh`, and AILang runtime/install hooks
- uses FreeBSD base tools rather than replacing them

## Non-Goals For The First Line

- Do not build a new OS from scratch.
- Do not modify FreeBSD base command source as the main proof; use clean
  upstream source plus Mixtar translation wrappers.
- Do not replace `/bin/sh` or boot-critical FreeBSD tooling.
- Do not fork WSL as if Linux pieces can become FreeBSD pieces.
- Do not claim WSL parity until VM lifecycle, command relay, terminal relay, and
  filesystem behavior are measured.
- Do not try to run unmodified FreeBSD ELF binaries directly on Windows.
- Do not rewrite a package manager first.
- Do not make a full POSIX shell first; let FreeBSD keep `/bin/sh`.

## Design Principle

MixtarRVS uses two layout modes depending on the base.

```text
FreeBSD/RVS/Workstation lab:
  real files stay where FreeBSD puts them
  Mixtar paths are additive symlinks or generated views

MixtarRVS Server:
  real system identity lives under readable Mixtar paths
  old Unix paths are compatibility symlinks or bind mounts
```

That keeps the FreeBSD lab removable while allowing the final Server image to
have a clean Mixtar identity.

## Current Practical Rule

Do not build a custom namespace system yet.

MixtarRVS Server should keep normal POSIX paths available to the kernel,
third-party software, build tools, games, Wine, Steam, and compatibility
layers. Mixtar identity comes from readable top-level paths, `msh`, the app
bundle/view model, service tools, and UI policy.

Postpone:

```text
System:
Programs:
A:/
C:/
custom per-volume path resolver
custom filesystem semantics
```

Those ideas can come back later as an `msh` or AILang runtime convenience if
the base system is already useful.

## Human-Readable Filesystem Layer

FreeBSD Workstation lab visible map:

```text
/Config             -> /etc
/Users              -> /home
/Temporary          -> /tmp
/Resources          -> /usr/share
/Libraries          -> /usr/lib
/Logs               -> /var/log
/Volumes            -> /media or /mnt
/System/Boot        -> /boot
/System/Devices     -> /dev
/System/Tools       -> /usr/bin
/System/SystemTools -> /usr/sbin
/System/Runtime     -> /run
/System/Process     -> /proc
/System/Hardware    -> /sys
~/Config            -> ~/.config
```

Native Server map:

```text
/System/Kernel       kernel profiles
/System/Runtime      runtime contracts and state
/System/Tools        normal commands
/System/SystemTools  privileged/system commands
/System/Shells       msh and compatibility shells
/System/Libraries    shared libraries
/System/Config       system configuration
/Users               human homes

/bin      -> /System/Tools
/sbin     -> /System/SystemTools
/usr/bin  -> /System/Tools
/usr/sbin -> /System/SystemTools
/home     -> /Users
```

`/System/Binaries` is a legacy note name. New Server docs should use
`/System/Tools`.

Server shell identity:

```text
/System/Shells/msh
```

`rvs-sh` remains the FreeBSD/RVS lab shell name. `msh` is the MixtarRVS Server
shell name.

`/Applications` is special. It is not a raw symlink. It is a generated directory
of per-application launchers or symlinks built from installed app metadata:

```text
/Applications/Firefox
/Applications/Terminal
/Applications/Files
/Applications/Text Editor
```

For Linux hosts, the first generator should scan `.desktop` files and resolve
their `Exec=` and icon metadata. For a later BSD host, it can scan package
metadata and curated app manifests.

## App Bundle Direction

MixtarRVS should use its own `.apx` directory bundle format for
copy-installable applications. This remains after the first `/Applications`
generator, but the shape is now defined so future code does not drift.

Candidate shape:

```text
Foo.apx/
  Launcher.ail
  Info.xml
  Program/
    Foo.ail
    Icon/
      app.svg
      app.ico
    Resources/
    Data/
    Library/
      windows-x64/
        lib/
      linux-x64/
        lib/
      freebsd-x64/
        lib/
```

Installation model:

```text
copy or drop bundle into /Applications
remove bundle to uninstall
```

This is intentionally macOS-inspired but not a macOS-compatible bundle. A normal
Mixtar app stores portable AILang/Mixtar code under `Program/`, starts through
`Launcher.ail`, and declares metadata in `Info.xml`. Generated native
executables are not part of the source package. Optional target-specific
libraries or adapters may live under `Program/Library/<target>`.

Portable application code should call `system_*` APIs such as `system_open`,
`system_read`, `system_write`, and `system_list_dir`. Each host backend maps
those calls to Windows, Linux, or FreeBSD primitives.

Detailed spec: `docs/BUNDLE_MODEL.md`.

This should be implemented after the generated `/Applications` layer works for
normal installed software.

## Next Direction

The next development target is the **Mixtar identity slice**, not another
kernel/filesystem theory pass.

Build these in order:

```text
1. msh skeleton
   command dispatch
   .ail script execution
   POSIX shell delegation for unsupported syntax

2. /Applications generator
   scan installed app metadata
   emit visible launchers
   avoid overwriting manual entries

3. service/system surface
   list/start/stop/status
   simple service manifests
   logs/status contracts

4. layout bootstrap/verify
   create /System, /Applications, /Programs, /Users
   create POSIX compatibility aliases
   verify without destructive repair
```

The BSD/OpenBSD Toolkit stays frozen except for repairs needed by this slice.
Do not expand command coverage just to chase a number.

## Phase 0: Preservation And Source Of Truth

- [x] Preserve the old notes in `Information.md`.
- [x] Create this concrete roadmap.
- [x] Create an agent orientation file.
- [ ] Extract the useful Mixtar filesystem notes from old chat logs into a
  clean design document.
- [x] Define the first Mixtar `.apx` bundle shape.
- [x] Command name decided: `rvs` (`rvs.exe` on Windows).
- [ ] Decide repository layout before writing code.

Acceptance:

```text
Future agents can open the repo and understand what MixtarRVS is in 5 minutes.
```

## Phase 1: FreeBSD Guest Proof

Build or prepare one minimal FreeBSD guest image first.

Acceptance:

```text
FreeBSD boots under Hyper-V or QEMU.
Host can reach the guest over SSH or TCP.
Guest can run uname -a and /bin/sh.
AILang can be installed or copied into /usr/local/bin.
```

Notes:

- Hyper-V is the preferred long-term Windows backend.
- QEMU is acceptable for the first proof if it is faster to automate.
- Do not optimize boot speed until command relay works.

## Phase 2: rvs.exe Host Manager

Build the Windows-side command surface:

```text
rvs start
rvs stop
rvs status
rvs run uname -a
rvs shell
```

v0 implementation must keep product logic in AILang. Hyper-V control is native
Windows ABI work, not host shell-script glue.

Current Hyper-V implementation:

- typed AILang HCS bindings for status/start/stop/create
- staged provision ISO derivation from the active image profile
- create-time read-only ISO attachment in the HCS VM document
- `rvs attach-iso --backend hyperv` and `rvs detach-iso --backend hyperv`
  through HCS modify documents and `HcsModifyComputeSystem`
- `--elevate` relaunch for privileged Hyper-V operations through Windows UAC
  using AILang's direct `ShellExecuteW` Win32 binding
- `rvs service-install --elevate` installs the first privileged lifecycle
  broker as an on-demand highest-privilege Windows Scheduled Task
- bare `rvs --elevate` starts/resumes the default VM instead of reinstalling
- bare `rvs` first tries the installed privileged broker when the configured
  guest shell transport is unreachable; if no broker is installed it falls back
  to UAC, then polls SSH and opens the shell if the guest becomes reachable,
  rather than configuring host-boot autostart
- non-elevated validation reaches the expected
  early `elevation required` boundary for mutating operations with clean leak
  accounting

Actual VM creation and live ISO attach/detach success still require an elevated
host process or Hyper-V Administrators membership.

Acceptance:

```text
rvs status
rvs start
rvs run uname -a
rvs stop
```

Status: completed for the Phase 1 proof. Hyper-V lifecycle paths exist and the
host manager can run FreeBSD tools through the configured guest transport.
Full WSL-grade lifecycle polish remains Phase 2 hardening.

## Phase 3: rvs-agentd Guest Bridge

Build a small guest daemon inside FreeBSD:

```text
/usr/local/sbin/rvs-agentd
```

Responsibilities:

- accept command execution requests
- run FreeBSD tools through `execve`/process spawn
- relay stdout, stderr, exit code, cwd, and environment
- expose health/status
- keep protocol explicit and versioned

v0 transport can be TCP localhost/NAT or SSH command wrapping. Later transport
can investigate Hyper-V sockets if FreeBSD support is practical.

Current v0 implementation:

- `rvs-agentd serve` binds inside FreeBSD on `127.0.0.1:8757`.
- Windows starts an SSH `-L` tunnel to expose it locally as
  `127.0.0.1:18757`.
- `rvs.exe --backend agent -e <command...>` sends requests over the local TCP
  client instead of creating a new SSH login per command.
- Request parsing stays in the long-lived AILang daemon.
- Command execution uses native `fork`/`execvp` plus stdout/stderr pipes instead
  of a nested `rvs-agentd request` process.
- Interactive `rvs shell --backend agent` uses SSH `-tt` to enter the guest
  account's normal login shell. The TCP agent stays command-oriented for v0.
  Native TCP-framed PTY transport remains separate future work.

Acceptance:

```text
rvs -e uname -a
rvs -e ls /
rvs -e pkg --version
```

Status: completed for the Phase 1 proof. Persistent `rvs-agentd` command/status
paths are working and checked RVS paths are leak-clean under AILang reporting.

## Phase 4: AILang-Native Shell Layer

Build the FreeBSD-side user shell:

```text
/usr/local/bin/rvs-sh
```

Rules:

- `rvs-sh` may be a user/login shell.
- Do not replace `/bin/sh`.
- Add `rvs-sh` to `/etc/shells` only after smoke tests pass.
- Unsupported shell syntax may delegate to `/bin/sh`.

Minimum behavior:

- execute normal FreeBSD tools
- execute `.ail` files through AILang
- support command arguments and exit codes
- preserve cwd and environment

Acceptance:

```text
rvs shell
./hello.ail
uname -a
```

## Phase 5: .ail Execution And AOT/JIT Cache

Make `.ail` files first-class inside the guest:

```text
#!/usr/local/bin/ailang-run
print "hello from AILang"
```

Acceptance:

```text
rvs run ./hello.ail
rvs run ailang --version
```

Later:

- add AOT cache keyed by source hash
- add native FreeBSD backend validation
- measure startup and warm execution

## Phase 6: Mixtar Layer On Top Of FreeBSD

Only after command relay and shell integration work, add Mixtar-specific polish:

- `/Applications`
- `.apx` app bundles
- human-readable `/Config`, `/System`, `/Libraries` views
- desktop/file-manager integration
- FreeBSD lab polish only where it supports Server comparison

These features should enhance FreeBSD, not replace it.

## Server Track

Server is now the strategic source-of-truth track.

First layout target:

```text
Server/
  Kernel/
    notes/
  Rootfs/
    layout/
    initramfs/
  Runtime/
  Init/
  Userland/
      Toolkit/
      FreeBSD/
        freebsd-src/
      Bridge/
    Manifests/
    Generated/
    References/
      TOOLKIT_MIRROR.md
    Tools/
      echo/
      pwd/
      cat/
      true/
      false/
      mkdir/
      rmdir/
      rm/
      cp/
      mv/
    Tests/
    References/
```

Native Server rootfs policy:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Rootfs\LAYOUT_POLICY.md
```

Kernel profile policy:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Kernel\README.md
C:\Users\V\source\repos\MixtarRVS\Server\Kernel\KERNEL_SECURITY_PROFILE.md
```

Immediate Server scope:

- [x] Create `Server/` source tree.
- [ ] Define freestanding AILang support matrix.
- [x] Define minimal Linux-kernel rootfs layout.
- [x] Define native Server layout and POSIX compatibility alias policy.
- [x] Define Server kernel/security profile.
- [x] Define selectable kernel profile model under `/System/Kernel`.
- [x] Add controlled Linux kernel source acquisition manifest and fetch wrapper.
- [x] Download/extract pinned stable 7.x kernel source as generated build input.
- [x] Add clean local OpenBSD/FreeBSD toolkit mirrors under `Server/Userland/Toolkit/`.
- [x] Fetch first sparse FreeBSD Toolkit subset into `Server/Userland/Toolkit/FreeBSD/freebsd-src`.
- [x] Add initial OpenBSD/FreeBSD source and selected-tool manifests.
- [x] Add `Toolkit/Bridge` as the allowed translation/wrapper layer.
- [ ] Add once-per-day upstream check when network is enabled.
- [x] Add source integrity manifest with selected file hashes.
- [ ] Add full upstream revision and tool dependency map.
- [ ] Fetch changed upstream files into the clean mirror without local edits.
- [ ] Add first Mixtar translation-layer manifest for selected `src/bin` tools.
- [x] Add compatibility-wrapper reports for certified Tier A tools.
- [x] Build/certify Tier A common-command source-ported toolkit slice.
- [x] Implement/port first tool group: `echo`, `pwd`, `true`, `false`.
- [x] Implement/port file tools: `cat`, `mkdir`, `rmdir`, `rm`, `cp`, `mv`.
- [ ] Compare selected behavior against clean FreeBSD `src/bin` and a real FreeBSD target through RVS.
- [x] Verify no upstream OpenBSD/FreeBSD source file is modified by Mixtar build steps.
- [ ] Build each tool with the C backend.
- [ ] Build each tool with LLVM where supported.
- [ ] Run completed-exit leak checks for each tool.
- [ ] Add basic performance measurements.
- [x] Build a tiny VM/rootfs proof with no GNU command dependency as identity.

Explicitly postponed:

- [ ] FreeBSD ZFS port.
- [ ] FreeBSD jails port.
- [ ] FreeBSD bhyve port.
- [ ] FreeBSD network stack port.
- [ ] OpenBSD Wi-Fi stack port.
- [ ] custom kernel or hypervisor.
- [ ] systemd as the architectural center.
- [ ] mandatory SELinux policy.

Do not add these before the AILang Userland/runtime proof works.

Kernel/security profile:

```text
C:\Users\V\source\repos\MixtarRVS\Server\Kernel\KERNEL_SECURITY_PROFILE.md
```

Near-term security work:

- [ ] Implement `pledge` compatibility through Linux seccomp.
- [ ] Implement `unveil` compatibility through Linux Landlock.
- [ ] Add per-tool sandbox manifests for certified Toolkit commands.
- [ ] Add capability/no_new_privs/rlimit defaults for service profiles.

## Workstation Track

The first Workstation layer has started under:

```text
Workstation/session/
```

Current scope:

- [x] Create `mixtar-session` AILang entrypoint.
- [x] Use FreeBSD system paths instead of `/home` as the source of truth.
- [x] Support `status`, `paths`, `check`, `init`, and `env`.
- [x] Add `mixtar` hidden/service user bootstrap model.
- [x] Add non-destructive `plan`, `contract`, and `uninstall-plan` tools.
- [x] Build `mixtar-session` through the Windows C backend.
- [x] Build and run `mixtar-session` on the FreeBSD guest from `/tmp`.
- [x] Keep `init` explicit and root-only.
- [ ] Run `mixtar-session init` from a deliberate root shell to create
  `mixtar:mixtar` and apply ownership.
- [ ] Install `mixtar-session` to `/usr/local/bin` after root bootstrap policy is decided.
- [x] Add `mixtar-layout` proof for `/Applications`, `/System`, and visible symlink map.
- [x] Keep `mixtar-layout` explicit, root-only, and non-overwriting.
- [ ] Run `mixtar-layout init` from a deliberate root shell to create visible paths.
- [ ] Install `mixtar-layout` to `/usr/local/bin` after root bootstrap policy is decided.
- [ ] Add `rvs-sh` only after session/layout behavior is stable.

Do not start with a login screen. Session bootstrap comes first, then layout,
then shell, then UI, then login.

## AILang Requirements This Project Should Prove

- freestanding/minimal-runtime command output
- Linux-kernel syscall/runtime bridge viability
- AILang-native tool implementations
- OpenBSD/FreeBSD behavior comparison tests
- `.ail` script runner with native-speed path
- native FreeBSD executable output
- reliable long-running daemon behavior
- process spawning and stdio relay
- TCP or SSH protocol handling
- stable CLI parsing
- string/array cleanup under daemon workloads
- portable `.ail` script execution
- Windows host manager build
- FreeBSD guest agent build

If AILang cannot express one of these cleanly, that is valid feedback for the
AILang 1.8 compiler line. Do not add language surface before the app proves the
need.

## First Six-Week Backlog

Immediate bootstrap:

- [x] Command name decided: `rvs` (`rvs.exe` on Windows).
- [x] Archive the legacy AILang-native Userland/appbox experiment.
- [x] Decide v0 VM backend: Hyper-V first; QEMU remains fallback only.
- [x] Add `rvs-host/` host manager at repository root.
- [x] Split `rvs-host` runtime behavior into `rvs-host/managed/*` modules.
- [x] Add managed backends and shared helpers (`local_backend`, `state`, `json_parser`,
  `response`) as separate files.
- [x] Create `rvs-agentd/` for first FreeBSD guest agent skeleton.
- [ ] Create `rvs-sh/` for FreeBSD user shell.
- [x] Document first FreeBSD VM staging/bootstrap steps.
- [x] Define WSL-like `rvs` CLI model.
- [x] Implement direct AILang HCS create/open/start/stop/status binding.
- [x] Implement staged provision ISO derivation and HCS ISO attach/detach calls.
- [x] Add `--elevate` UAC relaunch for privileged Hyper-V operations.
- [x] Add WSL-like profile/image surface: `rvs --list`, `--import`,
  `--export`, and `--unregister --force`.
- [x] Add explicit built-in mode selection: `--mode vhd`, `--mode physical`,
  `--mode physical-maint`, `--mode ssh`, and `--mode agent`.
- [x] Add Phase 1 hardening tools: `audit`, `leakcheck`, and `validate`.
- [ ] Validate elevated Hyper-V VM creation from staged UFS image.
- [ ] Validate elevated live HCS ISO attach/detach against a running VM.

Week 1:

- [ ] Boot a FreeBSD guest manually.
- [ ] Establish SSH or TCP reachability from Windows.
- [x] Run `uname -a` remotely from a scripted host command.

Week 2:

- [x] Implement `rvs status`.
- [x] Implement `rvs start` and `rvs stop` using the Hyper-V/HCS backend.
- [x] Implement `rvs run <cmd>` through SSH or TCP.
- [x] Implement profile list/import/export/unregister surface with explicit
  image paths.

Week 3:

- [x] Implement minimal `rvs-agentd`.
- [x] Relay stdout, stderr, and exit code.
- [x] Add protocol roundtrip validation through `rvs validate`.

Week 4:

- [x] Build AILang for FreeBSD or document the cross-build path.
- [x] Add `ailang-run` or equivalent `.ail` script runner.
- [x] Prove `rvs run ./hello.ail`.

Week 5:

- [ ] Implement minimal `rvs-sh`.
- [ ] Add `/etc/shells` and `chsh` instructions, but do not automate them yet.
- [x] Add pragmatic PTY shell entry through SSH `-tt` and `rvs-agentd shell`.
- [ ] Prove `rvs shell` in an interactive guest session.

Week 6:

- [ ] Implement native Hyper-V socket or equivalent PTY transport if FreeBSD
  guest support is practical.
- [ ] Add a supported host filesystem bridge. `\\wsl$` parity needs a real
  Windows filesystem provider or SMB/SFTP/9P-style guest service, not CLI path
  mapping alone.
- [x] Add profile switching for built-in VHD, physical disk, SSH, maintenance,
  and agent modes.
- [ ] Add profile switching/import/export polish around generated registry
  entries and non-built-in profile configs.

- [x] Measure cold start, warm command overhead, and agent overhead.
- [x] Run AILang routine validation for host and current guest artifacts.
- [x] Decide whether to move from SSH/TCP to HCS/Hyper-V sockets.

## Key External Reference Notes

Current MixtarRVS docs:

- `C:\Users\V\source\repos\MixtarRVS\AGENTS.md`
- `C:\Users\V\source\repos\MixtarRVS\Information.md`
- `C:\Users\V\source\repos\MixtarRVS\docs\FREEBSD_BRIDGE_MODEL.md` 
- `C:\Users\V\source\repos\MixtarRVS\docs\RVS_BOOTSTRAP_ROADMAP.md`
- `C:\Users\V\source\repos\MixtarRVS\docs\RVS_REAL_BOOTSTRAP.md`
- `C:\Users\V\source\repos\MixtarRVS\docs\RVS_IMAGE_SPEC.md`
- `C:\Users\V\source\repos\MixtarRVS\docs\RVS_WSL2_COMPARISON_20260513.md`
- `C:\Users\V\source\repos\MixtarRVS\docs\BUNDLE_MODEL.md`

Useful historical notes are currently scattered. Start here:

- `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\experimental\gtk4-desktop\Mixtar_Roadmap.md`
- `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\Directions.md`
- `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\DebianBSD.md`
- `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\pl convo.md`
- `C:\Users\V\source\repos\FreeBSD-Mixtar-Theme\last_chat.md`
- `C:\Users\V\source\repos\AILang-Pure\ROADMAP.md`
- `C:\Users\V\source\repos\AILang-Pure\RELEASE_1_7.md`

## Release Definition

MixtarRVS v0.1 / AILang 1.8 Phase 1 proof is successful when:

- [x] FreeBSD boots as the managed guest
- [x] `rvs.exe start|stop|status` work on Windows
- [x] `rvs run uname -a` runs inside FreeBSD
- [x] `rvs run ./hello.ail` runs an AILang script inside FreeBSD
- [x] `rvs run <cmd>` can run as the configured normal FreeBSD user, not root
- [x] `rvs install --user <name>` creates/repairs that normal FreeBSD user and
  switches `ssh.user` / `default_user` away from root
- [x] `rvs shell` enters a FreeBSD shell path
- [x] all current routine checks pass
- [x] no memory/data leaks are detected in the checked AILang paths
- [x] the project has not grown new AILang syntax just to avoid normal engineering

This release proof is explicitly **FreeBSD utility environment first**.

RVS WSL-parity follow-up is successful when:

- [ ] native Hyper-V socket/PTY shell, or a measured equivalent native terminal
  transport, replaces SSH PTY for the default interactive path
- [ ] supported host/guest filesystem bridge exists beyond cwd string mapping
- [ ] profile import/export/unregister is backed by a polished profile registry
- [ ] first-run setup can install/start/configure a profile without manual
  endpoint edits








