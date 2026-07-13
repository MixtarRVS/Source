# MixtarRVS ThinkPad first boot runbook

Status: pre-v0
Target laptop: ThinkPad T480
Target host: `vxz@192.168.99.110`
Target partition: `/dev/nvme0n1p3`
Root label: `MIXTARROOT`
Kernel release: `7.0.0-rc3-mixtarrvs`

This runbook is the operational path from the current lab state to the first
bootable MixtarRVS pre-v0 system on the ThinkPad.

It deliberately separates:

```text
safe preparation
  from
physical install approval
  from
first boot
```

`image-ready`, `readiness-report`, and `preinstall-gate` are technical evidence.
They are not approval to format `/dev/nvme0n1p3`.

## Current intended system shape

```text
Linux kernel
  Alpine minirootfs substrate
  musl libc
  apk package substrate
  OpenRC init
  zsh user shell
  Mixtar visible layout
  no Nix dependency
  no GNU userland as Mixtar identity
```

Mixtar identity paths:

```text
/System
/System/Current
/System/Generations
/System/Kernel
/System/Runtime
/System/Tools
/System/SystemTools
/System/Shells
/Applications
/Programs
/Users
/Compatibility
```

Compatibility/reference paths:

```text
/Compatibility/Alpine
/Compatibility/FreeBSD
/Compatibility/OpenBSD
```

For pre-v0, `/Compatibility/*` is not a multi-distro package root. It is a
reference and adaptation space. The active package substrate remains Alpine/apk.

## Important paths on the ThinkPad

```text
Builder:
  /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh

Manifest:
  /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf

Rootfs image:
  /home/vxz/mixtar-lab/images/mixtar-pre-v0-rootfs.ext4

Installer UI:
  /home/vxz/mixtar-lab/repo-tools/Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer
```

## Phase 1: open the local installer UI

This is safe. It starts only a static local web server.

```sh
cd /home/vxz/mixtar-lab/repo-tools/Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer
./serve-installer.sh 127.0.0.1 8088
```

Open:

```text
http://127.0.0.1:8088/
```

The UI must be treated as a command generator and runbook viewer. It is not a
remote root installer.

## Phase 2: safe preparation commands

These commands are non-destructive by project policy. They must not format
`/dev/nvme0n1p3` and must not write GRUB.

Preferred safe wrapper:

```sh
/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-safe-prep.sh \
  /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
```

With live target inspection added:

```sh
/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-safe-prep.sh \
  /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf \
  --with-preinstall-gate
```

The wrapper does not run `physical-install`, `install-rootfs --erase-device`, or
`grub-install --write-grub`.

At the end it generates a non-destructive approval packet under:

```text
/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/approval-packets/
```

The approval packet records target, image, checksums, required phrase, and the
exact destructive command. It still says `install_approval=missing`.

Set a convenience variable:

```sh
MIXTAR_REBUILD=/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh
MIXTAR_MANIFEST=/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
```

Build or refresh the rootfs:

```sh
$MIXTAR_REBUILD build "$MIXTAR_MANIFEST"
```

Create or refresh the ext4 image file:

```sh
$MIXTAR_REBUILD image-plan "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD install-image "$MIXTAR_MANIFEST" --erase-image
```

Inspect readiness:

```sh
$MIXTAR_REBUILD image-verify "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD readiness-report "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD operator-runbook "$MIXTAR_MANIFEST"
```

Review physical install plan without changing disk state:

```sh
$MIXTAR_REBUILD physical-plan "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD grub-rollback-plan "$MIXTAR_MANIFEST"
```

Run the technical gate only when ready to inspect the live laptop state:

```sh
$MIXTAR_REBUILD preinstall-gate "$MIXTAR_MANIFEST"
```

Passing `preinstall-gate` is not approval to install. It means only that the
technical state is ready enough to ask for the destructive decision.

Recommended one-pass smoke sequence while still safe:

```sh
$MIXTAR_REBUILD qemu-plan "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD qemu-rescue-smoke "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD qemu-init-smoke "$MIXTAR_MANIFEST"
```

Expected outputs:

```text
qemu-rescue-smoke: ok
qemu-init-smoke: ok
```

## Phase 3: login decision

The manifest currently supports:

```text
MIXTAR_FIRST_USER
MIXTAR_FIRST_PASSWORD_HASH
```

If `MIXTAR_FIRST_PASSWORD_HASH` is empty, the first boot may be rescue-first or
normal login may be locked. That is acceptable only if it is intentional.

Generate a password hash on the ThinkPad:

```sh
/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-password-hash.sh
```

Apply it to the manifest without storing plaintext:

```sh
/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-set-login.sh "$MIXTAR_MANIFEST" vxz --hash-stdin
```

Then rebuild and refresh the image before physical installation.

## Phase 4: destructive physical install approval

Do not run this phase without explicit approval.

The physical installer generates a non-destructive approval packet before it
asks for the confirmation phrase. The packet path is printed and written to the
install audit log.

The required phrase is:

```text
FORMAT /dev/nvme0n1p3 AS MIXTARROOT
```

The command is:

```sh
./Server/Rootfs/tools/mixtar-physical-install.sh install "$MIXTAR_MANIFEST" --erase-device --write-grub
```

or with explicit phrase in one command:

```sh
./Server/Rootfs/tools/mixtar-physical-install.sh install "$MIXTAR_MANIFEST" --erase-device --write-grub <<'EOF'
FORMAT /dev/nvme0n1p3 AS MIXTARROOT
EOF
```

Expected destructive effects:

```text
/dev/nvme0n1p3 is formatted
Mixtar rootfs is installed there
GRUB receives Mixtar boot entries
Debian remains the rollback boot path
```

## Phase 5: first boot

After physical install:

```text
1. Reboot.
2. Select the Mixtar GRUB entry.
3. If the normal entry fails, select the Mixtar rescue entry.
4. If both fail, boot Debian rollback.
```

The OpenRC service `mixtar-firstboot-report` should run automatically during
boot. It writes:

```text
/System/Logs/firstboot-evidence.txt
/System/Logs/firstboot-report.service.log
```

Minimum first-boot evidence:

```sh
rc-service mixtar-firstboot-report status
cat /System/Logs/firstboot-report.service.log
mixtar-postboot-report
mixtar-firstboot-verify
mixtar-generation-report
cat /System/Logs/firstboot-evidence.txt
uname -a
cat /etc/os-release
mount
ls /System
readlink /System/Current
cat /System/Runtime/generation.env
ls /Applications
ls /Users
ls /Compatibility
rc-status
zsh --version
apk --version
```

Expected identity evidence:

```text
firstboot-verification=ok
Linux kernel is active
OpenRC is present
zsh is present
apk is present
/System exists
/Applications exists
/Users exists
/Compatibility exists
"/System/Current" points to active generation
`firstboot-verification=ok`
```

## Rollback rule

Debian must remain bootable until Mixtar has completed at least one successful
boot and the first-boot evidence has been captured.

Do not remove Debian boot entries during pre-v0.

## Completion condition for this runbook

The first boot objective is complete only when current evidence proves:

```text
Mixtar boots on the ThinkPad
the selected kernel boots
the installed rootfs is mounted
OpenRC can be inspected
zsh is installed
apk is installed
Mixtar layout paths exist
the active generation is visible through /System/Current
mixtar-firstboot-verify reports firstboot-verification=ok
Debian rollback remains available
```

### One-shot local flow (optional)

```sh
export MIXTAR_MANIFEST=/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
export MIXTAR_REBUILD=/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh
export MIXTAR_PHRASE="FORMAT /dev/nvme0n1p3 AS MIXTARROOT"
export MIXTAR_FIRST_BOOT=/home/vxz/mixtar-lab/repo-tools/Server/Installer/imported/Mixtar-OS-Setup/artifacts/mixtar-installer/scripts/first-boot-mixtar-t480.sh

# Safe path (non-destructive)
$MIXTAR_FIRST_BOOT --safe-only --host=192.168.99.110 --user=vxz --manifest=$MIXTAR_MANIFEST

# Optional extra validation before physical install
$MIXTAR_REBUILD qemu-plan "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD qemu-rescue-smoke "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD qemu-init-smoke "$MIXTAR_MANIFEST"
$MIXTAR_REBUILD preinstall-gate "$MIXTAR_MANIFEST"

# Physical install - still requires explicit operator phrase:
# FORMAT /dev/nvme0n1p3 AS MIXTARROOT
$MIXTAR_FIRST_BOOT --install-only --host=192.168.99.110 --user=vxz --manifest=$MIXTAR_MANIFEST --phrase="$MIXTAR_PHRASE"
```
