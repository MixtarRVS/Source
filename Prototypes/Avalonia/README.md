# MixtarRVS Avalonia Preview

Native Avalonia equivalent of the repository-level `Preview.html`. It does not
embed a browser, WebView, HTML, CSS, or JavaScript.

## Scope

- fixed 1600 x 900 design surface scaled proportionally by Avalonia;
- HUD, taskbar, Start menu, command palette, and four desktop windows;
- draggable/focusable/minimizable/maximizable desktop windows;
- Mixtar namespace file explorer with filtering and address entry;
- simulated zsh terminal, network node selection, and runtime meters;
- all user-facing Mixtar text is English.

The project intentionally uses code-behind only for desktop behavior. There is
no MVVM framework or dependency injection container in this visual prototype.

## Build

```powershell
dotnet restore Prototypes/Avalonia/MixtarRVS.Avalonia.csproj
dotnet run --project Prototypes/Avalonia/MixtarRVS.Avalonia.csproj -c Release
```

For a Windows self-contained publication:

```powershell
dotnet publish Prototypes/Avalonia/MixtarRVS.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

Avalonia packages are fixed to the reviewed stable release `12.0.3`. Avalonia
is MIT-licensed; a published application must still carry notices for Avalonia,
SkiaSharp, .NET, and their transitive dependencies.

This is an Avalonia feasibility prototype. It is not MWM or MDDM, and the .NET
runtime is not yet part of the Mixtar base system.
