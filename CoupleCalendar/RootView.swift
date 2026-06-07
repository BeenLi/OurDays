import CloudKit
import SwiftData
import SwiftUI

enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"

    var id: String { rawValue }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @State private var isSyncingAcceptedShare = false

    var body: some View {
        TabView {
            NavigationStack {
                CalendarTabView()
            }
            .tabItem {
                Label("Calendar", systemImage: "calendar")
            }

            NavigationStack {
                InvitesTabView()
            }
            .tabItem {
                Label("Invites", systemImage: "envelope")
            }

            NavigationStack {
                SettingsTabView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .task {
            await syncAfterAcceptedShareIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShareCalAcceptedShareSignal.notificationName)) { _ in
            Task {
                await syncAfterAcceptedShareIfNeeded()
            }
        }
    }

    @MainActor
    private func syncAfterAcceptedShareIfNeeded() async {
        guard !isSyncingAcceptedShare else { return }
        guard ShareCalAcceptedShareSignal.consumePending() else { return }

        isSyncingAcceptedShare = true
        defer { isSyncingAcceptedShare = false }

        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
    }
}

struct CalendarTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @State private var selectedDate = Date()
    @State private var mode: CalendarMode = .day
    @State private var selectedEvent: EventMirror?

    var activeMirrors: [EventMirror] {
        mirrors.filter { $0.deletedAt == nil }
    }

    var visibleMirrors: [EventMirror] {
        activeMirrors.filter { mirror in
            visibleInterval.contains(mirror.startDate)
        }
    }

    var myEvents: [EventMirror] {
        visibleMirrors.filter { $0.ownerMemberID == settings.currentMemberID }
    }

    var partnerEvents: [EventMirror] {
        visibleMirrors.filter { $0.ownerMemberID != settings.currentMemberID }
    }

    var selectedDayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    var visibleInterval: DateInterval {
        let calendar = Calendar.current
        switch mode {
        case .day:
            let start = selectedDayStart
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? selectedDate
            return DateInterval(start: start, end: end)
        case .week:
            let components = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            return components ?? DateInterval(start: selectedDate, duration: 7 * 24 * 60 * 60)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            DateStrip(selectedDate: $selectedDate)

            Picker("Mode", selection: $mode) {
                ForEach(CalendarMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            SyncStatusBar()

            if activeMirrors.isEmpty {
                ShareCalEmptyState {
                    loadReviewSampleData()
                }
                .padding(.horizontal)
                .frame(maxHeight: .infinity, alignment: .center)
            } else {
                GeometryReader { proxy in
                    switch mode {
                    case .day:
                        DayAlignedTimelineView(
                            dayStart: selectedDayStart,
                            myTitle: "Me",
                            mySubtitle: settings.currentMemberID,
                            myEvents: myEvents,
                            partnerTitle: "Partner",
                            partnerSubtitle: settings.partnerMemberID,
                            partnerEvents: partnerEvents,
                            availableWidth: proxy.size.width,
                            onSelect: { selectedEvent = $0 }
                        )
                    case .week:
                        ScrollView {
                            TwoColumnTimelineList(
                                myTitle: "Me",
                                mySubtitle: settings.currentMemberID,
                                myEvents: myEvents,
                                partnerTitle: "Partner",
                                partnerSubtitle: settings.partnerMemberID,
                                partnerEvents: partnerEvents,
                                availableWidth: proxy.size.width,
                                onSelect: { selectedEvent = $0 }
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
        }
        .navigationTitle("ShareCal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        let coordinator = SyncCoordinator(
                            calendarAccess: services.calendarAccess,
                            eventMirrorService: services.eventMirrorService,
                            cloudKit: services.cloudKitIfAvailable
                        )
                        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel("Sync")
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
    }

    private func loadReviewSampleData() {
        selectedDate = Date()
        if activeMirrors.contains(where: { $0.sourceCalendarID == ShareCalReviewSampleData.sourceCalendarID }) {
            return
        }

        let sample = ShareCalReviewSampleData.build(
            currentMemberID: settings.currentMemberID,
            partnerMemberID: settings.partnerMemberID
        )
        sample.mirrors.forEach(modelContext.insert)
        sample.invitations.forEach(modelContext.insert)
        sample.comments.forEach(modelContext.insert)
        try? modelContext.save()
    }
}

struct ShareCalEmptyState: View {
    let onLoadSampleData: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No shared schedules", systemImage: "calendar.badge.plus")
        } description: {
            Text("Preview a paired schedule or choose calendars in Settings.")
        } actions: {
            Button("Load Sample Schedule", action: onLoadSampleData)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct DateStrip: View {
    @Binding var selectedDate: Date

    var dates: [Date] {
        let calendar = Calendar.current
        return (-3...3).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dates, id: \.self) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 4) {
                            Text(date, format: .dateTime.weekday(.abbreviated))
                                .font(.caption2)
                            Text(date, format: .dateTime.day())
                                .font(.headline)
                        }
                        .frame(width: 52, height: 56)
                        .foregroundStyle(isSelected ? .white : .primary)
                        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

struct SyncStatusBar: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal)
    }

    var color: Color {
        switch settings.syncPhase {
        case .idle: settings.lastSyncError == nil ? .green : .orange
        case .syncing: .blue
        case .failed: .red
        }
    }

    var statusText: String {
        if settings.syncPhase == .syncing {
            return "Syncing selected calendars..."
        }
        if let error = settings.lastSyncError {
            return error
        }
        if let lastSyncAt = settings.lastSyncAt {
            return "Last sync \(lastSyncAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Not synced yet"
    }
}

struct TwoColumnTimelineList: View {
    let myTitle: String
    let mySubtitle: String
    let myEvents: [EventMirror]
    let partnerTitle: String
    let partnerSubtitle: String
    let partnerEvents: [EventMirror]
    let availableWidth: CGFloat
    let onSelect: (EventMirror) -> Void

    var columnWidth: CGFloat {
        max(160, (availableWidth - 30) / 2)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TimelineColumn(
                title: myTitle,
                subtitle: mySubtitle,
                events: myEvents,
                tint: .blue,
                width: columnWidth,
                onSelect: onSelect
            )

            TimelineColumn(
                title: partnerTitle,
                subtitle: partnerSubtitle,
                events: partnerEvents,
                tint: .pink,
                width: columnWidth,
                onSelect: onSelect
            )
        }
    }
}

struct DayAlignedTimelineView: View {
    let dayStart: Date
    let myTitle: String
    let mySubtitle: String
    let myEvents: [EventMirror]
    let partnerTitle: String
    let partnerSubtitle: String
    let partnerEvents: [EventMirror]
    let availableWidth: CGFloat
    let onSelect: (EventMirror) -> Void

    private let hourHeight: CGFloat = 58
    private let railWidth: CGFloat = 46
    private let railSpacing: CGFloat = 8
    private let laneSpacing: CGFloat = 10
    private let horizontalPadding: CGFloat = 16

    var dayHeight: CGFloat {
        DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight)
    }

    var laneWidth: CGFloat {
        let available = availableWidth - (horizontalPadding * 2) - railWidth - railSpacing - laneSpacing
        return max(138, available / 2)
    }

    var contentWidth: CGFloat {
        railWidth + railSpacing + (laneWidth * 2) + laneSpacing
    }

    var body: some View {
        VStack(spacing: 8) {
            DayTimelineHeader(
                railWidth: railWidth,
                railSpacing: railSpacing,
                laneSpacing: laneSpacing,
                laneWidth: laneWidth,
                myTitle: myTitle,
                mySubtitle: mySubtitle,
                myCount: myEvents.count,
                partnerTitle: partnerTitle,
                partnerSubtitle: partnerSubtitle,
                partnerCount: partnerEvents.count
            )
            .padding(.horizontal, horizontalPadding)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    DayTimelineHourGrid(
                        hourHeight: hourHeight,
                        railWidth: railWidth,
                        railSpacing: railSpacing,
                        contentWidth: contentWidth
                    )

                    HStack(alignment: .top, spacing: railSpacing) {
                        DayTimelineHourRail(hourHeight: hourHeight, width: railWidth)

                        HStack(alignment: .top, spacing: laneSpacing) {
                            DayTimelineLane(
                                events: myEvents,
                                tint: .blue,
                                dayStart: dayStart,
                                hourHeight: hourHeight,
                                width: laneWidth,
                                onSelect: onSelect
                            )

                            DayTimelineLane(
                                events: partnerEvents,
                                tint: .pink,
                                dayStart: dayStart,
                                hourHeight: hourHeight,
                                width: laneWidth,
                                onSelect: onSelect
                            )
                        }
                    }
                }
                .frame(width: contentWidth, height: dayHeight, alignment: .topLeading)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 24)
            }
        }
    }
}

struct DayTimelineHeader: View {
    let railWidth: CGFloat
    let railSpacing: CGFloat
    let laneSpacing: CGFloat
    let laneWidth: CGFloat
    let myTitle: String
    let mySubtitle: String
    let myCount: Int
    let partnerTitle: String
    let partnerSubtitle: String
    let partnerCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: railSpacing) {
            Color.clear
                .frame(width: railWidth, height: 1)

            HStack(alignment: .top, spacing: laneSpacing) {
                DayTimelineColumnHeader(
                    title: myTitle,
                    subtitle: mySubtitle,
                    count: myCount,
                    tint: .blue,
                    width: laneWidth
                )

                DayTimelineColumnHeader(
                    title: partnerTitle,
                    subtitle: partnerSubtitle,
                    count: partnerCount,
                    tint: .pink,
                    width: laneWidth
                )
            }
        }
    }
}

struct DayTimelineColumnHeader: View {
    let title: String
    let subtitle: String
    let count: Int
    let tint: Color
    let width: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct DayTimelineHourRail: View {
    let hourHeight: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(DayTimelineLayoutPlan.hourMarks(hourHeight: hourHeight), id: \.hour) { mark in
                Text(String(format: "%02d:00", mark.hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .offset(y: max(0, mark.y - 7))
            }
        }
        .frame(width: width, height: DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight), alignment: .topTrailing)
    }
}

struct DayTimelineHourGrid: View {
    let hourHeight: CGFloat
    let railWidth: CGFloat
    let railSpacing: CGFloat
    let contentWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(DayTimelineLayoutPlan.hourMarks(hourHeight: hourHeight), id: \.hour) { mark in
                Rectangle()
                    .fill(Color(.separator).opacity(mark.hour == 0 ? 0.55 : 0.28))
                    .frame(width: contentWidth - railWidth - railSpacing, height: 1)
                    .offset(x: railWidth + railSpacing, y: mark.y)
            }
        }
        .frame(width: contentWidth, height: DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight), alignment: .topLeading)
    }
}

struct DayTimelineLane: View {
    let events: [EventMirror]
    let tint: Color
    let dayStart: Date
    let hourHeight: CGFloat
    let width: CGFloat
    let onSelect: (EventMirror) -> Void

    var dayHeight: CGFloat {
        DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground).opacity(0.55))

            ForEach(events) { event in
                let frame = frame(for: event)
                let eventHeight = min(max(frame.height, 44), dayHeight)
                let eventY = min(frame.y, max(0, dayHeight - eventHeight))

                Button {
                    onSelect(event)
                } label: {
                    DayTimelineEventBlock(event: event, tint: tint)
                }
                .buttonStyle(.plain)
                .frame(width: max(44, width - 8), height: eventHeight, alignment: .top)
                .offset(x: 4, y: eventY)
                .accessibilityLabel("\(event.title), \(EventCard(event: event, tint: tint).timeText)")
            }
        }
        .frame(width: width, height: dayHeight, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        )
    }

    private func frame(for event: EventMirror) -> DayTimelineEventFrame {
        if event.isAllDay {
            return DayTimelineEventFrame(y: 0, height: hourHeight)
        }

        return DayTimelineLayoutPlan.eventFrame(
            startDate: event.startDate,
            endDate: event.endDate,
            dayStart: dayStart,
            hourHeight: hourHeight
        )
    }
}

struct DayTimelineEventBlock: View {
    let event: EventMirror
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Rectangle()
                .fill(Color(hex: event.calendarColorHex) ?? tint)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    var timeText: String {
        if event.isAllDay {
            return "All day"
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct TimelineColumn: View {
    let title: String
    let subtitle: String
    let events: [EventMirror]
    let tint: Color
    let width: CGFloat
    let onSelect: (EventMirror) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(events.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }

            if events.isEmpty {
                ContentUnavailableView("No events", systemImage: "calendar.badge.clock")
                    .frame(minHeight: 220)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(events) { event in
                        Button {
                            onSelect(event)
                        } label: {
                            EventCard(event: event, tint: tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: width, alignment: .top)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EventCard: View {
    let event: EventMirror
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Rectangle()
                    .fill(Color(hex: event.calendarColorHex) ?? tint)
                    .frame(width: 4)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var timeText: String {
        if event.isAllDay {
            return "All day"
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]
    @State private var commentBody = ""
    @State private var inviteError: String?
    let event: EventMirror

    var eventComments: [EventComment] {
        comments.filter { $0.eventMirrorID == event.id && $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Owner", value: event.ownerMemberID == settings.currentMemberID ? "Me" : "Partner")
                    LabeledContent("Calendar", value: event.sourceCalendarTitle)
                    LabeledContent("Starts", value: event.startDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Ends", value: event.endDate.formatted(date: .abbreviated, time: .shortened))
                    if let location = event.location {
                        LabeledContent("Location", value: location)
                    }
                    if let notes = event.notes {
                        Text(notes)
                    }
                } header: {
                    Text(event.title)
                }

                Section("Invite") {
                    Button {
                        createInvite()
                    } label: {
                        Label("Invite partner", systemImage: "person.badge.plus")
                    }

                    if let inviteError {
                        Text(inviteError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Comments") {
                    ForEach(eventComments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.authorMemberID)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(comment.createdAt, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(comment.body)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                services.commentService.delete(comment)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    HStack {
                        TextField("Add a comment", text: $commentBody, axis: .vertical)
                        Button {
                            addComment()
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func createInvite() {
        let invitation = EventInvitation(
            creatorMemberID: settings.currentMemberID,
            inviteeMemberID: settings.partnerMemberID,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            statusRawValue: InvitationStatus.pending.rawValue
        )
        modelContext.insert(invitation)
        do {
            try modelContext.save()
            services.cloudKitIfAvailable?.queueInvitationsForSync([invitation])
        } catch {
            inviteError = error.localizedDescription
        }
    }

    private func addComment() {
        let comment = services.commentService.createComment(
            eventMirrorID: event.id,
            authorMemberID: settings.currentMemberID,
            body: commentBody
        )
        modelContext.insert(comment)
        do {
            try modelContext.save()
            let eventOwnerMemberID = event.ownerMemberID
            let currentMemberID = settings.currentMemberID
            let eventRecordName = event.cloudKitRecordName ?? event.mirrorKey
            if let cloudKit = services.cloudKitIfAvailable {
                Task {
                    do {
                        try await cloudKit.saveCommentForSync(
                            comment,
                            eventOwnerMemberID: eventOwnerMemberID,
                            currentMemberID: currentMemberID,
                            eventRecordName: eventRecordName
                        )
                    } catch {
                        inviteError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                    }
                }
            }
            commentBody = ""
        } catch {
            inviteError = error.localizedDescription
        }
    }
}

struct InvitesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(InvitationStatus.allCases) { status in
                let filtered = invitations.filter { $0.status == status }
                if !filtered.isEmpty {
                    Section(status.rawValue.capitalized) {
                        ForEach(filtered) { invitation in
                            InvitationRow(invitation: invitation) {
                                accept(invitation)
                            } decline: {
                                services.invitationService.decline(invitation)
                                try? modelContext.save()
                                services.cloudKitIfAvailable?.queueInvitationsForSync([invitation])
                            }
                        }
                    }
                }
            }

            if invitations.isEmpty {
                ContentUnavailableView("No invitations", systemImage: "envelope.open")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Invites")
    }

    private func accept(_ invitation: EventInvitation) {
        do {
            let draft = services.invitationService.draft(from: invitation)
            let localEventID = try services.calendarAccess.createLocalEvent(from: draft)
            _ = try services.invitationService.accept(invitation, createdLocalEventID: localEventID)
            try modelContext.save()
            services.cloudKitIfAvailable?.queueInvitationsForSync([invitation])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InvitationRow: View {
    let invitation: EventInvitation
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(invitation.title)
                .font(.headline)
            Text("\(invitation.startDate.formatted(date: .abbreviated, time: .shortened)) - \(invitation.endDate.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let location = invitation.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if invitation.status == .pending {
                HStack {
                    Button("Accept", action: accept)
                        .buttonStyle(.borderedProminent)
                    Button("Decline", role: .destructive, action: decline)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsTabView: View {
    @Environment(\.openURL) private var openURL
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @State private var authorizationState: CalendarAuthorizationState = .unknown
    @State private var calendars: [CalendarDescriptor] = []
    @State private var preparedShare: PreparedCloudShare?
    @State private var errorMessage: String?
    @State private var calendarAccessMessage: String?
    @State private var isRequestingCalendarAccess = false
    @State private var cloudKitDiagnosticMessage: String?
    @State private var isCheckingCloudKitAccount = false
    @State private var isPreparingShare = false
    @State private var activeSharePreparationID: UUID?

    private var calendarAccessButtonTitle: String {
        switch authorizationState {
        case .denied, .restricted, .writeOnly:
            "Open Calendar Settings"
        case .fullAccess, .legacyAuthorized:
            "Calendar Access Granted"
        default:
            "Request Full Calendar Access"
        }
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            Section("Members") {
                TextField("My display name", text: $settings.currentMemberID)
                    .textInputAutocapitalization(.never)
                TextField("Partner display name", text: $settings.partnerMemberID)
                    .textInputAutocapitalization(.never)
            }

            Section("Calendar Access") {
                LabeledContent("Status", value: String(describing: authorizationState))
                Button(calendarAccessButtonTitle) {
                    Task { await requestAccess() }
                }
                .disabled(isRequestingCalendarAccess || authorizationState.canReadEvents)
                if isRequestingCalendarAccess {
                    HStack {
                        ProgressView()
                        Text("Requesting calendar access...")
                            .foregroundStyle(.secondary)
                    }
                }
                if let calendarAccessMessage {
                    Text(calendarAccessMessage)
                        .font(.caption)
                        .foregroundStyle(authorizationState.canReadEvents ? .green : .orange)
                }
                Button("Refresh Calendars") {
                    refreshCalendars()
                }
            }

            Section("Calendars to Share") {
                if ShareCalCalendarBootstrapPlan.shouldOfferCreation(calendars: calendars) {
                    Button("Create ShareCal Calendar") {
                        createShareCalCalendar()
                    }
                }
                if calendars.isEmpty {
                    Text("No calendars loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendars) { calendar in
                        Toggle(isOn: Binding(
                            get: { settings.selectedCalendarIDs.contains(calendar.id) },
                            set: { settings.toggleCalendarSelection(calendar.id, isSelected: $0) }
                        )) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: calendar.colorHex) ?? .accentColor)
                                    .frame(width: 10, height: 10)
                                Text(calendar.title)
                            }
                        }
                    }
                }
            }

            Section("Privacy") {
                Picker("Default visibility", selection: $settings.defaultVisibility) {
                    ForEach(EventVisibility.allCases) { visibility in
                        Text(visibility.label).tag(visibility)
                    }
                }
            }

            Section("iCloud Share") {
                Button(isPreparingShare ? "Preparing Share..." : "Create or Open Share") {
                    Task { await prepareShare() }
                }
                .disabled(!services.isCloudKitEnabled || isPreparingShare)
                Button(isCheckingCloudKitAccount ? "Checking iCloud Status..." : "Check iCloud Status") {
                    Task { await checkCloudKitStatus() }
                }
                .disabled(!services.isCloudKitEnabled || isCheckingCloudKitAccount)
                Text("Creates an iCloud share for your partner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !services.isCloudKitEnabled {
                    Text("iCloud sharing is unavailable in this local build.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let cloudKitDiagnosticMessage {
                    Text(cloudKitDiagnosticMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync") {
                LabeledContent("Last sync", value: settings.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            authorizationState = services.calendarAccess.authorizationState()
            refreshCalendars()
        }
        .sheet(item: $preparedShare) { share in
            CloudSharingController(preparedShare: share) { message in
                errorMessage = "CloudKit share failed: \(message)"
            }
        }
    }

    private func requestAccess() async {
        errorMessage = nil
        calendarAccessMessage = nil
        authorizationState = services.calendarAccess.authorizationState()

        if authorizationState.canReadEvents {
            refreshCalendars()
            calendarAccessMessage = "Calendar access is already enabled."
            return
        }

        switch authorizationState {
        case .denied, .restricted, .writeOnly:
            calendarAccessMessage = "Calendar access must be changed in iPhone Settings."
            openAppSettings()
            return
        default:
            break
        }

        isRequestingCalendarAccess = true
        defer { isRequestingCalendarAccess = false }

        do {
            let granted = try await services.calendarAccess.requestFullAccess()
            authorizationState = services.calendarAccess.authorizationState()
            refreshCalendars()
            calendarAccessMessage = granted
                ? "Calendar access granted. Select calendars below, then sync."
                : "Calendar access was not granted. Open Settings to enable it."
            if !granted {
                openAppSettings()
            }
        } catch {
            errorMessage = error.localizedDescription
            calendarAccessMessage = "Calendar access request failed."
        }
    }

    private func refreshCalendars() {
        authorizationState = services.calendarAccess.authorizationState()
        calendars = services.calendarAccess.calendars()
        if settings.selectedCalendarIDs.isEmpty,
           let shareCalCalendar = calendars.first(where: ShareCalCalendarBootstrapPlan.isShareCalCalendar) {
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
                afterEnsuring: shareCalCalendar,
                currentSelection: settings.selectedCalendarIDs
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func createShareCalCalendar() {
        errorMessage = nil
        calendarAccessMessage = nil

        do {
            let calendar = try services.calendarAccess.ensureShareCalCalendar()
            refreshCalendars()
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
                afterEnsuring: calendar,
                currentSelection: settings.selectedCalendarIDs
            )
            calendarAccessMessage = "ShareCal calendar is ready."
        } catch {
            errorMessage = error.localizedDescription
            calendarAccessMessage = "ShareCal calendar creation failed."
        }
    }

    @MainActor
    private func prepareShare() async {
        guard !isPreparingShare else { return }
        errorMessage = nil
        guard let cloudKit = services.cloudKitIfAvailable else {
            errorMessage = "iCloud sharing is unavailable in this local build."
            return
        }

        let preparationID = UUID()
        activeSharePreparationID = preparationID
        isPreparingShare = true
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await MainActor.run {
                guard activeSharePreparationID == preparationID else { return }
                errorMessage = CloudKitSharingError.operationTimedOut("share preparation").localizedDescription
                isPreparingShare = false
                activeSharePreparationID = nil
            }
        }
        defer { timeoutTask.cancel() }

        do {
            let share = try await cloudKit.prepareShare(ownerMemberID: settings.currentMemberID)
            guard activeSharePreparationID == preparationID else { return }
            preparedShare = share
        } catch {
            guard activeSharePreparationID == preparationID else { return }
            errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
        }
        isPreparingShare = false
        activeSharePreparationID = nil
    }

    private func checkCloudKitStatus() async {
        errorMessage = nil
        cloudKitDiagnosticMessage = nil
        guard let cloudKit = services.cloudKitIfAvailable else {
            cloudKitDiagnosticMessage = "iCloud sharing is unavailable in this local build."
            return
        }

        isCheckingCloudKitAccount = true
        defer { isCheckingCloudKitAccount = false }

        let diagnostic = await cloudKit.accountDiagnostic()
        cloudKitDiagnosticMessage = diagnostic.displayText
        if !diagnostic.isAccountAvailable {
            errorMessage = "CloudKit account status is \(diagnostic.accountStatus)."
        }
    }
}

private extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }

        guard raw.count == 6, let value = Int(raw, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
