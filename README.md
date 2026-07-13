# MixtarRVS Source

This repository contains the first-party source of MixtarRVS.

MixtarRVS is offline-first. Boot, init, the installed userland, APX execution,
and local configuration never require this repository or a network connection.
The source updater is optional and contacts official upstream projects only
when an update check is requested.

Current source-of-truth track:

```text
Linux PREEMPT_RT kernel
MixtarRVS Init and runtime
OpenBSD-first userland with explicit FreeBSD fallback
AILang Bridge and native AILang components
SQLite .config policy databases
```

Native system identity:

```text
/Applications
/System
/Users
/Volumes
/Temporary
```

The published 0.9 tree is limited to the current Server Core: authentication,
init, kernel policy, rootfs, runtime, shells, updates, and userland. Display
managers, desktop/UI experiments, installers, research branches, the older RVS
bridge, generated images, downloaded build trees, credentials, caches, and
private signing keys are deliberately outside this release source.

See `MixtarRVS_PLAN.MD`, `ROADMAP.md`, and `AGENTS.md` before making
architectural changes.
