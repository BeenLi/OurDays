import Foundation

struct CalendarDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
    /// The account the calendar lives in (`EKSource.title`); with `title` it names the
    /// calendar on every device of the user (`CalendarSelectionRelayPolicy`).
    var sourceTitle: String = ""
}

enum ShareCalSmokeTestEventPolicy {
    static let title = "ShareCal E2E Smoke Test"
    static let notes = "Created by ShareCal simulator validation."

    static func draft(now: Date = .now, title: String = title) -> LocalCalendarEventDraft {
        LocalCalendarEventDraft(
            title: title,
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(45 * 60),
            isAllDay: false,
            location: nil,
            notes: notes
        )
    }
}

enum ShareCalCalendarBootstrapPolicy {
    static let calendarTitle = "ShareCal"
    static let calendarColorHex = "#FF2D55"

    static func shouldOfferCreation(calendars: [CalendarDescriptor]) -> Bool {
        !calendars.contains { calendar in
            isShareCalCalendar(calendar) && calendar.allowsContentModifications
        }
    }

    static func selectedCalendarIDs(
        afterEnsuring calendar: CalendarDescriptor,
        currentSelection: Set<String>
    ) -> Set<String> {
        var selection = currentSelection
        selection.insert(calendar.id)
        return selection
    }

    static func isShareCalCalendar(_ calendar: CalendarDescriptor) -> Bool {
        calendar.title.compare(calendarTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct CalendarSourceEvent: Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
    let startDate: Date
    let endDate: Date
    let occurrenceStartDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    /// Part of a repeating series: its occurrences share `eventIdentifier`, so only
    /// the occurrence date tells them apart.
    var isRecurring: Bool = false
}

struct LocalCalendarEventDraft: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

struct CreatedCalendarEvent: Equatable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
}

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

/// Builds the stable key that identifies one EventKit occurrence across syncs.
/// Shared by the mirror generator, the SwiftData models and the display policies, so
/// it lives with the other calendar-source policies rather than in `EventMirrorService`.
enum EventMirrorKeyPolicy {
    static func makeMirrorKey(
        calendarIdentifier: String,
        eventIdentifier: String,
        occurrenceStartDate: Date,
        fingerprint: String
    ) -> String {
        let stableEventID = eventIdentifier.isEmpty ? fingerprint : eventIdentifier
        let occurrenceEpoch = Int(occurrenceStartDate.timeIntervalSince1970.rounded())
        return "\(eventPrefix(calendarIdentifier: calendarIdentifier, eventIdentifier: stableEventID))\(occurrenceEpoch)"
    }

    static func makeMirrorKey(for event: CalendarSourceEvent) -> String {
        makeMirrorKey(
            calendarIdentifier: event.calendarIdentifier,
            eventIdentifier: event.eventIdentifier,
            occurrenceStartDate: event.occurrenceStartDate,
            fingerprint: fingerprint(for: event)
        )
    }

    /// The key every event gets: its own key, or the key it was first uploaded under
    /// when it has since moved (`keptKeysForRescheduledEvents`).
    static func mirrorKey(for event: CalendarSourceEvent, keptKeys: [String: String]) -> String {
        let key = makeMirrorKey(for: event)
        return keptKeys[key] ?? key
    }

    /// A one-off event's occurrence date is its start date, so moving it would give it a
    /// new key: a new record for the partner, and the comments on the old one (they hang
    /// on the record name) would vanish with it. A moved event keeps the key it already
    /// has instead, and its record is updated in place.
    ///
    /// Returns `[key the event would get now: key it keeps]`, only for events that moved.
    /// An event keeps a key when it is not repeating (a series' occurrences share the
    /// event identifier), its own key is unknown, and exactly one live shadow or own
    /// mirror carries its calendar and event identifier under a key no other current
    /// event has. Anything ambiguous gets its own key, as before.
    static func keptKeysForRescheduledEvents(
        _ events: [CalendarSourceEvent],
        existingShadows: [LocalEventShadow],
        existingMirrors: [EventMirror]
    ) -> [String: String] {
        let currentKeys = events.map { makeMirrorKey(for: $0) }
        let currentKeySet = Set(currentKeys)
        var liveKeys = Set(existingShadows.filter { !$0.isTombstone }.map(\.id))
        liveKeys.formUnion(existingMirrors.filter { $0.deletedAt == nil }.map(\.mirrorKey))
        let eventCountByPrefix = Dictionary(
            events.map { (eventPrefix(calendarIdentifier: $0.calendarIdentifier, eventIdentifier: $0.eventIdentifier), 1) },
            uniquingKeysWith: +
        )

        var kept: [String: String] = [:]
        for (event, key) in zip(events, currentKeys) {
            guard !event.isRecurring, !event.eventIdentifier.isEmpty, !liveKeys.contains(key) else { continue }
            let prefix = eventPrefix(calendarIdentifier: event.calendarIdentifier, eventIdentifier: event.eventIdentifier)
            guard eventCountByPrefix[prefix] == 1 else { continue }
            let candidates = liveKeys.filter { candidate in
                guard candidate.hasPrefix(prefix), !currentKeySet.contains(candidate) else { return false }
                return Int(candidate.dropFirst(prefix.count)) != nil
            }
            guard candidates.count == 1, let keptKey = candidates.first else { continue }
            kept[key] = keptKey
        }
        return kept
    }

    private static func eventPrefix(calendarIdentifier: String, eventIdentifier: String) -> String {
        "\(calendarIdentifier):\(eventIdentifier):"
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
}
