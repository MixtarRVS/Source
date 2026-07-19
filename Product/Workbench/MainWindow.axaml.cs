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
    private sealed class FileTab
    {
        public string Path = "/";
        public List<string> History = new();
        public int HistoryIndex = -1;
    }

    private readonly Dictionary<Border, DesktopBounds> _restoreBounds = new();
    private readonly List<FileTab> _fileTabs = new();
    private int _activeFileTab;
    private List<string> _history = new();
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
    private readonly HashSet<string> _selectedPaths = new(StringComparer.Ordinal);
    private Point _rubberOrigin;
    private bool _rubberActive;
    private bool _rubberAdditive;
    private Avalonia.Media.Imaging.Bitmap? _viewerBitmap;
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
        LoadThemeOverrides();
        SizeToPrimaryScreen();
        foreach (var window in DesktopWindows())
        {
            // Tunnel: inside the 7px edge band the resize grab must win over
            // child buttons (Windows semantics - the frame sliver resizes even
            // over the caption buttons; the button body below still clicks).
            window.AddHandler(PointerPressedEvent, OnWindowResizePressed,
                RoutingStrategies.Tunnel);
            window.PointerMoved += OnWindowResizeMoved;
            window.PointerReleased += OnWindowResizeReleased;
        }

        FileArea.PointerCaptureLost += (_, _) => CancelRubberBand();

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
        _fileTabs.Add(new FileTab { Path = _currentPath, History = _history, HistoryIndex = _historyIndex });
        RenderFileTabs();
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

        if (e.Key == Key.F2 && _activeWindow == FilesWindow && _selectedPath is not null &&
            !_renameActive)
        {
            var entry = ListDirectory(_currentPath)
                .FirstOrDefault(item => item.FullPath == _selectedPath);
            if (entry is not null)
            {
                BeginRename(entry);
                e.Handled = true;
                return;
            }
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
