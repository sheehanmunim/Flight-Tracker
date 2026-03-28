# Feeding FlightAware, airplanes.live, and Flightradar24

This Windows tracker already publishes useful network feeds:

- Local map: `http://localhost:8080`
- RAW/AVR TCP output: `localhost:30002`
- SBS/BaseStation TCP output: `localhost:30003`

## Recommended Layout

Use this Windows project as the receiver/decoder, then add one small Linux sidecar for feeder software.

That sidecar can be:

- a lightweight Debian or Ubuntu VM
- Docker Desktop with Linux containers
- a separate Raspberry Pi or Linux mini PC

## Why The Sidecar Helps

`dump1090.exe` in this repo exposes RAW (`30002`) and SBS (`30003`), but not Beast output (`30005`).

That matters because:

- FlightAware PiAware expects Beast-format TCP for external receivers.
- airplanes.live expects a Linux receiver install and checks Beast and MLAT connections.
- Flightradar24 can use the existing Windows feed directly, but using the same Beast bridge keeps all three services aligned.

## Bridge With readsb

Install `readsb` in the Linux sidecar and point it at this Windows tracker's RAW output.

If the sidecar runs under Docker Desktop on the same PC, use `host.docker.internal`.
If it runs in a separate VM or on another machine, replace that with your Windows host IP.

Example command:

```bash
readsb \
  --net-only \
  --net \
  --net-connector host.docker.internal,30002,raw_in \
  --net-ro-port 30002 \
  --net-sbs-port 30003 \
  --net-bi-port 30004,30104 \
  --net-bo-port 30005
```

After that bridge is running:

- Beast output is available on `127.0.0.1:30005` inside the Linux sidecar.
- SBS output is available on `127.0.0.1:30003` inside the Linux sidecar.

## FlightAware

Install PiAware in the Linux sidecar, then point it at the local Beast bridge.

For a package install, use settings like this in `piaware.conf`:

```ini
receiver-type other
receiver-host 127.0.0.1
receiver-port 30005
allow-mlat yes
```

See [piaware.conf.example](./piaware.conf.example).

## Flightradar24

Install the official `fr24feed` package in the Linux sidecar and point it at the same Beast bridge.

Use settings like:

```ini
receiver="beast-tcp"
host="127.0.0.1:30005"
bs="no"
raw="no"
mlat="yes"
```

See [fr24feed.ini.example](./fr24feed.ini.example).

## airplanes.live

Once `readsb` is running in the Linux sidecar, follow the existing-receiver guide from airplanes.live:

- `https://airplanes.live/how-to-feed/`

Their install flow is designed to work with an existing Linux receiver such as `readsb` or `dump1090-fa`.

## Official References

- FlightAware PiAware advanced receiver settings:
  `https://www.flightaware.com/adsb/piaware/advanced_configuration`
- Flightradar24 feeder manual:
  `https://www.flightradar24.com/blog/wp-content/uploads/2023/02/fr24feed-manual.pdf`
- airplanes.live feed guide:
  `https://airplanes.live/how-to-feed/`
- readsb network connector reference:
  `https://github.com/wiedehopf/readsb`
