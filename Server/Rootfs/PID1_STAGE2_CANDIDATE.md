# MixtarRVS PID1 Stage 2 Candidate

Updated: 2026-06-30

This document defines the first test-only Mixtar PID1 candidate.

It is not the default boot path.

## Installed Target

```text
/System/SystemTools/mixtar-pid1-stage2
```

Source:

```text
Server/Rootfs/mixtar-pid1-stage2.sh
```

## Purpose

Stage 1 proved that MixtarRVS has a working `/System` control surface:

```text
mixtar-mount-runtime
mixtar-service-supervisor
mixtar-init-stage1
```

Stage 2 prepares the next boundary:

```text
Can MixtarRVS own boot orchestration without OpenRC owning service policy?
```

This candidate coordinates:

```text
/System/SystemTools/mixtar-mount-runtime
/System/SystemTools/mixtar-service-supervisor
```

## Safety Rule

If executed as PID1, it requires this kernel command line flag:

```text
mixtar.stage2.allow=1
```

Without that flag it falls back to:

```text
/sbin/init
```

This prevents accidental replacement of the current known-working OpenRC boot.

## Non-PID1 Commands

```text
mixtar-pid1-stage2 check
mixtar-pid1-stage2 dry-run
mixtar-pid1-stage2 run-once
mixtar-pid1-stage2 fallback-openrc
```

`run-once` is root-only. It performs the same runtime/service convergence as
the Stage 1 init orchestrator, but through the PID1 candidate entrypoint.

## Current Status

```text
prepared
installable
not boot-active
not a final init
not an AILang init yet
still depends on /bin/sh and musl
```

## Next Safe Test

The next safe test is not to make it the default boot.

The next safe test is:

```text
1. install /System/SystemTools/mixtar-pid1-stage2
2. boot normal Mixtar through OpenRC
3. run mixtar-pid1-stage2 check
4. run a fixed sudo wrapper for run-once if needed
5. return to Debian fallback
```

## Fixed Live Wrapper

The controlled live test wrapper is:

```text
source:
  Server/Rootfs/mixtar-stage2-live-run-once-check.sh

installed target:
  /System/SystemTools/mixtar-stage2-live-run-once-check
```

It runs a fixed sequence:

```text
mixtar-pid1-stage2 check
mixtar-pid1-stage2 dry-run
mixtar-pid1-stage2 run-once
mixtar-init-stage1 status
```

The sudo bridge should allow only this wrapper, not arbitrary
`mixtar-pid1-stage2` arguments.

## Verified Live Run-Once Check

Verified on the ThinkPad T480 on 2026-06-30:

```text
Boot:
  BootNext=0006
  kernel=7.1.2-mixtar-rt

Wrapper:
  /System/SystemTools/mixtar-stage2-live-run-once-check

Safe return:
  sudo -n /System/SystemTools/mixtar-reboot-debian-once 0003
```

Observed result:

```text
check:
  mount-runtime ok
  service-supervisor ok
  dbus/iwd/dhcpcd/sshd commands ok
  openrc fallback ok: /sbin/init

dry-run:
  planned PID1 sequence emitted
  dbus/iwd/dhcpcd/sshd observed running

run-once:
  runtime mounts already mounted
  dbus already running
  iwd already running
  dhcpcd already running
  sshd already running

status-after:
  dbus running
  iwd running
  dhcpcd running
  sshd running

wrapper rc:
  0

fallback:
  returned to Debian kernel 7.0.0-rc3-mixtarrvs
```

This proves the Stage 2 PID1 candidate can execute its non-PID1 convergence
path on a normally booted Mixtar system. It still does not prove PID1 boot
ownership.

## First Real PID1 Boot Finding

The first real Stage 2 `BootNext=0024` attempt did not bring SSH up within the
test window and returned to Debian safely.

Root cause found in the candidate:

```text
PID1 mode tried to read /proc/cmdline before /proc was mounted.
The root filesystem was also still mounted read-only during the earliest log
and service setup path.
```

The candidate now prepares a minimal early runtime before reading the command
line or starting services:

```text
/proc
/sys
/dev
/run
remount / read-write
/System/SystemTools/mixtar-openrc-compat-guard
```

It also writes early status to `/dev/kmsg` when available.

The second finding was that PID1 Stage 2 can run the shell/control path, but
network/SSH cannot be assumed without the OpenRC `hwdrivers`/`mdev` phase.
Stage 2 now has an explicit device runtime component:

```text
Server/Rootfs/mixtar-device-runtime.sh
/System/SystemTools/mixtar-device-runtime
Server/Rootfs/modules.stage2
/System/Config/MixtarRVS/modules.stage2
```

For the ThinkPad T480, the first explicit module closure is:

```text
iwlwifi
```

A real PID1 boot test should only be created after a dedicated EFI BootNext
entry exists with:

```text
init=/System/SystemTools/mixtar-pid1-stage2
mixtar.stage2.allow=1
mixtar.stage2.return_debian=180
fallback path documented and verified
```

Boot-test procedure:

```text
Server/Rootfs/PID1_STAGE2_BOOT_TEST.md
```
