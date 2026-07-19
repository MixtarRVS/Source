using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;

namespace Mixtar.UX.Workbench;

public sealed partial class MainWindow
{
    private static readonly IReadOnlyDictionary<string, string> ThemeKeys =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["accent"] = "AccentBrush", ["desktop"] = "DesktopBrush", ["panel"] = "PanelBrush",
            ["card"] = "CardBrush", ["sidebar"] = "SidebarBrush", ["taskbar"] = "TaskbarBrush",
            ["terminal"] = "TerminalBackBrush", ["text"] = "TextBrush", ["title"] = "TitleBrush",
            ["heading"] = "HeadingBrush", ["info"] = "InfoBrush", ["soft"] = "SoftBrush",
            ["list"] = "ListTextBrush", ["muted"] = "MutedBrush", ["success"] = "SuccessBrush",
            ["warning"] = "WarningBrush", ["danger"] = "DangerBrush",
            ["selection.hover"] = "RowHoverBrush", ["selection.active"] = "RowSelectedBrush",
            ["stroke"] = "StrokeBrush", ["hairline"] = "HairlineBrush", ["start"] = "StartBrush",
            ["caption.hover"] = "CaptionHoverBrush", ["caption.close"] = "CaptionCloseHoverBrush"
        };

    private void LoadThemeOverrides() => LoadTheme();

    private IBrush Token(string resourceKey)
    {
        return this.TryFindResource(resourceKey, out var value) && value is IBrush brush
            ? brush
            : Brushes.Transparent;
    }

    private void LoadTheme()
    {
        ApplyThemeMode("night");
        ApplyThemeFile(WorkbenchConfig.SystemThemePath, required: false);
        var userPath = WorkbenchConfig.ThemePath();
        if (!File.Exists(userPath)) WriteThemeTemplate(userPath);
        ApplyThemeFile(userPath, required: false);
    }

    private void ApplyThemeFile(string path, bool required)
    {
        if (!File.Exists(path))
        {
            if (required) throw new FileNotFoundException("Theme configuration is missing.", path);
            return;
        }
        try
        {
            var values = WorkbenchConfig.ReadFlatToml(path);
            WorkbenchConfig.RequireSchema(values, path);
            if (values.TryGetValue("theme.mode", out var mode)) ApplyThemeMode(mode);
            foreach (var pair in values.Where(pair => pair.Key.StartsWith("theme.", StringComparison.Ordinal)))
            {
                var key = pair.Key["theme.".Length..];
                if (ThemeKeys.TryGetValue(key, out var resource)) ApplyThemeValue(resource, pair.Value);
            }
        }
        catch (Exception error) when (error is IOException or InvalidDataException or FormatException or UnauthorizedAccessException)
        { Console.Error.WriteLine($"Workbench: invalid theme configuration {path}: {error.Message}"); }
    }

    private void ApplyThemeValue(string resourceKey, string value)
    {
        if (!this.TryFindResource(resourceKey, out var existing)) return;
        if (value.StartsWith("gradient(", StringComparison.OrdinalIgnoreCase) && value.EndsWith(')'))
        {
            if (existing is not LinearGradientBrush gradient) return;
            var parts = value["gradient(".Length..^1]
                .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            var horizontal = parts.Length > 0 && parts[^1].Equals("horizontal", StringComparison.OrdinalIgnoreCase);
            var colors = (horizontal ? parts[..^1] : parts).Select(Color.Parse).ToList();
            if (colors.Count is < 2 or > 4) return;
            var stops = colors.Count switch
            {
                2 => new[] { (colors[0], 0.0), (colors[1], 1.0) },
                3 => new[] { (colors[0], 0.0), (colors[1], 0.5), (colors[2], 1.0) },
                _ => new[] { (colors[0], 0.0), (colors[1], 0.49), (colors[2], 0.5), (colors[3], 1.0) }
            };
            gradient.GradientStops.Clear();
            foreach (var (color, offset) in stops) gradient.GradientStops.Add(new GradientStop(color, offset));
            gradient.StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative);
            gradient.EndPoint = horizontal ? new RelativePoint(1, 0, RelativeUnit.Relative)
                : new RelativePoint(0, 1, RelativeUnit.Relative);
            return;
        }
        var parsed = Color.Parse(value);
        switch (existing)
        {
            case SolidColorBrush solid: solid.Color = parsed; break;
            case LinearGradientBrush gradient:
                gradient.GradientStops.Clear();
                gradient.GradientStops.Add(new GradientStop(parsed, 0));
                gradient.GradientStops.Add(new GradientStop(parsed, 1));
                break;
        }
    }

    private void OnThemeModeClick(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string mode }) SetThemeMode(mode);
    }

    private void SetThemeMode(string mode)
    {
        mode = mode.Equals("day", StringComparison.OrdinalIgnoreCase) ? "day" : "night";
        var path = WorkbenchConfig.ThemePath();
        var current = new Dictionary<string, string>(StringComparer.Ordinal);
        if (File.Exists(path))
        {
            try
            {
                var loaded = WorkbenchConfig.ReadFlatToml(path);
                WorkbenchConfig.RequireSchema(loaded, path);
                foreach (var pair in loaded.Where(pair => pair.Key.StartsWith("theme.", StringComparison.Ordinal)))
                    current[pair.Key["theme.".Length..]] = pair.Value;
            }
            catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException)
            { Console.Error.WriteLine($"Workbench: replacing invalid theme configuration: {error.Message}"); }
        }
        current["mode"] = mode;
        var lines = new List<string> { "schema = 1", "", "[theme]" };
        lines.AddRange(current.OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .Select(pair => $"{pair.Key} = {WorkbenchConfig.TomlString(pair.Value)}"));
        try
        {
            WorkbenchConfig.AtomicWrite(path, lines);
            ApplyThemeFile(path, required: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { Console.Error.WriteLine($"Workbench: could not save theme mode: {error.Message}"); }
    }

    private string _activeThemeMode = "night";

    private void ApplyThemeMode(string mode)
    {
        var day = mode.Equals("day", StringComparison.OrdinalIgnoreCase);
        _activeThemeMode = day ? "day" : "night";
        RequestedThemeVariant = day
            ? Avalonia.Styling.ThemeVariant.Light
            : Avalonia.Styling.ThemeVariant.Dark;
        var palette = day ? DayPalette : NightPalette;
        foreach (var pair in palette) ApplyThemeValue(pair.Key, pair.Value);
        Foreground = Token("TextBrush");
        RefreshTerminalOutputColors();
        if (ThemeInfo is not null)
            ThemeInfo.Text = day ? "Day client, Faux Aero frame (no blur)" : "Night client, Faux Aero frame (no blur)";
    }

    private static readonly IReadOnlyDictionary<string, string> NightPalette =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["ClientBrush"] = "#FF1E1E1E", ["PanelSoftBrush"] = "#E6191B20",
            ["MenuBrush"] = "#F214161A", ["OverlayBrush"] = "#F514161A",
            ["CardBrush"] = "#E01B1E24", ["HeaderBackBrush"] = "#FF1E1E1E",
            ["CommandBarBorderBrush"] = "#FF333333", ["SidebarBorderBrush"] = "#FF333333",
            ["SidebarBrush"] = "#FF1E1E1E", ["StatusBackBrush"] = "#FF1E1E1E",
            ["TerminalBackBrush"] = "#FF1E1E1E",
            ["InputBackBrush"] = "#FF2D2D30", ["InputSoftBrush"] = "#FF2D2D30",
            ["ToolBackBrush"] = "#FF262A31", ["TextBrush"] = "#FFD4D4D4",
            ["MonoBrush"] = "#FFC4DCFF", ["HeadingBrush"] = "#FF8FC1FF",
            ["InfoBrush"] = "#FF91B7E8", ["SoftBrush"] = "#FF9EC1EF",
            ["ListTextBrush"] = "#FFD8E7FF", ["TabTextBrush"] = "#FFB0B0B0",
            ["TabActiveTextBrush"] = "#FFFFFFFF",
            ["MutedBrush"] = "#FF668AB9", ["RowHoverBrush"] = "#FF3E3E42",
            ["RowSelectedBrush"] = "#FF2D2D30", ["TextSelectionBrush"] = "#703580DB",
            ["ItemHoverBrush"] = "#FF3E3E42", ["TabHoverBrush"] = "#0DFFFFFF",
            ["TabActiveBrush"] = "#FF1E1E1E", ["RowLineBrush"] = "#0EFFFFFF",
            ["TrackBrush"] = "#17FFFFFF", ["PaneBorderBrush"] = "#FF333333",
            ["InputBorderBrush"] = "#FF444444", ["ToolBorderBrush"] = "#47FFFFFF",
            ["StrokeBrush"] = "#26FFFFFF", ["StrokeStrongBrush"] = "#4DFFFFFF",
            ["HairlineBrush"] = "#1AFFFFFF", ["DividerBrush"] = "#20FFFFFF",
            ["AccentBrush"] = "#FF4A90E2",
            ["CaptionHoverBrush"] = "#FF4388CC",
            ["CaptionCloseHoverBrush"] = "#FFD34031",
            ["CaptionPressedBrush"] = "#FF1A3957",
            ["CaptionHoverGlyphBrush"] = "#FFFFFFFF",
            ["CaptionCloseGlyphBrush"] = "#FFFFFFFF"
        };

    private static readonly IReadOnlyDictionary<string, string> DayPalette = CreateDayPalette();

    private static IReadOnlyDictionary<string, string> CreateDayPalette()
    {
        // Literal body-light rules from dark_plex_aero_vs_faux_aero.html.
        // Shared frame, caption and inactive-tab rules remain inherited.
        return new Dictionary<string, string>(NightPalette, StringComparer.Ordinal)
        {
            ["ClientBrush"] = "#FFFFFFFF",
            ["PanelSoftBrush"] = "#FFFFFFFF",
            ["CardBrush"] = "#FFFFFFFF",
            ["MenuBrush"] = "#FFFAFAFA",
            ["HeaderBackBrush"] = "#FFFAFAFA",
            ["CommandBarBorderBrush"] = "#FFDDDDDD",
            ["SidebarBrush"] = "#FFF3F3F3",
            ["SidebarBorderBrush"] = "#FFEAEAEA",
            ["StatusBackBrush"] = "#FFFFFFFF",
            ["TerminalBackBrush"] = "#FFFFFFFF",
            ["InputBackBrush"] = "#FFFFFFFF",
            ["InputSoftBrush"] = "#FFFFFFFF",
            ["InputBorderBrush"] = "#FFCCCCCC",
            ["ToolBackBrush"] = "#FFFAFAFA",
            ["ToolBorderBrush"] = "#FFCCCCCC",
            ["TextBrush"] = "#FF222222",
            ["MonoBrush"] = "#FF294F70",
            ["HeadingBrush"] = "#FF222222",
            ["InfoBrush"] = "#FF365F84",
            ["SoftBrush"] = "#FF555555",
            ["ListTextBrush"] = "#FF333333",
            ["MutedBrush"] = "#FF666666",
            ["OverlayBrush"] = "#FFFFFFFF",
            ["RowHoverBrush"] = "#FFE5E5E5",
            ["RowSelectedBrush"] = "#FFE0EAF3",
            ["TextSelectionBrush"] = "#FFE0EAF3",
            ["ItemHoverBrush"] = "#FFE5E5E5",
            ["TabActiveBrush"] = "#FFFFFFFF",
            ["TabActiveTextBrush"] = "#FF000000",
            ["StrokeBrush"] = "#FFDDDDDD",
            ["StrokeStrongBrush"] = "#FFCCCCCC",
            ["HairlineBrush"] = "#FFEAEAEA",
            ["DividerBrush"] = "#FFDDDDDD",
            ["RowLineBrush"] = "#FFEAEAEA",
            ["TrackBrush"] = "#FFDDDDDD",
            ["PaneBorderBrush"] = "#FFEAEAEA",
            ["CaptionHoverBrush"] = "#FFD58A2F",
            ["CaptionCloseHoverBrush"] = "#FFD65D3F",
            ["CaptionPressedBrush"] = "#FFA8611F",
            ["CaptionHoverGlyphBrush"] = "#FF2A1B07",
            ["CaptionCloseGlyphBrush"] = "#FFFFFFFF"
        };
    }

    private void SetThemeOption(string key, string value)
    {
        if (!ThemeKeys.TryGetValue(key, out var resource)) return;
        ApplyThemeValue(resource, value);
        var path = WorkbenchConfig.ThemePath();
        var current = new Dictionary<string, string>(StringComparer.Ordinal);
        if (File.Exists(path))
        {
            try
            {
                var loaded = WorkbenchConfig.ReadFlatToml(path);
                WorkbenchConfig.RequireSchema(loaded, path);
                foreach (var pair in loaded.Where(pair => pair.Key.StartsWith("theme.", StringComparison.Ordinal)))
                    current[pair.Key["theme.".Length..]] = pair.Value;
            }
            catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException)
            { Console.Error.WriteLine($"Workbench: replacing invalid theme configuration: {error.Message}"); }
        }
        current[key] = value;
        var lines = new List<string> { "schema = 1", "", "[theme]" };
        lines.AddRange(current.OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .Select(pair => $"{pair.Key} = {WorkbenchConfig.TomlString(pair.Value)}"));
        try { WorkbenchConfig.AtomicWrite(path, lines); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { Console.Error.WriteLine($"Workbench: could not save theme configuration: {error.Message}"); }
    }

    private static void WriteThemeTemplate(string path)
    {
        var lines = new[]
        {
            "schema = 1", "", "# Mixtar Workbench user theme. Values are TOML strings.", "[theme]",
            "mode = \"night\"",
            "# accent = \"#18B9FF\"", "# desktop = \"#0B1220\"", "# panel = \"#D914161A\"",
            "# text = \"#E8EEF7\"", "# selection.hover = \"#273580DB\"",
            "# selection.active = \"#473580DB\"",
            "# caption.hover = \"#4388CC\"",
            "# caption.close = \"#D34031\""
        };
        try { WorkbenchConfig.AtomicWrite(path, lines); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { Console.Error.WriteLine($"Workbench: could not create theme template: {error.Message}"); }
    }
}
