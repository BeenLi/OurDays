#!/usr/bin/env bash
# Automated two-simulator pairing smoke test against the CloudKit Development
# environment. Prerequisites:
#   - Owner simulator signed in to an iCloud account on the Apple Developer team
#   - Partner simulator signed in to another team iCloud account
#   - Both simulators booted (the script boots them if needed)
# Usage: Scripts/dev-pairing-smoke.sh [--skip-build]
#   SKIP_ICLOUD_PRECHECK=1 skips the cloudd AuthTokenError (2011) precheck.
set -euo pipefail

OWNER_UDID="${OWNER_UDID:-AF9A93BC-6151-4C6D-B5F7-E4F5053351E2}"   # iPhone 17
PARTNER_UDID="${PARTNER_UDID:-244DFAAC-93A7-4BE7-AEA0-4F0A52ABA7D6}" # iPhone 17 Pro
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
  # SMOKE_FRESH_INSTALL=1 skips the seeding: the reinstall step must look exactly like a
  # user's fresh install so the recovery path has to bring the nickname back itself.
  local profile_name="SmokeUser"
  [ "$udid" = "$OWNER_UDID" ] && profile_name="SmokeOwner"
  [ "$udid" = "$PARTNER_UDID" ] && profile_name="SmokePartner"
  local seed_args=(-ShareCalSeedProfileName "$profile_name")
  [ "${SMOKE_FRESH_INSTALL:-0}" = "1" ] && seed_args=()
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  sleep 1
  CONSOLE_LOG="$CONSOLE_DIR/$logname.log"
  : > "$CONSOLE_LOG"
  (xcrun simctl launch --console-pty "$udid" "$BUNDLE_ID" \
     ${seed_args[@]+"${seed_args[@]}"} "$@" > "$CONSOLE_LOG" 2>&1 &)
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
  # plutil prints "missing file/key" errors on *stdout*, so test the exit code
  # instead of relying on `|| echo`.
  local value
  if value="$(plutil -extract "$2" raw "$plist" 2>/dev/null)"; then
    echo "$value"
  else
    echo "(none)"
  fi
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
    CODE_SIGN_ENTITLEMENTS=CoupleCalendar/App/CoupleCalendar.entitlements \
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG" \
    build -quiet
fi
[ -d "$APP_PATH" ] || fail "app not found at $APP_PATH"

log "Booting simulators..."
xcrun simctl bootstatus "$OWNER_UDID" -b >/dev/null
xcrun simctl bootstatus "$PARTNER_UDID" -b >/dev/null

# ---------- 0b. iCloud token precheck ----------
# Simulator iCloud sessions expire on their own (Apple-side token policy; nothing
# local extends them). When that happens cloudd logs `AuthTokenError (2011)` for
# every CloudKit call and the app never logs a share URL, so the run only fails
# after the first console-wait timeout (~5-10 min). Look at cloudd's recent log
# first and fail fast with a re-login hint instead. The check is skipped when
# cloudd has no recent activity (fresh boot). SKIP_ICLOUD_PRECHECK=1 bypasses it.
ICLOUD_PRECHECK_WINDOW="${ICLOUD_PRECHECK_WINDOW:-15m}"
icloud_precheck() { # icloud_precheck <udid> <label>
  local udid="$1" label="$2" last
  last=$(xcrun simctl spawn "$udid" log show --last "$ICLOUD_PRECHECK_WINDOW" \
           --style compact --predicate 'process == "cloudd"' 2>/dev/null \
         | grep -E 'AuthTokenError|Finished' | tail -1 || true)
  if [ -z "$last" ]; then
    log "$label: no cloudd activity in the last $ICLOUD_PRECHECK_WINDOW, skipping iCloud token check."
  elif printf '%s' "$last" | grep -q AuthTokenError; then
    fail "$label simulator's iCloud session has expired (cloudd: AuthTokenError 2011). Open Settings on the simulator, sign in to iCloud again, then rerun. Last line: $last"
  else
    log "$label: cloudd completed a CloudKit operation recently, iCloud token looks valid."
  fi
}
if [ "${SKIP_ICLOUD_PRECHECK:-0}" != "1" ]; then
  log "Checking simulators' iCloud tokens (cloudd log, last $ICLOUD_PRECHECK_WINDOW)..."
  icloud_precheck "$OWNER_UDID" "Owner"
  icloud_precheck "$PARTNER_UDID" "Partner"
fi

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
  CODE_SIGN_ENTITLEMENTS=CoupleCalendar/App/CoupleCalendar.entitlements \
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

# ---------- 9b. Own-event thread: owner comments FIRST on its own fresh event → partner sees → replies → owner sees ----------
# A comment on my own event is keyed by the mirrorKey (== the persisted record's id on both
# devices), so the owner can start the thread before the mirror has synced; the mirror lands
# on the following sync and the partner finds the comment under the imported event. The
# partner's reply goes into the owner's shared zone, and the owner reads it back.
OWN_EVENT_TITLE="Own Comment Event"
OWN_COMMENT="own-first-$RANDOM"
OWN_REPLY="partner-on-own-$RANDOM"

log "Owner: creating a fresh own event and commenting on it right away ('$OWN_COMMENT')..."
launch_app "$OWNER_UDID" "owner-own-comment" \
  -ShareCalSeedCalendarEvent -ShareCalSeedCalendarEventTitle "$OWN_EVENT_TITLE" \
  -ShareCalAddEventComment "$OWN_COMMENT" -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
OWN_ADD=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag addEventComment succeeded" $DIAG_TIMEOUT "owner comments on its own event")
echo "$OWN_ADD" | grep -q "via=own" \
  || fail "owner's comment did not take the own-event (display mirror) path. Log: $OWN_ADD"

log "Partner: probing '$OWN_EVENT_TITLE' comments (must see the owner's comment)..."
launch_app "$PARTNER_UDID" "partner-own-probe1" -ShareCalProbeEventComments -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
PARTNER_OWN_PROBE1=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "partner probes the owner's own-event thread")
echo "$PARTNER_OWN_PROBE1" | grep -q "$OWN_COMMENT" \
  || fail "partner did NOT see the owner's comment on the owner's own event ('$OWN_COMMENT'). Probe: $PARTNER_OWN_PROBE1"
log "Partner sees the owner's own-event comment ✓"

log "Partner: replying on the owner's event ('$OWN_REPLY')..."
launch_app "$PARTNER_UDID" "partner-own-reply" -ShareCalAddEventComment "$OWN_REPLY" -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
OWN_REPLY_ADD=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag addEventComment succeeded" $DIAG_TIMEOUT "partner replies on the owner's event")
echo "$OWN_REPLY_ADD" | grep -q "via=persisted" \
  || fail "partner's reply did not resolve the imported (persisted) mirror. Log: $OWN_REPLY_ADD"

log "Owner: probing '$OWN_EVENT_TITLE' comments (must see BOTH comments)..."
launch_app "$OWNER_UDID" "owner-own-probe2" -ShareCalProbeEventComments -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
OWNER_OWN_PROBE2=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "owner probes its own-event thread")
echo "$OWNER_OWN_PROBE2" | grep -q "$OWN_COMMENT" \
  || fail "owner lost its own comment ('$OWN_COMMENT') on its own event. Probe: $OWNER_OWN_PROBE2"
echo "$OWNER_OWN_PROBE2" | grep -q "$OWN_REPLY" \
  || fail "owner did NOT see the partner's reply ('$OWN_REPLY') on its own event. Probe: $OWNER_OWN_PROBE2"
log "Owner sees BOTH comments on its own event ✓ (own-event thread is symmetric)"

# ---------- 10. Joint event UI: tapping the green block opens the comment thread ----------
# Steps 8-9 prove the comment DATA pipeline; this proves the partner can actually REACH it
# from the calendar UI — the green joint block must be tappable and open the comment thread
# (regression guard for making the block a Button instead of an offset .onTapGesture).
log "Partner: verifying the joint event opens its comment thread on tap (XCUITest)..."
JOINT_UI_RESULT="$DERIVED/joint-comment-ui.xcresult"
rm -rf "$JOINT_UI_RESULT"
TEST_RUNNER_SHARECAL_SMOKE_UI=1 xcodebuild test \
  -project "$ROOT_DIR/CoupleCalendar.xcodeproj" -scheme CoupleCalendar \
  -configuration Debug -destination "platform=iOS Simulator,id=$PARTNER_UDID" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$JOINT_UI_RESULT" \
  -only-testing:CoupleCalendarUITests/CoupleCalendarUITests/testPairedPartnerCanOpenJointEventCommentThread \
  CODE_SIGN_ENTITLEMENTS=CoupleCalendar/App/CoupleCalendar.entitlements \
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG" \
  -quiet || fail "partner could not open the joint event's comment thread from the UI (see $JOINT_UI_RESULT)"
log "Partner opened the joint event comment thread from the UI (screenshot in $JOINT_UI_RESULT)."

# ---------- 11. Withdraw: owner invites again → partner sees pending → owner withdraws → partner sees canceled ----------
# Exercises the sender-side withdrawal (InvitationService.cancel + upload to the creator's
# zone) and the partner's import applying the terminal `canceled` over its `pending` copy.
# Runs after the UI steps: the second invitation shares the smoke event's title and, once
# canceled, sorts above the accepted row in the invites list, which would mislead the
# title-based tap in step 10's XCUITest.
log "Owner: seeding a second invitation (to be withdrawn)..."
launch_app "$OWNER_UDID" "owner-seed-invite2" -ShareCalSeedInvitation
SEED2=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag seedInvitation succeeded" $DIAG_TIMEOUT "owner seeds second invitation")
WITHDRAW_ID=$(echo "$SEED2" | sed -n 's/.*seedInvitation succeeded id=\([^ ]*\).*/\1/p' | tail -1)
[ -n "$WITHDRAW_ID" ] || fail "could not parse the seeded invitation id from: $SEED2"

log "Partner: probing invitations (must see $WITHDRAW_ID as pending)..."
launch_app "$PARTNER_UDID" "partner-probe-invites1" -ShareCalProbeInvitations
PARTNER_INVITES1=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag invitations count=" $DIAG_TIMEOUT "partner probes invitations")
echo "$PARTNER_INVITES1" | grep -q "$WITHDRAW_ID:pending" \
  || fail "partner did NOT receive the second invitation as pending. Probe: $PARTNER_INVITES1"
log "Partner sees the second invitation as pending ✓"

log "Owner: withdrawing invitation $WITHDRAW_ID..."
launch_app "$OWNER_UDID" "owner-withdraw-invite" -ShareCalWithdrawInvitation "$WITHDRAW_ID"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag withdrawInvitation succeeded" $DIAG_TIMEOUT "owner withdraws invitation"

log "Partner: probing invitations (must now see $WITHDRAW_ID as canceled)..."
launch_app "$PARTNER_UDID" "partner-probe-invites2" -ShareCalProbeInvitations
PARTNER_INVITES2=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag invitations count=" $DIAG_TIMEOUT "partner probes invitations after withdrawal")
echo "$PARTNER_INVITES2" | grep -q "$WITHDRAW_ID:canceled" \
  || fail "partner still does NOT see the withdrawn invitation as canceled. Probe: $PARTNER_INVITES2"
log "Partner sees the withdrawn invitation as canceled ✓"

# ---------- 12. Delete & reinstall: the owner recovers everything from iCloud ----------
# A user who deletes the app loses only the local cache + UserDefaults; every paired record
# survives in CloudKit. This proves the 「发现旧的 iCloud 数据 → 继续使用」 path (run through
# its diagnostic twin) restores the pairing, the nickname and the imported data on a truly
# fresh install, and that an event deleted WHILE the app was gone is tombstoned for the
# partner (OwnMirrorReconciliationPolicy) instead of living on as a ghost.
log "Owner: syncing once so the next launch's automatic sync is throttled..."
launch_app "$OWNER_UDID" "owner-presync" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "foregroundSync finished" $SYNC_TIMEOUT "owner pre-delete sync"

log "Owner: deleting the smoke event from the system calendar without syncing..."
# Launched within the 60 s automatic-sync throttle, so the deletion is NOT observed by
# this install; the reinstall must discover it from its own cloud mirrors.
launch_app "$OWNER_UDID" "owner-delete-event" -ShareCalDeleteCalendarEventTitled "ShareCal E2E Smoke Test"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag deleteCalendarEvent succeeded title=.* count=[1-9]" $DIAG_TIMEOUT \
  "owner deletes the smoke event from the system calendar"
xcrun simctl terminate "$OWNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
grep -q "foregroundSync finished" "$CONSOLE_LOG" \
  && fail "the delete-event launch ran a sync, so the reinstall step cannot prove the ghost-event tombstone; rerun"
OWNER_NAME_BEFORE=$(read_default "$OWNER_UDID" currentDisplayName)

log "Owner: deleting and reinstalling the app (fresh install, no seeded defaults)..."
xcrun simctl uninstall "$OWNER_UDID" "$BUNDLE_ID"
xcrun simctl install "$OWNER_UDID" "$APP_PATH"
xcrun simctl privacy "$OWNER_UDID" grant calendar "$BUNDLE_ID" 2>/dev/null || true
# get_app_container can still point at the old container for a moment after
# uninstall; give it a few seconds before concluding the defaults survived.
for _ in $(seq 1 30); do
  [ "$(read_default "$OWNER_UDID" partnerShareOwnerID)" = "(none)" ] && break
  sleep 1
done
[ "$(read_default "$OWNER_UDID" partnerShareOwnerID)" = "(none)" ] \
  || fail "uninstall did not clear the owner's UserDefaults (partnerShareOwnerID=$(read_default "$OWNER_UDID" partnerShareOwnerID))"

log "Owner: recovering from existing iCloud data (the 「继续使用现有 iCloud 数据」 path)..."
SMOKE_FRESH_INSTALL=1 launch_app "$OWNER_UDID" "owner-recover" -ShareCalRecoverExistingICloudData
RECOVERY=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag recoverExistingICloudData result" $DIAG_TIMEOUT "owner recovers from iCloud")
echo "$RECOVERY" | grep -q "phase=idle" || fail "recovery sync did not finish cleanly: $RECOVERY"
echo "$RECOVERY" | grep -q "partner=$PARTNER_ID " || fail "recovery did not restore the pairing (expected partner=$PARTNER_ID): $RECOVERY"
echo "$RECOVERY" | grep -q "hasStartedPairing=1" || fail "recovery did not mark pairing as started: $RECOVERY"
echo "$RECOVERY" | grep -q "displayName=$OWNER_NAME_BEFORE " || fail "recovery did not restore the owner's nickname '$OWNER_NAME_BEFORE': $RECOVERY"
echo "$RECOVERY" | grep -qE "partnerMirrors=[1-9]" || fail "recovery did not import the partner's events: $RECOVERY"
echo "$RECOVERY" | grep -qE "comments=[1-9]" || fail "recovery did not bring the comments back: $RECOVERY"
echo "$RECOVERY" | grep -qE "invitations=[1-9]" || fail "recovery did not bring the invitations back: $RECOVERY"
grep -qE "cloudOwnMirrorsReconciled cloud=[1-9][0-9]* tombstones=[1-9]" "$CONSOLE_LOG" \
  || fail "the reinstall did not tombstone the event deleted while the app was gone (ghost event). Console: $(grep -E 'cloudOwnMirrorsReconciled|saveMirrorsForSync' "$CONSOLE_LOG" | tail -3)"
log "Owner recovered pairing, nickname, partner events, comments and invitations from iCloud, and tombstoned the ghost event ✓"
xcrun simctl terminate "$OWNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
[ "$(read_default "$OWNER_UDID" partnerShareOwnerID)" = "$PARTNER_ID" ] || fail "recovered partnerShareOwnerID was not persisted"

xcrun simctl terminate "$OWNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl terminate "$PARTNER_UDID" "$BUNDLE_ID" 2>/dev/null || true

log "✅ PASS: mutual two-person pairing established, events synced both ways, the partner UI renders the owner's event, a withdrawn invitation reads canceled on the partner's side, a joint event's comment thread is shared symmetrically across both partners, a thread the owner starts on its own event reaches the partner and takes the reply, the joint block opens its comment thread on tap, and a delete-and-reinstall recovers the pairing from iCloud and tombstones the ghost event."
