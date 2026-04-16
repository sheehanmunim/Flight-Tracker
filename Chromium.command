#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PORT=5099
KEY_FILE="$ROOT/logs/dashboard.key"
APP_URL=""

launch_chromium_app() {
  local url="$1"
  local app_name

  for app_name in "Google Chrome" "Chromium" "Google Chrome Canary" "Microsoft Edge"; do
    if osascript -e "POSIX path of (path to application \"$app_name\")" >/dev/null 2>&1; then
      open -na "$app_name" --args --app="$url"
      return 0
    fi
  done

  return 1
}

bash "$ROOT/Browser.command" --no-open

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Dashboard key file was not created."
  exit 1
fi

DASHBOARD_KEY="$(tr -d '\r\n' < "$KEY_FILE")"
APP_URL="http://localhost:$PORT/?key=$DASHBOARD_KEY"

if ! launch_chromium_app "$APP_URL"; then
  echo "No Chromium-based browser was found in /Applications."
  echo "Opening the dashboard in the default browser instead."
  open "$APP_URL"
fi
