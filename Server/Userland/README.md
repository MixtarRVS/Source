# Server/Userland

This is the MixtarRVS Server Userland workspace.

Userland is not only commands. It is the full base toolkit above the kernel:

```text
tool sources
runtime assumptions
compatibility headers
build manifests
generated wrappers
behavior contracts
tests
Mixtar-owned native tools
```

## Purpose

```text
Toolkit/     clean local mirror of selected upstream toolkit source files
  OpenBSD/   preferred source for Tier 1 core tools when mirrored/certified
  FreeBSD/   fallback and broad-source reference
  Bridge/    Mixtar translation/wrapper layer
Manifests/   upstream revision, file hashes, tool dependency maps
Generated/   wrappers, build metadata, reports, temporary generated output
Tools/       Mixtar-owned AILang/native tools and adapters
Tests/       behavior and compatibility tests
```

Do not edit files under `Toolkit/OpenBSD/` or `Toolkit/FreeBSD/` by hand. These
mirrors are updated by the Toolkit mirror/update pipeline only. Put translation
work under `Toolkit/Bridge/`, `Generated/`, or `Tools/`.

Current upstream policy:

```text
OpenBSD first for Tier 1 core tools.
FreeBSD remains fallback and breadth reference.
```

The machine-readable policy lives in:

```text
Manifests/upstream-policy.json
```

Current mirrored upstream manifests:

```text
Manifests/openbsd-src.json
Manifests/freebsd-src.json
```

## Generated Targets

On a Windows development host, WSL is the first Linux build executor for Server
Userland proofs. Generated Linux artifacts go under:

```text
Generated/targets/linux-x64/bin/
```

These files prove that the Bridge can build against a Linux-kernel target. They
are not promoted userland yet. Promotion into `Tools/` requires the strict build
gate and behavior comparison against the selected upstream behavior.

When promoted into a native Server rootfs, commands should land under the Mixtar
layout, not directly as the system identity under old Unix paths:

```text
/System/Tools        normal commands
/System/SystemTools  privileged/system commands
/System/Shells       msh and compatibility shells

/bin      -> /System/Tools
/sbin     -> /System/SystemTools
/usr/bin  -> /System/Tools
/usr/sbin -> /System/SystemTools
```

See:

```text
Server/Rootfs/LAYOUT_POLICY.md
```

Current automated build driver:

```text
Toolkit/Bridge/toolkit_build.ail
```

Current Tier A generated/certified smoke tools: 106

```text
See `Generated/reports/toolkit-certified-coverage.md` for the canonical list,
common-command coverage, and remaining gaps.
```

Tier A closure note:

```text
Server/Userland/TIER_A_PROOF.md
```

`toolkit_build all`, `toolkit_build tier-a`, and `toolkit_build source` are
source-ported-only targets. Hosted placeholders are explicit-only and remain
outside Tier A.

Existing command names must preserve their upstream userland semantics. The
Toolkit is not a place to invent new Mixtar versions of `mount`, `login`, `vi`,
or similar tools. If the Bridge cannot support the upstream behavior yet, keep
the tool blocked/deferred instead of shipping a misleading replacement.

Security mapping for promoted tools should follow:

```text
pledge -> seccomp
unveil -> Landlock
capability/no_new_privs/rlimit defaults from service/tool manifests
```

Typical Windows-host command flow:

```powershell
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Userland\Toolkit\Bridge\toolkit_build.ail --backend=c -o out\server\toolkit_build.exe
out\server\toolkit_build.exe build-wsl all
out\server\toolkit_build.exe test-wsl all
out\server\toolkit_build.exe certify-wsl all
out\server\toolkit_build.exe probe-auto-wsl
```

`test-wsl` is a smoke comparison against WSL-native tools. It proves that the
generated Linux binaries run and match simple native behavior. It is not a
promise of GNU semantics and does not replace later selected-upstream behavior
tests.

`certify-wsl` is the canonical current proof command. It rebuilds, retests, and
writes certification reports under:

```text
Generated/certification/
```

`probe-auto-wsl` is the discovery command. It scans mirrored `bin/*` and
`usr.bin/*` directories, tries strict compile recipes where possible, and writes
the next-batch report:

```text
Generated/reports/toolkit-auto-probe-wsl.md
```

Current detailed rules live in:

```text
References/TOOLKIT_MIRROR.md
../Runtime/TRANSLATION_LAYER.md
```




