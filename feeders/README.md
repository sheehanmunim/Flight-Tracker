# Feeder Bridge Notes

This repo now exposes three useful local outputs:

- `127.0.0.1:30002` as AVR/raw
- `127.0.0.1:30003` as SBS/BaseStation
- `127.0.0.1:30005` as Beast binary

`30005` is produced by `scripts/Dump1090BeastBridge.py`, which converts the
AVR/raw stream from `30002` into Beast frames with synthetic 12 MHz timestamps.

## Important Limitation

This bridge is for ADS-B message transport, not real MLAT timing.

- Use `30005` when a feeder client insists on Beast format.
- Disable MLAT in the feeder client when using this bridge.

## Flightradar24

FR24 can use either:

- `receiver="avr-tcp"` with `host="127.0.0.1:30002"`
- `receiver="beast-tcp"` with `host="127.0.0.1:30005"`

Recommended with this repo:

- leave `mlat="no"`

## FlightAware

This repo now includes a native Windows-side FlightAware uploader.

It:

- logs into `piaware.flightaware.com:1200` over TLS
- requests or reuses a cached feeder ID automatically
- uploads SBS-derived aircraft updates from `127.0.0.1:30003`

If you want to use PiAware on Linux, WSL, or another host instead, point it at the Beast bridge:

```text
receiver-type other
receiver-host 127.0.0.1
receiver-port 30005
allow-mlat no
```

If PiAware is not on the same machine, replace `127.0.0.1` with the Windows host IP.

## airplanes.live

This repo now includes a native Windows-side connector for `airplanes.live`.

It relays:

- from `127.0.0.1:30005`
- to `feed.airplanes.live:30004`

If you want to use their own tooling on another host instead, point it at:

```text
INPUT="127.0.0.1:30005"
```

Disable MLAT during setup when using this bridge.

## Scope

This repo provides:

- the local decoder
- the local Beast bridge
- a native Windows host connector for `FlightAware`
- a native Windows host connector for `airplanes.live`

It does not install or manage:

- PiAware
- fr24feed
- account signup or sharing keys

## Windows Host Note

If you plan to run the feeder daemons inside WSL on the same Windows PC, WSL itself
must be healthy first.

- If `wsl --status` says the WSL 2 kernel is missing, fixing that requires an
  administrator-level WSL repair or install before Debian can run.
