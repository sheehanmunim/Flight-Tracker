#!/bin/bash
set -euo pipefail

echo
echo "Flight Tracker Host Check"
echo "Computer      : $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "OS            : macOS $(sw_vers -productVersion 2>/dev/null || echo unknown)"
echo "Architecture  : $(uname -m)"

echo
echo "Tooling"
if command -v dotnet >/dev/null 2>&1; then
  echo "dotnet        : Yes"
  echo "dotnet path   : $(command -v dotnet)"
else
  echo "dotnet        : No"
fi

if command -v readsb >/dev/null 2>&1; then
  echo "readsb        : Yes"
  echo "readsb path   : $(command -v readsb)"
else
  echo "readsb        : No"
  echo "Install hint  : brew install readsb"
fi

echo
echo "Detected SDR Hardware"
USB_MATCH="$(system_profiler SPUSBDataType 2>/dev/null | grep -Ei 'RTL|2832|2838|Bulk-In' | head -n 6 || true)"
if [[ -n "$USB_MATCH" ]]; then
  echo "$USB_MATCH"
else
  echo "No obvious RTL-SDR USB entry was detected in system_profiler output."
fi
