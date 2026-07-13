# Toolkit Mirror

MixtarRVS Server keeps local clean mirrors of selected OpenBSD and FreeBSD userland/toolkit
source used for tool builds and behavior reference.

This is not a fork.

The mirror is an input cache. Mixtar changes live outside it.

## What The Toolkit Is

The Toolkit is the base layer that makes the system usable above the kernel.

It is larger than "commands":

```text
core tool sources
shell-facing behavior contracts
headers and constants expected by imported source
small libc/runtime compatibility assumptions
filesystem/process/terminal behavior wrappers
build manifests
translation metadata
generated glue
behavior tests
update reports
```

Mixtar-owned tools may live beside this mirror, but the mirror itself is clean
input.

## Intended Local Layout

Use a clearly separated layout:

```text
Server/Userland/
  Toolkit/              clean mirrored upstream toolkit source subsets
    OpenBSD/
      src/
        bin/
        sbin/
        usr.bin/
        usr.sbin/
        lib/
        libexec/
        include/
    FreeBSD/
      freebsd-src/
        bin/
        usr.bin/
    Bridge/
      compatibility headers, libraries, and build adapters
  Manifests/
    openbsd-src.json
    freebsd-src.json
    selected-tools.json
    upstream-policy.json
  Generated/
    wrappers/
    build/
    reports/
  Tools/
    AILang-native tools, adapters, and Mixtar-owned replacements
  Tests/
    behavior comparisons
```

The architectural name is `Server/Userland/`.

## Hard Rule

Do not modify files inside `Server/Userland/Toolkit/OpenBSD/` or `Server/Userland/Toolkit/FreeBSD/`.

Forbidden:

```text
editing Server/Userland/Toolkit/OpenBSD/src/bin/pwd/*.c
editing Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/ls/*.c
editing Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/cat/*.c
committing patched OpenBSD/FreeBSD source as Mixtar source
```

Allowed adaptation locations:

```text
Server/Runtime/
Server/Userland/Toolkit/Bridge/
Server/Userland/Manifests/
Server/Userland/Generated/
Server/Userland/Tools/
Server/Userland/Tests/
out/
compatibility headers
compatibility libraries
translation manifests
build recipes
```

## Daily Update Model

If network is enabled, Mixtar can check once per day for upstream OpenBSD/FreeBSD source
updates.

Flow:

```text
1. Read last known upstream revision from manifest.
2. Query upstream OpenBSD/FreeBSD source metadata.
3. If no selected files changed, continue with existing local mirror.
4. If selected files changed, fetch only the changed files or commit delta.
5. Update the local clean mirror.
6. Mark "there is an update" for affected tools.
7. Regenerate Mixtar translation/build metadata.
8. Rebuild affected Linux-target tool outputs.
9. Run behavior comparisons against the selected upstream reference target when available.
10. Write an update report.
```

No network means no update check. Existing mirrored source and compiled outputs
continue to be used.

## Manifest State

The mirror must track:

```text
upstream remotes
upstream branch/tag
last checked time
last imported commit/revision
selected source files
hash of every selected file
tool-to-source dependency map
last successful build per tool
last behavior comparison result per tool
```

## Current Batch State

Current sparse mirror scope:

```text
OpenBSD userland-only roots:
  bin, sbin, usr.bin, usr.sbin, lib, libexec, include

Removed from the OpenBSD mirror:
  gnu, sys, regress, distrib, share, etc, games

FreeBSD sparse userland roots:
  bin, usr.bin

FreeBSD root build metadata and embedded .git data are not part of the mirror.
```

Current certified smoke tool count and common-command coverage are canonical in:

```text
Server/Userland/Generated/reports/toolkit-certified-coverage.md
```

Current discovery command:

```text
out/server/toolkit_build.exe probe-auto-wsl
```

Discovery reports strict-compile candidates and blockers here:

```text
Server/Userland/Generated/reports/toolkit-auto-probe-wsl.md
```

This lets Mixtar answer:

```text
What changed upstream?
Which tools are affected?
What needs rebuilding?
What still matches selected upstream behavior?
What broke in the translation layer?
```

## Update Report

Each upstream change should produce a report such as:

```text
OpenBSD/FreeBSD source update detected
upstream: openbsd/src master <commit> or freebsd/freebsd-src main <commit>
changed:
  bin/ls/ls.c
  bin/ls/print.c
affected Mixtar tools:
  ls
action:
  mirror updated
  wrappers regenerated
  build passed
  behavior comparison passed with 2 known divergences
```

If a build or comparison fails, classify the failure:

```text
missing header/type wrapper
missing constant/flag mapping
missing syscall/runtime wrapper
semantic mismatch
unsupported OpenBSD/FreeBSD-specific feature
intentional Mixtar divergence
upstream OpenBSD/FreeBSD behavior change
AILang compiler/runtime bug
```

## Translation Model

The local mirror feeds the translation layer:

```text
clean local OpenBSD/FreeBSD toolkit mirror
  + Mixtar/AIl translation metadata
  + compatibility headers
  + compatibility libraries
  + build recipes
  + generated glue
    -> Linux-kernel Mixtar binary
```

The Toolkit mirror itself remains clean. If an upstream tool needs adaptation, add
or fix the wrapper, not the source file.

## AILang Responsibility

AILang should eventually own the automation:

```text
mirror check
manifest update
change detection
wrapper generation
compile/transpile step
behavior comparison orchestration
update report generation
```

So AILang is not just "a compiler" here. It is the compiler plus the source
translator/build orchestrator plus the native script runner inside MixtarRVS.

## Patch Exception

Temporary patches for investigation must not modify the mirror.

If unavoidable, store them outside the mirror:

```text
Server/Userland/Generated/patches/
```

A temporary patch is not the normal build path. The preferred outcome is a new
translation rule that allows the clean mirrored source to build again.






