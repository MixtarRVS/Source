# MixtarRVS CoreV08 Plan

CoreV08 is the next controlled step after CoreV07.

CoreV07 status:

```text
PASS:
  native root shape
  single EFI artifact
  Mixtar PID1
  zsh shell
  APX Executor foundation
  /System/Userland command root
  /System/Tools reserved for administrative tools
  /System/Drivers store-only
  Wi-Fi recovery networking on ThinkPad T480
  native ping through /System/Userland/ping
  one-shot boot with autoreturn

NOT YET PRODUCT:
  persistent Mixtar boot
  full remote administration
  UI
  package/application installation
  stable service manager
```

## CoreV08 Objective

Make MixtarRVS remotely controllable and testable without relying on manual
console interaction.

CoreV08 should not expand the UI or package system yet. It should turn CoreV07
from a one-shot boot proof into a small system that can be inspected, reached,
and recovered predictably.

## Scope

CoreV08 includes:

```text
/System/Networking
  stable Wi-Fi/LAN selection
  stable route ownership
  native network probes
  SSH service as controlled recovery access

/System/Userland
  native ping
  minimal network status command
  no broken hosted placeholders in the default command path

/System/Configuration
  SQLite-first networking configuration
  SQLite-first SSH configuration
  text fallback for recovery

/System/Runtime
  networking logs
  service state
  boot result markers

Gates
  local gate
  chroot gate
  boot preflight
  one-shot boot gate
  SSH reachability gate
```

CoreV08 excludes:

```text
graphical UI
desktop session
package manager
permanent default boot
Debian mutation
full POSIX compatibility
custom kernel namespace rewrite
```

## Required Gates

CoreV08 must keep the gates separated.

```text
corev07-local-gate.sh
  proves staged files, config, EFI, and preflight checks

corev07-chroot-gate.sh
  proves userland execution inside staged root
  does not prove PID1, EFI, firmware, Wi-Fi, or boot behavior

corev07-oneshot-deploy.sh
  proves controlled boot on the laptop
  must use BootNext only
  must preserve Debian as normal BootOrder default

CoreV08 SSH gate
  proves Mixtar can be reached after boot
  must confirm command execution over SSH
  must not require manual console input
```

## Acceptance Criteria

CoreV08 is accepted only if all of these pass:

```text
1. Local gate passes.
2. Chroot gate passes.
3. One-shot boot returns to Debian automatically.
4. Mixtar boot log shows selected active interface.
5. Mixtar has one default route through the selected active interface.
6. Native ping returns 4/4 packets to 8.8.8.8.
7. UDP DNS probe receives a reply from 8.8.8.8.
8. SSH service starts without console-only workarounds.
9. SSH login or key-based command execution works at least for recovery.
10. Debian remains untouched except for controlled read-only inspection and
    BootNext-based one-shot tests.
```

## Engineering Rules

```text
Do not make Debian part of Mixtar.
Do not use Debian's kernel as a Mixtar kernel.
Do not use /System/Tools as the normal command root.
Do not put drivers under /System/Tools.
Do not add UI before remote recovery is reliable.
Do not treat chroot as a full boot proof.
Do not leave a broken command in /System/Userland if a native replacement exists.
```

## First CoreV08 Tasks

```text
1. Promote the chroot gate into the normal validation flow.
2. Add a CoreV08 SSH reachability gate.
3. Make SSH logs explicit under /System/Runtime/Networking/SSH.
4. Add a native network status command under /System/Userland.
5. Replace or quarantine any remaining broken hosted networking commands.
```

## Result

After CoreV08, MixtarRVS should be a small bootable system with working network
and recovery access. It is still not the UI release. It is the release that makes
future UI work safe because the machine can be reached and diagnosed without
manual reboot loops.
