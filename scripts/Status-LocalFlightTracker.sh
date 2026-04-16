#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$ROOT/logs/readsb.log"
PID_FILE="$ROOT/logs/readsb.pid"

port_status() {
  local port="$1"
  local label="$2"
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    printf "%-15s: listening on tcp://127.0.0.1:%s\n" "$label" "$port"
  else
    printf "%-15s: not listening on port %s\n" "$label" "$port"
  fi
}

if [[ -f "$PID_FILE" ]]; then
  PID_VALUE="$(tr -d '[:space:]' < "$PID_FILE")"
else
  PID_VALUE=""
fi

if [[ "$PID_VALUE" =~ ^[0-9]+$ ]] && kill -0 "$PID_VALUE" 2>/dev/null; then
  echo "Tracker process : running (PID $PID_VALUE)"
else
  echo "Tracker process : not running"
fi

port_status 30002 "AVR/raw"
port_status 30003 "SBS"
port_status 30005 "Beast"

if [[ -f "$LOG_FILE" ]]; then
  echo
  echo "Recent log output:"
  tail -n 20 "$LOG_FILE"
fi
