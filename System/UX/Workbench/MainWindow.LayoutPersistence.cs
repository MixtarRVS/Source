using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using Avalonia.Controls;

namespace Mixtar.UX.Workbench;

public sealed partial class MainWindow
{
    private void SaveLayout()
    {
        var lines = new List<string> { "schema = 1" };
        foreach (var window in DesktopWindows())
        {
            if (string.IsNullOrWhiteSpace(window.Name)) continue;
            var left = Canvas.GetLeft(window); var top = Canvas.GetTop(window);
            if (double.IsNaN(left)) left = 0; if (double.IsNaN(top)) top = 0;
            var width = double.IsNaN(window.Width) ? window.Bounds.Width : window.Width;
            var height = double.IsNaN(window.Height) ? window.Bounds.Height : window.Height;
            lines.Add(string.Empty); lines.Add($"[windows.{window.Name}]");
            lines.Add($"x = {WorkbenchConfig.Number(left)}"); lines.Add($"y = {WorkbenchConfig.Number(top)}");
            lines.Add($"width = {WorkbenchConfig.Number(width)}"); lines.Add($"height = {WorkbenchConfig.Number(height)}");
            lines.Add($"visible = {window.IsVisible.ToString().ToLowerInvariant()}");
        }
        try { WorkbenchConfig.AtomicWrite(WorkbenchConfig.LayoutPath(), lines); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { Console.Error.WriteLine($"Workbench: could not save layout: {error.Message}"); }
    }

    private void LoadLayout()
    {
        var path = WorkbenchConfig.LayoutPath();
        if (!File.Exists(path)) return;
        try
        {
            var values = WorkbenchConfig.ReadFlatToml(path); WorkbenchConfig.RequireSchema(values, path);
            foreach (var window in DesktopWindows())
            {
                if (string.IsNullOrWhiteSpace(window.Name)) continue;
                var prefix = $"windows.{window.Name}.";
                if (!TryDouble(values, prefix + "x", out var x) || !TryDouble(values, prefix + "y", out var y)
                    || !TryDouble(values, prefix + "width", out var width)
                    || !TryDouble(values, prefix + "height", out var height)) continue;
                Canvas.SetLeft(window, x); Canvas.SetTop(window, y);
                window.Width = Math.Max(220, width); window.Height = Math.Max(140, height);
                if (values.TryGetValue(prefix + "visible", out var visible) && bool.TryParse(visible, out var parsed))
                    window.IsVisible = parsed;
            }
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException)
        { Console.Error.WriteLine($"Workbench: ignoring invalid layout configuration: {error.Message}"); }
    }

    private static bool TryDouble(IReadOnlyDictionary<string, string> values, string key, out double value)
    {
        value = 0;
        return values.TryGetValue(key, out var text)
            && double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out value);
    }
}
