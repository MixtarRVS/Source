# Init Identity

Updated: 2026-06-12

## Decision

The first Mixtar PID 1 should be named `Mixtar`.

Installed path:

```text
/System/Init/Mixtar
/init -> /System/Init/Mixtar
```

## Rule

Mixtar's visible system components should use clean names, not mechanical
prefixes.

Use:

```text
Mixtar
msh
Panel
Login
Settings
```

Avoid for visible installed components:

```text
mixtar-init
mixtar-panel
mixtar-settings-daemon
mixtar-login-manager
```

Implementation files may still use descriptive names when useful:

```text
mixtar_init.c
build_graphical_initramfs.sh
init_services.ail
```

## Meaning

`Mixtar` is not a generic init clone. It is the boot identity of MixtarRVS:

```text
Linux kernel
  -> Mixtar
    -> /System layout
    -> compatibility aliases
    -> service/session startup
    -> desktop target
    -> emergency msh fallback
```

OpenRC, s6, runit, or systemd-style compatibility can exist later as service
profiles. They should not own PID 1 in the base identity.

## First Boot Markers

Expected log markers after the rename:

```text
Mixtar: pid1
Mixtar: target smoke
Mixtar: mounts ok
Mixtar: layout ok
toolkit ready
msh ready
desktop-wayland: ok
desktop-panel: ok
boot-smoke: ok
```
