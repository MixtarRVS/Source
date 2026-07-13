# MixtarRVS Base Closure ThinkPad Findings

Updated: 2026-06-30

This file records the current ThinkPad evidence used for the Base Closure work.
It is intentionally operational and concrete.

## Current reachable environment

The ThinkPad is currently reachable through Debian at:

```text
192.168.99.110
```

Mixtar root partition:

```text
/dev/nvme0n1p3
label: MIXTARROOT
uuid: 146d4ab3-3e58-4317-8799-da2f451b9a6c
```

Debian root partition:

```text
/dev/nvme0n1p2
```

## Evidence collected

Read-only collection was done from Debian with:

```text
Server/Rootfs/scripts/debian-mixtar-safe-recovery.sh collect /dev/nvme0n1p3
```

The run mounted Mixtar read-only and wrote:

```text
/tmp/mixtar-safe-report-20260630-131331.txt
```

No chroot, reboot, BootNext, or EFI mutation was used for collection.

## Important findings

Mixtar fallback boot is still the stable baseline:

```text
/System/Current -> Generations/0002-alpine-openrc-zsh
```

`/System/Previous` is not currently set.

Mixtar is still not Base Closure clean:

```text
/System/Tools       -> ../bin
/System/SystemTools -> ../sbin
/System/Config      -> ../etc
/System/Libraries   -> ../lib
```

That means the current system is still Alpine/OpenRC/musl as the active
bootstrap substrate with Mixtar names layered on top. `/System` is not yet the
source of truth.

The root directory is still visually mixed:

```text
Applications
Compatibility
Programs
System
Temporary
Users
Volumes
bin
boot
dev
etc
lib
proc
run
sbin
sys
usr
var
```

This confirms that Clean Root has not been safely activated.

## Space blocker

Mixtar root has critically low free space:

```text
size: 7.7G
used: 7.1G
free: 181M
use: 98%
```

The main cause is inactive experimental rootfs-image generations:

```text
0030-rootfs-image-runtime-closure-confirmed-supervisor  762M
0031-rootfs-image-local-health-supervisor               762M
0032-rootfs-image-bounded-local-health-supervisor       762M
0033-rootfs-image-direct-service-supervisor             762M
0033-rootfs-image-early-watchdog-supervisor             762M
0033-rootfs-image-hard-trace-pid1-supervisor            762M
0034-rootfs-image-static-network-selftest-supervisor    762M
```

These are not the current fallback generation. They should be pruned before
building another Base Closure stage.

Prepared safe pruning tool:

```text
Server/Rootfs/scripts/debian-mixtar-prune-experimental-generations.sh
```

Default mode is dry-run. It only removes generations with `rootfs-image` in the
name, and refuses to remove the current or previous generation.

## SSH and runtime state

The collected OpenRC log from the stable fallback shows:

```text
dbus   started
iwd    started
dhcpcd started
sshd   started
```

This means the stable fallback can start SSH when it reaches normal OpenRC
default runlevel. The earlier SSH failures are therefore more likely tied to
the experimental rootfs-image boot path, network reachability, or boot state,
not simply to a missing `sshd_config` in the fallback root.

## Rootfs-image failure class

The failed experimental rootfs-image boot path showed:

```text
Read-only file system
can't create /System/Runtime/initramfs/base/System/Base/Closure/*.log
can't create /dev/null
```

This confirms that rootfs-image boot attempted to write runtime state into a
read-only image/root without a correct writable overlay/runtime handoff.

Base Closure must not continue by adding more rootfs-image generations until
the initramfs contract is fixed.

## Next safe order

1. Prune inactive rootfs-image generations to restore free space.
2. Keep `/System/Current` on `0002-alpine-openrc-zsh` until a new stage is
   proven from Debian/offline checks.
3. Build the next stage as an inactive generation first.
4. Move `/System` toward source-of-truth ownership without moving live `/bin`,
   `/sbin`, `/etc`, `/lib`, or `/usr` in-place.
5. Fix initramfs writable runtime contract before any new rootfs-image boot.

Do not mutate UEFI, reboot, or chroot as part of Base Closure diagnosis.

## Base Closure inventory, 2026-06-30

Read-only inventory was collected from Debian with:

```text
Server/Rootfs/scripts/debian-mixtar-base-closure-inventory.sh /dev/nvme0n1p3
```

The report was written on the ThinkPad to:

```text
/tmp/mixtar-base-closure-inventory-20260630-131948.txt
```

Confirmed `/System` state:

```text
/System/Tools       -> ../bin
/System/SystemTools -> ../sbin
/System/Config      -> ../etc
/System/Libraries   -> ../lib
/System/Runtime     directory
/System/Kernel      directory
/System/Shells      directory
/System/Logs        directory
```

Confirmed tool ownership counters:

```text
/bin executable files:              26
/bin symlinks:                       72
/sbin executable files:              58
/sbin symlinks:                      50
/System/Tools executable files:       0
/System/SystemTools executable files: 0
```

This proves the active fallback is still Alpine/BusyBox/OpenRC as identity.
Mixtar names are present, but the tool closure has not moved under `/System`.

Runtime mountpoint gaps in the offline root:

```text
/dev/null    file, not character device
/dev/tty     missing
/dev/tty0    missing
/proc/mounts missing
/sys/kernel  missing
/run/openrc  missing
```

This does not mean these are always missing at runtime, because OpenRC can mount
some of them in the stable fallback. It does mean any rootfs-image or clean-root
stage must explicitly create/mount these before services start.

The next Base Closure stage must therefore solve these in order:

```text
1. /System/Tools independent directory with certified MixtarRVS tools.
2. /System/SystemTools independent directory with boot/runtime control tools.
3. /System/Config independent directory or declared compatibility bridge.
4. /System/Libraries independent directory with musl loader/libs closure.
5. initramfs/runtime mounts for devtmpfs, procfs, sysfs, tmpfs /run, tmpfs /tmp.
6. service dependency graph for dbus, iwd, dhcpcd, sshd.
```

## Toolkit repair, 2026-06-30

The generated WSL/Linux Toolkit binaries were confirmed to be glibc-linked:

```text
interpreter: /lib64/ld-linux-x86-64.so.2
needed: libc.so.6
```

They must not be installed as MixtarRVS native tools on the musl root.

The musl packaging helper had a group-selection bug: `package-musl all` was
being resolved as a literal tool named `all`, which produced a package that
only built `echo`. This was repaired in:

```text
Server/Userland/Toolkit/Bridge/scripts/mixtarrvs_musl_toolkit.py
```

`all`, `tier-a`, `source`, and `core` now map to the source-certified Toolkit
list and duplicate names are removed while preserving order.

After the fix:

```text
out/server/toolkit_build.exe package-musl all
```

produced a musl source package whose build script contains:

```text
157 source-certified userland tools
```

The extra generated WSL artifact not in the source package is:

```text
rpcgen_probe
```

That is a helper/probe artifact, not a normal command surface tool.

## ThinkPad deployment result, 2026-06-30

The musl-native Toolkit was built inside the Mixtar root from Debian using an
isolated chroot mount namespace. No `apk add` was needed because the required
build packages were already present:

```text
build-base
linux-headers
musl-fts-dev
flex
bison
ncurses-dev
perl
```

Installed profile:

```text
/System/Tools/MixtarRVS/bin
/System/Tools/MixtarRVS/libexec
/System/Tools/Current -> MixtarRVS
```

Chroot smoke result:

```text
command -v ls  -> /System/Tools/Current/bin/ls
command -v cat -> /System/Tools/Current/bin/cat
command -v sh  -> /System/Tools/Current/bin/sh
tool_count     -> 158 files in /System/Tools/Current/bin
```

Representative binaries now use musl:

```text
/System/Tools/Current/bin/ls
  interpreter: /lib/ld-musl-x86_64.so.1
  needed: libfts.so.0, libc.musl-x86_64.so.1

/System/Tools/Current/bin/cat
  interpreter: /lib/ld-musl-x86_64.so.1
  needed: libc.musl-x86_64.so.1

/System/Tools/Current/bin/sh
  interpreter: /lib/ld-musl-x86_64.so.1
  needed: libc.musl-x86_64.so.1
```

Shell PATH smoke:

```text
/bin/sh -lc 'command -v ls'
  /System/Tools/Current/bin/ls

/bin/zsh -lc 'command -v ls'
  /System/Tools/Current/bin/ls

/bin/zsh -lic 'command -v ls'
  /System/Tools/Current/bin/ls
```

Live boot result:

```text
BootCurrent: 0006 MixtarRVS RT
OpenRC default reached
dbus started
iwd started
dhcpcd started
sshd started
mixtar-return-debian-once scheduled return after 180s
BootNext set to Boot0003 debian
system returned to Debian
```

This proves the current safe stage:

```text
Linux/Alpine/OpenRC bootstrap still boots.
MixtarRVS musl Toolkit is now built from OpenBSD/FreeBSD source through the Bridge.
Interactive shell PATH resolves normal commands to /System/Tools/Current/bin first.
Debian fallback remains intact.
```

Remaining Base Closure gap:

```text
/System/Tools is still a compatibility symlink to ../bin in the active fallback.
The Toolkit profile lives under /System/Tools/MixtarRVS through that path.
The next closure step is making /System/Tools an independent source-of-truth
directory without breaking /bin compatibility.
```

## Source-of-truth `/System/Tools` step, 2026-06-30

The active root was moved one step closer to Base Closure:

```text
/System/Tools       directory
/System/SystemTools directory
/bin                -> /System/Tools/Current/bin
/sbin               -> /System/SystemTools
```

The original Alpine bootstrap directories were preserved:

```text
/Compatibility/POSIX/Alpine/3.24/bin
/Compatibility/POSIX/Alpine/3.24/sbin
```

The first live boot after this change did not expose SSH within the test
window. The likely cause was `/bin/sh` resolving to the BSD-derived shell while
OpenRC/Alpine boot scripts still require BusyBox ash compatibility.

The shell compatibility fix:

```text
/System/Tools/Current/bin/sh      -> busybox
/System/Tools/Current/bin/ash     -> busybox
/System/Tools/Current/bin/bsd-sh  preserved BSD-derived shell
/System/Tools/Current/bin/mixtar-sh -> bsd-sh
```

Chroot smoke after the fix:

```text
/bin                -> /System/Tools/Current/bin
/sbin               -> /System/SystemTools
sh                  -> /System/Tools/Current/bin/sh
sh target           -> busybox
bsd-sh              works
ls                  -> /System/Tools/Current/bin/ls
rc-status           -> /System/Tools/Current/bin/rc-status
openrc              -> /System/SystemTools/openrc
```

Five-minute Mixtar safety reboot is enabled:

```text
/System/Runtime/return-to-debian.always = 300
/System/Config/MixtarRVS/return-to-debian.delay = 300
/etc/init.d/mixtar-return-debian-once
/etc/runlevels/default/mixtar-return-debian-once
```

Boot policy:

```text
BootOrder: Debian first
Mixtar test boots must use BootNext only
```

This means a successful Mixtar userspace boot should automatically return to
Debian after 300 seconds. If Mixtar fails before OpenRC default starts, a manual
reset should fall back to Debian because Debian is first in BootOrder.

## SSH watchdog, 2026-06-30

An immediate failure watchdog was installed for Mixtar live boots:

```text
/System/SystemTools/mixtar-ssh-watchdog
/etc/init.d/mixtar-ssh-watchdog
/etc/runlevels/default/mixtar-ssh-watchdog
/System/Config/MixtarRVS/ssh-watchdog.delay = 45
```

Behavior:

```text
wait 45 seconds after OpenRC default starts
check non-loopback IPv4 address
check sshd process
check tcp/22 listening
if any check fails:
  append diagnostics to /System/Logs/ssh-watchdog.log
  set BootNext to Debian Boot0003
  reboot immediately
```

The watchdog captures:

```text
uname -a
/proc/cmdline
/proc/mounts
ip addr
ip route
netstat -ltn
ps
rc-status
/run tree
sshd config test
tail of /var/log/rc.log
dmesg
```

The five-minute safety return remains enabled independently:

```text
/System/Runtime/return-to-debian.always = 300
```

Chroot smoke result:

```text
watchdog=/System/SystemTools/mixtar-ssh-watchdog
netstat=/System/Tools/Current/bin/netstat
ip=/System/SystemTools/ip
ps=/System/Tools/Current/bin/ps
reboot_tool=ok
delay=45
autoreboot=300
SMOKE_OK
```

The first default-runlevel watchdog placement was not sufficient: the collected
post-test logs showed an empty `ssh-watchdog.log` and no
`mixtar-ssh-watchdog` start line in `rc.log`. That means Mixtar did not reach
the default watchdog service during the failing boot window.

The watchdog was therefore moved earlier as well:

```text
/etc/init.d/mixtar-ssh-watchdog-early
/etc/runlevels/boot/mixtar-ssh-watchdog-early -> ../../init.d/mixtar-ssh-watchdog-early
/System/Config/MixtarRVS/ssh-watchdog-early.delay = 90
```

The default watchdog remains:

```text
/etc/runlevels/default/mixtar-ssh-watchdog -> ../../init.d/mixtar-ssh-watchdog
/System/Config/MixtarRVS/ssh-watchdog.delay = 45
```

Boot policy was restored to Debian-first:

```text
BootOrder: 0003,0006,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
```

Chroot smoke after moving the watchdog earlier:

```text
EARLY_WATCHDOG_SMOKE
early_delay=90
default_delay=45
ip=/System/SystemTools/ip
netstat=/System/Tools/Current/bin/netstat
ps=/System/Tools/Current/bin/ps
reboot_tool=ok
SMOKE_OK
```

Expected next Mixtar test behavior:

```text
if boot reaches boot runlevel but SSH never becomes available:
  /System/Logs/ssh-watchdog.log gets diagnostics
  system returns immediately to Debian

if boot reaches default runlevel and SSH is unavailable:
  /System/Logs/ssh-watchdog.log gets diagnostics
  system returns immediately to Debian

if boot fails before OpenRC boot runlevel:
  firmware default remains Debian, so manual reset returns to Debian
```
