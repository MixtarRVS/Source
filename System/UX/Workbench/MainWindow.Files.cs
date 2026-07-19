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
                TreePanel.Children.Add(TreeButton($"▰  {DriveDisplayName(drive.Name[..1])}", drive.RootDirectory.FullName));
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

    private TextBlock TreeHeader(string text) => new()
    {
        Text = text,
        Margin = new Thickness(8, 8, 8, 4),
        Foreground = Token("HeadingBrush"),
        FontFamily = new FontFamily("Noto Sans Mono"),
        FontSize = 11,
        FontWeight = FontWeight.Bold
    };

    private Button TreeButton(string label, string path)
    {
        var button = new Button { Content = label, Tag = path };
        button.Classes.Add("tree");
        button.Click += OnTreePath;
        button.PointerPressed += (_, args) =>
        {
            if (args.GetCurrentPoint(button).Properties.IsMiddleButtonPressed)
            {
                OpenBackgroundTab(path);
                args.Handled = true;
            }
        };
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
        PathHint.Text = path;
        BuildBreadcrumb(path);
        AddressBox.Text = path;
        TerminalPrompt.Text = $"root@{HostName()}:{path}#";
        // Selection never survives a directory change - stale paths in the
        // set would make Delete reach into a previously visited folder.
        _selectedPaths.Clear();
        SelectionStatus.Text = "No selection";
        _selectedFileRow = null;
        _selectedPath = null;
        ResetDeleteButton();
        UpdateVolumeInfo(path);
        RenderFiles();
        if (_fileTabs.Count > 0)
        {
            _fileTabs[_activeFileTab].Path = path;
            RenderFileTabs();
        }
    }

    // ------------------------------------------------------------------
    // Titlebar tabs (Mixtar-Studio pattern): each tab owns its own path
    // and navigation history.
    // ------------------------------------------------------------------

    // Explorer semantics: drive roots are shown as "<volume label> (X:)";
    // the raw "X:\" form appears only in the editable address box.
    private static string DriveDisplayName(string letter)
    {
        letter = letter.ToUpperInvariant();
        try
        {
            var info = new DriveInfo(letter);
            var label = info.VolumeLabel;
            if (string.IsNullOrWhiteSpace(label))
            {
                label = info.DriveType == DriveType.Removable ? "Removable Disk" : "Local Disk";
            }

            return $"{label} ({letter}:)";
        }
        catch
        {
            return $"{letter}:";
        }
    }

    private static string TabLabel(string path)
    {
        var trimmed = path.TrimEnd('/', '\\');
        if (trimmed.Length == 0)
        {
            return "⌂ Root";
        }

        if (trimmed.Length == 2 && trimmed[1] == ':')
        {
            return $"▰ {DriveDisplayName(trimmed[..1])}";
        }

        var name = IOPath.GetFileName(trimmed);
        return name.Length > 0 ? $"▣ {name}" : trimmed;
    }

    private void SaveActiveTabState()
    {
        if (_fileTabs.Count == 0)
        {
            return;
        }

        var tab = _fileTabs[_activeFileTab];
        tab.Path = _currentPath;
        tab.History = _history;
        tab.HistoryIndex = _historyIndex;
    }

    private void SwitchFileTab(int index)
    {
        if (index < 0 || index >= _fileTabs.Count)
        {
            return;
        }

        SaveActiveTabState();
        _activeFileTab = index;
        var tab = _fileTabs[index];
        _history = tab.History;
        _historyIndex = tab.HistoryIndex;
        Navigate(tab.Path, recordHistory: false);
        RenderFileTabs();
    }

    private void OnAddFileTab(object? sender, RoutedEventArgs e)
    {
        SaveActiveTabState();
        var tab = new FileTab
        {
            Path = _currentPath,
            History = new List<string> { _currentPath },
            HistoryIndex = 0
        };
        _fileTabs.Add(tab);
        SwitchFileTab(_fileTabs.Count - 1);
    }

    private void CloseFileTab(int index)
    {
        if (_fileTabs.Count <= 1 || index < 0 || index >= _fileTabs.Count)
        {
            return;
        }

        _fileTabs.RemoveAt(index);
        if (_activeFileTab >= _fileTabs.Count)
        {
            _activeFileTab = _fileTabs.Count - 1;
        }
        else if (index < _activeFileTab)
        {
            _activeFileTab--;
        }

        var tab = _fileTabs[_activeFileTab];
        _history = tab.History;
        _historyIndex = tab.HistoryIndex;
        Navigate(tab.Path, recordHistory: false);
        RenderFileTabs();
    }

    private void OpenBackgroundTab(string path)
    {
        SaveActiveTabState();
        _fileTabs.Add(new FileTab
        {
            Path = path,
            History = new List<string> { path },
            HistoryIndex = 0
        });
        RenderFileTabs();
    }

    // Explorer semantics: uniform tab width, inline close button,
    // middle-click closes a tab.
    private void RenderFileTabs()
    {
        FileTabsPanel.Children.Clear();
        for (var index = 0; index < _fileTabs.Count; index++)
        {
            var tab = _fileTabs[index];
            var captured = index;

            var label = new TextBlock
            {
                Text = TabLabel(tab.Path),
                FontSize = 12,
                VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            var content = new Grid
            {
                ColumnDefinitions =
                {
                    new ColumnDefinition(GridLength.Star),
                    new ColumnDefinition(GridLength.Auto)
                },
                Children = { label }
            };
            if (_fileTabs.Count > 1)
            {
                var close = new Button { Content = "✕" };
                close.Classes.Add("tab-close");
                close.Click += (_, _) => CloseFileTab(captured);
                Grid.SetColumn(close, 1);
                content.Children.Add(close);
            }

            var button = new Button
            {
                Content = content,
                Width = 150,
                HorizontalContentAlignment = Avalonia.Layout.HorizontalAlignment.Stretch
            };
            button.Classes.Add("file-tab");
            if (index == _activeFileTab)
            {
                button.Classes.Add("active");
            }

            button.Click += (_, _) => SwitchFileTab(captured);
            button.PointerPressed += (_, args) =>
            {
                if (args.GetCurrentPoint(button).Properties.IsMiddleButtonPressed)
                {
                    CloseFileTab(captured);
                    args.Handled = true;
                }
            };

            FileTabsPanel.Children.Add(button);
        }
    }

    private void BuildBreadcrumb(string path)
    {
        BreadcrumbPanel.Children.Clear();
        var isDrivePath = path.Length >= 2 && path[1] == ':';
        var rootLabel = isDrivePath ? $"▰ {DriveBreadcrumb(path)}" : "⌂ MixtarRVS";
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
                Foreground = Token("MutedBrush"),
                FontSize = 10,
                Margin = new Thickness(4, 0),
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
        var entries = isDirectory && type != "Link" ? "dir" : "-";

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

    private Listing[] ListDirectoryBlocking(string path)
    {
        try
        {
            var directory = new DirectoryInfo(path);
            return directory.EnumerateFileSystemInfos().Select(DescribeEntry).ToArray();
        }
        catch (Exception error)
        {
            throw new IOException($"Could not enumerate {path}.", error);
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

            grid.Children.Add(Cell($"{IconFor(entry)}  {entry.Name}", 0, Token("ListTextBrush")));
            grid.Children.Add(Cell(entry.Type, 1, Token("SoftBrush")));
            grid.Children.Add(Cell(entry.Size, 2, Token("SoftBrush")));
            grid.Children.Add(Cell(entry.Modified, 3, Token("SoftBrush")));
            grid.Children.Add(Cell(entry.Entries, 4, Token("SoftBrush")));
            row.Child = grid;

            var captured = entry;
            row.Tag = entry.FullPath;
            if (_selectedPaths.Contains(entry.FullPath))
            {
                row.Classes.Add("selected");
            }

            row.ContextFlyout = BuildFileContextMenu(captured);
            row.PointerPressed += (_, args) =>
            {
                if (captured.IsDirectory &&
                    args.GetCurrentPoint(row).Properties.IsMiddleButtonPressed)
                {
                    OpenBackgroundTab(captured.FullPath);
                    args.Handled = true;
                    return;
                }

                // Explorer semantics: right-press on an already-selected row
                // keeps the multi-selection for the context menu; on an
                // unselected row it retargets the selection first.
                if (args.GetCurrentPoint(row).Properties.IsRightButtonPressed)
                {
                    if (!_selectedPaths.Contains(captured.FullPath))
                    {
                        ClearSelection();
                        _selectedPaths.Add(captured.FullPath);
                        row.Classes.Add("selected");
                        _selectedFileRow = row;
                        _selectedPath = captured.FullPath;
                        UpdateSelectionStatus();
                        ResetDeleteButton();
                    }

                    return;
                }

                if (!args.GetCurrentPoint(row).Properties.IsLeftButtonPressed)
                {
                    return;
                }

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

                if (args.KeyModifiers.HasFlag(KeyModifiers.Control))
                {
                    // Explorer semantics: Ctrl+click toggles membership.
                    if (_selectedPaths.Remove(captured.FullPath))
                    {
                        row.Classes.Remove("selected");
                        if (_selectedPath == captured.FullPath)
                        {
                            _selectedPath = _selectedPaths.FirstOrDefault();
                        }
                    }
                    else
                    {
                        _selectedPaths.Add(captured.FullPath);
                        row.Classes.Add("selected");
                        _selectedFileRow = row;
                        _selectedPath = captured.FullPath;
                    }
                }
                else
                {
                    ClearSelection();
                    _selectedPaths.Add(captured.FullPath);
                    row.Classes.Add("selected");
                    _selectedFileRow = row;
                    _selectedPath = captured.FullPath;
                }

                UpdateSelectionStatus();
                ResetDeleteButton();
                args.Handled = true;
            };

            FileRows.Children.Add(row);
        }

        ItemCount.Text = $"{entries.Length} item{(entries.Length == 1 ? string.Empty : "s")}";
    }

    private void ClearSelection()
    {
        foreach (var row in FileRows.Children.OfType<Border>())
        {
            row.Classes.Remove("selected");
        }

        _selectedPaths.Clear();
        _selectedFileRow = null;
    }

    private void UpdateSelectionStatus()
    {
        SelectionStatus.Text = _selectedPaths.Count switch
        {
            0 => "No selection",
            1 => $"{IOPath.GetFileName(_selectedPaths.First())} selected",
            var count => $"{count} selected"
        };
    }

    // ------------------------------------------------------------------
    // Rubber-band selection: drag on the empty list area. Row presses mark
    // the event handled, so the band only ever starts from empty space.
    // ------------------------------------------------------------------

    private void OnFileAreaPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!e.GetCurrentPoint(FileArea).Properties.IsLeftButtonPressed)
        {
            return;
        }

        _rubberOrigin = e.GetPosition(FileArea);
        _rubberActive = true;
        _rubberAdditive = e.KeyModifiers.HasFlag(KeyModifiers.Control);
        if (!_rubberAdditive)
        {
            ClearSelection();
            _selectedPath = null;
            UpdateSelectionStatus();
        }

        ResetDeleteButton();
        e.Pointer.Capture(FileArea);
    }

    private void OnFileAreaMoved(object? sender, PointerEventArgs e)
    {
        if (!_rubberActive)
        {
            return;
        }

        // Capture can vanish without a release reaching us (Alt+Tab away,
        // popup grabbing the pointer) - never track a button-less move.
        if (!e.GetCurrentPoint(FileArea).Properties.IsLeftButtonPressed)
        {
            CancelRubberBand();
            return;
        }

        var position = e.GetPosition(FileArea);
        var rect = new Rect(
            Math.Min(position.X, _rubberOrigin.X), Math.Min(position.Y, _rubberOrigin.Y),
            Math.Abs(position.X - _rubberOrigin.X), Math.Abs(position.Y - _rubberOrigin.Y));
        rect = rect.Intersect(new Rect(FileArea.Bounds.Size));
        if (!RubberBand.IsVisible && rect.Width < 4 && rect.Height < 4)
        {
            return;
        }

        RubberBand.IsVisible = true;
        RubberBand.Margin = new Thickness(rect.X, rect.Y, 0, 0);
        RubberBand.Width = rect.Width;
        RubberBand.Height = rect.Height;

        foreach (var row in FileRows.Children.OfType<Border>())
        {
            if (row.Tag is not string path ||
                row.TranslatePoint(new Point(0, 0), FileArea) is not { } topLeft)
            {
                continue;
            }

            var hit = rect.Intersects(new Rect(topLeft, row.Bounds.Size));
            if (hit && _selectedPaths.Add(path))
            {
                row.Classes.Add("selected");
                _selectedPath = path;
            }
            else if (!hit && !_rubberAdditive && _selectedPaths.Remove(path))
            {
                row.Classes.Remove("selected");
            }
        }

        if (_selectedPath is not null && !_selectedPaths.Contains(_selectedPath))
        {
            _selectedPath = _selectedPaths.FirstOrDefault();
        }

        UpdateSelectionStatus();
    }

    private void OnFileAreaReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_rubberActive)
        {
            return;
        }

        CancelRubberBand();
        e.Pointer.Capture(null);
    }

    private void CancelRubberBand()
    {
        _rubberActive = false;
        RubberBand.IsVisible = false;
        RubberBand.Width = 0;
        RubberBand.Height = 0;
    }

    private void OnBackgroundNewFolder(object? sender, RoutedEventArgs e) => CreateNewFolder();

    private void OnBackgroundRefresh(object? sender, RoutedEventArgs e) => RenderFiles();

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
        var rename = new MenuItem { Header = "Rename" };
        rename.Click += (_, _) => BeginRename(entry);
        var delete = new MenuItem { Header = "Delete" };
        delete.Click += (_, _) =>
        {
            // Explorer semantics: acting on an unselected row retargets the
            // selection to that row first.
            if (!_selectedPaths.Contains(entry.FullPath))
            {
                ClearSelection();
                _selectedPaths.Add(entry.FullPath);
            }

            _selectedPath = entry.FullPath;
            DeleteSelected();
        };
        flyout.Items.Add(open);
        flyout.Items.Add(copyPath);
        flyout.Items.Add(rename);
        flyout.Items.Add(delete);
        return flyout;
    }

    // Inline rename (F2 / context menu): the name cell swaps for a TextBox;
    // Enter commits, Escape cancels, focus loss commits - Explorer rules.
    private bool _renameActive;

    private void BeginRename(Listing entry)
    {
        if (_renameActive)
        {
            return;
        }

        var row = FileRows.Children.OfType<Border>()
            .FirstOrDefault(item => item.Tag as string == entry.FullPath);
        if (row?.Child is not Grid grid || grid.Children.Count == 0)
        {
            return;
        }

        _renameActive = true;

        var box = new TextBox
        {
            Text = entry.Name,
            FontSize = 11,
            MinHeight = 24,
            Padding = new Thickness(4, 0),
            Margin = new Thickness(0, 2, 8, 2),
            VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
        };
        Grid.SetColumn(box, 0);
        grid.Children[0].IsVisible = false;
        grid.Children.Add(box);

        var done = false;
        void Finish(bool commit)
        {
            if (done)
            {
                return;
            }

            done = true;
            _renameActive = false;
            var fresh = box.Text?.Trim() ?? string.Empty;
            if (commit && fresh.Length > 0 && fresh != entry.Name &&
                fresh.IndexOfAny(IOPath.GetInvalidFileNameChars()) < 0)
            {
                try
                {
                    var target = IOPath.Combine(_currentPath, fresh);
                    if (entry.IsDirectory)
                    {
                        FileMutationPolicy.MoveDirectory(entry.FullPath, target);
                        RetargetTabs(entry.FullPath, target);
                    }
                    else
                    {
                        FileMutationPolicy.MoveFile(entry.FullPath, target);
                    }

                    _selectedPaths.Remove(entry.FullPath);
                    _selectedPaths.Add(target);
                    _selectedPath = target;
                }
                catch (Exception error)
                {
                    AppendTerminal($"[FS] rename failed: {error.Message}", "#FF5C7B");
                    SelectionStatus.Text = $"Rename failed: {error.Message}";
                    RenderFiles();
                    return;
                }
            }

            RenderFiles();
            UpdateSelectionStatus();
        }

        box.KeyDown += (_, args) =>
        {
            if (args.Key == Key.Enter)
            {
                Finish(true);
                args.Handled = true;
            }
            else if (args.Key == Key.Escape)
            {
                Finish(false);
                args.Handled = true;
            }
        };
        box.LostFocus += (_, _) => Finish(true);
        box.Focus();

        // Explorer preselects the name without its extension.
        var dot = entry.IsDirectory ? -1 : entry.Name.LastIndexOf('.');
        box.SelectionStart = 0;
        box.SelectionEnd = dot > 0 ? dot : entry.Name.Length;
    }

    // Renaming a directory must not orphan tabs that live inside it.
    private void RetargetTabsLegacy(string oldPath, string newPath)
    {
        foreach (var tab in _fileTabs)
        {
            if (tab.Path == oldPath)
            {
                tab.Path = newPath;
            }
            else if (tab.Path.StartsWith(oldPath + '/', StringComparison.Ordinal) ||
                     tab.Path.StartsWith(oldPath + '\\', StringComparison.Ordinal))
            {
                tab.Path = newPath + tab.Path[oldPath.Length..];
            }
        }

        RenderFileTabs();
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

            FileMutationPolicy.CreateDirectory(target);
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
        if (_selectedPaths.Count == 0 && _selectedPath is not null)
        {
            _selectedPaths.Add(_selectedPath);
        }

        if (_selectedPaths.Count == 0)
        {
            AppendTerminal("[FS] delete: nothing selected", "#FFC65C");
            return;
        }

        if ((DateTime.UtcNow - _deleteArmedAt).TotalSeconds > 4)
        {
            _deleteArmedAt = DateTime.UtcNow;
            DeleteButton.Content = _selectedPaths.Count > 1
                ? $"Confirm {_selectedPaths.Count}?"
                : "Confirm?";
            return;
        }

        // Per-item: one locked file must not stop the rest, and the list
        // must always re-render to reflect what actually happened.
        var failures = 0;
        foreach (var path in _selectedPaths.ToArray())
        {
            try
            {
                if (Directory.Exists(path))
                {
                    FileMutationPolicy.DeleteDirectory(path);
                }
                else
                {
                    FileMutationPolicy.DeleteFile(path);
                }

                _selectedPaths.Remove(path);
            }
            catch (Exception error)
            {
                failures++;
                AppendTerminal($"[FS] delete failed: {error.Message}", "#FF5C7B");
            }
        }

        _selectedPath = _selectedPaths.FirstOrDefault();
        RenderFiles();
        UpdateSelectionStatus();
        if (failures > 0)
        {
            SelectionStatus.Text = $"Delete failed for {failures} item{(failures == 1 ? string.Empty : "s")}";
        }

        ResetDeleteButton();
    }

    private static readonly string[] ImageExtensions =
        { ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".webp" };

    private void OpenViewer(string path)
    {
        if (ImageExtensions.Contains(IOPath.GetExtension(path).ToLowerInvariant()))
        {
            BeginLoadViewerImage(path);
            return;
        }

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
            ViewerImage.IsVisible = false;
            ViewerContent.IsVisible = true;
            ViewerContent.Text = content;
            ViewerScroll.Offset = default;
            ShowWindow(ViewerWindow);
        }
        catch (Exception error)
        {
            AppendTerminal($"[FS] open failed: {error.Message}", "#FF5C7B");
        }
    }

    private static TextBlock Cell(string text, int column, IBrush color)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = 11,
            Foreground = color,
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

    private static string ParentPathLegacy(string path)
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

        if (AddressBox.IsVisible && !Within(AddressBox) && !Within(AddressSuggestions) &&
            !Within(Breadcrumb))
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
                Foreground = Token("HeadingBrush"),
                FontFamily = new FontFamily("Noto Sans Mono"),
                FontSize = 10,
                FontWeight = FontWeight.Bold,
                Margin = new Thickness(8, 4, 8, 4)
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
}
