#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for env_file in "$ROOT_DIR/.env" "$ROOT_DIR/.env.local"; do
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  fi
done

dart_define_args=()
for key in \
  RTW_FIREBASE_CONFIGURED \
  RTW_FIREBASE_API_KEY \
  RTW_FIREBASE_APP_ID \
  RTW_FIREBASE_ANDROID_API_KEY \
  RTW_FIREBASE_ANDROID_APP_ID \
  RTW_FIREBASE_IOS_API_KEY \
  RTW_FIREBASE_IOS_APP_ID \
  RTW_FIREBASE_SENDER_ID \
  RTW_FIREBASE_PROJECT_ID \
  RTW_FIREBASE_AUTH_DOMAIN \
  RTW_FIREBASE_STORAGE_BUCKET \
  RTW_GOOGLE_WEB_CLIENT_ID \
  RTW_GOOGLE_IOS_CLIENT_ID \
  RTW_RECAPTCHA_ENTERPRISE_SITE_KEY \
  RTW_WEB_PUSH_VAPID_KEY
do
  if [[ -n "${!key:-}" ]]; then
    dart_define_args+=("--dart-define=$key=${!key}")
  fi
done

cd "$ROOT_DIR/apps/app"
flutter build web --release "${dart_define_args[@]}" "$@"

cd "$ROOT_DIR"
node scripts/copy-flutter-web-static.mjs
