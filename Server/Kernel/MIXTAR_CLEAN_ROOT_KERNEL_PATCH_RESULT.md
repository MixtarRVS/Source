# Mixtar Clean-Root Linux Kernel Patch Result

Updated: 05.07.2026

Goal:

```text
Patch Linux RT 7.1.2 so the kernel boot path follows MixtarRVS clean-root
identity instead of requiring /dev, /sbin, /etc, /bin fallback paths.
```

Safety boundary:

```text
No Debian mutation.
No EFI partition writes.
No boot-order changes.
No physical disk changes.
Only local source/build/rootfs artifacts were changed.
```

## Files Added Or Changed

Repository files:

```text
Server/Kernel/scripts/apply_mixtar_clean_root_kernel_patch.sh
Server/Kernel/configs/mixtar-corev05-rt.fragment
Server/Rootfs/scripts/corev05-build-efi.sh
```

Generated/kernel workspace patched by script:

```text
/home/V/.cache/mixtarrvs-corev05/kernel/src/linux-7.1.2/init/main.c
/home/V/.cache/mixtarrvs-corev05/kernel/src/linux-7.1.2/init/do_mounts.c
/home/V/.cache/mixtarrvs-corev05/kernel/src/linux-7.1.2/init/noinitramfs.c
```

## Kernel Source Changes

### init/main.c

Changed initial console path:

```text
from: /dev/console
to:   /System/Devices/console
```

Changed fallback init behavior:

```text
from:
  /sbin/init
  /etc/init
  /bin/init
  /bin/sh

to:
  /System/Init/MixtarRVS
```

### init/do_mounts.c

Changed block-root helper:

```text
from: /dev/root
to:   /System/Devices/root
```

### init/noinitramfs.c

Changed default kernel-created rootfs:

```text
from:
  /dev
  /dev/console
  /root

to:
  /System
  /System/Devices
  /System/Devices/console
  /Users
  /Users/root
```

## Build Config Changes

Kernel config now contains:

```text
CONFIG_DEFAULT_INIT="/System/Init/MixtarRVS"
CONFIG_CMDLINE="quiet loglevel=4 console=tty0 console=ttyS0,115200 rdinit=/System/Init/MixtarRVS init=/System/Init/MixtarRVS devtmpfs.mount=0"
CONFIG_DEVTMPFS=y
# CONFIG_DEVTMPFS_MOUNT is not set
```

Meaning:

```text
devtmpfs exists
devtmpfs is not automounted at /dev
Mixtar Init owns mounting devices under /System/Devices
```

## Initramfs Changes

The generated initramfs now contains:

```text
System/Devices/console
System/Devices/null
```

and does not contain:

```text
dev
dev/console
dev/null
```

This means the early Linux bootstrap no longer needs a technical `/dev` in the
initramfs.

## Build Result

Command:

```text
wsl.exe --cd /mnt/c/Users/V/source/repos/MixtarRVS -- bash -lc 'JOBS=${JOBS:-$(nproc)} bash Server/Rootfs/scripts/corev05-build-efi.sh all'
```

Result:

```text
PASS
```

Built artifact:

```text
Server/Rootfs/Generated/corev05-efi-build/MixtarRVS-0.5.efi
Server/Rootfs/Generated/corev05-root/System/EFI/MixtarRVS/0.5.efi
```

Build observed recompilation of:

```text
init/main.o
init/do_mounts.o
drivers/base/devtmpfs.o
usr/initramfs_inc_data
```

CoreV05 verifier:

```text
PASS
```

## QEMU Smoke Result

Command:

```text
wsl.exe --cd /mnt/c/Users/V/source/repos/MixtarRVS -- bash Server/Rootfs/scripts/corev05-qemu-smoke.sh
```

Result:

```text
PASS
corev05-qemu-smoke: boot marker found
```

Observed boot output:

```text
MixtarRVS Init: AILang PID1
MixtarRVS Init: native root only
MixtarRVS Init: case-sensitive paths
MixtarRVS Init: POSIX only through /System/Compatibility
session: starting ZSH
vxz@MixtarRVS:/>
```

The previous early warning:

```text
Warning: unable to open an initial console.
```

was not observed.

## Remaining `/dev/console` String

`strings vmlinux` still finds:

```text
/dev/console
Couldn't register /dev/console driver
```

This is not the boot open path from `init/main.c`. The boot-open path now appears
as:

```text
/System/Devices/console
```

The remaining string is a driver/message-level compatibility string and is not
currently blocking clean-root boot.

## Decision

The first clean-root kernel patch is successful.

Linux RT now boots the local Mixtar image without requiring:

```text
/dev/console
/dev/root
/sbin/init
/etc/init
/bin/init
/bin/sh
```

for the primary boot path.

## Next Work

Next technical target should be:

```text
Mixtar Driver Store v0
```

Scope:

```text
1. Inspect loaded/built-in driver set.
2. Define /System/Kernel/Linux/RT/7.1.2/Drivers.config.
3. Distinguish:
   boot-required
   hardware-present
   optional-local
   blocked
4. Add /System/Tools/drivers status.
5. Keep no distro coldplug policy.
```

Do not move to physical ThinkPad boot until:

```text
QEMU smoke stays clean
driver profile is explicit
there is an autoreturn/recovery path
```
