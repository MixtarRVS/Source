# Init Stack Decision

Updated: 2026-06-12

## Decision

MixtarRVS should keep a Mixtar-owned PID 1.

OpenRC should not be the first PID 1. Treat it as an optional compatibility or
service-profile candidate after the base system has a stable `Mixtar` init
contract.

## Why

The current boot proof needs a small coordinator that owns the Mixtar layout,
mounts the minimal filesystems, launches the desktop proof, reaps children, and
shuts down cleanly. OpenRC solves a different problem: dependency-based
runlevels and service scripts for a traditional Unix-like installation.

Using OpenRC as PID 1 now would force MixtarRVS to adapt to OpenRC's service
model before Mixtar's own boot contract is stable.

## Naming

The installed PID 1 name should be:

```text
/System/Init/Mixtar
/init -> /System/Init/Mixtar
```

Do not call the installed component `mixtar-init`. The source file and build
helpers may stay descriptive, but the visible system component should be
`Mixtar`. This is the first customization rule: core Mixtar components should
use clean product names when they are user-visible, and technical suffixes only
when they clarify implementation internals.

## Measured Local Data

Current Mixtar PID 1:

| Item | Value |
|---|---:|
| Binary | `/System/Init/Mixtar` |
| AILang candidate | `/System/Init/MixtarAil` |
| Current size | `787592` bytes |
| AILang candidate size | `766880` bytes |
| Stripped-copy size | `700856` bytes |
| Link mode | static |
| Dynamic runtime dependencies | none |
| Source size | `665` lines |
| AILang candidate source size | `735` lines |
| Text initramfs | `2.46 MB` compressed |
| Graphical initramfs | `32.78 MB` compressed |

Current path note: the proof image now stages the binary at
`/System/Init/Mixtar`. The older `/System/SystemTools/init` proof location is
retired.

OpenRC package data from the local Debian/WSL apt metadata:

| Package | Installed size |
|---|---:|
| `openrc` | `1850 KiB` |
| `insserv` | `136 KiB` |
| `libaudit1` | `179 KiB` |
| `libcap2` | `92 KiB` |
| `libeinfo1` | `45 KiB` |
| `libpam0g` | `194 KiB` |
| `librc1t64` | `94 KiB` |
| `libselinux1` | `229 KiB` |

The listed OpenRC package and direct dependencies are about `2.75 MB` before
counting libc, secondary dependencies, scripts, service directories, and any
policy/profile files MixtarRVS would still need.

The current WSL host cannot directly install-test OpenRC without replacing or
conflicting with the host init package path:

```text
systemd-sysv Conflicts: insserv
openrc Depends: insserv
```

That is a host packaging conflict, not a proof that OpenRC cannot work in a
dedicated rootfs.

## Adaptability Comparison

| Criterion | Mixtar PID 1 | OpenRC |
|---|---|---|
| Mixtar `/System` layout ownership | direct | adapter scripts required |
| Static initramfs boot proof | already works | extra staging required |
| Child reaping | minimal PID 1 reaper implemented | mature |
| Shutdown/reboot | smoke poweroff and signal shutdown implemented | mature |
| Service dependency model | can stay minimal | mature runlevel model |
| Traditional Unix services | limited at first | strong |
| Resource footprint | smallest current path | larger but still modest |
| Project control | full | constrained by OpenRC model |

## Recommended Shape

Use this split:

```text
Linux kernel
  -> /System/Init/Mixtar as PID 1
    -> mount core filesystems
    -> create Mixtar layout and compatibility aliases
    -> start required early services
    -> reap children
    -> launch graphical/session target
    -> emergency fallback to /System/Shells/msh
```

Later, if needed:

```text
/System/Services/openrc-profile
```

That profile can run OpenRC-style service scripts or import selected OpenRC
semantics without making OpenRC the identity of the system.

## Implemented First Gate

The first implementation gate is now Mixtar-owned PID 1 identity and bounded
boot validation:

```text
/System/Init/Mixtar
/init -> /System/Init/Mixtar
```

Implemented first features:

```text
mount proc/sysfs/devtmpfs/tmpfs/devshm/run
create /System, /Tools, /Applications, /Users
create /bin, /usr/bin, /home compatibility aliases
create /Users/Administrator as the canonical UID 0 home
create Superuser as an Administrator alias
start labwc/Xwayland/panel smoke target
start persistent labwc/Xwayland/panel graphical target
start xterm -> /System/Shells/msh terminal/session smoke
start optional rich-profile D-Bus session daemon
reap children
handle SIGTERM/SIGINT/SIGCHLD
sync and poweroff after smoke targets
support emergency target fallback to msh
log target, mounts, layout, and smoke markers
```

Verified gates:

```text
text initramfs build
graphical initramfs build
QEMU text smoke
QEMU graphical smoke
QEMU persistent graphical session probe
QEMU AILang PID 1 smoke through rdinit=/System/Init/MixtarAil
QEMU AILang PID 1 text target probe
QEMU AILang PID 1 emergency target probe
QEMU AILang PID 1 graphical smoke through rdinit=/System/Init/MixtarAil
QEMU AILang PID 1 persistent graphical session probe
QEMU C PID 1 rich graphical smoke with D-Bus and terminal/session markers
QEMU AILang PID 1 rich graphical smoke with D-Bus and terminal/session markers
QEMU C PID 1 rich MDDM greeter/auth smoke
msh smoke gate against WSL sh, bash --posix, and zsh sh-emulation
MDDM hardening test
MDDM login controller validation/cooldown/success/lockout test
```

## Remaining Gate

The next gate is not replacing Mixtar with OpenRC. It is adding a small service
and session layer above Mixtar:

```text
keep explicit Xauthority handling in persistent graphical target
keep D-Bus out of the base graphical target; stage it only for rich/MDDM
keep xterm as the current proven terminal command until MSH gets a native terminal
define service start/stop metadata without importing a full runlevel system
soak-test the AILang PID 1 before making it the default /init
replace MDDM test auth with PAM or a Mixtar auth helper before production use
```

Only after that should OpenRC be tested inside a separate Mixtar rootfs profile.
