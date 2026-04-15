# Feeding Networks

Flight Tracker can save or manage feeder settings for:

- `FlightAware`
- `airplanes.live`
- `Flightradar24`

For example configs, see:

- `feeders/piaware.conf.example`
- `feeders/fr24feed.ini.example`

The short version:

- `FlightAware` offers two paths:
- `Quick Connect` is the lightweight Windows uploader.
- `Install Official Feeder` now builds and runs PiAware in WSL against Beast on `30005`, which is the full FlightAware MLAT path on this Windows PC.
- `airplanes.live` also offers two paths:
- `Quick Connect` is the lightweight Windows relay.
- `Install Official Feeder` installs the standard airplanes.live runtime in WSL against Beast on `30005` for the normal MLAT path.
- `Flightradar24` can use the saved local/LAN settings or the WSL package install.
- The Beast feed on `30005` now comes directly from `dump1090.exe` and carries decoder timestamps, which is the key requirement for MLAT-capable feeders.
