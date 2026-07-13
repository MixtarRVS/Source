# Boot Proof

Updated: 12.06.2026

## Current Status

The rootfs/initramfs proof boots under QEMU/KVM and reaches Mixtar-controlled
first userspace.

Completed:

```text
static /init source exists
initramfs build script exists
QEMU boot script exists
QEMU boot smoke script exists
AILang wrapper exists
kernel config fragment exists
Linux 7.0.9 bzImage build exists
QEMU/KVM boot reaches /init
/init points to /System/Init/Mixtar
/System/Init/MixtarAil is staged as an opt-in AILang PID 1 candidate
/System/Init/MixtarAil boots through rdinit and passes smoke/text/emergency/graphical probes
/System/Init/Mixtar detects explicit boot targets
/System/Init/Mixtar logs target, mount, and layout markers
/System/Init/Mixtar handles SIGCHLD, SIGTERM, SIGINT, and SIGHUP
/System/Init/Mixtar reaps children while idle
/System layout is staged as the primary identity
POSIX compatibility aliases are staged
Administrator is staged as the canonical UID 0 account
Superuser is staged as an Administrator alias
Toolkit command check passes from /System/Tools
/System/Shells/msh is staged when a Linux build exists
QEMU serial console starts /System/Shells/msh
commands run inside the booted initramfs through msh
completed-exit AILang wrapper leak report is clean
graphical initramfs build script exists
graphical QEMU smoke script exists
QEMU/KVM graphical smoke reaches labwc
QEMU/KVM graphical smoke starts the Mixtar GTK4/layer-shell panel
QEMU/KVM graphical smoke reaches Xwayland through labwc
xdpyinfo reaches Xwayland inside the graphical rootfs
```

Observed proof:

```text
kernel:  Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu
initrd:  Server/Rootfs/Generated/mixtar-initramfs.cpio.gz
log:     Server/Rootfs/Generated/boot/boot-smoke.log
command: out/server/rootfs_proof.exe boot-smoke
result:  boot-smoke: ok
```

Graphical proof:

```text
kernel:  Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu
initrd:  Server/Rootfs/Generated/mixtar-graphical-initramfs.cpio.gz
log:     Server/Rootfs/Generated/boot/boot-graphical-smoke.log
command: out/server/rootfs_proof.exe boot-graphical-smoke
result:  boot-graphical-smoke: ok
```

AILang PID 1 candidate proof:

```text
kernel:  Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu
initrd:  Server/Rootfs/Generated/mixtar-initramfs.cpio.gz
log:     Server/Rootfs/Generated/boot/boot-ail-smoke.log
command: bash Server/Rootfs/scripts/boot_qemu_ail_smoke.sh
result:  boot-ail-smoke: ok
log:     Server/Rootfs/Generated/boot/boot-ail-text-probe.log
command: bash Server/Rootfs/scripts/boot_qemu_ail_text_probe.sh
result:  boot-ail-text-probe: ok
log:     Server/Rootfs/Generated/boot/boot-ail-emergency-probe.log
command: bash Server/Rootfs/scripts/boot_qemu_ail_emergency_probe.sh
result:  boot-ail-emergency-probe: ok
```

## Intended Boot Flow

```text
Linux 7.0.9 bzImage
  -> initramfs
    -> /init
      -> /System/Init/Mixtar
      -> parse mixtar.target
      -> mount /dev /proc /sys /Temporary
      -> announce MixtarRVS v0
      -> verify /System layout
      -> run /System/Tools/echo from the copied Toolkit slice
      -> report /System/Shells/msh as ready or deferred
      -> write /System/Logs/boot.log
      -> start /System/Shells/msh on the serial console when available
      -> keep first userspace alive
```

## Boot Evidence

The current smoke log contains:

```text
Linux version 7.0.9
Mixtar: pid1
Mixtar: target smoke
MixtarRVS v0
Mixtar: mounts ok
/System ready
Mixtar: layout ok
toolkit ready
stage: first userspace
boot-smoke: ok
smoke: powering off after boot proof
console: starting /System/Shells/msh
```

In smoke mode, `console: starting /System/Shells/msh` is not expected because
`/init` powers off immediately after the boot markers. In normal console mode,
`/init` starts `/System/Shells/msh`.

Smoke targets request poweroff after the proof markers are observed. Normal
text and graphical targets intentionally keep `/System/Init/Mixtar` alive for
inspection.

## AILang PID 1 Candidate Evidence

The AILang candidate smoke log contains:

```text
Command line: console=ttyS0 earlyprintk=serial panic=-1 rdinit=/System/Init/MixtarAil mixtar.target=smoke
Run /System/Init/MixtarAil as init process
Mixtar: pid1
Mixtar: implementation ailang
Mixtar: target smoke
MixtarRVS v0
Mixtar: mounts ok
Mixtar: layout ok
/System ready
toolkit ready
msh ready
boot-smoke: ok
smoke: powering off after boot proof
```

This proves AILang can currently produce a static executable that the Linux
kernel accepts as initramfs PID 1 and that can parse targets, create the
Mixtar layout, launch Toolkit commands, launch `msh`, handle emergency target
fallback, install basic signal handlers, and reap children.

## Graphical Evidence

The graphical smoke log contains:

```text
Mixtar: pid1
Mixtar: target graphical-smoke
desktop: starting labwc
desktop-xauth: ok
desktop-wayland: ok
desktop-panel: ok
name of display:    :0
vendor string:    The X.Org Foundation
X.Org version: 24.1.6
XWAYLAND
desktop-x11-smoke: ok
boot-smoke: ok
smoke: powering off after boot proof
```

This proves:

```text
virtio-gpu DRM/KMS is present in the QEMU kernel profile
labwc starts in the Mixtar graphical initramfs
the Mixtar GTK4/layer-shell panel starts and stays alive
Xwayland starts under labwc
real xkbcomp works through /bin/sh -> /System/Shells/msh
an X11 client can connect to the Xwayland display
persistent graphical target reaches desktop-session: ready
```

The AILang PID 1 graphical smoke log contains the same core desktop markers:

```text
Mixtar: implementation ailang
Mixtar: target graphical-smoke
desktop-xauth: ok
desktop: starting labwc
desktop-wayland: ok
desktop-panel: ok
desktop-x11-smoke: ok
boot-smoke: ok
smoke: powering off after boot proof
```

The persistent graphical session probes contain:

```text
Mixtar: target graphical
desktop-xauth: ok
desktop-wayland: ok
desktop-panel: ok
desktop-session: ready
```

Current graphical caveat:

```text
The smoke image starts Xwayland through a wrapper that injects
`-auth $XAUTHORITY` when needed.
PID 1 creates `/System/Runtime/run/Administrator/Xauthority` before labwc starts.
The panel starts without a D-Bus session bus; GTK warns, but the process stays alive.
```

That proves the X11 compatibility smoke path no longer depends on open
Xwayland access. The persistent graphical target now stays alive after the
desktop is ready. The remaining graphical hardening task is selecting D-Bus,
launching a terminal/session command, and staging MDDM behind a login/auth gate.

## Policy

This proof intentionally avoids:

```text
systemd
GNU coreutils identity
BusyBox dependency
shell dependency
kernel patches
```

Selected Tier A Toolkit commands are copied into `/System/Tools` when available.
`/bin` is a compatibility symlink to `/System/Tools`.
When `/System/Shells/msh` is staged, `/System/Tools/sh` points to it so legacy
software that invokes `/bin/sh -c` can still run without adding another shell.

The first `/init` is static so the boot proof does not depend on a shell.

## Console Evidence

The serial console path was exercised by sending commands to QEMU after
`/System/Shells/msh` started:

```text
pwd
echo hello-from-mixtar
ls /System/Tools
cat /System/Config/mixtar-release
exit
```

Observed output included:

```text
/
hello-from-mixtar
cat echo false ls printf pwd test true uname
NAME=MixtarRVS Server
STAGE=v0-rootfs-proof
USERLAND=OpenBSD-first Toolkit Tier A
ADMIN_USER=Administrator
SUPERUSER_ALIAS=Superuser
console: msh exited 0
```

## Next Step

The next step is not more kernel acquisition and not replacing PID 1. It is
turning the session layer into a usable desktop profile:

```text
keep explicit Xauthority handling in smoke and persistent graphical targets
decide the D-Bus profile
launch a terminal/session command
define minimal service metadata above /System/Init/Mixtar
soak-test /System/Init/MixtarAil before making it the default /init
stage MDDM behind a greeter/auth gate, not as a direct shell launcher
```

The v0 layout, Toolkit slice, msh staging, boot log, and bounded smoke checks
are already present in the current proof.
