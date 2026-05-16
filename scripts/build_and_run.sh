#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Robin"
EXECUTABLE_NAME="robin"
BUNDLE_ID="${BUNDLE_ID:-dev.local.robin}"
APP_DIR="$ROOT/.build/${APP_NAME}.app"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
pkill -x "$EXECUTABLE_NAME" 2>/dev/null || true
pkill -f "/${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true

tccutil reset ListenEvent "$BUNDLE_ID"
tccutil reset Accessibility "$BUNDLE_ID"

CONFIGURATION=debug "$ROOT/scripts/package_app.sh" >/dev/null
open "$APP_DIR"

echo "Launched $APP_DIR"
