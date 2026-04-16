using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using FlightTracker.Shared;

var repoRoot = RepoPaths.FindRepoRoot();
var dashboardKey = RepoPaths.GetOrCreateDashboardKey(repoRoot);
var hostOptions = DashboardHostOptions.Parse(args);

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRouting();
builder.WebHost.UseUrls(hostOptions.ListenUrl);

var app = builder.Build();

app.UseStaticFiles();

app.Use(async (context, next) =>
{
    if (!context.Request.Path.StartsWithSegments("/api"))
    {
        await next();
        return;
    }

    var requestKey = context.Request.Headers["X-FlightTracker-Key"].FirstOrDefault()
        ?? context.Request.Query["key"].FirstOrDefault();

    if (!string.Equals(requestKey, dashboardKey, StringComparison.Ordinal))
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsync("""{"error":"Dashboard key required."}""");
        return;
    }

    await next();
});

app.MapGet("/api/meta", (HttpRequest request) =>
{
    var host = request.Host.Host;
    var baseUrl = $"{request.Scheme}://{request.Host}";
    var mapUrl = HostPlatform.GetMapUrl(request, dashboardKey);
    var lanUrl = $"{baseUrl}/?key={dashboardKey}";

    return Results.Json(new
    {
        hostKind = HostPlatform.Kind,
        hostOs = Environment.OSVersion.ToString(),
        repoRoot,
        mapUrl,
        lanUrl,
        chromeDirectUrl = HostPlatform.GetChromeDirectUrl(request, dashboardKey),
        usbNote = HostPlatform.GetUsbNote(),
        beastNote = HostPlatform.GetBeastNote()
    });
});

app.MapGet("/api/feeders", (HttpRequest request) =>
{
    return Results.Json(FeederApi.BuildResponse(repoRoot, request.Host.Host));
});

app.MapPost("/api/feeders/{id}", (string id, HttpRequest request) =>
{
    FeederProfiles.AddSelection(repoRoot, id);
    return Results.Json(FeederApi.BuildResponse(repoRoot, request.Host.Host));
});

app.MapDelete("/api/feeders/{id}", (string id, HttpRequest request) =>
{
    FeederProfiles.RemoveSelection(repoRoot, id);
    return Results.Json(FeederApi.BuildResponse(repoRoot, request.Host.Host));
});

app.MapPost("/api/feeders/{id}/install", async (string id) =>
{
    var result = await ScriptRunner.RunLocalScriptAsync(repoRoot, "Install-Feeder", $"-Provider {id}");
    return Results.Json(result);
});

app.MapPost("/api/feeders/{id}/connect", async (string id) =>
{
    var result = await ScriptRunner.RunLocalScriptAsync(repoRoot, "Manage-NativeFeeder", $"-Provider {id} -Action Connect");
    return Results.Json(result);
});

app.MapPost("/api/feeders/{id}/disconnect", async (string id) =>
{
    var result = await ScriptRunner.RunLocalScriptAsync(repoRoot, "Manage-NativeFeeder", $"-Provider {id} -Action Disconnect");
    return Results.Json(result);
});

app.MapGet("/api/status", async () =>
{
    var result = await ScriptRunner.RunLocalScriptAsync(repoRoot, "Status-LocalFlightTracker");
    return Results.Json(result);
});

app.MapPost("/api/start", async () =>
{
    var result = await ScriptRunner.RunLocalScriptAsync(
        repoRoot,
        "Start-LocalFlightTracker",
        "-NoBrowser");

    return Results.Json(result);
});

app.MapPost("/api/stop", async () =>
{
    var result = await ScriptRunner.RunLocalScriptAsync(repoRoot, "Stop-LocalFlightTracker");
    return Results.Json(result);
});

app.MapPost("/api/host-check", async () =>
{
    var result = await ScriptRunner.RunLocalScriptAsync(repoRoot, "Test-FlightTrackerHost");
    return Results.Json(result);
});

app.MapGet("/api/receiver/aircraft", async () =>
{
    var json = await ReceiverDataApi.LoadAircraftJsonAsync(repoRoot);
    return Results.Text(json, "application/json", Encoding.UTF8);
});

app.MapGet("/api/logs/{name}", async (string name) =>
{
    var allowed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["dump1090"] = Path.Combine(repoRoot, "logs", "dump1090.log"),
        ["readsb"] = Path.Combine(repoRoot, "logs", "readsb.log"),
        ["beast"] = Path.Combine(repoRoot, "logs", "beast-bridge.log"),
        ["flightaware"] = Path.Combine(repoRoot, "logs", "flightaware.log"),
        ["airplanes-live"] = Path.Combine(repoRoot, "logs", "airplanes-live.log")
    };

    if (!allowed.TryGetValue(name, out var path))
    {
        return Results.NotFound(new { error = "Unknown log name." });
    }

    if (!File.Exists(path))
    {
        return Results.Json(new { ok = true, output = "", error = "", exitCode = 0 });
    }

    var lines = await File.ReadAllLinesAsync(path);
    var tail = string.Join(Environment.NewLine, lines.TakeLast(60));
    return Results.Json(new { ok = true, output = tail, error = "", exitCode = 0 });
});

app.MapFallbackToFile("index.html");

app.Lifetime.ApplicationStarted.Register(() =>
{
    HostStartupTasks.OnStarted(repoRoot, dashboardKey, hostOptions);
});

await app.RunAsync();

static class RepoPaths
{
    public static string FindRepoRoot()
    {
        var candidates = new[]
        {
            new DirectoryInfo(AppContext.BaseDirectory),
            new DirectoryInfo(Directory.GetCurrentDirectory())
        };

        foreach (var start in candidates)
        {
            var current = start;
            while (current is not null)
            {
                var hasRootMarker = File.Exists(Path.Combine(current.FullName, "flight-tracker-root.marker"));
                var hasScripts =
                    File.Exists(Path.Combine(current.FullName, "scripts", "Start-LocalFlightTracker.ps1"))
                    || File.Exists(Path.Combine(current.FullName, "scripts", "Start-LocalFlightTracker.sh"));

                if (hasScripts && hasRootMarker)
                {
                    return current.FullName;
                }

                current = current.Parent;
            }
        }

        throw new DirectoryNotFoundException("Could not find the Flight Tracker repo root.");
    }

    public static string GetOrCreateDashboardKey(string repoRoot)
    {
        var keyFromEnv = Environment.GetEnvironmentVariable("FLIGHT_TRACKER_DASHBOARD_KEY");
        if (!string.IsNullOrWhiteSpace(keyFromEnv))
        {
            return keyFromEnv.Trim();
        }

        var logDir = Path.Combine(repoRoot, "logs");
        Directory.CreateDirectory(logDir);

        var keyFile = Path.Combine(logDir, "dashboard.key");
        if (File.Exists(keyFile))
        {
            var existing = File.ReadAllText(keyFile).Trim();
            if (!string.IsNullOrWhiteSpace(existing))
            {
                return existing;
            }
        }

        var keyBytes = RandomNumberGenerator.GetBytes(24);
        var key = Convert.ToBase64String(keyBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        File.WriteAllText(keyFile, key);
        return key;
    }
}

internal static class ScriptRunner
{
    public static async Task<ScriptResult> RunLocalScriptAsync(string repoRoot, string scriptBaseName, string extraArgs = "")
    {
        var scriptPath = HostPlatform.ResolveScriptPath(repoRoot, scriptBaseName);
        if (scriptPath is null)
        {
            return new ScriptResult(false, "", "Local host scripts are not available for this platform yet.", -1);
        }

        ProcessStartInfo psi;

        if (OperatingSystem.IsWindows())
        {
            psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\" {extraArgs}".Trim(),
                WorkingDirectory = repoRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
        }
        else if (OperatingSystem.IsMacOS())
        {
            psi = new ProcessStartInfo
            {
                FileName = "/bin/bash",
                Arguments = $"\"{scriptPath}\" {extraArgs}".Trim(),
                WorkingDirectory = repoRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
        }
        else
        {
            return new ScriptResult(false, "", "Local script execution is not supported on this platform.", -1);
        }

        using var process = new Process { StartInfo = psi };
        process.Start();

        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        return new ScriptResult(
            process.ExitCode == 0,
            stdout.Trim(),
            stderr.Trim(),
            process.ExitCode);
    }
}

internal sealed record ScriptResult(bool Ok, string Output, string Error, int ExitCode);

internal static class HostPlatform
{
    public static string Kind =>
        OperatingSystem.IsWindows() ? "windows"
        : OperatingSystem.IsMacOS() ? "macos"
        : "unsupported";

    public static string? ResolveScriptPath(string repoRoot, string scriptBaseName)
    {
        var extension =
            OperatingSystem.IsWindows() ? ".ps1"
            : OperatingSystem.IsMacOS() ? ".sh"
            : string.Empty;

        if (string.IsNullOrEmpty(extension))
        {
            return null;
        }

        var path = Path.Combine(repoRoot, "scripts", scriptBaseName + extension);
        return File.Exists(path) ? path : null;
    }

    public static string GetMapUrl(HttpRequest request, string dashboardKey)
    {
        var baseUrl = $"{request.Scheme}://{request.Host}";
        if (OperatingSystem.IsWindows())
        {
            return $"http://{request.Host.Host}:8080";
        }

        return $"{baseUrl}/receiver-map.html?key={Uri.EscapeDataString(dashboardKey)}";
    }

    public static string GetChromeDirectUrl(HttpRequest request, string dashboardKey)
    {
        var baseUrl = $"{request.Scheme}://{request.Host}";
        return $"{baseUrl}/chrome-direct.html?key={Uri.EscapeDataString(dashboardKey)}";
    }

    public static string GetUsbNote()
    {
        if (OperatingSystem.IsMacOS())
        {
            return "The RTL-SDR can stay attached to this Mac host. Install a local decoder such as readsb on the Mac when you want the browser dashboard to control it directly.";
        }

        if (OperatingSystem.IsWindows())
        {
            return "The browser dashboard can control the local host directly. Keep the RTL-SDR attached to the same machine that is running the decoder.";
        }

        return "Host-specific USB control is not available on this platform yet.";
    }

    public static string GetBeastNote()
    {
        if (OperatingSystem.IsMacOS())
        {
            return "Mac host mode exposes the local receiver feed on the standard ports when a compatible decoder is installed. The Chrome Direct page is still experimental.";
        }

        return "Port 30005 carries real decoder timestamps. Use Install Official Feeder for the full MLAT path when it is available on this host.";
    }
}

internal sealed record DashboardHostOptions(string ListenUrl, bool OpenBrowser)
{
    public int Port => new Uri(ListenUrl).Port;

    public static DashboardHostOptions Parse(string[] args)
    {
        const string defaultUrl = "http://0.0.0.0:5099";

        var listenUrl = defaultUrl;
        var openBrowser = true;

        for (var index = 0; index < args.Length; index++)
        {
            var arg = args[index];

            if (string.Equals(arg, "--no-browser", StringComparison.OrdinalIgnoreCase))
            {
                openBrowser = false;
                continue;
            }

            if (string.Equals(arg, "--urls", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
            {
                listenUrl = args[index + 1];
                index++;
                continue;
            }

            if (arg.StartsWith("--urls=", StringComparison.OrdinalIgnoreCase))
            {
                listenUrl = arg["--urls=".Length..];
            }
        }

        return new DashboardHostOptions(listenUrl, openBrowser);
    }
}

internal static class HostStartupTasks
{
    public static void OnStarted(string repoRoot, string dashboardKey, DashboardHostOptions options)
    {
        var lanHost = FeederProfiles.GetLanHost();
        var localUrl = $"http://localhost:{options.Port}/?key={dashboardKey}";
        var lanUrl = $"http://{lanHost}:{options.Port}/?key={dashboardKey}";

        Console.WriteLine($"Flight Tracker dashboard ready. Key: {dashboardKey}");
        Console.WriteLine($"Open locally: {localUrl}");
        Console.WriteLine($"Share on your LAN: {lanUrl}");

        try
        {
            var macDir = Path.Combine(repoRoot, "macOS");
            Directory.CreateDirectory(macDir);
            File.WriteAllText(Path.Combine(macDir, "flight-tracker-url.txt"), $"{lanUrl}{Environment.NewLine}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Could not update the Mac launcher URL file: {ex.Message}");
        }

        if (!options.OpenBrowser)
        {
            return;
        }

        BrowserLauncher.TryOpen(localUrl);
    }
}

internal static class BrowserLauncher
{
    public static void TryOpen(string url)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = url,
                    UseShellExecute = true
                });
                return;
            }

            if (OperatingSystem.IsMacOS())
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "open",
                    Arguments = $"\"{url}\"",
                    UseShellExecute = false
                });
                return;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Could not open the dashboard automatically: {ex.Message}");
        }
    }
}

internal static class FeederApi
{
    public static object BuildResponse(string repoRoot, string requestHost)
    {
        var lanHost = ResolveLanHost(requestHost);
        var catalog = FeederProfiles.GetCatalog(lanHost);
        var selections = FeederProfiles.LoadSelections(repoRoot);
        var selectedIds = selections.SelectedIds
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        return new
        {
            lanHost,
            providers = catalog.Select(provider => new
            {
                provider.Id,
                provider.Name,
                provider.Badge,
                provider.Summary,
                provider.InstallHint,
                provider.SourceLabel,
                localSettings = provider.LocalSettings,
                lanSettings = provider.LanSettings,
                provider.Notes,
                nativeConnector = NativeFeederRuntime.Load(repoRoot, provider.Id),
                selected = selectedIds.Contains(provider.Id)
            }),
            selectedIds = selectedIds.OrderBy(id => id, StringComparer.OrdinalIgnoreCase).ToArray()
        };
    }

    private static string ResolveLanHost(string requestHost)
    {
        if (!string.IsNullOrWhiteSpace(requestHost)
            && !string.Equals(requestHost, "localhost", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(requestHost, "127.0.0.1", StringComparison.OrdinalIgnoreCase))
        {
            return requestHost;
        }

        return FeederProfiles.GetLanHost();
    }
}

internal static class ReceiverDataApi
{
    private static readonly HttpClient HttpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(3)
    };

    private const string EmptyAircraftPayload = """{"now":0,"messages":0,"aircraft":[]}""";

    public static async Task<string> LoadAircraftJsonAsync(string repoRoot)
    {
        var readsbPath = Path.Combine(repoRoot, "logs", "readsb-data", "aircraft.json");
        if (File.Exists(readsbPath))
        {
            return await File.ReadAllTextAsync(readsbPath);
        }

        try
        {
            var response = await HttpClient.GetAsync("http://127.0.0.1:8080/data/aircraft.json");
            if (response.IsSuccessStatusCode)
            {
                return await response.Content.ReadAsStringAsync();
            }
        }
        catch
        {
        }

        return EmptyAircraftPayload;
    }
}
