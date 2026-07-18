namespace Mixtar.Product.Executor;

internal sealed record ParsedCommand(
    string Name,
    string? Bundle,
    LaunchContext Context,
    string User,
    string Session,
    IReadOnlyList<string> ApplicationArguments,
    bool Diagnostics,
    bool Wait,
    bool Help);

internal static class CommandLine
{
    internal static ParsedCommand Parse(string[] arguments)
    {
        if (arguments.Length == 0 || IsHelp(arguments[0]))
        {
            return HelpCommand();
        }

        var name = arguments[0].ToLowerInvariant();
        if (name == "version")
        {
            return new ParsedCommand(name, null, LaunchContext.Terminal, "Administrator", "console", [], false, false, false);
        }

        if (name is not ("validate" or "plan" or "launch"))
        {
            throw new ExecutorException($"Unknown command: {arguments[0]}.");
        }

        string? bundle = null;
        var context = LaunchContext.Terminal;
        var user = Environment.GetEnvironmentVariable("MIXTAR_USER") ?? "Administrator";
        var session = Environment.GetEnvironmentVariable("MIXTAR_SESSION_ID") ?? "console";
        var diagnostics = false;
        var wait = false;
        var appArguments = new List<string>();
        for (var index = 1; index < arguments.Length; index++)
        {
            var value = arguments[index];
            if (IsHelp(value))
            {
                return HelpCommand();
            }

            if (value == "--")
            {
                appArguments.AddRange(arguments[(index + 1)..]);
                break;
            }

            switch (value)
            {
                case "--context":
                    var contextValue = Next(arguments, ref index, "--context");
                    context = contextValue switch
                    {
                        "graphical" => LaunchContext.Graphical,
                        "terminal" => LaunchContext.Terminal,
                        _ => throw new ExecutorException("--context must be 'graphical' or 'terminal'."),
                    };
                    break;
                case "--user":
                    user = Next(arguments, ref index, "--user");
                    break;
                case "--session":
                    session = Next(arguments, ref index, "--session");
                    break;
                case "--diagnostics":
                    diagnostics = true;
                    break;
                case "--wait":
                    wait = true;
                    break;
                default:
                    if (value.StartsWith('-'))
                    {
                        throw new ExecutorException($"Unknown Executor option: {value}.");
                    }

                    if (bundle is not null)
                    {
                        throw new ExecutorException("Application arguments must follow '--'.");
                    }

                    bundle = value;
                    break;
            }
        }

        if (bundle is null)
        {
            throw new ExecutorException($"The {name} command requires an APX bundle path.");
        }

        if (name == "validate"
            && (context != LaunchContext.Terminal
                || diagnostics
                || wait
                || appArguments.Count != 0
                || user != (Environment.GetEnvironmentVariable("MIXTAR_USER") ?? "Administrator")
                || session != (Environment.GetEnvironmentVariable("MIXTAR_SESSION_ID") ?? "console")))
        {
            throw new ExecutorException("validate accepts only an APX bundle path.");
        }

        SessionStore.ValidateToken(user, "user name");
        SessionStore.ValidateToken(session, "session id");
        return new ParsedCommand(
            name,
            bundle,
            context,
            user,
            session,
            appArguments,
            diagnostics,
            wait,
            false);
    }

    private static ParsedCommand HelpCommand()
    {
        return new ParsedCommand("help", null, LaunchContext.Terminal, "Administrator", "console", [], false, false, true);
    }

    private static bool IsHelp(string value)
    {
        return value is "--help" or "-h" or "/?";
    }

    private static string Next(string[] arguments, ref int index, string option)
    {
        index++;
        if (index >= arguments.Length || string.IsNullOrWhiteSpace(arguments[index]))
        {
            throw new ExecutorException($"{option} requires a value.");
        }

        return arguments[index];
    }
}

internal static class Program
{
    private const int UsageError = 64;
    private const int ContractError = 65;
    private const int LaunchError = 70;

    private static async Task<int> Main(string[] arguments)
    {
        try
        {
            var command = CommandLine.Parse(arguments);
            if (command.Help)
            {
                PrintHelp();
                return 0;
            }

            if (command.Name == "version")
            {
                Console.WriteLine("Mixtar Executor contract 1 / .NET 10 Native AOT");
                return 0;
            }

            var runtime = new ExecutorRuntime();
            if (command.Name == "validate")
            {
                var bundle = runtime.Validate(command.Bundle!);
                Console.WriteLine($"APX valid: {bundle.Application.Id}");
                Console.WriteLine($"Publisher: {bundle.Application.Publisher}");
                Console.WriteLine($"Entries: {string.Join(", ", bundle.Entries.Keys.Select(ExecutorRuntime.ContextName))}");
                return 0;
            }

            var request = new LaunchRequest(
                command.Bundle!,
                command.Context,
                command.User,
                command.Session,
                command.ApplicationArguments,
                command.Diagnostics,
                command.Wait);
            var plan = runtime.Plan(request);
            if (command.Diagnostics && plan.Authorization.DeniedOptional.Count != 0)
            {
                Console.Error.WriteLine(
                    "Optional capabilities denied: "
                    + string.Join(", ", plan.Authorization.DeniedOptional.OrderBy(value => value, StringComparer.Ordinal)));
            }

            if (command.Name == "plan")
            {
                Console.Write(runtime.Describe(plan, "planned"));
                return 0;
            }

            var result = await runtime.LaunchAsync(plan).ConfigureAwait(false);
            if (command.Diagnostics || !result.Waiting)
            {
                Console.Error.WriteLine($"Launch id: {result.Id}");
                if (result.ProcessId.HasValue)
                {
                    Console.Error.WriteLine($"Process id: {result.ProcessId.Value}");
                }
            }

            return result.ExitCode ?? 0;
        }
        catch (ExecutorException error)
        {
            Console.Error.WriteLine($"Executor: {error.Message}");
            return error.Message.Contains("launch", StringComparison.OrdinalIgnoreCase)
                ? LaunchError
                : ContractError;
        }
        catch (ArgumentException error)
        {
            Console.Error.WriteLine($"Executor: {error.Message}");
            return UsageError;
        }
    }

    private static void PrintHelp()
    {
        Console.WriteLine("MixtarRVS APX Executor");
        Console.WriteLine();
        Console.WriteLine("Usage:");
        Console.WriteLine("  Executor validate <Application.apx>");
        Console.WriteLine("  Executor plan [options] <Application.apx> [-- arguments]");
        Console.WriteLine("  Executor launch [options] <Application.apx> [-- arguments]");
        Console.WriteLine("  Executor version");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --context graphical|terminal");
        Console.WriteLine("  --user <name>");
        Console.WriteLine("  --session <id>");
        Console.WriteLine("  --diagnostics");
        Console.WriteLine("  --wait");
        Console.WriteLine("  --help, /?");
        Console.WriteLine();
        Console.WriteLine("The Executor never invokes a command shell. Application arguments must follow '--'.");
    }
}
