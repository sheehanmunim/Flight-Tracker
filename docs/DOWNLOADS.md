# Downloads

## Only Three Things

From the repo root:

- `Browser.cmd`
- `Windows-EXE.cmd`
- `./Mac-DMG.command`

## Best Option For Users

If you are browsing this project on GitHub, use the repository `Releases` tab.

Release downloads are created automatically when a tag like `v1.0.0` is pushed.
The release workflow attaches:

- `FlightTracker-Setup.exe`
- `FlightTracker.dmg` for Mac (Apple Silicon compatible)

## Windows

The main Windows download is:

- `FlightTracker-Setup.exe`: installer that puts Flight Tracker in `Program Files` and adds shortcuts

The Windows build command is:

- `Windows-EXE.cmd`

That creates:

- `output/windows/FlightTracker-Setup.exe`
- `output/windows/FlightTracker/`

## Mac

The Mac package is built from:

- `./Mac-DMG.command`

That produces:

- `output/macos/Flight Tracker.app`
- `output/macos/FlightTracker.dmg` for Mac (Apple Silicon compatible)

## GitHub Actions

Pushing a tag like `v1.0.0` triggers `.github/workflows/build-release-artifacts.yml`, which builds:

- the Windows installer and ZIP on `windows-latest`
- the Mac app and DMG on `macos-latest`

On `v*` tags, the same workflow also creates a GitHub Release and uploads:

- `FlightTracker-Setup.exe`
- `FlightTracker.dmg` for Mac (Apple Silicon compatible)
