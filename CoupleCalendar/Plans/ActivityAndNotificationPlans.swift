import Foundation

struct ActivityFeedSection: Identifiable, Equatable {
    let dayStart: Date
    let items: [ActivityFeedItem]

    var id: Date { dayStart }
}

/// Groups the activity feed by the calendar day of each thread's latest comment,
/// keeping the feed's newest-first order inside and across sections.
enum ActivityFeedSectionPlan {
    static func sections(_ items: [ActivityFeedItem], calendar: Calendar = .current) -> [ActivityFeedSection] {
        var sections: [ActivityFeedSection] = []
        for item in items.sorted(by: { $0.latestCommentAt > $1.latestCommentAt }) {
            let dayStart = calendar.startOfDay(for: item.latestCommentAt)
            if let last = sections.last, last.dayStart == dayStart {
                sections[sections.count - 1] = ActivityFeedSection(dayStart: dayStart, items: last.items + [item])
            } else {
                sections.append(ActivityFeedSection(dayStart: dayStart, items: [item]))
            }
        }
        return sections
    }
}

/// The springboard app-icon badge number = unread activity + pending actions. Kept in
/// sync on scene-active and whenever the counts change, so viewing activity / acting on
/// invites drives it to zero. Nothing else sets the icon badge once the silent-push
/// migration (notifications decision 0002) removed the subscription's `shouldBadge`, so
/// this is also what clears a badge orphaned by a pre-migration visible push.
enum AppIconBadgePlan {
    static func badgeCount(unreadActivityCount: Int, pendingInviteCount: Int) -> Int {
        max(0, unreadActivityCount + pendingInviteCount)
    }
}

enum PendingActionBadgePlan {
    static func count(
        invitations: [EventInvitation],
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> Int {
        let invitationCount = invitations.filter {
            InvitationInteractionPlan.canRespond(to: $0, currentMemberID: currentMemberID)
                && $0.archivedAt == nil
        }.count
        return invitationCount + CalendarAccessRequestListPlan.pendingIncoming(
            accessRequests,
            currentMemberID: currentMemberID
        ).count
    }
}

/// One row in the "动态" (activity) feed: an event that has comment activity,
/// summarized by its latest comment and how many partner comments are unread.
struct ActivityFeedItem: Identifiable, Equatable {
    let eventMirrorID: String
    let eventTitle: String
    let latestCommentAt: Date
    let latestCommentBody: String
    let latestCommentAuthorMemberID: String
    let commentCount: Int
    let unreadCount: Int

    var id: String { eventMirrorID }
    var hasUnread: Bool { unreadCount > 0 }
}

/// Pure aggregation for the activity feed. Groups non-deleted comments by event
/// (newest-comment-first), and counts unread as partner-authored comments newer
/// than the local `lastSeenActivityAt`. Deliberately does NOT use `EventComment.isRead`
/// (that field is synced/shared with the partner) — see plan-tree decision 0002.
enum ActivityFeedPlan {
    static func items(
        comments: [EventComment],
        mirrors: [EventMirror],
        invitations: [EventInvitation],
        currentMemberID: String,
        lastSeenActivityAt: Date?
    ) -> [ActivityFeedItem] {
        let mirrorsByID = Dictionary(
            mirrors.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let invitationsByID = Dictionary(
            invitations.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let liveComments = comments.filter { $0.deletedAt == nil }
        let grouped = Dictionary(grouping: liveComments, by: { $0.eventMirrorID })

        var result: [ActivityFeedItem] = []
        for (eventMirrorID, group) in grouped {
            // Resolve the thread's title from a mirror OR, for joint-event comments
            // (anchored to the invitation id, see EventCommentAnchorPlan), the invitation.
            // Without the invitation fallback joint comments would silently vanish from the
            // feed while still bumping the unread badge — surface them instead.
            guard let title = threadTitle(
                forAnchor: eventMirrorID,
                mirrorsByID: mirrorsByID,
                invitationsByID: invitationsByID
            ) else { continue }
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            guard let latest = sorted.last else { continue }
            let unread = group.filter {
                isUnread($0, currentMemberID: currentMemberID, lastSeenActivityAt: lastSeenActivityAt)
            }.count
            result.append(
                ActivityFeedItem(
                    eventMirrorID: eventMirrorID,
                    eventTitle: title,
                    latestCommentAt: latest.createdAt,
                    latestCommentBody: latest.body,
                    latestCommentAuthorMemberID: latest.authorMemberID,
                    commentCount: group.count,
                    unreadCount: unread
                )
            )
        }
        return result.sorted { $0.latestCommentAt > $1.latestCommentAt }
    }

    /// Unread badge count. Mirrors `items`' resolvability rule: only count comments the
    /// feed can actually surface (backed by a mirror or a joint invitation), so the badge
    /// never points at activity the Activity tab can't display.
    static func unreadCount(
        comments: [EventComment],
        mirrors: [EventMirror],
        invitations: [EventInvitation],
        currentMemberID: String,
        lastSeenActivityAt: Date?
    ) -> Int {
        let displayableAnchors = Set(mirrors.map(\.id)).union(invitations.map(\.id))
        return comments.filter {
            displayableAnchors.contains($0.eventMirrorID)
                && isUnread($0, currentMemberID: currentMemberID, lastSeenActivityAt: lastSeenActivityAt)
        }.count
    }

    private static func threadTitle(
        forAnchor anchor: String,
        mirrorsByID: [String: EventMirror],
        invitationsByID: [String: EventInvitation]
    ) -> String? {
        if let mirror = mirrorsByID[anchor] { return mirror.title }
        if let invitation = invitationsByID[anchor] { return invitation.title }
        return nil
    }

    private static func isUnread(
        _ comment: EventComment,
        currentMemberID: String,
        lastSeenActivityAt: Date?
    ) -> Bool {
        guard comment.deletedAt == nil else { return false }
        guard comment.authorMemberID != currentMemberID else { return false }
        guard let lastSeen = lastSeenActivityAt else { return true }
        return comment.createdAt > lastSeen
    }
}

/// A single user-facing notification the app should post, identified by a stable
/// `id` so the same underlying event is never notified twice.
enum LocalNotificationKind: Equatable {
    case partnerCommentedOnMyEvent(eventTitle: String, commentBody: String)
    case invitationReceived(title: String)
    case invitationAccepted(title: String)
    case invitationDeclined(title: String)
    case accessRequestReceived
    case accessRequestAnswered(approved: Bool)
}

struct PlannedLocalNotification: Equatable, Identifiable {
    let id: String
    let kind: LocalNotificationKind
    let occurredAt: Date
}

/// Pure decision for which local notifications to post for the four user-selected
/// triggers (plan-tree notifications/decision 0001): partner comments on MY events,
/// new invitations to me, responses to my invitations, and history access requests/replies.
/// `since` is the local high-water mark of the last notification check; a nil `since`
/// means "no baseline yet" and produces nothing (so first launch doesn't flood).
enum LocalNotificationPlan {
    static func pending(
        comments: [EventComment],
        mirrors: [EventMirror],
        invitations: [EventInvitation],
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        since lastNotifiedAt: Date?
    ) -> [PlannedLocalNotification] {
        guard let since = lastNotifiedAt else { return [] }
        var result: [PlannedLocalNotification] = []
        let mirrorsByID = Dictionary(
            mirrors.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. Partner commented on one of MY events.
        for comment in comments
        where comment.deletedAt == nil
            && comment.authorMemberID != currentMemberID
            && comment.createdAt > since {
            guard let mirror = mirrorsByID[comment.eventMirrorID],
                  mirror.ownerMemberID == currentMemberID else { continue }
            result.append(
                PlannedLocalNotification(
                    id: "comment-\(comment.id)",
                    kind: .partnerCommentedOnMyEvent(eventTitle: mirror.title, commentBody: comment.body),
                    occurredAt: comment.createdAt
                )
            )
        }

        // 2. A new invitation addressed to me.
        for invite in invitations
        where invite.inviteeMemberID == currentMemberID
            && invite.creatorMemberID != currentMemberID
            && invite.archivedAt == nil
            && invite.status == .pending
            && invite.createdAt > since {
            result.append(
                PlannedLocalNotification(
                    id: "invite-recv-\(invite.id)",
                    kind: .invitationReceived(title: invite.title),
                    occurredAt: invite.createdAt
                )
            )
        }

        // 3. My invitation was accepted or declined by the partner.
        for invite in invitations
        where invite.creatorMemberID == currentMemberID
            && invite.updatedAt > since {
            switch invite.status {
            case .accepted:
                result.append(
                    PlannedLocalNotification(
                        id: "invite-resp-\(invite.id)-accepted",
                        kind: .invitationAccepted(title: invite.title),
                        occurredAt: invite.updatedAt
                    )
                )
            case .declined:
                result.append(
                    PlannedLocalNotification(
                        id: "invite-resp-\(invite.id)-declined",
                        kind: .invitationDeclined(title: invite.title),
                        occurredAt: invite.updatedAt
                    )
                )
            case .pending, .canceled:
                break
            }
        }

        // 4. History access requests. The incoming request from the partner lands in
        // MY zone (.privateOwnerZone); the partner's reply to MY request comes back via
        // the accepted shared zone (any source other than .privateOwnerZone), mirroring
        // CalendarAccessRequestListPlan.outgoing.
        for request in accessRequests {
            if request.source == .privateOwnerZone
                && request.ownerMemberID == currentMemberID
                && request.requesterMemberID != currentMemberID
                && request.status == .pending
                && request.createdAt > since {
                result.append(
                    PlannedLocalNotification(
                        id: "access-recv-\(request.id)",
                        kind: .accessRequestReceived,
                        occurredAt: request.createdAt
                    )
                )
            }
            if request.source != .privateOwnerZone
                && request.requesterMemberID == currentMemberID
                && request.status != .pending
                && request.updatedAt > since {
                result.append(
                    PlannedLocalNotification(
                        id: "access-ans-\(request.id)-\(request.status.rawValue)",
                        kind: .accessRequestAnswered(approved: request.status == .approved),
                        occurredAt: request.updatedAt
                    )
                )
            }
        }

        return result.sorted { $0.occurredAt < $1.occurredAt }
    }
}

/// Pure mapping from a notification kind to localized title/body. Kept separate from
/// LocalNotificationPlan so notification policy (what to notify) is tested independently
/// of wording (how it reads).
enum LocalNotificationContentPlan {
    static func content(
        for kind: LocalNotificationKind,
        strings: ShareCalStrings,
        partnerName: String
    ) -> (title: String, body: String) {
        switch kind {
        case let .partnerCommentedOnMyEvent(eventTitle, commentBody):
            return (strings.notifCommentTitle, "\(eventTitle): \(commentBody)")
        case let .invitationReceived(title):
            return (strings.notifInviteReceivedTitle, title)
        case let .invitationAccepted(title):
            return (strings.notifInviteAcceptedTitle, title)
        case let .invitationDeclined(title):
            return (strings.notifInviteDeclinedTitle, title)
        case .accessRequestReceived:
            return (strings.notifAccessRequestTitle, strings.notifAccessRequestBody)
        case let .accessRequestAnswered(approved):
            return (
                approved ? strings.notifAccessApprovedTitle : strings.notifAccessDeclinedTitle,
                strings.notifAccessAnsweredBody
            )
        }
    }
}
