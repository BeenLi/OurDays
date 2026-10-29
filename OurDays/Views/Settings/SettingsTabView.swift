import CloudKit
import SwiftData
import SwiftUI
import UIKit

enum SettingsSheet: Identifiable {
    case historyRequest
    case myAvatar
    case partnerAvatar
    case inviteHelp
    case acceptInvite

    var id: String {
        switch self {
        case .historyRequest: "historyRequest"
        case .myAvatar: "myAvatar"
        case .partnerAvatar: "partnerAvatar"
        case .inviteHelp: "inviteHelp"
        case .acceptInvite: "acceptInvite"
        }
    }
}

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Binding var focus: SettingsFocusTarget?
    @Query(sort: \CalendarAccessRequest.createdAt) private var accessRequests: [CalendarAccessRequest]
    @State private var authorizationState: CalendarAuthorizationState = .unknown
    @State private var calendars: [CalendarDescriptor] = []
    @State private var preparedShare: PreparedCloudShare?
    @State private var inviteDraft: PairingInviteDraft?
    /// Set when the invite sheet hands off to Apple's panel; shown once the sheet is gone.
    @State private var pendingAppleSharingShare: PreparedCloudShare?
    @State private var errorMessage: String?
    @State private var accessRequestMessage: String?
    @State private var calendarAccessMessage: String?
    @State private var isRequestingCalendarAccess = false
    @State private var cloudKitDiagnosticMessage: String?
    @State private var isCheckingCloudKitAccount = false
    @State private var isPreparingShare = false
    @State private var iCloudProblem: ICloudAvailabilityPolicy.Problem?
    @State private var isAcceptingInviteLink = false
    @State private var inviteLinkMessage: String?
    @State private var isStoppingShare = false
    @State private var isDeletingICloudData = false
    @State private var activeSharePreparationID: UUID?
    @State private var activeSettingsSheet: SettingsSheet?
    @State private var showStopSharingConfirmation = false
    @State private var showDeleteICloudDataConfirmation = false

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

    private var pendingIncomingAccessRequests: [CalendarAccessRequest] {
        CalendarAccessRequestListPolicy.pendingIncoming(
            accessRequests,
            currentMemberID: settings.currentMemberID
        )
    }

    private var outgoingAccessRequests: [CalendarAccessRequest] {
        CalendarAccessRequestListPolicy.outgoing(accessRequests, currentMemberID: settings.currentMemberID)
    }

    private var guidePartnerName: String? {
        PairingGuidePolicy.knownPartnerName(
            partnerNoteName: settings.partnerNoteName,
            partnerSyncedDisplayName: settings.partnerSyncedDisplayName
        )
    }

    private var pairingGuideState: PairingGuideState? {
        PairingGuidePolicy.state(
            status: pairingStatus,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            sentInviteBackToOwnerID: settings.sentInviteBackToOwnerID
        )
    }

    private var syncStatusText: String {
        let strings = settings.strings
        if settings.syncPhase == .syncing {
            return strings.syncingSelectedCalendars
        }
        if let lastSyncAt = settings.lastSyncAt {
            return strings.lastSyncStatus(lastSyncAt.formatted(date: .omitted, time: .shortened))
        }
        return strings.notSyncedYet
    }

    private var pairingStatus: PairingStatus {
        PairingSettingsPolicy.status(
            hasStartedPairing: settings.hasStartedPairing,
            outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
            incomingOwnerID: settings.partnerShareOwnerID
        )
    }

    private var ownerMemberIDForPartnerHistory: String {
        settings.partnerOwnerIDForLocalData
    }

    private var myCalendarScopeValue: String {
        sharingScopeValue(
            direction: .meSharedToPartner,
            ownerMemberID: nil
        )
    }

    private var partnerCalendarScopeValue: String {
        sharingScopeValue(
            direction: .partnerSharedToMe,
            ownerMemberID: ownerMemberIDForPartnerHistory
        )
    }

    private var prePairingHistoryScopeValue: String {
        let strings = settings.strings
        guard let pairingDate = settings.pairingDate else {
            return strings.requestRequiredValue
        }
        let calendar = Calendar.current
        let normalizedPairingDate = PairingDatePolicy.normalizedPairingDate(pairingDate, calendar: calendar)
        let authorizedStartDate = PrePairingHistoryAccessPolicy.contiguousAuthorizedStartDate(
            pairingDate: normalizedPairingDate,
            accessRequests: accessRequests,
            currentMemberID: settings.currentMemberID,
            ownerMemberID: ownerMemberIDForPartnerHistory,
            direction: .partnerSharedToMe,
            calendar: calendar
        )
        guard authorizedStartDate < normalizedPairingDate else {
            return strings.requestRequiredValue
        }
        return strings.historyAuthorizedFromValue(authorizedStartDate)
    }

    private var nextHistoryRequestRange: PairingHistoryRequestRange {
        let pairingDate = settings.pairingDate ?? PairingDatePolicy.normalizedPairingDate(.now)
        return PrePairingHistoryAccessPolicy.defaultNextRequestRange(
            pairingDate: pairingDate,
            accessRequests: accessRequests,
            currentMemberID: settings.currentMemberID,
            ownerMemberID: ownerMemberIDForPartnerHistory
        )
    }

    private func sharingScopeValue(
        direction: PrePairingHistoryAccessPolicy.Direction,
        ownerMemberID: String?
    ) -> String {
        let strings = settings.strings
        guard let pairingDate = settings.pairingDate else {
            return strings.sharedAfterPairingDateValue
        }
        let calendar = Calendar.current
        let normalizedPairingDate = PairingDatePolicy.normalizedPairingDate(pairingDate, calendar: calendar)
        let authorizedStartDate = PrePairingHistoryAccessPolicy.contiguousAuthorizedStartDate(
            pairingDate: normalizedPairingDate,
            accessRequests: accessRequests,
            currentMemberID: settings.currentMemberID,
            ownerMemberID: ownerMemberID,
            direction: direction,
            calendar: calendar
        )
        guard authorizedStartDate < normalizedPairingDate else {
            return strings.sharedAfterPairingDateValue
        }
        return strings.sharedAfterDateValue(authorizedStartDate)
    }

    /// Kept out of `body` so the type checker handles the card's long argument list on its own.
    private var pairingStatusCard: some View {
        PairingStatusCard(
            status: pairingStatus,
            pairingDate: settings.pairingDate,
            partnerName: settings.partnerStatusDisplayName,
            syncStatusText: syncStatusText,
            isCloudKitEnabled: services.isCloudKitEnabled,
            isPreparingShare: isPreparingShare,
            isCheckingCloudKitAccount: isCheckingCloudKitAccount,
            isSyncing: settings.syncPhase == .syncing,
            cloudKitDiagnosticMessage: cloudKitDiagnosticMessage,
            iCloudProblem: iCloudProblem,
            isAcceptingInviteLink: isAcceptingInviteLink,
            inviteLinkMessage: inviteLinkMessage,
            guideState: pairingGuideState,
            guidePartnerName: guidePartnerName,
            onStartPairing: {
                Task { await prepareShare(presentation: .inviteSheet) }
            },
            onShowInviteHelp: {
                activeSettingsSheet = .inviteHelp
            },
            onPasteInviteLink: {
                inviteLinkMessage = nil
                activeSettingsSheet = .acceptInvite
            },
            onCheckCloudKitStatus: {
                Task { await checkCloudKitStatus() }
            },
            onSync: {
                syncNow()
            },
            onEditMyAvatar: {
                activeSettingsSheet = .myAvatar
            },
            onEditPartnerAvatar: {
                activeSettingsSheet = .partnerAvatar
            },
            onHideCloudKitDiagnostic: {
                cloudKitDiagnosticMessage = nil
            }
        )
        .onChange(of: pairingStatus) { _, _ in
            // "Joining…" or a paste error belongs to the step it was shown on.
            inviteLinkMessage = nil
        }
    }

    private func inviteSheet(for draft: PairingInviteDraft) -> some View {
        PairingInviteSheet(
            draft: draft,
            partnerName: guidePartnerName,
            onSent: {
                // Only now has a letter left the phone; a cancelled sheet leaves the
                // guide on the step it was on.
                markPairingStarted()
                if draft.isSendingBack {
                    settings.sentInviteBackToOwnerID = settings.partnerShareOwnerID
                }
            },
            onUseAppleSheet: {
                markPairingStarted()
                pendingAppleSharingShare = draft.preparedShare
            }
        )
    }

    private func markPairingStarted() {
        settings.iCloudSharingEnabled = true
        settings.hasStartedPairing = true
        settings.markPairingDateIfNeeded()
    }

    private func presentPendingAppleSharingShare() {
        guard let share = pendingAppleSharingShare else { return }
        pendingAppleSharingShare = nil
        preparedShare = share
    }

    var body: some View {
        @Bindable var settings = settings
        let strings = settings.strings

        ScrollViewReader { proxy in
            List {
                Section {
                    OurDaysPageHeader(title: strings.usTitle, subtitle: strings.usSubtitle)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    pairingStatusCard
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .id(SettingsFocusTarget.pairing)

            if pairingStatus != .notPaired {
                Section(strings.sharingScopeTitle) {
                    SharingScopeRow(label: strings.sharingMyCalendarLabel, value: myCalendarScopeValue)
                    SharingScopeRow(label: strings.partnersCalendarLabel, value: partnerCalendarScopeValue)
                    SharingScopeRow(label: strings.prePairingHistoryLabel, value: prePairingHistoryScopeValue)
                }
                .listRowBackground(OurDaysTheme.surface)
            }

            Section(strings.moreSection) {
                if pairingStatus != .notPaired {
                    SettingsNavigationRow(title: strings.requestHistoryAccessButton) {
                        ensurePairingDateIfNeeded()
                        activeSettingsSheet = .historyRequest
                    } leading: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .disabled(!services.isCloudKitEnabled || settings.pairingDate == nil)
                }
                SettingsNavigationRow(
                    title: strings.sharedPeopleRowTitle,
                    isLoading: isPreparingShare
                ) {
                    Task { await prepareShare(presentation: .appleSharingPanel) }
                } leading: {
                    Image(systemName: "person.2.badge.gearshape")
                }
                .accessibilityIdentifier("shared-people-official-share-button")
                .disabled(!SharedPeoplePresentationPolicy.canOpenOfficialSharing(
                    isCloudKitEnabled: services.isCloudKitEnabled,
                    isPreparingShare: isPreparingShare,
                    isStoppingShare: isStoppingShare
                ))
            }
            .listRowBackground(OurDaysTheme.surface)

            if PairingSafetyEducationPolicy.shouldShowPersistentWarning(pairingStatus: pairingStatus) {
                Section(strings.pairingSafetySection) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(strings.pairingSafetyPersistentWarningTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(strings.pairingSafetyPersistentWarningMessage)
                                .font(.caption)
                                .foregroundStyle(OurDaysTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
                .listRowBackground(OurDaysTheme.surface)
            }

            Section(strings.profileSection) {
                SettingsNavigationRow(title: strings.myAvatarLabel) {
                    activeSettingsSheet = .myAvatar
                } leading: {
                    MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: 28)
                }
                LabeledContent {
                    TextField(
                        strings.myDisplayNamePlaceholder,
                        text: $settings.currentDisplayName
                    )
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(strings.myNicknameLabel)
                } label: {
                    Text(strings.myNicknameLabel)
                }
                LabeledContent {
                    TextField(
                        strings.partnerDisplayNamePlaceholder,
                        text: $settings.partnerNoteName
                    )
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(strings.partnerNicknameEditLabel)
                } label: {
                    Text(strings.partnerNicknameEditLabel)
                }
                if pairingStatus != .notPaired {
                    SettingsNavigationRow(
                        title: strings.partnerAvatarLabel(settings.partnerDisplayName),
                        subtitle: strings.partnerAvatarFootnote
                    ) {
                        activeSettingsSheet = .partnerAvatar
                    } leading: {
                        MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: 28)
                    }
                }
            }
            .listRowBackground(OurDaysTheme.surface)

            Section(strings.languageSection) {
                Picker(strings.appLanguagePicker, selection: $settings.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(strings.languageDisplayName(for: language)).tag(language)
                    }
                }
            }

            Section(strings.calendarAccessSection) {
                LabeledContent(strings.statusLabel, value: strings.calendarAuthorizationStatusText(authorizationState))
                Button(calendarAccessButtonTitle) {
                    Task { await requestAccess() }
                }
                .accessibilityIdentifier("settings-calendar-access-button")
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
            .id(SettingsFocusTarget.calendarAccess)

            Section(strings.calendarsToShareSection) {
                if ShareCalCalendarBootstrapPolicy.shouldOfferCreation(calendars: calendars) {
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

            Section(strings.accessRequestSection) {
                if !pendingIncomingAccessRequests.isEmpty {
                    Text(strings.pendingAccessRequestsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(pendingIncomingAccessRequests) { request in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(strings.incomingHistoryRequestText(
                                requester: displayName(forRequesterMemberID: request.requesterMemberID),
                                rangeText: accessRequestRangeText(for: request)
                            ))
                            .font(.subheadline.weight(.semibold))
                            Text(strings.prePairingHistoryLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button(strings.approveButton) {
                                    update(request, status: .approved)
                                }
                                .buttonStyle(.borderedProminent)
                                Button(strings.declineButton, role: .destructive) {
                                    update(request, status: .declined)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !outgoingAccessRequests.isEmpty {
                    Text(strings.outgoingAccessRequestsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(outgoingAccessRequests) { request in
                        LabeledContent(
                            accessRequestRangeText(for: request),
                            value: strings.accessRequestStatusTitle(for: request.status)
                        )
                    }
                }

                if let accessRequestMessage {
                    Text(accessRequestMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(strings.syncSection) {
                LabeledContent(strings.lastSyncLabel, value: settings.lastSyncAt.map(strings.abbreviatedDateTimeText) ?? strings.never)
                Button(
                    isDeletingICloudData ? strings.deletingICloudDataButton : strings.deleteICloudDataButton,
                    role: .destructive
                ) {
                    showDeleteICloudDataConfirmation = true
                }
                .disabled(!services.isCloudKitEnabled || isDeletingICloudData || isStoppingShare)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            Section(strings.aboutSection) {
                LabeledContent(strings.versionLabel, value: AppLegalInfo.versionText)
                if let icpNumber = AppLegalInfo.icpFilingNumber {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(strings.icpFilingLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(icpNumber)
                        Link("beian.miit.gov.cn", destination: AppLegalInfo.icpFilingSystemURL)
                            .font(.footnote)
                    }
                }
            }

            if pairingStatus != .notPaired {
                Section {
                    Button(strings.unpairButton, role: .destructive) {
                        showStopSharingConfirmation = true
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!services.isCloudKitEnabled || isStoppingShare)
                }
                .listRowBackground(OurDaysTheme.surface)
            }
        }
        .listSectionSpacing(20)
        .ourDaysListBackground()
        .navigationTitle(strings.settingsTitle)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            authorizationState = services.calendarAccess.authorizationState()
            refreshCalendars()
            ensurePairingDateIfNeeded()
            consumeSettingsFocus(with: proxy)
            await refreshICloudProblem()
        }
        .onChange(of: scenePhase) { _, phase in
            // The fix for an iCloud problem happens in the Settings app; re-check on return.
            guard phase == .active else { return }
            Task { await refreshICloudProblem() }
        }
        .onChange(of: focus) { _, _ in
            consumeSettingsFocus(with: proxy)
        }
        .sheet(item: $preparedShare) { share in
            CloudSharingController(
                preparedShare: share,
                onError: { message in
                    errorMessage = strings.cloudKitShareFailed(message)
                },
                onStoppedSharing: {
                    clearLocalPairingAfterSharingStopped()
                }
            )
        }
        .sheet(item: $inviteDraft, onDismiss: presentPendingAppleSharingShare) { draft in
            // Read the live draft: its link fills in after the sheet is already up.
            inviteSheet(for: inviteDraft ?? draft)
        }
        .sheet(item: $activeSettingsSheet) { sheet in
            switch sheet {
            case .historyRequest:
                HistoryRequestSheet(
                    pairingDate: settings.pairingDate ?? PairingDatePolicy.normalizedPairingDate(.now),
                    initialRange: nextHistoryRequestRange
                ) { startDate, endDate in
                    sendAccessRequest(startDate: startDate, endDate: endDate)
                }
            case .myAvatar:
                AvatarEditorSheet(
                    title: strings.myAvatarLabel,
                    avatar: settings.currentAvatar,
                    fallbackText: settings.myAvatarFallbackText,
                    identity: .me,
                    footnote: strings.avatarSyncFootnote(settings.partnerDisplayName)
                ) { avatar in
                    settings.currentAvatar = MemberAvatarPolicy.normalized(avatar)
                    if pairingStatus != .notPaired {
                        syncNow()
                    }
                }
            case .inviteHelp:
                InviteLinkHelpSheet()
            case .acceptInvite:
                AcceptInviteLinkSheet(
                    lookUp: { url in await lookUpInvite(url) },
                    knownName: { ownerID in knownInviterName(ownerID) },
                    completesPairing: pairingStatus == .waitingForPartnerToShare,
                    onAccept: { metadata in acceptInvite(metadata) }
                )
            case .partnerAvatar:
                AvatarEditorSheet(
                    title: strings.partnerAvatarLabel(settings.partnerDisplayName),
                    avatar: settings.partnerAvatarOverride,
                    defaultAvatar: settings.partnerSyncedAvatar,
                    fallbackText: settings.partnerAvatarFallbackText,
                    identity: .partner,
                    footnote: strings.partnerAvatarFootnote
                ) { avatar in
                    settings.partnerAvatarOverride = MemberAvatarPolicy.normalized(avatar)
                }
            }
        }
        .alert(strings.unpairConfirmationTitle, isPresented: $showStopSharingConfirmation) {
            Button(strings.unpairButton, role: .destructive) {
                Task { await stopSharing() }
            }
            Button(strings.cancelButton, role: .cancel) {}
        } message: {
            Text(strings.unpairConfirmationMessage)
        }
        .alert(strings.deleteICloudDataConfirmationTitle, isPresented: $showDeleteICloudDataConfirmation) {
            Button(strings.deleteICloudDataButton, role: .destructive) {
                Task { await deleteICloudData() }
            }
            Button(strings.cancelButton, role: .cancel) {}
        } message: {
            Text(strings.deleteICloudDataConfirmationMessage)
        }
    }
    }

    private func consumeSettingsFocus(with proxy: ScrollViewProxy) {
        guard let focus else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(focus == .shareBack ? SettingsFocusTarget.pairing : focus, anchor: .top)
            }
            self.focus = nil
            if focus == .shareBack {
                Task { await prepareShare(presentation: .inviteSheet) }
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
           let shareCalCalendar = calendars.first(where: ShareCalCalendarBootstrapPolicy.isShareCalCalendar) {
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPolicy.selectedCalendarIDs(
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
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPolicy.selectedCalendarIDs(
                afterEnsuring: calendar,
                currentSelection: settings.selectedCalendarIDs
            )
            calendarAccessMessage = settings.strings.shareCalCalendarReady
        } catch {
            errorMessage = error.localizedDescription
            calendarAccessMessage = settings.strings.shareCalCalendarCreationFailed
        }
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

    private func ensurePairingDateIfNeeded() {
        guard pairingStatus != .notPaired else { return }
        settings.markPairingDateIfNeeded()
    }

    @discardableResult
    private func sendAccessRequest(startDate: Date, endDate: Date) -> Bool {
        errorMessage = nil
        accessRequestMessage = nil

        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedDisplayedEndDate = calendar.startOfDay(for: endDate)
        let exclusiveEndDate = PairingDatePolicy.exclusiveEndDate(
            forDisplayedEndDate: normalizedDisplayedEndDate,
            calendar: calendar
        )

        guard exclusiveEndDate > normalizedStartDate else {
            accessRequestMessage = settings.strings.invalidAccessRequestRangeMessage
            return false
        }

        let validation = PrePairingHistoryAccessPolicy.validation(
            requestedStartDate: normalizedStartDate,
            requestedEndDate: exclusiveEndDate,
            pairingDate: settings.pairingDate ?? PairingDatePolicy.normalizedPairingDate(.now),
            accessRequests: accessRequests,
            currentMemberID: settings.currentMemberID,
            ownerMemberID: ownerMemberIDForPartnerHistory,
            calendar: calendar
        )
        switch validation {
        case .valid:
            break
        case .invalidRange:
            accessRequestMessage = settings.strings.invalidAccessRequestRangeMessage
            return false
        case .alreadyAuthorized:
            accessRequestMessage = settings.strings.accessRequestAlreadyAuthorizedMessage
            return false
        case .overlapsAuthorized:
            accessRequestMessage = settings.strings.accessRequestOverlapsAuthorizedMessage
            return false
        case .overlapsExistingRequest:
            accessRequestMessage = settings.strings.accessRequestOverlapsExistingRequestMessage
            return false
        }

        let request = CalendarAccessRequest(
            requesterMemberID: settings.currentMemberID,
            ownerMemberID: ownerMemberIDForPartnerHistory,
            requestedStartDate: normalizedStartDate,
            requestedEndDate: exclusiveEndDate,
            sourceRawValue: CalendarAccessRequestSource.localOutgoing.rawValue
        )
        modelContext.insert(request)
        do {
            try modelContext.save()
            accessRequestMessage = settings.strings.accessRequestSentMessage
            saveAccessRequestToCloudKit(request)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func update(_ request: CalendarAccessRequest, status: CalendarAccessRequestStatus) {
        errorMessage = nil
        accessRequestMessage = nil

        request.status = status
        do {
            try modelContext.save()
            accessRequestMessage = settings.strings.accessRequestUpdatedMessage
            saveAccessRequestToCloudKit(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAccessRequestToCloudKit(_ request: CalendarAccessRequest) {
        guard let cloudKit = services.cloudKitIfAvailable else { return }
        Task {
            do {
                try await cloudKit.saveCalendarAccessRequestForSync(
                    request,
                    currentMemberID: settings.currentMemberID
                )
            } catch {
                errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            }
        }
    }

    private func accessRequestRangeText(for request: CalendarAccessRequest) -> String {
        let start = settings.strings.abbreviatedDateText(request.requestedStartDate)
        let displayedEndDate = PairingDatePolicy.displayedEndDate(forExclusiveEndDate: request.requestedEndDate)
        let end = settings.strings.abbreviatedDateText(displayedEndDate)
        return "\(start) - \(end)"
    }

    private func displayName(forRequesterMemberID requesterMemberID: String) -> String {
        MemberDisplayNamePolicy.displayName(
            forMemberID: requesterMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }

    private enum SharePresentation {
        /// The pairing guide's invite sheet: our message with the link inside it.
        case inviteSheet
        /// Apple's UICloudSharingController, for managing who is on the share.
        case appleSharingPanel
    }

    @MainActor
    private func prepareShare(presentation: SharePresentation) async {
        guard !isPreparingShare else { return }
        errorMessage = nil
        guard let cloudKit = services.cloudKitIfAvailable else {
            errorMessage = settings.strings.iCloudSharingUnavailableLocalBuild
            return
        }
        guard let displayName = PairingSettingsPolicy.normalizedDisplayName(settings.currentDisplayName) else {
            errorMessage = settings.strings.currentDisplayNameRequiredMessage
            return
        }
        settings.currentDisplayName = displayName

        let preparationID = UUID()
        activeSharePreparationID = preparationID
        isPreparingShare = true
        // Making the link takes several CloudKit round trips; open the invite sheet on
        // the tap and let the link fill in, instead of a few silent seconds.
        let draftID: UUID?
        if presentation == .inviteSheet {
            let draft = PairingInviteDraft(isSendingBack: pairingStatus == .waitingForYouToShare)
            inviteDraft = draft
            draftID = draft.id
        } else {
            draftID = nil
        }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await MainActor.run {
                guard activeSharePreparationID == preparationID else { return }
                errorMessage = CloudKitSharingError.operationTimedOut("share preparation").localizedDescription
                isPreparingShare = false
                activeSharePreparationID = nil
                if let draftID, inviteDraft?.id == draftID { inviteDraft = nil }
            }
        }
        defer { timeoutTask.cancel() }

        do {
            if !settings.hasSyncedMemberID {
                settings.currentMemberID = try await cloudKit.fetchCurrentUserRecordID()
            }
            let share = try await cloudKit.prepareShare(ownerMemberID: settings.currentMemberID)
            guard activeSharePreparationID == preparationID else { return }
            settings.outgoingShareParticipantIDs = CloudKitShareParticipantIdentityPolicy.acceptedParticipantIDs(
                from: share.share
            )
            if let draftID {
                if inviteDraft?.id == draftID {
                    if share.share.url != nil {
                        inviteDraft?.preparedShare = share
                    } else {
                        // No link to put in a message; Apple's panel can still invite.
                        // It opens once the invite sheet is gone (onDismiss).
                        markPairingStarted()
                        pendingAppleSharingShare = share
                        inviteDraft = nil
                    }
                }
            } else {
                markPairingStarted()
                preparedShare = share
            }
            // The partner reads my nickname from this record. It can follow the link:
            // a failure here must not close a sheet that already works, and the next
            // sync saves the profile again.
            try? await cloudKit.saveMemberProfileForSync(
                ownerMemberID: settings.currentMemberID,
                displayName: displayName,
                avatar: settings.currentAvatar
            )
        } catch {
            guard activeSharePreparationID == preparationID else { return }
            if let draftID, inviteDraft?.id == draftID { inviteDraft = nil }
            errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
        }
        isPreparingShare = false
        activeSharePreparationID = nil
    }

    @MainActor
    private func refreshICloudProblem() async {
        guard pairingStatus != .paired, let cloudKit = services.cloudKitIfAvailable else {
            iCloudProblem = nil
            return
        }
        iCloudProblem = ICloudAvailabilityPolicy.problem(for: await cloudKit.accountStatus())
    }

    /// Looks up an invite link copied from a chat app. Links tapped inside WeChat open the
    /// icloud.com web page (which can only ask for an Apple ID sign-in) instead of the app.
    @MainActor
    private func lookUpInvite(_ url: URL) async -> Result<CKShare.Metadata, ShareInvitationLinkPolicy.Failure> {
        guard let cloudKit = services.cloudKitIfAvailable else {
            return .failure(.other(settings.strings.iCloudSharingUnavailableLocalBuild))
        }
        isAcceptingInviteLink = true
        defer { isAcceptingInviteLink = false }
        do {
            let metadata = try await cloudKit.fetchShareMetadata(from: url)
            guard metadata.participantRole != .owner else { return .failure(.ownLink) }
            return .success(metadata)
        } catch {
            cloudKitSharingError("lookUpInvite failed error=\(describeCloudKitFailure(error))")
            let failure = ShareInvitationLinkPolicy.failure(for: error)
            if failure == .iCloudUnavailable {
                await refreshICloudProblem()
            }
            return .failure(failure)
        }
    }

    /// A nickname only for someone already on one half of this pairing; a stranger's
    /// invite reads "TA" rather than exposing their Apple ID name.
    private func knownInviterName(_ ownerID: String) -> String? {
        let knownIDs = Set(([settings.partnerShareOwnerID] + settings.outgoingShareParticipantIDs).compactMap {
            MemberIDPolicy.normalized($0)
        })
        guard knownIDs.contains(ownerID) else { return nil }
        return PairingGuidePolicy.knownPartnerName(
            partnerNoteName: settings.partnerNoteName,
            partnerSyncedDisplayName: settings.partnerSyncedDisplayName
        )
    }

    /// The user confirmed whose invite it is; hand it to the same path a tapped link takes.
    private func acceptInvite(_ metadata: CKShare.Metadata) {
        ShareCalCloudKitShareAcceptanceHandler.handle(metadata: metadata)
        inviteLinkMessage = settings.strings.inviteLinkAccepted
    }

    @MainActor
    private func clearLocalPairingAfterSharingStopped() {
        let localOwnerIDsToPurge = ICloudSharingTeardownPolicy.localOwnerIDsToPurge(
            partnerShareOwnerID: settings.partnerShareOwnerID
        )
        var purgeError: Error?
        do {
            try ShareCalLocalDataCleanupService.purgeSharedOwnerData(
                ownerMemberIDs: localOwnerIDsToPurge,
                modelContext: modelContext
            )
        } catch {
            purgeError = error
        }

        preparedShare = nil
        cloudKitDiagnosticMessage = nil
        settings.clearPairingState()

        if let purgeError {
            errorMessage = purgeError.localizedDescription
        } else {
            errorMessage = settings.strings.unpairSucceeded
        }
    }

    @MainActor
    private func stopSharing() async {
        guard !isStoppingShare else { return }
        errorMessage = nil
        guard let cloudKit = services.cloudKitIfAvailable else {
            errorMessage = settings.strings.iCloudSharingUnavailableLocalBuild
            return
        }

        isStoppingShare = true
        defer { isStoppingShare = false }

        do {
            try await cloudKit.stopSharing(ownerMemberID: settings.currentMemberID)
        } catch {
            errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            return
        }
        // The share is gone, so local pairing state must be cleared whatever happens
        // next. The partner can no longer read my zone, but whatever they left in it
        // would ride into the next share: clean it out now (PartnerScopedDataPolicy); a
        // failure here is reported, and the import-time filter still hides the leftovers.
        var cleanupError: Error?
        do {
            try await cloudKit.purgeExPartnerRecordsFromPrivateZone(currentMemberID: settings.currentMemberID)
        } catch {
            cleanupError = error
        }
        // Pairing is two shares. Deleting mine only takes back my half; also leave the
        // partner's share, or they still see me on theirs and sit at "waiting for your
        // partner to share" instead of going back to not paired.
        do {
            try await cloudKit.deleteAcceptedSharedZones(
                ownerIDs: [settings.partnerShareOwnerID].compactMap { MemberIDPolicy.normalized($0) }
            )
        } catch {
            cleanupError = cleanupError ?? error
        }
        clearLocalPairingAfterSharingStopped()
        if let cleanupError {
            errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: cleanupError)
        }
    }

    @MainActor
    private func deleteICloudData() async {
        guard !isDeletingICloudData else { return }
        errorMessage = nil
        guard let cloudKit = services.cloudKitIfAvailable else {
            errorMessage = settings.strings.iCloudSharingUnavailableLocalBuild
            return
        }

        isDeletingICloudData = true
        defer { isDeletingICloudData = false }

        do {
            try await cloudKit.deleteICloudData(ownerMemberID: settings.currentMemberID)
            try ShareCalLocalDataCleanupService.purge(modelContext: modelContext)
            cloudKitDiagnosticMessage = nil
            settings.iCloudSharingEnabled = false
            settings.hasStartedPairing = false
            settings.partnerShareOwnerID = nil
            settings.partnerNoteName = ""
            settings.hasPromptedPartnerNoteForCurrentPairing = false
            settings.hasShownPairingSafetyNoticeForCurrentPairing = false
            settings.partnerSyncedDisplayName = nil
            settings.clearPartnerAvatars()
            settings.outgoingShareParticipantIDs = []
            settings.pairingConflict = nil
            settings.clearPairingDate()
            settings.lastSyncAt = nil
            settings.lastSyncError = nil
            settings.syncPhase = .idle
            errorMessage = settings.strings.deleteICloudDataSucceeded
        } catch {
            errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
        }
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
        cloudKitDiagnosticMessage = localPairingDiagnosticText(cloudKitDiagnostic: diagnostic)
        if !diagnostic.isAccountAvailable {
            errorMessage = settings.strings.cloudKitAccountStatus(diagnostic.accountStatus)
        }
    }

    private func localPairingDiagnosticText(cloudKitDiagnostic: CloudKitAccountDiagnostic) -> String {
        [
            "Member ID: \(diagnosticShortCode(settings.currentMemberID))",
            "Partner Owner ID: \(diagnosticShortCode(settings.partnerShareOwnerID))",
            "",
            cloudKitDiagnostic.displayText
        ].joined(separator: "\n")
    }

    private func diagnosticShortCode(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "none"
        }
        return String(value.prefix(12))
    }
}

// MARK: - Design language ("纸上双线")
