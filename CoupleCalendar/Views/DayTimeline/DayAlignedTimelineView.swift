import SwiftUI

struct DayAlignedTimelineView: View {
    @Environment(SettingsStore.self) private var settings
    let dayStart: Date
    let myTitle: String
    let myEvents: [EventMirror]
    let jointEvents: [JointScheduleEvent]
    let focusedJointEventID: String?
    let partnerTitle: String
    let partnerEvents: [EventMirror]
    @Binding var isNightExpanded: Bool
    let availableWidth: CGFloat
    let onSelect: (EventMirror) -> Void
    let onSelectJoint: (JointScheduleEvent) -> Void
    let commentedAnchorKeys: Set<String>
    let persistedMirrorIDByKey: [String: String]

    private let hourHeight: CGFloat = 60
    private let railWidth: CGFloat = 40
    private let railSpacing: CGFloat = 6
    private let laneSpacing: CGFloat = 6
    private let horizontalPadding: CGFloat = 12

    private var timedEventStartDates: [Date] {
        myEvents.filter { !$0.isAllDay }.map(\.startDate)
            + partnerEvents.filter { !$0.isAllDay }.map(\.startDate)
            + jointEvents.filter { !$0.isAllDay }.map(\.startDate)
    }

    /// First hour drawn; the hours before it fold into the "both free" band.
    func startHour(isExpanded: Bool) -> Int {
        DayTimelineCollapsePlan.visibleStartHour(
            eventStartDates: timedEventStartDates,
            dayStart: dayStart,
            now: .now,
            isExpanded: isExpanded
        )
    }

    // All-day blocks are drawn as a one-hour band at the top of the day, so
    // for overlap purposes they occupy that same band.
    private func timedSpan(id: String, startDate: Date, endDate: Date, isAllDay: Bool) -> DayTimelineTimedSpan {
        if isAllDay {
            return DayTimelineTimedSpan(id: id, startDate: dayStart, endDate: dayStart.addingTimeInterval(60 * 60))
        }
        return DayTimelineTimedSpan(id: id, startDate: startDate, endDate: endDate)
    }

    private func timedSpans(_ events: [EventMirror]) -> [DayTimelineTimedSpan] {
        events.map { timedSpan(id: $0.id, startDate: $0.startDate, endDate: $0.endDate, isAllDay: $0.isAllDay) }
    }

    private var jointTimedSpans: [DayTimelineTimedSpan] {
        jointEvents.map { timedSpan(id: $0.id, startDate: $0.startDate, endDate: $0.endDate, isAllDay: $0.isAllDay) }
    }

    var visibleStartHour: Int { startHour(isExpanded: isNightExpanded) }

    var offsetY: CGFloat { CGFloat(visibleStartHour) * hourHeight }

    var dayHeight: CGFloat {
        DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight) - offsetY
    }

    var laneWidth: CGFloat {
        let available = availableWidth - (horizontalPadding * 2) - railWidth - railSpacing - laneSpacing
        return max(138, available / 2)
    }

    var contentWidth: CGFloat {
        railWidth + railSpacing + (laneWidth * 2) + laneSpacing
    }

    var body: some View {
        let collapsedStartHour = startHour(isExpanded: false)

        VStack(spacing: 8) {
            DayTimelineHeader(
                railWidth: railWidth,
                railSpacing: railSpacing,
                laneSpacing: laneSpacing,
                laneWidth: laneWidth,
                myTitle: myTitle,
                myCount: myEvents.count,
                partnerTitle: partnerTitle,
                partnerCount: partnerEvents.count
            )
            .padding(.horizontal, horizontalPadding)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 8) {
                        if collapsedStartHour > 0 {
                            nightBand(collapsedStartHour: collapsedStartHour)
                        }

                        ZStack(alignment: .topLeading) {
                            let jointPlacements = DayTimelineJointLayoutPlan.placements(for: jointEvents)
                            let mySpans = timedSpans(myEvents)
                            let partnerSpans = timedSpans(partnerEvents)
                            let jointSpans = DayTimelineOverlapPlan.jointSpans(
                                jointEvents: jointTimedSpans,
                                myEvents: mySpans,
                                partnerEvents: partnerSpans
                            )
                            let narrowedMyEventIDs = DayTimelineOverlapPlan.narrowedLaneEventIDs(
                                laneEvents: mySpans,
                                jointEvents: jointTimedSpans
                            )
                            let narrowedPartnerEventIDs = DayTimelineOverlapPlan.narrowedLaneEventIDs(
                                laneEvents: partnerSpans,
                                jointEvents: jointTimedSpans
                            )

                            // Paper-white lane sheets sit under the hour lines; events sit on top.
                            HStack(spacing: laneSpacing) {
                                ForEach(0..<2, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(OurDaysTheme.surface)
                                        .frame(width: laneWidth, height: dayHeight)
                                }
                            }
                            .offset(x: railWidth + railSpacing)

                            DayTimelineHourGrid(
                                hourHeight: hourHeight,
                                startHour: visibleStartHour,
                                railWidth: railWidth,
                                railSpacing: railSpacing,
                                contentWidth: contentWidth
                            )
                            .allowsHitTesting(false)

                            HStack(alignment: .top, spacing: railSpacing) {
                                DayTimelineHourRail(hourHeight: hourHeight, startHour: visibleStartHour, width: railWidth)

                                HStack(alignment: .top, spacing: laneSpacing) {
                                    DayTimelineLane(
                                        events: myEvents,
                                        identity: .me,
                                        dayStart: dayStart,
                                        hourHeight: hourHeight,
                                        startHour: visibleStartHour,
                                        width: laneWidth,
                                        narrowedEventIDs: narrowedMyEventIDs,
                                        onSelect: onSelect,
                                        commentedAnchorKeys: commentedAnchorKeys,
                                        persistedMirrorIDByKey: persistedMirrorIDByKey
                                    )

                                    DayTimelineLane(
                                        events: partnerEvents,
                                        identity: .partner,
                                        dayStart: dayStart,
                                        hourHeight: hourHeight,
                                        startHour: visibleStartHour,
                                        width: laneWidth,
                                        narrowedEventIDs: narrowedPartnerEventIDs,
                                        onSelect: onSelect,
                                        commentedAnchorKeys: commentedAnchorKeys,
                                        persistedMirrorIDByKey: persistedMirrorIDByKey
                                    )
                                }
                            }

                            defaultScrollMarker()

                            ForEach(jointEvents) { event in
                                jointScrollMarker(for: event)
                            }

                            ForEach(jointEvents) { event in
                                let frame = frame(for: event)
                                let eventHeight = min(max(frame.height, 44), dayHeight)
                                let eventY = min(frame.y, max(0, dayHeight - eventHeight))
                                // A joint block bridges both lanes, but yields the outer half of
                                // a lane whose own event runs at the same time, so that event
                                // stays visible beside it instead of underneath it.
                                let span = jointSpans[event.id] ?? .full
                                let leadingInset = span.yieldsMyLane ? laneWidth / 2 : 0
                                let trailingInset = span.yieldsPartnerLane ? laneWidth / 2 : 0
                                let jointWidth = (laneWidth * 2) + laneSpacing - leadingInset - trailingInset
                                let placement = jointPlacements[event.id] ?? DayTimelineJointPlacement(columnIndex: 0, columnCount: 1)
                                let slotWidth = max(44, (jointWidth - 8) / CGFloat(placement.columnCount))

                                // A Button (not .onTapGesture) so the joint block hit-tests as
                                // reliably as the regular lane events in DayTimelineLane.
                                Button {
                                    onSelectJoint(event)
                                } label: {
                                    DayTimelineJointEventBlock(
                                        event: event,
                                        isFocused: event.id == focusedJointEventID,
                                        hasComments: EventCommentIndicatorPlan.hasComments(
                                            jointEvent: event,
                                            commentedKeys: commentedAnchorKeys
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(44, slotWidth - 4), height: eventHeight, alignment: .top)
                                .offset(
                                    x: railWidth + railSpacing + leadingInset + 4 + (CGFloat(placement.columnIndex) * slotWidth),
                                    y: eventY
                                )
                                .accessibilityLabel("\(event.title), \(EventTimeRangeTextPlan.text(for: event, strings: settings.strings)), \(event.calendarTitle), \(settings.strings.jointScheduleLabel)")
                            }

                            DayTimelineNowIndicatorOverlay(
                                dayStart: dayStart,
                                hourHeight: hourHeight,
                                offsetY: offsetY,
                                visibleHeight: dayHeight,
                                railWidth: railWidth,
                                railSpacing: railSpacing,
                                contentWidth: contentWidth
                            )
                        }
                        .frame(width: contentWidth, height: dayHeight, alignment: .topLeading)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    scrollToInitialTimelinePosition(with: proxy)
                }
                .onChange(of: focusedJointEventID) { _, _ in
                    scrollToInitialTimelinePosition(with: proxy)
                }
                .onChange(of: dayStart) { _, _ in
                    scrollToInitialTimelinePosition(with: proxy)
                }
            }
        }
    }

    /// The folded night hours. Tapping it unfolds 00:00 onward (and folds it back).
    private func nightBand(collapsedStartHour: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isNightExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isNightExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                Text(settings.strings.nightCollapsedLabel(untilHour: collapsedStartHour))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(OurDaysTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OurDaysTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, railWidth + railSpacing)
        .frame(width: contentWidth)
        .accessibilityIdentifier("timeline-night-band")
    }

    private func frame(for event: JointScheduleEvent) -> DayTimelineEventFrame {
        if event.isAllDay {
            return DayTimelineEventFrame(y: 0, height: hourHeight)
        }

        let frame = DayTimelineLayoutPlan.eventFrame(
            startDate: event.startDate,
            endDate: event.endDate,
            dayStart: dayStart,
            hourHeight: hourHeight
        )
        return DayTimelineEventFrame(y: max(0, frame.y - offsetY), height: frame.height)
    }

    private func jointScrollID(for eventID: String) -> String {
        "joint-\(eventID)"
    }

    private var defaultScrollID: String {
        "timeline-initial-target"
    }

    private func scrollToInitialTimelinePosition(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                if let focusedJointEventID {
                    proxy.scrollTo(jointScrollID(for: focusedJointEventID), anchor: .center)
                } else {
                    proxy.scrollTo(defaultScrollID, anchor: .top)
                }
            }
        }
    }

    /// Marks where the timeline opens: the current time on today, otherwise
    /// the day's first event, otherwise 08:00 (`DayTimelineScrollTargetPlan`).
    private func defaultScrollMarker() -> some View {
        let targetY = DayTimelineScrollTargetPlan.initialTargetY(
            now: .now,
            dayStart: dayStart,
            eventStartDates: timedEventStartDates,
            hourHeight: hourHeight
        ) - offsetY

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, targetY))
            Color.clear
                .frame(width: 1, height: 1)
                .id(defaultScrollID)
            Spacer(minLength: 0)
        }
        .frame(width: 1, height: dayHeight, alignment: .top)
        .allowsHitTesting(false)
    }

    private func jointScrollMarker(for event: JointScheduleEvent) -> some View {
        let targetY = DayTimelineScrollTargetPlan.targetY(
            for: event,
            dayStart: dayStart,
            hourHeight: hourHeight
        ) - offsetY

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: max(0, targetY))
            Color.clear
                .frame(width: 1, height: 1)
                .id(jointScrollID(for: event.id))
            Spacer(minLength: 0)
        }
        .frame(width: 1, height: dayHeight, alignment: .top)
        .allowsHitTesting(false)
    }
}
