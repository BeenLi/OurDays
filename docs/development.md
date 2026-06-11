# 开发与测试运维指南 (Development & Testing Operations)

## Simulator Test Devices

Use these fixed simulator instances for the two-device CloudKit Share smoke test:

| Role | Simulator | UDID |
| --- | --- | --- |
| Owner | iPhone 17 | `5509EBC5-44A3-4C7D-862D-2811FA330AF1` |
| Partner | iPhone 17 Pro | `E75449FE-AD7B-429B-84A5-12ED862B2349` |

These simulator instances preserve their iCloud sign-in state as long as the
same UDIDs are reused. Do not erase, delete, or recreate them unless you intend
to sign in to iCloud again.

Useful commands:

```bash
xcrun simctl boot 5509EBC5-44A3-4C7D-862D-2811FA330AF1
xcrun simctl boot E75449FE-AD7B-429B-84A5-12ED862B2349
open -a Simulator
```

## CloudKit Schema

Release builds use the Production CloudKit environment. Before a Release
simulator or TestFlight build can create a share, the schema for
`iCloud.com.leeberty.CoupleCalendar` must be imported into Development and then
deployed to Production from CloudKit Console.

Save a CloudKit management token in `cktool`, or set
`CLOUDKIT_MANAGEMENT_TOKEN`, then import the schema into Development:

```bash
xcrun cktool save-token --type management --method keychain
Scripts/import-cloudkit-schema.sh development
```

The management token must be generated for Apple Developer team `3SF92B92JF`
with access to container `iCloud.com.leeberty.CoupleCalendar`.

`cktool import-schema` cannot import directly into Production. After the
Development import succeeds, open CloudKit Console for the Development
environment and run `Deploy Schema Changes...` to deploy the same record types
and indexes to Production.

The import script first checks that the local schema contains every CloudKit
record type and field currently written by the app, plus the CloudKit Sharing
system type `cloudkit.share`, then calls `cktool`.

For a quick local schema coverage check and Development import, the default is
also Development:

```bash
Scripts/import-cloudkit-schema.sh
```

If `Create or Open Share` reports `Cannot create new type CoupleSpace in
production schema`, the app reached the correct Production container, but this
schema has not been deployed yet, or a new field was added after the last
Production schema deployment.

If it reports `Cannot create new type cloudkit.share in production schema`, the
business record types are deployed but the CloudKit Sharing system schema is
missing. Create one share in the Development environment first, rerun the
Development import if needed, then deploy schema changes to Production again.

After deploying schema changes, rerun the Owner simulator flow and then retry
the Partner invitation flow.

## Release CloudKit Share Smoke Test

Use `Release` with `CoupleCalendarProduction.entitlements` when validating
Production CloudKit sharing on the two fixed simulators.

Owner setup:

```bash
xcodebuild \
  -project CoupleCalendar.xcodeproj \
  -scheme CoupleCalendar \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=5509EBC5-44A3-4C7D-862D-2811FA330AF1' \
  build
```

Launch the Owner app with `-ShareCalSeedCalendarEvent` to create or reuse a
real EventKit event named `ShareCal E2E Smoke Test` in the writable `ShareCal`
calendar. Then tap `Sync`; the Owner should show one event in the `Me` column.

Open `Settings > Create or Open Share`. Existing shares are upgraded to allow an
iCloud invite link, and the system sharing UI can be used to open the invitation
on the Partner simulator.

Partner validation:

1. Install and run the same Release build on
   `E75449FE-AD7B-429B-84A5-12ED862B2349`.
2. Open the Owner share URL on the Partner simulator and accept the system
   prompt.
3. Tap `Sync` in Partner.

Expected result: Partner logs show `acceptShare succeeded` and
`fetchSharedEventMirrors fetched records=1`, and the Partner UI shows
`ShareCal E2E Smoke Test` in the `Partner` column. If the Partner simulator has
no writable calendar, the app creates and selects a local `ShareCal` calendar
before syncing.

## Stop Sharing Privacy Probe

Release builds include launch diagnostics for validating that a stopped share is
not readable from the Partner simulator.

1. Before stopping sharing, run the Partner app with
   `-ShareCalSharedReadProbe`. The runtime log prints `Shared Zones` and shared
   record counts for `EventMirror`, `EventComment`, `EventInvitation`, and
   `CalendarAccessRequest`.
2. Run the Owner app with `-ShareCalStopICloudSharing`. The runtime log must
   print `ShareCal stop sharing probe succeeded`. If it reports an iCloud
   account error, refresh the Owner simulator's Apple Account sign-in and retry.
3. Run the Partner app with `-ShareCalSharedReadProbe` again.

Expected result after a successful stop-sharing probe: `Shared Zones: 0`, all
shared record counts are `0`, and the log prints
`ShareCal shared read probe proves no access: true`.

## Automated Pairing Smoke Test

`Scripts/dev-pairing-smoke.sh` runs the full two-simulator pairing flow
unattended against the Development environment:

```bash
Scripts/dev-pairing-smoke.sh            # build + run
Scripts/dev-pairing-smoke.sh --skip-build
```

Prerequisites: both fixed simulators signed in to iCloud accounts that are
members of the Apple Developer team (Development environment requirement).

What it does: builds Debug with CloudKit entitlement overrides (the project's
Debug configuration is LOCAL_SIGNING), resets app state, seeds an event on the
Owner, creates the pairing share via `-ShareCalPreparePairingShare`, accepts it
on the Partner via `-ShareCalAcceptShareURL` (no system prompt), repeats in the
reverse direction, and finally asserts that each device's stored
`partnerShareOwnerID` equals the other's `currentMemberID`.

Implementation notes (hard-won):

- Assertions read the app's captured stdout (`simctl launch --console-pty`),
  because info-level OSLog lines are not persisted on simulators and are
  invisible to `log show`.
- `simctl spawn <udid> defaults write/read` operates on the device-level
  preferences domain, which the app's UserDefaults merges as a *fallback*.
  Seeding works through it, but stale identity keys left there shadow real
  state (this bit us with a leftover `currentMemberID = me`). The script reads
  verification values from the app container's plist instead.
- App console logs land in `build/dev-smoke/console/*.log` for debugging.
