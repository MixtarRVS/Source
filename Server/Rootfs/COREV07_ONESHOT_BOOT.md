# CoreV07 One-Shot Laptop Boot Contract

Status: local artifact only.

This document defines the safe path for the first laptop boot of CoreV07.
It is not an installer and not an automated deployer.

## Local gates required before touching the laptop

Run from WSL in the MixtarRVS repository:

```sh
COREV07_AUTORETURN=1 Server/Rootfs/scripts/corev07-build-efi.sh prepare
COREV07_AUTORETURN=1 Server/Rootfs/scripts/corev07-build-efi.sh build
COREV07_AUTORETURN=1 Server/Rootfs/scripts/corev07-build-efi.sh stage
Server/Rootfs/scripts/corev07-build-efi.sh verify
COREV07_REQUIRE_AUTORETURN=1 sh Server/Rootfs/scripts/corev07-local-gate.sh
```

Required PASS evidence:

```text
CoreV07 verifier: OK
CoreV07 boot preflight: OK
EFI cmdline enables Mixtar autoreturn
EFI cmdline enables kernel panic watchdog
PID1 autoreturn watchdog is fixed at 5m
EFI provenance hash matches official EFI
```

## Artifact pair

The tested EFI artifact pair is:

```text
Server/Rootfs/Generated/corev07-root/System/EFI/MixtarRVS/0.8.efi
Server/Rootfs/Generated/corev07-root/System/EFI/MixtarRVS/0.8.efi.provenance
```

The Mixtar-native mirror paths are:

```text
/System/EFI/MixtarRVS/0.8.efi
/System/EFI/MixtarRVS/0.8.efi.provenance
```

The physical UEFI System Partition path is firmware-specific and may still need:

```text
EFI/MixtarRVS/0.8.efi
EFI/MixtarRVS/0.8.efi.provenance
```

That ESP path is firmware compatibility, not Mixtar identity.

## Laptop policy

Allowed for the first boot:

```text
copy one EFI file and its provenance file
create or reuse one MixtarRVS EFI boot entry
set BootNext only
reboot once
```

Forbidden for the first boot:

```text
leaving BootOrder changed
deleting Debian entries
running update-grub
running grub-install
formatting partitions
editing Debian packages
changing Debian kernel or initramfs
```

## Required safety behavior

The test artifact must contain:

```text
mixtar.autoreturn=1
mixtar.persist_logs=1
panic=300
```

Expected behavior:

```text
If MixtarRVS reaches PID1:
  PID1 autoreturns after 30 seconds.

If Linux panics after boot:
  panic=300 asks the kernel to reboot after 300 seconds.

If firmware hangs before the kernel starts:
  manual firmware/boot-menu recovery may still be required.
```

## Deployment sequence, manual by design

The laptop must already be booted into Debian and reachable over SSH.

Preferred controlled flow:

```sh
Server/Rootfs/scripts/corev07-oneshot-deploy.sh --target vxz@192.168.99.110
Server/Rootfs/scripts/corev07-oneshot-deploy.sh --target vxz@192.168.99.110 --apply
Server/Rootfs/scripts/corev07-oneshot-deploy.sh --target vxz@192.168.99.110 --apply --reboot
```

The first command is dry-run/read-only. The second copies the EFI artifact pair
and sets BootNext. The third starts the one-shot boot immediately.

If an existing test entry must be corrected, use:

```sh
Server/Rootfs/scripts/corev07-oneshot-deploy.sh --target vxz@192.168.99.110 --apply --replace-entry
```

The script must use:

```text
ssh BatchMode=yes
sudo -n
BootNext only
```

If the script has to create an EFI entry, efibootmgr/firmware may temporarily
insert the new entry into BootOrder. The script must restore the original
BootOrder before setting BootNext.

Do not use this flow as a permanent install process.
