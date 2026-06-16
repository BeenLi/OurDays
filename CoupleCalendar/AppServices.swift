import BackgroundTasks
import Foundation
import Observation
import OSLog
import SwiftData
import UserNotifications

private let syncLogger = Logger(
    subsystem: "com.leeberty.CoupleCalendar",
    category: "Sync"
)

private func syncInfo(_ message: String) {
    #if DEBUG
    print("[Sync] \(message)")
    #endif
    syncLogger.info("\(message, privacy: .public)")
}

private struct SyncTimingLog {
    private let startedAt = Date()
    private var previousMark = Date()

    mutating func mark(_ label: String) {
        let now = Date()
        let stepDuration = now.timeIntervalSince(previousMark)
        let totalDuration = now.timeIntervalSince(startedAt)
        previousMark = now
        syncInfo(
            String(
                format: "foregroundSync %@ step=%.3fs total=%.3fs",
                label,
                stepDuration,
                totalDuration
            )
        )
    }
}

@Observable
final class SettingsStore {
    /// Placeholder member ID used until the CloudKit userRecordID is known
    /// (and permanently in LOCAL_SIGNING builds without CloudKit).
    static let unsyncedMemberID = "local-user"
    /// Placeholder owner ID for partner-owned local records created before the
    /// partner's CloudKit identity is known.
    static let unknownPartnerID = "partner"

    var currentMemberID: String {
        didSet { defaults.set(currentMemberID, forKey: Key.currentMemberID) }
    }
    var currentDisplayName: String {
        didSet { defaults.set(currentDisplayName, forKey: Key.currentDisplayName) }
    }
    var currentICloudEmailAddress: String {
        didSet { defaults.set(currentICloudEmailAddress, forKey: Key.currentICloudEmailAddress) }
    }
    var partnerNoteName: String {
        didSet { defaults.set(partnerNoteName, forKey: Key.partnerNoteName) }
    }
    var partnerShareOwnerID: String? {
        didSet { saveOptionalString(partnerShareOwnerID, forKey: Key.partnerShareOwnerID) }
    }
    var partnerSyncedDisplayName: String? {
        didSet { saveOptionalString(partnerSyncedDisplayName, forKey: Key.partnerSyncedDisplayName) }
    }
    var hasCompletedInitialProfilePrompt: Bool {
        didSet { defaults.set(hasCompletedInitialProfilePrompt, forKey: Key.hasCompletedInitialProfilePrompt) }
    }
    var hasPromptedPartnerNoteForCurrentPairing: Bool {
        didSet { defaults.set(hasPromptedPartnerNoteForCurrentPairing, forKey: Key.hasPromptedPartnerNoteForCurrentPairing) }
    }
    var hasShownPairingSafetyNoticeForCurrentPairing: Bool {
        didSet { defaults.set(hasShownPairingSafetyNoticeForCurrentPairing, forKey: Key.hasShownPairingSafetyNoticeForCurrentPairing) }
    }
    var hasResolvedExistingICloudDataPrompt: Bool {
        didSet { defaults.set(hasResolvedExistingICloudDataPrompt, forKey: Key.hasResolvedExistingICloudDataPrompt) }
    }
    var outgoingShareParticipantIDs: [String] {
        didSet { defaults.set(outgoingShareParticipantIDs, forKey: Key.outgoingShareParticipantIDs) }
    }
    var pairingConflict: TwoPersonPairingConflict? {
        didSet { savePairingConflict() }
    }
    var iCloudSharingEnabled: Bool {
        didSet { defaults.set(iCloudSharingEnabled, forKey: Key.iCloudSharingEnabled) }
    }
    var hasStartedPairing: Bool {
        didSet { defaults.set(hasStartedPairing, forKey: Key.hasStartedPairing) }
    }
    var pairingDate: Date? {
        didSet { saveOptionalDate(pairingDate, forKey: Key.pairingDate) }
    }
    var selectedCalendarIDs: Set<String> {
        didSet { saveSelectedCalendarIDs() }
    }
    var defaultVisibility: EventVisibility {
        didSet { defaults.set(defaultVisibility.rawValue, forKey: Key.defaultVisibility) }
    }
    var appLanguage: AppLanguage {
        didSet { AppLanguagePreference.write(appLanguage, to: defaults) }
    }
    var lastSyncAt: Date? {
        didSet { defaults.set(lastSyncAt, forKey: Key.lastSyncAt) }
    }
    /// Local, per-device marker for when the user last viewed the 动态 (activity) tab.
    /// Drives the unread comment count. Deliberately NOT synced (unlike EventComment.isRead).
    var lastSeenActivityAt: Date? {
        didSet { defaults.set(lastSeenActivityAt, forKey: Key.lastSeenActivityAt) }
    }
    /// Local high-water mark for the last time local notifications were evaluated, so
    /// the same partner activity is never notified twice. Nil until the first sync.
    var lastNotifiedAt: Date? {
        didSet { defaults.set(lastNotifiedAt, forKey: Key.lastNotifiedAt) }
    }
    var lastSyncError: String?
    var syncPhase: SyncPhase = .idle

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.resetLegacyPairingStateIfNeeded(defaults: defaults)
        currentMemberID = Self.normalizedString(defaults.string(forKey: Key.currentMemberID)) ?? Self.unsyncedMemberID
        let resolvedCurrentDisplayName = Self.normalizedString(defaults.string(forKey: Key.currentDisplayName)) ?? ""
        currentDisplayName = resolvedCurrentDisplayName
        currentICloudEmailAddress = defaults.string(forKey: Key.currentICloudEmailAddress) ?? ""
        partnerNoteName = Self.normalizedString(defaults.string(forKey: Key.partnerNoteName)) ?? ""
        partnerShareOwnerID = defaults.string(forKey: Key.partnerShareOwnerID)
        partnerSyncedDisplayName = Self.normalizedString(defaults.string(forKey: Key.partnerSyncedDisplayName))
        let storedHasCompletedInitialProfilePrompt = defaults.object(forKey: Key.hasCompletedInitialProfilePrompt) as? Bool ?? false
        if storedHasCompletedInitialProfilePrompt,
           Self.normalizedString(resolvedCurrentDisplayName) == nil {
            hasCompletedInitialProfilePrompt = false
            defaults.set(false, forKey: Key.hasCompletedInitialProfilePrompt)
        } else {
            hasCompletedInitialProfilePrompt = storedHasCompletedInitialProfilePrompt
        }
        hasPromptedPartnerNoteForCurrentPairing = defaults.object(forKey: Key.hasPromptedPartnerNoteForCurrentPairing) as? Bool ?? false
        hasShownPairingSafetyNoticeForCurrentPairing = defaults.object(forKey: Key.hasShownPairingSafetyNoticeForCurrentPairing) as? Bool ?? false
        hasResolvedExistingICloudDataPrompt = defaults.object(forKey: Key.hasResolvedExistingICloudDataPrompt) as? Bool ?? false
        outgoingShareParticipantIDs = defaults.stringArray(forKey: Key.outgoingShareParticipantIDs) ?? []
        pairingConflict = (defaults.data(forKey: Key.pairingConflict)).flatMap {
            try? JSONDecoder().decode(TwoPersonPairingConflict.self, from: $0)
        }
        iCloudSharingEnabled = defaults.object(forKey: Key.iCloudSharingEnabled) as? Bool ?? true
        hasStartedPairing = defaults.object(forKey: Key.hasStartedPairing) as? Bool ?? false
        pairingDate = defaults.object(forKey: Key.pairingDate) as? Date
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendarIDs) ?? [])
        defaultVisibility = EventVisibility(rawValue: defaults.string(forKey: Key.defaultVisibility) ?? "") ?? .fullDetails
        appLanguage = AppLanguagePreference.read(from: defaults)
        lastSyncAt = defaults.object(forKey: Key.lastSyncAt) as? Date
        lastSeenActivityAt = defaults.object(forKey: Key.lastSeenActivityAt) as? Date
        lastNotifiedAt = defaults.object(forKey: Key.lastNotifiedAt) as? Date
    }

    var hasSyncedMemberID: Bool {
        currentMemberID != Self.unsyncedMemberID
    }

    /// One-time reset for pre-userRecordID installs: the legacy local-owner-UUID
    /// identity cannot be mapped onto the CloudKit identity, so pairing state is
    /// wiped and the user re-pairs. Non-pairing preferences are preserved.
    private static func resetLegacyPairingStateIfNeeded(defaults: UserDefaults) {
        guard defaults.string(forKey: LegacyKey.localOwnerID) != nil else { return }
        for key in LegacyKey.allRemovedKeys {
            defaults.removeObject(forKey: key)
        }
        for key in [
            Key.partnerShareOwnerID,
            Key.partnerSyncedDisplayName,
            Key.partnerNoteName,
            Key.outgoingShareParticipantIDs,
            Key.hasStartedPairing,
            Key.pairingDate,
            Key.hasPromptedPartnerNoteForCurrentPairing,
            Key.hasShownPairingSafetyNoticeForCurrentPairing,
            Key.hasResolvedExistingICloudDataPrompt,
            Key.lastSyncAt
        ] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: LegacyKey.needsLocalDataPurge)
    }

    func consumeLegacyLocalDataPurgeFlag() -> Bool {
        guard defaults.bool(forKey: LegacyKey.needsLocalDataPurge) else { return false }
        defaults.removeObject(forKey: LegacyKey.needsLocalDataPurge)
        return true
    }

    static func storedPartnerShareOwnerID(defaults: UserDefaults = .standard) -> String? {
        normalizedString(defaults.string(forKey: Key.partnerShareOwnerID))
    }

    static func storedOutgoingShareParticipantIDs(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: Key.outgoingShareParticipantIDs) ?? []
    }

    func toggleCalendarSelection(_ calendarID: String, isSelected: Bool) {
        if isSelected {
            selectedCalendarIDs.insert(calendarID)
        } else {
            selectedCalendarIDs.remove(calendarID)
        }
    }

    private func saveSelectedCalendarIDs() {
        defaults.set(Array(selectedCalendarIDs).sorted(), forKey: Key.selectedCalendarIDs)
    }

    private func saveOptionalString(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func markPairingDateIfNeeded(at date: Date = .now, calendar: Calendar = .current) {
        guard pairingDate == nil else { return }
        pairingDate = PairingDatePlan.normalizedPairingDate(date, calendar: calendar)
    }

    func clearPairingDate() {
        pairingDate = nil
    }

    private func savePairingConflict() {
        if let pairingConflict, let data = try? JSONEncoder().encode(pairingConflict) {
            defaults.set(data, forKey: Key.pairingConflict)
        } else {
            defaults.removeObject(forKey: Key.pairingConflict)
        }
    }

    private func saveOptionalDate(_ value: Date?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func normalizedID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private enum Key {
        static let currentMemberID = "currentMemberID"
        static let currentDisplayName = "currentDisplayName"
        static let currentICloudEmailAddress = "currentICloudEmailAddress"
        static let partnerNoteName = "partnerNoteName"
        static let partnerShareOwnerID = "partnerShareOwnerID"
        static let partnerSyncedDisplayName = "partnerSyncedDisplayName"
        static let hasCompletedInitialProfilePrompt = "hasCompletedInitialProfilePrompt"
        static let hasPromptedPartnerNoteForCurrentPairing = "hasPromptedPartnerNoteForCurrentPairing"
        static let hasShownPairingSafetyNoticeForCurrentPairing = "hasShownPairingSafetyNoticeForCurrentPairing"
        static let hasResolvedExistingICloudDataPrompt = "hasResolvedExistingICloudDataPrompt"
        static let outgoingShareParticipantIDs = "outgoingShareParticipantIDs"
        static let pairingConflict = "pairingConflict"
        static let iCloudSharingEnabled = "iCloudSharingEnabled"
        static let hasStartedPairing = "hasStartedPairing"
        static let pairingDate = "pairingDate"
        static let selectedCalendarIDs = "selectedCalendarIDs"
        static let defaultVisibility = "defaultVisibility"
        static let lastSyncAt = "lastSyncAt"
        static let lastSeenActivityAt = "lastSeenActivityAt"
        static let lastNotifiedAt = "lastNotifiedAt"
    }

    private enum LegacyKey {
        static let localOwnerID = "currentLocalOwnerID"
        static let needsLocalDataPurge = "needsLegacyLocalDataPurge"
        static let allRemovedKeys = [
            localOwnerID,
            "pairingID",
            "partnerICloudEmailAddresses",
            "inactiveSharedOwnerIDs",
            "ShareCalPendingAcceptedPartnerICloudEmailAddress"
        ]
    }
}

extension SettingsStore {
    var strings: ShareCalStrings {
        ShareCalStrings(language: appLanguage)
    }

    var partnerDisplayName: String {
        PairingSettingsPlan.partnerDisplayName(
            partnerNoteName: partnerNoteName,
            partnerSyncedDisplayName: partnerSyncedDisplayName,
            fallback: strings.partnerTitle
        )
    }

    var partnerStatusDisplayName: String {
        PairingSettingsPlan.partnerStatusDisplayName(
            partnerNoteName: partnerNoteName,
            partnerSyncedDisplayName: partnerSyncedDisplayName,
            fallback: strings.partnerTitle,
            language: appLanguage
        )
    }

    var partnerOwnerIDForLocalData: String {
        partnerShareOwnerID ?? Self.unknownPartnerID
    }
}

@Observable
final class AppServices {
    let calendarAccess: CalendarAccessService
    let eventMirrorService: EventMirrorService
    let invitationService: InvitationService
    let commentService: CommentService
    @ObservationIgnored private var cloudKitStorage: CloudKitCoupleSpaceService?

    var cloudKit: CloudKitCoupleSpaceService {
        if let cloudKitStorage {
            return cloudKitStorage
        }

        let service = CloudKitCoupleSpaceService()
        cloudKitStorage = service
        return service
    }

    var cloudKitIfAvailable: CloudKitCoupleSpaceService? {
        guard isCloudKitEnabled else { return nil }
        return cloudKit
    }

    var isCloudKitEnabled: Bool {
        #if LOCAL_SIGNING
        false
        #else
        true
        #endif
    }

    init(
        calendarAccess: CalendarAccessService = CalendarAccessService(),
        eventMirrorService: EventMirrorService = EventMirrorService(),
        cloudKit: CloudKitCoupleSpaceService? = nil,
        invitationService: InvitationService = InvitationService(),
        commentService: CommentService = CommentService()
    ) {
        self.calendarAccess = calendarAccess
        self.eventMirrorService = eventMirrorService
        self.cloudKitStorage = cloudKit
        self.invitationService = invitationService
        self.commentService = commentService
    }
}

/// Posts user-facing local notifications. Abstracted so the (untestable) UNUserNotificationCenter
/// side effects stay out of SyncCoordinator's decision flow.
@MainActor
protocol LocalNotificationScheduling {
    func post(_ notifications: [PlannedLocalNotification], strings: ShareCalStrings, partnerName: String) async
}

@MainActor
struct UserNotificationScheduler: LocalNotificationScheduling {
    func post(_ notifications: [PlannedLocalNotification], strings: ShareCalStrings, partnerName: String) async {
        guard !notifications.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        for planned in notifications {
            let content = UNMutableNotificationContent()
            let text = LocalNotificationContentPlan.content(
                for: planned.kind,
                strings: strings,
                partnerName: partnerName
            )
            content.title = text.title
            content.body = text.body
            content.sound = .default
            // Reuse the stable id as the request identifier so the same underlying
            // event is coalesced rather than duplicated across syncs.
            let request = UNNotificationRequest(
                identifier: planned.id,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}

@MainActor
struct SyncCoordinator {
    let calendarAccess: CalendarAccessService
    let eventMirrorService: EventMirrorService
    let cloudKit: CloudKitCoupleSpaceService?
    var notificationScheduler: LocalNotificationScheduling = UserNotificationScheduler()

    func foregroundSync(
        modelContext: ModelContext,
        settings: SettingsStore,
        forceCloudKit: Bool = false
    ) async {
        settings.syncPhase = .syncing
        settings.lastSyncError = nil
        var timing = SyncTimingLog()
        syncInfo("foregroundSync begin")

        do {
            let syncedAt = Date()
            var shouldRunCloudKit = CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: settings.iCloudSharingEnabled,
                hasStartedPairing: settings.hasStartedPairing,
                partnerShareOwnerID: settings.partnerShareOwnerID,
                outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
                forceCloudKit: forceCloudKit
            )
            // The member ID must be the CloudKit userRecordID before any mirrors
            // are generated or uploaded; without it, cloud sync cannot run.
            if shouldRunCloudKit, let cloudKit, !settings.hasSyncedMemberID {
                do {
                    settings.currentMemberID = try await cloudKit.fetchCurrentUserRecordID()
                    timing.mark("memberIDFetched")
                } catch {
                    settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                    shouldRunCloudKit = false
                    timing.mark("memberIDFetchFailed")
                }
            }
            if settings.selectedCalendarIDs.isEmpty {
                let calendar = try calendarAccess.ensureShareCalCalendar()
                settings.selectedCalendarIDs = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
                    afterEnsuring: calendar,
                    currentSelection: settings.selectedCalendarIDs
                )
            }
            timing.mark("calendarSelectionReady selected=\(settings.selectedCalendarIDs.count)")

            let localAccessRequests = try modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())
            if settings.hasStartedPairing || settings.partnerShareOwnerID != nil || !settings.outgoingShareParticipantIDs.isEmpty {
                settings.markPairingDateIfNeeded(at: syncedAt)
            }
            let pairingDate = settings.pairingDate ?? PairingDatePlan.normalizedPairingDate(syncedAt)
            let sharingWindows = CalendarSharingWindowPlan.effectiveWindows(
                now: pairingDate,
                accessRequests: localAccessRequests
            )
            let window = CalendarSharingWindowPlan.enclosingInterval(for: sharingWindows)
            let sourceEvents = calendarAccess.events(
                from: window.start,
                to: window.end,
                selectedCalendarIDs: settings.selectedCalendarIDs
            )
            timing.mark("localEventsFetched count=\(sourceEvents.count)")
            let mirrors = eventMirrorService.makeMirrors(
                from: sourceEvents,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                ownerMemberID: settings.currentMemberID,
                visibility: settings.defaultVisibility,
                sharingWindows: sharingWindows
            )
            // Shadows are recorded without an upload stamp; the stamp is set
            // only after CloudKit writes succeed, so events synced before
            // pairing still upload once a partner exists.
            let activeShadows = eventMirrorService.makeShadows(
                from: sourceEvents,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                uploadedAt: nil,
                sharingWindows: sharingWindows
            )
            let currentMirrorKeys = Set(mirrors.map(\.mirrorKey))
            let existingShadows = try modelContext.fetch(FetchDescriptor<LocalEventShadow>())
            let existingLocalMirrors = try localMirrors(
                ownerMemberID: settings.currentMemberID,
                modelContext: modelContext
            )
            timing.mark(
                "localStateLoaded accessRequests=\(localAccessRequests.count) shadows=\(existingShadows.count) mirrors=\(existingLocalMirrors.count)"
            )
            let hardDeletedMirrors = eventMirrorService.mirrorsOutsideSharingWindows(
                existingLocalMirrors,
                sharingWindows: sharingWindows
            )
            let hardDeletedMirrorKeys = Set(hardDeletedMirrors.map(\.mirrorKey))
            let retainedLocalMirrors = existingLocalMirrors.filter { !hardDeletedMirrorKeys.contains($0.mirrorKey) }
            let retainedShadows = existingShadows.filter { !hardDeletedMirrorKeys.contains($0.mirrorKey) }
            let deletedShadows = eventMirrorService.deletedShadows(
                existingEventKeys: currentMirrorKeys,
                shadows: retainedShadows,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                syncWindow: window
            )
            let deletedMirrorsFromShadows = eventMirrorService.deletedMirrorTombstones(
                for: deletedShadows,
                existingMirrors: retainedLocalMirrors,
                deletedAt: syncedAt
            )
            let deletedMirrorsFromExistingLocalState = eventMirrorService.deletedMirrorTombstones(
                existingEventKeys: currentMirrorKeys,
                existingMirrors: retainedLocalMirrors,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                syncWindow: window,
                deletedAt: syncedAt
            )
            var deletedMirrorByKey: [String: EventMirror] = [:]
            for mirror in deletedMirrorsFromShadows + deletedMirrorsFromExistingLocalState {
                deletedMirrorByKey[mirror.mirrorKey] = mirror
            }
            let deletedMirrors = deletedMirrorByKey.keys.sorted().compactMap { deletedMirrorByKey[$0] }
            let mirrorsForSync = mirrors + deletedMirrors
            let mirrorsNeedingCloudUpload = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
                mirrorsForSync,
                activeShadows: activeShadows,
                existingShadows: existingShadows,
                existingLocalMirrors: existingLocalMirrors
            )
            syncInfo(
                "foregroundSync mirror upload candidates total=\(mirrorsForSync.count) changed=\(mirrorsNeedingCloudUpload.count) hardDeletes=\(hardDeletedMirrors.count)"
            )

            try upsert(mirrors: mirrorsForSync, modelContext: modelContext)
            try upsert(shadows: activeShadows + deletedShadows, modelContext: modelContext)
            timing.mark("localMirrorsUpserted mirrors=\(mirrorsForSync.count) shadows=\(activeShadows.count + deletedShadows.count)")
            let localInvitations = try modelContext.fetch(FetchDescriptor<EventInvitation>())
            let canceledInvitations = InvitationLocalEventSyncPlan.cancelAcceptedInvitationsMissingLocalEvents(
                localInvitations,
                now: syncedAt,
                localEventExists: { invitation in
                    calendarAccess.localEventExists(for: invitation)
                }
            )
            if !canceledInvitations.isEmpty {
                try modelContext.save()
            }
            if shouldRunCloudKit {
                guard let cloudKit else {
                    settings.lastSyncError = settings.strings.cloudKitSyncDisabledLocalBuild
                    try purge(mirrors: hardDeletedMirrors, modelContext: modelContext)
                    try purgeShadows(mirrorKeys: hardDeletedMirrorKeys, modelContext: modelContext)
                    settings.lastSyncAt = .now
                    settings.syncPhase = .idle
                    timing.mark("finishedWithoutCloudKit")
                    return
                }

                // Resolve who the partner is BEFORE any cloud write: while a
                // pairing conflict is unresolved (e.g. a stranger joined the
                // share), nothing may be uploaded to the still-readable share.
                async let outgoingParticipantIDsTask = cloudKit.fetchOutgoingShareParticipantIDs(
                    ownerMemberID: settings.currentMemberID,
                    lockingForPartnerID: settings.partnerShareOwnerID
                )
                async let sharedZoneIDsTask = cloudKit.fetchSharedCoupleSpaceZoneIDs()
                let outgoingParticipantIDs = try await outgoingParticipantIDsTask
                settings.outgoingShareParticipantIDs = outgoingParticipantIDs
                timing.mark("cloudOutgoingParticipantsFetched count=\(outgoingParticipantIDs.count)")
                let fetchedSharedZoneIDs = try await sharedZoneIDsTask
                timing.mark("cloudSharedZonesFetched count=\(fetchedSharedZoneIDs.count)")

                let resolution = TwoPersonPairingPlan.resolve(
                    storedPartnerID: settings.partnerShareOwnerID,
                    outgoingAcceptedParticipantIDs: outgoingParticipantIDs,
                    sharedZoneOwnerIDs: fetchedSharedZoneIDs.map(\.ownerName)
                )
                settings.pairingConflict = resolution.conflict
                if resolution.conflict != nil {
                    // Do not upload, import, or clean up anything until the user
                    // picks a partner; otherwise we could expose fresh data to a
                    // participant who is about to be rejected, or mix two
                    // people's data.
                    timing.mark("cloudPairingConflictDetected")
                    settings.lastSyncAt = .now
                    settings.syncPhase = .idle
                    try purge(mirrors: hardDeletedMirrors, modelContext: modelContext)
                    try purgeShadows(mirrorKeys: hardDeletedMirrorKeys, modelContext: modelContext)
                    return
                }

                let accessRequestsNeedingCloudUpload = CalendarAccessRequestCloudUploadPlan.requestsNeedingUpload(
                    localAccessRequests,
                    currentMemberID: settings.currentMemberID
                )
                let hasCloudWrites = !mirrorsNeedingCloudUpload.isEmpty
                    || !hardDeletedMirrors.isEmpty
                    || !canceledInvitations.isEmpty
                    || !accessRequestsNeedingCloudUpload.isEmpty
                let shouldUpdateShareRootMetadata = settings.hasStartedPairing
                    || settings.partnerShareOwnerID != nil
                    || !settings.outgoingShareParticipantIDs.isEmpty
                if hasCloudWrites || shouldUpdateShareRootMetadata {
                    try await cloudKit.ensureShareRoot(ownerMemberID: settings.currentMemberID)
                    timing.mark("cloudShareRootReady")
                    if shouldUpdateShareRootMetadata {
                        try await saveCurrentMemberProfileIfPossible(
                            cloudKit: cloudKit,
                            settings: settings
                        )
                        timing.mark("cloudMemberProfileChecked")
                    }
                    if hasCloudWrites {
                        try await cloudKit.saveMirrorsForSync(mirrorsNeedingCloudUpload)
                        try upsert(mirrors: mirrorsNeedingCloudUpload, modelContext: modelContext)
                        timing.mark("cloudMirrorsSaved count=\(mirrorsNeedingCloudUpload.count)")
                        try await cloudKit.deleteMirrorsForSync(hardDeletedMirrors)
                        timing.mark("cloudHardDeletesSaved count=\(hardDeletedMirrors.count)")
                        // CloudKit accepted the mirror writes — only now mark
                        // the shadows as uploaded.
                        for shadow in activeShadows + deletedShadows {
                            shadow.lastUploadedAt = syncedAt
                        }
                        try upsert(shadows: activeShadows + deletedShadows, modelContext: modelContext)
                        for invitation in canceledInvitations {
                            try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                        }
                        timing.mark("cloudCanceledInvitationsSaved count=\(canceledInvitations.count)")
                        for request in accessRequestsNeedingCloudUpload {
                            try await cloudKit.saveCalendarAccessRequestForSync(
                                request,
                                currentMemberID: settings.currentMemberID
                            )
                        }
                        timing.mark("cloudAccessRequestsSaved count=\(accessRequestsNeedingCloudUpload.count)")
                    }
                } else {
                    timing.mark("cloudWritesSkipped")
                }

                try await cloudKit.foregroundSync()
                timing.mark("cloudSyncEngineFinished")

                if !resolution.sharedZoneOwnerIDsToLeave.isEmpty {
                    try await cloudKit.deleteAcceptedSharedZones(ownerIDs: resolution.sharedZoneOwnerIDsToLeave)
                    try ShareCalLocalDataCleanupService.purgeSharedOwnerData(
                        ownerMemberIDs: Set(resolution.sharedZoneOwnerIDsToLeave),
                        modelContext: modelContext
                    )
                    timing.mark("cloudStaleSharedZonesLeft count=\(resolution.sharedZoneOwnerIDsToLeave.count)")
                }
                let activeSharedZoneIDs = fetchedSharedZoneIDs.filter { $0.ownerName == resolution.partnerID }
                timing.mark("cloudActiveSharedZones selected=\(activeSharedZoneIDs.count)")

                async let accessRequestsTask = cloudKit.fetchCalendarAccessRequests(sharedZoneIDs: activeSharedZoneIDs)
                async let sharedMirrorsTask = cloudKit.fetchSharedEventMirrors(sharedZoneIDs: activeSharedZoneIDs)
                async let commentsTask = cloudKit.fetchEventComments(sharedZoneIDs: activeSharedZoneIDs)
                async let invitationsTask = cloudKit.fetchEventInvitations(sharedZoneIDs: activeSharedZoneIDs)
                async let memberProfilesTask = cloudKit.fetchMemberProfiles(sharedZoneIDs: activeSharedZoneIDs)

                let cloudAccessRequests = try await accessRequestsTask
                try upsert(accessRequests: cloudAccessRequests, modelContext: modelContext)
                timing.mark("cloudAccessRequestsFetched count=\(cloudAccessRequests.count)")
                let previousPartnerShareOwnerID = settings.partnerShareOwnerID
                let partnerShareOwnerID = resolution.partnerID
                settings.partnerShareOwnerID = partnerShareOwnerID
                if partnerShareOwnerID != nil || !settings.outgoingShareParticipantIDs.isEmpty {
                    settings.hasStartedPairing = true
                    settings.markPairingDateIfNeeded(at: syncedAt)
                }
                let memberProfiles = try await memberProfilesTask
                settings.partnerSyncedDisplayName = MemberProfileDisplayPlan.partnerSyncedDisplayName(
                    from: memberProfiles,
                    partnerID: partnerShareOwnerID
                )
                let sharedMirrors = try await sharedMirrorsTask
                let importableSharedMirrors = CloudKitSharedDatabaseImportPlan.importableMirrors(
                    sharedMirrors,
                    currentMemberID: settings.currentMemberID
                )
                timing.mark("cloudSharedMirrorsFetched count=\(sharedMirrors.count) importable=\(importableSharedMirrors.count)")
                let ownerIDsToPurge = Set([previousPartnerShareOwnerID, partnerShareOwnerID].compactMap { $0 })
                for ownerID in ownerIDsToPurge {
                    try purgeStalePartnerMirrors(
                        importedMirrors: ownerID == partnerShareOwnerID ? importableSharedMirrors : [],
                        partnerShareOwnerID: ownerID,
                        modelContext: modelContext
                    )
                }
                try upsert(mirrors: importableSharedMirrors, modelContext: modelContext)
                let cloudComments = try await commentsTask
                try upsert(comments: cloudComments, modelContext: modelContext)
                timing.mark("cloudCommentsFetched count=\(cloudComments.count)")
                let cloudInvitations = try await invitationsTask
                try upsert(invitations: cloudInvitations, modelContext: modelContext)
                timing.mark("cloudInvitationsFetched count=\(cloudInvitations.count)")

                // Reliability for terminal decisions made in a tab (fire-and-forget
                // upload): re-upload any local decision the just-fetched server copy
                // hasn't caught up to, so a failed/missed one-shot upload self-heals on
                // a later sync rather than being made permanent by the merge guard.
                // Compares against post-import local state; self-limiting once the
                // server agrees. See decision 0003.
                let localRequestsForReupload = try modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())
                let requestsToReupload = CalendarAccessRequestReuploadPlan.ownerDecisionsNeedingReupload(
                    local: localRequestsForReupload,
                    cloud: cloudAccessRequests,
                    currentMemberID: settings.currentMemberID
                )
                for request in requestsToReupload {
                    try await cloudKit.saveCalendarAccessRequestForSync(request, currentMemberID: settings.currentMemberID)
                }
                timing.mark("cloudAccessRequestDecisionsReuploaded count=\(requestsToReupload.count)")

                let localInvitationsForReupload = try modelContext.fetch(FetchDescriptor<EventInvitation>())
                let invitationsToReupload = InvitationReuploadPlan.responsesNeedingReupload(
                    local: localInvitationsForReupload,
                    cloud: cloudInvitations,
                    currentMemberID: settings.currentMemberID
                )
                for invitation in invitationsToReupload {
                    try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                }
                timing.mark("cloudInvitationResponsesReuploaded count=\(invitationsToReupload.count)")
            } else if !settings.iCloudSharingEnabled {
                settings.partnerShareOwnerID = nil
                settings.partnerSyncedDisplayName = nil
                settings.outgoingShareParticipantIDs = []
                settings.pairingConflict = nil
                settings.hasStartedPairing = false
            } else {
                timing.mark("cloudSyncSkippedUnpaired")
            }
            try purge(mirrors: hardDeletedMirrors, modelContext: modelContext)
            try purgeShadows(mirrorKeys: hardDeletedMirrorKeys, modelContext: modelContext)

            await postPendingNotifications(modelContext: modelContext, settings: settings, syncedAt: syncedAt)
            settings.lastSyncAt = .now
            settings.syncPhase = .idle
            timing.mark("finished")
        } catch {
            settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            settings.syncPhase = .failed
            timing.mark("failed")
        }
    }

    /// After a sync imports the partner's latest data, surface anything new since the
    /// last check as system notifications, then advance the high-water mark. Runs only
    /// once a baseline exists (first sync just sets the baseline — see LocalNotificationPlan).
    private func postPendingNotifications(
        modelContext: ModelContext,
        settings: SettingsStore,
        syncedAt: Date
    ) async {
        let planned: [PlannedLocalNotification]
        do {
            let comments = try modelContext.fetch(FetchDescriptor<EventComment>())
            let mirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
            let invitations = try modelContext.fetch(FetchDescriptor<EventInvitation>())
            let accessRequests = try modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())
            planned = LocalNotificationPlan.pending(
                comments: comments,
                mirrors: mirrors,
                invitations: invitations,
                accessRequests: accessRequests,
                currentMemberID: settings.currentMemberID,
                since: settings.lastNotifiedAt
            )
        } catch {
            // Notifications are best-effort; never let them fail a sync.
            settings.lastNotifiedAt = syncedAt
            return
        }
        if !planned.isEmpty {
            await notificationScheduler.post(
                planned,
                strings: settings.strings,
                partnerName: settings.partnerStatusDisplayName
            )
        }
        settings.lastNotifiedAt = syncedAt
    }

    private func localMirrors(ownerMemberID: String, modelContext: ModelContext) throws -> [EventMirror] {
        let descriptor = FetchDescriptor<EventMirror>(
            predicate: #Predicate { $0.ownerMemberID == ownerMemberID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func saveCurrentMemberProfileIfPossible(
        cloudKit: CloudKitCoupleSpaceService,
        settings: SettingsStore
    ) async throws {
        guard let displayName = PairingSettingsPlan.normalizedDisplayName(settings.currentDisplayName) else {
            return
        }
        try await cloudKit.saveMemberProfileForSync(
            ownerMemberID: settings.currentMemberID,
            displayName: displayName
        )
    }

    private func upsert(mirrors: [EventMirror], modelContext: ModelContext) throws {
        for mirror in mirrors {
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
        try modelContext.save()
    }

    private func upsert(shadows: [LocalEventShadow], modelContext: ModelContext) throws {
        for shadow in shadows {
            let shadowID = shadow.id
            let descriptor = FetchDescriptor<LocalEventShadow>(
                predicate: #Predicate { $0.id == shadowID }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.localEventIdentifier = shadow.localEventIdentifier
                existing.calendarIdentifier = shadow.calendarIdentifier
                existing.occurrenceStartDate = shadow.occurrenceStartDate
                existing.fingerprint = shadow.fingerprint
                existing.cloudKitRecordName = shadow.cloudKitRecordName
                // nil means "upload not confirmed this sync" — never erase a
                // previous confirmation with it.
                existing.lastUploadedAt = shadow.lastUploadedAt ?? existing.lastUploadedAt
                existing.isTombstone = shadow.isTombstone
            } else {
                modelContext.insert(shadow)
            }
        }
        try modelContext.save()
    }

    private func upsert(comments: [EventComment], modelContext: ModelContext) throws {
        for comment in comments {
            let commentID = comment.id
            let descriptor = FetchDescriptor<EventComment>(
                predicate: #Predicate { $0.id == commentID }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.eventMirrorID = comment.eventMirrorID
                existing.authorMemberID = comment.authorMemberID
                existing.body = comment.body
                existing.createdAt = comment.createdAt
                existing.editedAt = comment.editedAt
                existing.deletedAt = comment.deletedAt
                existing.isRead = comment.isRead
                existing.cloudKitRecordName = comment.cloudKitRecordName
            } else {
                modelContext.insert(comment)
            }
        }
        try modelContext.save()
    }

    private func upsert(invitations: [EventInvitation], modelContext: ModelContext) throws {
        for invitation in invitations {
            let invitationID = invitation.id
            let descriptor = FetchDescriptor<EventInvitation>(
                predicate: #Predicate { $0.id == invitationID }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                // Same status-aware guard as access requests: never let a stale `pending`
                // server copy roll back a local accept/decline whose upload is still in
                // flight. See InvitationImportMergePlan / decision 0003.
                guard InvitationImportMergePlan.shouldApplyIncoming(
                    existingStatus: existing.status,
                    existingUpdatedAt: existing.updatedAt,
                    incomingStatus: invitation.status,
                    incomingUpdatedAt: invitation.updatedAt
                ) else { continue }
                existing.creatorMemberID = invitation.creatorMemberID
                existing.inviteeMemberID = invitation.inviteeMemberID
                existing.title = invitation.title
                existing.startDate = invitation.startDate
                existing.endDate = invitation.endDate
                existing.isAllDay = invitation.isAllDay
                existing.location = invitation.location
                existing.notes = invitation.notes
                existing.statusRawValue = invitation.statusRawValue
                existing.createdAt = invitation.createdAt
                existing.updatedAt = invitation.updatedAt
                existing.createdLocalEventID = invitation.createdLocalEventID
                existing.cloudKitRecordName = invitation.cloudKitRecordName
            } else {
                modelContext.insert(invitation)
            }
        }
        try modelContext.save()
    }

    private func upsert(accessRequests: [CalendarAccessRequest], modelContext: ModelContext) throws {
        for request in accessRequests {
            let requestID = request.id
            let descriptor = FetchDescriptor<CalendarAccessRequest>(
                predicate: #Predicate { $0.id == requestID }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                // Status-aware merge: a stale `pending` server copy must never roll back
                // a local decision (e.g. a just-approved request whose upload hasn't
                // landed), and a decision must always win over pending regardless of
                // cross-device clock skew. See CalendarAccessRequestImportMergePlan.
                guard CalendarAccessRequestImportMergePlan.shouldApplyIncoming(
                    existingStatus: existing.status,
                    existingUpdatedAt: existing.updatedAt,
                    incomingStatus: request.status,
                    incomingUpdatedAt: request.updatedAt
                ) else { continue }
                existing.requesterMemberID = request.requesterMemberID
                existing.ownerMemberID = request.ownerMemberID
                existing.requestedStartDate = request.requestedStartDate
                existing.requestedEndDate = request.requestedEndDate
                existing.statusRawValue = request.statusRawValue
                existing.createdAt = request.createdAt
                existing.updatedAt = request.updatedAt
                existing.cloudKitRecordName = request.cloudKitRecordName
                existing.sourceRawValue = request.sourceRawValue
            } else {
                modelContext.insert(request)
            }
        }
        try modelContext.save()
    }

    private func purge(
        mirrors: [EventMirror],
        modelContext: ModelContext
    ) throws {
        guard !mirrors.isEmpty else { return }
        let mirrorKeys = Set(mirrors.map(\.mirrorKey))
        let existingMirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
        for mirror in existingMirrors where mirrorKeys.contains(mirror.mirrorKey) {
            modelContext.delete(mirror)
        }
        try modelContext.save()
    }

    private func purgeShadows(
        mirrorKeys: Set<String>,
        modelContext: ModelContext
    ) throws {
        guard !mirrorKeys.isEmpty else { return }
        let existingShadows = try modelContext.fetch(FetchDescriptor<LocalEventShadow>())
        for shadow in existingShadows where mirrorKeys.contains(shadow.mirrorKey) {
            modelContext.delete(shadow)
        }
        try modelContext.save()
    }

    private func purgeStalePartnerMirrors(
        importedMirrors: [EventMirror],
        partnerShareOwnerID: String,
        modelContext: ModelContext
    ) throws {
        let importedMirrorKeys = Set(importedMirrors.map(\.mirrorKey))
        let existingMirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
        for mirror in existingMirrors
            where mirror.ownerMemberID == partnerShareOwnerID
                && !importedMirrorKeys.contains(mirror.mirrorKey) {
            modelContext.delete(mirror)
        }
        try modelContext.save()
    }
}

/// Runs the sync pipeline from background entry points (silent CloudKit push,
/// BGAppRefresh) — outside the SwiftUI view tree that drives foreground syncs
/// (notifications decision 0002). Holds the SAME SettingsStore/AppServices/container
/// instances the UI uses, so background writes propagate to the live UI and the
/// existing-iCloud-data safety gate is honored everywhere.
///
/// Lives here (not in CoupleCalendarApp.swift) because the @main file is not a member
/// of the test target; the scene delegate that schedules refreshes needs this type
/// visible when the app sources are compiled into the test bundle.
@MainActor
final class ShareCalBackgroundSyncRunner {
    static let shared = ShareCalBackgroundSyncRunner()

    private var modelContainer: ModelContainer?
    private var settings: SettingsStore?
    private var services: AppServices?
    private var isRunning = false

    private init() {}

    func configure(modelContainer: ModelContainer, settings: SettingsStore, services: AppServices) {
        self.modelContainer = modelContainer
        self.settings = settings
        self.services = services
    }

    /// Runs the full sync pipeline to completion. Returns true if a sync actually ran
    /// (i.e. new partner data may have been fetched), false if it was skipped.
    @discardableResult
    func runSync() async -> Bool {
        guard let modelContainer, let settings, let services else { return false }
        guard services.isCloudKitEnabled else { return false }
        guard !isRunning, settings.syncPhase != .syncing else { return false }
        // Honor the existing-iCloud-data recovery gate exactly as the foreground callers
        // do (notifications decision 0001): never auto-sync/merge while the user has not
        // decided what to do with pre-existing iCloud data. The gate is a pure function
        // of SettingsStore, so the background path enforces it identically.
        guard !ExistingICloudDataRecoveryPlan.shouldDeferAutomaticSync(
            hasResolvedPrompt: settings.hasResolvedExistingICloudDataPrompt,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
            lastSyncAt: settings.lastSyncAt
        ) else { return false }

        isRunning = true
        defer { isRunning = false }

        let context = ModelContext(modelContainer)
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        // A push / BGAppRefresh is itself the authoritative "there may be new data"
        // signal, so force the CloudKit leg (bypasses the time throttle, still guards
        // against concurrent runs above).
        await coordinator.foregroundSync(modelContext: context, settings: settings, forceCloudKit: true)
        return true
    }

    /// Queue the next opportunistic background refresh, when one is worthwhile. No-op
    /// for unpaired or CloudKit-disabled installs (nothing to fetch).
    func scheduleAppRefresh() {
        guard let settings, let services else { return }
        guard BackgroundRefreshSchedulePlan.shouldSchedule(
            isCloudKitEnabled: services.isCloudKitEnabled,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs
        ) else { return }
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshSchedulePlan.taskIdentifier)
        request.earliestBeginDate = BackgroundRefreshSchedulePlan.earliestBeginDate(from: Date())
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // submit fails on the simulator and when over budget; best-effort only.
            NSLog("ShareCal BGAppRefresh submit failed: \(error)")
        }
    }

    /// Run a scheduled BGAppRefresh: chain the next one first (so the cadence survives
    /// even if this run is killed), run the sync within the OS time budget, and always
    /// report completion. Expiration cancels the in-flight sync; the next run catches up
    /// because the pipeline is idempotent and `lastNotifiedAt` only advances after
    /// notifications post.
    func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        let work = Task { @MainActor in
            await runSync()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
