# macOS Launcher

`FlightTrackerMac.command` opens the browser dashboard hosted by your Windows flight tracker machine.

## Setup

1. Start the dashboard on the Windows host with `FlightTrackerWeb.cmd`.
2. The Windows launcher automatically writes a shareable URL to `macOS/flight-tracker-url.txt`.
3. If needed, replace that URL with the correct Windows host IP and the same `?key=...` value.
4. Double-click `FlightTrackerMac.command` on the Mac.

## Important Note

The browser dashboard can control the Windows host and show its status, but it does
not directly attach the RTL-SDR dongle through the browser.

The dongle still has to be plugged into the host machine that is actually running
the SDR decoder.
