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

# Single source of truth for the define keys: a key added to one list and not
# the other would either ship unset or dodge the release guard.
RTW_REQUIRED_DEFINE_KEYS=(
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
)
# Web-only keys: passed through when set, never required for a mobile build.
RTW_OPTIONAL_DEFINE_KEYS=(
  RTW_RECAPTCHA_ENTERPRISE_SITE_KEY
  RTW_WEB_PUSH_VAPID_KEY
)

rtw_flutter_dart_define_args() {
  local key
  for key in "${RTW_REQUIRED_DEFINE_KEYS[@]}" "${RTW_OPTIONAL_DEFINE_KEYS[@]}"; do
    if [[ -n "${!key:-}" ]]; then
      printf '%s\n' "--dart-define=$key=${!key}"
    fi
  done
}

# Fails loudly when a define the mobile app cannot run without is unset or
# blank. A missing key would otherwise compile to an empty string and the app
# would silently boot in the degraded "Firebase unavailable" mode.
rtw_require_mobile_flutter_defines() {
  local key
  local missing=()
  for key in "${RTW_REQUIRED_DEFINE_KEYS[@]}"; do
    if [[ -z "${!key:-}" ]]; then
      missing+=("$key")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "Missing required dart-define env keys: ${missing[*]}" >&2
    echo "Populate them in .env.local before building." >&2
    return 1
  fi

  if [[ "${RTW_FIREBASE_CONFIGURED}" != "true" ]]; then
    echo "RTW_FIREBASE_CONFIGURED must be 'true' (found '${RTW_FIREBASE_CONFIGURED}')." >&2
    return 1
  fi
}

# Web has its own smaller contract. Requiring it here prevents a successful
# release build that boots into "Live authentication is unavailable" because
# Firebase values were silently compiled as empty strings.
rtw_require_web_flutter_defines() {
  local key
  local missing=()
  local required_web_keys=(
    RTW_FIREBASE_CONFIGURED
    RTW_FIREBASE_API_KEY
    RTW_FIREBASE_APP_ID
    RTW_FIREBASE_SENDER_ID
    RTW_FIREBASE_PROJECT_ID
    RTW_FIREBASE_AUTH_DOMAIN
    RTW_FIREBASE_STORAGE_BUCKET
    RTW_GOOGLE_WEB_CLIENT_ID
  )
  for key in "${required_web_keys[@]}"; do
    if [[ -z "${!key:-}" ]]; then
      missing+=("$key")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "Missing required web dart-define env keys: ${missing[*]}" >&2
    echo "Populate them in .env.local before building." >&2
    return 1
  fi

  if [[ "${RTW_FIREBASE_CONFIGURED}" != "true" ]]; then
    echo "RTW_FIREBASE_CONFIGURED must be 'true' (found '${RTW_FIREBASE_CONFIGURED}')." >&2
    return 1
  fi
}
