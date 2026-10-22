import XCTest

final class EventCommentAnchorPlanTests: XCTestCase {
    func testInvitationAnchorUsesInvitationIdAndCreatorForSymmetricRouting() {
        let invitation = EventInvitation(
            id: "invite-1",
            creatorMemberID: "_creator",
            inviteeMemberID: "hashed-invitee",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            location: nil,
            notes: nil
        )

        let anchor = EventCommentAnchorPlan.anchor(forInvitation: invitation)
        // Both partners key the thread off the shared invitation id.
        XCTAssertEqual(anchor.key, "invite-1")
        XCTAssertEqual(anchor.recordName, "invite-1")
        XCTAssertEqual(anchor.ownerMemberID, "_creator")

        // The creator's comment lands in their private zone; the partner's lands in the
        // creator's shared zone. Both devices read both zones back, so the thread is shared.
        XCTAssertEqual(
            CloudKitCommentWritePlan.destination(eventOwnerMemberID: anchor.ownerMemberID, currentMemberID: "_creator"),
            .privateOwnerZone
        )
        XCTAssertEqual(
            CloudKitCommentWritePlan.destination(eventOwnerMemberID: anchor.ownerMemberID, currentMemberID: "_partner"),
            .acceptedSharedZone
        )
    }
}

final class EventCommentIndicatorPlanTests: XCTestCase {
    func testCommentedAnchorKeysCollectsLiveCommentKeysIgnoringDeleted() {
        let comments = [
            comment(event: "real-1", at: 1),
            comment(event: "real-1", at: 2),
            comment(event: "invite-9", at: 3),
            comment(event: "gone", at: 4, deletedAt: 5),
        ]

        let keys = EventCommentIndicatorPlan.commentedAnchorKeys(comments)

        XCTAssertEqual(keys, ["real-1", "invite-9"])
    }

    func testPartnerRealMirrorWithCommentsShowsIndicator() {
        let partnerMirror = mirror(id: "real-1", mirrorKey: "key-1")

        XCTAssertTrue(
            EventCommentIndicatorPlan.hasComments(
                mirror: partnerMirror,
                commentedKeys: ["real-1"],
                persistedIDByMirrorKey: ["key-1": "real-1"]
            )
        )
    }

    func testMyDisplayMirrorResolvesToPersistedTwinForIndicator() {
        // My own calendar event is a transient "display:" mirror; the partner's comment is
        // keyed to the persisted twin's real id. Resolve via the shared mirrorKey.
        let displayMirror = mirror(id: "display:key-1", mirrorKey: "key-1", recordName: nil)

        XCTAssertTrue(
            EventCommentIndicatorPlan.hasComments(
                mirror: displayMirror,
                commentedKeys: ["real-1"],
                persistedIDByMirrorKey: ["key-1": "real-1"]
            )
        )
    }

    func testDisplayMirrorWithoutPersistedTwinHasNoIndicator() {
        let displayMirror = mirror(id: "display:key-2", mirrorKey: "key-2", recordName: nil)

        XCTAssertFalse(
            EventCommentIndicatorPlan.hasComments(
                mirror: displayMirror,
                commentedKeys: ["real-1"],
                persistedIDByMirrorKey: ["key-1": "real-1"]
            )
        )
    }

    func testMirrorWithoutCommentsHasNoIndicator() {
        let partnerMirror = mirror(id: "real-3", mirrorKey: "key-3")

        XCTAssertFalse(
            EventCommentIndicatorPlan.hasComments(
                mirror: partnerMirror,
                commentedKeys: ["real-1"],
                persistedIDByMirrorKey: ["key-3": "real-3"]
            )
        )
    }

    func testJointEventIndicatorKeysOffInvitationId() {
        let jointEvent = JointScheduleEvent(
            id: "invite-9",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            isAllDay: false,
            location: nil,
            notes: nil
        )

        XCTAssertTrue(EventCommentIndicatorPlan.hasComments(jointEvent: jointEvent, commentedKeys: ["invite-9"]))
        XCTAssertFalse(EventCommentIndicatorPlan.hasComments(jointEvent: jointEvent, commentedKeys: ["other"]))
    }

    private func comment(event: String, at seconds: TimeInterval, deletedAt: TimeInterval? = nil) -> EventComment {
        EventComment(
            eventMirrorID: event,
            authorMemberID: "author",
            body: "body",
            createdAt: Date(timeIntervalSince1970: seconds),
            deletedAt: deletedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func mirror(
        id: String,
        mirrorKey: String,
        ownerMemberID: String = "owner",
        recordName: String? = nil
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
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

final class CloudKitCommentWritePlanTests: XCTestCase {
    func testWritesOwnEventCommentsToPrivateOwnerZone() {
        XCTAssertEqual(
            CloudKitCommentWritePlan.destination(eventOwnerMemberID: "me", currentMemberID: "me"),
            .privateOwnerZone
        )
    }

    func testWritesPartnerEventCommentsToAcceptedSharedZone() {
        XCTAssertEqual(
            CloudKitCommentWritePlan.destination(eventOwnerMemberID: "partner", currentMemberID: "me"),
            .acceptedSharedZone
        )
    }
}

final class CommentServiceTests: XCTestCase {
    func testCommentLifecycleCreateEditDeleteAndMarkRead() {
        let service = CommentService(now: { Date(timeIntervalSince1970: 100) })
        let comment = service.createComment(
            eventMirrorID: "mirror-1",
            authorMemberID: "me",
            body: "See you there"
        )

        XCTAssertEqual(comment.body, "See you there")
        XCTAssertFalse(comment.isRead)

        service.edit(comment, body: "See you at 6")
        XCTAssertEqual(comment.body, "See you at 6")
        XCTAssertNotNil(comment.editedAt)

        service.markRead(comment)
        XCTAssertTrue(comment.isRead)

        service.delete(comment)
        XCTAssertNotNil(comment.deletedAt)
    }
}
