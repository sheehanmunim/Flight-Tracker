# Flight Tracker

This project is now intentionally narrow:

- plug in one RTL-SDR USB dongle
- run one start command
- see nearby planes on a local web page

It can also expose local network outputs from `dump1090`, but it is still not a full
multi-feeder Linux stack.

## Start

1. Plug in your RTL-SDR dongle and antenna.
2. Use exactly one launcher for the way you want to work:

- Windows desktop app: `Run-FlightTracker-Windows.cmd`
- Browser dashboard host: `Run-FlightTracker-Browser.cmd`
- Mac client opener: `macOS/Run-FlightTracker-Mac.command`

If the map does not open, go to `http://localhost:8080`.

## What This Uses

- `vendor/Dump1090/dump1090.exe` for decoding ADS-B
- Tar1090 for the local aircraft map
- a small PowerShell wrapper for Windows startup checks
- a small WinForms launcher app for one-click control on Windows

## Windows App

`Run-FlightTracker-Windows.cmd` launches the Windows desktop app. It builds and launches a small app that can:

- start the tracker
- stop the tracker
- refresh status
- add feeder profiles for FlightAware, Flightradar24, and airplanes.live
- open the local map
- open the feeder guide
- open logs

If the .NET 8 SDK is not already available, the launcher installs it to
`%USERPROFILE%\.dotnet` using Microsoft's official `dotnet-install.ps1` script.

## Browser Dashboard

`Run-FlightTracker-Browser.cmd` starts the browser dashboard on port `5099` and opens it with an access key in the URL.

The dashboard can:

- start the tracker
- stop the tracker
- refresh tracker status
- add feeder profiles from an `Add Feeder To` dropdown
- run the host check
- show recent dump1090 and Beast bridge logs
- open the map on the same host

Added feeder profiles are saved on the host, so the browser dashboard and the Windows app stay in sync.

It binds to `0.0.0.0:5099`, so you can also open it from another device on your LAN
if you use the Windows host's IP address and include the same `?key=...` query value.

## Browser USB Note

The browser dashboard does not directly attach the RTL-SDR dongle.

The dongle still has to be plugged into the machine that is actually running the
decoder. The browser controls that host, but it does not replace the host OS USB layer.

## macOS Launcher

`macOS/Run-FlightTracker-Mac.command` opens the browser dashboard from a Mac.

It is a lightweight launcher for the hosted dashboard, not a native macOS SDR decoder. See `macOS/README.md` for setup.
Because the Mac client opens the same dashboard, it includes the same `Add Feeder To` UI as the browser host view.

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
- Run the Windows app or browser dashboard and use the status view to confirm Windows can see the device.

`The SDR is busy`

- Close other SDR apps such as SDR#, dump1090, rtl_test, or Virtual Radar tools.
- Stop the tracker from the Windows app or browser dashboard, then launch your entrypoint again.

`Port 8080 is already in use`

- Another app is already using the local web port.
- Open the Windows app or browser dashboard and refresh status to see what is listening.

`The map still does not open`

- Open `http://localhost:8080` manually.
- Check `logs/dump1090.log` for the last startup error.

## Main Files

- `Run-FlightTracker-Windows.cmd`: the Windows launcher
- `Run-FlightTracker-Browser.cmd`: the browser dashboard launcher
- `macOS/Run-FlightTracker-Mac.command`: the Mac opener for the hosted dashboard
- `dump1090-local.cfg`: local config overrides
- `feeders/README.md`: optional bridge guide for FlightAware, airplanes.live, and Flightradar24
- `scripts/*.ps1`: internal start, stop, status, and host-check scripts used by the app and dashboard
