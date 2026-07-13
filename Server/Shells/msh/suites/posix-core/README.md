# msh posix-core suite

This directory contains file-based shell cases for the current `msh-core` POSIX profile gate.

Each `.sh` file is executed by `msh` and compared with WSL `/bin/sh` by `tools/msh_posix_suite.py`. The cases are deliberately normal shell files so this harness can later import broader external POSIX shell suites without embedding tests in Python source.

Metadata comments supported by the runner:

```text
# msh-name: human readable name
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
```

`msh-stderr` accepts:

```text
off         compare status and stdout only
raw         compare stderr byte-for-byte
normalized  compare stderr after removing shell-specific prefixes
```

Use `normalized` for WSL-matched diagnostic-body cases because `/bin/sh` and
`msh` intentionally use different executable/path prefixes.
