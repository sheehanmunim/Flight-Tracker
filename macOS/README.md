# macOS Launcher

`Run-FlightTracker-Mac.command` is the simple Mac entrypoint during development.

If you want a real Mac app bundle and DMG, run `Build-FlightTracker-MacApp.sh` on a Mac.
That script creates:

- `dist/macos/Flight Tracker.app`
- `dist/macos/FlightTracker.dmg`

The packaged app stores its shared dashboard URL in:

- `~/Library/Application Support/Flight Tracker/flight-tracker-url.txt`

## Setup

1. Start the dashboard on the Windows host with `Run-FlightTracker-Browser.cmd`.
2. The Windows launcher automatically writes a shareable URL to `macOS/flight-tracker-url.txt`.
3. If needed, replace that URL with the correct Windows host IP and the same `?key=...` value.
4. Double-click `Run-FlightTracker-Mac.command` on the Mac.

For the packaged `.app`, the first launch copies a template URL file into the
Application Support folder above. If the file still contains `REPLACE_ME`, the app
opens it in TextEdit so you can paste the shared dashboard URL from the Windows host.

Once open, the dashboard includes the same `Add Feeder To` flow as the Windows host browser view, including the native `Connect On Host` controls for `FlightAware` and `airplanes.live`.

## Important Note

The browser dashboard can control the Windows host and show its status, but it does
not directly attach the RTL-SDR dongle through the browser.

The dongle still has to be plugged into the host machine that is actually running
the SDR decoder.
