# MixtarRVS install-ready packet

Generated: 20260628T200653Z
Host: MixtarRVS
Kernel: 7.0.0-rc3-mixtarrvs

## Current evidence

```text
preinstall_gate=ok
image_verify=ok
qemu_rescue_smoke=ok
qemu_init_openrc_smoke=ok
ssh_snapshot_saved=yes
remote_access_in_rootfs=openssh+iwd+dhcpcd+authorized_keys
```

## Target disk

```text
NAME        PATH             SIZE TYPE FSTYPE LABEL      UUID                                 MOUNTPOINTS MODEL
sda         /dev/sda           0B disk                                                                    SD/MMC
zram0       /dev/zram0       3.8G disk swap              08518778-565c-46bd-b04d-1fd87f6d3d06 [SWAP]      
nvme0n1     /dev/nvme0n1   238.5G disk                                                                    INTEL SSDPEKKF256G8L
├─nvme0n1p1 /dev/nvme0n1p1   976M part vfat              F70B-FE60                            /boot/efi   
├─nvme0n1p2 /dev/nvme0n1p2 229.6G part ext4              146fa690-7146-406a-be59-d955c4127401 /           
└─nvme0n1p3 /dev/nvme0n1p3   7.9G part ext4   MIXTARROOT 361af464-c78b-4bff-8b38-23624cc9066a             
```

## Manifest

```text
/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/t480-pre-v0.mixtar.conf
```

## Image

```text
path=/home/vxz/mixtar-lab/images/mixtar-pre-v0-rootfs.ext4
dfe4db1b957ca3e974f009d25b8396eb9f7f8f25081fd073ec9759734acc3abf  /home/vxz/mixtar-lab/images/mixtar-pre-v0-rootfs.ext4
-rw-rw-r-- 1 vxz vxz 512M Jun 28 22:03 /home/vxz/mixtar-lab/images/mixtar-pre-v0-rootfs.ext4
```

## Latest approval packet

```text
/home/vxz/mixtar-lab/repo-tools/Server/Rootfs/manifests/approval-packets/physical-install-20260628T200333Z.md
```

## Required phrase

```text
FORMAT /dev/nvme0n1p3 AS MIXTARROOT
```

## Destructive install command

```sh
cd /home/vxz/mixtar-lab/repo-tools
printf '%s
' 'FORMAT /dev/nvme0n1p3 AS MIXTARROOT' | sh Server/Rootfs/tools/mixtar-rebuild.sh physical-install Server/Rootfs/manifests/t480-pre-v0.mixtar.conf --erase-device --write-grub
```

## Post-boot watcher

```sh
cd /home/vxz/mixtar-lab/repo-tools
sh Server/Rootfs/tools/mixtar-postboot-watch.sh --host=192.168.99.110 --user=vxz
```
