# Project Structure

## Top Level

- `README.md`: product-level overview and quick links
- `Run-FlightTracker-Windows.cmd`: source launcher for the Windows desktop app
- `Run-FlightTracker-Browser.cmd`: source launcher for the browser dashboard
- `Build-FlightTracker-Windows.cmd`: simple Windows packaging entrypoint
- `Build-FlightTracker-Mac.command`: simple Mac packaging entrypoint
- `Create-FlightTracker-Release.cmd`: simple GitHub release entrypoint
- `Create-FlightTracker-Release.ps1`: PowerShell release implementation
- `apps/`: app source code
- `docs/`: install, download, and repo guides
- `Windows/`: Windows packaging files
- `scripts/`: runtime PowerShell and Python helpers
- `vendor/`: bundled third-party binaries used by the tracker
- `feeders/`: feeder examples and templates
- `macOS/`: Mac launcher assets and DMG builder
- `dist/`: generated build outputs such as Windows ZIPs and Mac DMGs
- `logs/`: local runtime output and status files

## apps/windows

- `FlightTracker/`: WinForms desktop launcher source
- `DashboardHost/`: browser dashboard host source
- `Shared/`: shared C# feeder/runtime code

## scripts

These are the actual runtime operations the apps call:

- `Start-LocalFlightTracker.ps1`
- `Stop-LocalFlightTracker.ps1`
- `Status-LocalFlightTracker.ps1`
- `Test-FlightTrackerHost.ps1`
- `Manage-NativeFeeder.ps1`

## Windows

- `Build-FlightTracker-Windows.ps1`: Windows packaging script
- `FlightTracker-Installer.iss`: Windows installer definition
- `README.md`: notes about Windows packaging outputs

## Release Flow

- `Create-FlightTracker-Release.cmd 1.0.0`: creates and pushes tag `v1.0.0`
- `.github/workflows/build-release-artifacts.yml`: builds the Windows `.exe`, Windows ZIP, and Mac `.dmg`, then publishes the GitHub Release

## dist

- `dist/windows/FlightTracker-Setup.exe`: Windows installer output
- `dist/windows/FlightTracker-Windows.zip`: packaged Windows ZIP output
- `dist/windows/FlightTracker/`: unpacked packaged Windows app folder
- `dist/macos/`: Mac app bundle and DMG outputs
