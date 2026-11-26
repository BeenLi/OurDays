import EventKit
import Foundation
import UIKit

enum CalendarAccessError: LocalizedError {
    case noWritableCalendarSource

    var errorDescription: String? {
        switch self {
        case .noWritableCalendarSource:
            "OurDays could not find a writable calendar source."
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
    func ensureShareCalSmokeTestEvent(now: Date = .now, title: String = ShareCalSmokeTestEventPolicy.title) throws -> String {
        try ensureShareCalSmokeTestEvent(
            draft: ShareCalSmokeTestEventPolicy.draft(now: now, title: title)
        )
    }

    @discardableResult
    func ensureShareCalSmokeTestEvent(draft: LocalCalendarEventDraft) throws -> String {
        let calendar = try ensureShareCalEKCalendar()
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
            // Refresh the matched event to the requested (now-relative) time. The system
            // calendar survives app uninstall/reinstall, so a same-titled event from a
            // prior day's smoke run sits within the ±24h search window; reusing it as-is
            // would leave the smoke event stranded on an old date and absent from today's
            // calendar view. Re-dating it keeps every run's event on "now".
            if existing.startDate != draft.startDate || existing.endDate != draft.endDate {
                existing.startDate = draft.startDate
                existing.endDate = draft.endDate
                try eventStore.save(existing, span: .thisEvent, commit: true)
            }
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

    /// Test-harness only (`-ShareCalDeleteCalendarEventTitled`): removes every event with
    /// this title from the ShareCal calendar within ±30 days, so a smoke run can make an
    /// already-synced event disappear from the system calendar. Returns how many it removed.
    @discardableResult
    func deleteShareCalEvents(titled title: String, now: Date = .now) throws -> Int {
        let calendar = try ensureShareCalEKCalendar()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-30 * 24 * 60 * 60),
            end: now.addingTimeInterval(30 * 24 * 60 * 60),
            calendars: [calendar]
        )
        let matches = eventStore.events(matching: predicate).filter { $0.title == title }
        for event in matches {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }
        return matches.count
    }

    /// Test-harness only (`-ShareCalMoveCalendarEventTitled`): moves every event with this
    /// title in the ShareCal calendar within ±30 days one hour later, keeping its length, so a
    /// smoke run can reschedule an already-synced event. Returns how many it moved.
    @discardableResult
    func moveShareCalEventsOneHourLater(titled title: String, now: Date = .now) throws -> Int {
        let calendar = try ensureShareCalEKCalendar()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-30 * 24 * 60 * 60),
            end: now.addingTimeInterval(30 * 24 * 60 * 60),
            calendars: [calendar]
        )
        let matches = eventStore.events(matching: predicate).filter { $0.title == title }
        for event in matches {
            event.startDate = event.startDate.addingTimeInterval(60 * 60)
            event.endDate = event.endDate.addingTimeInterval(60 * 60)
            try eventStore.save(event, span: .thisEvent, commit: true)
        }
        return matches.count
    }

    /// Test-harness only (`-ShareCalSeedDailySeriesTitled`): a daily series of five
    /// one-hour events in the ShareCal calendar, the first in 15 minutes. Replaces a
    /// series left by an earlier run. Returns the series' event identifier.
    @discardableResult
    func ensureShareCalDailySeries(titled title: String, now: Date = .now) throws -> String {
        try deleteShareCalSeries(titled: title, now: now)
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = now.addingTimeInterval(15 * 60)
        event.endDate = now.addingTimeInterval(75 * 60)
        event.notes = ShareCalSmokeTestEventPolicy.notes
        event.calendar = try ensureShareCalEKCalendar()
        event.addRecurrenceRule(
            EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 5))
        )
        try eventStore.save(event, span: .futureEvents, commit: true)
        return event.eventIdentifier ?? ""
    }

    /// Test-harness only (`-ShareCalMoveSeriesTitled`): moves the series with this title
    /// one hour later from its `fromOccurrence`-th occurrence on ("all future events"),
    /// so a smoke run can see what EventKit does to the event identifiers and whether
    /// the uploaded records survive. Returns each occurrence before and after, as
    /// `index:eventIdentifier@occurrenceEpoch`.
    func moveShareCalSeriesOneHourLater(
        titled title: String,
        fromOccurrence: Int,
        now: Date = .now
    ) throws -> (before: [String], after: [String])? {
        let occurrences = try shareCalOccurrences(titled: title, now: now)
        guard occurrences.indices.contains(fromOccurrence) else { return nil }
        let before = Self.describe(occurrences)
        let event = occurrences[fromOccurrence]
        event.startDate = event.startDate.addingTimeInterval(60 * 60)
        event.endDate = event.endDate.addingTimeInterval(60 * 60)
        try eventStore.save(event, span: .futureEvents, commit: true)
        return (before, Self.describe(try shareCalOccurrences(titled: title, now: now)))
    }

    /// Test-harness only: removes every series (or event) with this title from the
    /// ShareCal calendar within ±30 days. Returns how many saves it took.
    @discardableResult
    func deleteShareCalSeries(titled title: String, now: Date = .now) throws -> Int {
        var removed = 0
        while removed < 20, let first = try shareCalOccurrences(titled: title, now: now).first {
            try eventStore.remove(first, span: .futureEvents, commit: true)
            removed += 1
        }
        return removed
    }

    /// Test-harness only (`-ShareCalPurgeSmokeTestData`): removes the throwaway events an
    /// earlier smoke run left in the ShareCal calendar, whole series included.
    @discardableResult
    func deleteLeftoverShareCalSmokeEvents(now: Date = .now) throws -> Int {
        let calendar = try ensureShareCalEKCalendar()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-30 * 24 * 60 * 60),
            end: now.addingTimeInterval(30 * 24 * 60 * 60),
            calendars: [calendar]
        )
        var removed = 0
        while removed < 200, let leftover = eventStore.events(matching: predicate)
            .sorted(by: { $0.startDate < $1.startDate })
            .first(where: { ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: $0.title) }) {
            try eventStore.remove(leftover, span: .futureEvents, commit: true)
            removed += 1
        }
        return removed
    }

    private func shareCalOccurrences(titled title: String, now: Date) throws -> [EKEvent] {
        let calendar = try ensureShareCalEKCalendar()
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-30 * 24 * 60 * 60),
            end: now.addingTimeInterval(30 * 24 * 60 * 60),
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate)
            .filter { $0.title == title }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func describe(_ occurrences: [EKEvent]) -> [String] {
        occurrences.enumerated().map { index, event in
            let occurrenceDate: Date = event.occurrenceDate ?? event.startDate
            return "\(index):\(event.eventIdentifier ?? "")@\(Int(occurrenceDate.timeIntervalSince1970.rounded()))"
        }
    }

    func events(from startDate: Date, to endDate: Date, selectedCalendarIDs: Set<String>) -> [CalendarSourceEvent] {
        let calendars = eventStore.calendars(for: .event)
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }

        return events(from: startDate, to: endDate, calendars: calendars)
    }

    func authorizedEvents(from startDate: Date, to endDate: Date) -> [CalendarSourceEvent] {
        events(
            from: startDate,
            to: endDate,
            calendars: eventStore.calendars(for: .event)
        )
    }

    private func events(from startDate: Date, to endDate: Date, calendars: [EKCalendar]) -> [CalendarSourceEvent] {
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
                url: event.url,
                isRecurring: event.hasRecurrenceRules,
                externalIdentifier: event.calendarItemExternalIdentifier,
                isDetached: event.isDetached
            )
        }
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

    func createShareCalEvent(from draft: LocalCalendarEventDraft) throws -> CreatedCalendarEvent {
        try createEvent(from: draft, calendar: ensureShareCalEKCalendar())
    }

    /// The calendar the system puts new events in (Settings > Calendar > Default Calendar).
    func defaultCalendarIDForNewEvents() -> String? {
        eventStore.defaultCalendarForNewEvents?.calendarIdentifier
    }

    /// Creates the event in the chosen calendar; in the app's own calendar when none
    /// was chosen or the chosen one is gone or read-only by now.
    func createEvent(from draft: LocalCalendarEventDraft, inCalendarWithID calendarID: String?) throws -> CreatedCalendarEvent {
        if let calendarID,
           let calendar = eventStore.calendar(withIdentifier: calendarID),
           calendar.allowsContentModifications {
            return try createEvent(from: draft, calendar: calendar)
        }
        return try createShareCalEvent(from: draft)
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

    private func ensureShareCalEKCalendar() throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .event).first(where: { calendar in
            calendar.title.compare(ShareCalCalendarBootstrapPolicy.calendarTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && calendar.allowsContentModifications
        }) {
            return existing
        }

        guard let source = writableCalendarSource() else {
            throw CalendarAccessError.noWritableCalendarSource
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = ShareCalCalendarBootstrapPolicy.calendarTitle
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
            allowsContentModifications: calendar.allowsContentModifications,
            sourceTitle: calendar.source?.title ?? ""
        )
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
