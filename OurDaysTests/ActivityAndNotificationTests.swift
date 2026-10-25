import XCTest

final class ActivityFeedPolicyTests: XCTestCase {
    private let me = "me"
    private let partner = "you"

    func testGroupsCommentsByEventSortedByLatestCommentDescending() {
        let mirrors = [mirror(id: "A", title: "Dinner"), mirror(id: "B", title: "Movie")]
        let comments = [
            comment(event: "A", author: me, body: "see you", at: 100),
            comment(event: "A", author: partner, body: "running late", at: 300),
            comment(event: "B", author: partner, body: "tonight?", at: 200),
        ]

        let items = ActivityFeedPolicy.items(
            comments: comments,
            mirrors: mirrors,
            invitations: [],
            currentMemberID: me,
            lastSeenActivityAt: nil
        )

        XCTAssertEqual(items.map(\.eventMirrorID), ["A", "B"])
        XCTAssertEqual(items[0].eventTitle, "Dinner")
        XCTAssertEqual(items[0].commentCount, 2)
        XCTAssertEqual(items[0].latestCommentBody, "running late")
        XCTAssertEqual(items[0].latestCommentAuthorMemberID, partner)
        XCTAssertEqual(items[1].eventMirrorID, "B")
    }

    func testUnreadCountsPartnerCommentsNewerThanLastSeen() {
        let comments = [
            comment(event: "A", author: partner, body: "old", at: 100),
            comment(event: "A", author: partner, body: "new", at: 200),
            comment(event: "A", author: me, body: "mine", at: 300),
        ]

        let count = ActivityFeedPolicy.unreadCount(
            comments: comments,
            mirrors: [mirror(id: "A", title: "Dinner")],
            invitations: [],
            currentMemberID: me,
            lastSeenActivityAt: Date(timeIntervalSince1970: 150)
        )

        XCTAssertEqual(count, 1)
    }

    func testNilLastSeenTreatsAllPartnerCommentsAsUnread() {
        let comments = [
            comment(event: "A", author: partner, body: "a", at: 100),
            comment(event: "A", author: partner, body: "b", at: 200),
            comment(event: "A", author: me, body: "mine", at: 300),
        ]

        let count = ActivityFeedPolicy.unreadCount(
            comments: comments,
            mirrors: [mirror(id: "A", title: "Dinner")],
            invitations: [],
            currentMemberID: me,
            lastSeenActivityAt: nil
        )

        XCTAssertEqual(count, 2)
    }

    func testOwnCommentsAreNeverUnread() {
        let comments = [
            comment(event: "A", author: me, body: "a", at: 100),
            comment(event: "A", author: me, body: "b", at: 200),
        ]

        let count = ActivityFeedPolicy.unreadCount(
            comments: comments,
            mirrors: [mirror(id: "A", title: "Dinner")],
            invitations: [],
            currentMemberID: me,
            lastSeenActivityAt: nil
        )

        XCTAssertEqual(count, 0)
    }

    func testIgnoresDeletedComments() {
        let mirrors = [mirror(id: "A", title: "Dinner")]
        let comments = [
            comment(event: "A", author: partner, body: "kept", at: 200),
            comment(event: "A", author: partner, body: "gone", at: 300, deletedAt: 350),
        ]

        let items = ActivityFeedPolicy.items(
            comments: comments,
            mirrors: mirrors,
            invitations: [],
            currentMemberID: me,
            lastSeenActivityAt: nil
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].commentCount, 1)
        XCTAssertEqual(items[0].latestCommentBody, "kept")
        XCTAssertEqual(items[0].unreadCount, 1)
    }

    func testSkipsCommentsWithoutMatchingMirrorOrInvitation() {
        let mirrors = [mirror(id: "A", title: "Dinner")]
        let comments = [
            comment(event: "A", author: partner, body: "real", at: 100),
            comment(event: "ghost", author: partner, body: "orphan", at: 200),
        ]

        let items = ActivityFeedPolicy.items(
            comments: comments,
            mirrors: mirrors,
            invitations: [],
            currentMemberID: me,
            lastSeenActivityAt: nil
        )

        XCTAssertEqual(items.map(\.eventMirrorID), ["A"])
    }

    func testSurfacesJointEventCommentsViaInvitationAndCountsThemUnread() {
        // Joint-event comments are anchored to the invitation id (EventCommentAnchorPolicy),
        // which has no EventMirror. They must still show in the feed (titled by the
        // invitation) AND count toward unread — otherwise the badge points at an invisible row.
        let invitations = [invitation(id: "inv-1", title: "Joint Dinner")]
        let comments = [
            comment(event: "inv-1", author: partner, body: "see you at the joint event", at: 500),
        ]

        let items = ActivityFeedPolicy.items(
            comments: comments,
            mirrors: [],
            invitations: invitations,
            currentMemberID: me,
            lastSeenActivityAt: nil
        )
        XCTAssertEqual(items.map(\.eventMirrorID), ["inv-1"])
        XCTAssertEqual(items[0].eventTitle, "Joint Dinner")
        XCTAssertEqual(items[0].unreadCount, 1)

        let count = ActivityFeedPolicy.unreadCount(
            comments: comments,
            mirrors: [],
            invitations: invitations,
            currentMemberID: me,
            lastSeenActivityAt: nil
        )
        XCTAssertEqual(count, 1)
    }

    func testUnreadCountIgnoresUndisplayableOrphanComments() {
        // A comment whose anchor resolves to neither a mirror nor an invitation can't be
        // shown, so it must not inflate the badge (the bug this guards against).
        let comments = [comment(event: "ghost", author: partner, body: "orphan", at: 100)]

        let count = ActivityFeedPolicy.unreadCount(
            comments: comments,
            mirrors: [],
            invitations: [],
            currentMemberID: me,
            lastSeenActivityAt: nil
        )

        XCTAssertEqual(count, 0)
    }

    private func invitation(id: String, title: String) -> EventInvitation {
        EventInvitation(
            id: id,
            creatorMemberID: me,
            inviteeMemberID: partner,
            title: title,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.accepted.rawValue
        )
    }

    private func comment(
        event: String,
        author: String,
        body: String,
        at seconds: TimeInterval,
        deletedAt: TimeInterval? = nil
    ) -> EventComment {
        EventComment(
            eventMirrorID: event,
            authorMemberID: author,
            body: body,
            createdAt: Date(timeIntervalSince1970: seconds),
            deletedAt: deletedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func mirror(id: String, title: String) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: "owner",
            mirrorKey: id,
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
            cloudKitRecordName: id
        )
    }
}

final class LocalNotificationPolicyTests: XCTestCase {
    private let me = "me"
    private let partner = "you"
    private let since = Date(timeIntervalSince1970: 1_000)

    func testReturnsEmptyWithoutBaseline() {
        let planned = LocalNotificationPolicy.pending(
            comments: [comment(event: "M1", author: partner, body: "hi", at: 2_000)],
            mirrors: [mirror(id: "M1", owner: me)],
            invitations: [],
            accessRequests: [],
            currentMemberID: me,
            since: nil
        )

        XCTAssertTrue(planned.isEmpty)
    }

    func testNotifiesOnlyPartnerCommentsOnMyEvents() {
        let mirrors = [mirror(id: "M1", owner: me, title: "Dinner"), mirror(id: "P1", owner: partner)]
        let comments = [
            comment(event: "M1", author: partner, body: "late", at: 2_000),
            comment(event: "M1", author: me, body: "ok", at: 2_100),
            comment(event: "P1", author: partner, body: "mine", at: 2_200),
            comment(event: "M1", author: partner, body: "old", at: 500),
        ]

        let planned = LocalNotificationPolicy.pending(
            comments: comments,
            mirrors: mirrors,
            invitations: [],
            accessRequests: [],
            currentMemberID: me,
            since: since
        )

        XCTAssertEqual(planned.map(\.kind), [.partnerCommentedOnMyEvent(eventTitle: "Dinner", commentBody: "late")])
    }

    func testNotifiesNewInvitationsToMe() {
        let invitations = [
            invitation(creator: partner, invitee: me, title: "Trip", status: .pending, createdAt: 2_000, updatedAt: 2_000),
            invitation(creator: me, invitee: partner, title: "Mine", status: .pending, createdAt: 2_000, updatedAt: 2_000),
            invitation(creator: partner, invitee: me, title: "Archived", status: .pending, createdAt: 2_000, updatedAt: 2_000, archivedAt: 2_050),
            invitation(creator: partner, invitee: me, title: "Old", status: .pending, createdAt: 500, updatedAt: 500),
        ]

        let planned = LocalNotificationPolicy.pending(
            comments: [], mirrors: [], invitations: invitations, accessRequests: [],
            currentMemberID: me, since: since
        )

        XCTAssertEqual(planned.map(\.kind), [.invitationReceived(title: "Trip")])
    }

    func testNotifiesMyInvitationAcceptedOrDeclinedButNotPendingOrCanceled() {
        let invitations = [
            invitation(creator: me, invitee: partner, title: "Yes", status: .accepted, createdAt: 100, updatedAt: 2_000),
            invitation(creator: me, invitee: partner, title: "No", status: .declined, createdAt: 100, updatedAt: 2_100),
            invitation(creator: me, invitee: partner, title: "Waiting", status: .pending, createdAt: 100, updatedAt: 2_200),
            invitation(creator: me, invitee: partner, title: "Gone", status: .canceled, createdAt: 100, updatedAt: 2_300),
            invitation(creator: me, invitee: partner, title: "Stale", status: .accepted, createdAt: 100, updatedAt: 500),
        ]

        let planned = LocalNotificationPolicy.pending(
            comments: [], mirrors: [], invitations: invitations, accessRequests: [],
            currentMemberID: me, since: since
        )

        XCTAssertEqual(planned.map(\.kind), [
            .invitationAccepted(title: "Yes"),
            .invitationDeclined(title: "No"),
        ])
    }

    func testNotifiesIncomingAccessRequestsAndAnsweredOutgoing() {
        let requests = [
            // Incoming request from the partner lands in my zone (privateOwnerZone).
            accessRequest(requester: partner, owner: me, status: .pending, source: .privateOwnerZone, createdAt: 2_000, updatedAt: 2_000),
            // The partner's reply to MY request comes back via the accepted shared zone.
            accessRequest(requester: me, owner: partner, status: .approved, source: .acceptedSharedZone, createdAt: 100, updatedAt: 2_100),
            accessRequest(requester: me, owner: partner, status: .declined, source: .acceptedSharedZone, createdAt: 100, updatedAt: 2_200),
            // Older incoming request before the cursor — ignored.
            accessRequest(requester: partner, owner: me, status: .pending, source: .privateOwnerZone, createdAt: 500, updatedAt: 500),
            // My freshly-sent outgoing request (still pending, local copy) — not a reply.
            accessRequest(requester: me, owner: partner, status: .pending, source: .localOutgoing, createdAt: 100, updatedAt: 2_050),
        ]

        let planned = LocalNotificationPolicy.pending(
            comments: [], mirrors: [], invitations: [], accessRequests: requests,
            currentMemberID: me, since: since
        )

        XCTAssertEqual(planned.map(\.kind), [
            .accessRequestReceived,
            .accessRequestAnswered(approved: true),
            .accessRequestAnswered(approved: false),
        ])
    }

    func testProducesStableDedupeIDs() {
        let c = comment(event: "M1", author: partner, body: "late", at: 2_000)
        let planned = LocalNotificationPolicy.pending(
            comments: [c],
            mirrors: [mirror(id: "M1", owner: me)],
            invitations: [],
            accessRequests: [],
            currentMemberID: me,
            since: since
        )

        XCTAssertEqual(planned.map(\.id), ["comment-\(c.id)"])
    }

    func testEventOnlyChangesProduceNoNotifications() {
        // Decision 0002 (silent-push model): a sync whose only changes are the
        // partner's calendar events (EventMirror) must produce zero user-facing
        // notifications. This is the invariant that keeps switching the CloudKit
        // push to silent from resurrecting the phantom "动态" notifications — the
        // shared-DB subscription fires on every mirror write, but nothing about a
        // calendar-event change is notification-worthy on its own.
        let planned = LocalNotificationPolicy.pending(
            comments: [],
            mirrors: [
                mirror(id: "P1", owner: partner, title: "New partner event"),
                mirror(id: "P2", owner: partner, title: "Edited partner event"),
                mirror(id: "M1", owner: me, title: "My event"),
            ],
            invitations: [],
            accessRequests: [],
            currentMemberID: me,
            since: since
        )

        XCTAssertTrue(planned.isEmpty)
    }

    private func comment(event: String, author: String, body: String, at seconds: TimeInterval) -> EventComment {
        EventComment(
            eventMirrorID: event,
            authorMemberID: author,
            body: body,
            createdAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func mirror(id: String, owner: String, title: String = "Event") -> EventMirror {
        EventMirror(
            id: id, ownerMemberID: owner, mirrorKey: id,
            sourceCalendarID: "calendar", sourceCalendarTitle: "Calendar",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_000),
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false, timeZoneIdentifier: "Asia/Singapore",
            title: title, location: nil, notes: nil, urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil, cloudKitRecordName: id
        )
    }

    private func invitation(
        id: String = UUID().uuidString,
        creator: String,
        invitee: String,
        title: String,
        status: InvitationStatus,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        archivedAt: TimeInterval? = nil
    ) -> EventInvitation {
        EventInvitation(
            id: id,
            creatorMemberID: creator,
            inviteeMemberID: invitee,
            title: title,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60),
            location: nil,
            notes: nil,
            statusRawValue: status.rawValue,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            archivedAt: archivedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func accessRequest(
        id: String = UUID().uuidString,
        requester: String,
        owner: String,
        status: CalendarAccessRequestStatus,
        source: CalendarAccessRequestSource,
        createdAt: TimeInterval,
        updatedAt: TimeInterval
    ) -> CalendarAccessRequest {
        CalendarAccessRequest(
            id: id,
            requesterMemberID: requester,
            ownerMemberID: owner,
            requestedStartDate: Date(timeIntervalSince1970: 0),
            requestedEndDate: Date(timeIntervalSince1970: 60),
            statusRawValue: status.rawValue,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            sourceRawValue: source.rawValue
        )
    }
}

final class LocalNotificationContentPolicyTests: XCTestCase {
    private let strings = ShareCalStrings(language: .english)

    func testCommentContentIncludesEventTitleAndCommentBody() {
        let content = LocalNotificationContentPolicy.content(
            for: .partnerCommentedOnMyEvent(eventTitle: "Dinner", commentBody: "running late"),
            strings: strings,
            partnerName: "Yoki"
        )

        XCTAssertFalse(content.title.isEmpty)
        XCTAssertTrue(content.body.contains("Dinner"))
        XCTAssertTrue(content.body.contains("running late"))
    }

    func testInvitationReceivedContentUsesInviteTitle() {
        let content = LocalNotificationContentPolicy.content(
            for: .invitationReceived(title: "Weekend Trip"),
            strings: strings,
            partnerName: "Yoki"
        )

        XCTAssertFalse(content.title.isEmpty)
        XCTAssertTrue(content.body.contains("Weekend Trip"))
    }

    func testAccessRequestApprovedAndDeclinedDiffer() {
        let approved = LocalNotificationContentPolicy.content(
            for: .accessRequestAnswered(approved: true),
            strings: strings,
            partnerName: "Yoki"
        )
        let declined = LocalNotificationContentPolicy.content(
            for: .accessRequestAnswered(approved: false),
            strings: strings,
            partnerName: "Yoki"
        )

        XCTAssertNotEqual(approved.title, declined.title)
        XCTAssertFalse(approved.title.isEmpty)
        XCTAssertFalse(declined.title.isEmpty)
    }
}

final class AppIconBadgePolicyTests: XCTestCase {
    func testSumsUnreadActivityAndPendingActions() {
        XCTAssertEqual(
            AppIconBadgePolicy.badgeCount(unreadActivityCount: 2, pendingInviteCount: 3), 5
        )
    }

    func testZeroWhenNothingOutstandingClearsTheBadge() {
        XCTAssertEqual(
            AppIconBadgePolicy.badgeCount(unreadActivityCount: 0, pendingInviteCount: 0), 0
        )
    }

    func testNeverNegative() {
        XCTAssertEqual(
            AppIconBadgePolicy.badgeCount(unreadActivityCount: -1, pendingInviteCount: 0), 0
        )
    }
}
