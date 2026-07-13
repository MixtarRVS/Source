# MixtarRVS Server Kernel and Security Profile

MixtarRVS Server is hypervisor-first, but not kernel-rewrite-first.

The first production-shaped base should use a Linux kernel configured for:

```text
virtualization
low-latency scheduling
service isolation
OpenBSD-style security compatibility
minimal non-GNU userland
```

The goal is to make Mixtar feel like a controlled server platform without
turning the first phase into a custom kernel, SELinux policy distribution, or
systemd clone.

## Source Of Truth

```text
Hardware
  Linux kernel
    virtualization + isolation + low-latency profile
      Mixtar init/runtime
        OpenBSD-first Toolkit
        AILang tools
        pledge/unveil compatibility
```

RVS/FreeBSD remains the lab/reference environment. Server is the strategic
system base.

## Init Decision

Use one of these for the first bootable Server image:

```text
preferred v0: AILang-owned minimal init/supervisor
acceptable v0: OpenRC-style init model
postponed: systemd as PID 1
```

OpenRC-style init is enough for the first Server proof because it gives clear
service ordering, readable scripts, and small surface area.

Systemd is not banned forever, but it is bloat for the current phase. It should
only be reconsidered if Mixtar needs broad Linux ecosystem service compatibility
more than it needs a small, auditable base.

## Security Decision

SELinux is optional later, not required now.

First security layer:

```text
OpenBSD pledge API  -> Linux seccomp filter profile
OpenBSD unveil API  -> Linux Landlock filesystem rules
capability dropping -> Linux capabilities
no privilege growth -> PR_SET_NO_NEW_PRIVS
resource limits     -> rlimit/cgroup policy
service isolation   -> namespaces + cgroups
```

This gives Mixtar the developer-facing OpenBSD model while using Linux kernel
features that already exist.

SELinux becomes relevant only after:

```text
base Toolkit works
init/supervisor works
services have stable profiles
package/install policy exists
filesystem labeling policy can be generated and tested
```

Do not block Toolkit or init work on SELinux.

## Required Kernel Feature Classes

Virtualization/hypervisor base:

```text
KVM
KVM_INTEL or KVM_AMD
VFIO
VFIO_PCI
IOMMU_SUPPORT
INTEL_IOMMU or AMD_IOMMU
VHOST_NET
TUN
BRIDGE
```

Isolation/security base:

```text
SECCOMP
SECCOMP_FILTER
SECURITY_LANDLOCK
NAMESPACES
USER_NS
PID_NS
NET_NS
IPC_NS
UTS_NS
CGROUPS
CGROUP_BPF
BPF
BPF_SYSCALL
POSIX_MQUEUE
KEYS
```

Low-latency/RTOS-like base:

```text
HIGH_RES_TIMERS
PREEMPT_DYNAMIC or PREEMPT_RT
IRQ_FORCED_THREADING where available
NO_HZ_IDLE baseline
NO_HZ_FULL optional for isolated CPU profiles
RCU_NOCB_CPU optional for isolated CPU profiles
CPU_FREQ_GOV_PERFORMANCE
```

Diagnostics/audit:

```text
AUDIT optional
SECURITYFS
DEBUG_FS optional for development images only
FTRACE optional for development images only
```

SELinux:

```text
SECURITY_SELINUX optional later
SECURITY_SELINUX_BOOTPARAM optional later
```

## Runtime Profiles

Mixtar should eventually ship named kernel/runtime profiles instead of one
opaque configuration.

```text
server-default:
  virtualization enabled
  seccomp/Landlock enabled
  normal low-latency preemption
  no SELinux requirement

server-rt:
  virtualization enabled
  PREEMPT_RT or strongest available preemption
  threaded IRQs
  optional CPU isolation
  used only when latency measurement proves the need

server-secure:
  seccomp/Landlock enforced
  strict capability dropping
  cgroup/namespaces for services
  SELinux still optional until policy exists

dev:
  debugfs/ftrace available
  broader logging
  not the release profile
```

## Filesystem Profile Location

Profiles are selected through the native Mixtar layout:

```text
/System/Kernel/
  Profiles/
    workstation/
    server/
    realtime/
    debug/
  Current -> Profiles/server
```

Each profile must carry:

```text
vmlinuz
initramfs.img
modules/
config
profile.json
```

The active runtime contract is exposed as:

```text
/System/Runtime/kernel-profile.json
```

This is the compatibility boundary. Userland should depend on the declared
profile, not on guessing which kernel happened to boot.

## What Is Bloat Right Now

Do not add these as phase blockers:

```text
systemd as PID 1
SELinux as mandatory policy
custom Linux kernel patches
custom hypervisor
FreeBSD network stack port
OpenBSD Wi-Fi stack port
ZFS/jails/bhyve ports
```

These are future research items, not the next implementation step.

## Next Implementation Order

```text
1. Keep expanding/certifying OpenBSD-first Toolkit coverage.
2. Add Mixtar init/supervisor proof.
3. Add Linux seccomp wrapper for pledge-style promises.
4. Add Linux Landlock wrapper for unveil-style path rules.
5. Add per-tool/per-service sandbox manifests.
6. Build minimal Linux rootfs with Server kernel profile.
7. Measure boot time, command latency, memory use, and isolation failures.
8. Revisit SELinux/systemd only with evidence.
```
