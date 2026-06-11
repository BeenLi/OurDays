#!/usr/bin/env bash
# Automated two-simulator pairing smoke test against the CloudKit Development
# environment. Prerequisites:
#   - Owner simulator signed in to an iCloud account on the Apple Developer team
#   - Partner simulator signed in to another team iCloud account
#   - Both simulators booted (the script boots them if needed)
# Usage: Scripts/dev-pairing-smoke.sh [--skip-build]
set -euo pipefail

OWNER_UDID="${OWNER_UDID:-5509EBC5-44A3-4C7D-862D-2811FA330AF1}"   # iPhone 17
PARTNER_UDID="${PARTNER_UDID:-E75449FE-AD7B-429B-84A5-12ED862B2349}" # iPhone 17 Pro
BUNDLE_ID="com.leeberty.CoupleCalendar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT_DIR/build/dev-smoke"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/CoupleCalendar.app"

log() { printf '\n\033[1;36m[smoke]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[smoke FAILED]\033[0m %s\n' "$*"; exit 1; }

CONSOLE_DIR="$DERIVED/console"
mkdir -p "$CONSOLE_DIR" 2>/dev/null || true

# Launches the app with its stdout captured to a log file. DEBUG builds print
# every sync/sharing log line, which is far more reliable than `log show`
# (info-level OSLog lines are not persisted on simulators).
launch_app() { # launch_app <udid> <console-log-name> [args...]
  local udid="$1" logname="$2"; shift 2
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  sleep 1
  CONSOLE_LOG="$CONSOLE_DIR/$logname.log"
  : > "$CONSOLE_LOG"
  (xcrun simctl launch --console-pty "$udid" "$BUNDLE_ID" "$@" > "$CONSOLE_LOG" 2>&1 &)
}

wait_for_console() { # wait_for_console <console-log> <pattern> <timeout-seconds> <description>
  local logfile="$1" pattern="$2" timeout="$3" description="$4"
  local elapsed=0
  until [ "$elapsed" -ge "$timeout" ]; do
    if grep -qE "$pattern" "$logfile" 2>/dev/null; then
      grep -E "$pattern" "$logfile" | tail -2
      return 0
    fi
    sleep 5; elapsed=$((elapsed + 5))
  done
  echo "--- last console lines ($logfile) ---"; tail -5 "$logfile" 2>/dev/null
  fail "timed out waiting for: $description"
}

seed_defaults() { # skip first-run sheets that would otherwise block automation
  local udid="$1" name="$2"
  xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" currentDisplayName "$name"
  xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" hasCompletedInitialProfilePrompt -bool YES
  xcrun simctl spawn "$udid" defaults write "$BUNDLE_ID" hasResolvedExistingICloudDataPrompt -bool YES
}

# Reads from the app container's plist — the authoritative store for values the
# app wrote. (`simctl spawn defaults read` shows the device-level domain, which
# is only a fallback layer of the app's UserDefaults search list.)
read_default() { # read_default <udid> <key>
  local plist
  plist="$(xcrun simctl get_app_container "$1" "$BUNDLE_ID" data 2>/dev/null)/Library/Preferences/$BUNDLE_ID.plist"
  plutil -extract "$2" raw "$plist" 2>/dev/null || echo "(none)"
}

# ---------- 0. Build & install ----------
# The project's Debug configuration is LOCAL_SIGNING (CloudKit disabled), so the
# smoke build overrides entitlements + compilation conditions on the command
# line to produce a Development-environment CloudKit build.
if [ "${1:-}" != "--skip-build" ]; then
  log "Building Debug app (Development CloudKit overrides)..."
  xcodebuild -project "$ROOT_DIR/CoupleCalendar.xcodeproj" -scheme CoupleCalendar \
    -configuration Debug -destination "platform=iOS Simulator,id=$OWNER_UDID" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_ENTITLEMENTS=CoupleCalendar/CoupleCalendar.entitlements \
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG" \
    build -quiet
fi
[ -d "$APP_PATH" ] || fail "app not found at $APP_PATH"

log "Booting simulators..."
xcrun simctl bootstatus "$OWNER_UDID" -b >/dev/null
xcrun simctl bootstatus "$PARTNER_UDID" -b >/dev/null

# The app's success markers are info-level Logger lines; without this they are
# memory-only and invisible to `log show`.
for udid in "$OWNER_UDID" "$PARTNER_UDID"; do
  xcrun simctl spawn "$udid" log config --mode "level:info,persist:info" \
    --subsystem com.leeberty.CoupleCalendar 2>/dev/null || true
done

log "Resetting app state on both simulators (uninstall + reinstall)..."
xcrun simctl uninstall "$OWNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$PARTNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$OWNER_UDID" "$APP_PATH"
xcrun simctl install "$PARTNER_UDID" "$APP_PATH"
xcrun simctl privacy "$OWNER_UDID" grant calendar "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl privacy "$PARTNER_UDID" grant calendar "$BUNDLE_ID" 2>/dev/null || true
seed_defaults "$OWNER_UDID" "SmokeOwner"
seed_defaults "$PARTNER_UDID" "SmokePartner"

# ---------- 1. Owner: seed event + create share, capture invite URL ----------
log "Owner: seeding test event and preparing pairing share..."
launch_app "$OWNER_UDID" "owner-prepare" -ShareCalSeedCalendarEvent -ShareCalPreparePairingShare
URL_LINE=$(wait_for_console "$CONSOLE_LOG" "ShareCalPairingShareURL:" 120 "owner share URL")
SHARE_URL=$(echo "$URL_LINE" | grep -oE 'https://[^" ]+' | tail -1)
[ -n "$SHARE_URL" ] && [ "$SHARE_URL" != "missing" ] || fail "no share URL captured"
log "Share URL: $SHARE_URL"

# The first automatic sync ran before pairing state existed, so force one more
# sync to upload the seeded event mirror before the partner looks for it.
log "Owner: syncing to upload the seeded event mirror..."
launch_app "$OWNER_UDID" "owner-upload" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "foregroundSync finished" 240 "owner mirror upload sync"

# ---------- 2. Partner: accept share via URL (no system prompt) ----------
log "Partner: accepting owner's share..."
launch_app "$PARTNER_UDID" "partner-accept" -ShareCalAcceptShareURL "$SHARE_URL"
wait_for_console "$CONSOLE_LOG" "acceptShare succeeded" 180 "partner share acceptance"
wait_for_console "$CONSOLE_LOG" "fetchSharedEventMirrors fetched records=[1-9]" 240 \
  "partner importing owner's event mirror"

# ---------- 3. Partner: share back ----------
log "Partner: preparing reverse share..."
launch_app "$PARTNER_UDID" "partner-prepare" \
  -ShareCalSeedCalendarEvent -ShareCalSeedCalendarEventTitle "Partner Smoke Event" \
  -ShareCalPreparePairingShare
URL_LINE2=$(wait_for_console "$CONSOLE_LOG" "ShareCalPairingShareURL:" 120 "partner share URL")
SHARE_URL2=$(echo "$URL_LINE2" | grep -oE 'https://[^" ]+' | tail -1)
[ -n "$SHARE_URL2" ] && [ "$SHARE_URL2" != "missing" ] || fail "no reverse share URL captured"
log "Reverse share URL: $SHARE_URL2"

log "Partner: syncing to upload its event mirror..."
launch_app "$PARTNER_UDID" "partner-upload" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "foregroundSync finished" 240 "partner mirror upload sync"

# ---------- 4. Owner: accept reverse share, verify mutual pairing ----------
log "Owner: accepting partner's share..."
launch_app "$OWNER_UDID" "owner-accept" -ShareCalAcceptShareURL "$SHARE_URL2"
wait_for_console "$CONSOLE_LOG" "acceptShare succeeded" 180 "owner share acceptance"
wait_for_console "$CONSOLE_LOG" "fetchSharedEventMirrors fetched records=[1-9]" 240 \
  "owner importing partner's event mirror"
wait_for_console "$CONSOLE_LOG" "fetchOutgoingShareParticipantIDs succeeded count=1" 240 \
  "owner sees partner as accepted participant (userRecordID available)"

# ---------- 5. Partner: one more sync so it sees the owner joined its share ----------
log "Partner: final sync to confirm mutual state..."
launch_app "$PARTNER_UDID" "partner-final" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "fetchOutgoingShareParticipantIDs succeeded count=1" 240 \
  "partner sees owner as accepted participant"
xcrun simctl terminate "$OWNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl terminate "$PARTNER_UDID" "$BUNDLE_ID" 2>/dev/null || true

# ---------- 6. Verify stored pairing identities ----------
log "Verifying stored pairing state..."
OWNER_ID=$(read_default "$OWNER_UDID" currentMemberID)
OWNER_PARTNER=$(read_default "$OWNER_UDID" partnerShareOwnerID)
PARTNER_ID=$(read_default "$PARTNER_UDID" currentMemberID)
PARTNER_PARTNER=$(read_default "$PARTNER_UDID" partnerShareOwnerID)
echo "Owner   memberID=$OWNER_ID partner=$OWNER_PARTNER"
echo "Partner memberID=$PARTNER_ID partner=$PARTNER_PARTNER"
[ "$OWNER_PARTNER" = "$PARTNER_ID" ] || fail "owner's partner ID != partner's member ID"
[ "$PARTNER_PARTNER" = "$OWNER_ID" ] || fail "partner's partner ID != owner's member ID"

log "✅ PASS: mutual two-person pairing established and events synced both ways."
