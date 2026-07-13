# MixtarRVS CoreV07 Contract

Updated: 08.07.2026

This document records the current CoreV07 staged-root contract.

CoreV07 staging is local-only:

```text
stage.scope = generated-only
boot.deploy = disabled
efi.mutation = disabled
```

The CoreV07 staging script is not an installer and not a deployment tool.

CoreV07 staging must not mutate:

```text
Debian
EFI variables
ESP contents
GRUB
systemd-boot
BCD
live root filesystems
```

Required order:

```text
1. build/stage CoreV07 under Server/Rootfs/Generated
2. run the local CoreV07 verifier
3. run the CoreV07 boot preflight
4. only then consider boot or deployment tests
```

Step 4 requires a separate decision. That decision is deliberately not part of the local gate.

The local gate is:

```text
Server/Rootfs/scripts/corev07-local-gate.sh
```

This local gate must remain local-only. It must not be extended into
installation, live deployment, boot testing, bootloader mutation, EFI mutation,
or Debian mutation.

## Native Root

The native root identity is:

```text
/Applications
/System
/Temporary
/Users
/Volumes
```

Forbidden native root paths:

```text
/bin
/boot
/dev
/etc
/home
/lib
/lib64
/proc
/root
/run
/sbin
/sys
/tmp
/usr
/var
```

Compatibility paths belong under:

```text
/System/Compatibility
```

## Required System Paths

CoreV07 uses:

```text
/System/Userland
/System/Shells
/System/Runtime/Executor
/System/Configuration
/System/Drivers
/System/Security
/System/UI
/System/Tools
/System/Compilers
```

Path roles:

```text
/System/Userland
  mode: command-root
  normal command userland
  no compiler or toolchain executables in this tree

/System/Shells
  system shell binaries and shell runtime files

/System/Runtime/Executor
  APX executor
  source: AILang
  source path: Server/Runtime/Executor/mixtar_executor.ail

/System/Configuration
  mode: sqlite-primary
  primary system configuration

/System/Drivers
  mode: store-only
  driver metadata and kernel-profile data

/System/Security
  mode: authority-policy
  authentication policy and Administrator Mode contract

/System/Runtime/Security
  mode: runtime-only
  auth sockets and elevated-session token state

/System/UI
  console/session/UI namespace

/System/Tools
  mode: admin-only
  not userland
  not APX runtime PATH
  not default user PATH

/System/Compilers
  mode: toolchain-only
  compiler binaries and helpers
  versioned under /System/Compilers/<name>/<version>/...
  /System/Userland and /System/Tools must not contain compiler or toolchain executables
``` 

## EFI Provenance

CoreV07 official EFI output is:

```text
/System/EFI/MixtarRVS/0.8.efi
/System/EFI/MixtarRVS/0.8.efi.provenance
```

The provenance file is mandatory. Staging, verifier, and boot preflight must
reject an EFI artifact without matching provenance.

Required provenance fields:

```text
format=MixtarRVS-EFI-Provenance-v1
core=CoreV07
release=0.8
source_mode=build
builder=corev07-build-efi.sh
kernel_version=7.1.2
efi_sha256=<hash of 0.8.efi>
```

A copied or imported EFI without this proof must fail local gates.

## Shell

CoreV07 uses:

```text
/System/Shells/zsh
```

Default user shell PATH:

```text
/System/Shells:/System/Userland
```

APX runtime PATH:

```text
/System/Userland
```

## Administrator Mode

CoreV07 defines Administrator Mode but keeps it fail-closed until interactive
approval/UI exists.

Current paths:

```text
/System/Security/Auth
/System/Security/Auth.contract
/System/Configuration/Security/Policy.config
/System/Configuration/Security/AdminSession.config
/System/Runtime/Security/Tokens
```

Current commands:

```text
/System/Userland/admin
/System/Userland/exit-admin
```

`admin` must not silently grant privileges. Until the Auth service and UI
approval path exist, it reports the configured policy and exits fail-closed.

Default policy:

```text
sudo.default=false
```

## APX And UI Foundation

Current APX shape:

```text
Application.apx/
  Application.config
  Program/
    Application
  Icon/
  Resources/
  Data/
```

Current system UI shell APX:

```text
/System/UI/Shell/MixtarShell.apx
```

It must not be staged under:

```text
/Applications
/System/Shells
/System/Userland
/System/Tools
/System/Runtime
```

CoreV07 UI is still console-first:

```text
session.mode=console
ui.graphical.enabled=false
runtime.executor=/System/Runtime/Executor
```

## Verification

`corev07-verify.sh` is the local gate for this contract.

It must verify:

```text
native root shape
forbidden POSIX root paths
required /System paths
APX bundle shape
SQLite config semantics
AILang-only Executor source
no C Executor fallback
no legacy Tools-to-Userland fallback
mandatory EFI provenance
fail-closed Administrator command foundation
no stage source mutation of Debian/EFI/bootloader state
```

Passing verifier and boot preflight is required before any boot or deployment
experiment.


Verifier-required safety wording:

It must not be extended into installation, EFI mutation, or Debian mutation.
