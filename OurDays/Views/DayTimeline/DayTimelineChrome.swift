import SwiftUI

struct DayTimelineHeader: View {
    @Environment(SettingsStore.self) private var settings
    let railWidth: CGFloat
    let railSpacing: CGFloat
    let laneSpacing: CGFloat
    let laneWidth: CGFloat
    let myTitle: String
    let myCount: Int
    let partnerTitle: String
    let partnerCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: railSpacing) {
            Color.clear
                .frame(width: railWidth, height: 1)

            HStack(alignment: .center, spacing: laneSpacing) {
                DayTimelineColumnHeader(
                    title: myTitle,
                    count: myCount,
                    identity: .me,
                    width: laneWidth
                )

                DayTimelineColumnHeader(
                    title: partnerTitle,
                    count: partnerCount,
                    identity: .partner,
                    width: laneWidth
                )
            }
        }
    }
}

struct DayTimelineColumnHeader: View {
    @Environment(SettingsStore.self) private var settings
    let title: String
    let count: Int
    let identity: OurDaysIdentity
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            switch identity {
            case .me:
                MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: 28)
            case .partner:
                MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: 28)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(OurDaysTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 4)
            Text(settings.strings.laneEventCountText(count))
                .font(.caption.weight(.bold))
                .foregroundStyle(identity.onTint)
        }
        .padding(.horizontal, 4)
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DayTimelineHourRail: View {
    let hourHeight: CGFloat
    let startHour: Int
    let width: CGFloat

    var body: some View {
        let offsetY = CGFloat(startHour) * hourHeight
        ZStack(alignment: .topTrailing) {
            ForEach(DayTimelineLayoutPolicy.hourMarks(hourHeight: hourHeight).filter { $0.hour >= startHour }, id: \.hour) { mark in
                Text(String(format: "%02d:00", mark.hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .offset(y: max(0, mark.y - offsetY - 7))
            }
        }
        .frame(width: width, height: DayTimelineLayoutPolicy.dayHeight(hourHeight: hourHeight) - offsetY, alignment: .topTrailing)
    }
}

/// The "now" line + time chip drawn over the day timeline. `TimelineView(.everyMinute)`
/// refreshes it cheaply while visible; `DayTimelineNowIndicatorPolicy` returns nil (hiding
/// it) unless the displayed day is today. Non-interactive so it never blocks taps.
struct DayTimelineNowIndicatorOverlay: View {
    let dayStart: Date
    let hourHeight: CGFloat
    let offsetY: CGFloat
    let visibleHeight: CGFloat
    let railWidth: CGFloat
    let railSpacing: CGFloat
    let contentWidth: CGFloat

    var body: some View {
        let lineX = railWidth + railSpacing

        TimelineView(.everyMinute) { context in
            if let indicator = DayTimelineNowIndicatorPolicy.indicator(
                now: context.date,
                dayStart: dayStart,
                hourHeight: hourHeight
            ), indicator.y >= offsetY {
                let y = indicator.y - offsetY
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(OurDaysTheme.ink)
                        .frame(width: max(0, contentWidth - lineX + 4), height: 2)
                        .offset(x: lineX - 4, y: y - 1)

                    Text(indicator.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(OurDaysTheme.onInkFill)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .frame(width: railWidth + 2, height: 18)
                        .background(OurDaysTheme.inkFill, in: Capsule())
                        .offset(x: -2, y: y - 9)
                }
                .frame(width: contentWidth, height: visibleHeight, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

struct DayTimelineHourGrid: View {
    let hourHeight: CGFloat
    let startHour: Int
    let railWidth: CGFloat
    let railSpacing: CGFloat
    let contentWidth: CGFloat

    var body: some View {
        let offsetY = CGFloat(startHour) * hourHeight
        ZStack(alignment: .topLeading) {
            ForEach(DayTimelineLayoutPolicy.hourMarks(hourHeight: hourHeight).filter { $0.hour > startHour }, id: \.hour) { mark in
                Rectangle()
                    .fill(OurDaysTheme.hairline)
                    .frame(width: contentWidth - railWidth - railSpacing, height: 1)
                    .offset(x: railWidth + railSpacing, y: mark.y - offsetY)
            }
        }
        .frame(width: contentWidth, height: DayTimelineLayoutPolicy.dayHeight(hourHeight: hourHeight) - offsetY, alignment: .topLeading)
    }
}
