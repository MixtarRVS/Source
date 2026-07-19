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

namespace Mixtar.UX.Workbench;

public sealed partial class MainWindow
{
    // Terminal: honest built-ins on real data
    // ------------------------------------------------------------------

    private void OnTerminalKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Up && _commandHistory.Count > 0)
        {
            _commandHistoryIndex = _commandHistoryIndex <= 0 ? 0 : _commandHistoryIndex - 1;
            TerminalInput.Text = _commandHistory[_commandHistoryIndex];
            TerminalInput.CaretIndex = TerminalInput.Text.Length;
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Down && _commandHistory.Count > 0)
        {
            if (_commandHistoryIndex >= _commandHistory.Count - 1)
            {
                _commandHistoryIndex = _commandHistory.Count;
                TerminalInput.Text = string.Empty;
            }
            else
            {
                _commandHistoryIndex++;
                TerminalInput.Text = _commandHistory[_commandHistoryIndex];
                TerminalInput.CaretIndex = TerminalInput.Text.Length;
            }

            e.Handled = true;
            return;
        }

        if (e.Key != Key.Enter) return;

        var command = TerminalInput.Text?.Trim() ?? string.Empty;
        if (command.Length == 0) return;

        _commandHistory.Add(command);
        _commandHistoryIndex = _commandHistory.Count;
        AppendTerminal($"{TerminalPrompt.Text} {command}", "#FFFFFF");
        TerminalInput.Text = string.Empty;
        RunCommand(command);
        e.Handled = true;
    }

    private void RunCommand(string command)
    {
        var parts = command.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
        var argument = parts.Length > 1 ? parts[1].Trim() : string.Empty;

        switch (parts[0].ToLowerInvariant())
        {
            case "clear":
                TerminalLines.Children.Clear();
                break;
            case "help":
                AppendTerminal("built-ins: sysinfo ls [path] cd <path> pwd cat <file> uname ps free df mount state date echo clear", "#91B7E8");
                AppendTerminal("windows  : files runtime network settings", "#91B7E8");
                break;
            case "sysinfo":
                AppendSysinfo();
                break;
            case "uname":
                AppendTerminal(KernelDescription(), "#91B7E8");
                break;
            case "date":
                AppendTerminal(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss zzz", CultureInfo.InvariantCulture), "#91B7E8");
                break;
            case "echo":
                AppendTerminal(argument, "#91B7E8");
                break;
            case "pwd":
                AppendTerminal(_currentPath, "#91B7E8");
                break;
            case "cd":
                var destination = argument.Length > 0 ? argument : "/";
                if (!destination.StartsWith('/') && !(destination.Length >= 2 && destination[1] == ':'))
                {
                    destination = IOPath.Combine(_currentPath, destination);
                }

                Navigate(destination, recordHistory: true);
                break;
            case "ps":
                foreach (var (name, rss) in TopProcesses(10))
                {
                    AppendTerminal($"{(rss > 0 ? FormatSize(rss) : ""),10}  {name}", "#91B7E8");
                }

                AppendTerminal($"total: {CountProcesses()} processes", "#91B7E8");
                break;
            case "free":
                var (memTotal, memAvailable) = ReadMemory();
                AppendTerminal(memTotal > 0
                        ? $"memory: {FormatSize(memTotal * 1024)} total, {FormatSize(memAvailable * 1024)} available"
                        : "memory: no /System/Processes/meminfo on this host",
                    "#91B7E8");
                break;
            case "df":
                foreach (var drive in DriveInfo.GetDrives().Where(item => item.IsReady))
                {
                    AppendTerminal(
                        $"{drive.Name,-24} {FormatSize(drive.AvailableFreeSpace),10} free of {FormatSize(drive.TotalSize)}",
                        "#91B7E8");
                }
                break;
            case "mount":
                var shown = 0;
                try
                {
                    foreach (var line in File.ReadLines(IOPath.Combine(ProcRoot, "mounts")))
                    {
                        AppendTerminal(line, "#9FC5F4");
                        if (++shown >= 25)
                        {
                            AppendTerminal("... (truncated)", "#668AB9");
                            break;
                        }
                    }
                }
                catch
                {
                }

                if (shown == 0)
                {
                    AppendTerminal("mount table unavailable on this host (try df)", "#FFC65C");
                }
                break;
            case "state":
                AppendTerminal($"graphics : {(StateReady("Graphics/Status.config") ? "ready" : "down")}", "#91B7E8");
                AppendTerminal($"volumes  : {(StateReady("Volumes/Status.config") ? "mounted" : "none")}", "#91B7E8");
                AppendTerminal($"logging  : {(StateReady("Logging/System.config") ? "ready" : "down")}", "#91B7E8");
                break;
            case "ls":
                var target = argument.Length > 0 ? NormalizePath(argument) : _currentPath;
                foreach (var entry in SortEntries(ListDirectory(target)).Take(60))
                {
                    AppendTerminal($"{entry.Type,-5} {entry.Size,10}  {entry.Name}", "#91B7E8");
                }
                break;
            case "cat":
                RunCat(argument);
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
            default:
                AppendTerminal("unknown built-in (real zsh session is on the roadmap) - type 'help'", "#FFC65C");
                break;
        }

        TerminalScroll.ScrollToEnd();
    }

    private void RunCat(string argument)
    {
        if (argument.Length == 0)
        {
            AppendTerminal("cat: missing file path", "#FF5C7B");
            return;
        }

        var path = argument.StartsWith('/') || (argument.Length >= 2 && argument[1] == ':')
            ? argument
            : IOPath.Combine(_currentPath, argument);
        try
        {
            var shown = 0;
            foreach (var line in File.ReadLines(path))
            {
                AppendTerminal(line.Length > 400 ? line[..400] : line, "#9FC5F4");
                if (++shown >= 60)
                {
                    AppendTerminal("... (truncated at 60 lines)", "#668AB9");
                    break;
                }
            }

            if (shown == 0)
            {
                AppendTerminal("(empty file)", "#668AB9");
            }
        }
        catch (Exception error)
        {
            AppendTerminal($"cat: {error.Message}", "#FF5C7B");
        }
    }

    private StackPanel? _outputTarget;

    private void AppendTerminal(string text, string color)
    {
        (_outputTarget ?? TerminalLines).Children.Add(new TextBlock
        {
            Text = text,
            Tag = color,
            Foreground = TerminalOutputBrush(color),
            FontFamily = new FontFamily("Noto Sans Mono"),
            FontSize = 10,
            TextWrapping = TextWrapping.Wrap
        });

        var target = _outputTarget ?? TerminalLines;
        if (target.Children.Count > 400)
        {
            target.Children.RemoveRange(0, target.Children.Count - 400);
        }
    }

    private Avalonia.Media.IBrush TerminalOutputBrush(string color)
    {
        if (!string.Equals(_activeThemeMode, "day", StringComparison.OrdinalIgnoreCase))
        {
            return new SolidColorBrush(Color.Parse(color));
        }

        return color.ToUpperInvariant() switch
        {
            "#FFFFFF" => Token("TextBrush"),
            "#91B7E8" => Token("InfoBrush"),
            "#9FC5F4" => Token("MonoBrush"),
            "#668AB9" => Token("MutedBrush"),
            _ => new SolidColorBrush(Color.Parse(color))
        };
    }

    private void RefreshTerminalOutputColors()
    {
        if (TerminalLines is null)
        {
            return;
        }

        foreach (var child in TerminalLines.Children)
        {
            if (child is TextBlock line && line.Tag is string color)
            {
                line.Foreground = TerminalOutputBrush(color);
            }
        }
    }

    // ------------------------------------------------------------------
}
