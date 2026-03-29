using System.Text.Json;
using System.Text.Json.Serialization;

namespace FlightTracker.Shared;

internal sealed class NativeFeederRuntimeStatus
{
    public required string ProviderId { get; init; }
    public required bool SupportsNativeConnector { get; init; }
    public required bool Enabled { get; init; }
    public required bool Running { get; init; }
    public required string StatusLabel { get; init; }
    public required string Summary { get; init; }
    public required string PrimaryActionLabel { get; init; }
    public required bool CanConnect { get; init; }
    public required bool CanDisconnect { get; init; }
    public string? LogName { get; init; }
    public string? Source { get; init; }
    public string? Target { get; init; }
    public string? LastError { get; init; }
    public string? UpdatedAtUtc { get; init; }
    public string? User { get; init; }
    public string? FeederId { get; init; }
    public int? MessagesUploaded { get; init; }
}

internal static class NativeFeederRuntime
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public static NativeFeederRuntimeStatus Load(string repoRoot, string providerId)
    {
        if (!SupportsNativeConnector(providerId))
        {
            return new NativeFeederRuntimeStatus
            {
                ProviderId = providerId,
                SupportsNativeConnector = false,
                Enabled = false,
                Running = false,
                StatusLabel = "Profile only",
                Summary = "This provider still uses its saved host profile only. A native host connector is not wired into the app yet.",
                PrimaryActionLabel = "Not Yet Native",
                CanConnect = false,
                CanDisconnect = false
            };
        }

        var enabled = File.Exists(GetEnabledMarkerPath(repoRoot, providerId));
        var statusFile = LoadStatusFile(repoRoot, providerId);
        var running = statusFile?.Running == true;
        var state = statusFile?.State?.Trim() ?? string.Empty;

        string statusLabel;
        string summary;

        if (running)
        {
            statusLabel = "Connected on host";
            summary = statusFile?.Summary
                ?? $"Relaying Beast data from {statusFile?.Source ?? "127.0.0.1:30005"} to {statusFile?.Target ?? "the provider"} on this host.";
        }
        else if (enabled)
        {
            statusLabel = "Starting on host";
            summary = statusFile?.LastError
                ?? statusFile?.Summary
                ?? "The host connector is enabled and will keep retrying until the local Beast feed and provider endpoint are both reachable.";
        }
        else if (string.Equals(state, "stopped", StringComparison.OrdinalIgnoreCase))
        {
            statusLabel = "Disconnected";
            summary = statusFile?.Summary ?? "The host connector is currently stopped.";
        }
        else
        {
            statusLabel = "Not connected";
            summary = "Click Connect On Host and this machine will start the feeder runtime itself.";
        }

        return new NativeFeederRuntimeStatus
        {
            ProviderId = providerId,
            SupportsNativeConnector = true,
            Enabled = enabled,
            Running = running,
            StatusLabel = statusLabel,
            Summary = summary,
            PrimaryActionLabel = enabled ? "Disconnect" : "Connect On Host",
            CanConnect = !enabled,
            CanDisconnect = enabled,
            LogName = providerId,
            Source = statusFile?.Source,
            Target = statusFile?.Target,
            LastError = statusFile?.LastError,
            UpdatedAtUtc = statusFile?.UpdatedAtUtc,
            User = statusFile?.User,
            FeederId = statusFile?.FeederId,
            MessagesUploaded = statusFile?.MessagesUploaded
        };
    }

    public static bool SupportsNativeConnector(string providerId)
    {
        return string.Equals(providerId, "airplanes-live", StringComparison.OrdinalIgnoreCase)
            || string.Equals(providerId, "flightaware", StringComparison.OrdinalIgnoreCase);
    }

    private static NativeFeederRuntimeStatusFile? LoadStatusFile(string repoRoot, string providerId)
    {
        var path = GetStatusFilePath(repoRoot, providerId);
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<NativeFeederRuntimeStatusFile>(json, JsonOptions);
        }
        catch
        {
            return null;
        }
    }

    private static string GetEnabledMarkerPath(string repoRoot, string providerId)
    {
        return Path.Combine(repoRoot, "logs", $"{providerId}.enabled");
    }

    private static string GetStatusFilePath(string repoRoot, string providerId)
    {
        return Path.Combine(repoRoot, "logs", $"{providerId}.status.json");
    }
}

internal sealed class NativeFeederRuntimeStatusFile
{
    [JsonPropertyName("providerId")]
    public string? ProviderId { get; set; }

    [JsonPropertyName("running")]
    public bool Running { get; set; }

    [JsonPropertyName("state")]
    public string? State { get; set; }

    [JsonPropertyName("summary")]
    public string? Summary { get; set; }

    [JsonPropertyName("source")]
    public string? Source { get; set; }

    [JsonPropertyName("target")]
    public string? Target { get; set; }

    [JsonPropertyName("lastError")]
    public string? LastError { get; set; }

    [JsonPropertyName("updatedAtUtc")]
    public string? UpdatedAtUtc { get; set; }

    [JsonPropertyName("user")]
    public string? User { get; set; }

    [JsonPropertyName("feederId")]
    public string? FeederId { get; set; }

    [JsonPropertyName("messagesUploaded")]
    public int? MessagesUploaded { get; set; }
}
