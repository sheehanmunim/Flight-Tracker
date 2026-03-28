#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/flight-tracker-url.txt"

if [[ ! -f "$CONFIG_FILE" ]]; then
  cat >"$CONFIG_FILE" <<'EOF'
http://YOUR-WINDOWS-HOST:5099/?key=REPLACE_ME
EOF
fi

URL="$(tr -d '\r' < "$CONFIG_FILE" | head -n 1)"

if [[ -z "$URL" || "$URL" == *"REPLACE_ME"* ]]; then
  osascript -e 'display dialog "Edit macOS/flight-tracker-url.txt with the shared dashboard URL from your Windows host, then run FlightTrackerMac.command again." buttons {"OK"} default button "OK"'
  exit 1
fi

open "$URL"
