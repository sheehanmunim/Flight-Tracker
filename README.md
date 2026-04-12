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
- `output/`: generated packaged outputs such as the Windows EXE and Mac DMG
- `logs/`: runtime logs and status files created locally

## Build Outputs

- `Windows-EXE.cmd` creates `output/windows/FlightTracker-Setup.exe`
- `./Mac-DMG.command` creates `output/macos/FlightTracker.dmg` on a Mac

Releases are published by pushing a tag like `v1.0.0`.

## Mac Setup

1. Start the dashboard on the Windows host with `Browser.cmd`.
2. Build the Mac app with `./Mac-DMG.command` on a Mac.
3. Open the Mac app and paste the shared dashboard URL if prompted.

The packaged Mac app stores its shared dashboard URL in:

- `~/Library/Application Support/Flight Tracker/flight-tracker-url.txt`

The RTL-SDR dongle still has to stay plugged into the Windows host machine.

## Feeding Networks

Flight Tracker can save or manage feeder settings for:

- `FlightAware`
- `airplanes.live`
- `Flightradar24`

Important feeder note:

- the Beast bridge uses synthetic timestamps, so MLAT should stay disabled for Beast-only clients

Example config files:

- `feeders/piaware.conf.example`
- `feeders/fr24feed.ini.example`

Useful local feed outputs:

- `127.0.0.1:30002` as AVR/raw
- `127.0.0.1:30003` as SBS/BaseStation
- `127.0.0.1:30005` as Beast binary

`FlightAware` and `airplanes.live` have built-in native Windows host connectors in this repo.

## Notes

- The browser dashboard and Mac client control the Windows host, but the RTL-SDR dongle still has to be plugged into the Windows machine that runs the decoder.
- The one remaining fresh-machine setup item on Windows can still be the RTL-SDR driver itself.
- `logs/` is only for local runtime state such as `dump1090.log`, feeder status files, and the temporary dashboard key.
