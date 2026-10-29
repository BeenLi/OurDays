import XCTest

final class DayTimelineLayoutPolicyTests: XCTestCase {
    func testProvidesTwentyFourAlignedHourMarks() {
        let marks = DayTimelineLayoutPolicy.hourMarks(hourHeight: 60)

        XCTAssertEqual(marks.count, 24)
        XCTAssertEqual(marks.first?.hour, 0)
        XCTAssertEqual(marks.first?.y, 0)
        XCTAssertEqual(marks.last?.hour, 23)
        XCTAssertEqual(marks.last?.y, 23 * 60)
        XCTAssertEqual(DayTimelineLayoutPolicy.dayHeight(hourHeight: 60), 24 * 60)
    }

    func testPositionsEventByMinutesSinceStartOfDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let start = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 30, second: 0, of: dayStart))
        let end = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 45, second: 0, of: dayStart))

        let frame = DayTimelineLayoutPolicy.eventFrame(
            startDate: start,
            endDate: end,
            dayStart: dayStart,
            hourHeight: 48
        )

        XCTAssertEqual(frame.y, 9.5 * 48, accuracy: 0.001)
        XCTAssertEqual(frame.height, 1.25 * 48, accuracy: 0.001)
    }

    func testClampsEventFrameToVisibleDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let start = dayStart.addingTimeInterval(-30 * 60)
        let end = dayStart.addingTimeInterval(90 * 60)

        let frame = DayTimelineLayoutPolicy.eventFrame(
            startDate: start,
            endDate: end,
            dayStart: dayStart,
            hourHeight: 60
        )

        XCTAssertEqual(frame.y, 0, accuracy: 0.001)
        XCTAssertEqual(frame.height, 90, accuracy: 0.001)
    }
}

final class DayTimelineBlockHeightTests: XCTestCase {
    func testShortEventBlockEndsWhereTheEventEnds() throws {
        // 14:55–15:26 at 60 pt/hour: the block must end before a 15:27 now line.
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29)))
        let start = try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 55, second: 0, of: dayStart))
        let end = try XCTUnwrap(calendar.date(bySettingHour: 15, minute: 26, second: 0, of: dayStart))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 15, minute: 27, second: 0, of: dayStart))

        let frame = DayTimelineLayoutPolicy.eventFrame(startDate: start, endDate: end, dayStart: dayStart, hourHeight: 60, calendar: calendar)
        let height = DayTimelineLayoutPolicy.blockHeight(frameHeight: frame.height, availableHeight: 24 * 60)
        let nowY = try XCTUnwrap(DayTimelineNowIndicatorPolicy.indicator(now: now, dayStart: dayStart, hourHeight: 60, calendar: calendar)).y

        XCTAssertEqual(height, 31, accuracy: 0.001)
        XCTAssertLessThan(frame.y + height, nowY)
        XCTAssertEqual(DayTimelineLayoutPolicy.blockStyle(height: height), .compact)
    }

    func testVeryShortEventKeepsOneLineOfHeight() {
        XCTAssertEqual(DayTimelineLayoutPolicy.blockHeight(frameHeight: 15, availableHeight: 1440), DayTimelineLayoutPolicy.minimumBlockHeight)
        XCTAssertEqual(DayTimelineLayoutPolicy.blockHeight(frameHeight: 15, availableHeight: 10), 10)
    }

    func testEventsOfFortyFourMinutesOrMoreUseTheTwoLineLayout() {
        XCTAssertEqual(DayTimelineLayoutPolicy.blockStyle(height: 44), .regular)
        XCTAssertEqual(DayTimelineLayoutPolicy.blockStyle(height: 90), .regular)
        XCTAssertEqual(DayTimelineLayoutPolicy.blockStyle(height: 43), .compact)
    }
}

final class DayTimelineNowIndicatorPolicyTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testPositionsLineByMinutesSinceStartOfDayWhenViewingToday() throws {
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 30, second: 0, of: dayStart))

        let indicator = try XCTUnwrap(
            DayTimelineNowIndicatorPolicy.indicator(now: now, dayStart: dayStart, hourHeight: 48, calendar: calendar)
        )

        XCTAssertEqual(indicator.y, 9.5 * 48, accuracy: 0.001)
        XCTAssertEqual(indicator.date, now)
    }

    func testHidesWhenViewingADifferentDay() throws {
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let nowYesterday = dayStart.addingTimeInterval(-60)
        let nowTomorrow = dayStart.addingTimeInterval(24 * 60 * 60 + 60)

        XCTAssertNil(DayTimelineNowIndicatorPolicy.indicator(now: nowYesterday, dayStart: dayStart, hourHeight: 58, calendar: calendar))
        XCTAssertNil(DayTimelineNowIndicatorPolicy.indicator(now: nowTomorrow, dayStart: dayStart, hourHeight: 58, calendar: calendar))
    }

    func testKeepsLineWithinTheDayAtBoundaries() throws {
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let dayHeight = DayTimelineLayoutPolicy.dayHeight(hourHeight: 58)

        let atMidnight = try XCTUnwrap(
            DayTimelineNowIndicatorPolicy.indicator(now: dayStart, dayStart: dayStart, hourHeight: 58, calendar: calendar)
        )
        XCTAssertEqual(atMidnight.y, 0, accuracy: 0.001)

        let lastMinute = dayStart.addingTimeInterval(24 * 60 * 60 - 60)
        let nearEnd = try XCTUnwrap(
            DayTimelineNowIndicatorPolicy.indicator(now: lastMinute, dayStart: dayStart, hourHeight: 58, calendar: calendar)
        )
        XCTAssertLessThanOrEqual(nearEnd.y, dayHeight)
        XCTAssertGreaterThan(nearEnd.y, 0)
    }
}

final class DayTimelineJointLayoutPolicyTests: XCTestCase {
    func testAssignsOverlappingJointEventsToSeparateColumns() {
        let first = jointEvent(
            id: "first",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000)
        )
        let second = jointEvent(
            id: "second",
            startDate: Date(timeIntervalSince1970: 11_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )
        let third = jointEvent(
            id: "third",
            startDate: Date(timeIntervalSince1970: 13_000),
            endDate: Date(timeIntervalSince1970: 14_000)
        )

        let placements = DayTimelineJointLayoutPolicy.placements(for: [first, second, third])

        XCTAssertEqual(placements["first"], DayTimelineJointPlacement(columnIndex: 0, columnCount: 2))
        XCTAssertEqual(placements["second"], DayTimelineJointPlacement(columnIndex: 1, columnCount: 2))
        XCTAssertEqual(placements["third"], DayTimelineJointPlacement(columnIndex: 0, columnCount: 1))
    }

    private func jointEvent(id: String, startDate: Date, endDate: Date) -> JointScheduleEvent {
        JointScheduleEvent(
            id: id,
            title: id,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: nil,
            notes: nil
        )
    }
}

final class DayTimelineScrollTargetPolicyTests: XCTestCase {
    func testDefaultsInitialScrollTargetToEightAM() {
        let targetY = DayTimelineScrollTargetPolicy.defaultTargetY(hourHeight: 58)

        XCTAssertEqual(targetY, 464, accuracy: 0.001)
    }

    func testTargetsEventStartTimeInsteadOfOffsetLayoutOrigin() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let startDate = dayStart.addingTimeInterval(15 * 60 * 60)
        let event = JointScheduleEvent(
            id: "invite-1",
            title: "Dinner",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            isAllDay: false,
            location: nil,
            notes: nil
        )

        let targetY = DayTimelineScrollTargetPolicy.targetY(
            for: event,
            dayStart: dayStart,
            hourHeight: 58,
            calendar: calendar
        )

        XCTAssertEqual(targetY, 870, accuracy: 0.001)
    }

    func testOpensAtCurrentTimeWithLeadWhenViewingToday() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let now = dayStart.addingTimeInterval(20 * 60 * 60 + 15 * 60) // 20:15

        let targetY = DayTimelineScrollTargetPolicy.initialTargetY(
            now: now,
            dayStart: dayStart,
            eventStartDates: [dayStart.addingTimeInterval(9 * 60 * 60)],
            hourHeight: 60,
            calendar: calendar
        )

        // 20:15 minus the 30-minute lead = 19:45 → 19.75 h × 60 pt.
        XCTAssertEqual(targetY, 1185, accuracy: 0.001)
    }

    func testOpensAtFirstEventWhenViewingAnotherDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let otherDay = dayStart.addingTimeInterval(3 * 24 * 60 * 60)

        let targetY = DayTimelineScrollTargetPolicy.initialTargetY(
            now: otherDay,
            dayStart: dayStart,
            eventStartDates: [
                dayStart.addingTimeInterval(15 * 60 * 60),
                dayStart.addingTimeInterval(13 * 60 * 60),
            ],
            hourHeight: 60,
            calendar: calendar
        )

        // 13:00 minus the 30-minute lead = 12:30.
        XCTAssertEqual(targetY, 750, accuracy: 0.001)
    }

    func testClampsEarlyMorningTargetToTopAndFallsBackToDefaultWithoutEvents() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let otherDay = dayStart.addingTimeInterval(3 * 24 * 60 * 60)

        XCTAssertEqual(
            DayTimelineScrollTargetPolicy.initialTargetY(
                now: otherDay,
                dayStart: dayStart,
                eventStartDates: [dayStart.addingTimeInterval(10 * 60)],
                hourHeight: 60,
                calendar: calendar
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DayTimelineScrollTargetPolicy.initialTargetY(
                now: otherDay,
                dayStart: dayStart,
                eventStartDates: [],
                hourHeight: 60,
                calendar: calendar
            ),
            480,
            accuracy: 0.001
        )
    }
}

final class DayTimelineOverlapPolicyTests: XCTestCase {
    private func span(_ id: String, _ start: TimeInterval, _ end: TimeInterval) -> DayTimelineTimedSpan {
        DayTimelineTimedSpan(
            id: id,
            startDate: Date(timeIntervalSince1970: start),
            endDate: Date(timeIntervalSince1970: end)
        )
    }

    func testJointBlockYieldsOnlyTheLaneWithAnOverlappingEvent() {
        let dinner = span("dinner", 19_000, 21_000)
        let partnerCall = span("call", 19_500, 20_000)
        let myMorning = span("gym", 8_000, 9_000)

        let spans = DayTimelineOverlapPolicy.jointSpans(
            jointEvents: [dinner],
            myEvents: [myMorning],
            partnerEvents: [partnerCall]
        )

        XCTAssertEqual(spans["dinner"], DayTimelineJointSpan(yieldsMyLane: false, yieldsPartnerLane: true))
    }

    func testJointBlockKeepsFullWidthWhenLaneEventsOnlyTouchItsEdges() {
        let dinner = span("dinner", 19_000, 21_000)

        let spans = DayTimelineOverlapPolicy.jointSpans(
            jointEvents: [dinner],
            myEvents: [span("before", 18_000, 19_000)],
            partnerEvents: [span("after", 21_000, 22_000)]
        )

        XCTAssertEqual(spans["dinner"], .full)
    }

    func testOnlyLaneEventsOverlappingAJointBlockAreNarrowed() {
        let narrowed = DayTimelineOverlapPolicy.narrowedLaneEventIDs(
            laneEvents: [span("call", 19_500, 20_000), span("gym", 8_000, 9_000)],
            jointEvents: [span("dinner", 19_000, 21_000)]
        )

        XCTAssertEqual(narrowed, ["call"])
    }
}

final class CalendarDateNavigationPolicyTests: XCTestCase {
    func testMovesByDayOrWeekAndBuildsStripAroundSelectedDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))

        XCTAssertEqual(
            CalendarDateNavigationPolicy.date(afterMoving: selected, mode: .day, direction: .previous, calendar: calendar),
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 6)))
        )
        XCTAssertEqual(
            CalendarDateNavigationPolicy.date(afterMoving: selected, mode: .week, direction: .next, calendar: calendar),
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14)))
        )
    }

    func testSelectingDateFromHierarchySwitchesToDayMode() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))

        let result = CalendarDateNavigationPolicy.selectionResult(for: selected)

        XCTAssertEqual(result.selectedDate, selected)
        XCTAssertEqual(result.mode, .day)
    }

    func testBuildsCompactDayAndWeekTitles() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let locale = Locale(identifier: "en_US_POSIX")
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))

        let dayTitle = CalendarDateNavigationPolicy.compactTitle(
            for: selected,
            mode: .day,
            calendar: calendar,
            locale: locale
        )
        let weekTitle = CalendarDateNavigationPolicy.compactTitle(
            for: selected,
            mode: .week,
            calendar: calendar,
            locale: locale
        )

        XCTAssertEqual(dayTitle, "Sep 25")
        XCTAssertEqual(weekTitle, "Sep 21-27")
    }
}

final class CalendarSwipeNavigationPolicyTests: XCTestCase {
    func testLeftSwipeMovesToNextAndRightSwipeMovesToPrevious() {
        XCTAssertEqual(
            CalendarSwipeNavigationPolicy.direction(horizontalTranslation: -80, verticalTranslation: 10),
            .next
        )
        XCTAssertEqual(
            CalendarSwipeNavigationPolicy.direction(horizontalTranslation: 80, verticalTranslation: -10),
            .previous
        )
    }

    func testMostlyVerticalDragDoesNotNavigate() {
        XCTAssertNil(
            CalendarSwipeNavigationPolicy.direction(horizontalTranslation: -60, verticalTranslation: 50)
        )
    }

    func testDragShorterThanMinimumDistanceDoesNotNavigate() {
        XCTAssertNil(
            CalendarSwipeNavigationPolicy.direction(horizontalTranslation: -30, verticalTranslation: 0)
        )
    }
}

final class HierarchicalDatePickerPolicyTests: XCTestCase {
    func testMonthGridIncludesLeadingAndTrailingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))

        let days = HierarchicalDatePickerPolicy.monthGrid(containing: month, calendar: calendar)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.date, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31))))
        XCTAssertEqual(days.first { $0.isInDisplayedMonth }?.date, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))))
    }

    func testMonthAndYearSelectionNavigateWithoutProducingDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let visibleMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let selectedYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 1)))
        let selectedMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 11, day: 1)))

        let yearNavigation = HierarchicalDatePickerPolicy.selectYear(selectedYear, calendar: calendar)
        let monthNavigation = HierarchicalDatePickerPolicy.selectMonth(selectedMonth, calendar: calendar)
        let days = HierarchicalDatePickerPolicy.months(inYearContaining: visibleMonth, calendar: calendar)

        XCTAssertEqual(yearNavigation.level, .months)
        XCTAssertEqual(calendar.component(.year, from: yearNavigation.visibleMonth), 2030)
        XCTAssertNil(yearNavigation.selectedDate)
        XCTAssertEqual(monthNavigation.level, .month)
        XCTAssertEqual(calendar.component(.month, from: monthNavigation.visibleMonth), 11)
        XCTAssertNil(monthNavigation.selectedDate)
        XCTAssertEqual(days.count, 12)
    }
}

final class WeekAgendaPolicyTests: XCTestCase {
    func testBuildsSevenDayAgendaAndSortsMixedItemsByTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let myEvent = eventMirror(
            id: "me-late",
            ownerMemberID: "me",
            title: "Late",
            startDate: monday.addingTimeInterval(15 * 60 * 60),
            endDate: monday.addingTimeInterval(16 * 60 * 60)
        )
        let partnerEvent = eventMirror(
            id: "partner-early",
            ownerMemberID: "partner",
            title: "Early",
            startDate: monday.addingTimeInterval(9 * 60 * 60),
            endDate: monday.addingTimeInterval(10 * 60 * 60)
        )
        let jointEvent = JointScheduleEvent(
            id: "joint-mid",
            title: "Together",
            startDate: monday.addingTimeInterval(12 * 60 * 60),
            endDate: monday.addingTimeInterval(13 * 60 * 60),
            isAllDay: false,
            location: nil,
            notes: nil
        )

        let days = WeekAgendaPolicy.days(
            containing: selected,
            mirrors: [myEvent, partnerEvent],
            jointEvents: [jointEvent],
            currentMemberID: "me",
            calendar: calendar
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days[0].date, monday)
        XCTAssertEqual(days[0].items.map(\.title), ["Early", "Together", "Late"])
        XCTAssertEqual(days[0].items.map(\.kind), [.partner, .joint, .currentMember])
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: id
        )
    }
}

final class EventTimeRangeTextPolicyTests: XCTestCase {
    func testAllDayUsesLocalizedLabelAndTimedEventsShowStartEnd() {
        let strings = ShareCalStrings(language: .english)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 4_600)

        XCTAssertEqual(
            EventTimeRangeTextPolicy.text(startDate: start, endDate: end, isAllDay: true, strings: strings),
            strings.allDay
        )
        XCTAssertEqual(
            EventTimeRangeTextPolicy.text(startDate: start, endDate: end, isAllDay: false, strings: strings),
            "\(start.formatted(date: .omitted, time: .shortened)) - \(end.formatted(date: .omitted, time: .shortened))"
        )
    }
}

final class DateFormatterCacheTests: XCTestCase {
    func testReusesFormatterForSameConfigurationAndSeparatesDifferentOnes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let english = Locale(identifier: "en_US")
        let chinese = Locale(identifier: "zh_Hans")

        let first = DateFormatterCache.formatter(template: "MMM d", locale: english, calendar: calendar)
        let second = DateFormatterCache.formatter(template: "MMM d", locale: english, calendar: calendar)
        let other = DateFormatterCache.formatter(template: "MMM d", locale: chinese, calendar: calendar)
        let fixed = DateFormatterCache.formatter(dateFormat: "yyyy年M月d日", locale: chinese, calendar: calendar)

        XCTAssertTrue(first === second)
        XCTAssertFalse(first === other)
        XCTAssertEqual(first.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(fixed.string(from: Date(timeIntervalSince1970: 0)), "1970年1月1日")
    }
}
