# Project Structure

## Top Level

- `README.md`: product-level overview and quick links
- `Browser.cmd`: browser dashboard entrypoint
- `Windows-EXE.cmd`: Windows installer build entrypoint
- `Mac-DMG.command`: Mac DMG build entrypoint
- `apps/`: app source code
- `docs/`: install, download, and repo guides
- `Windows/`: Windows packaging files
- `scripts/`: runtime PowerShell and Python helpers
- `vendor/`: bundled third-party binaries used by the tracker
- `feeders/`: feeder examples and templates
- `macOS/`: Mac launcher assets and DMG builder
- `output/`: generated build outputs such as the Windows EXE and Mac DMG
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

- Push a tag like `v1.0.0`
- `.github/workflows/build-release-artifacts.yml`: builds the Windows `.exe` and Mac `.dmg`, then publishes the GitHub Release

## output

- `output/windows/FlightTracker-Setup.exe`: Windows installer output
- `output/windows/FlightTracker/`: unpacked packaged Windows app folder
- `output/macos/`: Mac app bundle and DMG outputs
