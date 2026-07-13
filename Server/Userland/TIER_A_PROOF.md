# Server Userland Tier A Proof

Updated: 21.05.2026

## Status

Tier A is complete for the narrow common-command slice.

This means:

```text
MixtarRVS can build and certify a useful BSD-derived command toolkit on a
Linux-kernel target without treating GNU coreutils as the system identity.
```

This does not mean the full userland is complete.

It also does not mean the generated binaries are already installed into the
native Server layout. Promotion target is:

```text
/System/Tools        normal commands
/System/SystemTools  privileged/system commands
/System/Shells/msh   Mixtar shell
```

Old Unix paths such as `/bin`, `/usr/bin`, `/sbin`, and `/usr/sbin` remain
compatibility aliases. They are not the Mixtar identity.

## Completed Scope

- The generated coverage report tracks the current Tier A count. At this
  snapshot, `107` common command names are source-certified and `27` common
  command names are explicit hosted placeholders.
- `toolkit_build all`, `toolkit_build tier-a`, and `toolkit_build source`
  now mean source-ported Tier A only.
- Hosted placeholders are explicit-only and do not count as Tier A.
- Existing command names must preserve OpenBSD/FreeBSD semantics.
- Mirrored OpenBSD/FreeBSD upstream source is protected by integrity hashes.
- Bridge work lives outside upstream mirrors.

Canonical coverage:

```text
Server/Userland/Generated/reports/toolkit-certified-coverage.md
```

Regenerate it with:

```text
out\server\toolkit_build.exe coverage
```

## Deferred Scope

These are not Tier A and should not be forced into fake replacements:

```text
adduser
cron
fdisk
fsck
gprof
init
ipcs
less
lex
login
mount
mt
passwd
ping
pkgconf
reboot
su
swapon
sysctl
top
umount
vi
vipw
vmstat
w
watch
yacc
```

They need deeper bridge/kernel/auth/terminal/block-device work or explicit
deferral. Do not invent Mixtar-specific command semantics for these names.

## Validation Snapshot

The Tier A closure was validated with:

```text
python C:\Users\V\source\repos\AILang-Pure\ailang.py Server\Userland\Toolkit\Bridge\toolkit_build.ail --backend=c -O2 -o out\server\toolkit_build.exe
out\server\toolkit_build.exe certify-wsl all
out\server\toolkit_build.exe coverage
out\server\toolkit_build.exe verify-upstream
out\server\toolkit_build.exe action-wsl
python tools\mixtar_tranche.py --scope toolkit
python C:\Users\V\source\repos\AILang-Pure\tools\quickcheck.py
python C:\Users\V\source\repos\AILang-Pure\tools\god_object_audit.py --max-file-lines 750
```

Observed result:

```text
certify-wsl all: pass
verify-upstream: pass, 13230 upstream mirror files unchanged
action-wsl: pass
AILang leak reports on completed toolkit runs: 0 live bytes
AILang quickcheck: pass
god-object audit: 0 candidates
```

## Maintenance Rule

Keep Tier A boring.

Allowed work:

```text
repair Bridge compatibility
improve tests
refresh clean upstream mirrors intentionally
fix regressions
document blockers honestly
```

Avoid:

```text
new command semantics
fake replacements for blocked tools
editing upstream source mirrors
expanding userland scope before the rootfs/runtime proof needs it
```
