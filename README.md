# Flight Tracker

Flight Tracker is a Windows-first RTL-SDR plane tracker with three simple ways to use it:

- `Windows app`: full desktop launcher for starting the tracker and managing feeders
- `Browser host`: a lightweight dashboard you run on the Windows machine and open from any browser
- `Mac client`: a packaged Mac app that opens the shared dashboard from your Windows host

## Quick Start

1. Plug in the RTL-SDR USB dongle to the Windows computer that will do the tracking.
2. Pick one way to run it:

- `Windows app`: `Run-FlightTracker-Windows.cmd`
- `Browser host`: `Run-FlightTracker-Browser.cmd`
- `Mac client`: `macOS/Run-FlightTracker-Mac.command`

3. If you want packaged downloads instead of source launchers, see `docs/DOWNLOADS.md`.

## Simple Commands

If you only want the main commands, use these from the repo root:

- Run browser dashboard on Windows: `Run-FlightTracker-Browser.cmd`
- Run Windows desktop app from source: `Run-FlightTracker-Windows.cmd`
- Build Windows installer and portable ZIP: `Build-FlightTracker-Windows.cmd`
- Build the Mac app and DMG on a Mac: `./Build-FlightTracker-Mac.command`
- Create a GitHub release for version `1.0.0`: `Create-FlightTracker-Release.cmd 1.0.0`

That release command pushes tag `v1.0.0`, which triggers GitHub Actions to build and publish:

- `FlightTracker-Setup.exe`
- `FlightTracker-Windows.zip`
- `FlightTracker.dmg` for Mac (Apple Silicon compatible)

## Downloads

If you are on GitHub and just want the app:

- open the repository `Releases` tab
- download `FlightTracker-Setup.exe` for Windows and run the installer
- or download `FlightTracker-Windows.zip` if you want the portable version
- download `FlightTracker.dmg` for Mac (Apple Silicon compatible)

Tagged builds now publish release assets automatically from `.github/workflows/build-release-artifacts.yml`.

## Best Starting Point

- New user who just wants the app: read `docs/INSTALL.md`
- Someone downloading release builds: read `docs/DOWNLOADS.md`
- Someone browsing the repo on GitHub: read `docs/PROJECT-STRUCTURE.md`
- Someone setting up feeders: read `docs/FEEDING-NETWORKS.md`

## Repo Layout

- `Run-FlightTracker-Windows.cmd`: source launcher for the Windows desktop app
- `Run-FlightTracker-Browser.cmd`: source launcher for the Windows browser dashboard
- `Build-FlightTracker-Windows.cmd`: simple Windows packaging command
- `Build-FlightTracker-Mac.command`: simple Mac packaging command
- `Create-FlightTracker-Release.cmd`: simple GitHub release command
- `apps/windows/`: Windows app source code
- `docs/`: install guide, download guide, repo layout, and feeder overview
- `Windows/`: Windows packaging files
- `scripts/`: PowerShell and Python runtime helpers used by the app
- `vendor/`: bundled SDR and dump1090 binaries
- `feeders/`: example feeder configuration files
- `macOS/`: Mac launcher files and DMG builder
- `dist/`: generated packaged outputs such as Windows ZIPs and Mac DMGs
- `logs/`: runtime logs and status files created locally

## Build Packaged Apps

- `Windows`: run `Build-FlightTracker-Windows.cmd`
- `Mac`: run `./Build-FlightTracker-Mac.command` on a Mac
- `GitHub release`: run `Create-FlightTracker-Release.cmd 1.0.0`

Local Windows build outputs go to `dist/windows/FlightTracker-Windows.zip`
and `dist/windows/FlightTracker-Setup.exe`.

## Notes

- The browser dashboard and Mac client control the Windows host, but the RTL-SDR dongle still has to be plugged into the Windows machine that runs the decoder.
- The one remaining fresh-machine setup item on Windows can still be the RTL-SDR driver itself.
