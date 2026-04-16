#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/apps/windows/DashboardHost/DashboardHost.csproj"
TRACKER_START="$ROOT/scripts/Start-LocalFlightTracker.sh"
PORT=5099
KEY_FILE="$ROOT/logs/dashboard.key"
HOST_LOG="$ROOT/logs/dashboard-host.log"
MAC_URL_FILE="$ROOT/macOS/flight-tracker-url.txt"
OPEN_BROWSER=1

for arg in "$@"; do
  if [[ "$arg" == "--no-open" ]]; then
    OPEN_BROWSER=0
  fi
done

mkdir -p "$ROOT/logs" "$ROOT/macOS"

if ! command -v dotnet >/dev/null 2>&1; then
  echo ".NET 8 SDK was not found on PATH."
  echo "Install .NET 8 on this Mac, then run Browser.command again."
  exit 1
fi

echo "Starting the local tracker runtime..."
bash "$TRACKER_START" -NoBrowser

if ! lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  nohup dotnet run --project "$PROJECT" -c Release -- --no-browser --urls "http://0.0.0.0:$PORT" >"$HOST_LOG" 2>&1 &
  sleep 4
fi

for _ in $(seq 1 20); do
  if [[ -f "$KEY_FILE" ]]; then
    break
  fi
  sleep 1
done

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Dashboard key file was not created. Check $HOST_LOG."
  exit 1
fi

DASHBOARD_KEY="$(tr -d '\r\n' < "$KEY_FILE")"
LAN_IP="$(route get default 2>/dev/null | awk '/interface: / { print $2; exit }')"
if [[ -n "${LAN_IP:-}" ]]; then
  LAN_IP="$(ipconfig getifaddr "$LAN_IP" 2>/dev/null || true)"
fi
if [[ -z "${LAN_IP:-}" ]]; then
  LAN_IP="localhost"
fi

printf 'http://%s:%s/?key=%s\n' "$LAN_IP" "$PORT" "$DASHBOARD_KEY" > "$MAC_URL_FILE"

echo
echo "Flight Tracker dashboard URL:"
echo "http://localhost:$PORT/?key=$DASHBOARD_KEY"
echo
echo "Share this LAN URL:"
echo "http://$LAN_IP:$PORT/?key=$DASHBOARD_KEY"

if [[ "$OPEN_BROWSER" == "1" ]]; then
  open "http://localhost:$PORT/?key=$DASHBOARD_KEY"
fi
