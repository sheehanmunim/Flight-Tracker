#!/usr/bin/env python3
"""Native host feeder runtimes for provider-specific uplinks."""

from __future__ import annotations

import argparse
import json
import logging
import os
import tempfile
import selectors
import signal
import socket
import ssl
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


HEARTBEAT = b"\x1a1" + (b"\x00" * 9)
HEARTBEAT_BURST = HEARTBEAT * 5
HEARTBEAT_INTERVAL_SECONDS = 30
CONNECT_TIMEOUT_SECONDS = 10
FLIGHTAWARE_HEALTH_INTERVAL_SECONDS = 300


@dataclass
class RuntimeContext:
    args: argparse.Namespace
    stop_event: threading.Event
    logger: logging.Logger
    last_error: str = ""
    last_status_write_monotonic: float = 0.0
    last_status_payload: str = ""


class BaseRuntime:
    def __init__(self, args: argparse.Namespace) -> None:
        self.context = RuntimeContext(
            args=args,
            stop_event=threading.Event(),
            logger=logging.getLogger("native-feeder"),
        )

    @property
    def args(self) -> argparse.Namespace:
        return self.context.args

    @property
    def logger(self) -> logging.Logger:
        return self.context.logger

    @property
    def stop_event(self) -> threading.Event:
        return self.context.stop_event

    @property
    def last_error(self) -> str:
        return self.context.last_error

    @last_error.setter
    def last_error(self, value: str) -> None:
        self.context.last_error = value

    def run(self) -> int:
        signal.signal(signal.SIGINT, self._handle_signal)
        if hasattr(signal, "SIGTERM"):
            signal.signal(signal.SIGTERM, self._handle_signal)

        self._configure_logging()
        self._ensure_parent_dirs()
        self.logger.info("Starting provider runtime for %s", self.args.provider)

        backoff = 3
        while not self.stop_event.is_set():
            try:
                self._write_status(
                    running=False,
                    state="connecting",
                    summary=self.connecting_summary(),
                    last_error=self.last_error,
                )
                self.run_once()
                backoff = 3
            except Exception as exc:  # noqa: BLE001
                self.last_error = str(exc)
                self.logger.warning("Runtime loop failed: %s", exc)
                self._write_status(
                    running=False,
                    state="reconnecting",
                    summary=self.reconnecting_summary(),
                    last_error=self.last_error,
                )
                self.stop_event.wait(backoff)
                backoff = min(backoff * 2, 30)

        self._write_status(
            running=False,
            state="stopped",
            summary=f"{self.args.provider} feeder runtime stopped on this host.",
            last_error=self.last_error,
        )
        self.logger.info("Provider runtime stopped for %s", self.args.provider)
        return 0

    def connecting_summary(self) -> str:
        return f"Connecting {self.args.provider} to {self.args.target_host}:{self.args.target_port}."

    def reconnecting_summary(self) -> str:
        return f"Retrying {self.args.provider} after a connection problem."

    def run_once(self) -> None:
        raise NotImplementedError

    def _configure_logging(self) -> None:
        logging.basicConfig(
            filename=self.args.log_file,
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
        )

    def _ensure_parent_dirs(self) -> None:
        Path(self.args.log_file).parent.mkdir(parents=True, exist_ok=True)
        Path(self.args.status_file).parent.mkdir(parents=True, exist_ok=True)

    def _handle_signal(self, _signum: int, _frame: object) -> None:
        self.stop_event.set()

    def _open_socket(self, host: str, port: int) -> socket.socket:
        sock = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT_SECONDS)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(None)
        return sock

    def _write_status(
        self,
        *,
        running: bool,
        state: str,
        summary: str,
        last_error: str,
        extra: dict[str, object] | None = None,
        min_interval_seconds: float = 0.0,
    ) -> None:
        payload: dict[str, object] = {
            "providerId": self.args.provider,
            "running": running,
            "state": state,
            "summary": summary,
            "source": f"{self.args.source_host}:{self.args.source_port}",
            "target": f"{self.args.target_host}:{self.args.target_port}",
            "lastError": last_error,
            "updatedAtUtc": datetime.now(timezone.utc).isoformat(),
            "pid": os.getpid(),
        }
        if extra:
            payload.update(extra)

        status_path = Path(self.args.status_file)
        payload_json = json.dumps(payload, indent=2)
        now = time.monotonic()

        if (
            min_interval_seconds > 0
            and payload_json == self.context.last_status_payload
            and now - self.context.last_status_write_monotonic < min_interval_seconds
        ):
            return

        if min_interval_seconds > 0 and now - self.context.last_status_write_monotonic < min_interval_seconds:
            return

        for attempt in range(6):
            temp_path: str | None = None
            try:
                with tempfile.NamedTemporaryFile(
                    "w",
                    encoding="utf-8",
                    delete=False,
                    dir=str(status_path.parent),
                    prefix=status_path.stem + ".",
                    suffix=".tmp",
                ) as handle:
                    handle.write(payload_json)
                    temp_path = handle.name

                os.replace(temp_path, status_path)
                self.context.last_status_payload = payload_json
                self.context.last_status_write_monotonic = time.monotonic()
                return
            except PermissionError as exc:
                if temp_path:
                    try:
                        os.unlink(temp_path)
                    except OSError:
                        pass

                if attempt == 5:
                    self.logger.warning("Skipping status update because the status file is locked: %s", exc)
                    return

                time.sleep(0.15 * (attempt + 1))
            except OSError as exc:
                if temp_path:
                    try:
                        os.unlink(temp_path)
                    except OSError:
                        pass
                self.logger.warning("Skipping status update because the status file could not be replaced: %s", exc)
                return


class BeastRelayRuntime(BaseRuntime):
    def run_once(self) -> None:
        with self._open_socket(self.args.source_host, self.args.source_port) as source, self._open_socket(
            self.args.target_host,
            self.args.target_port,
        ) as target:
            self.logger.info(
                "Connected source %s:%s and target %s:%s",
                self.args.source_host,
                self.args.source_port,
                self.args.target_host,
                self.args.target_port,
            )
            target.sendall(self._build_uuid_packet())
            target.sendall(HEARTBEAT_BURST)

            selector = selectors.DefaultSelector()
            selector.register(source, selectors.EVENT_READ, "source")
            selector.register(target, selectors.EVENT_READ, "target")

            last_send = time.monotonic()
            self._write_status(
                running=True,
                state="connected",
                summary=f"Relaying Beast data from {self.args.source_host}:{self.args.source_port} to {self.args.target_host}:{self.args.target_port}.",
                last_error="",
            )

            try:
                while not self.stop_event.is_set():
                    events = selector.select(timeout=1.0)
                    if not events:
                        if time.monotonic() - last_send >= HEARTBEAT_INTERVAL_SECONDS:
                            target.sendall(HEARTBEAT)
                            last_send = time.monotonic()
                        continue

                    for key, _ in events:
                        if key.data == "source":
                            payload = source.recv(16384)
                            if not payload:
                                raise ConnectionError("Local Beast source closed the connection.")

                            target.sendall(payload)
                            last_send = time.monotonic()
                        else:
                            payload = target.recv(4096)
                            if not payload:
                                raise ConnectionError("Provider closed the feeder connection.")
            finally:
                selector.close()

    def _build_uuid_packet(self) -> bytes:
        state_path = Path(self.args.uuid_file)
        raw_uuid = state_path.read_text(encoding="utf-8").strip() if state_path.exists() else ""
        if not raw_uuid:
            raw_uuid = str(uuid.uuid4())
            state_path.write_text(raw_uuid, encoding="utf-8")

        padded = raw_uuid[:36].ljust(36, "f")
        return b"\x1a\xe4" + padded.encode("ascii", errors="ignore") + b"\x1aWO"


class FlightAwareRuntime(BaseRuntime):
    def __init__(self, args: argparse.Namespace) -> None:
        super().__init__(args)
        self.logged_in_user = "guest"
        self.feeder_id = ""
        self.messages_received = 0
        self.messages_uploaded = 0
        self.started_monotonic = time.monotonic()
        self.pending_source = b""
        self.pending_server = b""
        self.last_health_sent = 0.0
        self.last_alive_clock = 0

    def connecting_summary(self) -> str:
        return "Connecting the native FlightAware uploader and waiting for a feeder ID or login response."

    def reconnecting_summary(self) -> str:
        return "Retrying the native FlightAware uploader after a connection problem."

    def run_once(self) -> None:
        with self._open_socket(self.args.source_host, self.args.source_port) as source, self._open_flightaware_socket() as target:
            self.pending_source = b""
            self.pending_server = b""
            self.messages_received = 0
            self.messages_uploaded = 0
            self.last_health_sent = 0.0
            self.last_alive_clock = 0

            self.logger.info(
                "Connected SBS source %s:%s and FlightAware target %s:%s",
                self.args.source_host,
                self.args.source_port,
                self.args.target_host,
                self.args.target_port,
            )

            self._send_login(target)

            selector = selectors.DefaultSelector()
            selector.register(source, selectors.EVENT_READ, "source")
            selector.register(target, selectors.EVENT_READ, "target")

            self._write_status(
                running=True,
                state="connected",
                summary="Connected to FlightAware and waiting for login confirmation.",
                last_error="",
                extra=self._status_extra(),
            )

            try:
                while not self.stop_event.is_set():
                    events = selector.select(timeout=1.0)
                    if not events:
                        self._maybe_send_health(target)
                        continue

                    for key, _ in events:
                        if key.data == "source":
                            self._process_source(target, source)
                        else:
                            self._process_server(target)

                    self._maybe_send_health(target)
            finally:
                selector.close()

    def _open_flightaware_socket(self) -> ssl.SSLSocket:
        cert_bundle = Path(__file__).with_name("flightaware-ca-bundle.pem")
        if not cert_bundle.exists():
            raise FileNotFoundError(f"FlightAware CA bundle not found: {cert_bundle}")

        context = ssl.create_default_context(cafile=str(cert_bundle))
        raw = socket.create_connection((self.args.target_host, self.args.target_port), timeout=CONNECT_TIMEOUT_SECONDS)
        raw.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        return context.wrap_socket(raw, server_hostname=self.args.target_host)

    def _send_login(self, target: ssl.SSLSocket) -> None:
        login_fields = {
            "type": "login",
            "mac": self._normalized_mac_address(),
            "compression_version": "1.0",
            "connected_host": self.args.target_host,
            "piaware_version": "10.1",
            "piaware_version_full": "FlightTracker native host uploader",
            "image_type": "flighttracker_native",
            "receiver_type": "relay",
            "local_mlat_enable": "no",
            "local_auto_update_enable": "no",
            "local_manual_update_enable": "no",
            "adsbprogram": "dump1090",
            "transprogram": "flighttracker_sbs",
            "feeder_id": self._cached_feeder_tag(),
        }
        self._send_fields(target, login_fields)

    def _process_source(self, target: ssl.SSLSocket, source: socket.socket) -> None:
        payload = source.recv(16384)
        if not payload:
            raise ConnectionError("Local SBS source closed the connection.")

        self.pending_source += payload
        while b"\n" in self.pending_source:
            line_bytes, self.pending_source = self.pending_source.split(b"\n", 1)
            line = line_bytes.strip().decode("utf-8", errors="ignore")
            if not line:
                continue

            row = self._translate_sbs_line(line)
            if not row:
                continue

            self.messages_received += 1
            self._send_fields(target, row)
            self.messages_uploaded += 1

            if self.messages_uploaded == 7:
                self.logger.info("FlightAware uploader has successfully sent several SBS-derived messages.")

            self._write_status(
                running=True,
                state="connected",
                summary=self._connected_summary(),
                last_error="",
                extra=self._status_extra(),
                min_interval_seconds=2.0,
            )

    def _process_server(self, target: ssl.SSLSocket) -> None:
        payload = target.recv(4096)
        if not payload:
            raise ConnectionError("FlightAware closed the feeder connection.")

        self.pending_server += payload
        while b"\n" in self.pending_server:
            line_bytes, self.pending_server = self.pending_server.split(b"\n", 1)
            line = line_bytes.strip().decode("utf-8", errors="ignore")
            if not line:
                continue
            self._handle_server_line(target, line)

    def _handle_server_line(self, target: ssl.SSLSocket, line: str) -> None:
        row = self._parse_tsv_line(line)
        message_type = row.get("type", "")

        if message_type == "login_response":
            if row.get("status") != "ok":
                reason = row.get("reason", "unknown login failure")
                raise ConnectionError(f"FlightAware login failed: {reason}")

            self.logged_in_user = row.get("user", "guest")
            self.feeder_id = row.get("feeder_id", self.feeder_id)
            if self.feeder_id:
                Path(self.args.uuid_file).write_text(self.feeder_id, encoding="utf-8")

            self.logger.info("Logged in to FlightAware as %s", self.logged_in_user)
            if self.feeder_id:
                self.logger.info("FlightAware feeder ID: %s", self.feeder_id)

            self._write_status(
                running=True,
                state="connected",
                summary=self._connected_summary(),
                last_error="",
                extra=self._status_extra(),
            )
            return

        if message_type == "alive":
            now = int(time.time())
            self.last_alive_clock = now
            response = {
                "type": "alive",
                "clock": str(now),
                "offset": str(now - int(row.get("clock", now))),
            }
            self._send_fields(target, response)
            return

        if message_type == "notice":
            self.logger.info("FlightAware notice: %s", row.get("message", "").strip())
            return

        if message_type == "shutdown":
            reason = row.get("reason", "server requested shutdown")
            raise ConnectionError(f"FlightAware requested shutdown: {reason}")

        if message_type.startswith("faup_") or message_type.startswith("mlat_"):
            self.logger.info("FlightAware control message received: %s", message_type)
            return

        if message_type:
            self.logger.info("FlightAware message received: %s", message_type)

    def _maybe_send_health(self, target: ssl.SSLSocket) -> None:
        now = time.monotonic()
        if now - self.last_health_sent < FLIGHTAWARE_HEALTH_INTERVAL_SECONDS:
            return

        health_fields = {
            "type": "health",
            "clock": str(int(time.time())),
            "uptime": str(int(now - self.started_monotonic)),
            "cpuload": "0.0",
            "adsbprogram_running": "1",
            "adsbprogram": "dump1090",
        }
        self._send_fields(target, health_fields)
        self.last_health_sent = now

    def _connected_summary(self) -> str:
        feeder = self.feeder_id if self.feeder_id else "pending"
        return (
            f"Connected to FlightAware as {self.logged_in_user}. "
            f"Feeder ID: {feeder}. Uploaded {self.messages_uploaded} SBS-derived updates from "
            f"{self.args.source_host}:{self.args.source_port}."
        )

    def _status_extra(self) -> dict[str, object]:
        return {
            "user": self.logged_in_user,
            "feederId": self.feeder_id,
            "messagesReceived": self.messages_received,
            "messagesUploaded": self.messages_uploaded,
            "lastAliveClock": self.last_alive_clock,
        }

    def _cached_feeder_tag(self) -> str:
        cache_path = Path(self.args.uuid_file)
        if cache_path.exists():
            feeder_id = cache_path.read_text(encoding="utf-8").strip()
            if feeder_id:
                return f"cache {feeder_id}"
        return "cache {}"

    @staticmethod
    def _normalized_mac_address() -> str:
        raw = uuid.getnode()
        return ":".join(f"{(raw >> shift) & 0xFF:02x}" for shift in range(40, -1, -8))

    @staticmethod
    def _parse_tsv_line(line: str) -> dict[str, str]:
        parts = line.split("\t")
        if len(parts) % 2 != 0:
            return {}
        return {parts[index]: parts[index + 1] for index in range(0, len(parts), 2)}

    @staticmethod
    def _send_fields(target: socket.socket, fields: dict[str, str]) -> None:
        ordered = []
        for key in sorted(fields.keys(), key=str):
            value = str(fields[key]).replace("\t", " ").replace("\n", " ").strip()
            if not value:
                continue
            ordered.extend([key, value])
        target.sendall(("\t".join(ordered) + "\n").encode("utf-8"))

    def _translate_sbs_line(self, line: str) -> dict[str, str] | None:
        parts = [part.strip() for part in line.split(",")]
        if len(parts) < 22 or parts[0] != "MSG":
            return None

        transmission_type = parts[1]
        hexid = parts[4].upper()
        if len(hexid) != 6 or any(ch not in "0123456789ABCDEF" for ch in hexid):
            return None

        row: dict[str, str] = {
            "_v": "4E",
            "clock": str(int(time.time())),
            "hexid": hexid,
            "addrtype": "adsb_icao",
        }

        callsign = parts[10].strip().upper()
        altitude = parts[11].strip()
        ground_speed = parts[12].strip()
        track = parts[13].strip()
        latitude = parts[14].strip()
        longitude = parts[15].strip()
        vertical_rate = parts[16].strip()
        squawk = parts[17].strip()
        emergency_flag = parts[19].strip()
        on_ground = parts[21].strip()

        if callsign:
            row["ident"] = self._meta_value(callsign)

        if squawk and len(squawk) == 4 and squawk.isdigit():
            row["squawk"] = self._meta_value(squawk)

        if altitude and self._is_number(altitude):
            row["alt"] = self._meta_value(str(int(float(altitude))))

        if ground_speed and self._is_number(ground_speed):
            row["speed"] = self._meta_value(f"{float(ground_speed):.1f}")

        if track and self._is_number(track):
            row["track"] = self._meta_value(f"{float(track):.1f}")

        if vertical_rate and self._is_number(vertical_rate):
            row["vrate"] = self._meta_value(str(int(float(vertical_rate))))

        if latitude and longitude and self._is_number(latitude) and self._is_number(longitude):
            row["position"] = self._meta_value(
                "{" + f"{float(latitude):.5f} {float(longitude):.5f} 0 0" + "}"
            )

        if on_ground == "1" or transmission_type == "2":
            row["airGround"] = self._meta_value("G+")
        elif on_ground == "0" or transmission_type in {"3", "4"}:
            row["airGround"] = self._meta_value("A+")

        if emergency_flag == "1":
            row["emergency"] = self._meta_value("general")

        if len(row) <= 4:
            return None

        return row

    @staticmethod
    def _meta_value(value: str, source: str = "A") -> str:
        return f"{value} 0 {source}"

    @staticmethod
    def _is_number(value: str) -> bool:
        try:
            float(value)
        except ValueError:
            return False
        return True


def build_runtime(args: argparse.Namespace) -> BaseRuntime:
    provider = args.provider.lower()
    if provider == "airplanes-live":
        return BeastRelayRuntime(args)
    if provider == "flightaware":
        return FlightAwareRuntime(args)
    raise ValueError(f"Unsupported native feeder runtime provider: {args.provider}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a provider-specific feeder runtime.")
    parser.add_argument("--provider", required=True)
    parser.add_argument("--source-host", required=True)
    parser.add_argument("--source-port", required=True, type=int)
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-port", required=True, type=int)
    parser.add_argument("--uuid-file", required=True)
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--status-file", required=True)
    return parser.parse_args()


def main() -> int:
    runtime = build_runtime(parse_args())
    return runtime.run()


if __name__ == "__main__":
    sys.exit(main())
