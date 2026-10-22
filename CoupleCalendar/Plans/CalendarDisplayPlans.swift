import Foundation

/// One line of "when" for an event detail header: "Jun 16, Tue · 19:30 – 21:30".
enum EventDetailTimePlan {
    static func text(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        strings: ShareCalStrings,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        let dayFormatter = formatter(template: "MMMdEEE", locale: locale, calendar: calendar)
        let timeFormatter = formatter(template: "jmm", locale: locale, calendar: calendar)
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

    private static func formatter(template: String, locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

enum CalendarSharingWindowPlan {
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

enum CalendarMirrorVisibilityPlan {
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
}

enum CalendarSetupGuidancePlan {
    static func step(
        hasCompletedInitialProfilePrompt: Bool,
        currentDisplayName: String,
        authorizationState: CalendarAuthorizationState,
        selectedCalendarIDs: Set<String>,
        pairingStatus: PairingStatus
    ) -> CalendarSetupGuidanceStep? {
        guard hasCompletedInitialProfilePrompt else { return nil }
        guard PairingSettingsPlan.normalizedDisplayName(currentDisplayName) != nil else { return nil }
        guard authorizationState.canReadEvents && !selectedCalendarIDs.isEmpty else {
            return .calendarAccess
        }

        switch pairingStatus {
        case .notPaired, .waitingForYouToShare:
            return .pairing
        case .waitingForPartner, .waitingForPartnerToShare, .paired:
            return nil
        }
    }
}

enum CalendarDisplayMirrorPlan {
    static let transientIDPrefix = "display:"

    static func displayMirrors(
        from events: [CalendarSourceEvent],
        ownerMemberID: String
    ) -> [EventMirror] {
        events.map { event in
            let fingerprint = EventMirrorService.fingerprint(for: event)
            let mirrorKey = EventMirrorService.makeMirrorKey(
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

enum EventDetailMirrorResolutionPlan {
    /// Resolves a possibly-transient display mirror (my own events render as `display:` mirrors,
    /// see `CalendarDisplayMirrorPlan`) to its persisted twin, matched by the shared `mirrorKey`,
    /// so the detail's comment thread anchors to the real record id and routes writes correctly.
    /// A real mirror resolves to itself; a display mirror with no synced twin yet resolves to nil
    /// (nothing to comment on — and the partner couldn't have commented on an unsynced event).
    static func persistedTwin(for event: EventMirror, in mirrors: [EventMirror]) -> EventMirror? {
        guard event.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix) else {
            return event
        }
        return mirrors.first {
            !$0.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix) && $0.mirrorKey == event.mirrorKey
        }
    }
}
