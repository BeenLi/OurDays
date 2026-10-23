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
