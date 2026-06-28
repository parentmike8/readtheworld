#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$ROOT_DIR/scripts/flutter-dart-defines.sh"

rtw_load_flutter_env "$ROOT_DIR"
dart_define_args=()
while IFS= read -r arg; do
  dart_define_args+=("$arg")
done < <(rtw_flutter_dart_define_args)

cd "$ROOT_DIR/apps/app"
flutter build ios --simulator --debug "${dart_define_args[@]}" "$@"
