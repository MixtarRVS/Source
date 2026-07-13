# MixtarRVS Runtime/Library Closure Stage 1

Updated: 2026-06-30

This document records the current runtime and shared-library closure after the
Stage 1 live checks.

The authoritative ThinkPad scan was written to:

```text
/System/Config/MixtarRVS/base-closure-stage1.runtime-libraries.txt
```

The scan was produced offline from Debian fallback against the Mixtar partition:

```text
/dev/nvme0n1p3
```

## Current ABI Reality

The current runtime ABI is Linux + musl:

```text
ELF interpreter:
  /lib/ld-musl-x86_64.so.1
```

This is true for:

```text
BusyBox
OpenRC
dbus-daemon
iwd
dhcpcd
sshd
sudo
MixtarRVS BSD Toolkit binaries under /System/Tools/Current/bin
```

This is acceptable for Stage 1. It means MixtarRVS is not glibc/GNU userland
identity, but it still relies on Alpine's musl-based bootstrap/runtime closure.

## Current Critical Runtime Owners

### Alpine/BusyBox Critical

```text
/bin/busybox
/bin/sh
/bin/mount
/bin/umount
/sbin/init
/sbin/mdev
/sbin/sysctl
```

These own early shell, applets, PID1 handoff, mount behavior, device management,
and basic sysctl behavior.

### Alpine/OpenRC Critical

```text
/sbin/openrc
/sbin/openrc-run
/sbin/rc-service
/sbin/start-stop-daemon
/etc/init.d
/etc/runlevels
```

These still own boot orchestration and service policy.

### Alpine Network Critical

```text
/usr/bin/dbus-daemon
/usr/libexec/iwd
/sbin/dhcpcd
```

These still own Wi-Fi association, system bus, DHCP/static network bring-up, and
the active network path.

### Alpine Remote-Access Critical

```text
/usr/sbin/sshd
/usr/bin/sudo
/etc/ssh
/etc/sudoers.d
```

These still own remote access and controlled fallback operations.

## Mixtar-Owned Stage 1 Components

```text
/System/SystemTools/mixtar-mount-runtime
/System/SystemTools/mixtar-service-supervisor
/System/SystemTools/mixtar-init-stage1
/System/SystemTools/mixtar-stage1-live-start-check
/System/SystemTools/mixtar-reboot-debian-once
/System/Config/MixtarRVS/services.stage1
```

These are now the `/System` control surface for the runtime/service closure.

They do not yet replace PID1 or OpenRC.

## Mixtar Toolkit Runtime

The BSD-derived Toolkit is installed under:

```text
/System/Tools/Current/bin
```

Representative binaries such as `ls`, `cat`, `bsd-mount`, and `bsd-init` are
Linux ELF binaries using:

```text
/lib/ld-musl-x86_64.so.1
```

Guarded boot-sensitive BSD commands remain under `bsd-*` names and must not be
used as boot primitives yet:

```text
bsd-init
bsd-mount
bsd-umount
bsd-fsck
bsd-reboot
bsd-shutdown
bsd-su
bsd-login
```

## Observed Broken or Non-Canonical Items

The scan observed:

```text
/usr/bin/login missing
/usr/bin/passwd -> /bin/bbsuid
```

This does not block the current SSH-based Stage 1 path, but it means local
interactive account-management closure is not owned or complete yet.

## Replacement Order

To remove Alpine as runtime identity without breaking the ThinkPad:

```text
1. Keep musl as the initial C runtime ABI.
2. Replace OpenRC service policy with Mixtar service supervisor policy.
3. Replace BusyBox mount/device/runtime applet usage with Mixtar SystemTools.
4. Wrap or replace dbus/iwd/dhcpcd as Mixtar network policy.
5. Keep OpenSSH temporarily while moving config and key policy under /System.
6. Replace BusyBox PID1/OpenRC boot with Mixtar initramfs + Mixtar init.
7. Only after that, remove Alpine from visible boot identity.
```

The important boundary is:

```text
musl dependency is acceptable in Stage 1.
Alpine/OpenRC/BusyBox identity is not the final state.
```
