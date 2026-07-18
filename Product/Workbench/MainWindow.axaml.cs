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

public sealed partial class MainWindow : Window
{
    private sealed record DesktopBounds(double Left, double Top, double Width, double Height);
    private sealed record NetworkNode(string Name, string Address, string Location);
    private sealed record Listing(string Name, string FullPath, bool IsDirectory, string Type, long SizeBytes,
        string Size, DateTime ModifiedAt, string Modified, string Entries);

    private const string ProcRoot = "/System/Processes";
    private const string StateRoot = "/System/State";
    private const string IdentityPath = "/System/Configuration/Product/Identity.config";

    private readonly DispatcherTimer _clockTimer;
    private readonly DispatcherTimer _metricsTimer;
    private readonly Dictionary<Border, DesktopBounds> _restoreBounds = new();
    private readonly List<string> _history = new();
    private readonly List<string> _commandHistory = new();
    private readonly List<double> _cpuHistory = new();
    private readonly Dictionary<string, NetworkNode> _nodes = new()
    {
        ["local"] = new("local.mix", "127.0.0.1", "Local machine"),
        ["relay"] = new("relay-ams.mix", "sample", "Sample relay"),
        ["vault"] = new("vault.mix", "sample", "Sample vault"),
        ["edge"] = new("edge.mix", "sample", "Sample edge")
    };

    private int _historyIndex = -1;
    private int _commandHistoryIndex = -1;
    private Border? _activeWindow;
    private Border? _dragWindow;
    private Control? _dragHandle;
    private Point _dragPointerOrigin;
    private Point _dragWindowOrigin;
    private Border? _selectedFileRow;
    private string? _selectedPath;
    private int _topZ = 30;
    private string _currentPath = "/";
    private long _previousCpuIdle;
    private long _previousCpuTotal;
    private string _sortKey = "name";
    private bool _sortDescending;
    private string _scaleMode = "auto";
    private DateTime _deleteArmedAt = DateTime.MinValue;
    private bool _windowsPlaced;

    private static bool HasProcfs => Directory.Exists(ProcRoot);

    private Border? _resizeWindow;
    private int _resizeFlags;
    private Rect _resizeStartBounds;
    private Point _resizeStartPointer;

    public MainWindow()
    {
        InitializeComponent();
        SizeToPrimaryScreen();
        foreach (var window in DesktopWindows())
        {
            window.PointerPressed += OnWindowResizePressed;
            window.PointerMoved += OnWindowResizeMoved;
            window.PointerReleased += OnWindowResizeReleased;
        }

        StartMenu.PointerPressed += OnStartMenuResizePressed;
        StartMenu.PointerMoved += OnStartMenuResizeMoved;
        StartMenu.PointerReleased += OnStartMenuResizeReleased;

        foreach (var task in new[] { TerminalTask, FilesTask, RuntimeTask, NetworkTask })
        {
            AttachTaskContextMenu(task);
        }

        LoadLayout();
        Closed += (_, _) => SaveLayout();

        // Buttons mark PointerPressed as handled, so light dismiss must see
        // handled events too - otherwise taskbar/toolbar clicks keep menus open.
        RootLayout.AddHandler(PointerPressedEvent, OnGlobalPointerPressed,
            RoutingStrategies.Bubble, handledEventsToo: true);
        RootLayout.PointerMoved += OnConsoleDragMoved;
        RootLayout.PointerReleased += OnConsoleDragReleased;
        ConsoleLayer.RenderTransform = new TranslateTransform(0, 0);
        _consoleSlide = new Transitions
        {
            new DoubleTransition
            {
                Property = TranslateTransform.YProperty,
                Duration = TimeSpan.FromMilliseconds(260),
                Easing = new CubicEaseOut()
            }
        };
        BuildTree();
        AppendSysinfo();
        Navigate(StartPath(), recordHistory: true);
        ActivateWindow(TerminalWindow);
        ApplyScale();

        _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _clockTimer.Tick += (_, _) => UpdateClock();
        _clockTimer.Start();
        UpdateClock();

        _metricsTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _metricsTimer.Tick += (_, _) => UpdateMetrics();
        _metricsTimer.Start();
        UpdateMetrics();

        Closed += (_, _) =>
        {
            _clockTimer.Stop();
            _metricsTimer.Stop();
        };
    }

    private static string StartPath()
    {
        if (Directory.Exists("/System")) return "/System";
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Directory.Exists(profile) ? profile : "/";
    }

    private void SizeToPrimaryScreen()
    {
        try
        {
            var screen = Screens.Primary ?? Screens.All.FirstOrDefault();
            if (screen is null)
            {
                return;
            }

            var scaling = screen.Scaling > 0 ? screen.Scaling : 1.0;
            Width = screen.Bounds.Width / scaling;
            Height = screen.Bounds.Height / scaling;
            Position = new PixelPoint(screen.Bounds.X, screen.Bounds.Y);
        }
        catch
        {
            // Keep the XAML fallback size when the backend exposes no outputs.
        }
    }

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
    // Files: the real filesystem
    // ------------------------------------------------------------------

    private void BuildTree()
    {
        TreePanel.Children.Clear();
        TreePanel.Children.Add(TreeHeader("ROOT"));
        var roots = new (string Label, string Path)[]
        {
            ("⌂  / Root", "/"),
            ("◇  Applications", "/Applications"),
            ("⚙  System", "/System"),
            ("●  Users", "/Users"),
            ("▣  Volumes", "/Volumes"),
            ("◇  Temporary", "/Temporary")
        };

        var added = 0;
        foreach (var (label, path) in roots)
        {
            if (!Directory.Exists(path))
            {
                continue;
            }

            TreePanel.Children.Add(TreeButton(label, path));
            added++;
        }

        if (added == 0)
        {
            foreach (var drive in DriveInfo.GetDrives().Where(drive => drive.IsReady))
            {
                TreePanel.Children.Add(TreeButton($"▰  {drive.Name}", drive.RootDirectory.FullName));
            }
        }

        var shortcuts = new (string Label, string Path)[]
        {
            ("   ◈  Runtime", "/System/Runtime"),
            ("   ◈  State", "/System/State"),
            ("   ≡  Logs", "/System/Logs")
        };

        if (shortcuts.Any(entry => Directory.Exists(entry.Path)))
        {
            TreePanel.Children.Add(TreeHeader("SYSTEM"));
            foreach (var (label, path) in shortcuts)
            {
                if (Directory.Exists(path))
                {
                    TreePanel.Children.Add(TreeButton(label, path));
                }
            }
        }
    }

    private static TextBlock TreeHeader(string text) => new()
    {
        Text = text,
        Margin = new Thickness(7, 6, 7, 3),
        Foreground = new SolidColorBrush(Color.Parse("#7EAFE8")),
        FontFamily = new FontFamily("Noto Sans Mono"),
        FontSize = 11,
        FontWeight = FontWeight.Bold
    };

    private Button TreeButton(string label, string path)
    {
        var button = new Button { Content = label, Tag = path };
        button.Classes.Add("tree");
        button.Click += OnTreePath;
        return button;
    }

    private void OnTreePath(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string path })
        {
            ShowWindow(FilesWindow);
            Navigate(path, recordHistory: true);
        }
    }

    private void NavigateHistory(int direction)
    {
        var target = _historyIndex + direction;
        if (target < 0 || target >= _history.Count)
        {
            return;
        }

        _historyIndex = target;
        Navigate(_history[target], recordHistory: false);
    }

    private void Navigate(string path, bool recordHistory)
    {
        path = NormalizePath(path);
        if (!Directory.Exists(path))
        {
            AppendTerminal($"[FS] path not found: {path}", "#FF5C7B");
            return;
        }

        if (recordHistory)
        {
            if (_historyIndex < _history.Count - 1)
            {
                _history.RemoveRange(_historyIndex + 1, _history.Count - _historyIndex - 1);
            }

            _history.Add(path);
            _historyIndex = _history.Count - 1;
        }

        _currentPath = path;
        FilesTitle.Text = $"FILES - {path.ToUpperInvariant()}";
        PathHint.Text = path;
        BuildBreadcrumb(path);
        AddressBox.Text = path;
        TerminalPrompt.Text = $"root@{HostName()}:{path}#";
        SelectionStatus.Text = "No selection";
        _selectedFileRow = null;
        _selectedPath = null;
        UpdateVolumeInfo(path);
        RenderFiles();
    }

    private void BuildBreadcrumb(string path)
    {
        BreadcrumbPanel.Children.Clear();
        var isDrivePath = path.Length >= 2 && path[1] == ':';
        var rootLabel = "⌂ MixtarRVS";
        var rootTarget = isDrivePath ? path[..2] + IOPath.DirectorySeparatorChar : "/";
        BreadcrumbPanel.Children.Add(CrumbButton(rootLabel, rootTarget));

        var segments = path.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
        var accumulated = isDrivePath ? string.Empty : "";
        for (var index = 0; index < segments.Length; index++)
        {
            var segment = segments[index];
            accumulated = index == 0 && isDrivePath
                ? segment + IOPath.DirectorySeparatorChar
                : (isDrivePath
                    ? IOPath.Combine(accumulated, segment)
                    : accumulated + "/" + segment);
            if (index == 0 && isDrivePath)
            {
                continue;
            }

            BreadcrumbPanel.Children.Add(new TextBlock
            {
                Text = "›",
                Foreground = new SolidColorBrush(Color.Parse("#5E86BC")),
                FontSize = 10,
                Margin = new Thickness(2, 0),
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
            });
            BreadcrumbPanel.Children.Add(CrumbButton(segment, accumulated));
        }
    }

    private Button CrumbButton(string label, string target)
    {
        var button = new Button { Content = label, Tag = target };
        button.Classes.Add("crumb");
        button.Click += (_, _) => Navigate(target, recordHistory: true);
        return button;
    }

    private void UpdateVolumeInfo(string path)
    {
        try
        {
            var drive = new DriveInfo(IOPath.GetPathRoot(IOPath.GetFullPath(path)) ?? "/");
            VolumeInfo.Text = $"{FormatSize(drive.AvailableFreeSpace)} free of {FormatSize(drive.TotalSize)}";
        }
        catch
        {
            VolumeInfo.Text = string.Empty;
        }
    }

    private static Listing DescribeEntry(FileSystemInfo info)
    {
        var isDirectory = info is DirectoryInfo;
        var type = isDirectory ? "Dir" : "File";
        if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
        {
            type = "Link";
        }

        var sizeBytes = info is FileInfo file ? file.Length : -1;
        var size = sizeBytes >= 0 ? FormatSize(sizeBytes) : "-";
        var entries = "-";
        if (isDirectory && type != "Link")
        {
            try
            {
                entries = Directory.EnumerateFileSystemEntries(info.FullName).Take(1000).Count()
                    .ToString(CultureInfo.InvariantCulture);
            }
            catch
            {
                entries = "?";
            }
        }

        var modifiedAt = info.LastWriteTime;
        return new Listing(info.Name, info.FullName, isDirectory, type, sizeBytes, size, modifiedAt,
            modifiedAt.ToString("dd.MM HH:mm", CultureInfo.InvariantCulture), entries);
    }

    private static string FormatSize(long bytes) => bytes switch
    {
        < 1024 => $"{bytes} B",
        < 1024 * 1024 => $"{bytes / 1024.0:0.#} K",
        < 1024L * 1024 * 1024 => $"{bytes / (1024.0 * 1024):0.#} M",
        _ => $"{bytes / (1024.0 * 1024 * 1024):0.##} G"
    };

    private Listing[] ListDirectory(string path)
    {
        try
        {
            var directory = new DirectoryInfo(path);
            return directory.EnumerateFileSystemInfos().Select(DescribeEntry).ToArray();
        }
        catch (Exception error)
        {
            AppendTerminal($"[FS] {path}: {error.Message}", "#FF5C7B");
            return [];
        }
    }

    private IEnumerable<Listing> SortEntries(IEnumerable<Listing> entries)
    {
        var directoriesFirst = entries.OrderByDescending(entry => entry.IsDirectory);
        IOrderedEnumerable<Listing> ordered = _sortKey switch
        {
            "type" => directoriesFirst.ThenBy(entry => entry.Type),
            "size" => directoriesFirst.ThenBy(entry => entry.SizeBytes),
            "modified" => directoriesFirst.ThenBy(entry => entry.ModifiedAt),
            _ => directoriesFirst.ThenBy(entry => entry.Name, StringComparer.OrdinalIgnoreCase)
        };

        return _sortDescending
            ? directoriesFirst.ThenByDescending(entry => _sortKey switch
            {
                "type" => (object)entry.Type,
                "size" => entry.SizeBytes,
                "modified" => entry.ModifiedAt,
                _ => entry.Name
            })
            : ordered;
    }

    private void OnSortColumn(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string key })
        {
            return;
        }

        if (_sortKey == key)
        {
            _sortDescending = !_sortDescending;
        }
        else
        {
            _sortKey = key;
            _sortDescending = false;
        }

        RenderFiles();
    }

    private void RenderFiles()
    {
        FileRows.Children.Clear();
        var query = FileSearch.Text?.Trim() ?? string.Empty;
        var entries = SortEntries(ListDirectory(_currentPath)
                .Where(entry => query.Length == 0 ||
                    entry.Name.Contains(query, StringComparison.OrdinalIgnoreCase)))
            .ToArray();

        foreach (var entry in entries)
        {
            var row = new Border();
            row.Classes.Add("file-row");

            var grid = new Grid
            {
                ColumnDefinitions =
                {
                    new ColumnDefinition(new GridLength(190)),
                    new ColumnDefinition(new GridLength(60)),
                    new ColumnDefinition(new GridLength(74)),
                    new ColumnDefinition(new GridLength(96)),
                    new ColumnDefinition(GridLength.Star)
                }
            };

            grid.Children.Add(Cell($"{IconFor(entry)}  {entry.Name}", 0, "#D8E7FF"));
            grid.Children.Add(Cell(entry.Type, 1, "#9EC1EF"));
            grid.Children.Add(Cell(entry.Size, 2, "#9EC1EF"));
            grid.Children.Add(Cell(entry.Modified, 3, "#9EC1EF"));
            grid.Children.Add(Cell(entry.Entries, 4, "#9EC1EF"));
            row.Child = grid;

            var captured = entry;
            row.ContextFlyout = BuildFileContextMenu(captured);
            row.PointerPressed += (_, args) =>
            {
                if (args.ClickCount >= 2)
                {
                    if (captured.IsDirectory)
                    {
                        Navigate(captured.FullPath, recordHistory: true);
                    }
                    else
                    {
                        OpenViewer(captured.FullPath);
                    }

                    args.Handled = true;
                    return;
                }

                _selectedFileRow?.Classes.Remove("selected");
                row.Classes.Add("selected");
                _selectedFileRow = row;
                _selectedPath = captured.FullPath;
                SelectionStatus.Text = $"{captured.Name} selected";
                ResetDeleteButton();
                args.Handled = true;
            };

            FileRows.Children.Add(row);
        }

        ItemCount.Text = $"{entries.Length} item{(entries.Length == 1 ? string.Empty : "s")}";
    }

    // HIG: file rows carry a context menu (open, copy path, delete).
    private MenuFlyout BuildFileContextMenu(Listing entry)
    {
        var flyout = new MenuFlyout();
        var open = new MenuItem { Header = entry.IsDirectory ? "Open" : "View" };
        open.Click += (_, _) =>
        {
            if (entry.IsDirectory)
            {
                Navigate(entry.FullPath, recordHistory: true);
            }
            else
            {
                OpenViewer(entry.FullPath);
            }
        };
        var copyPath = new MenuItem { Header = "Copy path" };
        copyPath.Click += async (_, _) =>
        {
            try
            {
                if (Clipboard is { } clipboard)
                {
                    var transfer = new DataTransfer();
                    transfer.Add(DataTransferItem.CreateText(entry.FullPath));
                    await clipboard.SetDataAsync(transfer);
                }
            }
            catch
            {
            }
        };
        var delete = new MenuItem { Header = "Delete" };
        delete.Click += (_, _) =>
        {
            _selectedPath = entry.FullPath;
            DeleteSelected();
        };
        flyout.Items.Add(open);
        flyout.Items.Add(copyPath);
        flyout.Items.Add(delete);
        return flyout;
    }

    private void CreateNewFolder()
    {
        try
        {
            var name = "New Folder";
            var target = IOPath.Combine(_currentPath, name);
            var counter = 2;
            while (Directory.Exists(target) || File.Exists(target))
            {
                target = IOPath.Combine(_currentPath, $"{name} {counter}");
                counter++;
            }

            Directory.CreateDirectory(target);
            RenderFiles();
        }
        catch (Exception error)
        {
            AppendTerminal($"[FS] mkdir failed: {error.Message}", "#FF5C7B");
        }
    }

    private void ResetDeleteButton()
    {
        DeleteButton.Content = "Delete";
        _deleteArmedAt = DateTime.MinValue;
    }

    private void DeleteSelected()
    {
        if (_selectedPath is null)
        {
            AppendTerminal("[FS] delete: nothing selected", "#FFC65C");
            return;
        }

        if ((DateTime.UtcNow - _deleteArmedAt).TotalSeconds > 4)
        {
            _deleteArmedAt = DateTime.UtcNow;
            DeleteButton.Content = "Confirm?";
            return;
        }

        try
        {
            if (Directory.Exists(_selectedPath))
            {
                Directory.Delete(_selectedPath, recursive: false);
            }
            else
            {
                File.Delete(_selectedPath);
            }

            _selectedPath = null;
            RenderFiles();
        }
        catch (Exception error)
        {
            AppendTerminal($"[FS] delete failed: {error.Message}", "#FF5C7B");
        }
        finally
        {
            ResetDeleteButton();
        }
    }

    private void OpenViewer(string path)
    {
        const int limit = 200 * 1024;
        try
        {
            var info = new FileInfo(path);
            string content;
            using (var stream = info.OpenRead())
            {
                var buffer = new byte[Math.Min(limit, info.Length)];
                var read = stream.Read(buffer, 0, buffer.Length);
                var slice = buffer.AsSpan(0, read);
                content = slice.Contains((byte)0)
                    ? $"(binary file, {FormatSize(info.Length)})"
                    : System.Text.Encoding.UTF8.GetString(slice);
                if (content.Length == 0)
                {
                    content = "(empty file)";
                }
            }

            if (info.Length > limit && !content.StartsWith("(binary", StringComparison.Ordinal))
            {
                content += $"\n\n... (showing first {FormatSize(limit)} of {FormatSize(info.Length)})";
            }

            ViewerTitle.Text = $"VIEWER - {info.Name.ToUpperInvariant()}";
            ViewerContent.Text = content;
            ShowWindow(ViewerWindow);
        }
        catch (Exception error)
        {
            AppendTerminal($"[FS] open failed: {error.Message}", "#FF5C7B");
        }
    }

    private static TextBlock Cell(string text, int column, string color)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.Parse(color)),
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(block, column);
        return block;
    }

    private static string IconFor(Listing entry) => entry.Type switch
    {
        "Dir" => "▣",
        "Link" => "◈",
        _ => "□"
    };

    private static string NormalizePath(string raw)
    {
        var path = (raw ?? string.Empty).Trim();
        if (path.StartsWith("MIXTARROOT:", StringComparison.OrdinalIgnoreCase))
        {
            path = path["MIXTARROOT:".Length..];
        }

        if (path.Length == 0)
        {
            return "/";
        }

        if (path.Length >= 2 && path[1] == ':')
        {
            return path;
        }

        if (!path.StartsWith('/') && !path.StartsWith('\\'))
        {
            path = "/" + path;
        }

        return path.Length > 1 ? path.TrimEnd('/', '\\') : path;
    }

    private static string ParentPath(string path)
    {
        var parent = IOPath.GetDirectoryName(path.TrimEnd('/', '\\'));
        return string.IsNullOrEmpty(parent) ? "/" : parent;
    }

    private void OnFileSearchChanged(object? sender, TextChangedEventArgs e) => RenderFiles();

    // HIG: the Start menu resizes too (right edge = width, top edge = height;
    // bottom-anchored, so height growth extends upward).
    private int _startMenuResize;
    private Point _startMenuPointer;
    private Size _startMenuSize;

    private void OnStartMenuResizePressed(object? sender, PointerPressedEventArgs e)
    {
        var position = e.GetPosition(StartMenu);
        var flags = 0;
        if (position.X >= StartMenu.Bounds.Width - 8) flags |= 1;
        if (position.Y <= 8) flags |= 2;
        if (flags == 0 || !e.GetCurrentPoint(StartMenu).Properties.IsLeftButtonPressed)
        {
            return;
        }

        _startMenuResize = flags;
        _startMenuPointer = e.GetPosition(RootLayout);
        _startMenuSize = new Size(StartMenu.Bounds.Width, StartMenu.Bounds.Height);
        e.Pointer.Capture(StartMenu);
        e.Handled = true;
    }

    private void OnStartMenuResizeMoved(object? sender, PointerEventArgs e)
    {
        if (_startMenuResize == 0)
        {
            var probe = e.GetPosition(StartMenu);
            var hover = 0;
            if (probe.X >= StartMenu.Bounds.Width - 8) hover |= 1;
            if (probe.Y <= 8) hover |= 2;
            StartMenu.Cursor = new Cursor(hover switch
            {
                1 => StandardCursorType.SizeWestEast,
                2 => StandardCursorType.SizeNorthSouth,
                3 => StandardCursorType.TopRightCorner,
                _ => StandardCursorType.Arrow
            });
            return;
        }

        var delta = e.GetPosition(RootLayout) - _startMenuPointer;
        if ((_startMenuResize & 1) != 0)
        {
            StartMenu.Width = Math.Clamp(_startMenuSize.Width + delta.X, 320, RootLayout.Bounds.Width - 20);
        }

        if ((_startMenuResize & 2) != 0)
        {
            StartMenu.Height = Math.Clamp(_startMenuSize.Height - delta.Y, 260, RootLayout.Bounds.Height - 80);
        }
    }

    private void OnStartMenuResizeReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (_startMenuResize == 0)
        {
            return;
        }

        e.Pointer.Capture(null);
        _startMenuResize = 0;
        e.Handled = true;
    }

    // System console layer (first-concept screen manager): drag down from the
    // top-center edge of the desktop, or F12. Escape closes.
    private bool _consoleOpen;
    private bool _consoleDragging;
    private bool _consoleClosingDrag;
    private double _consoleDragStartY;
    private Transitions? _consoleSlide;

    private TranslateTransform ConsoleTransform => (TranslateTransform)ConsoleLayer.RenderTransform!;

    private void SetConsoleOffset(double offset) => ConsoleTransform.Y = offset;

    private void AnimateConsole(double target, bool hideAfter)
    {
        ConsoleTransform.Transitions = _consoleSlide;
        SetConsoleOffset(target);
        if (hideAfter)
        {
            DispatcherTimer.RunOnce(() =>
            {
                if (!_consoleOpen)
                {
                    ConsoleLayer.IsVisible = false;
                }
            }, TimeSpan.FromMilliseconds(300));
        }
    }

    private void ToggleConsole()
    {
        if (_consoleOpen)
        {
            _consoleOpen = false;
            AnimateConsole(-RootLayout.Bounds.Height, hideAfter: true);
        }
        else
        {
            _consoleOpen = true;
            ConsoleGrip.Opacity = 0;
            ConsoleTransform.Transitions = null;
            SetConsoleOffset(-RootLayout.Bounds.Height);
            ConsoleLayer.IsVisible = true;
            AnimateConsole(0, hideAfter: false);
            ConsolePrompt.Text = $"root@{HostName()}:{_currentPath}#";
            ConsoleInput.Focus();
        }
    }

    private void OnConsoleDragMoved(object? sender, PointerEventArgs e)
    {
        if (!_consoleDragging)
        {
            var probe = e.GetPosition(RootLayout);
            ConsoleGrip.Opacity = !_consoleOpen && probe.Y <= 18 &&
                Math.Abs(probe.X - RootLayout.Bounds.Width / 2) < RootLayout.Bounds.Width * 0.22
                ? 1
                : 0;
            return;
        }

        ConsoleGrip.Opacity = 0;

        var offset = e.GetPosition(RootLayout).Y - _consoleDragStartY;
        SetConsoleOffset(_consoleClosingDrag
            ? Math.Min(0, offset)
            : Math.Min(0, -RootLayout.Bounds.Height + Math.Max(0, offset)));
    }

    private void OnConsoleDragReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_consoleDragging)
        {
            return;
        }

        _consoleDragging = false;
        var pulled = e.GetPosition(RootLayout).Y - _consoleDragStartY;
        if (_consoleClosingDrag)
        {
            _consoleClosingDrag = false;
            if (-pulled > RootLayout.Bounds.Height * 0.15)
            {
                _consoleOpen = false;
                AnimateConsole(-RootLayout.Bounds.Height, hideAfter: true);
            }
            else
            {
                AnimateConsole(0, hideAfter: false);
            }

            return;
        }

        if (pulled > RootLayout.Bounds.Height * 0.2)
        {
            _consoleOpen = true;
            ConsoleGrip.Opacity = 0;
            AnimateConsole(0, hideAfter: false);
            ConsolePrompt.Text = $"root@{HostName()}:{_currentPath}#";
            ConsoleInput.Focus();
        }
        else
        {
            _consoleOpen = false;
            AnimateConsole(-RootLayout.Bounds.Height, hideAfter: true);
        }
    }

    private void OnConsoleKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            ToggleConsole();
            e.Handled = true;
            return;
        }

        if (e.Key != Key.Enter) return;
        var command = ConsoleInput.Text?.Trim() ?? string.Empty;
        if (command.Length == 0) return;

        _outputTarget = ConsoleLines;
        AppendTerminal($"{ConsolePrompt.Text} {command}", "#FFFFFF");
        RunCommand(command);
        _outputTarget = TerminalLines;
        ConsoleInput.Text = string.Empty;
        ConsoleScroll.ScrollToEnd();
        e.Handled = true;
    }

    private void OnGlobalPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.Source is not Control control)
        {
            return;
        }

        if (_consoleOpen && !e.Handled)
        {
            var closePosition = e.GetPosition(RootLayout);
            if (closePosition.Y >= RootLayout.Bounds.Height - 26)
            {
                _consoleDragging = true;
                _consoleClosingDrag = true;
                _consoleDragStartY = closePosition.Y;
                ConsoleTransform.Transitions = null;
                e.Handled = true;
                return;
            }
        }
        else if (!_consoleOpen)
        {
            var position = e.GetPosition(RootLayout);
            if (!e.Handled && position.Y <= 18 &&
                Math.Abs(position.X - RootLayout.Bounds.Width / 2) <
                RootLayout.Bounds.Width * 0.22)
            {
                _consoleDragging = true;
                _consoleDragStartY = position.Y;
                ConsoleTransform.Transitions = null;
                ConsoleLayer.IsVisible = true;
                SetConsoleOffset(-RootLayout.Bounds.Height);
                e.Handled = true;
                return;
            }
        }

        var ancestors = control.GetVisualAncestors().OfType<Control>().ToList();
        bool Within(Control host) => control == host || ancestors.Contains(host);
        var startButton = (control as Button ?? ancestors.OfType<Button>().FirstOrDefault())
            is { Tag: "start" };

        if (!startButton)
        {
            if (StartMenu.IsVisible && !Within(StartMenu))
            {
                StartMenu.IsVisible = false;
            }

            if (CommandPalette.IsVisible && !Within(CommandPalette))
            {
                CommandPalette.IsVisible = false;
            }
        }

        if (AddressBox.IsVisible && !Within(AddressBox) && !Within(AddressSuggestions))
        {
            ExitAddressMode();
        }
    }

    private void EnterAddressMode()
    {
        Breadcrumb.IsVisible = false;
        AddressBox.IsVisible = true;
        BuildAddressSuggestions();
        AddressPopup.IsOpen = true;
        AddressBox.Focus();
        AddressBox.SelectAll();
    }

    private void BuildAddressSuggestions()
    {
        AddressSuggestions.Children.Clear();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var recent = Enumerable.Reverse(_history).Where(seen.Add).Take(6).ToList();
        var roots = new[] { "/", "/Applications", "/System", "/Users", "/Volumes", "/Temporary" }
            .Where(path => Directory.Exists(path) && seen.Add(path))
            .ToList();
        if (roots.Count == 0)
        {
            roots = DriveInfo.GetDrives().Where(drive => drive.IsReady)
                .Select(drive => drive.RootDirectory.FullName)
                .Where(seen.Add)
                .ToList();
        }

        foreach (var section in new[] { ("RECENT", recent), ("LOCATIONS", roots) })
        {
            if (section.Item2.Count == 0)
            {
                continue;
            }

            AddressSuggestions.Children.Add(new TextBlock
            {
                Text = section.Item1,
                Foreground = new SolidColorBrush(Color.Parse("#7EAFE8")),
                FontFamily = new FontFamily("Noto Sans Mono"),
                FontSize = 8,
                FontWeight = FontWeight.Bold,
                Margin = new Thickness(6, 4, 6, 2)
            });
            foreach (var path in section.Item2)
            {
                var button = new Button
                {
                    Content = path,
                    HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = Avalonia.Layout.HorizontalAlignment.Left
                };
                button.Classes.Add("tree");
                var captured = path;
                button.Click += (_, _) =>
                {
                    Navigate(captured, recordHistory: true);
                    ExitAddressMode();
                };
                AddressSuggestions.Children.Add(button);
            }
        }
    }

    private void OnAddressPressed(object? sender, PointerPressedEventArgs e)
    {
        EnterAddressMode();
        e.Handled = true;
    }

    private void OnAddressKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            Navigate(AddressBox.Text ?? "/", recordHistory: true);
            ExitAddressMode();
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            ExitAddressMode();
            e.Handled = true;
        }
    }

    private void ExitAddressMode()
    {
        AddressPopup.IsOpen = false;
        AddressBox.IsVisible = false;
        Breadcrumb.IsVisible = true;
    }

    // ------------------------------------------------------------------
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
            Foreground = new SolidColorBrush(Color.Parse(color)),
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

    // ------------------------------------------------------------------
    // Global keys and power
    // ------------------------------------------------------------------

    // HIG: Alt+Tab cycles windows, show-desktop minimizes everything and
    // restores the same set on the second use.
    private readonly List<Border> _showDesktopStash = new();

    private void CycleWindows()
    {
        var visible = DesktopWindows().Where(item => item.IsVisible)
            .OrderBy(item => item.ZIndex).ToList();
        if (visible.Count == 0)
        {
            var fallback = DesktopWindows().FirstOrDefault();
            if (fallback is not null) ShowWindow(fallback);
            return;
        }

        ActivateWindow(visible[0]);
    }

    private void ToggleShowDesktop()
    {
        if (_showDesktopStash.Count > 0)
        {
            foreach (var window in _showDesktopStash)
            {
                window.IsVisible = true;
                TaskFor(window)?.Classes.Remove("minimized");
            }

            _showDesktopStash.Clear();
            return;
        }

        foreach (var window in DesktopWindows().Where(item => item.IsVisible))
        {
            _showDesktopStash.Add(window);
            window.IsVisible = false;
            window.Classes.Remove("active");
            TaskFor(window)?.Classes.Add("minimized");
        }

        _activeWindow = null;
    }

    private void OnStartSearchChanged(object? sender, TextChangedEventArgs e)
    {
        var query = StartSearch.Text?.Trim() ?? string.Empty;
        foreach (var panel in new[] { StartAppsPanel, StartSystemPanel })
        {
            foreach (var child in panel.Children.OfType<Button>())
            {
                child.IsVisible = query.Length == 0 ||
                    (child.Content?.ToString() ?? string.Empty)
                        .Contains(query, StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    private void OnWindowKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Tab && e.KeyModifiers.HasFlag(KeyModifiers.Alt))
        {
            CycleWindows();
            e.Handled = true;
            return;
        }

        if (e.KeyModifiers.HasFlag(KeyModifiers.Control) && e.Key == Key.K)
        {
            CommandPalette.IsVisible = !CommandPalette.IsVisible;
            StartMenu.IsVisible = false;
            if (CommandPalette.IsVisible) PaletteInput.Focus();
            e.Handled = true;
        }
        else if (e.KeyModifiers.HasFlag(KeyModifiers.Control) && e.Key == Key.L)
        {
            ShowWindow(FilesWindow);
            EnterAddressMode();
            e.Handled = true;
        }
        else if (e.Key == Key.F12)
        {
            ToggleConsole();
            e.Handled = true;
        }
        else if (e.Key == Key.F11)
        {
            if (Width >= (Screens.Primary?.Bounds.Width ?? 1) / (Screens.Primary?.Scaling ?? 1) - 4)
            {
                Width = 1440;
                Height = 900;
                Position = new PixelPoint(120, 80);
            }
            else
            {
                SizeToPrimaryScreen();
            }

            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            if (_consoleOpen)
            {
                ToggleConsole();
                return;
            }

            StartMenu.IsVisible = false;
            CommandPalette.IsVisible = false;
            ExitAddressMode();
        }
    }

    private void OnPaletteKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            CommandPalette.IsVisible = false;
            e.Handled = true;
        }
    }

    private void OnPowerClick(object? sender, RoutedEventArgs e) => Close();
}
