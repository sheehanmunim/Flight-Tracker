#!/usr/bin/env python3
"""Native host feeder runtime for provider-managed TCP relays."""

from __future__ import annotations

import argparse
import json
import logging
import os
import selectors
import signal
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path


HEARTBEAT = b"\x1a1" + (b"\x00" * 9)
HEARTBEAT_BURST = HEARTBEAT * 5
HEARTBEAT_INTERVAL_SECONDS = 30
CONNECT_TIMEOUT_SECONDS = 10


class FeederRuntime:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.stop_event = threading.Event()
        self.logger = logging.getLogger("native-feeder")
        self.last_error = ""

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
                    summary=f"Connecting {self.args.provider} to {self.args.target_host}:{self.args.target_port}.",
                    last_error=self.last_error,
                )
                self._relay_once()
                backoff = 3
            except Exception as exc:  # noqa: BLE001
                self.last_error = str(exc)
                self.logger.warning("Relay loop failed: %s", exc)
                self._write_status(
                    running=False,
                    state="reconnecting",
                    summary=f"Retrying {self.args.provider} after a connection problem.",
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

    def _relay_once(self) -> None:
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
        raw_uuid = Path(self.args.uuid_file).read_text(encoding="utf-8").strip()
        if not raw_uuid:
            raise ValueError(f"UUID file is empty: {self.args.uuid_file}")

        padded = raw_uuid[:36].ljust(36, "f")
        return b"\x1a\xe4" + padded.encode("ascii", errors="ignore") + b"\x1aWO"

    def _open_socket(self, host: str, port: int) -> socket.socket:
        sock = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT_SECONDS)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(None)
        return sock

    def _write_status(self, *, running: bool, state: str, summary: str, last_error: str) -> None:
        payload = {
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
        status_path = Path(self.args.status_file)
        status_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Relay local Beast data to a provider endpoint.")
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
    runtime = FeederRuntime(parse_args())
    return runtime.run()


if __name__ == "__main__":
    sys.exit(main())
