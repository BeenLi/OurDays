import CloudKit
import SwiftData
import SwiftUI

enum ShareCalTab {
    case calendar
    case invites
    case settings
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @State private var isSyncingAcceptedShare = false
    @State private var selectedTab: ShareCalTab = .calendar
    @State private var calendarFocusRequest: CalendarFocusRequest?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarTabView(focusRequest: $calendarFocusRequest)
            }
            .tabItem {
                Label(settings.strings.calendarTab, systemImage: "calendar")
            }
            .tag(ShareCalTab.calendar)

            NavigationStack {
                InvitesTabView { invitation in
                    guard let request = CalendarFocusPlan.request(for: invitation) else { return }
                    calendarFocusRequest = request
                    selectedTab = .calendar
                }
            }
            .tabItem {
                Label(settings.strings.invitesTab, systemImage: "envelope")
            }
            .tag(ShareCalTab.invites)

            NavigationStack {
                SettingsTabView()
            }
            .tabItem {
                Label(settings.strings.settingsTab, systemImage: "gearshape")
            }
            .tag(ShareCalTab.settings)
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

enum CalendarSheet: Identifiable {
    case datePicker
    case createInvite

    var id: String {
        switch self {
        case .datePicker: "datePicker"
        case .createInvite: "createInvite"
        }
    }
}

struct CalendarTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Binding var focusRequest: CalendarFocusRequest?
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @State private var selectedDate = Date()
    @State private var mode: CalendarMode = .day
    @State private var selectedEvent: EventMirror?
    @State private var focusedJointEventID: String?
    @State private var activeCalendarSheet: CalendarSheet?

    var activeMirrors: [EventMirror] {
        mirrors.filter { $0.deletedAt == nil }
    }

    var visibleMirrors: [EventMirror] {
        activeMirrors.filter { mirror in
            visibleInterval.contains(mirror.startDate)
        }
    }

    var acceptedJointEvents: [JointScheduleEvent] {
        JointSchedulePlan.jointEvents(
            from: invitations,
            currentMemberID: settings.currentMemberID,
            partnerMemberID: settings.partnerMemberID
        )
    }

    var visibleJointEvents: [JointScheduleEvent] {
        acceptedJointEvents.filter { jointEvent in
            visibleInterval.contains(jointEvent.startDate)
        }
    }

    var visibleOrdinaryMirrors: [EventMirror] {
        JointSchedulePlan.ordinaryMirrors(visibleMirrors, excluding: visibleJointEvents)
    }

    var myEvents: [EventMirror] {
        visibleOrdinaryMirrors.filter { $0.ownerMemberID == settings.currentMemberID }
    }

    var partnerEvents: [EventMirror] {
        visibleOrdinaryMirrors.filter { $0.ownerMemberID != settings.currentMemberID }
    }

    var visibleMirrorByID: [String: EventMirror] {
        Dictionary(uniqueKeysWithValues: visibleOrdinaryMirrors.map { ($0.id, $0) })
    }

    var weekAgendaDays: [WeekAgendaDay] {
        WeekAgendaPlan.days(
            containing: selectedDate,
            mirrors: visibleOrdinaryMirrors,
            jointEvents: visibleJointEvents,
            currentMemberID: settings.currentMemberID
        )
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
        let strings = settings.strings

        VStack(spacing: 8) {
            CompactCalendarTopBar(
                selectedDate: $selectedDate,
                mode: $mode,
                title: CalendarDateNavigationPlan.compactTitle(for: selectedDate, mode: mode),
                syncPhase: settings.syncPhase,
                hasSyncError: settings.lastSyncError != nil,
                onOpenPicker: {
                    activeCalendarSheet = .datePicker
                },
                onCreateInvite: {
                    activeCalendarSheet = .createInvite
                },
                onSync: {
                    syncNow()
                }
            )
            .padding(.horizontal)
            .padding(.top, 8)

            if settings.syncPhase == .failed, let lastSyncError = settings.lastSyncError {
                CompactSyncErrorBanner(message: lastSyncError)
                    .padding(.horizontal)
            }

            if activeMirrors.isEmpty && acceptedJointEvents.isEmpty {
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
                            myTitle: strings.meTitle,
                            mySubtitle: settings.currentMemberID,
                            myEvents: myEvents,
                            jointEvents: visibleJointEvents,
                            focusedJointEventID: focusedJointEventID,
                            partnerTitle: strings.partnerTitle,
                            partnerSubtitle: settings.partnerMemberID,
                            partnerEvents: partnerEvents,
                            availableWidth: proxy.size.width,
                            onSelect: { selectedEvent = $0 }
                        )
                    case .week:
                        WeekAgendaView(
                            days: weekAgendaDays,
                            mirrorByID: visibleMirrorByID,
                            onSelect: { selectedEvent = $0 }
                        )
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activeCalendarSheet) { sheet in
            switch sheet {
            case .datePicker:
                HierarchicalDatePickerSheet(selectedDate: $selectedDate, mode: $mode)
            case .createInvite:
                CreateInviteView(selectedDate: $selectedDate, mode: $mode)
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .onAppear {
            consumeFocusRequestIfNeeded()
        }
        .onChange(of: focusRequest) { _, _ in
            consumeFocusRequestIfNeeded()
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

    private func consumeFocusRequestIfNeeded() {
        guard let request = focusRequest else { return }
        selectedDate = request.startDate
        mode = .day
        focusedJointEventID = request.invitationID
        focusRequest = nil
    }

    private func syncNow() {
        guard settings.syncPhase != .syncing else { return }
        Task {
            let coordinator = SyncCoordinator(
                calendarAccess: services.calendarAccess,
                eventMirrorService: services.eventMirrorService,
                cloudKit: services.cloudKitIfAvailable
            )
            await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
        }
    }
}

struct CompactCalendarTopBar: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var selectedDate: Date
    @Binding var mode: CalendarMode
    let title: String
    let syncPhase: SyncPhase
    let hasSyncError: Bool
    let onOpenPicker: () -> Void
    let onCreateInvite: () -> Void
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            CompactModeToggle(mode: $mode)
                .frame(width: 92)

            HStack(spacing: 4) {
                CompactIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: settings.strings.previousDateAccessibilityLabel
                ) {
                    move(.previous)
                }

                Button {
                    onOpenPicker()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.semibold))
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .padding(.horizontal, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.strings.selectDateAccessibilityLabel)
                .accessibilityValue(title)
                .accessibilityIdentifier("compact-date-picker-button")

                CompactIconButton(
                    systemName: "chevron.right",
                    accessibilityLabel: settings.strings.nextDateAccessibilityLabel
                ) {
                    move(.next)
                }
            }
            .layoutPriority(1)

            HStack(spacing: 6) {
                CompactIconButton(
                    systemName: "plus",
                    accessibilityLabel: settings.strings.createInviteAccessibilityLabel,
                    accessibilityIdentifier: "compact-create-invite-button",
                    action: onCreateInvite
                )

                CompactSyncButton(
                    syncPhase: syncPhase,
                    hasSyncError: hasSyncError,
                    onSync: onSync
                )
            }
        }
        .frame(height: 38)
    }

    private func move(_ direction: CalendarNavigationDirection) {
        selectedDate = CalendarDateNavigationPlan.date(
            afterMoving: selectedDate,
            mode: mode,
            direction: direction
        )
    }
}

struct CompactModeToggle: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var mode: CalendarMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarMode.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        mode = item
                    }
                } label: {
                    Text(settings.strings.modeLabel(for: item.rawValue))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(mode == item ? Color.primary : Color.secondary)
                        .background(mode == item ? Color(.systemBackground) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compact-mode-\(item.rawValue.lowercased())-button")
            }
        }
        .padding(2)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CompactIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? accessibilityLabel)
    }
}

struct CompactSyncButton: View {
    @Environment(SettingsStore.self) private var settings
    let syncPhase: SyncPhase
    let hasSyncError: Bool
    let onSync: () -> Void

    var body: some View {
        Button {
            onSync()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if syncPhase == .syncing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.78)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(width: 34, height: 34)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                    .offset(x: 2, y: -2)
            }
        }
        .buttonStyle(.plain)
        .disabled(syncPhase == .syncing)
        .accessibilityLabel(settings.strings.syncAccessibilityLabel)
        .accessibilityIdentifier("compact-sync-button")
    }

    private var statusColor: Color {
        switch syncPhase {
        case .syncing:
            return .blue
        case .failed:
            return .red
        case .idle:
            return hasSyncError ? .orange : .green
        }
    }
}

struct CompactSyncErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
            Text(message)
                .font(.caption2)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ShareCalEmptyState: View {
    @Environment(SettingsStore.self) private var settings
    let onLoadSampleData: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(settings.strings.noSharedSchedulesTitle, systemImage: "calendar.badge.plus")
        } description: {
            Text(settings.strings.noSharedSchedulesDescription)
        } actions: {
            Button(settings.strings.loadSampleScheduleButton, action: onLoadSampleData)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct CalendarDateNavigator: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var selectedDate: Date
    let mode: CalendarMode
    let title: String
    let onOpenPicker: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                move(.previous)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(settings.strings.previousDateAccessibilityLabel)

            Button {
                onOpenPicker()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(settings.strings.selectDateAccessibilityLabel)

            Button(settings.strings.todayButton) {
                selectedDate = Calendar.current.startOfDay(for: Date())
            }
            .buttonStyle(.bordered)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 34)

            Button {
                move(.next)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(settings.strings.nextDateAccessibilityLabel)
        }
    }

    private func move(_ direction: CalendarNavigationDirection) {
        selectedDate = CalendarDateNavigationPlan.date(
            afterMoving: selectedDate,
            mode: mode,
            direction: direction
        )
    }
}

struct HierarchicalDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Binding var selectedDate: Date
    @Binding var mode: CalendarMode
    @State private var level: HierarchicalDatePickerLevel = .month
    @State private var visibleMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let monthColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let yearColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    init(selectedDate: Binding<Date>, mode: Binding<CalendarMode>) {
        _selectedDate = selectedDate
        _mode = mode
        _visibleMonth = State(
            initialValue: HierarchicalDatePickerPlan.normalizedMonth(containing: selectedDate.wrappedValue)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch level {
                case .month:
                    monthView
                case .months:
                    monthsView
                case .years:
                    yearsView
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(settings.strings.datePickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.strings.cancelButton) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var monthView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Button {
                    level = .months
                } label: {
                    Text(visibleMonth, format: .dateTime.month(.wide))
                        .font(.headline)
                }

                Button {
                    level = .years
                } label: {
                    Text(yearText(for: visibleMonth))
                        .font(.headline)
                }

                Spacer()

                Button {
                    moveMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)

                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(HierarchicalDatePickerPlan.monthGrid(containing: visibleMonth)) { day in
                    let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                    Button {
                        selectDay(day.date)
                    } label: {
                        Text(day.date, format: .dateTime.day())
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(dayTextColor(day: day, isSelected: isSelected))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthsView: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    level = .years
                } label: {
                    Text(yearText(for: visibleMonth))
                        .font(.headline)
                }

                Spacer()
            }

            LazyVGrid(columns: monthColumns, spacing: 10) {
                ForEach(HierarchicalDatePickerPlan.months(inYearContaining: visibleMonth), id: \.self) { month in
                    Button {
                        let navigation = HierarchicalDatePickerPlan.selectMonth(month)
                        visibleMonth = navigation.visibleMonth
                        level = navigation.level
                    } label: {
                        Text(month, format: .dateTime.month(.abbreviated))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var yearsView: some View {
        let years = HierarchicalDatePickerPlan.years(centeredOn: visibleMonth)

        return VStack(spacing: 14) {
            HStack {
                Button {
                    moveYearPage(-12)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(yearRangeText(years))
                    .font(.headline)

                Spacer()

                Button {
                    moveYearPage(12)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: yearColumns, spacing: 10) {
                ForEach(years, id: \.self) { year in
                    Button {
                        let navigation = HierarchicalDatePickerPlan.selectYear(year)
                        visibleMonth = navigation.visibleMonth
                        level = navigation.level
                    } label: {
                        Text(yearText(for: year))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let start = max(0, calendar.firstWeekday - 1)
        return Array(symbols[start...] + symbols[..<start])
    }

    private func selectDay(_ date: Date) {
        let navigation = HierarchicalDatePickerPlan.selectDay(date)
        let selection = CalendarDateNavigationPlan.selectionResult(for: navigation.selectedDate ?? date)
        selectedDate = selection.selectedDate
        mode = selection.mode
        dismiss()
    }

    private func moveMonth(_ value: Int) {
        visibleMonth = Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func moveYearPage(_ value: Int) {
        visibleMonth = Calendar.current.date(byAdding: .year, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func yearText(for date: Date) -> String {
        String(Calendar.current.component(.year, from: date))
    }

    private func yearRangeText(_ years: [Date]) -> String {
        guard let first = years.first, let last = years.last else { return yearText(for: visibleMonth) }
        return "\(yearText(for: first)) - \(yearText(for: last))"
    }

    private func dayTextColor(day: HierarchicalMonthDay, isSelected: Bool) -> Color {
        if isSelected {
            return .white
        }
        return day.isInDisplayedMonth ? .primary : .secondary
    }
}

struct DateStrip: View {
    @Binding var selectedDate: Date

    var dates: [Date] {
        CalendarDateNavigationPlan.dateStrip(around: selectedDate)
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
        let strings = settings.strings
        if settings.syncPhase == .syncing {
            return strings.syncingSelectedCalendars
        }
        if let error = settings.lastSyncError {
            return error
        }
        if let lastSyncAt = settings.lastSyncAt {
            return strings.lastSyncStatus(lastSyncAt.formatted(date: .omitted, time: .shortened))
        }
        return strings.notSyncedYet
    }
}

struct TwoColumnTimelineList: View {
    let myTitle: String
    let mySubtitle: String
    let myEvents: [EventMirror]
    let jointEvents: [JointScheduleEvent]
    let partnerTitle: String
    let partnerSubtitle: String
    let partnerEvents: [EventMirror]
    let availableWidth: CGFloat
    let onSelect: (EventMirror) -> Void

    var columnWidth: CGFloat {
        max(160, (availableWidth - 30) / 2)
    }

    var body: some View {
        VStack(spacing: 10) {
            if !jointEvents.isEmpty {
                JointTimelineList(jointEvents: jointEvents)
            }

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
}

struct DayAlignedTimelineView: View {
    @Environment(SettingsStore.self) private var settings
    let dayStart: Date
    let myTitle: String
    let mySubtitle: String
    let myEvents: [EventMirror]
    let jointEvents: [JointScheduleEvent]
    let focusedJointEventID: String?
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

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        let jointPlacements = DayTimelineJointLayoutPlan.placements(for: jointEvents)

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

                        defaultScrollMarker()

                        ForEach(jointEvents) { event in
                            jointScrollMarker(for: event)
                        }

                        ForEach(jointEvents) { event in
                            let frame = frame(for: event)
                            let eventHeight = min(max(frame.height, 44), dayHeight)
                            let eventY = min(frame.y, max(0, dayHeight - eventHeight))
                            let jointWidth = (laneWidth * 2) + laneSpacing
                            let placement = jointPlacements[event.id] ?? DayTimelineJointPlacement(columnIndex: 0, columnCount: 1)
                            let slotWidth = max(44, (jointWidth - 8) / CGFloat(placement.columnCount))

                            DayTimelineJointEventBlock(
                                event: event,
                                isFocused: event.id == focusedJointEventID
                            )
                            .frame(width: max(44, slotWidth - 4), height: eventHeight, alignment: .top)
                            .offset(
                                x: railWidth + railSpacing + 4 + (CGFloat(placement.columnIndex) * slotWidth),
                                y: eventY
                            )
                            .accessibilityLabel("\(event.title), \(timeText(for: event)), \(event.calendarTitle), \(settings.strings.jointScheduleLabel)")
                        }
                    }
                    .frame(width: contentWidth, height: dayHeight, alignment: .topLeading)
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

    private func frame(for event: JointScheduleEvent) -> DayTimelineEventFrame {
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

    private func timeText(for event: JointScheduleEvent) -> String {
        if event.isAllDay {
            return settings.strings.allDay
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }

    private func jointScrollID(for eventID: String) -> String {
        "joint-\(eventID)"
    }

    private var defaultScrollID: String {
        "timeline-default-start-\(DayTimelineScrollTargetPlan.defaultStartHour)"
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

    private func defaultScrollMarker() -> some View {
        let targetY = DayTimelineScrollTargetPlan.defaultTargetY(hourHeight: hourHeight)

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
        )

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
    @Environment(SettingsStore.self) private var settings
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
                .accessibilityLabel("\(event.title), \(timeText(for: event))")
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

    private func timeText(for event: EventMirror) -> String {
        if event.isAllDay {
            return settings.strings.allDay
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct DayTimelineEventBlock: View {
    @Environment(SettingsStore.self) private var settings
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
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct DayTimelineJointEventBlock: View {
    @Environment(SettingsStore.self) private var settings
    let event: JointScheduleEvent
    let isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.green)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(event.calendarTitle) · \(settings.strings.jointScheduleLabel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)

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
        .background(Color.green.opacity(isFocused ? 0.22 : 0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(isFocused ? 0.9 : 0.45), lineWidth: isFocused ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.green.opacity(isFocused ? 0.22 : 0.04), radius: isFocused ? 5 : 2, x: 0, y: 1)
    }

    var timeText: String {
        if event.isAllDay {
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct JointTimelineList: View {
    @Environment(SettingsStore.self) private var settings
    let jointEvents: [JointScheduleEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(settings.strings.jointScheduleLabel, systemImage: "person.2.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text("\(jointEvents.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            ForEach(jointEvents) { event in
                JointEventCard(event: event)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct JointEventCard: View {
    @Environment(SettingsStore.self) private var settings
    let event: JointScheduleEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.green)
                .frame(width: 4)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text("\(event.calendarTitle) · \(settings.strings.jointScheduleLabel)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .lineLimit(1)

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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var timeText: String {
        if event.isAllDay {
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct TimelineColumn: View {
    @Environment(SettingsStore.self) private var settings
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
                ContentUnavailableView(settings.strings.noEvents, systemImage: "calendar.badge.clock")
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
    @Environment(SettingsStore.self) private var settings
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
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct WeekAgendaView: View {
    let days: [WeekAgendaDay]
    let mirrorByID: [String: EventMirror]
    let onSelect: (EventMirror) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(days) { day in
                    WeekAgendaDaySection(
                        day: day,
                        mirrorByID: mirrorByID,
                        onSelect: onSelect
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.date, format: .dateTime.weekday(.wide))
                        .font(.headline)
                    Text(day.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(day.items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if day.items.isEmpty {
                Text(settings.strings.noEvents)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(day.items) { item in
                        if let mirrorID = item.mirrorID, let mirror = mirrorByID[mirrorID] {
                            Button {
                                onSelect(mirror)
                            } label: {
                                WeekAgendaItemCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            WeekAgendaItemCard(item: item)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WeekAgendaItemCard: View {
    @Environment(SettingsStore.self) private var settings
    let item: WeekAgendaItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(tint)
                .frame(width: 4)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(contextLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let location = item.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tint: Color {
        switch item.kind {
        case .currentMember:
            Color(hex: item.colorHex) ?? .blue
        case .partner:
            Color(hex: item.colorHex) ?? .pink
        case .joint:
            .green
        }
    }

    private var contextLabel: String {
        switch item.kind {
        case .currentMember:
            "\(settings.strings.meTitle) · \(item.calendarTitle)"
        case .partner:
            "\(settings.strings.partnerTitle) · \(item.calendarTitle)"
        case .joint:
            "\(item.calendarTitle) · \(settings.strings.jointScheduleLabel)"
        }
    }

    private var timeText: String {
        if item.isAllDay {
            return settings.strings.allDay
        }
        return "\(item.startDate.formatted(date: .omitted, time: .shortened)) - \(item.endDate.formatted(date: .omitted, time: .shortened))"
    }
}

struct CreateInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Binding var selectedDate: Date
    @Binding var mode: CalendarMode
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay = false
    @State private var location = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var conflictMessage: String?
    @State private var isShowingConflict = false
    @State private var isSending = false

    init(selectedDate: Binding<Date>, mode: Binding<CalendarMode>) {
        _selectedDate = selectedDate
        _mode = mode
        let defaultStart = Self.defaultStartDate(for: selectedDate.wrappedValue)
        _title = State(initialValue: "")
        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: defaultStart.addingTimeInterval(60 * 60))
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            Form {
                Section(strings.createInviteSection) {
                    TextField(strings.titleLabel, text: $title)

                    DatePicker(
                        strings.dateLabel,
                        selection: dayBinding,
                        displayedComponents: .date
                    )

                    Toggle(strings.allDay, isOn: $isAllDay)

                    DatePicker(
                        strings.startsLabel,
                        selection: $startDate,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(isAllDay)

                    DatePicker(
                        strings.endsLabel,
                        selection: $endDate,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(isAllDay)

                    TextField(strings.locationLabel, text: $location)
                    TextField(strings.notesLabel, text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(strings.newInviteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(strings.cancelButton) {
                        dismiss()
                    }
                    .disabled(isSending)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sendInvite()
                    } label: {
                        Label(strings.sendInviteButton, systemImage: "paperplane.fill")
                    }
                    .disabled(isSending)
                }
            }
            .overlay {
                if isSending {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .alert(strings.invitationConflictTitle, isPresented: $isShowingConflict) {
                Button(strings.cancelButton, role: .cancel) {}
                Button(strings.inviteAnywayButton) {
                    sendInvite(skipConflictCheck: true)
                }
            } message: {
                if let conflictMessage {
                    Text(conflictMessage)
                }
            }
            .onChange(of: isAllDay) { _, newValue in
                adjustForAllDay(newValue)
            }
        }
    }

    private var dayBinding: Binding<Date> {
        Binding {
            startDate
        } set: { newDate in
            moveInvite(toDayContaining: newDate)
        }
    }

    private static func defaultStartDate(for selectedDate: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: selectedDate)
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(10 * 60 * 60)
    }

    private func moveInvite(toDayContaining newDate: Date) {
        let calendar = Calendar.current
        let currentDuration = max(60 * 60, endDate.timeIntervalSince(startDate))
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)
        let newDayStart = calendar.startOfDay(for: newDate)
        startDate = calendar.date(
            bySettingHour: startComponents.hour ?? 10,
            minute: startComponents.minute ?? 0,
            second: startComponents.second ?? 0,
            of: newDayStart
        ) ?? newDayStart
        endDate = startDate.addingTimeInterval(currentDuration)
        if isAllDay {
            adjustForAllDay(true)
        }
    }

    private func adjustForAllDay(_ enabled: Bool) {
        if enabled {
            let dayStart = Calendar.current.startOfDay(for: startDate)
            startDate = dayStart
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
                ?? dayStart.addingTimeInterval(24 * 60 * 60)
        } else if endDate <= startDate {
            endDate = startDate.addingTimeInterval(60 * 60)
        }
    }

    private func currentDraft() -> CreateInviteDraft {
        CreateInviteDraft(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes
        )
    }

    private func sendInvite(skipConflictCheck: Bool = false) {
        guard !isSending else { return }
        errorMessage = nil
        let draft = currentDraft()

        do {
            _ = try CreateInvitePlan.localCalendarDraft(from: draft)

            if !skipConflictCheck {
                let candidate = try CreateInvitePlan.conflictCandidateMirror(
                    from: draft,
                    ownerMemberID: settings.currentMemberID
                )
                let conflicts = InvitationConflictPlan.conflicts(
                    for: candidate,
                    partnerMemberID: settings.partnerMemberID,
                    mirrors: mirrors
                )
                if let firstConflict = conflicts.first {
                    conflictMessage = settings.strings.invitationConflictMessage(
                        eventTitle: firstConflict.title,
                        timeText: timeText(for: firstConflict),
                        additionalConflictCount: conflicts.count - 1
                    )
                    isShowingConflict = true
                    return
                }
            }

            isSending = true
            let localDraft = try CreateInvitePlan.localCalendarDraft(from: draft)
            let createdEvent = try services.calendarAccess.createShareCalEvent(from: localDraft)
            let mirror = try CreateInvitePlan.mirror(
                from: draft,
                createdEvent: createdEvent,
                ownerMemberID: settings.currentMemberID
            )
            let invitation = try CreateInvitePlan.invitation(
                from: draft,
                creatorMemberID: settings.currentMemberID,
                inviteeMemberID: settings.partnerMemberID
            )
            invitation.createdLocalEventID = createdEvent.eventIdentifier
            try upsertMirror(mirror)
            modelContext.insert(invitation)
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
                afterEnsuring: CalendarDescriptor(
                    id: createdEvent.calendarIdentifier,
                    title: createdEvent.calendarTitle,
                    colorHex: createdEvent.calendarColorHex,
                    allowsContentModifications: true
                ),
                currentSelection: settings.selectedCalendarIDs
            )
            try modelContext.save()
            selectedDate = localDraft.startDate
            mode = .day

            guard let cloudKit = services.cloudKitIfAvailable else {
                dismiss()
                return
            }

            Task {
                do {
                    try await cloudKit.ensureShareRoot(ownerMemberID: settings.currentMemberID)
                    try await cloudKit.saveMirrorsForSync([mirror])
                    try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                    dismiss()
                } catch {
                    errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                    isSending = false
                }
            }
        } catch {
            errorMessage = validationMessage(for: error)
            isSending = false
        }
    }

    private func upsertMirror(_ mirror: EventMirror) throws {
        let mirrorKey = mirror.mirrorKey
        let descriptor = FetchDescriptor<EventMirror>(
            predicate: #Predicate { $0.mirrorKey == mirrorKey }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.ownerMemberID = mirror.ownerMemberID
            existing.sourceCalendarID = mirror.sourceCalendarID
            existing.sourceCalendarTitle = mirror.sourceCalendarTitle
            existing.occurrenceStartDate = mirror.occurrenceStartDate
            existing.startDate = mirror.startDate
            existing.endDate = mirror.endDate
            existing.isAllDay = mirror.isAllDay
            existing.timeZoneIdentifier = mirror.timeZoneIdentifier
            existing.title = mirror.title
            existing.location = mirror.location
            existing.notes = mirror.notes
            existing.urlString = mirror.urlString
            existing.calendarColorHex = mirror.calendarColorHex
            existing.visibilityRawValue = mirror.visibilityRawValue
            existing.deletedAt = mirror.deletedAt
            existing.cloudKitRecordName = mirror.cloudKitRecordName
        } else {
            modelContext.insert(mirror)
        }
    }

    private func validationMessage(for error: Error) -> String {
        if let validationError = error as? CreateInviteValidationError {
            switch validationError {
            case .emptyTitle:
                return settings.strings.emptyTitleError
            case .invalidDateRange:
                return settings.strings.invalidDateRangeError
            }
        }
        return error.localizedDescription
    }

    private func timeText(for event: EventMirror) -> String {
        if event.isAllDay {
            return settings.strings.allDay
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
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @State private var commentBody = ""
    @State private var inviteError: String?
    @State private var inviteSuccessMessage: String?
    @State private var isSendingInvite = false
    @State private var conflictMessage: String?
    @State private var isShowingInviteConflict = false
    let event: EventMirror

    var eventComments: [EventComment] {
        comments.filter { $0.eventMirrorID == event.id && $0.deletedAt == nil }
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                Section {
                    LabeledContent(strings.ownerLabel, value: event.ownerMemberID == settings.currentMemberID ? strings.meTitle : strings.partnerTitle)
                    LabeledContent(strings.calendarLabel, value: event.sourceCalendarTitle)
                    LabeledContent(strings.startsLabel, value: event.startDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent(strings.endsLabel, value: event.endDate.formatted(date: .abbreviated, time: .shortened))
                    if let location = event.location {
                        LabeledContent(strings.locationLabel, value: location)
                    }
                    if let notes = event.notes {
                        Text(notes)
                    }
                } header: {
                    Text(event.title)
                }

                Section(strings.inviteSection) {
                    Button {
                        createInviteAfterConflictCheck()
                    } label: {
                        Label(
                            isSendingInvite ? strings.sendingInvitationButton : strings.invitePartnerButton,
                            systemImage: isSendingInvite ? "clock.arrow.circlepath" : "person.badge.plus"
                        )
                    }
                    .disabled(isSendingInvite)

                    if isSendingInvite {
                        ProgressView()
                    }

                    if let inviteSuccessMessage {
                        Text(inviteSuccessMessage)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if let inviteError {
                        Text(inviteError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section(strings.commentsSection) {
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
                                Label(strings.deleteButton, systemImage: "trash")
                            }
                        }
                    }

                    HStack {
                        TextField(strings.addCommentPlaceholder, text: $commentBody, axis: .vertical)
                        Button {
                            addComment()
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle(strings.eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.doneButton) {
                        dismiss()
                    }
                }
            }
            .alert(strings.invitationConflictTitle, isPresented: $isShowingInviteConflict) {
                Button(strings.cancelButton, role: .cancel) {}
                Button(strings.inviteAnywayButton) {
                    createInvite()
                }
            } message: {
                if let conflictMessage {
                    Text(conflictMessage)
                }
            }
        }
    }

    private func createInviteAfterConflictCheck() {
        guard !isSendingInvite else { return }
        inviteError = nil
        inviteSuccessMessage = nil
        let conflicts = InvitationConflictPlan.conflicts(
            for: event,
            partnerMemberID: settings.partnerMemberID,
            mirrors: mirrors
        )
        guard let firstConflict = conflicts.first else {
            createInvite()
            return
        }

        conflictMessage = settings.strings.invitationConflictMessage(
            eventTitle: firstConflict.title,
            timeText: timeText(for: firstConflict),
            additionalConflictCount: conflicts.count - 1
        )
        isShowingInviteConflict = true
    }

    private func createInvite() {
        guard !isSendingInvite else { return }
        isSendingInvite = true
        inviteError = nil
        inviteSuccessMessage = nil
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
            if let cloudKit = services.cloudKitIfAvailable {
                Task {
                    do {
                        try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                        inviteSuccessMessage = settings.strings.invitationSentMessage
                    } catch {
                        inviteError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                    }
                    isSendingInvite = false
                }
            } else {
                inviteSuccessMessage = settings.strings.invitationSentMessage
                isSendingInvite = false
            }
        } catch {
            inviteError = error.localizedDescription
            isSendingInvite = false
        }
    }

    private func timeText(for event: EventMirror) -> String {
        if event.isAllDay {
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
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
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @State private var errorMessage: String?
    let openInCalendar: (EventInvitation) -> Void

    var body: some View {
        let strings = settings.strings
        let visibleInvitations = InvitationListPlan.visibleInvitations(invitations)

        List {
            ForEach(InvitationStatus.allCases) { status in
                let filtered = visibleInvitations.filter { $0.status == status }
                if !filtered.isEmpty {
                    Section(strings.invitationStatusTitle(for: status)) {
                        ForEach(filtered) { invitation in
                            InvitationRow(invitation: invitation, currentMemberID: settings.currentMemberID) {
                                accept(invitation)
                            } decline: {
                                decline(invitation)
                            } openInCalendar: {
                                openInCalendar(invitation)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if InvitationListPlan.canDelete(invitation) {
                                    Button(role: .destructive) {
                                        archive(invitation)
                                    } label: {
                                        Label(strings.deleteButton, systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if visibleInvitations.isEmpty {
                ContentUnavailableView(strings.noInvitations, systemImage: "envelope.open")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(strings.invitesTab)
    }

    private func accept(_ invitation: EventInvitation) {
        do {
            let draft = services.invitationService.draft(from: invitation)
            let createdEvent = try services.calendarAccess.createShareCalEvent(from: draft)
            _ = try services.invitationService.accept(invitation, createdLocalEventID: createdEvent.eventIdentifier)
            let mirror = AcceptedInvitationMirrorPlan.mirror(
                from: invitation,
                createdEvent: createdEvent,
                ownerMemberID: settings.currentMemberID
            )
            try upsertAcceptedMirror(mirror)
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
                afterEnsuring: CalendarDescriptor(
                    id: createdEvent.calendarIdentifier,
                    title: createdEvent.calendarTitle,
                    colorHex: createdEvent.calendarColorHex,
                    allowsContentModifications: true
                ),
                currentSelection: settings.selectedCalendarIDs
            )
            try modelContext.save()
            saveInvitationStatusToCloudKit(invitation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsertAcceptedMirror(_ mirror: EventMirror) throws {
        let mirrorKey = mirror.mirrorKey
        let descriptor = FetchDescriptor<EventMirror>(
            predicate: #Predicate { $0.mirrorKey == mirrorKey }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.ownerMemberID = mirror.ownerMemberID
            existing.sourceCalendarID = mirror.sourceCalendarID
            existing.sourceCalendarTitle = mirror.sourceCalendarTitle
            existing.occurrenceStartDate = mirror.occurrenceStartDate
            existing.startDate = mirror.startDate
            existing.endDate = mirror.endDate
            existing.isAllDay = mirror.isAllDay
            existing.timeZoneIdentifier = mirror.timeZoneIdentifier
            existing.title = mirror.title
            existing.location = mirror.location
            existing.notes = mirror.notes
            existing.urlString = mirror.urlString
            existing.calendarColorHex = mirror.calendarColorHex
            existing.visibilityRawValue = mirror.visibilityRawValue
            existing.deletedAt = mirror.deletedAt
            existing.cloudKitRecordName = mirror.cloudKitRecordName
        } else {
            modelContext.insert(mirror)
        }
    }

    private func decline(_ invitation: EventInvitation) {
        services.invitationService.decline(invitation)
        do {
            try modelContext.save()
            saveInvitationStatusToCloudKit(invitation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive(_ invitation: EventInvitation) {
        invitation.archivedAt = .now
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveInvitationStatusToCloudKit(_ invitation: EventInvitation) {
        guard let cloudKit = services.cloudKitIfAvailable else { return }
        Task {
            do {
                try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
            } catch {
                errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            }
        }
    }
}

struct InvitationRow: View {
    @Environment(SettingsStore.self) private var settings
    let invitation: EventInvitation
    let currentMemberID: String
    let accept: () -> Void
    let decline: () -> Void
    let openInCalendar: () -> Void

    var body: some View {
        let strings = settings.strings
        let canOpenInCalendar = InvitationListPlan.canOpenInCalendar(invitation)

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

            if InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: currentMemberID) {
                HStack {
                    Button(strings.acceptButton, action: accept)
                        .buttonStyle(.borderedProminent)
                    Button(strings.declineButton, role: .destructive, action: decline)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canOpenInCalendar else { return }
            openInCalendar()
        }
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
        let strings = settings.strings
        switch authorizationState {
        case .denied, .restricted, .writeOnly:
            return strings.openCalendarSettingsButton
        case .fullAccess, .legacyAuthorized:
            return strings.calendarAccessGrantedButton
        default:
            return strings.requestFullCalendarAccessButton
        }
    }

    var body: some View {
        @Bindable var settings = settings
        let strings = settings.strings

        List {
            Section(strings.membersSection) {
                TextField(strings.myDisplayNamePlaceholder, text: $settings.currentMemberID)
                    .textInputAutocapitalization(.never)
                TextField(strings.partnerDisplayNamePlaceholder, text: $settings.partnerMemberID)
                    .textInputAutocapitalization(.never)
            }

            Section(strings.languageSection) {
                Picker(strings.appLanguagePicker, selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(strings.languageDisplayName(for: language)).tag(language)
                    }
                }
            }

            Section(strings.calendarAccessSection) {
                LabeledContent(strings.statusLabel, value: String(describing: authorizationState))
                Button(calendarAccessButtonTitle) {
                    Task { await requestAccess() }
                }
                .disabled(isRequestingCalendarAccess || authorizationState.canReadEvents)
                if isRequestingCalendarAccess {
                    HStack {
                        ProgressView()
                        Text(strings.requestingCalendarAccess)
                            .foregroundStyle(.secondary)
                    }
                }
                if let calendarAccessMessage {
                    Text(calendarAccessMessage)
                        .font(.caption)
                        .foregroundStyle(authorizationState.canReadEvents ? .green : .orange)
                }
                Button(strings.refreshCalendarsButton) {
                    refreshCalendars()
                }
            }

            Section(strings.calendarsToShareSection) {
                if ShareCalCalendarBootstrapPlan.shouldOfferCreation(calendars: calendars) {
                    Button(strings.createShareCalCalendarButton) {
                        createShareCalCalendar()
                    }
                }
                if calendars.isEmpty {
                    Text(strings.noCalendarsLoaded)
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

            Section(strings.privacySection) {
                Picker(strings.defaultVisibilityPicker, selection: $settings.defaultVisibility) {
                    ForEach(EventVisibility.allCases) { visibility in
                        Text(strings.defaultVisibilityLabel(for: visibility)).tag(visibility)
                    }
                }
            }

            Section(strings.iCloudShareSection) {
                Button(strings.createOrOpenShareButton(isPreparing: isPreparingShare)) {
                    Task { await prepareShare() }
                }
                .disabled(!services.isCloudKitEnabled || isPreparingShare)
                Button(strings.checkICloudStatusButton(isChecking: isCheckingCloudKitAccount)) {
                    Task { await checkCloudKitStatus() }
                }
                .disabled(!services.isCloudKitEnabled || isCheckingCloudKitAccount)
                Text(strings.createsICloudShareDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !services.isCloudKitEnabled {
                    Text(strings.iCloudSharingUnavailableLocalBuild)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let cloudKitDiagnosticMessage {
                    Text(cloudKitDiagnosticMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section(strings.syncSection) {
                LabeledContent(strings.lastSyncLabel, value: settings.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? strings.never)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(strings.settingsTitle)
        .task {
            authorizationState = services.calendarAccess.authorizationState()
            refreshCalendars()
        }
        .sheet(item: $preparedShare) { share in
            CloudSharingController(preparedShare: share) { message in
                errorMessage = strings.cloudKitShareFailed(message)
            }
        }
    }

    private func requestAccess() async {
        errorMessage = nil
        calendarAccessMessage = nil
        authorizationState = services.calendarAccess.authorizationState()

        if authorizationState.canReadEvents {
            refreshCalendars()
            calendarAccessMessage = settings.strings.calendarAccessAlreadyEnabled
            return
        }

        switch authorizationState {
        case .denied, .restricted, .writeOnly:
            calendarAccessMessage = settings.strings.calendarAccessMustBeChanged
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
                ? settings.strings.calendarAccessGrantedMessage
                : settings.strings.calendarAccessDeniedMessage
            if !granted {
                openAppSettings()
            }
        } catch {
            errorMessage = error.localizedDescription
            calendarAccessMessage = settings.strings.calendarAccessRequestFailed
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
            calendarAccessMessage = settings.strings.shareCalCalendarReady
        } catch {
            errorMessage = error.localizedDescription
            calendarAccessMessage = settings.strings.shareCalCalendarCreationFailed
        }
    }

    @MainActor
    private func prepareShare() async {
        guard !isPreparingShare else { return }
        errorMessage = nil
        guard let cloudKit = services.cloudKitIfAvailable else {
            errorMessage = settings.strings.iCloudSharingUnavailableLocalBuild
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
            cloudKitDiagnosticMessage = settings.strings.iCloudSharingUnavailableLocalBuild
            return
        }

        isCheckingCloudKitAccount = true
        defer { isCheckingCloudKitAccount = false }

        let diagnostic = await cloudKit.accountDiagnostic()
        cloudKitDiagnosticMessage = diagnostic.displayText
        if !diagnostic.isAccountAvailable {
            errorMessage = settings.strings.cloudKitAccountStatus(diagnostic.accountStatus)
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
