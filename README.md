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

## Downloads

If you are on GitHub and just want the app:

- open the repository `Releases` tab
- download `FlightTracker-Windows.zip` for Windows
- download `FlightTracker.dmg` for Mac

Tagged builds now publish release assets automatically from `.github/workflows/build-release-artifacts.yml`.

## Best Starting Point

- New user who just wants the app: read `docs/INSTALL.md`
- Someone downloading release builds: read `docs/DOWNLOADS.md`
- Someone browsing the repo on GitHub: read `docs/PROJECT-STRUCTURE.md`
- Someone setting up feeders: read `docs/FEEDING-NETWORKS.md`

## Repo Layout

- `apps/windows/`: Windows launcher source, browser host source, and development launchers
- `docs/`: install guide, download guide, repo layout, and feeder overview
- `scripts/`: PowerShell and Python runtime helpers used by the app
- `vendor/`: bundled SDR and dump1090 binaries
- `feeders/`: example feeder configuration files
- `macOS/`: Mac launcher files and DMG builder
- `releases/`: Windows release-ready package outputs
- `dist/`: other generated outputs such as local Mac builds

## Build Packaged Apps

- `Windows`: run `scripts/Package-FlightTracker-Windows.ps1`
- `Mac`: run `macOS/Build-FlightTracker-MacApp.sh` on a Mac
- `GitHub`: `.github/workflows/build-release-artifacts.yml` builds artifacts on demand and publishes release downloads on `v*` tags

The current Windows download artifact is `releases/windows/FlightTracker-Windows.zip`.

## Notes

- The browser dashboard and Mac client control the Windows host, but the RTL-SDR dongle still has to be plugged into the Windows machine that runs the decoder.
- The one remaining fresh-machine setup item on Windows can still be the RTL-SDR driver itself.
