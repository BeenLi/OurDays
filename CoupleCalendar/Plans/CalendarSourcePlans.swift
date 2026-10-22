import Foundation

struct CalendarDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

enum ShareCalSmokeTestEventPlan {
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

enum ShareCalCalendarBootstrapPlan {
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
