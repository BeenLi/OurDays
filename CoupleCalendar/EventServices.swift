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

enum InvitationInteractionPlan {
    static func canRespond(to invitation: EventInvitation, currentMemberID: String) -> Bool {
        invitation.status == .pending && invitation.inviteeMemberID == currentMemberID
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

struct ShareCalReviewSample {
    let mirrors: [EventMirror]
    let invitations: [EventInvitation]
    let comments: [EventComment]
}

enum ShareCalReviewSampleData {
    static let sourceCalendarID = "sharecal-preview"
    static let sourceCalendarTitle = "ShareCal Preview"

    static func build(
        now: Date = .now,
        currentMemberID: String,
        partnerMemberID: String
    ) -> ShareCalReviewSample {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayID = Int(dayStart.timeIntervalSince1970)

        func date(hour: Int, minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
                ?? dayStart.addingTimeInterval(TimeInterval((hour * 60 + minute) * 60))
        }

        func mirror(
            suffix: String,
            ownerMemberID: String,
            title: String,
            startHour: Int,
            startMinute: Int = 0,
            endHour: Int,
            endMinute: Int = 0,
            location: String?,
            notes: String?,
            colorHex: String
        ) -> EventMirror {
            let startDate = date(hour: startHour, minute: startMinute)
            let mirrorKey = "\(Self.sourceCalendarID):\(ownerMemberID):\(suffix):\(dayID)"
            return EventMirror(
                id: mirrorKey,
                ownerMemberID: ownerMemberID,
                mirrorKey: mirrorKey,
                sourceCalendarID: Self.sourceCalendarID,
                sourceCalendarTitle: Self.sourceCalendarTitle,
                occurrenceStartDate: startDate,
                startDate: startDate,
                endDate: date(hour: endHour, minute: endMinute),
                isAllDay: false,
                timeZoneIdentifier: TimeZone.current.identifier,
                title: title,
                location: location,
                notes: notes,
                urlString: nil,
                calendarColorHex: colorHex,
                visibilityRawValue: EventVisibility.fullDetails.rawValue,
                deletedAt: nil,
                cloudKitRecordName: nil
            )
        }

        let myFocus = mirror(
            suffix: "me-focus",
            ownerMemberID: currentMemberID,
            title: "Focus block",
            startHour: 9,
            endHour: 10,
            location: nil,
            notes: "Sample private work block.",
            colorHex: "#3A86FF"
        )
        let myErrand = mirror(
            suffix: "me-errand",
            ownerMemberID: currentMemberID,
            title: "Pick up groceries",
            startHour: 17,
            startMinute: 30,
            endHour: 18,
            location: "Market",
            notes: "Shared household errand.",
            colorHex: "#4CC9F0"
        )
        let partnerGym = mirror(
            suffix: "partner-gym",
            ownerMemberID: partnerMemberID,
            title: "Gym class",
            startHour: 7,
            endHour: 8,
            location: "Fitness studio",
            notes: nil,
            colorHex: "#FF006E"
        )
        let partnerDinner = mirror(
            suffix: "partner-dinner",
            ownerMemberID: partnerMemberID,
            title: "Dinner with friends",
            startHour: 19,
            endHour: 21,
            location: "Preview Bistro",
            notes: "Sample shared availability.",
            colorHex: "#FB5607"
        )

        let invitation = EventInvitation(
            id: "\(Self.sourceCalendarID):invite:\(dayID)",
            creatorMemberID: currentMemberID,
            inviteeMemberID: partnerMemberID,
            title: "Plan dinner together",
            startDate: date(hour: 20),
            endDate: date(hour: 21),
            location: "Preview Bistro",
            notes: "Sample invitation for TestFlight review."
        )

        let comment = EventComment(
            id: "\(Self.sourceCalendarID):comment:\(dayID)",
            eventMirrorID: partnerDinner.id,
            authorMemberID: partnerMemberID,
            body: "I can leave after this.",
            createdAt: date(hour: 18, minute: 30)
        )

        return ShareCalReviewSample(
            mirrors: [myFocus, myErrand, partnerGym, partnerDinner],
            invitations: [invitation],
            comments: [comment]
        )
    }
}
