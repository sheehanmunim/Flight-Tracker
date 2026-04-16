#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT/logs/readsb.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "Flight tracker is not running."
  exit 0
fi

PID_VALUE="$(tr -d '[:space:]' < "$PID_FILE")"
if [[ "$PID_VALUE" =~ ^[0-9]+$ ]] && kill -0 "$PID_VALUE" 2>/dev/null; then
  kill "$PID_VALUE" 2>/dev/null || true

  for _ in $(seq 1 20); do
    if ! kill -0 "$PID_VALUE" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done

  if kill -0 "$PID_VALUE" 2>/dev/null; then
    kill -9 "$PID_VALUE" 2>/dev/null || true
  fi
fi

rm -f "$PID_FILE"
echo "Flight tracker stopped."
