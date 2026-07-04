#!/usr/bin/env bash

rtw_load_flutter_env() {
  local root_dir="$1"
  local env_file
  for env_file in "$root_dir/.env" "$root_dir/.env.local"; do
    if [[ -f "$env_file" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "$env_file"
      set +a
    fi
  done
}

rtw_flutter_dart_define_args() {
  local key
  local keys=(
    RTW_FIREBASE_CONFIGURED
    RTW_FIREBASE_API_KEY
    RTW_FIREBASE_APP_ID
    RTW_FIREBASE_ANDROID_API_KEY
    RTW_FIREBASE_ANDROID_APP_ID
    RTW_FIREBASE_IOS_API_KEY
    RTW_FIREBASE_IOS_APP_ID
    RTW_FIREBASE_SENDER_ID
    RTW_FIREBASE_PROJECT_ID
    RTW_FIREBASE_AUTH_DOMAIN
    RTW_FIREBASE_STORAGE_BUCKET
    RTW_GOOGLE_WEB_CLIENT_ID
    RTW_GOOGLE_IOS_CLIENT_ID
    RTW_RECAPTCHA_ENTERPRISE_SITE_KEY
    RTW_WEB_PUSH_VAPID_KEY
  )

  for key in "${keys[@]}"; do
    if [[ -n "${!key:-}" ]]; then
      printf '%s\n' "--dart-define=$key=${!key}"
    fi
  done
}
