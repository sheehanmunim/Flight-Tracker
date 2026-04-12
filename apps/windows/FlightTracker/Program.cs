using System.Diagnostics;
using System.Text;
using FlightTracker.Shared;

namespace FlightTrackerLauncher;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

internal sealed class MainForm : Form
{
    private sealed record FeederChoice(string Id, string Name)
    {
        public override string ToString() => Name;
    }

    private readonly string _repoRoot;
    private readonly string _startScript;
    private readonly string _statusScript;
    private readonly string _stopScript;
    private readonly string _nativeFeederScript;
    private readonly string _webLauncher;
    private readonly string _feedersGuide;
    private readonly string _logFile;

    private readonly TextBox _statusBox;
    private readonly Button _startButton;
    private readonly Button _stopButton;
    private readonly Button _refreshButton;
    private readonly Button _openMapButton;
    private readonly Button _openWebButton;
    private readonly Button _openGuideButton;
    private readonly Button _openLogsButton;
    private readonly Button _addFeederButton;
    private readonly Button _removeFeederButton;
    private readonly Button _copyLocalFeederButton;
    private readonly Button _copyLanFeederButton;
    private readonly Button _connectFeederButton;
    private readonly Button _disconnectFeederButton;
    private readonly Label _summaryLabel;
    private readonly Label _feederHostLabel;
    private readonly ComboBox _feederComboBox;
    private readonly ListBox _feederListBox;
    private readonly TextBox _feederDetailsBox;

    public MainForm()
    {
        _repoRoot = FindRepoRoot();
        _startScript = Path.Combine(_repoRoot, "scripts", "Start-LocalFlightTracker.ps1");
        _statusScript = Path.Combine(_repoRoot, "scripts", "Status-LocalFlightTracker.ps1");
        _stopScript = Path.Combine(_repoRoot, "scripts", "Stop-LocalFlightTracker.ps1");
        _nativeFeederScript = Path.Combine(_repoRoot, "scripts", "Manage-NativeFeeder.ps1");
        var preferredWebLauncher = Path.Combine(_repoRoot, "Browser.cmd");
        var legacyWebLauncher = Path.Combine(_repoRoot, "Run-FlightTracker-Browser.cmd");
        _webLauncher = File.Exists(preferredWebLauncher) ? preferredWebLauncher : legacyWebLauncher;
        _feedersGuide = Path.Combine(_repoRoot, "docs", "FEEDING-NETWORKS.md");
        _logFile = Path.Combine(_repoRoot, "logs", "dump1090.log");

        Text = "Flight Tracker Launcher";
        MinimumSize = new Size(980, 760);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10);

        var header = new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 18, FontStyle.Bold),
            Text = "Flight Tracker",
            Margin = new Padding(0, 0, 0, 6)
        };

        var subheader = new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI", 10),
            Text = "One-click control for the local map, SDR decoder, and Beast bridge on port 30005.",
            Margin = new Padding(0, 0, 0, 16)
        };

        _summaryLabel = new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI", 10),
            Text = "Local ports: map 8080, AVR 30002, SBS 30003, Beast 30005",
            Margin = new Padding(0, 0, 0, 12)
        };

        _startButton = CreateButton("Start Tracker", async (_, _) => await RunAndRefreshAsync(_startScript, "-NoBrowser"));
        _stopButton = CreateButton("Stop Tracker", async (_, _) => await RunAndRefreshAsync(_stopScript));
        _refreshButton = CreateButton("Refresh Status", async (_, _) => await RefreshStatusAsync());
        _openMapButton = CreateButton("Open Map", (_, _) => OpenExternal("http://localhost:8080"));
        _openWebButton = CreateButton("Launch Web Dashboard", (_, _) => OpenExternal(_webLauncher));
        _openGuideButton = CreateButton("Open Feed Guide", (_, _) => OpenExternal(_feedersGuide));
        _openLogsButton = CreateButton("Open Logs", (_, _) => OpenExternal(_logFile));
        _addFeederButton = CreateButton("Add Feeder", (_, _) => AddSelectedFeeder());
        _removeFeederButton = CreateButton("Remove Feeder", (_, _) => RemoveSelectedFeeder());
        _copyLocalFeederButton = CreateButton("Copy Same-Host Setup", (_, _) => CopySelectedFeederSettings(useLanSettings: false));
        _copyLanFeederButton = CreateButton("Copy LAN Setup", (_, _) => CopySelectedFeederSettings(useLanSettings: true));
        _connectFeederButton = CreateButton("Connect On Host", async (_, _) => await ConnectSelectedFeederAsync());
        _disconnectFeederButton = CreateButton("Disconnect", async (_, _) => await DisconnectSelectedFeederAsync());

        var buttonRow = new FlowLayoutPanel
        {
            AutoSize = true,
            WrapContents = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 16)
        };

        buttonRow.Controls.AddRange(
        [
            _startButton,
            _stopButton,
            _refreshButton,
            _openMapButton,
            _openWebButton,
            _openGuideButton,
            _openLogsButton
        ]);

        _feederHostLabel = new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI", 9),
            Text = $"LAN host: {FeederProfiles.GetLanHost()}",
            Margin = new Padding(0, 4, 0, 10)
        };

        _feederComboBox = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 280
        };

        _feederListBox = new ListBox
        {
            Dock = DockStyle.Fill,
            IntegralHeight = false
        };
        _feederListBox.SelectedIndexChanged += (_, _) => RefreshFeederDetails();

        _feederDetailsBox = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            ReadOnly = true,
            Font = new Font("Consolas", 10),
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle
        };

        var feederToolbar = new FlowLayoutPanel
        {
            AutoSize = true,
            WrapContents = true,
            Dock = DockStyle.Top,
            Margin = new Padding(0, 0, 0, 10)
        };
        feederToolbar.Controls.Add(_feederComboBox);
        feederToolbar.Controls.Add(_addFeederButton);
        feederToolbar.Controls.Add(_removeFeederButton);
        feederToolbar.Controls.Add(_connectFeederButton);
        feederToolbar.Controls.Add(_disconnectFeederButton);
        feederToolbar.Controls.Add(_copyLocalFeederButton);
        feederToolbar.Controls.Add(_copyLanFeederButton);

        var feederSplit = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            RowCount = 1
        };
        feederSplit.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 240));
        feederSplit.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        feederSplit.Controls.Add(_feederListBox, 0, 0);
        feederSplit.Controls.Add(_feederDetailsBox, 1, 0);

        var feederPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 1,
            RowCount = 5,
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 14)
        };
        feederPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        feederPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        feederPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        feederPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        feederPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 220));

        feederPanel.Controls.Add(new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 11, FontStyle.Bold),
            Text = "Add Feeder To",
            Margin = new Padding(0, 0, 0, 4)
        }, 0, 0);
        feederPanel.Controls.Add(new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI", 9),
            Text = "Pick a network once and this host keeps its feeder profile ready for the app and the dashboard.",
            Margin = new Padding(0, 0, 0, 2)
        }, 0, 1);
        feederPanel.Controls.Add(_feederHostLabel, 0, 2);
        feederPanel.Controls.Add(feederToolbar, 0, 3);
        feederPanel.Controls.Add(feederSplit, 0, 4);

        _statusBox = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            ReadOnly = true,
            Font = new Font("Consolas", 10),
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle
        };

        var noteLabel = new Label
        {
            AutoSize = true,
            Font = new Font("Segoe UI", 9),
            Text = "Note: the local Beast bridge uses synthetic timestamps. Use it for Beast-format feeders, but keep MLAT disabled.",
            Margin = new Padding(0, 12, 0, 0)
        };

        var mainPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 7,
            Padding = new Padding(18)
        };

        mainPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        mainPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        mainPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        mainPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        mainPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        mainPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        mainPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        mainPanel.Controls.Add(header, 0, 0);
        mainPanel.Controls.Add(subheader, 0, 1);
        mainPanel.Controls.Add(_summaryLabel, 0, 2);
        mainPanel.Controls.Add(buttonRow, 0, 3);
        mainPanel.Controls.Add(feederPanel, 0, 4);
        mainPanel.Controls.Add(_statusBox, 0, 5);
        mainPanel.Controls.Add(noteLabel, 0, 6);

        Controls.Add(mainPanel);

        Shown += async (_, _) =>
        {
            RefreshFeederUi();
            await RefreshStatusAsync();
        };
    }

    private static Button CreateButton(string text, EventHandler onClick)
    {
        var button = new Button
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Text = text,
            Margin = new Padding(0, 0, 10, 10),
            Padding = new Padding(12, 8, 12, 8),
            UseVisualStyleBackColor = true
        };

        button.Click += onClick;
        return button;
    }

    private async Task RunAndRefreshAsync(string scriptPath, string extraArgs = "")
    {
        SetButtonsEnabled(false);
        try
        {
            _statusBox.Text = "Working..." + Environment.NewLine;
            var output = await RunPowerShellAsync(scriptPath, extraArgs);
            _statusBox.Text = output;
            await RefreshStatusAsync();
        }
        catch (Exception ex)
        {
            _statusBox.Text = ex.Message;
        }
        finally
        {
            SetButtonsEnabled(true);
        }
    }

    private async Task RefreshStatusAsync()
    {
        SetButtonsEnabled(false);
        try
        {
            _statusBox.Text = await RunPowerShellAsync(_statusScript);
            RefreshFeederUi();
        }
        catch (Exception ex)
        {
            _statusBox.Text = ex.Message;
        }
        finally
        {
            SetButtonsEnabled(true);
        }
    }

    private async Task<string> RunPowerShellAsync(string scriptPath, string extraArgs = "")
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-ExecutionPolicy Bypass -File \"{scriptPath}\" {extraArgs}".Trim(),
            WorkingDirectory = _repoRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = psi };
        var outputBuilder = new StringBuilder();

        process.Start();

        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        if (!string.IsNullOrWhiteSpace(stdout))
        {
            outputBuilder.AppendLine(stdout.TrimEnd());
        }

        if (!string.IsNullOrWhiteSpace(stderr))
        {
            outputBuilder.AppendLine(stderr.TrimEnd());
        }

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(outputBuilder.ToString().Trim());
        }

        return outputBuilder.ToString().Trim();
    }

    private void OpenExternal(string target)
    {
        if (!File.Exists(target) && !Uri.TryCreate(target, UriKind.Absolute, out _))
        {
            MessageBox.Show(this, $"Not found: {target}", "Flight Tracker", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = target,
            UseShellExecute = true
        });
    }

    private void SetButtonsEnabled(bool enabled)
    {
        _startButton.Enabled = enabled;
        _stopButton.Enabled = enabled;
        _refreshButton.Enabled = enabled;
        _openMapButton.Enabled = enabled;
        _openWebButton.Enabled = enabled;
        _openGuideButton.Enabled = enabled;
        _openLogsButton.Enabled = enabled;
        _feederComboBox.Enabled = enabled;
        _feederListBox.Enabled = enabled;
        UpdateFeederButtons(enabled);
    }

    private void RefreshFeederUi()
    {
        var lanHost = FeederProfiles.GetLanHost();
        _feederHostLabel.Text = $"LAN host: {lanHost}";

        var catalog = FeederProfiles.GetCatalog(lanHost);
        var selectedIds = FeederProfiles.LoadSelections(_repoRoot).SelectedIds
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var selectedProfiles = catalog.Where(profile => selectedIds.Contains(profile.Id)).ToArray();
        var availableProfiles = catalog.Where(profile => !selectedIds.Contains(profile.Id)).ToArray();

        _feederComboBox.BeginUpdate();
        _feederComboBox.Items.Clear();
        foreach (var provider in availableProfiles)
        {
            _feederComboBox.Items.Add(new FeederChoice(provider.Id, provider.Name));
        }

        if (_feederComboBox.Items.Count > 0)
        {
            _feederComboBox.SelectedIndex = 0;
        }
        _feederComboBox.EndUpdate();

        _feederListBox.BeginUpdate();
        _feederListBox.Items.Clear();
        foreach (var provider in selectedProfiles)
        {
            _feederListBox.Items.Add(provider);
        }
        _feederListBox.DisplayMember = nameof(FeederProfile.Name);
        if (_feederListBox.Items.Count > 0 && _feederListBox.SelectedIndex < 0)
        {
            _feederListBox.SelectedIndex = 0;
        }
        _feederListBox.EndUpdate();

        if (_feederListBox.Items.Count == 0)
        {
            _feederDetailsBox.Text = "No feeder profiles added yet." + Environment.NewLine + Environment.NewLine
                + "Pick a network above and click Add Feeder to save its host settings.";
        }
        else
        {
            RefreshFeederDetails();
        }
        UpdateFeederButtons(true);
    }

    private void RefreshFeederDetails()
    {
        if (_feederListBox.SelectedItem is not FeederProfile provider)
        {
            _feederDetailsBox.Text = "Select a feeder profile to see its settings.";
            UpdateFeederButtons(true);
            return;
        }

        var runtime = NativeFeederRuntime.Load(_repoRoot, provider.Id);
        _feederDetailsBox.Text = BuildFeederDetails(provider, runtime);
        UpdateFeederButtons(true);
    }

    private void AddSelectedFeeder()
    {
        if (_feederComboBox.SelectedItem is not FeederChoice choice)
        {
            return;
        }

        FeederProfiles.AddSelection(_repoRoot, choice.Id);
        RefreshFeederUi();
    }

    private void RemoveSelectedFeeder()
    {
        if (_feederListBox.SelectedItem is not FeederProfile provider)
        {
            return;
        }

        FeederProfiles.RemoveSelection(_repoRoot, provider.Id);
        RefreshFeederUi();
    }

    private void CopySelectedFeederSettings(bool useLanSettings)
    {
        if (_feederListBox.SelectedItem is not FeederProfile provider)
        {
            return;
        }

        var text = BuildFeederCopyText(provider, useLanSettings);
        try
        {
            Clipboard.SetText(text);
            _statusBox.Text = $"{provider.Name} {(useLanSettings ? "LAN" : "same-host")} setup copied to the clipboard.";
        }
        catch (Exception ex)
        {
            _statusBox.Text = ex.Message;
        }
    }

    private async Task ConnectSelectedFeederAsync()
    {
        if (_feederListBox.SelectedItem is not FeederProfile provider)
        {
            return;
        }

        SetButtonsEnabled(false);
        try
        {
            _statusBox.Text = $"Connecting {provider.Name} on this host..." + Environment.NewLine;
            _statusBox.Text = await RunPowerShellAsync(_nativeFeederScript, $"-Provider {provider.Id} -Action Connect");
            RefreshFeederUi();
        }
        catch (Exception ex)
        {
            _statusBox.Text = ex.Message;
        }
        finally
        {
            SetButtonsEnabled(true);
        }
    }

    private async Task DisconnectSelectedFeederAsync()
    {
        if (_feederListBox.SelectedItem is not FeederProfile provider)
        {
            return;
        }

        SetButtonsEnabled(false);
        try
        {
            _statusBox.Text = $"Disconnecting {provider.Name} on this host..." + Environment.NewLine;
            _statusBox.Text = await RunPowerShellAsync(_nativeFeederScript, $"-Provider {provider.Id} -Action Disconnect");
            RefreshFeederUi();
        }
        catch (Exception ex)
        {
            _statusBox.Text = ex.Message;
        }
        finally
        {
            SetButtonsEnabled(true);
        }
    }

    private static string BuildFeederDetails(FeederProfile provider, NativeFeederRuntimeStatus runtime)
    {
        var builder = new StringBuilder();
        builder.AppendLine(provider.Name);
        builder.AppendLine(provider.Badge);
        builder.AppendLine();
        builder.AppendLine(provider.Summary);
        builder.AppendLine();
        builder.AppendLine(provider.InstallHint);
        builder.AppendLine();
        builder.AppendLine("Host connector:");
        builder.AppendLine($"  Status: {runtime.StatusLabel}");
        builder.AppendLine($"  Summary: {runtime.Summary}");
        if (!string.IsNullOrWhiteSpace(runtime.User))
        {
            builder.AppendLine($"  User: {runtime.User}");
        }
        if (!string.IsNullOrWhiteSpace(runtime.FeederId))
        {
            builder.AppendLine($"  Feeder ID: {runtime.FeederId}");
        }
        if (runtime.MessagesUploaded is int uploaded)
        {
            builder.AppendLine($"  Messages uploaded: {uploaded}");
        }
        if (!string.IsNullOrWhiteSpace(runtime.Target))
        {
            builder.AppendLine($"  Target: {runtime.Target}");
        }
        if (!string.IsNullOrWhiteSpace(runtime.LastError))
        {
            builder.AppendLine($"  Last error: {runtime.LastError}");
        }
        builder.AppendLine();
        builder.AppendLine(provider.SourceLabel);
        builder.AppendLine();
        builder.AppendLine("Same host:");
        foreach (var setting in provider.LocalSettings)
        {
            builder.AppendLine($"  {setting.Label}: {setting.Value}");
        }

        builder.AppendLine();
        builder.AppendLine("From another device:");
        foreach (var setting in provider.LanSettings)
        {
            builder.AppendLine($"  {setting.Label}: {setting.Value}");
        }

        builder.AppendLine();
        builder.AppendLine("Notes:");
        foreach (var note in provider.Notes)
        {
            builder.AppendLine($"  - {note}");
        }

        return builder.ToString().Trim();
    }

    private static string BuildFeederCopyText(FeederProfile provider, bool useLanSettings)
    {
        var settings = useLanSettings ? provider.LanSettings : provider.LocalSettings;
        var builder = new StringBuilder();
        builder.AppendLine(provider.Name);
        builder.AppendLine();
        builder.AppendLine(provider.Summary);
        builder.AppendLine();
        foreach (var setting in settings)
        {
            builder.AppendLine($"{setting.Label}: {setting.Value}");
        }

        builder.AppendLine();
        foreach (var note in provider.Notes)
        {
            builder.AppendLine(note);
        }

        return builder.ToString().Trim();
    }

    private void UpdateFeederButtons(bool enabled)
    {
        _addFeederButton.Enabled = enabled && _feederComboBox.Items.Count > 0;
        _removeFeederButton.Enabled = enabled && _feederListBox.SelectedItem is FeederProfile;
        _copyLocalFeederButton.Enabled = enabled && _feederListBox.SelectedItem is FeederProfile;
        _copyLanFeederButton.Enabled = enabled && _feederListBox.SelectedItem is FeederProfile;

        if (_feederListBox.SelectedItem is FeederProfile provider)
        {
            var runtime = NativeFeederRuntime.Load(_repoRoot, provider.Id);
            _connectFeederButton.Enabled = enabled && runtime.CanConnect;
            _disconnectFeederButton.Enabled = enabled && runtime.CanDisconnect;
        }
        else
        {
            _connectFeederButton.Enabled = false;
            _disconnectFeederButton.Enabled = false;
        }
    }

    private static string FindRepoRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);

        while (current is not null)
        {
            var hasRootMarker = File.Exists(Path.Combine(current.FullName, "flight-tracker-root.marker"));
            var hasScripts = File.Exists(Path.Combine(current.FullName, "scripts", "Start-LocalFlightTracker.ps1"));

            if (hasScripts && hasRootMarker)
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new DirectoryNotFoundException("Could not find the Flight Tracker repo root from the launcher location.");
    }
}
