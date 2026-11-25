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
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/OurDays.app"

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

# Every log line carries the time since the script started, so a run's output shows
# where the minutes went. Both go to stderr: most waits run inside `$(...)`, where a
# failure message on stdout would be swallowed by the capture.
elapsed_stamp() { printf '+%dm%02ds' $((SECONDS / 60)) $((SECONDS % 60)); }
log() { printf '\n\033[1;36m[smoke %s]\033[0m %s\n' "$(elapsed_stamp)" "$*" >&2; }
fail() { printf '\n\033[1;31m[smoke FAILED %s]\033[0m %s\n' "$(elapsed_stamp)" "$*" >&2; exit 1; }

# A diagnostic that gave up logs one of these and never logs its success marker, so
# waiting out the full timeout (15 min by default) only delays the failure.
DIAG_FAILURE_RE='ShareCalDiag [A-Za-z]+ failed|ShareCalDiag acceptInvitation none-pending|ShareCal prepare pairing share probe failed|ShareCal failed to seed calendar event'
POLL_INTERVAL="${POLL_INTERVAL:-1}"               # seconds between console checks

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
  local deadline=$((SECONDS + timeout))
  until [ "$SECONDS" -ge "$deadline" ]; do
    if grep -qE "$pattern" "$logfile" 2>/dev/null; then
      grep -E "$pattern" "$logfile" | tail -2
      return 0
    fi
    if grep -qE "$DIAG_FAILURE_RE" "$logfile" 2>/dev/null; then
      grep -E "$DIAG_FAILURE_RE" "$logfile" | tail -2 >&2
      fail "the app reported a failure while waiting for: $description (see $logfile)"
    fi
    sleep "$POLL_INTERVAL"
  done
  { echo "--- last console lines ($logfile) ---"; tail -5 "$logfile" 2>/dev/null; } >&2
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
  # The second marker is the share-metadata fetch failing before the accept even starts.
  local accept_failure_re='acceptShare failed|ShareCal accept share probe failed'
  local attempt=1
  while [ "$attempt" -le "$ACCEPT_MAX_ATTEMPTS" ]; do
    log "Accepting share (attempt $attempt/$ACCEPT_MAX_ATTEMPTS): $description"
    launch_app "$udid" "$logname" -ShareCalAcceptShareURL "$url"
    local logfile="$CONSOLE_LOG" deadline=$((SECONDS + ACCEPT_TIMEOUT))
    while [ "$SECONDS" -lt "$deadline" ]; do
      if grep -qE "acceptShare succeeded" "$logfile" 2>/dev/null; then
        grep -E "acceptShare succeeded" "$logfile" | tail -1
        return 0
      fi
      if grep -qE "$accept_failure_re" "$logfile" 2>/dev/null; then
        local failline; failline="$(grep -E "$accept_failure_re" "$logfile" | tail -1)"
        if echo "$failline" | grep -qE "$transient_re"; then
          echo "--- transient CloudKit error (will retry) ---"; echo "$failline"
          break # break the poll loop → relaunch and retry
        fi
        echo "--- non-transient acceptShare failure ---"; echo "$failline"
        fail "share acceptance failed with a non-retryable error: $description"
      fi
      sleep "$POLL_INTERVAL"
    done
    if [ "$SECONDS" -ge "$deadline" ]; then
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
# `build-for-testing` also builds the UI-test runner, so the two XCUITest steps below
# start straight away (`test-without-building`) instead of each re-running the build.
# With --skip-build nothing is known about the test products, so those steps fall back
# to a plain `test`, which builds whatever is missing.
UI_TEST_ACTION="test"
if [ "${1:-}" != "--skip-build" ]; then
  log "Building Debug app and UI tests (Development CloudKit overrides)..."
  xcodebuild -project "$ROOT_DIR/OurDays.xcodeproj" -scheme OurDays \
    -configuration Debug -destination "platform=iOS Simulator,id=$OWNER_UDID" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_ENTITLEMENTS=OurDays/App/OurDays.entitlements \
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG" \
    build-for-testing -quiet
  UI_TEST_ACTION="test-without-building"
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

# ---------- 0c. Clear what earlier runs left behind ----------
# Both test accounts are reused by every run, and their iCloud data survives the
# uninstall below: comments and invitations piled up (the joint thread grew by two
# comments per run until its input field scrolled off screen), and a run that failed
# halfway left its throwaway events in the calendar. Each side deletes the comment and
# invitation records in its own private zone, which is where both partners' writes on
# its events live, plus the leftover events. It runs before the reset so the pairing
# flow starts from a fresh install that never saw the old records.
purge_test_data() { # purge_test_data <udid> <console-log-name> <label>
  xcrun simctl install "$1" "$APP_PATH"
  xcrun simctl privacy "$1" grant calendar "$BUNDLE_ID" 2>/dev/null || true
  launch_app "$1" "$2" -ShareCalPurgeSmokeTestData
  local purged
  purged=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag purgeSmokeTestData succeeded" $SYNC_TIMEOUT "$3 clears earlier runs' test data")
  log "$3: ${purged##*purgeSmokeTestData succeeded }"
  xcrun simctl terminate "$1" "$BUNDLE_ID" 2>/dev/null || true
}
log "Clearing comments, invitations and leftover events from earlier runs..."
purge_test_data "$OWNER_UDID" "owner-purge" "Owner"
purge_test_data "$PARTNER_UDID" "partner-purge" "Partner"

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
TEST_RUNNER_SHARECAL_SMOKE_UI=1 xcodebuild "$UI_TEST_ACTION" \
  -project "$ROOT_DIR/OurDays.xcodeproj" -scheme OurDays \
  -configuration Debug -destination "platform=iOS Simulator,id=$PARTNER_UDID" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$UI_RESULT" \
  -only-testing:OurDaysUITests/OurDaysUITests/testPairedPartnerCalendarShowsOwnerEvent \
  CODE_SIGN_ENTITLEMENTS=OurDays/App/OurDays.entitlements \
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
# A title of its own per run: the comment diags pick the first event (and cloud mirror)
# with this title, and mirrors from earlier runs outside the sync window are never
# tombstoned, so a shared title can resolve to an old run's event.
OWN_EVENT_TITLE="Own Comment Event $RANDOM"
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

# ---------- 9c. Reschedule: the owner moves the commented event one hour later ----------
# The record is named after the event's start time; a moved one-off event keeps its first
# name (EventMirrorKeyPolicy.keptKeysForRescheduledEvents), so both comments stay on it.
log "Owner: moving '$OWN_EVENT_TITLE' one hour later (the next probe syncs it)..."
launch_app "$OWNER_UDID" "owner-own-move" -ShareCalMoveCalendarEventTitled "$OWN_EVENT_TITLE"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag moveCalendarEvent succeeded title=.* count=1" $DIAG_TIMEOUT \
  "owner moves its commented event" >/dev/null

log "Owner: probing '$OWN_EVENT_TITLE' comments after the move (must still see BOTH)..."
launch_app "$OWNER_UDID" "owner-own-probe3" -ShareCalProbeEventComments -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
OWNER_OWN_PROBE3=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "owner probes after the move")
echo "$OWNER_OWN_PROBE3" | grep -q "$OWN_COMMENT" && echo "$OWNER_OWN_PROBE3" | grep -q "$OWN_REPLY" \
  || fail "owner lost comments after moving its event. Probe: $OWNER_OWN_PROBE3"

log "Partner: probing '$OWN_EVENT_TITLE' comments after the move (must still see BOTH)..."
launch_app "$PARTNER_UDID" "partner-own-probe3" -ShareCalProbeEventComments -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
PARTNER_OWN_PROBE3=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "partner probes after the move")
echo "$PARTNER_OWN_PROBE3" | grep -q "$OWN_COMMENT" && echo "$PARTNER_OWN_PROBE3" | grep -q "$OWN_REPLY" \
  || fail "partner lost comments after the owner moved the event. Probe: $PARTNER_OWN_PROBE3"
log "Both sides keep BOTH comments after the move ✓"

# ---------- 9d. Delete: each side deletes its own comment; it disappears on BOTH sides ----------
# A delete is a soft delete (deletedAt) written to the comment's own record in the event
# owner's zone. The partner's reply lives in the OWNER's zone (written via the shared DB),
# so this covers both routes; a following sync must not bring either back (decision 0005).
log "Partner: deleting its reply ('$OWN_REPLY')..."
launch_app "$PARTNER_UDID" "partner-own-delete" -ShareCalDeleteEventComment "$OWN_REPLY" -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag deleteEventComment succeeded .*stillDeletedAfterSync=true" $DIAG_TIMEOUT \
  "partner deletes its reply (and it stays deleted after a sync)" >/dev/null

log "Owner: probing '$OWN_EVENT_TITLE' comments (the reply must be gone, own comment kept)..."
launch_app "$OWNER_UDID" "owner-own-probe4" -ShareCalProbeEventComments -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
OWNER_OWN_PROBE4=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "owner probes after the partner's delete")
echo "$OWNER_OWN_PROBE4" | grep -q "$OWN_REPLY" \
  && fail "owner still sees the partner's deleted reply ('$OWN_REPLY'). Probe: $OWNER_OWN_PROBE4"
echo "$OWNER_OWN_PROBE4" | grep -q "$OWN_COMMENT" \
  || fail "owner lost its own comment when the partner deleted theirs. Probe: $OWNER_OWN_PROBE4"

log "Owner: deleting its own comment ('$OWN_COMMENT')..."
launch_app "$OWNER_UDID" "owner-own-delete" -ShareCalDeleteEventComment "$OWN_COMMENT" -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag deleteEventComment succeeded .*stillDeletedAfterSync=true" $DIAG_TIMEOUT \
  "owner deletes its comment (and it stays deleted after a sync)" >/dev/null

log "Partner: probing '$OWN_EVENT_TITLE' comments (both must be gone)..."
launch_app "$PARTNER_UDID" "partner-own-probe4" -ShareCalProbeEventComments -ShareCalEventCommentTitle "$OWN_EVENT_TITLE"
PARTNER_OWN_PROBE4=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "partner probes after both deletes")
echo "$PARTNER_OWN_PROBE4" | grep -q "count=0" \
  || fail "partner still sees deleted comments. Probe: $PARTNER_OWN_PROBE4"
log "Deleted comments disappear on both sides and stay deleted after sync ✓"
# Delete it while it is still inside the sync window, so its mirror is tombstoned
# instead of piling up in the owner's zone run after run.
launch_app "$OWNER_UDID" "owner-own-cleanup" -ShareCalDeleteCalendarEventTitled "$OWN_EVENT_TITLE"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag deleteCalendarEvent succeeded title=.* count=[1-9]" $DIAG_TIMEOUT \
  "owner deletes its own-comment event" >/dev/null

# ---------- 9d. Repeating series: "all future events" moved one hour later ----------
# Moving a series shifts every occurrence date, and moving it from a later occurrence makes
# EventKit start a new series with a new event identifier. The uploaded records keep their
# names either way (EventMirrorKeyPolicy.keptKeysForRescheduledEvents), so the comments on
# the fourth occurrence stay on it.
SERIES_TITLE="Series Comment Event $RANDOM"
SERIES_COMMENT="series-first-$RANDOM"
SERIES_REPLY="partner-on-series-$RANDOM"
series_probe() { # series_probe <udid> <console-log-name> <description>
  launch_app "$1" "$2" -ShareCalProbeEventComments -ShareCalEventCommentTitle "$SERIES_TITLE" \
    -ShareCalEventCommentOccurrence 3
  local probe
  probe=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "$3")
  echo "$probe" | grep -q "$SERIES_COMMENT" && echo "$probe" | grep -q "$SERIES_REPLY" \
    || fail "$3: comments on the series' fourth occurrence are gone. Probe: $probe"
  echo "$probe"
}

log "Owner: creating a daily series and commenting on its fourth occurrence ('$SERIES_COMMENT')..."
launch_app "$OWNER_UDID" "owner-series-comment" \
  -ShareCalSeedDailySeriesTitled "$SERIES_TITLE" \
  -ShareCalAddEventComment "$SERIES_COMMENT" -ShareCalEventCommentTitle "$SERIES_TITLE" \
  -ShareCalEventCommentOccurrence 3
SERIES_ADD=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag addEventComment (succeeded|failed)" $DIAG_TIMEOUT "owner comments on the series' fourth occurrence")
echo "$SERIES_ADD" | grep -q "addEventComment succeeded" || fail "owner could not comment on the series. Log: $SERIES_ADD"

# The reply diag reads the partner's local copy, so the series has to be imported first.
log "Partner: probing the series (must see the owner's comment on the fourth occurrence)..."
launch_app "$PARTNER_UDID" "partner-series-probe0" -ShareCalProbeEventComments \
  -ShareCalEventCommentTitle "$SERIES_TITLE" -ShareCalEventCommentOccurrence 3
PARTNER_SERIES_PROBE0=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag eventComments title=" $DIAG_TIMEOUT "partner imports the series")
echo "$PARTNER_SERIES_PROBE0" | grep -q "$SERIES_COMMENT" \
  || fail "partner did NOT see the owner's comment on the series' fourth occurrence. Probe: $PARTNER_SERIES_PROBE0"

log "Partner: replying on the same occurrence ('$SERIES_REPLY')..."
launch_app "$PARTNER_UDID" "partner-series-reply" \
  -ShareCalAddEventComment "$SERIES_REPLY" -ShareCalEventCommentTitle "$SERIES_TITLE" \
  -ShareCalEventCommentOccurrence 3
SERIES_REPLY_ADD=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag addEventComment (succeeded|failed)" $DIAG_TIMEOUT "partner replies on the series' fourth occurrence")
echo "$SERIES_REPLY_ADD" | grep -q "addEventComment succeeded" || fail "partner could not reply on the series. Log: $SERIES_REPLY_ADD"
SERIES_KEY_BEFORE=$(series_probe "$OWNER_UDID" "owner-series-probe1" "owner before the move" | sed -n 's/.* key=//p' | tail -1 | tr -d '\r')
[ -n "$SERIES_KEY_BEFORE" ] || fail "the series' fourth occurrence has no commented record before the move"

log "Owner: moving the series one hour later from its third occurrence on..."
launch_app "$OWNER_UDID" "owner-series-split" -ShareCalMoveSeriesTitled "$SERIES_TITLE"
SERIES_SPLIT=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag moveSeries (succeeded|failed)" $DIAG_TIMEOUT "owner moves all future events")
echo "$SERIES_SPLIT" | grep -q "moveSeries succeeded" || fail "could not move the series. Log: $SERIES_SPLIT"
log "EventKit identifiers around the split: $SERIES_SPLIT"
SERIES_KEY_OWNER=$(series_probe "$OWNER_UDID" "owner-series-probe2" "owner after all future events moved" | sed -n 's/.* key=//p' | tail -1 | tr -d '\r')
[ "$SERIES_KEY_OWNER" = "$SERIES_KEY_BEFORE" ] \
  || fail "the fourth occurrence changed its record: '$SERIES_KEY_BEFORE' -> '$SERIES_KEY_OWNER'"
series_probe "$PARTNER_UDID" "partner-series-probe2" "partner after all future events moved" >/dev/null
log "Both sides keep the comments after all future events moved ✓"

log "Owner: moving the later series one more hour as a whole..."
launch_app "$OWNER_UDID" "owner-series-move" -ShareCalMoveSeriesTitled "$SERIES_TITLE"
SERIES_MOVE=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag moveSeries (succeeded|failed)" $DIAG_TIMEOUT "owner moves the whole later series")
echo "$SERIES_MOVE" | grep -q "moveSeries succeeded" || fail "could not move the later series. Log: $SERIES_MOVE"
log "EventKit identifiers around the whole-series move: $SERIES_MOVE"
SERIES_KEY_OWNER=$(series_probe "$OWNER_UDID" "owner-series-probe3" "owner after the whole series moved" | sed -n 's/.* key=//p' | tail -1 | tr -d '\r')
[ "$SERIES_KEY_OWNER" = "$SERIES_KEY_BEFORE" ] \
  || fail "the fourth occurrence changed its record: '$SERIES_KEY_BEFORE' -> '$SERIES_KEY_OWNER'"
series_probe "$PARTNER_UDID" "partner-series-probe3" "partner after the whole series moved" >/dev/null
log "Both sides keep the comments after the whole series moved ✓"
launch_app "$OWNER_UDID" "owner-series-cleanup" -ShareCalDeleteSeriesTitled "$SERIES_TITLE"
wait_for_console "$CONSOLE_LOG" "ShareCalDiag deleteSeries succeeded title=.* count=[1-9]" $DIAG_TIMEOUT \
  "owner deletes the series" >/dev/null

# ---------- 10. Joint event UI: tapping the green block opens the comment thread ----------
# Steps 8-9 prove the comment DATA pipeline; this proves the partner can actually REACH it
# from the calendar UI — the green joint block must be tappable and open the comment thread
# (regression guard for making the block a Button instead of an offset .onTapGesture).
log "Partner: verifying the joint event opens its comment thread on tap (XCUITest)..."
JOINT_UI_RESULT="$DERIVED/joint-comment-ui.xcresult"
rm -rf "$JOINT_UI_RESULT"
TEST_RUNNER_SHARECAL_SMOKE_UI=1 xcodebuild "$UI_TEST_ACTION" \
  -project "$ROOT_DIR/OurDays.xcodeproj" -scheme OurDays \
  -configuration Debug -destination "platform=iOS Simulator,id=$PARTNER_UDID" \
  -parallel-testing-enabled NO \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$JOINT_UI_RESULT" \
  -only-testing:OurDaysUITests/OurDaysUITests/testPairedPartnerCanOpenJointEventCommentThread \
  CODE_SIGN_ENTITLEMENTS=OurDays/App/OurDays.entitlements \
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

# ---------- 11b. Incremental read: real record deletions reach the partner ----------
# Everything above travels as changed records (a deleted event or comment is a
# `deletedAt` write). Here the owner hard-deletes its tombstoned event records, so the
# partner's next read gets record DELETIONS in a delta. It must drop exactly those and
# keep every other event: the partner's list shrinks by the number deleted, not to zero.
shared_mirror_count() { # shared_mirror_count <console-log>: the last sync's imported partner records
  grep -E "cloudSharedMirrorsFetched count=" "$1" 2>/dev/null | tail -1 | sed -n 's/.*cloudSharedMirrorsFetched count=\([0-9]*\).*/\1/p'
}
log "Partner: syncing to count the owner's event records before the deletion..."
launch_app "$PARTNER_UDID" "partner-predelete" -ShareCalForceSync
wait_for_console "$CONSOLE_LOG" "foregroundSync finished" $SYNC_TIMEOUT "partner pre-deletion sync" >/dev/null
MIRRORS_BEFORE=$(shared_mirror_count "$CONSOLE_LOG")
[ -n "$MIRRORS_BEFORE" ] || fail "could not read the partner's count of owner events before the deletion"
xcrun simctl terminate "$PARTNER_UDID" "$BUNDLE_ID" 2>/dev/null || true

log "Owner: hard-deleting its tombstoned event records from the cloud..."
launch_app "$OWNER_UDID" "owner-hard-delete" -ShareCalHardDeleteOwnTombstones
HARD_DELETE=$(wait_for_console "$CONSOLE_LOG" "ShareCalDiag hardDeleteOwnTombstones succeeded records=[1-9]" $DIAG_TIMEOUT \
  "owner hard-deletes tombstoned event records (at least one)")
log "Owner: ${HARD_DELETE##*hardDeleteOwnTombstones succeeded }"

log "Partner: syncing (the delta must carry the deletions and nothing else may go)..."
launch_app "$PARTNER_UDID" "partner-postdelete" -ShareCalForceSync
DELETION_LINE=$(wait_for_console "$CONSOLE_LOG" "fetchZoneChanges .*scope=shared mode=delta .* deleted=[1-9]" $SYNC_TIMEOUT \
  "partner's incremental read reports the deleted records")
MIRRORS_DELETED=$(echo "$DELETION_LINE" | sed -n 's/.* deleted=\([0-9]*\) .*/\1/p' | tail -1)
MIRRORS_EXPECTED=$((MIRRORS_BEFORE - MIRRORS_DELETED))
[ "$MIRRORS_EXPECTED" -ge 1 ] \
  || fail "the deletion left the partner no owner events to keep (before=$MIRRORS_BEFORE deleted=$MIRRORS_DELETED); the step cannot prove the rest survives"
MIRRORS_AFTER=""
for _ in $(seq 1 60); do
  MIRRORS_AFTER=$(shared_mirror_count "$CONSOLE_LOG")
  [ "$MIRRORS_AFTER" = "$MIRRORS_EXPECTED" ] && break
  sleep 1
done
[ "$MIRRORS_AFTER" = "$MIRRORS_EXPECTED" ] \
  || fail "after $MIRRORS_DELETED deletions the partner holds $MIRRORS_AFTER owner events, expected $MIRRORS_EXPECTED (before=$MIRRORS_BEFORE)"
log "Partner dropped the $MIRRORS_DELETED deleted records and kept the other $MIRRORS_AFTER ✓"

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
# UserDefaults reach the plist a moment after the app is gone; the recovery is quick
# enough now that reading at once can see the file before that write.
for _ in $(seq 1 30); do
  [ "$(read_default "$OWNER_UDID" partnerShareOwnerID)" = "$PARTNER_ID" ] && break
  sleep 1
done
[ "$(read_default "$OWNER_UDID" partnerShareOwnerID)" = "$PARTNER_ID" ] || fail "recovered partnerShareOwnerID was not persisted"

xcrun simctl terminate "$OWNER_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl terminate "$PARTNER_UDID" "$BUNDLE_ID" 2>/dev/null || true

log "✅ PASS: mutual two-person pairing established, events synced both ways, the partner UI renders the owner's event, a withdrawn invitation reads canceled on the partner's side, a joint event's comment thread is shared symmetrically across both partners, a thread the owner starts on its own event reaches the partner and takes the reply, the joint block opens its comment thread on tap, and a delete-and-reinstall recovers the pairing from iCloud and tombstones the ghost event."
