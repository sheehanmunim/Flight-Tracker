# Downloads

## Simple Commands

From the repo root:

- Run the browser dashboard on Windows: `Run-FlightTracker-Browser.cmd`
- Build the Windows installer and ZIP: `Build-FlightTracker-Windows.cmd`
- Build the Mac app and DMG on a Mac: `./Build-FlightTracker-Mac.command`
- Push a release tag and publish release assets: `Create-FlightTracker-Release.cmd 1.0.0`

## Best Option For Users

If you are browsing this project on GitHub, use the repository `Releases` tab.

Release downloads are created automatically when a tag like `v1.0.0` is pushed.
The release workflow attaches:

- `FlightTracker-Setup.exe`
- `FlightTracker-Windows.zip`
- `FlightTracker.dmg` for Mac (Apple Silicon compatible)

## Windows

The main Windows download is:

- `FlightTracker-Setup.exe`: installer that puts Flight Tracker in `Program Files` and adds shortcuts

There is also a portable option:

- `FlightTracker-Windows.zip`: extracted app folder you can run directly

Inside the portable folder you can launch:

- `Desktop\FlightTracker.exe`: full Windows launcher
- `DashboardHost\FlightTrackerDashboard.exe`: browser-host version
- `Run-FlightTracker-Windows.cmd`: package-local shortcut
- `Run-FlightTracker-Browser.cmd`: package-local shortcut

The packaged ZIP is created by:

- `Build-FlightTracker-Windows.cmd`

The setup EXE is created by the same command when `Inno Setup 6` is available.

Local build outputs go to:

- `dist/windows/FlightTracker-Setup.exe`
- `dist/windows/FlightTracker-Windows.zip`
- `dist/windows/FlightTracker/`

## Mac

The Mac package is built from:

- `./Build-FlightTracker-Mac.command`

That produces:

- `dist/macos/Flight Tracker.app`
- `dist/macos/FlightTracker.dmg` for Mac (Apple Silicon compatible)

## GitHub Actions

`Create-FlightTracker-Release.cmd 1.0.0` pushes tag `v1.0.0`, and then `.github/workflows/build-release-artifacts.yml` builds:

- the Windows installer and ZIP on `windows-latest`
- the Mac app and DMG on `macos-latest`

On `v*` tags, the same workflow also creates a GitHub Release and uploads:

- `FlightTracker-Setup.exe`
- `FlightTracker-Windows.zip`
- `FlightTracker.dmg` for Mac (Apple Silicon compatible)
