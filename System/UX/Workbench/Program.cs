using Avalonia;

namespace Mixtar.UX.Workbench;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args) =>
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);

    public static AppBuilder BuildAvaloniaApp()
    {
        var builder = AppBuilder.Configure<App>();
        if (string.Equals(
                Environment.GetEnvironmentVariable("MIXTAR_GRAPHICS_MODE"),
                "software",
                StringComparison.OrdinalIgnoreCase))
        {
            builder = builder.With(new Avalonia.WaylandPlatformOptions
            {
                GlProfiles = []
            });
        }

        return builder
            .UseWayland()
            .UseSkia()
            .UseHarfBuzz()
            .LogToTrace();
    }
}