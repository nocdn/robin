#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Robin"
EXECUTABLE_NAME="robin"
APP_DIR="$ROOT/.build/${APP_NAME}.app"

osascript -e 'tell application id "dev.local.robin" to quit' >/dev/null 2>&1 || true
pkill -x "$EXECUTABLE_NAME" 2>/dev/null || true
pkill -f "/${APP_NAME}.app/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true

CONFIGURATION=debug "$ROOT/scripts/package_app.sh" >/dev/null
open "$APP_DIR"

echo "Launched $APP_DIR"
