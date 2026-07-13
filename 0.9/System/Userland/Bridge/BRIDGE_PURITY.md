# Bridge Purity Target

The long-term target is:

```text
upstream OpenBSD/FreeBSD source: unchanged
callable compatibility behavior: AILang
C bridge headers: reduced to source-language mechanics only
```

`100% AILang bridge` does not mean deleting every C header tomorrow. The
mirrored userland is still C source, so the build needs C preprocessor-visible
types, macros, constants, and declarations. The correct target is to eliminate
handwritten C behavior, not to pretend C source can compile without C header
syntax.

## Current AILang-Owned Behavior

`Server/Runtime/LibC/Source/bsd_compat.ail` now owns these bridge-callable
surfaces:

```text
BSD login/session stubs
Capsicum helper stubs
Casper channel/fileargs/net limit stubs
ACL stubs
MAC label stubs
kqueue/kevent stubs
vis/strvis/strunvis copy adapters
mode/string/flag helpers
recallocarray/freezero
strtonum
setmode/getmode
FILE * helpers that do not inspect host FILE internals: fparseln, fpurge
```

The related bridge headers now mostly expose prototypes and constants.

## Current AILang-Owned Headers

`Toolkit/Bridge/abi_headers.ail` now owns the simple generated ABI header
surface for:

```text
sys/event.h
sys/mac.h
event.h
imsg.h
capsicum_helpers.h
libcasper.h
casper/cap_fileargs.h
casper/cap_net.h
login_cap.h
netinet/if_ether.h
rpc/rpc.h
rpc/types.h
sys/_null.h
sys/acl.h
sys/capsicum.h
sys/cpuset.h
sys/dirent.h
sys/limits.h
sys/malloc.h
sys/tty.h
util.h
vis.h
```

This is intentionally not the whole bridge. It covers includes, include_next
wrappers, conditional defines, constants, typedefs, structs, prototypes,
variadic prototypes/macros, small macro wrappers, and small static inline
helpers. Macro-generator headers and host-layout adapters remain documented in
`HEADER_INVENTORY.md`.

## Remaining C Categories

These are the remaining categories that block a literal zero-C bridge:

```text
1. Preprocessor-only APIs
   Examples: bitstring.h, sys/tree.h, EV_SET, timespec macros.
   Needed AILang feature: generated C-header macro surface or a source-to-source
   preprocessing replacement.

2. Varargs ABI and macro interposition beyond header-only helpers
   Examples: open/openat wrappers, warnc/errc.
   Current status: ABI header generation can spell variadic prototypes/macros
   and static inline varargs helpers, but AILang exported runtime functions are
   still fixed-ABI.
   Needed AILang feature: exported C varargs or generated macro wrappers that
   call AILang fixed-ABI functions safely.

3. FILE * and stdio internals
   Moved: fparseln, fpurge.
   Remaining examples: fgetln, fgetwln, readpassphrase, fopen interposition.
   Needed AILang feature: stream-local cache/lifetime support, terminal policy,
   macro interposition, or a small retained host-libc adapter layer.

4. Host struct layout adapters
   Examples: statfs/statvfs, sysctl clockinfo/message-buffer structs, kvm proc
   structs.
   Needed AILang feature: exported C structs/layout declarations or generated
   C adapters around AILang logic.

5. Host libc calls requiring exact signatures
   Examples: realpath, getaddrinfo, connect, statvfs, sysconf, readlink.
   Needed AILang feature: typed extern C declarations with exact pointer/struct
   signatures, not generic integer-only bindings.

6. Collision-sensitive upstream symbols
   Example: mbsavis is defined by some upstream source files, so the bridge must
   keep it header-local instead of exporting one global symbol.
   Needed AILang feature: weak symbols or per-tool conditional export control.
```

## Implementation Rule

Move code from C to AILang only when all are true:

```text
the behavior is callable, not just preprocessor syntax
the ABI can be represented exactly enough by AILang internal declarations
the generated symbol does not collide with upstream source
the LibC WSL gate covers it
the full toolkit certification still passes
```

If any condition fails, keep the C as a small, documented header adapter until
AILang grows the missing boundary feature.

## Current Proof Commands

```powershell
.\out\server\toolkit_build.exe libc-wsl
.\out\server\toolkit_build.exe certify-wsl all
.\out\server\toolkit_build.exe verify-upstream
```

Current latest validation after the bridge reduction:

```text
libc-wsl: PASS
certify-wsl all: PASS
```

