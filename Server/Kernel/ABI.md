# Linux Kernel ABI Notes

MixtarRVS Server uses the Linux kernel for the first Server base.

Do not start by downloading and reading the whole Linux kernel source tree.
Start from the stable user/kernel boundary actually needed by Toolkit tools.

For kernel configuration, virtualization, low-latency, and security policy,
read:

```text
Server/Kernel/KERNEL_SECURITY_PROFILE.md
```

## First Boundary

The first ABI boundary is:

```text
Toolkit tool source
  -> Mixtar Bridge headers/runtime
  -> libc or minimal runtime boundary
  -> Linux syscalls
  -> Linux kernel
```

For early tools, prefer the libc/POSIX surface first. Direct syscalls should be
added only when the runtime needs them.

Security compatibility also starts above the raw syscall-number layer:

```text
pledge -> seccomp wrapper/runtime profile
unveil -> Landlock wrapper/runtime profile
capability policy -> Linux capabilities + no_new_privs
```

SELinux is not part of this first ABI boundary. Treat it as a later policy
system, not as the first compatibility mechanism.

## Reference Priority

Use Linux ABI references in this order:

```text
1. local Linux UAPI/libc headers for the actual build target
2. POSIX/man-pages when a Toolkit tool only needs portable behavior
3. Linux kernel syscall tables when a direct syscall is truly required
4. generated public lookup tables for cross-checking and review
```

Do not hard-code syscall numbers from a website directly into MixtarRVS unless
the target architecture, kernel version/source, and lookup reference are recorded
in a manifest.

## Useful Lookup Tables

- Filippo Valsorda Linux syscall table:
  `https://filippo.io/linux-syscall-table/`
  Good for quick x86-64 syscall name/number/signature lookup.
- Mebeim/Systrack syscall table:
  `https://syscalls.mebeim.net/?table=x86/64/x64/latest`
  Good for generated syscall metadata, version comparison, and multi-arch
  cross-checking.
- Systrack source:
  `https://github.com/mebeim/systrack`
  Useful when the generator/source path matters more than the rendered table.

These tables are engineering references. They are not the single source of
truth for the Mixtar Bridge.

## Bridge Rule

Prefer libc/POSIX wrappers first. Use direct syscall numbers only when:

```text
no suitable libc/POSIX surface exists
the target architecture is fixed in a manifest
the syscall number source is recorded
errno/result mapping is tested
the behavior is covered by a Toolkit comparison test
```

## Read First

Initial topics to document before implementation:

```text
process: fork, execve, wait, exit
files: openat, read, write, close, statx/newfstatat, getdents64
dirs: mkdirat, unlinkat, renameat2 where available
cwd: getcwd, chdir
time: clock_gettime
terminal: ioctl surface used by tools
signals: signal numbers and basic handling
errors: errno mapping
```

## Do Not Do Yet

Postpone:

```text
custom syscall table generator
raw kernel headers as the primary API
kernel module work
network stack replacement
Wi-Fi stack replacement
filesystem driver work
mandatory SELinux policy
systemd integration
```

Use the Linux kernel source only when a Bridge gap proves that public
documentation and libc headers are not enough.

## Controlled Kernel Source Acquisition

The first Server boot/rootfs proof may use a pinned kernel.org source tarball,
but it must remain generated build input:

```text
Server/Kernel/Manifests/linux-kernel.json
Server/Kernel/kernel_source.ail
Server/Kernel/scripts/kernel_fetch.sh
Server/Kernel/Generated/
```

Current pinned proof target:

```text
linux-stable 7.0.9
```

MixtarRVS Server follows the current stable 7.x line for Debian-sid-like
freshness. Do not use longterm/LTS kernels as the default proof target.

Do not edit this source tree as Mixtar source. If kernel changes are ever
needed, record them as explicit patches/manifests after a measured boot/runtime
need exists.
