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
    // Actions
    // ------------------------------------------------------------------

    private void OnAction(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not string action)
        {
            return;
        }

        if (action == "start")
        {
            StartMenu.IsVisible = !StartMenu.IsVisible;
            CommandPalette.IsVisible = false;
            return;
        }

        if (action.StartsWith("scale:", StringComparison.Ordinal))
        {
            _scaleMode = action[6..];
            ApplyScale();
            return;
        }

        switch (action)
        {
            case "terminal":
                ShowWindow(TerminalWindow);
                break;
            case "files":
                ShowWindow(FilesWindow);
                break;
            case "runtime":
                ShowWindow(RuntimeWindow);
                break;
            case "network":
                ShowWindow(NetworkWindow);
                break;
            case "settings":
                ShowWindow(SettingsWindow);
                break;
            case "root":
                ShowWindow(FilesWindow);
                Navigate("/", recordHistory: true);
                break;
            case "home":
                ShowWindow(FilesWindow);
                Navigate(Directory.Exists("/Users") ? "/Users" : StartPath(), recordHistory: true);
                break;
            case "showdesktop":
                ToggleShowDesktop();
                return;
            case "apx":
                ShowWindow(FilesWindow);
                Navigate("/Applications", recordHistory: true);
                break;
            case "back":
                NavigateHistory(-1);
                break;
            case "forward":
                NavigateHistory(1);
                break;
            case "up":
                Navigate(ParentPath(_currentPath), recordHistory: true);
                break;
            case "reload":
                RenderFiles();
                break;
            case "newfolder":
                CreateNewFolder();
                break;
            case "delete":
                DeleteSelected();
                break;
            case "verify":
                ShowWindow(TerminalWindow);
                RunCommand("state");
                break;
            case "reboot":
                RunPowerCommand("-r");
                break;
            case "poweroff":
                RunPowerCommand("-p");
                break;
        }

        StartMenu.IsVisible = false;
        CommandPalette.IsVisible = false;
    }

    private void RunPowerCommand(string argument)
    {
        AppendTerminal($"openrc-shutdown {argument} now", "#FFC65C");
        try
        {
            System.Diagnostics.Process.Start("/System/Init/openrc-shutdown", $"{argument} now");
        }
        catch (Exception error)
        {
            AppendTerminal($"shutdown failed: {error.Message}", "#FF5C7B");
        }
    }

    private void OnNetworkNode(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id } || !_nodes.TryGetValue(id, out var node))
        {
            return;
        }

        NodeName.Text = node.Name;
        NodeIp.Text = node.Address;
        NodeLocation.Text = node.Location;
    }

    // ------------------------------------------------------------------
}
