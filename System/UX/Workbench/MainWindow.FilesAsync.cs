using System;
using System.Collections.Concurrent;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Media.Imaging;
using Avalonia.Threading;

namespace Mixtar.UX.Workbench;

public sealed partial class MainWindow
{
    private sealed record DirectorySnapshot(Listing[] Entries, long MutationVersion);
    private readonly ConcurrentDictionary<string, DirectorySnapshot> _directorySnapshots = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, byte> _directoryLoads = new(StringComparer.Ordinal);
    private int _viewerGeneration;

    private Listing[] ListDirectory(string path)
    {
        var version = FileMutationPolicy.Version;
        _directorySnapshots.TryGetValue(path, out var snapshot);
        if (snapshot is not null && snapshot.MutationVersion == version) return snapshot.Entries;
        if (_directoryLoads.TryAdd(path, 0))
        {
            _ = Task.Run(() => ListDirectoryBlocking(path)).ContinueWith(task =>
            {
                _directoryLoads.TryRemove(path, out _);
                if (task.Status == TaskStatus.RanToCompletion)
                {
                    _directorySnapshots[path] = new DirectorySnapshot(task.Result, version);
                    Dispatcher.UIThread.Post(() =>
                    { if (string.Equals(_currentPath, path, StringComparison.Ordinal)) RenderFiles(); });
                }
                else if (task.Exception is not null)
                    Console.Error.WriteLine($"Workbench: directory scan failed: {task.Exception.GetBaseException().Message}");
            }, TaskScheduler.Default);
        }
        return snapshot?.Entries ?? [];
    }

    private void BeginLoadViewerImage(string path)
    {
        var generation = ++_viewerGeneration;
        ViewerImage.Source = null; ViewerImage.IsVisible = false;
        ViewerContent.IsVisible = true; ViewerContent.Text = "Loading image...";
        ViewerTitle.Text = $"VIEWER - {Path.GetFileName(path).ToUpperInvariant()}";
        ShowWindow(ViewerWindow);
        _ = Task.Run(() =>
        {
            if (new FileInfo(path).Length > 64L * 1024 * 1024)
                throw new InvalidDataException("Image exceeds the 64 MiB preview limit.");
            return new Bitmap(path);
        }).ContinueWith(task => Dispatcher.UIThread.Post(() =>
        {
            if (generation != _viewerGeneration)
            { if (task.Status == TaskStatus.RanToCompletion) task.Result.Dispose(); return; }
            if (task.Status == TaskStatus.RanToCompletion)
            {
                var previous = _viewerBitmap; _viewerBitmap = task.Result; ViewerImage.Source = task.Result;
                ViewerImage.IsVisible = true; ViewerContent.IsVisible = false;
                ViewerTitle.Text = $"VIEWER - {Path.GetFileName(path).ToUpperInvariant()} ({task.Result.PixelSize.Width}x{task.Result.PixelSize.Height})";
                ViewerScroll.Offset = default; previous?.Dispose();
            }
            else
            {
                ViewerImage.IsVisible = false; ViewerContent.IsVisible = true;
                ViewerContent.Text = $"Could not load image: {task.Exception?.GetBaseException().Message}";
            }
        }), TaskScheduler.Default);
    }
}
