import BackgroundTasks
import Foundation
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
            let text = LocalNotificationContentPolicy.content(
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

    /// The one entry point screens use for a user-visible sync (pull-to-refresh,
    /// `.task`, post-edit). `foregroundSync` sets `syncPhase = .syncing` synchronously on
    /// entry and everything runs on the main actor, so this single guard already prevents
    /// overlapping/reentrant syncs from the UI.
    static func syncIfIdle(services: AppServices, settings: SettingsStore, modelContext: ModelContext) async {
        guard settings.syncPhase != .syncing else { return }
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        // Run the sync in its own task. View-scoped callers (`.task`, `.refreshable`) are
        // cancelled when their view goes away, e.g. closing an event sheet while its
        // open-sync is still running; inherited, that cancellation reaches CloudKit's
        // async calls and aborts a healthy sync. Awaiting `.value` keeps the
        // pull-to-refresh spinner until the sync ends.
        await Task {
            await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
        }.value
    }

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
            var shouldRunCloudKit = CloudKitForegroundSyncPolicy.shouldRunCloudKit(
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
                settings.selectedCalendarIDs = ShareCalCalendarBootstrapPolicy.selectedCalendarIDs(
                    afterEnsuring: calendar,
                    currentSelection: settings.selectedCalendarIDs
                )
            }
            timing.mark("calendarSelectionReady selected=\(settings.selectedCalendarIDs.count)")

            let localAccessRequests = try modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())
            if settings.hasStartedPairing || settings.partnerShareOwnerID != nil || !settings.outgoingShareParticipantIDs.isEmpty {
                settings.markPairingDateIfNeeded(at: syncedAt)
            }
            let pairingDate = settings.pairingDate ?? PairingDatePolicy.normalizedPairingDate(syncedAt)
            let sharingWindows = CalendarSharingWindowPolicy.effectiveWindows(
                now: pairingDate,
                accessRequests: localAccessRequests
            )
            let window = CalendarSharingWindowPolicy.enclosingInterval(for: sharingWindows)
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
            let mirrorsNeedingCloudUpload = CloudKitMirrorSyncPolicy.mirrorsNeedingUpload(
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
            let canceledInvitations = InvitationLocalEventSyncPolicy.cancelAcceptedInvitationsMissingLocalEvents(
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
                var pairingChangeCountAtStart = settings.localPairingChangeCount
                // Unpairing (or accepting a share) while this sync waits on CloudKit leaves
                // it holding the old pairing; writing that back would undo the change.
                let pairingChangedMeanwhile = { settings.localPairingChangeCount != pairingChangeCountAtStart }
                async let outgoingParticipantIDsTask = cloudKit.fetchOutgoingShareParticipantIDs(
                    ownerMemberID: settings.currentMemberID
                )
                async let sharedZoneIDsTask = cloudKit.fetchSharedCoupleSpaceZoneIDs()
                let outgoingParticipantIDs = try await outgoingParticipantIDsTask
                timing.mark("cloudOutgoingParticipantsFetched count=\(outgoingParticipantIDs.count)")
                let fetchedSharedZoneIDs = try await sharedZoneIDsTask
                timing.mark("cloudSharedZonesFetched count=\(fetchedSharedZoneIDs.count)")

                let previousPartnerShareOwnerID = settings.partnerShareOwnerID
                let previousOutgoingParticipantIDs = settings.outgoingShareParticipantIDs
                let resolution = TwoPersonPairingPolicy.resolve(
                    storedPartnerID: previousPartnerShareOwnerID,
                    outgoingAcceptedParticipantIDs: outgoingParticipantIDs,
                    sharedZoneOwnerIDs: fetchedSharedZoneIDs.map(\.ownerName)
                )
                if pairingChangedMeanwhile() {
                    timing.mark("cloudPairingResetDuringSync")
                    settings.lastSyncAt = .now
                    settings.syncPhase = .idle
                    try purge(mirrors: hardDeletedMirrors, modelContext: modelContext)
                    try purgeShadows(mirrorKeys: hardDeletedMirrorKeys, modelContext: modelContext)
                    return
                }
                settings.pairingConflict = resolution.conflict
                settings.outgoingShareParticipantIDs = outgoingParticipantIDs
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
                // Both halves of the pairing change together: written across awaits, the
                // status would pass through a half-pairing (an unpairing partner reads as
                // "waiting for you to share" for a moment) and the UI would react to it.
                settings.partnerShareOwnerID = resolution.partnerID

                if PartnerDeparturePolicy.partnerHasLeft(
                    previousPartnerID: previousPartnerShareOwnerID,
                    previousOutgoingParticipantIDs: previousOutgoingParticipantIDs,
                    resolvedPartnerID: resolution.partnerID,
                    outgoingParticipantIDs: outgoingParticipantIDs
                ) {
                    // The partner unpaired (left my share, deleted theirs). Take back my
                    // half too, so both of us start over from step 1 instead of me holding
                    // an invitation nobody is coming back to.
                    settings.clearPairingState()
                    pairingChangeCountAtStart = settings.localPairingChangeCount
                    do {
                        try await cloudKit.stopSharing(ownerMemberID: settings.currentMemberID)
                        try await cloudKit.purgeExPartnerRecordsFromPrivateZone(currentMemberID: settings.currentMemberID)
                        timing.mark("cloudPartnerLeftSharingStopped")
                    } catch {
                        timing.mark("cloudPartnerLeftCleanupFailed")
                    }
                    try ShareCalLocalDataCleanupService.purgeSharedOwnerData(
                        ownerMemberIDs: ICloudSharingTeardownPolicy.localOwnerIDsToPurge(
                            partnerShareOwnerID: previousPartnerShareOwnerID
                        ),
                        modelContext: modelContext
                    )
                }

                // Reinstall reconciliation: until this install has confirmed one cloud
                // write (fresh install over existing iCloud data) the ordinary tombstone
                // diff has no trustworthy "previous state", so events that vanished
                // while the app was gone would stay live in the cloud for the partner.
                // Use our own cloud mirrors as that previous state instead.
                var reconciledTombstones: [EventMirror] = []
                if OwnMirrorReconciliationPolicy.shouldReconcileWithCloud(existingShadows: existingShadows) {
                    let cloudOwnMirrors = try await cloudKit.fetchOwnEventMirrors(currentMemberID: settings.currentMemberID)
                    reconciledTombstones = eventMirrorService.deletedMirrorTombstones(
                        existingEventKeys: currentMirrorKeys,
                        existingMirrors: cloudOwnMirrors,
                        selectedCalendarIDs: settings.selectedCalendarIDs,
                        syncWindow: window,
                        deletedAt: syncedAt
                    )
                    timing.mark("cloudOwnMirrorsReconciled cloud=\(cloudOwnMirrors.count) tombstones=\(reconciledTombstones.count)")
                }
                let mirrorsToUpload = mirrorsNeedingCloudUpload + reconciledTombstones

                let accessRequestsNeedingCloudUpload = CalendarAccessRequestCloudUploadPolicy.requestsNeedingUpload(
                    localAccessRequests,
                    currentMemberID: settings.currentMemberID
                )
                let hasCloudWrites = !mirrorsToUpload.isEmpty
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
                        try await cloudKit.saveMirrorsForSync(mirrorsToUpload)
                        try upsert(mirrors: mirrorsToUpload, modelContext: modelContext)
                        timing.mark("cloudMirrorsSaved count=\(mirrorsToUpload.count)")
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

                // Import only what belongs to this pairing: a record whose other party is
                // neither me nor the resolved partner is an ex-partner's leftover.
                let fetchedAccessRequests = try await accessRequestsTask
                let cloudAccessRequests = PartnerScopedDataPolicy.scoped(
                    fetchedAccessRequests,
                    currentMemberID: settings.currentMemberID,
                    partnerID: resolution.partnerID
                )
                try upsert(accessRequests: cloudAccessRequests, modelContext: modelContext)
                timing.mark("cloudAccessRequestsFetched count=\(cloudAccessRequests.count)")
                if pairingChangedMeanwhile() {
                    timing.mark("cloudPairingResetDuringSync")
                    settings.lastSyncAt = .now
                    settings.syncPhase = .idle
                    try purge(mirrors: hardDeletedMirrors, modelContext: modelContext)
                    try purgeShadows(mirrorKeys: hardDeletedMirrorKeys, modelContext: modelContext)
                    return
                }
                let partnerShareOwnerID = resolution.partnerID
                if partnerShareOwnerID != nil || !settings.outgoingShareParticipantIDs.isEmpty {
                    settings.hasStartedPairing = true
                    settings.markPairingDateIfNeeded(at: syncedAt)
                }
                let memberProfiles = try await memberProfilesTask
                settings.partnerSyncedDisplayName = MemberProfileDisplayPolicy.partnerSyncedDisplayName(
                    from: memberProfiles,
                    partnerID: partnerShareOwnerID
                )
                let partnerSyncedAvatar = MemberProfileDisplayPolicy.partnerSyncedAvatar(
                    from: memberProfiles,
                    partnerID: partnerShareOwnerID
                )
                if settings.partnerSyncedAvatar != partnerSyncedAvatar {
                    settings.partnerSyncedAvatar = partnerSyncedAvatar
                }
                let sharedMirrors = try await sharedMirrorsTask
                let importableSharedMirrors = CloudKitSharedDatabaseImportPolicy.importableMirrors(
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
                let fetchedComments = try await commentsTask
                let cloudComments = PartnerScopedDataPolicy.scoped(
                    fetchedComments,
                    currentMemberID: settings.currentMemberID,
                    partnerID: resolution.partnerID
                )
                try upsert(comments: cloudComments, modelContext: modelContext)
                timing.mark("cloudCommentsFetched count=\(cloudComments.count)")
                let fetchedInvitations = try await invitationsTask
                let cloudInvitations = PartnerScopedDataPolicy.scoped(
                    fetchedInvitations,
                    currentMemberID: settings.currentMemberID,
                    partnerID: resolution.partnerID
                )
                try upsert(invitations: cloudInvitations, modelContext: modelContext)
                timing.mark("cloudInvitationsFetched count=\(cloudInvitations.count)")
                try ShareCalLocalDataCleanupService.purgeForeignPartnerData(
                    currentMemberID: settings.currentMemberID,
                    partnerID: resolution.partnerID,
                    modelContext: modelContext
                )

                // Reliability for terminal decisions made in a tab (fire-and-forget
                // upload): re-upload any local decision the just-fetched server copy
                // hasn't caught up to, so a failed/missed one-shot upload self-heals on
                // a later sync rather than being made permanent by the merge guard.
                // Compares against post-import local state; self-limiting once the
                // server agrees. See decision 0003.
                let localRequestsForReupload = try modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())
                let requestsToReupload = CalendarAccessRequestReuploadPolicy.ownerDecisionsNeedingReupload(
                    local: localRequestsForReupload,
                    cloud: cloudAccessRequests,
                    currentMemberID: settings.currentMemberID
                )
                for request in requestsToReupload {
                    try await cloudKit.saveCalendarAccessRequestForSync(request, currentMemberID: settings.currentMemberID)
                }
                timing.mark("cloudAccessRequestDecisionsReuploaded count=\(requestsToReupload.count)")

                let localInvitationsForReupload = try modelContext.fetch(FetchDescriptor<EventInvitation>())
                let invitationsToReupload = InvitationReuploadPolicy.responsesNeedingReupload(
                    local: localInvitationsForReupload,
                    cloud: cloudInvitations,
                    currentMemberID: settings.currentMemberID
                )
                for invitation in invitationsToReupload {
                    try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                }
                timing.mark("cloudInvitationResponsesReuploaded count=\(invitationsToReupload.count)")

                // Self-heal optimistic creates (req2): a created invitation whose upload
                // never landed keeps `needsCloudKitUpload` set; re-push it and clear the
                // flag on success so it stops retrying. Creator data lives in our private
                // zone (never read back), so this is flag-driven, not diff-driven.
                let creationsToReupload = InvitationReuploadPolicy.creationsNeedingReupload(
                    local: localInvitationsForReupload,
                    currentMemberID: settings.currentMemberID
                )
                for invitation in creationsToReupload {
                    try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                    invitation.needsCloudKitUpload = false
                }
                if !creationsToReupload.isEmpty {
                    try? modelContext.save()
                }
                timing.mark("cloudInvitationCreationsReuploaded count=\(creationsToReupload.count)")
            } else if !settings.iCloudSharingEnabled {
                settings.partnerShareOwnerID = nil
                settings.partnerSyncedDisplayName = nil
                settings.partnerSyncedAvatar = nil
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
        } catch let error where SyncCancellationPolicy.isCancellation(error) {
            // Not a failure: no banner, and `lastSyncAt` stays put so the next
            // automatic sync is not throttled away.
            settings.syncPhase = .idle
            timing.mark("cancelled")
        } catch {
            settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            settings.syncPhase = .failed
            timing.mark("failed")
        }
    }

    /// After a sync imports the partner's latest data, surface anything new since the
    /// last check as system notifications, then advance the high-water mark. Runs only
    /// once a baseline exists (first sync just sets the baseline — see LocalNotificationPolicy).
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
            planned = LocalNotificationPolicy.pending(
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
        guard let displayName = PairingSettingsPolicy.normalizedDisplayName(settings.currentDisplayName) else {
            return
        }
        try await cloudKit.saveMemberProfileForSync(
            ownerMemberID: settings.currentMemberID,
            displayName: displayName,
            avatar: settings.currentAvatar
        )
    }

    private func upsert(mirrors: [EventMirror], modelContext: ModelContext) throws {
        for mirror in mirrors {
            try EventMirrorStore.upsert(mirror, modelContext: modelContext)
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
                // flight. See InvitationImportMergePolicy / decision 0003.
                guard InvitationImportMergePolicy.shouldApplyIncoming(
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
                // cross-device clock skew. See CalendarAccessRequestImportMergePolicy.
                guard CalendarAccessRequestImportMergePolicy.shouldApplyIncoming(
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

/// The 「继续使用现有 iCloud 数据」 path's identity step, shared by RootView and the
/// reinstall smoke diagnostic. The regular sync only imports the partner's zone, so the
/// pairing date and our own nickname/avatar (which the partner already knows us by) would
/// otherwise be lost on a reinstall and overwritten by whatever the fresh install prompted
/// for. Best-effort: anything it cannot read stays as the user entered it.
@MainActor
enum ExistingICloudDataIdentityRecovery {
    static func restore(cloudKit: CloudKitCoupleSpaceService, settings: SettingsStore) async {
        if !settings.hasSyncedMemberID {
            guard let memberID = try? await cloudKit.fetchCurrentUserRecordID() else { return }
            settings.currentMemberID = memberID
        }
        let identity = await cloudKit.fetchExistingICloudIdentity(ownerMemberID: settings.currentMemberID)
        let recovered = ExistingICloudDataRecoveryPolicy.recoveredState(
            shareRootCreatedAt: identity.shareRootCreatedAt,
            ownProfile: identity.ownProfile
        )
        if let pairingDate = recovered.pairingDate {
            settings.pairingDate = pairingDate
        }
        if let displayName = recovered.displayName {
            settings.currentDisplayName = displayName
            settings.currentAvatar = recovered.avatar
            settings.hasCompletedInitialProfilePrompt = true
        }
    }
}

/// Runs the sync pipeline from background entry points (silent CloudKit push,
/// BGAppRefresh) — outside the SwiftUI view tree that drives foreground syncs
/// (notifications decision 0002). Holds the SAME SettingsStore/AppServices/container
/// instances the UI uses, so background writes propagate to the live UI and the
/// existing-iCloud-data safety gate is honored everywhere.
///
/// Lives here (not in OurDaysApp.swift) because the @main file is not a member
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
        guard !ExistingICloudDataRecoveryPolicy.shouldDeferAutomaticSync(
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
        guard BackgroundRefreshSchedulePolicy.shouldSchedule(
            isCloudKitEnabled: services.isCloudKitEnabled,
            hasStartedPairing: settings.hasStartedPairing,
            partnerShareOwnerID: settings.partnerShareOwnerID,
            outgoingShareParticipantIDs: settings.outgoingShareParticipantIDs
        ) else { return }
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshSchedulePolicy.taskIdentifier)
        request.earliestBeginDate = BackgroundRefreshSchedulePolicy.earliestBeginDate(from: Date())
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
