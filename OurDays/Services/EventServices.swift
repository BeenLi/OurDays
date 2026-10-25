import Foundation

struct EventMirrorService {
    func makeMirrors(
        from events: [CalendarSourceEvent],
        selectedCalendarIDs: Set<String>,
        ownerMemberID: String,
        visibility: EventVisibility,
        sharingWindows: [DateInterval]? = nil
    ) -> [EventMirror] {
        guard visibility != .hidden else { return [] }

        return events
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
            .filter { event in
                guard let sharingWindows else { return true }
                return Self.isEvent(event, inside: sharingWindows)
            }
            .map { event in
                let fingerprint = EventMirrorKeyPolicy.fingerprint(for: event)
                let mirrorKey = EventMirrorKeyPolicy.makeMirrorKey(
                    calendarIdentifier: event.calendarIdentifier,
                    eventIdentifier: event.eventIdentifier,
                    occurrenceStartDate: event.occurrenceStartDate,
                    fingerprint: fingerprint
                )
                let visibleFields = Self.visibleFields(for: event, visibility: visibility)

                return EventMirror(
                    id: mirrorKey,
                    ownerMemberID: ownerMemberID,
                    mirrorKey: mirrorKey,
                    sourceCalendarID: event.calendarIdentifier,
                    sourceCalendarTitle: event.calendarTitle,
                    occurrenceStartDate: event.occurrenceStartDate,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    timeZoneIdentifier: event.timeZoneIdentifier,
                    title: visibleFields.title,
                    location: visibleFields.location,
                    notes: visibleFields.notes,
                    urlString: visibleFields.urlString,
                    calendarColorHex: event.calendarColorHex,
                    visibilityRawValue: visibility.rawValue,
                    deletedAt: nil,
                    cloudKitRecordName: mirrorKey
                )
            }
    }

    func makeShadows(
        from events: [CalendarSourceEvent],
        selectedCalendarIDs: Set<String>,
        uploadedAt: Date?,
        sharingWindows: [DateInterval]? = nil
    ) -> [LocalEventShadow] {
        events
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
            .filter { event in
                guard let sharingWindows else { return true }
                return Self.isEvent(event, inside: sharingWindows)
            }
            .map { event in
                let fingerprint = EventMirrorKeyPolicy.fingerprint(for: event)
                let mirrorKey = EventMirrorKeyPolicy.makeMirrorKey(
                    calendarIdentifier: event.calendarIdentifier,
                    eventIdentifier: event.eventIdentifier,
                    occurrenceStartDate: event.occurrenceStartDate,
                    fingerprint: fingerprint
                )
                return LocalEventShadow(
                    id: mirrorKey,
                    localEventIdentifier: event.eventIdentifier,
                    calendarIdentifier: event.calendarIdentifier,
                    occurrenceStartDate: event.occurrenceStartDate,
                    fingerprint: fingerprint,
                    cloudKitRecordName: mirrorKey,
                    lastUploadedAt: uploadedAt,
                    isTombstone: false
                )
            }
    }

    func deletedShadows(
        existingEventKeys: Set<String>,
        shadows: [LocalEventShadow],
        selectedCalendarIDs: Set<String>? = nil,
        syncWindow: DateInterval? = nil
    ) -> [LocalEventShadow] {
        shadows
            .filter { shadow in
                !existingEventKeys.contains(shadow.mirrorKey)
                    && !shadow.isTombstone
                    && (selectedCalendarIDs?.contains(shadow.calendarIdentifier) ?? true)
                    && (syncWindow?.contains(shadow.occurrenceStartDate) ?? true)
            }
            .map { shadow in
                LocalEventShadow(
                    id: shadow.id,
                    localEventIdentifier: shadow.localEventIdentifier,
                    calendarIdentifier: shadow.calendarIdentifier,
                    occurrenceStartDate: shadow.occurrenceStartDate,
                    fingerprint: shadow.fingerprint,
                    cloudKitRecordName: shadow.cloudKitRecordName,
                    lastUploadedAt: shadow.lastUploadedAt,
                    isTombstone: true
                )
            }
    }

    func deletedMirrorTombstones(
        for deletedShadows: [LocalEventShadow],
        existingMirrors: [EventMirror],
        deletedAt: Date
    ) -> [EventMirror] {
        let existingMirrorByKey = Dictionary(uniqueKeysWithValues: existingMirrors.map { ($0.mirrorKey, $0) })
        return deletedShadows.compactMap { shadow in
            guard let mirror = existingMirrorByKey[shadow.mirrorKey] else { return nil }
            return Self.deletedMirror(from: mirror, deletedAt: deletedAt, fallbackRecordName: shadow.cloudKitRecordName)
        }
    }

    func deletedMirrorTombstones(
        existingEventKeys: Set<String>,
        existingMirrors: [EventMirror],
        selectedCalendarIDs: Set<String>,
        syncWindow: DateInterval,
        deletedAt: Date
    ) -> [EventMirror] {
        existingMirrors
            .filter { mirror in
                !existingEventKeys.contains(mirror.mirrorKey)
                    && mirror.deletedAt == nil
                    && selectedCalendarIDs.contains(mirror.sourceCalendarID)
                    && syncWindow.contains(mirror.occurrenceStartDate)
            }
            .map { Self.deletedMirror(from: $0, deletedAt: deletedAt) }
    }

    func mirrorsOutsideSharingWindows(
        _ mirrors: [EventMirror],
        sharingWindows: [DateInterval]
    ) -> [EventMirror] {
        mirrors
            .filter { $0.deletedAt == nil }
            .filter { mirror in
                !CalendarSharingWindowPolicy.contains(mirror.occurrenceStartDate, in: sharingWindows)
            }
    }

    private static func deletedMirror(
        from mirror: EventMirror,
        deletedAt: Date,
        fallbackRecordName: String? = nil
    ) -> EventMirror {
        EventMirror(
            id: mirror.id,
            ownerMemberID: mirror.ownerMemberID,
            mirrorKey: mirror.mirrorKey,
            sourceCalendarID: mirror.sourceCalendarID,
            sourceCalendarTitle: mirror.sourceCalendarTitle,
            occurrenceStartDate: mirror.occurrenceStartDate,
            startDate: mirror.startDate,
            endDate: mirror.endDate,
            isAllDay: mirror.isAllDay,
            timeZoneIdentifier: mirror.timeZoneIdentifier,
            title: mirror.title,
            location: mirror.location,
            notes: mirror.notes,
            urlString: mirror.urlString,
            calendarColorHex: mirror.calendarColorHex,
            visibilityRawValue: mirror.visibilityRawValue,
            deletedAt: deletedAt,
            cloudKitRecordName: mirror.cloudKitRecordName ?? fallbackRecordName
        )
    }

    private static func visibleFields(
        for event: CalendarSourceEvent,
        visibility: EventVisibility
    ) -> (title: String, location: String?, notes: String?, urlString: String?) {
        switch visibility {
        case .busyOnly:
            return ("Busy", nil, nil, nil)
        case .titleAndLocation:
            return (event.title, event.location, nil, nil)
        case .fullDetails:
            return (event.title, event.location, event.notes, event.url?.absoluteString)
        case .hidden:
            return ("", nil, nil, nil)
        }
    }

    private static func isEvent(_ event: CalendarSourceEvent, inside sharingWindows: [DateInterval]) -> Bool {
        CalendarSharingWindowPolicy.contains(event.occurrenceStartDate, in: sharingWindows)
    }
}

enum InvitationError: LocalizedError {
    case notPending

    var errorDescription: String? {
        switch self {
        case .notPending:
            return "Only pending invitations can be accepted."
        }
    }
}

struct InvitationService {
    func accept(_ invitation: EventInvitation, createdLocalEventID: String) throws -> LocalCalendarEventDraft {
        guard invitation.status == .pending else {
            throw InvitationError.notPending
        }

        invitation.status = .accepted
        invitation.createdLocalEventID = createdLocalEventID

        return LocalCalendarEventDraft(
            title: invitation.title,
            startDate: invitation.startDate,
            endDate: invitation.endDate,
            isAllDay: invitation.isAllDay,
            location: invitation.location,
            notes: invitation.notes
        )
    }

    func decline(_ invitation: EventInvitation) {
        guard invitation.status == .pending else { return }
        invitation.status = .declined
    }

    /// The creator takes a pending invitation back. The record is the creator's own
    /// (private zone), so the partner learns of it only when this status reaches
    /// CloudKit; the upload flag keeps it queued until it does.
    func cancel(_ invitation: EventInvitation) {
        guard invitation.status == .pending else { return }
        invitation.status = .canceled
        invitation.needsCloudKitUpload = true
    }

    func draft(from invitation: EventInvitation) -> LocalCalendarEventDraft {
        LocalCalendarEventDraft(
            title: invitation.title,
            startDate: invitation.startDate,
            endDate: invitation.endDate,
            isAllDay: invitation.isAllDay,
            location: invitation.location,
            notes: invitation.notes
        )
    }
}

struct CommentService {
    var now: () -> Date = { .now }

    func createComment(eventMirrorID: String, authorMemberID: String, body: String) -> EventComment {
        EventComment(
            eventMirrorID: eventMirrorID,
            authorMemberID: authorMemberID,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now()
        )
    }

    func edit(_ comment: EventComment, body: String) {
        comment.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        comment.editedAt = now()
    }

    func markRead(_ comment: EventComment) {
        comment.isRead = true
    }

    func delete(_ comment: EventComment) {
        comment.deletedAt = now()
    }
}
