#!/usr/bin/env bash
# Build, install, and launch the live-Firebase iOS simulator app.
# Usage: scripts/install-flutter-ios-sim.sh [device-id]   (defaults to "booted")
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-booted}"
BUNDLE_ID="today.readtheworld.app"
APP_PATH="$ROOT_DIR/apps/app/build/ios/iphonesimulator/Runner.app"

"$ROOT_DIR/scripts/build-flutter-ios-sim.sh"

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
