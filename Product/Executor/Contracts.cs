namespace Mixtar.Product.Executor;

internal static class ExecutorContract
{
    internal const long ApxSchema = 1;
    internal const long ConfigurationSchema = 1;
    internal const long SessionSchema = 1;
    internal const long PolicySchema = 1;
    internal const string RuntimeConfig = "/System/Configuration/Product/Executor.config";

    internal static readonly HashSet<string> KnownCapabilities = new(StringComparer.Ordinal)
    {
        "ui.window",
        "ui.notifications",
        "network.client",
        "network.listen",
        "storage.user",
        "storage.volumes.read",
        "storage.volumes.write",
        "devices.input",
        "devices.graphics",
        "process.inspect",
        "system.status",
        "system.admin",
    };
}

internal sealed class ExecutorException : Exception
{
    internal ExecutorException(string message) : base(message)
    {
    }

    internal ExecutorException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

internal enum LaunchContext
{
    Graphical,
    Terminal,
}

internal sealed record ApxApplication(
    string Id,
    string Name,
    string Version,
    string Publisher);

internal sealed record ApxEntry(
    LaunchContext Context,
    string RelativePath,
    string Executable);

internal sealed record ApxBundle(
    string Root,
    string Config,
    ApxApplication Application,
    IReadOnlyDictionary<LaunchContext, ApxEntry> Entries,
    IReadOnlySet<string> RequiredCapabilities,
    IReadOnlySet<string> OptionalCapabilities);

internal sealed record SessionRecord(
    string Id,
    string User,
    string Type,
    string State,
    string? WaylandDisplay,
    string LogicalDirectory,
    string PhysicalDirectory);

internal sealed record Authorization(
    IReadOnlySet<string> Effective,
    IReadOnlySet<string> MissingRequired,
    IReadOnlySet<string> DeniedOptional);

internal sealed record LaunchRequest(
    string Bundle,
    LaunchContext Context,
    string User,
    string Session,
    IReadOnlyList<string> Arguments,
    bool Diagnostics,
    bool Wait);

internal sealed record LaunchPlan(
    string Id,
    ApxBundle Bundle,
    ApxEntry Entry,
    LaunchRequest Request,
    SessionRecord Session,
    Authorization Authorization,
    string LogicalDescriptor,
    string PhysicalDescriptor,
    string LogicalAppData,
    string PhysicalAppData);
