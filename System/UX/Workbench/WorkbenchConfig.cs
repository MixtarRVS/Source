using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace Mixtar.UX.Workbench;

internal static class WorkbenchConfig
{
    internal const long Schema = 1;

    internal static string UserName()
    {
        var value = Environment.GetEnvironmentVariable("MIXTAR_USER")
            ?? Environment.GetEnvironmentVariable("USER")
            ?? Environment.UserName
            ?? "Administrator";
        var safe = new string(value.Where(character =>
            char.IsAsciiLetterOrDigit(character) || character is '_' or '-' or '.').ToArray());
        return string.IsNullOrWhiteSpace(safe) ? "Administrator" : safe;
    }

    internal static string UserInterfaceRoot()
    {
        if (!OperatingSystem.IsWindows()) return $"/Users/{UserName()}/.Interface";
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MixtarWorkbench", "Interface");
    }

    internal static string ThemePath() => Path.Combine(UserInterfaceRoot(), "Theme.config");
    internal static string LayoutPath() => Path.Combine(UserInterfaceRoot(), "Workbench", "Layout.config");
    internal static string SystemThemePath => "/System/UX/Interface/Theme.config";

    internal static IReadOnlyDictionary<string, string> ReadFlatToml(string path)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var tables = new HashSet<string>(StringComparer.Ordinal);
        var table = string.Empty;
        var lineNumber = 0;
        foreach (var source in File.ReadLines(path, Encoding.UTF8))
        {
            lineNumber++;
            var line = StripComment(source).Trim();
            if (line.Length == 0) continue;
            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                table = line[1..^1].Trim();
                ValidateDottedKey(table, path, lineNumber);
                if (!tables.Add(table))
                    throw new InvalidDataException($"Duplicate TOML table [{table}] in {path}:{lineNumber}.");
                continue;
            }
            var separator = FindUnquoted(line, '=');
            if (separator <= 0)
                throw new InvalidDataException($"Invalid TOML assignment in {path}:{lineNumber}.");
            var key = line[..separator].Trim();
            ValidateDottedKey(key, path, lineNumber);
            var value = ParseValue(line[(separator + 1)..].Trim(), path, lineNumber);
            var fullKey = table.Length == 0 ? key : $"{table}.{key}";
            if (!result.TryAdd(fullKey, value))
                throw new InvalidDataException($"Duplicate TOML key {fullKey} in {path}:{lineNumber}.");
        }
        return result;
    }

    internal static void RequireSchema(IReadOnlyDictionary<string, string> values, string path)
    {
        if (!values.TryGetValue("schema", out var schema)
            || !long.TryParse(schema, NumberStyles.Integer, CultureInfo.InvariantCulture, out var number)
            || number != Schema)
            throw new InvalidDataException($"Unsupported or missing schema in {path}.");
    }

    internal static string TomlString(string value) =>
        "\"" + value.Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\t", "\\t", StringComparison.Ordinal) + "\"";

    internal static string Number(double value) => value.ToString("0.###", CultureInfo.InvariantCulture);

    internal static void AtomicWrite(string path, IEnumerable<string> lines)
    {
        var directory = Path.GetDirectoryName(path)
            ?? throw new InvalidDataException($"Configuration path has no parent: {path}.");
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
            {
                foreach (var line in lines) writer.WriteLine(line);
                writer.Flush();
                stream.Flush(true);
            }
            File.Move(temporary, path, true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    private static string StripComment(string source)
    {
        var quoted = false;
        var escaped = false;
        for (var index = 0; index < source.Length; index++)
        {
            var character = source[index];
            if (escaped) { escaped = false; continue; }
            if (quoted && character == '\\') { escaped = true; continue; }
            if (character == '"') { quoted = !quoted; continue; }
            if (!quoted && character == '#') return source[..index];
        }
        return source;
    }

    private static int FindUnquoted(string source, char wanted)
    {
        var quoted = false;
        var escaped = false;
        for (var index = 0; index < source.Length; index++)
        {
            var character = source[index];
            if (escaped) { escaped = false; continue; }
            if (quoted && character == '\\') { escaped = true; continue; }
            if (character == '"') { quoted = !quoted; continue; }
            if (!quoted && character == wanted) return index;
        }
        return -1;
    }

    private static void ValidateDottedKey(string key, string path, int lineNumber)
    {
        if (key.Length == 0 || key.Split('.').Any(segment => segment.Length == 0
            || segment.Any(character => !char.IsAsciiLetterOrDigit(character)
                && character != '_' && character != '-')))
            throw new InvalidDataException($"Invalid TOML key {key} in {path}:{lineNumber}.");
    }

    private static string ParseValue(string source, string path, int lineNumber)
    {
        if (source.Length == 0) throw new InvalidDataException($"Missing TOML value in {path}:{lineNumber}.");
        if (source[0] != '"') return source;
        if (source.Length < 2 || source[^1] != '"')
            throw new InvalidDataException($"Unterminated TOML string in {path}:{lineNumber}.");
        var result = new StringBuilder();
        var escaped = false;
        foreach (var character in source[1..^1])
        {
            if (!escaped)
            {
                if (character == '\\') escaped = true;
                else result.Append(character);
                continue;
            }
            result.Append(character switch
            {
                'n' => '\n', 'r' => '\r', 't' => '\t', '"' => '"', '\\' => '\\',
                _ => throw new InvalidDataException($"Unsupported TOML escape in {path}:{lineNumber}.")
            });
            escaped = false;
        }
        if (escaped) throw new InvalidDataException($"Unterminated TOML escape in {path}:{lineNumber}.");
        return result.ToString();
    }
}
