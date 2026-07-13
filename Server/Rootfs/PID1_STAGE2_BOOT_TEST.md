# MixtarRVS Stage 2 PID1 Boot Test Procedure

Updated: 2026-06-30

This is the first planned real PID1 ownership test.

It must not become the default boot path.

## Test Tool

```text
source:
  Server/Rootfs/mixtar-stage2-arm-pid1-boot.sh

installed target:
  /System/SystemTools/mixtar-stage2-arm-pid1-boot
```

The tool must be run from Debian fallback, not from Mixtar.

It refuses to run unless the active kernel is:

```text
7.0.0-rc3-mixtarrvs
```

## Planned EFI Entry

Label:

```text
MixtarRVS Stage2 PID1 Test
```

Loader:

```text
\EFI\mixtarrvs-rt\vmlinuz.efi
```

Critical command line additions:

```text
init=/System/SystemTools/mixtar-pid1-stage2
mixtar.stage2.allow=1
mixtar.stage2.return_debian=180
```

The `return_debian` watchdog is the key safety condition. The Stage 2 PID1
candidate starts a timer and calls:

```text
/System/SystemTools/mixtar-reboot-debian-once 0003
```

after the configured delay.

## Safe Sequence

Only this order is acceptable:

```text
1. Boot Debian fallback.
2. Run: mixtar-stage2-arm-pid1-boot plan
3. Inspect the intended EFI command line.
4. Run: mixtar-stage2-arm-pid1-boot create
5. Run: mixtar-stage2-arm-pid1-boot arm
6. Reboot manually or run boot-once only when ready.
7. Wait for either SSH on Mixtar or automatic Debian fallback.
```

Do not change permanent `BootOrder`.

Use only `BootNext`.

## Success Criteria

The test is successful only if one of these happens:

```text
Mixtar Stage 2 boots:
  kernel=7.1.2-mixtar-rt
  PID1 is /System/SystemTools/mixtar-pid1-stage2
  /run is mounted
  dbus/iwd/dhcpcd/sshd are running
  SSH is reachable
  automatic Debian return works

or:

Debian fallback returns automatically after the watchdog delay.
```

Any manual power cycle means the PID1 boot test failed and must be debugged
offline from Debian.

## Current Status

```text
prepared
arming tool installed on Mixtar
plan verified from Debian fallback
existing EFI entry: Boot0024
armed once through BootNext
boot attempted once
not proven as PID1
```

First attempt result:

```text
BootNext=0024 was consumed.
Mixtar SSH did not become reachable within 75 seconds.
Debian fallback returned without manual power-cycle.
No fresh pid1-stage2 log was written.
Candidate defect found: /proc/cmdline was read before /proc was mounted.
```

Second attempt result:

```text
PID1 Stage 2 started.
Debian return watchdog started.
Stage2 run-once completed.
getty on tty1 started.
PID1 keepalive loop entered.
SSH still did not become reachable.
Debian fallback returned without manual power-cycle.
```

Next fix:

```text
Add Mixtar-owned device/runtime setup before services:
  /System/SystemTools/mixtar-device-runtime
  /System/Config/MixtarRVS/modules.stage2
```

Verified plan output on 2026-06-30:

```text
loader=\EFI\mixtarrvs-rt\vmlinuz.efi
root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c
init=/System/SystemTools/mixtar-pid1-stage2
mixtar.stage2.allow=1
mixtar.stage2.return_debian=180
```
