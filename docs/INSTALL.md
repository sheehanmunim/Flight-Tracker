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

If you want the Mac client:

1. Download the Mac DMG.
2. Open the app on the Mac.
3. Paste the shared dashboard URL from the Windows host when prompted.

## From Source

Use these three commands in the repo root:

- `Browser.cmd`
- `Browser.command`
- `Chromium.command`
- `Chrome-Direct.command`
- `Windows-EXE.cmd`
- `./Mac-DMG.command`

## Mac Host Mode

If you want the Mac itself to be the receiver host:

1. Install `readsb` on the Mac.
2. Plug the RTL-SDR USB dongle into that same Mac.
3. Run `Browser.command`.
4. Open the local browser dashboard it starts.

The Mac host path expects a local `readsb` binary on `PATH`. `brew install readsb` is the simplest path on current macOS systems.

If you want the same local Mac host in a standalone Chromium-family app window instead of a normal browser tab, run `Chromium.command`.

Neither of those Mac paths requires a Windows machine.

## Windows Host Notes

- The RTL-SDR USB dongle
- The dump1090 and RTL-SDR binaries, which are already bundled in this repo/package
- In some setups, the correct RTL-SDR driver on first use
