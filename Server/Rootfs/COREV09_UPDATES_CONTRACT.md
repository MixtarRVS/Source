# MixtarRVS 0.9 Updates Contract

MixtarRVS 0.9 is the source-native update release built on the accepted 0.8
core. It does not include the graphical product experience planned for 1.0.

## Release Boundary

    0.8  bootable no-UI core, native root, PID1, userland, network and recovery
    0.9  trusted upstream discovery, verified source builds and safe activation
    1.0  graphical shell, update UI and normal user-facing administration

## Distribution Policy

mixtarrvs.com may publish documentation, the system specification, release
signatures and installation ISO images. It must not become a package mirror,
binary update repository, component catalog API, or mandatory runtime service.

Mixtar obtains component source directly from its declared official upstream:

    OpenBSD userland  official OpenBSD source service
    ZSH               https://www.zsh.org/pub/
    Grml ZSH config   https://grml.org/
    Linux             https://kernel.org/
    Linux RT          https://kernel.org/pub/linux/kernel/projects/rt/
    MixtarRVS         an explicit official source repository, once published

## Canonical Configuration

The installed policy is the SQLite database:

    /System/Configuration/Updates.config

It owns component versions, upstream locations, discovery adapters, local
recipe identifiers, target paths, trust anchors and automatic-install policy.
Remote content must never replace this policy database or inject a build
recipe.

## State Machine

    never-checked
      -> available-unverified
      -> verified-source
      -> build-passed
      -> system-verified
      -> staged
      -> boot-tested
      -> installed

Any failed signature, missing trust anchor, unsupported adapter, failed build,
failed component test, failed full verifier or RT-driver conflict transitions
the update to blocked. A blocked update is never activated.

## Build And Activation Rules

    source and signatures may download in parallel
    build order follows the dependency graph
    builds run without network access after acquisition
    build tools and compilers live ONLY under versioned trees like
    /System/Compilers/<name>/<version>/...
    and are forbidden in both /System/Userland and /System/Tools
    this is a hard invariant for 0.9: any compiler or toolchain path outside this
    layout must block update activation
    OpenBSD mirror source remains unmodified
    OpenBSD userland is rebuilt through the AILang Bridge
    ZSH is emitted as /System/Shells/zsh.apx
    Linux RT is emitted under /System/Kernel/Linux/RT/<version>
    boot output is /System/EFI/MixtarRVS/<version>.efi
    the active EFI artifact is not overwritten before every gate passes

depends on !PREEMPT_RT is a hard compatibility blocker. Mixtar may apply an
explicitly trusted upstream patch or select a fixed kernel version. It must not
delete the condition or force the driver on automatically.

## Proof Order

    1. deterministic Updates.config build
    2. local policy audit
    3. upstream discovery
    4. parallel source/signature acquisition
    5. cryptographic verification
    6. isolated component build and tests
    7. full staged-root verifier
    8. chroot gate
    9. QEMU boot gate
    10. ThinkPad BootNext one-shot gate with Debian preserved

No physical boot is allowed before steps 1 through 9 pass.
