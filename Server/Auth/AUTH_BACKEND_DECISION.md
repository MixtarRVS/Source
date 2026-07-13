# Mixtar Auth Backend Decision

Mixtar uses a real system authentication boundary. The greeter, shell, and QML
must not own password policy.

## Current Source Trail

The older FreeBSD experiment was not a reusable PAM module. It proved these
pieces:

- FreeBSD autologin was controlled through `/etc/gettytab` and `/etc/ttys`.
- Real login used the system PAM stack through `libpam`.
- The UI "remember me" control changed autologin policy, not password validity.
- Running PAM as an unprivileged web/server process failed because it could not
  read the protected password database.

MDDM already carries the reusable production direction:

- service name: `mixtar-login`
- backend: PAM where available, BSD auth where selected, Windows logon on
  Windows
- in-process guard: username validation, password length cap, short cooldown,
  lockout after repeated failures, and secure cleanup of local password buffers

## Mixtar Profile

MixtarRVS stages the Linux/PAM profile at:

```text
/System/Config/pam.d/mixtar-login
/etc/pam.d/mixtar-login -> same file through the /etc compatibility alias
```

The profile deliberately uses a short PAM fail delay instead of the usual slow
desktop-manager delay. The login controller still applies a local cooldown and
lockout, so the profile is fast for correct passwords without turning failed
attempts into a free brute-force loop.

## AILang Rewrite Boundary

The right AILang rewrite is not "rewrite PAM". The right boundary is:

```text
MDDM greeter -> mixtar-auth helper -> PAM/BSD-auth/system backend -> session
```

That keeps password policy system-owned while allowing Mixtar to replace the
small glue layer with AILang.

Initial helper contract:

```text
mixtar-auth verify --user Administrator
stdin: password bytes
exit 0: authenticated
exit 1: denied
exit 2: malformed request
exit 3: backend unavailable
```

Rules:

- no password is accepted from argv or environment
- no password is logged
- password buffers are scrubbed before exit where the runtime allows it
- `Administrator` is the canonical UID 0 account
- `Superuser` resolves to `Administrator`
- `root` remains a compatibility alias, not the primary Mixtar identity

Current helper:

```text
Server/Auth/mixtar_auth.ail
```

Current behavior is PAM-backed when the Linux rootfs profile stages PAM:

```text
malformed request -> exit 2
blank secret -> exit 1
PAM denial -> exit 1
PAM success -> exit 0
PAM runtime/backend unavailable -> exit 3
```

The rich graphical rootfs stages it as:

```text
/System/Tools/mixtar-auth
```

Implementation:

```text
AILang request/validation layer: Server/Auth/mixtar_auth.ail
Linux PAM backend shim:        Server/Auth/mixtar_auth_pam.c
```

The backend shim loads `libpam.so.0` at runtime with `dlopen`, so the helper can
stay small and still fail cleanly when PAM is not staged. The rootfs builder
copies the PAM policy, `libpam.so.0`, and the modules used by
`mixtar-login` for the rich graphical profile.

## Password Database Provisioning

The rootfs builder always stages an explicit shadow policy:

```text
/System/Config/shadow
/etc/shadow -> same file through the /etc compatibility alias
```

Default generated images lock `Administrator` and `Superuser`:

```text
Administrator:!:...
Superuser:!:...
```

PID 1 enforces `0600` on `/System/Config/shadow` during boot because builds may
run on filesystems that do not preserve Unix mode bits before the initramfs is
packed.

To enable production PAM login, provide a crypt(3) hash at build time instead
of committing a password:

```text
MIXTAR_ADMIN_PASSWORD_HASH=<sha512-or-yescrypt-hash>
MIXTAR_ADMIN_PASSWORD_HASH_FILE=<file-containing-hash>
```

The helper script can also generate a local SHA-512 hash interactively:

```text
python3 Server/Auth/tools/provision_rootfs_shadow.py --rootfs <rootfs> --prompt
```

## Not Done

- PAM libraries and modules are not staged into the tiny/base graphical profile.
- Production login-to-session QEMU proof still needs a provisioned password
  database and an interactive/automated greeter input path.
