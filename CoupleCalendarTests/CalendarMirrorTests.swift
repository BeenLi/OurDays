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
        let window = CalendarSharingWindowPlan.defaultWindows(now: pairingDate)[0]
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
        let allowed = CalendarSharingWindowPlan.defaultWindows(now: pairingDate)
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

final class CalendarDisplayMirrorPlanTests: XCTestCase {
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

        let mirrors = CalendarDisplayMirrorPlan.displayMirrors(
            from: [event],
            ownerMemberID: "me"
        )

        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors[0].ownerMemberID, "me")
        XCTAssertEqual(mirrors[0].sourceCalendarID, "personal-calendar")
        XCTAssertEqual(mirrors[0].title, "Older local event")
        XCTAssertNil(mirrors[0].cloudKitRecordName)
        // A lone transient display mirror has no persisted twin, so it can't be commented on.
        XCTAssertNil(EventDetailMirrorResolutionPlan.persistedTwin(for: mirrors[0], in: []))
    }
}

final class CalendarSharingWindowPlanTests: XCTestCase {
    func testDefaultWindowSharesFromPairingDateToDistantFuture() {
        let pairingDate = Date(timeIntervalSince1970: 1_000_000)

        let windows = CalendarSharingWindowPlan.defaultWindows(now: pairingDate)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, pairingDate)
        XCTAssertEqual(windows[0].end, Date.distantFuture)
        XCTAssertFalse(CalendarSharingWindowPlan.contains(pairingDate.addingTimeInterval(-60), in: windows))
        XCTAssertTrue(CalendarSharingWindowPlan.contains(pairingDate.addingTimeInterval(60), in: windows))
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

        let windows = CalendarSharingWindowPlan.effectiveWindows(
            now: pairingDate,
            accessRequests: [approved, pending, sharedCopy]
        )

        XCTAssertTrue(CalendarSharingWindowPlan.contains(approvedStart.addingTimeInterval(60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPlan.contains(now.addingTimeInterval(-55 * 24 * 60 * 60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPlan.contains(now.addingTimeInterval(-85 * 24 * 60 * 60), in: windows))
        XCTAssertTrue(CalendarSharingWindowPlan.contains(now.addingTimeInterval(30 * 24 * 60 * 60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPlan.contains(pairingDate.addingTimeInterval(-60), in: windows))
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

        let windows = CalendarSharingWindowPlan.effectiveWindows(
            now: pairingDate,
            accessRequests: [privateOwnerRequest, sharedOutgoingCopy]
        )

        XCTAssertTrue(CalendarSharingWindowPlan.contains(approvedStart.addingTimeInterval(60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPlan.contains(pairingDate.addingTimeInterval(-55 * 24 * 60 * 60), in: windows))
    }

    func testEnclosingIntervalUsesEarliestStartAndLatestEnd() {
        let first = DateInterval(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20))
        let second = DateInterval(start: Date(timeIntervalSince1970: -10), end: Date(timeIntervalSince1970: 30))

        let enclosing = CalendarSharingWindowPlan.enclosingInterval(for: [first, second])

        XCTAssertEqual(enclosing.start, Date(timeIntervalSince1970: -10))
        XCTAssertEqual(enclosing.end, Date(timeIntervalSince1970: 30))
    }
}

final class ShareCalCalendarBootstrapPlanTests: XCTestCase {
    func testOffersCreationWhenShareCalCalendarIsMissing() {
        let calendars = [
            CalendarDescriptor(id: "work", title: "Work", colorHex: "#3A86FF", allowsContentModifications: true)
        ]

        XCTAssertTrue(ShareCalCalendarBootstrapPlan.shouldOfferCreation(calendars: calendars))
    }

    func testDoesNotOfferCreationWhenWritableShareCalCalendarExists() {
        let calendars = [
            CalendarDescriptor(id: "sharecal", title: "ShareCal", colorHex: "#FF2D55", allowsContentModifications: true)
        ]

        XCTAssertFalse(ShareCalCalendarBootstrapPlan.shouldOfferCreation(calendars: calendars))
    }

    func testSelectsEnsuredShareCalCalendar() {
        let selected = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
            afterEnsuring: CalendarDescriptor(id: "sharecal", title: "ShareCal", colorHex: "#FF2D55", allowsContentModifications: true),
            currentSelection: ["work"]
        )

        XCTAssertEqual(selected, ["sharecal", "work"])
    }
}

final class CalendarMirrorVisibilityPlanTests: XCTestCase {
    func testShowsOnlyCurrentMemberAndStablePartnerOwnerMirrors() {
        let current = mirror(owner: "me", key: "current")
        let sharedOwner = mirror(owner: "icloud-owner", key: "shared-owner")
        let partnerNickname = mirror(owner: "yoki", key: "partner-nickname")
        let staleNickname = mirror(owner: "partner", key: "stale-nickname")
        let stranger = mirror(owner: "someone-else", key: "stranger")

        let visible = CalendarMirrorVisibilityPlan.memberMirrors(
            [current, sharedOwner, partnerNickname, staleNickname, stranger],
            currentMemberID: "me",
            partnerShareOwnerID: "icloud-owner"
        )

        XCTAssertEqual(visible.map(\.mirrorKey), ["current", "shared-owner"])
    }

    func testHidesPartnerMirrorsWhenStablePartnerOwnerIsUnknown() {
        let current = mirror(owner: "me", key: "current")
        let partnerNickname = mirror(owner: "yoki", key: "partner-nickname")

        let visible = CalendarMirrorVisibilityPlan.memberMirrors(
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

final class CalendarSetupGuidancePlanTests: XCTestCase {
    func testHidesGuidanceUntilInitialProfileIsComplete() {
        XCTAssertNil(CalendarSetupGuidancePlan.step(
            hasCompletedInitialProfilePrompt: false,
            currentDisplayName: "",
            authorizationState: .notDetermined,
            selectedCalendarIDs: [],
            pairingStatus: .notPaired
        ))
    }

    func testShowsCalendarAccessGuidanceWhenCalendarPermissionIsMissing() {
        XCTAssertEqual(CalendarSetupGuidancePlan.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .notDetermined,
            selectedCalendarIDs: ["work"],
            pairingStatus: .notPaired
        ), .calendarAccess)
    }

    func testShowsCalendarAccessGuidanceWhenNoCalendarsAreSelected() {
        XCTAssertEqual(CalendarSetupGuidancePlan.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .fullAccess,
            selectedCalendarIDs: [],
            pairingStatus: .notPaired
        ), .calendarAccess)
    }

    func testShowsPairingGuidanceAfterCalendarSetupBeforePairingStarts() {
        XCTAssertEqual(CalendarSetupGuidancePlan.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .fullAccess,
            selectedCalendarIDs: ["work"],
            pairingStatus: .notPaired
        ), .pairing)
    }

    func testShowsPairingGuidanceWhenWaitingForYouToShareBack() {
        XCTAssertEqual(CalendarSetupGuidancePlan.step(
            hasCompletedInitialProfilePrompt: true,
            currentDisplayName: "Yoki",
            authorizationState: .fullAccess,
            selectedCalendarIDs: ["work"],
            pairingStatus: .waitingForYouToShare
        ), .pairing)
    }

    func testHidesGuidanceAfterOutgoingPairingStartsOrCompletes() {
        for status in [PairingStatus.waitingForPartner, .waitingForPartnerToShare, .paired] {
            XCTAssertNil(CalendarSetupGuidancePlan.step(
                hasCompletedInitialProfilePrompt: true,
                currentDisplayName: "Yoki",
                authorizationState: .fullAccess,
                selectedCalendarIDs: ["work"],
                pairingStatus: status
            ))
        }
    }
}

final class ShareCalSmokeTestEventPlanTests: XCTestCase {
    func testBuildsStableShortEventDraftNearNow() {
        let now = Date(timeIntervalSince1970: 2_000)
        let draft = ShareCalSmokeTestEventPlan.draft(now: now)

        XCTAssertEqual(draft.title, "ShareCal E2E Smoke Test")
        XCTAssertEqual(draft.startDate, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(draft.endDate, now.addingTimeInterval(45 * 60))
        XCTAssertFalse(draft.isAllDay)
        XCTAssertEqual(draft.notes, "Created by ShareCal simulator validation.")
    }

    func testUsesCustomLaunchSeedTitleWhenProvided() {
        let title = ShareCalLaunchDiagnosticPlan.seedCalendarEventTitle(
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

final class EventDetailMirrorResolutionPlanTests: XCTestCase {
    func testRealMirrorResolvesToItself() {
        let real = mirror(id: "real-1", mirrorKey: "key-1", recordName: "real-1")

        let twin = EventDetailMirrorResolutionPlan.persistedTwin(for: real, in: [real])

        XCTAssertEqual(twin?.id, "real-1")
    }

    func testDisplayMirrorResolvesToPersistedTwinByMirrorKey() {
        // My own event opens as a "display:" mirror; resolve to the synced twin so the comment
        // thread anchors to the real id (where the partner's comment on my event landed).
        let display = mirror(id: "display:key-1", mirrorKey: "key-1", recordName: nil)
        let persisted = mirror(id: "real-1", mirrorKey: "key-1", recordName: "real-1")

        let twin = EventDetailMirrorResolutionPlan.persistedTwin(for: display, in: [persisted])

        XCTAssertEqual(twin?.id, "real-1")
    }

    func testDisplayMirrorWithoutTwinResolvesToNil() {
        let display = mirror(id: "display:key-2", mirrorKey: "key-2", recordName: nil)

        XCTAssertNil(EventDetailMirrorResolutionPlan.persistedTwin(for: display, in: []))
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

final class CloudKitMirrorSyncPlanTests: XCTestCase {
    func testSkipsUnchangedActiveMirrors() {
        let existing = eventMirror(id: "event-1", title: "Planning")
        let current = eventMirror(id: "event-1", title: "Planning")
        let shadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
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

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
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

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
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

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
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

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
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

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
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
