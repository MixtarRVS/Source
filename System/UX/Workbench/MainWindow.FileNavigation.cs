using System;
using System.IO;

namespace Mixtar.UX.Workbench;

public sealed partial class MainWindow
{
    private void RetargetTabs(string oldPath, string newPath)
    {
        foreach (var tab in _fileTabs)
        {
            tab.Path = RetargetPath(tab.Path, oldPath, newPath);
            for (var index = 0; index < tab.History.Count; index++)
                tab.History[index] = RetargetPath(tab.History[index], oldPath, newPath);
        }
        RenderFileTabs();
    }

    private static string RetargetPath(string candidate, string oldPath, string newPath)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (candidate.Equals(oldPath, comparison)) return newPath;
        var prefix = oldPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        return candidate.StartsWith(prefix, comparison)
            ? newPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + candidate[(prefix.Length - 1)..] : candidate;
    }

    private static string ParentPath(string path)
    {
        var full = Path.GetFullPath(path); var root = Path.GetPathRoot(full) ?? "/";
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Equals(root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), comparison)) return root;
        return Directory.GetParent(full)?.FullName ?? root;
    }

    private static string DriveBreadcrumb(string path) => Path.GetPathRoot(path) ?? path;
}
