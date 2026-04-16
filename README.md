# Flight Tracker

Flight Tracker can run as a local receiver host with a browser dashboard, plus remote helper apps:

- `Browser`: a local web dashboard started with `Browser.cmd` on Windows or `Browser.command` on macOS
- `Windows app`: the packaged Windows launcher/app
- `Mac app`: a remote dashboard client that talks to a shared host

The browser-host path runs the decoder on the same machine that has the RTL-SDR attached. The packaged Mac app remains a remote client for a shared host.

There are also standalone Mac browser and Chromium app paths now:

- `Browser.command` starts the browser dashboard on a Mac and drives a local `readsb` decoder on that same Mac
- `Chromium.command` starts the local Mac host and opens the dashboard in a standalone Chromium-family app window
- `Chrome-Direct.command` is kept as a compatibility alias that forwards to `Chromium.command`

Those two Mac paths are standalone and do not require a Windows host.

## Quick Start

From the repo root:

- `Browser.cmd`
- `Browser.command`
- `Chromium.command`
- `Chrome-Direct.command`
- `Windows-EXE.cmd`
- `./Mac-DMG.command`

Those are the only top-level commands most users need.

## How It Works

There is one real receiver/decoder host:

- on `Windows`, the host runs `dump1090.exe`
- on `macOS`, the local browser-host path expects `readsb` on `PATH`
- the host serves the local aircraft view and exposes local feed outputs for feeder software

The three frontends are just different ways to control the same host:

- `Browser.cmd` starts the tracker runtime and opens the web dashboard
- the `Windows app` is a native launcher/control app for the Windows host path
- the `Mac app` is a remote client for a shared host and uses the shared dashboard URL

The Mac app does not decode ADS-B by itself. It controls a shared host over the dashboard URL.

The new Mac browser-host path is different from the remote Mac app:

- the `Mac app` is still a remote client for a shared host
- `Browser.command` makes the Mac itself the local host when `readsb` is installed and the RTL-SDR is plugged into that Mac

## Downloads

If you are on GitHub and just want the app:

- open the repository `Releases` tab
- download `FlightTracker-Setup.exe` for Windows
- download `FlightTracker.dmg` for Mac
- or use `Browser.cmd` on the Windows machine that has the SDR attached

Tagged builds publish release assets automatically from `.github/workflows/build-release-artifacts.yml`.

## Local Ports

Useful local feed outputs on the local host:

- `127.0.0.1:30002` as AVR/raw
- `127.0.0.1:30003` as SBS/BaseStation
- `127.0.0.1:30005` as Beast binary
- `http://127.0.0.1:5099` as the dashboard app

Platform note:

- on `Windows`, `http://127.0.0.1:8080` is the local map/web UI from `dump1090`
- on `macOS`, the local receiver view is served through the dashboard on `5099`

## MLAT

The important current state:

- `30005` now comes directly from `dump1090.exe`
- that means the Beast feed on `30005` now carries decoder timestamps instead of synthetic bridge timestamps
- this is the receiver-side requirement for MLAT-capable Beast clients

What that does and does not mean:

- `airplanes.live` MLAT works through `Install Official Feeder`, which installs the standard airplanes.live runtime in WSL against Beast on `30005`
- `FlightAware` MLAT now works through `Install Official Feeder`, which builds and runs PiAware in WSL against Beast on `30005`
- `Quick Connect` is still the lightweight uploader path and is not the full MLAT path for every network

So the Windows host path is MLAT-capable on its Beast output. Both the official `airplanes.live` and official `FlightAware` WSL installs now use that MLAT-capable Beast feed on that machine.

## Feeding Networks

Flight Tracker can save or manage feeder settings for:

- `FlightAware`
- `airplanes.live`
- `Flightradar24`

Current feeder behavior:

- `FlightAware`: `Quick Connect` uses the lightweight Windows uploader; `Install Official Feeder` builds and runs PiAware in WSL with MLAT support
- `airplanes.live`: `Quick Connect` uses the lightweight Windows relay; `Install Official Feeder` installs the standard WSL feeder with MLAT support
- `Flightradar24`: you can copy the saved settings or install the feeder package in WSL from the apps

Example config files:

- `feeders/piaware.conf.example`
- `feeders/fr24feed.ini.example`

## Mac Setup

1. Start the shared host with `Browser.cmd` on Windows or `Browser.command` on macOS.
2. Build the Mac app with `./Mac-DMG.command` on a Mac.
3. Open the Mac app and use the shared dashboard URL if prompted.

The packaged Mac app stores its shared dashboard URL in:

- `~/Library/Application Support/Flight Tracker/flight-tracker-url.txt`

## Repo Layout

- `Browser.cmd`: start the Windows tracker runtime and browser dashboard
- `Browser.command`: start the local Mac tracker runtime and browser dashboard
- `Chromium.command`: open the standalone Chromium-family app window for the local dashboard
- `Chrome-Direct.command`: compatibility alias for `Chromium.command`
- `Windows-EXE.cmd`: build `FlightTracker-Setup.exe`
- `Mac-DMG.command`: build `FlightTracker.dmg` on a Mac
- `apps/windows/`: Windows app and dashboard source code
- `docs/`: short guides
- `Windows/`: Windows packaging files
- `scripts/`: PowerShell and runtime helper scripts
- `vendor/`: bundled SDR and `dump1090` binaries/source
- `feeders/`: example feeder configuration files
- `macOS/`: Mac launcher files and DMG builder
- `logs/`: local runtime logs and state files

## Build Outputs

- `Windows-EXE.cmd` creates `FlightTracker-Setup.exe` in the repo root
- `./Mac-DMG.command` creates `FlightTracker.dmg` in the repo root on a Mac

Releases are published by pushing a tag like `v1.0.0`.

## Notes

- The RTL-SDR dongle must stay attached to whichever machine is running the local decoder.
- The browser dashboard, Windows app, and Mac app are all control surfaces for the same local or shared host.
- A fresh Windows machine may still need the RTL-SDR driver installed.
- `logs/` is only local runtime state such as `dump1090.log`, feeder status files, and the dashboard key.
