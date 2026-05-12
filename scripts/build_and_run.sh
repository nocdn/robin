#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="robin"
EXECUTABLE="$ROOT/.build/debug/robin"
APP_DIR="$ROOT/.build/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

osascript -e 'tell application id "dev.local.robin" to quit' >/dev/null 2>&1 || true
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -f "/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

cd "$ROOT"
swift build -c debug

rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$EXECUTABLE" "$MACOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>robin</string>
    <key>CFBundleIdentifier</key>
    <string>dev.local.robin</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Robin</string>
    <key>CFBundleDisplayName</key>
    <string>Robin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Robin records audio while you hold the configured push-to-talk hotkey so it can transcribe it.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null
open "$APP_DIR"

echo "Launched $APP_DIR"
