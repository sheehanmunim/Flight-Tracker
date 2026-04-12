# Install Guide

## Fastest Path

If you just want to use Flight Tracker and not work inside the repo:

1. Download `FlightTracker-Setup.exe` from the latest build or release.
2. Run the installer.
3. Launch `Flight Tracker` from the Start Menu or desktop shortcut.
4. Plug the RTL-SDR USB dongle into that same Windows machine.

If you want the browser-host mode instead:

1. Install the same Windows app.
2. Open `Flight Tracker Browser Host` from the Start Menu.
3. Open the local browser window it launches.

If you want the portable Windows version instead:

1. Download the Windows ZIP.
2. Extract it anywhere you want.
3. Double-click `FlightTracker\Desktop\FlightTracker.exe` or `FlightTracker\Run-FlightTracker-Windows.cmd`.

If you want the Mac client:

1. Download the Mac DMG.
2. Open the app on the Mac.
3. Paste the shared dashboard URL from the Windows host when prompted.

## From Source

Use these entrypoints in the repo:

- `Run-FlightTracker-Windows.cmd`
- `Run-FlightTracker-Browser.cmd`
- `macOS/Run-FlightTracker-Mac.command`

## What Still Has To Be On Windows

- The RTL-SDR USB dongle
- The dump1090 and RTL-SDR binaries, which are already bundled in this repo/package
- In some setups, the correct RTL-SDR driver on first use
