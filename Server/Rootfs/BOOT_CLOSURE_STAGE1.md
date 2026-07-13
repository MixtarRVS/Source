# MixtarRVS Boot Closure Stage 1

Updated: 2026-06-30

This is the next safe Base Closure rule after the ThinkPad reached a working
MixtarRVS RT boot, SSH access, and Debian fallback return.

## Stage 1 Boundary

MixtarRVS currently has two separate closures:

```text
Mixtar identity closure:
  /System/Tools/Current -> MixtarRVS
  /System/Tools/MixtarRVS/bin
  BSD-derived Toolkit commands

Bootstrap/runtime closure:
  /bin
  /sbin
  /etc
  /lib
  /usr/lib
  /run
  OpenRC
  BusyBox/Linux mount behavior
  iwd
  dhcpcd
  sshd
```

The first closure is allowed to move quickly.

The second closure must stay conservative until MixtarRVS owns replacement
components.

## Protected Names

These names are not safe to promote from BSD Toolkit source into the Linux boot
or service path yet:

```text
sh
init
mount
umount
fsck
reboot
shutdown
swapon
sysctl
fdisk
cron
adduser
su
passwd
login
top
ping
```

Reason:

```text
These commands cross the kernel/service/security boundary.
OpenBSD or FreeBSD source semantics are not automatically correct on a Linux
kernel, even when the source compiles through the Bridge.
```

They can exist under MixtarRVS as source-certified artifacts, but they must not
be the default implementation for early boot until their Linux behavior is
owned and tested.

## Current Guard

`Server/Userland/Toolkit/Bridge/scripts/mixtarrvs_musl_toolkit.py` now protects
the remote install path:

```text
BSD source commands with protected names are moved to:
  /System/Tools/MixtarRVS/bin/bsd-<name>

/System/Tools/MixtarRVS/bin/sh is kept as:
  /bin/busybox

Compatibility boot applets are forced back to BusyBox:
  /Compatibility/POSIX/Alpine/3.24/bin/mount  -> /bin/busybox
  /Compatibility/POSIX/Alpine/3.24/bin/umount -> /bin/busybox
  /Compatibility/POSIX/Alpine/3.24/sbin/mount  -> /bin/busybox
  /Compatibility/POSIX/Alpine/3.24/sbin/umount -> /bin/busybox

The guard also keeps `/run` as a real mountpoint directory and prepares:

```text
/System/Runtime/run
```

This prevents the known OpenRC failure where `/run` cannot become tmpfs and the
dependency cache cannot be written.

The same invariant is available as a standalone rootfs guard:

```text
Server/Rootfs/mixtar-openrc-compat-guard.sh
/System/SystemTools/mixtar-openrc-compat-guard
```
```

The guard also refuses an install if the target has the known-bad identity
mapping:

```text
/bin  -> /System/Tools/Current/bin
/sbin -> /System/SystemTools
```

## First Mixtar-Owned Runtime Component

Stage 1 adds the first explicit Mixtar-owned runtime mount component:

```text
source:
  Server/Rootfs/mixtar-mount-runtime.sh

installed target:
  /System/SystemTools/mixtar-mount-runtime
```

It prepares ownership of:

```text
/proc
/sys
/dev
/run
/dev/pts
/dev/shm
```

It is intentionally not enabled as an OpenRC boot service yet. At this stage it
is a manual/offline development component. The current boot still uses
Alpine/OpenRC for these mounts until MixtarRVS owns the full PID1/service
closure.

## First Mixtar-Owned Service Component

Stage 1 also adds a manual service supervisor:

```text
source:
  Server/Rootfs/mixtar-service-supervisor.sh

manifest:
  Server/Rootfs/services.stage1

installed target:
  /System/SystemTools/mixtar-service-supervisor
  /System/Config/MixtarRVS/services.stage1
```

Initial service set:

```text
dbus
iwd
dhcpcd
sshd
```

This supervisor is not PID1 and is not enabled in boot. It is the first
Mixtar-owned control surface for the network/remote-access service set that
OpenRC currently manages. The purpose is to move service policy into `/System`
before replacing the boot path.

## First Manual Init Orchestrator

Stage 1 adds a manual init orchestrator:

```text
source:
  Server/Rootfs/mixtar-init-stage1.sh

installed target:
  /System/SystemTools/mixtar-init-stage1
```

It coordinates:

```text
/System/SystemTools/mixtar-mount-runtime
/System/SystemTools/mixtar-service-supervisor
```

Supported commands:

```text
check
dry-run
status
start
stop
restart
```

It refuses PID1 mode unless `MIXTAR_INIT_STAGE1_ALLOW_PID1=1` is explicitly set
for a test boot. This keeps the current safe boot path intact while allowing the
Mixtar-owned runtime/service closure to be exercised manually.

## Verified Live Stage 1 Check

Verified on the ThinkPad T480 on 2026-06-30:

```text
Boot:
  BootNext=0006
  kernel=7.1.2-mixtar-rt

Commands run as normal user:
  /System/SystemTools/mixtar-init-stage1 check
  /System/SystemTools/mixtar-init-stage1 dry-run
  /System/SystemTools/mixtar-init-stage1 status

Safe return:
  sudo -n /System/SystemTools/mixtar-reboot-debian-once 0003
```

Observed result:

```text
mount-runtime ok
service-supervisor ok
dbus command ok
iwd command ok
dhcpcd command ok
sshd command ok

/proc mounted
/sys mounted
/dev mounted
/run mounted as tmpfs
/dev/pts mounted
/dev/shm mounted

dbus running
iwd running
dhcpcd running
sshd running

returned to Debian fallback kernel 7.0.0-rc3-mixtarrvs
```

No service `start` was executed in this check. OpenRC remained the active boot
owner. The check only proved that MixtarRVS now has a readable `/System`
control surface for the currently Alpine/OpenRC-owned service closure.

## Verified Live Stage 1 Start Check

Verified on the ThinkPad T480 on 2026-06-30:

```text
Boot:
  BootNext=0006
  kernel=7.1.2-mixtar-rt

Wrapper:
  /System/SystemTools/mixtar-stage1-live-start-check

Sudo bridge:
  /etc/sudoers.d/mixtar-vxz-stage1-live-check

Safe return:
  sudo -n /System/SystemTools/mixtar-reboot-debian-once 0003
```

Observed result:

```text
check:
  mount-runtime ok
  service-supervisor ok
  dbus/iwd/dhcpcd/sshd commands ok

status-before:
  dbus running
  iwd running
  dhcpcd running
  sshd running

start:
  mount-runtime confirmed existing mounts
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

This proves Stage 1 `start` is idempotent against the current OpenRC-owned
service state. It did not replace OpenRC yet; it proved the Mixtar-owned control
surface can safely observe and converge the current minimal service set.

## Runtime/Library Closure Inventory

The runtime and shared-library closure was scanned offline from Debian fallback
after the Stage 1 live checks.

System copy:

```text
/System/Config/MixtarRVS/base-closure-stage1.runtime-libraries.txt
```

Repo summary:

```text
Server/Rootfs/RUNTIME_LIBRARY_CLOSURE_STAGE1.md
```

## Stage 2 Candidate

The next candidate component is documented separately:

```text
Server/Rootfs/PID1_STAGE2_CANDIDATE.md
```

It prepares:

```text
/System/SystemTools/mixtar-pid1-stage2
```

This is not boot-active in Stage 1. It exists to make the next boundary explicit:
Mixtar-owned boot orchestration without OpenRC owning service policy.

## Why This Exists

The broken boot showed this failure mode:

```text
OpenRC starts
mount tmpfs /run fails
/run/openrc cannot be created
dependency tree cannot be cached
sshd cannot read /etc/ssh/sshd_config reliably
the system reaches a login prompt but is not a healthy runtime
```

The direct cause was that the early boot path used a `mount` implementation that
looked for a missing `mount.tmpfs` helper instead of the known-working BusyBox
mount behavior.

## Next Replacement Order

Replace the bootstrap/runtime closure in this order:

```text
1. Mixtar initramfs handoff with writable runtime setup
2. Mixtar-owned /run, /dev, /proc, /sys mount setup
3. Mixtar minimal PID1 or service supervisor
4. Mixtar Linux mount/umount/fsck policy
5. Mixtar user/session account policy
6. Mixtar network bring-up wrapper or replacement
7. Mixtar SSH/remote-access policy
8. Mixtar boot generation and rollback manager
```

Only after those exist should `/bin` and `/sbin` stop being the Alpine/BusyBox
compatibility path.
