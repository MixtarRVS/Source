# MixtarRVS Server Layout Policy

This document defines the native MixtarRVS Server filesystem model.

It is different from the older FreeBSD Workstation layout proof:

```text
FreeBSD Workstation proof:
  keep FreeBSD paths real
  add Mixtar paths as visible symlinks/views

MixtarRVS Server:
  make Mixtar paths the real system identity
  keep POSIX/Linux paths inside compatibility personas
```

## Kernel Profiles

The kernel is selectable through declared Mixtar-compatible profiles, not by
dropping arbitrary files into the root filesystem.

CoreV07 uses one explicit Linux RT profile layout:

```text
/System/Kernel/
  Linux/
    RT/
      7.1.2/
        kernel-profile.json
```

The official boot artifact for CoreV07 is versioned under:

```text
/System/EFI/MixtarRVS/0.8.efi
```

Split boot artifacts such as `vmlinuz`, `initramfs`, `initrd`, `Current.efi`,
and `Previous.efi` are not part of the CoreV07 native staged layout.

The runtime contract is recorded in:

```text
/System/Kernel/Linux/RT/7.1.2/kernel-profile.json
```

Do not support random kernels as a product promise. A kernel is Mixtar-compatible
only if its profile passes the required syscall, filesystem, security, module,
device, and init-contract checks.

## Native Mixtar Paths

The native Server layout should prefer readable paths:

```text
/Applications        installed GUI/application view
/System              base operating environment
/System/Compilers    compiler binaries, versioned toolchains, and compiler-side helpers
/System/Compatibility compatibility personas and old Unix views
/System/Devices      kernel device namespace
/System/Process      process namespace
/System/Hardware     hardware/sysfs namespace
/System/Kernel       kernel profiles and boot artifacts
/System/Runtime      runtime state and ABI/profile contracts
/System/Init         Mixtar PID 1 and boot targets
/System/Shells       system shells
/System/Userland     MixtarRVS userland commands
/System/Tools        administrative/system inspection tools
/System/Drivers      kernel driver store, store-only, not command PATH
/System/Security     security authority and Administrator Mode policy
/System/Libraries    system libraries
/System/Configuration       system configuration
/System/Resources    read-only shared resources
/System/Logs         logs
/System/UI           session and UI namespace
/Users               human user homes
/Volumes             mounted disks/network volumes
/Temporary           temporary files
```

CoreV07 path roles are deliberately separate:

```text
/System/Userland
  normal command userland
  mode: command-root

  /System/Userland must not store compiler executables or compiler toolchain
  binaries. Toolchain binaries belong only under /System/Compilers/.

/System/Tools
  administrative tools only
  forbidden to contain compiler executables or toolchain managers
  not a fallback home for normal commands
  not part of the default user or APX PATH
  mode: admin-only

/System/Drivers
  driver database, firmware/profile metadata, status data
  mode: store-only
  not part of PATH

/System/Security
  security authority, authentication policy, and Administrator Mode contract
  mode: authority-policy

/System/Runtime/Security
  runtime-only authentication sockets and elevated session tokens
  mode: runtime-only

/System/Runtime/Executor
  APX runtime executor

/System/UI/Shell
  system UI shell components
  current system shell APX: /System/UI/Shell/MixtarShell.apx

/System/Configuration
  SQLite-primary system configuration
  mode: sqlite-primary

/Applications
  user-visible APX/application view
  mode: user-visible-only
  system shells and UI components must not be staged here
```

## Administrator Identity

The native Mixtar privileged account name is:

```text
Administrator
```

`Superuser` is an alias for `Administrator`, not a separate identity:

```text
/Users/Administrator      canonical UID 0 home
/Users/Superuser          -> Administrator
```

Keep Linux compatibility aliases, but do not make them the Mixtar identity:

```text
/root                     -> /Users/Administrator
/Users/root               -> Administrator
```

The generated `/etc/passwd` view should identify UID 0 as `Administrator` and
may include `Superuser` as an alias entry pointing to the same home and shell.

CoreV07 Administrator Mode is session-token based. A terminal or future UI may
show:

```text
Administrator: Mixtar Terminal
```

while the visible user and prompt remain the human account, for example:

```text
vxz@MixtarRVS:/>
```

The elevated token is runtime state under `/System/Runtime/Security`, governed
by `/System/Security` and `/System/Configuration/Security/Policy.config`.

Default policy:

```text
sudo.default=false
```

`sudo` is compatibility-only and must not be the default Mixtar privilege model.

CoreV07 uses `zsh` as the default system shell while `msh` is postponed:

```text
/System/Shells/zsh
```

Do not make `sh`, `ksh`, `csh`, or `bash` the system identity. They can exist as
compatibility shells if they are built and certified later.

## Namespace And Drive-Letter Policy

Do not introduce a custom namespace engine in the first Server line.

The kernel, libc/runtime bridge, third-party packages, build tools, Steam, Wine,
and compatibility layers should see a normal POSIX filesystem. Mixtar-native
software can prefer readable paths, but it must not depend on a new drive-letter
or logical-volume syntax to boot or run.

Removed/postponed ideas:

```text
System:
Users:
A:/
B:/
C:/
VMS-style logical names
Amiga-style assigns
custom filesystem semantics
```

These can be explored later inside `msh` or the AILang runtime as optional path
resolution sugar. They are not rootfs requirements.

## POSIX Compatibility Paths

Linux does not require `/bin` or `/usr/bin`, but Unix software does. In the
native MixtarRVS root, old Unix paths are not visible identity paths.

Old paths belong under compatibility personas:

```text
/System/Compatibility/POSIX/Linux/dev
/System/Compatibility/POSIX/Linux/proc
/System/Compatibility/POSIX/Linux/sys
/System/Compatibility/POSIX/Linux/bin
/System/Compatibility/POSIX/Linux/usr
/System/Compatibility/POSIX/Linux/etc

/System/Compatibility/POSIX/OpenBSD/dev
/System/Compatibility/POSIX/FreeBSD/dev
```

The native kernel views are:

```text
/System/Devices   devtmpfs
/System/Process   procfs
/System/Hardware  sysfs
```

Compatibility execution may later create a private namespace where legacy
programs see:

```text
/dev  -> /System/Devices
/proc -> /System/Process
/sys  -> /System/Hardware
```

Native Mixtar software uses:

```text
#!/System/Shells/zsh
/System/Userland/ls
/System/Userland/awk
```

## APX Runtime Policy

APX bundles are executed through:

```text
/System/Runtime/Executor
```

The current APX model is:

```text
Application.apx/
  Application.config      SQLite configuration
  Program/
    Application           default executable entry
  Icon/
  Resources/
  Data/
```

APX does not use a separate launcher script or XML metadata file. The executor
opens the SQLite config read-only, validates metadata and launch settings, and
then executes `Program/<bundle-base-name>` by default.

## Deprecated Path Names

Older notes used `/System/Binaries` and sometimes treated `/System/Tools` as a
userland alias.

New documents should use:

```text
/System/Userland
```

`/System/Tools` must not be an alias to `/System/Userland` in CoreV07.
`/System/Tools` is reserved for administrative tools.

## Rule For Old Paths

Do not make old Unix paths visible in the native root.

Use them inside `/System/Compatibility` personas so the system can later build
and run portable Unix software without making `/bin`, `/dev`, `/etc`, `/usr`, or
`/root` part of the Mixtar identity.
