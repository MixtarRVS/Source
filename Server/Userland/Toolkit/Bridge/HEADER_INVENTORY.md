# Bridge Header Inventory

The bridge headers exist only to let untouched OpenBSD/FreeBSD userland source
compile against the Mixtar Linux-hosted target. They are not a place to invent
new command semantics.

## AILang-Generated Headers

These headers are generated from `abi_headers.ail` and should not be edited by
hand:

```text
include/sys/event.h
include/sys/mac.h
include/event.h
include/imsg.h
include/capsicum_helpers.h
include/libcasper.h
include/casper/cap_fileargs.h
include/casper/cap_net.h
include/login_cap.h
include/netinet/if_ether.h
include/rpc/rpc.h
include/rpc/types.h
include/sys/_null.h
include/sys/acl.h
include/sys/capsicum.h
include/sys/cpuset.h
include/sys/dirent.h
include/sys/limits.h
include/sys/malloc.h
include/sys/tty.h
include/util.h
include/vis.h
```

Regenerate them from the MixtarRVS repository root with:

```powershell
python ..\AILang-Pure\ailang.py Server\Userland\Toolkit\Bridge\abi_headers.ail --emit-abi-headers -o Server\Userland\Toolkit\Bridge\include
```

The AILang source should pass:

```powershell
python ..\AILang-Pure\ailang.py Server\Userland\Toolkit\Bridge\abi_headers.ail --check
```

## C Headers That Should Stay C For Now

These headers are source-language machinery, not callable runtime behavior:

```text
include/bitstring.h
include/sys/tree.h
include/sys/pledge.h
```

Reasons:

```text
bitstring.h: macro-generated bitset operations
sys/tree.h: macro-generated intrusive tree declarations
sys/pledge.h: conditional static tables and OpenBSD names
```

Do not force these into AILang until the language can represent the actual
source-language macro generator cleanly. Runtime behavior may still move into
AILang; the preprocessor-facing syntax may remain C.

## Semantic Adapter Headers

These headers expose or coordinate host compatibility behavior. They may shrink
as `Server/Runtime/LibC` grows, but they are not purely declarative yet:

```text
include/mixtar_bridge_compat.h
include/kvm.h
include/libutil.h
include/readpassphrase.h
include/sys/proc.h
include/sys/sysctl.h
include/sys/mount.h
include/nl_types.h
```

Move callable behavior out of these files only when an AILang implementation is
covered by `libc-wsl` and the full toolkit certification still passes.

## Thin Include Or Type Headers

These are candidates for later abi-header generation, but they are low priority unless
they block a real source port:

```text
include/sys/msgbuf.h
include/sys/ucred.h
include/utmp.h
```

## Rule

Use AILang for bridge behavior and simple generated headers. Keep C where the
upstream C preprocessor is the actual interface.

