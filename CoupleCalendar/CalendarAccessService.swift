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
            .map { calendar in
                CalendarDescriptor(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    colorHex: UIColor(cgColor: calendar.cgColor).hexString,
                    allowsContentModifications: calendar.allowsContentModifications
                )
            }
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

    func createLocalEvent(from draft: LocalCalendarEventDraft) throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? UUID().uuidString
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
