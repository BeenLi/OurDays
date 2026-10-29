# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build (Debug, simulator)
xcodebuild -project OurDays.xcodeproj -scheme OurDays \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run unit tests (the OurDaysTests scheme builds only the test bundle, not the app)
xcodebuild -project OurDays.xcodeproj -scheme OurDaysTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run a single test class / method
... -only-testing:OurDaysTests/TwoPersonPairingPolicyTests
... -only-testing:OurDaysTests/TwoPersonPairingPolicyTests/testMutualShareEstablishesPartnerAndLeavesStaleZones

# Import CloudKit schema into Development (Production deploys via CloudKit Console)
Scripts/import-cloudkit-schema.sh development
```

There are two schemes: `OurDays` (app, unit and UI tests) and `OurDaysTests` (unit tests only, what PR CI runs). Unit tests live in `OurDaysTests/`, one file per area (`PairingTests.swift`, `CloudKitTests.swift`, `InvitationAndAccessRequestTests.swift`, `CalendarMirrorTests.swift`, `DayTimelineAndNavigationTests.swift`, `CommentTests.swift`, `SyncTests.swift`, `ActivityAndNotificationTests.swift`, `SettingsAndStringsTests.swift`); `-only-testing:OurDaysTests/<ClassName>` works regardless of file.

## What this app is

"OurDays" — a strictly **two-person** couples calendar. (The app was renamed from "ShareCal"; many internal code identifiers, launch arguments, type names like `ShareCalStrings`, and the local EventKit calendar name still use the `ShareCal` prefix for backward compatibility — do not rename those. Likewise the Xcode project, targets and folders are `OurDays` (renamed from `CoupleCalendar` in 2026-10), but the bundle ID `com.leeberty.CoupleCalendar`, the CloudKit container `iCloud.com.leeberty.CoupleCalendar`, the BGTask identifier and the OSLog subsystem keep `CoupleCalendar` — changing them breaks installed users.) Each partner mirrors selected EventKit calendar events into CloudKit; partners see each other's events via one CKShare. Multi-person sharing is intentionally unsupported and must not be reintroduced.

## Architecture

Source lives in `OurDays/`, no SPM dependencies, one directory per layer; dependencies point App → Views → Services → Policies → Models and never back:

- **App/** — `OurDaysApp.swift` (`@main`, AppDelegate: BGTask registration, silent-push entry, notification authorization), `ShareCalSceneDelegate.swift` (`ShareCalSceneDelegate`, the share acceptance handler and `ShareCalPendingShareReplacement`), `AppServices.swift` (the `AppServices` service container only), `Info.plist` and the three entitlements files.
- **Models/Models.swift** — SwiftData models (`EventMirror`, `LocalEventShadow`, `EventInvitation`, `EventComment`, `CalendarAccessRequest`, `MemberProfile`), their stored enums, `ShareCalModelContainer`, and `ShareCalLocalDataCleanupService`.
- **Policies/** — the pure "Policy" enums, one file per area: `PairingPolicies` (`TwoPersonPairingPolicy`, `ShareAcceptanceGuardPolicy`, …), `SyncPolicies`, `InvitationAndAccessRequestPolicies`, `CalendarNavigationPolicies`, `CalendarDisplayPolicies`, `DayTimelinePolicies`, `CommentPolicies`, `ActivityAndNotificationPolicies`, `MemberIdentityPolicies` (incl. `MemberIDPolicy` placeholders), `CalendarSourcePolicies` (incl. `CalendarAuthorizationState`, `EventMirrorKeyPolicy`), `AgendaPolicies` (joint schedule, week agenda, calendar focus), `CloudKitPolicies` (the pure CloudKit decision enums). Policies never reference services or stores.
- **Services/** — `SyncCoordinator.swift` (`SyncCoordinator.foregroundSync`, the single sync pipeline, plus the notification scheduler and `ShareCalBackgroundSyncRunner`), `CloudKitCoupleSpaceService.swift` (all CloudKit I/O: zone/root/share management, the shared `cloudKitSharingInfo/Error` + `describeCloudKitFailure` log helpers), `CloudKitRecordMappers.swift` (the pure `CKRecord` ↔ model mappers `EventMirrorRecordMapper`, `InvitationRecordMapper`, `CommentRecordMapper`, `CalendarAccessRequestRecordMapper`, `MemberProfileRecordMapper`, and the batch/query policies next to them), `CalendarAccessService.swift` / `EventServices.swift` (EventKit access and the `EventMirrorService` / `InvitationService` / `CommentService` mutators; no decision logic, that lives in `Policies/`), `SettingsStore.swift` (`SettingsStore`, UserDefaults-backed, `@Observable`).
- **Views/** — the SwiftUI UI, one file per screen: `RootView.swift` (the tab container, sheet/alert routing, and pairing-conflict alerts), `CalendarTabView`, `InvitesTabView`, `ActivityTabView`, `Settings/`, `DayTimeline/`, `EventDetail/`, …, plus `DesignSystem.swift` (`OurDaysTheme`, `OurDaysIdentity`, card/button styles, avatar views) and `CloudSharingController.swift` (wraps `UICloudSharingController`). UI files are compiled into the app target only; the unit-test target compiles the non-UI sources directly (no `@testable import`), so a new non-UI file must be added to both targets in `project.pbxproj`.
- **Diagnostics/** — everything driven by launch arguments and probes, nothing the app uses in normal operation: `LaunchDiagnosticPolicies.swift` (`ShareCalLaunchDiagnosticPolicy`, the argument parser), `LaunchDiagnostics.swift` (`ShareCalLaunchDiagnostics`, the runner; app target only) and `CloudKitDiagnostics.swift` (`CloudKitAccountDiagnostic`, `CloudKitSharedReadDiagnostic`).
- **Resources/** — `Assets.xcassets` and `ShareCalStrings.swift` (hand-rolled EN/ZH localization via `text(english, chinese)`, plus `AppLanguage` / `AppLegalInfo`).

### Shared helpers (use these instead of re-rolling them)

- `SyncCoordinator.syncIfIdle(services:settings:modelContext:)` — the one way a screen triggers a user-visible sync.
- `EventMirrorStore.upsert(_:modelContext:)` — insert-or-update an `EventMirror` by `mirrorKey`.
- `MemberIDPolicy.normalized(_:)` / `normalizedList(_:)` — trim + nil-if-blank for every ID/nickname comparison.
- `EventTimeRangeTextPolicy.text(for:strings:)` — the short "19:30 - 21:30" / all-day text.
- `DateFormatterCache.formatter(template:…)` / `formatter(dateFormat:…)` — never build a `DateFormatter()` per call.

### The "Policy enum" convention

All decision logic lives in stateless `enum ...Policy` types with pure static functions (e.g. `TwoPersonPairingPolicy`, `CloudKitCommentWritePolicy`, `ForegroundSyncPolicy`). Views and services stay thin and call into policies; unit tests target the policies directly. New logic should follow this pattern.

### Identity model (load-bearing — do not regress)

- The **only** member ID is the CloudKit `userRecordID` (`_xxx`), fetched via `fetchCurrentUserRecordID()` and cached as `SettingsStore.currentMemberID` (`"local-user"` placeholder until available / in LOCAL_SIGNING builds).
- Partner identity = `ownerName` of the accepted shared zone (`partnerShareOwnerID`), verified against the accepted participant `userRecordID` of my outgoing CKShare. These are directly comparable because they're the same ID space; only `_`-prefixed identifiers participate in matching.
- There is **no pairingID** and no local UUID identity. `TwoPersonPairingPolicy.resolve` is the single decision point for who the partner is, which stale shared zones to auto-leave, and when to raise a `TwoPersonPairingConflict` (mismatched outgoing/incoming person, multiple shares). During a conflict, sync imports nothing until the user picks a partner in the RootView alert.
- Accepting a share from someone other than the current partner is intercepted (`ShareAcceptanceGuardPolicy` + `ShareCalPendingShareReplacement`) and requires user confirmation. An extra accepted participant on the outgoing share is never removed automatically: `TwoPersonPairingPolicy.resolve` raises a conflict and the user picks who stays (the newcomer may be the person they are switching to, and their share can arrive before or after they join ours). **Never flip `share.publicPermission` back to `.none` on a live share** — CloudKit removes the already-joined participants (including the partner) when a link share is closed; the partner joins as a `publicUser`, which is also why the native share UI offers no per-person "remove access" row (that's for invited `privateUser` participants, e.g. Notes' default invite-only shares).
- Partner display is nickname-only: local note (`partnerNoteName`) > synced `MemberProfile.displayName` > fallback "Partner". Never display iCloud email addresses.
- Legacy `local-owner-<UUID>` installs are reset (not migrated) in `SettingsStore.resetLegacyPairingStateIfNeeded`; users re-pair. Don't add back-compat paths.

### CloudKit layout & sync flow

- Container `iCloud.com.leeberty.CoupleCalendar`, private zone `CoupleSpace`, root record `couple-space-root` (type `CoupleSpace`); all records parent to the root so one CKShare covers everything.
- My data is written to my private zone; the partner's data is read from `sharedCloudDatabase` zones (records' `ownerMemberID` is overwritten with the zone `ownerName` on import — the zone owner is authoritative).
- Comments/invitations/access-request replies on the partner's records are written into the *partner's* shared zone. Access requests are transported as `EventInvitation` records with the `history-access-request:` recordName prefix (avoids a separate record type in the deployed schema).
- `SyncCoordinator.foregroundSync` runs the whole pipeline: regenerate own mirrors from EventKit (mirrors are derived data, rebuilt every sync), upsert into SwiftData, then CloudKit writes, pairing resolution, and shared-zone imports. SwiftData is a local cache only (`cloudKitDatabase: .none`).

### Build configurations

- Debug uses the Development CloudKit environment; Release uses Production (`OurDaysProduction.entitlements`). Schema changes must be imported to Development (`Scripts/import-cloudkit-schema.sh`) and deployed to Production in CloudKit Console before Release/TestFlight sharing works — see `docs/development.md` for the error messages this causes when missed.
- A `LOCAL_SIGNING` compilation condition disables CloudKit entirely (`AppServices.isCloudKitEnabled`).

## Manual two-device smoke testing

`Scripts/dev-pairing-smoke.sh` runs the whole two-simulator pairing flow unattended against the Development environment (build with entitlement overrides since the project's Debug config is LOCAL_SIGNING, reset app state, owner shares → partner accepts via URL → reverse share → mutual identity assertions). `docs/development.md` documents the manual flow. Key points: two fixed simulators preserve iCloud sign-in (on this Mac Owner: iPhone 17 `AF9A93BC-...`, Partner: iPhone 17 Pro `244DFAAC-...`; see `docs/development.md` for the other Mac's pair — do not erase/recreate them). Launch arguments drive diagnostics: `-ShareCalSeedCalendarEvent` (create test event), `-ShareCalPreparePairingShare` (create share, log invite URL), `-ShareCalAcceptShareURL <url>` (accept without the system prompt), `-ShareCalForceSync`, `-ShareCalSharedReadProbe`, `-ShareCalStopICloudSharing`, `-ShareCalCloudKitWriteProbe`, `--sharecal-reset-user-defaults`. Simulator gotchas the smoke script already handles: info-level OSLog lines are not persisted (assert on captured app stdout via `simctl launch --console-pty`, not `log show`), and `simctl spawn defaults write` hits the device-level domain that the app merges as a fallback — never leave identity keys there.

## Design decisions (docs/plantree)

`docs/plantree/plans/<topic>/decisions/NNNN-*.md` records why behavior is the way it is: how it worked before, what changed, and which alternatives were rejected. Before changing pairing, sync, invitations, comments or notifications, read that topic's decisions so a rejected approach isn't rebuilt. When a PR changes user-visible behavior or a sync/pairing/CloudKit rule, add a new decision in the same PR (format in `docs/plantree/README.md`). Don't keep PR lists, release status or todo lists there; GitHub and `git log` already have them.
