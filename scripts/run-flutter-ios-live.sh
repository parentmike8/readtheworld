#!/usr/bin/env bash
# Flutter iOS simulator run wired to live Firebase using root .env/.env.local.
# Usage: scripts/run-flutter-ios-live.sh [device-id]   (defaults to "booted")
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/scripts/flutter-dart-defines.sh"
rtw_load_flutter_env "$ROOT_DIR"

dart_define_args=()
while IFS= read -r arg; do
  dart_define_args+=("$arg")
done < <(rtw_flutter_dart_define_args)
while IFS= read -r arg; do
  dart_define_args+=("$arg")
done < <(rtw_local_app_check_debug_dart_define_arg)

device="${1:-booted}"

cd "$ROOT_DIR/apps/app"
exec flutter run -d "$device" "${dart_define_args[@]}"
