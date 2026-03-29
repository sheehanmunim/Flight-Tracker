# Project Structure

## Top Level

- `README.md`: product-level overview and quick links
- `apps/`: app source and platform launchers
- `docs/`: install, download, and repo guides
- `releases/`: release-ready Windows package outputs
- `scripts/`: runtime PowerShell and Python helpers
- `vendor/`: bundled third-party binaries used by the tracker
- `feeders/`: feeder examples and templates
- `macOS/`: Mac launcher assets and DMG builder
- `dist/`: other generated build outputs
- `logs/`: runtime output and status files

## apps/windows

- `FlightTracker/`: WinForms desktop launcher source
- `DashboardHost/`: browser dashboard host source
- `Shared/`: shared C# feeder/runtime code
- `Run-FlightTracker-Windows.cmd`: development launcher for the Windows desktop app
- `Run-FlightTracker-Browser.cmd`: development launcher for the browser host

## scripts

These are the actual runtime operations the apps call:

- `Start-LocalFlightTracker.ps1`
- `Stop-LocalFlightTracker.ps1`
- `Status-LocalFlightTracker.ps1`
- `Test-FlightTrackerHost.ps1`
- `Manage-NativeFeeder.ps1`

## release outputs

Windows release packaging now goes here:

- `releases/windows/FlightTracker-Windows.zip`
- `releases/windows/FlightTracker/`

Other generated outputs still go here:

- `dist/macos/`
