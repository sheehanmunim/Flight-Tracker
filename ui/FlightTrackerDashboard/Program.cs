using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using FlightTracker.Shared;

var repoRoot = RepoPaths.FindRepoRoot();
var dashboardKey = RepoPaths.GetOrCreateDashboardKey(repoRoot);

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRouting();

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
    var mapUrl = $"http://{host}:8080";
    var lanUrl = $"http://{host}:5099/?key={dashboardKey}";

    return Results.Json(new
    {
        hostOs = Environment.OSVersion.ToString(),
        repoRoot,
        mapUrl,
        lanUrl,
        usbNote = "The browser can control the host, but the RTL-SDR still has to be attached to the host OS running the decoder.",
        beastNote = "The local Beast bridge uses synthetic timestamps. Keep MLAT disabled."
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
    var nativeFeederScript = Path.Combine(repoRoot, "scripts", "Manage-NativeFeeder.ps1");
    var result = await ScriptRunner.RunPowerShellScriptAsync(repoRoot, nativeFeederScript, $"-Provider {id} -Action Connect");
    return Results.Json(result);
});

app.MapPost("/api/feeders/{id}/connect", async (string id) =>
{
    var nativeFeederScript = Path.Combine(repoRoot, "scripts", "Manage-NativeFeeder.ps1");
    var result = await ScriptRunner.RunPowerShellScriptAsync(repoRoot, nativeFeederScript, $"-Provider {id} -Action Connect");
    return Results.Json(result);
});

app.MapPost("/api/feeders/{id}/disconnect", async (string id) =>
{
    var nativeFeederScript = Path.Combine(repoRoot, "scripts", "Manage-NativeFeeder.ps1");
    var result = await ScriptRunner.RunPowerShellScriptAsync(repoRoot, nativeFeederScript, $"-Provider {id} -Action Disconnect");
    return Results.Json(result);
});

app.MapGet("/api/status", async () =>
{
    var result = await ScriptRunner.RunPowerShellScriptAsync(repoRoot, Path.Combine(repoRoot, "scripts", "Status-LocalFlightTracker.ps1"));
    return Results.Json(result);
});

app.MapPost("/api/start", async () =>
{
    var result = await ScriptRunner.RunPowerShellScriptAsync(
        repoRoot,
        Path.Combine(repoRoot, "scripts", "Start-LocalFlightTracker.ps1"),
        "-NoBrowser");

    return Results.Json(result);
});

app.MapPost("/api/stop", async () =>
{
    var result = await ScriptRunner.RunPowerShellScriptAsync(repoRoot, Path.Combine(repoRoot, "scripts", "Stop-LocalFlightTracker.ps1"));
    return Results.Json(result);
});

app.MapPost("/api/host-check", async () =>
{
    var result = await ScriptRunner.RunPowerShellScriptAsync(repoRoot, Path.Combine(repoRoot, "scripts", "Test-FlightTrackerHost.ps1"));
    return Results.Json(result);
});

app.MapGet("/api/logs/{name}", async (string name) =>
{
    var allowed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["dump1090"] = Path.Combine(repoRoot, "logs", "dump1090.log"),
        ["beast"] = Path.Combine(repoRoot, "logs", "beast-bridge.log"),
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

var addresses = string.Join(", ", app.Urls.DefaultIfEmpty("http://0.0.0.0:5099"));
Console.WriteLine($"Flight Tracker dashboard ready. Key: {dashboardKey}");
Console.WriteLine($"Open: http://localhost:5099/?key={dashboardKey}");
Console.WriteLine($"Listening on: {addresses}");

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
                if (File.Exists(Path.Combine(current.FullName, "Run-FlightTracker-Browser.cmd"))
                    && File.Exists(Path.Combine(current.FullName, "scripts", "Start-LocalFlightTracker.ps1")))
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
    public static async Task<ScriptResult> RunPowerShellScriptAsync(string repoRoot, string scriptPath, string extraArgs = "")
    {
        if (!OperatingSystem.IsWindows())
        {
            return new ScriptResult(false, "", "Local script execution is only supported on Windows hosts.", -1);
        }

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\" {extraArgs}".Trim(),
            WorkingDirectory = repoRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

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
