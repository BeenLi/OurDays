import CloudKit
import SwiftData
import SwiftUI

enum ShareCalTab {
    case calendar
    case activity
    case invites
    case settings
}

enum SettingsFocusTarget: Hashable {
    case calendarAccess
    case pairing
}

enum RootSheet: Identifiable, Equatable {
    case initialProfilePrompt
    case existingICloudDataRecovery
    case partnerNotePrompt
    case pairingSafetyNotice

    var id: String {
        switch self {
        case .initialProfilePrompt:
            return "initialProfilePrompt"
        case .existingICloudDataRecovery:
            return "existingICloudDataRecovery"
        case .partnerNotePrompt:
            return "partnerNotePrompt"
        case .pairingSafetyNotice:
            return "pairingSafetyNotice"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @State private var isRunningForegroundSync = false
    @State private var selectedTab: ShareCalTab = .calendar
    @State private var calendarFocusRequest: CalendarFocusRequest?
    @State private var settingsFocus: SettingsFocusTarget?
    @State private var activeRootSheet: RootSheet?
    @State private var hasEvaluatedExistingICloudDataPrompt = false
    @State private var pendingReplacementOwnerID: String?
    @State private var showPairingConflictAlert = false
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @Query(sort: \CalendarAccessRequest.createdAt) private var accessRequests: [CalendarAccessRequest]
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]

    private var pairingStatus: PairingStatus {
        PairingSettingsPlan.status(
            hasStartedPairing: settings.hasStartedPairing,
            outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
            incomingOwnerID: settings.partnerShareOwnerID
        )
    }

    private var pendingInviteBadgeCount: Int {
        PendingActionBadgePlan.count(
            invitations: invitations,
            accessRequests: accessRequests,
            currentMemberID: settings.currentMemberID
        )
    }

    private var unreadActivityCount: Int {
        ActivityFeedPlan.unreadCount(
            comments: comments,
            currentMemberID: settings.currentMemberID,
            lastSeenActivityAt: settings.lastSeenActivityAt
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarTabView(
                    focusRequest: $calendarFocusRequest,
                    onOpenSettings: { focus in
                        settingsFocus = focus
                        selectedTab = .settings
                    }
                )
            }
            .tabItem {
                Label(settings.strings.calendarTab, systemImage: "calendar")
            }
            .tag(ShareCalTab.calendar)

            NavigationStack {
                ActivityTabView()
            }
            .tabItem {
                Label(settings.strings.activityTab, systemImage: "bubble.left.and.bubble.right")
            }
            .badge(unreadActivityCount)
            .tag(ShareCalTab.activity)

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
            .badge(pendingInviteBadgeCount)
            .tag(ShareCalTab.invites)

            NavigationStack {
                SettingsTabView(focus: $settingsFocus)
            }
            .tabItem {
                Label(settings.strings.settingsTab, systemImage: "gearshape")
            }
            .tag(ShareCalTab.settings)
        }
        .task {
            await Task.yield()
            await reevaluateRootSheetFlow()
        }
        .onReceive(NotificationCenter.default.publisher(for: ShareCalAcceptedShareSignal.notificationName)) { _ in
            Task {
                checkPendingShareReplacement()
                await syncAfterAcceptedShareIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ShareCalRemoteChangeSignal.notificationName)) { _ in
            // A CloudKit push reported remote changes. Force a pull (bypassing the
            // time-based automatic-sync throttle) so a recent sync doesn't cause us to
            // skip and miss the partner activity — and its local notifications — the
            // push just told us about. Still honor the existing-iCloud-data recovery
            // gate: don't sync/merge before the user has resolved that decision.
            Task {
                guard !shouldDeferAutomaticSyncForExistingICloudDecision else { return }
                await runForegroundSync(consumingAcceptedShareSignal: false, forceCloudKit: true)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await syncAfterSceneBecameActiveIfNeeded()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Opening Activity, Invites or Settings should reflect the partner's
            // latest comments/accepts/approvals; reuse the throttled path so it stays cheap.
            guard newTab == .activity || newTab == .invites || newTab == .settings else { return }
            Task {
                await syncAfterSceneBecameActiveIfNeeded()
            }
        }
        .onChange(of: pairingStatus) { _, newStatus in
            guard newStatus == .paired else { return }
            Task {
                await reevaluateRootSheetFlow()
            }
        }
        .onChange(of: activeRootSheet) { _, newSheet in
            guard newSheet == nil else { return }
            Task {
                await reevaluateRootSheetFlow()
            }
        }
        .sheet(item: $activeRootSheet) { sheet in
            switch sheet {
            case .initialProfilePrompt:
                InitialProfilePromptSheet(
                    initialNickname: settings.currentDisplayName,
                    onSave: { nickname in
                        settings.currentDisplayName = nickname
                        settings.hasCompletedInitialProfilePrompt = true
                    },
                    onSkip: {
                        settings.currentDisplayName = PairingSettingsPlan.randomDisplayName()
                        settings.hasCompletedInitialProfilePrompt = true
                    }
                )
            case .existingICloudDataRecovery:
                ExistingICloudDataRecoverySheet(
                    onDelete: {
                        try await deleteExistingICloudData()
                    },
                    onKeep: {
                        try await continueUsingExistingICloudData()
                    }
                )
            case .partnerNotePrompt:
                PartnerNotePromptSheet(
                    initialNote: settings.partnerNoteName,
                    onSave: { note in
                        settings.partnerNoteName = note
                        settings.hasPromptedPartnerNoteForCurrentPairing = true
                    },
                    onSkip: {
                        settings.partnerNoteName = ""
                        settings.hasPromptedPartnerNoteForCurrentPairing = true
                    }
                )
            case .pairingSafetyNotice:
                PairingSafetyNoticeSheet {
                    settings.hasShownPairingSafetyNoticeForCurrentPairing = true
                }
            }
        }
        .alert(
            settings.strings.pairingReplacementTitle,
            isPresented: Binding(
                get: { pendingReplacementOwnerID != nil },
                set: { if !$0 { pendingReplacementOwnerID = nil } }
            )
        ) {
            Button(settings.strings.pairingReplacementConfirmButton, role: .destructive) {
                Task { await confirmShareReplacement() }
            }
            Button(settings.strings.cancelButton, role: .cancel) {
                cancelShareReplacement()
            }
        } message: {
            Text(settings.strings.pairingReplacementMessage(currentPartner: settings.partnerStatusDisplayName))
        }
        .alert(settings.strings.pairingConflictTitle, isPresented: $showPairingConflictAlert) {
            if let conflict = settings.pairingConflict {
                ForEach(TwoPersonPairingConflictPresentationPlan.candidateIDs(conflict), id: \.self) { candidateID in
                    Button(settings.strings.keepPartnerButton(conflictCandidateDisplayName(candidateID))) {
                        Task { await resolvePairingConflict(keeping: candidateID, conflict: conflict) }
                    }
                }
            }
            Button(settings.strings.cancelButton, role: .cancel) {}
        } message: {
            Text(pairingConflictMessage)
        }
        .onChange(of: settings.pairingConflict) { _, newConflict in
            showPairingConflictAlert = newConflict != nil
        }
    }

    private var pairingConflictMessage: String {
        switch settings.pairingConflict {
        case .outgoingIncomingMismatch:
            settings.strings.pairingConflictMismatchMessage
        case .multipleIncomingShares:
            settings.strings.pairingConflictMultipleIncomingMessage
        case .multipleOutgoingParticipants:
            settings.strings.pairingConflictMultipleOutgoingMessage
        case nil:
            ""
        }
    }

    private func conflictCandidateDisplayName(_ candidateID: String) -> String {
        if candidateID == settings.partnerShareOwnerID {
            return settings.partnerDisplayName
        }
        return String(candidateID.suffix(8))
    }

    @MainActor
    private func checkPendingShareReplacement() {
        if let incomingOwnerID = ShareCalPendingShareReplacement.incomingOwnerID {
            pendingReplacementOwnerID = incomingOwnerID
        }
    }

    /// `onChange` alone misses two cases: a persisted conflict at launch (no
    /// change event fires for the initial value) and a re-detected identical
    /// conflict after the user cancelled (Equatable-same values don't fire).
    @MainActor
    private func representPairingConflictIfNeeded() {
        if settings.pairingConflict != nil {
            showPairingConflictAlert = true
        }
    }

    @MainActor
    private func cancelShareReplacement() {
        ShareCalPendingShareReplacement.clear()
        pendingReplacementOwnerID = nil
    }

    @MainActor
    private func confirmShareReplacement() async {
        guard let pending = ShareCalPendingShareReplacement.consume() else {
            pendingReplacementOwnerID = nil
            return
        }
        pendingReplacementOwnerID = nil
        guard let cloudKit = services.cloudKitIfAvailable else { return }

        do {
            let ownerIDsToPurge = ICloudSharingTeardownPlan.localOwnerIDsToPurge(
                partnerShareOwnerID: settings.partnerShareOwnerID
            )
            if let oldPartnerID = settings.partnerShareOwnerID {
                try await cloudKit.deleteAcceptedSharedZones(ownerIDs: [oldPartnerID])
            }
            try await cloudKit.removeOutgoingShareParticipants(keeping: pending.incomingOwnerID)
            try ShareCalLocalDataCleanupService.purgeSharedOwnerData(
                ownerMemberIDs: ownerIDsToPurge,
                modelContext: modelContext
            )
            settings.partnerShareOwnerID = nil
            settings.partnerSyncedDisplayName = nil
            settings.partnerNoteName = ""
            settings.hasPromptedPartnerNoteForCurrentPairing = false
            settings.hasShownPairingSafetyNoticeForCurrentPairing = false
            settings.pairingConflict = nil
            settings.clearPairingDate()

            try await cloudKit.acceptShare(metadata: pending.metadata)
            ShareCalAcceptedShareSignal.markAccepted(partnerOwnerID: pending.incomingOwnerID)
            await syncAfterAcceptedShareIfNeeded()
        } catch {
            settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
        }
    }

    @MainActor
    private func resolvePairingConflict(
        keeping keptID: String,
        conflict: TwoPersonPairingConflict
    ) async {
        guard let cloudKit = services.cloudKitIfAvailable else { return }
        do {
            switch conflict {
            case .outgoingIncomingMismatch(_, let incomingOwnerIDs):
                // Whoever is kept: every other participant leaves my share, and
                // every incoming zone not owned by the kept person is left.
                try await cloudKit.removeOutgoingShareParticipants(keeping: keptID)
                try await leaveSharedZones(
                    ownerIDs: incomingOwnerIDs.filter { $0 != keptID },
                    cloudKit: cloudKit
                )
                settings.partnerShareOwnerID = incomingOwnerIDs.contains(keptID) ? keptID : nil
            case .multipleIncomingShares(let ownerIDs):
                try await leaveSharedZones(ownerIDs: ownerIDs.filter { $0 != keptID }, cloudKit: cloudKit)
                settings.partnerShareOwnerID = keptID
            case .multipleOutgoingParticipants:
                try await cloudKit.removeOutgoingShareParticipants(keeping: keptID)
            }
            settings.pairingConflict = nil
            await runForegroundSync(consumingAcceptedShareSignal: false, forceCloudKit: true)
        } catch {
            settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
        }
    }

    @MainActor
    private func leaveSharedZones(
        ownerIDs: [String],
        cloudKit: CloudKitCoupleSpaceService
    ) async throws {
        guard !ownerIDs.isEmpty else { return }
        try await cloudKit.deleteAcceptedSharedZones(ownerIDs: ownerIDs)
        try ShareCalLocalDataCleanupService.purgeSharedOwnerData(
            ownerMemberIDs: Set(ownerIDs),
            modelContext: modelContext
        )
    }

    private var shouldDeferAutomaticSyncForExistingICloudDecision: Bool {
        ExistingICloudDataRecoveryPlan.shouldDeferAutomaticSync(
            hasResolvedPrompt: settings.hasResolvedExistingICloudDataPrompt,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
            lastSyncAt: settings.lastSyncAt
        ) && (!hasEvaluatedExistingICloudDataPrompt || activeRootSheet == .existingICloudDataRecovery)
    }

    private func presentInitialProfilePromptIfNeeded() {
        guard activeRootSheet == nil else { return }
        if PairingSettingsPlan.normalizedDisplayName(settings.currentDisplayName) != nil {
            if !settings.hasCompletedInitialProfilePrompt {
                settings.hasCompletedInitialProfilePrompt = true
            }
            return
        }
        if settings.hasCompletedInitialProfilePrompt {
            settings.hasCompletedInitialProfilePrompt = false
        }
        activeRootSheet = .initialProfilePrompt
    }

    private func presentPartnerNotePromptIfNeeded() {
        guard activeRootSheet == nil else { return }
        guard pairingStatus == .paired else { return }
        guard !settings.hasPromptedPartnerNoteForCurrentPairing else { return }
        activeRootSheet = .partnerNotePrompt
    }

    private func presentPairingSafetyNoticeIfNeeded() {
        guard activeRootSheet == nil else { return }
        guard PairingSafetyEducationPlan.shouldPresentNotice(
            pairingStatus: pairingStatus,
            hasPromptedPartnerNoteForCurrentPairing: settings.hasPromptedPartnerNoteForCurrentPairing,
            hasShownPairingSafetyNoticeForCurrentPairing: settings.hasShownPairingSafetyNoticeForCurrentPairing
        ) else { return }
        activeRootSheet = .pairingSafetyNotice
    }

    @MainActor
    private func presentExistingICloudDataPromptIfNeeded() async {
        guard activeRootSheet == nil else { return }
        guard !settings.hasResolvedExistingICloudDataPrompt else {
            hasEvaluatedExistingICloudDataPrompt = true
            return
        }

        let shouldProbe = ExistingICloudDataRecoveryPlan.shouldDeferAutomaticSync(
            hasResolvedPrompt: settings.hasResolvedExistingICloudDataPrompt,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
            lastSyncAt: settings.lastSyncAt
        )
        guard shouldProbe else {
            hasEvaluatedExistingICloudDataPrompt = true
            return
        }
        guard settings.hasCompletedInitialProfilePrompt else { return }
        guard let cloudKit = services.cloudKitIfAvailable else {
            hasEvaluatedExistingICloudDataPrompt = true
            settings.hasResolvedExistingICloudDataPrompt = true
            return
        }

        let snapshot = await cloudKit.existingICloudDataSnapshot()
        if snapshot.lookupFailed {
            return
        }
        hasEvaluatedExistingICloudDataPrompt = true
        if ExistingICloudDataRecoveryPlan.shouldPresent(
            snapshot: snapshot,
            hasCompletedInitialProfilePrompt: settings.hasCompletedInitialProfilePrompt,
            hasResolvedPrompt: settings.hasResolvedExistingICloudDataPrompt,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
            lastSyncAt: settings.lastSyncAt
        ) {
            activeRootSheet = .existingICloudDataRecovery
            return
        }
        settings.hasResolvedExistingICloudDataPrompt = true
    }

    @MainActor
    private func reevaluateRootSheetFlow() async {
        purgeLegacyLocalDataIfNeeded()
        checkPendingShareReplacement()
        representPairingConflictIfNeeded()
        presentInitialProfilePromptIfNeeded()
        guard activeRootSheet == nil else { return }
        await syncAfterAcceptedShareIfNeeded()
        await presentExistingICloudDataPromptIfNeeded()
        presentPartnerNotePromptIfNeeded()
        presentPairingSafetyNoticeIfNeeded()
    }

    @MainActor
    private func syncAfterAcceptedShareIfNeeded() async {
        guard ShareCalAcceptedShareSignal.hasPending() else { return }
        await runForegroundSync(consumingAcceptedShareSignal: true)
    }

    @MainActor
    private func syncAfterSceneBecameActiveIfNeeded(now: Date = .now) async {
        guard !shouldDeferAutomaticSyncForExistingICloudDecision else { return }
        let hasPendingAcceptedShare = ShareCalAcceptedShareSignal.hasPending()
        guard ForegroundSyncPlan.shouldRunAutomaticSync(
            lastSyncAt: settings.lastSyncAt,
            now: now,
            syncPhase: settings.syncPhase,
            hasPendingAcceptedShare: hasPendingAcceptedShare
        ) else { return }

        await runForegroundSync(consumingAcceptedShareSignal: hasPendingAcceptedShare)
    }

    @MainActor
    @discardableResult
    private func runForegroundSync(
        consumingAcceptedShareSignal: Bool,
        forceCloudKit: Bool = false
    ) async -> Bool {
        guard !isRunningForegroundSync else { return false }
        guard settings.syncPhase != .syncing else { return false }
        if consumingAcceptedShareSignal {
            guard ShareCalAcceptedShareSignal.consumePending() else { return false }
            settings.iCloudSharingEnabled = true
            if let partnerOwnerID = ShareCalAcceptedShareSignal.consumePendingPartnerOwnerID() {
                settings.partnerShareOwnerID = partnerOwnerID
            }
        }

        isRunningForegroundSync = true
        defer { isRunningForegroundSync = false }

        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(
            modelContext: modelContext,
            settings: settings,
            forceCloudKit: consumingAcceptedShareSignal || forceCloudKit
        )
        representPairingConflictIfNeeded()
        return true
    }

    @MainActor
    private func continueUsingExistingICloudData() async throws {
        settings.lastSyncError = nil
        settings.iCloudSharingEnabled = true
        let didRun = await runForegroundSync(consumingAcceptedShareSignal: false, forceCloudKit: true)
        guard didRun else {
            let message = settings.strings.cloudKitSyncDisabledLocalBuild
            throw NSError(domain: "ShareCal", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        if settings.syncPhase == .failed {
            let message = settings.lastSyncError ?? settings.strings.cloudKitSyncDisabledLocalBuild
            throw NSError(domain: "ShareCal", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        settings.hasResolvedExistingICloudDataPrompt = true
    }

    @MainActor
    private func deleteExistingICloudData() async throws {
        guard let cloudKit = services.cloudKitIfAvailable else {
            throw NSError(
                domain: "ShareCal",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: settings.strings.iCloudSharingUnavailableLocalBuild]
            )
        }

        try await cloudKit.deleteICloudData(ownerMemberID: settings.currentMemberID)
        try ShareCalLocalDataCleanupService.purge(modelContext: modelContext)
        settings.iCloudSharingEnabled = false
        settings.hasStartedPairing = false
        settings.partnerShareOwnerID = nil
        settings.partnerNoteName = ""
        settings.hasPromptedPartnerNoteForCurrentPairing = false
        settings.hasShownPairingSafetyNoticeForCurrentPairing = false
        settings.partnerSyncedDisplayName = nil
        settings.outgoingShareParticipantIDs = []
        settings.pairingConflict = nil
        settings.clearPairingDate()
        settings.lastSyncAt = nil
        settings.lastSyncError = nil
        settings.syncPhase = .idle
        settings.hasResolvedExistingICloudDataPrompt = true
    }

    /// One-time SwiftData wipe after the legacy local-owner-UUID state reset:
    /// cached mirrors/comments are keyed by the old identity and re-sync cleanly.
    @MainActor
    private func purgeLegacyLocalDataIfNeeded() {
        guard settings.consumeLegacyLocalDataPurgeFlag() else { return }
        do {
            try ShareCalLocalDataCleanupService.purge(modelContext: modelContext)
        } catch {
            settings.lastSyncError = error.localizedDescription
        }
    }
}

struct InitialProfilePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @State private var nickname: String
    let onSave: (String) -> Void
    let onSkip: () -> Void

    init(
        initialNickname: String,
        onSave: @escaping (String) -> Void,
        onSkip: @escaping () -> Void
    ) {
        _nickname = State(initialValue: initialNickname)
        self.onSave = onSave
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.initialProfilePromptMessage)
                        .foregroundStyle(.secondary)
                    TextField(settings.strings.myDisplayNamePlaceholder, text: $nickname)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(settings.strings.myNicknameLabel)
                }
            }
            .navigationTitle(settings.strings.initialProfilePromptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(settings.strings.skipButton) {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.strings.saveButton) {
                        guard let normalizedNickname = PairingSettingsPlan.normalizedDisplayName(nickname) else { return }
                        onSave(normalizedNickname)
                        dismiss()
                    }
                    .disabled(PairingSettingsPlan.normalizedDisplayName(nickname) == nil)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct PartnerNotePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @State private var note: String
    let onSave: (String) -> Void
    let onSkip: () -> Void

    init(
        initialNote: String,
        onSave: @escaping (String) -> Void,
        onSkip: @escaping () -> Void
    ) {
        _note = State(initialValue: initialNote)
        self.onSave = onSave
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.partnerNotePromptMessage)
                        .foregroundStyle(.secondary)
                    TextField(settings.strings.partnerDisplayNamePlaceholder, text: $note)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(settings.strings.partnerNicknameEditLabel)
                }
            }
            .navigationTitle(settings.strings.partnerNotePromptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(settings.strings.skipButton) {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.strings.saveButton) {
                        let normalizedNote = PairingSettingsPlan.normalizedDisplayName(note) ?? ""
                        onSave(normalizedNote)
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct PairingSafetyNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let onAcknowledge: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.pairingSafetyNoticeMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Button(settings.strings.continueButton) {
                        onAcknowledge()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(settings.strings.pairingSafetyNoticeTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

struct ExistingICloudDataRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @State private var isRunningAction = false
    @State private var actionError: String?
    let onDelete: () async throws -> Void
    let onKeep: () async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.existingICloudDataPromptMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionError {
                        Text(actionError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        runAction(onDelete)
                    } label: {
                        if isRunningAction {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text(settings.strings.deleteICloudDataButton)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isRunningAction)

                    Button(settings.strings.continueExistingICloudDataButton) {
                        runAction(onKeep)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isRunningAction)
                }
            }
            .navigationTitle(settings.strings.existingICloudDataPromptTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isRunningAction)
    }

    private func runAction(_ action: @escaping () async throws -> Void) {
        guard !isRunningAction else { return }
        isRunningAction = true
        actionError = nil
        Task {
            do {
                try await action()
                await MainActor.run {
                    isRunningAction = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRunningAction = false
                    actionError = error.localizedDescription
                }
            }
        }
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Binding var focusRequest: CalendarFocusRequest?
    let onOpenSettings: (SettingsFocusTarget) -> Void
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @State private var selectedDate = Date()
    @State private var mode: CalendarMode = .day
    @State private var selectedEvent: EventMirror?
    @State private var focusedJointEventID: String?
    @State private var activeCalendarSheet: CalendarSheet?
    @State private var localDisplayMirrors: [EventMirror] = []
    @State private var authorizationState: CalendarAuthorizationState = .unknown

    var activeMirrors: [EventMirror] {
        mirrors.filter { mirror in
            guard mirror.deletedAt == nil else { return false }
            if mirror.ownerMemberID == settings.currentMemberID {
                return settings.selectedCalendarIDs.contains(mirror.sourceCalendarID)
            }
            return true
        }
    }

    var isPaired: Bool {
        PairingSettingsPlan.status(
            hasStartedPairing: settings.hasStartedPairing,
            outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
            incomingOwnerID: settings.partnerShareOwnerID
        ) == .paired
    }

    var visibleMirrors: [EventMirror] {
        CalendarMirrorVisibilityPlan.memberMirrors(
            activeMirrors,
            currentMemberID: settings.currentMemberID,
            partnerShareOwnerID: settings.partnerShareOwnerID
        ).filter { mirror in
            visibleInterval.contains(mirror.startDate)
        }
    }

    var acceptedJointEvents: [JointScheduleEvent] {
        JointSchedulePlan.jointEvents(
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
        JointSchedulePlan.ordinaryMirrors(
            localDisplayMirrors + visiblePartnerMirrors,
            excluding: visibleJointEvents
        )
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

    var localDisplayRefreshKey: String {
        "\(mode.rawValue):\(Int(visibleInterval.start.timeIntervalSince1970)):\(Int(visibleInterval.end.timeIntervalSince1970)):\(settings.currentMemberID)"
    }

    var setupGuidanceStep: CalendarSetupGuidanceStep? {
        CalendarSetupGuidancePlan.step(
            hasCompletedInitialProfilePrompt: settings.hasCompletedInitialProfilePrompt,
            currentDisplayName: settings.currentDisplayName,
            authorizationState: authorizationState,
            selectedCalendarIDs: settings.selectedCalendarIDs,
            pairingStatus: PairingSettingsPlan.status(
                hasStartedPairing: settings.hasStartedPairing,
                outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
                incomingOwnerID: settings.partnerShareOwnerID
            )
        )
    }

    var body: some View {
        let strings = settings.strings

        VStack(spacing: 8) {
            CompactCalendarTopBar(
                selectedDate: $selectedDate,
                mode: $mode,
                title: CalendarDateNavigationPlan.compactTitle(for: selectedDate, mode: mode, locale: settings.appLanguage.locale),
                onOpenPicker: {
                    activeCalendarSheet = .datePicker
                },
                onCreateInvite: {
                    activeCalendarSheet = .createInvite
                }
            )
            .padding(.horizontal)
            .padding(.top, 8)

            if isPaired, let pairingDate = settings.pairingDate {
                CalendarPairingStatusLine(pairingDate: pairingDate)
                    .padding(.horizontal)
            }

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
                } else if localDisplayMirrors.isEmpty && visiblePartnerMirrors.isEmpty && visibleJointEvents.isEmpty {
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
                                myTitle: strings.memberColumnTitle(
                                    baseTitle: strings.meTitle,
                                    nickname: settings.currentDisplayName
                                ),
                                myEvents: myEvents,
                                jointEvents: visibleJointEvents,
                                focusedJointEventID: focusedJointEventID,
                                partnerTitle: strings.memberColumnTitle(
                                    baseTitle: strings.partnerTitle,
                                    nickname: settings.partnerDisplayName
                                ),
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
            .contentShape(Rectangle())
            .simultaneousGesture(swipeNavigationGesture)
            .refreshable {
                await performSync()
            }
            .accessibilityAction(named: Text(strings.previousDateAccessibilityLabel)) {
                moveSelectedDate(.previous)
            }
            .accessibilityAction(named: Text(strings.nextDateAccessibilityLabel)) {
                moveSelectedDate(.next)
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
                guard let direction = CalendarSwipeNavigationPlan.direction(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height
                ) else { return }
                moveSelectedDate(direction)
            }
    }

    private func moveSelectedDate(_ direction: CalendarNavigationDirection) {
        withAnimation(.easeInOut(duration: 0.16)) {
            selectedDate = CalendarDateNavigationPlan.date(
                afterMoving: selectedDate,
                mode: mode,
                direction: direction
            )
        }
    }

    private func performSync() async {
        // foregroundSync sets syncPhase = .syncing synchronously on entry, and
        // everything here runs on the main actor, so this single guard already
        // prevents overlapping/reentrant syncs from this screen.
        guard settings.syncPhase != .syncing else { return }
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
    }

    private func refreshLocalDisplayMirrors() {
        let sourceEvents = services.calendarAccess.authorizedEvents(
            from: visibleInterval.start,
            to: visibleInterval.end
        )
        let selectedCalendarIDs = settings.selectedCalendarIDs
        localDisplayMirrors = CalendarDisplayMirrorPlan.displayMirrors(
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
    let onOpenPicker: () -> Void
    let onCreateInvite: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            CompactModeToggle(mode: $mode)
                .frame(width: 72)

            HStack(spacing: 4) {
                Button {
                    onOpenPicker()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.semibold))
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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

                Button(settings.strings.todayButton) {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                }
                .font(.caption2.weight(.semibold))
                .frame(width: 46, height: 34)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(Calendar.current.isDateInToday(selectedDate))
                .buttonStyle(.plain)
                .accessibilityIdentifier("compact-today-button")
            }
            .layoutPriority(1)

            CompactIconButton(
                systemName: "plus",
                accessibilityLabel: settings.strings.createInviteAccessibilityLabel,
                accessibilityIdentifier: "compact-create-invite-button",
                action: onCreateInvite
            )
        }
        .frame(height: 38)
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

struct CalendarPairingStatusLine: View {
    @Environment(SettingsStore.self) private var settings
    let pairingDate: Date

    var body: some View {
        let strings = settings.strings
        let dayCount = PairingDatePlan.dayCount(since: pairingDate)
        let dateText = strings.pairingDateText(for: pairingDate)

        Label(
            strings.calendarPairingStatusLine(dayCount: dayCount, dateText: dateText),
            systemImage: "heart.circle.fill"
        )
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("calendar-pairing-status-line")
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
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onPrimaryAction) {
                Label(buttonTitle, systemImage: buttonIconName)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("calendar-setup-guidance-button")
        }
        .padding(.vertical, 24)
        .frame(maxWidth: 420)
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
    let myEvents: [EventMirror]
    let jointEvents: [JointScheduleEvent]
    let focusedJointEventID: String?
    let partnerTitle: String
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
                myCount: myEvents.count,
                partnerTitle: partnerTitle,
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
    let myCount: Int
    let partnerTitle: String
    let partnerCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: railSpacing) {
            Color.clear
                .frame(width: railWidth, height: 1)

            HStack(alignment: .top, spacing: laneSpacing) {
                DayTimelineColumnHeader(
                    title: myTitle,
                    count: myCount,
                    tint: .blue,
                    width: laneWidth
                )

                DayTimelineColumnHeader(
                    title: partnerTitle,
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
    let count: Int
    let tint: Color
    let width: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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
                        selection: startTimeBinding,
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

    // Moving the start time slides the end time to keep the chosen duration,
    // matching the system calendar editor. The day row uses `dayBinding`, which
    // preserves duration separately, so this stays scoped to the time picker.
    private var startTimeBinding: Binding<Date> {
        Binding {
            startDate
        } set: { newStart in
            // All-day invites own start/end via `adjustForAllDay`; ignore any
            // stray time-picker writes entirely so startDate can't drift.
            guard !isAllDay else { return }
            let previousStart = startDate
            let previousEnd = endDate
            startDate = newStart
            endDate = InviteTimeAdjustmentPlan.endDate(
                forNewStart: newStart,
                previousStart: previousStart,
                previousEnd: previousEnd
            )
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
                    partnerMemberID: settings.partnerOwnerIDForLocalData,
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
                inviteeMemberID: settings.partnerOwnerIDForLocalData
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
        guard EventDetailInteractionPlan.canComment(on: event) else { return [] }
        return comments.filter { $0.eventMirrorID == event.id && $0.deletedAt == nil }
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                Section {
                    LabeledContent(strings.ownerLabel, value: event.ownerMemberID == settings.currentMemberID ? strings.meTitle : strings.partnerTitle)
                    LabeledContent(strings.calendarLabel, value: event.sourceCalendarTitle)
                    LabeledContent(strings.startsLabel, value: strings.abbreviatedDateTimeText(event.startDate))
                    LabeledContent(strings.endsLabel, value: strings.abbreviatedDateTimeText(event.endDate))
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

                if EventDetailInteractionPlan.canComment(on: event) {
                    Section(strings.commentsSection) {
                        ForEach(eventComments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(commentAuthorDisplayName(comment.authorMemberID))
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
            }
            .navigationTitle(strings.eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Opening an event should surface the partner's latest comments;
                // run a throttled sync so it stays cheap on repeated opens.
                await syncOnOpenIfNeeded()
            }
            .refreshable {
                await performSync()
            }
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
            partnerMemberID: settings.partnerOwnerIDForLocalData,
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
            inviteeMemberID: settings.partnerOwnerIDForLocalData,
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

    private func commentAuthorDisplayName(_ authorMemberID: String) -> String {
        MemberDisplayNamePlan.displayName(
            forMemberID: authorMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }

    private func performSync() async {
        // foregroundSync sets syncPhase = .syncing synchronously on entry, and
        // everything here runs on the main actor, so this single guard already
        // prevents overlapping/reentrant syncs from this screen.
        guard settings.syncPhase != .syncing else { return }
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
    }

    private func syncOnOpenIfNeeded() async {
        guard ForegroundSyncPlan.shouldRunAutomaticSync(
            lastSyncAt: settings.lastSyncAt,
            now: .now,
            syncPhase: settings.syncPhase,
            hasPendingAcceptedShare: false
        ) else { return }
        await performSync()
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

struct ActivityTabView: View {
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @State private var selectedEvent: EventMirror?
    @State private var seenSnapshot: Date?

    private var items: [ActivityFeedItem] {
        ActivityFeedPlan.items(
            comments: comments,
            mirrors: mirrors,
            currentMemberID: settings.currentMemberID,
            lastSeenActivityAt: seenSnapshot
        )
    }

    var body: some View {
        let strings = settings.strings
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    strings.activityEmptyTitle,
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(strings.activityEmptyMessage)
                )
            } else {
                List(items) { item in
                    Button {
                        selectedEvent = mirror(for: item.eventMirrorID)
                    } label: {
                        ActivityFeedRow(item: item, authorName: authorName(for: item))
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(strings.activityTitle)
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .onAppear(perform: markActivitySeen)
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

    private func authorName(for item: ActivityFeedItem) -> String {
        MemberDisplayNamePlan.displayName(
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.hasUnread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(!item.hasUnread)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.eventTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(item.latestCommentAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(authorName): \(item.latestCommentBody)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct InvitesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @Query(sort: \CalendarAccessRequest.createdAt) private var accessRequests: [CalendarAccessRequest]
    @State private var errorMessage: String?
    let openInCalendar: (EventInvitation) -> Void

    private var pendingIncomingAccessRequests: [CalendarAccessRequest] {
        CalendarAccessRequestListPlan.pendingIncoming(
            accessRequests,
            currentMemberID: settings.currentMemberID
        )
    }

    var body: some View {
        let strings = settings.strings
        let visibleInvitations = InvitationListPlan.visibleInvitations(invitations)

        List {
            if !pendingIncomingAccessRequests.isEmpty {
                Section(strings.pendingAccessRequestsLabel) {
                    ForEach(pendingIncomingAccessRequests) { request in
                        HistoryRequestRow(
                            request: request,
                            requesterDisplayName: displayName(forRequesterMemberID: request.requesterMemberID),
                            rangeText: accessRequestRangeText(for: request)
                        ) {
                            update(request, status: .approved)
                        } decline: {
                            update(request, status: .declined)
                        }
                    }
                }
            }

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

            if visibleInvitations.isEmpty && pendingIncomingAccessRequests.isEmpty {
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
        .refreshable {
            await performSync()
        }
    }

    private func performSync() async {
        // foregroundSync sets syncPhase = .syncing synchronously on entry, and
        // everything here runs on the main actor, so this single guard already
        // prevents overlapping/reentrant syncs from this screen.
        guard settings.syncPhase != .syncing else { return }
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
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

    private func update(_ request: CalendarAccessRequest, status: CalendarAccessRequestStatus) {
        request.status = status
        do {
            try modelContext.save()
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
        let displayedEndDate = PairingDatePlan.displayedEndDate(forExclusiveEndDate: request.requestedEndDate)
        let end = settings.strings.abbreviatedDateText(displayedEndDate)
        return "\(start) - \(end)"
    }

    private func displayName(forRequesterMemberID requesterMemberID: String) -> String {
        MemberDisplayNamePlan.displayName(
            forMemberID: requesterMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }
}

struct HistoryRequestRow: View {
    @Environment(SettingsStore.self) private var settings
    let request: CalendarAccessRequest
    let requesterDisplayName: String
    let rangeText: String
    let approve: () -> Void
    let decline: () -> Void

    var body: some View {
        let strings = settings.strings

        VStack(alignment: .leading, spacing: 8) {
            Text(strings.incomingHistoryRequestText(
                requester: requesterDisplayName,
                rangeText: rangeText
            ))
            .font(.subheadline.weight(.semibold))
            Text(strings.prePairingHistoryLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(strings.approveButton, action: approve)
                    .buttonStyle(.borderedProminent)
                Button(strings.declineButton, role: .destructive, action: decline)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
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
            Text("\(settings.strings.abbreviatedDateTimeText(invitation.startDate)) - \(settings.strings.shortTimeText(invitation.endDate))")
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

enum SettingsSheet: Identifiable {
    case historyRequest

    var id: String {
        switch self {
        case .historyRequest: "historyRequest"
        }
    }
}

struct PairingStatusCard: View {
    @Environment(SettingsStore.self) private var settings
    let status: PairingStatus
    let pairingDate: Date?
    let partnerNickname: String
    let myCalendarScopeValue: String
    let partnerCalendarScopeValue: String
    let prePairingHistoryScopeValue: String
    let isCloudKitEnabled: Bool
    let isPreparingShare: Bool
    let isCheckingCloudKitAccount: Bool
    let isSyncing: Bool
    let isStoppingShare: Bool
    let cloudKitDiagnosticMessage: String?
    let onStartPairing: () -> Void
    let onCheckCloudKitStatus: () -> Void
    let onSync: () -> Void
    let onRequestHistory: () -> Void
    let onUnpair: () -> Void
    let onOpenSharedPeople: () -> Void
    let onHideCloudKitDiagnostic: () -> Void

    var body: some View {
        let strings = settings.strings

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(strings.pairingSection)
                    .font(.headline)
                Spacer()
                Text(strings.pairingStatusTitle(for: status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusTint.opacity(0.12))
                    .clipShape(Capsule())
            }

            if status == .notPaired {
                notPairedContent(strings: strings)
            } else if status == .paired {
                pairedContent(strings: strings)
            } else if status == .waitingForYouToShare {
                waitingForYouToShareContent(strings: strings)
            } else {
                pairingInProgressContent(strings: strings)
            }

            sharedPeopleContent(strings: strings)

            if !isCloudKitEnabled {
                Text(strings.iCloudSharingUnavailableLocalBuild)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let cloudKitDiagnosticMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(strings.diagnosticsTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            onHideCloudKitDiagnostic()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(strings.cancelButton)
                    }
                    Text(cloudKitDiagnosticMessage)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sharedPeopleContent(strings: ShareCalStrings) -> some View {
        let canOpenOfficialSharing = SharedPeoplePresentationPlan.canOpenOfficialSharing(
            isCloudKitEnabled: isCloudKitEnabled,
            isPreparingShare: isPreparingShare,
            isStoppingShare: isStoppingShare
        )

        return Button {
            onOpenSharedPeople()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(strings.sharedPeopleTitle, systemImage: "person.2")
                        .font(.subheadline.weight(.semibold))
                    Text(strings.sharedPeopleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isPreparingShare {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canOpenOfficialSharing)
        .accessibilityIdentifier("shared-people-official-share-button")
    }

    private func notPairedContent(strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.pairingDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    onStartPairing()
                } label: {
                    Label(strings.startPairingButton(isPreparing: isPreparingShare), systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCloudKitEnabled || isPreparingShare)

                Button {
                    onCheckCloudKitStatus()
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!isCloudKitEnabled || isCheckingCloudKitAccount)
                .accessibilityLabel(strings.checkICloudStatusButton(isChecking: isCheckingCloudKitAccount))
            }
        }
    }

    private func pairedContent(strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pairingDate {
                let dayCount = PairingDatePlan.dayCount(since: pairingDate)
                VStack(alignment: .leading, spacing: 2) {
                    Text(strings.pairingDayCountText(dayCount))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(strings.pairingDateLine(strings.pairingDateText(for: pairingDate)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("pairing-day-count")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(partnerNickname)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.sharingScopeTitle)
                    .font(.subheadline.weight(.semibold))
                SharingScopeRow(label: strings.sharingMyCalendarLabel, value: myCalendarScopeValue)
                SharingScopeRow(label: strings.partnersCalendarLabel, value: partnerCalendarScopeValue)
                SharingScopeRow(label: strings.prePairingHistoryLabel, value: prePairingHistoryScopeValue)
            }

            HStack(spacing: 10) {
                Button {
                    onSync()
                } label: {
                    Label(strings.syncAccessibilityLabel, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSyncing)

                Button {
                    onRequestHistory()
                } label: {
                    Label(strings.requestHistoryAccessButton, systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isCloudKitEnabled || pairingDate == nil)
            }

            Button(role: .destructive) {
                onUnpair()
            } label: {
                Label(strings.unpairButton, systemImage: "person.2.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isCloudKitEnabled || isStoppingShare)
        }
    }

    private func pairingInProgressContent(strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.pairingDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let pairingDate {
                Text(strings.pairingDateLine(strings.pairingDateText(for: pairingDate)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    onSync()
                } label: {
                    Label(strings.syncAccessibilityLabel, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSyncing)

                Button {
                    onCheckCloudKitStatus()
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!isCloudKitEnabled || isCheckingCloudKitAccount)
                .accessibilityLabel(strings.checkICloudStatusButton(isChecking: isCheckingCloudKitAccount))
            }

            Button(role: .destructive) {
                onUnpair()
            } label: {
                Label(strings.unpairButton, systemImage: "person.2.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isCloudKitEnabled || isStoppingShare)
        }
    }

    private func waitingForYouToShareContent(strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.pairingWaitingForYouToShareDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let pairingDate {
                Text(strings.pairingDateLine(strings.pairingDateText(for: pairingDate)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    onStartPairing()
                } label: {
                    Label(strings.startPairingButton(isPreparing: isPreparingShare), systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCloudKitEnabled || isPreparingShare)

                Button {
                    onCheckCloudKitStatus()
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!isCloudKitEnabled || isCheckingCloudKitAccount)
                .accessibilityLabel(strings.checkICloudStatusButton(isChecking: isCheckingCloudKitAccount))
            }

            Button(role: .destructive) {
                onUnpair()
            } label: {
                Label(strings.unpairButton, systemImage: "person.2.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isCloudKitEnabled || isStoppingShare)
        }
    }

    private var statusTint: Color {
        switch status {
        case .notPaired:
            return .secondary
        case .waitingForPartner, .waitingForPartnerToShare, .waitingForYouToShare:
            return .orange
        case .paired:
            return .pink
        }
    }
}

struct SharingScopeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

struct HistoryRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let pairingDate: Date
    let onSend: (Date, Date) -> Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var validationMessage: String?

    init(
        pairingDate: Date,
        initialRange: PairingHistoryRequestRange? = nil,
        onSend: @escaping (Date, Date) -> Bool
    ) {
        self.pairingDate = pairingDate
        self.onSend = onSend
        let range = initialRange ?? PairingDatePlan.defaultHistoryRequestRange(pairingDate: pairingDate)
        _startDate = State(initialValue: range.start)
        _endDate = State(initialValue: range.end)
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            Form {
                Section {
                    Text(strings.prePairingHistoryRequestDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    DatePicker(
                        strings.accessRequestStartLabel,
                        selection: $startDate,
                        in: ...maxSelectableDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        strings.accessRequestEndLabel,
                        selection: $endDate,
                        in: ...maxSelectableDate,
                        displayedComponents: .date
                    )

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(strings.sendRequestButton) {
                        send()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(strings.prePairingHistoryRequestTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.cancelButton) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var maxSelectableDate: Date {
        PairingDatePlan.displayedEndDate(
            forExclusiveEndDate: PairingDatePlan.normalizedPairingDate(pairingDate)
        )
    }

    private func send() {
        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let exclusiveEndDate = PairingDatePlan.exclusiveEndDate(forDisplayedEndDate: endDate, calendar: calendar)
        guard exclusiveEndDate > normalizedStartDate else {
            validationMessage = settings.strings.invalidAccessRequestRangeMessage
            return
        }
        validationMessage = nil
        if onSend(startDate, endDate) {
            dismiss()
        }
    }
}

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Binding var focus: SettingsFocusTarget?
    @Query(sort: \CalendarAccessRequest.createdAt) private var accessRequests: [CalendarAccessRequest]
    @State private var authorizationState: CalendarAuthorizationState = .unknown
    @State private var calendars: [CalendarDescriptor] = []
    @State private var preparedShare: PreparedCloudShare?
    @State private var errorMessage: String?
    @State private var accessRequestMessage: String?
    @State private var calendarAccessMessage: String?
    @State private var isRequestingCalendarAccess = false
    @State private var cloudKitDiagnosticMessage: String?
    @State private var isCheckingCloudKitAccount = false
    @State private var isPreparingShare = false
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
        CalendarAccessRequestListPlan.pendingIncoming(
            accessRequests,
            currentMemberID: settings.currentMemberID
        )
    }

    private var outgoingAccessRequests: [CalendarAccessRequest] {
        CalendarAccessRequestListPlan.outgoing(accessRequests, currentMemberID: settings.currentMemberID)
    }

    private var pairingStatus: PairingStatus {
        PairingSettingsPlan.status(
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
        let normalizedPairingDate = PairingDatePlan.normalizedPairingDate(pairingDate, calendar: calendar)
        let authorizedStartDate = PrePairingHistoryAccessPlan.contiguousAuthorizedStartDate(
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
        let pairingDate = settings.pairingDate ?? PairingDatePlan.normalizedPairingDate(.now)
        return PrePairingHistoryAccessPlan.defaultNextRequestRange(
            pairingDate: pairingDate,
            accessRequests: accessRequests,
            currentMemberID: settings.currentMemberID,
            ownerMemberID: ownerMemberIDForPartnerHistory
        )
    }

    private func sharingScopeValue(
        direction: PrePairingHistoryAccessPlan.Direction,
        ownerMemberID: String?
    ) -> String {
        let strings = settings.strings
        guard let pairingDate = settings.pairingDate else {
            return strings.sharedAfterPairingDateValue
        }
        let calendar = Calendar.current
        let normalizedPairingDate = PairingDatePlan.normalizedPairingDate(pairingDate, calendar: calendar)
        let authorizedStartDate = PrePairingHistoryAccessPlan.contiguousAuthorizedStartDate(
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

    var body: some View {
        @Bindable var settings = settings
        let strings = settings.strings

        ScrollViewReader { proxy in
            List {
                Section {
                    PairingStatusCard(
                        status: pairingStatus,
                        pairingDate: settings.pairingDate,
                        partnerNickname: settings.partnerStatusDisplayName,
                        myCalendarScopeValue: myCalendarScopeValue,
                        partnerCalendarScopeValue: partnerCalendarScopeValue,
                        prePairingHistoryScopeValue: prePairingHistoryScopeValue,
                        isCloudKitEnabled: services.isCloudKitEnabled,
                        isPreparingShare: isPreparingShare,
                        isCheckingCloudKitAccount: isCheckingCloudKitAccount,
                        isSyncing: settings.syncPhase == .syncing,
                        isStoppingShare: isStoppingShare,
                        cloudKitDiagnosticMessage: cloudKitDiagnosticMessage,
                        onStartPairing: {
                            Task { await prepareShare() }
                        },
                        onCheckCloudKitStatus: {
                            Task { await checkCloudKitStatus() }
                        },
                        onSync: {
                            syncNow()
                        },
                        onRequestHistory: {
                            ensurePairingDateIfNeeded()
                            activeSettingsSheet = .historyRequest
                        },
                        onUnpair: {
                            showStopSharingConfirmation = true
                        },
                        onOpenSharedPeople: {
                            Task { await prepareShare() }
                        },
                        onHideCloudKitDiagnostic: {
                            cloudKitDiagnosticMessage = nil
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                .id(SettingsFocusTarget.pairing)

            if PairingSafetyEducationPlan.shouldShowPersistentWarning(pairingStatus: pairingStatus) {
                Section(strings.pairingSafetySection) {
                    Text(strings.pairingSafetyPersistentWarningTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(strings.pairingSafetyPersistentWarningMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(strings.profileSection) {
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
        }
        .navigationTitle(strings.settingsTitle)
        .task {
            authorizationState = services.calendarAccess.authorizationState()
            refreshCalendars()
            ensurePairingDateIfNeeded()
            consumeSettingsFocus(with: proxy)
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
        .sheet(item: $activeSettingsSheet) { sheet in
            switch sheet {
            case .historyRequest:
                HistoryRequestSheet(
                    pairingDate: settings.pairingDate ?? PairingDatePlan.normalizedPairingDate(.now),
                    initialRange: nextHistoryRequestRange
                ) { startDate, endDate in
                    sendAccessRequest(startDate: startDate, endDate: endDate)
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
                proxy.scrollTo(focus, anchor: .top)
            }
            self.focus = nil
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
        let exclusiveEndDate = PairingDatePlan.exclusiveEndDate(
            forDisplayedEndDate: normalizedDisplayedEndDate,
            calendar: calendar
        )

        guard exclusiveEndDate > normalizedStartDate else {
            accessRequestMessage = settings.strings.invalidAccessRequestRangeMessage
            return false
        }

        let validation = PrePairingHistoryAccessPlan.validation(
            requestedStartDate: normalizedStartDate,
            requestedEndDate: exclusiveEndDate,
            pairingDate: settings.pairingDate ?? PairingDatePlan.normalizedPairingDate(.now),
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
        let displayedEndDate = PairingDatePlan.displayedEndDate(forExclusiveEndDate: request.requestedEndDate)
        let end = settings.strings.abbreviatedDateText(displayedEndDate)
        return "\(start) - \(end)"
    }

    private func displayName(forRequesterMemberID requesterMemberID: String) -> String {
        MemberDisplayNamePlan.displayName(
            forMemberID: requesterMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }

    @MainActor
    private func prepareShare() async {
        guard !isPreparingShare else { return }
        errorMessage = nil
        guard let cloudKit = services.cloudKitIfAvailable else {
            errorMessage = settings.strings.iCloudSharingUnavailableLocalBuild
            return
        }
        guard let displayName = PairingSettingsPlan.normalizedDisplayName(settings.currentDisplayName) else {
            errorMessage = settings.strings.currentDisplayNameRequiredMessage
            return
        }
        settings.currentDisplayName = displayName

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
            if !settings.hasSyncedMemberID {
                settings.currentMemberID = try await cloudKit.fetchCurrentUserRecordID()
            }
            let share = try await cloudKit.prepareShare(ownerMemberID: settings.currentMemberID)
            try await cloudKit.saveMemberProfileForSync(
                ownerMemberID: settings.currentMemberID,
                displayName: displayName
            )
            guard activeSharePreparationID == preparationID else { return }
            settings.iCloudSharingEnabled = true
            settings.hasStartedPairing = true
            settings.markPairingDateIfNeeded()
            settings.outgoingShareParticipantIDs = CloudKitShareParticipantIdentityPlan.acceptedParticipantIDs(
                from: share.share
            )
            preparedShare = share
        } catch {
            guard activeSharePreparationID == preparationID else { return }
            errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
        }
        isPreparingShare = false
        activeSharePreparationID = nil
    }

    @MainActor
    private func clearLocalPairingAfterSharingStopped() {
        let localOwnerIDsToPurge = ICloudSharingTeardownPlan.localOwnerIDsToPurge(
            partnerShareOwnerID: settings.partnerShareOwnerID
        )
        var purgeError: Error?
        do {
            try ShareCalLocalDataCleanupService.purgeSharedOwnerMirrors(
                ownerMemberIDs: localOwnerIDsToPurge,
                modelContext: modelContext
            )
        } catch {
            purgeError = error
        }

        preparedShare = nil
        cloudKitDiagnosticMessage = nil
        settings.iCloudSharingEnabled = false
        settings.hasStartedPairing = false
        settings.partnerShareOwnerID = nil
        settings.partnerNoteName = ""
        settings.hasPromptedPartnerNoteForCurrentPairing = false
        settings.hasShownPairingSafetyNoticeForCurrentPairing = false
        settings.partnerSyncedDisplayName = nil
        settings.outgoingShareParticipantIDs = []
        settings.pairingConflict = nil
        settings.clearPairingDate()

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
            clearLocalPairingAfterSharingStopped()
        } catch {
            errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
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
