# Toolkit Bridge

The Bridge is the allowed Mixtar adaptation layer for clean mirrored FreeBSD
Toolkit source.

It exists inside `Toolkit/` because it is part of the Toolkit build model, but
it must never edit `Toolkit/FreeBSD/freebsd-src`.

## Job

The Bridge translates source/runtime expectations:

```text
FreeBSD headers/constants/types
FreeBSD build assumptions
FreeBSD libc/runtime calls
FreeBSD filesystem/process/terminal behavior
```

into a Linux-kernel target through:

```text
compatibility headers
compatibility libraries
AILang-generated glue
Runtime/LibC AILang helpers
build recipes
behavior reports
```

Current common compatibility header:

```text
include/mixtar_bridge_compat.h
```

It is injected with `-include` so the Bridge does not shadow libc headers. Keep
tool-specific compatibility decisions recorded in `Generated/reports/*-gap.md`.

Reusable runtime behavior belongs in:

```text
Server/Runtime/LibC
```

AILang-owned generated bridge headers live in:

```text
Toolkit/Bridge/abi_headers.ail
Toolkit/Bridge/HEADER_INVENTORY.md
```

Regenerate those headers from the repository root with:

```powershell
python ..\AILang-Pure\ailang.py Server\Userland\Toolkit\Bridge\abi_headers.ail --emit-abi-headers -o Server\Userland\Toolkit\Bridge\include
```

`Bridge/shims` is allowed, but it should stay small. A C shim is acceptable only
when it is a clear ABI boundary that AILang cannot express yet, or when it is
temporary scaffolding for a certified tool.

Current direction: if a shim is only a C-callable function with fixed-width
arguments and straightforward behavior, implement it in `Server/Runtime/LibC`
as AILang and let the Toolkit driver generate the C source. `df` raw filesystem
fallbacks, `sort`'s `MD5End` helper, BSD string helpers, and the shared
`bsd_compat` callable adapter set, and the first stdio/`FILE *` helpers now
follow this path.

Do not move C preprocessor mechanics into AILang by pretending they are normal
functions. The ABI header generator now handles simple conditional blocks,
`include_next`, variadic prototypes/macros, and small `static inline` helpers.
Keep the remaining source-language machinery in bridge headers until AILang has
a real replacement:

```text
tree/bitset generator macros
remaining FILE * helpers with stream cache or terminal policy requirements
host libc struct layout adapters
open/stat/fopen macro interposition
exact C ABI edge cases that AILang cannot spell yet
```

The bridge target is not "zero C at any cost". The bridge target is:

```text
0 handwritten C for callable adapters that AILang can express
AILang-generated headers for simple constants/types/prototypes/macros
minimal handwritten C headers for C preprocessor source-language compatibility
upstream OpenBSD/FreeBSD source remains untouched
```

The current purity inventory and remaining AILang feature blockers are tracked
in:

```text
Toolkit/Bridge/BRIDGE_PURITY.md
Toolkit/Bridge/HEADER_INVENTORY.md
```

Current certified `setmode/getmode` subset:

```text
octal modes, e.g. 700, 755
explicit symbolic who: u, g, o, a
operators: +, -, =
permissions: r, w, x, X
```

Current uncertified mode grammar:

```text
symbolic copy permissions: u, g, o as permission operands
setuid/setgid/sticky symbolic forms: s, t
umask-sensitive omitted-who edge cases
```

## Strict Gate

Nothing should be promoted into `Server/Userland/Tools/` until it passes the
strict translated build gate:

```text
-std=c23
-Wall
-Wextra
-Werror
-pedantic
```

and the equivalent AILang gates:

```text
ailang --check
AILang C backend build
AILang LLVM backend build where supported
completed-exit leakcheck
FreeBSD behavior comparison where available
```

`Tools/` is for Mixtar-owned implementations, adapters, or promoted outputs.
It is not where raw upstream FreeBSD source is edited.

## First Bridge Outputs

The preferred build entrypoint is:

```text
Toolkit/Bridge/toolkit_build.ail
```

It checks known mirrored tools, writes generated reports/plans, and builds
Linux target outputs through WSL on a Windows development host:

```powershell
out/server/toolkit_build.exe status all
out/server/toolkit_build.exe build-wsl all
out/server/toolkit_build.exe test-wsl all
out/server/toolkit_build.exe libc-wsl
out/server/toolkit_build.exe certify-wsl all
out/server/toolkit_build.exe coverage
out/server/toolkit_build.exe build-wsl echo
```

`echo_bridge.ail` is kept as the first worked example. New tools should go
through `toolkit_build.ail` unless they need a special one-off investigation.

The generated outputs are:

```text
Generated/reports/<tool>-gap.md
Generated/reports/<tool>-compat.md
Generated/certification/<tool>.md
Generated/build/<tool>/
Generated/tests/<tool>-compat.sh
Generated/targets/<target-triple>/bin/
```

On Windows, WSL may be used as the Linux build executor. The Bridge driver
should generate into `Generated/targets/linux-x64/bin/` first. Do not promote
that output into `Tools/` until behavior comparison passes.

`test-wsl` compares generated tools with WSL-native tools for smoke parity. It
does not replace FreeBSD behavior certification. Where GNU/Linux behavior
differs from FreeBSD behavior, Mixtar follows the FreeBSD Toolkit contract unless
a later explicit compatibility mode says otherwise.

`libc-wsl` is the fast gate for AILang-owned Runtime/LibC work. Run it whenever
Bridge C code is moved into AILang or a LibC ABI helper changes. It performs:

```text
ailang --check for known LibC slices
AILang C/header emission
strict WSL C23 compile of C consumers
smoke execution against generated Runtime/LibC outputs
```

`certify-wsl` is the canonical rerunnable proof for the current hosted Linux
surface. It performs build + test and writes `Generated/certification/*.md`.
Certification means "passes the documented surface", not "all possible FreeBSD
edge cases are complete".

`coverage` regenerates `Generated/reports/toolkit-certified-coverage.md` from
the selected-tool manifest, generated target directory, certification reports,
and gap reports. Use it after changing the selected userland surface, hosted
placeholder list, or generated certification outputs.

Each gap report should classify failures as:

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

