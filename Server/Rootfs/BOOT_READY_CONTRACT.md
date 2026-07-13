# MixtarRVS pre-v0 boot-ready contract

Updated: 28.06.2026

This contract defines what the pre-v0 Mixtar image must contain before it is
eligible for physical installation on the ThinkPad target partition.

## Target

```text
ThinkPad T480
  Linux kernel
  Alpine minirootfs
  musl
  apk
  OpenRC
  zsh
  Mixtar bootstrap-view layout
```

## Required image content

The ext4 image/rootfs must contain:

```text
/etc/mixtar-release
/etc/alpine-release
/sbin/apk
/lib/ld-musl-x86_64.so.1
/sbin/openrc
/bin/zsh
/sbin/init

/System
/System/Kernel
/System/Runtime
/System/Tools
/System/Tools/mixtar-postboot-report
/System/SystemTools
/System/Shells
/System/Shells/zsh
/Applications
/Programs
/Users

/Compatibility/Alpine
/Compatibility/Chimera
/Compatibility/Debian
/Compatibility/FreeBSD
/Compatibility/OpenBSD
/Compatibility/Void
```

The image must also contain the selected host kernel payload:

```text
/boot/vmlinuz-<kernel-release>
/boot/initrd.img-<kernel-release>
/lib/modules/<kernel-release>
```

`install-image` and `install-rootfs` must fail instead of silently producing an
artifact when this payload is missing on the build host.

This is required because the temporary GRUB block searches for `MIXTARROOT` and
loads:

```text
/boot/vmlinuz-<kernel-release>
/boot/initrd.img-<kernel-release>
```

from that partition.

The first pre-v0 GRUB entries should use `rootwait`:

```text
root=LABEL=<root-label> ro rootwait
root=LABEL=<root-label> rw rootwait init=/bin/sh
```

Do not hide first-boot logs with `quiet`; OpenRC/kernel output is useful during
the first physical boot.

## Login state

Two login states are valid before physical install:

```text
rescue-first:
  root is locked
  first user may be absent or password-locked
  rescue GRUB entry is required for first boot

login-ready:
  first user exists
  first user home is /Users/<user>
  first user shell is /System/Shells/zsh
  MIXTAR_FIRST_PASSWORD_HASH contains a SHA-512 crypt hash
```

Do not bake a default plaintext password into Mixtar.

## Required gate before physical install

Run:

```sh
mixtar-rebuild.sh preinstall-gate <manifest>
```

The gate must run before:

```sh
mixtar-rebuild.sh install-rootfs <manifest> --erase-device
mixtar-rebuild.sh grub-install <manifest> --write-grub
```

Physical installation still requires explicit user approval.

## Preferred physical install wrapper

Use the main builder wrapper below for the final physical install instead of
manually running the destructive commands one by one:

```sh
mixtar-rebuild.sh physical-plan <manifest>
mixtar-rebuild.sh physical-install <manifest> --erase-device --write-grub
```

Install mode requires typing the exact interactive confirmation phrase:

```text
FORMAT <target-device> AS <root-label>
```

The wrapper still runs `preinstall-gate` before formatting the target.

`mixtar-physical-install.sh` remains the lower-level implementation used by the
main wrapper.

Physical install writes an audit log under the manifest directory:

```text
install-logs/physical-install-<timestamp>.log
```

Operational approval checklist:

```text
Server/Rootfs/PHYSICAL_INSTALL_APPROVAL.md
```
