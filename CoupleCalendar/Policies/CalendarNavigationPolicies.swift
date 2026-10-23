import CoreGraphics
import Foundation

struct WeekStripDay: Identifiable, Equatable {
    let date: Date
    let hasMine: Bool
    let hasPartner: Bool
    let hasJoint: Bool

    var id: Date { date }
}

/// The seven days of the selected week, each flagged with whose schedules fall on it,
/// so the week strip can show "who is busy that day" without opening the day.
enum WeekStripPolicy {
    static func days(
        containing selectedDate: Date,
        mine: [DateInterval],
        partner: [DateInterval],
        joint: [DateInterval],
        calendar: Calendar = .current
    ) -> [WeekStripDay] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: week.start)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let day = DateInterval(start: dayStart, end: dayEnd)
            return WeekStripDay(
                date: dayStart,
                hasMine: mine.contains { overlaps($0, day) },
                hasPartner: partner.contains { overlaps($0, day) },
                hasJoint: joint.contains { overlaps($0, day) }
            )
        }
    }

    static func overlaps(_ event: DateInterval, _ day: DateInterval) -> Bool {
        if event.duration == 0 {
            return event.start >= day.start && event.start < day.end
        }
        return event.start < day.end && event.end > day.start
    }
}

enum CalendarNavigationDirection {
    case previous
    case next
}

struct CalendarDateSelectionResult: Equatable {
    let selectedDate: Date
    let mode: CalendarMode
}

enum CalendarDateNavigationPolicy {
    static func date(
        afterMoving selectedDate: Date,
        mode: CalendarMode,
        direction: CalendarNavigationDirection,
        calendar: Calendar = .current
    ) -> Date {
        let value: Int
        let component: Calendar.Component
        switch mode {
        case .day:
            value = direction == .next ? 1 : -1
            component = .day
        case .week:
            value = direction == .next ? 7 : -7
            component = .day
        }
        return calendar.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
    }

    static func selectionResult(for date: Date) -> CalendarDateSelectionResult {
        CalendarDateSelectionResult(selectedDate: date, mode: .day)
    }

    static func title(for selectedDate: Date, mode: CalendarMode, calendar: Calendar = .current) -> String {
        switch mode {
        case .day:
            return selectedDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: selectedDate, duration: 7 * 24 * 60 * 60)
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    static func compactTitle(
        for selectedDate: Date,
        mode: CalendarMode,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        switch mode {
        case .day:
            return monthDayText(for: selectedDate, calendar: calendar, locale: locale)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: selectedDate, duration: 7 * 24 * 60 * 60)
            let weekStart = calendar.startOfDay(for: interval.start)
            let weekEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            if calendar.component(.year, from: weekStart) == calendar.component(.year, from: weekEnd),
               calendar.component(.month, from: weekStart) == calendar.component(.month, from: weekEnd) {
                return "\(monthText(for: weekStart, calendar: calendar, locale: locale)) \(dayText(for: weekStart, calendar: calendar, locale: locale))-\(dayText(for: weekEnd, calendar: calendar, locale: locale))"
            }
            return "\(monthDayText(for: weekStart, calendar: calendar, locale: locale))-\(monthDayText(for: weekEnd, calendar: calendar, locale: locale))"
        }
    }

    private static func monthDayText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        DateFormatterCache.formatter(template: "MMM d", locale: locale, calendar: calendar).string(from: date)
    }

    private static func monthText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        DateFormatterCache.formatter(template: "MMM", locale: locale, calendar: calendar).string(from: date)
    }

    private static func dayText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        String(calendar.component(.day, from: date))
    }
}

enum CalendarSwipeNavigationPolicy {
    static func direction(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        minimumDistance: CGFloat = 50,
        dominanceRatio: CGFloat = 1.5
    ) -> CalendarNavigationDirection? {
        guard abs(horizontalTranslation) >= minimumDistance,
              abs(horizontalTranslation) > abs(verticalTranslation) * dominanceRatio
        else { return nil }
        return horizontalTranslation < 0 ? .next : .previous
    }
}

enum HierarchicalDatePickerLevel: Equatable {
    case month
    case months
    case years
}

struct HierarchicalMonthDay: Identifiable, Equatable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

struct HierarchicalDatePickerNavigation: Equatable {
    let level: HierarchicalDatePickerLevel
    let visibleMonth: Date
    let selectedDate: Date?
}

enum HierarchicalDatePickerPolicy {
    static func normalizedMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [HierarchicalMonthDay] {
        let monthStart = normalizedMonth(containing: date, calendar: calendar)
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart),
              let weekInterval = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start) else {
            return []
        }

        let displayedMonth = calendar.component(.month, from: monthStart)
        return (0..<42).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else {
                return nil
            }
            return HierarchicalMonthDay(
                date: calendar.startOfDay(for: day),
                isInDisplayedMonth: calendar.component(.month, from: day) == displayedMonth
            )
        }
    }

    static func months(inYearContaining date: Date, calendar: Calendar = .current) -> [Date] {
        let year = calendar.component(.year, from: date)
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    static func years(centeredOn date: Date, calendar: Calendar = .current) -> [Date] {
        let currentYear = calendar.component(.year, from: date)
        let firstYear = currentYear - 5
        return (0..<12).compactMap { offset in
            calendar.date(from: DateComponents(year: firstYear + offset, month: 1, day: 1))
        }
    }

    static func selectYear(_ date: Date, calendar: Calendar = .current) -> HierarchicalDatePickerNavigation {
        let year = calendar.component(.year, from: date)
        let visibleMonth = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? date
        return HierarchicalDatePickerNavigation(level: .months, visibleMonth: visibleMonth, selectedDate: nil)
    }

    static func selectMonth(_ date: Date, calendar: Calendar = .current) -> HierarchicalDatePickerNavigation {
        HierarchicalDatePickerNavigation(
            level: .month,
            visibleMonth: normalizedMonth(containing: date, calendar: calendar),
            selectedDate: nil
        )
    }

    static func selectDay(_ date: Date, calendar: Calendar = .current) -> HierarchicalDatePickerNavigation {
        HierarchicalDatePickerNavigation(
            level: .month,
            visibleMonth: normalizedMonth(containing: date, calendar: calendar),
            selectedDate: calendar.startOfDay(for: date)
        )
    }
}
