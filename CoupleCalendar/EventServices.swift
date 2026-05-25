import Foundation

struct EventMirrorService {
    static func makeMirrorKey(
        calendarIdentifier: String,
        eventIdentifier: String,
        occurrenceStartDate: Date,
        fingerprint: String
    ) -> String {
        let stableEventID = eventIdentifier.isEmpty ? fingerprint : eventIdentifier
        let occurrenceEpoch = Int(occurrenceStartDate.timeIntervalSince1970.rounded())
        return "\(calendarIdentifier):\(stableEventID):\(occurrenceEpoch)"
    }

    func makeMirrors(
        from events: [CalendarSourceEvent],
        selectedCalendarIDs: Set<String>,
        ownerMemberID: String,
        visibility: EventVisibility
    ) -> [EventMirror] {
        guard visibility != .hidden else { return [] }

        return events
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
            .map { event in
                let fingerprint = Self.fingerprint(for: event)
                let mirrorKey = Self.makeMirrorKey(
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

    func deletedShadows(existingEventKeys: Set<String>, shadows: [LocalEventShadow]) -> [LocalEventShadow] {
        shadows
            .filter { !existingEventKeys.contains($0.mirrorKey) && !$0.isTombstone }
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

    static func fingerprint(for event: CalendarSourceEvent) -> String {
        [
            event.eventIdentifier,
            event.calendarIdentifier,
            "\(Int(event.startDate.timeIntervalSince1970.rounded()))",
            "\(Int(event.endDate.timeIntervalSince1970.rounded()))",
            event.title,
            event.location ?? "",
            event.notes ?? "",
            event.url?.absoluteString ?? ""
        ].joined(separator: "|")
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

    func cancel(_ invitation: EventInvitation) {
        guard invitation.status == .pending else { return }
        invitation.status = .canceled
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
