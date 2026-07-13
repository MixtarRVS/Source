# Mixtar LibC

`Server/Runtime/LibC` is the AILang-first runtime bridge between Mixtar
userland code and the Linux kernel substrate.

It is not a copy of OpenBSD libc, FreeBSD libc, musl, or glibc. It is the place
where Mixtar gradually collects the libc-shaped behavior it needs while keeping
upstream OpenBSD/FreeBSD source mirrors unmodified.

## Role

```text
OpenBSD/FreeBSD-derived Toolkit source
  -> Toolkit/Bridge compatibility headers
  -> Runtime/LibC AILang-owned behavior
  -> temporary C shims only where AILang cannot express the boundary yet
  -> kernel ABI through the selected host libc or AILang syscall path
```

## Policy

Prefer this order:

```text
AILang implementation
AILang-generated C with strict ABI checks
small C shim for missing AILang boundary
host libc call
AILang syscall() only when the ABI is explicit and tested
```

Portable Mixtar code should use AILang's named builtins directly where they
already exist, such as `getpid()`, `getuid()`, `errno_get()`, `errno_clear()`,
`fd_open()`, `fd_read()`, `fd_write()`, and `fd_close()`.

Do not add `mixtar_`-prefixed pass-through wrappers around existing AILang
builtins. A wrapper belongs here only when it implements one of these things:

```text
real C/POSIX ABI symbol
real OpenBSD/FreeBSD semantic adapter
real kernel portability policy
real safety/security boundary
```

Naming rule:

```text
public C/POSIX/BSD ABI symbol: exact upstream name, e.g. strlcpy
AILang-owned internal libc helper: libc_<name>, e.g. libc_strlcpy
Mixtar product/policy API: system_<name> or a documented high-level API
avoid: mixtar_<name> inside LibC unless the public API is explicitly Mixtar-specific
```

Symbolic syscall names belong in the AILang/Mixtar runtime API layer, not in
application code that should work across kernels.

Do not grow a permanent pile of random C adapters in `Toolkit/Bridge/shims`.
Each C shim must have one of these states:

```text
temporary-boundary
waiting-for-ailang-abi
waiting-for-direct-syscall
retained-for-host-libc-interoperability
```

## Non-Goals

```text
do not fork OpenBSD libc in place
do not fork FreeBSD libc in place
do not turn Mixtar into GNU/glibc
do not hide semantic differences behind silent wrappers
do not promise full POSIX/libc coverage before tests exist
```

## First Surface

The first surface is intentionally small:

```text
direct use of AILang process/status/fd builtins
pledge/unveil shaped security API
errno/status normalization only where semantics differ
tool certification helpers
```

The goal is not to make a giant libc immediately. The goal is to make every
new bridge decision land in a stable, testable runtime layer instead of being
scattered across tool-specific hacks.

## First ABI Slice

`Source/unistd.ail` is the first real ABI slice. It uses AILang's contextual
`internal` ABI boundary form to emit C-callable symbols with hosted libc-shaped
signatures:

```text
read
write
close
fsync
fdatasync
getpid
getppid
getuid
geteuid
getgid
getegid
gettid
getpgid
getpgrp
setsid
```

This is intentionally a Linux x86_64 syscall proof, not a complete POSIX
`unistd.h`. The syscall numbers are isolated in one AILang source file so the
ABI table can later be generated per kernel/architecture instead of scattered
through application code.

The public ABI now uses C/POSIX names where the boundary requires them:

```text
ssize_t read(int fd, void *buf, size_t count)
pid_t getpid(void)
uid_t getuid(void)
gid_t getgid(void)
```

Inside the AILang body those names lower to ordinary AILang integer/pointer
types. Do not use AILang's historical `int`/`short` names as ordinary C ABI
type aliases outside `internal` declarations. `int` is AILang's 64-bit integer,
and `short` is not a C `short` in the current type ladder. Use fixed-width
types or an `internal` boundary declaration when ABI width matters.

## Toolkit Adapter Slices

`Source/df_raw_stubs.ail` replaces the previous handwritten C shim for OpenBSD
`df` raw filesystem probes:

```text
e2fs_df
ffs_df
```

Those functions intentionally return `-1` on the hosted Linux target. OpenBSD
raw FFS/ext2 device inspection is a kernel/filesystem feature, while the
current Linux Toolkit proof certifies mounted filesystem paths.

The Toolkit build driver emits this AILang file to:

```text
Server/Runtime/LibC/Generated/df_raw_stubs.c
```

before compiling `df` under WSL.

`Source/md5_end.ail` replaces the previous handwritten C `MD5End` helper used
by OpenBSD `sort -R`:

```text
MD5End
```

The MD5 algorithm itself remains upstream OpenBSD source. The AILang file only
formats the final 16-byte digest as a 32-character lowercase hex string and
allocates the output buffer when the caller passes `NULL`, matching the helper
shape expected by OpenBSD `sort`.

The Toolkit build driver emits this AILang file to:

```text
Server/Runtime/LibC/Generated/md5_end.c
```

before compiling `sort` under WSL.

`Source/string.ail` provides AILang-owned BSD string helpers:

```text
libc_strlcpy
libc_strlcat
strlcpy
strlcat
```

The public `strlcpy` / `strlcat` symbols are emitted directly from AILang using
the contextual `internal` ABI boundary form:

```ailang
internal size_t strlcpy(dst: internal charptr, src: internal cstring, dstsize: internal size_t):
    ...
end
```

That syntax lowers to AILang's `@cabi(...)` metadata internally. The
implementation still uses normal `pointer`/integer types; exact C spellings
such as `char *`, `const char *`, and `size_t` are allowed only at the exported
ABI boundary.

Validation:

```text
Source/string.ail --check
Generated/string.c + Tests/string_smoke.c
strict C23 WSL build
string_smoke: ok
```

`Source/stdio.ail` provides the first AILang-owned `FILE *` ABI slice:

```text
fparseln
fpurge
```

This slice deliberately covers only stdio helpers that can be expressed without
peeking into host `FILE` internals. `fparseln` uses hosted `getline()` through
exact ABI casts and returns the heap-owned line expected by BSD callers.
`fpurge` is currently an output-stream flush equivalent through `fflush()`.

Still retained in the C bridge for now:

```text
fgetln
fgetwln
readpassphrase
fopen path interposition
```

Those helpers need persistent stream-local caches, wide-character conversion,
terminal policy, or macro interposition. Moving them requires a managed stream
cache or a deliberate retained host-stdio adapter, not a fake AILang wrapper.

Validation:

```text
Source/stdio.ail --check
Generated/libc_stdio.c + Tests/stdio_smoke.c
strict C23 WSL build
stdio_smoke: ok
```

`Source/bsd_compat.ail` owns the callable BSD/POSIX compatibility functions
that no longer need handwritten static inline C in the Toolkit bridge:

```text
setlogin
revoke
issetugid
logwtmp
isduid
getrtable
setpassent
setgroupent
chflags
lchflags
fchflags
chflagsat
lpathconf
undelete
strmode
getbsize
setmode
getmode
strtonum
fflagstostr
strtofflags
recallocarray
freezero
caph_limit_stdio
caph_enter
caph_cache_catpages
caph_enter_casper
caph_rights_limit
cap_init
cap_close
cap_service_open
fileargs_cinit
cap_net_limit_init
cap_net_limit_name2addr_family
cap_net_limit
login_getclass
login_close
login_getcapbool
login_getcapnum
login_getcapsize
login_getcapstr
login_getcaptime
login_getstyle
setclasscontext
setusercontext
acl_get_fd_np
acl_get_link_np
acl_set_fd_np
acl_is_trivial_np
acl_is_trivial
acl_free
acl_supported
mac_prepare_file_label
mac_get_file
mac_get_link
mac_to_text
mac_free
kqueue
kevent
vis
strvis
strnvis
strvisx
strnvisx
stravis
stravisx
strunvis
strnunvis
unvis
```

The Toolkit bridge still keeps C headers for the parts AILang should not fake
yet:

```text
preprocessor macros
compile-time endian selection
varargs interposition
FILE * helpers
host libc struct layouts
tree/bitset generator macros
exact C ABI corner cases not expressible by AILang internal declarations yet
```

That is the current reduction rule: callable adapters move to AILang; C remains
only for header-language mechanics or unexpressed ABI boundaries.

## Validation

Minimum validation for AILang-owned LibC files:

```text
ailang --check
C backend build
LLVM backend build where supported
completed-exit leak report
Toolkit certification that consumes the API
```

Canonical userland-facing LibC gate:

```text
out/server/toolkit_build.exe libc-wsl
```

This rebuilds the known AILang-owned LibC slices, emits their C/header outputs,
strict-compiles hosted C consumers under WSL, and runs the current smoke set:

```text
unistd_smoke
df_raw_stubs_smoke
md5_end_smoke
string_smoke
stdio_smoke
bsd_compat_smoke
```

Passing this gate means the AILang LibC layer still links and behaves for the
current translated userland surface. It does not replace full Toolkit
certification for individual commands.

AILang's fd builtins use portable fd flags:

```text
1  read
2  write
4  create
8  truncate
16 append
```

Example validation:

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py libc_surface.ail --check
```

Useful ABI proof:

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py Source\unistd.ail --emit-header -o Generated\unistd.h
python C:\Users\V\source\repos\AILang-Pure\ailang.py Source\df_raw_stubs.ail --emit-c -o Generated\df_raw_stubs.c
generate Source\unistd.ail to C
compile generated C to an object
link Tests\unistd_smoke.c against that object on Linux/WSL
run the smoke executable
```

