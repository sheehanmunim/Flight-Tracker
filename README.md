# Flight Tracker Build

This folder is a practical setup for what you described:

- 1 antenna
- 1 RTL-SDR USB dongle
- local flight tracking
- feeding FlightAware
- feeding Flightradar24
- feeding airplanes.live

## Best Path

Your current Windows + Zadig setup is fine for testing the dongle, but it is not the best final host if you want to feed all three services reliably.

The clean setup is:

1. Antenna -> RTL-SDR dongle
2. RTL-SDR dongle -> Raspberry Pi 4/5 or a small Debian/Ubuntu Linux box
3. One decoder on that Linux host
4. Three feeder clients using the same decoded data

Recommended stack:

- `dump1090-fa` for 1090 MHz ADS-B decoding
- `piaware` for FlightAware
- `fr24feed` for Flightradar24
- `airplanes.live` feed client

If you are in the United States and also want 978 UAT, add a second SDR and install `dump978-fa`.

## Why I Recommend Linux/Pi

FlightAware's supported feeder path is PiAware on Raspberry Pi / Linux package installs, while Flightradar24 and airplanes.live both support adding their feeders onto an existing Linux ADS-B receiver. That means one Pi can do the whole job cleanly.

## Fastest Working Build

### Option A: Raspberry Pi OS Lite on a Pi 4/5

This is the simplest path if you are starting fresh.

1. Flash Raspberry Pi OS Lite to an SD card.
2. Boot the Pi and connect it to Ethernet or Wi-Fi.
3. Plug in the SDR dongle.
4. SSH into the Pi.

Then install the base receiver:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

After reboot:

```bash
wget https://www.flightaware.com/adsb/piaware/files/packages/pool/piaware/f/flightaware-apt-repository/flightaware-apt-repository_1.2_all.deb
sudo dpkg -i flightaware-apt-repository_1.2_all.deb
sudo apt update
sudo apt install -y piaware dump1090-fa
sudo reboot
```

Then add Flightradar24:

```bash
wget -qO- https://fr24.com/install.sh | sudo bash -s
```

During the FR24 setup:

- choose the existing decoder if it detects `dump1090`
- enter your exact latitude, longitude, and antenna altitude
- use autoconfig when offered

Then add airplanes.live:

```bash
curl -L -o /tmp/feed.sh https://raw.githubusercontent.com/airplanes-live/feed/main/install.sh
sudo bash /tmp/feed.sh
```

### Option B: Small Debian box

If you do not want to buy a Pi, an old mini PC or thin client running Debian can do the same job. The setup idea is identical: one decoder, multiple feeders.

## Local Tracking

Once `dump1090-fa` is running, your local aircraft map is usually available from:

```text
http://PI-IP-ADDRESS/skyaware/
```

Use your Pi's actual IP address in place of `PI-IP-ADDRESS`.

## What To Verify

Check the services:

```bash
sudo systemctl status dump1090-fa
sudo systemctl status piaware
sudo systemctl status fr24feed
```

Check FlightAware claim page after a few minutes:

```text
https://flightaware.com/adsb/piaware/claim
```

Check airplanes.live status:

```text
https://airplanes.live/myfeed/
```

For airplanes.live network checks:

```bash
netstat -t -n | grep -E '30004|31090'
```

## Important Notes

- Use precise coordinates and antenna altitude if you enable MLAT.
- For U.S. 978 UAT, you need a second SDR. One dongle cannot do 1090 and 978 at the same time.
- If you keep using the Windows machine for now, treat it as a test environment, not the final always-on feeder host.
- If you want the most stable setup, keep the feeder box wired to Ethernet and place the antenna as high and clear as possible.

## Suggested Shopping List

If you only have the dongle and antenna today, the easiest reliable build is:

- Raspberry Pi 4 or 5
- quality power supply
- microSD card or SSD
- Ethernet cable
- optional external filtered ADS-B antenna if your current antenna is temporary

## Next Step

Run the PowerShell checker in [scripts/Test-FlightTrackerHost.ps1](C:/Users/busin/OneDrive/Documents/Flight%20Tracker/scripts/Test-FlightTrackerHost.ps1) on your current Windows PC. It will tell you whether this machine should stay a test box or whether you still need a Pi/Linux host to finish the build.
