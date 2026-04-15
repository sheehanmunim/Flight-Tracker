# Flight Tracker

Flight Tracker is one Windows receiver PC with three user-facing ways to control it:

- `Browser`: a local web dashboard started with `Browser.cmd`
- `Windows app`: the packaged Windows launcher/app
- `Mac app`: a remote dashboard client that talks to the Windows receiver PC

All three surfaces control the same Windows machine. The RTL-SDR dongle and decoder stay on that Windows receiver PC.

## Quick Start

From the repo root:

- `Browser.cmd`
- `Windows-EXE.cmd`
- `./Mac-DMG.command`

Those are the only top-level commands most users need.

## How It Works

There is one real receiver/decoder PC:

- the `Windows receiver PC` runs `dump1090.exe`
- that PC serves the local aircraft map on `http://localhost:8080`
- that PC also exposes local feed outputs for feeder software

The three frontends are just different ways to control that same receiver PC:

- `Browser.cmd` starts the tracker runtime and opens the web dashboard
- the `Windows app` is a native launcher/control app for the same receiver PC
- the `Mac app` is a remote client for the same receiver PC and uses the shared dashboard URL

The Mac app does not decode ADS-B by itself. It controls the Windows receiver PC over the dashboard URL.

## Downloads

If you are on GitHub and just want the app:

- open the repository `Releases` tab
- download `FlightTracker-Setup.exe` for Windows
- download `FlightTracker.dmg` for Mac
- or use `Browser.cmd` on the Windows machine that has the SDR attached

Tagged builds publish release assets automatically from `.github/workflows/build-release-artifacts.yml`.

## Local Ports

Useful local feed outputs on the Windows receiver PC:

- `127.0.0.1:30002` as AVR/raw
- `127.0.0.1:30003` as SBS/BaseStation
- `127.0.0.1:30005` as Beast binary
- `http://127.0.0.1:8080` as the local map/web UI
- `http://127.0.0.1:5099` as the dashboard app

## MLAT

The important current state:

- `30005` now comes directly from `dump1090.exe`
- that means the Beast feed on `30005` now carries decoder timestamps instead of synthetic bridge timestamps
- this is the receiver-side requirement for MLAT-capable Beast clients

What that does and does not mean:

- `airplanes.live` MLAT works through `Install Official Feeder`, which installs the standard airplanes.live runtime in WSL against Beast on `30005`
- `FlightAware` MLAT now works through `Install Official Feeder`, which builds and runs PiAware in WSL against Beast on `30005`
- `Quick Connect` is still the lightweight Windows-only uploader path and is not the full MLAT path for every network

So the receiver PC is MLAT-capable on its Beast output. Both the official `airplanes.live` and official `FlightAware` WSL installs now use that MLAT-capable Beast feed on this machine.

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

1. Start the Windows receiver PC with `Browser.cmd`.
2. Build the Mac app with `./Mac-DMG.command` on a Mac.
3. Open the Mac app and use the shared dashboard URL if prompted.

The packaged Mac app stores its shared dashboard URL in:

- `~/Library/Application Support/Flight Tracker/flight-tracker-url.txt`

## Repo Layout

- `Browser.cmd`: start the Windows tracker runtime and browser dashboard
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

- The RTL-SDR dongle must stay attached to the Windows machine that runs the decoder.
- The browser dashboard, Windows app, and Mac app are all control surfaces for the same Windows receiver PC.
- A fresh Windows machine may still need the RTL-SDR driver installed.
- `logs/` is only local runtime state such as `dump1090.log`, feeder status files, and the dashboard key.
