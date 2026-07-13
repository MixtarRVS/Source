# MixtarRVS Initramfs Watchdog Policy

Updated: 2026-06-30

This document defines the fallback watchdog contract for MixtarRVS rootfs
candidates.

## Problem

The previous candidate chain placed the watchdog inside the candidate
`/sbin/init`.

That is not safe enough.

If the candidate fails before its `/sbin/init` starts, or if `/sbin/init` blocks
before starting the watchdog, the laptop can become unreachable and require a
manual reboot.

The watchdog must therefore belong to the initramfs handoff layer.

## Required Boot Contract

The safe candidate chain is:

```text
UEFI BootNext candidate
  Linux kernel
    MixtarRVS initramfs
      mount persistent base root read/write
      start initramfs fallback watchdog
      mount candidate rootfs.squashfs read-only
      switch_root into candidate
        candidate /sbin/init starts
        candidate marks boot-health after SSH is reachable
      watchdog observes health marker
        success: stop/release watchdog
        failure: reboot to default fallback Boot0006
```

The fallback must not depend on OpenRC, DHCP, iwd, sshd, or the candidate
service supervisor.

## Health Marker

The candidate may create an in-memory marker:

```text
/run/mixtar-ssh-confirmed
```

For initramfs watchdog survival across `switch_root`, the initramfs must also
provide a persistent or shared marker path visible outside the candidate root.

Preferred marker:

```text
/System/Runtime/initramfs/base/System/Runtime/boot-health/<generation>.ok
```

Minimum marker data:

```text
generation=<generation-name>
stage=<stage-id>
pid1=<path>
ssh_listen=1
user=vxz
created_utc=<timestamp>
```

The marker must be created only after:

```text
rootfs cmdline matches the expected generation
PID1 wrote persistent logs
vxz exists
/Users/vxz/.ssh/authorized_keys exists
sshd is listening on TCP/22
network has non-loopback IPv4
```

## Watchdog Timeout

The initramfs watchdog timeout must be bounded and explicit.

Recommended first value:

```text
180 seconds
```

Reason:

```text
Long enough for firmware, Wi-Fi, iwd, static IPv4 or DHCP, and sshd startup.
Short enough to avoid manual intervention during failed candidate tests.
```

## Fallback Behavior

The watchdog must not modify persistent boot order during failure recovery.

Correct behavior:

```text
sync logs
leave BootOrder unchanged
reboot -f
```

Because candidates are tested through `BootNext`, the next boot should return
to the stable fallback:

```text
Boot0006 MixtarRVS RT
```

## Logging Contract

The initramfs watchdog must write persistent logs under:

```text
/System/Base/Closure/
```

Required log events:

```text
watchdog started
candidate generation
candidate rootfs path
switch_root attempted
health marker observed
timeout reached
fallback reboot requested
```

Candidate PID1 logs remain separate:

```text
/System/Base/Closure/<stage>-*.log
```

## Development Rule

Do not run a new `BootNext` candidate until:

```text
1. MIXTAR_BUILD_ONLY=1 build succeeds
2. generated /sbin/init passes sh -n
3. rootfs-selftest-chroot.sh passes
4. initramfs watchdog behavior is either already present or explicitly not part
   of that no-boot test
```

If a candidate needs real boot validation before the initramfs watchdog is
implemented, it must be treated as high risk and run only when manual recovery
is acceptable.

## Implementation Direction

Move fallback authority from candidate `/sbin/init` into the initramfs handoff.

Candidate `/sbin/init` should only:

```text
mount runtime filesystems
bind persistent state
start minimal services
write logs
write health marker after SSH works
idle
```

Initramfs should own:

```text
root device mount
candidate image mount
switch_root
fallback watchdog
fallback reboot
handoff logs
```

This separation keeps the laptop recoverable even when the candidate rootfs or
PID1 is broken.
