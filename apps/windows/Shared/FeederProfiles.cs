using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace FlightTracker.Shared;

internal sealed record FeederSetting(string Label, string Value);

internal sealed class FeederProfile
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Badge { get; init; }
    public required string Summary { get; init; }
    public required string InstallHint { get; init; }
    public required string SourceLabel { get; init; }
    public required IReadOnlyList<FeederSetting> LocalSettings { get; init; }
    public required IReadOnlyList<FeederSetting> LanSettings { get; init; }
    public required IReadOnlyList<string> Notes { get; init; }
}

internal sealed class FeederSelectionState
{
    [JsonPropertyName("selectedIds")]
    public List<string> SelectedIds { get; set; } = [];
}

internal static class FeederProfiles
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    private static readonly IReadOnlyList<FeederProfile> Catalog =
    [
        new FeederProfile
        {
            Id = "flightradar24",
            Name = "Flightradar24",
            Badge = "Ready now",
            Summary = "Uses the live Windows tracker directly. This is the easiest network to add right away.",
            InstallHint = "Point FR24 at the host feed and it can start consuming data immediately.",
            SourceLabel = "Primary source: AVR/raw on 30002. Alternate source: Beast on 30005.",
            LocalSettings =
            [
                new("Receiver", "avr-tcp"),
                new("Host", "127.0.0.1"),
                new("Port", "30002"),
                new("Alternate", "beast-tcp on 127.0.0.1:30005")
            ],
            LanSettings =
            [
                new("Receiver", "avr-tcp"),
                new("Host", "{lanHost}"),
                new("Port", "30002"),
                new("Alternate", "beast-tcp on {lanHost}:30005")
            ],
            Notes =
            [
                "Best fit for the current Windows tracker.",
                "Use Beast instead if your FR24 feeder expects Beast TCP."
            ]
        },
        new FeederProfile
        {
            Id = "flightaware",
            Name = "FlightAware",
            Badge = "Native host uploader",
            Summary = "Uses a native host uploader that logs into FlightAware directly from this machine and caches the returned feeder ID.",
            InstallHint = "Click Connect On Host and the app will start the FlightAware uploader on this machine with MLAT disabled.",
            SourceLabel = "External manual source: Beast on 30005. Native host uploader uses the local host feed directly.",
            LocalSettings =
            [
                new("receiver-type", "relay"),
                new("receiver-host", "127.0.0.1"),
                new("receiver-port", "30005"),
                new("allow-mlat", "no")
            ],
            LanSettings =
            [
                new("receiver-type", "relay"),
                new("receiver-host", "{lanHost}"),
                new("receiver-port", "30005"),
                new("allow-mlat", "no")
            ],
            Notes =
            [
                "The native uploader reads the local SBS feed and forwards FlightAware ADEPT messages over TLS.",
                "The connector caches the returned feeder ID automatically and usually logs in as guest until the feed is claimed.",
                "Keep MLAT disabled with the current Windows bridge."
            ]
        },
        new FeederProfile
        {
            Id = "airplanes-live",
            Name = "airplanes.live",
            Badge = "Native host connector",
            Summary = "Uses the local Beast bridge on port 30005 and can now be connected directly from this host.",
            InstallHint = "Click Connect On Host and the app will start the airplanes.live relay on this machine with MLAT disabled.",
            SourceLabel = "Primary source: Beast on 30005.",
            LocalSettings =
            [
                new("INPUT", "127.0.0.1:30005"),
                new("MLAT", "off"),
                new("Protocol", "Beast TCP")
            ],
            LanSettings =
            [
                new("INPUT", "{lanHost}:30005"),
                new("MLAT", "off"),
                new("Protocol", "Beast TCP")
            ],
            Notes =
            [
                "The native host runtime relays Beast data directly to feed.airplanes.live on port 30004.",
                "Leave MLAT off with the current Windows bridge."
            ]
        }
    ];

    public static IReadOnlyList<FeederProfile> GetCatalog(string lanHost)
    {
        return Catalog.Select(profile => Resolve(profile, lanHost)).ToArray();
    }

    public static FeederSelectionState LoadSelections(string repoRoot)
    {
        var path = GetSelectionPath(repoRoot);
        if (!File.Exists(path))
        {
            return new FeederSelectionState();
        }

        try
        {
            var state = JsonSerializer.Deserialize<FeederSelectionState>(File.ReadAllText(path), JsonOptions);
            if (state is null)
            {
                return new FeederSelectionState();
            }

            state.SelectedIds = state.SelectedIds
                .Where(id => Catalog.Any(profile => string.Equals(profile.Id, id, StringComparison.OrdinalIgnoreCase)))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            return state;
        }
        catch
        {
            return new FeederSelectionState();
        }
    }

    public static FeederSelectionState AddSelection(string repoRoot, string providerId)
    {
        var state = LoadSelections(repoRoot);
        if (Catalog.All(profile => !string.Equals(profile.Id, providerId, StringComparison.OrdinalIgnoreCase)))
        {
            return state;
        }

        if (!state.SelectedIds.Contains(providerId, StringComparer.OrdinalIgnoreCase))
        {
            state.SelectedIds.Add(providerId);
            SaveSelections(repoRoot, state);
        }

        return state;
    }

    public static FeederSelectionState RemoveSelection(string repoRoot, string providerId)
    {
        var state = LoadSelections(repoRoot);
        state.SelectedIds = state.SelectedIds
            .Where(id => !string.Equals(id, providerId, StringComparison.OrdinalIgnoreCase))
            .ToList();
        SaveSelections(repoRoot, state);
        return state;
    }

    public static string GetLanHost()
    {
        foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (adapter.OperationalStatus != OperationalStatus.Up)
            {
                continue;
            }

            var properties = adapter.GetIPProperties();
            foreach (var address in properties.UnicastAddresses)
            {
                if (address.Address.AddressFamily != AddressFamily.InterNetwork)
                {
                    continue;
                }

                var value = address.Address.ToString();
                if (value.StartsWith("127.", StringComparison.Ordinal) || value.StartsWith("169.254.", StringComparison.Ordinal))
                {
                    continue;
                }

                return value;
            }
        }

        return "localhost";
    }

    private static void SaveSelections(string repoRoot, FeederSelectionState state)
    {
        var path = GetSelectionPath(repoRoot);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(state, JsonOptions));
    }

    private static string GetSelectionPath(string repoRoot)
    {
        return Path.Combine(repoRoot, "logs", "feeders.json");
    }

    private static FeederProfile Resolve(FeederProfile profile, string lanHost)
    {
        return new FeederProfile
        {
            Id = profile.Id,
            Name = profile.Name,
            Badge = profile.Badge,
            Summary = profile.Summary,
            InstallHint = profile.InstallHint,
            SourceLabel = profile.SourceLabel,
            LocalSettings = profile.LocalSettings.Select(setting => Resolve(setting, lanHost)).ToArray(),
            LanSettings = profile.LanSettings.Select(setting => Resolve(setting, lanHost)).ToArray(),
            Notes = profile.Notes
        };
    }

    private static FeederSetting Resolve(FeederSetting setting, string lanHost)
    {
        return setting with
        {
            Value = setting.Value.Replace("{lanHost}", lanHost, StringComparison.OrdinalIgnoreCase)
        };
    }
}
