# Mixtar product overlay

`Product/Root` is applied only by product profiles. It is never copied into the console M1 profile.

The 1.0 Core Identity overlay contains the APX Executor, its policy, a console session bootstrap and a generated `zsh.apx`. Graphical components are later layers with fixed roles:

```text
Linux GPU drivers / DRM / KMS
  -> MDDM: MixtarRVS Display Driver Model
  -> MWM: MixtarRVS Window Manager and Wayland compositor
  -> Login UI and desktop: Avalonia 12.1 on stable .NET 10 Native AOT
  -> APX applications
```

MDDM is not a login manager or UI component. Login UI, Auth Provider and Session Manager are separate product components.

`Product/build-graphics.ps1` is the only P4 graphics entrypoint. It publishes the Wayland-only Workbench as .NET 10 Native AOT, builds the locked graphics stack from source, stages it below `/System`, patches every ELF to the private Mixtar loader and emits a separate graphical overlay. It never modifies the console root.
