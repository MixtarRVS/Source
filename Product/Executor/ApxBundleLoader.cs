using Tomlyn.Model;

namespace Mixtar.Product.Executor;

internal static class ApxBundleLoader
{
    internal static ApxBundle Load(string path)
    {
        var declared = Path.GetFullPath(path);
        if (!Directory.Exists(declared) || !declared.EndsWith(".apx", StringComparison.Ordinal))
        {
            throw new ExecutorException("The application bundle must be a directory with the exact '.apx' suffix.");
        }

        RejectLink(declared, "The APX bundle may not be a symbolic link.");
        var root = Path.GetFullPath(declared);
        var baseName = Path.GetFileName(root)[..^4];
        if (baseName.Length == 0)
        {
            throw new ExecutorException("The APX bundle name is empty.");
        }

        var config = Path.Combine(root, baseName + ".config");
        if (!File.Exists(config))
        {
            throw new ExecutorException($"The matching APX configuration is missing: {baseName}.config.");
        }

        RejectLink(config, "The APX configuration may not be a symbolic link.");
        var document = TomlConfig.Load(config, "APX configuration");
        var schema = TomlConfig.RequiredInteger(document, "schema", "schema");
        if (schema != ExecutorContract.ApxSchema)
        {
            throw new ExecutorException($"Unsupported APX schema: {schema}.");
        }

        var applicationTable = TomlConfig.RequiredTable(document, "application", "application");
        var applicationId = TomlConfig.RequiredString(applicationTable, "id", "application.id");
        var publisher = TomlConfig.OptionalString(applicationTable, "publisher", "application.publisher")
            ?? "local-unsigned";
        if (!IsStableIdentifier(applicationId, requireDot: true))
        {
            throw new ExecutorException("application.id must be a dotted stable identifier.");
        }

        if (!IsStableIdentifier(publisher, requireDot: false))
        {
            throw new ExecutorException("application.publisher is not a valid stable identifier.");
        }

        var application = new ApxApplication(
            applicationId,
            TomlConfig.RequiredString(applicationTable, "name", "application.name"),
            TomlConfig.RequiredString(applicationTable, "version", "application.version"),
            publisher);

        var entryTable = TomlConfig.RequiredTable(document, "entry", "entry");
        foreach (var key in entryTable.Keys)
        {
            if (!key.Equals("graphical", StringComparison.Ordinal)
                && !key.Equals("terminal", StringComparison.Ordinal))
            {
                throw new ExecutorException($"Unknown APX entry context: {key}.");
            }
        }

        var entries = new Dictionary<LaunchContext, ApxEntry>();
        AddEntry(entries, root, entryTable, "graphical", LaunchContext.Graphical);
        AddEntry(entries, root, entryTable, "terminal", LaunchContext.Terminal);
        if (entries.Count == 0)
        {
            throw new ExecutorException("APX requires [entry.graphical] or [entry.terminal].");
        }

        var permissions = TomlConfig.OptionalTable(document, "capabilities", "capabilities");
        var required = TomlConfig.StringSet(permissions, "required", "capabilities.required");
        var optional = TomlConfig.StringSet(permissions, "optional", "capabilities.optional");
        ValidateCapabilities(required, "capabilities.required");
        ValidateCapabilities(optional, "capabilities.optional");
        var overlap = required
            .Intersect(optional, StringComparer.Ordinal)
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        if (overlap.Length != 0)
        {
            throw new ExecutorException(
                $"Capabilities cannot be both required and optional: {string.Join(", ", overlap)}.");
        }

        return new ApxBundle(root, config, application, entries, required, optional);
    }

    private static void AddEntry(
        IDictionary<LaunchContext, ApxEntry> entries,
        string bundleRoot,
        TomlTable entryTable,
        string key,
        LaunchContext context)
    {
        if (!entryTable.TryGetValue(key, out var value))
        {
            return;
        }

        if (value is not TomlTable table)
        {
            throw new ExecutorException($"[entry.{key}] must be a table.");
        }

        var type = TomlConfig.RequiredString(table, "kind", $"entry.{key}.type");
        if (!type.Equals("native", StringComparison.Ordinal))
        {
            throw new ExecutorException($"entry.{key}.type must be 'native' in APX v1.");
        }

        var relative = TomlConfig.RequiredString(table, "path", $"entry.{key}.path");
        var executable = ResolveEntry(bundleRoot, relative, $"entry.{key}.path");
        ValidateElfX64(executable, $"entry.{key}.path");
        entries.Add(context, new ApxEntry(context, relative, executable));
    }

    private static string ResolveEntry(string bundleRoot, string relative, string label)
    {
        if (relative.StartsWith("/", StringComparison.Ordinal) || relative.Contains('\\'))
        {
            throw new ExecutorException($"{label} must use a relative path with '/' separators.");
        }

        var segments = relative.Split('/', StringSplitOptions.None);
        if (segments.Length == 0
            || segments.Any(segment => segment.Length == 0 || segment is "." or ".."))
        {
            throw new ExecutorException($"{label} contains an empty, '.' or '..' segment.");
        }

        var cursor = bundleRoot;
        foreach (var segment in segments)
        {
            cursor = Path.Combine(cursor, segment);
            if (File.Exists(cursor) || Directory.Exists(cursor))
            {
                RejectLink(cursor, $"{label} may not traverse a symbolic link.");
            }
        }

        var executable = Path.GetFullPath(cursor);
        var prefix = bundleRoot.EndsWith(Path.DirectorySeparatorChar)
            ? bundleRoot
            : bundleRoot + Path.DirectorySeparatorChar;
        if (!executable.StartsWith(prefix, StringComparison.Ordinal) || !File.Exists(executable))
        {
            throw new ExecutorException($"{label} escapes the bundle or is not a file.");
        }

        if (OperatingSystem.IsLinux())
        {
            var mode = File.GetUnixFileMode(executable);
            var executableBits = UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute;
            if ((mode & executableBits) == 0)
            {
                throw new ExecutorException($"{label} is not executable.");
            }
        }

        return executable;
    }

    private static void ValidateElfX64(string path, string label)
    {
        Span<byte> header = stackalloc byte[20];
        using var stream = File.OpenRead(path);
        if (stream.Read(header) != header.Length
            || header[0] != 0x7f
            || header[1] != (byte)'E'
            || header[2] != (byte)'L'
            || header[3] != (byte)'F')
        {
            throw new ExecutorException($"{label} is not an ELF executable.");
        }

        if (header[4] != 2 || header[5] != 1)
        {
            throw new ExecutorException($"{label} must be a little-endian ELF64 executable.");
        }

        var type = header[16] | header[17] << 8;
        var machine = header[18] | header[19] << 8;
        if ((type != 2 && type != 3) || machine != 62)
        {
            throw new ExecutorException($"{label} must be an x86_64 ET_EXEC or ET_DYN ELF.");
        }
    }

    private static void ValidateCapabilities(IEnumerable<string> capabilities, string label)
    {
        var unknown = capabilities
            .Where(capability => !ExecutorContract.KnownCapabilities.Contains(capability))
            .OrderBy(value => value, StringComparer.Ordinal)
            .ToArray();
        if (unknown.Length != 0)
        {
            throw new ExecutorException($"Unknown capabilities in {label}: {string.Join(", ", unknown)}.");
        }
    }

    private static bool IsStableIdentifier(string value, bool requireDot)
    {
        if (value.Length is < 1 or > 128
            || (requireDot && !value.Contains('.'))
            || !char.IsAsciiLetterOrDigit(value[0])
            || !char.IsAsciiLetterOrDigit(value[^1]))
        {
            return false;
        }

        return value.All(character =>
            char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or '-');
    }

    private static void RejectLink(string path, string message)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
        {
            throw new ExecutorException(message);
        }
    }
}
