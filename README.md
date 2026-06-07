# CoupleCalendar

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
