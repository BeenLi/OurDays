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

# Console-wait timeouts (seconds), tunable via env. Defaults are generous because a
# CKShare between iCloud accounts in DIFFERENT storage regions (e.g. China GCBD ↔
# US/global) must coordinate across data centers, so share acceptance and the first
# cross-zone read can take minutes. Bump these (or export them higher) for cross-region
# accounts; same-region pairs complete much faster.
SHARE_URL_TIMEOUT="${SHARE_URL_TIMEOUT:-300}"     # create share + log invite URL
SYNC_TIMEOUT="${SYNC_TIMEOUT:-300}"               # a foreground sync to finish
ACCEPT_TIMEOUT="${ACCEPT_TIMEOUT:-900}"           # accept a share (cross-region sensitive)
IMPORT_TIMEOUT="${IMPORT_TIMEOUT:-900}"           # import partner's mirror after accept
PARTICIPANT_TIMEOUT="${PARTICIPANT_TIMEOUT:-900}" # see partner as accepted participant
DIAG_TIMEOUT="${DIAG_TIMEOUT:-900}"               # invitation/comment diagnostic round-trip

# Share acceptance is the cross-region-sensitive step. CloudKit can reject the accept
# with a transient serverRejectedRequest (HTTP 502 ServerHTTPError, CKError code 15)
# when the request has to hop between storage regions (China GCBD ↔ US/global). That
# class is retryable, so re-issue the accept a few times before giving up.
ACCEPT_MAX_ATTEMPTS="${ACCEPT_MAX_ATTEMPTS:-4}"   # total tries per accept (1 + retries)
ACCEPT_RETRY_BACKOFF="${ACCEPT_RETRY_BACKOFF:-15}" # seconds to wait between attempts

log() { printf '\n\033[1;36m[smoke]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[smoke FAILED]\033[0m %s\n' "$*"; exit 1; }

CONSOLE_DIR="$DERIVED/console"
mkdir -p "$CONSOLE_DIR" 2>/dev/null || true

# Launches the app with its stdout captured to a log file. DEBUG builds print
# every sync/sharing log line, which is far more reliable than `log show`
# (info-level OSLog lines are not persisted on simulators).
launch_app() { # launch_app <udid> <console-log-name> [args...]
  local udid="$1" logname="$2"; shift 2
  # Seed the profile in the app's OWN UserDefaults so the first-run nickname /
  # existing-iCloud-data sheets never block automation. (seed_defaults writes the
  # device-level domain, which iOS does not reliably merge as the app's fallback.)
  local profile_name="SmokeUser"
  [ "$udid" = "$OWNER_UDID" ] && profile_name="SmokeOwner"
  [ "$udid" = "$PARTNER_UDID" ] && profile_name="SmokePartner"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  sleep 1
  CONSOLE_LOG="$CONSOLE_DIR/$logname.log"
  : > "$CONSOLE_LOG"
  (xcrun simctl launch --console-pty "$udid" "$BUNDLE_ID" \
     -ShareCalSeedProfileName "$profile_name" "$@" > "$CONSOLE_LOG" 2>&1 &)
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

# Launches the accept-share diagnostic and waits for `acceptShare succeeded`, retrying
# the whole launch on a transient CloudKit serverRejectedRequest / 502 ServerHTTPError.
# A non-transient acceptShare failure (e.g. permissionFailure) fails immediately so we
# never paper over a real bug. Leaves CONSOLE_LOG pointing at the winning attempt's log
# so the caller's follow-up wait_for_console (import, participants) reads the right file.
accept_share_with_retry() { # accept_share_with_retry <udid> <console-log-name> <share-url> <description>
  local udid="$1" logname="$2" url="$3" description="$4"
  # Markers that classify a failed accept as a retryable cross-region server hiccup.
  local transient_re='http status code 5[0-9][0-9]|ServerHTTPError|rawValue: 15|15/2001'
  local attempt=1
  while [ "$attempt" -le "$ACCEPT_MAX_ATTEMPTS" ]; do
    log "Accepting share (attempt $attempt/$ACCEPT_MAX_ATTEMPTS): $description"
    launch_app "$udid" "$logname" -ShareCalAcceptShareURL "$url"
    local logfile="$CONSOLE_LOG" elapsed=0
    while [ "$elapsed" -lt "$ACCEPT_TIMEOUT" ]; do
      if grep -qE "acceptShare succeeded" "$logfile" 2>/dev/null; then
        grep -E "acceptShare succeeded" "$logfile" | tail -1
        return 0
      fi
      if grep -qE "acceptShare failed" "$logfile" 2>/dev/null; then
        local failline; failline="$(grep -E "acceptShare failed" "$logfile" | tail -1)"
        if echo "$failline" | grep -qE "$transient_re"; then
          echo "--- transient CloudKit error (will retry) ---"; echo "$failline"
          break # break the poll loop → relaunch and retry
        fi
        echo "--- non-transient acceptShare failure ---"; echo "$failline"
        fail "share acceptance failed with a non-retryable error: $description"
      fi
      sleep 5; elapsed=$((elapsed + 5))
    done
    if [ "$elapsed" -ge "$ACCEPT_TIMEOUT" ]; then
      echo "--- attempt $attempt produced no success/failure marker in ${ACCEPT_TIMEOUT}s ---"
      tail -5 "$logfile" 2>/dev/null
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$ACCEPT_MAX_ATTEMPTS" ] && sleep "$ACCEPT_RETRY_BACKOFF"
  done
  echo "--- last console lines ($CONSOLE_LOG) ---"; tail -8 "$CONSOLE_LOG" 2>/dev/null
  fail "share acceptance did not succeed after $ACCEPT_MAX_ATTEMPTS attempts: $description"
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
URL_LINE=$(wait_for_console "$CONSOLE_LOG" "ShareCalPairingShareURL:" $SHARE_URL_TIMEOUT "owner share URL")
SHARE_URL=$(echo "$URL_LINE" | grep -oE 'https://[^" ]+' | tail -1)
[ -n "$SHARE_URL" ] && [ "$SHARE_URL" != "missing" ] || fail "no share URL captured"
log "Share URL: $SHARE_URL"

# The first automatic sync ran before pairing state existed, so force one more
# sync to upload the seeded event mirror before the partner looks for it.
log "Owner: syncing to upload the seeded event mirror..."
launch_app "$OWNER_UDID" "owner-upload" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "foregroundSync finished" $SYNC_TIMEOUT "owner mirror upload sync"

# ---------- 2. Partner: accept share via URL (no system prompt) ----------
log "Partner: accepting owner's share..."
accept_share_with_retry "$PARTNER_UDID" "partner-accept" "$SHARE_URL" "partner share acceptance"
wait_for_console "$CONSOLE_LOG" "fetchSharedEventMirrors fetched records=[1-9]" $IMPORT_TIMEOUT \
  "partner importing owner's event mirror"

# ---------- 3. Partner: share back ----------
log "Partner: preparing reverse share..."
launch_app "$PARTNER_UDID" "partner-prepare" \
  -ShareCalSeedCalendarEvent -ShareCalSeedCalendarEventTitle "Partner Smoke Event" \
  -ShareCalPreparePairingShare
URL_LINE2=$(wait_for_console "$CONSOLE_LOG" "ShareCalPairingShareURL:" $SHARE_URL_TIMEOUT "partner share URL")
SHARE_URL2=$(echo "$URL_LINE2" | grep -oE 'https://[^" ]+' | tail -1)
[ -n "$SHARE_URL2" ] && [ "$SHARE_URL2" != "missing" ] || fail "no reverse share URL captured"
log "Reverse share URL: $SHARE_URL2"

log "Partner: syncing to upload its event mirror..."
launch_app "$PARTNER_UDID" "partner-upload" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "foregroundSync finished" $SYNC_TIMEOUT "partner mirror upload sync"

# ---------- 4. Owner: accept reverse share, verify mutual pairing ----------
log "Owner: accepting partner's share..."
accept_share_with_retry "$OWNER_UDID" "owner-accept" "$SHARE_URL2" "owner share acceptance"
wait_for_console "$CONSOLE_LOG" "fetchSharedEventMirrors fetched records=[1-9]" $IMPORT_TIMEOUT \
  "owner importing partner's event mirror"
wait_for_console "$CONSOLE_LOG" "fetchOutgoingShareParticipantIDs succeeded count=1" $PARTICIPANT_TIMEOUT \
  "owner sees partner as accepted participant (userRecordID available)"

# ---------- 5. Partner: one more sync so it sees the owner joined its share ----------
log "Partner: final sync to confirm mutual state..."
launch_app "$PARTNER_UDID" "partner-final" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "fetchOutgoingShareParticipantIDs succeeded count=1" $PARTICIPANT_TIMEOUT \
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

# ---------- 7. Verify the partner's calendar UI renders the owner's event ----------
# The checks above prove the pairing/sync STATE is correct (stored fields + log lines).
# This step proves the SwiftUI calendar actually DRAWS the owner's synced event, i.e.
# the background sync reaches the UI. It relaunches the partner app (install-over-install
# preserves the paired SwiftData cache + UserDefaults) and runs a single XCUITest gated
# by SHARECAL_SMOKE_UI so the ordinary UI suite stays green on an unpaired simulator.
log "Partner: verifying calendar UI renders owner's synced event (XCUITest)..."
UI_RESULT="$DERIVED/ui-verify.xcresult"
rm -rf "$UI_RESULT"
TEST_RUNNER_SHARECAL_SMOKE_UI=1 xcodebuild test \
  -project "$ROOT_DIR/CoupleCalendar.xcodeproj" -scheme CoupleCalendar \
  -configuration Debug -destination "platform=iOS Simulator,id=$PARTNER_UDID" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$UI_RESULT" \
  -only-testing:CoupleCalendarUITests/CoupleCalendarUITests/testPairedPartnerCalendarShowsOwnerEvent \
  CODE_SIGN_ENTITLEMENTS=CoupleCalendar/CoupleCalendar.entitlements \
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG" \
  -quiet || fail "partner calendar UI did not render the owner's synced event (see $UI_RESULT)"
log "Partner calendar UI rendered the owner's synced event (screenshot in $UI_RESULT)."

# ---------- 8. Joint event: owner invites, partner accepts ----------
# Exercises req2 (invitation sync) + sets up req1 (joint event). The owner seeds an
# invitation matching its smoke event; the partner syncs, accepts (real EventKit event so
# it isn't auto-canceled), and uploads the acceptance.
log "Owner: seeding invitation for the smoke event..."
launch_app "$OWNER_UDID" "owner-seed-invite" -ShareCalSeedInvitation
wait_for_console "$CONSOLE_LOG" "ShareCalDiag seedInvitation succeeded" $DIAG_TIMEOUT "owner seeds invitation"

log "Partner: accepting the invitation (creates joint event)..."
launch_app "$PARTNER_UDID" "partner-accept-invite" -ShareCalAcceptInvitation
wait_for_console "$CONSOLE_LOG" "ShareCalDiag acceptInvitation succeeded" $DIAG_TIMEOUT "partner accepts invitation"

# ---------- 9. Joint comment symmetry: owner comments → partner sees → replies → owner sees ----------
OWNER_COMMENT="owner-hello-$RANDOM"
PARTNER_COMMENT="partner-reply-$RANDOM"

log "Owner: commenting on the joint event ('$OWNER_COMMENT')..."
launch_app "$OWNER_UDID" "owner-comment" -ShareCalAddJointComment "$OWNER_COMMENT"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag addJointComment succeeded" $DIAG_TIMEOUT "owner adds joint comment"

log "Partner: probing joint comments (must see the owner's comment)..."
launch_app "$PARTNER_UDID" "partner-probe1" -ShareCalProbeJointComments
PARTNER_PROBE1=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag jointComments count=" $DIAG_TIMEOUT "partner probes joint comments")
echo "$PARTNER_PROBE1" | grep -q "$OWNER_COMMENT" \
  || fail "partner did NOT see the owner's joint comment ('$OWNER_COMMENT'). Probe: $PARTNER_PROBE1"
log "Partner sees the owner's comment ✓"

log "Partner: replying on the joint event ('$PARTNER_COMMENT')..."
launch_app "$PARTNER_UDID" "partner-reply" -ShareCalAddJointComment "$PARTNER_COMMENT"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag addJointComment succeeded" $DIAG_TIMEOUT "partner adds joint reply"

log "Owner: probing joint comments (must see BOTH comments = symmetric thread)..."
launch_app "$OWNER_UDID" "owner-probe2" -ShareCalProbeJointComments
OWNER_PROBE2=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag jointComments count=" $DIAG_TIMEOUT "owner probes joint comments")
echo "$OWNER_PROBE2" | grep -q "$OWNER_COMMENT" \
  || fail "owner lost its own joint comment ('$OWNER_COMMENT'). Probe: $OWNER_PROBE2"
echo "$OWNER_PROBE2" | grep -q "$PARTNER_COMMENT" \
  || fail "owner did NOT see the partner's reply ('$PARTNER_COMMENT') — thread is NOT symmetric. Probe: $OWNER_PROBE2"
log "Owner sees BOTH comments ✓ (joint comment thread is symmetric)"

xcrun simctl terminate "$OWNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl terminate "$PARTNER_UDID" "$BUNDLE_ID" 2>/dev/null || true

log "✅ PASS: mutual two-person pairing established, events synced both ways, the partner UI renders the owner's event, and a joint event's comment thread is shared symmetrically across both partners."
