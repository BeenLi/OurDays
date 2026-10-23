import Foundation

/// Describes which comment thread a detail screen reads/writes and how to route its
/// CloudKit writes, so the same comment UI serves both a regular `EventMirror` and a
/// joint event (which has no mirror — see `JointScheduleEvent`). `key` is the value
/// stored in `EventComment.eventMirrorID` (and the filter for the thread). `ownerMemberID`
/// drives `CloudKitCommentWritePlan.destination` (== me → my private zone, else the
/// accepted shared zone). `recordName` locates that shared zone.
struct EventCommentAnchor: Equatable {
    let key: String
    let ownerMemberID: String
    let recordName: String
}

enum EventCommentAnchorPlan {
    static func anchor(forMirror mirror: EventMirror) -> EventCommentAnchor {
        EventCommentAnchor(
            key: mirror.id,
            ownerMemberID: mirror.ownerMemberID,
            recordName: mirror.cloudKitRecordName ?? mirror.mirrorKey
        )
    }

    /// My own event as the calendar shows it: a transient `display:` mirror built straight
    /// from EventKit (see `CalendarDisplayMirrorPlan`). Its thread is keyed by the `mirrorKey`,
    /// which is also the id *and* CloudKit record name of the persisted mirror on both devices
    /// (`EventMirrorService.makeMirrors` and the partner's import both name the record after
    /// it). So the key is known before the event has ever synced: a comment written now lands
    /// in my private zone (parented to the share root, so the partner imports it) and the
    /// mirror follows on the next sync, both carrying the same key. When a persisted twin
    /// already exists it wins, so any legacy twin whose id is not its mirrorKey keeps its thread.
    static func anchor(forOwnDisplayMirror mirror: EventMirror, persistedTwin: EventMirror?) -> EventCommentAnchor {
        if let persistedTwin {
            return anchor(forMirror: persistedTwin)
        }
        return EventCommentAnchor(
            key: mirror.mirrorKey,
            ownerMemberID: mirror.ownerMemberID,
            recordName: mirror.mirrorKey
        )
    }

    /// Joint events are anchored to the invitation, the only id BOTH partners share
    /// (each side's own EventMirror has a different id). Routing keys off the invitation
    /// creator: on the creator's device the comment lands in their private zone; on the
    /// partner's it lands in the creator's shared zone. Both devices read both zones back
    /// (`fetchEventComments` queries private + shared), so the thread is symmetric.
    static func anchor(forInvitation invitation: EventInvitation) -> EventCommentAnchor {
        EventCommentAnchor(
            key: invitation.id,
            ownerMemberID: invitation.creatorMemberID,
            recordName: invitation.cloudKitRecordName ?? invitation.id
        )
    }
}

/// Whether an event's detail screen offers a comment thread, and which anchor it uses.
enum EventCommentAvailability: Equatable {
    case available(EventCommentAnchor)
    /// My own event that the partner cannot see (it sits outside the sharing windows: before
    /// the pairing day and not covered by an approved history request). A thread on it would
    /// have no reader on the other side, so the detail explains instead of offering a composer.
    case notSharedWithPartner
}

/// Decides whether the event detail shows a comment thread. The partner's events (and my
/// persisted mirrors) always do. My own events open as transient `display:` mirrors; they get
/// a thread as soon as the event is inside the sharing windows — synced or not — so I can
/// start the conversation on my own schedule and the partner can reply once the mirror lands.
enum EventDetailCommentPlan {
    static func availability(
        for event: EventMirror,
        mirrors: [EventMirror],
        sharingWindows: [DateInterval]
    ) -> EventCommentAvailability {
        guard event.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix) else {
            return .available(EventCommentAnchorPlan.anchor(forMirror: event))
        }
        let twin = EventDetailMirrorResolutionPlan.persistedTwin(for: event, in: mirrors)
        guard twin != nil || CalendarSharingWindowPlan.contains(event.occurrenceStartDate, in: sharingWindows) else {
            return .notSharedWithPartner
        }
        return .available(EventCommentAnchorPlan.anchor(forOwnDisplayMirror: event, persistedTwin: twin))
    }
}

/// Decides which calendar events show a "has comments" indicator (the red dot). A displayed
/// event may be a transient `display:` mirror — my own events render straight from EventKit
/// (see `CalendarDisplayMirrorPlan`) and their id is NOT the value comments are keyed by; the
/// persisted twin sharing its `mirrorKey` carries the real id. Callers pass a lightweight
/// `mirrorKey -> real id` map so this stays a pure, SwiftData-free plan (one place owns the
/// display→real resolution, matching `EventDetailView`'s own resolution).
enum EventCommentIndicatorPlan {
    /// Anchor keys (`EventComment.eventMirrorID`) that currently have at least one live comment.
    static func commentedAnchorKeys(_ comments: [EventComment]) -> Set<String> {
        Set(comments.lazy.filter { $0.deletedAt == nil }.map(\.eventMirrorID))
    }

    static func hasComments(
        mirror: EventMirror,
        commentedKeys: Set<String>,
        persistedIDByMirrorKey: [String: String]
    ) -> Bool {
        guard let key = resolvedAnchorKey(for: mirror, persistedIDByMirrorKey: persistedIDByMirrorKey) else {
            return false
        }
        return commentedKeys.contains(key)
    }

    /// Joint events anchor their shared thread to the invitation id (== `JointScheduleEvent.id`).
    static func hasComments(jointEvent: JointScheduleEvent, commentedKeys: Set<String>) -> Bool {
        commentedKeys.contains(jointEvent.id)
    }

    /// The value a mirror's comment thread is keyed by. A transient display mirror resolves to
    /// its persisted twin's id via the shared `mirrorKey`, falling back to the `mirrorKey`
    /// itself — the key my own not-yet-synced events comment under
    /// (`EventCommentAnchorPlan.anchor(forOwnDisplayMirror:persistedTwin:)`).
    private static func resolvedAnchorKey(
        for mirror: EventMirror,
        persistedIDByMirrorKey: [String: String]
    ) -> String? {
        if mirror.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix) {
            return persistedIDByMirrorKey[mirror.mirrorKey] ?? mirror.mirrorKey
        }
        return mirror.id
    }
}
