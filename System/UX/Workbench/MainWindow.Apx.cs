using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Avalonia.Controls;
using Avalonia.Interactivity;

namespace Mixtar.UX.Workbench;

public sealed partial class MainWindow
{
    private void InitializeApxApplications()
    {
        ApxAppsPanel.Children.Clear();
        var bundles = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var root in new[] { "/Applications", "/System/Applications" })
        {
            try
            {
                if (!Directory.Exists(root)) continue;
                foreach (var path in Directory.EnumerateDirectories(root, "*.apx", SearchOption.TopDirectoryOnly))
                    bundles.Add(path);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            { Console.Error.WriteLine($"Workbench: could not enumerate APX bundles in {root}: {error.Message}"); }
        }
        if (bundles.Count == 0)
        {
            ApxAppsPanel.Children.Add(new TextBlock { Text = "No graphical APX applications installed", FontSize = 10 });
            return;
        }
        foreach (var bundle in bundles)
        {
            var button = new Button { Content = Path.GetFileNameWithoutExtension(bundle), Tag = bundle };
            button.Classes.Add("tree"); button.Click += OnApxApplicationClick; ApxAppsPanel.Children.Add(button);
        }
    }

    private void OnApxApplicationClick(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string bundle }) return;
        StartMenu.IsVisible = false;
        var executor = "/System/Runtime/Executor";
        var user = Environment.GetEnvironmentVariable("MIXTAR_USER") ?? string.Empty;
        var session = Environment.GetEnvironmentVariable("MIXTAR_SESSION_ID") ?? string.Empty;
        if (!File.Exists(executor) || string.IsNullOrWhiteSpace(user) || string.IsNullOrWhiteSpace(session))
        { StateLines.Text = "APX launch unavailable: no active Mixtar graphical session"; return; }
        try
        {
            var start = new ProcessStartInfo { FileName = executor, UseShellExecute = false,
                RedirectStandardInput = false, RedirectStandardOutput = false, RedirectStandardError = false };
            foreach (var argument in new[] { "launch", "--context", "graphical", "--user", user,
                "--session", session, bundle }) start.ArgumentList.Add(argument);
            Process.Start(start);
            StateLines.Text = $"APX launch requested: {Path.GetFileName(bundle)}";
        }
        catch (Exception error) when (error is IOException or InvalidOperationException)
        { StateLines.Text = $"APX launch failed: {error.Message}"; }
    }
}
