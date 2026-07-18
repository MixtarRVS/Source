# MWM

MWM is the MixtarRVS Window Manager. It owns Wayland surfaces, focus, window
placement, movement, resizing, maximization, fullscreen state and keyboard
shortcuts. Applications, including Workbench, remain ordinary Wayland clients.

The first executable gate uses the nested Wayland backend. This makes the
window policy testable without changing the working console image. DRM/KMS and
libinput are the next backend additions to this same program, not alternative
window-manager implementations.

The low-level compositor mechanics are derived from wlroots tinywl, whose
source is CC0-1.0. The source is renamed and built as a Mixtar-owned component;
wlroots supplies protocol, renderer and backend mechanics but does not define
the Mixtar desktop policy.

Public runtime paths are Mixtar paths:

- `/System/Core/Graphics/MWM`
- `/System/Configuration/Graphics/MWM.config`
- `/System/Configuration/Graphics/MDDM.config`
- `/System/Runtime/Graphics`

X11 and Xwayland are not built.
