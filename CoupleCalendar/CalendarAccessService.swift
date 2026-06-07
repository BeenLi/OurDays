import EventKit
import Foundation
import UIKit

enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess
    case legacyAuthorized
    case unknown

    var canReadEvents: Bool {
        switch self {
        case .fullAccess, .legacyAuthorized:
            true
        default:
            false
        }
    }
}

enum CalendarAccessError: LocalizedError {
    case noWritableCalendarSource

    var errorDescription: String? {
        switch self {
        case .noWritableCalendarSource:
            "ShareCal could not find a writable calendar source."
        }
    }
}

final class CalendarAccessService {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationState() -> CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .legacyAuthorized
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unknown
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func calendars() -> [CalendarDescriptor] {
        eventStore.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map(descriptor(from:))
    }

    @discardableResult
    func ensureShareCalCalendar() throws -> CalendarDescriptor {
        try descriptor(from: ensureShareCalEKCalendar())
    }

    @discardableResult
    func ensureShareCalSmokeTestEvent(now: Date = .now, title: String = ShareCalSmokeTestEventPlan.title) throws -> String {
        let calendar = try ensureShareCalEKCalendar()
        let draft = ShareCalSmokeTestEventPlan.draft(now: now, title: title)
        let searchStart = draft.startDate.addingTimeInterval(-24 * 60 * 60)
        let searchEnd = draft.endDate.addingTimeInterval(24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: [calendar]
        )

        if let existing = eventStore.events(matching: predicate).first(where: { event in
            event.title == draft.title
        }) {
            return existing.eventIdentifier ?? UUID().uuidString
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? UUID().uuidString
    }

    func events(from startDate: Date, to endDate: Date, selectedCalendarIDs: Set<String>) -> [CalendarSourceEvent] {
        let calendars = eventStore.calendars(for: .event)
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )

        return eventStore.events(matching: predicate).map { event in
            CalendarSourceEvent(
                eventIdentifier: event.eventIdentifier ?? "",
                calendarIdentifier: event.calendar.calendarIdentifier,
                calendarTitle: event.calendar.title,
                calendarColorHex: UIColor(cgColor: event.calendar.cgColor).hexString,
                startDate: event.startDate,
                endDate: event.endDate,
                occurrenceStartDate: event.occurrenceDate ?? event.startDate,
                isAllDay: event.isAllDay,
                timeZoneIdentifier: (event.timeZone ?? .current).identifier,
                title: event.title ?? "Untitled",
                location: event.location,
                notes: event.notes,
                url: event.url
            )
        }
    }

    func existingEventIdentifiers(for eventIdentifiers: Set<String>) -> Set<String> {
        Set(eventIdentifiers.filter { eventStore.event(withIdentifier: $0) != nil })
    }

    func localEventExists(for invitation: EventInvitation) -> Bool {
        if let localEventID = invitation.createdLocalEventID,
           !localEventID.isEmpty,
           eventStore.event(withIdentifier: localEventID) != nil {
            return true
        }

        let searchStart = invitation.startDate.addingTimeInterval(-60)
        let searchEnd = invitation.endDate.addingTimeInterval(60)
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: eventStore.calendars(for: .event)
        )

        return eventStore.events(matching: predicate).contains { event in
            event.title == invitation.title
                && event.isAllDay == invitation.isAllDay
                && abs(event.startDate.timeIntervalSince(invitation.startDate)) <= 60
                && abs(event.endDate.timeIntervalSince(invitation.endDate)) <= 60
        }
    }

    func createLocalEvent(from draft: LocalCalendarEventDraft) throws -> String {
        let createdEvent = try createEvent(from: draft, calendar: writableCalendarForNewEvents())
        return createdEvent.eventIdentifier
    }

    func createShareCalEvent(from draft: LocalCalendarEventDraft) throws -> CreatedCalendarEvent {
        try createEvent(from: draft, calendar: ensureShareCalEKCalendar())
    }

    private func createEvent(from draft: LocalCalendarEventDraft, calendar: EKCalendar) throws -> CreatedCalendarEvent {
        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: true)
        return CreatedCalendarEvent(
            eventIdentifier: event.eventIdentifier ?? UUID().uuidString,
            calendarIdentifier: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            calendarColorHex: UIColor(cgColor: calendar.cgColor).hexString
        )
    }

    private func writableCalendarForNewEvents() throws -> EKCalendar {
        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           defaultCalendar.allowsContentModifications {
            return defaultCalendar
        }

        return try ensureShareCalEKCalendar()
    }

    private func ensureShareCalEKCalendar() throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .event).first(where: { calendar in
            calendar.title.compare(ShareCalCalendarBootstrapPlan.calendarTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && calendar.allowsContentModifications
        }) {
            return existing
        }

        guard let source = writableCalendarSource() else {
            throw CalendarAccessError.noWritableCalendarSource
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = ShareCalCalendarBootstrapPlan.calendarTitle
        calendar.cgColor = UIColor.systemPink.cgColor
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func writableCalendarSource() -> EKSource? {
        if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
            return defaultSource
        }

        return eventStore.sources.first { $0.sourceType == .calDAV }
            ?? eventStore.sources.first { $0.sourceType == .mobileMe }
            ?? eventStore.sources.first { $0.sourceType == .local }
            ?? eventStore.sources.first { source in
                source.sourceType != .birthdays && source.sourceType != .subscribed
            }
    }

    private func descriptor(from calendar: EKCalendar) -> CalendarDescriptor {
        CalendarDescriptor(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: UIColor(cgColor: calendar.cgColor).hexString,
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    static func defaultSyncWindow(now: Date = .now) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: 365, to: now) ?? now
        return DateInterval(start: start, end: end)
    }
}

private extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
