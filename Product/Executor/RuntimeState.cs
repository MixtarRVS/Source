using System.Text;
using Tomlyn.Model;

namespace Mixtar.Product.Executor;

internal sealed class ExecutorEnvironment
{
    internal ExecutorEnvironment()
    {
        var configured = Environment.GetEnvironmentVariable("MIXTAR_ROOT");
        Root = string.IsNullOrWhiteSpace(configured)
            ? Path.GetPathRoot(Path.GetFullPath("/")) ?? "/"
            : Path.GetFullPath(configured);
    }

    internal string Root { get; }

    internal string MapLogical(string logical)
    {
        var normalized = NormalizeLogical(logical);
        if (Root == "/")
        {
            return normalized;
        }

        return Path.GetFullPath(Path.Combine(
            Root,
            normalized[1..].Replace('/', Path.DirectorySeparatorChar)));
    }

    internal string ResolveInput(string value)
    {
        if (value.StartsWith("/", StringComparison.Ordinal) && Root != "/")
        {
            return MapLogical(value);
        }

        return Path.GetFullPath(value);
    }

    internal string ToLogical(string physical)
    {
        var full = Path.GetFullPath(physical);
        if (Root == "/")
        {
            return "/" + full.TrimStart(Path.DirectorySeparatorChar).Replace(Path.DirectorySeparatorChar, '/');
        }

        var relative = Path.GetRelativePath(Root, full);
        if (relative == ".."
            || relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal)
            || Path.IsPathRooted(relative))
        {
            throw new ExecutorException($"Path is outside the Mixtar root: {physical}.");
        }

        return "/" + relative.Replace(Path.DirectorySeparatorChar, '/');
    }

    private static string NormalizeLogical(string logical)
    {
        if (!logical.StartsWith("/", StringComparison.Ordinal) || logical.Contains('\\'))
        {
            throw new ExecutorException($"Mixtar path must be absolute and use '/' separators: {logical}.");
        }

        var segments = logical.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(segment => segment is "." or ".."))
        {
            throw new ExecutorException($"Mixtar path may not contain '.' or '..': {logical}.");
        }

        return "/" + string.Join('/', segments);
    }
}

internal sealed record ExecutorOptions(
    string Sessions,
    string Policies,
    string Logs,
    string Users,
    bool RequireActiveSession,
    bool DenySystemAdminProcess)
{
    internal static ExecutorOptions Load(ExecutorEnvironment environment)
    {
        var config = environment.MapLogical(ExecutorContract.RuntimeConfig);
        var document = TomlConfig.Load(config, "Executor configuration");
        if (TomlConfig.RequiredInteger(document, "schema", "schema")
            != ExecutorContract.ConfigurationSchema)
        {
            throw new ExecutorException("Unsupported Executor configuration schema.");
        }

        var paths = TomlConfig.RequiredTable(document, "paths", "paths");
        var security = TomlConfig.RequiredTable(document, "security", "security");
        var result = new ExecutorOptions(
            TomlConfig.RequiredString(paths, "sessions", "paths.sessions"),
            TomlConfig.RequiredString(paths, "policies", "paths.policies"),
            TomlConfig.RequiredString(paths, "logs", "paths.logs"),
            TomlConfig.RequiredString(paths, "users", "paths.users"),
            TomlConfig.RequiredBoolean(security, "require_active_session", "security.require_active_session"),
            TomlConfig.RequiredBoolean(security, "deny_system_admin_process", "security.deny_system_admin_process"));
        foreach (var path in new[] { result.Sessions, result.Policies, result.Logs, result.Users })
        {
            _ = environment.MapLogical(path);
        }

        return result;
    }
}

internal static class SessionStore
{
    internal static SessionRecord Load(
        ExecutorEnvironment environment,
        ExecutorOptions options,
        string sessionId,
        string user)
    {
        ValidateToken(sessionId, "session id");
        ValidateToken(user, "user name");
        var logicalDirectory = options.Sessions.TrimEnd('/') + "/" + sessionId;
        var physicalDirectory = environment.MapLogical(logicalDirectory);
        var path = Path.Combine(physicalDirectory, "Session.config");
        if (!File.Exists(path))
        {
            throw new ExecutorException($"Session does not exist: {sessionId}.");
        }

        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
        {
            throw new ExecutorException("Session configuration may not be a symbolic link.");
        }

        var document = TomlConfig.Load(path, "session configuration");
        if (TomlConfig.RequiredInteger(document, "schema", "schema") != ExecutorContract.SessionSchema)
        {
            throw new ExecutorException("Unsupported session schema.");
        }

        var table = TomlConfig.RequiredTable(document, "session", "session");
        var storedId = TomlConfig.RequiredString(table, "id", "session.id");
        var storedUser = TomlConfig.RequiredString(table, "user", "session.user");
        var type = TomlConfig.RequiredString(table, "type", "session.type");
        var state = TomlConfig.RequiredString(table, "state", "session.state");
        var wayland = TomlConfig.OptionalString(table, "wayland_display", "session.wayland_display");
        if (!storedId.Equals(sessionId, StringComparison.Ordinal)
            || !storedUser.Equals(user, StringComparison.Ordinal))
        {
            throw new ExecutorException("Session identity does not match the launch request.");
        }

        if (type is not ("console" or "graphical"))
        {
            throw new ExecutorException($"Unknown session type: {type}.");
        }

        if (options.RequireActiveSession && !state.Equals("active", StringComparison.Ordinal))
        {
            throw new ExecutorException($"Session is not active: {sessionId}.");
        }

        return new SessionRecord(
            storedId,
            storedUser,
            type,
            state,
            wayland,
            logicalDirectory,
            physicalDirectory);
    }

    internal static void ValidateToken(string value, string label)
    {
        if (value.Length is < 1 or > 64
            || !char.IsAsciiLetterOrDigit(value[0])
            || value.Any(character =>
                !char.IsAsciiLetterOrDigit(character) && character is not ('.' or '_' or '-')))
        {
            throw new ExecutorException($"Invalid {label}: {value}.");
        }
    }
}

internal static class CapabilityPolicy
{
    internal static Authorization Authorize(
        ExecutorEnvironment environment,
        ExecutorOptions options,
        ApxBundle bundle,
        LaunchContext context,
        SessionRecord session)
    {
        var policyPath = environment.MapLogical(
            options.Policies.TrimEnd('/') + "/" + bundle.Application.Id + ".config");
        IReadOnlySet<string> grants = new HashSet<string>(StringComparer.Ordinal);
        if (File.Exists(policyPath))
        {
            if ((File.GetAttributes(policyPath) & FileAttributes.ReparsePoint) != 0)
            {
                throw new ExecutorException("Application policy may not be a symbolic link.");
            }

            var document = TomlConfig.Load(policyPath, "application capability policy");
            if (TomlConfig.RequiredInteger(document, "schema", "schema") != ExecutorContract.PolicySchema)
            {
                throw new ExecutorException("Unsupported capability policy schema.");
            }

            var application = TomlConfig.RequiredTable(document, "application", "application");
            var policyId = TomlConfig.RequiredString(application, "id", "application.id");
            var policyPublisher = TomlConfig.RequiredString(application, "publisher", "application.publisher");
            if (!policyId.Equals(bundle.Application.Id, StringComparison.Ordinal)
                || !policyPublisher.Equals(bundle.Application.Publisher, StringComparison.Ordinal))
            {
                throw new ExecutorException("Application policy identity does not match the APX bundle.");
            }

            var grant = TomlConfig.RequiredTable(document, "grant", "grant");
            grants = TomlConfig.StringSet(grant, "capabilities", "grant.capabilities");
            var unknown = grants
                .Where(capability => !ExecutorContract.KnownCapabilities.Contains(capability))
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            if (unknown.Length != 0)
            {
                throw new ExecutorException(
                    $"Policy contains unknown capabilities: {string.Join(", ", unknown)}.");
            }
        }

        var missing = bundle.RequiredCapabilities
            .Where(capability => !grants.Contains(capability))
            .ToHashSet(StringComparer.Ordinal);
        var effective = bundle.RequiredCapabilities
            .Where(grants.Contains)
            .Concat(bundle.OptionalCapabilities.Where(grants.Contains))
            .ToHashSet(StringComparer.Ordinal);
        var deniedOptional = bundle.OptionalCapabilities
            .Where(capability => !grants.Contains(capability))
            .ToHashSet(StringComparer.Ordinal);

        if (options.DenySystemAdminProcess
            && (bundle.RequiredCapabilities.Contains("system.admin")
                || effective.Contains("system.admin")))
        {
            throw new ExecutorException(
                "system.admin requires a dedicated broker and cannot be granted to an application process.");
        }

        if (context == LaunchContext.Graphical)
        {
            if (!session.Type.Equals("graphical", StringComparison.Ordinal))
            {
                throw new ExecutorException("A graphical APX requires a graphical session.");
            }

            if (!effective.Contains("ui.window"))
            {
                missing.Add("ui.window");
            }
        }

        if (missing.Count != 0)
        {
            throw new ExecutorException(
                $"Required capabilities were denied: {string.Join(", ", missing.OrderBy(value => value, StringComparer.Ordinal))}.");
        }

        return new Authorization(effective, missing, deniedOptional);
    }
}

internal static class TomlText
{
    internal static string Quote(string value)
    {
        var output = new StringBuilder(value.Length + 2);
        output.Append('"');
        foreach (var character in value)
        {
            output.Append(character switch
            {
                '\\' => "\\\\",
                '"' => "\\\"",
                '\n' => "\\n",
                '\r' => "\\r",
                '\t' => "\\t",
                _ when char.IsControl(character) => $"\\u{(int)character:x4}",
                _ => character.ToString(),
            });
        }

        output.Append('"');
        return output.ToString();
    }

    internal static string Array(IEnumerable<string> values)
    {
        return "[" + string.Join(", ", values.Select(Quote)) + "]";
    }
}
