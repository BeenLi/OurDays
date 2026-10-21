import CloudKit
import PhotosUI
import SwiftData
import SwiftUI
import UserNotifications

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
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]

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
            mirrors: mirrors,
            invitations: invitations,
            currentMemberID: settings.currentMemberID,
            lastSeenActivityAt: settings.lastSeenActivityAt
        )
    }

    /// Keep the springboard icon badge in sync with the in-app unread/pending counts.
    /// Nothing else writes the icon badge after the silent-push migration, so this both
    /// clears a badge orphaned by an older visible push and makes the badge self-clearing.
    private func syncAppIconBadge() {
        let count = AppIconBadgePlan.badgeCount(
            unreadActivityCount: unreadActivityCount,
            pendingInviteCount: pendingInviteBadgeCount
        )
        UNUserNotificationCenter.current().setBadgeCount(count)
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
                Label(settings.strings.usTab, systemImage: "person.2")
            }
            .tag(ShareCalTab.settings)
        }
        .tint(OurDaysTheme.ink)
        .task {
            await Task.yield()
            await reevaluateRootSheetFlow()
        }
        .task {
            // Clear any badge orphaned by a pre-silent-push build and seed the live count.
            syncAppIconBadge()
        }
        .onChange(of: unreadActivityCount) { _, _ in syncAppIconBadge() }
        .onChange(of: pendingInviteBadgeCount) { _, _ in syncAppIconBadge() }
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
            // decision: never sync/merge while it is unresolved — and use the core
            // decision (not the prompt-presentation-narrowed gate) so an async push
            // can't slip through the window when the sheet isn't currently on screen.
            Task {
                guard !hasUnresolvedExistingICloudRecoveryDecision else { return }
                await runForegroundSync(consumingAcceptedShareSignal: false, forceCloudKit: true)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            syncAppIconBadge()
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
            clearPartnerPairingState()
            settings.pairingConflict = nil

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
            let previousPartnerID = settings.partnerShareOwnerID
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
                if previousPartnerID != nil, previousPartnerID != keptID {
                    settings.partnerShareOwnerID = nil
                }
            }
            // Keeping someone other than the previous partner is a replacement:
            // the old partner's nickname, avatar and pairing date must not carry
            // over to the new person.
            if let previousPartnerID, previousPartnerID != settings.partnerShareOwnerID {
                clearPartnerPairingState()
            }
            settings.pairingConflict = nil
            await runForegroundSync(consumingAcceptedShareSignal: false, forceCloudKit: true)
        } catch {
            settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
        }
    }

    /// Forgets everything tied to the previous partner so a new pairing starts
    /// clean (nickname note, synced profile, pairing date, one-time notices).
    /// Callers set `partnerShareOwnerID` themselves.
    @MainActor
    private func clearPartnerPairingState() {
        settings.partnerSyncedDisplayName = nil
        settings.clearPartnerAvatars()
        settings.partnerNoteName = ""
        settings.hasPromptedPartnerNoteForCurrentPairing = false
        settings.hasShownPairingSafetyNoticeForCurrentPairing = false
        settings.clearPairingDate()
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

    /// Core data-safety fact: the existing-iCloud-data recovery decision is still
    /// unresolved and the local state looks fresh, so an automatic sync would risk
    /// merging before the user decides. Independent of whether the prompt is on screen.
    private var hasUnresolvedExistingICloudRecoveryDecision: Bool {
        ExistingICloudDataRecoveryPlan.shouldDeferAutomaticSync(
            hasResolvedPrompt: settings.hasResolvedExistingICloudDataPrompt,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
            lastSyncAt: settings.lastSyncAt
        )
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
        // Never auto-sync while the existing-iCloud-data recovery decision is unresolved,
        // regardless of whether the prompt is currently on screen.
        guard !hasUnresolvedExistingICloudRecoveryDecision else { return }
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
        settings.clearPartnerAvatars()
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
        EventCommentIndicatorPlan.commentedAnchorKeys(comments)
    }

    // My own events render as transient "display:" mirrors whose id is not what comments are
    // keyed by; this maps their shared mirrorKey to the persisted twin's real id so the dot
    // (and its resolution) also fires for "partner commented on my event".
    var persistedMirrorIDByKey: [String: String] {
        var map: [String: String] = [:]
        for mirror in mirrors where !mirror.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix) {
            map[mirror.mirrorKey] = mirror.id
        }
        return map
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
            visibleLocalDisplayMirrors + visiblePartnerMirrors,
            excluding: visibleJointEvents
        )
    }

    var visibleLocalDisplayMirrors: [EventMirror] {
        localDisplayMirrors.filter { mirror in
            WeekStripPlan.overlaps(
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
        let partnerWeekMirrors = CalendarMirrorVisibilityPlan.memberMirrors(
            activeMirrors,
            currentMemberID: settings.currentMemberID,
            partnerShareOwnerID: settings.partnerShareOwnerID
        ).filter { $0.ownerMemberID == settings.partnerShareOwnerID }
        return WeekStripPlan.days(
            containing: selectedDate,
            mine: localDisplayMirrors.map { interval($0.startDate, $0.endDate) },
            partner: partnerWeekMirrors.map { interval($0.startDate, $0.endDate) },
            joint: acceptedJointEvents.map { interval($0.startDate, $0.endDate) }
        )
    }

    var pairingDayCount: Int? {
        guard isPaired, let pairingDate = settings.pairingDate else { return nil }
        return PairingDatePlan.dayCount(since: pairingDate)
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
        "\(Int(weekInterval.start.timeIntervalSince1970)):\(Int(weekInterval.end.timeIntervalSince1970)):\(settings.currentMemberID)"
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

        VStack(spacing: 10) {
            CompactCalendarTopBar(
                selectedDate: $selectedDate,
                mode: $mode,
                title: CalendarDateNavigationPlan.compactTitle(for: selectedDate, mode: mode, locale: settings.appLanguage.locale),
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
                await performSync()
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
            from: weekInterval.start,
            to: weekInterval.end
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

struct DayAlignedTimelineView: View {
    @Environment(SettingsStore.self) private var settings
    let dayStart: Date
    let myTitle: String
    let myEvents: [EventMirror]
    let jointEvents: [JointScheduleEvent]
    let focusedJointEventID: String?
    let partnerTitle: String
    let partnerEvents: [EventMirror]
    @Binding var isNightExpanded: Bool
    let availableWidth: CGFloat
    let onSelect: (EventMirror) -> Void
    let onSelectJoint: (JointScheduleEvent) -> Void
    let commentedAnchorKeys: Set<String>
    let persistedMirrorIDByKey: [String: String]

    private let hourHeight: CGFloat = 60
    private let railWidth: CGFloat = 40
    private let railSpacing: CGFloat = 6
    private let laneSpacing: CGFloat = 6
    private let horizontalPadding: CGFloat = 12

    /// First hour drawn; the hours before it fold into the "both free" band.
    func startHour(isExpanded: Bool) -> Int {
        let timedStarts = myEvents.filter { !$0.isAllDay }.map(\.startDate)
            + partnerEvents.filter { !$0.isAllDay }.map(\.startDate)
            + jointEvents.filter { !$0.isAllDay }.map(\.startDate)
        return DayTimelineCollapsePlan.visibleStartHour(
            eventStartDates: timedStarts,
            dayStart: dayStart,
            now: .now,
            isExpanded: isExpanded
        )
    }

    var visibleStartHour: Int { startHour(isExpanded: isNightExpanded) }

    var offsetY: CGFloat { CGFloat(visibleStartHour) * hourHeight }

    var dayHeight: CGFloat {
        DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight) - offsetY
    }

    var laneWidth: CGFloat {
        let available = availableWidth - (horizontalPadding * 2) - railWidth - railSpacing - laneSpacing
        return max(138, available / 2)
    }

    var contentWidth: CGFloat {
        railWidth + railSpacing + (laneWidth * 2) + laneSpacing
    }

    var body: some View {
        let collapsedStartHour = startHour(isExpanded: false)

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
                    VStack(spacing: 8) {
                        if collapsedStartHour > 0 {
                            nightBand(collapsedStartHour: collapsedStartHour)
                        }

                        ZStack(alignment: .topLeading) {
                            let jointPlacements = DayTimelineJointLayoutPlan.placements(for: jointEvents)

                            // Paper-white lane sheets sit under the hour lines; events sit on top.
                            HStack(spacing: laneSpacing) {
                                ForEach(0..<2, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(OurDaysTheme.surface)
                                        .frame(width: laneWidth, height: dayHeight)
                                }
                            }
                            .offset(x: railWidth + railSpacing)

                            DayTimelineHourGrid(
                                hourHeight: hourHeight,
                                startHour: visibleStartHour,
                                railWidth: railWidth,
                                railSpacing: railSpacing,
                                contentWidth: contentWidth
                            )
                            .allowsHitTesting(false)

                            HStack(alignment: .top, spacing: railSpacing) {
                                DayTimelineHourRail(hourHeight: hourHeight, startHour: visibleStartHour, width: railWidth)

                                HStack(alignment: .top, spacing: laneSpacing) {
                                    DayTimelineLane(
                                        events: myEvents,
                                        identity: .me,
                                        dayStart: dayStart,
                                        hourHeight: hourHeight,
                                        startHour: visibleStartHour,
                                        width: laneWidth,
                                        onSelect: onSelect,
                                        commentedAnchorKeys: commentedAnchorKeys,
                                        persistedMirrorIDByKey: persistedMirrorIDByKey
                                    )

                                    DayTimelineLane(
                                        events: partnerEvents,
                                        identity: .partner,
                                        dayStart: dayStart,
                                        hourHeight: hourHeight,
                                        startHour: visibleStartHour,
                                        width: laneWidth,
                                        onSelect: onSelect,
                                        commentedAnchorKeys: commentedAnchorKeys,
                                        persistedMirrorIDByKey: persistedMirrorIDByKey
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

                                // A Button (not .onTapGesture) so the joint block hit-tests as
                                // reliably as the regular lane events in DayTimelineLane.
                                Button {
                                    onSelectJoint(event)
                                } label: {
                                    DayTimelineJointEventBlock(
                                        event: event,
                                        isFocused: event.id == focusedJointEventID,
                                        hasComments: EventCommentIndicatorPlan.hasComments(
                                            jointEvent: event,
                                            commentedKeys: commentedAnchorKeys
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(44, slotWidth - 4), height: eventHeight, alignment: .top)
                                .offset(
                                    x: railWidth + railSpacing + 4 + (CGFloat(placement.columnIndex) * slotWidth),
                                    y: eventY
                                )
                                .accessibilityLabel("\(event.title), \(timeText(for: event)), \(event.calendarTitle), \(settings.strings.jointScheduleLabel)")
                            }

                            DayTimelineNowIndicatorOverlay(
                                dayStart: dayStart,
                                hourHeight: hourHeight,
                                offsetY: offsetY,
                                visibleHeight: dayHeight,
                                railWidth: railWidth,
                                railSpacing: railSpacing,
                                contentWidth: contentWidth
                            )
                        }
                        .frame(width: contentWidth, height: dayHeight, alignment: .topLeading)
                    }
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

    /// The folded night hours. Tapping it unfolds 00:00 onward (and folds it back).
    private func nightBand(collapsedStartHour: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isNightExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isNightExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
                Text(settings.strings.nightCollapsedLabel(untilHour: collapsedStartHour))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(OurDaysTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OurDaysTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, railWidth + railSpacing)
        .frame(width: contentWidth)
        .accessibilityIdentifier("timeline-night-band")
    }

    private func frame(for event: JointScheduleEvent) -> DayTimelineEventFrame {
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
        let targetY = DayTimelineScrollTargetPlan.defaultTargetY(hourHeight: hourHeight) - offsetY

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
        ) - offsetY

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
            ForEach(DayTimelineLayoutPlan.hourMarks(hourHeight: hourHeight).filter { $0.hour >= startHour }, id: \.hour) { mark in
                Text(String(format: "%02d:00", mark.hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .offset(y: max(0, mark.y - offsetY - 7))
            }
        }
        .frame(width: width, height: DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight) - offsetY, alignment: .topTrailing)
    }
}

/// The "now" line + time chip drawn over the day timeline. `TimelineView(.everyMinute)`
/// refreshes it cheaply while visible; `DayTimelineNowIndicatorPlan` returns nil (hiding
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
            if let indicator = DayTimelineNowIndicatorPlan.indicator(
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
            ForEach(DayTimelineLayoutPlan.hourMarks(hourHeight: hourHeight).filter { $0.hour > startHour }, id: \.hour) { mark in
                Rectangle()
                    .fill(OurDaysTheme.hairline)
                    .frame(width: contentWidth - railWidth - railSpacing, height: 1)
                    .offset(x: railWidth + railSpacing, y: mark.y - offsetY)
            }
        }
        .frame(width: contentWidth, height: DayTimelineLayoutPlan.dayHeight(hourHeight: hourHeight) - offsetY, alignment: .topLeading)
    }
}

struct DayTimelineLane: View {
    @Environment(SettingsStore.self) private var settings
    let events: [EventMirror]
    let identity: OurDaysIdentity
    let dayStart: Date
    let hourHeight: CGFloat
    let startHour: Int
    let width: CGFloat
    let onSelect: (EventMirror) -> Void
    let commentedAnchorKeys: Set<String>
    let persistedMirrorIDByKey: [String: String]

    var offsetY: CGFloat { CGFloat(startHour) * hourHeight }

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
                .frame(width: max(44, width - 8), height: eventHeight, alignment: .top)
                .offset(x: 4, y: eventY)
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
            return EventCommentIndicatorPlan.hasComments(
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
            .ourDaysListBackground()
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

/// The comments list + input, reused by `EventDetailView` (regular events) and
/// `JointEventDetailView` (joint events). Behavior is identical for both; only the
/// `EventCommentAnchor` differs, which is what keys the thread and routes CloudKit writes.
struct EventCommentsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]
    @State private var commentBody = ""
    @State private var commentError: String?
    let anchor: EventCommentAnchor

    private var threadComments: [EventComment] {
        comments.filter { $0.eventMirrorID == anchor.key && $0.deletedAt == nil }
    }

    var body: some View {
        let strings = settings.strings
        Section {
            ForEach(threadComments) { comment in
                EventCommentBubble(
                    comment: comment,
                    isMine: comment.authorMemberID == settings.currentMemberID,
                    authorName: authorDisplayName(comment.authorMemberID)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions {
                    Button(role: .destructive) {
                        services.commentService.delete(comment)
                        try? modelContext.save()
                    } label: {
                        Label(strings.deleteButton, systemImage: "trash")
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(strings.addCommentPlaceholder, text: $commentBody, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(OurDaysTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OurDaysTheme.border, lineWidth: 1)
                    )
                Button {
                    addComment()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(OurDaysTheme.onInkFill)
                        .frame(width: 44, height: 44)
                        .background(OurDaysTheme.inkFill, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                .accessibilityLabel(strings.addCommentPlaceholder)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if let commentError {
                Text(commentError)
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.destructive)
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text(strings.commentsSection)
                .font(.footnote.weight(.bold))
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .textCase(nil)
        }
    }

    private func authorDisplayName(_ authorMemberID: String) -> String {
        MemberDisplayNamePlan.displayName(
            forMemberID: authorMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }

    private func addComment() {
        let comment = services.commentService.createComment(
            eventMirrorID: anchor.key,
            authorMemberID: settings.currentMemberID,
            body: commentBody
        )
        modelContext.insert(comment)
        do {
            try modelContext.save()
            commentError = nil
            let anchor = anchor
            let currentMemberID = settings.currentMemberID
            if let cloudKit = services.cloudKitIfAvailable {
                Task {
                    do {
                        try await cloudKit.saveCommentForSync(
                            comment,
                            eventOwnerMemberID: anchor.ownerMemberID,
                            currentMemberID: currentMemberID,
                            eventRecordName: anchor.recordName
                        )
                    } catch {
                        commentError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                    }
                }
            }
            commentBody = ""
        } catch {
            commentError = error.localizedDescription
        }
    }
}

/// One comment as a chat bubble: the partner on the left in a white bubble, me on the
/// right in my identity color — the same left/right reading as any messaging app.
struct EventCommentBubble: View {
    let comment: EventComment
    let isMine: Bool
    let authorName: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 48)
            } else {
                MemberAvatarForID(memberID: comment.authorMemberID, size: 28)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(comment.body)
                    .font(.body)
                    .foregroundStyle(isMine ? Color.white : OurDaysTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isMine ? OurDaysIdentity.me.color : OurDaysTheme.surface,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: isMine ? 18 : 6,
                            bottomTrailingRadius: isMine ? 6 : 18,
                            topTrailingRadius: 18,
                            style: .continuous
                        )
                    )
                    .textSelection(.enabled)
                Text("\(authorName) · \(comment.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .padding(.horizontal, 6)
            }

            if !isMine {
                Spacer(minLength: 48)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Owner-tinted header of an event detail sheet: who it belongs to, a serif title,
/// and one line each for time and place.
struct EventDetailHeader: View {
    @Environment(SettingsStore.self) private var settings
    let title: String
    let ownerLabel: String
    let ownerMemberID: String?
    let timeText: String
    let location: String?
    let calendarTitle: String?
    let isJoint: Bool

    private var identity: OurDaysIdentity? {
        guard let ownerMemberID else { return nil }
        return ownerMemberID == settings.currentMemberID ? .me : .partner
    }

    private var primary: Color { isJoint ? OurDaysTheme.onJoint : OurDaysTheme.ink }
    private var secondary: Color { isJoint ? OurDaysTheme.onJointSecondary : (identity?.onTint ?? OurDaysTheme.secondaryInk) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isJoint {
                    HStack(spacing: -8) {
                        MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: 26)
                        MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: 26)
                    }
                } else if let ownerMemberID {
                    MemberAvatarForID(memberID: ownerMemberID, size: 26)
                }
                Text(ownerLabel)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(secondary)
            }

            Text(title)
                .font(OurDaysTheme.displayFont(28))
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label(timeText, systemImage: "clock")
                if let location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                if let calendarTitle, !calendarTitle.isEmpty {
                    Label(calendarTitle, systemImage: "calendar")
                }
            }
            .font(.subheadline)
            .foregroundStyle(isJoint ? OurDaysTheme.onJointSecondary : OurDaysTheme.secondaryInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isJoint ? OurDaysTheme.joint : (identity?.tint ?? OurDaysTheme.surface),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @State private var inviteError: String?
    @State private var inviteSuccessMessage: String?
    @State private var conflictMessage: String?
    @State private var isShowingInviteConflict = false
    let event: EventMirror

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                Section {
                    EventDetailHeader(
                        title: event.title,
                        ownerLabel: event.ownerMemberID == settings.currentMemberID
                            ? strings.myScheduleLabel
                            : strings.partnerScheduleLabel(settings.partnerDisplayName),
                        ownerMemberID: event.ownerMemberID,
                        timeText: detailTimeText,
                        location: event.location,
                        calendarTitle: event.sourceCalendarTitle,
                        isJoint: false
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.ink)
                            .ourDaysCard()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                Section {
                    Button {
                        createInviteAfterConflictCheck()
                    } label: {
                        Label(strings.invitePartnerButton, systemImage: "person.badge.plus")
                            .foregroundStyle(OurDaysTheme.ink)
                    }
                    // Optimistic send shows success instantly; disable to prevent a
                    // double-tap creating a duplicate invitation within this sheet.
                    .disabled(inviteSuccessMessage != nil)

                    if let inviteSuccessMessage {
                        Text(inviteSuccessMessage)
                            .font(.caption)
                            .foregroundStyle(OurDaysIdentity.me.onTint)
                    }

                    if let inviteError {
                        Text(inviteError)
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.destructive)
                    }
                } header: {
                    Text(strings.inviteSection)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .textCase(nil)
                }

                // `event` may be my own transient "display:" mirror; resolve to the persisted
                // twin so the thread anchors to the real record id (where the partner's comment
                // on my event landed) and writes route to the right zone. No twin yet (unsynced
                // own event) ⇒ no comment section, matching the prior transient-mirror behavior.
                if let commentMirror = EventDetailMirrorResolutionPlan.persistedTwin(for: event, in: mirrors) {
                    EventCommentsSection(anchor: EventCommentAnchorPlan.anchor(forMirror: commentMirror))
                }
            }
            .listSectionSpacing(16)
            .ourDaysListBackground()
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

    private var detailTimeText: String {
        EventDetailTimePlan.text(
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            strings: settings.strings,
            locale: settings.appLanguage.locale
        )
    }

    private func createInviteAfterConflictCheck() {
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
        inviteError = nil
        inviteSuccessMessage = nil
        let cloudKit = services.cloudKitIfAvailable
        let invitation = EventInvitation(
            creatorMemberID: settings.currentMemberID,
            inviteeMemberID: settings.partnerOwnerIDForLocalData,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            statusRawValue: InvitationStatus.pending.rawValue,
            // Mark "upload owed" so a failed/optimistic send self-heals on the next sync.
            needsCloudKitUpload: cloudKit != nil
        )
        modelContext.insert(invitation)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(invitation)
            inviteError = error.localizedDescription
            return
        }

        // Optimistic send (req2): the invitation is durably in the local store, so report
        // success immediately rather than blocking on the CloudKit round-trip. The upload
        // moves to the background; if it fails, `needsCloudKitUpload` keeps it queued for
        // self-heal on the next foregroundSync (InvitationReuploadPlan.creationsNeedingReupload).
        inviteSuccessMessage = settings.strings.invitationSentMessage

        guard let cloudKit else { return }
        Task {
            do {
                try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                invitation.needsCloudKitUpload = false
                try? modelContext.save()
            } catch {
                // Leave the flag set; the next sync retries. Don't surface an error that
                // would contradict the success already shown to the user.
            }
        }
    }

    private func timeText(for event: EventMirror) -> String {
        if event.isAllDay {
            return settings.strings.allDay
        }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
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
}

/// Detail screen for a joint (共同) event. A joint event has no `EventMirror` of its own
/// (it's derived from an accepted `EventInvitation`), so it shows the invitation's fields
/// and a comments thread anchored to the invitation — letting both partners comment on
/// the same thread. No "invite partner" section: it's already a shared/accepted event.
struct JointEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    let event: JointScheduleEvent
    let invitation: EventInvitation

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                Section {
                    EventDetailHeader(
                        title: event.title,
                        ownerLabel: strings.jointScheduleLabel,
                        ownerMemberID: nil,
                        timeText: EventDetailTimePlan.text(
                            startDate: event.startDate,
                            endDate: event.endDate,
                            isAllDay: event.isAllDay,
                            strings: strings,
                            locale: settings.appLanguage.locale
                        ),
                        location: event.location,
                        calendarTitle: nil,
                        isJoint: true
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.ink)
                            .ourDaysCard()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                EventCommentsSection(anchor: EventCommentAnchorPlan.anchor(forInvitation: invitation))
            }
            .listSectionSpacing(16)
            .ourDaysListBackground()
            .navigationTitle(strings.eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
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
        }
    }

    private func performSync() async {
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
}

struct ActivityTabView: View {
    @Environment(SettingsStore.self) private var settings
    @Query(sort: \EventComment.createdAt) private var comments: [EventComment]
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @State private var selectedEvent: EventMirror?
    @State private var selectedJointEvent: JointScheduleEvent?
    @State private var seenSnapshot: Date?

    private var items: [ActivityFeedItem] {
        ActivityFeedPlan.items(
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
                ForEach(ActivityFeedSectionPlan.sections(items)) { section in
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
    /// open the matching detail. Mirrors the anchor resolution in `ActivityFeedPlan`.
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
        let pendingInvitations = InvitationListPlan.sortedForDisplay(
            visibleInvitations.filter { $0.status == .pending }
        )
        let handledInvitations = InvitationListPlan.sortedForDisplay(
            visibleInvitations.filter { $0.status != .pending }
        )
        let answerableCount = pendingInvitations.filter {
            InvitationInteractionPlan.canRespond(to: $0, currentMemberID: settings.currentMemberID)
        }.count

        List {
            OurDaysPageHeader(
                title: strings.invitesTab,
                subtitle: answerableCount > 0 ? strings.pendingInvitationsSubtitle(answerableCount) : nil
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            if !pendingIncomingAccessRequests.isEmpty {
                Section {
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
                        .invitesRowStyle()
                    }
                } header: {
                    OurDaysSectionLabel(title: strings.pendingAccessRequestsLabel).textCase(nil)
                }
            }

            if !pendingInvitations.isEmpty {
                Section {
                    ForEach(pendingInvitations) { invitation in
                        InvitationTicket(invitation: invitation, currentMemberID: settings.currentMemberID) {
                            accept(invitation)
                        } decline: {
                            decline(invitation)
                        }
                        .invitesRowStyle()
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
                } header: {
                    OurDaysSectionLabel(title: strings.invitationStatusTitle(for: .pending)).textCase(nil)
                }
            }

            if !handledInvitations.isEmpty {
                Section {
                    ForEach(handledInvitations) { invitation in
                        InvitationRow(invitation: invitation, currentMemberID: settings.currentMemberID) {
                            accept(invitation)
                        } decline: {
                            decline(invitation)
                        } openInCalendar: {
                            openInCalendar(invitation)
                        }
                        .invitesRowStyle(vertical: 3)
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
                } header: {
                    OurDaysSectionLabel(title: strings.handledInvitationsSection).textCase(nil)
                }
            }

            if visibleInvitations.isEmpty && pendingIncomingAccessRequests.isEmpty {
                ContentUnavailableView(strings.noInvitations, systemImage: "envelope.open")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(OurDaysTheme.destructive)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .ourDaysListBackground()
        .toolbar(.hidden, for: .navigationBar)
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

private extension View {
    func invitesRowStyle(vertical: CGFloat = 6) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: vertical, leading: 16, bottom: vertical, trailing: 16))
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

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MemberAvatarForID(memberID: request.requesterMemberID, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.incomingHistoryRequestText(
                        requester: requesterDisplayName,
                        rangeText: rangeText
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(strings.prePairingHistoryLabel)
                        .font(.caption)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                }
            }
            HStack(spacing: 10) {
                Button(strings.declineButton, action: decline)
                    .buttonStyle(OurDaysSecondaryButtonStyle())
                Button(strings.approveButton, action: approve)
                    .buttonStyle(OurDaysPrimaryButtonStyle())
            }
        }
        .ourDaysCard()
    }
}

/// A pending invitation drawn as a ticket stub: the date block on the left, a dashed
/// tear line, the details on the right, and the answer buttons under a second tear —
/// an invitation is, after all, a ticket handed to the other person.
struct InvitationTicket: View {
    @Environment(SettingsStore.self) private var settings
    let invitation: EventInvitation
    let currentMemberID: String
    let accept: () -> Void
    let decline: () -> Void

    private var isFromMe: Bool { invitation.creatorMemberID == currentMemberID }
    private var senderIdentity: OurDaysIdentity { isFromMe ? .me : .partner }

    var body: some View {
        let strings = settings.strings
        let locale = settings.appLanguage.locale
        let canRespond = InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: currentMemberID)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(invitation.startDate.formatted(.dateTime.month(.abbreviated).locale(locale)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(senderIdentity.onTint)
                    Text(invitation.startDate.formatted(.dateTime.day()))
                        .font(OurDaysTheme.displayFont(38))
                        .foregroundStyle(OurDaysTheme.ink)
                    Text(invitation.startDate.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(senderIdentity.onTint)
                }
                .frame(width: 88)
                .frame(maxHeight: .infinity)
                .background(senderIdentity.tint)

                TicketTearLine(axis: .vertical)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        MemberAvatarForID(memberID: invitation.creatorMemberID, size: 20)
                        Text(isFromMe ? strings.sentByMeLabel : strings.invitedYouLine(settings.partnerDisplayName))
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Text(invitation.title)
                        .font(.headline)
                        .foregroundStyle(OurDaysTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(invitation.isAllDay
                         ? strings.allDay
                         : "\(strings.shortTimeText(invitation.startDate)) – \(strings.shortTimeText(invitation.endDate))")
                        .font(.subheadline)
                        .foregroundStyle(OurDaysTheme.ink.opacity(0.8))
                    if let location = invitation.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

            TicketTearLine(axis: .horizontal)

            Group {
                if canRespond {
                    HStack(spacing: 10) {
                        Button(strings.declineButton, action: decline)
                            .buttonStyle(OurDaysSecondaryButtonStyle())
                            .frame(maxWidth: 120)
                        Button(strings.acceptAndAddButton, action: accept)
                            .buttonStyle(OurDaysPrimaryButtonStyle())
                    }
                } else {
                    Text(strings.waitingForReplyLine(settings.partnerDisplayName))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
            }
            .padding(14)
        }
        .background(OurDaysTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

struct TicketTearLine: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis

    var body: some View {
        switch axis {
        case .horizontal:
            Line(axis: .horizontal)
                .stroke(OurDaysTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1.5)
        case .vertical:
            Line(axis: .vertical)
                .stroke(OurDaysTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 1.5)
        }
    }

    private struct Line: Shape {
        let axis: Axis

        func path(in rect: CGRect) -> Path {
            var path = Path()
            switch axis {
            case .horizontal:
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            case .vertical:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
            return path
        }
    }
}

/// A handled (accepted / declined / canceled) invitation: a compact row with its status.
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
        let isFromMe = invitation.creatorMemberID == currentMemberID

        HStack(spacing: 12) {
            Text(invitation.startDate.formatted(.dateTime.day()))
                .font(OurDaysTheme.displayFont(20))
                .foregroundStyle(OurDaysTheme.ink)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.ink)
                    .lineLimit(1)
                Text("\(isFromMe ? strings.sentByMeLabel : strings.invitedYouLine(settings.partnerDisplayName)) · \(settings.strings.abbreviatedDateTimeText(invitation.startDate))")
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            OurDaysChip(
                title: strings.invitationStatusTitle(for: invitation.status),
                foreground: invitation.status == .accepted ? OurDaysTheme.ink : OurDaysTheme.secondaryInk,
                background: invitation.status == .accepted ? OurDaysTheme.sunken : OurDaysTheme.paper
            )

            if canOpenInCalendar {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
            }
        }
        .ourDaysCard(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canOpenInCalendar else { return }
            openInCalendar()
        }
    }
}

enum SettingsSheet: Identifiable {
    case historyRequest
    case myAvatar
    case partnerAvatar

    var id: String {
        switch self {
        case .historyRequest: "historyRequest"
        case .myAvatar: "myAvatar"
        case .partnerAvatar: "partnerAvatar"
        }
    }
}

/// The hero card of the 我们 tab: the two avatars linked together, how many days the
/// pairing has lasted, and the sync state. Actions that change the pairing live in the
/// list below it, so the card only shows state plus the one next step.
struct PairingStatusCard: View {
    @Environment(SettingsStore.self) private var settings
    let status: PairingStatus
    let pairingDate: Date?
    let partnerName: String
    let syncStatusText: String
    let isCloudKitEnabled: Bool
    let isPreparingShare: Bool
    let isCheckingCloudKitAccount: Bool
    let isSyncing: Bool
    let cloudKitDiagnosticMessage: String?
    let onStartPairing: () -> Void
    let onCheckCloudKitStatus: () -> Void
    let onSync: () -> Void
    let onEditMyAvatar: () -> Void
    let onEditPartnerAvatar: () -> Void
    let onHideCloudKitDiagnostic: () -> Void

    var body: some View {
        let strings = settings.strings

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: -14) {
                    Button(action: onEditMyAvatar) {
                        MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.myAvatarLabel)
                    .zIndex(1)

                    if status != .notPaired {
                        Button(action: onEditPartnerAvatar) {
                            MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: 56)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(strings.partnerAvatarLabel(partnerName))
                    } else {
                        Circle()
                            .strokeBorder(OurDaysTheme.border, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .background(Circle().fill(OurDaysTheme.surface))
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "plus").font(.headline).foregroundStyle(OurDaysTheme.secondaryInk))
                            .accessibilityHidden(true)
                    }
                }

                Spacer()

                Button(action: onSync) {
                    Group {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(OurDaysTheme.ink)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(OurDaysTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .accessibilityLabel(strings.syncAccessibilityLabel)
            }

            if status == .paired {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.pairingDayHeadline(pairingDate.map { PairingDatePlan.dayCount(since: $0) } ?? 0))
                        .font(OurDaysTheme.displayFont(32))
                        .foregroundStyle(OurDaysTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let pairingDate {
                        Text(strings.pairedSinceLine(partnerName: partnerName, dateText: strings.pairingDateText(for: pairingDate)))
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pairing-day-count")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.pairingStatusTitle(for: status))
                        .font(OurDaysTheme.displayFont(28))
                        .foregroundStyle(OurDaysTheme.ink)
                    Text(status == .waitingForYouToShare ? strings.pairingWaitingForYouToShareDescription : strings.pairingDescription)
                        .font(.subheadline)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pairingDate {
                        Text(strings.pairingDateLine(strings.pairingDateText(for: pairingDate)))
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
            }

            HStack(spacing: 8) {
                OurDaysChip(
                    title: strings.pairingStatusTitle(for: status),
                    foreground: status == .paired ? OurDaysTheme.onInkFill : OurDaysTheme.ink,
                    background: status == .paired ? OurDaysTheme.inkFill : OurDaysTheme.sunken
                )
                OurDaysChip(title: syncStatusText, foreground: OurDaysTheme.secondaryInk)
            }

            if status == .notPaired || status == .waitingForYouToShare {
                HStack(spacing: 10) {
                    Button {
                        onStartPairing()
                    } label: {
                        Label(strings.startPairingButton(isPreparing: isPreparingShare), systemImage: "person.badge.plus")
                    }
                    .buttonStyle(OurDaysPrimaryButtonStyle())
                    .disabled(!isCloudKitEnabled || isPreparingShare)

                    checkICloudButton(strings: strings)
                }
            } else if status != .paired {
                HStack {
                    Spacer()
                    checkICloudButton(strings: strings)
                }
            }

            if !isCloudKitEnabled {
                Text(strings.iCloudSharingUnavailableLocalBuild)
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.destructive)
            }

            if let cloudKitDiagnosticMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(strings.diagnosticsTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OurDaysTheme.secondaryInk)
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
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(OurDaysTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OurDaysTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private func checkICloudButton(strings: ShareCalStrings) -> some View {
        Button {
            onCheckCloudKitStatus()
        } label: {
            Image(systemName: "icloud.and.arrow.up")
                .font(.headline)
                .foregroundStyle(OurDaysTheme.ink)
                .frame(width: 48, height: 48)
                .overlay(Circle().stroke(OurDaysTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isCloudKitEnabled || isCheckingCloudKitAccount)
        .accessibilityLabel(strings.checkICloudStatusButton(isChecking: isCheckingCloudKitAccount))
    }
}

struct SharingScopeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(OurDaysTheme.ink)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A tappable settings row with a leading glyph and a trailing chevron.
struct SettingsNavigationRow<Leading: View>: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var isLoading = false
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                    .foregroundStyle(OurDaysTheme.ink)
                    .frame(minWidth: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(OurDaysTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                }
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Edits one avatar: a photo, or up to three letters on a palette tint. The identity ring
/// stays fixed around the preview, because it is what tells the two people apart.
struct AvatarEditorSheet: View {
    private enum Mode: Hashable {
        case photo
        case text
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let title: String
    let defaultAvatar: MemberAvatar?
    let fallbackText: String
    let identity: OurDaysIdentity
    let footnote: String
    let onSave: (MemberAvatar?) -> Void
    @State private var mode: Mode
    @State private var imageData: Data?
    @State private var text: String
    @State private var background: AvatarBackground
    @State private var isReset: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false

    init(
        title: String,
        avatar: MemberAvatar?,
        defaultAvatar: MemberAvatar? = nil,
        fallbackText: String,
        identity: OurDaysIdentity,
        footnote: String,
        onSave: @escaping (MemberAvatar?) -> Void
    ) {
        self.title = title
        self.defaultAvatar = defaultAvatar
        self.fallbackText = fallbackText
        self.identity = identity
        self.footnote = footnote
        self.onSave = onSave
        let normalized = MemberAvatarPlan.normalized(avatar)
        _mode = State(initialValue: normalized?.imageData != nil ? .photo : .text)
        _imageData = State(initialValue: normalized?.imageData)
        _text = State(initialValue: normalized?.text ?? "")
        _background = State(initialValue: normalized?.background ?? (identity == .me ? .teal : .coral))
        _isReset = State(initialValue: normalized == nil)
    }

    /// What Done saves: nil means "no custom avatar", so the default shows again.
    private var draft: MemberAvatar? {
        guard !isReset else { return nil }
        switch mode {
        case .photo:
            return imageData.map { MemberAvatar(imageData: $0) }
        case .text:
            return MemberAvatarPlan.normalized(MemberAvatar(text: text, background: background))
        }
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    MemberAvatarView(
                        avatar: draft ?? defaultAvatar,
                        fallbackText: fallbackText,
                        identity: identity,
                        size: 132
                    )
                    .padding(.top, 8)

                    Picker("", selection: $mode) {
                        Text(strings.avatarPhotoTab).tag(Mode.photo)
                        Text(strings.avatarTextTab).tag(Mode.text)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Group {
                        switch mode {
                        case .photo:
                            photoContent(strings: strings)
                        case .text:
                            textContent(strings: strings)
                        }
                    }
                    .ourDaysCard()

                    Label {
                        Text(footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)

                    Button(strings.resetAvatarButton) {
                        isReset = true
                        imageData = nil
                        text = ""
                        pickerItem = nil
                    }
                    .buttonStyle(OurDaysSecondaryButtonStyle())
                    .disabled(isReset)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(OurDaysTheme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(strings.cancelButton) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(strings.doneButton) {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoadingPhoto)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                isLoadingPhoto = true
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    await MainActor.run {
                        isLoadingPhoto = false
                        if let data, let jpeg = AvatarImageRenderer.squareJPEG(from: data) {
                            imageData = jpeg
                            isReset = false
                        }
                    }
                }
            }
        }
    }

    private func photoContent(strings: ShareCalStrings) -> some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 10) {
                if isLoadingPhoto {
                    ProgressView()
                } else {
                    Image(systemName: "photo.on.rectangle")
                }
                Text(imageData == nil ? strings.choosePhotoButton : strings.changePhotoButton)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(OurDaysPrimaryButtonStyle())
    }

    private func textContent(strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(strings.avatarTextLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                TextField(fallbackText, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(OurDaysTheme.border, lineWidth: 1)
                    )
                    .onChange(of: text) { _, newValue in
                        let limited = MemberAvatarPlan.normalizedText(newValue) ?? ""
                        if limited != newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                            text = limited
                        }
                        isReset = false
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(strings.avatarBackgroundLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                HStack {
                    ForEach(AvatarBackground.allCases) { option in
                        Button {
                            background = option
                            isReset = false
                        } label: {
                            Circle()
                                .fill(option.fill)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle().strokeBorder(
                                        option == background ? OurDaysTheme.ink : OurDaysTheme.border,
                                        lineWidth: option == background ? 2 : 1
                                    )
                                )
                                .overlay {
                                    if option == background {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(option.onFill)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(strings.avatarBackgroundName(option))
                        .accessibilityAddTraits(option == background ? .isSelected : [])
                        if option != AvatarBackground.allCases.last {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

/// Turns a picked photo into the stored avatar: center-cropped square, 256 px, JPEG.
enum AvatarImageRenderer {
    static func squareJPEG(from data: Data, compressionQuality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let targetSide = MemberAvatarPlan.imagePixelSize
        let scale = targetSide / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (targetSide - drawSize.width) / 2, y: (targetSide - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide), format: format)
        return renderer.jpegData(withCompressionQuality: compressionQuality) { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
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
            .ourDaysListBackground()
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
                    OurDaysPageHeader(title: strings.usTitle, subtitle: strings.usSubtitle)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

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
                        onStartPairing: {
                            Task { await prepareShare() }
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
                    Task { await prepareShare() }
                } leading: {
                    Image(systemName: "person.2.badge.gearshape")
                }
                .accessibilityIdentifier("shared-people-official-share-button")
                .disabled(!SharedPeoplePresentationPlan.canOpenOfficialSharing(
                    isCloudKitEnabled: services.isCloudKitEnabled,
                    isPreparingShare: isPreparingShare,
                    isStoppingShare: isStoppingShare
                ))
            }
            .listRowBackground(OurDaysTheme.surface)

            if PairingSafetyEducationPlan.shouldShowPersistentWarning(pairingStatus: pairingStatus) {
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
            case .myAvatar:
                AvatarEditorSheet(
                    title: strings.myAvatarLabel,
                    avatar: settings.currentAvatar,
                    fallbackText: settings.myAvatarFallbackText,
                    identity: .me,
                    footnote: strings.avatarSyncFootnote(settings.partnerDisplayName)
                ) { avatar in
                    settings.currentAvatar = MemberAvatarPlan.normalized(avatar)
                    if pairingStatus != .notPaired {
                        syncNow()
                    }
                }
            case .partnerAvatar:
                AvatarEditorSheet(
                    title: strings.partnerAvatarLabel(settings.partnerDisplayName),
                    avatar: settings.partnerAvatarOverride,
                    defaultAvatar: settings.partnerSyncedAvatar,
                    fallbackText: settings.partnerAvatarFallbackText,
                    identity: .partner,
                    footnote: strings.partnerAvatarFootnote
                ) { avatar in
                    settings.partnerAvatarOverride = MemberAvatarPlan.normalized(avatar)
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
                displayName: displayName,
                avatar: settings.currentAvatar
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
        settings.clearPartnerAvatars()
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

/// Tokens for the paper-and-two-lines look: a warm paper ground, ink text, and one
/// identity color per person (taken from the app icon's teal and coral). Every token
/// has a dark-mode twin so the system appearance keeps working.
enum OurDaysTheme {
    static let paper = Color(light: 0xF6F3EE, dark: 0x15161B)
    static let surface = Color(light: 0xFFFFFF, dark: 0x202128)
    static let sunken = Color(light: 0xEFEBE4, dark: 0x2B2C34)
    static let hairline = Color(light: 0xEEEAE3, dark: 0x30313A)
    static let border = Color(light: 0xE2DDD4, dark: 0x3A3B45)
    static let ink = Color(light: 0x1E2233, dark: 0xECEDF2)
    static let secondaryInk = Color(light: 0x5B6072, dark: 0xA3A7B5)
    /// Fill for primary buttons; `onInkFill` is the text on top of it.
    static let inkFill = Color(light: 0x1E2233, dark: 0xE9EAF0)
    static let onInkFill = Color(light: 0xFFFFFF, dark: 0x1E2233)
    /// Joint ("共同") events: the place where the two lines meet.
    static let joint = Color(light: 0x1E2233, dark: 0x3A4468)
    static let onJoint = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let onJointSecondary = Color(light: 0xC9CCD6, dark: 0xC9CCD6)
    static let destructive = Color(light: 0xB3283A, dark: 0xFF8592)

    static let cornerRadius: CGFloat = 20

    static func displayFont(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

enum OurDaysIdentity {
    case me
    case partner

    /// Rings, dots and avatar fallbacks.
    var color: Color {
        switch self {
        case .me: Color(light: 0x1F7A84, dark: 0x5CC3CC)
        case .partner: Color(light: 0xC93E4E, dark: 0xFF8592)
        }
    }

    /// Event blocks and chips.
    var tint: Color {
        switch self {
        case .me: Color(light: 0xE1F1F2, dark: 0x173A3E)
        case .partner: Color(light: 0xFBE6E8, dark: 0x4A1E25)
        }
    }

    /// Text drawn on `tint` (passes 4.5:1 on it).
    var onTint: Color {
        switch self {
        case .me: Color(light: 0x1A6871, dark: 0x8ED8DE)
        case .partner: Color(light: 0xB3283A, dark: 0xFFB0B9)
        }
    }
}

extension AvatarBackground {
    var fill: Color {
        switch self {
        case .sand: Color(light: 0xEFE6D6, dark: 0x4A4234)
        case .teal: OurDaysIdentity.me.tint
        case .coral: OurDaysIdentity.partner.tint
        case .sage: Color(light: 0xE3EEDF, dark: 0x2F3D2B)
        case .lavender: Color(light: 0xE9E6F5, dark: 0x37334D)
        case .ink: Color(light: 0x1E2233, dark: 0xE9EAF0)
        }
    }

    var onFill: Color {
        self == .ink ? Color(light: 0xFFFFFF, dark: 0x1E2233) : OurDaysTheme.ink
    }
}

struct OurDaysCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = OurDaysTheme.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: OurDaysTheme.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func ourDaysCard(padding: CGFloat = 16, fill: Color = OurDaysTheme.surface) -> some View {
        modifier(OurDaysCardModifier(padding: padding, fill: fill))
    }

    /// Paper ground behind a List/Form, with rows sitting on white cards.
    func ourDaysListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(OurDaysTheme.paper)
    }
}

struct OurDaysPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(OurDaysTheme.onInkFill)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .background(OurDaysTheme.inkFill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

struct OurDaysSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(OurDaysTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .background(OurDaysTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(OurDaysTheme.border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct OurDaysChip: View {
    let title: String
    var foreground: Color = OurDaysTheme.ink
    var background: Color = OurDaysTheme.sunken

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

/// Small grey section label above a card group.
struct OurDaysSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.bold))
            .foregroundStyle(OurDaysTheme.secondaryInk)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Serif page title with an optional one-line subtitle above it, replacing the
/// default large navigation title so every tab opens the same way.
struct OurDaysPageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let subtitle {
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .lineLimit(1)
            }
            Text(title)
                .font(OurDaysTheme.displayFont(32))
                .foregroundStyle(OurDaysTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A member's avatar: photo, or text on a palette tint, or the name's first character on
/// the identity tint. The identity color always rings it, so a custom avatar never hides
/// whose event or comment it is.
struct MemberAvatarView: View {
    let avatar: MemberAvatar?
    let fallbackText: String
    let identity: OurDaysIdentity
    var size: CGFloat = 32

    private var ringWidth: CGFloat { size >= 80 ? 4 : (size >= 40 ? 2.5 : 2) }

    var body: some View {
        ZStack {
            Circle().fill(OurDaysTheme.surface)
            content
                .clipShape(Circle())
                .padding(size >= 80 ? ringWidth + 3 : ringWidth)
        }
        .overlay(Circle().stroke(identity.color, lineWidth: ringWidth))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        let normalized = MemberAvatarPlan.normalized(avatar)
        if let imageData = normalized?.imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let text = normalized?.text {
            let background = normalized?.background
            ZStack {
                (background?.fill ?? identity.tint)
                Text(text)
                    .font(OurDaysTheme.displayFont(size * (text.count >= 3 ? 0.3 : 0.38)))
                    .foregroundStyle(background?.onFill ?? identity.onTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.08)
            }
        } else {
            ZStack {
                identity.tint
                Text(fallbackText)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(identity.onTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

extension SettingsStore {
    var myAvatarFallbackText: String {
        MemberAvatarPlan.initials(from: currentDisplayName, fallback: strings.meTitle)
    }

    var partnerAvatarFallbackText: String {
        MemberAvatarPlan.initials(from: partnerDisplayName, fallback: strings.partnerTitle)
    }
}

/// Avatar for whoever owns `memberID` (me or the partner), resolved from settings.
struct MemberAvatarForID: View {
    @Environment(SettingsStore.self) private var settings
    let memberID: String
    var size: CGFloat = 32

    var body: some View {
        if memberID == settings.currentMemberID {
            MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: size)
        } else {
            MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: size)
        }
    }
}

extension Color {
    /// A color that follows the system appearance, from two 0xRRGGBB literals.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
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
