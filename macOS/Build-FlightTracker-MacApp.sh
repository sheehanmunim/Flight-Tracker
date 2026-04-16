#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/macos"
APP_NAME="Flight Tracker"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$REPO_ROOT/FlightTracker.dmg"
DMG_STAGING_DIR="$BUILD_DIR/dmg-root"
EXECUTABLE_PATH="$MACOS_DIR/FlightTracker"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required macOS tool: $1" >&2
    exit 1
  fi
}

require_tool swiftc
require_tool hdiutil

rm -rf "$APP_BUNDLE" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_STAGING_DIR"

swiftc \
  -framework Cocoa \
  -framework WebKit \
  "$SCRIPT_DIR/FlightTrackerApp.swift" \
  -o "$EXECUTABLE_PATH"

chmod +x "$EXECUTABLE_PATH"
cp "$SCRIPT_DIR/default-flight-tracker-url.txt" "$RESOURCES_DIR/default-flight-tracker-url.txt"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Flight Tracker</string>
    <key>CFBundleExecutable</key>
    <string>FlightTracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.flighttracker.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Flight Tracker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
      <key>NSAllowsArbitraryLoads</key>
      <true/>
    </dict>
  </dict>
</plist>
PLIST

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
