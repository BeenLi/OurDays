import CoreGraphics
import Foundation

/// Which hours the day timeline draws. Night hours before the first event of either
/// person are folded into one "both free" band instead of a screen of empty lanes.
enum DayTimelineCollapsePolicy {
    static func visibleStartHour(
        eventStartDates: [Date],
        dayStart: Date,
        now: Date,
        isExpanded: Bool,
        defaultStartHour: Int = DayTimelineScrollTargetPolicy.defaultStartHour,
        calendar: Calendar = .current
    ) -> Int {
        guard !isExpanded else { return 0 }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        var startHour = defaultStartHour
        for startDate in eventStartDates {
            guard startDate < dayEnd else { continue }
            guard startDate > dayStart else { return 0 }
            startHour = min(startHour, calendar.component(.hour, from: startDate))
        }
        if now >= dayStart, now < dayEnd {
            startHour = min(startHour, calendar.component(.hour, from: now))
        }
        return max(0, startHour)
    }
}

struct DayTimelineHourMark: Equatable {
    let hour: Int
    let y: CGFloat
}

struct DayTimelineEventFrame: Equatable {
    let y: CGFloat
    let height: CGFloat
}

struct DayTimelineJointPlacement: Equatable {
    let columnIndex: Int
    let columnCount: Int
}

enum DayTimelineJointLayoutPolicy {
    static func placements(for events: [JointScheduleEvent]) -> [String: DayTimelineJointPlacement] {
        var placements: [String: DayTimelineJointPlacement] = [:]
        let sortedEvents = events.sorted {
            if $0.startDate == $1.startDate {
                return $0.id < $1.id
            }
            return $0.startDate < $1.startDate
        }

        for event in sortedEvents {
            let overlapping = sortedEvents.filter { candidate in
                overlaps(event, candidate)
            }
            let orderedOverlappingIDs = overlapping.map(\.id)
            let columnIndex = orderedOverlappingIDs.firstIndex(of: event.id) ?? 0
            placements[event.id] = DayTimelineJointPlacement(
                columnIndex: columnIndex,
                columnCount: max(1, overlapping.count)
            )
        }

        return placements
    }

    private static func overlaps(_ lhs: JointScheduleEvent, _ rhs: JointScheduleEvent) -> Bool {
        lhs.startDate < rhs.endDate && rhs.startDate < lhs.endDate
    }
}

/// A timed block on the day timeline, reduced to what overlap decisions need.
struct DayTimelineTimedSpan: Equatable {
    let id: String
    let startDate: Date
    let endDate: Date
}

/// How a joint block shares the width of the two lanes with the lane events
/// it overlaps in time. A joint event normally bridges both lanes; when one
/// lane has its own event at the same time, the joint block yields the outer
/// half of that lane so the lane event stays visible beside it.
struct DayTimelineJointSpan: Equatable {
    let yieldsMyLane: Bool
    let yieldsPartnerLane: Bool

    static let full = DayTimelineJointSpan(yieldsMyLane: false, yieldsPartnerLane: false)
}

enum DayTimelineOverlapPolicy {
    static func jointSpans(
        jointEvents: [DayTimelineTimedSpan],
        myEvents: [DayTimelineTimedSpan],
        partnerEvents: [DayTimelineTimedSpan]
    ) -> [String: DayTimelineJointSpan] {
        var spans: [String: DayTimelineJointSpan] = [:]
        for joint in jointEvents {
            spans[joint.id] = DayTimelineJointSpan(
                yieldsMyLane: myEvents.contains { overlaps($0, joint) },
                yieldsPartnerLane: partnerEvents.contains { overlaps($0, joint) }
            )
        }
        return spans
    }

    /// Lane events that must shrink to the outer half of their lane because a
    /// joint block occupies the inner half at the same time.
    static func narrowedLaneEventIDs(
        laneEvents: [DayTimelineTimedSpan],
        jointEvents: [DayTimelineTimedSpan]
    ) -> Set<String> {
        Set(
            laneEvents
                .filter { lane in jointEvents.contains { overlaps(lane, $0) } }
                .map(\.id)
        )
    }

    private static func overlaps(_ lhs: DayTimelineTimedSpan, _ rhs: DayTimelineTimedSpan) -> Bool {
        lhs.startDate < rhs.endDate && rhs.startDate < lhs.endDate
    }
}

enum DayTimelineScrollTargetPolicy {
    static let defaultStartHour = 8
    /// Minutes of context kept visible above the current time / first event
    /// so the target line does not sit flush against the top edge.
    static let leadMinutes = 30

    static func defaultTargetY(hourHeight: CGFloat, startHour: Int = defaultStartHour) -> CGFloat {
        CGFloat(startHour) * hourHeight
    }

    /// Where the day timeline opens when no joint event is focused: at the
    /// current time when the displayed day is today, otherwise at the first
    /// timed event of that day, otherwise at the default morning hour. The
    /// result is in full-day coordinates (0 = 00:00); callers subtract the
    /// folded-night offset themselves.
    static func initialTargetY(
        now: Date,
        dayStart: Date,
        eventStartDates: [Date],
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> CGFloat {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        let pointsPerMinute = hourHeight / 60
        let lead = CGFloat(leadMinutes) * pointsPerMinute
        let dayHeight = DayTimelineLayoutPolicy.dayHeight(hourHeight: hourHeight)

        if now >= dayStart, now < dayEnd {
            let minutesFromStart = now.timeIntervalSince(dayStart) / 60
            return min(max(CGFloat(minutesFromStart) * pointsPerMinute - lead, 0), dayHeight)
        }

        let firstStart = eventStartDates
            .filter { $0 < dayEnd }
            .min()
        if let firstStart {
            let minutesFromStart = max(firstStart.timeIntervalSince(dayStart) / 60, 0)
            return min(max(CGFloat(minutesFromStart) * pointsPerMinute - lead, 0), dayHeight)
        }

        return defaultTargetY(hourHeight: hourHeight)
    }

    static func targetY(
        for event: JointScheduleEvent,
        dayStart: Date,
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> CGFloat {
        guard !event.isAllDay else { return 0 }
        return DayTimelineLayoutPolicy.eventFrame(
            startDate: event.startDate,
            endDate: event.endDate,
            dayStart: dayStart,
            hourHeight: hourHeight,
            calendar: calendar
        ).y
    }
}

/// How an event block lays out its title and time. A block is as tall as its
/// event lasts, so a short event gets the same two lines with tighter padding,
/// and an even shorter one puts them on one line.
enum DayTimelineBlockStyle: Equatable {
    /// Title (up to two lines) on top, time range below, roomy padding.
    case regular
    /// One title line and the time range, packed tight, for short events.
    case compact
    /// Title and time range side by side, for events too short for two lines.
    case singleLine
}

enum DayTimelineLayoutPolicy {
    static let hoursPerDay = 24
    /// Shortest block drawn, just enough for one line of text. Only events
    /// shorter than this many minutes (at 60 pt/hour) are drawn longer than
    /// they are.
    static let minimumBlockHeight: CGFloat = 18
    /// From this height up the title and time fit on two tight lines.
    static let twoLineBlockHeight: CGFloat = 30
    /// From this height up a block gets the roomy regular padding.
    static let regularBlockHeight: CGFloat = 44

    /// The drawn height of a timed block. It follows the event's real
    /// duration, so the block ends where the event ends and the now line
    /// never crosses an event that is already over.
    static func blockHeight(frameHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(max(frameHeight, minimumBlockHeight), availableHeight)
    }

    static func blockStyle(height: CGFloat) -> DayTimelineBlockStyle {
        if height >= regularBlockHeight { return .regular }
        if height >= twoLineBlockHeight { return .compact }
        return .singleLine
    }

    static func dayHeight(hourHeight: CGFloat) -> CGFloat {
        CGFloat(hoursPerDay) * hourHeight
    }

    static func hourMarks(hourHeight: CGFloat) -> [DayTimelineHourMark] {
        (0..<hoursPerDay).map { hour in
            DayTimelineHourMark(hour: hour, y: CGFloat(hour) * hourHeight)
        }
    }

    static func eventFrame(
        startDate: Date,
        endDate: Date,
        dayStart: Date,
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> DayTimelineEventFrame {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        let visibleStart = max(startDate, dayStart)
        let visibleEnd = min(max(endDate, visibleStart), dayEnd)
        let minutesFromStart = visibleStart.timeIntervalSince(dayStart) / 60
        let visibleMinutes = max(visibleEnd.timeIntervalSince(visibleStart) / 60, 15)
        let pointsPerMinute = hourHeight / 60

        return DayTimelineEventFrame(
            y: CGFloat(minutesFromStart) * pointsPerMinute,
            height: CGFloat(visibleMinutes) * pointsPerMinute
        )
    }
}

struct DayTimelineNowIndicator: Equatable {
    let y: CGFloat
    let date: Date
}

/// Computes where (and whether) to draw the "now" line in the day timeline,
/// mirroring `DayTimelineLayoutPolicy`'s points-per-minute math. Returns nil unless
/// `now` falls inside the displayed day `[dayStart, dayStart + 1 day)`, so the
/// indicator only appears when the user is actually looking at today.
enum DayTimelineNowIndicatorPolicy {
    static func indicator(
        now: Date,
        dayStart: Date,
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> DayTimelineNowIndicator? {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)
        guard now >= dayStart, now < dayEnd else { return nil }

        let pointsPerMinute = hourHeight / 60
        let minutesFromStart = now.timeIntervalSince(dayStart) / 60
        let rawY = CGFloat(minutesFromStart) * pointsPerMinute
        let clampedY = min(max(rawY, 0), DayTimelineLayoutPolicy.dayHeight(hourHeight: hourHeight))
        return DayTimelineNowIndicator(y: clampedY, date: now)
    }
}
