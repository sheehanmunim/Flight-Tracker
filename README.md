# Flight Tracker

Flight Tracker is now organized around only three user-facing things:

- `Browser`: run the dashboard on the Windows host
- `Windows EXE`: build the Windows installer
- `Mac DMG`: build the Mac app download

## The Only Three Commands

From the repo root:

- `Browser.cmd`
- `Windows-EXE.cmd`
- `./Mac-DMG.command`

That is the whole user-facing surface of this repo.

## Downloads

If you are on GitHub and just want the app:

- open the repository `Releases` tab
- download `FlightTracker-Setup.exe` for Windows and run the installer
- download `FlightTracker.dmg` for Mac (Apple Silicon compatible)
- use the browser mode from the Windows machine that is running the tracker

Tagged builds now publish release assets automatically from `.github/workflows/build-release-artifacts.yml`.

## Repo Layout

- `Browser.cmd`: run the browser dashboard on the Windows host
- `Windows-EXE.cmd`: build `FlightTracker-Setup.exe`
- `Mac-DMG.command`: build `FlightTracker.dmg` on a Mac
- `apps/windows/`: Windows app source code
- `docs/`: short guides for install/download/layout
- `Windows/`: Windows packaging files
- `scripts/`: PowerShell and Python runtime helpers used by the app
- `vendor/`: bundled SDR and dump1090 binaries
- `feeders/`: example feeder configuration files
- `macOS/`: Mac launcher files and DMG builder
- `dist/`: generated packaged outputs such as the Windows EXE and Mac DMG
- `logs/`: runtime logs and status files created locally

## Build Outputs

- `Windows-EXE.cmd` creates `dist/windows/FlightTracker-Setup.exe`
- `./Mac-DMG.command` creates `dist/macos/FlightTracker.dmg` on a Mac

Releases are published by pushing a tag like `v1.0.0`.

## Notes

- The browser dashboard and Mac client control the Windows host, but the RTL-SDR dongle still has to be plugged into the Windows machine that runs the decoder.
- The one remaining fresh-machine setup item on Windows can still be the RTL-SDR driver itself.
