import Foundation

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

enum CalendarFocusPolicy {
    static func request(for invitation: EventInvitation) -> CalendarFocusRequest? {
        guard InvitationListPolicy.canOpenInCalendar(invitation) else { return nil }
        return CalendarFocusRequest(invitationID: invitation.id, startDate: invitation.startDate)
    }
}

struct JointScheduleEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let calendarTitle: String = ShareCalCalendarBootstrapPolicy.calendarTitle
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

enum JointSchedulePolicy {
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

enum WeekAgendaPolicy {
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
                        colorHex: ShareCalCalendarBootstrapPolicy.calendarColorHex,
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
