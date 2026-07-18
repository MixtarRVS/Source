using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace Mixtar.Product.Executor;

internal sealed record LaunchResult(string Id, int? ProcessId, int? ExitCode, bool Waiting);

internal sealed class ExecutorRuntime
{
    private readonly ExecutorEnvironment environment;
    private readonly ExecutorOptions options;

    internal ExecutorRuntime()
    {
        environment = new ExecutorEnvironment();
        options = ExecutorOptions.Load(environment);
    }

    internal ApxBundle Validate(string bundle)
    {
        return ApxBundleLoader.Load(environment.ResolveInput(bundle));
    }

    internal LaunchPlan Plan(LaunchRequest request)
    {
        var bundle = Validate(request.Bundle);
        var session = SessionStore.Load(environment, options, request.Session, request.User);
        var authorization = CapabilityPolicy.Authorize(
            environment,
            options,
            bundle,
            request.Context,
            session);
        var fallback = !bundle.Entries.TryGetValue(request.Context, out var entry);
        entry ??= bundle.Entries.Values.Single();
        if (fallback && bundle.Entries.Count != 1)
        {
            throw new ExecutorException("The requested APX entry context is not available.");
        }

        var id = "launch-" + CreateNonce();
        var logicalDescriptor = session.LogicalDirectory.TrimEnd('/') + "/Launch/" + id + ".config";
        var physicalDescriptor = environment.MapLogical(logicalDescriptor);
        var logicalAppData = options.Users.TrimEnd('/') + "/" + request.User
            + "/Applications/" + bundle.Application.Id;
        var physicalAppData = environment.MapLogical(logicalAppData);
        return new LaunchPlan(
            id,
            bundle,
            entry,
            request,
            session,
            authorization,
            logicalDescriptor,
            physicalDescriptor,
            logicalAppData,
            physicalAppData);
    }

    internal string Describe(LaunchPlan plan, string state, int? processId = null, int? exitCode = null)
    {
        var output = new StringBuilder(2048);
        output.AppendLine("schema = 1");
        output.AppendLine();
        output.AppendLine("[launch]");
        output.Append("id = ").AppendLine(TomlText.Quote(plan.Id));
        output.Append("context = ").AppendLine(TomlText.Quote(ContextName(plan.Request.Context)));
        output.Append("entry_context = ").AppendLine(TomlText.Quote(ContextName(plan.Entry.Context)));
        output.Append("state = ").AppendLine(TomlText.Quote(state));
        output.Append("diagnostics = ").AppendLine(plan.Request.Diagnostics ? "true" : "false");
        output.Append("wait = ").AppendLine(plan.Request.Wait || plan.Request.Context == LaunchContext.Terminal ? "true" : "false");
        output.Append("updated_at = ").AppendLine(TomlText.Quote(DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture)));
        output.AppendLine();
        output.AppendLine("[application]");
        output.Append("id = ").AppendLine(TomlText.Quote(plan.Bundle.Application.Id));
        output.Append("name = ").AppendLine(TomlText.Quote(plan.Bundle.Application.Name));
        output.Append("version = ").AppendLine(TomlText.Quote(plan.Bundle.Application.Version));
        output.Append("publisher = ").AppendLine(TomlText.Quote(plan.Bundle.Application.Publisher));
        output.AppendLine();
        output.AppendLine("[session]");
        output.Append("id = ").AppendLine(TomlText.Quote(plan.Session.Id));
        output.Append("user = ").AppendLine(TomlText.Quote(plan.Session.User));
        output.Append("type = ").AppendLine(TomlText.Quote(plan.Session.Type));
        output.AppendLine();
        output.AppendLine("[paths]");
        output.Append("bundle = ").AppendLine(TomlText.Quote(environment.ToLogical(plan.Bundle.Root)));
        output.Append("entry = ").AppendLine(TomlText.Quote(plan.Entry.RelativePath));
        output.Append("app_data = ").AppendLine(TomlText.Quote(plan.LogicalAppData));
        output.Append("descriptor = ").AppendLine(TomlText.Quote(plan.LogicalDescriptor));
        output.AppendLine();
        output.AppendLine("[process]");
        output.Append("shell = false").AppendLine();
        output.Append("arguments = ").AppendLine(TomlText.Array(plan.Request.Arguments));
        if (processId.HasValue)
        {
            output.Append("pid = ").AppendLine(processId.Value.ToString(CultureInfo.InvariantCulture));
        }

        if (exitCode.HasValue)
        {
            output.Append("exit_code = ").AppendLine(exitCode.Value.ToString(CultureInfo.InvariantCulture));
        }

        output.AppendLine();
        output.AppendLine("[permissions]");
        output.Append("effective = ").AppendLine(TomlText.Array(
            plan.Authorization.Effective.OrderBy(value => value, StringComparer.Ordinal)));
        output.Append("denied_optional = ").AppendLine(TomlText.Array(
            plan.Authorization.DeniedOptional.OrderBy(value => value, StringComparer.Ordinal)));
        output.Append("enforcement = ").AppendLine(TomlText.Quote("declaration-and-session-gate-v1"));
        return output.ToString();
    }

    internal async Task<LaunchResult> LaunchAsync(LaunchPlan plan)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(plan.PhysicalDescriptor)!);
        Directory.CreateDirectory(plan.PhysicalAppData);
        SetPrivateDirectory(Path.GetDirectoryName(plan.PhysicalDescriptor)!);
        SetPrivateDirectory(plan.PhysicalAppData);
        AtomicWrite(plan.PhysicalDescriptor, Describe(plan, "starting"));
        AppendAudit(plan, "starting", null, null);

        var start = new ProcessStartInfo
        {
            FileName = plan.Entry.Executable,
            WorkingDirectory = plan.Bundle.Root,
            UseShellExecute = false,
            CreateNoWindow = plan.Request.Context == LaunchContext.Graphical,
            RedirectStandardInput = false,
            RedirectStandardOutput = false,
            RedirectStandardError = false,
        };
        foreach (var argument in plan.Request.Arguments)
        {
            if (argument.IndexOf('\0') >= 0)
            {
                throw new ExecutorException("Application arguments may not contain NUL.");
            }

            start.ArgumentList.Add(argument);
        }

        BuildEnvironment(start, plan);
        Process? process = null;
        try
        {
            process = Process.Start(start)
                ?? throw new ExecutorException("The operating system did not create the application process.");
            AtomicWrite(plan.PhysicalDescriptor, Describe(plan, "running", process.Id));
            AppendAudit(plan, "running", process.Id, null);
            var wait = plan.Request.Wait || plan.Request.Context == LaunchContext.Terminal;
            if (!wait)
            {
                return new LaunchResult(plan.Id, process.Id, null, false);
            }

            await process.WaitForExitAsync().ConfigureAwait(false);
            var exitCode = process.ExitCode;
            AtomicWrite(plan.PhysicalDescriptor, Describe(plan, "stopped", process.Id, exitCode));
            AppendAudit(plan, "stopped", process.Id, exitCode);
            return new LaunchResult(plan.Id, process.Id, exitCode, true);
        }
        catch (ExecutorException)
        {
            AtomicWrite(plan.PhysicalDescriptor, Describe(plan, "failed", process?.Id));
            AppendAudit(plan, "failed", process?.Id, null);
            throw;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            AtomicWrite(plan.PhysicalDescriptor, Describe(plan, "failed", process?.Id));
            AppendAudit(plan, "failed", process?.Id, null);
            throw new ExecutorException($"Could not launch APX: {error.Message}", error);
        }
        finally
        {
            process?.Dispose();
        }
    }

    private void BuildEnvironment(ProcessStartInfo start, LaunchPlan plan)
    {
        start.Environment.Clear();
        start.Environment["LANG"] = "C.UTF-8";
        start.Environment["HOME"] = options.Users.TrimEnd('/') + "/" + plan.Request.User;
        start.Environment["MIXTAR_APP_DATA"] = plan.LogicalAppData;
        start.Environment["MIXTAR_APP_ID"] = plan.Bundle.Application.Id;
        start.Environment["MIXTAR_BUNDLE"] = environment.ToLogical(plan.Bundle.Root);
        start.Environment["MIXTAR_CAPABILITIES"] = string.Join(',',
            plan.Authorization.Effective.OrderBy(value => value, StringComparer.Ordinal));
        start.Environment["MIXTAR_LAUNCH_CONTEXT"] = ContextName(plan.Request.Context);
        start.Environment["MIXTAR_LAUNCH_DESCRIPTOR"] = plan.LogicalDescriptor;
        start.Environment["MIXTAR_SESSION_ID"] = plan.Session.Id;
        start.Environment["MIXTAR_USER"] = plan.Request.User;
        start.Environment["MIXTAR_DIAGNOSTICS"] = plan.Request.Diagnostics ? "1" : "0";
        if (environment.Root != "/")
        {
            start.Environment["MIXTAR_ROOT"] = environment.Root;
        }

        if (plan.Request.Context == LaunchContext.Graphical)
        {
            start.Environment["WAYLAND_DISPLAY"] = plan.Session.WaylandDisplay
                ?? throw new ExecutorException("The graphical session has no Wayland display.");
            start.Environment["XDG_RUNTIME_DIR"] = plan.Session.LogicalDirectory + "/Wayland";
        }
    }

    private string CreateNonce()
    {
        Span<byte> entropy = stackalloc byte[16];
        var sourcePath = environment.MapLogical("/System/Devices/urandom");
        try
        {
            using var source = new FileStream(
                sourcePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read);
            source.ReadExactly(entropy);
        }
        catch (Exception error) when (
            error is IOException
            or UnauthorizedAccessException
            or NotSupportedException)
        {
            throw new ExecutorException(
                $"Mixtar entropy source is unavailable: /System/Devices/urandom ({error.Message}).");
        }

        return Convert.ToHexString(entropy).ToLowerInvariant();
    }

    private void AtomicWrite(string path, string text)
    {
        var directory = Path.GetDirectoryName(path)
            ?? throw new ExecutorException($"Invalid state path: {path}.");
        Directory.CreateDirectory(directory);
        var temporary = path + ".new-" + CreateNonce();
        try
        {
            File.WriteAllText(temporary, text, new UTF8Encoding(false));
            if (OperatingSystem.IsLinux())
            {
                File.SetUnixFileMode(temporary, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            }

            File.Move(temporary, path, true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }

    private void AppendAudit(LaunchPlan plan, string state, int? processId, int? exitCode)
    {
        var path = environment.MapLogical(options.Logs);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var fields = new[]
        {
            DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture),
            plan.Id,
            state,
            plan.Bundle.Application.Id,
            plan.Bundle.Application.Publisher,
            plan.Request.User,
            processId?.ToString(CultureInfo.InvariantCulture) ?? "-",
            exitCode?.ToString(CultureInfo.InvariantCulture) ?? "-",
        };
        File.AppendAllText(path, string.Join('\t', fields) + "\n", new UTF8Encoding(false));
    }

    private static void SetPrivateDirectory(string path)
    {
        if (OperatingSystem.IsLinux())
        {
            File.SetUnixFileMode(
                path,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
    }

    internal static string ContextName(LaunchContext context)
    {
        return context == LaunchContext.Graphical ? "graphical" : "terminal";
    }
}
