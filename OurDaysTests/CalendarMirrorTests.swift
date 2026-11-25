import SwiftData
import XCTest

final class EventMirrorServiceTests: XCTestCase {
    func testBuildMirrorsOnlySelectedCalendarsAndUsesStableOccurrenceKey() {
        let occurrence = CalendarSourceEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            url: URL(string: "https://example.com")
        )
        let ignored = CalendarSourceEvent(
            eventIdentifier: "event-2",
            calendarIdentifier: "private",
            calendarTitle: "Private",
            calendarColorHex: "#FF006E",
            startDate: Date(timeIntervalSince1970: 4_000),
            endDate: Date(timeIntervalSince1970: 5_000),
            occurrenceStartDate: Date(timeIntervalSince1970: 4_000),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Hidden",
            location: nil,
            notes: nil,
            url: nil
        )

        let mirrors = EventMirrorService().makeMirrors(
            from: [occurrence, ignored],
            selectedCalendarIDs: ["work"],
            ownerMemberID: "me",
            visibility: .fullDetails
        )

        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors[0].ownerMemberID, "me")
        XCTAssertEqual(mirrors[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(mirrors[0].title, "Planning")
        XCTAssertEqual(mirrors[0].location, "Cafe")
        XCTAssertEqual(mirrors[0].notes, "Bring notes")
    }

    func testBusyOnlyVisibilityStripsSensitiveFieldsBeforeUpload() {
        let event = CalendarSourceEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Sensitive title",
            location: "Home",
            notes: "Sensitive note",
            url: URL(string: "https://example.com")
        )

        let mirror = EventMirrorService().makeMirrors(
            from: [event],
            selectedCalendarIDs: ["work"],
            ownerMemberID: "me",
            visibility: .busyOnly
        )[0]

        XCTAssertEqual(mirror.title, "Busy")
        XCTAssertNil(mirror.location)
        XCTAssertNil(mirror.notes)
        XCTAssertNil(mirror.urlString)
    }

    func testDetectDeletedLocalEventsCreatesTombstones() {
        let shadow = LocalEventShadow(
            localEventIdentifier: "event-1",
            calendarIdentifier: "work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            fingerprint: "old",
            cloudKitRecordName: "record-1",
            lastUploadedAt: Date(timeIntervalSince1970: 2_000),
            isTombstone: false
        )

        let tombstones = EventMirrorService().deletedShadows(
            existingEventKeys: [],
            shadows: [shadow]
        )

        XCTAssertEqual(tombstones.map(\.cloudKitRecordName), ["record-1"])
        XCTAssertTrue(tombstones[0].isTombstone)
    }

    func testBuildsLocalEventShadowsForUploadedMirrors() {
        let event = CalendarSourceEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            url: URL(string: "https://example.com")
        )

        let shadows = EventMirrorService().makeShadows(
            from: [event],
            selectedCalendarIDs: ["work"],
            uploadedAt: Date(timeIntervalSince1970: 5_000)
        )

        XCTAssertEqual(shadows.count, 1)
        XCTAssertEqual(shadows[0].id, "work:event-1:1800")
        XCTAssertEqual(shadows[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(shadows[0].cloudKitRecordName, "work:event-1:1800")
        XCTAssertEqual(shadows[0].lastUploadedAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertFalse(shadows[0].isTombstone)
    }

    func testDeletedLocalEventProducesDeletedMirrorTombstone() {
        let deletedAt = Date(timeIntervalSince1970: 6_000)
        let existingMirror = EventMirror(
            id: "work:event-1:1800",
            ownerMemberID: "me",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            urlString: "https://example.com",
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "record-1"
        )
        let deletedShadow = LocalEventShadow(
            id: "work:event-1:1800",
            localEventIdentifier: "event-1",
            calendarIdentifier: "work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            fingerprint: "old",
            cloudKitRecordName: "record-1",
            lastUploadedAt: Date(timeIntervalSince1970: 5_000),
            isTombstone: true
        )

        let tombstones = EventMirrorService().deletedMirrorTombstones(
            for: [deletedShadow],
            existingMirrors: [existingMirror],
            deletedAt: deletedAt
        )

        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(tombstones[0].title, "Planning")
        XCTAssertEqual(tombstones[0].cloudKitRecordName, "record-1")
        XCTAssertEqual(tombstones[0].deletedAt, deletedAt)
    }

    func testMissingLocalMirrorProducesDeletedTombstoneEvenWithoutShadow() {
        let deletedAt = Date(timeIntervalSince1970: 6_000)
        let existingMirror = EventMirror(
            id: "work:event-1:1800",
            ownerMemberID: "me",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            urlString: nil,
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "record-1"
        )

        let tombstones = EventMirrorService().deletedMirrorTombstones(
            existingEventKeys: [],
            existingMirrors: [existingMirror],
            selectedCalendarIDs: ["work"],
            syncWindow: DateInterval(start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 5_000)),
            deletedAt: deletedAt
        )

        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(tombstones[0].deletedAt, deletedAt)
    }

    func testFiltersMirrorsAndShadowsToAllowedSharingWindows() {
        let pairingDate = Date(timeIntervalSince1970: 100_000)
        let window = CalendarSharingWindowPolicy.defaultWindows(now: pairingDate)[0]
        let oldEvent = calendarEvent(id: "old", startDate: pairingDate.addingTimeInterval(-60))
        let pairedDayEvent = calendarEvent(id: "paired-day", startDate: pairingDate.addingTimeInterval(60))
        let futureEvent = calendarEvent(id: "future", startDate: pairingDate.addingTimeInterval(10 * 24 * 60 * 60))

        let mirrors = EventMirrorService().makeMirrors(
            from: [oldEvent, pairedDayEvent, futureEvent],
            selectedCalendarIDs: ["work"],
            ownerMemberID: "me",
            visibility: .fullDetails,
            sharingWindows: [window]
        )
        let shadows = EventMirrorService().makeShadows(
            from: [oldEvent, pairedDayEvent, futureEvent],
            selectedCalendarIDs: ["work"],
            uploadedAt: pairingDate,
            sharingWindows: [window]
        )

        XCTAssertEqual(mirrors.map(\.title), ["paired-day", "future"])
        XCTAssertEqual(shadows.map(\.localEventIdentifier), ["paired-day", "future"])
    }

    func testBuildsHardDeleteRecordNamesForOutOfWindowMirrorsWithoutTombstones() {
        let pairingDate = Date(timeIntervalSince1970: 100_000)
        let allowed = CalendarSharingWindowPolicy.defaultWindows(now: pairingDate)
        let oldMirror = eventMirror(
            id: "old",
            ownerMemberID: "me",
            startDate: pairingDate.addingTimeInterval(-60),
            cloudKitRecordName: "old-record"
        )
        let pairedDayMirror = eventMirror(
            id: "paired-day",
            ownerMemberID: "me",
            startDate: pairingDate.addingTimeInterval(60),
            cloudKitRecordName: "paired-day-record"
        )

        let stale = EventMirrorService().mirrorsOutsideSharingWindows(
            [oldMirror, pairedDayMirror],
            sharingWindows: allowed
        )

        XCTAssertEqual(stale.map(\.cloudKitRecordName), ["old-record"])
        XCTAssertNil(stale[0].deletedAt)
        XCTAssertEqual(stale[0].title, "old")
    }

    private func calendarEvent(id: String, startDate: Date) -> CalendarSourceEvent {
        CalendarSourceEvent(
            eventIdentifier: id,
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            occurrenceStartDate: startDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: id,
            location: nil,
            notes: nil,
            url: nil
        )
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        startDate: Date,
        cloudKitRecordName: String
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: id,
            location: "Private",
            notes: "Sensitive",
            urlString: nil,
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: cloudKitRecordName
        )
    }
}

final class CalendarDisplayMirrorPolicyTests: XCTestCase {
    func testTransientDisplayMirrorsDoNotCarryCloudKitRecordNames() {
        let event = CalendarSourceEvent(
            eventIdentifier: "local-event",
            calendarIdentifier: "personal-calendar",
            calendarTitle: "Personal",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 11_000),
            occurrenceStartDate: Date(timeIntervalSince1970: 10_000),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Older local event",
            location: "Home",
            notes: "Visible only to me",
            url: nil
        )

        let mirrors = CalendarDisplayMirrorPolicy.displayMirrors(
            from: [event],
            ownerMemberID: "me"
        )

        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors[0].ownerMemberID, "me")
        XCTAssertEqual(mirrors[0].sourceCalendarID, "personal-calendar")
        XCTAssertEqual(mirrors[0].title, "Older local event")
        XCTAssertNil(mirrors[0].cloudKitRecordName)
        // A lone transient display mirror has no persisted twin, so it can't be commented on.
        XCTAssertNil(EventDetailMirrorResolutionPolicy.persistedTwin(for: mirrors[0], in: []))
    }
}

final class CalendarSharingWindowPolicyTests: XCTestCase {
    func testDefaultWindowSharesFromPairingDateToDistantFuture() {
        let pairingDate = Date(timeIntervalSince1970: 1_000_000)

        let windows = CalendarSharingWindowPolicy.defaultWindows(now: pairingDate)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, pairingDate)
        XCTAssertEqual(windows[0].end, Date.distantFuture)
        XCTAssertFalse(CalendarSharingWindowPolicy.contains(pairingDate.addingTimeInterval(-60), in: windows))
        XCTAssertTrue(CalendarSharingWindowPolicy.contains(pairingDate.addingTimeInterval(60), in: windows))
    }

    func testApprovedPrivateOwnerRequestsExpandEffectiveWindows() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let pairingDate = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let approvedStart = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let approvedEnd = now.addingTimeInterval(-20 * 24 * 60 * 60)
        let approved = CalendarAccessRequest(
            requesterMemberID: "partner",
            ownerMemberID: "_stableSelfOwner",
            requestedStartDate: approvedStart,
            requestedEndDate: approvedEnd,
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let pending = CalendarAccessRequest(
            requesterMemberID: "partner",
            ownerMemberID: "_stableSelfOwner",
            requestedStartDate: now.addingTimeInterval(-60 * 24 * 60 * 60),
            requestedEndDate: now.addingTimeInterval(-50 * 24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let sharedCopy = CalendarAccessRequest(
            requesterMemberID: "partner",
            ownerMemberID: "_stableSelfOwner",
            requestedStartDate: now.addingTimeInterval(-90 * 24 * 60 * 60),
            requestedEndDate: now.addingTimeInterval(-80 * 24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )

        let windows = CalendarSharingWindowPolicy.effectiveWindows(
            now: pairingDate,
            accessRequests: [approved, pending, sharedCopy]
        )

        XCTAssertTrue(CalendarSharingWindowPolicy.contains(approvedStart.addingTimeInterval(60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPolicy.contains(now.addingTimeInterval(-55 * 24 * 60 * 60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPolicy.contains(now.addingTimeInterval(-85 * 24 * 60 * 60), in: windows))
        XCTAssertTrue(CalendarSharingWindowPolicy.contains(now.addingTimeInterval(30 * 24 * 60 * 60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPolicy.contains(pairingDate.addingTimeInterval(-60), in: windows))
    }

    func testOnlyApprovedPrivateOwnerHistoryRequestsExpandOwnerUploadWindow() {
        let pairingDate = Date(timeIntervalSince1970: 1_000_000)
        let approvedStart = pairingDate.addingTimeInterval(-30 * 24 * 60 * 60)
        let approvedEnd = pairingDate.addingTimeInterval(-20 * 24 * 60 * 60)
        let privateOwnerRequest = CalendarAccessRequest(
            id: "private-owner",
            requesterMemberID: "me",
            ownerMemberID: "_stableSelfOwner",
            requestedStartDate: approvedStart,
            requestedEndDate: approvedEnd,
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let sharedOutgoingCopy = CalendarAccessRequest(
            id: "shared-copy",
            requesterMemberID: "me",
            ownerMemberID: "me",
            requestedStartDate: pairingDate.addingTimeInterval(-60 * 24 * 60 * 60),
            requestedEndDate: pairingDate.addingTimeInterval(-50 * 24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )

        let windows = CalendarSharingWindowPolicy.effectiveWindows(
            now: pairingDate,
            accessRequests: [privateOwnerRequest, sharedOutgoingCopy]
        )

        XCTAssertTrue(CalendarSharingWindowPolicy.contains(approvedStart.addingTimeInterval(60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPolicy.contains(pairingDate.addingTimeInterval(-55 * 24 * 60 * 60), in: windows))
    }

    func testEnclosingIntervalUsesEarliestStartAndLatestEnd() {
        let first = DateInterval(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20))
        let second = DateInterval(start: Date(timeIntervalSince1970: -10), end: Date(timeIntervalSince1970: 30))

        let enclosing = CalendarSharingWindowPolicy.enclosingInterval(for: [first, second])

        XCTAssertEqual(enclosing.start, Date(timeIntervalSince1970: -10))
        XCTAssertEqual(enclosing.end, Date(timeIntervalSince1970: 30))
    }
}

final class ShareCalCalendarBootstrapPolicyTests: XCTestCase {
    func testOffersCreationWhenShareCalCalendarIsMissing() {
        let calendars = [
            CalendarDescriptor(id: "work", title: "Work", colorHex: "#3A86FF", allowsContentModifications: true)
        ]

        XCTAssertTrue(ShareCalCalendarBootstrapPolicy.shouldOfferCreation(calendars: calendars))
    }

    func testDoesNotOfferCreationWhenWritableShareCalCalendarExists() {
        let calendars = [
            CalendarDescriptor(id: "sharecal", title: "ShareCal", colorHex: "#FF2D55", allowsContentModifications: true)
        ]

        XCTAssertFalse(ShareCalCalendarBootstrapPolicy.shouldOfferCreation(calendars: calendars))
    }

    func testSelectsEnsuredShareCalCalendar() {
        let selected = ShareCalCalendarBootstrapPolicy.selectedCalendarIDs(
            afterEnsuring: CalendarDescriptor(id: "sharecal", title: "ShareCal", colorHex: "#FF2D55", allowsContentModifications: true),
            currentSelection: ["work"]
        )

        XCTAssertEqual(selected, ["sharecal", "work"])
    }
}

final class CalendarMirrorVisibilityPolicyTests: XCTestCase {
    func testShowsOnlyCurrentMemberAndStablePartnerOwnerMirrors() {
        let current = mirror(owner: "me", key: "current")
        let sharedOwner = mirror(owner: "icloud-owner", key: "shared-owner")
        let partnerNickname = mirror(owner: "yoki", key: "partner-nickname")
        let staleNickname = mirror(owner: "partner", key: "stale-nickname")
        let stranger = mirror(owner: "someone-else", key: "stranger")

        let visible = CalendarMirrorVisibilityPolicy.memberMirrors(
            [current, sharedOwner, partnerNickname, staleNickname, stranger],
            currentMemberID: "me",
            partnerShareOwnerID: "icloud-owner"
        )

        XCTAssertEqual(visible.map(\.mirrorKey), ["current", "shared-owner"])
    }

    func testHidesPartnerMirrorsWhenStablePartnerOwnerIsUnknown() {
        let current = mirror(owner: "me", key: "current")
        let partnerNickname = mirror(owner: "yoki", key: "partner-nickname")

        let visible = CalendarMirrorVisibilityPolicy.memberMirrors(
            [current, partnerNickname],
            currentMemberID: "me",
            partnerShareOwnerID: nil
        )

        XCTAssertEqual(visible.map(\.mirrorKey), ["current"])
    }

    private func mirror(
        owner: String,
        key: String,
        sourceCalendarID: String = "calendar"
    ) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: owner,
            mirrorKey: key,
            sourceCalendarID: sourceCalendarID,
            sourceCalendarTitle: "Calendar",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_000),
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: key,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: key
        )
    }
}

final class CalendarSetupGuidancePolicyTests: XCTestCase {
    func testHidesGuidanceUntilInitialProfileIsComplete() {
        XCTAssertNil(CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: false,
            currentDisplayName: "",
            authorizationState: .notDetermined,
            selectedCalendarIDs: [],
            pairingStatus: .notPaired
        ))
    }

    func testShowsCalendarAccessGuidanceWhenCalendarPermissionIsMissing() {
        XCTAssertEqual(CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .notDetermined,
            selectedCalendarIDs: ["work"],
            pairingStatus: .notPaired
        ), .calendarAccess)
    }

    func testShowsCalendarAccessGuidanceWhenNoCalendarsAreSelected() {
        XCTAssertEqual(CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .fullAccess,
            selectedCalendarIDs: [],
            pairingStatus: .notPaired
        ), .calendarAccess)
    }

    func testShowsPairingGuidanceAfterCalendarSetupBeforePairingStarts() {
        XCTAssertEqual(CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .fullAccess,
            selectedCalendarIDs: ["work"],
            pairingStatus: .notPaired
        ), .pairing)
    }

    func testShowsShareBackGuidanceWhenWaitingForYouToShareBack() {
        XCTAssertEqual(CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .fullAccess,
            selectedCalendarIDs: ["work"],
            pairingStatus: .waitingForYouToShare
        ), .shareBack)
    }

    func testShareBackGuidanceComesBeforeCalendarAccess() {
        XCTAssertEqual(CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .notDetermined,
            selectedCalendarIDs: [],
            pairingStatus: .waitingForYouToShare
        ), .shareBack)
    }

    func testHidesShareBackGuidanceOnceTheLinkWasSentBack() {
        XCTAssertNil(CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .fullAccess,
            selectedCalendarIDs: ["work"],
            pairingStatus: .waitingForYouToShare,
            hasSentInviteBack: true
        ))
    }

    func testHidesGuidanceAfterOutgoingPairingStartsOrCompletes() {
        for status in [PairingStatus.waitingForPartner, .waitingForPartnerToShare, .paired] {
            XCTAssertNil(CalendarSetupGuidancePolicy.step(
                hasCompletedInitialProfilePrompt: true,
                currentDisplayName: "Yoki",
                authorizationState: .fullAccess,
                selectedCalendarIDs: ["work"],
                pairingStatus: status
            ))
        }
    }
}

final class ShareCalSmokeTestEventPolicyTests: XCTestCase {
    func testBuildsStableShortEventDraftNearNow() {
        let now = Date(timeIntervalSince1970: 2_000)
        let draft = ShareCalSmokeTestEventPolicy.draft(now: now)

        XCTAssertEqual(draft.title, "ShareCal E2E Smoke Test")
        XCTAssertEqual(draft.startDate, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(draft.endDate, now.addingTimeInterval(45 * 60))
        XCTAssertFalse(draft.isAllDay)
        XCTAssertEqual(draft.notes, "Created by ShareCal simulator validation.")
    }

    func testUsesCustomLaunchSeedTitleWhenProvided() {
        let title = ShareCalLaunchDiagnosticPolicy.seedCalendarEventTitle(
            arguments: [
                "ShareCal",
                "-ShareCalSeedCalendarEvent",
                "-ShareCalSeedCalendarEventTitle",
                "Owner bidirectional event"
            ]
        )

        XCTAssertEqual(title, "Owner bidirectional event")
    }
}

final class EventDetailMirrorResolutionPolicyTests: XCTestCase {
    func testRealMirrorResolvesToItself() {
        let real = mirror(id: "real-1", mirrorKey: "key-1", recordName: "real-1")

        let twin = EventDetailMirrorResolutionPolicy.persistedTwin(for: real, in: [real])

        XCTAssertEqual(twin?.id, "real-1")
    }

    func testDisplayMirrorResolvesToPersistedTwinByMirrorKey() {
        // My own event opens as a "display:" mirror; resolve to the synced twin so the comment
        // thread anchors to the real id (where the partner's comment on my event landed).
        let display = mirror(id: "display:key-1", mirrorKey: "key-1", recordName: nil)
        let persisted = mirror(id: "real-1", mirrorKey: "key-1", recordName: "real-1")

        let twin = EventDetailMirrorResolutionPolicy.persistedTwin(for: display, in: [persisted])

        XCTAssertEqual(twin?.id, "real-1")
    }

    func testDisplayMirrorWithoutTwinResolvesToNil() {
        let display = mirror(id: "display:key-2", mirrorKey: "key-2", recordName: nil)

        XCTAssertNil(EventDetailMirrorResolutionPolicy.persistedTwin(for: display, in: []))
    }

    private func mirror(id: String, mirrorKey: String, recordName: String?) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: "me",
            mirrorKey: mirrorKey,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: Date(timeIntervalSince1970: 0),
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Event",
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: recordName
        )
    }
}

final class OwnEventTwinPolicyTests: XCTestCase {
    private func mirror(id: String, key: String, title: String = "Dinner", start: TimeInterval = 1_000, deletedAt: Date? = nil) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: "_me",
            mirrorKey: key,
            sourceCalendarID: "cal",
            sourceCalendarTitle: "OurDays",
            occurrenceStartDate: Date(timeIntervalSince1970: start),
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: start + 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Shanghai",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: deletedAt,
            cloudKitRecordName: nil
        )
    }

    func testMacDisplayMirrorTakesTheUploadedCopysKey() {
        let display = mirror(id: "display:mac-key", key: "mac-key")
        let uploaded = mirror(id: "phone-key", key: "phone-key")

        let result = OwnEventTwinPolicy.adoptingPersistedKeys([display], persistedOwn: [uploaded])

        XCTAssertEqual(result.map(\.mirrorKey), ["phone-key"])
        XCTAssertEqual(result.map(\.id), ["display:phone-key"])
        XCTAssertEqual(EventDetailMirrorResolutionPolicy.persistedTwin(for: result[0], in: [uploaded])?.id, "phone-key")
    }

    func testMatchingKeyIsKept() {
        let display = mirror(id: "display:k", key: "k")
        let other = mirror(id: "other", key: "other")
        let same = mirror(id: "k", key: "k")
        XCTAssertEqual(OwnEventTwinPolicy.adoptingPersistedKeys([display], persistedOwn: [other, same]).map(\.mirrorKey), ["k"])
    }

    func testAmbiguousOrDeletedCopiesAreNotAdopted() {
        let twins = [mirror(id: "a", key: "a"), mirror(id: "b", key: "b")]
        XCTAssertEqual(
            OwnEventTwinPolicy.adoptingPersistedKeys([mirror(id: "display:x", key: "x")], persistedOwn: twins).map(\.mirrorKey),
            ["x"]
        )
        let deleted = mirror(id: "d", key: "d", deletedAt: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(
            OwnEventTwinPolicy.adoptingPersistedKeys([mirror(id: "display:y", key: "y")], persistedOwn: [deleted]).map(\.mirrorKey),
            ["y"]
        )
    }

    func testDifferentEventIsNotMatched() {
        let result = OwnEventTwinPolicy.adoptingPersistedKeys(
            [mirror(id: "display:x", key: "x", title: "Lunch")],
            persistedOwn: [mirror(id: "k", key: "k")]
        )
        XCTAssertEqual(result.map(\.mirrorKey), ["x"])
    }
}

final class CloudKitMirrorSyncPolicyTests: XCTestCase {
    func testSkipsUnchangedActiveMirrors() {
        let existing = eventMirror(id: "event-1", title: "Planning")
        let current = eventMirror(id: "event-1", title: "Planning")
        let shadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
            [current],
            activeShadows: [shadow],
            existingShadows: [shadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertTrue(mirrors.isEmpty)
    }

    func testUploadsNewActiveMirrors() {
        let current = eventMirror(id: "event-1", title: "Planning")
        let shadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
            [current],
            activeShadows: [shadow],
            existingShadows: [],
            existingLocalMirrors: []
        )

        XCTAssertEqual(mirrors.map(\.mirrorKey), ["work:event-1:1800"])
    }

    func testUploadsMirrorsWhoseShadowWasNeverConfirmedUploaded() {
        // A pre-pairing sync records shadows without an upload stamp; once a
        // partner exists those events must still be uploaded.
        let existing = eventMirror(id: "event-1", title: "Planning")
        let current = eventMirror(id: "event-1", title: "Planning")
        let activeShadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false, lastUploadedAt: nil)
        let existingShadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false, lastUploadedAt: nil)

        let mirrors = CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
            [current],
            activeShadows: [activeShadow],
            existingShadows: [existingShadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertEqual(mirrors.map(\.mirrorKey), ["work:event-1:1800"])
    }

    func testUploadsChangedActiveMirrors() {
        let existing = eventMirror(id: "event-1", title: "Planning")
        let current = eventMirror(id: "event-1", title: "Updated")
        let activeShadow = localShadow(id: "event-1", fingerprint: "new", isTombstone: false)
        let existingShadow = localShadow(id: "event-1", fingerprint: "old", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
            [current],
            activeShadows: [activeShadow],
            existingShadows: [existingShadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertEqual(mirrors.map(\.title), ["Updated"])
    }

    func testUploadsVisibilityOnlyChangesWhenFingerprintIsUnchanged() {
        let existing = eventMirror(id: "event-1", title: "Planning", visibility: .fullDetails)
        let current = eventMirror(id: "event-1", title: "Busy", visibility: .busyOnly)
        let shadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
            [current],
            activeShadows: [shadow],
            existingShadows: [shadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertEqual(mirrors.map(\.visibilityRawValue), [EventVisibility.busyOnly.rawValue])
    }

    func testUploadsDeletedMirrors() {
        let deletedAt = Date(timeIntervalSince1970: 5_000)
        let existing = eventMirror(id: "event-1", title: "Planning")
        let deleted = eventMirror(id: "event-1", title: "Planning", deletedAt: deletedAt)
        let existingShadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
            [deleted],
            activeShadows: [],
            existingShadows: [existingShadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors[0].deletedAt, deletedAt)
    }

    private func eventMirror(
        id: String,
        title: String,
        visibility: EventVisibility = .fullDetails,
        deletedAt: Date? = nil
    ) -> EventMirror {
        EventMirror(
            id: "work:\(id):1800",
            ownerMemberID: "me",
            mirrorKey: "work:\(id):1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: "Cafe",
            notes: "Bring notes",
            urlString: "https://example.com",
            calendarColorHex: "#3A86FF",
            visibilityRawValue: visibility.rawValue,
            deletedAt: deletedAt,
            cloudKitRecordName: "work:\(id):1800"
        )
    }

    private func localShadow(
        id: String,
        fingerprint: String,
        isTombstone: Bool,
        lastUploadedAt: Date? = Date(timeIntervalSince1970: 2_000)
    ) -> LocalEventShadow {
        LocalEventShadow(
            id: "work:\(id):1800",
            localEventIdentifier: id,
            calendarIdentifier: "work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            fingerprint: fingerprint,
            cloudKitRecordName: "work:\(id):1800",
            lastUploadedAt: lastUploadedAt,
            isTombstone: isTombstone
        )
    }
}

final class EventMirrorStoreTests: XCTestCase {
    @MainActor
    func testUpsertInsertsThenOverwritesByMirrorKey() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)

        try EventMirrorStore.upsert(mirror(key: "k", title: "First"), modelContext: context)
        try EventMirrorStore.upsert(mirror(key: "k", title: "Second"), modelContext: context)
        try EventMirrorStore.upsert(mirror(key: "other", title: "Other"), modelContext: context)
        try context.save()

        let mirrors = try context.fetch(FetchDescriptor<EventMirror>())
        XCTAssertEqual(mirrors.count, 2)
        XCTAssertEqual(mirrors.first { $0.mirrorKey == "k" }?.title, "Second")
    }

    private func mirror(key: String, title: String) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: "me",
            mirrorKey: key,
            sourceCalendarID: "calendar",
            sourceCalendarTitle: "Calendar",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_000),
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: key
        )
    }
}

final class RescheduledEventKeyTests: XCTestCase {
    // Repro 2026-11-24: an event moved 20:00 → 21:00 got a new key, a new record for the
    // partner, and the partner's comments (hung on the old record) vanished on both sides.
    func testMovedOneOffEventKeepsItsUploadedKey() {
        let moved = event(start: 5_400)
        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            [moved],
            existingShadows: [shadow(key: "work:event-1:1800", start: 1_800)],
            existingMirrors: [mirror(key: "work:event-1:1800", start: 1_800)]
        )

        XCTAssertEqual(kept, ["work:event-1:5400": "work:event-1:1800"])
        XCTAssertEqual(EventMirrorKeyPolicy.mirrorKey(for: moved, keptKeys: kept), "work:event-1:1800")
    }

    func testKeyIsFoundFromTheCloudCopyAloneAfterAReinstall() {
        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            [event(start: 5_400)],
            existingShadows: [],
            existingMirrors: [mirror(key: "work:event-1:1800", start: 1_800)]
        )

        XCTAssertEqual(kept, ["work:event-1:5400": "work:event-1:1800"])
    }

    func testUnmovedNewRecurringAndAmbiguousEventsUseTheirOwnKeys() {
        let old = [mirror(key: "work:event-1:1800", start: 1_800)]
        // Not moved: its own key is already live.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents([event(start: 1_800)], existingShadows: [], existingMirrors: old),
            [:]
        )
        // A new event: nothing carries its identifier.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents([event(id: "event-2", start: 5_400)], existingShadows: [], existingMirrors: old),
            [:]
        )
        // A repeating series' occurrences share the identifier, so they pair by date: only
        // with a copy closer than the series' spacing (a day when it can't be told).
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [event(start: 200_000, isRecurring: true)],
                existingShadows: [],
                existingMirrors: old
            ),
            [:]
        )
        // Two live keys for the identifier: no way to tell which is this event's.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [event(start: 5_400)],
                existingShadows: [],
                existingMirrors: old + [mirror(key: "work:event-1:3600", start: 3_600)]
            ),
            [:]
        )
        // A key another current event has is never taken.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [event(start: 5_400), event(start: 1_800)],
                existingShadows: [],
                existingMirrors: old
            ),
            [:]
        )
        // Same identifier in another calendar is another event.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [event(start: 5_400)],
                existingShadows: [],
                existingMirrors: [mirror(key: "home:event-1:1800", start: 1_800)]
            ),
            [:]
        )
    }

    func testDeletedOrTombstonedCopiesAreNotRevived() {
        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            [event(start: 5_400)],
            existingShadows: [shadow(key: "work:event-1:1800", start: 1_800, isTombstone: true)],
            existingMirrors: [mirror(key: "work:event-1:1800", start: 1_800, deletedAt: Date(timeIntervalSince1970: 9_000))]
        )

        XCTAssertEqual(kept, [:])
    }

    func testEventIdentifiersWithColonsMatchOnlyTheirOwnKeys() {
        // EventKit identifiers look like "UUID:UUID"; "event-1" must not claim "event-1:x"'s keys.
        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            [event(id: "A:B", start: 5_400)],
            existingShadows: [],
            existingMirrors: [mirror(key: "work:A:B:1800", start: 1_800)]
        )
        XCTAssertEqual(kept, ["work:A:B:5400": "work:A:B:1800"])

        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [event(id: "A", start: 5_400)],
                existingShadows: [],
                existingMirrors: [mirror(key: "work:A:B:1800", start: 1_800)]
            ),
            [:]
        )
    }

    func testMovedEventUpdatesItsRecordInPlaceInsteadOfTombstoningIt() {
        let service = EventMirrorService()
        let moved = event(start: 5_400)
        let oldShadow = shadow(key: "work:event-1:1800", start: 1_800)
        let oldMirror = mirror(key: "work:event-1:1800", start: 1_800)
        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            [moved],
            existingShadows: [oldShadow],
            existingMirrors: [oldMirror]
        )

        let mirrors = service.makeMirrors(
            from: [moved],
            selectedCalendarIDs: ["work"],
            ownerMemberID: "_me",
            visibility: .fullDetails,
            keptKeys: kept
        )
        let shadows = service.makeShadows(
            from: [moved],
            selectedCalendarIDs: ["work"],
            uploadedAt: nil,
            keptKeys: kept
        )

        XCTAssertEqual(mirrors.map(\.id), ["work:event-1:1800"])
        XCTAssertEqual(mirrors.map(\.cloudKitRecordName), ["work:event-1:1800"])
        XCTAssertEqual(mirrors.first?.startDate, Date(timeIntervalSince1970: 5_400))
        XCTAssertEqual(mirrors.first?.occurrenceStartDate, Date(timeIntervalSince1970: 5_400))
        XCTAssertEqual(shadows.map(\.id), ["work:event-1:1800"])
        XCTAssertEqual(shadows.map(\.mirrorKey), ["work:event-1:1800"])

        let currentKeys = Set(mirrors.map(\.mirrorKey))
        let window = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100_000))
        XCTAssertTrue(service.deletedShadows(existingEventKeys: currentKeys, shadows: [oldShadow], syncWindow: window).isEmpty)
        XCTAssertTrue(
            service.deletedMirrorTombstones(
                existingEventKeys: currentKeys,
                existingMirrors: [oldMirror],
                selectedCalendarIDs: ["work"],
                syncWindow: window,
                deletedAt: Date(timeIntervalSince1970: 9_000)
            ).isEmpty
        )
        // The new time is a change, so the record is uploaded again under its old name.
        XCTAssertEqual(
            CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
                mirrors,
                activeShadows: shadows,
                existingShadows: [oldShadow],
                existingLocalMirrors: [oldMirror]
            ).map(\.cloudKitRecordName),
            ["work:event-1:1800"]
        )

        // The next sync finds the kept key again from the updated shadow and mirror.
        let nextKept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            [moved],
            existingShadows: shadows,
            existingMirrors: mirrors
        )
        XCTAssertEqual(nextKept, kept)
    }

    func testDisplayMirrorOfAMovedEventShowsUnderItsUploadedKey() {
        let moved = event(start: 5_400)
        let display = CalendarDisplayMirrorPolicy.displayMirrors(
            from: [moved],
            ownerMemberID: "_me",
            keptKeys: EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [moved],
                existingShadows: [],
                existingMirrors: [mirror(key: "work:event-1:1800", start: 1_800)]
            )
        )

        XCTAssertEqual(display.map(\.mirrorKey), ["work:event-1:1800"])
        XCTAssertEqual(display.map(\.id), ["\(CalendarDisplayMirrorPolicy.transientIDPrefix)work:event-1:1800"])
    }

    private func event(id: String = "event-1", start: TimeInterval, isRecurring: Bool = false) -> CalendarSourceEvent {
        CalendarSourceEvent(
            eventIdentifier: id,
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: start + 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: start),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Dinner",
            location: nil,
            notes: nil,
            url: nil,
            isRecurring: isRecurring
        )
    }

    private func shadow(key: String, start: TimeInterval, isTombstone: Bool = false) -> LocalEventShadow {
        LocalEventShadow(
            id: key,
            localEventIdentifier: "event-1",
            calendarIdentifier: "work",
            occurrenceStartDate: Date(timeIntervalSince1970: start),
            fingerprint: "old",
            cloudKitRecordName: key,
            lastUploadedAt: Date(timeIntervalSince1970: 2_000),
            isTombstone: isTombstone
        )
    }

    private func mirror(key: String, start: TimeInterval, deletedAt: Date? = nil) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: "_me",
            mirrorKey: key,
            sourceCalendarID: String(key.prefix(while: { $0 != ":" })),
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: start),
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: start + 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Dinner",
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: deletedAt,
            cloudKitRecordName: key
        )
    }
}

final class MovedSeriesKeyTests: XCTestCase {
    private let hour: TimeInterval = 3_600
    private let week: TimeInterval = 7 * 24 * 3_600
    private let firstWednesday: TimeInterval = 1_000_000
    private let service = EventMirrorService()

    // Every Wednesday 20:00 moved to 21:00: every occurrence date shifts, and each
    // occurrence keeps the record (and comments) it had.
    func testWholeSeriesMovedAnHourKeepsEveryRecord() {
        let before = series(weeks: 0..<4)
        let old = uploaded(before)
        let after = series(weeks: 0..<4, shift: hour)

        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            after,
            existingShadows: old.shadows,
            existingMirrors: old.mirrors
        )

        XCTAssertEqual(kept, Dictionary(uniqueKeysWithValues: zip(after.map(key), before.map(key))))

        let new = uploaded(after, keptKeys: kept)
        XCTAssertEqual(new.mirrors.map(\.mirrorKey), before.map(key))
        XCTAssertEqual(new.mirrors.map(\.occurrenceStartDate), after.map(\.occurrenceStartDate))
        XCTAssertTrue(
            service.deletedShadows(existingEventKeys: Set(new.mirrors.map(\.mirrorKey)), shadows: old.shadows).isEmpty
        )
        // Updated in place: uploaded again under the old names.
        XCTAssertEqual(
            CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
                new.mirrors,
                activeShadows: new.shadows,
                existingShadows: old.shadows,
                existingLocalMirrors: old.mirrors
            ).map(\.mirrorKey),
            before.map(key)
        )
        // Later syncs read the names back from the name book.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(after, existingShadows: new.shadows, existingMirrors: new.mirrors),
            kept
        )
        // Also from the mirrors alone, and from one week of the calendar.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [after[2]],
                existingShadows: [],
                existingMirrors: new.mirrors,
                matchesMovedSeries: false
            ),
            [key(after[2]): key(before[2])]
        )
    }

    func testSeriesMovedToAnotherWeekdayPairsWithTheNearestOccurrence() {
        let before = series(weeks: 0..<4)
        let old = uploaded(before)
        let after = series(weeks: 0..<4, shift: 2 * 24 * hour)

        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(after, existingShadows: old.shadows, existingMirrors: old.mirrors)

        XCTAssertEqual(kept, Dictionary(uniqueKeysWithValues: zip(after.map(key), before.map(key))))
    }

    // "All future events" from the third week: EventKit ends the old series there and
    // starts a new one, with a new event identifier, for the rest.
    func testAllFutureEventsMovedIntoANewSeriesKeepTheirRecords() {
        let before = series(weeks: 0..<4)
        let old = uploaded(before)
        let moved = series(id: "series-2", weeks: 2..<4, shift: hour)
        let after = series(weeks: 0..<2) + moved

        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(after, existingShadows: old.shadows, existingMirrors: old.mirrors)

        XCTAssertEqual(kept, [key(moved[0]): key(before[2]), key(moved[1]): key(before[3])])

        // The name book now files the old names under the new series.
        let new = uploaded(after, keptKeys: kept)
        XCTAssertEqual(new.shadows.map(\.id), before.map(key))
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(after, existingShadows: new.shadows, existingMirrors: new.mirrors),
            kept
        )
        // A reinstall's first sync has only the cloud copies, named after the old series.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(after, existingShadows: [], existingMirrors: new.mirrors),
            kept
        )
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                [moved[1]],
                existingShadows: new.shadows,
                existingMirrors: new.mirrors,
                matchesMovedSeries: false
            ),
            [key(moved[1]): key(before[3])]
        )
    }

    func testNewSeriesOnlyContinuesOneSeriesWithTheSameContent() {
        let before = series(weeks: 0..<4)
        let old = uploaded(before)
        // Another title: a different series, not the old one continued.
        let renamed = series(id: "series-2", weeks: 2..<4, shift: hour, title: "Gym")
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                series(weeks: 0..<2) + renamed,
                existingShadows: old.shadows,
                existingMirrors: old.mirrors
            ),
            [:]
        )
        // Two ended series with this content: no way to tell which one it continues.
        let twin = uploaded(series(id: "series-3", weeks: 2..<4, shift: 2 * hour))
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                series(weeks: 0..<2) + series(id: "series-2", weeks: 2..<4, shift: hour),
                existingShadows: old.shadows + twin.shadows,
                existingMirrors: old.mirrors + twin.mirrors
            ),
            [:]
        )
        // Another calendar is never searched.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                series(weeks: 0..<2) + series(id: "series-2", calendar: "home", weeks: 2..<4, shift: hour),
                existingShadows: old.shadows,
                existingMirrors: old.mirrors
            ),
            [:]
        )
    }

    func testDeletedAndNewOccurrencesAreNotMistakenForAMove() {
        let old = uploaded(series(weeks: 0..<4))
        // Week 2 deleted and week 4 new: two weeks apart, further than the series' spacing.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                series(weeks: 0..<2) + series(weeks: 3..<5),
                existingShadows: old.shadows,
                existingMirrors: old.mirrors
            ),
            [:]
        )
        // The last one deleted and the next one new: exactly the spacing apart.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                series(weeks: 0..<3) + series(weeks: 4..<5),
                existingShadows: old.shadows,
                existingMirrors: old.mirrors
            ),
            [:]
        )
        // More occurrences of an unmoved series are simply new.
        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                series(weeks: 0..<8),
                existingShadows: old.shadows,
                existingMirrors: old.mirrors
            ),
            [:]
        )
    }

    func testSeriesMovedBackTakesItsOwnKeysAgain() {
        let before = series(weeks: 0..<4)
        let old = uploaded(before)
        let shifted = series(weeks: 0..<4, shift: hour)
        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(shifted, existingShadows: old.shadows, existingMirrors: old.mirrors)
        let moved = uploaded(shifted, keptKeys: kept)

        let keptAfterMovingBack = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
            before,
            existingShadows: moved.shadows,
            existingMirrors: moved.mirrors
        )

        XCTAssertEqual(keptAfterMovingBack, [:])
        XCTAssertEqual(uploaded(before, keptKeys: keptAfterMovingBack).mirrors.map(\.mirrorKey), before.map(key))
    }

    // The new series took over the old names; then the old series runs again at its old
    // times. The names go back to the events that derive them, so no two events share one.
    func testKeptKeyIsGivenUpToTheEventThatDerivesIt() {
        let before = series(weeks: 0..<2)
        let old = uploaded(before)
        let moved = series(id: "series-2", weeks: 0..<2, shift: hour)
        let kept = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(moved, existingShadows: old.shadows, existingMirrors: old.mirrors)
        XCTAssertEqual(kept.count, 2)
        let new = uploaded(moved, keptKeys: kept)

        let both = before + moved
        let keptWithBoth = EventMirrorKeyPolicy.keptKeysForRescheduledEvents(both, existingShadows: new.shadows, existingMirrors: new.mirrors)

        XCTAssertEqual(keptWithBoth, [:])
        let keys = both.map { EventMirrorKeyPolicy.mirrorKey(for: $0, keptKeys: keptWithBoth) }
        XCTAssertEqual(Set(keys).count, both.count)
    }

    func testOneWeekOfTheCalendarLooksNamesUpButNeverPairs() {
        let old = uploaded(series(weeks: 0..<4))

        XCTAssertEqual(
            EventMirrorKeyPolicy.keptKeysForRescheduledEvents(
                series(weeks: 1..<2, shift: hour),
                existingShadows: old.shadows,
                existingMirrors: old.mirrors,
                matchesMovedSeries: false
            ),
            [:]
        )
    }

    func testContentIsReadBackFromAFingerprint() {
        let event = CalendarSourceEvent(
            eventIdentifier: "A:B",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 5_400),
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Dinner | date",
            location: "Home",
            notes: "a|b",
            url: URL(string: "https://example.com")
        )

        XCTAssertEqual(EventMirrorKeyPolicy.content(for: event), "Dinner | date|Home|a|b|https://example.com")
        XCTAssertEqual(
            EventMirrorKeyPolicy.fingerprint(for: event),
            "A:B|work|1800|5400|Dinner | date|Home|a|b|https://example.com"
        )
        XCTAssertEqual(
            EventMirrorKeyPolicy.content(
                ofFingerprint: EventMirrorKeyPolicy.fingerprint(for: event),
                eventIdentifier: "A:B",
                calendarIdentifier: "work"
            ),
            EventMirrorKeyPolicy.content(for: event)
        )
        XCTAssertNil(EventMirrorKeyPolicy.content(ofFingerprint: "old", eventIdentifier: "A:B", calendarIdentifier: "work"))
    }

    private func key(_ event: CalendarSourceEvent) -> String {
        EventMirrorKeyPolicy.makeMirrorKey(for: event)
    }

    /// The shadows and own mirrors a sync leaves behind for these events.
    private func uploaded(
        _ events: [CalendarSourceEvent],
        keptKeys: [String: String] = [:]
    ) -> (shadows: [LocalEventShadow], mirrors: [EventMirror]) {
        let calendars = Set(events.map(\.calendarIdentifier))
        return (
            service.makeShadows(
                from: events,
                selectedCalendarIDs: calendars,
                uploadedAt: Date(timeIntervalSince1970: 2_000),
                keptKeys: keptKeys
            ),
            service.makeMirrors(
                from: events,
                selectedCalendarIDs: calendars,
                ownerMemberID: "_me",
                visibility: .fullDetails,
                keptKeys: keptKeys
            )
        )
    }

    private func series(
        id: String = "series-1",
        calendar: String = "work",
        weeks: Range<Int>,
        shift: TimeInterval = 0,
        title: String = "Dinner"
    ) -> [CalendarSourceEvent] {
        weeks.map { index in
            let start = Date(timeIntervalSince1970: firstWednesday + Double(index) * week + shift)
            return CalendarSourceEvent(
                eventIdentifier: id,
                calendarIdentifier: calendar,
                calendarTitle: "Work",
                calendarColorHex: "#3A86FF",
                startDate: start,
                endDate: start.addingTimeInterval(hour),
                occurrenceStartDate: start,
                isAllDay: false,
                timeZoneIdentifier: "Asia/Singapore",
                title: title,
                location: nil,
                notes: nil,
                url: nil,
                isRecurring: true
            )
        }
    }
}

final class EventStableKeyPolicyTests: XCTestCase {
    private func event(
        id: String = "event-1",
        calendar: String = "phone-cal",
        calendarTitle: String = "Home",
        external: String? = "UID-1",
        start: TimeInterval = 1_800,
        occurrence: TimeInterval? = nil,
        isAllDay: Bool = false,
        isRecurring: Bool = false,
        isDetached: Bool = false
    ) -> CalendarSourceEvent {
        CalendarSourceEvent(
            eventIdentifier: id,
            calendarIdentifier: calendar,
            calendarTitle: calendarTitle,
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: start + 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: occurrence ?? start),
            isAllDay: isAllDay,
            timeZoneIdentifier: "Asia/Shanghai",
            title: "Dinner",
            location: nil,
            notes: nil,
            url: nil,
            isRecurring: isRecurring,
            externalIdentifier: external,
            isDetached: isDetached
        )
    }

    private func key(_ event: CalendarSourceEvent, among others: [CalendarSourceEvent] = []) -> String? {
        EventStableKeyPolicy.stableKeys(for: [event] + others)[EventMirrorKeyPolicy.makeMirrorKey(for: event)]
    }

    func testSameEventOnTwoDevicesGetsTheSameKey() {
        let phone = event(id: "phone-event", calendar: "phone-cal")
        let mac = event(id: "mac-event", calendar: "mac-cal")

        XCTAssertNotEqual(EventMirrorKeyPolicy.makeMirrorKey(for: phone), EventMirrorKeyPolicy.makeMirrorKey(for: mac))
        XCTAssertEqual(key(phone), key(mac))
        XCTAssertTrue(key(phone)?.hasPrefix("s1:") == true)
        XCTAssertFalse(key(phone)?.contains("UID-1") == true, "the partner can read the record; the raw ID is not in it")
    }

    func testMovedOneOffEventKeepsItsKey() {
        XCTAssertEqual(key(event(start: 1_800)), key(event(start: 90_000)))
    }

    func testOccurrencesOfASeriesDiffer() {
        let first = event(start: 1_800, isRecurring: true)
        let second = event(start: 1_800 + 86_400, isRecurring: true)
        XCTAssertNotEqual(key(first, among: [second]), key(second, among: [first]))
    }

    func testDetachedOccurrenceUsesItsOriginalDate() {
        let moved = event(start: 5_400, occurrence: 1_800, isDetached: true)
        let asSeenElsewhere = event(id: "mac-event", calendar: "mac-cal", start: 5_400, occurrence: 1_800, isRecurring: true)
        XCTAssertEqual(key(moved), key(asSeenElsewhere))
        XCTAssertNotEqual(key(moved), key(event(start: 5_400, occurrence: 5_400, isDetached: true)))
    }

    func testAllDayOccurrenceUsesTheCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 12, day: 24))!
        let first = event(occurrence: midnight.timeIntervalSince1970, isAllDay: true, isRecurring: true)
        let sameDay = event(occurrence: midnight.timeIntervalSince1970 + 12 * 3_600, isAllDay: true, isRecurring: true)
        let nextDay = event(occurrence: midnight.timeIntervalSince1970 + 86_400, isAllDay: true, isRecurring: true)
        XCTAssertEqual(
            EventStableKeyPolicy.base(for: first, calendar: calendar),
            EventStableKeyPolicy.base(for: sameDay, calendar: calendar)
        )
        XCTAssertNotEqual(
            EventStableKeyPolicy.base(for: first, calendar: calendar),
            EventStableKeyPolicy.base(for: nextDay, calendar: calendar)
        )
    }

    func testNoExternalIdentifierGivesAnEmptyKey() {
        XCTAssertEqual(key(event(external: nil)), "")
        XCTAssertEqual(key(event(external: "  ")), "")
    }

    func testSameInvitationInTwoCalendarsIsToldApartByCalendarTitle() {
        let home = event(id: "a", calendar: "c1", calendarTitle: "Home")
        let work = event(id: "b", calendar: "c2", calendarTitle: "Work")
        let keys = EventStableKeyPolicy.stableKeys(for: [home, work])
        XCTAssertNotEqual(keys[EventMirrorKeyPolicy.makeMirrorKey(for: home)], keys[EventMirrorKeyPolicy.makeMirrorKey(for: work)])
        XCTAssertNotEqual(key(home, among: [work]), key(home))
    }

    func testMirrorsAndDisplayMirrorsCarryTheKey() {
        let source = event()
        let mirrors = EventMirrorService().makeMirrors(
            from: [source],
            selectedCalendarIDs: ["phone-cal"],
            ownerMemberID: "_me",
            visibility: .busyOnly
        )
        XCTAssertEqual(mirrors.map(\.stableKey), [key(source)])
        let display = CalendarDisplayMirrorPolicy.displayMirrors(from: [source], ownerMemberID: "_me")
        XCTAssertEqual(display.map(\.stableKey), [key(source)])
        let tombstone = EventMirrorService().deletedMirrorTombstones(
            existingEventKeys: [],
            existingMirrors: mirrors,
            selectedCalendarIDs: ["phone-cal"],
            syncWindow: DateInterval(start: .distantPast, end: .distantFuture),
            deletedAt: Date(timeIntervalSince1970: 9_000)
        )
        XCTAssertEqual(tombstone.map(\.stableKey), [key(source)])
    }

    func testAddingTheKeyUploadsTheRecordOnce() {
        let source = event()
        let current = EventMirrorService().makeMirrors(
            from: [source],
            selectedCalendarIDs: ["phone-cal"],
            ownerMemberID: "_me",
            visibility: .fullDetails
        )
        let shadows = EventMirrorService().makeShadows(
            from: [source],
            selectedCalendarIDs: ["phone-cal"],
            uploadedAt: Date(timeIntervalSince1970: 2_000)
        )
        let before = EventMirrorService().makeMirrors(
            from: [source],
            selectedCalendarIDs: ["phone-cal"],
            ownerMemberID: "_me",
            visibility: .fullDetails
        )
        before[0].stableKey = nil

        XCTAssertEqual(
            CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
                current, activeShadows: shadows, existingShadows: shadows, existingLocalMirrors: before
            ).count,
            1
        )
        XCTAssertTrue(
            CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
                current, activeShadows: shadows, existingShadows: shadows, existingLocalMirrors: current
            ).isEmpty
        )
    }

    func testMacDisplayFindsTheUploadedCopyByStableKeyAfterAnEdit() {
        let onPhone = EventMirrorService().makeMirrors(
            from: [event(id: "phone-event", calendar: "phone-cal")],
            selectedCalendarIDs: ["phone-cal"],
            ownerMemberID: "_me",
            visibility: .fullDetails
        )
        // Edited on the Mac: title and time no longer match the uploaded copy.
        let edited = CalendarSourceEvent(
            eventIdentifier: "mac-event",
            calendarIdentifier: "mac-cal",
            calendarTitle: "Home",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 7_200),
            endDate: Date(timeIntervalSince1970: 10_800),
            occurrenceStartDate: Date(timeIntervalSince1970: 7_200),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Shanghai",
            title: "Dinner with Mum",
            location: nil,
            notes: nil,
            url: nil,
            externalIdentifier: "UID-1"
        )
        let display = CalendarDisplayMirrorPolicy.displayMirrors(from: [edited], ownerMemberID: "_me")

        let result = OwnEventTwinPolicy.adoptingPersistedKeys(display, persistedOwn: onPhone)

        XCTAssertEqual(result.map(\.mirrorKey), [onPhone[0].mirrorKey])
    }

    func testTwoDisplayMirrorsNeverTakeTheSameRecord() {
        let uploaded = EventMirrorService().makeMirrors(
            from: [event(id: "phone-event", calendar: "phone-cal", external: nil)],
            selectedCalendarIDs: ["phone-cal"],
            ownerMemberID: "_me",
            visibility: .fullDetails
        )
        let display = CalendarDisplayMirrorPolicy.displayMirrors(
            from: [
                event(id: "m1", calendar: "mac-cal", external: nil),
                event(id: "m2", calendar: "mac-cal-2", external: nil)
            ],
            ownerMemberID: "_me"
        )

        let keys = OwnEventTwinPolicy.adoptingPersistedKeys(display, persistedOwn: uploaded).map(\.mirrorKey)

        XCTAssertEqual(keys.filter { $0 == uploaded[0].mirrorKey }.count, 1)
    }
}

final class EventIdentifierDumpTests: XCTestCase {
    func testDumpListsOnlyMatchingEventsWithTheirStableKey() {
        func event(_ title: String, id: String) -> CalendarSourceEvent {
            CalendarSourceEvent(
                eventIdentifier: id,
                calendarIdentifier: "cal",
                calendarTitle: "Home",
                calendarColorHex: "#3A86FF",
                startDate: Date(timeIntervalSince1970: 1_800),
                endDate: Date(timeIntervalSince1970: 3_600),
                occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
                isAllDay: false,
                timeZoneIdentifier: "Asia/Shanghai",
                title: title,
                location: nil,
                notes: nil,
                url: nil,
                externalIdentifier: "UID-\(id)"
            )
        }
        let lines = ShareCalLaunchDiagnosticPolicy.eventIdentifierLines(
            [event("IDT plain", id: "1"), event("Dinner", id: "2")],
            titlePrefix: "IDT"
        )
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("external=UID-1"))
        XCTAssertTrue(lines[0].contains("stableKey=s1:"))
    }
}
