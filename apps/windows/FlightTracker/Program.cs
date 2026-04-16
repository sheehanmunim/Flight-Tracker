using System.Diagnostics;
using System.Net.Http;
using System.Net.NetworkInformation;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace FlightTracker;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new DashboardShellForm());
    }
}

internal sealed class DashboardShellForm : Form
{
    private const int DashboardPort = 5099;
    private const string DashboardBaseUrl = "http://127.0.0.1:5099";

    private readonly string _repoRoot;
    private readonly string _dashboardProjectPath;
    private readonly string _dashboardKeyFile;
    private readonly WebView2 _webView;
    private readonly ToolStripButton _reloadButton;
    private readonly ToolStripButton _restartButton;
    private readonly ToolStripButton _copyUrlButton;
    private readonly ToolStripLabel _statusLabel;
    private readonly Label _fallbackLabel;

    private Process? _dashboardProcess;
    private string _dashboardUrl = "";

    public DashboardShellForm()
    {
        _repoRoot = FindRepoRoot();
        _dashboardProjectPath = Path.Combine(_repoRoot, "apps", "windows", "DashboardHost", "DashboardHost.csproj");
        _dashboardKeyFile = Path.Combine(_repoRoot, "logs", "dashboard.key");

        Text = "Flight Tracker";
        MinimumSize = new Size(1100, 760);
        StartPosition = FormStartPosition.CenterScreen;
        WindowState = FormWindowState.Maximized;
        Font = new Font("Segoe UI", 10);

        _reloadButton = new ToolStripButton("Reload")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text
        };
        _reloadButton.Click += async (_, _) => await LoadDashboardAsync(forceRestart: false, reloadOnly: true);

        _restartButton = new ToolStripButton("Restart App Host")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text
        };
        _restartButton.Click += async (_, _) => await LoadDashboardAsync(forceRestart: true, reloadOnly: false);

        _copyUrlButton = new ToolStripButton("Copy Dashboard URL")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text
        };
        _copyUrlButton.Click += (_, _) => CopyDashboardUrl();

        _statusLabel = new ToolStripLabel("Starting in-app dashboard...");

        var toolStrip = new ToolStrip
        {
            GripStyle = ToolStripGripStyle.Hidden,
            Dock = DockStyle.Top,
            Padding = new Padding(8, 6, 8, 6)
        };
        toolStrip.Items.Add(_reloadButton);
        toolStrip.Items.Add(_restartButton);
        toolStrip.Items.Add(_copyUrlButton);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_statusLabel);

        _webView = new WebView2
        {
            Dock = DockStyle.Fill,
            Visible = false
        };

        _fallbackLabel = new Label
        {
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
            Padding = new Padding(28),
            Font = new Font("Segoe UI", 11),
            Text = "Starting Flight Tracker..."
        };

        Controls.Add(_webView);
        Controls.Add(_fallbackLabel);
        Controls.Add(toolStrip);

        Shown += async (_, _) => await LoadDashboardAsync(forceRestart: false, reloadOnly: false);
        FormClosed += (_, _) =>
        {
            _dashboardProcess?.Dispose();
            _dashboardProcess = null;
        };
    }

    private async Task LoadDashboardAsync(bool forceRestart, bool reloadOnly)
    {
        SetToolbarEnabled(false);

        try
        {
            if (!reloadOnly)
            {
                UpdateStatus("Starting the local app host...");
                _dashboardUrl = await EnsureDashboardUrlAsync(forceRestart);
            }
            else if (string.IsNullOrWhiteSpace(_dashboardUrl))
            {
                _dashboardUrl = await EnsureDashboardUrlAsync(forceRestart: false);
            }

            await EnsureWebViewReadyAsync();
            _webView.Source = new Uri(_dashboardUrl);
            _webView.Visible = true;
            _fallbackLabel.Visible = false;
            UpdateStatus("Flight Tracker is running inside the app.");
        }
        catch (Exception ex)
        {
            _webView.Visible = false;
            _fallbackLabel.Visible = true;
            _fallbackLabel.Text = ex.Message;
            UpdateStatus("The in-app dashboard could not start.");
        }
        finally
        {
            SetToolbarEnabled(true);
        }
    }

    private async Task EnsureWebViewReadyAsync()
    {
        try
        {
            if (_webView.CoreWebView2 is null)
            {
                await _webView.EnsureCoreWebView2Async();
                var core = _webView.CoreWebView2 ?? throw new InvalidOperationException(
                    "WebView2 initialized without creating the browser control.");

                core.Settings.IsStatusBarEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = true;
                core.Settings.AreDevToolsEnabled = true;
                core.Settings.IsZoomControlEnabled = true;
                core.NavigationCompleted += (_, args) =>
                {
                    if (!args.IsSuccess)
                    {
                        UpdateStatus($"Navigation failed: {args.WebErrorStatus}");
                    }
                };
            }
        }
        catch (WebView2RuntimeNotFoundException)
        {
            throw new InvalidOperationException(
                "Microsoft Edge WebView2 Runtime is required for the Windows app. Install Edge/WebView2, then reopen Flight Tracker.");
        }
    }

    private async Task<string> EnsureDashboardUrlAsync(bool forceRestart)
    {
        if (forceRestart)
        {
            StopStartedDashboardHost();
        }

        if (!IsPortListening(DashboardPort))
        {
            StartDashboardHostProcess();
        }

        var key = await WaitForDashboardKeyAsync();
        await WaitForDashboardEndpointAsync(key);
        return $"{DashboardBaseUrl}/?key={Uri.EscapeDataString(key)}";
    }

    private void StartDashboardHostProcess()
    {
        var launch = ResolveDashboardLaunch();
        Directory.CreateDirectory(Path.Combine(_repoRoot, "logs"));

        _dashboardProcess = Process.Start(launch) ?? throw new InvalidOperationException(
            "The app host process could not be started.");
    }

    private ProcessStartInfo ResolveDashboardLaunch()
    {
        var packagedHostPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "DashboardHost", "FlightTrackerDashboard.exe"));
        if (File.Exists(packagedHostPath))
        {
            return new ProcessStartInfo
            {
                FileName = packagedHostPath,
                Arguments = "--no-browser --urls http://127.0.0.1:5099",
                WorkingDirectory = _repoRoot,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
        }

        var localBuildCandidates = new[]
        {
            Path.Combine(_repoRoot, "apps", "windows", "DashboardHost", "bin", "Release", "net8.0", "FlightTrackerDashboard.exe"),
            Path.Combine(_repoRoot, "apps", "windows", "DashboardHost", "bin", "Debug", "net8.0", "FlightTrackerDashboard.exe")
        };

        foreach (var candidate in localBuildCandidates)
        {
            if (File.Exists(candidate))
            {
                return new ProcessStartInfo
                {
                    FileName = candidate,
                    Arguments = "--no-browser --urls http://127.0.0.1:5099",
                    WorkingDirectory = _repoRoot,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
            }
        }

        if (!File.Exists(_dashboardProjectPath))
        {
            throw new InvalidOperationException("Could not find the dashboard host project or executable for the Windows app.");
        }

        return new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = $"run --project \"{_dashboardProjectPath}\" -c Release -- --no-browser --urls http://127.0.0.1:5099",
            WorkingDirectory = _repoRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
    }

    private async Task<string> WaitForDashboardKeyAsync()
    {
        for (var attempt = 0; attempt < 30; attempt += 1)
        {
            if (File.Exists(_dashboardKeyFile))
            {
                var key = (await File.ReadAllTextAsync(_dashboardKeyFile)).Trim();
                if (!string.IsNullOrWhiteSpace(key))
                {
                    return key;
                }
            }

            await Task.Delay(500);
        }

        throw new InvalidOperationException("The app host started, but the dashboard key file was not created.");
    }

    private static async Task WaitForDashboardEndpointAsync(string key)
    {
        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(4)
        };

        for (var attempt = 0; attempt < 30; attempt += 1)
        {
            try
            {
                using var response = await client.GetAsync($"{DashboardBaseUrl}/api/meta?key={Uri.EscapeDataString(key)}");
                if (response.IsSuccessStatusCode)
                {
                    return;
                }
            }
            catch
            {
                // Wait for the host to come online.
            }

            await Task.Delay(500);
        }

        throw new InvalidOperationException("The app host never became ready on http://127.0.0.1:5099.");
    }

    private void CopyDashboardUrl()
    {
        if (string.IsNullOrWhiteSpace(_dashboardUrl))
        {
            UpdateStatus("The dashboard URL is not ready yet.");
            return;
        }

        try
        {
            Clipboard.SetText(_dashboardUrl);
            UpdateStatus("Dashboard URL copied to the clipboard.");
        }
        catch (Exception ex)
        {
            UpdateStatus(ex.Message);
        }
    }

    private void StopStartedDashboardHost()
    {
        if (_dashboardProcess is null)
        {
            return;
        }

        try
        {
            if (!_dashboardProcess.HasExited)
            {
                _dashboardProcess.Kill(entireProcessTree: true);
                _dashboardProcess.WaitForExit(5000);
            }
        }
        catch
        {
            // Ignore restart cleanup failures and let the next launch attempt continue.
        }
        finally
        {
            _dashboardProcess.Dispose();
            _dashboardProcess = null;
        }
    }

    private void UpdateStatus(string text)
    {
        _statusLabel.Text = text;
        _fallbackLabel.Text = text;
    }

    private void SetToolbarEnabled(bool enabled)
    {
        _reloadButton.Enabled = enabled;
        _restartButton.Enabled = enabled;
        _copyUrlButton.Enabled = enabled;
    }

    private static bool IsPortListening(int port)
    {
        return IPGlobalProperties.GetIPGlobalProperties()
            .GetActiveTcpListeners()
            .Any(endpoint => endpoint.Port == port);
    }

    private static string FindRepoRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);

        while (current is not null)
        {
            var hasRootMarker = File.Exists(Path.Combine(current.FullName, "flight-tracker-root.marker"));
            var hasWindowsScripts = File.Exists(Path.Combine(current.FullName, "scripts", "Start-LocalFlightTracker.ps1"));
            var hasMacScripts = File.Exists(Path.Combine(current.FullName, "scripts", "Start-LocalFlightTracker.sh"));

            if (hasRootMarker && (hasWindowsScripts || hasMacScripts))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new DirectoryNotFoundException("Could not find the Flight Tracker repo root from the app location.");
    }
}
