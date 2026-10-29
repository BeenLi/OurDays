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
    @State private var isStoppingShare = false
    @State private var isDeletingICloudData = false
    @State private var activeSharePreparationID: UUID?
    @State private var activeSettingsSheet: SettingsSheet?
    @State private var showStopSharingConfirmation = false

    private var guidePartnerName: String? {
        PairingGuidePolicy.knownPartnerName(
            partnerNoteName: settings.partnerNoteName,
            partnerSyncedDisplayName: settings.partnerSyncedDisplayName
        )
    }

    private var pairingGuideState: PairingGuideState? {
        PairingGuidePolicy.state(
            status: pairingStatus,
            partnerShareOwnerID: settings.displayedIncomingOwnerID,
            sentInviteBackToOwnerID: settings.sentInviteBackToOwnerID,
            isConfirmingAccept: settings.isConfirmingShareAcceptance
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
            incomingOwnerID: settings.displayedIncomingOwnerID
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

    /// The newest history request I sent, shown under the 配对前历史 row.
    private var latestHistoryRequestLine: String? {
        guard let request = UsTabPolicy.latestOutgoingHistoryRequest(
            accessRequests,
            currentMemberID: settings.currentMemberID
        ) else { return nil }
        let strings = settings.strings
        return strings.historyRequestStatusLine(
            rangeText: accessRequestRangeText(for: request),
            statusText: strings.accessRequestStatusTitle(for: request.status)
        )
    }

    private var dataRecoveryView: some View {
        DataRecoveryView(
            isPreparingShare: isPreparingShare,
            canOpenSharedPeople: SharedPeoplePresentationPolicy.canOpenOfficialSharing(
                isCloudKitEnabled: services.isCloudKitEnabled,
                isPreparingShare: isPreparingShare,
                isStoppingShare: isStoppingShare
            ),
            isDeletingICloudData: isDeletingICloudData,
            canDeleteICloudData: services.isCloudKitEnabled && !isDeletingICloudData && !isStoppingShare,
            errorMessage: errorMessage,
            onOpenSharedPeople: {
                Task { await prepareShare(presentation: .appleSharingPanel) }
            },
            onDeleteICloudData: {
                Task { await deleteICloudData() }
            }
        )
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
            inviteLinkMessage: settings.shareAcceptanceFailureMessage,
            guideState: pairingGuideState,
            guidePartnerName: guidePartnerName,
            onStartPairing: {
                Task { await prepareShare(presentation: .inviteSheet) }
            },
            onShowInviteHelp: {
                activeSettingsSheet = .inviteHelp
            },
            onPasteInviteLink: {
                settings.shareAcceptanceFailureMessage = nil
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(OurDaysTheme.destructive)
                            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 4, trailing: 24))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .id(SettingsFocusTarget.pairing)

            Section(strings.usPairSection) {
                ProfileIdentityRow(
                    avatar: settings.currentAvatar,
                    fallbackText: settings.myAvatarFallbackText,
                    identity: .me,
                    avatarLabel: strings.myAvatarLabel,
                    namePlaceholder: strings.myDisplayNamePlaceholder,
                    nameLabel: strings.myNicknameLabel,
                    name: $settings.currentDisplayName,
                    footnote: strings.myProfileFootnote
                ) {
                    activeSettingsSheet = .myAvatar
                }
                if UsTabPolicy.showsPartnerProfileRow(pairingStatus: pairingStatus) {
                    ProfileIdentityRow(
                        avatar: settings.partnerAvatar,
                        fallbackText: settings.partnerAvatarFallbackText,
                        identity: .partner,
                        avatarLabel: strings.partnerAvatarLabel(settings.partnerDisplayName),
                        namePlaceholder: settings.partnerSyncedDisplayName ?? strings.partnerDisplayNamePlaceholder,
                        nameLabel: strings.partnerNicknameEditLabel,
                        name: $settings.partnerNoteName,
                        footnote: strings.partnerProfileFootnote
                    ) {
                        activeSettingsSheet = .partnerAvatar
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
            .listRowBackground(OurDaysTheme.surface)

            Section {
                if UsTabPolicy.showsCalendarPermissionRow(authorizationState) {
                    SettingsNavigationRow(
                        title: strings.calendarPermissionMissingTitle,
                        subtitle: strings.calendarPermissionMissingMessage,
                        value: strings.calendarPermissionTurnOnButton,
                        isLoading: isRequestingCalendarAccess
                    ) {
                        Task { await requestAccess() }
                    } leading: {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(OurDaysTheme.destructive)
                    }
                    .accessibilityIdentifier("settings-calendar-access-button")
                    .disabled(isRequestingCalendarAccess)
                } else {
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
                    Picker(strings.partnerCanSeePicker, selection: $settings.defaultVisibility) {
                        ForEach(EventVisibility.allCases) { visibility in
                            Text(strings.defaultVisibilityLabel(for: visibility)).tag(visibility)
                        }
                    }
                }
                if let calendarAccessMessage {
                    Text(calendarAccessMessage)
                        .font(.caption)
                        .foregroundStyle(authorizationState.canReadEvents ? OurDaysTheme.secondaryInk : OurDaysTheme.destructive)
                }
            } header: {
                Text(strings.calendarsToShareSection)
            } footer: {
                if !UsTabPolicy.showsCalendarPermissionRow(authorizationState) {
                    Text(strings.calendarsToShareFootnote(partnerName: settings.partnerDisplayName))
                }
            }
            .listRowBackground(OurDaysTheme.surface)
            .id(SettingsFocusTarget.calendarAccess)

            if UsTabPolicy.showsPairedSections(pairingStatus: pairingStatus) {
                Section {
                    SharingScopeRow(label: strings.sharingMyCalendarLabel, value: myCalendarScopeValue)
                    SharingScopeRow(label: strings.partnersCalendarLabel, value: partnerCalendarScopeValue)
                    SettingsNavigationRow(
                        title: strings.prePairingHistoryLabel,
                        subtitle: latestHistoryRequestLine,
                        value: prePairingHistoryScopeValue
                    ) {
                        ensurePairingDateIfNeeded()
                        activeSettingsSheet = .historyRequest
                    } leading: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("settings-history-request-button")
                    .disabled(!services.isCloudKitEnabled || settings.pairingDate == nil)
                } header: {
                    Text(strings.sharingScopeTitle)
                } footer: {
                    if let accessRequestMessage {
                        Text(accessRequestMessage)
                    }
                }
                .listRowBackground(OurDaysTheme.surface)
            }

            Section(strings.moreSection) {
                NavigationLink {
                    dataRecoveryView
                } label: {
                    LabeledContent(strings.dataRecoveryTitle, value: strings.dataRecoveryRowValue)
                }
                .accessibilityIdentifier("settings-data-recovery-link")
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
            .listRowBackground(OurDaysTheme.surface)

            if UsTabPolicy.showsPairedSections(pairingStatus: pairingStatus) {
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
        .ourDaysStatusBarCover()
        .refreshable {
            await SyncCoordinator.syncIfIdle(services: services, settings: settings, modelContext: modelContext)
        }
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
            // Calendar permission and the calendar list change in the Settings and Calendar apps.
            refreshCalendars()
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
                    outgoingParticipantIDs: { await fetchOutgoingParticipantIDs() },
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
            let share = try await ShareCalOutgoingSharePrewarm.shared.take(key: settings.currentMemberID) {
                try await cloudKit.prepareShare(ownerMemberID: settings.currentMemberID)
            }
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

    /// Asks CloudKit who has joined my share rather than trusting the last sync: the
    /// inviter may have accepted my letter since, and then this one completes pairing.
    private func fetchOutgoingParticipantIDs() async -> [String] {
        if let cloudKit = services.cloudKitIfAvailable,
           let fetched = try? await cloudKit.fetchOutgoingShareParticipantIDs(ownerMemberID: settings.currentMemberID) {
            return fetched
        }
        return settings.outgoingShareParticipantIDs
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
        let incomingOwnerID = metadata.share.recordID.zoneID.ownerName
        guard !ShareAcceptanceGuardPolicy.requiresReplacementConfirmation(
            incomingOwnerID: incomingOwnerID,
            storedPartnerID: settings.partnerShareOwnerID,
            outgoingParticipantIDs: settings.outgoingShareParticipantIDs
        ) else {
            // Someone other than the current partner: RootView asks first.
            ShareCalCloudKitShareAcceptanceHandler.handle(metadata: metadata)
            return
        }
        // The card moves to the next step at once, marked "confirming with iCloud" until
        // CloudKit has accepted. A failure steps back, and RootView shows the error. Set
        // here as well as on the handler's signal, which lands a hop later: otherwise step 1
        // flashes "joining…" while the paste sheet closes.
        settings.shareAcceptanceFailureMessage = nil
        settings.acceptingShareOwnerID = MemberIDPolicy.normalized(incomingOwnerID)
        isAcceptingInviteLink = true
        Task {
            defer { isAcceptingInviteLink = false }
            try? await ShareCalCloudKitShareAcceptanceHandler.acceptNow(
                metadata: metadata,
                incomingOwnerID: incomingOwnerID
            )
        }
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

        ShareCalOutgoingSharePrewarm.shared.discard()
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
            ShareCalOutgoingSharePrewarm.shared.discard()
            try await cloudKit.deleteICloudData(ownerMemberID: settings.currentMemberID)
            try ShareCalLocalDataCleanupService.purge(modelContext: modelContext)
            cloudKitDiagnosticMessage = nil
            settings.clearPairingState()
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
