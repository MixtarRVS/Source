using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Animation;
using Avalonia.Animation.Easings;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.VisualTree;
using IOPath = System.IO.Path;

namespace Mixtar.Product.Workbench;

public sealed partial class MainWindow
{
    // ------------------------------------------------------------------
    // Window management
    // ------------------------------------------------------------------

    private Border? WindowByName(string? name) => name switch
    {
        nameof(TerminalWindow) => TerminalWindow,
        nameof(FilesWindow) => FilesWindow,
        nameof(RuntimeWindow) => RuntimeWindow,
        nameof(NetworkWindow) => NetworkWindow,
        nameof(ViewerWindow) => ViewerWindow,
        nameof(SettingsWindow) => SettingsWindow,
        _ => null
    };

    private Button? TaskFor(Border window)
    {
        if (window == TerminalWindow) return TerminalTask;
        if (window == FilesWindow) return FilesTask;
        if (window == RuntimeWindow) return RuntimeTask;
        if (window == NetworkWindow) return NetworkTask;
        return null;
    }

    // HIG: keep z-indexes bounded by renormalizing once they run away.
    private void RecycleZIndices()
    {
        if (_topZ < 5000)
        {
            return;
        }

        var ordered = DesktopWindows().OrderBy(item => item.ZIndex).ToList();
        _topZ = 30;
        foreach (var item in ordered)
        {
            item.ZIndex = ++_topZ;
        }
    }

    // HIG: always-on-top windows stay above everything after each activation.
    private readonly HashSet<Border> _alwaysOnTop = new();

    private void ReassertAlwaysOnTop()
    {
        foreach (var pinned in _alwaysOnTop)
        {
            if (pinned.IsVisible)
            {
                pinned.ZIndex = ++_topZ;
            }
        }
    }

    private void ActivateWindow(Border window)
    {
        RecycleZIndices();
        window.IsVisible = true;
        window.ZIndex = ++_topZ;
        ReassertAlwaysOnTop();

        foreach (var item in DesktopWindows())
        {
            item.Classes.Remove("active");
            TaskFor(item)?.Classes.Remove("active");
        }

        window.Classes.Add("active");
        TaskFor(window)?.Classes.Add("active");
        TaskFor(window)?.Classes.Remove("minimized");
        _activeWindow = window;
    }

    // HIG: every window resizes from all 8 edges/corners (7px band).
    private static int EdgeFlags(Border window, Point position)
    {
        const double band = 7;
        var flags = 0;
        if (position.X <= band) flags |= 1;
        if (position.X >= window.Bounds.Width - band) flags |= 2;
        if (position.Y <= band) flags |= 4;
        if (position.Y >= window.Bounds.Height - band) flags |= 8;
        return flags;
    }

    private static StandardCursorType CursorFor(int flags) => flags switch
    {
        1 or 2 => StandardCursorType.SizeWestEast,
        4 or 8 => StandardCursorType.SizeNorthSouth,
        5 or 10 => StandardCursorType.TopLeftCorner,
        6 or 9 => StandardCursorType.TopRightCorner,
        _ => StandardCursorType.Arrow
    };

    private void OnWindowResizePressed(object? sender, PointerPressedEventArgs e)
    {
        if (sender is not Border window || _restoreBounds.ContainsKey(window))
        {
            return;
        }

        var flags = EdgeFlags(window, e.GetPosition(window));
        if (flags == 0 || !e.GetCurrentPoint(window).Properties.IsLeftButtonPressed)
        {
            return;
        }

        ActivateWindow(window);
        _resizeWindow = window;
        _resizeFlags = flags;
        _resizeStartBounds = new Rect(Canvas.GetLeft(window), Canvas.GetTop(window),
            window.Width, window.Height);
        _resizeStartPointer = e.GetPosition(DesktopCanvas);
        e.Pointer.Capture(window);
        e.Handled = true;
    }

    private void OnWindowResizeMoved(object? sender, PointerEventArgs e)
    {
        if (sender is not Border window)
        {
            return;
        }

        if (_resizeWindow != window)
        {
            window.Cursor = new Cursor(CursorFor(
                _restoreBounds.ContainsKey(window) ? 0 : EdgeFlags(window, e.GetPosition(window))));
            return;
        }

        const double minWidth = 260;
        const double minHeight = 160;
        var delta = e.GetPosition(DesktopCanvas) - _resizeStartPointer;
        var left = _resizeStartBounds.X;
        var top = _resizeStartBounds.Y;
        var width = _resizeStartBounds.Width;
        var height = _resizeStartBounds.Height;

        if ((_resizeFlags & 1) != 0)
        {
            var newWidth = Math.Max(minWidth, width - delta.X);
            left += width - newWidth;
            width = newWidth;
        }
        else if ((_resizeFlags & 2) != 0)
        {
            width = Math.Max(minWidth, width + delta.X);
        }

        if ((_resizeFlags & 4) != 0)
        {
            var newHeight = Math.Max(minHeight, height - delta.Y);
            top += height - newHeight;
            height = newHeight;
        }
        else if ((_resizeFlags & 8) != 0)
        {
            height = Math.Max(minHeight, height + delta.Y);
        }

        Canvas.SetLeft(window, left);
        Canvas.SetTop(window, Math.Max(8, top));
        window.Width = width;
        window.Height = height;
    }

    private void OnWindowResizeReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (_resizeWindow is null || sender != _resizeWindow)
        {
            return;
        }

        e.Pointer.Capture(null);
        _resizeWindow = null;
        _resizeFlags = 0;
        e.Handled = true;
    }

    private void FocusDesktopWindow(object? sender, PointerPressedEventArgs e)
    {
        if (sender is Border window)
        {
            ActivateWindow(window);
        }
    }

    private void BeginDesktopWindowDrag(object? sender, PointerPressedEventArgs e)
    {
        if (sender is not Control handle || handle.Tag is not string name)
        {
            return;
        }

        if (e.Source is Button || e.Source is Control source && source.FindAncestorOfType<Button>() is not null)
        {
            return;
        }

        var point = e.GetCurrentPoint(handle);
        if (!point.Properties.IsLeftButtonPressed)
        {
            return;
        }

        var window = WindowByName(name);
        if (window is null)
        {
            return;
        }

        // The titlebar covers the window's top edge - inside the resize band
        // the press belongs to the resize handler, not to dragging.
        if (EdgeFlags(window, e.GetPosition(window)) != 0)
        {
            return;
        }

        ActivateWindow(window);
        _dragWindow = window;
        _dragHandle = handle;
        _dragPointerOrigin = e.GetPosition(DesktopCanvas);

        // HIG: dragging a maximized/snapped window tears it off and restores
        // its size under the pointer, Windows-style.
        if (_restoreBounds.Remove(window, out var saved))
        {
            var fraction = Math.Clamp(
                (_dragPointerOrigin.X - Canvas.GetLeft(window)) / Math.Max(1, window.Width), 0.1, 0.9);
            window.Width = saved.Width;
            window.Height = saved.Height;
            Canvas.SetLeft(window, _dragPointerOrigin.X - saved.Width * fraction);
            Canvas.SetTop(window, Math.Max(8, _dragPointerOrigin.Y - 17));
            UpdateMaximizeGlyph(window);
        }

        _dragWindowOrigin = new Point(Canvas.GetLeft(window), Canvas.GetTop(window));
        e.Pointer.Capture(handle);
        e.Handled = true;
    }

    // HIG: edge/corner snapping with preview. Zone flags reuse the resize
    // convention: 1=left 2=right 4=top 8=bottom.
    private int _pendingSnap;

    private Rect SnapRect(int zone)
    {
        var bounds = DesktopCanvas.Bounds;
        var top = 8d;
        var height = Math.Max(200, bounds.Height - top - 48);
        var half = bounds.Width / 2;
        var halfH = height / 2;
        return zone switch
        {
            1 => new Rect(0, top, half, height),
            2 => new Rect(half, top, half, height),
            4 => new Rect(0, top, bounds.Width, height),
            5 => new Rect(0, top, half, halfH),
            6 => new Rect(half, top, half, halfH),
            9 => new Rect(0, top + halfH, half, halfH),
            10 => new Rect(half, top + halfH, half, halfH),
            _ => default
        };
    }

    private void ContinueDesktopWindowDrag(object? sender, PointerEventArgs e)
    {
        if (_dragWindow is null || sender != _dragHandle)
        {
            return;
        }

        var bounds = DesktopCanvas.Bounds;
        var point = e.GetPosition(DesktopCanvas);
        var x = Math.Clamp(_dragWindowOrigin.X + point.X - _dragPointerOrigin.X, 0,
            Math.Max(0, bounds.Width - _dragWindow.Bounds.Width));
        var y = Math.Clamp(_dragWindowOrigin.Y + point.Y - _dragPointerOrigin.Y, 8,
            Math.Max(8, bounds.Height - 48 - 34));
        Canvas.SetLeft(_dragWindow, x);
        Canvas.SetTop(_dragWindow, y);

        const double edge = 14;
        const double corner = 90;
        var zone = 0;
        if (point.X <= edge) zone |= 1;
        else if (point.X >= bounds.Width - edge) zone |= 2;
        if (point.Y <= edge + 8) zone |= 4;
        else if (point.Y >= bounds.Height - 48 - edge) zone |= 8;
        if (zone is 4 && point.X <= corner) zone = 5;
        else if (zone is 4 && point.X >= bounds.Width - corner) zone = 6;
        if (zone is 8) zone = 0;

        _pendingSnap = zone;
        var rect = SnapRect(zone);
        SnapPreview.IsVisible = zone != 0;
        if (zone != 0)
        {
            Canvas.SetLeft(SnapPreview, rect.X);
            Canvas.SetTop(SnapPreview, rect.Y);
            SnapPreview.Width = rect.Width;
            SnapPreview.Height = rect.Height;
        }
    }

    private void EndDesktopWindowDrag(object? sender, PointerReleasedEventArgs e)
    {
        if (_dragWindow is null)
        {
            return;
        }

        if (_pendingSnap != 0)
        {
            var rect = SnapRect(_pendingSnap);
            _restoreBounds[_dragWindow] = new DesktopBounds(
                Canvas.GetLeft(_dragWindow), Canvas.GetTop(_dragWindow),
                _dragWindow.Width, _dragWindow.Height);
            Canvas.SetLeft(_dragWindow, rect.X);
            Canvas.SetTop(_dragWindow, rect.Y);
            _dragWindow.Width = rect.Width;
            _dragWindow.Height = rect.Height;
            _pendingSnap = 0;
            UpdateMaximizeGlyph(_dragWindow);
        }

        SnapPreview.IsVisible = false;
        e.Pointer.Capture(null);
        _dragWindow = null;
        _dragHandle = null;
        e.Handled = true;
    }

    private Border? WindowFromButton(object? sender) =>
        sender is Button { Tag: string name } ? WindowByName(name) : null;

    private void OnDesktopMinimize(object? sender, RoutedEventArgs e)
    {
        var window = WindowFromButton(sender);
        if (window is null) return;

        window.IsVisible = false;
        window.Classes.Remove("active");
        TaskFor(window)?.Classes.Add("minimized");
        if (_activeWindow == window) _activeWindow = null;
        e.Handled = true;
    }

    private void OnDesktopClose(object? sender, RoutedEventArgs e)
    {
        var window = WindowFromButton(sender);
        if (window is null) return;

        window.IsVisible = false;
        window.Classes.Remove("active");
        if (TaskFor(window) is { } task) task.IsVisible = false;
        if (_activeWindow == window) _activeWindow = null;
        e.Handled = true;
    }

    // The max button shows the restore glyph exactly when clicking it would
    // restore, i.e. when the window has saved bounds (maximized or snapped).
    private void UpdateMaximizeGlyph(Border window)
    {
        var button = window.GetVisualDescendants().OfType<Button>()
            .FirstOrDefault(item => item.Classes.Contains("max"));
        if (button is null)
        {
            return;
        }

        if (_restoreBounds.ContainsKey(window))
        {
            if (!button.Classes.Contains("restore"))
            {
                button.Classes.Add("restore");
            }
        }
        else
        {
            button.Classes.Remove("restore");
        }
    }

    private void OnDesktopMaximize(object? sender, RoutedEventArgs e)
    {
        var window = WindowFromButton(sender);
        if (window is null) return;

        var bounds = DesktopCanvas.Bounds;
        if (_restoreBounds.Remove(window, out var saved))
        {
            Canvas.SetLeft(window, saved.Left);
            Canvas.SetTop(window, saved.Top);
            window.Width = saved.Width;
            window.Height = saved.Height;
        }
        else
        {
            _restoreBounds[window] = new DesktopBounds(
                Canvas.GetLeft(window), Canvas.GetTop(window), window.Width, window.Height);
            Canvas.SetLeft(window, 0);
            Canvas.SetTop(window, 40);
            window.Width = bounds.Width;
            window.Height = Math.Max(200, bounds.Height - 40 - 48);
        }

        UpdateMaximizeGlyph(window);
        ActivateWindow(window);
        e.Handled = true;
    }

    private void OnTaskClick(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string name } || WindowByName(name) is not { } window)
        {
            return;
        }

        if (window.IsVisible && _activeWindow == window)
        {
            OnDesktopMinimize(new Button { Tag = name }, e);
        }
        else
        {
            ActivateWindow(window);
        }
    }

    // HIG: taskbar buttons carry a context menu (show/minimize/close).
    private void AttachTaskContextMenu(Button task)
    {
        var flyout = new MenuFlyout();
        var show = new MenuItem { Header = "Show" };
        show.Click += (_, _) =>
        {
            if (task.Tag is string name && WindowByName(name) is { } window) ShowWindow(window);
        };
        var minimize = new MenuItem { Header = "Minimize" };
        minimize.Click += (_, _) =>
        {
            if (task.Tag is string name) OnDesktopMinimize(new Button { Tag = name }, new RoutedEventArgs());
        };
        var close = new MenuItem { Header = "Close" };
        close.Click += (_, _) =>
        {
            if (task.Tag is string name) OnDesktopClose(new Button { Tag = name }, new RoutedEventArgs());
        };
        var pin = new MenuItem { Header = "Always on top" };
        pin.Click += (_, _) =>
        {
            if (task.Tag is not string name || WindowByName(name) is not { } window)
            {
                return;
            }

            if (!_alwaysOnTop.Remove(window))
            {
                _alwaysOnTop.Add(window);
            }

            pin.Header = _alwaysOnTop.Contains(window) ? "✓ Always on top" : "Always on top";
            ReassertAlwaysOnTop();
        };
        flyout.Items.Add(show);
        flyout.Items.Add(minimize);
        flyout.Items.Add(close);
        flyout.Items.Add(pin);
        task.ContextFlyout = flyout;
    }

    // HIG: window layout persists between sessions.
    private static string LayoutPath()
    {
        if (Directory.Exists("/System/State"))
        {
            Directory.CreateDirectory("/System/State/Workbench");
            return "/System/State/Workbench/Layout.config";
        }

        var directory = IOPath.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MixtarWorkbench");
        Directory.CreateDirectory(directory);
        return IOPath.Combine(directory, "layout.config");
    }

    private void SaveLayout()
    {
        try
        {
            var lines = DesktopWindows().Select(window => string.Create(CultureInfo.InvariantCulture,
                $"{window.Name}={Canvas.GetLeft(window):0},{Canvas.GetTop(window):0},{window.Width:0},{window.Height:0},{(window.IsVisible ? 1 : 0)}"));
            File.WriteAllLines(LayoutPath(), lines);
        }
        catch
        {
        }
    }

    private void LoadLayout()
    {
        try
        {
            var path = LayoutPath();
            if (!File.Exists(path))
            {
                return;
            }

            foreach (var line in File.ReadAllLines(path))
            {
                var separator = line.IndexOf('=');
                if (separator <= 0)
                {
                    continue;
                }

                var window = WindowByName(line[..separator]);
                var parts = line[(separator + 1)..].Split(',');
                if (window is null || parts.Length < 5)
                {
                    continue;
                }

                if (double.TryParse(parts[0], CultureInfo.InvariantCulture, out var left))
                    Canvas.SetLeft(window, left);
                if (double.TryParse(parts[1], CultureInfo.InvariantCulture, out var top))
                    Canvas.SetTop(window, Math.Max(8, top));
                if (double.TryParse(parts[2], CultureInfo.InvariantCulture, out var width) && width >= 200)
                    window.Width = width;
                if (double.TryParse(parts[3], CultureInfo.InvariantCulture, out var height) && height >= 120)
                    window.Height = height;

                var visible = parts[4] == "1";
                window.IsVisible = visible;
                if (TaskFor(window) is { } task)
                {
                    if (visible)
                    {
                        task.IsVisible = true;
                        task.Classes.Remove("minimized");
                    }
                    else if (window != NetworkWindow)
                    {
                        task.Classes.Add("minimized");
                    }
                }
            }

            _windowsPlaced = true;
        }
        catch
        {
        }
    }

    private void ShowWindow(Border window)
    {
        if (TaskFor(window) is { } task)
        {
            task.IsVisible = true;
            task.Classes.Remove("minimized");
        }

        ActivateWindow(window);
    }

}
