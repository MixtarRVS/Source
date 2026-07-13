# MixtarRVS install-ready packet

Generated: 20260628T201555Z
System: t480-mixtar-pre-v0

This packet records non-destructive readiness evidence only.
It does not approve installation.
It does not format the target partition.
It does not write GRUB.

## Current evidence

```text
preinstall_gate=passed
target_device=/dev/nvme0n1p3
root_label=MIXTARROOT
kernel_release=7.0.0-rc3-mixtarrvs
manifest=/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
manifest_sha256=1945baf1675095950e3a3b7d04f84542cc1894e78bcf8917c9beb3daf8c7ebef
image_path=/home/vxz/mixtar-lab/images/mixtar-pre-v0-rootfs.ext4
image_sha256=fb7f39d240ab74fcc6faef0383ef6ae4ca460727ee4aa007968e49e5005ce6bf
approval_packet=/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/approval-packets/physical-install-20260628T201406Z.md
```

## Required exact confirmation phrase

```text
FORMAT /dev/nvme0n1p3 AS MIXTARROOT
```

## Destructive command after approval only

```sh
sh /home/vxz/mixtar-lab/repo-tools/Server/Rootfs/tools/mixtar-rebuild.sh physical-install '/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf' --erase-device --write-grub
```
