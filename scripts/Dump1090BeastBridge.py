#!/usr/bin/env python3
"""Bridge dump1090 AVR/raw output to a local Beast-format TCP port.

This is intentionally simple:
- reads raw frames from dump1090 on tcp://127.0.0.1:30002
- republishes them as Beast binary on tcp://127.0.0.1:30005
- generates synthetic 12 MHz timestamps from the local monotonic clock

The synthetic timestamps are good enough for software that only requires
Beast framing, but they are not SDR-grade timestamps and should not be
expected to produce useful MLAT results.
"""

from __future__ import annotations

import argparse
import logging
import os
import signal
import socket
import threading
import time
from typing import Iterable


RAW_HEARTBEAT = b"*0000;"
BEAST_MARKER = 0x1A
BEAST_ESCAPE = bytes((BEAST_MARKER, BEAST_MARKER))
BEAST_MAX_TS = (1 << 48) - 1
BEAST_SIGNAL = 0x80


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-host", default="127.0.0.1")
    parser.add_argument("--source-port", type=int, default=30002)
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, default=30005)
    parser.add_argument("--retry-seconds", type=float, default=2.0)
    parser.add_argument("--log-file", default="")
    parser.add_argument("--pid-file", default="")
    parser.add_argument("--log-level", default="INFO")
    return parser


def configure_logging(log_file: str, log_level: str) -> None:
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    if log_file:
        handlers.append(logging.FileHandler(log_file, encoding="utf-8"))

    logging.basicConfig(
        level=getattr(logging, log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=handlers,
    )


def beast_timestamp() -> int:
    return (time.monotonic_ns() * 12 // 1000) & BEAST_MAX_TS


def escape_beast_bytes(data: bytes) -> bytes:
    return data.replace(bytes((BEAST_MARKER,)), BEAST_ESCAPE)


def encode_beast_frame(message: bytes) -> bytes:
    if len(message) == 2:
        frame_type = b"1"
    elif len(message) == 7:
        frame_type = b"2"
    elif len(message) == 14:
        frame_type = b"3"
    else:
        raise ValueError(f"Unsupported message length: {len(message)}")

    timestamp = beast_timestamp().to_bytes(6, "big")
    signal = bytes((BEAST_SIGNAL,))
    payload = escape_beast_bytes(timestamp + signal + message)
    return bytes((BEAST_MARKER,)) + frame_type + payload


class ClientRegistry:
    def __init__(self) -> None:
        self._clients: set[socket.socket] = set()
        self._lock = threading.Lock()

    def add(self, client: socket.socket) -> None:
        client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        with self._lock:
            self._clients.add(client)

    def remove(self, client: socket.socket) -> None:
        with self._lock:
            self._clients.discard(client)
        try:
            client.close()
        except OSError:
            pass

    def broadcast(self, frame: bytes) -> None:
        dead_clients: list[socket.socket] = []
        with self._lock:
            clients = tuple(self._clients)

        for client in clients:
            try:
                client.sendall(frame)
            except OSError:
                dead_clients.append(client)

        for client in dead_clients:
            logging.warning("Removing disconnected Beast client")
            self.remove(client)


class BeastBridge:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.clients = ClientRegistry()
        self.stop_event = threading.Event()
        self.server_socket: socket.socket | None = None
        self.accept_thread: threading.Thread | None = None

    def run(self) -> int:
        self.server_socket = socket.create_server(
            (self.args.listen_host, self.args.listen_port),
            family=socket.AF_INET,
            backlog=8,
            reuse_port=False,
        )
        self.server_socket.settimeout(1.0)

        logging.info(
            "Beast bridge listening on tcp://%s:%s and reading AVR from tcp://%s:%s",
            self.args.listen_host,
            self.args.listen_port,
            self.args.source_host,
            self.args.source_port,
        )
        self.write_pid_file()

        self.accept_thread = threading.Thread(target=self.accept_loop, name="accept-loop", daemon=True)
        self.accept_thread.start()

        try:
            self.source_loop()
        finally:
            self.stop_event.set()
            if self.server_socket is not None:
                try:
                    self.server_socket.close()
                except OSError:
                    pass
            self.remove_pid_file()

        return 0

    def write_pid_file(self) -> None:
        if not self.args.pid_file:
            return

        with open(self.args.pid_file, "w", encoding="ascii") as handle:
            handle.write(str(os.getpid()))

    def remove_pid_file(self) -> None:
        if not self.args.pid_file:
            return

        try:
            if os.path.exists(self.args.pid_file):
                os.remove(self.args.pid_file)
        except OSError:
            logging.warning("Unable to remove pid file %s", self.args.pid_file)

    def accept_loop(self) -> None:
        assert self.server_socket is not None

        while not self.stop_event.is_set():
            try:
                client, address = self.server_socket.accept()
            except socket.timeout:
                continue
            except OSError:
                break

            logging.info("Beast client connected from %s:%s", address[0], address[1])
            self.clients.add(client)

    def source_loop(self) -> None:
        while not self.stop_event.is_set():
            try:
                with socket.create_connection((self.args.source_host, self.args.source_port), timeout=5.0) as sock:
                    sock.settimeout(1.0)
                    logging.info(
                        "Connected to AVR source tcp://%s:%s",
                        self.args.source_host,
                        self.args.source_port,
                    )
                    self.stream_source(sock)
            except OSError as exc:
                if self.stop_event.is_set():
                    break
                logging.warning("AVR source connection failed: %s", exc)
                time.sleep(self.args.retry_seconds)

    def stream_source(self, sock: socket.socket) -> None:
        buffer = bytearray()

        while not self.stop_event.is_set():
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                continue

            if not chunk:
                logging.warning("AVR source disconnected")
                return

            buffer.extend(chunk)

            while True:
                newline = buffer.find(b"\n")
                if newline < 0:
                    break

                line = bytes(buffer[:newline]).strip()
                del buffer[: newline + 1]

                for frame in self.convert_line(line):
                    self.clients.broadcast(frame)

    def convert_line(self, line: bytes) -> Iterable[bytes]:
        if not line or line == RAW_HEARTBEAT:
            return ()

        if not line.startswith(b"*") or not line.endswith(b";"):
            logging.debug("Skipping non-AVR line: %r", line)
            return ()

        payload = line[1:-1]
        if len(payload) % 2 != 0:
            logging.debug("Skipping odd-length AVR frame: %r", line)
            return ()

        try:
            message = bytes.fromhex(payload.decode("ascii"))
        except ValueError:
            logging.debug("Skipping invalid AVR hex frame: %r", line)
            return ()

        if len(message) not in (2, 7, 14):
            logging.debug("Skipping unsupported AVR frame length %s", len(message))
            return ()

        return (encode_beast_frame(message),)

    def stop(self, *_args: object) -> None:
        logging.info("Stopping Beast bridge")
        self.stop_event.set()


def main() -> int:
    parser = build_arg_parser()
    args = parser.parse_args()
    configure_logging(args.log_file, args.log_level)

    bridge = BeastBridge(args)
    signal.signal(signal.SIGINT, bridge.stop)
    signal.signal(signal.SIGTERM, bridge.stop)
    return bridge.run()


if __name__ == "__main__":
    raise SystemExit(main())
