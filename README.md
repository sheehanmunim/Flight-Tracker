# Flight Tracker

This project is now intentionally narrow:

- plug in one RTL-SDR USB dongle
- run one start command
- see nearby planes on a local web page

It can also expose local network outputs from `dump1090`, but it is still not a full
multi-feeder Linux stack.

## Start

1. Plug in your RTL-SDR dongle and antenna.
2. Double-click `Start-LocalFlightTracker.cmd`.
3. If the browser does not open, go to `http://localhost:8080`.

To stop it, run `Stop-LocalFlightTracker.cmd`.

To check what Windows sees, run `Status-LocalFlightTracker.cmd`.

## What This Uses

- `vendor/Dump1090/dump1090.exe` for decoding ADS-B
- Tar1090 for the local aircraft map
- a small PowerShell wrapper for Windows startup checks

## Feed Outputs

When the tracker is running, this Windows setup exposes:

- `http://localhost:8080` for the local Tar1090 map
- `127.0.0.1:30002` for AVR/raw TCP output
- `127.0.0.1:30003` for SBS/BaseStation TCP output

This bundled Windows `dump1090` build does not expose Beast TCP on `30005`.

## Feeding Other Networks

`Flightradar24`

- This is the one that can use the current Windows output directly.
- Their support docs say `receiver="avr-tcp"` with `host="127.0.0.1:30002"` is valid, or
  `receiver="beast-tcp"` with `host="127.0.0.1:30005"` if you have a Beast source.

`FlightAware`

- PiAware's advanced configuration says external receivers must provide Beast binary
  format over TCP for `receiver-type "relay"` or `receiver-type "other"`.
- Because this Windows project does not provide Beast on `30005`, it is not enough on
  its own for a direct FlightAware feed.

`airplanes.live`

- The official feed scripts say a decoder such as `readsb` must already be installed.
- Their setup defaults to `INPUT="127.0.0.1:30005"`, which is again a Beast source.

## Recommended Path For All Three

If your goal is to feed `FlightAware`, `airplanes.live`, and `Flightradar24` together,
use a Raspberry Pi or Debian/Ubuntu box as the always-on feeder host and run a
Beast-capable decoder there, typically `readsb` or `dump1090-fa`.

Use this Windows repo for:

- verifying the dongle works
- viewing a local map
- optionally feeding `Flightradar24` from `127.0.0.1:30002`

Move to a Linux feeder host for:

- `FlightAware` via PiAware
- `airplanes.live` via their official feed scripts
- `Flightradar24` alongside the other two from the same Beast source

For a concrete bridge layout and example configs, see `feeders/README.md`.

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

- `Start-LocalFlightTracker.cmd`: starts the local tracker
- `Stop-LocalFlightTracker.cmd`: stops the local tracker
- `Status-LocalFlightTracker.cmd`: prints hardware and web status
- `dump1090-local.cfg`: local config overrides
- `feeders/README.md`: optional bridge guide for FlightAware, airplanes.live, and Flightradar24
