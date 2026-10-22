import XCTest

final class PrePairingHistoryAccessPlanTests: XCTestCase {
    func testApprovedOutgoingHistoryExpandsVisiblePartnerRange() {
        let calendar = gregorianUTC()
        let pairingDate = date(2026, 6, 9, calendar: calendar)
        let approved = historyRequest(
            id: "approved",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            start: date(2026, 6, 8, calendar: calendar),
            end: date(2026, 6, 9, calendar: calendar),
            status: .approved,
            source: .acceptedSharedZone
        )
        let pendingOlder = historyRequest(
            id: "pending-older",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            start: date(2026, 6, 7, calendar: calendar),
            end: date(2026, 6, 8, calendar: calendar),
            status: .pending,
            source: .acceptedSharedZone
        )

        XCTAssertEqual(
            PrePairingHistoryAccessPlan.contiguousAuthorizedStartDate(
                pairingDate: pairingDate,
                accessRequests: [approved, pendingOlder],
                currentMemberID: "xiaoyugan",
                ownerMemberID: "_manuOwner",
                direction: .partnerSharedToMe,
                calendar: calendar
            ),
            date(2026, 6, 8, calendar: calendar)
        )
    }

    func testNextRequestRangeStartsBeforeCurrentAuthorizedRange() {
        let calendar = gregorianUTC()
        let pairingDate = date(2026, 6, 9, calendar: calendar)
        let approved = historyRequest(
            id: "approved",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            start: date(2026, 6, 8, calendar: calendar),
            end: date(2026, 6, 9, calendar: calendar),
            status: .approved,
            source: .acceptedSharedZone
        )

        let range = PrePairingHistoryAccessPlan.defaultNextRequestRange(
            pairingDate: pairingDate,
            accessRequests: [approved],
            currentMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            calendar: calendar
        )

        XCTAssertEqual(range.start, date(2026, 5, 9, calendar: calendar))
        XCTAssertEqual(range.end, date(2026, 6, 7, calendar: calendar))
    }

    func testRequestValidationRejectsAuthorizedOrOverlappingRanges() {
        let calendar = gregorianUTC()
        let pairingDate = date(2026, 6, 9, calendar: calendar)
        let approved = historyRequest(
            id: "approved",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            start: date(2026, 6, 8, calendar: calendar),
            end: date(2026, 6, 9, calendar: calendar),
            status: .approved,
            source: .acceptedSharedZone
        )

        XCTAssertEqual(
            PrePairingHistoryAccessPlan.validation(
                requestedStartDate: date(2026, 6, 8, calendar: calendar),
                requestedEndDate: date(2026, 6, 9, calendar: calendar),
                pairingDate: pairingDate,
                accessRequests: [approved],
                currentMemberID: "xiaoyugan",
                ownerMemberID: "_manuOwner"
            ),
            .alreadyAuthorized
        )
        XCTAssertEqual(
            PrePairingHistoryAccessPlan.validation(
                requestedStartDate: date(2026, 6, 7, calendar: calendar),
                requestedEndDate: date(2026, 6, 9, calendar: calendar),
                pairingDate: pairingDate,
                accessRequests: [approved],
                currentMemberID: "xiaoyugan",
                ownerMemberID: "_manuOwner"
            ),
            .overlapsAuthorized
        )
        XCTAssertEqual(
            PrePairingHistoryAccessPlan.validation(
                requestedStartDate: date(2026, 6, 7, calendar: calendar),
                requestedEndDate: date(2026, 6, 8, calendar: calendar),
                pairingDate: pairingDate,
                accessRequests: [approved],
                currentMemberID: "xiaoyugan",
                ownerMemberID: "_manuOwner"
            ),
            .valid
        )
    }

    private func historyRequest(
        id: String,
        requesterMemberID: String,
        ownerMemberID: String,
        start: Date,
        end: Date,
        status: CalendarAccessRequestStatus,
        source: CalendarAccessRequestSource
    ) -> CalendarAccessRequest {
        CalendarAccessRequest(
            id: id,
            requesterMemberID: requesterMemberID,
            ownerMemberID: ownerMemberID,
            requestedStartDate: start,
            requestedEndDate: end,
            statusRawValue: status.rawValue,
            createdAt: start,
            updatedAt: start,
            sourceRawValue: source.rawValue
        )
    }

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

final class CalendarAccessRequestListPlanTests: XCTestCase {
    func testSourceMappingDrivesIncomingAndOutgoingListsWhenMemberIDsMatch() {
        let rangeStart = Date(timeIntervalSince1970: 10_000)
        let incoming = CalendarAccessRequest(
            id: "incoming",
            requesterMemberID: "me",
            ownerMemberID: "me",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let acceptedSharedCopy = CalendarAccessRequest(
            id: "shared-copy",
            requesterMemberID: "me",
            ownerMemberID: "me",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )
        let localOutgoing = CalendarAccessRequest(
            id: "local-outgoing",
            requesterMemberID: "me",
            ownerMemberID: "_partnerOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.localOutgoing.rawValue
        )

        XCTAssertEqual(
            CalendarAccessRequestListPlan.pendingIncoming(
                [incoming, acceptedSharedCopy, localOutgoing],
                currentMemberID: "me"
            ).map(\.id),
            ["incoming"]
        )
        XCTAssertEqual(
            CalendarAccessRequestListPlan.outgoing([incoming, acceptedSharedCopy, localOutgoing], currentMemberID: "me").map(\.id),
            ["shared-copy", "local-outgoing"]
        )
    }

    func testPendingOutgoingRequestsNeedCloudUploadRetry() {
        let rangeStart = Date(timeIntervalSince1970: 10_000)
        let pendingLocalOutgoing = CalendarAccessRequest(
            id: "local-outgoing",
            requesterMemberID: "me",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.localOutgoing.rawValue
        )
        let pendingSharedOutgoing = CalendarAccessRequest(
            id: "shared-outgoing",
            requesterMemberID: "me",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )
        let incoming = CalendarAccessRequest(
            id: "incoming",
            requesterMemberID: "partner",
            ownerMemberID: "me",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )

        // Only the locally-created copy that has not yet been confirmed on the
        // server needs uploading. The `.acceptedSharedZone` copy round-tripped back
        // from CloudKit, so re-uploading it would overwrite the owner's response.
        XCTAssertEqual(
            CalendarAccessRequestCloudUploadPlan.requestsNeedingUpload(
                [pendingLocalOutgoing, pendingSharedOutgoing, incoming],
                currentMemberID: "me"
            ).map(\.id),
            ["local-outgoing"]
        )
    }

    func testApprovedDuplicateSuppressesPendingHistoryRequestCopies() {
        let rangeStart = Date(timeIntervalSince1970: 10_000)
        let rangeEnd = rangeStart.addingTimeInterval(24 * 60 * 60)
        let stalePendingIncoming = CalendarAccessRequest(
            id: "stale-pending-incoming",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            updatedAt: rangeStart,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let approvedIncoming = CalendarAccessRequest(
            id: "approved-incoming",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            updatedAt: rangeStart.addingTimeInterval(60),
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let stalePendingOutgoing = CalendarAccessRequest(
            id: "stale-pending-outgoing",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            updatedAt: rangeStart,
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )
        let approvedOutgoing = CalendarAccessRequest(
            id: "approved-outgoing",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            updatedAt: rangeStart.addingTimeInterval(60),
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )

        XCTAssertEqual(
            CalendarAccessRequestListPlan.pendingIncoming(
                [stalePendingIncoming, approvedIncoming],
                currentMemberID: "_manuOwner"
            ).map(\.id),
            []
        )
        XCTAssertEqual(
            CalendarAccessRequestListPlan.outgoing(
                [stalePendingOutgoing, approvedOutgoing],
                currentMemberID: "xiaoyugan"
            ).map(\.id),
            ["approved-outgoing"]
        )
        XCTAssertEqual(
            CalendarAccessRequestCloudUploadPlan.requestsNeedingUpload(
                [stalePendingOutgoing, approvedOutgoing],
                currentMemberID: "xiaoyugan"
            ).map(\.id),
            []
        )
    }

    func testNewerPendingDuplicateIsNotSuppressedByOlderTerminalCopy() {
        let rangeStart = Date(timeIntervalSince1970: 10_000)
        let rangeEnd = rangeStart.addingTimeInterval(24 * 60 * 60)
        let olderDeclinedIncoming = CalendarAccessRequest(
            id: "older-declined-incoming",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.declined.rawValue,
            updatedAt: rangeStart,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let newerPendingIncoming = CalendarAccessRequest(
            id: "newer-pending-incoming",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            updatedAt: rangeStart.addingTimeInterval(60),
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let olderApprovedOutgoing = CalendarAccessRequest(
            id: "older-approved-outgoing",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            updatedAt: rangeStart,
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )
        let newerPendingOutgoing = CalendarAccessRequest(
            id: "newer-pending-outgoing",
            requesterMemberID: "xiaoyugan",
            ownerMemberID: "_manuOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeEnd,
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            updatedAt: rangeStart.addingTimeInterval(60),
            sourceRawValue: CalendarAccessRequestSource.localOutgoing.rawValue
        )

        XCTAssertEqual(
            CalendarAccessRequestListPlan.pendingIncoming(
                [olderDeclinedIncoming, newerPendingIncoming],
                currentMemberID: "_manuOwner"
            ).map(\.id),
            ["newer-pending-incoming"]
        )
        XCTAssertEqual(
            CalendarAccessRequestListPlan.outgoing(
                [olderApprovedOutgoing, newerPendingOutgoing],
                currentMemberID: "xiaoyugan"
            ).map(\.id),
            ["newer-pending-outgoing"]
        )
        XCTAssertEqual(
            CalendarAccessRequestCloudUploadPlan.requestsNeedingUpload(
                [olderApprovedOutgoing, newerPendingOutgoing],
                currentMemberID: "xiaoyugan"
            ).map(\.id),
            ["newer-pending-outgoing"]
        )
    }

    func testIncomingRequestsAreIdentifiedByPrivateOwnerZoneSource() {
        let rangeStart = Date(timeIntervalSince1970: 10_000)
        // The request lives in the recipient's own private zone, so it is incoming
        // regardless of the owner identifier the creator stamped (a hashed CloudKit ID
        // the recipient cannot express as its own local owner ID).
        let incoming = CalendarAccessRequest(
            id: "incoming",
            requesterMemberID: "partner",
            ownerMemberID: "_recipientHashedID",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        // A request mirrored from the partner's shared zone is outgoing, not incoming.
        let outgoing = CalendarAccessRequest(
            id: "outgoing",
            requesterMemberID: "_recipientLocalID",
            ownerMemberID: "_partnerHashedID",
            requestedStartDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            requestedEndDate: rangeStart.addingTimeInterval(2 * 24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.acceptedSharedZone.rawValue
        )

        XCTAssertEqual(
            CalendarAccessRequestListPlan.pendingIncoming(
                [incoming, outgoing],
                currentMemberID: "_recipientLocalID"
            ).map(\.id),
            ["incoming"]
        )
        XCTAssertEqual(
            PendingActionBadgePlan.count(
                invitations: [],
                accessRequests: [incoming, outgoing],
                currentMemberID: "_recipientLocalID"
            ),
            1
        )
    }
}

final class JointSchedulePlanTests: XCTestCase {
    func testAcceptedInvitationCreatesJointEventForBothMembers() {
        let invitation = EventInvitation(
            id: "invite-1",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: "Bistro",
            notes: "Window seat",
            statusRawValue: InvitationStatus.accepted.rawValue
        )

        let jointEvents = JointSchedulePlan.jointEvents(
            from: [invitation],
            currentMemberID: "me",
            partnerMemberID: "partner"
        )

        XCTAssertEqual(jointEvents.count, 1)
        XCTAssertEqual(jointEvents[0].id, "invite-1")
        XCTAssertEqual(jointEvents[0].title, "Dinner")
        XCTAssertEqual(jointEvents[0].calendarTitle, "ShareCal")
        XCTAssertEqual(jointEvents[0].startDate, Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(jointEvents[0].endDate, Date(timeIntervalSince1970: 12_000))
    }

    func testOrdinaryMirrorsMatchingAcceptedJointEventAreHiddenFromSplitColumns() {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = Date(timeIntervalSince1970: 12_000)
        let jointEvent = JointScheduleEvent(
            id: "invite-1",
            title: "Dinner",
            startDate: start,
            endDate: end,
            isAllDay: false,
            location: nil,
            notes: nil
        )
        let myCopy = eventMirror(id: "my-copy", ownerMemberID: "me", title: "Dinner", startDate: start, endDate: end)
        let partnerCopy = eventMirror(id: "partner-copy", ownerMemberID: "partner", title: "Dinner", startDate: start, endDate: end)
        let unrelated = eventMirror(
            id: "unrelated",
            ownerMemberID: "me",
            title: "Focus",
            startDate: Date(timeIntervalSince1970: 20_000),
            endDate: Date(timeIntervalSince1970: 21_000)
        )

        let ordinary = JointSchedulePlan.ordinaryMirrors(
            [myCopy, partnerCopy, unrelated],
            excluding: [jointEvent]
        )

        XCTAssertEqual(ordinary.map(\.id), ["unrelated"])
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: id
        )
    }
}

final class AcceptedInvitationMirrorPlanTests: XCTestCase {
    func testCreatesCurrentMemberShareCalMirrorForAcceptedInvitation() {
        let invitation = EventInvitation(
            id: "invite-1",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            isAllDay: false,
            location: "Bistro",
            notes: "Window seat",
            statusRawValue: InvitationStatus.accepted.rawValue
        )
        let createdEvent = CreatedCalendarEvent(
            eventIdentifier: "local-1",
            calendarIdentifier: "sharecal-calendar",
            calendarTitle: "ShareCal",
            calendarColorHex: "#FF2D55"
        )

        let mirror = AcceptedInvitationMirrorPlan.mirror(
            from: invitation,
            createdEvent: createdEvent,
            ownerMemberID: "partner",
            timeZoneIdentifier: "Asia/Singapore"
        )

        XCTAssertEqual(mirror.ownerMemberID, "partner")
        XCTAssertEqual(mirror.mirrorKey, "sharecal-calendar:local-1:10000")
        XCTAssertEqual(mirror.id, mirror.mirrorKey)
        XCTAssertEqual(mirror.sourceCalendarID, "sharecal-calendar")
        XCTAssertEqual(mirror.sourceCalendarTitle, "ShareCal")
        XCTAssertEqual(mirror.calendarColorHex, "#FF2D55")
        XCTAssertEqual(mirror.title, "Dinner")
        XCTAssertEqual(mirror.startDate, Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(mirror.endDate, Date(timeIntervalSince1970: 12_000))
        XCTAssertEqual(mirror.location, "Bistro")
        XCTAssertEqual(mirror.notes, "Window seat")
        XCTAssertEqual(mirror.visibility, .fullDetails)
        XCTAssertNil(mirror.deletedAt)
        XCTAssertEqual(mirror.cloudKitRecordName, mirror.mirrorKey)
    }
}

final class InvitationConflictPlanTests: XCTestCase {
    func testFindsOnlyOverlappingPartnerEvents() {
        let candidate = eventMirror(
            id: "candidate",
            ownerMemberID: "me",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000)
        )
        let partnerOverlap = eventMirror(
            id: "partner-overlap",
            ownerMemberID: "partner",
            title: "Gym",
            startDate: Date(timeIntervalSince1970: 11_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )
        let partnerBoundary = eventMirror(
            id: "partner-boundary",
            ownerMemberID: "partner",
            title: "No overlap",
            startDate: Date(timeIntervalSince1970: 12_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )
        let myOverlap = eventMirror(
            id: "my-overlap",
            ownerMemberID: "me",
            title: "Focus",
            startDate: Date(timeIntervalSince1970: 11_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )

        let conflicts = InvitationConflictPlan.conflicts(
            for: candidate,
            partnerMemberID: "partner",
            mirrors: [partnerOverlap, partnerBoundary, myOverlap]
        )

        XCTAssertEqual(conflicts.map(\.id), ["partner-overlap"])
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: id
        )
    }
}

final class InviteTimeAdjustmentPlanTests: XCTestCase {
    func testMovingStartSlidesEndByTheSameAmount() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(90 * 60) // custom 90-minute duration
        let newStart = start.addingTimeInterval(45 * 60)

        let newEnd = InviteTimeAdjustmentPlan.endDate(
            forNewStart: newStart,
            previousStart: start,
            previousEnd: end
        )

        XCTAssertEqual(newEnd, newStart.addingTimeInterval(90 * 60))
    }

    func testPreservesAtLeastOneHourWhenPriorDurationIsTooShort() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(10 * 60) // shorter than the 1h floor
        let newStart = start.addingTimeInterval(60 * 60)

        let newEnd = InviteTimeAdjustmentPlan.endDate(
            forNewStart: newStart,
            previousStart: start,
            previousEnd: end
        )

        XCTAssertEqual(newEnd, newStart.addingTimeInterval(60 * 60))
    }

    func testKeepsEndAfterStartWhenMovingStartBackward() {
        let start = Date(timeIntervalSince1970: 5_000)
        let end = start.addingTimeInterval(60 * 60)
        let newStart = start.addingTimeInterval(-30 * 60)

        let newEnd = InviteTimeAdjustmentPlan.endDate(
            forNewStart: newStart,
            previousStart: start,
            previousEnd: end
        )

        XCTAssertGreaterThan(newEnd, newStart)
        XCTAssertEqual(newEnd, newStart.addingTimeInterval(60 * 60))
    }
}

final class InvitationServiceTests: XCTestCase {
    func testAcceptPendingInvitationCreatesLocalCalendarDraftAndPreventsDuplicateAccept() throws {
        let invitation = EventInvitation(
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: "Bistro",
            notes: "Window seat",
            statusRawValue: InvitationStatus.pending.rawValue
        )
        let service = InvitationService()

        let draft = try service.accept(invitation, createdLocalEventID: "local-1")

        XCTAssertEqual(draft.title, "Dinner")
        XCTAssertEqual(draft.location, "Bistro")
        XCTAssertEqual(invitation.status, .accepted)
        XCTAssertEqual(invitation.createdLocalEventID, "local-1")
        XCTAssertThrowsError(try service.accept(invitation, createdLocalEventID: "local-2"))
    }

    func testOnlyInviteeCanRespondToPendingInvitation() {
        let invitation = EventInvitation(
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.pending.rawValue
        )

        XCTAssertTrue(InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: "partner"))
        XCTAssertFalse(InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: "me"))

        invitation.status = .accepted

        XCTAssertFalse(InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: "partner"))
    }

    func testCancelsAcceptedInvitationWhenCreatedLocalEventIsMissing() {
        let missingLocalEvent = EventInvitation(
            id: "missing",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.accepted.rawValue,
            createdLocalEventID: "local-missing"
        )
        let existingLocalEvent = EventInvitation(
            id: "existing",
            creatorMemberID: "partner",
            inviteeMemberID: "me",
            title: "Lunch",
            startDate: Date(timeIntervalSince1970: 13_000),
            endDate: Date(timeIntervalSince1970: 14_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.accepted.rawValue,
            createdLocalEventID: "local-existing"
        )
        let pending = EventInvitation(
            id: "pending",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Pending",
            startDate: Date(timeIntervalSince1970: 15_000),
            endDate: Date(timeIntervalSince1970: 16_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.pending.rawValue,
            createdLocalEventID: "local-pending"
        )

        let canceled = InvitationLocalEventSyncPlan.cancelAcceptedInvitationsMissingLocalEvents(
            [missingLocalEvent, existingLocalEvent, pending],
            existingLocalEventIDs: ["local-existing"],
            now: Date(timeIntervalSince1970: 20_000)
        )

        XCTAssertEqual(canceled.map(\.id), ["missing"])
        XCTAssertEqual(missingLocalEvent.status, .canceled)
        XCTAssertEqual(missingLocalEvent.updatedAt, Date(timeIntervalSince1970: 20_000))
        XCTAssertEqual(existingLocalEvent.status, .accepted)
        XCTAssertEqual(pending.status, .pending)
    }

    func testKeepsAcceptedInvitationWhenFallbackLocalEventMatcherFindsIt() {
        let invitation = EventInvitation(
            id: "accepted",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.accepted.rawValue,
            createdLocalEventID: "stale-local-id"
        )

        let canceled = InvitationLocalEventSyncPlan.cancelAcceptedInvitationsMissingLocalEvents(
            [invitation],
            now: Date(timeIntervalSince1970: 20_000),
            localEventExists: { candidate in
                candidate.title == "Dinner"
                    && candidate.startDate == Date(timeIntervalSince1970: 10_000)
                    && candidate.endDate == Date(timeIntervalSince1970: 12_000)
            }
        )

        XCTAssertTrue(canceled.isEmpty)
        XCTAssertEqual(invitation.status, .accepted)
    }
}

final class InvitationListPlanTests: XCTestCase {
    func testOnlyAcceptedInvitationsCanOpenInCalendar() {
        let accepted = invitation(id: "accepted", status: .accepted)
        let pending = invitation(id: "pending", status: .pending)
        let declined = invitation(id: "declined", status: .declined)

        XCTAssertTrue(InvitationListPlan.canOpenInCalendar(accepted))
        XCTAssertFalse(InvitationListPlan.canOpenInCalendar(pending))
        XCTAssertFalse(InvitationListPlan.canOpenInCalendar(declined))
    }

    func testAllVisibleInvitationsCanBeDeletedFromList() {
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "accepted", status: .accepted)))
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "declined", status: .declined)))
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "pending", status: .pending)))
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "canceled", status: .canceled)))
    }

    func testSortsInvitationsNearestToNowFirst() {
        let old = invitation(id: "old", status: .accepted, startDate: Date(timeIntervalSince1970: 10_000))
        let mid = invitation(id: "mid", status: .accepted, startDate: Date(timeIntervalSince1970: 20_000))
        let recent = invitation(id: "recent", status: .accepted, startDate: Date(timeIntervalSince1970: 30_000))

        let sorted = InvitationListPlan.sortedForDisplay([old, recent, mid])

        XCTAssertEqual(sorted.map(\.id), ["recent", "mid", "old"])
    }

    func testArchivedInvitationsAreHiddenFromInvitesList() {
        let visible = invitation(id: "visible", status: .accepted)
        let archived = invitation(
            id: "archived",
            status: .declined,
            archivedAt: Date(timeIntervalSince1970: 20_000)
        )

        let invitations = InvitationListPlan.visibleInvitations([visible, archived])

        XCTAssertEqual(invitations.map(\.id), ["visible"])
    }

    func testAcceptedInvitationBuildsCalendarFocusRequest() throws {
        let accepted = invitation(id: "accepted", status: .accepted)

        let request = try XCTUnwrap(CalendarFocusPlan.request(for: accepted))

        XCTAssertEqual(request.invitationID, "accepted")
        XCTAssertEqual(request.startDate, Date(timeIntervalSince1970: 10_000))
    }

    func testPendingActionBadgeCountsRespondableInvitationsAndIncomingHistoryRequests() {
        let pendingInvite = invitation(
            id: "pending-invite",
            status: .pending,
            creatorMemberID: "partner",
            inviteeMemberID: "me"
        )
        let ownPendingInvite = invitation(
            id: "own-pending-invite",
            status: .pending,
            creatorMemberID: "me",
            inviteeMemberID: "partner"
        )
        let rangeStart = Date(timeIntervalSince1970: 10_000)
        let incomingHistory = CalendarAccessRequest(
            id: "history",
            requesterMemberID: "partner",
            ownerMemberID: "me",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )
        let outgoingHistory = CalendarAccessRequest(
            id: "outgoing-history",
            requesterMemberID: "me",
            ownerMemberID: "_partnerOwner",
            requestedStartDate: rangeStart,
            requestedEndDate: rangeStart.addingTimeInterval(24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            sourceRawValue: CalendarAccessRequestSource.localOutgoing.rawValue
        )

        let count = PendingActionBadgePlan.count(
            invitations: [pendingInvite, ownPendingInvite],
            accessRequests: [incomingHistory, outgoingHistory],
            currentMemberID: "me"
        )

        XCTAssertEqual(count, 2)
    }

    private func invitation(
        id: String,
        status: InvitationStatus,
        creatorMemberID: String = "me",
        inviteeMemberID: String = "partner",
        startDate: Date = Date(timeIntervalSince1970: 10_000),
        archivedAt: Date? = nil
    ) -> EventInvitation {
        EventInvitation(
            id: id,
            creatorMemberID: creatorMemberID,
            inviteeMemberID: inviteeMemberID,
            title: "Dinner",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(2_000),
            location: nil,
            notes: nil,
            statusRawValue: status.rawValue,
            archivedAt: archivedAt
        )
    }
}

final class CreateInvitePlanTests: XCTestCase {
    func testBuildsFutureInviteArtifactsForShareCalCalendar() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let draft = CreateInviteDraft(
            title: "Weekend trip",
            startDate: start,
            endDate: start.addingTimeInterval(2 * 60 * 60),
            isAllDay: false,
            location: "Beach",
            notes: "Bring camera"
        )
        let createdEvent = CreatedCalendarEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "sharecal",
            calendarTitle: "ShareCal",
            calendarColorHex: "#FF2D55"
        )

        let localDraft = try CreateInvitePlan.localCalendarDraft(from: draft)
        let mirror = try CreateInvitePlan.mirror(
            from: draft,
            createdEvent: createdEvent,
            ownerMemberID: "me",
            timeZoneIdentifier: "Asia/Singapore"
        )
        let invitation = try CreateInvitePlan.invitation(
            from: draft,
            creatorMemberID: "me",
            inviteeMemberID: "partner"
        )

        XCTAssertEqual(localDraft.title, "Weekend trip")
        XCTAssertEqual(mirror.mirrorKey, "sharecal:event-1:20000")
        XCTAssertEqual(mirror.ownerMemberID, "me")
        XCTAssertEqual(invitation.status, .pending)
        XCTAssertEqual(invitation.title, "Weekend trip")
        XCTAssertEqual(invitation.location, "Beach")
    }

    func testRejectsEmptyTitleAndInvalidDateRange() {
        let start = Date(timeIntervalSince1970: 20_000)
        let emptyTitle = CreateInviteDraft(
            title: "  ",
            startDate: start,
            endDate: start.addingTimeInterval(60),
            isAllDay: false,
            location: nil,
            notes: nil
        )
        let invalidRange = CreateInviteDraft(
            title: "Weekend trip",
            startDate: start,
            endDate: start,
            isAllDay: false,
            location: nil,
            notes: nil
        )

        XCTAssertThrowsError(try CreateInvitePlan.localCalendarDraft(from: emptyTitle))
        XCTAssertThrowsError(try CreateInvitePlan.localCalendarDraft(from: invalidRange))
    }
}

final class CalendarAccessRequestImportMergePlanTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    func testPendingNeverRollsBackLocalApprovalEvenIfPendingTimestampIsNewer() {
        // Cross-device clock skew: the requester's still-`pending` copy carries a NEWER
        // updatedAt than the owner's approval. A purely timestamp-based guard would roll
        // the approval back; the status-aware rule must not.
        XCTAssertFalse(
            CalendarAccessRequestImportMergePlan.shouldApplyIncoming(
                existingStatus: .approved, existingUpdatedAt: older,
                incomingStatus: .pending, incomingUpdatedAt: newer
            )
        )
    }

    func testStalePendingDoesNotRollBackApproval() {
        // The common race: approval saved locally, upload not yet landed, sync re-reads
        // the older pending server copy.
        XCTAssertFalse(
            CalendarAccessRequestImportMergePlan.shouldApplyIncoming(
                existingStatus: .approved, existingUpdatedAt: newer,
                incomingStatus: .pending, incomingUpdatedAt: older
            )
        )
    }

    func testIncomingDecisionAlwaysWinsOverLocalPendingEvenIfOlder() {
        // The requester importing the owner's approval: it must land even if the owner's
        // clock is behind the requester's (decision wins over pending, ignoring clocks).
        XCTAssertTrue(
            CalendarAccessRequestImportMergePlan.shouldApplyIncoming(
                existingStatus: .pending, existingUpdatedAt: newer,
                incomingStatus: .approved, incomingUpdatedAt: older
            )
        )
    }

    func testSameTerminalityFallsBackToLastWriterWins() {
        // Both pending: newer applies, equal applies (idempotent), older skips.
        XCTAssertTrue(
            CalendarAccessRequestImportMergePlan.shouldApplyIncoming(
                existingStatus: .pending, existingUpdatedAt: older,
                incomingStatus: .pending, incomingUpdatedAt: newer
            )
        )
        XCTAssertTrue(
            CalendarAccessRequestImportMergePlan.shouldApplyIncoming(
                existingStatus: .pending, existingUpdatedAt: newer,
                incomingStatus: .pending, incomingUpdatedAt: newer
            )
        )
        // Both terminal: last-writer-wins by timestamp (owner's own sequential writes).
        XCTAssertFalse(
            CalendarAccessRequestImportMergePlan.shouldApplyIncoming(
                existingStatus: .approved, existingUpdatedAt: newer,
                incomingStatus: .declined, incomingUpdatedAt: older
            )
        )
    }
}

final class InvitationImportMergePlanTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    func testStalePendingDoesNotRollBackAcceptedInvitation() {
        // Invitee accepted locally; a concurrent sync re-reads the still-pending server
        // copy before the accept upload lands — must not flip the invite back to pending.
        XCTAssertFalse(
            InvitationImportMergePlan.shouldApplyIncoming(
                existingStatus: .accepted, existingUpdatedAt: older,
                incomingStatus: .pending, incomingUpdatedAt: newer
            )
        )
    }

    func testIncomingDecisionAppliesOverLocalPending() {
        // The creator receiving the invitee's accept must land it over local pending,
        // regardless of clock skew.
        XCTAssertTrue(
            InvitationImportMergePlan.shouldApplyIncoming(
                existingStatus: .pending, existingUpdatedAt: newer,
                incomingStatus: .accepted, incomingUpdatedAt: older
            )
        )
    }

    func testCanceledIsTerminalAndNotRolledBackByPending() {
        XCTAssertFalse(
            InvitationImportMergePlan.shouldApplyIncoming(
                existingStatus: .canceled, existingUpdatedAt: older,
                incomingStatus: .pending, incomingUpdatedAt: newer
            )
        )
    }
}

final class StatusReuploadPlanTests: XCTestCase {
    private let me = "me"
    private let partner = "you"

    func testReuploadsOwnerApprovalWhenServerStillPending() {
        // Owner approved locally; the server copy is still pending (one-shot upload
        // failed). Must be returned for re-upload so it self-heals.
        let local = [request(id: "r1", owner: me, status: .approved, source: .privateOwnerZone)]
        let cloud = [request(id: "r1", owner: me, status: .pending, source: .privateOwnerZone)]
        let result = CalendarAccessRequestReuploadPlan.ownerDecisionsNeedingReupload(
            local: local, cloud: cloud, currentMemberID: me
        )
        XCTAssertEqual(result.map(\.id), ["r1"])
    }

    func testReuploadsOwnerApprovalWhenMissingFromServer() {
        let local = [request(id: "r1", owner: me, status: .approved, source: .privateOwnerZone)]
        let result = CalendarAccessRequestReuploadPlan.ownerDecisionsNeedingReupload(
            local: local, cloud: [], currentMemberID: me
        )
        XCTAssertEqual(result.map(\.id), ["r1"])
    }

    func testDoesNotReuploadWhenServerAgrees() {
        // Self-limiting: once the server has the decision, nothing is re-uploaded.
        let local = [request(id: "r1", owner: me, status: .approved, source: .privateOwnerZone)]
        let cloud = [request(id: "r1", owner: me, status: .approved, source: .privateOwnerZone)]
        XCTAssertTrue(
            CalendarAccessRequestReuploadPlan.ownerDecisionsNeedingReupload(
                local: local, cloud: cloud, currentMemberID: me
            ).isEmpty
        )
    }

    func testIgnoresPendingAndNonOwnerAndOutgoingRequests() {
        let local = [
            request(id: "pending", owner: me, status: .pending, source: .privateOwnerZone),
            request(id: "notMine", owner: partner, status: .approved, source: .privateOwnerZone),
            request(id: "outgoing", owner: me, status: .approved, source: .acceptedSharedZone),
        ]
        XCTAssertTrue(
            CalendarAccessRequestReuploadPlan.ownerDecisionsNeedingReupload(
                local: local, cloud: [], currentMemberID: me
            ).isEmpty
        )
    }

    func testReuploadsMyResponseWhenServerStillPending() {
        // Partner created the invitation (I'm the invitee = not the creator); I accepted
        // locally but the partner's zone copy is still pending. inviteeMemberID is the
        // partner's hashed id (NOT my member ID), so identity keys off the creator.
        let local = [invite(id: "i1", creator: partner, status: .accepted)]
        let cloud = [invite(id: "i1", creator: partner, status: .pending)]
        XCTAssertEqual(
            InvitationReuploadPlan.responsesNeedingReupload(
                local: local, cloud: cloud, currentMemberID: me
            ).map(\.id),
            ["i1"]
        )
    }

    func testDoesNotReuploadOverDifferentTerminalCloudDecision() {
        // The creator legitimately canceled (terminal) while my local is accepted.
        // Re-pushing accepted would clobber a real decision — the import merge resolves
        // this conflict, not the reupload. Only a still-pending server copy may be healed.
        let local = [invite(id: "i1", creator: partner, status: .accepted)]
        let cloud = [invite(id: "i1", creator: partner, status: .canceled)]
        XCTAssertTrue(
            InvitationReuploadPlan.responsesNeedingReupload(
                local: local, cloud: cloud, currentMemberID: me
            ).isEmpty
        )
    }

    func testDoesNotReuploadWhenServerAgreesOrIAmTheCreator() {
        let local = [
            invite(id: "agreed", creator: partner, status: .accepted),
            invite(id: "mine", creator: me, status: .accepted), // I created it — not my response
            invite(id: "pending", creator: partner, status: .pending),
        ]
        let cloud = [
            invite(id: "agreed", creator: partner, status: .accepted),
            invite(id: "mine", creator: me, status: .pending),
        ]
        XCTAssertTrue(
            InvitationReuploadPlan.responsesNeedingReupload(
                local: local, cloud: cloud, currentMemberID: me
            ).isEmpty
        )
    }

    func testReuploadsMyCreationStillOwingAnUpload() {
        // req2 optimistic send: I created an invitation whose background upload never
        // landed (needsCloudKitUpload still set). It lives in my private zone, never read
        // back, so the flag — not a cloud diff — is what queues it for self-heal.
        let local = [
            creation(id: "owed", creator: me, needsUpload: true),
            creation(id: "done", creator: me, needsUpload: false),
            creation(id: "partners", creator: partner, needsUpload: true), // not mine
        ]
        XCTAssertEqual(
            InvitationReuploadPlan.creationsNeedingReupload(local: local, currentMemberID: me).map(\.id),
            ["owed"]
        )
    }

    func testNoCreationReuploadWhenNothingOwesAnUpload() {
        let local = [creation(id: "done", creator: me, needsUpload: false)]
        XCTAssertTrue(
            InvitationReuploadPlan.creationsNeedingReupload(local: local, currentMemberID: me).isEmpty
        )
    }

    private func creation(id: String, creator: String, needsUpload: Bool) -> EventInvitation {
        EventInvitation(
            id: id,
            creatorMemberID: creator,
            inviteeMemberID: "hashed-invitee-id",
            title: "Event",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.pending.rawValue,
            needsCloudKitUpload: needsUpload
        )
    }

    private func request(
        id: String, owner: String, status: CalendarAccessRequestStatus, source: CalendarAccessRequestSource
    ) -> CalendarAccessRequest {
        CalendarAccessRequest(
            id: id,
            requesterMemberID: partner,
            ownerMemberID: owner,
            requestedStartDate: Date(timeIntervalSince1970: 0),
            requestedEndDate: Date(timeIntervalSince1970: 60),
            statusRawValue: status.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1),
            sourceRawValue: source.rawValue
        )
    }

    private func invite(id: String, creator: String, status: InvitationStatus) -> EventInvitation {
        EventInvitation(
            id: id,
            creatorMemberID: creator,
            // The stamped invitee id is the partner's hashed CloudKit id and never equals
            // the recipient's own member id — identity must key off the creator instead.
            inviteeMemberID: "hashed-invitee-id",
            title: "Event",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            location: nil,
            notes: nil,
            statusRawValue: status.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1),
            archivedAt: nil
        )
    }
}
