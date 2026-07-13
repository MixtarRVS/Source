# MixtarRVS Base Closure

Updated: 29.06.2026

This document tracks the transition from:

```text
Linux kernel + Alpine/OpenRC bootstrap + MixtarRVS Toolkit
```

to:

```text
Linux kernel + MixtarRVS base closure
```

The goal is not to delete Alpine first. The goal is to make Alpine unnecessary
as the visible system identity, while keeping it as a bootable fallback until a
MixtarRVS base profile can boot, log in, bring up networking, and expose the
MixtarRVS Toolkit by default.

## Current Evidence

Audit target:

```text
vxz@192.168.99.110
```

Current runtime identity:

```text
kernel:  Linux MixtarRVS 7.1.2-mixtar-rt
os-release: Alpine Linux 3.24.1
toolkit: 158 files in /System/Tools/MixtarRVS/bin
```

Current default command path:

```text
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

That means normal interactive commands still resolve through Alpine paths:

```text
sh       -> /bin/sh
ls       -> /bin/ls
uname    -> /bin/uname
vi       -> /usr/bin/vi
rc-status -> /bin/rc-status
apk      -> /sbin/apk
init     -> /sbin/init
sshd     -> /usr/sbin/sshd
dhcpcd   -> /sbin/dhcpcd
login    -> /bin/login
passwd   -> /usr/bin/passwd
mount    -> /bin/mount
```

Current MixtarRVS Toolkit path:

```text
/System/Tools/MixtarRVS/bin
/System/Tools/Current -> MixtarRVS
```

Important current mismatch:

```text
running kernel: 7.1.2-mixtar-rt
visible /boot artifacts:
  /boot/vmlinuz-7.0.0-rc3-mixtarrvs
  /boot/initrd.img-7.0.0-rc3-mixtarrvs
```

Base Closure must reconcile kernel profile metadata before it claims boot
ownership.

## Alpine Dependencies Still In Use

These are current hard dependencies, not final Mixtar identity.

Boot and init:

```text
/sbin/init
/sbin/openrc
/sbin/openrc-run
/etc/inittab
/etc/runlevels/*
/etc/init.d/*
```

Mounted kernel filesystems:

```text
/dev        devtmpfs
/proc       procfs
/sys        sysfs
/run        tmpfs
/tmp        tmpfs
/dev/pts    devpts
/dev/shm    tmpfs
```

Network and remote access:

```text
dbus-daemon
iwd
dhcpcd
sshd
```

Package/build substrate:

```text
apk
musl runtime from /lib
headers/libraries needed to rebuild tools
```

Login/session substrate:

```text
getty
login
passwd/shadow plumbing
zsh user shell
```

## MixtarRVS-Owned Pieces Already Present

Toolkit:

```text
/System/Tools/MixtarRVS/bin
  158 source-ported tools
  hosted placeholders: 0
  OpenBSD-first source, FreeBSD fallback where selected
  musl target
  Mixtar Bridge for BSD-to-Linux gaps
```

Kernel:

```text
running kernel: 7.1.2-mixtar-rt
PREEMPT_RT enabled by kernel profile
```

Layout:

```text
/System
/Applications
/Programs
/Users
/Volumes
/Temporary
```

## Base Closure Requirements

A MixtarRVS base closure is not complete until all of these are true.

1. Boot ownership exists:

```text
/System/Kernel/Profiles/<profile>/vmlinuz
/System/Kernel/Profiles/<profile>/initramfs.img
/System/Kernel/Profiles/<profile>/modules
/System/Kernel/Profiles/<profile>/profile.json
/System/Kernel/Current -> Profiles/<profile>
```

2. Runtime libraries are owned by the profile:

```text
/System/Libraries/ld-musl-x86_64.so.1
/System/Libraries/*.so needed by enabled services
```

3. PID 1 path is explicit:

```text
phase 0001: Alpine /sbin/init remains fallback
phase 0002: Mixtar init shim can mount kernel filesystems and exec fallback
phase 0003: Mixtar init/supervisor owns default boot
```

4. Kernel filesystems are mounted by the profile:

```text
/dev
/proc
/sys
/run
/tmp
/dev/pts
/dev/shm
```

5. Command resolution prefers MixtarRVS:

```text
/System/Tools/Current/bin
/System/Tools/MixtarRVS/bin
```

must precede:

```text
/bin
/usr/bin
```

for Mixtar sessions.

6. Network closure is explicit:

```text
wireless manager
DHCP client
resolver config
sshd or Mixtar remote agent
```

7. Fallback remains bootable:

```text
Alpine/OpenRC fallback must not be removed while Base Closure is experimental.
```

## Stage 0001: Non-Activating Base Closure Profile

Stage 0001 is a manifest and filesystem staging step only.

It must not:

```text
replace /sbin/init
rewrite bootloader defaults
delete Alpine packages
move /bin, /sbin, /usr, /etc, /lib, or /var
disable sshd
disable network services
```

It may:

```text
create /System/Base/Closure/0001-audit
record the current dependency closure
record the selected MixtarRVS Toolkit path
record the fallback Alpine/OpenRC paths
prepare a profile manifest for later activation
```

Acceptance for Stage 0001:

```text
1. /System/Tools/MixtarRVS/bin contains 158 tools.
2. hosted placeholder count is 0 in repo.
3. upstream OpenBSD/FreeBSD mirrors verify unchanged.
4. /System/Base/Closure/0001-audit/manifest.json exists on the laptop.
5. fallback boot/runtime paths remain unchanged.
```

## Next Engineering Step

Build the Stage 0001 profile on the laptop as an inert manifest:

```text
/System/Base/Closure/0001-audit/manifest.json
/System/Base/Closure/0001-audit/runtime-audit.txt
```

Then add a separate Stage 0002 target that creates a Mixtar session profile
where `PATH` resolves MixtarRVS tools first, without changing PID 1 or boot
defaults.

## Stage 0002: Mixtar Session Path

Stage 0002 makes MixtarRVS userland the default inside an explicitly entered
session, without changing boot, PID 1, OpenRC, SSH, or the global Alpine login
environment.

It must not:

```text
replace /sbin/init
rewrite /etc/inittab
rewrite /etc/profile
rewrite bootloader defaults
remove apk/OpenRC/Alpine fallback commands
```

It may:

```text
create /System/Base/Closure/0002-mixtar-session-path
install enter-mixtar-session.sh there
export a Mixtar-first PATH for the current command/session
keep Alpine paths after Mixtar paths as fallback
```

Mixtar-first PATH:

```text
/System/Tools/Current/bin
/System/Tools/MixtarRVS/bin
/usr/local/sbin
/usr/local/bin
/usr/sbin
/usr/bin
/sbin
/bin
```

Acceptance for Stage 0002:

```text
1. Stage 0001 audit artifacts remain present.
2. /System/Base/Closure/0002-mixtar-session-path/manifest.json exists.
3. /System/Base/Closure/0002-mixtar-session-path/enter-mixtar-session.sh exists.
4. In the entered session, ls/uname/vi/sh resolve to /System/Tools.
5. Alpine fallback tools such as rc-status and apk remain reachable.
6. PID 1, OpenRC, SSH, and boot defaults remain unchanged.
```

Observed Stage 0002 smoke result:

```text
PATH_AFTER=/System/Tools/Current/bin:/System/Tools/MixtarRVS/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LS=/System/Tools/Current/bin/ls
UNAME=/System/Tools/Current/bin/uname
VI=/System/Tools/Current/bin/vi
SH=/System/Tools/Current/bin/sh
RC_STATUS=/bin/rc-status
APK=/sbin/apk
UNAME_S=Linux
VI_RC=0
VI_OK=1
RC_STATUS_OK=1
APK_OK=1
```

Known Stage 0002 limitation:

```text
MixtarRVS sh resolves first, but it is not yet certified as the default script
driver for Base Closure orchestration. Stage 0002 uses the existing login shell
to source the profile, then external commands resolve through MixtarRVS first.
```

This makes shell/runtime certification a hard blocker before MixtarRVS can own
PID 1 scripts, initramfs scripts, or service orchestration.

## Stage 0003: Shell Runtime And Libraries Profile

Stage 0003 records and stages the shared-library runtime needed by the current
MixtarRVS Toolkit and the fallback network/remote-access services.

It must not:

```text
replace /lib/ld-musl-x86_64.so.1
replace /usr/lib
rewrite /etc/ld-musl-*.path
rewrite bootloader defaults
replace PID 1
disable OpenRC, SSH, iwd, dhcpcd, dbus, or apk
```

It may:

```text
create /System/Libraries/MixtarRVS/Runtime/0003/lib
copy required runtime libraries there
create /System/Base/Closure/0003-shell-runtime-and-libraries-profile
record runtime-library audits
run shell smoke tests
test tools with LD_LIBRARY_PATH pointed at the staged library directory
```

Observed MixtarRVS Toolkit runtime libraries:

```text
/lib/ld-musl-x86_64.so.1
/usr/lib/libfts.so.0
/usr/lib/libncursesw.so.6
/usr/lib/libz.so.1
```

Observed fallback service runtime libraries:

```text
/usr/sbin/sshd      -> /usr/lib/libcrypto.so.3
/usr/bin/dbus-daemon -> /usr/lib/libdbus-1.so.3 /usr/lib/libexpat.so.1
/usr/libexec/iwd    -> musl only
/sbin/dhcpcd        -> musl only
```

Stage 0003 library staging target:

```text
/System/Libraries/MixtarRVS/Runtime/0003/lib/
  ld-musl-x86_64.so.1
  libfts.so.0
  libncursesw.so.6
  libz.so.1
  libcrypto.so.3
  libdbus-1.so.3
  libexpat.so.1
```

Observed shell smoke:

```text
SH=/System/Tools/MixtarRVS/bin/sh
SH_C_RC=0
SH_C_OUT=SH_C_OK
SH_SCRIPT_RC=7
SH_SCRIPT_OUT=script:alpha
```

Acceptance for Stage 0003:

```text
1. Stage 0001 and Stage 0002 artifacts remain present.
2. Stage 0003 manifest and scripts exist under /System/Base/Closure.
3. Runtime libraries are copied to /System/Libraries/MixtarRVS/Runtime/0003/lib.
4. MixtarRVS sh passes -c and script-file smoke.
5. A representative MixtarRVS dynamic tool runs with LD_LIBRARY_PATH pointing at
   the staged library directory.
6. PID 1, OpenRC, SSH, iwd, dhcpcd, dbus, apk, /lib, and /usr/lib remain
   fallback-owned.
```

Observed Stage 0003 smoke result:

```text
STAGE0001=1
STAGE0002=1
STAGE0003=1
LIB_COUNT=7
SH_C=ok
SH_SCRIPT=rc:7 script:alpha
VI_LD_RC=0
VI_LD_OK=1
GREP_LD_RC=0
GREP_LD_OK=1
PID1=/sbin/init
OPENRC_OK=1
APK_OK=1
SSHD_OK=1
```

Known Stage 0003 limitation:

```text
ELF interpreters in current MixtarRVS binaries still point at
/lib/ld-musl-x86_64.so.1. The staged loader is a closure artifact, not active
boot/runtime ownership yet.
```

The next stage must decide how MixtarRVS will own the loader path during
initramfs/rootfs construction without breaking fallback boot.

## Stage 0004: Initramfs Loader Path And Kernel Profile

Stage 0004 records the active MixtarRVS kernel profile contract and separates it
from legacy `/boot` evidence.

Observed active kernel:

```text
UNAME_R=7.1.2-mixtar-rt
PROC_VERSION=Linux version 7.1.2-mixtar-rt (V@RYZEN) (gcc (Debian 14.2.0-19) 14.2.0, GNU ld (GNU Binutils for Debian) 2.44) #2 SMP PREEMPT_RT Mon Jun 29 08:00:23 CEST 2026
CMDLINE=initrd=\EFI\mixtarrvs-rt\initrd.img root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt
```

Observed Mixtar kernel profile:

```text
/System/Kernel/Current -> Profiles/rt-7.1.2-mixtar-rt
/System/Kernel/Profiles/rt-7.1.2-mixtar-rt/vmlinuz
/System/Kernel/Profiles/rt-7.1.2-mixtar-rt/initramfs.img
/System/Kernel/Profiles/rt-7.1.2-mixtar-rt/modules
/System/Kernel/Profiles/rt-7.1.2-mixtar-rt/config
/System/Kernel/Profiles/rt-7.1.2-mixtar-rt/System.map
/System/Kernel/Profiles/rt-7.1.2-mixtar-rt/profile.json
```

Legacy `/boot` still shows:

```text
/boot/vmlinuz-7.0.0-rc3-mixtarrvs
/boot/initrd.img-7.0.0-rc3-mixtarrvs
```

That means `/boot` is not the authoritative MixtarRVS kernel profile source.
Stage 0004 treats `/System/Kernel/Current` plus `/proc/cmdline` as the active
contract.

It must not:

```text
mount EFI partitions
rewrite EFI loader entries
rewrite bootloader defaults
replace /sbin/init
move legacy /boot artifacts
delete rollback profiles
```

It may:

```text
create /System/Base/Closure/0004-initramfs-loader-path-and-kernel-profile
copy the current profile.json into the stage record
record the active kernel profile audit
record an activation guard explaining that EFI mutation is not done yet
```

Acceptance for Stage 0004:

```text
1. Stage 0001, 0002, and 0003 artifacts remain present.
2. /System/Kernel/Current points at Profiles/rt-7.1.2-mixtar-rt.
3. uname -r is 7.1.2-mixtar-rt.
4. /proc/cmdline contains mixtar.profile=rt-7.1.2-mixtar-rt.
5. The current profile has vmlinuz, initramfs.img, modules, config, System.map,
   and profile.json.
6. Stage 0004 records runtime-kernel-audit.txt, profile-current.json, and
   activation-guard.txt.
7. PID 1 and bootloader defaults remain unchanged.
```

Known Stage 0004 limitation:

```text
EFI currently reports initrd=\EFI\mixtarrvs-rt\initrd.img, but the EFI
filesystem is not mounted in the audited runtime. Stage 0004 therefore records
the loader path contract but does not claim bootloader ownership.
```

The next stage must build a Mixtar-owned initramfs contract that can mount
kernel filesystems, locate `/System`, expose `/System/Libraries`, and then exec
the fallback init or a Mixtar init shim.

### Stage 0004 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
profile-status: verified
/System/Kernel/Current -> Profiles/rt-7.1.2-mixtar-rt
uname -r: 7.1.2-mixtar-rt
PID1: init
OpenRC default runlevel: ok
cmdline token: mixtar.profile=rt-7.1.2-mixtar-rt
staged files: activation-guard.txt, manifest.json, profile-current.json, profile-status.txt, runtime-kernel-audit.txt, stage-kernel-profile.sh
```

Stage 0004 did not mount EFI, rewrite loader entries, replace `/sbin/init`, move legacy `/boot`, or delete rollback profiles.

## Stage 0005: initramfs contract and fallback init shim

Stage 0005 records the future Mixtar-owned initramfs handoff contract and stages a safe fallback init shim.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0005-initramfs-contract.json
Server/Rootfs/scripts/stage-initramfs-contract.sh
Server/Rootfs/scripts/mixtar-fallback-init.sh
```

Installed on ThinkPad:

```text
/System/Base/Closure/0005-initramfs-contract-and-fallback-init-shim/
/System/SystemTools/mixtar-fallback-init
```

The staged initramfs contract requires the future Mixtar initramfs to:

```text
parse mixtar.profile=rt-7.1.2-mixtar-rt
mount the selected root filesystem read-only first
preserve /dev, /proc, /sys, /run, and /tmp
expose native Mixtar runtime views under /System and /Temporary
prefer /System/Tools/Current/bin before compatibility paths
keep /System/Libraries/MixtarRVS/Runtime/0003/lib as the staged runtime library root
exec /System/SystemTools/mixtar-fallback-init --exec
fall back to /sbin/init while OpenRC remains the live supervisor
```

### Stage 0005 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
initramfs-contract-status: verified
/System/SystemTools/mixtar-fallback-init: installed
shim check: native-init=compat-fallback:/System/SystemTools/init, fallback-init=/sbin/init
/System/SystemTools/init -> /bin/busybox
PID1: init
OpenRC default runlevel: ok
/System/Kernel/Current -> Profiles/rt-7.1.2-mixtar-rt
uname -r: 7.1.2-mixtar-rt
```

Stage 0005 did not rebuild `initramfs.img`, rewrite EFI loader entries, replace `/sbin/init`, stop OpenRC services, hide POSIX compatibility paths, or remove Alpine/apk fallback components.

Important limitation:

```text
/System/SystemTools/init is still a BusyBox compatibility symlink, not a Mixtar-native init.
OpenRC, sshd, dhcpcd, iwd, dbus, and apk remain bootstrap/fallback components.
```

Next stage:

```text
0006-service-and-network-closure-inventory
```

## Stage 0006: service and network closure inventory

Stage 0006 records the live service/network/SSH bootstrap dependencies and defines the missing MixtarRVS replacements required before Alpine can stop being the system identity.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0006-service-network-inventory.json
Server/Rootfs/scripts/stage-service-network-inventory.sh
```

Installed on ThinkPad:

```text
/System/Base/Closure/0006-service-and-network-closure-inventory/
```

### Stage 0006 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
service-network-status: verified
active default services: sshd, dbus, iwd, dhcpcd, mixtar-boot-profiler, mixtar-firstboot-report
network: wlan0 192.168.99.110/24, default route via 192.168.99.254
/System/Kernel/Current -> Profiles/rt-7.1.2-mixtar-rt
PID1 remains: init
```

Key Alpine/bootstrap package ownership:

```text
/sbin/openrc        -> openrc-0.63.2-r0
/bin/busybox        -> busybox-1.37.0-r31
/sbin/dhcpcd        -> dhcpcd-10.3.2-r0
/usr/libexec/iwd    -> iwd-3.12-r0
/usr/bin/dbus-daemon -> dbus-1.16.2-r2
/usr/sbin/sshd      -> openssh-server-10.3_p1-r0
/sbin/apk           -> apk-tools-3.0.6-r0
```

Current bootstrap roles:

```text
service supervisor: OpenRC
PID1: BusyBox init
sysinit/device setup: devfs, procfs, sysfs, mdev, hwdrivers through OpenRC
network addressing: dhcpcd
Wi-Fi: iwd
remote access: OpenSSH sshd
system bus: dbus-daemon
package/bootstrap tool: apk-tools
```

Required MixtarRVS replacements before Alpine can stop being identity:

```text
Mixtar service runner: list/start/stop/status, ordered startup, shutdown hooks, logs, fallback to OpenRC while incomplete
Mixtar runtime/device setup: own or verify /dev, /proc, /sys, /run, /tmp and expose /System native views
Mixtar network layer: profiles, interface discovery, DHCP/static handoff, route/resolver health checks
Mixtar Wi-Fi layer: profile/state ownership over iwd first
Mixtar remote access policy: sshd service manifest now, future Mixtar agent optional
Mixtar package/generation control: apk hidden as backend only, not user-facing identity
D-Bus policy: declare base/workstation/backend-only role
```

Stage 0006 did not stop/restart services, change runlevels, change network configuration, replace PID1, remove Alpine packages, or hide POSIX compatibility paths.

Next stage:

```text
0007-mixtar-service-runner-skeleton
```

## Stage 0007: Mixtar service runner skeleton

Stage 0007 installs the first MixtarRVS service interface and service manifests under `/System`, while keeping OpenRC as the explicit compatibility backend.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0007-service-runner.json
Server/Rootfs/scripts/mixtar-service.sh
Server/Rootfs/scripts/stage-service-runner.sh
Server/Rootfs/services/*.service
```

Installed on ThinkPad:

```text
/System/SystemTools/mixtar-service
/System/Config/Services/*.service
/System/Base/Closure/0007-mixtar-service-runner-skeleton/
```

Implemented commands:

```text
mixtar-service contract
mixtar-service check
mixtar-service list
mixtar-service status <service>
mixtar-service start <service>
mixtar-service stop <service>
```

Current backend policy:

```text
MixtarRVS owns the service interface.
OpenRC remains the explicit backend through /sbin/rc-service and /bin/rc-status.
status is non-mutating and works as a normal user through rc-status -a.
start/stop are intentionally mutating OpenRC backend calls.
```

### Stage 0007 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
service-runner-status: verified
mixtar-service check: ok service-manifests=7 backend=openrc
mixtar-service list:
  boot-profiler -> mixtar-boot-profiler
  dbus -> dbus
  firstboot-report -> mixtar-firstboot-report
  network -> dhcpcd
  realtime-tune -> mixtar-realtime-tune
  sshd -> sshd
  wifi -> iwd
mixtar-service status sshd: started
mixtar-service status dbus: started
mixtar-service status wifi: started
mixtar-service status network: started
PID1 remains: init
OpenRC default runlevel remains: sshd, dbus, iwd, dhcpcd, mixtar-boot-profiler, mixtar-firstboot-report
```

Stage 0007 did not restart services, change runlevels, replace PID1, remove OpenRC scripts, remove Alpine packages, or hide POSIX compatibility paths.

Important limitation:

```text
mixtar-service is a Mixtar interface and manifest layer, not a native supervisor yet.
OpenRC remains the live backend.
Dependency ordering, log capture, restart policy, and shutdown hooks are still missing.
```

Next stage:

```text
0008-mixtar-network-profile-layer
```

## Stage 0008: Mixtar network profile layer

Stage 0008 installs the first MixtarRVS network profile/status interface under `/System`, while keeping `dhcpcd`, `iwd`, `sshd`, and OpenRC as explicit compatibility backends.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0008-network-profile-layer.json
Server/Rootfs/scripts/mixtar-network.sh
Server/Rootfs/scripts/stage-network-profile-layer.sh
Server/Rootfs/network/current.network
```

Installed on ThinkPad:

```text
/System/SystemTools/mixtar-network
/System/Config/Network/current.network
/System/Base/Closure/0008-mixtar-network-profile-layer/
```

Implemented commands:

```text
mixtar-network contract
mixtar-network check
mixtar-network status
mixtar-network profile
mixtar-network interfaces
mixtar-network routes
mixtar-network dns
mixtar-network wifi
mixtar-network backend
```

Current backend policy:

```text
interface: wlan0
addressing: DHCP
DHCP backend: dhcpcd
Wi-Fi backend: iwd via iwctl
DNS source: dhcpcd-generated /etc/resolv.conf
remote access: sshd
service status: mixtar-service over OpenRC
```

### Stage 0008 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
network-profile-status: verified
mixtar-network check: ok profile=current interface=wlan0 backend=dhcpcd+iwd remote=sshd
ipv4: 192.168.99.110/24
default route: 192.168.99.254 via wlan0
DNS: 192.168.99.254
network service: dhcpcd started
wifi service: iwd started
remote service: sshd started
backend tools: /sbin/dhcpcd, /usr/bin/iwctl, /usr/sbin/sshd
```

Stage 0008 did not restart `dhcpcd`, `iwd`, `dbus`, `sshd`, or OpenRC; did not rewrite `/etc/resolv.conf`; did not change IP addresses, routes, DNS, Wi-Fi credentials, or service runlevels.

Important limitation:

```text
mixtar-network is a Mixtar profile/status layer, not a native network daemon.
dhcpcd remains the live DHCP/resolver backend.
iwd remains the live Wi-Fi backend.
OpenSSH remains the live remote-access backend.
Profile application is not implemented yet.
```

Next stage:

```text
0009-mixtar-remote-access-policy
```

## Stage 0009: Mixtar remote access policy

Stage 0009 installs the first MixtarRVS remote-access policy/status interface under `/System`, while keeping OpenSSH, OpenRC, and the active SSH configuration unchanged.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0009-remote-access-policy.json
Server/Rootfs/scripts/mixtar-remote.sh
Server/Rootfs/scripts/stage-remote-access-policy.sh
Server/Rootfs/remote/current.remote
```

Installed on ThinkPad:

```text
/System/SystemTools/mixtar-remote
/System/Config/RemoteAccess/current.remote
/System/Base/Closure/0009-mixtar-remote-access-policy/
```

Implemented commands:

```text
mixtar-remote contract
mixtar-remote check
mixtar-remote status
mixtar-remote profile
mixtar-remote config
mixtar-remote keys
mixtar-remote listeners
mixtar-remote backend
```

Current backend policy:

```text
transport: SSH
backend: OpenSSH sshd
service status: mixtar-service over OpenRC
network status: mixtar-network over dhcpcd+iwd
config: /etc/ssh/sshd_config
keys: authorized_keys fingerprints only
```

### Stage 0009 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
remote-access-status: verified
mixtar-remote check: ok remote=ssh user=vxz host=192.168.99.110 port=22 backend=openssh
service_status: sshd started
network_status: ok profile=current interface=wlan0 backend=dhcpcd+iwd remote=sshd
authorized_keys: /Users/vxz/.ssh/authorized_keys
authorized_keys_count: 1
authorized_key_fingerprint: SHA256:SonZlvqXaNtA9h6IQTHHnMchdJ8Ix4yMU4KoTHzrxkI
configured_port: 22
listeners: /proc/net/tcp 0.0.0.0:22 LISTEN, /proc/net/tcp6 :::22 LISTEN
```

Stage 0009 did not restart `sshd`, rewrite `/etc/ssh/sshd_config`, add/remove SSH keys, read private host keys, change network configuration, replace OpenSSH, or replace OpenRC.

Important limitation:

```text
mixtar-remote is a Mixtar policy/status layer, not a native remote daemon.
OpenSSH remains the live backend.
Key management is inventory-only in this stage.
Listener audit confirms TCP LISTEN state through /proc/net/tcp and /proc/net/tcp6; PID/program ownership is not required without root.
```

Next stage:

```text
0010-mixtar-package-generation-backend-boundary
```

## Stage 0010: package/generation backend boundary

Stage 0010 installs the first MixtarRVS generation/package boundary under `/System`, making `apk` an explicit hidden compatibility backend instead of the user-facing system identity.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0010-package-generation-boundary.json
Server/Rootfs/scripts/mixtar-generation.sh
Server/Rootfs/scripts/stage-package-generation-boundary.sh
Server/Rootfs/generation/current.generation
```

Installed on ThinkPad:

```text
/System/SystemTools/mixtar-generation
/System/Config/Generation/current.generation
/System/Base/Closure/0010-package-generation-backend-boundary/
```

Implemented commands:

```text
mixtar-generation contract
mixtar-generation check
mixtar-generation status
mixtar-generation profile
mixtar-generation world
mixtar-generation repos
mixtar-generation packages
mixtar-generation backend
mixtar-generation closure
```

Current backend policy:

```text
visible identity: MixtarRVS generation profile
package backend: apk
backend visibility: hidden compatibility backend
current generation link: /System/Current -> Generations/0002-alpine-openrc-zsh
generation root: /System/Generations
toolkit root: /System/Tools/Current/bin
apk world: /etc/apk/world
apk repositories: /etc/apk/repositories
```

### Stage 0010 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
package-generation-status: verified
mixtar-generation check: ok generation=current toolkit=158 packages=167 backend=apk-hidden
toolkit_count: 158
apk package_count: 167
apk world_count: 37
repository_count: 2
stage_count: 10
current_target: Generations/0002-alpine-openrc-zsh
root_model: installed-mutable-root
apk_version: apk-tools 3.0.6-r0, compiled for x86_64
mksquashfs: missing
```

Stage 0010 did not install packages, remove packages, run `apk upgrade`, rewrite `/etc/apk/world`, rewrite `/etc/apk/repositories`, create a boot generation, rebuild rootfs/initramfs, or remove Alpine fallback components.

Important limitation:

```text
mixtar-generation is a Mixtar boundary/status layer, not a full system builder yet.
apk remains the live package backend.
mksquashfs is missing, so image-based generation building is not available yet.
The active root is still an installed mutable root, not a complete immutable generation closure.
Rollback boot ownership is not implemented by this stage.
```

Next stage:

```text
0011-mixtar-generation-builder-dry-run
```

## Stage 0011: Mixtar generation builder dry-run

Stage 0011 adds the first dry-run generation build plan to `mixtar-generation`.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0011-generation-builder-dry-run.json
Server/Rootfs/scripts/mixtar-generation.sh
Server/Rootfs/scripts/stage-generation-builder-dry-run.sh
```

Installed on ThinkPad:

```text
/System/SystemTools/mixtar-generation
/System/Base/Closure/0011-mixtar-generation-builder-dry-run/
```

New command:

```text
mixtar-generation build --dry-run
```

Dry-run guarantees:

```text
would_create_generation=false
would_activate_generation=false
would_run_apk_add=false
would_run_apk_del=false
would_run_apk_upgrade=false
would_rewrite_apk_world=false
would_rewrite_apk_repositories=false
```

### Stage 0011 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
generation-builder-dry-run-status: verified
mixtar-generation check: ok generation=current toolkit=158 packages=167 backend=apk-hidden
current_target: Generations/0002-alpine-openrc-zsh
kernel_profile: Profiles/rt-7.1.2-mixtar-rt
toolkit_count: 158
package_count: 167
world_count: 37
repository_count: 2
base_closure_stage_count: 11
service_check: ok service-manifests=7 backend=openrc
network_check: ok profile=current interface=wlan0 backend=dhcpcd+iwd remote=sshd
remote_check: ok remote=ssh user=vxz host=192.168.99.110 port=22 backend=openssh
runtime_libraries_ready: true
initramfs_contract_ready: true
image_builder_ready: false
missing_image_builder: mksquashfs
buildable_now: false
```

Stage 0011 did not create a generation directory, switch `/System/Current`, install/remove/upgrade packages, rewrite `/etc/apk/world`, rewrite `/etc/apk/repositories`, rebuild rootfs, rebuild initramfs, or change bootloader state.

Important limitation:

```text
This is a real dry-run planner, not a real builder yet.
The next hard blocker is image/rootfs generation: mksquashfs and the activation/switch/rollback model are missing.
apk remains the hidden compatibility backend.
The active root is still an installed mutable root.
```

Next stage:

```text
0012-mixtar-rootfs-image-builder-requirements
```

## Stage 0012: rootfs image builder requirements

Stage 0012 installs the first MixtarRVS rootfs image builder requirements contract under `/System`.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0012-rootfs-image-builder-requirements.json
Server/Rootfs/scripts/mixtar-rootfs-image.sh
Server/Rootfs/scripts/stage-rootfs-image-builder-requirements.sh
Server/Rootfs/image/rootfs-image.requirements
```

Installed on ThinkPad:

```text
/System/SystemTools/mixtar-rootfs-image
/System/Config/ImageBuilder/rootfs-image.requirements
/System/Base/Closure/0012-rootfs-image-builder-requirements/
```

Implemented commands:

```text
mixtar-rootfs-image contract
mixtar-rootfs-image check
mixtar-rootfs-image requirements
mixtar-rootfs-image inputs
mixtar-rootfs-image exclusions
mixtar-rootfs-image plan
mixtar-rootfs-image backend
mixtar-rootfs-image readiness
```

Image model:

```text
format: squashfs
required_builder: mksquashfs
future_output: /System/Generations/<id>/rootfs.squashfs
future_manifest: /System/Generations/<id>/manifest.json
future_activation: /System/Generations/<id>/activation.plan
activation_policy: stage-only-first
rollback_policy: preserve-current-and-previous-until-boot-tested
```

### Stage 0012 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
rootfs-image-requirements-status: verified
mixtar-rootfs-image check: ok rootfs-image requirements format=squashfs builder=mksquashfs builder_ready=false
would_create_rootfs_image: false
would_create_generation: false
would_mount_filesystems: false
would_run_mksquashfs: false
would_rebuild_initramfs: false
would_switch_current: false
kernel_vmlinuz_ready: true
kernel_initramfs_ready: true
toolkit_ready: true
runtime_libraries_ready: true
builder_ready: false
build_blocker: mksquashfs missing
image_buildable_now: false
/System/Current remains: Generations/0002-alpine-openrc-zsh
```

Rootfs image exclusions currently declared:

```text
/dev
/proc
/sys
/run
/tmp
/Temporary
/Users
/Volumes
/System/Runtime/run
/System/Logs
/var/cache/apk
/mnt
/media
/lost+found
```

Stage 0012 did not create `rootfs.squashfs`, create a generation directory, mount filesystems, run `mksquashfs`, rebuild initramfs, change bootloader state, switch `/System/Current`, or remove Alpine/OpenRC/apk fallback.

Important limitation:

```text
This stage defines the rootfs image requirements only.
mksquashfs is missing, so squashfs generation is blocked.
The active root is still a mutable ext4 install.
Activation, switch, boot, rollback, and garbage collection are still missing.
/System/Config currently resolves into compatibility /etc, so immutable config capture still needs explicit policy before real image builds.
```

Next stage:

```text
0013-rootfs-image-builder-dependency-stage
```

## Stage 0013: rootfs image builder dependency stage

Stage 0013 installs the minimal image builder dependency required by the MixtarRVS rootfs image contract.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0013-rootfs-image-builder-dependency-stage.json
Server/Rootfs/scripts/stage-rootfs-image-builder-dependency.sh
Server/Rootfs/scripts/mixtar-generation.sh
Server/Rootfs/scripts/mixtar-rootfs-image.sh
Server/Rootfs/image/rootfs-image.requirements
```

Installed/updated on ThinkPad:

```text
/System/Base/Closure/0013-rootfs-image-builder-dependency-stage/
/System/Config/ImageBuilder/rootfs-image.requirements
/System/SystemTools/mixtar-rootfs-image
/System/SystemTools/mixtar-generation
```

Allowed package mutation:

```text
apk add squashfs-tools
```

Observed result:

```text
rootfs-image-builder-dependency-status: verified
package_count: 170
world_count: 38
world_has_squashfs_tools: true
mksquashfs: /usr/bin/mksquashfs
unsquashfs: /usr/bin/unsquashfs
/System/Current remains: Generations/0002-alpine-openrc-zsh
```

`mixtar-rootfs-image` after stage 0013:

```text
mixtar-rootfs-image check: ok rootfs-image requirements format=squashfs builder=mksquashfs builder_ready=true
builder_ready: true
generation_root_ready: true
kernel_vmlinuz_ready: true
kernel_initramfs_ready: true
toolkit_ready: true
runtime_libraries_ready: true
image_buildable_now: false
```

`mixtar-generation build --dry-run` after stage 0013:

```text
would_create_generation=false
would_activate_generation=false
mksquashfs=/usr/bin/mksquashfs
unsquashfs=/usr/bin/unsquashfs
image_builder_ready=true
buildable_now=false
build_blocker=activation/switch/rollback not implemented
```

Stage 0013 did not create `rootfs.squashfs`, create a bootable generation, switch `/System/Current`, rebuild initramfs, change bootloader state, remove packages, run `apk upgrade`, or remove Alpine/OpenRC/apk fallback.

Important limitation:

```text
The image builder dependency is now present, but there is still no actual rootfs image build command.
Activation, switch, boot, rollback, and garbage collection are still missing.
apk remains the hidden compatibility backend.
The active root is still a mutable ext4 install.
```

Next stage:

```text
0014-rootfs-image-build-dry-run
```

## Stage 0014: rootfs image build dry-run

Stage 0014 adds the first real dry-run plan for building `rootfs.squashfs`.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0014-rootfs-image-build-dry-run.json
Server/Rootfs/scripts/mixtar-rootfs-image.sh
Server/Rootfs/scripts/stage-rootfs-image-build-dry-run.sh
```

Installed on ThinkPad:

```text
/System/SystemTools/mixtar-rootfs-image
/System/Base/Closure/0014-rootfs-image-build-dry-run/
```

New command:

```text
mixtar-rootfs-image build --dry-run
```

Planned target:

```text
target_generation_id=0014-rootfs-image-preview
target_generation_dir=/System/Generations/0014-rootfs-image-preview
target_image=/System/Generations/0014-rootfs-image-preview/rootfs.squashfs
target_manifest=/System/Generations/0014-rootfs-image-preview/manifest.json
target_activation=/System/Generations/0014-rootfs-image-preview/activation.plan
```

Planned image command:

```text
mksquashfs / /System/Generations/0014-rootfs-image-preview/rootfs.squashfs -comp zstd -noappend -wildcards -e dev proc sys run tmp Temporary Users Volumes System/Runtime/run System/Logs var/cache/apk mnt media lost+found
```

### Stage 0014 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
rootfs-image-build-dry-run-status: verified
mixtar-rootfs-image check: ok rootfs-image requirements format=squashfs builder=mksquashfs builder_ready=true
would_create_rootfs_image: false
would_create_generation: false
would_create_target_dir: false
would_mount_filesystems: false
would_run_mksquashfs: false
would_rebuild_initramfs: false
would_switch_current: false
would_change_bootloader: false
builder: /usr/bin/mksquashfs
unsquashfs: /usr/bin/unsquashfs
builder_ready: true
dry_run_result: plan-generated
buildable_now: false
build_blocker: actual image creation and activation/switch/rollback not implemented
/System/Generations/0014-rootfs-image-preview exists: no
/System/Current remains: Generations/0002-alpine-openrc-zsh
```

Input size estimate from anchor roots:

```text
/System: 310992 KiB
/bin: 19608 KiB
/sbin: 2068 KiB
/lib: 580944 KiB
/usr: 410652 KiB
/etc: 2480 KiB
```

Current dry-run exclusions:

```text
/dev
/proc
/sys
/run
/tmp
/Temporary
/Users
/Volumes
/System/Runtime/run
/System/Logs
/var/cache/apk
/mnt
/media
/lost+found
```

Stage 0014 did not create `rootfs.squashfs`, create the target generation directory, mount filesystems, run `mksquashfs`, rebuild initramfs, switch `/System/Current`, change bootloader state, or remove Alpine/OpenRC/apk fallback.

Important limitation:

```text
This stage produces the real build plan only.
It still does not create an image file.
The file manifest is planned but not emitted as a full file list yet.
Activation, switch, boot, rollback, and garbage collection are still missing.
```

Next stage:

```text
0015-rootfs-image-build-first-file-no-activation
```

## Stage 0015: rootfs image first file, no activation

Stage 0015 creates the first real `rootfs.squashfs` artifact for MixtarRVS without activating it.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0015-rootfs-image-build-first-file.json
Server/Rootfs/scripts/mixtar-rootfs-image.sh
Server/Rootfs/scripts/stage-rootfs-image-build-first-file.sh
```

Installed/built on ThinkPad:

```text
/System/Base/Closure/0015-rootfs-image-build-first-file-no-activation/
/System/Generations/0015-rootfs-image-first-file/rootfs.squashfs
/System/Generations/0015-rootfs-image-first-file/manifest.json
/System/Generations/0015-rootfs-image-first-file/activation.plan
```

Build command path:

```text
mixtar-rootfs-image build --first-file
```

Planned/executed image command:

```text
mksquashfs / /System/Generations/0015-rootfs-image-first-file/rootfs.squashfs -comp zstd -noappend -wildcards -e dev proc sys run tmp Temporary Users Volumes System/Runtime/run System/Logs var/cache/apk mnt media lost+found System/Generations/0015-rootfs-image-first-file
```

### Stage 0015 smoke result

Observed on ThinkPad T480 after non-activating build:

```text
rootfs-image-build-first-file-status: verified
rootfs.squashfs: created
size_bytes: 783585280
filesystem_size: 747.28 MiB
compression: zstd
sha256: 7f48825e78c3cdd47f9bbe9ce29ad26c1cde6bde5b35cf4b5ce0e39a1355a372
unsquashfs -s: valid SQUASHFS 4.0 superblock
number_of_files: 30698
number_of_inodes: 36860
number_of_device_nodes: 0
self_include_check: no-self-include
/System/Current remains: Generations/0002-alpine-openrc-zsh
```

Generated manifest:

```text
id: 0015-rootfs-image-first-file
status: non-activating
rootfs: rootfs.squashfs
format: squashfs
compression: zstd
activation: not-active
current_at_build: Generations/0002-alpine-openrc-zsh
```

Generated activation plan:

```text
activation=none
would_switch_current=false
would_rebuild_initramfs=false
would_change_bootloader=false
rollback=preserve-current-generation
```

Stage 0015 did not switch `/System/Current`, rewrite `/System/Previous`, rebuild initramfs, change bootloader state, mount the generated image as root, remove Alpine/OpenRC/apk fallback, or run `apk add`, `apk del`, or `apk upgrade`.

Important limitation:

```text
The image exists but is not booted.
The image is not mounted as root.
No switch, rollback, bootloader, or garbage collection path is implemented yet.
The generated image still reflects the current mutable installed source root, including compatibility substrate.
```

Next stage:

```text
0016-rootfs-image-inspection-and-mount-plan
```

## Stage 0016: rootfs image inspection and mount plan

Stage 0016 inspects the first `rootfs.squashfs` and records a safe read-only mount plan without mounting or activating the image.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0016-rootfs-image-inspection-and-mount-plan.json
Server/Rootfs/scripts/mixtar-rootfs-image.sh
Server/Rootfs/scripts/stage-rootfs-image-inspection-and-mount-plan.sh
```

Installed on ThinkPad:

```text
/System/Base/Closure/0016-rootfs-image-inspection-and-mount-plan/
/System/SystemTools/mixtar-rootfs-image
```

New/verified commands:

```text
mixtar-rootfs-image inspect
mixtar-rootfs-image contents-check
mixtar-rootfs-image mount-plan
```

### Stage 0016 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
rootfs-image-inspection-status: verified
image: /System/Generations/0015-rootfs-image-first-file/rootfs.squashfs
image_status: present
size_bytes: 783585280
sha256: 7f48825e78c3cdd47f9bbe9ce29ad26c1cde6bde5b35cf4b5ce0e39a1355a372
unsquashfs -s: valid SQUASHFS 4.0 superblock
compression: zstd
inodes: 36860
contents_check: ok
self_include: absent
/System/Current remains: Generations/0002-alpine-openrc-zsh
```

Required content verified in the image:

```text
/System
/System/Tools -> ../bin
/bin/Current
/bin/MixtarRVS/bin
/System/SystemTools -> ../sbin
/sbin/mixtar-rootfs-image
/System/Kernel/Current
/System/Config -> ../etc
/etc/Services
/etc/Network/current.network
/etc/RemoteAccess/current.remote
/etc/ImageBuilder/rootfs-image.requirements
/System/Libraries -> ../lib
/lib/MixtarRVS/Runtime/0003/lib
/bin
/sbin
/lib
/usr
/etc
```

Mount plan recorded but not executed:

```text
mount_plan=inspect-only
would_mount=false
requires_root=true
mount_point=/System/Runtime/Inspect/rootfs-0015
mount_command=mount -t squashfs -o loop,ro /System/Generations/0015-rootfs-image-first-file/rootfs.squashfs /System/Runtime/Inspect/rootfs-0015
umount_command=umount /System/Runtime/Inspect/rootfs-0015
activation=none
```

Stage 0016 did not mount the image, mount it as root, switch `/System/Current`, rebuild initramfs, change bootloader state, modify the image file, or remove Alpine/OpenRC/apk fallback.

Important limitation:

```text
The image is inspected but not mounted.
The image is still not booted.
The image currently reflects the compatibility layout: /System/Tools, /System/SystemTools, /System/Config, and /System/Libraries are aliases into /bin, /sbin, /etc, and /lib.
Switch, rollback, bootloader, and garbage collection are still missing.
```

Next stage:

```text
0017-rootfs-image-readonly-mount-inspection
```

## Stage 0017: rootfs image read-only mount inspection

Stage 0017 mounts the first `rootfs.squashfs` read-only for inspection, verifies mounted paths, then unmounts it before finishing.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0017-rootfs-image-readonly-mount-inspection.json
Server/Rootfs/scripts/mixtar-rootfs-image.sh
Server/Rootfs/scripts/stage-rootfs-image-readonly-mount-inspection.sh
```

Installed on ThinkPad:

```text
/System/Base/Closure/0017-rootfs-image-readonly-mount-inspection/
/System/SystemTools/mixtar-rootfs-image
```

Command executed by the stage:

```text
mixtar-rootfs-image mount-inspect --once
```

### Stage 0017 smoke result

Observed on ThinkPad T480 after read-only mount inspection:

```text
rootfs-image-readonly-mount-inspection-status: verified
image: /System/Generations/0015-rootfs-image-first-file/rootfs.squashfs
mount_point: /System/Runtime/Inspect/rootfs-0015
mount_status: mounted
mount_line: /dev/loop0 /System/Runtime/Inspect/rootfs-0015 squashfs ro,relatime,errors=continue 0 0
would_use_as_rootfs: false
mounted_path_System: present
mounted_path_System_Tools_Current: present
mounted_path_System_SystemTools: present
mounted_path_System_Kernel_Current: present
mounted_path_etc_Network: present
mounted_path_etc_RemoteAccess: present
mounted_path_etc_ImageBuilder: present
mounted_path_lib_Runtime: present
mounted_path_bin: present
mounted_path_sbin: present
mounted_self_include: absent
unmount_status: unmounted
mount_after: absent
mount_inspect_result: ok
/System/Current remains: Generations/0002-alpine-openrc-zsh
```

Final mount state:

```text
/System/Runtime/Inspect/rootfs-0015 exists as a directory.
It is not mounted after the stage.
```

Stage 0017 did not mount the image as root, switch `/System/Current`, rebuild initramfs, change bootloader state, leave the image mounted, modify the image file, or remove Alpine/OpenRC/apk fallback.

Important limitation:

```text
The image has now been mounted read-only for inspection, but it is still not booted.
No switch, rollback, bootloader, or garbage collection path is implemented by this stage.
The image still reflects compatibility layout from the current mutable source root.
```

Next stage:

```text
0018-rootfs-image-file-manifest-and-diff
```

## Stage 0018: rootfs image file manifest and diff

Stage 0018 generates a normalized path manifest for the first `rootfs.squashfs`, generates a comparable current-root manifest with the declared rootfs exclusions, and records path-level differences.

Artifacts:

```text
Server/Rootfs/manifests/base-closure-0018-rootfs-image-file-manifest-and-diff.json
Server/Rootfs/scripts/mixtar-rootfs-image.sh
Server/Rootfs/scripts/stage-rootfs-image-file-manifest-and-diff.sh
```

Installed/generated on ThinkPad:

```text
/System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/image-file-manifest.txt
/System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/current-root-manifest.txt
/System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/image-only.txt
/System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/current-only.txt
/System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/manifest-diff-summary.txt
```

New commands:

```text
mixtar-rootfs-image file-manifest
mixtar-rootfs-image current-manifest
mixtar-rootfs-image diff-current
```

### Stage 0018 smoke result

Observed on ThinkPad T480 after non-activating staging:

```text
rootfs-image-file-manifest-and-diff-status: verified
diff_status: generated
image_path_count: 36882
current_path_count: 36926
image_only_count: 0
current_only_count: 44
current_target: Generations/0002-alpine-openrc-zsh
mount_after: absent
```

Interpretation:

```text
image_only_count=0 means every normalized path in the image still exists in the current root.
current_only_count=44 is expected because stages 0016, 0017, and 0018 were added after the stage 0015 image was built.
```

Examples of current-only paths:

```text
System/Base/Closure/0015-rootfs-image-build-first-file-no-activation/activation.plan
System/Base/Closure/0016-rootfs-image-inspection-and-mount-plan/manifest.json
System/Base/Closure/0017-rootfs-image-readonly-mount-inspection/rootfs-image-mount-inspect.txt
System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/image-file-manifest.txt
System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/current-root-manifest.txt
```

Stage 0018 did not mount the image, modify the image file, switch `/System/Current`, rebuild initramfs, change bootloader state, or remove Alpine/OpenRC/apk fallback.

Important limitation:

```text
This is a path-level manifest and diff, not a full content-hash manifest for every file.
The image still reflects compatibility layout from the current mutable source root.
Switch, rollback, bootloader, and garbage collection are still missing.
```

Next stage:

```text
0019-rootfs-image-content-hash-sample-and-switch-readiness
```
