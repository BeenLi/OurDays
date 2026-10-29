import Foundation

/// One line of "when" for an event detail header: "Jun 16, Tue · 19:30 – 21:30".
enum EventDetailTimePolicy {
    static func text(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        strings: ShareCalStrings,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        let dayFormatter = DateFormatterCache.formatter(template: "MMMdEEE", locale: locale, calendar: calendar)
        let timeFormatter = DateFormatterCache.formatter(template: "jmm", locale: locale, calendar: calendar)
        if isAllDay {
            // All-day end dates are exclusive (next midnight); show the last covered day.
            let lastDay = max(startDate, endDate.addingTimeInterval(-1))
            if calendar.isDate(startDate, inSameDayAs: lastDay) {
                return "\(dayFormatter.string(from: startDate)) · \(strings.allDay)"
            }
            return "\(dayFormatter.string(from: startDate)) – \(dayFormatter.string(from: lastDay)) · \(strings.allDay)"
        }
        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return "\(dayFormatter.string(from: startDate)) · \(timeFormatter.string(from: startDate)) – \(timeFormatter.string(from: endDate))"
        }
        return "\(dayFormatter.string(from: startDate)) \(timeFormatter.string(from: startDate)) – \(dayFormatter.string(from: endDate)) \(timeFormatter.string(from: endDate))"
    }
}

/// `DateFormatter()` costs milliseconds to build; the display policies format every visible
/// event, so configured formatters are kept per (format, locale, calendar, time zone).
/// A formatter is never mutated after it is cached, which makes it safe to share.
enum DateFormatterCache {
    private static let lock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    /// Formatter for a localized template such as `"MMM d"` (via `setLocalizedDateFormatFromTemplate`).
    static func formatter(template: String, locale: Locale, calendar: Calendar, timeZone: TimeZone? = nil) -> DateFormatter {
        formatter(key: "template:\(template)", locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone) {
            $0.setLocalizedDateFormatFromTemplate(template)
        }
    }

    /// Formatter for a fixed `dateFormat` such as `"yyyy年M月d日"`.
    static func formatter(dateFormat: String, locale: Locale, calendar: Calendar, timeZone: TimeZone? = nil) -> DateFormatter {
        formatter(key: "format:\(dateFormat)", locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone) {
            $0.dateFormat = dateFormat
        }
    }

    private static func formatter(
        key: String,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone,
        configure: (DateFormatter) -> Void
    ) -> DateFormatter {
        let cacheKey = [
            key,
            locale.identifier,
            "\(calendar.identifier)",
            "\(calendar.firstWeekday)/\(calendar.minimumDaysInFirstWeek)",
            timeZone.identifier
        ].joined(separator: "|")
        return lock.withLock {
            if let cached = formatters[cacheKey] {
                return cached
            }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = timeZone
            configure(formatter)
            formatters[cacheKey] = formatter
            return formatter
        }
    }
}

/// The short "19:30 - 21:30" (or localized all-day) text used in lists, conflict
/// banners and accessibility labels.
enum EventTimeRangeTextPolicy {
    static func text(startDate: Date, endDate: Date, isAllDay: Bool, strings: ShareCalStrings) -> String {
        if isAllDay {
            return strings.allDay
        }
        return "\(startDate.formatted(date: .omitted, time: .shortened)) - \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    static func text(for event: EventMirror, strings: ShareCalStrings) -> String {
        text(startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay, strings: strings)
    }

    static func text(for event: JointScheduleEvent, strings: ShareCalStrings) -> String {
        text(startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay, strings: strings)
    }
}

enum CalendarSharingWindowPolicy {
    static let defaultEndDate = Date.distantFuture

    static func defaultWindows(now: Date = .now) -> [DateInterval] {
        [
            DateInterval(
                start: now,
                end: defaultEndDate
            )
        ]
    }

    static func effectiveWindows(
        now: Date = .now,
        accessRequests: [CalendarAccessRequest]
    ) -> [DateInterval] {
        let approvedRequestWindows = accessRequests.compactMap { request -> DateInterval? in
            guard request.source == .privateOwnerZone,
                  request.status == .approved,
                  request.requestedEndDate > request.requestedStartDate else {
                return nil
            }
            return DateInterval(start: request.requestedStartDate, end: request.requestedEndDate)
        }
        return defaultWindows(now: now) + approvedRequestWindows
    }

    static func contains(_ date: Date, in windows: [DateInterval]) -> Bool {
        windows.contains { window in
            date >= window.start && date < window.end
        }
    }

    static func enclosingInterval(for windows: [DateInterval]) -> DateInterval {
        precondition(!windows.isEmpty, "Calendar sharing windows must not be empty.")
        let start = windows.map(\.start).min() ?? windows[0].start
        let end = windows.map(\.end).max() ?? windows[0].end
        return DateInterval(start: start, end: end)
    }
}

enum CalendarMirrorVisibilityPolicy {
    static func memberMirrors(
        _ mirrors: [EventMirror],
        currentMemberID: String,
        partnerShareOwnerID: String?
    ) -> [EventMirror] {
        mirrors.filter { mirror in
            mirror.ownerMemberID == currentMemberID || mirror.ownerMemberID == partnerShareOwnerID
        }
    }
}

enum CalendarSetupGuidanceStep: Equatable {
    case calendarAccess
    case pairing
    /// I accepted the partner's link and still owe them mine.
    case shareBack
}

enum CalendarSetupGuidancePolicy {
    static func step(
        hasCompletedInitialProfilePrompt: Bool,
        currentDisplayName: String,
        authorizationState: CalendarAuthorizationState,
        selectedCalendarIDs: Set<String>,
        pairingStatus: PairingStatus,
        hasSentInviteBack: Bool = false
    ) -> CalendarSetupGuidanceStep? {
        guard hasCompletedInitialProfilePrompt else { return nil }
        guard PairingSettingsPolicy.normalizedDisplayName(currentDisplayName) != nil else { return nil }
        // Sending my link back needs no calendar access, and until I do the partner
        // sees nothing of mine, so it comes before calendar setup.
        if pairingStatus == .waitingForYouToShare {
            return hasSentInviteBack ? nil : .shareBack
        }
        guard authorizationState.canReadEvents && !selectedCalendarIDs.isEmpty else {
            return .calendarAccess
        }

        switch pairingStatus {
        case .notPaired:
            return .pairing
        case .waitingForPartner, .waitingForPartnerToShare, .waitingForYouToShare, .paired:
            return nil
        }
    }
}

enum CalendarDisplayMirrorPolicy {
    static let transientIDPrefix = "display:"

    static func displayMirrors(
        from events: [CalendarSourceEvent],
        ownerMemberID: String
    ) -> [EventMirror] {
        events.map { event in
            let fingerprint = EventMirrorKeyPolicy.fingerprint(for: event)
            let mirrorKey = EventMirrorKeyPolicy.makeMirrorKey(
                calendarIdentifier: event.calendarIdentifier,
                eventIdentifier: event.eventIdentifier,
                occurrenceStartDate: event.occurrenceStartDate,
                fingerprint: fingerprint
            )
            return EventMirror(
                id: "\(transientIDPrefix)\(mirrorKey)",
                ownerMemberID: ownerMemberID,
                mirrorKey: mirrorKey,
                sourceCalendarID: event.calendarIdentifier,
                sourceCalendarTitle: event.calendarTitle,
                occurrenceStartDate: event.occurrenceStartDate,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                timeZoneIdentifier: event.timeZoneIdentifier,
                title: event.title,
                location: event.location,
                notes: event.notes,
                urlString: event.url?.absoluteString,
                calendarColorHex: event.calendarColorHex,
                visibilityRawValue: EventVisibility.fullDetails.rawValue,
                deletedAt: nil,
                cloudKitRecordName: nil
            )
        }
    }
}

enum EventDetailMirrorResolutionPolicy {
    /// Resolves a possibly-transient display mirror (my own events render as `display:` mirrors,
    /// see `CalendarDisplayMirrorPolicy`) to its persisted twin, matched by the shared `mirrorKey`,
    /// so the detail's comment thread anchors to the real record id and routes writes correctly.
    /// A real mirror resolves to itself; a display mirror with no synced twin yet resolves to nil
    /// (nothing to comment on — and the partner couldn't have commented on an unsynced event).
    static func persistedTwin(for event: EventMirror, in mirrors: [EventMirror]) -> EventMirror? {
        guard event.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix) else {
            return event
        }
        return mirrors.first {
            !$0.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix) && $0.mirrorKey == event.mirrorKey
        }
    }
}
