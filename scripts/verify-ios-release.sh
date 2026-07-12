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

if [[ "$bundle_id" != "today.readtheworld.app" ]]; then
  echo "Unexpected bundle identifier: $bundle_id" >&2
  exit 1
fi

if [[ -n "$expected_build" && "$build_number" != "$expected_build" ]]; then
  echo "Expected build $expected_build, found $build_number" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$app_path"

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

echo "iOS release verified: today.readtheworld.app build $build_number"
echo "  Apple Sign-In: Default"
echo "  Push notifications: production"
echo "  Associated domain: applinks:rtw.codes"
echo "  Distribution signature: valid"
