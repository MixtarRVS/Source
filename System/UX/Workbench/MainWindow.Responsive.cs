using System;
using System.IO;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;

namespace Mixtar.UX.Workbench;

public sealed partial class MainWindow
{
    private const double DesignWidth = 1280;
    private const double DesignHeight = 800;
    private double _interfaceScale = 1;
    private Size _lastViewport;
    private bool _responsiveLayoutReady;

    private void OnWorkbenchOpened(object? sender, EventArgs e)
    {
        _interfaceScale = 1; ScaleHost.LayoutTransform = null;
        ScaleInfo.Text = "Auto: compositor DPI, 100% logical scale";
        InitializeApxApplications();
        ReflowDesktop(RootLayout.Bounds.Size, initial: true);
    }

    private void OnResponsiveViewportChanged(object? sender, SizeChangedEventArgs e) =>
        ReflowDesktop(e.NewSize, initial: !_responsiveLayoutReady);

    private void OnScaleClick(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag }) return;
        if (tag.Equals("scale:auto", StringComparison.Ordinal))
        { _interfaceScale = 1; ScaleInfo.Text = "Auto: compositor DPI, 100% logical scale"; }
        else if (tag.StartsWith("scale:", StringComparison.Ordinal)
            && double.TryParse(tag["scale:".Length..], System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var scale))
        { _interfaceScale = Math.Clamp(scale, 0.75, 2.0); ScaleInfo.Text = $"Manual logical scale: {_interfaceScale:P0}"; }
        ScaleHost.LayoutTransform = Math.Abs(_interfaceScale - 1) < 0.001
            ? null : new ScaleTransform(_interfaceScale, _interfaceScale);
        ReflowDesktop(RootLayout.Bounds.Size, initial: false);
    }

    private void ReflowDesktop(Size rawViewport, bool initial)
    {
        if (rawViewport.Width < 1 || rawViewport.Height < 1) return;
        var viewport = new Size(rawViewport.Width / _interfaceScale, rawViewport.Height / _interfaceScale);
        var persisted = File.Exists(WorkbenchConfig.LayoutPath());
        double shiftX; double shiftY;
        if (initial && !persisted)
        { shiftX = (viewport.Width - DesignWidth) / 2; shiftY = (viewport.Height - DesignHeight) / 2; }
        else if (_responsiveLayoutReady)
        { shiftX = (viewport.Width - _lastViewport.Width) / 2; shiftY = (viewport.Height - _lastViewport.Height) / 2; }
        else { shiftX = 0; shiftY = 0; }
        foreach (var window in DesktopWindows())
        {
            var left = Canvas.GetLeft(window); var top = Canvas.GetTop(window);
            if (double.IsNaN(left)) left = 12; if (double.IsNaN(top)) top = 48;
            left += shiftX; top += shiftY;
            var width = double.IsNaN(window.Width) ? window.Bounds.Width : window.Width;
            var height = double.IsNaN(window.Height) ? window.Bounds.Height : window.Height;
            var maximumLeft = Math.Max(12, viewport.Width - Math.Max(120, width) - 12);
            var maximumTop = Math.Max(42, viewport.Height - Math.Max(100, height) - 60);
            Canvas.SetLeft(window, Math.Clamp(left, 12, maximumLeft));
            Canvas.SetTop(window, Math.Clamp(top, 42, maximumTop));
        }
        _lastViewport = viewport; _responsiveLayoutReady = true; RedrawBackgroundGrid(viewport);
    }
}
