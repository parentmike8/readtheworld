#!/usr/bin/env bash
set -euo pipefail

echo "Read the World account preflight"
echo
echo "This script is read-only. It does not log in, switch accounts, deploy, or change cloud state."
echo

warned=0
expected_google_account="mike@readtheworld.today"
expected_github_account="parentmike8"

flag_if_work_context() {
  local label="$1"
  local value="$2"
  if printf '%s' "$value" | grep -Eiq 'covet|covetai|covet-org|smart\.vet'; then
    echo "WARNING: $label appears to reference a CoVet/work context."
    warned=1
  fi
}

flag_if_google_not_readtheworld() {
  local label="$1"
  local value="$2"
  if printf '%s' "$value" | grep -Eq '@' &&
    ! printf '%s' "$value" | grep -Eq "$expected_google_account|No authorized accounts"; then
    echo "WARNING: $label should use $expected_google_account for Read the World cloud/Firebase work."
    warned=1
  fi
}

run_if_available() {
  local binary="$1"
  shift
  if command -v "$binary" >/dev/null 2>&1; then
    "$binary" "$@" 2>&1 || true
  else
    echo "$binary is not installed or not on PATH."
  fi
}

echo "GitHub auth:"
github_output="$(run_if_available gh auth status)"
printf '%s\n' "$github_output"
active_github_account="$(printf '%s\n' "$github_output" | awk '
  /Logged in to github.com account / {
    account = $0
    sub(/^.*account /, "", account)
    sub(/ .*/, "", account)
  }
  /Active account: true/ {
    print account
    exit
  }
')"
if [[ -n "$active_github_account" && "$active_github_account" != "$expected_github_account" ]]; then
  echo "WARNING: GitHub active account should be $expected_github_account for Read the World work; found $active_github_account."
  warned=1
fi
if printf '%s' "$active_github_account" | grep -Eiq 'covet|covetai|covet-org|smart\.vet'; then
  echo "WARNING: GitHub active account appears to reference a CoVet/work context."
  warned=1
elif printf '%s\n' "$github_output" | awk '
  /Logged in to github.com account / {
    account = $0
    sub(/^.*account /, "", account)
    sub(/ .*/, "", account)
  }
  /Active account: false/ {
    print account
  }
' | grep -Eiq 'covet|covetai|covet-org|smart\.vet'; then
  echo "Note: an inactive GitHub CoVet/work login is still stored locally, but it is not the active account."
fi
echo

echo "Google Cloud auth:"
gcloud_output="$(run_if_available gcloud auth list)"
printf '%s\n' "$gcloud_output"
flag_if_work_context "Google Cloud auth" "$gcloud_output"
flag_if_google_not_readtheworld "Google Cloud auth" "$gcloud_output"
echo

echo "Firebase auth:"
firebase_output="$(run_if_available firebase login:list)"
printf '%s\n' "$firebase_output"
flag_if_work_context "Firebase auth" "$firebase_output"
flag_if_google_not_readtheworld "Firebase auth" "$firebase_output"
echo

if [[ -f ".firebaserc" ]]; then
  echo ".firebaserc:"
  firebaserc_output="$(cat .firebaserc)"
  printf '%s\n' "$firebaserc_output"
  flag_if_work_context ".firebaserc" "$firebaserc_output"
else
  echo ".firebaserc is not present. That is expected before isolated Firebase setup."
fi
echo

if [[ "$warned" -eq 1 ]]; then
  echo "Preflight result: review account context before continuing."
  exit 1
fi

echo "Preflight result: no obvious CoVet/work context detected."
