# CoreV07 Session/UI Contract

Updated: 08.07.2026

Goal:

```text
Define where Mixtar sessions and UI state live before adding a graphical shell.
```

This stage intentionally adds no graphical compositor and no full control center.
It only establishes the namespace, APX shell location, and session contract.

Runtime and UI paths:

```text
/System/UI
/System/UI/Session.config
/System/UI/Session.contract
/System/UI/Sessions
/System/UI/Shell
/System/UI/Themes
/System/UI/Fonts
/System/UI/Icons
/System/Runtime/Sessions
/System/Runtime/Display
/Applications
```

Current policy:

```text
session.mode=console
session.user=vxz
session.shell=/System/Shells/zsh
ui.graphical.enabled=false
ui.graphical.shell=/System/UI/Shell/MixtarShell.apx
runtime.executor=/System/Runtime/Executor
apx.executor=/System/Runtime/Executor
```

Meaning:

```text
CoreV07 prepares the UI namespace and system shell APX location, but still boots
into the existing console session. Graphical MixtarShell, MDDM, and a control
center are future scope.
```

Forbidden in this stage:

```text
/System/Applications
/Applications/MixtarShell.apx
/System/Shells/MixtarShell.apx
```
