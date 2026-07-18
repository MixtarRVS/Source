using System.Collections;
using Tomlyn;
using Tomlyn.Model;

namespace Mixtar.Product.Executor;

internal static class TomlConfig
{
    internal static TomlTable Load(string path, string description)
    {
        string text;
        try
        {
            text = File.ReadAllText(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new ExecutorException($"Could not read {description}: {path}", error);
        }

        try
        {
            return TomlSerializer.Deserialize<TomlTable>(text, ExecutorTomlContext.Default)
                ?? throw new ExecutorException($"{description} is empty: {path}");
        }
        catch (ExecutorException)
        {
            throw;
        }
        catch (Exception error)
        {
            throw new ExecutorException($"Invalid TOML in {description}: {path}: {error.Message}", error);
        }
    }

    internal static TomlTable RequiredTable(TomlTable parent, string key, string label)
    {
        if (!parent.TryGetValue(key, out var value) || value is not TomlTable table)
        {
            throw new ExecutorException($"Missing or invalid [{label}] table.");
        }

        return table;
    }

    internal static TomlTable OptionalTable(TomlTable parent, string key, string label)
    {
        if (!parent.TryGetValue(key, out var value))
        {
            return new TomlTable();
        }

        if (value is not TomlTable table)
        {
            throw new ExecutorException($"Invalid [{label}] table.");
        }

        return table;
    }

    internal static long RequiredInteger(TomlTable table, string key, string label)
    {
        if (!table.TryGetValue(key, out var value) || value is not long number)
        {
            throw new ExecutorException($"Missing or invalid integer: {label}.");
        }

        return number;
    }

    internal static string RequiredString(TomlTable table, string key, string label)
    {
        if (!table.TryGetValue(key, out var value) || value is not string text || string.IsNullOrWhiteSpace(text))
        {
            throw new ExecutorException($"Missing or invalid string: {label}.");
        }

        if (text.IndexOf('\0') >= 0)
        {
            throw new ExecutorException($"NUL is not allowed in {label}.");
        }

        return text.Trim();
    }

    internal static string? OptionalString(TomlTable table, string key, string label)
    {
        if (!table.TryGetValue(key, out var value))
        {
            return null;
        }

        if (value is not string text || string.IsNullOrWhiteSpace(text))
        {
            throw new ExecutorException($"Invalid string: {label}.");
        }

        if (text.IndexOf('\0') >= 0)
        {
            throw new ExecutorException($"NUL is not allowed in {label}.");
        }

        return text.Trim();
    }

    internal static bool RequiredBoolean(TomlTable table, string key, string label)
    {
        if (!table.TryGetValue(key, out var value) || value is not bool flag)
        {
            throw new ExecutorException($"Missing or invalid boolean: {label}.");
        }

        return flag;
    }

    internal static IReadOnlySet<string> StringSet(TomlTable table, string key, string label)
    {
        if (!table.TryGetValue(key, out var value))
        {
            return new HashSet<string>(StringComparer.Ordinal);
        }

        if (value is string || value is not IEnumerable sequence)
        {
            throw new ExecutorException($"{label} must be an array of strings.");
        }

        var result = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in sequence)
        {
            if (item is not string text || string.IsNullOrWhiteSpace(text))
            {
                throw new ExecutorException($"{label} contains a non-string or empty value.");
            }

            text = text.Trim();
            if (!result.Add(text))
            {
                throw new ExecutorException($"{label} contains a duplicate value: {text}.");
            }
        }

        return result;
    }
}
