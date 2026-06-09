import Foundation
import Observation
import OSLog
import SwiftData

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
    var currentLocalOwnerID: String {
        didSet { defaults.set(currentLocalOwnerID, forKey: Key.currentLocalOwnerID) }
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
    var partnerICloudEmailAddresses: [String] {
        didSet { defaults.set(partnerICloudEmailAddresses, forKey: Key.partnerICloudEmailAddresses) }
    }
    var inactiveSharedOwnerIDs: [String] {
        didSet { defaults.set(inactiveSharedOwnerIDs, forKey: Key.inactiveSharedOwnerIDs) }
    }
    var outgoingShareParticipantIDs: [String] {
        didSet { defaults.set(outgoingShareParticipantIDs, forKey: Key.outgoingShareParticipantIDs) }
    }
    var pairingID: String? {
        didSet { saveOptionalString(pairingID, forKey: Key.pairingID) }
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
    var lastSyncError: String?
    var syncPhase: SyncPhase = .idle

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedOwnerID = Self.normalizedString(defaults.string(forKey: Key.currentLocalOwnerID))
        let localOwnerID: String
        if let storedOwnerID {
            localOwnerID = storedOwnerID
        } else {
            let generatedOwnerID = "local-owner-\(UUID().uuidString)"
            localOwnerID = generatedOwnerID
            defaults.set(generatedOwnerID, forKey: Key.currentLocalOwnerID)
        }
        currentLocalOwnerID = localOwnerID
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
        partnerICloudEmailAddresses = defaults.stringArray(forKey: Key.partnerICloudEmailAddresses) ?? []
        inactiveSharedOwnerIDs = defaults.stringArray(forKey: Key.inactiveSharedOwnerIDs) ?? []
        outgoingShareParticipantIDs = defaults.stringArray(forKey: Key.outgoingShareParticipantIDs) ?? []
        pairingID = defaults.string(forKey: Key.pairingID)
        iCloudSharingEnabled = defaults.object(forKey: Key.iCloudSharingEnabled) as? Bool ?? true
        hasStartedPairing = defaults.object(forKey: Key.hasStartedPairing) as? Bool ?? false
        pairingDate = defaults.object(forKey: Key.pairingDate) as? Date
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendarIDs) ?? [])
        defaultVisibility = EventVisibility(rawValue: defaults.string(forKey: Key.defaultVisibility) ?? "") ?? .fullDetails
        appLanguage = AppLanguagePreference.read(from: defaults)
        lastSyncAt = defaults.object(forKey: Key.lastSyncAt) as? Date
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

    func ensurePairingID() -> String {
        if let pairingID = normalizedID(pairingID) {
            self.pairingID = pairingID
            return pairingID
        }
        let pairingID = UUID().uuidString
        self.pairingID = pairingID
        return pairingID
    }

    func clearPairingID() {
        pairingID = nil
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
        static let currentLocalOwnerID = "currentLocalOwnerID"
        static let currentDisplayName = "currentDisplayName"
        static let currentICloudEmailAddress = "currentICloudEmailAddress"
        static let partnerNoteName = "partnerNoteName"
        static let partnerShareOwnerID = "partnerShareOwnerID"
        static let partnerSyncedDisplayName = "partnerSyncedDisplayName"
        static let hasCompletedInitialProfilePrompt = "hasCompletedInitialProfilePrompt"
        static let hasPromptedPartnerNoteForCurrentPairing = "hasPromptedPartnerNoteForCurrentPairing"
        static let hasShownPairingSafetyNoticeForCurrentPairing = "hasShownPairingSafetyNoticeForCurrentPairing"
        static let hasResolvedExistingICloudDataPrompt = "hasResolvedExistingICloudDataPrompt"
        static let partnerICloudEmailAddresses = "partnerICloudEmailAddresses"
        static let inactiveSharedOwnerIDs = "inactiveSharedOwnerIDs"
        static let outgoingShareParticipantIDs = "outgoingShareParticipantIDs"
        static let pairingID = "pairingID"
        static let iCloudSharingEnabled = "iCloudSharingEnabled"
        static let hasStartedPairing = "hasStartedPairing"
        static let pairingDate = "pairingDate"
        static let selectedCalendarIDs = "selectedCalendarIDs"
        static let defaultVisibility = "defaultVisibility"
        static let lastSyncAt = "lastSyncAt"
    }
}

extension SettingsStore {
    var strings: ShareCalStrings {
        ShareCalStrings(language: appLanguage)
    }

    var readablePartnerICloudIdentity: String {
        PairingSettingsPlan.partnerIdentity(
            incomingOwnerID: partnerShareOwnerID,
            outgoingParticipantIDs: outgoingShareParticipantIDs,
            partnerICloudEmailAddresses: partnerICloudEmailAddresses,
            emptyValue: strings.noICloudSharingIdentity
        )
    }

    var partnerDisplayName: String {
        PairingSettingsPlan.partnerDisplayName(
            partnerNoteName: partnerNoteName,
            partnerSyncedDisplayName: partnerSyncedDisplayName,
            partnerICloudIdentity: readablePartnerICloudIdentity,
            fallback: strings.partnerTitle
        )
    }

    var partnerStatusDisplayName: String {
        PairingSettingsPlan.partnerStatusDisplayName(
            partnerNoteName: partnerNoteName,
            partnerSyncedDisplayName: partnerSyncedDisplayName,
            partnerICloudIdentity: readablePartnerICloudIdentity,
            fallback: strings.partnerTitle,
            language: appLanguage
        )
    }

    var partnerOwnerIDForLocalData: String {
        let trimmedNoteName = partnerNoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        return partnerShareOwnerID ?? (trimmedNoteName.isEmpty ? "partner" : trimmedNoteName)
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

@MainActor
struct SyncCoordinator {
    let calendarAccess: CalendarAccessService
    let eventMirrorService: EventMirrorService
    let cloudKit: CloudKitCoupleSpaceService?

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
                ownerMemberID: settings.currentLocalOwnerID,
                visibility: settings.defaultVisibility,
                sharingWindows: sharingWindows
            )
            let activeShadows = eventMirrorService.makeShadows(
                from: sourceEvents,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                uploadedAt: syncedAt,
                sharingWindows: sharingWindows
            )
            let currentMirrorKeys = Set(mirrors.map(\.mirrorKey))
            let existingShadows = try modelContext.fetch(FetchDescriptor<LocalEventShadow>())
            let existingLocalMirrors = try localMirrors(
                ownerMemberID: settings.currentLocalOwnerID,
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
            let shouldRunCloudKit = CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: settings.iCloudSharingEnabled,
                hasStartedPairing: settings.hasStartedPairing,
                partnerShareOwnerID: settings.partnerShareOwnerID,
                outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs,
                forceCloudKit: forceCloudKit
            )
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

                let accessRequestsNeedingCloudUpload = CalendarAccessRequestCloudUploadPlan.requestsNeedingUpload(
                    localAccessRequests,
                    currentMemberID: settings.currentLocalOwnerID
                )
                let hasCloudWrites = !mirrorsNeedingCloudUpload.isEmpty
                    || !hardDeletedMirrors.isEmpty
                    || !canceledInvitations.isEmpty
                    || !accessRequestsNeedingCloudUpload.isEmpty
                let shouldUpdateShareRootMetadata = settings.hasStartedPairing
                    || settings.partnerShareOwnerID != nil
                    || !settings.outgoingShareParticipantIDs.isEmpty
                    || settings.pairingID != nil
                if hasCloudWrites || shouldUpdateShareRootMetadata {
                    try await cloudKit.ensureShareRoot(
                        ownerMemberID: settings.currentLocalOwnerID,
                        pairingID: settings.pairingID
                    )
                    timing.mark("cloudShareRootReady")
                    if let pairingID = normalizedID(settings.pairingID) {
                        try await saveCurrentMemberProfileIfPossible(
                            cloudKit: cloudKit,
                            settings: settings,
                            pairingID: pairingID
                        )
                        timing.mark("cloudMemberProfileChecked")
                    }
                    if hasCloudWrites {
                        try await cloudKit.saveMirrorsForSync(mirrorsNeedingCloudUpload)
                        try upsert(mirrors: mirrorsNeedingCloudUpload, modelContext: modelContext)
                        timing.mark("cloudMirrorsSaved count=\(mirrorsNeedingCloudUpload.count)")
                        try await cloudKit.deleteMirrorsForSync(hardDeletedMirrors)
                        timing.mark("cloudHardDeletesSaved count=\(hardDeletedMirrors.count)")
                        for invitation in canceledInvitations {
                            try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentLocalOwnerID)
                        }
                        timing.mark("cloudCanceledInvitationsSaved count=\(canceledInvitations.count)")
                        for request in accessRequestsNeedingCloudUpload {
                            try await cloudKit.saveCalendarAccessRequestForSync(
                                request,
                                currentMemberID: settings.currentLocalOwnerID
                            )
                        }
                        timing.mark("cloudAccessRequestsSaved count=\(accessRequestsNeedingCloudUpload.count)")
                    }
                } else {
                    timing.mark("cloudWritesSkipped")
                }

                try await cloudKit.foregroundSync()
                timing.mark("cloudSyncEngineFinished")
                async let outgoingShareParticipantIdentitySnapshot = cloudKit.fetchOutgoingShareParticipantIdentitySnapshot(
                    ownerMemberID: settings.currentLocalOwnerID
                )
                async let sharedZoneIDs = cloudKit.fetchSharedCoupleSpaceZoneIDs()
                let fetchedOutgoingShareParticipantIdentitySnapshot = try await outgoingShareParticipantIdentitySnapshot
                settings.outgoingShareParticipantIDs = fetchedOutgoingShareParticipantIdentitySnapshot.identifiers
                settings.partnerICloudEmailAddresses = ICloudSharingIdentityDisplayPlan.emailAddresses(
                    merging: settings.partnerICloudEmailAddresses,
                    fetchedOutgoingShareParticipantIdentitySnapshot.emailAddresses
                )
                timing.mark("cloudOutgoingParticipantsFetched count=\(settings.outgoingShareParticipantIDs.count)")
                let fetchedSharedZoneIDs = try await sharedZoneIDs
                timing.mark("cloudSharedZonesFetched count=\(fetchedSharedZoneIDs.count)")
                if LegacyPairingIDMigrationPlan.shouldGeneratePairingID(
                    currentPairingID: settings.pairingID,
                    hasStartedPairing: settings.hasStartedPairing,
                    partnerShareOwnerID: settings.partnerShareOwnerID,
                    outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
                    sharedZoneOwnerIDs: fetchedSharedZoneIDs.map(\.ownerName)
                ) {
                    let pairingID = settings.ensurePairingID()
                    try await cloudKit.ensureShareRoot(
                        ownerMemberID: settings.currentLocalOwnerID,
                        pairingID: pairingID
                    )
                    try await saveCurrentMemberProfileIfPossible(
                        cloudKit: cloudKit,
                        settings: settings,
                        pairingID: pairingID
                    )
                    timing.mark("cloudLegacyPairingIDMigrated")
                }
                let sharedZonePairingInfos = try await cloudKit.fetchSharedZonePairingInfos(sharedZoneIDs: fetchedSharedZoneIDs)
                let legacyPartnerOwnerIDs = LegacyPairingIDMigrationPlan.partnerOwnerIDsForSelection(
                    partnerShareOwnerID: settings.partnerShareOwnerID,
                    outgoingParticipantIDs: settings.outgoingShareParticipantIDs,
                    hasStartedPairing: settings.hasStartedPairing
                )
                let pairingSelection = PairingSharedZoneSelectionPlan.selection(
                    currentPairingID: settings.pairingID,
                    sharedZones: sharedZonePairingInfos,
                    allowsPairingIDConflictResolution: settings.partnerShareOwnerID == nil,
                    legacyPartnerOwnerIDs: legacyPartnerOwnerIDs
                )
                if let selectedPairingID = pairingSelection.pairingID,
                   settings.pairingID != selectedPairingID {
                    settings.pairingID = selectedPairingID
                    try await cloudKit.ensureShareRoot(
                        ownerMemberID: settings.currentLocalOwnerID,
                        pairingID: selectedPairingID
                    )
                    try await saveCurrentMemberProfileIfPossible(
                        cloudKit: cloudKit,
                        settings: settings,
                        pairingID: selectedPairingID
                    )
                }
                let activeSharedZoneIDs = pairingSelection.activeSharedZoneIDs
                settings.inactiveSharedOwnerIDs = pairingSelection.inactiveSharedOwnerIDs
                timing.mark("cloudActiveSharedZones selected=\(activeSharedZoneIDs.count) inactive=\(settings.inactiveSharedOwnerIDs.count)")

                async let accessRequestsTask = cloudKit.fetchCalendarAccessRequests(sharedZoneIDs: activeSharedZoneIDs)
                async let sharedMirrorsTask = cloudKit.fetchSharedEventMirrors(sharedZoneIDs: activeSharedZoneIDs)
                async let commentsTask = cloudKit.fetchEventComments(sharedZoneIDs: activeSharedZoneIDs)
                async let invitationsTask = cloudKit.fetchEventInvitations(sharedZoneIDs: activeSharedZoneIDs)
                async let memberProfilesTask = cloudKit.fetchMemberProfiles(sharedZoneIDs: activeSharedZoneIDs)
                async let sharedOwnerEmailAddressesTask = cloudKit.fetchSharedOwnerICloudEmailAddresses(sharedZoneIDs: activeSharedZoneIDs)

                let cloudAccessRequests = try await accessRequestsTask
                try upsert(accessRequests: cloudAccessRequests, modelContext: modelContext)
                timing.mark("cloudAccessRequestsFetched count=\(cloudAccessRequests.count)")
                let previousPartnerShareOwnerID = settings.partnerShareOwnerID
                let partnerShareOwnerID = pairingSelection.activePartnerOwnerID
                settings.partnerShareOwnerID = partnerShareOwnerID
                if partnerShareOwnerID != nil || !settings.outgoingShareParticipantIDs.isEmpty {
                    settings.hasStartedPairing = true
                    settings.markPairingDateIfNeeded(at: syncedAt)
                }
                let sharedOwnerEmailAddresses = try await sharedOwnerEmailAddressesTask
                settings.partnerICloudEmailAddresses = ICloudSharingIdentityDisplayPlan.emailAddresses(
                    merging: settings.partnerICloudEmailAddresses,
                    sharedOwnerEmailAddresses
                )
                let memberProfiles = try await memberProfilesTask
                settings.partnerSyncedDisplayName = normalizedID(settings.pairingID).flatMap { pairingID in
                    MemberProfileDisplayPlan.partnerSyncedDisplayName(
                        from: memberProfiles,
                        currentLocalOwnerID: settings.currentLocalOwnerID,
                        pairingID: pairingID
                    )
                }
                let sharedMirrors = try await sharedMirrorsTask
                let importableSharedMirrors = CloudKitSharedDatabaseImportPlan.importableMirrors(
                    sharedMirrors,
                    currentMemberID: settings.currentLocalOwnerID
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
            } else if !settings.iCloudSharingEnabled {
                settings.partnerShareOwnerID = nil
                settings.partnerSyncedDisplayName = nil
                settings.partnerICloudEmailAddresses = []
                settings.inactiveSharedOwnerIDs = []
                settings.outgoingShareParticipantIDs = []
                settings.clearPairingID()
                settings.hasStartedPairing = false
            } else {
                timing.mark("cloudSyncSkippedUnpaired")
            }
            try purge(mirrors: hardDeletedMirrors, modelContext: modelContext)
            try purgeShadows(mirrorKeys: hardDeletedMirrorKeys, modelContext: modelContext)

            settings.lastSyncAt = .now
            settings.syncPhase = .idle
            timing.mark("finished")
        } catch {
            settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            settings.syncPhase = .failed
            timing.mark("failed")
        }
    }

    private func localMirrors(ownerMemberID: String, modelContext: ModelContext) throws -> [EventMirror] {
        let descriptor = FetchDescriptor<EventMirror>(
            predicate: #Predicate { $0.ownerMemberID == ownerMemberID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func normalizedID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func saveCurrentMemberProfileIfPossible(
        cloudKit: CloudKitCoupleSpaceService,
        settings: SettingsStore,
        pairingID: String
    ) async throws {
        guard let displayName = PairingSettingsPlan.normalizedDisplayName(settings.currentDisplayName) else {
            return
        }
        try await cloudKit.saveMemberProfileForSync(
            ownerMemberID: settings.currentLocalOwnerID,
            pairingID: pairingID,
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
                existing.lastUploadedAt = shadow.lastUploadedAt
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
