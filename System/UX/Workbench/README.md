# MixtarRVS Workbench

This is the single product implementation of the Mixtar 1.1 desktop client.

Contract:

- Avalonia 12.1.0;
- stable .NET 10 Native AOT;
- native Avalonia.Wayland backend only;
- no Avalonia.Desktop, X11, Xwayland, browser, Qt, QML, GTK or platform fallback;
- Noto fonts supplied by the Mixtar graphical sysroot;
- installed as an APX client under the Product graphical overlay.

MWM remains the compositor and window owner. Workbench is a Wayland client and
does not implement MWM or MDDM.
## Rendering policy

`MIXTAR_GRAPHICS_MODE=auto` is the production default and lets Avalonia Wayland select EGL/GPU rendering. `MIXTAR_GRAPHICS_MODE=software` disables GL profiles explicitly and selects Avalonia's Wayland framebuffer fallback; it is the deterministic low-CPU path for headless and software-only gates. The nested MWM test also accepts `MIXTAR_GALLIUM_DRIVER` for controlled Mesa comparisons without changing the production default.