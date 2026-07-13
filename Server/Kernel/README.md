# MixtarRVS Server Kernel

The Server track uses a Linux kernel as generated build input, not as Mixtar
source.

## Current Kernel Target

The first boot/rootfs proof uses the current stable 7.x line, not longterm/LTS:

```text
linux-stable: 7.0.9
```

The acquisition proof is recorded in:

```text
Server/Kernel/KERNEL_SOURCE_PROOF.md
```

Policy:

```text
Track kernel.org stable 7.x for MixtarRVS Server proofs.
Do not use longterm/LTS kernels unless explicitly doing a regression comparison.
```

See:

```text
Server/Kernel/Manifests/linux-kernel.json
```

## Kernel Profile Model

The kernel is not a random swappable component. It is selectable through named
Mixtar-compatible profiles.

Native layout:

```text
/System/Kernel/
  Profiles/
    workstation/
    server/
    realtime/
    debug/
  Current -> Profiles/server
```

Each profile owns:

```text
vmlinuz
initramfs.img
modules/
config
profile.json
```

The bootloader should load:

```text
/System/Kernel/Current/vmlinuz
/System/Kernel/Current/initramfs.img
```

The runtime-visible contract belongs at:

```text
/System/Runtime/kernel-profile.json
```

Do not promise arbitrary kernel swapping. A kernel is supported only if it
passes the Mixtar kernel profile contract: required syscalls, filesystem layout,
init protocol, security features, device support, and modules.

## Fetch Policy

Do not paste or edit Linux kernel source inside Mixtar source directories.

Use the generated-source location:

```text
Server/Kernel/Generated/
```

Commands:

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Kernel\kernel_source.ail --check
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Kernel\kernel_source.ail --backend=c -O2 -o out\server\kernel_source.exe
out\server\kernel_source.exe status
out\server\kernel_source.exe fetch
out\server\kernel_source.exe verify
out\server\kernel_source.exe extract
```

Equivalent direct WSL command:

```text
wsl.exe -d Debian -- bash Server/Kernel/scripts/kernel_fetch.sh all
```

The current local source state can be checked with:

```text
out\server\kernel_source.exe status
```

## Build And Boot Proof

After source acquisition, do not start patching the kernel.

Prepare the first QEMU/KVM proof config:

```text
wsl.exe -d Debian -- bash Server/Kernel/scripts/prepare_config.sh
```

Build the proof kernel when ready:

```text
wsl.exe -d Debian -- bash Server/Kernel/scripts/build_bzimage.sh
```

The next proof is:

```text
kernel source present: done
minimal config selected: done
initramfs/rootfs assembled: done
QEMU/KVM boot reaches Mixtar /init: done
```

Kernel patches are explicitly out of scope until the rootfs/boot proof shows a
measured reason.

The boot proof is recorded in:

```text
Server/Rootfs/BOOT_PROOF.md
```
