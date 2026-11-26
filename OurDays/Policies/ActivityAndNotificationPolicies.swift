import Foundation

struct ActivityFeedSection: Identifiable, Equatable {
    let dayStart: Date
    let items: [ActivityFeedItem]

    var id: Date { dayStart }
}

/// Groups the activity feed by the calendar day of each thread's latest comment,
/// keeping the feed's newest-first order inside and across sections.
enum ActivityFeedSectionPolicy {
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
enum AppIconBadgePolicy {
    static func badgeCount(unreadActivityCount: Int, pendingInviteCount: Int) -> Int {
        max(0, unreadActivityCount + pendingInviteCount)
    }
}

enum PendingActionBadgePolicy {
    static func count(
        invitations: [EventInvitation],
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        now: Date = .now
    ) -> Int {
        let invitationCount = invitations.filter {
            InvitationInteractionPolicy.canRespond(to: $0, currentMemberID: currentMemberID, now: now)
                && $0.archivedAt == nil
        }.count
        return invitationCount + CalendarAccessRequestListPolicy.pendingIncoming(
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
enum ActivityFeedPolicy {
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
            // (anchored to the invitation id, see EventCommentAnchorPolicy), the invitation.
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
enum LocalNotificationPolicy {
    static func pending(
        comments: [EventComment],
        mirrors: [EventMirror],
        invitations: [EventInvitation],
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        since lastNotifiedAt: Date?,
        pushedRecordNames: Set<String> = []
    ) -> [PlannedLocalNotification] {
        guard let since = lastNotifiedAt else { return [] }
        var result: [PlannedLocalNotification] = []
        let mirrorsByID = Dictionary(
            mirrors.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. Partner commented on one of MY events. Skipped only for a comment whose
        // visible push is known to have reached this device (CommentAlertPushPolicy,
        // decision 0004); a push that never arrived still gets its local notification.
        for comment in comments
        where !pushedRecordNames.contains(comment.cloudKitRecordName ?? comment.id)
            && comment.deletedAt == nil
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
            && invite.createdAt > since
            && !PartnerNudgePolicy.isNudged(.invitationReceived, invite, in: pushedRecordNames) {
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
            case .accepted where PartnerNudgePolicy.isNudged(.invitationAccepted, invite, in: pushedRecordNames),
                 .declined where PartnerNudgePolicy.isNudged(.invitationDeclined, invite, in: pushedRecordNames):
                // The nudge push for this answer reached this device (decision 0005).
                break
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
        // CalendarAccessRequestListPolicy.outgoing.
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

/// The visible push iCloud sends the moment the partner comments on one of MY events
/// (notifications decision 0004). Those comments are written into MY zone, i.e. my
/// private database, where a query subscription can watch one record type, fire on
/// creation only and carry the comment text. Everything else still travels by silent
/// push + sync + local notification.
enum CommentAlertPushPolicy {
    static let subscriptionID = "couplecalendar-comment-alert-subscription"
    /// Not a key in any strings file on purpose: iOS falls back to the key itself as
    /// the format, so the alert body is exactly the first argument (the comment text).
    static let bodyFormatKey = "%1$@"
    static let bodyArgumentKeys = ["body"]
    /// Excludes what I write myself on another device (iPhone and Mac share one
    /// account). Needs `authorMemberID` to be QUERYABLE in the deployed schema.
    static let predicateFormat = "authorMemberID != %@"

    /// Only a real CloudKit user id can go into the predicate; the "local-user"
    /// placeholder would make every comment (my own included) match.
    static func canSubscribe(currentMemberID: String) -> Bool {
        MemberIDPolicy.normalized(currentMemberID)?.hasPrefix("_") == true
    }

}

/// Which visible pushes this device has actually shown. A saved subscription does not
/// prove a push arrived (it can be dropped, or the device can be offline for days), so
/// the sync only skips the local notification for a record it knows was pushed: one
/// still sitting in Notification Center, or one the app saw arrive or get tapped.
enum SeenPushPolicy {
    static let limit = 200

    /// True when the planned notifications contain a kind that also travels as a
    /// visible push, i.e. when Notification Center is worth checking before posting.
    static func mayHaveBeenPushed(_ planned: [PlannedLocalNotification]) -> Bool {
        planned.contains { notification in
            switch notification.kind {
            case .partnerCommentedOnMyEvent,
                 .invitationReceived, .invitationAccepted, .invitationDeclined: true
            case .accessRequestReceived, .accessRequestAnswered: false
            }
        }
    }

    /// `seen` with `recordName` appended, oldest dropped beyond `limit`.
    static func remembering(_ recordName: String, in seen: [String]) -> [String] {
        guard !seen.contains(recordName) else { return seen }
        return Array((seen + [recordName]).suffix(limit))
    }
}

/// What a nudge tells the partner about. Raw values are part of the CloudKit record
/// name and of the `kind` field the subscriptions match on; don't rename.
enum PartnerNudgeKind: String, CaseIterable {
    case invitationReceived = "invitation"
    case invitationAccepted = "invitation-accepted"
    case invitationDeclined = "invitation-declined"
}

struct PartnerNudge: Equatable {
    let kind: PartnerNudgeKind
    /// Record name of what the nudge is about (the invitation).
    let subjectID: String
    /// Shown as the push body (the invitation title).
    let text: String
}

/// The "reminder inbox" (notifications decision 0005). An invitation lives in its
/// creator's zone, which the invitee only sees through the shared database, where no
/// query subscription is possible. So whoever wants the partner alerted also writes a
/// tiny `PartnerNudge` record into the PARTNER's zone; the partner's private database
/// has one query subscription per kind and iCloud shows the push at once.
enum PartnerNudgePolicy {
    static let recordType = "PartnerNudge"
    static let recordNamePrefix = "nudge:"
    static let kindKey = "kind"
    static let textKey = "text"
    static let predicateFormat = "kind == %@"
    static let bodyFormatKey = "%1$@"
    static let bodyArgumentKeys = [textKey]
    /// Nudges only matter until every device of the receiver has synced once.
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    static func subscriptionID(for kind: PartnerNudgeKind) -> String {
        "couplecalendar-nudge-\(kind.rawValue)-subscription"
    }

    /// One nudge per kind and subject: saving it a second time is refused by the
    /// server, so a retried upload never alerts twice.
    static func recordName(kind: PartnerNudgeKind, subjectID: String) -> String {
        "\(recordNamePrefix)\(kind.rawValue):\(subjectID)"
    }

    static func subjectID(for invitation: EventInvitation) -> String {
        invitation.cloudKitRecordName ?? invitation.id
    }

    /// The nudge to send after `invitation` was saved to CloudKit by me, if any: a new
    /// pending invitation of mine, or my accept / decline of the partner's. Cancels,
    /// withdrawals and archived invitations stay quiet.
    static func nudge(afterSaving invitation: EventInvitation, currentMemberID: String) -> PartnerNudge? {
        let kind: PartnerNudgeKind
        if invitation.creatorMemberID == currentMemberID {
            guard invitation.status == .pending, invitation.archivedAt == nil else { return nil }
            kind = .invitationReceived
        } else {
            switch invitation.status {
            case .accepted: kind = .invitationAccepted
            case .declined: kind = .invitationDeclined
            case .pending, .canceled: return nil
            }
        }
        return PartnerNudge(kind: kind, subjectID: subjectID(for: invitation), text: invitation.title)
    }

    static func isNudged(
        _ kind: PartnerNudgeKind,
        _ invitation: EventInvitation,
        in pushedRecordNames: Set<String>
    ) -> Bool {
        pushedRecordNames.contains(recordName(kind: kind, subjectID: subjectID(for: invitation)))
    }

    static func isExpired(createdAt: Date?, now: Date) -> Bool {
        guard let createdAt else { return false }
        return now.timeIntervalSince(createdAt) > retention
    }
}

/// Pure mapping from a notification kind to localized title/body. Kept separate from
/// LocalNotificationPolicy so notification policy (what to notify) is tested independently
/// of wording (how it reads).
enum LocalNotificationContentPolicy {
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

/// The happy moments at which the system App Store rating prompt may be shown.
/// Raw values are persisted in `SettingsStore.reviewPromptedMoments`; don't rename.
enum ReviewPromptMoment: String, CaseIterable, Codable {
    /// The 7th day of being paired ("配对第 7 天").
    case pairingDay7
    /// The first time the partner's comment shows up on this device.
    case firstPartnerComment
}

/// When to ask for an App Store rating. Each moment fires at most once per install,
/// and two prompts are kept apart so one launch never shows two. The system decides
/// whether the dialog actually appears (at most three times a year per user).
enum ReviewPromptPolicy {
    static let pairingDayThreshold = 7
    /// A partner comment counts as "just received" for this long; older ones (for
    /// example, years of history on the first launch after an update) don't fire.
    static let freshPartnerCommentWindow: TimeInterval = 3 * 24 * 60 * 60
    static let minimumIntervalBetweenPrompts: TimeInterval = 3 * 24 * 60 * 60

    static func moment(
        isPaired: Bool,
        pairingDate: Date?,
        currentMemberID: String,
        partnerShareOwnerID: String?,
        comments: [EventComment],
        promptedMoments: Set<ReviewPromptMoment>,
        lastPromptAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReviewPromptMoment? {
        guard isPaired else { return nil }
        if let lastPromptAt, now.timeIntervalSince(lastPromptAt) < minimumIntervalBetweenPrompts {
            return nil
        }
        if !promptedMoments.contains(.firstPartnerComment),
           hasFreshPartnerComment(
               comments: comments,
               currentMemberID: currentMemberID,
               partnerShareOwnerID: partnerShareOwnerID,
               now: now
           ) {
            return .firstPartnerComment
        }
        if !promptedMoments.contains(.pairingDay7),
           let pairingDate,
           PairingDatePolicy.ordinalDayNumber(since: pairingDate, now: now, calendar: calendar) >= pairingDayThreshold {
            return .pairingDay7
        }
        return nil
    }

    static func hasFreshPartnerComment(
        comments: [EventComment],
        currentMemberID: String,
        partnerShareOwnerID: String?,
        now: Date
    ) -> Bool {
        guard let partnerID = MemberIDPolicy.normalized(partnerShareOwnerID),
              partnerID != currentMemberID else { return false }
        return comments.contains { comment in
            comment.deletedAt == nil
                && comment.authorMemberID == partnerID
                && now.timeIntervalSince(comment.createdAt) <= freshPartnerCommentWindow
        }
    }

    /// Never prompt during automation: UI tests and the smoke script launch with
    /// `-ShareCal…` / `--sharecal-…` arguments, and a rating dialog would cover the UI.
    static func isAllowed(launchArguments: [String]) -> Bool {
        !launchArguments.contains { $0.hasPrefix("-ShareCal") || $0.hasPrefix("--sharecal") }
    }
}
