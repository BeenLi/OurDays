import CloudKit
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
    /// Scroll to the pairing card and open the invite sheet to send my link back.
    case shareBack
}

enum RootSheet: Identifiable, Equatable {
    case initialProfilePrompt
    case existingICloudDataRecovery
    case partnerNotePrompt
    case pairingSafetyNotice
    case shareBackPrompt

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
        case .shareBackPrompt:
            return "shareBackPrompt"
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
        PairingSettingsPolicy.status(
            hasStartedPairing: settings.hasStartedPairing,
            outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
            incomingOwnerID: settings.partnerShareOwnerID
        )
    }

    private var pendingInviteBadgeCount: Int {
        PendingActionBadgePolicy.count(
            invitations: invitations,
            accessRequests: accessRequests,
            currentMemberID: settings.currentMemberID
        )
    }

    private var unreadActivityCount: Int {
        ActivityFeedPolicy.unreadCount(
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
        let count = AppIconBadgePolicy.badgeCount(
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
                    guard let request = CalendarFocusPolicy.request(for: invitation) else { return }
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
            if newStatus == .notPaired {
                // A later pairing, even with the same person, starts the guide over.
                settings.sentInviteBackToOwnerID = nil
                settings.shareBackPromptShownForOwnerID = nil
            }
            guard newStatus == .paired || newStatus == .waitingForYouToShare else { return }
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
                        settings.currentDisplayName = PairingSettingsPolicy.randomDisplayName()
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
            case .shareBackPrompt:
                ShareBackPromptSheet(
                    partnerName: PairingGuidePolicy.knownPartnerName(
                        partnerNoteName: settings.partnerNoteName,
                        partnerSyncedDisplayName: settings.partnerSyncedDisplayName
                    ),
                    onSendBack: {
                        settings.shareBackPromptShownForOwnerID = settings.partnerShareOwnerID
                        settingsFocus = .shareBack
                        selectedTab = .settings
                    },
                    onLater: {
                        settings.shareBackPromptShownForOwnerID = settings.partnerShareOwnerID
                    }
                )
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
                ForEach(TwoPersonPairingConflictPresentationPolicy.candidateIDs(conflict), id: \.self) { candidateID in
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
            let ownerIDsToPurge = ICloudSharingTeardownPolicy.localOwnerIDsToPurge(
                partnerShareOwnerID: settings.partnerShareOwnerID
            )
            if let oldPartnerID = settings.partnerShareOwnerID {
                try await cloudKit.deleteAcceptedSharedZones(ownerIDs: [oldPartnerID])
            }
            try await cloudKit.removeOutgoingShareParticipants(keeping: pending.incomingOwnerID)
            try await cloudKit.purgeExPartnerRecordsFromPrivateZone(currentMemberID: settings.currentMemberID)
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
                try await cloudKit.purgeExPartnerRecordsFromPrivateZone(currentMemberID: settings.currentMemberID)
                try ShareCalLocalDataCleanupService.purgeSharedOwnerData(
                    ownerMemberIDs: ICloudSharingTeardownPolicy.localOwnerIDsToPurge(partnerShareOwnerID: previousPartnerID),
                    modelContext: modelContext
                )
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
        ExistingICloudDataRecoveryPolicy.shouldDeferAutomaticSync(
            hasResolvedPrompt: settings.hasResolvedExistingICloudDataPrompt,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
            lastSyncAt: settings.lastSyncAt
        )
    }


    private func presentInitialProfilePromptIfNeeded() {
        guard activeRootSheet == nil else { return }
        if PairingSettingsPolicy.normalizedDisplayName(settings.currentDisplayName) != nil {
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
        guard PairingSafetyEducationPolicy.shouldPresentNotice(
            pairingStatus: pairingStatus,
            hasPromptedPartnerNoteForCurrentPairing: settings.hasPromptedPartnerNoteForCurrentPairing,
            hasShownPairingSafetyNoticeForCurrentPairing: settings.hasShownPairingSafetyNoticeForCurrentPairing
        ) else { return }
        activeRootSheet = .pairingSafetyNotice
    }

    private func presentShareBackPromptIfNeeded() {
        guard activeRootSheet == nil else { return }
        // Smoke runs drive both simulators by launch arguments; keep the sheet off them.
        guard ShareCalLaunchDiagnosticPolicy.seedProfileName() == nil else { return }
        guard PairingGuidePolicy.shouldPresentShareBackPrompt(
            status: pairingStatus,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            sentInviteBackToOwnerID: settings.sentInviteBackToOwnerID,
            shareBackPromptShownForOwnerID: settings.shareBackPromptShownForOwnerID
        ) else { return }
        activeRootSheet = .shareBackPrompt
    }

    @MainActor
    private func presentExistingICloudDataPromptIfNeeded() async {
        guard activeRootSheet == nil else { return }
        guard !settings.hasResolvedExistingICloudDataPrompt else {
            hasEvaluatedExistingICloudDataPrompt = true
            return
        }

        let shouldProbe = ExistingICloudDataRecoveryPolicy.shouldDeferAutomaticSync(
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
        if ExistingICloudDataRecoveryPolicy.shouldPresent(
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
        presentShareBackPromptIfNeeded()
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
        guard ForegroundSyncPolicy.shouldRunAutomaticSync(
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
        // Own task, like `SyncCoordinator.syncIfIdle`: the root `.task` that can start
        // this must not cancel a sync that is already talking to CloudKit.
        await Task {
            await coordinator.foregroundSync(
                modelContext: modelContext,
                settings: settings,
                forceCloudKit: consumingAcceptedShareSignal || forceCloudKit
            )
        }.value
        representPairingConflictIfNeeded()
        return true
    }

    @MainActor
    private func continueUsingExistingICloudData() async throws {
        settings.lastSyncError = nil
        settings.iCloudSharingEnabled = true
        if let cloudKit = services.cloudKitIfAvailable {
            await ExistingICloudDataIdentityRecovery.restore(cloudKit: cloudKit, settings: settings)
        }
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
