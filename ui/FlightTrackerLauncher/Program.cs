using System.Diagnostics;
using System.Text;

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
    private readonly string _repoRoot;
    private readonly string _startScript;
    private readonly string _statusScript;
    private readonly string _stopScript;
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
    private readonly Label _summaryLabel;

    public MainForm()
    {
        _repoRoot = FindRepoRoot();
        _startScript = Path.Combine(_repoRoot, "scripts", "Start-LocalFlightTracker.ps1");
        _statusScript = Path.Combine(_repoRoot, "scripts", "Status-LocalFlightTracker.ps1");
        _stopScript = Path.Combine(_repoRoot, "scripts", "Stop-LocalFlightTracker.ps1");
        _webLauncher = Path.Combine(_repoRoot, "FlightTrackerWeb.cmd");
        _feedersGuide = Path.Combine(_repoRoot, "feeders", "README.md");
        _logFile = Path.Combine(_repoRoot, "logs", "dump1090.log");

        Text = "Flight Tracker Launcher";
        MinimumSize = new Size(860, 620);
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
            RowCount = 6,
            Padding = new Padding(18)
        };

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
        mainPanel.Controls.Add(_statusBox, 0, 4);
        mainPanel.Controls.Add(noteLabel, 0, 5);

        Controls.Add(mainPanel);

        Shown += async (_, _) => await RefreshStatusAsync();
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
    }

    private static string FindRepoRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);

        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, "Start-LocalFlightTracker.cmd")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new DirectoryNotFoundException("Could not find the Flight Tracker repo root from the launcher location.");
    }
}
