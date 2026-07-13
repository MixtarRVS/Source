# MixtarRVS Base Closure Current State

Updated: 2026-06-30

This file records the current ThinkPad T480 Base Closure boundary after the
safe MixtarRVS RT read/write boot/SSH/safe-return cycle.

It is not the final Base Closure. It is the current safe line that must not be
crossed accidentally.

## Verified Runtime State

Current safe boot relationship:

```text
BootOrder:
  Debian first
  MixtarRVS RT RW second
  MixtarRVS RT legacy third

Normal recovery:
  Debian remains the fallback OS

Preferred Mixtar test entry:
  efibootmgr -n 0007

Legacy Mixtar test entry:
  efibootmgr -n 0006

Mixtar safe return:
  sudo -n /System/SystemTools/mixtar-reboot-debian-once 0003
```

Verified on the ThinkPad:

```text
MixtarRVS:
  boots Linux 7.1.2-mixtar-rt through Boot0007 MixtarRVS-RT-RW
  mounts MIXTARROOT as ext4 read/write
  reaches OpenRC default runlevel
  mounts /run as tmpfs
  starts iwd
  starts dhcpcd
  starts sshd
  accepts SSH as vxz@192.168.99.110
  can return to Debian through the restricted sudoers command

Debian fallback:
  returns after Mixtar test
  remains reachable as vxz@192.168.99.110
```

## Latest Boot Repair

The latest verified safe entry is:

```text
Boot0007* MixtarRVS-RT-RW
  kernel: /EFI/mixtarrvs-rt/vmlinuz.efi
  initrd: /EFI/mixtarrvs-rt/initrd.img
  root: UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c
  rootfstype: ext4
  root mode: rw
  profile: rt-7.1.2-mixtar-rt
```

Boot0006 is kept as the older legacy entry:

```text
Boot0006* MixtarRVS RT
  rootflags=ro
  ro
```

Do not use Boot0006 as the preferred test path for Base Closure work. It can
still boot, but the verified read/write runtime path is Boot0007.

The latest repaired boot failure was:

```text
OpenRC could not mount tmpfs on /run.
/run/openrc could not be created.
OpenRC dependency cache writes failed.
The system reached tty login but did not have a healthy runtime.
```

The safe repaired state is:

```text
/bin  -> /Compatibility/POSIX/Alpine/3.24/bin
/sbin -> /Compatibility/POSIX/Alpine/3.24/sbin

/Compatibility/POSIX/Alpine/3.24/bin/mount  -> /bin/busybox
/Compatibility/POSIX/Alpine/3.24/bin/umount -> /bin/busybox
/Compatibility/POSIX/Alpine/3.24/sbin/mount  -> /bin/busybox
/Compatibility/POSIX/Alpine/3.24/sbin/umount -> /bin/busybox

/run is a real mountpoint directory before OpenRC starts.
```

This state was live-tested by booting `Boot0007`, confirming `/` as read/write
ext4, confirming SSH reachability, confirming `mixtar-userland-verify` PASS,
then returning to Debian through BootNext `0003`.

## Current Layout Boundary

The active, safe layout is:

```text
/System/Tools/Current -> MixtarRVS
/System/Tools/Current/bin
  MixtarRVS BSD-derived Toolkit identity

/bin  -> /Compatibility/POSIX/Alpine/3.24/bin
/sbin -> /Compatibility/POSIX/Alpine/3.24/sbin
```

This is intentional for the current stage.

OpenRC, init scripts, mount handling, tmpfs setup, and early boot still require
the Alpine/BusyBox compatibility tools. Moving `/bin` or `/sbin` to the
MixtarRVS Toolkit breaks boot because OpenRC expects Linux/BusyBox-compatible
behavior for early system operations.

## Source-Only Userland Slice

The MixtarRVS userland slice is now installed from a musl build produced inside
the Mixtar rootfs through Debian/chroot.

Current userland state:

```text
/System/Tools/MixtarRVS/bin
  157 source-built OpenBSD/FreeBSD-derived tools
  0 hosted placeholders

/System/Tools/Current -> MixtarRVS
```

The source list is recorded on the target at:

```text
/System/Config/MixtarRVS/userland-source-tools.txt
/System/Config/MixtarRVS/userland-source-only.manifest
```

The installer used for this path is:

```text
Server/Userland/Toolkit/Bridge/scripts/install_mixtarrvs_userland_from_debian.sh
```

Important boundary:

```text
/System/Tools/MixtarRVS/bin is the userland identity.
/bin and /sbin remain compatibility/bootstrap paths for OpenRC and early boot.
```

Verified:

```text
chroot from Debian:
  PATH=/System/Tools/MixtarRVS/bin:...
  uname, ls, cat, cp, grep, sed, awk, ps, find, sort, wc, head, tail resolve to
  /System/Tools/MixtarRVS/bin

normal Mixtar Boot0006:
  kernel=7.1.2-mixtar-rt
  explicit /System/Tools/MixtarRVS/bin command execution works
  vxz .profile prepends /System/Tools/MixtarRVS/bin for interactive sessions

normal Mixtar Boot0007:
  kernel=7.1.2-mixtar-rt
  / is /dev/nvme0n1p3 ext4 rw,relatime
  mixtar-userland-verify PASS
  vxz SSH works
  safe return to Debian works

fallback:
  returned to Debian kernel 7.0.0-rc3-mixtarrvs
```

Verification tool:

```text
source:
  Server/Rootfs/mixtar-userland-verify.sh

target:
  /System/SystemTools/mixtar-userland-verify
```

It checks:

```text
/System/Tools/MixtarRVS/bin exists
source tool manifest exists
tool count matches manifest
no non-manifest tools are present
selected command names resolve through /System/Tools/MixtarRVS/bin when that
path is first in PATH
/bin and /sbin remain bootstrap compatibility links
```

## Bootstrap Closure Report

The current Alpine/bootstrap dependency report is generated by:

```text
source:
  Server/Rootfs/mixtar-bootstrap-closure-report.sh

target:
  /System/SystemTools/mixtar-bootstrap-closure-report
```

Current target reports:

```text
/System/Config/MixtarRVS/bootstrap-closure-report-mounted.txt
  generated from Debian against mounted /dev/nvme0n1p3

/System/Config/MixtarRVS/bootstrap-closure-report-live.txt
  generated from live Boot0007 MixtarRVS-RT-RW
```

The live report currently records these blockers:

```text
pid1           -> /sbin/init
shell          -> /bin/sh
mount          -> /bin/mount, /sbin/mount
device_nodes   -> /sbin/mdev
kernel_modules -> /sbin/modprobe, /sbin/depmod
services       -> /sbin/openrc, /sbin/rc-service
network        -> /usr/libexec/iwd, /sbin/dhcpcd
remote         -> /usr/sbin/sshd
packages       -> /sbin/apk
libraries      -> /lib, /usr/lib, /System/Libraries
```

Next replacement order:

```text
1. initramfs-runtime
   status: PID1 one-shot handoff PASS, not default boot path yet
2. pid1-supervisor
   status: PID1 one-shot OpenRC handoff PASS, OpenRC remains backend
3. device-and-module-tools
4. network
5. remote
6. package-source
```

## Initramfs Runtime Candidate

Mixtar-owned initramfs runtime candidate:

```text
source:
  Server/Rootfs/mixtar-initramfs-runtime.sh

target:
  /System/SystemTools/mixtar-initramfs-runtime
```

Installed behavior:

```text
contract
write-contract
check
ensure
handoff-dry-run
handoff
```

Live verified through `Boot0007 MixtarRVS-RT-RW`:

```text
kernel=7.1.2-mixtar-rt
/=/dev/nvme0n1p3 ext4 rw,relatime
/dev mounted
/proc mounted
/sys mounted
/run mounted
root mount is rw
musl loader path starts with /System/Libraries
status: PASS
```

Target evidence:

```text
/System/Config/MixtarRVS/initramfs-runtime-live-check.txt
/System/Config/MixtarRVS/initramfs-runtime.contract
/System/Config/MixtarRVS/initramfs-runtime-plan.txt
```

One-shot handoff verified through `Boot0008 MixtarRVS-RT-HANDOFF`:

```text
cmdline includes:
  init=/System/SystemTools/mixtar-initramfs-runtime

runtime PID1 marker:
  stage=before-system-init
  pid=1
  next=/System/SystemTools/init boot
  kernel=7.1.2-mixtar-rt

init shim PID1 marker:
  stage=after-runtime-mounts
  pid=1
  next=/sbin/init
  kernel=7.1.2-mixtar-rt

runtime check:
  status: PASS

fallback after test:
  BootCurrent: 0003
```

Target proof:

```text
/System/Config/MixtarRVS/initramfs-runtime-handoff-live-proof.txt
```

Important implementation boundary:

```text
The early runtime still uses /bin/mount explicitly for Linux mount operations.
That is intentional for the current stage because Mixtar Toolkit mount is not
yet the Linux early-boot mount provider.
```

Boundary:

```text
This is not yet the default boot path.
Current safe default remains Debian first, then Boot0007 MixtarRVS-RT-RW.
Boot0008 is a verified one-shot handoff candidate and must not become default
until the next service-supervisor stage is ready.
```

## Supervisor PID1 Candidate

Mixtar-owned supervisor candidate:

```text
source:
  Server/Rootfs/mixtar-supervisor.sh

target:
  /System/SystemTools/mixtar-supervisor
```

Init shim integration:

```text
source:
  Server/Rootfs/mixtar-init-shim.sh

target:
  /System/SystemTools/init
```

One-shot supervisor handoff verified through `Boot0009 MixtarRVS-RT-SUPERVISOR`:

```text
cmdline includes:
  init=/System/SystemTools/mixtar-initramfs-runtime
  mixtar.supervisor=pre-openrc

runtime PID1 marker:
  stage=before-system-init
  pid=1
  next=/System/SystemTools/init boot
  kernel=7.1.2-mixtar-rt

init shim PID1 marker:
  stage=after-runtime-mounts
  pid=1
  next=/System/SystemTools/mixtar-supervisor pid1-openrc
  kernel=7.1.2-mixtar-rt

supervisor PID1 marker:
  stage=before-openrc
  pid=1
  next=/sbin/init
  kernel=7.1.2-mixtar-rt

supervisor check:
  status: PASS

fallback after test:
  BootCurrent: 0003
```

Target proof:

```text
/System/Config/MixtarRVS/supervisor-pid1-openrc-live-proof.txt
/System/Config/MixtarRVS/supervisor-pid1-latest.txt
/System/Config/MixtarRVS/supervisor-pid1-check.txt
```

Boundary:

```text
Supervisor is now proven as PID1 in a one-shot path.
It still uses OpenRC as the service backend through /sbin/init.
It does not yet replace OpenRC service ordering or service execution.
```

## Direct Service Status

Mixtar-owned direct service health check:

```text
command:
  /System/SystemTools/mixtar-supervisor direct-status

backend:
  mixtar-procfs
```

Live verified through `Boot0009 MixtarRVS-RT-SUPERVISOR`:

```text
dbus:
  process=dbus-daemon
  socket=/run/dbus/system_bus_socket

iwd:
  process=iwd

dhcpcd:
  process=dhcpcd

sshd:
  process=sshd

status:
  PASS
```

Target proof:

```text
/System/Config/MixtarRVS/supervisor-direct-status-live-proof.txt
/System/Config/MixtarRVS/supervisor-direct-status-live.txt
/System/Config/MixtarRVS/supervisor-check-live.txt
```

Boundary:

```text
Mixtar now owns direct status for the critical runtime services.
OpenRC still owns service start/stop/order.
```

## Direct Start Candidate: dbus

Mixtar-owned direct start candidate:

```text
command:
  /System/SystemTools/mixtar-supervisor direct-start dbus

plan:
  /System/SystemTools/mixtar-supervisor direct-start-plan dbus

backend:
  mixtar-direct
```

Implemented behavior:

```text
1. If dbus-daemon and /run/dbus/system_bus_socket already exist, do nothing.
2. Ensure /run/dbus exists.
3. Start /usr/bin/dbus-daemon --system --fork.
4. Verify dbus through Mixtar direct-status.
```

Live verified through `Boot0009 MixtarRVS-RT-SUPERVISOR` while OpenRC had
already started dbus:

```text
direct-start:
  ok: dbus already running
  rc=0

direct-status-after:
  dbus PASS
  iwd PASS
  dhcpcd PASS
  sshd PASS
```

Target proof:

```text
/System/Config/MixtarRVS/supervisor-direct-start-dbus-live-proof.txt
/System/Config/MixtarRVS/supervisor-direct-start-dbus-plan.txt
/System/Config/MixtarRVS/supervisor-direct-start-dbus-live.txt
/System/Config/MixtarRVS/supervisor-direct-status-after-dbus-start.txt
```

Boundary:

```text
Direct-start dbus is implemented.
No-op safety is live-verified.
Cold-starting dbus before OpenRC is live-verified through Boot000A.
OpenRC still owns default ordering and the rest of the service start sequence.
```

## Direct Start Cold Proof: dbus before OpenRC

One-shot entry:

```text
Boot000A* MixtarRVS-RT-DBUS-COLD
```

Cmdline delta from Boot0009:

```text
mixtar.direct_start=dbus
```

Verified flow:

```text
initramfs-runtime PID1
  -> init shim PID1
    -> supervisor PID1
      -> direct-start dbus before OpenRC
      -> /sbin/init OpenRC
```

PID1 direct-start result:

```text
MixtarRVS direct start
backend: mixtar-direct
ok: dbus process=dbus-daemon socket=/run/dbus/system_bus_socket
```

Expected early status detail:

```text
The PID1 direct_status_after report sees dbus OK and iwd/dhcpcd/sshd FAIL.
That is expected because iwd, dhcpcd, and sshd are still started later by
OpenRC in this stage.
```

Post-boot live observation from the Boot000A SSH session:

```text
dbus PASS
iwd PASS
dhcpcd PASS
sshd PASS
```

Target proof:

```text
/System/Config/MixtarRVS/supervisor-direct-start-dbus-cold-live-proof.txt
/System/Config/MixtarRVS/supervisor-pid1-direct-start-dbus.txt
```

Boundary:

```text
dbus can now be started by Mixtar before OpenRC.
OpenRC remains responsible for dhcpcd, sshd, and service ordering.
```

## Direct Start Candidate: iwd

Mixtar-owned direct start candidate:

```text
command:
  /System/SystemTools/mixtar-supervisor direct-start iwd

plan:
  /System/SystemTools/mixtar-supervisor direct-start-plan iwd

backend:
  mixtar-direct
```

Implemented behavior:

```text
1. Require dbus direct status to be OK.
2. If iwd already exists, do nothing.
3. Start /usr/libexec/iwd in background.
4. Write /run/iwd.pid.
5. Verify iwd through Mixtar direct-status.
```

No-op safety verified through `Boot0009 MixtarRVS-RT-SUPERVISOR` while OpenRC
had already started iwd:

```text
direct-start:
  ok: iwd already running
  rc=0

direct-status-after:
  dbus PASS
  iwd PASS
  dhcpcd PASS
  sshd PASS
```

Cold-start verified through:

```text
Boot000B* MixtarRVS-RT-IWD-COLD
```

Cmdline delta:

```text
mixtar.direct_start=dbus,iwd
```

Verified flow:

```text
initramfs-runtime PID1
  -> init shim PID1
    -> supervisor PID1
      -> direct-start dbus before OpenRC
      -> direct-start iwd before OpenRC
      -> /sbin/init OpenRC
```

PID1 direct-start iwd result:

```text
MixtarRVS direct start
backend: mixtar-direct
ok: iwd process=iwd
```

Expected early status detail:

```text
The PID1 direct_status_after report sees dbus OK and iwd OK, while dhcpcd and
sshd are still FAIL. That is expected because dhcpcd and sshd are still started
later by OpenRC in this stage.
```

Post-boot live observation from the Boot000B SSH session:

```text
dbus PASS
iwd PASS
dhcpcd PASS
sshd PASS
```

Target proof:

```text
/System/Config/MixtarRVS/supervisor-direct-start-iwd-cold-live-proof.txt
/System/Config/MixtarRVS/supervisor-pid1-direct-start-iwd.txt
```

Boundary:

```text
dbus and iwd can now be started by Mixtar before OpenRC.
OpenRC remains responsible for dhcpcd, sshd, and service ordering.
```

## Current Compatibility Boundary

Alpine is no longer the desired identity, but it is still part of the boot and
runtime closure.

Current compatibility responsibilities:

```text
/Compatibility/POSIX/Alpine/3.24/bin
  sh
  mount
  umount
  mkdir
  busybox applets needed by OpenRC and init scripts

/Compatibility/POSIX/Alpine/3.24/sbin
  init
  reboot
  service tools required by OpenRC/bootstrap

/etc
  OpenRC configuration
  sshd configuration
  iwd/dhcpcd configuration
  passwd/group/shadow
  restricted sudoers bridge
```

The MixtarRVS Toolkit is currently promoted as a user/session identity through:

```text
/System/Tools/Current/bin
```

It is not yet safe to make it PID1/OpenRC's `/bin`.

## Verified User Access

Current Mixtar user:

```text
user:  vxz
uid:   1000
gid:   1000
home:  /Users/vxz
shell: /bin/sh
auth:  SSH public key copied from Debian
```

Restricted sudoers bridge:

```text
/etc/sudoers.d/mixtar-vxz-safe-admin
```

Allowed command:

```text
/System/SystemTools/mixtar-reboot-debian-once
/System/SystemTools/mixtar-reboot-debian-once *
```

This is deliberately narrow. It exists only so the normal test user can return
the laptop to Debian fallback without needing a manual power cycle.

## Network State

Current Mixtar network path:

```text
interface: wlan0
tooling:   iwd + dhcpcd
address:   192.168.99.110/24
gateway:   192.168.99.254
ssh:       0.0.0.0:22
```

The iwd profile is copied from Debian into:

```text
/var/lib/iwd
```

The static address is configured in:

```text
/etc/dhcpcd.conf
```

## Removed Temporary Diagnostics

The temporary `mixtar-network-late-report` diagnostic service was removed from
the default runlevel after it served its purpose.

Removed from active boot:

```text
/etc/runlevels/default/mixtar-network-late-report
/etc/init.d/mixtar-network-late-report
/System/SystemTools/mixtar-network-late-report
```

Backups/logs were moved under:

```text
/System/Logs
```

## Do Not Repeat

Do not make this change again:

```text
/bin -> /System/Tools/Current/bin
/sbin -> /System/SystemTools
```

That change makes the system look more like Mixtar, but it breaks the current
OpenRC bootstrap closure. It caused `/run` tmpfs and dependency handling to
fail because early boot commands were no longer Linux/BusyBox-compatible.

The correct next step is not to hide Alpine harder. The correct next step is to
replace the remaining boot/runtime closure deliberately.

## Next Closure Targets

To remove Alpine as identity and eventually as bootstrap dependency, replace
these layers in order:

1. Mixtar initramfs handoff
2. Mixtar PID1 or minimal service supervisor
3. Linux mount/dev/proc/sys/run setup tools
4. fsck/ext4 handling or explicit no-fsck policy
5. user/group/session setup
6. network bring-up for iwd/dhcpcd replacement or owned wrappers
7. ssh/remote access policy
8. controlled boot generation and rollback manager

Only after those are owned by MixtarRVS should `/bin` and `/sbin` stop pointing
at `/Compatibility/POSIX/Alpine/3.24`.

## Acceptance For The Next Stage

The next safe stage should prove:

```text
MixtarRVS boots with:
  /System/SystemTools/init or supervisor owned by MixtarRVS
  /run mounted correctly
  /dev, /proc, /sys mounted correctly
  network up
  ssh reachable
  safe return to Debian still works

and without requiring:
  /bin/mount from Alpine/BusyBox
  /sbin/init from Alpine/BusyBox
```

Until that is true, Alpine remains a compatibility/bootstrap substrate, not the
system identity.
