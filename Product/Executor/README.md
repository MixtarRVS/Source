# Mixtar Executor

This is the product implementation of `/System/Runtime/Executor` for Mixtar 1.0 Core Identity.

Properties:

- stable .NET 10 Native AOT;
- Tomlyn 2.10.1 with reflection disabled by default;
- APX v1 TOML validation;
- x86-64 ELF validation and path traversal rejection;
- no command shell and argv-only process creation;
- active-session validation;
- application policy bound to application id and publisher;
- explicit terminal and graphical launch contexts;
- atomic launch descriptors and an English lifecycle audit log.

The current capability layer is deliberately named `declaration-and-session-gate-v1`. It denies missing declared capabilities and refuses `system.admin` without a broker, but it is not yet the Landlock/seccomp isolation planned for the policy phase.

The immutable binary is staged as `/System/Core/Product/Executor`. OpenRC copies it into the ephemeral `/System/Runtime/Executor` at boot. The console M1 image does not include this overlay.
