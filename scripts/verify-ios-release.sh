#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <Runner.app|Runner.xcarchive|app.ipa> [expected-build-number]" >&2
  exit 64
fi

input_path=$1
expected_build=${2:-}
temporary_dir=""

cleanup() {
  if [[ -n "$temporary_dir" && -d "$temporary_dir" ]]; then
    rm -rf "$temporary_dir"
  fi
}
trap cleanup EXIT

case "$input_path" in
  *.ipa)
    temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/rtw-ios-release.XXXXXX")
    /usr/bin/ditto -x -k "$input_path" "$temporary_dir"
    app_path="$temporary_dir/Payload/Runner.app"
    ;;
  *.xcarchive)
    app_path="$input_path/Products/Applications/Runner.app"
    ;;
  *.app)
    app_path="$input_path"
    ;;
  *)
    echo "Unsupported release artifact: $input_path" >&2
    exit 64
    ;;
esac

if [[ ! -d "$app_path" ]]; then
  echo "Runner.app was not found in $input_path" >&2
  exit 1
fi

plist="$app_path/Info.plist"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
uses_non_exempt_encryption=$(
  /usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' \
    "$plist" 2>/dev/null || true
)

if [[ "$bundle_id" != "today.readtheworld.app" ]]; then
  echo "Unexpected bundle identifier: $bundle_id" >&2
  exit 1
fi

if [[ -n "$expected_build" && "$build_number" != "$expected_build" ]]; then
  echo "Expected build $expected_build, found $build_number" >&2
  exit 1
fi

if [[ "$uses_non_exempt_encryption" != "false" ]]; then
  echo "ITSAppUsesNonExemptEncryption must be false for TestFlight export compliance." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$app_path"

# Reject simulator-native assets before Apple does. Flutter code assets are
# emitted as embedded frameworks and can retain simulator slices when release
# and simulator builds reuse build/native_assets/ios.
while IFS= read -r framework_path; do
  framework_plist="$framework_path/Info.plist"
  [[ -f "$framework_plist" ]] || continue
  framework_executable=$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
      "$framework_plist" 2>/dev/null || true
  )
  [[ -n "$framework_executable" ]] || continue
  framework_binary="$framework_path/$framework_executable"
  [[ -f "$framework_binary" ]] || continue

  framework_architectures=$(lipo -archs "$framework_binary" 2>/dev/null || true)
  if [[ " $framework_architectures " == *" x86_64 "* || \
        " $framework_architectures " == *" i386 "* ]]; then
    echo "Embedded framework contains simulator architecture: $framework_path ($framework_architectures)" >&2
    exit 1
  fi

  framework_load_commands=$(otool -l "$framework_binary" 2>/dev/null || true)
  if grep -Eq 'LC_VERSION_MIN_IPHONESIMULATOR|platform[[:space:]]+7([[:space:]]|$)' \
    <<<"$framework_load_commands"; then
    echo "Embedded framework targets the iOS Simulator: $framework_path" >&2
    exit 1
  fi
done < <(find "$app_path/Frameworks" -type d -name '*.framework' -print)

temporary_dir=${temporary_dir:-$(mktemp -d "${TMPDIR:-/tmp}/rtw-ios-release.XXXXXX")}
entitlements_plist="$temporary_dir/entitlements.plist"
/usr/bin/codesign -d --entitlements :- "$app_path" > "$entitlements_plist" 2>/dev/null

assert_entitlement() {
  local key=$1
  local expected=$2
  local actual
  actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$entitlements_plist" 2>/dev/null || true)
  if [[ "$actual" != "$expected" ]]; then
    echo "Entitlement $key expected '$expected', found '${actual:-missing}'" >&2
    exit 1
  fi
}

assert_entitlement "aps-environment" "production"
assert_entitlement "com.apple.developer.applesignin:0" "Default"
assert_entitlement "com.apple.developer.associated-domains:0" "applinks:rtw.codes"
assert_entitlement "get-task-allow" "false"

signature=$(/usr/bin/codesign -dvv "$app_path" 2>&1)
if [[ "$signature" != *"Authority=Apple Distribution: MICHAEL DENIS PARENT (GC99GKC845)"* ]]; then
  echo "The app is not signed with the expected Apple Distribution identity." >&2
  exit 1
fi

if [[ ! -f "$app_path/embedded.mobileprovision" ]]; then
  echo "The app has no embedded provisioning profile." >&2
  exit 1
fi

# The Dart AOT snapshot must contain the production dart-defines: a binary
# built without them boots in the degraded "Firebase unavailable" mode with no
# other symptom until it is on a user's phone.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/flutter-dart-defines.sh"
rtw_load_flutter_env "$script_dir/.."
expected_project_id="${RTW_FIREBASE_PROJECT_ID:-read-the-world-74f2a}"

app_binary="$app_path/Frameworks/App.framework/App"
if [[ ! -f "$app_binary" ]]; then
  echo "Dart AOT snapshot not found at Frameworks/App.framework/App." >&2
  exit 1
fi

# Dump once and grep the file: piping strings straight into grep -q can die
# on SIGPIPE under pipefail, which would invert these gates.
strings_dump="$temporary_dir/app-strings.txt"
/usr/bin/strings "$app_binary" > "$strings_dump"

if ! grep -qF "$expected_project_id" "$strings_dump"; then
  echo "The Dart snapshot does not contain Firebase project '$expected_project_id'." >&2
  echo "This binary was built without the production dart-defines. Do not ship it." >&2
  exit 1
fi

if grep -qE '(^|[^0-9.])(127\.0\.0\.1|10\.0\.2\.2)([^0-9.]|$)' "$strings_dump"; then
  echo "The Dart snapshot contains an emulator host (127.0.0.1/10.0.2.2)." >&2
  echo "This binary looks like a QA/emulator build. Do not ship it." >&2
  exit 1
fi

echo "iOS release verified: today.readtheworld.app build $build_number"
echo "  Apple Sign-In: Default"
echo "  Push notifications: production"
echo "  Associated domain: applinks:rtw.codes"
echo "  Distribution signature: valid"
echo "  Export compliance: no non-exempt encryption"
echo "  Firebase config: $expected_project_id baked into Dart snapshot, no emulator hosts"
