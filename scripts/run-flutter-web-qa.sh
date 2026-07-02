#!/usr/bin/env bash
# Flutter web dev server wired to the local Firebase emulator suite (QA).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/scripts/flutter-dart-defines.sh"
rtw_load_flutter_env "$ROOT_DIR"

dart_define_args=()
while IFS= read -r arg; do
  dart_define_args+=("$arg")
done < <(rtw_flutter_dart_define_args)

cd "$ROOT_DIR/apps/app"
exec flutter run -d web-server \
  --web-port "${RTW_QA_WEB_PORT:-5173}" \
  --web-hostname 127.0.0.1 \
  --dart-define=RTW_USE_EMULATORS=true \
  "${dart_define_args[@]}"
