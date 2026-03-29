# Feeding Networks

Flight Tracker can save or manage feeder settings for:

- `FlightAware`
- `airplanes.live`
- `Flightradar24`

For the full bridge notes and example configs, see:

- `feeders/README.md`
- `feeders/piaware.conf.example`
- `feeders/fr24feed.ini.example`

The short version:

- `FlightAware` and `airplanes.live` have built-in native Windows host connectors in this repo.
- `Flightradar24` currently uses saved local/LAN feed settings rather than a built-in native uploader.
- The local Beast bridge uses synthetic timestamps, so MLAT should stay disabled for Beast-only clients.
