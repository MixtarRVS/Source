# msh posix-external-seed suite

This suite is the first external-style conformance gate for `msh`.

The cases are ordinary POSIX `.sh` files consumed by `tools/msh_posix_suite.py`.
They intentionally avoid Mixtar-specific helpers and broad external utilities so
that the comparator can run them against WSL `/bin/sh` and the current `msh`
binary with the same file format expected from imported external suites.

This is not a certification corpus. It is the seed harness that future imported
POSIX shell-language tests should grow from.
