# macOS Launcher

`FlightTrackerMac.command` opens the browser dashboard hosted by your Windows flight tracker machine.

## Setup

1. Start the dashboard on the Windows host with `FlightTrackerWeb.cmd`.
2. Copy the full dashboard URL, including the `?key=...` query string.
3. Put that URL into `macOS/flight-tracker-url.txt`.
4. Double-click `FlightTrackerMac.command` on the Mac.

## Important Note

The browser dashboard can control the Windows host and show its status, but it does
not directly attach the RTL-SDR dongle through the browser.

The dongle still has to be plugged into the host machine that is actually running
the SDR decoder.
