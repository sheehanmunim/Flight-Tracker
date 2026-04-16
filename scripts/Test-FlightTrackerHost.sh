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

BREW_PATH=""
if command -v brew >/dev/null 2>&1; then
  BREW_PATH="$(command -v brew)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_PATH="/opt/homebrew/bin/brew"
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_PATH="/usr/local/bin/brew"
fi

if [[ -n "$BREW_PATH" ]]; then
  echo "brew          : Yes"
  echo "brew path     : $BREW_PATH"
else
  echo "brew          : No"
fi

if command -v readsb >/dev/null 2>&1; then
  echo "readsb        : Yes"
  echo "readsb path   : $(command -v readsb)"
else
  echo "readsb        : No"
  if [[ -n "$BREW_PATH" ]]; then
    echo "Install hint  : Browser.command and Chromium.command will auto-install readsb with Homebrew on first run."
  else
    echo "Install hint  : install Homebrew from https://brew.sh, then run Browser.command or Chromium.command."
  fi
fi

echo
echo "Detected SDR Hardware"
USB_MATCH="$(system_profiler SPUSBDataType 2>/dev/null | grep -Ei 'RTL|2832|2838|Bulk-In' | head -n 6 || true)"
if [[ -n "$USB_MATCH" ]]; then
  echo "$USB_MATCH"
else
  echo "No obvious RTL-SDR USB entry was detected in system_profiler output."
fi
