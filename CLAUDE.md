# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build (Debug, simulator)
xcodebuild -project CoupleCalendar.xcodeproj -scheme CoupleCalendar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run unit tests
xcodebuild -project CoupleCalendar.xcodeproj -scheme CoupleCalendar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CoupleCalendarTests

# Run a single test class / method
... -only-testing:CoupleCalendarTests/TwoPersonPairingPlanTests
... -only-testing:CoupleCalendarTests/TwoPersonPairingPlanTests/testMutualShareEstablishesPartnerAndLeavesStaleZones

# Import CloudKit schema into Development (Production deploys via CloudKit Console)
Scripts/import-cloudkit-schema.sh development
```

There is one scheme (`CoupleCalendar`) and all unit tests live in a single file, `CoupleCalendarTests/CoupleCalendarTests.swift`.

## What this app is

"ShareCal" — a strictly **two-person** couples calendar. Each partner mirrors selected EventKit calendar events into CloudKit; partners see each other's events via one CKShare. Multi-person sharing is intentionally unsupported and must not be reintroduced.

## Architecture

Six Swift files in `CoupleCalendar/`, no SPM dependencies:

- **Models.swift** — SwiftData models (`EventMirror`, `LocalEventShadow`, `EventInvitation`, `EventComment`, `CalendarAccessRequest`), `ShareCalStrings` (hand-rolled EN/ZH localization via `text(english, chinese)`), and most pure "Plan" enums.
- **AppServices.swift** — `SettingsStore` (UserDefaults-backed, `@Observable`) and `SyncCoordinator.foregroundSync`, the single sync pipeline.
- **CloudKitCoupleSpaceService.swift** — all CloudKit I/O: zone/root/share management, record mappers, share acceptance handler, scene delegate.
- **RootView.swift** — entire SwiftUI UI (tabs, settings, pairing flows, conflict alerts).
- **CalendarAccessService.swift / EventServices.swift** — EventKit access and mirror/invitation/comment generation.

### The "Plan enum" convention

All decision logic lives in stateless `enum ...Plan` types with pure static functions (e.g. `TwoPersonPairingPlan`, `CloudKitCommentWritePlan`, `ForegroundSyncPlan`). Views and services stay thin and call into plans; unit tests target the plans directly. New logic should follow this pattern.

### Identity model (load-bearing — do not regress)

- The **only** member ID is the CloudKit `userRecordID` (`_xxx`), fetched via `fetchCurrentUserRecordID()` and cached as `SettingsStore.currentMemberID` (`"local-user"` placeholder until available / in LOCAL_SIGNING builds).
- Partner identity = `ownerName` of the accepted shared zone (`partnerShareOwnerID`), verified against the accepted participant `userRecordID` of my outgoing CKShare. These are directly comparable because they're the same ID space; only `_`-prefixed identifiers participate in matching.
- There is **no pairingID** and no local UUID identity. `TwoPersonPairingPlan.resolve` is the single decision point for who the partner is, which stale shared zones to auto-leave, and when to raise a `TwoPersonPairingConflict` (mismatched outgoing/incoming person, multiple shares). During a conflict, sync imports nothing until the user picks a partner in the RootView alert.
- Accepting a share from someone other than the current partner is intercepted (`ShareAcceptanceGuardPlan` + `ShareCalPendingShareReplacement`) and requires user confirmation. Extra accepted participants on the outgoing share are auto-removed once the partner is established (`TwoPersonShareLockPlan`). **Never flip `share.publicPermission` back to `.none` on a live share** — CloudKit removes the already-joined participants (including the partner) when a link share is closed; the partner joins as a `publicUser`, which is also why the native share UI offers no per-person "remove access" row (that's for invited `privateUser` participants, e.g. Notes' default invite-only shares).
- Partner display is nickname-only: local note (`partnerNoteName`) > synced `MemberProfile.displayName` > fallback "Partner". Never display iCloud email addresses.
- Legacy `local-owner-<UUID>` installs are reset (not migrated) in `SettingsStore.resetLegacyPairingStateIfNeeded`; users re-pair. Don't add back-compat paths.

### CloudKit layout & sync flow

- Container `iCloud.com.leeberty.CoupleCalendar`, private zone `CoupleSpace`, root record `couple-space-root` (type `CoupleSpace`); all records parent to the root so one CKShare covers everything.
- My data is written to my private zone; the partner's data is read from `sharedCloudDatabase` zones (records' `ownerMemberID` is overwritten with the zone `ownerName` on import — the zone owner is authoritative).
- Comments/invitations/access-request replies on the partner's records are written into the *partner's* shared zone. Access requests are transported as `EventInvitation` records with the `history-access-request:` recordName prefix (avoids a separate record type in the deployed schema).
- `SyncCoordinator.foregroundSync` runs the whole pipeline: regenerate own mirrors from EventKit (mirrors are derived data, rebuilt every sync), upsert into SwiftData, then CloudKit writes, pairing resolution, and shared-zone imports. SwiftData is a local cache only (`cloudKitDatabase: .none`).

### Build configurations

- Debug uses the Development CloudKit environment; Release uses Production (`CoupleCalendarProduction.entitlements`). Schema changes must be imported to Development (`Scripts/import-cloudkit-schema.sh`) and deployed to Production in CloudKit Console before Release/TestFlight sharing works — see `docs/development.md` for the error messages this causes when missed.
- A `LOCAL_SIGNING` compilation condition disables CloudKit entirely (`AppServices.isCloudKitEnabled`).

## Manual two-device smoke testing

`Scripts/dev-pairing-smoke.sh` runs the whole two-simulator pairing flow unattended against the Development environment (build with entitlement overrides since the project's Debug config is LOCAL_SIGNING, reset app state, owner shares → partner accepts via URL → reverse share → mutual identity assertions). `docs/development.md` documents the manual flow. Key points: two fixed simulators preserve iCloud sign-in (Owner: iPhone 17 `5509EBC5-...`, Partner: iPhone 17 Pro `E75449FE-...` — do not erase/recreate them). Launch arguments drive diagnostics: `-ShareCalSeedCalendarEvent` (create test event), `-ShareCalPreparePairingShare` (create share, log invite URL), `-ShareCalAcceptShareURL <url>` (accept without the system prompt), `-ShareCalForceSync`, `-ShareCalSharedReadProbe`, `-ShareCalStopICloudSharing`, `-ShareCalCloudKitWriteProbe`, `--sharecal-reset-user-defaults`. Simulator gotchas the smoke script already handles: info-level OSLog lines are not persisted (assert on captured app stdout via `simctl launch --console-pty`, not `log show`), and `simctl spawn defaults write` hits the device-level domain that the app merges as a fallback — never leave identity keys there.
