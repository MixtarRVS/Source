# MixtarRVS Base Closure Contract

Updated: 2026-06-30

This document defines the minimum closure that makes MixtarRVS a real base
system track instead of an Alpine install with Mixtar labels.

## Closure Definition

A MixtarRVS base closure is valid when the system can boot, log, expose SSH, and
run its base toolkit with `/System` as the source of truth while keeping the old
Linux/Alpine substrate demoted to compatibility/runtime input.

The closure does not require a custom kernel, custom libc, custom package
manager, or custom desktop yet.

## Required Runtime Chain

```text
UEFI
  loads MixtarRVS kernel profile
  loads MixtarRVS initramfs

initramfs
  mounts persistent base root
  starts an early fallback watchdog
  mounts selected rootfs.squashfs generation
  prepares /dev/console and basic device nodes
  switches into candidate root

/sbin/init
  is Mixtar-owned policy, even if implemented as shell initially
  mounts /dev /proc /sys /run /tmp
  binds persistent state
  starts minimal network/SSH path
  writes persistent logs
  marks health only after SSH is reachable
```

Fallback watchdog policy is defined in:

```text
Server/Rootfs/INITRAMFS_WATCHDOG_POLICY.md
```

Fallback authority belongs to initramfs, not to the candidate `/sbin/init`.

## Source of Truth

Mixtar-owned:

```text
/System/Generations
/System/Kernel
/System/Runtime
/System/Base/Closure
/System/Tools
/System/SystemTools
/System/Config
/System/Logs
/Users
```

Compatibility/runtime substrate:

```text
/bin
/sbin
/usr
/lib
/etc
/var
```

These compatibility paths may exist during boot, but they are not the identity
of the system.

## Current Alpine-Derived Runtime Closure

The following pieces are still Alpine-derived or Alpine-packaged runtime input:

```text
musl loader:
  /lib/ld-musl-x86_64.so.1

shell/bootstrap:
  /bin/sh
  /bin/busybox

kernel userspace helpers:
  /sbin/modprobe
  /sbin/mdev
  /sbin/ip
  /bin/netstat

service/runtime daemons:
  /usr/bin/dbus-daemon
  /usr/libexec/iwd
  /sbin/dhcpcd
  /usr/sbin/sshd
  /usr/bin/ssh-keygen

previous service framework:
  /sbin/openrc
  /etc/init.d/*

configuration/state:
  /etc/passwd
  /etc/group
  /etc/shadow
  /etc/ssh
  /var/lib/iwd
  /var/lib/dhcpcd
```

These dependencies must be explicitly inventoried before they are hidden,
replaced, or moved under `/Compatibility`.

## Current Mixtar-Owned Pieces

Already Mixtar-owned:

```text
generation image model
rootfs.squashfs candidates
MixtarRVS EFI candidate naming
BootNext-only candidate policy
persistent closure logs
/System layout
BSD-derived Toolkit target under /System/Tools
candidate PID1 policy scripts
Base Closure status/contract documents
no-boot self-test workflow
```

Partially Mixtar-owned:

```text
initramfs handoff
fallback watchdog
runtime mount ordering
network bring-up
service supervision
```

Not yet Mixtar-owned:

```text
libc/runtime bridge
package manager
full service manager
network manager
firmware/module resolver
boot UI
desktop/session
```

## Evidence From Current Candidates

Established:

```text
initramfs can mount the candidate squashfs image
switch_root into the image works
PID1 runs after switch_root
PID1 can write persistent logs
static /dev/console and tty nodes are required in the image
OpenRC sysinit is not safe as the candidate PID1 path
manual direct-service PID1 starts dbus-daemon and iwd
dhcpcd is currently not safe in the candidate path
```

Therefore the next base closure proof should use:

```text
Mixtar PID1
manual mount setup
manual persistent-state bind setup
manual Wi-Fi module/hotplug setup
iwd for association
static IPv4 for lab reachability
sshd for remote control
```

DHCP can return after the direct path is stable.

## No-Boot Development Rule

Normal iteration must use:

```text
MIXTAR_BUILD_ONLY=1 sh stage-0083-static-network-selftest-supervisor.sh
sh rootfs-selftest-chroot.sh /System/Generations/0034-rootfs-image-static-network-selftest-supervisor/rootfs.squashfs /
```

This mode must not:

```text
call efibootmgr
create an EFI candidate
set BootNext
reboot
modify BootOrder
```

Only after syntax check and self-test pass may a single `BootNext` smoke test be
used. That smoke test must either use the initramfs watchdog contract or be
treated as high-risk/manual-recovery-only.

## Acceptance For First Safe Base Closure Stage

The first safe stage is acceptable when:

```text
1. rootfs generation builds with MIXTAR_BUILD_ONLY=1
2. /sbin/init passes sh -n
3. rootfs-selftest-chroot.sh passes
4. candidate BootNext returns either SSH access or a persistent failure log
5. stable Boot0006 fallback remains default
6. no host/user data is deleted
```

This is still not the final self-sufficient MixtarRVS. It is the first safe
stage toward replacing Alpine identity with MixtarRVS-owned boot/runtime policy.
