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
    // Real system data
    // ------------------------------------------------------------------

    private static string ReadProcLine(string relative)
    {
        try
        {
            using var reader = new StreamReader(IOPath.Combine(ProcRoot, relative));
            return reader.ReadLine() ?? string.Empty;
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string IdentityValue(string key, string fallback)
    {
        try
        {
            foreach (var line in File.ReadLines(IdentityPath))
            {
                var separator = line.IndexOf('=');
                if (separator <= 0)
                {
                    continue;
                }

                if (!line[..separator].Trim().Equals(key, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var value = line[(separator + 1)..].Trim();
                if (value.Length >= 2 && value[0] == '"' && value[^1] == '"')
                {
                    value = value[1..^1];
                }

                return value.Length > 0 ? value : fallback;
            }
        }
        catch
        {
        }

        return fallback;
    }

    private static string KernelDescription()
    {
        var version = ReadProcLine("version");
        if (version.Length > 0)
        {
            var parts = version.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 3)
            {
                return $"{parts[0]} {parts[2]}";
            }
        }

        return RuntimeInformation.OSDescription;
    }

    private static string HostName()
    {
        var name = ReadProcLine("sys/kernel/hostname");
        if (name.Length > 0)
        {
            return name;
        }

        try
        {
            return Environment.MachineName.ToLowerInvariant();
        }
        catch
        {
            return "mixtar";
        }
    }

    private static (long Idle, long Total) ReadCpuSample()
    {
        var line = ReadProcLine("stat");
        if (!line.StartsWith("cpu ", StringComparison.Ordinal))
        {
            return (0, 0);
        }

        var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        long total = 0;
        long idle = 0;
        for (var index = 1; index < fields.Length; index++)
        {
            if (!long.TryParse(fields[index], out var value))
            {
                continue;
            }

            total += value;
            if (index == 4 || index == 5)
            {
                idle += value;
            }
        }

        return (idle, total);
    }

    private static (long TotalKib, long AvailableKib) ReadMemory()
    {
        long total = 0;
        long available = 0;
        try
        {
            foreach (var line in File.ReadLines(IOPath.Combine(ProcRoot, "meminfo")))
            {
                if (line.StartsWith("MemTotal:", StringComparison.Ordinal))
                {
                    total = ParseMeminfoKib(line);
                }
                else if (line.StartsWith("MemAvailable:", StringComparison.Ordinal))
                {
                    available = ParseMeminfoKib(line);
                    break;
                }
            }
        }
        catch
        {
        }

        return (total, available);
    }

    private static long ParseMeminfoKib(string line)
    {
        var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return fields.Length >= 2 && long.TryParse(fields[1], out var value) ? value : 0;
    }

    private static int CountProcesses()
    {
        try
        {
            if (HasProcfs)
            {
                return Directory.EnumerateDirectories(ProcRoot)
                    .Count(path => IOPath.GetFileName(path).All(char.IsAsciiDigit));
            }

            return System.Diagnostics.Process.GetProcesses().Length;
        }
        catch
        {
            return 0;
        }
    }

    private static string ReadUptime()
    {
        var line = ReadProcLine("uptime");
        var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        double seconds;
        if (fields.Length > 0 && double.TryParse(fields[0], CultureInfo.InvariantCulture, out seconds))
        {
        }
        else
        {
            seconds = Environment.TickCount64 / 1000.0;
        }

        var span = TimeSpan.FromSeconds(seconds);
        return span.TotalHours >= 1
            ? $"{(int)span.TotalHours}h {span.Minutes:00}m"
            : $"{span.Minutes}m {span.Seconds:00}s";
    }

    private static bool StateReady(string relative)
    {
        try
        {
            foreach (var line in File.ReadLines(IOPath.Combine(StateRoot, relative)))
            {
                var compact = line.Replace(" ", string.Empty);
                if (compact.StartsWith("ready=", StringComparison.OrdinalIgnoreCase))
                {
                    return compact[6..].StartsWith("true", StringComparison.OrdinalIgnoreCase);
                }
            }
        }
        catch
        {
        }

        return false;
    }

    private static IEnumerable<(string Name, long Rss)> TopProcesses(int count)
    {
        try
        {
            if (HasProcfs)
            {
                var entries = new List<(string Name, long Rss)>();
                foreach (var directory in Directory.EnumerateDirectories(ProcRoot))
                {
                    if (!IOPath.GetFileName(directory).All(char.IsAsciiDigit))
                    {
                        continue;
                    }

                    try
                    {
                        var comm = File.ReadAllText(IOPath.Combine(directory, "comm")).Trim();
                        var statm = File.ReadAllText(IOPath.Combine(directory, "statm"))
                            .Split(' ', StringSplitOptions.RemoveEmptyEntries);
                        var rss = statm.Length >= 2 && long.TryParse(statm[1], out var pages)
                            ? pages * 4096
                            : 0;
                        if (comm.Length > 0)
                        {
                            entries.Add((comm, rss));
                        }
                    }
                    catch
                    {
                    }
                }

                return entries.OrderByDescending(entry => entry.Rss).Take(count);
            }

            return System.Diagnostics.Process.GetProcesses()
                .OrderByDescending(process => process.WorkingSet64)
                .Take(count)
                .Select(process => (process.ProcessName, process.WorkingSet64));
        }
        catch
        {
            return [];
        }
    }

    private void UpdateMetrics()
    {
        var (idle, total) = ReadCpuSample();
        double cpuFraction = 0;
        var hasCpu = false;
        if (_previousCpuTotal > 0 && total > _previousCpuTotal)
        {
            var deltaTotal = total - _previousCpuTotal;
            var deltaIdle = idle - _previousCpuIdle;
            cpuFraction = Math.Clamp(1.0 - (double)deltaIdle / deltaTotal, 0, 1);
            hasCpu = true;
        }

        _previousCpuIdle = idle;
        _previousCpuTotal = total;
        CpuText.Text = hasCpu ? $"{cpuFraction * 100:0}%" : "--";
        CpuBar.Width = Math.Max(0, CpuTrack.Bounds.Width * cpuFraction);
        if (hasCpu)
        {
            _cpuHistory.Add(cpuFraction);
            if (_cpuHistory.Count > 60)
            {
                _cpuHistory.RemoveAt(0);
            }
        }

        DrawCpuGraph();

        var (memTotal, memAvailable) = ReadMemory();
        if (memTotal > 0)
        {
            var used = Math.Clamp(1.0 - (double)memAvailable / memTotal, 0, 1);
            MemText.Text = $"{used * 100:0}%";
            MemBar.Width = Math.Max(0, MemTrack.Bounds.Width * used);
        }
        else
        {
            MemText.Text = "--";
        }

        ProcText.Text = CountProcesses().ToString(CultureInfo.InvariantCulture);
        UptimeText.Text = ReadUptime();
        RenderProcessList();

        var graphicsReady = StateReady("Graphics/Status.config");
        var volumesReady = StateReady("Volumes/Status.config");
        GraphicsDot.Foreground = new SolidColorBrush(Color.Parse(graphicsReady ? "#9ED8C6" : "#668AB9"));
        VolumesDot.Foreground = new SolidColorBrush(Color.Parse(volumesReady ? "#9ED8C6" : "#668AB9"));
        TrayGraphicsDot.Foreground = GraphicsDot.Foreground;
        TrayVolumesDot.Foreground = VolumesDot.Foreground;
        StateLines.Text = HasProcfs
            ? $"MWM {(graphicsReady ? "ready" : "down")}\n" +
              $"Volumes {(volumesReady ? "mounted" : "none")}\n" +
              $"Host {HostName()}"
            : $"preview on {RuntimeInformation.OSDescription}\nHost {HostName()}";
    }

    private void DrawCpuGraph()
    {
        CpuGraph.Children.Clear();
        if (_cpuHistory.Count < 2)
        {
            return;
        }

        var width = CpuGraph.Bounds.Width;
        var height = CpuGraph.Bounds.Height;
        if (width <= 0 || height <= 0)
        {
            return;
        }

        var points = new List<Point>();
        for (var index = 0; index < _cpuHistory.Count; index++)
        {
            var x = width * index / Math.Max(1, _cpuHistory.Count - 1);
            var y = height - _cpuHistory[index] * (height - 2) - 1;
            points.Add(new Point(x, y));
        }

        CpuGraph.Children.Add(new Polyline
        {
            Points = points,
            Stroke = new SolidColorBrush(Color.Parse("#18B9FF")),
            StrokeThickness = 1.4
        });
    }

    private void RenderProcessList()
    {
        ProcessList.Children.Clear();
        foreach (var (name, rss) in TopProcesses(7))
        {
            ProcessList.Children.Add(new Grid
            {
                ColumnDefinitions =
                {
                    new ColumnDefinition(GridLength.Star),
                    new ColumnDefinition(GridLength.Auto)
                },
                Children =
                {
                    new TextBlock
                    {
                        Text = name.Length > 22 ? name[..22] : name,
                        FontFamily = new FontFamily("Noto Sans Mono"),
                        FontSize = 11,
                        Foreground = new SolidColorBrush(Color.Parse("#C6DCFA"))
                    },
                    WithColumn(new TextBlock
                    {
                        Text = rss > 0 ? FormatSize(rss) : "",
                        FontFamily = new FontFamily("Noto Sans Mono"),
                        FontSize = 11,
                        Foreground = new SolidColorBrush(Color.Parse("#7FAEE6"))
                    }, 1)
                }
            });
        }
    }

    private static Control WithColumn(Control control, int column)
    {
        Grid.SetColumn(control, column);
        return control;
    }

    private void AppendSysinfo()
    {
        var name = IdentityValue("name", "MixtarRVS");
        var version = IdentityValue("version", HasProcfs ? "1.1" : "preview");
        AppendTerminal($"{name} {version}", "#91B7E8");
        AppendTerminal($"Kernel : {KernelDescription()}", "#91B7E8");
        AppendTerminal($"Host   : {HostName()}", "#91B7E8");
        AppendTerminal("Shell  : Workbench built-ins (PTY session planned) - type 'help'", "#91B7E8");
    }

}
