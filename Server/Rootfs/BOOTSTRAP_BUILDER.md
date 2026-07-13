# Mixtar Bootstrap Builder

This document defines the pre-v0 bootstrap path.

It is intentionally smaller than the existing QEMU/initramfs proof. The purpose
is to create a visible Mixtar rootfs artifact first, then install or boot that
artifact later.

## Decision

Build Mixtar like a modified `debootstrap`:

```text
host Linux
  builds an isolated Mixtar rootfs artifact
    under out/mixtar-bootstrap by default
  does not mutate the host root filesystem
  does not install packages into the host
  does not assume Debian is the target identity
```

The current ThinkPad Debian install is a build host and lab. It is not the
Mixtar base.

## Current Bootstrap Scope

This stage creates layout and metadata only:

```text
/System
/System/Tools
/System/SystemTools
/System/Shells
/System/Libraries
/System/Config
/System/Runtime
/System/Init
/System/Logs
/Applications
/Programs
/Users
/Compatibility
```

This stage does not include:

```text
msh
AILang
package manager integration
bootloader changes
host system installation
```

Those are later stages.

## Compatibility Roots

Foreign distro payloads must not be merged into the Mixtar root.

Allowed compatibility roots:

```text
/Compatibility/Debian
/Compatibility/Alpine
/Compatibility/Chimera
/Compatibility/Void
```

Programs from those roots must eventually be launched through explicit wrappers
such as `compat-run debian <command>`. A compatibility root is a contained
foreign environment, not the system identity.

## First Builder

The first local builder is:

```text
Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh
```

The user-facing pre-v0 wrapper is:

```text
Server/Rootfs/tools/mixtar-rebuild.sh
```

The first Replit-friendly installer UI is:

```text
Server/Installer/web/index.html
```

It is a static HTML/CSS/JS command generator. It does not run SSH, format disks,
write GRUB, or store passwords. It generates the manifest and command sequence
for `mixtar-rebuild.sh`.

The first ThinkPad manifest is:

```text
Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
```

It describes:

```text
system=t480-mixtar-pre-v0
build_dir=/home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh
target_device=/dev/nvme0n1p3
root_label=MIXTARROOT
kernel_release=7.0.0-rc3-mixtarrvs
substrate=alpine-minirootfs
libc=musl
package_backend=apk
init=openrc
user_shell=zsh
layout_mode=bootstrap-view
```

`mixtar-rebuild.sh` is intentionally not Nix. It is a small coordinator:

```text
manifest -> build rootfs -> preflight -> install plan -> grub plan
```

Supported commands:

```text
mixtar-rebuild.sh build
mixtar-rebuild.sh status
mixtar-rebuild.sh preflight
mixtar-rebuild.sh install-plan
mixtar-rebuild.sh image-plan
mixtar-rebuild.sh install-image ... --erase-image
mixtar-rebuild.sh install-rootfs ... --erase-device
mixtar-rebuild.sh grub-plan
mixtar-rebuild.sh grub-install ... --write-grub
```

Default output:

```text
out/mixtar-bootstrap/
  rootfs/
  generations/0001-layout-only/
```

Run on a Linux build host:

```text
sh Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build
```

Run with an explicit output directory:

```text
sh Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build /home/vxz/mixtar-lab/local-bootstrap
```

Build the first Alpine/OpenRC artifact:

```text
sh Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build-alpine /home/vxz/mixtar-lab/builds/0002-alpine-openrc
```

Build with an explicit first user:

```text
MIXTAR_FIRST_USER=vxz sh Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build-alpine /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh-user-smoke
```

No password is set unless an explicit password hash is supplied:

```text
MIXTAR_FIRST_USER=vxz MIXTAR_FIRST_PASSWORD_HASH='<crypt-hash>' sh Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build-alpine /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh
```

Do not store plaintext passwords in scripts or manifests. Generate the hash
outside the repo and pass it as an environment variable.

Helper:

```text
Server/Rootfs/tools/mixtar-password-hash.sh
```

Usage on the ThinkPad:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-password-hash.sh
```

Then use the printed hash as `MIXTAR_FIRST_PASSWORD_HASH`. The plaintext
password must not be written to command history.

This creates:

```text
/home/vxz/mixtar-lab/builds/0002-alpine-openrc/
  rootfs/
  generations/0002-alpine-openrc/manifest.json
  images/mixtar-0002-alpine-openrc-rootfs.squashfs
```

The `build-alpine` mode intentionally uses a bootstrap view layout:

```text
/System/Tools       -> ../bin
/System/SystemTools -> ../sbin
/System/Libraries   -> ../lib
/System/Config      -> ../etc
/System/Resources   -> ../usr/share
```

This keeps Alpine `apk` and OpenRC in their expected paths while exposing the
Mixtar names. A later identity-mode build can invert this after package-manager
relocation is proven.

## ThinkPad Substrate Probe

Probe host:

```text
vxz@192.168.99.110
Debian GNU/Linux forky/sid
Linux 7.0.0-rc3-mixtarrvs
```

Installed host test tool:

```text
proot
```

Existing useful host tools:

```text
curl
wget
tar
xz
zstd
squashfs-tools
bubblewrap
busybox
qemu-system-x86_64
```

Alpine minirootfs probe before the zsh decision:

```text
source: Alpine latest-stable x86_64 minirootfs
resolved: alpine-minirootfs-3.24.1-x86_64.tar.gz
unpacked size: 8.7M
chroot smoke: ok
apk update: ok
available packages: 28637
installed test package: oksh
post-install rootfs size: 13M
squashfs zstd image size: 6.5M
```

`proot` was not reliable on this host/kernel combination. It started but the
Alpine BusyBox process terminated with signal 7 through the ptrace/seccomp
path. A normal privileged `chroot` worked and is the better local smoke method
for this ThinkPad.

Current conclusion:

```text
Alpine minirootfs is the fastest practical substrate for the first bootable
Mixtar artifact.
Debian remains the build host.
The target rootfs should be built as an artifact first, then installed or
booted separately.
```

## ThinkPad Build Result

Current successful build before the zsh switch:

```text
host: vxz@192.168.99.110
command: sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build-alpine /home/vxz/mixtar-lab/builds/0002-alpine-openrc
result: ok
alpine source: alpine-minirootfs-3.24.1-x86_64.tar.gz
installed packages: alpine-base openrc oksh
image: /home/vxz/mixtar-lab/builds/0002-alpine-openrc/images/mixtar-0002-alpine-openrc-rootfs.squashfs
image size: 3.9M
```

Chroot smoke:

```text
BusyBox v1.37.0
apk-tools 3.0.6-r0
openrc 0.63.2
rc-status 0.63.2
oksh: ok
/System view: ok
```

Read-only disk observation:

```text
/dev/nvme0n1p1  vfat  mounted at /boot/efi
/dev/nvme0n1p2  ext4  mounted at /
/dev/nvme0n1p3        7.9G, no filesystem shown, not mounted
```

Do not install to `/dev/nvme0n1p3` without explicit approval. It is the likely
first test target, but formatting it is destructive.

## Install Strategy

The first real laptop install should be a dual-boot test, not a replacement of
the Debian host.

Recommended first install target:

```text
/dev/nvme0n1p3 -> ext4 label MIXTARROOT
```

Initial boot path:

```text
Debian GRUB
  loads existing Mixtar/Debian-built Linux kernel
  root=/dev/disk/by-label/MIXTARROOT
  starts Alpine/OpenRC userspace from the Mixtar rootfs
```

The installer must:

```text
1. verify the selected block device is not mounted
2. format it only after an explicit destructive flag
3. extract the built Mixtar rootfs
4. copy matching kernel modules from the host for the selected kernel
5. write fstab
6. add a temporary bootstrap console/login policy
7. add a GRUB entry without removing Debian entries
8. keep rollback by leaving Debian bootable
```

The install script must default to `plan`/dry-run. The destructive path must
require an exact device and an explicit confirmation flag.

Current installer scaffold:

```text
Server/Rootfs/tools/mixtar-install-rootfs.sh
```

Plan command tested on the ThinkPad:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-install-rootfs.sh plan /home/vxz/mixtar-lab/builds/0002-alpine-openrc /dev/nvme0n1p3
```

Result:

```text
target: /dev/nvme0n1p3
filesystem: none shown
mounted: no
planned label: MIXTARROOT
kernel modules source: /lib/modules/7.0.0-rc3-mixtarrvs
bootloader changes: not performed yet
```

Rootfs-only install command, not yet run:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-install-rootfs.sh install-ext4-rootfs /home/vxz/mixtar-lab/builds/0002-alpine-openrc /dev/nvme0n1p3 --erase-device
```

Current zsh rootfs plan command:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-install-rootfs.sh plan /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh /dev/nvme0n1p3
```

Current preflight command:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-install-rootfs.sh preflight /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh /dev/nvme0n1p3 MIXTARROOT 7.0.0-rc3-mixtarrvs
```

Current preflight result:

```text
preflight: ok-with-rescue
WARN: root login is locked
WARN: no first user configured
```

Wrapper smoke on the ThinkPad:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh status /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh preflight /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh install-plan /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh grub-plan /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
```

Result:

```text
status: ok
preflight: ok-with-rescue
install-plan: ok
grub-plan: ok
```

Image install smoke:

```text
command: sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh image-plan /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
result: ok
command: sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh install-image /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf --erase-image
result: ok
image: /home/vxz/mixtar-lab/images/mixtar-pre-v0-rootfs.ext4
image size: 512M
label: MIXTARROOT
filesystem: ext4
```

Read-only image inspection:

```text
/etc/mixtar-release: ok
/sbin/init -> /bin/busybox
/System/Shells/zsh -> ../Tools/zsh
/System/Tools -> ../bin
/Compatibility/{Alpine,Chimera,Debian,FreeBSD,OpenBSD,Void}: present
/etc/fstab uses LABEL=MIXTARROOT
/lib/modules/7.0.0-rc3-mixtarrvs: present
```

First-user smoke preflight:

```text
command: sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-install-rootfs.sh preflight /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh-user-smoke /dev/nvme0n1p3 MIXTARROOT 7.0.0-rc3-mixtarrvs
result: preflight: ok-with-rescue
WARN: first user login is locked: vxz
```

To get `preflight: ok` for normal login, rebuild with both:

```text
MIXTAR_FIRST_USER=vxz
MIXTAR_FIRST_PASSWORD_HASH=<sha512-crypt-hash>
```

Current zsh rootfs install command, not yet run:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-install-rootfs.sh install-ext4-rootfs /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh /dev/nvme0n1p3 --erase-device
```

Next build target:

```text
generation: 0002-alpine-openrc
interactive shell: zsh
/bin/sh: BusyBox ash for Alpine/OpenRC scripts
/System/Shells/zsh -> /System/Tools/zsh -> /bin/zsh
installed packages: alpine-base openrc zsh
```

Current successful zsh build:

```text
host: vxz@192.168.99.110
command: sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build-alpine /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh
result: ok
installed packages: alpine-base openrc zsh
image: /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh/images/mixtar-0002-alpine-openrc-rootfs.squashfs
image size: 5.2M
```

Chroot smoke:

```text
zsh 5.9 (x86_64-alpine-linux-musl)
/System/Shells/zsh: ok
openrc 0.63.2: ok
apk world includes zsh
root shell: /System/Shells/zsh
BusyBox init: /sbin/init -> /bin/busybox
OpenRC boot path: /etc/inittab runs openrc sysinit, boot, default
```

Root password state:

```text
/etc/shadow root field: *
```

This means the normal OpenRC boot can reach getty, but root login is locked
until an explicit first-user/password policy is applied. The temporary GRUB plan
therefore also includes a rescue shell entry with `init=/bin/sh`.

First-user smoke:

```text
command: MIXTAR_FIRST_USER=vxz sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh build-alpine /home/vxz/mixtar-lab/builds/0002-alpine-openrc-zsh-user-smoke
result: ok
passwd: vxz:x:1000:1000::/Users/vxz:/System/Shells/zsh
shadow: vxz:!
manifest: "first_user": "vxz"
```

This proves the builder can create a first user without embedding a default
password. A login-capable install still needs an explicit
`MIXTAR_FIRST_PASSWORD_HASH`.

Bootloader plan helper:

```text
Server/Rootfs/tools/mixtar-plan-grub-entry.sh
```

Plan command tested on the ThinkPad:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-plan-grub-entry.sh plan MIXTARROOT 7.0.0-rc3-mixtarrvs
```

Generated entries:

```text
MixtarRVS pre-v0 Alpine/OpenRC/zsh
MixtarRVS pre-v0 rescue shell
```

The normal entry uses:

```text
linux /boot/vmlinuz-7.0.0-rc3-mixtarrvs root=LABEL=MIXTARROOT ro quiet
initrd /boot/initrd.img-7.0.0-rc3-mixtarrvs
```

The rescue entry uses:

```text
linux /boot/vmlinuz-7.0.0-rc3-mixtarrvs root=LABEL=MIXTARROOT rw init=/bin/sh
initrd /boot/initrd.img-7.0.0-rc3-mixtarrvs
```

Install mode is idempotent and guarded:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-plan-grub-entry.sh install MIXTARROOT 7.0.0-rc3-mixtarrvs
```

Result without the guard flag:

```text
rc=1
error: install requires explicit --write-grub
```

Actual GRUB write command, not yet run:

```text
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-plan-grub-entry.sh install MIXTARROOT 7.0.0-rc3-mixtarrvs --write-grub
```

This appends or replaces only the marked Mixtar block in `/etc/grub.d/40_custom`
and then runs `update-grub`. It must be run only after the rootfs is installed
or immediately before the first reboot test.
