# Flight Tracker

This project is now intentionally narrow:

- plug in one RTL-SDR USB dongle
- run one start command
- see nearby planes on a local web page

It can also expose local network outputs from `dump1090`, but it is still not a full
multi-feeder Linux stack.

## Start

1. Plug in your RTL-SDR dongle and antenna.
2. For the desktop app, double-click `FlightTrackerApp.cmd`.
3. For the original script-only flow, double-click `Start-LocalFlightTracker.cmd`.
4. For the browser dashboard, double-click `FlightTrackerWeb.cmd`.
5. If the browser does not open, go to `http://localhost:8080`.

To stop it, run `Stop-LocalFlightTracker.cmd`.

To check what Windows sees, run `Status-LocalFlightTracker.cmd`.

## What This Uses

- `vendor/Dump1090/dump1090.exe` for decoding ADS-B
- Tar1090 for the local aircraft map
- a small PowerShell wrapper for Windows startup checks
- a small WinForms launcher app for one-click control on Windows

## Windows App

`FlightTrackerApp.cmd` builds and launches a small Windows desktop app that can:

- start the tracker
- stop the tracker
- refresh status
- open the local map
- open the feeder guide
- open logs

If the .NET 8 SDK is not already available, the launcher installs it to
`%USERPROFILE%\.dotnet` using Microsoft's official `dotnet-install.ps1` script.

## Browser Dashboard

`FlightTrackerWeb.cmd` starts a local browser dashboard on port `5099` and opens it
with an access key in the URL.

The dashboard can:

- start the tracker
- stop the tracker
- refresh tracker status
- run the host check
- show recent dump1090 and Beast bridge logs
- open the map on the same host

It binds to `0.0.0.0:5099`, so you can also open it from another device on your LAN
if you use the Windows host's IP address and include the same `?key=...` query value.

## Browser USB Note

The browser dashboard does not directly attach the RTL-SDR dongle.

The dongle still has to be plugged into the machine that is actually running the
decoder. The browser controls that host, but it does not replace the host OS USB layer.

## macOS Launcher

The `macOS/FlightTrackerMac.command` helper opens the browser dashboard from a Mac.

It is a lightweight launcher for the hosted dashboard, not a native macOS SDR decoder.
See `macOS/README.md` for setup.

## Feed Outputs

When the tracker is running, this Windows setup exposes:

- `http://localhost:8080` for the local Tar1090 map
- `127.0.0.1:30002` for AVR/raw TCP output
- `127.0.0.1:30003` for SBS/BaseStation TCP output
- `127.0.0.1:30005` for a local Beast bridge fed from `30002`

The Beast bridge uses synthetic 12 MHz timestamps generated on the Windows host.
That is enough for software that requires Beast framing, but it should not be
expected to produce useful MLAT results.

## Feeding Other Networks

`Flightradar24`

- This is the one that can use the current Windows output directly.
- Their support docs say `receiver="avr-tcp"` with `host="127.0.0.1:30002"` is valid, or
  `receiver="beast-tcp"` with `host="127.0.0.1:30005"` if you have a Beast source.

`FlightAware`

- PiAware's advanced configuration says external receivers must provide Beast binary
  format over TCP for `receiver-type "relay"` or `receiver-type "other"`.
- This project now provides a local Beast bridge on `127.0.0.1:30005`.
- Keep `allow-mlat no` with this bridge, because the timestamps are synthetic.

`airplanes.live`

- The official feed scripts say a decoder such as `readsb` must already be installed.
- Their setup defaults to `INPUT="127.0.0.1:30005"`, which matches the local Beast bridge here.
- Keep MLAT disabled with this bridge.

## Recommended Path For All Three

If your goal is to feed `FlightAware`, `airplanes.live`, and `Flightradar24` together,
use a Raspberry Pi or Debian/Ubuntu box as the always-on feeder host and run a
Beast-capable decoder there, typically `readsb` or `dump1090-fa`.

Use this Windows repo for:

- verifying the dongle works
- viewing a local map
- feeding Beast-only clients from `127.0.0.1:30005`
- optionally feeding `Flightradar24` from `127.0.0.1:30002` or `127.0.0.1:30005`

Move to a Linux feeder host for:

- `FlightAware` via PiAware
- `airplanes.live` via their official feed scripts
- `Flightradar24` alongside the other two from the same Beast source

For a concrete bridge layout and example configs, see `feeders/README.md`.

## Feeder Prerequisite Note

The local Beast bridge is ready on Windows now.

The remaining blocker for official `FlightAware` and `airplanes.live` feeder-daemon
installation on this machine is WSL itself: if `wsl --status` reports that the WSL 2
kernel is missing, repairing or installing the WSL package requires administrator
privileges before Debian can be installed.

## Troubleshooting

`No RTL-SDR dongle detected`

- Unplug and reconnect the USB dongle.
- Try another USB port.
- Run `Status-LocalFlightTracker.cmd` to confirm Windows can see the device.

`The SDR is busy`

- Close other SDR apps such as SDR#, dump1090, rtl_test, or Virtual Radar tools.
- Run `Stop-LocalFlightTracker.cmd` and start again.

`Port 8080 is already in use`

- Another app is already using the local web port.
- Run `Status-LocalFlightTracker.cmd` to see what is listening.

`The map still does not open`

- Open `http://localhost:8080` manually.
- Check `logs/dump1090.log` for the last startup error.

## Files

- `FlightTrackerApp.cmd`: builds and launches the Windows desktop app
- `FlightTrackerWeb.cmd`: starts the browser dashboard
- `Start-LocalFlightTracker.cmd`: starts the local tracker
- `Stop-LocalFlightTracker.cmd`: stops the local tracker
- `Status-LocalFlightTracker.cmd`: prints hardware and web status
- `dump1090-local.cfg`: local config overrides
- `feeders/README.md`: optional bridge guide for FlightAware, airplanes.live, and Flightradar24
- `macOS/FlightTrackerMac.command`: opens the dashboard from a Mac
