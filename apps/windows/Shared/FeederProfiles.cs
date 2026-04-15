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
            Summary = "This can use the live Windows receiver feed right away, or you can install the official feeder in WSL from the apps.",
            InstallHint = "Copy the saved settings for a manual setup, or run Install Official Feeder if you want the WSL package on this Windows PC.",
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
            Badge = "Quick Connect or PiAware",
            Summary = "Quick Connect starts the lightweight uploader on this Windows PC. Install Official Feeder builds and runs PiAware in WSL against Beast on 30005 for the full FlightAware MLAT path.",
            InstallHint = "Quick Connect is the fast Windows-only uploader. Use Install Official Feeder when you want PiAware and FlightAware MLAT on this Windows PC.",
            SourceLabel = "Best local MLAT source is Beast on 30005, but the Windows Quick Connect path still uses the local SBS uploader path.",
            LocalSettings =
            [
                new("receiver-type", "relay"),
                new("receiver-host", "127.0.0.1"),
                new("receiver-port", "30005"),
                new("allow-mlat", "yes")
            ],
            LanSettings =
            [
                new("receiver-type", "relay"),
                new("receiver-host", "{lanHost}"),
                new("receiver-port", "30005"),
                new("allow-mlat", "yes")
            ],
            Notes =
            [
                "Quick Connect reads the local SBS feed and is useful for a fast ADS-B-only upload from this Windows PC.",
                "Install Official Feeder now builds and runs PiAware directly inside WSL on this Windows PC.",
                "After Quick Connect starts, claim the feeder in your FlightAware account."
            ]
        },
        new FeederProfile
        {
            Id = "airplanes-live",
            Name = "airplanes.live",
            Badge = "Quick Connect or Official Install",
            Summary = "Quick Connect starts the lightweight relay on this Windows PC. Install Official Feeder to put the standard airplanes.live runtime in WSL and use the MLAT-capable Beast feed on 30005.",
            InstallHint = "Use Install Official Feeder for the standard airplanes.live runtime and MLAT path. Quick Connect is the lightweight Windows relay.",
            SourceLabel = "Primary source: Beast on 30005.",
            LocalSettings =
            [
                new("INPUT", "127.0.0.1:30005"),
                new("MLAT", "enabled in the official feeder"),
                new("Protocol", "Beast TCP")
            ],
            LanSettings =
            [
                new("INPUT", "{lanHost}:30005"),
                new("MLAT", "enabled in the official feeder"),
                new("Protocol", "Beast TCP")
            ],
            Notes =
            [
                "Quick Connect relays Beast data directly from this Windows PC to airplanes.live for a lightweight setup.",
                "Install Official Feeder stops the lightweight relay and installs the standard airplanes.live package in WSL with its MLAT runtime."
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
