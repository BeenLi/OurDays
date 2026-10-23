import SwiftUI

struct WeekAgendaView: View {
    let days: [WeekAgendaDay]
    let mirrorByID: [String: EventMirror]
    let onSelect: (EventMirror) -> Void
    let onSelectJoint: (WeekAgendaItem) -> Void
    let commentedAnchorKeys: Set<String>
    let persistedMirrorIDByKey: [String: String]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(days) { day in
                    WeekAgendaDaySection(
                        day: day,
                        mirrorByID: mirrorByID,
                        onSelect: onSelect,
                        onSelectJoint: onSelectJoint,
                        commentedAnchorKeys: commentedAnchorKeys,
                        persistedMirrorIDByKey: persistedMirrorIDByKey
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}

struct WeekAgendaDaySection: View {
    @Environment(SettingsStore.self) private var settings
    let day: WeekAgendaDay
    let mirrorByID: [String: EventMirror]
    let onSelect: (EventMirror) -> Void
    let onSelectJoint: (WeekAgendaItem) -> Void
    let commentedAnchorKeys: Set<String>
    let persistedMirrorIDByKey: [String: String]

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day.date)

        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(settings.appLanguage.locale)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                Text(day.date.formatted(.dateTime.day()))
                    .font(OurDaysTheme.displayFont(24))
                    .foregroundStyle(isToday ? OurDaysTheme.onInkFill : OurDaysTheme.ink)
                    .frame(width: 40, height: 40)
                    .background {
                        if isToday {
                            Circle().fill(OurDaysTheme.inkFill)
                        }
                    }
            }
            .frame(width: 44)

            if day.items.isEmpty {
                Text(settings.strings.noEvents)
                    .font(.footnote)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OurDaysTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .padding(.top, 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(day.items) { item in
                        if let mirrorID = item.mirrorID, let mirror = mirrorByID[mirrorID] {
                            Button {
                                onSelect(mirror)
                            } label: {
                                WeekAgendaItemCard(item: item, hasComments: itemHasComments(item))
                            }
                            .buttonStyle(.plain)
                        } else if item.kind == .joint {
                            // Joint items carry no mirror; their id is the invitation id.
                            // Make them tappable so the shared comment thread opens here too.
                            Button {
                                onSelectJoint(item)
                            } label: {
                                WeekAgendaItemCard(item: item, hasComments: itemHasComments(item))
                            }
                            .buttonStyle(.plain)
                        } else {
                            WeekAgendaItemCard(item: item, hasComments: itemHasComments(item))
                        }
                    }
                }
                .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemHasComments(_ item: WeekAgendaItem) -> Bool {
        if let mirrorID = item.mirrorID, let mirror = mirrorByID[mirrorID] {
            return EventCommentIndicatorPolicy.hasComments(
                mirror: mirror,
                commentedKeys: commentedAnchorKeys,
                persistedIDByMirrorKey: persistedMirrorIDByKey
            )
        }
        if item.kind == .joint {
            // Joint items carry no mirror; their id is the shared invitation id (the anchor).
            return commentedAnchorKeys.contains(item.id)
        }
        return false
    }
}

struct WeekAgendaItemCard: View {
    @Environment(SettingsStore.self) private var settings
    let item: WeekAgendaItem
    var hasComments: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contextLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(item.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(primaryColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(timeText)
                .font(.caption)
                .foregroundStyle(secondaryColor)

            if let location = item.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            CommentIndicatorDot(
                isVisible: hasComments,
                color: item.kind == .joint ? OurDaysTheme.onJoint : OurDaysTheme.ink,
                ringColor: background
            )
            .padding(8)
        }
    }

    private var background: Color {
        switch item.kind {
        case .currentMember: OurDaysIdentity.me.tint
        case .partner: OurDaysIdentity.partner.tint
        case .joint: OurDaysTheme.joint
        }
    }

    private var primaryColor: Color {
        item.kind == .joint ? OurDaysTheme.onJoint : OurDaysTheme.ink
    }

    private var secondaryColor: Color {
        switch item.kind {
        case .currentMember: OurDaysIdentity.me.onTint
        case .partner: OurDaysIdentity.partner.onTint
        case .joint: OurDaysTheme.onJointSecondary
        }
    }

    private var contextLabel: String {
        switch item.kind {
        case .currentMember:
            "\(settings.strings.meTitle) · \(item.calendarTitle)"
        case .partner:
            "\(settings.partnerDisplayName) · \(item.calendarTitle)"
        case .joint:
            settings.strings.jointScheduleLabel
        }
    }

    private var timeText: String {
        if item.isAllDay {
            return settings.strings.allDay
        }
        return "\(item.startDate.formatted(date: .omitted, time: .shortened)) - \(item.endDate.formatted(date: .omitted, time: .shortened))"
    }
}
