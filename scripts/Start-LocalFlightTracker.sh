#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ROOT/logs"
PID_FILE="$LOG_DIR/readsb.pid"
LOG_FILE="$LOG_DIR/readsb.log"
DATA_DIR="$LOG_DIR/readsb-data"
CONFIG_FILE="$ROOT/dump1090-local.cfg"
NO_BROWSER=0
BREW_BIN=""

for arg in "$@"; do
  if [[ "$arg" == "-NoBrowser" || "$arg" == "--no-browser" ]]; then
    NO_BROWSER=1
  fi
done

mkdir -p "$LOG_DIR" "$DATA_DIR"

ensure_brew_on_path() {
  if command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
    return 0
  fi

  for prefix in /opt/homebrew/bin /usr/local/bin; do
    if [[ -x "$prefix/brew" ]]; then
      export PATH="$prefix:$PATH"
      BREW_BIN="$prefix/brew"
      return 0
    fi
  done

  return 1
}

refresh_shell_from_brew() {
  if ensure_brew_on_path; then
    eval "$("$BREW_BIN" shellenv)" >/dev/null 2>&1 || true
  fi
}

ensure_readsb() {
  if command -v readsb >/dev/null 2>&1; then
    return 0
  fi

  refresh_shell_from_brew
  if command -v readsb >/dev/null 2>&1; then
    return 0
  fi

  if ! ensure_brew_on_path; then
    echo "readsb was not found on PATH."
    echo
    echo "Install Homebrew from https://brew.sh, then run Browser.command or Chromium.command again."
    exit 1
  fi

  echo "readsb was not found on PATH."
  echo "Installing readsb with Homebrew for the local Mac host..."

  if ! "$BREW_BIN" install readsb; then
    echo
    echo "Homebrew could not install readsb automatically."
    echo "Try running: brew install readsb"
    exit 1
  fi

  refresh_shell_from_brew

  if ! command -v readsb >/dev/null 2>&1; then
    for prefix in /opt/homebrew/bin /usr/local/bin; do
      if [[ -x "$prefix/readsb" ]]; then
        export PATH="$prefix:$PATH"
        break
      fi
    done
  fi

  if ! command -v readsb >/dev/null 2>&1; then
    echo
    echo "readsb installed, but it was not visible on PATH in this shell."
    echo "Open a new terminal and run Browser.command or Chromium.command again."
    exit 1
  fi

  echo "readsb is installed and ready."
}

port_listener_pid() {
  lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -n 1 || true
}

recent_log_tail() {
  if [[ -f "$LOG_FILE" ]]; then
    tail -n 40 "$LOG_FILE"
  fi
}

ensure_readsb

if [[ -f "$PID_FILE" ]]; then
  EXISTING_PID="$(tr -d '[:space:]' < "$PID_FILE")"
  if [[ "$EXISTING_PID" =~ ^[0-9]+$ ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    if [[ -n "$(port_listener_pid 30005)" ]]; then
      echo "Flight tracker is already running on this Mac host."
      echo "Feed outputs: AVR/raw on tcp://127.0.0.1:30002, SBS on tcp://127.0.0.1:30003, Beast on tcp://127.0.0.1:30005."
      exit 0
    fi
  fi

  rm -f "$PID_FILE"
fi

for port in 30002 30003 30005; do
  BLOCKING_PID="$(port_listener_pid "$port")"
  if [[ -n "$BLOCKING_PID" ]]; then
    echo "Port $port is already in use by PID $BLOCKING_PID. Stop that process first, then try again."
    exit 1
  fi
done

READSB_ARGS=(
  "--device-type" "rtlsdr"
  "--net"
  "--net-bind-address" "127.0.0.1"
  "--net-ro-port" "30002"
  "--net-sbs-port" "30003"
  "--net-bo-port" "30005"
  "--write-json" "$DATA_DIR"
  "--write-json-every" "1"
  "--quiet"
)

if [[ -f "$CONFIG_FILE" ]]; then
  HOMEPOS_LINE="$(grep -E '^[[:space:]]*homepos[[:space:]]*=' "$CONFIG_FILE" | head -n 1 || true)"
  if [[ "$HOMEPOS_LINE" =~ homepos[[:space:]]*=[[:space:]]*([-0-9.]+)[[:space:]]*,[[:space:]]*([-0-9.]+) ]]; then
    READSB_ARGS+=("--lat" "${BASH_REMATCH[1]}" "--lon" "${BASH_REMATCH[2]}")
  fi
fi

nohup readsb "${READSB_ARGS[@]}" >>"$LOG_FILE" 2>&1 &
TRACKER_PID=$!
echo "$TRACKER_PID" > "$PID_FILE"

for _ in $(seq 1 60); do
  if ! kill -0 "$TRACKER_PID" 2>/dev/null; then
    echo "readsb exited during startup."
    echo
    recent_log_tail
    rm -f "$PID_FILE"
    exit 1
  fi

  if [[ -n "$(port_listener_pid 30002)" && -n "$(port_listener_pid 30003)" && -n "$(port_listener_pid 30005)" ]]; then
    echo "Flight tracker is running on this Mac host."
    echo "Feed outputs: AVR/raw on tcp://127.0.0.1:30002, SBS on tcp://127.0.0.1:30003, Beast on tcp://127.0.0.1:30005."
    echo "Receiver data view: use the local browser dashboard on port 5099."
    exit 0
  fi

  sleep 0.5
done

kill "$TRACKER_PID" 2>/dev/null || true
rm -f "$PID_FILE"
echo "readsb started but never opened the expected local feed ports."
echo
recent_log_tail
exit 1
