#!/usr/bin/env bash
# Signs a smoke-test simulator out of iCloud and back in, unattended.
#
# Simulator iCloud sessions expire on their own (cloudd: AuthTokenError 2011) and need a
# full sign-out + sign-in in Settings. On a simulator that has signed in to the same
# Apple ID before, that sign-in asks for no verification code, so a UI test
# (OurDaysUITests/SimulatorICloudSignInTests) can drive Settings for you.
#
# The Apple ID and password live only in this Mac's login Keychain, one item per
# simulator, which you add once yourself:
#   Scripts/sim-icloud-relogin.sh store owner     # asks for the Apple ID, then the password
#   Scripts/sim-icloud-relogin.sh store partner
# Then, whenever a simulator's session expires:
#   Scripts/sim-icloud-relogin.sh owner           # or: partner
#   Scripts/sim-icloud-relogin.sh owner --signin-only   # simulator is already signed out
# Scripts/dev-pairing-smoke.sh calls this automatically when its precheck finds an
# expired session and the Keychain item exists.
#
# The password is handed to the test through a 0600 temp file that is deleted on exit,
# together with this run's result bundle; it is never put in the environment, a
# command line, the repository or the test logs.
set -euo pipefail

OWNER_UDID="${OWNER_UDID:-AF9A93BC-6151-4C6D-B5F7-E4F5053351E2}"   # iPhone 17
PARTNER_UDID="${PARTNER_UDID:-244DFAAC-93A7-4BE7-AEA0-4F0A52ABA7D6}" # iPhone 17 Pro
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${SIM_ICLOUD_DERIVED:-$ROOT_DIR/build/dev-smoke}"   # shared with the smoke build
KEYCHAIN_SERVICE_PREFIX="OurDays smoke simulator iCloud"

log() { printf '\033[1;35m[sim-icloud]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[sim-icloud FAILED]\033[0m %s\n' "$*" >&2; exit 1; }

# XCTest logs every typeText as "Type '<text>' into …" (the first ~20 characters), which
# would put the start of the password in the log kept on failure. Drop the text.
redact_typing() { sed -E '/ Type .* into /s/ Type .* into / Type <redacted> into /'; }

service_for() { printf '%s (%s)' "$KEYCHAIN_SERVICE_PREFIX" "$1"; }

# keychain_apple_id <role>: prints the Apple ID stored for the role, or nothing.
keychain_apple_id() {
  security find-generic-password -s "$(service_for "$1")" 2>/dev/null \
    | sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p' | head -1
}

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

[ $# -ge 1 ] || usage

if [ "$1" = "store" ]; then
  role="${2:-}"; case "$role" in owner|partner) ;; *) usage ;; esac
  read -r -p "Apple ID for the $role simulator: " apple_id
  [ -n "$apple_id" ] || die "no Apple ID given"
  echo "Now type that Apple ID's password (asked twice by macOS 'security'; nothing is echoed)."
  # -w as the LAST argument makes `security` prompt for the password itself, so it
  # never appears on a command line or in shell history. -U replaces an older item.
  security add-generic-password -U -s "$(service_for "$role")" -a "$apple_id" \
    -l "$(service_for "$role")" -w
  log "Stored in the login Keychain as \"$(service_for "$role")\"."
  exit 0
fi

role="$1"; shift
case "$role" in
  owner) udid="$OWNER_UDID" ;;
  partner) udid="$PARTNER_UDID" ;;
  *) usage ;;
esac
mode="relogin"
[ "${1:-}" = "--signin-only" ] && mode="signin"

apple_id="$(keychain_apple_id "$role")"
[ -n "$apple_id" ] || die "no Keychain item \"$(service_for "$role")\". Add it once with: Scripts/sim-icloud-relogin.sh store $role"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sim-icloud.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"
SECRET_FILE="$WORK/secret"
( umask 077; security find-generic-password -s "$(service_for "$role")" -a "$apple_id" -w > "$SECRET_FILE" ) \
  || die "could not read the password from the Keychain (did you click Deny?)"

xcrun simctl bootstatus "$udid" -b >/dev/null

# Reuse the smoke build's test products when they exist; otherwise build them once with
# the same Development-CloudKit overrides (so installing the host app never swaps the
# simulator's OurDays for a LOCAL_SIGNING build). Both phases below then run from them.
BUILD_FLAGS=(
  -project "$ROOT_DIR/OurDays.xcodeproj" -scheme OurDays
  -configuration Debug -destination "platform=iOS Simulator,id=$udid"
  -derivedDataPath "$DERIVED"
  CODE_SIGN_ENTITLEMENTS=OurDays/App/OurDays.entitlements
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG"
)
if ! ls "$DERIVED"/Build/Products/*.xctestrun >/dev/null 2>&1; then
  log "No smoke build in $DERIVED yet; building the app and UI tests first..."
  xcodebuild build-for-testing "${BUILD_FLAGS[@]}" -quiet > "$WORK/build.log" 2>&1 \
    || { tail -30 "$WORK/build.log" >&2; die "build-for-testing failed"; }
fi

# run_phase <mode>: drives Settings once with SIM_ICLOUD_MODE=<mode>. Sets $status; on
# failure keeps the redacted log and the test's named screenshots (Settings screens
# only, password fields show dots). The other attachments (the synthesized key events,
# the screen recording, UI snapshots) are not kept: they can hold what was typed.
run_phase() {
  local phase_mode="$1" result="$WORK/$1.xcresult" log_file="$WORK/$1.log"
  set +e
  TEST_RUNNER_SIM_ICLOUD_APPLE_ID="$apple_id" \
  TEST_RUNNER_SIM_ICLOUD_SECRET_FILE="$SECRET_FILE" \
  TEST_RUNNER_SIM_ICLOUD_MODE="$phase_mode" \
  xcodebuild test-without-building "${BUILD_FLAGS[@]}" -resultBundlePath "$result" \
    -only-testing:OurDaysUITests/SimulatorICloudSignInTests/testReSignInToICloud \
    2>&1 | redact_typing > "$log_file"
  status=${PIPESTATUS[0]}
  set -e
  grep -E '\[sim-icloud\]|error:|Test Case .*(passed|failed|skipped)' "$log_file" || true
  if [ "$status" -ne 0 ]; then
    keep="$ROOT_DIR/.screenshots/sim-icloud-$role-$phase_mode-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$keep"
    xcrun xcresulttool export attachments --path "$result" --output-path "$keep" >/dev/null 2>&1 || true
    find "$keep" -type f ! -name '*.png' -delete
    cp "$log_file" "$keep/xcodebuild.log" 2>/dev/null || true
  fi
}

if [ "$mode" = "relogin" ]; then
  log "Signing the $role simulator ($udid) out of iCloud..."
  run_phase signout
  # On iOS 26 the simulator restarts as soon as the sign-out goes through, killing the
  # test runner (so this phase "fails"), and can end up shut down. Restart it cleanly
  # either way; the sign-in phase below then refuses to pass if the account is still there.
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  sleep 10   # let SpringBoard and Settings settle after the boot
  signin_mode="signin-after-signout"
else
  signin_mode="signin"
fi

log "Signing the $role simulator ($udid) in to iCloud as $apple_id..."
run_phase "$signin_mode"
[ "$status" -eq 0 ] || die "Settings automation failed (exit $status). Screenshots and log: $keep"
log "Done: the $role simulator is signed in to iCloud as $apple_id."
