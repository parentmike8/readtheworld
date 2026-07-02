#!/usr/bin/env bash
# Flutter iOS simulator run wired to the local Firebase emulator suite (QA).
# Usage: scripts/run-flutter-ios-qa.sh [device-id]   (defaults to "booted")
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/scripts/flutter-dart-defines.sh"
rtw_load_flutter_env "$ROOT_DIR"

dart_define_args=()
while IFS= read -r arg; do
  dart_define_args+=("$arg")
done < <(rtw_flutter_dart_define_args)

device="${1:-booted}"

cd "$ROOT_DIR/apps/app"
exec flutter run -d "$device" \
  --dart-define=RTW_USE_EMULATORS=true \
  --dart-define=RTW_EMULATOR_HOST=127.0.0.1 \
  "${dart_define_args[@]}"
