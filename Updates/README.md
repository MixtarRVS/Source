# MixtarRVS Updates

This directory implements the MixtarRVS 0.9 source-native update engine.

## Files

    updates.ail
      AILang-owned status, policy audit, discovery, acquisition and verification

    updates_config_builder.ail
      deterministic SQLite configuration builder

    updates_grml.ail
      downloads the official grml-etc-core source and its signed dsc manifest

    updates_openbsd_build.ail
      builds a verified OpenBSD-first userland candidate through the local
      AILang Bridge plan without modifying or activating /System/Userland

    Schema/Updates.schema.sql
      database structure

    Schema/Updates.seed.sql
      local release policy and initial trust anchors

The SQL sources are image-build inputs. The installed source of truth is the
SQLite database /System/Configuration/Updates.config; SQL files are not
required in the running system.

## Security Model

The update engine accepts source bytes from the network. It does not accept
remote recipes, commands, target paths, trust keys or activation policy.
Those values come from Updates.config built into the Mixtar image.

HTTPS is transport protection, not artifact authentication. Automatic
progress stops unless the configured verification mode and trust anchor pass.
Unsigned upstreams may be represented as manual-only sources, but they cannot
be activated automatically.

Runtime update tools must resolve to `/System/Userland`, `/System/Shells`, or
the versioned `/System/Compilers` tree. Loose PATH names and host-distribution
paths such as `/bin`, `/usr/bin`, and `/opt` make `updates audit` fail. Grml
does not require Git, APT, or Debian tools: Mixtar verifies one official source
archive against its signed dsc manifest and pinned local keyring.

Compiler toolchain policy for 0.9:
- Canonical runtime layout:
  `/System/Compilers/<compiler-name>/<version>/...` (binaries and runtime
  helper files for that compiler stay there).
- Zig/minisign/bootstrap compilers must be installed in `/System/Compilers`
  and tracked as explicit compiler components.
- `/System/Userland` is strictly for userland runtime commands; it must not contain
  compiler binaries. `/System/Tools` is also forbidden as a compiler/toolchain location.
- Build compiler/build-tool paths (for example `tool.make`, `build.toolchain.*`, and
  language tool entries) are not allowed to point into `/System/Userland` or
  `/System/Tools` in release policy.
- A compiler path is valid only if it contains at least three path segments after
  `/System/Compilers`, e.g.:
  `/System/Compilers/Zig/0.16.0/bin/zig` or
  `/System/Compilers/GNU/13.2/bin/gcc`.
- This is a hard gate for 0.9: any compiler toolchain path outside `/System/Compilers`
  or without a version segment makes `updates audit` fail immediately.
- `component.*.compiler` entries are required to be `/System/Compilers/...` paths.
  Loose compiler names are not permitted.
- Rust toolchains are currently unsupported in native userland; if added in the
  future they must follow the same `/System/Compilers` boundary.
- This is a hard rule for all build compiler entries: no compiler binary path in
  `/System/Userland` or `/System/Tools`, including future additions that match
  compiler naming.

## Initial Commands

    updates status [Updates.config]
    updates audit [Updates.config]
    updates check-zsh [Updates.config]
    updates fetch-zsh [Updates.config] [work-directory]
    updates verify-zsh [Updates.config] [work-directory]
    updates-grml check-grml [Updates.config] [work-directory]
    updates-grml fetch-grml [Updates.config] [work-directory]
    updates-grml verify-grml [Updates.config] [work-directory]
    updates-openbsd-build build [Updates.config] [work-directory]

`updates check` is now an explicit policy gate; it maps to `updates audit`.
