using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using IOPath = System.IO.Path;

namespace Mixtar.Product.Workbench;

public sealed partial class MainWindow
{
    // Theme API v1: a plain "key = value" file the user edits to recolor the
    // shell without rebuilding it. Values are #RRGGBB / #AARRGGBB, or
    // gradient(c1, c2[, c3[, c4]][, horizontal]). Gradients run top to
    // bottom unless "horizontal" is appended. Color-count semantics:
    //   2 = plain fade, 3 = top/middle/bottom,
    //   4 = aero gloss: the middle pair sits on both sides of the 50% line.
    // The overrides MUTATE the shared brush instances from Theme.axaml, so
    // every StaticResource reference picks them up.
    private static readonly Dictionary<string, string> ThemeKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        ["panel"] = "PanelBrush",
        ["stroke"] = "StrokeBrush",
        ["accent"] = "AccentBrush",
        ["text"] = "TextBrush",
        ["caption.hover"] = "CaptionHoverBrush",
        ["caption.close"] = "CaptionCloseHoverBrush"
    };

    private static string ThemePath() => Directory.Exists("/System/Configuration")
        ? "/System/Configuration/Product/Theme.config"
        : IOPath.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MixtarWorkbench", "Theme.config");

    private void LoadThemeOverrides()
    {
        try
        {
            var path = ThemePath();
            if (!File.Exists(path))
            {
                WriteThemeTemplate(path);
                return;
            }

            foreach (var line in File.ReadAllLines(path))
            {
                var trimmed = line.Trim();
                if (trimmed.Length == 0 || trimmed.StartsWith('#'))
                {
                    continue;
                }

                var split = trimmed.Split('=', 2);
                if (split.Length != 2 || !ThemeKeys.TryGetValue(split[0].Trim(), out var resource))
                {
                    continue;
                }

                try
                {
                    ApplyThemeValue(resource, split[1].Trim());
                }
                catch
                {
                    // One bad value must not spoil the remaining lines.
                }
            }
        }
        catch
        {
            // A broken theme file must never take the shell down.
        }
    }

    private void ApplyThemeValue(string resourceKey, string value)
    {
        if (!this.TryFindResource(resourceKey, out var existing))
        {
            return;
        }

        if (value.StartsWith("gradient(", StringComparison.OrdinalIgnoreCase) && value.EndsWith(')'))
        {
            if (existing is not LinearGradientBrush gradient)
            {
                return;
            }

            var parts = value["gradient(".Length..^1]
                .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            var horizontal = parts.Length > 0 &&
                parts[^1].Equals("horizontal", StringComparison.OrdinalIgnoreCase);
            var colors = (horizontal ? parts[..^1] : parts).Select(Color.Parse).ToList();
            if (colors.Count is < 2 or > 4)
            {
                return;
            }

            var stops = colors.Count switch
            {
                2 => new[] { (colors[0], 0.0), (colors[1], 1.0) },
                3 => new[] { (colors[0], 0.0), (colors[1], 0.5), (colors[2], 1.0) },
                _ => new[] { (colors[0], 0.0), (colors[1], 0.49), (colors[2], 0.5), (colors[3], 1.0) }
            };
            gradient.GradientStops.Clear();
            foreach (var (color, offset) in stops)
            {
                gradient.GradientStops.Add(new GradientStop(color, offset));
            }

            gradient.StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative);
            gradient.EndPoint = horizontal
                ? new RelativePoint(1, 0, RelativeUnit.Relative)
                : new RelativePoint(0, 1, RelativeUnit.Relative);
        }
        else
        {
            // A plain color is valid for every key: on a gradient brush it
            // collapses the stops, giving a flat (Windows-basic) hover.
            var color = Color.Parse(value);
            switch (existing)
            {
                case SolidColorBrush solid:
                    solid.Color = color;
                    break;
                case LinearGradientBrush gradient:
                    gradient.GradientStops.Clear();
                    gradient.GradientStops.Add(new GradientStop(color, 0));
                    gradient.GradientStops.Add(new GradientStop(color, 1));
                    break;
            }
        }
    }

    // Settings writes personalization through the same file the user can
    // edit by hand - one source of truth, applied live via brush mutation.
    private void SetThemeOption(string key, string value)
    {
        if (ThemeKeys.TryGetValue(key, out var resource))
        {
            try
            {
                ApplyThemeValue(resource, value);
            }
            catch
            {
            }
        }

        try
        {
            var path = ThemePath();
            var lines = File.Exists(path) ? File.ReadAllLines(path).ToList() : new List<string>();
            lines.RemoveAll(line =>
            {
                var trimmed = line.TrimStart();
                return !trimmed.StartsWith('#') &&
                    trimmed.Split('=', 2)[0].Trim().Equals(key, StringComparison.OrdinalIgnoreCase);
            });
            lines.Add($"{key} = {value}");
            Directory.CreateDirectory(IOPath.GetDirectoryName(path)!);
            File.WriteAllLines(path, lines);
        }
        catch
        {
            // Personalization still applies for this session even when the
            // configuration tree is read-only.
        }
    }

    // First run drops a fully commented template so the keys are
    // discoverable without documentation hunting.
    private static void WriteThemeTemplate(string path)
    {
        try
        {
            Directory.CreateDirectory(IOPath.GetDirectoryName(path)!);
            File.WriteAllText(path,
                "# MixtarRVS Workbench - user theme (Theme API v1)\n" +
                "# Uncomment a key to override the default color.\n" +
                "# gradient(...) takes 2-4 colors, top to bottom; append\n" +
                "# \", horizontal\" to rotate. 2 = plain fade, 3 = top/middle/\n" +
                "# bottom, 4 = aero gloss break at the 50% line. A single color\n" +
                "# on a gradient key gives a flat hover instead.\n" +
                "#\n" +
                "# accent        = #18B9FF\n" +
                "# panel         = #D914161A\n" +
                "# stroke        = #26FFFFFF\n" +
                "# text          = #E8EEF7\n" +
                "# caption.hover = gradient(#5BA4E5, #4388CC, #2969AD, #1C528F)\n" +
                "# caption.close = gradient(#E85F51, #D34031, #B52B1E, #8E1C12)\n");
        }
        catch
        {
            // Read-only configuration tree - the defaults simply stay.
        }
    }
}
