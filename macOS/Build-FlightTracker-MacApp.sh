#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/output/macos"
APP_NAME="Flight Tracker"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/FlightTracker.dmg"
DMG_STAGING_DIR="$DIST_DIR/dmg-root"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required macOS tool: $1" >&2
    exit 1
  fi
}

require_tool osacompile
require_tool hdiutil

set_plist_value() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  if ! /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist_path" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist_path"
  fi
}

rm -rf "$APP_BUNDLE" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$DIST_DIR" "$DMG_STAGING_DIR"

osacompile -o "$APP_BUNDLE" "$SCRIPT_DIR/FlightTrackerLauncher.applescript"

mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$SCRIPT_DIR/default-flight-tracker-url.txt" "$APP_BUNDLE/Contents/Resources/default-flight-tracker-url.txt"

if [ -x /usr/libexec/PlistBuddy ]; then
  set_plist_value "$APP_BUNDLE/Contents/Info.plist" "CFBundleName" "$APP_NAME"
  set_plist_value "$APP_BUNDLE/Contents/Info.plist" "CFBundleDisplayName" "$APP_NAME"
  set_plist_value "$APP_BUNDLE/Contents/Info.plist" "CFBundleIdentifier" "com.flighttracker.launcher"
  set_plist_value "$APP_BUNDLE/Contents/Info.plist" "CFBundleShortVersionString" "1.0.0"
  set_plist_value "$APP_BUNDLE/Contents/Info.plist" "CFBundleVersion" "1.0.0"
fi

cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
cp "$REPO_ROOT/README.md" "$DMG_STAGING_DIR/README.md"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo
echo "macOS app bundle:"
echo "  $APP_BUNDLE"
echo
echo "macOS DMG:"
echo "  $DMG_PATH"
