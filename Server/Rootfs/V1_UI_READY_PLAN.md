# MixtarRVS 1.0 Graphics Plan

Version 1.0 is the first graphical MixtarRVS release. The no-UI core is 0.8,
and the source-native update release is 0.9.

## 1.0 Definition

MixtarRVS 1.0 is accepted when the verified 0.9 base gains the graphical login,
shell, application presentation and update experience.

Required state:

```text
Root:
  /Applications
  /System
  /Users
  /Volumes
  /Temporary

Core:
  /System/Init/MixtarRVS
  /System/Shells/zsh
  /System/Userland
  /System/Runtime/Executor
  /System/Configuration

Status:
  system status
  network status
  security status
  updates status

Recovery:
  one-shot boot
  autoreturn
  boot logs exported to ESP
  optional recovery SSH

Validation:
  local gate
  chroot gate
  boot preflight
  one-shot gate
```

## Version 0.9 Prerequisite

Version 0.9 is the source-native update milestone. It must be complete before
the graphical update UI is implemented.

It provides UI-callable status surfaces:

```text
/System/Userland/system
/System/Userland/network
/System/Userland/security
/System/Userland/updates
```

These are intentionally terminal-callable now and UI-callable later. The UI
should not parse `ip`, `iwd`, `sshd`, kernel logs, or random Unix paths directly.
It should call Mixtar status surfaces or read the same SQLite-backed state.

## Status Semantics

Initial status values must be honest:

```text
Network:
  Connected only after route and connectivity checks pass.

Security:
  Normal until signed boot, immutable system, sandboxing, and audit are real.

Updates:
  Unknown until upstream checking and certified build generation exist.

Recovery:
  Available when one-shot/autoreturn and logs work.
```

Do not show `High`, `Highest`, or `Updates: Available` before the checks exist.

## Version 1.0 Scope

After 0.9 passes, 1.0 may implement:

```text
Graphical login:
  UI session shell / MDDM foundation

Desktop shell:
  APX app presentation and launch UX

System UI:
  installer/update/app manager foundation
```

Terminal commands remain available, but they are not the product experience.
