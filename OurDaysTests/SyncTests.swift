import SwiftData
import XCTest

final class ForegroundSyncPolicyTests: XCTestCase {
    func testAllowsAutomaticSyncWhenThereIsNoPreviousSync() {
        XCTAssertTrue(
            ForegroundSyncPolicy.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testSkipsAutomaticSyncWhenLastSyncIsWithinThrottleWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-(ForegroundSyncPolicy.automaticThrottleInterval - 1))

        XCTAssertFalse(
            ForegroundSyncPolicy.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testAutomaticThrottleIsShortEnoughToFeelLive() {
        // Tester feedback flagged the previous 5-minute throttle as "too slow";
        // keep automatic refreshes within a minute so a partner's change shows up
        // shortly after re-foregrounding or switching tabs.
        XCTAssertLessThanOrEqual(ForegroundSyncPolicy.automaticThrottleInterval, 60)
    }

    func testAllowsAutomaticSyncWhenThrottleWindowHasElapsed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-ForegroundSyncPolicy.automaticThrottleInterval)

        XCTAssertTrue(
            ForegroundSyncPolicy.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testSkipsAutomaticSyncWhileSyncing() {
        XCTAssertFalse(
            ForegroundSyncPolicy.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .syncing,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testPendingAcceptedShareBypassesThrottleWhenIdle() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-1)

        XCTAssertTrue(
            ForegroundSyncPolicy.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: true
            )
        )
    }

    func testPendingAcceptedShareDoesNotStartDuplicateSync() {
        XCTAssertFalse(
            ForegroundSyncPolicy.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .syncing,
                hasPendingAcceptedShare: true
            )
        )
    }
}

final class CloudKitForegroundSyncPolicyTests: XCTestCase {
    func testSkipsCloudKitWhenSharingDisabledEvenIfForced() {
        XCTAssertFalse(
            CloudKitForegroundSyncPolicy.shouldRunCloudKit(
                iCloudSharingEnabled: false,
                hasStartedPairing: true,
                partnerShareOwnerID: "partner-owner",
                outgoingShareParticipantIDs: ["participant"],
                forceCloudKit: true
            )
        )
    }

    func testSkipsCloudKitBeforePairingWhenThereIsNoAcceptedShareSignal() {
        XCTAssertFalse(
            CloudKitForegroundSyncPolicy.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
    }

    func testRunsCloudKitForPairingSignalsOrAcceptedShareSignal() {
        XCTAssertTrue(
            CloudKitForegroundSyncPolicy.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: true,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPolicy.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: "partner-owner",
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPolicy.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: ["participant"],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPolicy.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                forceCloudKit: true
            )
        )
    }
}

final class ShareCalModelContainerTests: XCTestCase {
    @MainActor
    func testMakesLocalContainerWhenCloudKitEntitlementsArePresent() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)

        XCTAssertNotNil(container)
    }
}

final class BackgroundRefreshSchedulePolicyTests: XCTestCase {
    func testSchedulesOnlyWhenCloudKitEnabledAndPairingActive() {
        // Unpaired install has nothing to fetch — don't spend background budget.
        XCTAssertFalse(BackgroundRefreshSchedulePolicy.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: false,
            partnerShareOwnerID: nil, outgoingShareParticipantIDs: []
        ))
        // Pairing started (outgoing share created) — schedule.
        XCTAssertTrue(BackgroundRefreshSchedulePolicy.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: true,
            partnerShareOwnerID: nil, outgoingShareParticipantIDs: []
        ))
        // Has a confirmed partner — schedule.
        XCTAssertTrue(BackgroundRefreshSchedulePolicy.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: false,
            partnerShareOwnerID: "_partner", outgoingShareParticipantIDs: []
        ))
        // Outgoing participants present — schedule.
        XCTAssertTrue(BackgroundRefreshSchedulePolicy.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: false,
            partnerShareOwnerID: nil, outgoingShareParticipantIDs: ["_p"]
        ))
    }

    func testNeverSchedulesWhenCloudKitDisabled() {
        // LOCAL_SIGNING / CloudKit-off builds must never arm a background sync.
        XCTAssertFalse(BackgroundRefreshSchedulePolicy.shouldSchedule(
            isCloudKitEnabled: false, hasStartedPairing: true,
            partnerShareOwnerID: "_partner", outgoingShareParticipantIDs: ["_p"]
        ))
    }

    func testEarliestBeginDateClampsToFifteenMinuteFloor() {
        let now = Date(timeIntervalSince1970: 10_000)
        // iOS won't run BGAppRefresh more than ~once/15min; a smaller ask is clamped up.
        let clamped = BackgroundRefreshSchedulePolicy.earliestBeginDate(from: now, requestedInterval: 60)
        XCTAssertEqual(clamped, now.addingTimeInterval(BackgroundRefreshSchedulePolicy.minimumInterval))
        // A larger interval is respected verbatim.
        let large = BackgroundRefreshSchedulePolicy.earliestBeginDate(from: now, requestedInterval: 3_600)
        XCTAssertEqual(large, now.addingTimeInterval(3_600))
        XCTAssertEqual(BackgroundRefreshSchedulePolicy.minimumInterval, 15 * 60)
    }

    func testTaskIdentifierMatchesBundlePrefix() {
        XCTAssertEqual(BackgroundRefreshSchedulePolicy.taskIdentifier, "com.leeberty.CoupleCalendar.refresh")
    }
}

final class OwnMirrorReconciliationPolicyTests: XCTestCase {
    func testReconcilesUntilOneUploadHasBeenConfirmedOnThisInstall() {
        XCTAssertTrue(OwnMirrorReconciliationPolicy.shouldReconcileWithCloud(existingShadows: []))
        // Shadows are written before the cloud step, so an unconfirmed shadow (a failed
        // or pre-pairing sync) must not end the reconciliation window.
        XCTAssertTrue(
            OwnMirrorReconciliationPolicy.shouldReconcileWithCloud(existingShadows: [shadow(uploadedAt: nil)])
        )
        XCTAssertFalse(
            OwnMirrorReconciliationPolicy.shouldReconcileWithCloud(
                existingShadows: [shadow(uploadedAt: nil), shadow(uploadedAt: Date(timeIntervalSince1970: 1))]
            )
        )
    }

    func testOwnedMirrorsTakeTheCurrentMemberIDRegardlessOfTheUploadedOne() {
        let owned = OwnMirrorReconciliationPolicy.ownedMirrors(
            [mirror(key: "k", owner: "local-user")],
            currentMemberID: "_me"
        )
        XCTAssertEqual(owned.map(\.ownerMemberID), ["_me"])
        XCTAssertEqual(owned.map(\.mirrorKey), ["k"])
    }

    /// The reinstall path feeds the cloud copies into the ordinary tombstone diff: a
    /// cloud mirror that is not regenerated from the calendar becomes a tombstone, one
    /// that is regenerated (same key) stays, and an already-deleted one is left alone.
    func testCloudMirrorsMissingFromTheCalendarBecomeTombstones() {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 10_000)
        let cloudMirrors = [
            mirror(key: "kept"),
            mirror(key: "vanished"),
            mirror(key: "already-dead", deletedAt: Date(timeIntervalSince1970: 500))
        ]

        let tombstones = EventMirrorService().deletedMirrorTombstones(
            existingEventKeys: ["kept"],
            existingMirrors: cloudMirrors,
            selectedCalendarIDs: ["sharecal"],
            syncWindow: window,
            deletedAt: now
        )

        XCTAssertEqual(tombstones.map(\.mirrorKey), ["vanished"])
        XCTAssertEqual(tombstones.first?.deletedAt, now)
        XCTAssertEqual(tombstones.first?.cloudKitRecordName, "vanished")
    }

    private func shadow(uploadedAt: Date?) -> LocalEventShadow {
        LocalEventShadow(
            id: "k",
            localEventIdentifier: "e",
            calendarIdentifier: "sharecal",
            occurrenceStartDate: Date(timeIntervalSince1970: 0),
            fingerprint: "f",
            cloudKitRecordName: "k",
            lastUploadedAt: uploadedAt,
            isTombstone: false
        )
    }

    private func mirror(key: String, owner: String = "_me", deletedAt: Date? = nil) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: owner,
            mirrorKey: key,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: Date(timeIntervalSince1970: 100),
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 160),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Shanghai",
            title: "Event",
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: deletedAt,
            cloudKitRecordName: key
        )
    }
}

// MARK: - Every device uploads its own events (pairing-sync-integrity 0017)

private func ownEvent(
    id: String,
    calendar: String,
    external: String? = "UID-1",
    start: TimeInterval = 1_800,
    title: String = "Dinner"
) -> CalendarSourceEvent {
    CalendarSourceEvent(
        eventIdentifier: id,
        calendarIdentifier: calendar,
        calendarTitle: "Home",
        calendarColorHex: "#3A86FF",
        startDate: Date(timeIntervalSince1970: start),
        endDate: Date(timeIntervalSince1970: start + 3_600),
        occurrenceStartDate: Date(timeIntervalSince1970: start),
        isAllDay: false,
        timeZoneIdentifier: "Asia/Shanghai",
        title: title,
        location: nil,
        notes: nil,
        url: nil,
        externalIdentifier: external
    )
}

private func ownMirrors(of events: [CalendarSourceEvent], keptKeys: [String: String] = [:]) -> [EventMirror] {
    EventMirrorService().makeMirrors(
        from: events,
        selectedCalendarIDs: Set(events.map(\.calendarIdentifier)),
        ownerMemberID: "_me",
        visibility: .fullDetails,
        keptKeys: keptKeys
    )
}

final class OwnEventUploadPolicyTests: XCTestCase {
    func testMacStartsRecordsOnlyOnceEveryLiveRecordHasAStableKey() {
        let withKey = ownMirrors(of: [ownEvent(id: "e", calendar: "phone")])
        let legacy = ownMirrors(of: [ownEvent(id: "old", calendar: "phone", external: "UID-2")])
        legacy[0].stableKey = nil
        let legacyTombstone = ownMirrors(of: [ownEvent(id: "gone", calendar: "phone", external: "UID-3")])
        legacyTombstone[0].stableKey = nil
        legacyTombstone[0].deletedAt = Date(timeIntervalSince1970: 5)

        XCTAssertTrue(OwnEventUploadPolicy.mayStartNewRecords(isRunningOnMac: false, cloudOwnMirrors: nil))
        XCTAssertFalse(OwnEventUploadPolicy.mayStartNewRecords(isRunningOnMac: true, cloudOwnMirrors: nil))
        XCTAssertTrue(OwnEventUploadPolicy.mayStartNewRecords(isRunningOnMac: true, cloudOwnMirrors: []))
        XCTAssertTrue(OwnEventUploadPolicy.mayStartNewRecords(isRunningOnMac: true, cloudOwnMirrors: withKey + legacyTombstone))
        XCTAssertFalse(OwnEventUploadPolicy.mayStartNewRecords(isRunningOnMac: true, cloudOwnMirrors: withKey + legacy))
    }

    func testIPhoneLooksUpOnlyWhileAMacUploads() {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        XCTAssertFalse(OwnEventUploadPolicy.looksUpNewEventsInCloud(isRunningOnMac: false, macUploadsOwnEventsAt: nil, now: now))
        XCTAssertTrue(OwnEventUploadPolicy.looksUpNewEventsInCloud(
            isRunningOnMac: false, macUploadsOwnEventsAt: now.addingTimeInterval(-3 * 86_400), now: now
        ))
        XCTAssertFalse(OwnEventUploadPolicy.looksUpNewEventsInCloud(
            isRunningOnMac: false, macUploadsOwnEventsAt: now.addingTimeInterval(-60 * 86_400), now: now
        ))
        XCTAssertFalse(OwnEventUploadPolicy.looksUpNewEventsInCloud(isRunningOnMac: true, macUploadsOwnEventsAt: now, now: now))
    }

    func testMacRestampsItsUploadTimeAtMostDaily() {
        let now = Date(timeIntervalSince1970: 10 * 86_400 + 0.7)
        let recent = Date(timeIntervalSince1970: 10 * 86_400 - 3_600)
        XCTAssertEqual(OwnEventUploadPolicy.macActivityStamp(previous: recent, now: now), recent)
        XCTAssertEqual(
            OwnEventUploadPolicy.macActivityStamp(previous: recent.addingTimeInterval(-86_400), now: now),
            Date(timeIntervalSince1970: 10 * 86_400)
        )
        XCTAssertEqual(OwnEventUploadPolicy.macActivityStamp(previous: nil, now: now), Date(timeIntervalSince1970: 10 * 86_400))
    }

    func testMacUploadTimeRelaysLaterWins() {
        var local = OwnRelayedSettings()
        local.macUploadsOwnEventsAt = Date(timeIntervalSince1970: 2_000)
        var cloud = OwnRelayedSettings()
        cloud.macUploadsOwnEventsAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            OwnSettingsRelayMergePolicy.merge(local: local, cloud: cloud).macUploadsOwnEventsAt,
            Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertEqual(
            OwnSettingsRelayMergePolicy.merge(local: cloud, cloud: local).macUploadsOwnEventsAt,
            Date(timeIntervalSince1970: 2_000)
        )
    }
}

final class OwnRecordAdoptionPolicyTests: XCTestCase {
    private func resolve(
        _ events: [CalendarSourceEvent],
        cloud: [EventMirror],
        confirmed: Set<String> = [],
        keptKeys: [String: String] = [:],
        wholeZone: Bool = true,
        mayStart: Bool = true,
        onMac: Bool = true
    ) -> OwnRecordAdoptionPolicy.Result {
        OwnRecordAdoptionPolicy.resolve(
            events: events,
            stableKeys: EventStableKeyPolicy.stableKeys(for: events),
            keptKeys: keptKeys,
            confirmedKeys: confirmed,
            cloudOwnMirrors: cloud,
            cloudCoversWholeZone: wholeZone,
            mayStartNewRecords: mayStart,
            isRunningOnMac: onMac
        )
    }

    private let phone = ownEvent(id: "phone-event", calendar: "phone-cal")
    private let mac = ownEvent(id: "mac-event", calendar: "mac-cal")

    func testMacTakesTheIPhonesRecordForTheSameEvent() {
        let uploaded = ownMirrors(of: [phone])
        let result = resolve([mac], cloud: uploaded)

        let macKey = EventMirrorKeyPolicy.makeMirrorKey(for: mac)
        XCTAssertEqual(result.keptKeys[macKey], uploaded[0].mirrorKey)
        XCTAssertEqual(result.adoptedKeys, [uploaded[0].mirrorKey])
        XCTAssertTrue(result.heldKeys.isEmpty)
    }

    func testMacStartsAPrefixedRecordForAnEventOnlyItHas() {
        let result = resolve([mac], cloud: [])
        let macKey = EventMirrorKeyPolicy.makeMirrorKey(for: mac)
        XCTAssertEqual(result.keptKeys[macKey], "mac:\(macKey)")
        XCTAssertTrue(result.adoptedKeys.isEmpty)

        // Next sync: the name book already gives the prefixed name.
        let again = resolve([mac], cloud: [], keptKeys: [macKey: "mac:\(macKey)"])
        XCTAssertEqual(again.keptKeys[macKey], "mac:\(macKey)")
    }

    func testMacHoldsNewEventsWhileItMayNotStartRecords() {
        let result = resolve([mac], cloud: [], mayStart: false)
        XCTAssertEqual(result.heldKeys, [EventMirrorKeyPolicy.makeMirrorKey(for: mac)])
        XCTAssertNil(result.keptKeys[EventMirrorKeyPolicy.makeMirrorKey(for: mac)])
    }

    func testEventDeletedOnTheOtherDeviceIsHeldNotRevived() {
        let deleted = ownMirrors(of: [phone])
        deleted[0].deletedAt = Date(timeIntervalSince1970: 5)
        let result = resolve([mac], cloud: deleted)
        XCTAssertEqual(result.heldKeys, [EventMirrorKeyPolicy.makeMirrorKey(for: mac)])
    }

    func testMacMovesToTheIPhonesRecordWhenBothStartedOne() {
        let macKey = "mac:\(EventMirrorKeyPolicy.makeMirrorKey(for: mac))"
        let macRecord = ownMirrors(of: [mac], keptKeys: [EventMirrorKeyPolicy.makeMirrorKey(for: mac): macKey])
        let phoneRecord = ownMirrors(of: [phone])

        let result = resolve(
            [mac],
            cloud: macRecord + phoneRecord,
            confirmed: [macKey],
            keptKeys: [EventMirrorKeyPolicy.makeMirrorKey(for: mac): macKey]
        )

        XCTAssertEqual(result.keptKeys[EventMirrorKeyPolicy.makeMirrorKey(for: mac)], phoneRecord[0].mirrorKey)
        XCTAssertTrue(result.adoptedKeys.isEmpty, "a move between known records uploads as usual")
    }

    func testIPhoneKeepsItsRecordAndTakesTheMacsForANewEvent() {
        let phoneKey = EventMirrorKeyPolicy.makeMirrorKey(for: phone)
        let macRecord = ownMirrors(of: [mac], keptKeys: [EventMirrorKeyPolicy.makeMirrorKey(for: mac): "mac:x"])

        let confirmedPhone = resolve([phone], cloud: macRecord, confirmed: [phoneKey], wholeZone: false, onMac: false)
        XCTAssertNil(confirmedPhone.keptKeys[phoneKey])

        let newOnPhone = resolve([phone], cloud: macRecord, wholeZone: false, onMac: false)
        XCTAssertEqual(newOnPhone.keptKeys[phoneKey], "mac:x")
        XCTAssertEqual(newOnPhone.adoptedKeys, ["mac:x"])
    }

    func testIPhoneWithoutCloudViewStartsRecordsAsBefore() {
        let result = resolve([phone], cloud: [], wholeZone: false, onMac: false)
        XCTAssertTrue(result.keptKeys.isEmpty)
        XCTAssertTrue(result.heldKeys.isEmpty)
    }

    func testEventsSharingOneStableKeyAdoptNothing() {
        let first = ownEvent(id: "a", calendar: "mac-cal")
        let second = ownEvent(id: "b", calendar: "mac-cal-2")
        let uploaded = ownMirrors(of: [ownEvent(id: "p", calendar: "phone-cal")])
        // Same UID, same calendar title: the stable keys collide.
        let result = resolve([first, second], cloud: uploaded)
        XCTAssertFalse(result.keptKeys.values.contains(uploaded[0].mirrorKey))
    }

    func testAnEmptyStableKeyIsNeverMatched() {
        let uploaded = ownMirrors(of: [ownEvent(id: "p", calendar: "phone-cal", external: nil)])
        let result = resolve([ownEvent(id: "m", calendar: "mac-cal", external: nil)], cloud: uploaded)
        XCTAssertFalse(result.keptKeys.values.contains(uploaded[0].mirrorKey))
    }

    func testIPhoneRecordIsPreferredOverAMacsThenTheSmallerName() {
        XCTAssertEqual(OwnRecordAdoptionPolicy.preferred(["mac:a", "z"]), "z")
        XCTAssertEqual(OwnRecordAdoptionPolicy.preferred(["b", "a"]), "a")
        XCTAssertEqual(OwnRecordAdoptionPolicy.preferred(["mac:b", "mac:a"]), "mac:a")
        XCTAssertNil(OwnRecordAdoptionPolicy.preferred([]))
    }
}

final class OwnRecordUploadFilterPolicyTests: XCTestCase {
    func testWithoutACloudViewEverythingUploads() {
        let mirrors = ownMirrors(of: [ownEvent(id: "e", calendar: "c")])
        XCTAssertEqual(OwnRecordUploadFilterPolicy.uploads(mirrors, cloudByKey: nil, adoptedKeys: []).count, 1)
    }

    func testWhatTheCloudHoldsAlreadyIsNotWrittenAgain() {
        let phoneCopy = ownMirrors(of: [ownEvent(id: "p", calendar: "phone-cal")])[0]
        let macCopy = ownMirrors(
            of: [ownEvent(id: "m", calendar: "mac-cal")],
            keptKeys: [EventMirrorKeyPolicy.makeMirrorKey(for: ownEvent(id: "m", calendar: "mac-cal")): phoneCopy.mirrorKey]
        )[0]
        let cloud = [phoneCopy.mirrorKey: phoneCopy]

        XCTAssertTrue(OwnRecordUploadFilterPolicy.uploads([macCopy], cloudByKey: cloud, adoptedKeys: []).isEmpty)
    }

    func testFirstSightKeepsTheCloudCopyButALaterEditUploads() {
        let phoneCopy = ownMirrors(of: [ownEvent(id: "p", calendar: "phone-cal")])[0]
        let macEvent = ownEvent(id: "m", calendar: "mac-cal", title: "Dinner with Mum")
        let macCopy = ownMirrors(
            of: [macEvent],
            keptKeys: [EventMirrorKeyPolicy.makeMirrorKey(for: macEvent): phoneCopy.mirrorKey]
        )[0]
        let cloud = [phoneCopy.mirrorKey: phoneCopy]

        XCTAssertTrue(OwnRecordUploadFilterPolicy.uploads([macCopy], cloudByKey: cloud, adoptedKeys: [phoneCopy.mirrorKey]).isEmpty)
        XCTAssertEqual(OwnRecordUploadFilterPolicy.uploads([macCopy], cloudByKey: cloud, adoptedKeys: []).count, 1)
    }

    func testDeletingWhatIsAlreadyDeletedIsSkipped() {
        let tombstone = ownMirrors(of: [ownEvent(id: "e", calendar: "c")])[0]
        tombstone.deletedAt = Date(timeIntervalSince1970: 9)
        let cloudTombstone = ownMirrors(of: [ownEvent(id: "e", calendar: "c")])[0]
        cloudTombstone.deletedAt = Date(timeIntervalSince1970: 3)
        let cloudLive = ownMirrors(of: [ownEvent(id: "e", calendar: "c")])[0]

        XCTAssertTrue(OwnRecordUploadFilterPolicy.uploads(
            [tombstone], cloudByKey: [tombstone.mirrorKey: cloudTombstone], adoptedKeys: []
        ).isEmpty)
        XCTAssertEqual(OwnRecordUploadFilterPolicy.uploads(
            [tombstone], cloudByKey: [tombstone.mirrorKey: cloudLive], adoptedKeys: []
        ).count, 1)
        XCTAssertEqual(OwnRecordUploadFilterPolicy.uploads([tombstone], cloudByKey: [:], adoptedKeys: []).count, 1)
    }

    func testMacKeepsItsOwnMirrorsAndTheCloudCopiesOfTheRest() {
        let mine = ownMirrors(of: [ownEvent(id: "m", calendar: "mac-cal")])
        let stale = ownMirrors(of: [ownEvent(id: "m", calendar: "mac-cal", title: "Old")])
        let phoneOnly = ownMirrors(of: [ownEvent(id: "p", calendar: "on-my-iphone", external: "UID-9")])

        let persisted = OwnMirrorReconciliationPolicy.persistedOwnMirrors(generated: mine, cloud: stale + phoneOnly)

        XCTAssertEqual(persisted.map(\.title).sorted(), ["Dinner", "Dinner"])
        XCTAssertEqual(Set(persisted.map(\.mirrorKey)), Set((mine + phoneOnly).map(\.mirrorKey)))
    }
}

// MARK: - Settings that follow me to my other devices (pairing-sync-integrity 0013)

final class OwnSettingsRelayMergePolicyTests: XCTestCase {
    private let t1 = Date(timeIntervalSince1970: 1_000)
    private let t2 = Date(timeIntervalSince1970: 2_000)

    func testNewerPartWinsPartByPart() {
        var local = OwnRelayedSettings()
        local.defaultVisibility = .init(rawValue: EventVisibility.busyOnly.rawValue, updatedAt: t2)
        local.language = .init(rawValue: AppLanguage.english.rawValue, updatedAt: t1)
        var cloud = OwnRelayedSettings()
        cloud.defaultVisibility = .init(rawValue: EventVisibility.fullDetails.rawValue, updatedAt: t1)
        cloud.language = .init(rawValue: AppLanguage.chinese.rawValue, updatedAt: t2)

        let merged = OwnSettingsRelayMergePolicy.merge(local: local, cloud: cloud)

        XCTAssertEqual(merged.defaultVisibility?.rawValue, EventVisibility.busyOnly.rawValue)
        XCTAssertEqual(merged.language?.rawValue, AppLanguage.chinese.rawValue)
        XCTAssertTrue(OwnSettingsRelayMergePolicy.needsUpload(merged: merged, cloud: cloud))
    }

    func testTieKeepsCloudAndNeedsNoWrite() {
        var local = OwnRelayedSettings()
        local.language = .init(rawValue: AppLanguage.english.rawValue, updatedAt: t1)
        var cloud = OwnRelayedSettings()
        cloud.language = .init(rawValue: AppLanguage.chinese.rawValue, updatedAt: t1)

        let merged = OwnSettingsRelayMergePolicy.merge(local: local, cloud: cloud)

        XCTAssertEqual(merged, cloud)
        XCTAssertFalse(OwnSettingsRelayMergePolicy.needsUpload(merged: merged, cloud: cloud))
    }

    func testMissingPartsAndReadPosition() {
        var local = OwnRelayedSettings()
        local.lastSeenActivityAt = t1
        var cloud = OwnRelayedSettings()
        cloud.lastSeenActivityAt = t2
        cloud.language = .init(rawValue: AppLanguage.chinese.rawValue, updatedAt: t1)

        let merged = OwnSettingsRelayMergePolicy.merge(local: local, cloud: cloud)

        XCTAssertEqual(merged.lastSeenActivityAt, t2)
        XCTAssertEqual(merged.language, cloud.language)
        XCTAssertEqual(OwnSettingsRelayMergePolicy.merge(local: local, cloud: nil), local)
        XCTAssertFalse(OwnSettingsRelayMergePolicy.needsUpload(merged: .empty, cloud: nil))
    }

    func testStampDropsFractionsOfASecond() {
        XCTAssertEqual(
            OwnSettingsRelayClock.stamp(Date(timeIntervalSince1970: 1_234.987)),
            Date(timeIntervalSince1970: 1_234)
        )
    }
}

final class CalendarSelectionRelayPolicyTests: XCTestCase {
    private func calendar(_ id: String, _ title: String, source: String) -> CalendarDescriptor {
        CalendarDescriptor(id: id, title: title, colorHex: "#000000", allowsContentModifications: true, sourceTitle: source)
    }

    private func ref(_ source: String, _ title: String) -> CalendarReference {
        CalendarReference(sourceTitle: source, title: title)
    }

    func testKeepsOtherDeviceCalendarsAndTakesThisDevicesChoiceForItsOwn() {
        let macCalendars = [
            calendar("mac-work", "Work", source: "iCloud"),
            calendar("mac-home", "Home", source: "iCloud")
        ]
        let relayed: Set = [ref("iCloud", "Work"), ref("On My iPhone", "ShareCal")]

        let result = CalendarSelectionRelayPolicy.references(
            relayed: relayed,
            localSelection: ["mac-home"],
            calendars: macCalendars
        )

        XCTAssertEqual(result, [ref("On My iPhone", "ShareCal"), ref("iCloud", "Home")])
    }

    func testMatchesByAccountAndTitleAndSkipsDuplicates() {
        let calendars = [
            calendar("a", "Family", source: "iCloud"),
            calendar("b", "Family", source: "someone@gmail.com"),
            calendar("c", "Work", source: "iCloud"),
            calendar("d", "Work", source: "iCloud")
        ]
        let relayed: Set = [ref("iCloud", "Family"), ref("iCloud", "Work"), ref("Exchange", "Team")]

        XCTAssertEqual(CalendarSelectionRelayPolicy.localIDs(for: relayed, calendars: calendars), ["a"])
        XCTAssertEqual(
            CalendarSelectionRelayPolicy.unavailable(relayed, calendars: calendars),
            [ref("Exchange", "Team"), ref("iCloud", "Work")]
        )
    }

    func testNothingMatchingKeepsTheLocalSelection() {
        let relayed = OwnRelayedSettings.Calendars(references: [ref("On My iPhone", "ShareCal")], updatedAt: .distantPast)
        XCTAssertNil(
            OwnSettingsRelayAdoptionPolicy.calendarSelection(
                relayed: relayed,
                calendars: [calendar("mac-sharecal", "ShareCal", source: "On My Mac")]
            )
        )
    }
}

final class SettingsStoreRelayTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        super.tearDown()
    }

    private func makeStore() -> SettingsStore {
        let name = "SettingsStoreRelayTests-\(UUID().uuidString)"
        suiteNames.append(name)
        return SettingsStore(defaults: UserDefaults(suiteName: name)!)
    }

    private let iPhoneCalendars = [
        CalendarDescriptor(id: "phone-work", title: "Work", colorHex: "#000000", allowsContentModifications: true, sourceTitle: "iCloud"),
        CalendarDescriptor(id: "phone-sharecal", title: "ShareCal", colorHex: "#000000", allowsContentModifications: true, sourceTitle: "On My iPhone")
    ]
    private let macCalendars = [
        CalendarDescriptor(id: "mac-work", title: "Work", colorHex: "#000000", allowsContentModifications: true, sourceTitle: "iCloud")
    ]

    func testSettingsMadeBeforeUpgradeReachANewDevice() {
        let phone = makeStore()
        phone.partnerShareOwnerID = "_partner"
        phone.partnerNoteName = "宝"
        phone.hasPromptedPartnerNoteForCurrentPairing = true
        phone.selectedCalendarIDs = ["phone-work", "phone-sharecal"]
        // Before this version nothing was stamped.
        phone.partnerNoteUpdatedAt = nil

        let uploaded = phone.relayedSettingsSnapshot(calendars: iPhoneCalendars)
        XCTAssertEqual(uploaded.partnerNote?.noteName, "宝")
        XCTAssertEqual(uploaded.partnerNote?.updatedAt, .distantPast)
        XCTAssertEqual(uploaded.calendars?.references.count, 2)

        let mac = makeStore()
        mac.adoptRelayedSettings(uploaded, calendars: macCalendars)
        XCTAssertEqual(mac.selectedCalendarIDs, ["mac-work"])
        XCTAssertEqual(mac.partnerNoteName, "", "the Mac doesn't know the partner yet")

        mac.partnerShareOwnerID = "_partner"
        mac.adoptRelayedSettings(uploaded, calendars: macCalendars)
        XCTAssertEqual(mac.partnerNoteName, "宝")
        XCTAssertTrue(mac.hasPromptedPartnerNoteForCurrentPairing)
        XCTAssertTrue(mac.hasShownPairingSafetyNoticeForCurrentPairing)
    }

    func testAdoptedCopyIsNotWrittenBack() {
        let phone = makeStore()
        phone.partnerShareOwnerID = "_partner"
        phone.partnerNoteName = "宝"
        phone.hasPromptedPartnerNoteForCurrentPairing = true
        phone.toggleCalendarSelection("phone-work", isSelected: true)
        phone.defaultVisibility = .busyOnly
        let cloud = phone.relayedSettingsSnapshot(calendars: iPhoneCalendars)

        let mac = makeStore()
        mac.partnerShareOwnerID = "_partner"
        mac.adoptRelayedSettings(cloud, calendars: macCalendars)
        let merged = OwnSettingsRelayMergePolicy.merge(local: mac.relayedSettingsSnapshot(calendars: macCalendars), cloud: cloud)

        XCTAssertEqual(mac.defaultVisibility, .busyOnly)
        XCTAssertFalse(OwnSettingsRelayMergePolicy.needsUpload(merged: merged, cloud: cloud))
    }

    func testOwnNewerEditIsKeptAndOlderCopyIgnored() {
        let mac = makeStore()
        mac.defaultVisibility = .titleAndLocation
        var older = OwnRelayedSettings()
        older.defaultVisibility = .init(rawValue: EventVisibility.busyOnly.rawValue, updatedAt: Date(timeIntervalSince1970: 1))

        mac.adoptRelayedSettings(older, calendars: nil)

        XCTAssertEqual(mac.defaultVisibility, .titleAndLocation)
        XCTAssertNotNil(mac.defaultVisibilityUpdatedAt)
    }

    func testAutomaticShareCalSelectionIsNotAnEdit() {
        let mac = makeStore()
        mac.selectedCalendarIDs = ["mac-work"]
        XCTAssertNil(mac.calendarSelectionUpdatedAt)

        mac.toggleCalendarSelection("mac-work", isSelected: false)
        XCTAssertNotNil(mac.calendarSelectionUpdatedAt)
    }

    func testNoteForAnotherPartnerIsIgnored() {
        let mac = makeStore()
        mac.partnerShareOwnerID = "_new"
        var relayed = OwnRelayedSettings()
        relayed.partnerNote = .init(partnerID: "_old", noteName: "前任", avatarOverride: nil, updatedAt: Date(timeIntervalSince1970: 5))

        mac.adoptRelayedSettings(relayed, calendars: nil)

        XCTAssertEqual(mac.partnerNoteName, "")
        XCTAssertFalse(mac.hasPromptedPartnerNoteForCurrentPairing)
    }
}

final class OwnEventCloudOnlyMirrorTests: XCTestCase {
    private func mirror(key: String, calendarTitle: String, start: TimeInterval, deleted: Bool = false) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: "me",
            mirrorKey: key,
            sourceCalendarID: "phone-\(calendarTitle)",
            sourceCalendarTitle: calendarTitle,
            occurrenceStartDate: Date(timeIntervalSince1970: start),
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: start + 60),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: key,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: deleted ? Date(timeIntervalSince1970: 0) : nil,
            cloudKitRecordName: key
        )
    }

    func testShowsOnlyLiveCopiesFromCalendarsThisDeviceDoesntShow() {
        let week = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 10_000))
        let shown = mirror(key: "shown", calendarTitle: "Work", start: 100)
        let persisted = [
            shown,
            mirror(key: "phone-only", calendarTitle: "ShareCal", start: 200),
            mirror(key: "edited-here", calendarTitle: "Work", start: 300),
            mirror(key: "gone", calendarTitle: "ShareCal", start: 400, deleted: true),
            mirror(key: "next-week", calendarTitle: "ShareCal", start: 20_000)
        ]

        let result = OwnEventTwinPolicy.cloudOnlyMirrors(
            display: [shown],
            persistedOwn: persisted,
            localCalendarTitles: ["Work"],
            in: week
        )

        XCTAssertEqual(result.map(\.mirrorKey), ["phone-only"])
    }
}

final class PairingDateRelayTests: XCTestCase {
    private var suiteNames: [String] = []
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    override func tearDown() {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        super.tearDown()
    }

    private func makeStore() -> SettingsStore {
        let name = "PairingDateRelayTests-\(UUID().uuidString)"
        suiteNames.append(name)
        return SettingsStore(defaults: UserDefaults(suiteName: name)!)
    }

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: value))!
    }

    func testSamePartnerKeepsTheEarliestDay() {
        let phone = OwnRelayedSettings.Pairing(partnerID: "_partner", date: day(1))
        let mac = OwnRelayedSettings.Pairing(partnerID: "_partner", date: day(24))
        XCTAssertEqual(PairingDateRelayPolicy.merge(mac, phone, clearedAt: nil, calendar: calendar), phone)
        XCTAssertEqual(PairingDateRelayPolicy.merge(phone, mac, clearedAt: nil, calendar: calendar), phone)
    }

    func testNewPartnerReplacesTheOldPairing() {
        let old = OwnRelayedSettings.Pairing(partnerID: "_old", date: day(1))
        let new = OwnRelayedSettings.Pairing(partnerID: "_new", date: day(20))
        XCTAssertEqual(PairingDateRelayPolicy.merge(new, old, clearedAt: nil, calendar: calendar), new)
    }

    func testPairingFromBeforeUnpairIsDropped() {
        let old = OwnRelayedSettings.Pairing(partnerID: "_partner", date: day(1))
        let again = OwnRelayedSettings.Pairing(partnerID: "_partner", date: day(20))
        let clearedAt = day(20).addingTimeInterval(3_600)
        XCTAssertEqual(PairingDateRelayPolicy.merge(again, old, clearedAt: clearedAt, calendar: calendar), again)
        XCTAssertNil(PairingDateRelayPolicy.merge(nil, old, clearedAt: clearedAt, calendar: calendar))
    }

    func testNewDeviceTakesTheIPhoneDayOverItsOwnFirstSync() {
        let phone = makeStore()
        phone.partnerShareOwnerID = "_partner"
        phone.pairingDate = day(1)
        let uploaded = phone.relayedSettingsSnapshot(calendars: nil)
        XCTAssertEqual(uploaded.pairing, .init(partnerID: "_partner", date: day(1)))

        let mac = makeStore()
        mac.adoptRelayedSettings(uploaded, calendars: nil)
        XCTAssertNil(mac.pairingDate, "the partner isn't known yet")

        mac.partnerShareOwnerID = "_partner"
        mac.markPairingDateIfNeeded(at: day(24), calendar: calendar)
        mac.adoptRelayedSettings(uploaded, calendars: nil)
        XCTAssertEqual(mac.pairingDate, day(1))

        let merged = OwnSettingsRelayMergePolicy.merge(
            local: mac.relayedSettingsSnapshot(calendars: nil),
            cloud: uploaded,
            calendar: calendar
        )
        XCTAssertFalse(OwnSettingsRelayMergePolicy.needsUpload(merged: merged, cloud: uploaded))
    }

    func testRecoveredDayIsReplacedAndNeverRelayed() {
        let mac = makeStore()
        mac.partnerShareOwnerID = "_partner"
        // The share root was made when the invitation went out, before the partner accepted.
        mac.setRecoveredPairingDate(day(1))
        XCTAssertNil(mac.relayedSettingsSnapshot(calendars: nil).pairing)

        var relayed = OwnRelayedSettings()
        relayed.pairing = .init(partnerID: "_partner", date: day(3))
        mac.adoptRelayedSettings(relayed, calendars: nil)
        XCTAssertEqual(mac.pairingDate, day(3))
        XCTAssertFalse(mac.pairingDateIsRecovered)
    }

    func testOtherPartnersDayIsNotAdopted() {
        let mac = makeStore()
        mac.partnerShareOwnerID = "_new"
        mac.pairingDate = day(20)
        var relayed = OwnRelayedSettings()
        relayed.pairing = .init(partnerID: "_old", date: day(1))
        mac.adoptRelayedSettings(relayed, calendars: nil)
        XCTAssertEqual(mac.pairingDate, day(20))
    }

    func testUnpairStampsTheClearTime() {
        let phone = makeStore()
        phone.partnerShareOwnerID = "_partner"
        phone.pairingDate = day(1)
        phone.clearPairingState()
        XCTAssertNil(phone.pairingDate)
        XCTAssertNotNil(phone.pairingClearedAt)
        XCTAssertNil(phone.relayedSettingsSnapshot(calendars: nil).pairing)
    }
}

final class EventTombstonePurgePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000_000)
    private var old: Date { now.addingTimeInterval(-EventTombstonePurgePolicy.retention) }
    private var recent: Date { now.addingTimeInterval(-EventTombstonePurgePolicy.retention + 1) }

    func testPurgesOnlyTombstonesPastRetention() {
        let expired = EventTombstonePurgePolicy.expiredTombstones(
            localOwnMirrors: [
                mirror(key: "live"),
                mirror(key: "old", deletedAt: old),
                mirror(key: "recent", deletedAt: recent),
                mirror(key: "future", deletedAt: now.addingTimeInterval(3_600))
            ],
            cloudOwnMirrors: nil,
            liveKeys: ["live"],
            confirmedKeys: [],
            ownCalendarIDs: ["sharecal"],
            now: now
        )

        XCTAssertEqual(expired.map(\.mirrorKey), ["old"])
    }

    func testDevicePurgesOnlyTheTombstonesItLooksAfter() {
        // My other device's tombstones (written from its calendars, never confirmed here).
        let expired = EventTombstonePurgePolicy.expiredTombstones(
            localOwnMirrors: [mirror(key: "old", deletedAt: old)],
            cloudOwnMirrors: [mirror(key: "cloud-old", deletedAt: old)],
            liveKeys: [],
            confirmedKeys: [],
            ownCalendarIDs: ["mac-calendar"],
            now: now
        )
        XCTAssertTrue(expired.isEmpty)

        // One it uploaded itself, though last written from the other device's calendar.
        let confirmed = EventTombstonePurgePolicy.expiredTombstones(
            localOwnMirrors: [mirror(key: "old", deletedAt: old)],
            cloudOwnMirrors: [mirror(key: "cloud-old", deletedAt: old)],
            liveKeys: [],
            confirmedKeys: ["old"],
            ownCalendarIDs: ["mac-calendar"],
            now: now
        )
        XCTAssertEqual(confirmed.map(\.mirrorKey), ["old"])
    }

    func testReinstallSweepsTombstonesFoundInTheCloudOnce() {
        let expired = EventTombstonePurgePolicy.expiredTombstones(
            localOwnMirrors: [mirror(key: "both", deletedAt: old)],
            cloudOwnMirrors: [
                mirror(key: "both", deletedAt: old),
                mirror(key: "cloud-only", deletedAt: old),
                mirror(key: "cloud-recent", deletedAt: recent)
            ],
            liveKeys: [],
            confirmedKeys: [],
            ownCalendarIDs: ["sharecal"],
            now: now
        )

        XCTAssertEqual(expired.map(\.mirrorKey), ["both", "cloud-only"])
    }

    func testRecordOfAnEventThatExistsAgainStays() {
        // The event is back in the calendar (this sync re-uploads it live), or one of
        // the two copies still shows it live or freshly deleted.
        let expired = EventTombstonePurgePolicy.expiredTombstones(
            localOwnMirrors: [
                mirror(key: "back", deletedAt: old),
                mirror(key: "cloud-live", deletedAt: old),
                mirror(key: "cloud-redeleted", deletedAt: old)
            ],
            cloudOwnMirrors: [
                mirror(key: "cloud-live"),
                mirror(key: "cloud-redeleted", deletedAt: recent)
            ],
            liveKeys: ["back"],
            confirmedKeys: [],
            ownCalendarIDs: ["sharecal"],
            now: now
        )

        XCTAssertTrue(expired.isEmpty)
    }

    func testCommentsOfPurgedEventsGoWithThem() {
        let comments = [
            EventComment(eventMirrorID: "old", authorMemberID: "_me", body: "mine", createdAt: now),
            EventComment(eventMirrorID: "old", authorMemberID: "_partner", body: "theirs", createdAt: now),
            EventComment(eventMirrorID: "live", authorMemberID: "_partner", body: "stays", createdAt: now)
        ]

        let purged = EventTombstonePurgePolicy.commentsToPurge(comments, purged: [mirror(key: "old", deletedAt: old)])

        XCTAssertEqual(purged.map(\.body), ["mine", "theirs"])
    }

    private func mirror(key: String, deletedAt: Date? = nil) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: "_me",
            mirrorKey: key,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: Date(timeIntervalSince1970: 100),
            startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 160),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Shanghai",
            title: "Event",
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: deletedAt,
            cloudKitRecordName: key
        )
    }
}
