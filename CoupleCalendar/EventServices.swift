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

    func makeShadows(
        from events: [CalendarSourceEvent],
        selectedCalendarIDs: Set<String>,
        uploadedAt: Date,
        sharingWindows: [DateInterval]? = nil
    ) -> [LocalEventShadow] {
        events
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
            .filter { event in
                guard let sharingWindows else { return true }
                return Self.isEvent(event, inside: sharingWindows)
            }
            .map { event in
                let fingerprint = Self.fingerprint(for: event)
                let mirrorKey = Self.makeMirrorKey(
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
                !CalendarSharingWindowPlan.contains(mirror.occurrenceStartDate, in: sharingWindows)
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

    private static func isEvent(_ event: CalendarSourceEvent, inside sharingWindows: [DateInterval]) -> Bool {
        CalendarSharingWindowPlan.contains(event.occurrenceStartDate, in: sharingWindows)
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
        // In a two-person space, anyone who is not the creator is the invitee.
        // The stored `inviteeMemberID` is the partner's hashed CloudKit ID (stamped
        // by the creator), which never equals the recipient's local owner ID, so we
        // identify the invitee by "not the creator" instead.
        invitation.status == .pending && invitation.creatorMemberID != currentMemberID
    }
}

enum InvitationLocalEventSyncPlan {
    static func localEventIDsToTrack(from invitations: [EventInvitation]) -> Set<String> {
        Set(
            invitations.compactMap { invitation in
                guard let localEventID = invitation.createdLocalEventID,
                      !localEventID.isEmpty else {
                    return nil
                }
                return localEventID
            }
        )
    }

    static func cancelAcceptedInvitationsMissingLocalEvents(
        _ invitations: [EventInvitation],
        existingLocalEventIDs: Set<String>,
        now: Date
    ) -> [EventInvitation] {
        let trackableInvitations = invitations.filter { invitation in
            guard let localEventID = invitation.createdLocalEventID else { return false }
            return !localEventID.isEmpty
        }
        return cancelAcceptedInvitationsMissingLocalEvents(trackableInvitations, now: now) { invitation in
            guard let localEventID = invitation.createdLocalEventID,
                  !localEventID.isEmpty else {
                return false
            }
            return existingLocalEventIDs.contains(localEventID)
        }
    }

    static func cancelAcceptedInvitationsMissingLocalEvents(
        _ invitations: [EventInvitation],
        now: Date,
        localEventExists: (EventInvitation) -> Bool
    ) -> [EventInvitation] {
        let missing = invitations.filter { invitation in
            guard invitation.status == .accepted else {
                return false
            }
            return !localEventExists(invitation)
        }

        for invitation in missing {
            invitation.statusRawValue = InvitationStatus.canceled.rawValue
            invitation.updatedAt = now
        }

        return missing
    }
}

struct CalendarFocusRequest: Identifiable, Equatable {
    let id: String
    let invitationID: String
    let startDate: Date

    init(invitationID: String, startDate: Date) {
        self.id = invitationID
        self.invitationID = invitationID
        self.startDate = startDate
    }
}

enum CalendarFocusPlan {
    static func request(for invitation: EventInvitation) -> CalendarFocusRequest? {
        guard InvitationListPlan.canOpenInCalendar(invitation) else { return nil }
        return CalendarFocusRequest(invitationID: invitation.id, startDate: invitation.startDate)
    }
}

enum InvitationListPlan {
    static func visibleInvitations(_ invitations: [EventInvitation]) -> [EventInvitation] {
        invitations.filter { $0.archivedAt == nil }
    }

    static func canOpenInCalendar(_ invitation: EventInvitation) -> Bool {
        invitation.status == .accepted
    }

    static func canDelete(_ invitation: EventInvitation) -> Bool {
        invitation.archivedAt == nil
    }
}

struct CreateInviteDraft: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

enum CreateInviteValidationError: LocalizedError, Equatable {
    case emptyTitle
    case invalidDateRange

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Invite title is required."
        case .invalidDateRange:
            return "Invite end time must be after the start time."
        }
    }
}

enum CreateInvitePlan {
    static func localCalendarDraft(from draft: CreateInviteDraft) throws -> LocalCalendarEventDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CreateInviteValidationError.emptyTitle }
        guard draft.endDate > draft.startDate else { throw CreateInviteValidationError.invalidDateRange }

        return LocalCalendarEventDraft(
            title: title,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            location: cleanOptional(draft.location),
            notes: cleanOptional(draft.notes)
        )
    }

    static func invitation(
        from draft: CreateInviteDraft,
        creatorMemberID: String,
        inviteeMemberID: String
    ) throws -> EventInvitation {
        let localDraft = try localCalendarDraft(from: draft)
        return EventInvitation(
            creatorMemberID: creatorMemberID,
            inviteeMemberID: inviteeMemberID,
            title: localDraft.title,
            startDate: localDraft.startDate,
            endDate: localDraft.endDate,
            isAllDay: localDraft.isAllDay,
            location: localDraft.location,
            notes: localDraft.notes,
            statusRawValue: InvitationStatus.pending.rawValue
        )
    }

    static func mirror(
        from draft: CreateInviteDraft,
        createdEvent: CreatedCalendarEvent,
        ownerMemberID: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> EventMirror {
        let localDraft = try localCalendarDraft(from: draft)
        let fingerprint = [
            createdEvent.eventIdentifier,
            "\(Int(localDraft.startDate.timeIntervalSince1970.rounded()))",
            "\(Int(localDraft.endDate.timeIntervalSince1970.rounded()))",
            localDraft.title
        ].joined(separator: "|")
        let mirrorKey = EventMirrorService.makeMirrorKey(
            calendarIdentifier: createdEvent.calendarIdentifier,
            eventIdentifier: createdEvent.eventIdentifier,
            occurrenceStartDate: localDraft.startDate,
            fingerprint: fingerprint
        )

        return EventMirror(
            id: mirrorKey,
            ownerMemberID: ownerMemberID,
            mirrorKey: mirrorKey,
            sourceCalendarID: createdEvent.calendarIdentifier,
            sourceCalendarTitle: createdEvent.calendarTitle,
            occurrenceStartDate: localDraft.startDate,
            startDate: localDraft.startDate,
            endDate: localDraft.endDate,
            isAllDay: localDraft.isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            title: localDraft.title,
            location: localDraft.location,
            notes: localDraft.notes,
            urlString: nil,
            calendarColorHex: createdEvent.calendarColorHex,
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: mirrorKey
        )
    }

    static func conflictCandidateMirror(
        from draft: CreateInviteDraft,
        ownerMemberID: String
    ) throws -> EventMirror {
        let createdEvent = CreatedCalendarEvent(
            eventIdentifier: "new-invite-candidate",
            calendarIdentifier: ShareCalCalendarBootstrapPlan.calendarTitle,
            calendarTitle: ShareCalCalendarBootstrapPlan.calendarTitle,
            calendarColorHex: ShareCalCalendarBootstrapPlan.calendarColorHex
        )
        return try mirror(from: draft, createdEvent: createdEvent, ownerMemberID: ownerMemberID)
    }

    private static func cleanOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct JointScheduleEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let calendarTitle: String = ShareCalCalendarBootstrapPlan.calendarTitle
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

enum JointSchedulePlan {
    static func jointEvents(
        from invitations: [EventInvitation],
        currentMemberID: String,
        partnerMemberID: String
    ) -> [JointScheduleEvent] {
        // Every invitation in a two-person space is between the current user and
        // their partner, so any accepted one is a joint event. We cannot verify the
        // member pair by ID: the creator/invitee are stored in the creator's
        // vocabulary (its local owner ID + the partner's hashed CloudKit ID), which
        // the recipient cannot match against its own local owner ID.
        invitations
            .filter { invitation in
                invitation.status == .accepted
            }
            .map { invitation in
                JointScheduleEvent(
                    id: invitation.id,
                    title: invitation.title,
                    startDate: invitation.startDate,
                    endDate: invitation.endDate,
                    isAllDay: invitation.isAllDay,
                    location: invitation.location,
                    notes: invitation.notes
                )
            }
    }

    static func ordinaryMirrors(
        _ mirrors: [EventMirror],
        excluding jointEvents: [JointScheduleEvent]
    ) -> [EventMirror] {
        mirrors.filter { mirror in
            !jointEvents.contains { jointEvent in
                representsSameSchedule(mirror, jointEvent)
            }
        }
    }

    private static func representsSameSchedule(
        _ mirror: EventMirror,
        _ jointEvent: JointScheduleEvent
    ) -> Bool {
        mirror.deletedAt == nil
            && mirror.title == jointEvent.title
            && mirror.startDate == jointEvent.startDate
            && mirror.endDate == jointEvent.endDate
            && mirror.isAllDay == jointEvent.isAllDay
    }
}

enum WeekAgendaItemKind: Equatable {
    case currentMember
    case partner
    case joint
}

struct WeekAgendaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarTitle: String
    let colorHex: String
    let kind: WeekAgendaItemKind
    let mirrorID: String?
}

struct WeekAgendaDay: Identifiable, Equatable {
    let id: Date
    let date: Date
    let items: [WeekAgendaItem]
}

enum WeekAgendaPlan {
    static func days(
        containing selectedDate: Date,
        mirrors: [EventMirror],
        jointEvents: [JointScheduleEvent],
        currentMemberID: String,
        calendar: Calendar = .current
    ) -> [WeekAgendaDay] {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: calendar.startOfDay(for: selectedDate), duration: 7 * 24 * 60 * 60)
        let weekStart = calendar.startOfDay(for: weekInterval.start)

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                return nil
            }
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
            let interval = DateInterval(start: dayStart, end: dayEnd)
            let mirrorItems = mirrors
                .filter { $0.deletedAt == nil && interval.contains($0.startDate) }
                .map { mirror in
                    WeekAgendaItem(
                        id: mirror.id,
                        title: mirror.title,
                        startDate: mirror.startDate,
                        endDate: mirror.endDate,
                        isAllDay: mirror.isAllDay,
                        location: mirror.location,
                        notes: mirror.notes,
                        calendarTitle: mirror.sourceCalendarTitle,
                        colorHex: mirror.calendarColorHex,
                        kind: mirror.ownerMemberID == currentMemberID ? .currentMember : .partner,
                        mirrorID: mirror.id
                    )
                }
            let jointItems = jointEvents
                .filter { interval.contains($0.startDate) }
                .map { event in
                    WeekAgendaItem(
                        id: event.id,
                        title: event.title,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        isAllDay: event.isAllDay,
                        location: event.location,
                        notes: event.notes,
                        calendarTitle: event.calendarTitle,
                        colorHex: ShareCalCalendarBootstrapPlan.calendarColorHex,
                        kind: .joint,
                        mirrorID: nil
                    )
                }
            let items = (mirrorItems + jointItems).sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay && !rhs.isAllDay
                }
                if lhs.startDate == rhs.startDate {
                    return lhs.title < rhs.title
                }
                return lhs.startDate < rhs.startDate
            }
            return WeekAgendaDay(id: dayStart, date: dayStart, items: items)
        }
    }
}

enum InvitationConflictPlan {
    static func conflicts(
        for event: EventMirror,
        partnerMemberID: String,
        mirrors: [EventMirror]
    ) -> [EventMirror] {
        mirrors
            .filter { mirror in
                mirror.deletedAt == nil
                    && mirror.id != event.id
                    && mirror.ownerMemberID == partnerMemberID
                    && overlaps(
                        startA: event.startDate,
                        endA: event.endDate,
                        startB: mirror.startDate,
                        endB: mirror.endDate
                    )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func overlaps(startA: Date, endA: Date, startB: Date, endB: Date) -> Bool {
        startA < endB && startB < endA
    }
}

enum AcceptedInvitationMirrorPlan {
    static func mirror(
        from invitation: EventInvitation,
        createdEvent: CreatedCalendarEvent,
        ownerMemberID: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> EventMirror {
        let fingerprint = [
            invitation.id,
            createdEvent.eventIdentifier,
            "\(Int(invitation.startDate.timeIntervalSince1970.rounded()))",
            "\(Int(invitation.endDate.timeIntervalSince1970.rounded()))",
            invitation.title
        ].joined(separator: "|")
        let mirrorKey = EventMirrorService.makeMirrorKey(
            calendarIdentifier: createdEvent.calendarIdentifier,
            eventIdentifier: createdEvent.eventIdentifier,
            occurrenceStartDate: invitation.startDate,
            fingerprint: fingerprint
        )

        return EventMirror(
            id: mirrorKey,
            ownerMemberID: ownerMemberID,
            mirrorKey: mirrorKey,
            sourceCalendarID: createdEvent.calendarIdentifier,
            sourceCalendarTitle: createdEvent.calendarTitle,
            occurrenceStartDate: invitation.startDate,
            startDate: invitation.startDate,
            endDate: invitation.endDate,
            isAllDay: invitation.isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            title: invitation.title,
            location: invitation.location,
            notes: invitation.notes,
            urlString: nil,
            calendarColorHex: createdEvent.calendarColorHex,
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: mirrorKey
        )
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
