#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/../.build/macos/Flight Tracker.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Flight Tracker.app was not found in .build/macos."
  echo "Run ./Mac-DMG.command on a Mac first, then run this helper again."
  exit 1
fi

open "$APP_BUNDLE"
