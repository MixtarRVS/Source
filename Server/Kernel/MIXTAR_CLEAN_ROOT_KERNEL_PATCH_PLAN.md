# Mixtar Clean-Root Linux Kernel Patch Plan

Updated: 05.07.2026

Scope:

```text
Map Linux kernel hardcoded paths that conflict with MixtarRVS clean-root.
Separate kernel boot ABI from userland convention.
Prepare a minimal patch plan.
Do not rebuild the kernel in this step.
Do not touch Debian, EFI, boot order, or physical disks.
```

Local kernel source inspected:

```text
Server/Kernel/Generated/build/linux-7.1.2-mixtar-rt/source
```

Context artifact:

```text
Server/Kernel/Generated/linux-7.1.2-boot-path-context.txt
```

Current relevant kernel config:

```text
CONFIG_DEFAULT_INIT=""
CONFIG_BLK_DEV_INITRD=y
CONFIG_INITRAMFS_SOURCE=".../corev05-initramfs.cpio"
CONFIG_MODULES=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
# CONFIG_DEVTMPFS_SAFE is not set
```

## Kernel-Hardcoded Paths Found

### 1. Init command line support

File:

```text
init/main.c
```

Relevant lines:

```text
__setup("init=", init_setup);
__setup("rdinit=", rdinit_setup);
```

Meaning:

```text
Linux already supports explicit init paths.
Mixtar can pass:
  rdinit=/System/Init/MixtarRVS
  init=/System/Init/MixtarRVS
```

This is not the problem. The problem is fallback behavior when explicit init is
missing or rejected.

### 2. POSIX init fallback paths

File:

```text
init/main.c
```

Relevant lines:

```text
try_to_run_init_process("/sbin/init")
try_to_run_init_process("/etc/init")
try_to_run_init_process("/bin/init")
try_to_run_init_process("/bin/sh")
```

Mixtar conflict:

```text
/sbin
/etc
/bin
```

are not native Mixtar root identity.

Patch policy:

```text
Add CONFIG_MIXTAR_STRICT_INIT_FALLBACKS.

When enabled:
  do not try POSIX fallback init paths
  try only CONFIG_DEFAULT_INIT if set
  otherwise panic with a Mixtar-specific message
```

Recommended config:

```text
CONFIG_DEFAULT_INIT="/System/Init/MixtarRVS"
CONFIG_MIXTAR_STRICT_INIT_FALLBACKS=y
```

### 3. Initial console path

File:

```text
init/main.c
```

Relevant line:

```text
filp_open("/dev/console", O_RDWR, 0);
```

Mixtar conflict:

```text
/dev/console
```

Current workaround:

```text
initramfs creates technical /dev/console for early Linux bootstrap.
Mixtar PID1 removes /dev from final native identity later.
```

Mixtar patch policy:

```text
Add CONFIG_MIXTAR_CONSOLE_PATH.

Default upstream-compatible:
  "/dev/console"

Mixtar:
  "/System/Devices/console"
```

Then `console_on_rootfs()` should open:

```text
CONFIG_MIXTAR_CONSOLE_PATH
```

This makes the kernel adapt to Mixtar paths instead of forcing `/dev/console`.

### 4. Default no-initramfs rootfs creates /dev and /root

File:

```text
init/noinitramfs.c
```

Relevant lines:

```text
init_mkdir("/dev", 0755);
init_mknod("/dev/console", ...);
init_mkdir("/root", 0700);
```

Mixtar conflict:

```text
/dev
/dev/console
/root
```

Patch policy:

```text
Add CONFIG_MIXTAR_DEFAULT_ROOTFS_LAYOUT.

When enabled:
  create /System
  create /System/Devices
  create /System/Devices/console
  create /Users
  create /Users/root

Do not create:
  /dev
  /root
```

Impact:

```text
This only matters when booting without an explicit initramfs.
Mixtar normally uses its own initramfs/root image, but patching this keeps the
kernel internally consistent with Mixtar identity.
```

### 5. Block-root helper creates /dev/root

File:

```text
init/do_mounts.c
```

Relevant lines:

```text
create_dev("/dev/root", ROOT_DEV);
mount_root_generic("/dev/root", root_device_name, root_mountflags);
```

Mixtar conflict:

```text
/dev/root
```

Patch policy:

```text
Add CONFIG_MIXTAR_ROOT_DEVICE_PATH.

Default upstream-compatible:
  "/dev/root"

Mixtar:
  "/System/Devices/root"
```

Then block-root mounting uses the configured path.
```

Important:

```text
If Mixtar always mounts real root from its own initramfs/PID1, this path can be
avoided. But for direct root= boot without POSIX /dev, this must be patched.
```

### 6. Special root device names

File:

```text
init/do_mounts.c
```

Relevant lines:

```text
strcmp(root_device_name, "/dev/nfs")
strcmp(root_device_name, "/dev/cifs")
strcmp(root_device_name, "/dev/ram")
```

Mixtar conflict:

```text
/dev/nfs
/dev/cifs
/dev/ram
```

Patch policy:

```text
Do not patch first unless needed.
```

Reason:

```text
These are kernel command-line compatibility tokens for special root modes.
Mixtar should initially use normal block root or initramfs handoff.
```

Later Mixtar-native aliases could be added:

```text
root=mixtar:nfs
root=mixtar:cifs
root=mixtar:ram
```

or:

```text
/System/Devices/nfs
/System/Devices/cifs
/System/Devices/ram
```

### 7. devtmpfs automount target

File:

```text
drivers/base/devtmpfs.c
```

Relevant lines:

```text
__setup("devtmpfs.mount=", mount_param);
init_mount("devtmpfs", "dev", "devtmpfs", ...);
```

Current config:

```text
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
```

Mixtar conflict:

```text
With automount enabled, Linux mounts devtmpfs at /dev.
```

Minimal non-patch policy:

```text
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=n
cmdline: devtmpfs.mount=0
Mixtar Init mounts devtmpfs at /System/Devices
```

Patch policy:

```text
Add CONFIG_MIXTAR_DEVTMPFS_MOUNT_PATH.

Default upstream-compatible:
  "dev"

Mixtar:
  "System/Devices"
```

Then automatic devtmpfs mount can target:

```text
/System/Devices
```

instead of:

```text
/dev
```

Recommended first step:

```text
Do not patch devtmpfs first.
Set CONFIG_DEVTMPFS_MOUNT=n and let Mixtar Init mount it explicitly.
```

Reason:

```text
This is simpler, less invasive, and already supported by Linux.
```

## What Is Not Primarily Kernel-Hardcoded

These are mostly userland conventions, not Linux-kernel requirements:

```text
/etc/passwd
/etc/group
/etc/resolv.conf
/etc/hosts
/etc/shells
/usr/bin/env
/bin/sh shebangs
/var/log
/var/run
/tmp
/proc
/sys
```

Kernel provides mechanisms:

```text
procfs
sysfs
devtmpfs
```

but userspace chooses normal mountpoints:

```text
/proc
/sys
/dev
```

Mixtar policy:

```text
Native Mixtar:
  /System/Process
  /System/Hardware
  /System/Devices

POSIX compatibility:
  synthetic /proc
  synthetic /sys
  synthetic /dev
  only inside compatibility namespace
```

## Minimal Patchset Proposal

### Patch 1: Mixtar Kconfig options

Add options:

```text
CONFIG_MIXTAR_PATHS
CONFIG_MIXTAR_CONSOLE_PATH="/System/Devices/console"
CONFIG_MIXTAR_ROOT_DEVICE_PATH="/System/Devices/root"
CONFIG_MIXTAR_STRICT_INIT_FALLBACKS=y
CONFIG_MIXTAR_DEFAULT_ROOTFS_LAYOUT=y
```

### Patch 2: init/main.c

Change:

```text
filp_open("/dev/console", ...)
```

to:

```text
filp_open(CONFIG_MIXTAR_CONSOLE_PATH, ...)
```

when `CONFIG_MIXTAR_PATHS=y`.

Change fallback init behavior:

```text
/sbin/init
/etc/init
/bin/init
/bin/sh
```

to disabled fallback when strict Mixtar mode is enabled.

### Patch 3: init/noinitramfs.c

When `CONFIG_MIXTAR_DEFAULT_ROOTFS_LAYOUT=y`, create:

```text
/System
/System/Devices
/System/Devices/console
/Users
/Users/root
```

instead of:

```text
/dev
/dev/console
/root
```

### Patch 4: init/do_mounts.c

Change:

```text
/dev/root
```

to configurable:

```text
CONFIG_MIXTAR_ROOT_DEVICE_PATH
```

### Patch 5: devtmpfs policy

First implementation:

```text
CONFIG_DEVTMPFS_MOUNT=n
```

Mixtar Init mounts:

```text
devtmpfs -> /System/Devices
```

Later optional patch:

```text
CONFIG_MIXTAR_DEVTMPFS_MOUNT_PATH="System/Devices"
```

## Recommended Order

```text
1. Config-only:
   CONFIG_DEVTMPFS_MOUNT=n
   CONFIG_DEFAULT_INIT="/System/Init/MixtarRVS"
   cmdline rdinit=/System/Init/MixtarRVS

2. Patch console path:
   /dev/console -> /System/Devices/console

3. Patch fallback init:
   remove POSIX fallback paths in Mixtar strict mode

4. Patch noinitramfs rootfs:
   no /dev, no /root

5. Patch /dev/root:
   /System/Devices/root

6. Only later:
   devtmpfs auto-mount path, if still desired
```

## Resulting Mixtar Kernel Contract

Mixtar Linux RT should be able to boot with:

```text
rdinit=/System/Init/MixtarRVS
devtmpfs.mount=0
```

and expose native runtime paths:

```text
/System/Devices
/System/Process
/System/Hardware
```

without requiring native root identity paths:

```text
/dev
/etc
/bin
/sbin
/usr
/var
/root
```

## Decision

This is patchable.

The kernel-hardcoded boot paths are few and localized:

```text
init/main.c
init/do_mounts.c
init/noinitramfs.c
drivers/base/devtmpfs.c
```

Most remaining `/etc`, `/bin`, `/usr`, `/var`, `/tmp`, `/proc`, and `/sys`
pressure comes from userland, not the Linux kernel itself.
