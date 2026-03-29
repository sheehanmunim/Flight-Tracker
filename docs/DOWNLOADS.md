# Downloads

## Best Option For Users

If you are browsing this project on GitHub, use the repository `Releases` tab.

Release downloads are created automatically when a tag like `v1.0.0` is pushed.
The release workflow attaches:

- `FlightTracker-Windows.zip`
- `FlightTracker.dmg`

## Windows

The Windows package contains both app styles:

- `Desktop\FlightTracker.exe`: full Windows launcher
- `DashboardHost\FlightTrackerDashboard.exe`: browser-host version
- `Run-FlightTracker-Windows.cmd`: package-local shortcut
- `Run-FlightTracker-Browser.cmd`: package-local shortcut

The packaged ZIP is created by:

- `scripts/Package-FlightTracker-Windows.ps1`

The current local build output is:

- `releases/windows/FlightTracker-Windows.zip`

## Mac

The Mac package is built from:

- `macOS/Build-FlightTracker-MacApp.sh`

That produces:

- `dist/macos/Flight Tracker.app`
- `dist/macos/FlightTracker.dmg`

## GitHub Actions

`.github/workflows/build-release-artifacts.yml` builds:

- the Windows ZIP on `windows-latest`
- the Mac app and DMG on `macos-latest`

On `v*` tags, the same workflow also creates a GitHub Release and uploads:

- `FlightTracker-Windows.zip`
- `FlightTracker.dmg`
