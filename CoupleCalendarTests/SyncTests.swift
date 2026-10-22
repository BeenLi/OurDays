import SwiftData
import XCTest

final class ForegroundSyncPlanTests: XCTestCase {
    func testAllowsAutomaticSyncWhenThereIsNoPreviousSync() {
        XCTAssertTrue(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testSkipsAutomaticSyncWhenLastSyncIsWithinThrottleWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-(ForegroundSyncPlan.automaticThrottleInterval - 1))

        XCTAssertFalse(
            ForegroundSyncPlan.shouldRunAutomaticSync(
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
        XCTAssertLessThanOrEqual(ForegroundSyncPlan.automaticThrottleInterval, 60)
    }

    func testAllowsAutomaticSyncWhenThrottleWindowHasElapsed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-ForegroundSyncPlan.automaticThrottleInterval)

        XCTAssertTrue(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testSkipsAutomaticSyncWhileSyncing() {
        XCTAssertFalse(
            ForegroundSyncPlan.shouldRunAutomaticSync(
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
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: true
            )
        )
    }

    func testPendingAcceptedShareDoesNotStartDuplicateSync() {
        XCTAssertFalse(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .syncing,
                hasPendingAcceptedShare: true
            )
        )
    }
}

final class CloudKitForegroundSyncPlanTests: XCTestCase {
    func testSkipsCloudKitWhenSharingDisabledEvenIfForced() {
        XCTAssertFalse(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
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
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
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
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: true,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: "partner-owner",
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: ["participant"],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
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

final class BackgroundRefreshSchedulePlanTests: XCTestCase {
    func testSchedulesOnlyWhenCloudKitEnabledAndPairingActive() {
        // Unpaired install has nothing to fetch — don't spend background budget.
        XCTAssertFalse(BackgroundRefreshSchedulePlan.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: false,
            partnerShareOwnerID: nil, outgoingShareParticipantIDs: []
        ))
        // Pairing started (outgoing share created) — schedule.
        XCTAssertTrue(BackgroundRefreshSchedulePlan.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: true,
            partnerShareOwnerID: nil, outgoingShareParticipantIDs: []
        ))
        // Has a confirmed partner — schedule.
        XCTAssertTrue(BackgroundRefreshSchedulePlan.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: false,
            partnerShareOwnerID: "_partner", outgoingShareParticipantIDs: []
        ))
        // Outgoing participants present — schedule.
        XCTAssertTrue(BackgroundRefreshSchedulePlan.shouldSchedule(
            isCloudKitEnabled: true, hasStartedPairing: false,
            partnerShareOwnerID: nil, outgoingShareParticipantIDs: ["_p"]
        ))
    }

    func testNeverSchedulesWhenCloudKitDisabled() {
        // LOCAL_SIGNING / CloudKit-off builds must never arm a background sync.
        XCTAssertFalse(BackgroundRefreshSchedulePlan.shouldSchedule(
            isCloudKitEnabled: false, hasStartedPairing: true,
            partnerShareOwnerID: "_partner", outgoingShareParticipantIDs: ["_p"]
        ))
    }

    func testEarliestBeginDateClampsToFifteenMinuteFloor() {
        let now = Date(timeIntervalSince1970: 10_000)
        // iOS won't run BGAppRefresh more than ~once/15min; a smaller ask is clamped up.
        let clamped = BackgroundRefreshSchedulePlan.earliestBeginDate(from: now, requestedInterval: 60)
        XCTAssertEqual(clamped, now.addingTimeInterval(BackgroundRefreshSchedulePlan.minimumInterval))
        // A larger interval is respected verbatim.
        let large = BackgroundRefreshSchedulePlan.earliestBeginDate(from: now, requestedInterval: 3_600)
        XCTAssertEqual(large, now.addingTimeInterval(3_600))
        XCTAssertEqual(BackgroundRefreshSchedulePlan.minimumInterval, 15 * 60)
    }

    func testTaskIdentifierMatchesBundlePrefix() {
        XCTAssertEqual(BackgroundRefreshSchedulePlan.taskIdentifier, "com.leeberty.CoupleCalendar.refresh")
    }
}
