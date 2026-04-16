# Project Structure

## Top Level

- `README.md`: product-level overview and quick links
- `Browser.cmd`: browser dashboard entrypoint for the system browser path
- `Windows-EXE.cmd`: Windows installer build entrypoint
- `Mac-DMG.command`: Mac DMG build entrypoint
- `apps/`: app source code
- `docs/`: install, download, and repo guides
- `Windows/`: Windows packaging files
- `scripts/`: runtime PowerShell and Python helpers
- `vendor/`: bundled third-party binaries used by the tracker
- `feeders/`: feeder examples and templates
- `macOS/`: Mac launcher assets and DMG builder
- `logs/`: local runtime output and status files

## apps/windows

- `FlightTracker/`: WinForms desktop app source with the embedded dashboard shell
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

## Release Flow

- Push a tag like `v1.0.0`
- `.github/workflows/build-release-artifacts.yml`: builds the Windows `.exe` and Mac `.dmg`, then publishes the GitHub Release

## Build Artifacts

- `FlightTracker-Setup.exe`: Windows installer output in the repo root
- `FlightTracker.dmg`: Mac DMG output in the repo root
