# Flight Tracker

This project is now intentionally narrow:

- plug in one RTL-SDR USB dongle
- run one start command
- see nearby planes on a local web page

It does not try to set up feeder services, Raspberry Pi workflows, or cloud accounts.

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

