import SwiftData
import SwiftUI

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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Binding var focusRequest: CalendarFocusRequest?
    let onOpenSettings: (SettingsFocusTarget) -> Void
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]
    @State private var selectedDate = Date()
    @State private var mode: CalendarMode = .day
    @State private var selectedEvent: EventMirror?
    @State private var selectedJointEvent: JointScheduleEvent?
    @State private var focusedJointEventID: String?
    @State private var activeCalendarSheet: CalendarSheet?
    /// My own events for the whole selected week (the week strip needs all seven days);
    /// `visibleLocalDisplayMirrors` narrows it to what the current mode shows.
    @State private var localDisplayMirrors: [EventMirror] = []
    @State private var authorizationState: CalendarAuthorizationState = .unknown
    @State private var isNightExpanded = false

    var activeMirrors: [EventMirror] {
        mirrors.filter { mirror in
            guard mirror.deletedAt == nil else { return false }
            if mirror.ownerMemberID == settings.currentMemberID {
                return settings.selectedCalendarIDs.contains(mirror.sourceCalendarID)
            }
            return true
        }
    }

    // Anchor keys that currently have at least one live comment. Leaf calendar views compare
    // an event's resolved anchor against this set to show the "has comments" red dot.
    var commentedAnchorKeys: Set<String> {
        EventCommentIndicatorPolicy.commentedAnchorKeys(comments)
    }

    // My own events render as transient "display:" mirrors whose id is not what comments are
    // keyed by; this maps their shared mirrorKey to the persisted twin's real id so the dot
    // (and its resolution) also fires for "partner commented on my event".
    var persistedMirrorIDByKey: [String: String] {
        var map: [String: String] = [:]
        for mirror in mirrors where !mirror.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix) {
            map[mirror.mirrorKey] = mirror.id
        }
        return map
    }

    var isPaired: Bool {
        PairingSettingsPolicy.status(
            hasStartedPairing: settings.hasStartedPairing,
            outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
            incomingOwnerID: settings.partnerShareOwnerID
        ) == .paired
    }

    var visibleMirrors: [EventMirror] {
        CalendarMirrorVisibilityPolicy.memberMirrors(
            activeMirrors,
            currentMemberID: settings.currentMemberID,
            partnerShareOwnerID: settings.partnerShareOwnerID
        ).filter { mirror in
            visibleInterval.contains(mirror.startDate)
        }
    }

    var acceptedJointEvents: [JointScheduleEvent] {
        JointSchedulePolicy.jointEvents(
            from: invitations,
            currentMemberID: settings.currentMemberID,
            partnerMemberID: settings.partnerOwnerIDForLocalData
        )
    }

    var visibleJointEvents: [JointScheduleEvent] {
        acceptedJointEvents.filter { jointEvent in
            visibleInterval.contains(jointEvent.startDate)
        }
    }

    var visibleOrdinaryMirrors: [EventMirror] {
        JointSchedulePolicy.ordinaryMirrors(
            visibleLocalDisplayMirrors + visiblePartnerMirrors,
            excluding: visibleJointEvents
        )
    }

    var visibleLocalDisplayMirrors: [EventMirror] {
        localDisplayMirrors.filter { mirror in
            WeekStripPolicy.overlaps(
                DateInterval(start: mirror.startDate, end: max(mirror.endDate, mirror.startDate)),
                visibleInterval
            )
        }
    }

    var weekInterval: DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: selectedDate)
            ?? DateInterval(start: selectedDate, duration: 7 * 24 * 60 * 60)
    }

    var weekStripDays: [WeekStripDay] {
        func interval(_ start: Date, _ end: Date) -> DateInterval {
            DateInterval(start: start, end: max(end, start))
        }
        let partnerWeekMirrors = CalendarMirrorVisibilityPolicy.memberMirrors(
            activeMirrors,
            currentMemberID: settings.currentMemberID,
            partnerShareOwnerID: settings.partnerShareOwnerID
        ).filter { $0.ownerMemberID == settings.partnerShareOwnerID }
        return WeekStripPolicy.days(
            containing: selectedDate,
            mine: localDisplayMirrors.map { interval($0.startDate, $0.endDate) },
            partner: partnerWeekMirrors.map { interval($0.startDate, $0.endDate) },
            joint: acceptedJointEvents.map { interval($0.startDate, $0.endDate) }
        )
    }

    /// "配对第 N 天": the pairing day is day 1.
    var pairingDayCount: Int? {
        guard isPaired, let pairingDate = settings.pairingDate else { return nil }
        return PairingDatePolicy.ordinalDayNumber(since: pairingDate)
    }

    var myEvents: [EventMirror] {
        visibleOrdinaryMirrors.filter { $0.ownerMemberID == settings.currentMemberID }
    }

    var visiblePartnerMirrors: [EventMirror] {
        visibleMirrors.filter { $0.ownerMemberID == settings.partnerShareOwnerID }
    }

    var partnerEvents: [EventMirror] {
        guard let partnerOwnerID = settings.partnerShareOwnerID else { return [] }
        return visibleOrdinaryMirrors.filter { $0.ownerMemberID == partnerOwnerID }
    }

    var visibleMirrorByID: [String: EventMirror] {
        Dictionary(uniqueKeysWithValues: visibleOrdinaryMirrors.map { ($0.id, $0) })
    }

    var weekAgendaDays: [WeekAgendaDay] {
        WeekAgendaPolicy.days(
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

    var localDisplayRefreshKey: String {
        "\(Int(weekInterval.start.timeIntervalSince1970)):\(Int(weekInterval.end.timeIntervalSince1970)):\(settings.currentMemberID)"
    }

    var setupGuidanceStep: CalendarSetupGuidanceStep? {
        CalendarSetupGuidancePolicy.step(
            hasCompletedInitialProfilePrompt: settings.hasCompletedInitialProfilePrompt,
            currentDisplayName: settings.currentDisplayName,
            authorizationState: authorizationState,
            selectedCalendarIDs: settings.selectedCalendarIDs,
            pairingStatus: PairingSettingsPolicy.status(
                hasStartedPairing: settings.hasStartedPairing,
                outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
                incomingOwnerID: settings.partnerShareOwnerID
            )
        )
    }

    var body: some View {
        let strings = settings.strings

        VStack(spacing: 10) {
            CompactCalendarTopBar(
                selectedDate: $selectedDate,
                mode: $mode,
                title: CalendarDateNavigationPolicy.compactTitle(for: selectedDate, mode: mode, locale: settings.appLanguage.locale),
                subtitle: strings.calendarHeaderSubtitle(
                    weekdayText: selectedDate.formatted(.dateTime.weekday(.wide).locale(settings.appLanguage.locale)),
                    pairingDayCount: pairingDayCount
                ),
                onOpenPicker: {
                    activeCalendarSheet = .datePicker
                },
                onCreateInvite: {
                    activeCalendarSheet = .createInvite
                }
            )
            .padding(.horizontal)
            .padding(.top, 8)

            WeekStrip(days: weekStripDays, selectedDate: $selectedDate)
                .padding(.horizontal, 12)

            if settings.syncPhase == .failed, let lastSyncError = settings.lastSyncError {
                CompactSyncErrorBanner(message: lastSyncError)
                    .padding(.horizontal)
            }

            Group {
                if let setupGuidanceStep {
                    CalendarSetupGuidanceCard(step: setupGuidanceStep) {
                        onOpenSettings(settingsFocusTarget(for: setupGuidanceStep))
                    }
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity, alignment: .center)
                } else if visibleLocalDisplayMirrors.isEmpty && visiblePartnerMirrors.isEmpty && visibleJointEvents.isEmpty {
                    ScrollView {
                        ShareCalEmptyState()
                            .padding(.horizontal)
                            .containerRelativeFrame(.vertical)
                    }
                    .scrollBounceBehavior(.always, axes: [.vertical])
                } else {
                    GeometryReader { proxy in
                        switch mode {
                        case .day:
                            DayAlignedTimelineView(
                                dayStart: selectedDayStart,
                                myTitle: strings.meTitle,
                                myEvents: myEvents,
                                jointEvents: visibleJointEvents,
                                focusedJointEventID: focusedJointEventID,
                                partnerTitle: settings.partnerDisplayName,
                                partnerEvents: partnerEvents,
                                isNightExpanded: $isNightExpanded,
                                availableWidth: proxy.size.width,
                                onSelect: { selectedEvent = $0 },
                                onSelectJoint: { selectedJointEvent = $0 },
                                commentedAnchorKeys: commentedAnchorKeys,
                                persistedMirrorIDByKey: persistedMirrorIDByKey
                            )
                        case .week:
                            WeekAgendaView(
                                days: weekAgendaDays,
                                mirrorByID: visibleMirrorByID,
                                onSelect: { selectedEvent = $0 },
                                onSelectJoint: { item in
                                    selectedJointEvent = visibleJointEvents.first { $0.id == item.id }
                                },
                                commentedAnchorKeys: commentedAnchorKeys,
                                persistedMirrorIDByKey: persistedMirrorIDByKey
                            )
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(swipeNavigationGesture)
            .refreshable {
                await SyncCoordinator.syncIfIdle(services: services, settings: settings, modelContext: modelContext)
            }
            .accessibilityAction(named: Text(strings.previousDateAccessibilityLabel)) {
                moveSelectedDate(.previous)
            }
            .accessibilityAction(named: Text(strings.nextDateAccessibilityLabel)) {
                moveSelectedDate(.next)
            }
        }
        .background(OurDaysTheme.paper)
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
        .sheet(item: $selectedJointEvent) { jointEvent in
            // The joint event is derived from an invitation; look the invitation back up
            // so the detail can anchor its comment thread to it (shared across partners).
            if let invitation = invitations.first(where: { $0.id == jointEvent.id }) {
                JointEventDetailView(event: jointEvent, invitation: invitation)
            }
        }
        .onAppear {
            refreshAuthorizationState()
            consumeFocusRequestIfNeeded()
            refreshLocalDisplayMirrors()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshAuthorizationState()
        }
        .onChange(of: focusRequest) { _, _ in
            consumeFocusRequestIfNeeded()
        }
        .task(id: localDisplayRefreshKey) {
            refreshLocalDisplayMirrors()
        }
    }

    private func consumeFocusRequestIfNeeded() {
        guard let request = focusRequest else { return }
        selectedDate = request.startDate
        mode = .day
        focusedJointEventID = request.invitationID
        focusRequest = nil
    }

    private func refreshAuthorizationState() {
        authorizationState = services.calendarAccess.authorizationState()
    }

    private func settingsFocusTarget(for guidanceStep: CalendarSetupGuidanceStep) -> SettingsFocusTarget {
        switch guidanceStep {
        case .calendarAccess:
            return .calendarAccess
        case .pairing:
            return .pairing
        }
    }

    private var swipeNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard let direction = CalendarSwipeNavigationPolicy.direction(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height
                ) else { return }
                moveSelectedDate(direction)
            }
    }

    private func moveSelectedDate(_ direction: CalendarNavigationDirection) {
        withAnimation(.easeInOut(duration: 0.16)) {
            selectedDate = CalendarDateNavigationPolicy.date(
                afterMoving: selectedDate,
                mode: mode,
                direction: direction
            )
        }
    }

    private func refreshLocalDisplayMirrors() {
        let sourceEvents = services.calendarAccess.authorizedEvents(
            from: weekInterval.start,
            to: weekInterval.end
        )
        let selectedCalendarIDs = settings.selectedCalendarIDs
        localDisplayMirrors = CalendarDisplayMirrorPolicy.displayMirrors(
            from: sourceEvents.filter { selectedCalendarIDs.contains($0.calendarIdentifier) },
            ownerMemberID: settings.currentMemberID
        )
    }
}

struct CompactCalendarTopBar: View {
    @Environment(SettingsStore.self) private var settings
    @Binding var selectedDate: Date
    @Binding var mode: CalendarMode
    let title: String
    let subtitle: String
    let onOpenPicker: () -> Void
    let onCreateInvite: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                onOpenPicker()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("calendar-pairing-status-line")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(title)
                            .font(OurDaysTheme.displayFont(30))
                            .foregroundStyle(OurDaysTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.strings.selectDateAccessibilityLabel)
            .accessibilityValue(title)
            .accessibilityIdentifier("compact-date-picker-button")

            if !Calendar.current.isDateInToday(selectedDate) {
                Button(settings.strings.todayButton) {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OurDaysTheme.ink)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("compact-today-button")
            }

            CompactModeToggle(mode: $mode)
                .frame(width: 96)

            Button(action: onCreateInvite) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(OurDaysTheme.onInkFill)
                    .frame(width: 44, height: 44)
                    .background(OurDaysTheme.inkFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.strings.createInviteAccessibilityLabel)
            .accessibilityIdentifier("compact-create-invite-button")
        }
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
                        .font(.subheadline.weight(mode == item ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(mode == item ? OurDaysTheme.ink : OurDaysTheme.secondaryInk)
                        .background {
                            if mode == item {
                                Capsule()
                                    .fill(OurDaysTheme.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("compact-mode-\(item.rawValue.lowercased())-button")
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(OurDaysTheme.sunken, in: Capsule())
    }
}

/// The selected week as seven tappable days. Under each day, a teal dot means I have
/// something, a coral dot means the partner does, and an ink bar means a joint event —
/// so "who is busy when" reads at a glance without opening each day.
struct WeekStrip: View {
    @Environment(SettingsStore.self) private var settings
    let days: [WeekStripDay]
    @Binding var selectedDate: Date

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days) { day in
                let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDateInToday(day.date)
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedDate = day.date
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow).locale(settings.appLanguage.locale)))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isSelected ? OurDaysTheme.onInkFill.opacity(0.75) : OurDaysTheme.secondaryInk)
                        Text(day.date.formatted(.dateTime.day()))
                            .font(OurDaysTheme.displayFont(17, weight: isSelected || isToday ? .bold : .semibold))
                            .foregroundStyle(isSelected ? OurDaysTheme.onInkFill : OurDaysTheme.ink)
                        dots(for: day, isSelected: isSelected)
                            .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OurDaysTheme.inkFill)
                        } else if isToday {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(OurDaysTheme.border, lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.date.formatted(.dateTime.month().day().weekday(.wide).locale(settings.appLanguage.locale)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func dots(for day: WeekStripDay, isSelected: Bool) -> some View {
        HStack(spacing: 3) {
            if day.hasJoint {
                Capsule()
                    .fill(isSelected ? OurDaysTheme.onInkFill : OurDaysTheme.joint)
                    .frame(width: 10, height: 5)
            }
            if day.hasMine {
                Circle().fill(OurDaysIdentity.me.color).frame(width: 5, height: 5)
            }
            if day.hasPartner {
                Circle().fill(OurDaysIdentity.partner.color).frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

struct CompactSyncErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
            Text(message)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(OurDaysTheme.destructive)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OurDaysIdentity.partner.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ShareCalEmptyState: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ContentUnavailableView {
            Label(settings.strings.noSharedSchedulesTitle, systemImage: "calendar")
        } description: {
            Text(settings.strings.noSharedSchedulesDescription)
        }
    }
}

struct CalendarSetupGuidanceCard: View {
    @Environment(SettingsStore.self) private var settings
    let step: CalendarSetupGuidanceStep
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(OurDaysIdentity.me.color, OurDaysIdentity.partner.color)

            VStack(spacing: 6) {
                Text(title)
                    .font(OurDaysTheme.displayFont(24))
                    .foregroundStyle(OurDaysTheme.ink)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onPrimaryAction) {
                Label(buttonTitle, systemImage: buttonIconName)
            }
            .buttonStyle(OurDaysPrimaryButtonStyle())
            .accessibilityIdentifier("calendar-setup-guidance-button")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(OurDaysTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var title: String {
        switch step {
        case .calendarAccess:
            return settings.strings.setupCalendarAccessTitle
        case .pairing:
            return settings.strings.setupPairingTitle
        }
    }

    private var message: String {
        switch step {
        case .calendarAccess:
            return settings.strings.setupCalendarAccessMessage
        case .pairing:
            return settings.strings.setupPairingMessage
        }
    }

    private var buttonTitle: String {
        switch step {
        case .calendarAccess:
            return settings.strings.setupCalendarAccessButton
        case .pairing:
            return settings.strings.setupPairingButton
        }
    }

    private var iconName: String {
        switch step {
        case .calendarAccess:
            return "calendar.badge.checkmark"
        case .pairing:
            return "person.2.badge.plus"
        }
    }

    private var buttonIconName: String {
        switch step {
        case .calendarAccess:
            return "gearshape"
        case .pairing:
            return "person.badge.plus"
        }
    }
}
