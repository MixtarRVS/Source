# AILang PID 1 Candidate

Updated: 2026-06-12

## Status

Mixtar now has a functional AILang PID 1 candidate staged as:

```text
/System/Init/MixtarAil
```

The production/default init remains:

```text
/init -> /System/Init/Mixtar
```

This split is intentional. The C PID 1 remains the stable boot anchor while
`MixtarAil` proves that AILang can own the same first-userspace contract.

## Verified

The AILang candidate currently proves:

```text
AILang source compiles to generated C
generated C compiles as a static Linux x86_64 binary
the binary is staged inside the initramfs
the kernel can execute it directly as initramfs PID 1 through rdinit
target parsing from /proc/cmdline
boot log writing to /System/Logs/boot.log
Mixtar /System layout creation
legacy compatibility aliases such as /bin, /usr/bin, /home, /tmp, /run
Administrator as the canonical UID 0 account home
Superuser as an Administrator alias
core filesystem mounts: devtmpfs, proc, sysfs, tmpfs
console setup through /dev/console
signal installation for SIGCHLD, SIGTERM, SIGINT, and SIGHUP
child reaping through wait4
Toolkit command execution proof through fork/execve/wait4
console /System/Shells/msh launch for text and emergency targets
emergency shell fallback marker
labwc/Xwayland graphical smoke launch
smoke-target poweroff through sync and reboot
the existing C PID 1 path still boots after the candidate is added
```

## Gates

Run:

```text
bash Server/Rootfs/scripts/build_initramfs.sh
bash Server/Rootfs/scripts/boot_qemu_smoke.sh
bash Server/Rootfs/scripts/boot_qemu_ail_smoke.sh
bash Server/Rootfs/scripts/boot_qemu_ail_text_probe.sh
bash Server/Rootfs/scripts/boot_qemu_ail_emergency_probe.sh
```

Graphical gate:

```text
bash Server/Rootfs/scripts/build_graphical_initramfs.sh
bash Server/Rootfs/scripts/boot_qemu_graphical_smoke.sh
bash Server/Rootfs/scripts/boot_qemu_ail_graphical_smoke.sh
```

Wrapper commands after rebuilding `rootfs_proof.exe`:

```text
out\server\rootfs_proof.exe boot-smoke
out\server\rootfs_proof.exe boot-ail-smoke
out\server\rootfs_proof.exe boot-ail-text
out\server\rootfs_proof.exe boot-ail-emergency
out\server\rootfs_proof.exe boot-ail-graphical-smoke
```

## Observed Evidence

Text/smoke:

```text
Command line: ... rdinit=/System/Init/MixtarAil mixtar.target=smoke
Run /System/Init/MixtarAil as init process
Mixtar: pid1
Mixtar: implementation ailang
Mixtar: target smoke
MixtarRVS v0
Mixtar: mounts ok
Mixtar: layout ok
/System ready
Mixtar toolkit path reachable
toolkit-echo: ok
toolkit ready
msh ready
boot-smoke: ok
smoke: powering off after boot proof
```

Graphical:

```text
Mixtar: implementation ailang
Mixtar: target graphical-smoke
desktop: starting labwc
desktop-wayland: ok
desktop-panel: ok
desktop-x11-smoke: ok
boot-smoke: ok
smoke: powering off after boot proof
```

## Current Limits

`MixtarAil` is close to the C PID 1 smoke contract, but it is not promoted to
the default `/init` yet.

Remaining before replacement:

```text
longer soak testing under repeated QEMU boots
explicit boot-log verification from inside the initramfs
signal/reaping stress probe, not only smoke-path behavior
interactive console lifecycle testing beyond launch marker
graphical target testing beyond smoke startup and cleanup
decide whether AILang PID 1 should stay direct-syscall only or use runtime helpers
```

## Replacement Rule

Do not repoint `/init` to `MixtarAil` until it passes the same gates as the C
PID 1 repeatedly and the logs show no regressions:

```text
QEMU text smoke
QEMU graphical smoke
AILang PID 1 smoke
AILang PID 1 text target probe
AILang PID 1 emergency target probe
AILang PID 1 graphical smoke
signal/reaping probe
no dependency on Python, llvmlite, dynamic host tools, or a shell
```
