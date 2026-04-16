# Install Guide

## Fastest Path

If you just want to use Flight Tracker and not work inside the repo:

1. Download `FlightTracker-Setup.exe` from the latest build or release.
2. Run the installer.
3. Launch `Flight Tracker` from the Start Menu or desktop shortcut.
4. Use the dedicated Windows app window with the dashboard embedded inside it.
5. Plug the RTL-SDR USB dongle into that same Windows machine.

If you want the browser-host mode instead:

1. Install the same Windows app.
2. Open `Flight Tracker Browser Host` from the Start Menu.
3. Open the local browser window it launches.

If you want the Mac client:

1. Download the Mac DMG.
2. Open the app on the Mac.
3. Paste the shared or local dashboard URL into the app when prompted.
4. Use the dedicated Mac app window with the dashboard embedded inside it.

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

1. Install Homebrew on the Mac if it is not already installed.
2. Plug the RTL-SDR USB dongle into that same Mac.
3. Run `Browser.command` or `Chromium.command`.
4. Let the script auto-install `readsb` on first run if needed.
5. Open the local browser dashboard or Chromium app window it starts.

The Mac host path uses a local `readsb` binary. `Browser.command` and `Chromium.command` now try to install it automatically with Homebrew on first run. If Homebrew is not installed yet, install it from `https://brew.sh` and rerun the launcher.

If you want the same local Mac host in a standalone Chromium-family app window instead of a normal browser tab, run `Chromium.command`. That is the supported standalone Chromium path today.

Neither of those Mac paths requires a Windows machine.

## Browser-Only Receiver

If you want the browser itself to read the USB dongle and decode ADS-B without the native Windows or Mac decoder:

1. Open the `Browser-Only Receiver` link from the dashboard, or serve `apps/windows/DashboardHost/wwwroot/chrome-direct.html` from any secure `https://` or `http://localhost` web origin.
2. Use desktop Chromium or Chrome.
3. Plug the RTL-SDR USB dongle into that same computer.
4. Press `Start Browser Receiver` and authorize the dongle when Chromium prompts for USB access.

The browser-only receiver path decodes ADS-B directly in the page with WebUSB. It does not rely on `dump1090.exe` or `readsb`, but it does require a secure browser context and a Chromium-family browser with WebUSB support.

## Windows Host Notes

- The RTL-SDR USB dongle
- The dump1090 and RTL-SDR binaries, which are already bundled in this repo/package
- In some setups, the correct RTL-SDR driver on first use
- The dedicated Windows app uses WebView2 to render the dashboard inside the app window.
