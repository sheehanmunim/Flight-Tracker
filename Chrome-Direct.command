#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT=5099
KEY_FILE="$ROOT/logs/dashboard.key"

"$ROOT/Browser.command"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Dashboard key file was not created."
  exit 1
fi

DASHBOARD_KEY="$(tr -d '\r\n' < "$KEY_FILE")"
open "http://localhost:$PORT/chrome-direct.html?key=$DASHBOARD_KEY"
