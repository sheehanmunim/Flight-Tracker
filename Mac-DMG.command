#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

chmod +x "$SCRIPT_DIR/macOS/Build-FlightTracker-MacApp.sh"
"$SCRIPT_DIR/macOS/Build-FlightTracker-MacApp.sh" "$@"
