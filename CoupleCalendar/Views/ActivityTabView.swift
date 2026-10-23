import SwiftData
import SwiftUI

struct ActivityTabView: View {
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @State private var selectedEvent: EventMirror?
    @State private var selectedJointEvent: JointScheduleEvent?
    @State private var seenSnapshot: Date?

    private var items: [ActivityFeedItem] {
        ActivityFeedPolicy.items(
            comments: comments,
            mirrors: mirrors,
            invitations: invitations,
            currentMemberID: settings.currentMemberID,
            lastSeenActivityAt: seenSnapshot
        )
    }

    var body: some View {
        let strings = settings.strings
        List {
            OurDaysPageHeader(title: strings.activityTitle, subtitle: strings.activitySubtitle)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            if items.isEmpty {
                ContentUnavailableView(
                    strings.activityEmptyTitle,
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(strings.activityEmptyMessage)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(ActivityFeedSectionPolicy.sections(items)) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                open(item)
                            } label: {
                                ActivityFeedRow(
                                    item: item,
                                    authorName: authorName(for: item),
                                    contextText: contextText(for: item),
                                    contextIdentity: contextIdentity(for: item)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    } header: {
                        OurDaysSectionLabel(title: sectionTitle(for: section.dayStart))
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .ourDaysListBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .sheet(item: $selectedJointEvent) { jointEvent in
            if let invitation = invitations.first(where: { $0.id == jointEvent.id }) {
                JointEventDetailView(event: jointEvent, invitation: invitation)
            }
        }
        .onAppear(perform: markActivitySeen)
    }

    /// A feed row maps to either a regular event (mirror) or a joint event (invitation);
    /// open the matching detail. Mirrors the anchor resolution in `ActivityFeedPolicy`.
    private func open(_ item: ActivityFeedItem) {
        if let mirror = mirror(for: item.eventMirrorID) {
            selectedEvent = mirror
        } else if let invitation = invitations.first(where: { $0.id == item.eventMirrorID }) {
            selectedJointEvent = JointScheduleEvent(
                id: invitation.id,
                title: invitation.title,
                startDate: invitation.startDate,
                endDate: invitation.endDate,
                isAllDay: invitation.isAllDay,
                location: invitation.location,
                notes: invitation.notes
            )
        }
    }

    /// Snapshot the previous last-seen time (so this visit still highlights what was
    /// unread), then advance the stored marker to now so the tab badge clears.
    private func markActivitySeen() {
        seenSnapshot = settings.lastSeenActivityAt
        settings.lastSeenActivityAt = .now
    }

    private func mirror(for id: String) -> EventMirror? {
        mirrors.first { $0.id == id }
    }

    private func sectionTitle(for dayStart: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(dayStart) { return settings.strings.todaySectionTitle }
        if calendar.isDateInYesterday(dayStart) { return settings.strings.yesterdaySectionTitle }
        return dayStart.formatted(.dateTime.month().day().weekday(.abbreviated).locale(settings.appLanguage.locale))
    }

    /// nil = a joint event; otherwise whose event the thread hangs off.
    private func contextIdentity(for item: ActivityFeedItem) -> OurDaysIdentity? {
        guard let mirror = mirror(for: item.eventMirrorID) else { return nil }
        return mirror.ownerMemberID == settings.currentMemberID ? .me : .partner
    }

    private func contextText(for item: ActivityFeedItem) -> String {
        let strings = settings.strings
        let owner: String
        let startDate: Date?
        if let mirror = mirror(for: item.eventMirrorID) {
            owner = mirror.ownerMemberID == settings.currentMemberID
                ? strings.myScheduleLabel
                : strings.partnerScheduleLabel(settings.partnerDisplayName)
            startDate = mirror.startDate
        } else {
            owner = strings.jointScheduleLabel
            startDate = invitations.first(where: { $0.id == item.eventMirrorID })?.startDate
        }
        var parts = [owner]
        if let startDate {
            parts.append(startDate.formatted(.dateTime.month().day().hour().minute().locale(settings.appLanguage.locale)))
        }
        parts.append(strings.commentCountText(item.commentCount))
        return parts.joined(separator: " · ")
    }

    private func authorName(for item: ActivityFeedItem) -> String {
        MemberDisplayNamePolicy.displayName(
            forMemberID: item.latestCommentAuthorMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }
}

private struct ActivityFeedRow: View {
    let item: ActivityFeedItem
    let authorName: String
    let contextText: String
    let contextIdentity: OurDaysIdentity?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MemberAvatarForID(memberID: item.latestCommentAuthorMemberID, size: 36)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.eventTitle)
                        .font(.subheadline.weight(item.hasUnread ? .bold : .semibold))
                        .foregroundStyle(OurDaysTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.latestCommentAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                    if item.hasUnread {
                        Circle()
                            .fill(OurDaysTheme.ink)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(item.latestCommentBody)
                    .font(.subheadline)
                    .foregroundStyle(item.hasUnread ? OurDaysTheme.ink : OurDaysTheme.secondaryInk)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        OurDaysTheme.paper,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 4,
                            bottomLeadingRadius: 14,
                            bottomTrailingRadius: 14,
                            topTrailingRadius: 14,
                            style: .continuous
                        )
                    )

                HStack(spacing: 6) {
                    if let contextIdentity {
                        Circle().fill(contextIdentity.color).frame(width: 7, height: 7)
                    } else {
                        Capsule().fill(OurDaysTheme.joint).frame(width: 10, height: 7)
                    }
                    Text(contextText)
                        .font(.caption)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .ourDaysCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.eventTitle), \(authorName): \(item.latestCommentBody)")
    }
}
