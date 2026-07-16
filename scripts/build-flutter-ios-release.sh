#!/usr/bin/env bash
# Builds the App Store archive/IPA with the production dart-defines baked in,
# then proves the built binary actually contains them. Always archive through
# this script: a bare `flutter build ipa` or Xcode Organizer archive inherits
# DART_DEFINES from whatever flutter command ran last (including the QA
# emulator config) and ships a silently broken binary.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$ROOT_DIR/scripts/flutter-dart-defines.sh"

rtw_load_flutter_env "$ROOT_DIR"
rtw_require_mobile_flutter_defines

if [[ "${RTW_USE_EMULATORS:-}" == "true" || -n "${RTW_LOCAL_PREVIEW:-}" ]]; then
  echo "RTW_USE_EMULATORS/RTW_LOCAL_PREVIEW are set. Refusing to build a release with QA config." >&2
  exit 1
fi

dart_define_args=()
while IFS= read -r arg; do
  dart_define_args+=("$arg")
done < <(rtw_flutter_dart_define_args)

cd "$ROOT_DIR/apps/app"
flutter build ipa --release "${dart_define_args[@]}" "$@"

# Confirm the defines that were just compiled in: DART_DEFINES in
# Generated.xcconfig is a comma-separated list of base64-encoded KEY=VALUE
# pairs written by the build above.
decoded_defines=$(
  tr ',' '\n' < <(sed -n 's/^DART_DEFINES=//p' ios/Flutter/Generated.xcconfig) |
    while IFS= read -r chunk; do
      printf '%s' "$chunk" | base64 -d 2>/dev/null || true
      printf '\n'
    done
)

assert_define() {
  local expected=$1
  if ! grep -qxF "$expected" <<<"$decoded_defines"; then
    echo "Built archive is missing dart-define '$expected'. Do not upload it." >&2
    exit 1
  fi
}

assert_define "RTW_FIREBASE_CONFIGURED=true"
assert_define "RTW_FIREBASE_PROJECT_ID=${RTW_FIREBASE_PROJECT_ID}"

if grep -q '^RTW_USE_EMULATORS=true$' <<<"$decoded_defines"; then
  echo "Built archive has RTW_USE_EMULATORS=true baked in. Do not upload it." >&2
  exit 1
fi

ipa_path=$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)
archive_path="build/ios/archive/Runner.xcarchive"

echo
echo "Release build verified: production dart-defines are baked in."
if [[ -n "$ipa_path" ]]; then
  echo "IPA: apps/app/$ipa_path"
  echo "Next: $ROOT_DIR/scripts/verify-ios-release.sh \"$PWD/$ipa_path\" <expected-build-number>"
elif [[ -d "$archive_path" ]]; then
  echo "Archive: apps/app/$archive_path (IPA export did not run; export via Xcode Organizer)"
  echo "Next: $ROOT_DIR/scripts/verify-ios-release.sh \"$PWD/$archive_path\" <expected-build-number>"
fi
