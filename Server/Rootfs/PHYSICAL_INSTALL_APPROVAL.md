# MixtarRVS physical install approval checklist

Updated: 28.06.2026

This checklist separates three states that must not be confused.

## 1. Image-ready

Image-ready means the ext4 image is built and can be used as the source for a
future physical install.

Quick non-destructive state report:

```sh
mixtar-rebuild.sh readiness-report <manifest>
```

Operator runbook generated from the current manifest:

```sh
mixtar-rebuild.sh operator-runbook <manifest>
```

Required evidence:

```text
mixtar-rebuild.sh image-verify <manifest>
mixtar-rebuild.sh qemu-rescue-smoke <manifest>
mixtar-rebuild.sh qemu-init-smoke <manifest>
```

or the combined gate:

```sh
mixtar-rebuild.sh preinstall-gate <manifest>
```

Image-ready does not mean the ThinkPad partition was modified.

## 2. Login-ready

Login-ready means the first user can log in normally.

Required manifest state:

```text
MIXTAR_FIRST_USER="vxz"
MIXTAR_FIRST_PASSWORD_HASH='$6$...'
```

Safe setup command:

```sh
mixtar-password-hash.sh | mixtar-rebuild.sh set-login <manifest> vxz --hash-stdin
```

Then rebuild the image:

```sh
mixtar-rebuild.sh build <manifest>
mixtar-rebuild.sh install-image <manifest> --erase-image
mixtar-rebuild.sh preinstall-gate <manifest>
```

Do not store plaintext passwords in a manifest, runbook, shell script, or repo
file.

## 2a. Post-boot evidence (after physical install)

After a reboot to Mixtar, these non-destructive commands should be run immediately:

```sh
mixtar-firstboot-verify
mixtar-generation-report
mixtar-postboot-report
cat /System/Logs/firstboot-evidence.txt
cat /System/Logs/firstboot-report.service.log
```

Required checks:

```text
/System/Logs/firstboot-evidence.txt exists
mixtar-firstboot-verify returns firstboot-verification=ok
/System/Current exists and points to active generation
```

Keep this evidence as the acceptance signal before any deeper package-level testing.

## 3. Physical-install-approved

Physical-install-approved means the user has explicitly approved formatting the
target partition and writing the GRUB entry.

Current target:

```text
/dev/nvme0n1p3
```

Current root label:

```text
MIXTARROOT
```

Preferred final command through the main builder wrapper:

```sh
mixtar-rebuild.sh physical-install <manifest> --erase-device --write-grub
```

Required interactive phrase:

```text
FORMAT /dev/nvme0n1p3 AS MIXTARROOT
```

The wrapper runs:

```text
preinstall-gate
install-rootfs --erase-device
grub-install --write-grub
```

Rollback planning command:

```sh
mixtar-rebuild.sh grub-rollback-plan <manifest>
```

This prints manual commands for removing only the marked Mixtar GRUB block while
leaving the existing normal boot entries intact.

It also writes an audit log beside the manifest:

```text
<manifest-directory>/install-logs/physical-install-<timestamp>.log
```

Lower-level implementation:

```sh
mixtar-physical-install.sh install <manifest> --erase-device --write-grub
```

## Hard stop

Do not run the physical install command until the user explicitly approves the
destructive step.

Approval must mention the target partition or the exact confirmation phrase.
