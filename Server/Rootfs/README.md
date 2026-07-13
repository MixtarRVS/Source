# MixtarRVS Server Rootfs

This folder owns the first Linux-kernel boot proof.

The goal is not a complete OS image yet. The goal is:

```text
kernel boots
initramfs mounts
/init runs
Mixtar-controlled first userspace stays alive
selected Tier A Toolkit commands are present
```

The graphical desktop target is intentionally separate from this text-mode
initramfs proof. The current desktop runtime profile is:

```text
Server/Desktop/DESKTOP_RUNTIME_PROFILE.md
```

Policy summary:

```text
Wayland is native.
X11 is compatibility through Xwayland.
labwc + Xwayland is the first graphical rootfs target.
Plain WSLg is not enough to validate layer-shell panels.
```

The next target is the v0 contract:

```text
Server/MIXTAR_V0_CONTRACT.md
```

That means this proof should become a small bootable Mixtar base with
`/System` as the real identity, compatibility aliases for old Unix paths,
selected Toolkit commands under `/System/Tools`, explicit `msh` status, and a
boot smoke log.

## Layout Policy

The native Server rootfs uses Mixtar paths as the system identity and keeps
POSIX/Linux paths as compatibility aliases.

Canonical policy:

```text
Server/Rootfs/LAYOUT_POLICY.md
```

Important rule:

```text
Mixtar-native paths:
  /System/Tools
  /System/SystemTools
  /System/Shells
  /System/Kernel
  /System/Runtime
  /Users
  /Users/Administrator

Compatibility paths:
  /bin -> /System/Tools
  /sbin -> /System/SystemTools
  /usr/bin -> /System/Tools
  /usr/sbin -> /System/SystemTools
  /home -> /Users
  /root -> /Users/Administrator
  /Users/Superuser -> /Users/Administrator
```

`Administrator` is the canonical Mixtar UID 0 account name. `Superuser` is an
alias for `Administrator`; `root` exists only as a compatibility path/name for
Linux/POSIX software that expects it.

Do not remove the compatibility paths. The Linux kernel does not require them,
but scripts, build systems, and portable Unix software do.

## Build Initramfs

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Rootfs\rootfs_proof.ail --check
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Rootfs\rootfs_proof.ail --backend=c -O2 -o out\server\rootfs_proof.exe
out\server\rootfs_proof.exe build
```

Output:

```text
Server/Rootfs/Generated/mixtar-initramfs.cpio.gz
```

## Boot

Boot needs a built kernel image:

```text
Server/Kernel/Generated/boot/bzImage-7.0.9-mixtar-qemu
```

Then:

```text
out\server\rootfs_proof.exe boot
```

To see and test the booted proof through QEMU serial console:

```text
out\server\rootfs_proof.exe boot-console
```

After the v0 markers, `/init` starts:

```text
/System/Shells/msh
```

You can test the staged tools:

```text
pwd
echo hello
ls /System/Tools
uname
cat /System/Config/mixtar-release
```

Exit QEMU with `Ctrl-A` then `X`.

For validation, prefer the bounded smoke proof:

```text
out\server\rootfs_proof.exe boot-smoke
```

`boot-smoke` passes `mixtar.target=smoke` to `/init`. The legacy
`mixtar.smoke=1` flag is still accepted. After the required markers are
printed, `/init` powers off QEMU instead of waiting for the timeout. Normal
`boot` and `boot-console` still stay alive for inspection.

Expected result:

```text
boot-smoke: ok
```

To test the AILang PID 1 candidate without changing the default `/init`
symlink:

```text
out\server\rootfs_proof.exe boot-ail-smoke
out\server\rootfs_proof.exe boot-ail-text
out\server\rootfs_proof.exe boot-ail-emergency
out\server\rootfs_proof.exe boot-ail-graphical-smoke
out\server\rootfs_proof.exe boot-ail-graphical-session
```

Equivalent WSL script path:

```text
bash Server/Rootfs/scripts/boot_qemu_ail_smoke.sh
bash Server/Rootfs/scripts/boot_qemu_ail_text_probe.sh
bash Server/Rootfs/scripts/boot_qemu_ail_emergency_probe.sh
bash Server/Rootfs/scripts/boot_qemu_ail_graphical_smoke.sh
bash Server/Rootfs/scripts/boot_qemu_ail_graphical_session_probe.sh
bash Server/Rootfs/scripts/boot_qemu_graphical_rich_smoke.sh
bash Server/Rootfs/scripts/boot_qemu_ail_graphical_rich_smoke.sh
bash Server/Rootfs/scripts/boot_qemu_graphical_mddm_smoke.sh
```

This boots the same initramfs with:

```text
rdinit=/System/Init/MixtarAil
```

Expected result:

```text
boot-ail-smoke: ok
boot-ail-text-probe: ok
boot-ail-emergency-probe: ok
boot-ail-graphical-smoke: ok
boot-ail-graphical-session-probe: ok
```

For v0, the smoke log must also prove:

```text
MixtarRVS v0
/System ready
toolkit-echo: ok
toolkit ready
msh ready
desktop-wayland: ok
desktop-panel: ok
desktop-x11-smoke: ok
```

If `msh` is not staged yet, the log must say:

```text
msh deferred
```

If no kernel image exists yet, the boot script must fail clearly instead of
pretending the proof is complete.

## Graphical Smoke

The graphical proof is separate from the text-mode initramfs proof.

Build the graphical initramfs:

```text
out\server\rootfs_proof.exe build-graphical
```

Boot it interactively:

```text
out\server\rootfs_proof.exe boot-graphical
```

Run the bounded graphical smoke:

```text
out\server\rootfs_proof.exe boot-graphical-smoke
```

Run the bounded persistent graphical session probe:

```text
out\server\rootfs_proof.exe boot-graphical-session
```

Equivalent WSL path:

```text
bash Server/Rootfs/scripts/boot_qemu_graphical_session_probe.sh
```

Equivalent WSL script path:

```text
bash Server/Rootfs/scripts/build_graphical_initramfs.sh
MIXTAR_QEMU_DISPLAY=gtk,gl=off bash Server/Rootfs/scripts/boot_qemu_graphical_smoke.sh
MIXTAR_QEMU_DISPLAY=none bash Server/Rootfs/scripts/boot_qemu_graphical_session_probe.sh
```

The graphical smoke script passes `mixtar.target=graphical-smoke`. Normal
interactive graphical boot uses `mixtar.target=graphical`. The session probe
boots the normal graphical target and expects QEMU to be stopped by timeout
after the session-ready marker appears.

Current expected result:

```text
boot-graphical-smoke: ok
boot-graphical-session-probe: ok
desktop-xauth: ok
desktop-wayland: ok
desktop-panel: ok
desktop-terminal: ok
desktop-x11-smoke: ok
desktop-session: ready
desktop-dbus: ok      # rich profile only, with mixtar.dbus=1
```

The graphical smoke currently stages `labwc`, the Mixtar GTK4/layer-shell
panel, `Xwayland`, `xdpyinfo`, `xkbcomp`, `xauth`, XKB resources, a small font
set, GLib schemas, and the required shared libraries into
`/System/Runtime/Desktop`, `/System/Tools`, `/System/Libraries`, and
`/System/Resources`.

Current auth behavior:

```text
PID 1 creates /System/Runtime/run/Administrator/Xauthority with xauth.
The Xwayland launcher injects -auth $XAUTHORITY when labwc does not pass one.
```

Do not reintroduce `-ac`. Production graphical boot must keep this auth gate
and extend it to the persistent session target.

Generated desktop profile:

```text
PROFILE=graphical-base
SESSION=labwc-panel
COMPOSITOR=labwc
X11_COMPAT=Xwayland
X11_AUTH=Xauthority
DBUS=none
TERMINAL=xterm
MDDM=auth-gated-rich-profile
SMOKE=xdpyinfo
```

The base panel currently starts without a D-Bus session bus. GTK may print a
warning, but the panel stays alive and the smoke gate requires
`desktop-panel: ok`.

Rich profile:

```text
MIXTAR_DESKTOP_PROFILE=rich bash Server/Rootfs/scripts/build_graphical_initramfs.sh
MIXTAR_QEMU_DISPLAY=none bash Server/Rootfs/scripts/boot_qemu_graphical_rich_smoke.sh
MIXTAR_QEMU_DISPLAY=none bash Server/Rootfs/scripts/boot_qemu_ail_graphical_rich_smoke.sh
MIXTAR_QEMU_DISPLAY=none bash Server/Rootfs/scripts/boot_qemu_graphical_mddm_smoke.sh
```

Generated rich profile:

```text
PROFILE=graphical-rich
DBUS=session-daemon
TERMINAL=xterm
MDDM=login-auth-smoke
```

The rich smoke passes `mixtar.dbus=1`, stages `dbus-daemon`, and requires
`desktop-dbus: ok` before declaring the graphical target valid.

MDDM smoke is heavier and explicitly opt-in. It passes:

```text
mixtar.target=graphical-smoke mixtar.dbus=1 mixtar.mddm=1
```

Required MDDM markers:

```text
mddm-greeter: ok
mddm-auth-backend: test
mddm-auth: ok
mddm-session: started
mddm-session: stopped
mddm-smoke: ok
```

This is not production authentication yet. It proves that the greeter and login
state machine can be staged into the rich rootfs and driven through a bounded
QEMU boot using deterministic test auth.

The rich image also stages the production auth policy file:

```text
/System/Config/pam.d/mixtar-login
```

That file is not enough by itself. A production login proof still needs PAM
runtime libraries/modules in the image and a non-test MDDM build.
