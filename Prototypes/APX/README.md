# APX P4-pre prototype

`ContractProbe.apx` is a minimal APX v1 contract fixture. Its x86-64 ELF entrypoint performs only `exit(0)` and has no runtime dependencies. It exists to exercise bundle validation and launch-plan generation, not to define the final Executor implementation.

```powershell
py -3.14 -m mixtar_builder.apx validate Prototypes/APX/ContractProbe.apx
py -3.14 -m mixtar_builder.apx plan --context terminal --diagnostics --wait Prototypes/APX/ContractProbe.apx -- --help
```

The `plan` command never starts the entrypoint. It emits the argv-based descriptor that a future `/System/Runtime/Executor` must consume.
