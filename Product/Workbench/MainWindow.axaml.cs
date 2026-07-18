using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Threading;
using Avalonia.VisualTree;

namespace Mixtar.Product.Workbench;

public sealed partial class MainWindow : Window
{
    private sealed record FileEntry(string Name, string Type, string Items, string Modified, string Role);
    private sealed record DesktopBounds(double Left, double Top, double Width, double Height);
    private sealed record NetworkNode(string Name, string Address, string Location);

    private readonly DispatcherTimer _clockTimer;
    private readonly Dictionary<Border, DesktopBounds> _restoreBounds = new();
    private readonly Dictionary<string, FileEntry[]> _fileSystem = new(StringComparer.OrdinalIgnoreCase)
    {
        ["/"] =
        [
            new("Applications", "Dir", "24", "Today", "APX bundles"),
            new("System", "Dir", "10", "Today", "Native system"),
            new("Users", "Dir", "3", "Today", "Profiles"),
            new("Volumes", "Dir", "4", "Live", "Mounted storage"),
            new("Temporary", "Dir", "14", "Live", "Ephemeral data")
        ],
        ["/Applications"] =
        [
            new("Files.apx", "Application", "1", "Today", "File explorer"),
            new("Terminal.apx", "Application", "1", "Today", "zsh session"),
            new("NetworkInspector.apx", "Application", "1", "Today", "Network tools"),
            new("RuntimeMonitor.apx", "Application", "1", "Today", "Runtime metrics")
        ],
        ["/System"] =
        [
            new("Tools", "Dir", "24", "Today", "Native CLI"),
            new("Shells", "Dir", "6", "Today", "APX shells"),
            new("Libraries", "Dir", "132", "Today", "Runtime"),
            new("Configuration", "Dir", "18", "Yesterday", "TOML-compatible config"),
            new("Resources", "Dir", "42", "Today", "Themes and fonts"),
            new("Logs", "Dir", "9", "Today", "Persistent logs"),
            new("Runtime", "Service", "11", "Live", "Ephemeral state"),
            new("Kernel", "Dir", "4", "Today", "Kernel and modules"),
            new("Init", "Dir", "8", "Today", "System tasks"),
            new("Compatibility", "Dir", "3", "Hidden", "Application islands")
        ],
        ["/System/Runtime"] =
        [
            new("Executor", "Service", "1", "Live", "APX lifecycle"),
            new("Tasks", "Service", "12", "Live", "Scheduled work"),
            new("Devices", "Service", "31", "Live", "Device objects"),
            new("Processes", "Service", "47", "Live", "Process view")
        ],
        ["/System/Logs"] =
        [
            new("system.log", "Log", "1", "Today", "Core events"),
            new("executor.log", "Log", "1", "Today", "APX lifecycle"),
            new("network.log", "Log", "1", "Today", "Network inspection"),
            new("boot.log", "Log", "1", "Today", "Init timeline")
        ],
        ["/Users"] =
        [
            new("Administrator", "User", "12", "Today", "Administrative profile"),
            new("Superuser", "User", "8", "Today", "Privileged profile"),
            new("V", "User", "34", "Today", "Primary user")
        ],
        ["/Volumes"] =
        [
            new("System", "Volume", "1", "Mounted", "Boot volume"),
            new("Data", "Volume", "1", "Mounted", "User data"),
            new("Recovery", "Volume", "1", "Ready", "Recovery image"),
            new("RemoteVault", "Volume", "1", "Online", "Remote APX mount")
        ],
        ["/Temporary"] =
        [
            new("session-cache", "Temp", "14", "Live", "Auto-clean"),
            new("apx-build", "Temp", "3", "Live", "Build workspace")
        ]
    };

    private readonly Dictionary<string, NetworkNode> _nodes = new()
    {
        ["local"] = new("local.mix", "127.0.0.1", "Local machine"),
        ["relay"] = new("relay-ams.mix", "198.51.100.12", "Amsterdam / relay"),
        ["vault"] = new("vault.mix", "192.0.2.77", "Reykjavik / pinned relay"),
        ["edge"] = new("edge-tokyo.mix", "203.0.113.42", "Tokyo / edge")
    };

    private Border? _activeWindow;
    private Border? _dragWindow;
    private Control? _dragHandle;
    private Point _dragPointerOrigin;
    private Point _dragWindowOrigin;
    private Border? _selectedFileRow;
    private int _topZ = 30;
    private string _currentPath = "/System";

    public MainWindow()
    {
        InitializeComponent();
        BuildBackgroundGrid();
        Navigate("/System");
        ActivateWindow(TerminalWindow);

        _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _clockTimer.Tick += (_, _) => UpdateClock();
        _clockTimer.Start();
        UpdateClock();
        Closed += (_, _) => _clockTimer.Stop();
    }

    private void BuildBackgroundGrid()
    {
        var stroke = new SolidColorBrush(Color.Parse("#202569D2"));
        for (var x = 0; x <= 1600; x += 36)
        {
            GridLines.Children.Add(new Line
            {
                StartPoint = new Point(x, 0),
                EndPoint = new Point(x, 900),
                Stroke = stroke,
                StrokeThickness = 1
            });
        }

        for (var y = 0; y <= 900; y += 36)
        {
            GridLines.Children.Add(new Line
            {
                StartPoint = new Point(0, y),
                EndPoint = new Point(1600, y),
                Stroke = stroke,
                StrokeThickness = 1
            });
        }
    }

    private void UpdateClock() =>
        ClockText.Text = DateTime.Now.ToString("HH:mm:ss", CultureInfo.InvariantCulture);

    private Border? WindowByName(string? name) => name switch
    {
        nameof(TerminalWindow) => TerminalWindow,
        nameof(NetworkWindow) => NetworkWindow,
        nameof(FilesWindow) => FilesWindow,
        nameof(RuntimeWindow) => RuntimeWindow,
        _ => null
    };

    private Button? TaskFor(Border window)
    {
        if (window == TerminalWindow) return TerminalTask;
        if (window == NetworkWindow) return NetworkTask;
        if (window == FilesWindow) return FilesTask;
        if (window == RuntimeWindow) return RuntimeTask;
        return null;
    }

    private void ActivateWindow(Border window)
    {
        window.IsVisible = true;
        window.ZIndex = ++_topZ;

        foreach (var item in new[] { TerminalWindow, NetworkWindow, FilesWindow, RuntimeWindow })
        {
            item.Classes.Remove("active");
            TaskFor(item)?.Classes.Remove("active");
        }

        window.Classes.Add("active");
        TaskFor(window)?.Classes.Add("active");
        TaskFor(window)?.Classes.Remove("minimized");
        _activeWindow = window;
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
        if (window is null || _restoreBounds.ContainsKey(window))
        {
            return;
        }

        ActivateWindow(window);
        _dragWindow = window;
        _dragHandle = handle;
        _dragPointerOrigin = e.GetPosition(DesktopCanvas);
        _dragWindowOrigin = new Point(Canvas.GetLeft(window), Canvas.GetTop(window));
        e.Pointer.Capture(handle);
        e.Handled = true;
    }

    private void ContinueDesktopWindowDrag(object? sender, PointerEventArgs e)
    {
        if (_dragWindow is null || sender != _dragHandle)
        {
            return;
        }

        var point = e.GetPosition(DesktopCanvas);
        var x = Math.Clamp(_dragWindowOrigin.X + point.X - _dragPointerOrigin.X, 0, 1600 - _dragWindow.Bounds.Width);
        var y = Math.Clamp(_dragWindowOrigin.Y + point.Y - _dragPointerOrigin.Y, 40, 852 - 34);
        Canvas.SetLeft(_dragWindow, x);
        Canvas.SetTop(_dragWindow, y);
    }

    private void EndDesktopWindowDrag(object? sender, PointerReleasedEventArgs e)
    {
        if (_dragWindow is null)
        {
            return;
        }

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
            window.Width = 1600;
            window.Height = 812;
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

    private void ShowWindow(Border window)
    {
        if (TaskFor(window) is { } task)
        {
            task.IsVisible = true;
            task.Classes.Remove("minimized");
        }

        ActivateWindow(window);
    }

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

        switch (action)
        {
            case "terminal":
                ShowWindow(TerminalWindow);
                break;
            case "files":
                ShowWindow(FilesWindow);
                break;
            case "network":
                ShowWindow(NetworkWindow);
                break;
            case "runtime":
                ShowWindow(RuntimeWindow);
                break;
            case "root":
                ShowWindow(FilesWindow);
                Navigate("/");
                break;
            case "apx":
                ShowWindow(FilesWindow);
                Navigate("/Applications");
                break;
            case "up":
                Navigate(ParentPath(_currentPath));
                break;
            case "reload":
                RenderFiles();
                AppendTerminal($"[FS] refreshed {_currentPath}", "#91B7E8");
                break;
            case "trace":
                ShowWindow(NetworkWindow);
                AppendTerminal("[NET] route verified: local > relay-ams > vault", "#91B7E8");
                break;
            case "recon":
                ShowWindow(NetworkWindow);
                AppendTerminal($"[SEC] authorized recon completed for {NodeName.Text}", "#91B7E8");
                break;
            case "ssh":
                AppendTerminal($"[SSH] pinned-key session granted for {NodeName.Text}", "#91B7E8");
                break;
            case "verify":
                ShowWindow(TerminalWindow);
                AppendTerminal("MixtarRVS visual verifier: PASS", "#27EE91");
                break;
            case "reboot":
                ShowWindow(TerminalWindow);
                AppendTerminal("[INIT] controlled reboot request queued through Supervisor", "#FFC65C");
                break;
        }

        StartMenu.IsVisible = false;
        CommandPalette.IsVisible = false;
    }

    private void OnTreePath(object? sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string path })
        {
            Navigate(path);
        }
    }

    private void Navigate(string path)
    {
        path = NormalizePath(path);
        if (!_fileSystem.ContainsKey(path))
        {
            AppendTerminal($"[FS] path not found: {path}", "#FF5C7B");
            return;
        }

        _currentPath = path;
        FilesTitle.Text = $"FILES - {path.ToUpperInvariant()}";
        PathHint.Text = $"MIXTARROOT:{path}";
        BreadcrumbText.Text = path == "/"
            ? "⌂  MixtarRVS"
            : $"⌂  MixtarRVS   >   {string.Join("   >   ", path.Split('/', StringSplitOptions.RemoveEmptyEntries))}";
        AddressBox.Text = $"MIXTARROOT:{path}";
        FileSearch.PlaceholderText = $"Search {path}";
        TerminalPrompt.Text = $"root@mixtar:{path}#";
        SelectionStatus.Text = "No selection";
        _selectedFileRow = null;
        RenderFiles();
    }

    private void RenderFiles()
    {
        FileRows.Children.Clear();
        var query = FileSearch.Text?.Trim() ?? string.Empty;
        var entries = _fileSystem[_currentPath]
            .Where(entry => query.Length == 0 ||
                $"{entry.Name} {entry.Type} {entry.Role}".Contains(query, StringComparison.OrdinalIgnoreCase))
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
                    new ColumnDefinition(new GridLength(74)),
                    new ColumnDefinition(new GridLength(45)),
                    new ColumnDefinition(new GridLength(72)),
                    new ColumnDefinition(GridLength.Star)
                }
            };

            grid.Children.Add(Cell($"{IconFor(entry)}  {entry.Name}", 0, "#D8E7FF"));
            grid.Children.Add(Cell(entry.Type, 1, "#9EC1EF"));
            grid.Children.Add(Cell(entry.Items, 2, "#9EC1EF"));
            grid.Children.Add(Cell(entry.Modified, 3, "#9EC1EF"));
            grid.Children.Add(Cell(entry.Role, 4, "#9EC1EF"));
            row.Child = grid;

            row.PointerPressed += (_, args) =>
            {
                _selectedFileRow?.Classes.Remove("selected");
                row.Classes.Add("selected");
                _selectedFileRow = row;
                SelectionStatus.Text = $"{entry.Name} selected";
                args.Handled = true;
            };

            FileRows.Children.Add(row);
        }

        ItemCount.Text = $"{entries.Length} item{(entries.Length == 1 ? string.Empty : "s")}";
    }

    private static TextBlock Cell(string text, int column, string color)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = 9,
            Foreground = new SolidColorBrush(Color.Parse(color)),
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(block, column);
        return block;
    }

    private static string IconFor(FileEntry entry) => entry.Type switch
    {
        "Dir" => "▣",
        "Service" => "◈",
        "Application" => "◇",
        "Volume" => "▰",
        "User" => "●",
        "Log" => "≡",
        _ => "□"
    };

    private static string NormalizePath(string raw)
    {
        var path = (raw ?? string.Empty).Trim();
        if (path.StartsWith("MIXTARROOT:", StringComparison.OrdinalIgnoreCase))
        {
            path = path["MIXTARROOT:".Length..];
        }

        if (path.Length == 0) return "/";
        if (!path.StartsWith('/')) path = "/" + path;
        return path.Length > 1 ? path.TrimEnd('/') : path;
    }

    private static string ParentPath(string path)
    {
        if (path == "/") return "/";
        var index = path.LastIndexOf('/');
        return index <= 0 ? "/" : path[..index];
    }

    private void OnFileSearchChanged(object? sender, TextChangedEventArgs e) => RenderFiles();

    private void EnterAddressMode()
    {
        Breadcrumb.IsVisible = false;
        AddressBox.IsVisible = true;
        AddressBox.Focus();
        AddressBox.SelectAll();
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
            Navigate(AddressBox.Text ?? "/");
            ExitAddressMode();
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            ExitAddressMode();
            e.Handled = true;
        }
    }

    private void OnAddressLostFocus(object? sender, RoutedEventArgs e) => ExitAddressMode();

    private void ExitAddressMode()
    {
        AddressBox.IsVisible = false;
        Breadcrumb.IsVisible = true;
    }

    private void OnTerminalKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;

        var command = TerminalInput.Text?.Trim() ?? string.Empty;
        if (command.Length == 0) return;

        AppendTerminal($"{TerminalPrompt.Text} {command}", "#FFFFFF");
        TerminalInput.Text = string.Empty;

        switch (command.ToLowerInvariant())
        {
            case "clear":
                TerminalLines.Children.Clear();
                break;
            case "files":
                ShowWindow(FilesWindow);
                break;
            case "network":
                ShowWindow(NetworkWindow);
                break;
            case "runtime":
                ShowWindow(RuntimeWindow);
                break;
            case "root":
                ShowWindow(FilesWindow);
                Navigate("/");
                break;
            case "verify":
                AppendTerminal("ok: native root clean | APX Executor online | PASS", "#27EE91");
                break;
            default:
                AppendTerminal("visual shell: command simulated", "#FFC65C");
                break;
        }

        e.Handled = true;
    }

    private void AppendTerminal(string text, string color)
    {
        TerminalLines.Children.Add(new TextBlock
        {
            Text = text,
            Foreground = new SolidColorBrush(Color.Parse(color)),
            FontFamily = new FontFamily("Noto Sans Mono"),
            FontSize = 10,
            TextWrapping = TextWrapping.Wrap
        });
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
        AppendTerminal($"[NET] selected {node.Name} ({node.Address})", "#91B7E8");
    }

    private void OnHudPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (e.Source is Button || e.Source is Control source && source.FindAncestorOfType<Button>() is not null)
        {
            return;
        }

        if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
        {
            BeginMoveDrag(e);
        }
    }

    private void OnWindowKeyDown(object? sender, KeyEventArgs e)
    {
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
        else if (e.Key == Key.Escape)
        {
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
