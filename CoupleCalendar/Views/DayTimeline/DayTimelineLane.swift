import SwiftUI

struct DayTimelineLane: View {
    @Environment(SettingsStore.self) private var settings
    let events: [EventMirror]
    let identity: OurDaysIdentity
    let dayStart: Date
    let hourHeight: CGFloat
    let startHour: Int
    let width: CGFloat
    /// Events that share their time with a joint block and therefore keep only
    /// the outer half of the lane (left half for me, right half for the partner).
    var narrowedEventIDs: Set<String> = []
    let onSelect: (EventMirror) -> Void
    let commentedAnchorKeys: Set<String>
    let persistedMirrorIDByKey: [String: String]

    var offsetY: CGFloat { CGFloat(startHour) * hourHeight }

    private func blockX(isNarrowed: Bool) -> CGFloat {
        guard isNarrowed, identity == .partner else { return 4 }
        return (width / 2) + 4
    }

    private func blockWidth(isNarrowed: Bool) -> CGFloat {
        max(44, (isNarrowed ? width / 2 : width) - 8)
    }

    var dayHeight: CGFloat {
        DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight) - offsetY
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ForEach(events) { event in
                let frame = frame(for: event)
                let eventHeight = min(max(frame.height, 44), dayHeight)
                let eventY = min(frame.y, max(0, dayHeight - eventHeight))
                let isNarrowed = narrowedEventIDs.contains(event.id)

                Button {
                    onSelect(event)
                } label: {
                    DayTimelineEventBlock(
                        event: event,
                        identity: identity,
                        hasComments: EventCommentIndicatorPlan.hasComments(
                            mirror: event,
                            commentedKeys: commentedAnchorKeys,
                            persistedIDByMirrorKey: persistedMirrorIDByKey
                        )
                    )
                }
                .buttonStyle(.plain)
                .frame(width: blockWidth(isNarrowed: isNarrowed), height: eventHeight, alignment: .top)
                .offset(x: blockX(isNarrowed: isNarrowed), y: eventY)
                .accessibilityLabel("\(event.title), \(timeText(for: event))")
            }
        }
        .frame(width: width, height: dayHeight, alignment: .topLeading)
    }

    private func frame(for event: EventMirror) -> DayTimelineEventFrame {
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

    private func timeText(for event: EventMirror) -> String {
        if event.isAllDay {
            return settings.strings.allDay
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

/// Small dot marking a calendar event that has at least one comment. Decorative
/// (`accessibilityHidden`) so it doesn't disturb the buttons' existing accessibility labels;
/// the visibility decision comes from `EventCommentIndicatorPlan`.
struct CommentIndicatorDot: View {
    let isVisible: Bool
    var color: Color = OurDaysTheme.ink
    var ringColor: Color = OurDaysTheme.surface

    var body: some View {
        if isVisible {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(ringColor, lineWidth: 1.5))
                .accessibilityHidden(true)
        }
    }
}

struct DayTimelineEventBlock: View {
    @Environment(SettingsStore.self) private var settings
    let event: EventMirror
    let identity: OurDaysIdentity
    var hasComments: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(OurDaysTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 4) {
                // The source calendar's own color survives as a small dot, so people
                // who share several calendars can still tell them apart.
                if let calendarColor = Color(hex: event.calendarColorHex) {
                    Circle()
                        .fill(calendarColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(timeText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(identity.onTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(identity.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topTrailing) {
            CommentIndicatorDot(isVisible: hasComments, ringColor: identity.tint).padding(6)
        }
    }

    var timeText: String {
        if event.isAllDay {
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct DayTimelineJointEventBlock: View {
    @Environment(SettingsStore.self) private var settings
    let event: JointScheduleEvent
    let isFocused: Bool
    var hasComments: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                HStack(spacing: -3) {
                    Circle().fill(OurDaysIdentity.me.color).frame(width: 8, height: 8)
                    Circle().fill(OurDaysIdentity.partner.color).frame(width: 8, height: 8)
                }
                .accessibilityHidden(true)
                Text(settings.strings.jointScheduleLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.onJointSecondary)
                    .lineLimit(1)
            }

            Text(event.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(OurDaysTheme.onJoint)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(detailText)
                .font(.caption2)
                .foregroundStyle(OurDaysTheme.onJointSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OurDaysTheme.joint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OurDaysIdentity.me.color, lineWidth: isFocused ? 2 : 0)
        )
        .shadow(color: OurDaysTheme.joint.opacity(isFocused ? 0.35 : 0.12), radius: isFocused ? 8 : 3, x: 0, y: 2)
        .overlay(alignment: .topTrailing) {
            CommentIndicatorDot(isVisible: hasComments, color: OurDaysTheme.onJoint, ringColor: OurDaysTheme.joint).padding(7)
        }
    }

    private var detailText: String {
        if let location = event.location, !location.isEmpty {
            return "\(timeText) · \(location)"
        }
        return timeText
    }

    var timeText: String {
        if event.isAllDay {
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}
