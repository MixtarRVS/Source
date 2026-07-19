using System;
using System.IO;
using System.Threading;

namespace Mixtar.UX.Workbench;

internal static class FileMutationPolicy
{
    private static long version;
    internal static long Version => Interlocked.Read(ref version);
    internal static void MoveDirectory(string source, string destination)
    { Demand(source); Demand(destination); Directory.Move(source, destination); Changed(); }
    internal static void MoveFile(string source, string destination)
    { Demand(source); Demand(destination); File.Move(source, destination); Changed(); }
    internal static void DeleteDirectory(string path)
    { Demand(path); Directory.Delete(path, recursive: false); Changed(); }
    internal static void DeleteFile(string path)
    { Demand(path); File.Delete(path); Changed(); }
    internal static DirectoryInfo CreateDirectory(string path)
    { Demand(path); var result = Directory.CreateDirectory(path); Changed(); return result; }
    private static void Changed() => Interlocked.Increment(ref version);

    private static void Demand(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            if (!"1".Equals(Environment.GetEnvironmentVariable("MIXTAR_WORKBENCH_ENABLE_HOST_WRITES"), StringComparison.Ordinal))
                throw new UnauthorizedAccessException(
                    "Host filesystem writes are disabled in Workbench Preview. Set MIXTAR_WORKBENCH_ENABLE_HOST_WRITES=1 to opt in.");
            return;
        }
        if (!"user-volumes".Equals(Environment.GetEnvironmentVariable("MIXTAR_STORAGE_WRITE"), StringComparison.Ordinal))
            throw new UnauthorizedAccessException("This Workbench session has no storage.write grant.");
        var full = Path.GetFullPath(path);
        var userRoot = Path.GetFullPath($"/Users/{WorkbenchConfig.UserName()}");
        if (!IsBelow(full, userRoot) && !IsBelow(full, "/Volumes"))
            throw new UnauthorizedAccessException(
                "Workbench may modify only the active user's profile and mounted volumes. System changes require an administrator broker.");
    }

    private static bool IsBelow(string path, string root)
    {
        var normalizedRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        return path.StartsWith(normalizedRoot, StringComparison.Ordinal);
    }
}
