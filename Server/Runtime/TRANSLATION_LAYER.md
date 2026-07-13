# Mixtar Translation Layer

The Mixtar translation layer exists to build the clean local FreeBSD source
mirror against a Linux-kernel Server base without modifying mirrored FreeBSD
files.

## First Target: Source Compatibility

The first target is source-level compatibility, not binary emulation.

```text
Server/Userland/Toolkit/FreeBSD/freebsd-src
  + Server/Userland/Toolkit/Bridge
  + Server/Runtime/LibC
  -> Mixtar compatibility headers/libraries
  -> AILang-owned runtime behavior where possible
  -> selected host libc or AILang syscall boundary where still necessary
  -> native Mixtar binary
```

This is different from running unmodified FreeBSD ELF binaries. Binary ABI and
syscall emulation can be researched later, but it is not the first Server proof.

## What Gets Translated

The layer translates assumptions that FreeBSD userland code makes about its
environment:

```text
headers
constants
types
errno behavior
filesystem flags
process APIs
terminal APIs
directory/stat APIs
sysctl-like queries
ioctl differences
event APIs such as kqueue
build-system expectations
```

It does not translate every machine instruction. It does not replace the Linux
kernel.

## Security Translation

Mixtar should expose OpenBSD-shaped security APIs where upstream source expects
them, but the Linux implementation belongs in the Bridge/runtime layer:

```text
pledge(promises, execpromises)
  -> parse promise string
  -> select syscall allowlist
  -> install seccomp filter
  -> set no_new_privs before tightening

unveil(path, permissions)
  -> collect path permissions
  -> install Landlock ruleset
  -> lock ruleset when unveil(NULL, NULL) is called
```

This keeps OpenBSD-derived code readable while using Linux kernel primitives.

SELinux is not the first translation target. It can be added later as a
system-wide policy backend if Mixtar gains stable service/package profiles.

## ABI Boundary

For the first phase, "ABI" means C/source/runtime ABI where userland code meets
headers, libc, and runtime functions.

Kernel syscall ABI is handled by the selected kernel and the chosen
libc/runtime boundary. Mixtar wrappers should prefer named runtime APIs; direct
`syscall(number, ...)` use is reserved for explicit, tested ABI cases.

The preferred runtime home is:

```text
Server/Runtime/LibC
```

The Toolkit Bridge may still use C headers and shims, but reusable behavior
should migrate into `Runtime/LibC` as AILang code whenever AILang can express
the ABI cleanly. C shims are temporary boundary adapters, not the architectural
center.

Windows-style calling conventions such as `stdcall` or `fastcall` are not the
central issue for Unix userland tools. If function calling-convention gaps
appear in FFI work, they belong in AILang's C ABI layer, not in the FreeBSD
source tree.

## AILang Role

AILang should own the translation pipeline:

```text
check upstream once per day when network is enabled
update the clean local source mirror when selected files changed
scan source manifest
detect changed files
load compatibility rules
generate wrappers or build metadata
compile generated AILang/C glue
build command
run behavior tests against FreeBSD reference
report drift
```

AILang can also provide direct tool implementations where that is simpler,
but the clean-vendor policy still applies when FreeBSD source is used.

AILang should also own the Mixtar libc-shaped runtime surface over time:

```text
filesystem helpers
process helpers
stdio/write helpers
errno/status normalization
pledge/unveil shaped security wrappers
tool certification helpers
```

This does not mean copying OpenBSD libc or FreeBSD libc into Mixtar. It means
implementing the needed behavior in AILang first, then dropping to C shims only
when the current AILang ABI surface is not sufficient.

## Output Locations

Generated files belong under disposable or clearly generated locations:

```text
out/
Server/Userland/Generated/     optional later
Server/Runtime/Generated/      optional later
```

Do not write generated compatibility edits into the upstream FreeBSD source
checkout.

## Failure Classification

When a command fails to build or behaves differently, classify it as one of:

```text
missing header/type wrapper
missing constant/flag mapping
missing syscall/runtime wrapper
semantic mismatch
unsupported FreeBSD-specific feature
intentional Mixtar divergence
upstream FreeBSD behavior change
AILang compiler/runtime bug
```

The classification is part of the value of this project. It tells whether
AILang, the compatibility layer, or the architecture needs work.

Kernel/security profile:

```text
Server/Kernel/KERNEL_SECURITY_PROFILE.md
```

## Implemented Bridge Slices

### Toolkit Process Bridge

The first real process bridge slice is now present under:

```text
Server/Userland/Toolkit/Bridge/include/kvm.h
Server/Userland/Toolkit/Bridge/include/sys/proc.h
Server/Userland/Toolkit/Bridge/include/sys/sysctl.h
Server/Userland/Toolkit/Bridge/include/sys/pledge.h
Server/Userland/Toolkit/Bridge/include/sys/ucred.h
```

Purpose:

```text
OpenBSD process tools
  -> kvm_getprocs / kvm_getargv / struct kinfo_proc
  -> Linux /proc
  -> unchanged OpenBSD tool source
```

Current certified consumer:

```text
pkill
ps
```

Certification deliberately uses signal `0` so the process-discovery bridge is
exercised without terminating unrelated host processes. `ps` certification
exercises hosted process-table reads and selected `-o` formatting over Linux
`/proc`.

This bridge is not full OpenBSD kernel process semantics yet. It is a hosted
Linux `/proc` adapter sufficient for safe smoke-certified process discovery and
process listing. Bridge-internal `/proc` reads bypass user-space `unveil`
restrictions because they model the privileged kernel/process interface exposed
to OpenBSD process tools, not ordinary application file access.
Next likely consumers are:

```text
pgrep
top
w
vmstat
```

Those require broader terminal/session, kernel-statistics, and formatting
compatibility before they can be honestly certified.





