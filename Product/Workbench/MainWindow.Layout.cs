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
    // UI scale
    // ------------------------------------------------------------------

    private double AutoScale()
    {
        // When the host compositor already applies a user-chosen DPI scale
        // (e.g. Windows at 125%), auto must not multiply on top of it. The
        // resolution heuristic only kicks in where no scaling exists yet -
        // which is exactly the Mixtar/MWM case.
        double osScaling = 1.0;
        try
        {
            osScaling = (Screens.Primary ?? Screens.All.FirstOrDefault())?.Scaling ?? 1.0;
        }
        catch
        {
        }

        if (osScaling > 1.05)
        {
            return 1.0;
        }

        var width = ClientSize.Width;
        var height = ClientSize.Height;
        if (width <= 0 || height <= 0)
        {
            return 1;
        }

        return Math.Clamp(Math.Min(width / 1500.0, height / 850.0), 1.0, 2.5);
    }

    private void ApplyScale()
    {
        var scale = _scaleMode == "auto"
            ? AutoScale()
            : double.Parse(_scaleMode, CultureInfo.InvariantCulture);
        ScaleHost.LayoutTransform = new ScaleTransform(scale, scale);
        ScaleInfo.Text = _scaleMode == "auto"
            ? $"auto ({scale * 100:0}%)"
            : $"fixed ({scale * 100:0}%)";
    }

    private Size _lastCanvasSize;

    private void OnRootSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        RedrawBackgroundGrid(e.NewSize);
        if (!_windowsPlaced)
        {
            _windowsPlaced = true;
            PlaceWindows(e.NewSize);
        }
        else if (_lastCanvasSize.Width > 0 && _lastCanvasSize.Height > 0 &&
                 e.NewSize.Width > 0 && e.NewSize != _lastCanvasSize)
        {
            // HIG: on resolution change the whole layout rescales
            // proportionally so windows can never get stranded off-screen.
            var ratioX = e.NewSize.Width / _lastCanvasSize.Width;
            var ratioY = e.NewSize.Height / _lastCanvasSize.Height;
            foreach (var window in DesktopWindows())
            {
                Canvas.SetLeft(window, Canvas.GetLeft(window) * ratioX);
                Canvas.SetTop(window, Math.Max(8, Canvas.GetTop(window) * ratioY));
                window.Width = Math.Max(260, window.Width * ratioX);
                window.Height = Math.Max(160, window.Height * ratioY);
            }

            foreach (var key in _restoreBounds.Keys.ToList())
            {
                var saved = _restoreBounds[key];
                _restoreBounds[key] = new DesktopBounds(saved.Left * ratioX, saved.Top * ratioY,
                    Math.Max(260, saved.Width * ratioX), Math.Max(160, saved.Height * ratioY));
            }
        }

        _lastCanvasSize = e.NewSize;
        ClampWindowsIntoView(e.NewSize);
    }

    private void PlaceWindows(Size size)
    {
        Canvas.SetLeft(TerminalWindow, Math.Max(16, size.Width * 0.03));
        Canvas.SetTop(TerminalWindow, 56);
        Canvas.SetLeft(FilesWindow, Math.Max(16, size.Width * 0.20));
        Canvas.SetTop(FilesWindow, Math.Max(120, size.Height * 0.42));
        Canvas.SetLeft(RuntimeWindow, Math.Max(16, size.Width - RuntimeWindow.Width - 28));
        Canvas.SetTop(RuntimeWindow, Math.Max(120, size.Height * 0.12));
        Canvas.SetLeft(ViewerWindow, Math.Max(16, size.Width * 0.30));
        Canvas.SetTop(ViewerWindow, Math.Max(90, size.Height * 0.15));
        Canvas.SetLeft(SettingsWindow, Math.Max(16, size.Width * 0.36));
        Canvas.SetTop(SettingsWindow, Math.Max(90, size.Height * 0.28));
        Canvas.SetLeft(NetworkWindow, Math.Max(16, size.Width * 0.42));
        Canvas.SetTop(NetworkWindow, 70);
    }

    private void RedrawBackgroundGrid(Size size)
    {
        GridLines.Children.Clear();
        var stroke = new SolidColorBrush(Color.Parse("#202569D2"));
        for (var x = 0d; x <= size.Width; x += 36)
        {
            GridLines.Children.Add(new Line
            {
                StartPoint = new Point(x, 0),
                EndPoint = new Point(x, size.Height),
                Stroke = stroke,
                StrokeThickness = 1
            });
        }

        for (var y = 0d; y <= size.Height; y += 36)
        {
            GridLines.Children.Add(new Line
            {
                StartPoint = new Point(0, y),
                EndPoint = new Point(size.Width, y),
                Stroke = stroke,
                StrokeThickness = 1
            });
        }
    }

    private void ClampWindowsIntoView(Size size)
    {
        foreach (var window in DesktopWindows())
        {
            var left = Canvas.GetLeft(window);
            var top = Canvas.GetTop(window);
            var maxLeft = Math.Max(0, size.Width - window.Width);
            var maxTop = Math.Max(40, size.Height - 48 - 34);
            Canvas.SetLeft(window, Math.Clamp(double.IsNaN(left) ? 0 : left, 0, maxLeft));
            Canvas.SetTop(window, Math.Clamp(double.IsNaN(top) ? 40 : top, 40, maxTop));
        }
    }

    private IEnumerable<Border> DesktopWindows() =>
        new[] { TerminalWindow, FilesWindow, RuntimeWindow, NetworkWindow, ViewerWindow, SettingsWindow };

    private void UpdateClock()
    {
        var clock = DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture);
        ClockText.Text = clock;
        TrayClock.Text = clock;
        DateText.Text = DateTime.Now.ToString("ddd dd.MM", CultureInfo.InvariantCulture);
    }

}
