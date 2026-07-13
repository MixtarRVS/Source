# MixtarRVS Base Closure Status

Updated: 2026-06-30

This document tracks the current practical path from the Alpine/OpenRC bootstrap
system toward a minimal MixtarRVS base closure.

Related current files:

```text
Server/Rootfs/BASE_CLOSURE_CONTRACT.md
Server/Rootfs/INITRAMFS_WATCHDOG_POLICY.md
Server/Rootfs/scripts/inspect-base-closure.sh
Server/Rootfs/scripts/stage-0083-static-network-selftest-supervisor.sh
Server/Rootfs/scripts/rootfs-selftest-chroot.sh
Server/Rootfs/scripts/run-0083-selftest-no-boot.sh
Server/Rootfs/scripts/recover-selftest-host.sh
Server/Rootfs/scripts/repair-mixtar-ssh-from-debian.sh
Server/Rootfs/scripts/collect-mixtar-offline-logs-from-debian.sh
Server/Rootfs/scripts/mixtar-initramfs-watchdog-handoff-prototype.sh
Server/Rootfs/scripts/debian-mixtar-offline-runner.sh
```

## Target

The target is not "Alpine with renamed folders". The target is:

```text
Linux kernel
  MixtarRVS boot/initramfs handoff
    MixtarRVS rootfs generation
      /System as source of truth
      MixtarRVS BSD-derived Toolkit in /System/Tools
      Alpine kept only as temporary bootstrap/runtime substrate
```

The working fallback must remain bootable while candidates are tested.

## Current Safe Fallback

The known safe fallback is the normal RT entry:

```text
Boot0006 MixtarRVS RT
```

Candidate boots must use `BootNext` only. The stable `BootOrder` must remain:

```text
0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
```

## Current Candidate Chain

```text
0030-rootfs-image-runtime-closure-confirmed-supervisor
  known to boot far enough to start OpenRC/network/sshd in earlier tests

0031-rootfs-image-local-health-supervisor
  booted and logged OpenRC default, then returned to fallback

0032-rootfs-image-bounded-local-health-supervisor
  initramfs reached switch_root
  /sbin/init did not produce useful runtime log
  0079 log was created/truncated but stayed empty

0033-rootfs-image-early-watchdog-supervisor
  adds early watchdog before OpenRC
  adds static /dev/console, /dev/null, /dev/tty, /dev/tty0, /dev/tty1 nodes
  intended to prevent tty0 spam and no-fallback hangs
```

## Evidence So Far

The initramfs handoff is able to mount the selected squashfs image and move the
real base root under:

```text
/System/Runtime/initramfs/base
```

The handoff logs show:

```text
mounting rootfs image /MixtarBase/System/Generations/<candidate>/rootfs.squashfs
moved base root into readonly target /MixtarImage/System/Runtime/initramfs/base
switch_root target=/MixtarImage init=/sbin/init
```

The 0079 image had a valid `/sbin/init` shebang and passed `sh -n`, so the
remaining failure is runtime/PID1 behavior, not a trivial syntax or CRLF issue.

## Current Alpine Dependencies

Alpine is still required for the current runtime closure:

```text
musl dynamic loader and shared libraries
BusyBox/core bootstrap tools
OpenRC
iwd
dhcpcd
OpenSSH server
kernel firmware/userspace integration
apk-era filesystem/service metadata
```

MixtarRVS already owns the visible generation model and selected userland
surface, but it does not yet own all boot/runtime closure pieces.

## Minimal Closure Still Needed

To stop depending on Alpine as identity, MixtarRVS needs these components under
MixtarRVS control:

```text
/System/Kernel
  kernel profile metadata
  initramfs builder input
  module list and firmware policy

/System/Runtime
  dev/proc/sys/run/tmp mount policy
  persistent base mount contract
  PID1 logging contract
  early watchdog/fallback contract

/System/SystemTools
  init or supervisor
  mount helpers or direct syscall equivalents
  service runner
  shutdown/reboot path

/System/Tools
  BSD-derived Toolkit commands
  enough shell/core commands for boot scripts and maintenance

/System/Libraries
  musl loader and closure libraries
  later Mixtar-owned libc/runtime bridge

/System/Config
  accounts
  ssh
  network
  service manifests
```

## Immediate Engineering Rule

Do not hide Alpine paths until the runtime closure is proven. First make the
candidate root boot, log, network, and return safely. Then move the compatibility
substrate deeper.

Do not use repeated laptop reboots as the normal development loop. Most new
candidate work must be rejected or accepted before boot through:

```text
/sbin/init --self-test
rootfs-selftest-chroot.sh <rootfs.squashfs> <base-root>
short static analysis of generated /sbin/init
```

`BootNext` is only the final smoke test after the chroot/self-test path passes.

## Current Runtime Findings

The following facts are established by the 0079-0082 candidate chain:

```text
initramfs handoff works
switch_root into a rootfs.squashfs image works
static /dev/console and tty nodes are required in the image
PID1 can start after switch_root
PID1 can write to persistent /System/Base/Closure logs
OpenRC sysinit is currently not a safe PID1 path in the readonly image namespace
manual direct-service PID1 can start dbus-daemon and iwd
dhcpcd is currently a blocking/unstable step in the direct-service path
```

This means the next closure step should not be "fix OpenRC harder". The next
step is a Mixtar-owned minimal runtime path:

```text
mount /dev /proc /sys /run /tmp
bind persistent account/network/ssh state
load required Wi-Fi modules/hotplug state
start dbus-daemon
start iwd
assign known static IPv4 for the lab network
start sshd
mark boot health only after SSH listens and vxz credentials exist
```

The static IPv4 path is not the final network manager. It is a controlled
closure proof that avoids making DHCP/OpenRC the center of the boot identity.

## Next Step

The next valid candidate must prove:

```text
1. initramfs reaches switch_root
2. /sbin/init logs its first line
3. /dev/console and tty nodes exist before PID1 starts
4. early watchdog returns to fallback if OpenRC/network blocks
5. SSH is reachable or the persistent log explains why not
```

Only after that should `/System` become the default visible identity for normal
login sessions.

Current next candidate:

```text
Server/Rootfs/scripts/stage-0083-static-network-selftest-supervisor.sh
Server/Rootfs/scripts/rootfs-selftest-chroot.sh
```

0083 adds a self-testable PID1 contract. It should be built and checked through
`rootfs-selftest-chroot.sh` before any further `BootNext` test.

For no-boot iteration, stage scripts must support:

```text
MIXTAR_BUILD_ONLY=1
```

In this mode the script may create/update the rootfs generation, but must not
call `efibootmgr`, must not create a new EFI candidate, must not set `BootNext`,
and must not reboot.

Important correction:

```text
The first self-test harness revision mounted test filesystems in the host mount
namespace. That is not acceptable for routine iteration.
```

The harness must use a private mount namespace when available:

```text
unshare -m -- /bin/sh rootfs-selftest-chroot.sh <rootfs.squashfs> <base-root>
```

It must also prepare persistent-state bind mounts itself and run:

```text
MIXTAR_SELFTEST_PREPARED=1 chroot <root> /sbin/init --self-test
```

This keeps `/sbin/init --self-test` from remounting `/dev`, `/proc`, `/sys`,
`/run`, or persistent state inside the host namespace.

The self-test harness must provide isolated tmpfs mounts for:

```text
<root>/run
<root>/tmp
```

It must create:

```text
<root>/run/sshd
<root>/run/dbus
<root>/var/run/dbus
```

before calling `sshd -t` through `/sbin/init --self-test`.

Future `BootNext` tests must follow:

```text
Server/Rootfs/INITRAMFS_WATCHDOG_POLICY.md
```

The key rule is that fallback authority belongs in initramfs, not inside the
candidate `/sbin/init`.

The current local prototype for that future initramfs behavior is:

```text
Server/Rootfs/scripts/mixtar-initramfs-watchdog-handoff-prototype.sh
```

It is not installed into the laptop initrd yet. Do not treat it as active boot
state until an explicit no-install build and inspection step proves the packed
initramfs contents.

If a previous unsafe self-test left stale host mounts, the first recovery action
after the laptop is reachable again is:

```text
sh recover-selftest-host.sh
```

This script only cleans `/tmp/mixtar-rootfs-selftest-*` mount trees by default.
It does not touch `/System/Generations`, EFI, `BootNext`, or `BootOrder`.

Only if network services need an explicit restart, use:

```text
sh recover-selftest-host.sh --restart-network
```

If SSH is broken before any remote recovery is possible, boot Debian manually
and repair MixtarRVS from a chroot:

```text
sh repair-mixtar-ssh-from-debian.sh /dev/nvme0n1p3
```

The script fixes `/etc/ssh/sshd_config` readability, host-key permissions,
`vxz` authorized-key permissions, removes stale self-test directories under
`/tmp`, and runs `sshd -t` inside the mounted Mixtar root.

If repair succeeds but MixtarRVS still does not expose SSH after reboot, boot
Debian again and collect offline logs without modifying MixtarRVS:

```text
sh collect-mixtar-offline-logs-from-debian.sh /dev/nvme0n1p3
```

This mounts the Mixtar root read-only and writes a Debian-side report under
`/tmp/mixtar-offline-report-*.txt`.

Preferred Debian-side entrypoint:

```text
sh debian-mixtar-offline-runner.sh collect
sh debian-mixtar-offline-runner.sh collect-and-repair
```

The runner does not reboot, does not set `BootNext`, and does not edit EFI.
