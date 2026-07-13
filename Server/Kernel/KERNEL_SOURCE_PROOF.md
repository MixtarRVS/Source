# Kernel Source Proof

Updated: 22.05.2026

## Status

The first MixtarRVS Server Linux-kernel source input has been acquired.

This is not a custom kernel fork. It is generated build input for the next
rootfs/boot proof.

## Selected Target

```text
target:  linux-stable
version: 7.0.9
channel: stable
source:  kernel.org
role:    first MixtarRVS Server rootfs/boot proof
```

The kernel.org page listed `7.0.9` as the latest stable release on
`2026-05-17` when this target was recorded. Debian sid is also on the `7.0.x`
kernel line, so MixtarRVS Server follows stable 7.x rather than an LTS line.

## Local Files

```text
Server/Kernel/Generated/sources/linux-7.0.9.tar.xz
Server/Kernel/Generated/sources/linux-7.0.9.tar.sign
Server/Kernel/Generated/sources/linux-7.0.9.tar.xz.sha256
Server/Kernel/Generated/src/linux-7.0.9/
```

Observed archive SHA256:

```text
ac07acdf76cf4621cc5187a2670270a1a699533c8a6b225e4878c416ad83f1c4
```

GPG signature note:

```text
signature downloaded
signature key reported by gpg: 647F28654894E3BD457199BE38DBBDC86092693E
local WSL keyring did not have the public key, so trust verification is not
complete yet
```

## Commands Used

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Kernel\kernel_source.ail --backend=c -O2 -o out\server\kernel_source.exe
out\server\kernel_source.exe fetch
out\server\kernel_source.exe verify
out\server\kernel_source.exe extract
out\server\kernel_source.exe status
```

## Validation

```text
kernel_source.ail --check: pass
C backend build: pass
fetch: pass
verify: SHA256 matches manifest, GPG trust incomplete
extract: pass
completed-exit AILang leak reports: 0 live bytes
```

## Completed Follow-Up

Do not patch the kernel.

The immediate follow-up has now been completed:

```text
minimal kernel config selection
minimal initramfs/rootfs layout
QEMU/KVM boot proof
Mixtar proof /init as first userspace
Toolkit echo check from /init
```

See:

```text
Server/Rootfs/BOOT_PROOF.md
```
