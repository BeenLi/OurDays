import Foundation
import SwiftData

@MainActor
enum ShareCalLaunchDiagnostics {
    static func runIfRequested(
        services: AppServices,
        settings: SettingsStore,
        modelContext: ModelContext,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) async {
        if ShareCalLaunchDiagnosticPlan.shouldSeedCalendarEvent(arguments: arguments) {
            do {
                let eventID = try services.calendarAccess.ensureShareCalSmokeTestEvent(
                    draft: ShareCalLaunchDiagnosticPlan.seedCalendarEventDraft(arguments: arguments)
                )
                NSLog("ShareCal seeded calendar event: \(eventID)")
            } catch {
                NSLog("ShareCal failed to seed calendar event: \(error)")
            }
        }

        if let title = ShareCalLaunchDiagnosticPlan.deleteCalendarEventTitle(arguments: arguments) {
            do {
                let count = try services.calendarAccess.deleteShareCalEvents(titled: title)
                NSLog("%@ deleteCalendarEvent succeeded title=%@ count=%d", diag, title, count)
            } catch {
                NSLog("%@ deleteCalendarEvent failed: %@", diag, String(describing: error))
            }
        }

        if ShareCalLaunchDiagnosticPlan.shouldRunCloudKitWriteProbe(arguments: arguments) {
            await services.cloudKit.runPrivateDatabaseWriteProbe()
        }

        if ShareCalLaunchDiagnosticPlan.shouldRunSharedReadProbe(arguments: arguments) {
            let diagnostic = await services.cloudKit.sharedReadDiagnostic()
            NSLog("ShareCal shared read probe:\n\(diagnostic.displayText)")
            NSLog("ShareCal shared read probe proves no access: \(diagnostic.provesNoSharedCalendarReadAccess)")
        }

        if ShareCalLaunchDiagnosticPlan.shouldRunStopSharingProbe(arguments: arguments) {
            do {
                try await services.cloudKit.stopSharing(ownerMemberID: settings.currentMemberID)
                NSLog("ShareCal stop sharing probe succeeded")
            } catch {
                NSLog("ShareCal stop sharing probe failed: \(error)")
            }
        }

        if ShareCalLaunchDiagnosticPlan.shouldPreparePairingShare(arguments: arguments) {
            do {
                if !settings.hasSyncedMemberID {
                    settings.currentMemberID = try await services.cloudKit.fetchCurrentUserRecordID()
                }
                if PairingSettingsPlan.normalizedDisplayName(settings.currentDisplayName) == nil {
                    settings.currentDisplayName = PairingSettingsPlan.randomDisplayName()
                    settings.hasCompletedInitialProfilePrompt = true
                }
                let preparedShare = try await services.cloudKit.prepareShare(ownerMemberID: settings.currentMemberID)
                try await services.cloudKit.saveMemberProfileForSync(
                    ownerMemberID: settings.currentMemberID,
                    displayName: settings.currentDisplayName
                )
                settings.iCloudSharingEnabled = true
                settings.hasStartedPairing = true
                settings.markPairingDateIfNeeded()
                NSLog(
                    "%@ %@",
                    ShareCalLaunchDiagnosticPlan.pairingShareURLLogPrefix,
                    preparedShare.share.url?.absoluteString ?? "missing"
                )
            } catch {
                NSLog("ShareCal prepare pairing share probe failed: \(error)")
            }
        }

        if let shareURL = ShareCalLaunchDiagnosticPlan.acceptShareURL(arguments: arguments) {
            do {
                let metadata = try await services.cloudKit.fetchShareMetadata(from: shareURL)
                ShareCalCloudKitShareAcceptanceHandler.handle(metadata: metadata)
                NSLog("ShareCal accept share probe handled metadata owner=%@", metadata.share.recordID.zoneID.ownerName)
            } catch {
                NSLog("ShareCal accept share probe failed: \(error)")
            }
        }

        if ShareCalLaunchDiagnosticPlan.shouldForceSync(arguments: arguments) {
            // Reuses the accepted-share signal channel: RootView consumes it and
            // runs a foreground sync that bypasses the automatic-sync throttle.
            ShareCalAcceptedShareSignal.markAccepted(partnerOwnerID: nil)
        }

        // Joint-event / comment smoke flow. Each handler that needs current data runs
        // its own direct foreground sync (the force-sync signal above is consumed by
        // RootView asynchronously, so it can't be relied on within this task).
        if ShareCalLaunchDiagnosticPlan.shouldRecoverExistingICloudData(arguments: arguments) {
            await recoverExistingICloudData(services: services, settings: settings, modelContext: modelContext)
        }
        if ShareCalLaunchDiagnosticPlan.shouldSeedInvitation(arguments: arguments) {
            await seedInvitation(services: services, settings: settings, modelContext: modelContext, arguments: arguments)
        }
        if ShareCalLaunchDiagnosticPlan.shouldAcceptInvitation(arguments: arguments) {
            await acceptInvitation(services: services, settings: settings, modelContext: modelContext)
        }
        if let invitationID = ShareCalLaunchDiagnosticPlan.withdrawInvitationID(arguments: arguments) {
            await withdrawInvitation(id: invitationID, services: services, settings: settings, modelContext: modelContext)
        }
        if ShareCalLaunchDiagnosticPlan.shouldProbeInvitations(arguments: arguments) {
            await probeInvitations(services: services, settings: settings, modelContext: modelContext)
        }
        if let body = ShareCalLaunchDiagnosticPlan.jointCommentBody(arguments: arguments) {
            await addJointComment(body: body, services: services, settings: settings, modelContext: modelContext)
        }
        if ShareCalLaunchDiagnosticPlan.shouldProbeJointComments(arguments: arguments) {
            await probeJointComments(services: services, settings: settings, modelContext: modelContext)
        }
        if let body = ShareCalLaunchDiagnosticPlan.ordinaryCommentBody(arguments: arguments) {
            await seedOrdinaryComment(body: body, services: services, settings: settings, modelContext: modelContext)
        }
        if let body = ShareCalLaunchDiagnosticPlan.eventCommentBody(arguments: arguments) {
            await addEventComment(
                body: body,
                title: ShareCalLaunchDiagnosticPlan.eventCommentTitle(arguments: arguments),
                services: services, settings: settings, modelContext: modelContext
            )
        }
        if ShareCalLaunchDiagnosticPlan.shouldProbeEventComments(arguments: arguments) {
            await probeEventComments(
                title: ShareCalLaunchDiagnosticPlan.eventCommentTitle(arguments: arguments),
                services: services, settings: settings, modelContext: modelContext
            )
        }
    }

    private static let diag = ShareCalLaunchDiagnosticPlan.diagnosticLogPrefix

    private static func runForegroundSync(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
    }

    private static func acceptedInvitation(in modelContext: ModelContext) -> EventInvitation? {
        let all = (try? modelContext.fetch(FetchDescriptor<EventInvitation>())) ?? []
        return all.first { $0.status == .accepted && $0.archivedAt == nil }
    }

    /// Owner side: create an invitation matching the owner's already-seeded smoke event
    /// (so the title/date fallback in `localEventExists` keeps it from being auto-canceled
    /// once the partner's acceptance syncs back), then upload it.
    private static func seedInvitation(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext, arguments: [String]
    ) async {
        do {
            _ = try? services.calendarAccess.ensureShareCalSmokeTestEvent()
            let title = ShareCalLaunchDiagnosticPlan.seedInvitationTitle(arguments: arguments)
                ?? ShareCalSmokeTestEventPlan.title
            let window = services.calendarAccess.authorizedEvents(
                from: Date().addingTimeInterval(-2 * 24 * 3600),
                to: Date().addingTimeInterval(8 * 24 * 3600)
            )
            guard let source = window.first(where: { $0.title == title }) else {
                NSLog("%@ seedInvitation failed: no local event titled %@", diag, title)
                return
            }
            let invitation = EventInvitation(
                creatorMemberID: settings.currentMemberID,
                inviteeMemberID: settings.partnerOwnerIDForLocalData,
                title: source.title,
                startDate: source.startDate,
                endDate: source.endDate,
                isAllDay: source.isAllDay,
                location: source.location,
                notes: source.notes,
                statusRawValue: InvitationStatus.pending.rawValue,
                needsCloudKitUpload: services.cloudKitIfAvailable != nil
            )
            modelContext.insert(invitation)
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                invitation.needsCloudKitUpload = false
                try? modelContext.save()
            }
            NSLog("%@ seedInvitation succeeded id=%@ title=%@", diag, invitation.id, source.title)
        } catch {
            NSLog("%@ seedInvitation failed: %@", diag, String(describing: error))
        }
    }

    /// Partner side: sync to receive the pending invitation, then accept it via the real
    /// flow (creates a local EventKit event so it isn't auto-canceled) and upload.
    private static func acceptInvitation(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let all = (try? modelContext.fetch(FetchDescriptor<EventInvitation>())) ?? []
        guard let pending = all.first(where: {
            $0.status == .pending && $0.creatorMemberID != settings.currentMemberID
        }) else {
            NSLog("%@ acceptInvitation none-pending", diag)
            return
        }
        do {
            let draft = services.invitationService.draft(from: pending)
            let createdEvent = try services.calendarAccess.createShareCalEvent(from: draft)
            _ = try services.invitationService.accept(pending, createdLocalEventID: createdEvent.eventIdentifier)
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveInvitationForSync(pending, currentMemberID: settings.currentMemberID)
            }
            NSLog("%@ acceptInvitation succeeded id=%@", diag, pending.id)
        } catch {
            NSLog("%@ acceptInvitation failed: %@", diag, String(describing: error))
        }
    }

    /// Fresh install over existing iCloud data: what the 「继续使用现有 iCloud 数据」 button
    /// does (identity restore + forced sync), then log the recovered state so the smoke
    /// script can assert the pairing, nickname and imported data came back without a
    /// re-pair. The owner's console also carries the sync's `cloudOwnMirrorsReconciled`
    /// line for the ghost-event tombstones.
    private static func recoverExistingICloudData(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        guard let cloudKit = services.cloudKitIfAvailable else {
            NSLog("%@ recoverExistingICloudData failed: CloudKit unavailable", diag)
            return
        }
        let snapshot = await cloudKit.existingICloudDataSnapshot()
        NSLog("%@ recoverExistingICloudData snapshot privateZone=%d outgoingShare=%d sharedZones=%d lookupFailed=%d",
              diag, snapshot.hasPrivateZoneData ? 1 : 0, snapshot.hasOutgoingShare ? 1 : 0,
              snapshot.acceptedSharedZoneCount, snapshot.lookupFailed ? 1 : 0)
        settings.iCloudSharingEnabled = true
        await ExistingICloudDataIdentityRecovery.restore(cloudKit: cloudKit, settings: settings)
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings, forceCloudKit: true)
        settings.hasResolvedExistingICloudDataPrompt = true

        let partnerID = settings.partnerShareOwnerID ?? "nil"
        let partnerMirrors = ((try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? [])
            .filter { $0.ownerMemberID == settings.partnerShareOwnerID && $0.deletedAt == nil }.count
        let comments = ((try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? []).count
        let invitations = ((try? modelContext.fetch(FetchDescriptor<EventInvitation>())) ?? []).count
        let pairingDate = settings.pairingDate.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
        NSLog("%@ recoverExistingICloudData result phase=%@ partner=%@ hasStartedPairing=%d displayName=%@ pairingDate=%@ partnerMirrors=%d comments=%d invitations=%d error=%@",
              diag, settings.syncPhase.rawValue, partnerID, settings.hasStartedPairing ? 1 : 0,
              settings.currentDisplayName, pairingDate, partnerMirrors, comments, invitations,
              settings.lastSyncError ?? "none")
    }

    /// Creator side: withdraw my pending invitation through the real service path
    /// (`InvitationService.cancel` → upload to my private zone), exactly as the
    /// "撤销邀请" button does.
    private static func withdrawInvitation(
        id: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        let all = (try? modelContext.fetch(FetchDescriptor<EventInvitation>())) ?? []
        guard let invitation = all.first(where: { $0.id == id }) else {
            NSLog("%@ withdrawInvitation failed: no invitation id=%@", diag, id)
            return
        }
        guard InvitationInteractionPlan.canWithdraw(invitation, currentMemberID: settings.currentMemberID) else {
            NSLog("%@ withdrawInvitation failed: not withdrawable id=%@ status=%@ creator=%@ me=%@",
                  diag, id, invitation.statusRawValue, invitation.creatorMemberID, settings.currentMemberID)
            return
        }
        do {
            services.invitationService.cancel(invitation)
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                invitation.needsCloudKitUpload = false
                try? modelContext.save()
            }
            NSLog("%@ withdrawInvitation succeeded id=%@", diag, id)
        } catch {
            NSLog("%@ withdrawInvitation failed: %@", diag, String(describing: error))
        }
    }

    /// Either side: sync, then log every invitation's id and status so the smoke script
    /// can assert what this device currently believes about each one.
    private static func probeInvitations(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let all = ((try? modelContext.fetch(FetchDescriptor<EventInvitation>())) ?? [])
            .sorted { $0.createdAt < $1.createdAt }
        let entries = all.map { "\($0.id):\($0.statusRawValue)" }.joined(separator: ",")
        NSLog("%@ invitations count=%d entries=[%@]", diag, all.count, entries)
    }

    /// Either side: sync, find the joint (accepted) invitation, add a comment anchored to
    /// it (routed by `EventCommentAnchorPlan`), and upload.
    private static func addJointComment(
        body: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        guard let invitation = acceptedInvitation(in: modelContext) else {
            NSLog("%@ addJointComment failed: no accepted invitation", diag)
            return
        }
        let anchor = EventCommentAnchorPlan.anchor(forInvitation: invitation)
        let comment = services.commentService.createComment(
            eventMirrorID: anchor.key,
            authorMemberID: settings.currentMemberID,
            body: body
        )
        modelContext.insert(comment)
        do {
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveCommentForSync(
                    comment,
                    eventOwnerMemberID: anchor.ownerMemberID,
                    currentMemberID: settings.currentMemberID,
                    eventRecordName: anchor.recordName
                )
            }
            NSLog("%@ addJointComment succeeded id=%@ anchor=%@ body=%@", diag, comment.id, anchor.key, body)
        } catch {
            NSLog("%@ addJointComment failed: %@", diag, String(describing: error))
        }
    }

    /// Either side: sync, then log every comment on the joint thread (count + bodies), so
    /// the smoke script can assert both partners' comments are present (symmetry).
    private static func probeJointComments(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        guard let invitation = acceptedInvitation(in: modelContext) else {
            NSLog("%@ jointComments count=0 (no accepted invitation)", diag)
            return
        }
        let anchor = EventCommentAnchorPlan.anchor(forInvitation: invitation)
        let comments = ((try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? [])
            .filter { $0.eventMirrorID == anchor.key && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let bodies = comments.map(\.body).joined(separator: "|")
        NSLog("%@ jointComments count=%d bodies=[%@]", diag, comments.count, bodies)
    }

    /// Either side: comment on the event with the given title. On the owner the event is
    /// found in EventKit and opened exactly like the calendar does — as a transient display
    /// mirror run through `EventDetailCommentPlan` — so the comment is keyed by the mirrorKey
    /// whether or not the mirror has synced yet (that is the "start a thread on my own event"
    /// path). On the partner there is no such EventKit event, so the imported persisted mirror
    /// is used and the write routes into the owner's shared zone. A sync follows the upload so
    /// an unsynced own mirror lands too and the partner can find the event.
    private static func addEventComment(
        body: String, title: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        let persisted = (try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? []
        let selectedCalendarIDs = settings.selectedCalendarIDs
        let now = Date.now
        let ownEvents = services.calendarAccess.authorizedEvents(
            from: now.addingTimeInterval(-7 * 86_400),
            to: now.addingTimeInterval(7 * 86_400)
        ).filter { selectedCalendarIDs.contains($0.calendarIdentifier) && $0.title == title }
        let displayMirrors = CalendarDisplayMirrorPlan.displayMirrors(
            from: ownEvents, ownerMemberID: settings.currentMemberID
        )

        let anchor: EventCommentAnchor
        let resolution: String
        if let display = displayMirrors.first {
            let sharingWindows = CalendarSharingWindowPlan.effectiveWindows(
                now: settings.pairingDate ?? PairingDatePlan.normalizedPairingDate(now),
                accessRequests: (try? modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())) ?? []
            )
            switch EventDetailCommentPlan.availability(for: display, mirrors: persisted, sharingWindows: sharingWindows) {
            case .available(let resolved):
                anchor = resolved
                let twin = EventDetailMirrorResolutionPlan.persistedTwin(for: display, in: persisted)
                resolution = "own twin=\(twin?.id ?? "none")"
            case .notSharedWithPartner:
                NSLog("%@ addEventComment failed: own event '%@' is outside the sharing windows", diag, title)
                return
            }
        } else if let mirror = persisted.first(where: {
            $0.deletedAt == nil && $0.title == title && !$0.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix)
        }) {
            anchor = EventCommentAnchorPlan.anchor(forMirror: mirror)
            resolution = "persisted owner=\(mirror.ownerMemberID)"
        } else {
            NSLog("%@ addEventComment failed: no event titled '%@' (EventKit or persisted)", diag, title)
            return
        }

        let comment = services.commentService.createComment(
            eventMirrorID: anchor.key,
            authorMemberID: settings.currentMemberID,
            body: body
        )
        modelContext.insert(comment)
        do {
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveCommentForSync(
                    comment,
                    eventOwnerMemberID: anchor.ownerMemberID,
                    currentMemberID: settings.currentMemberID,
                    eventRecordName: anchor.recordName
                )
            }
        } catch {
            NSLog("%@ addEventComment failed: %@", diag, String(describing: error))
            return
        }
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        NSLog(
            "%@ addEventComment succeeded title=%@ anchor=%@ via=%@ body=%@",
            diag, title, anchor.key, resolution, body
        )
    }

    /// Either side: sync, then log the thread of the persisted mirror with the given title.
    private static func probeEventComments(
        title: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let mirrors = (try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? []
        guard let mirror = mirrors.first(where: {
            $0.deletedAt == nil && $0.title == title && !$0.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix)
        }) else {
            NSLog("%@ eventComments title=%@ count=0 (no persisted mirror)", diag, title)
            return
        }
        let anchor = EventCommentAnchorPlan.anchor(forMirror: mirror)
        let comments = ((try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? [])
            .filter { $0.eventMirrorID == anchor.key && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let bodies = comments.map(\.body).joined(separator: "|")
        NSLog("%@ eventComments title=%@ count=%d bodies=[%@]", diag, title, comments.count, bodies)
    }

    /// V1b visual check title — a fresh ORDINARY event of my own (no matching invitation, so it
    /// is NOT reclassified as a joint event and stays on the regular EventDetailView path).
    static let ordinaryCommentEventTitle = "V1B Ordinary Event"

    /// V1b: simulate "partner commented on MY ordinary event". Ensure the ordinary event, sync so
    /// my `EventMirror` twin is persisted, then add a partner-authored comment anchored to that
    /// mirror's real id and upload it (survives later syncs). A single simulator can then show the
    /// red dot on my own event and the comment thread + reply box in its detail — exactly req1+req2.
    private static func seedOrdinaryComment(
        body: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        _ = try? services.calendarAccess.ensureShareCalSmokeTestEvent(title: ordinaryCommentEventTitle)
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let mirrors = (try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? []
        guard let mine = mirrors.first(where: {
            $0.deletedAt == nil
                && $0.ownerMemberID == settings.currentMemberID
                && $0.title == ordinaryCommentEventTitle
                && !$0.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix)
        }) else {
            NSLog("%@ seedOrdinaryComment failed: no persisted mirror titled %@", diag, ordinaryCommentEventTitle)
            return
        }
        let anchor = EventCommentAnchorPlan.anchor(forMirror: mine)
        // Author as the partner (any non-self id renders as "Partner") so it reads as
        // "partner commented on my event".
        let comment = services.commentService.createComment(
            eventMirrorID: anchor.key,
            authorMemberID: "_smoke_partner",
            body: body
        )
        modelContext.insert(comment)
        do {
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveCommentForSync(
                    comment,
                    eventOwnerMemberID: anchor.ownerMemberID,
                    currentMemberID: settings.currentMemberID,
                    eventRecordName: anchor.recordName
                )
            }
            NSLog("%@ seedOrdinaryComment succeeded mirror=%@ anchor=%@ body=%@", diag, mine.id, anchor.key, body)
        } catch {
            NSLog("%@ seedOrdinaryComment failed: %@", diag, String(describing: error))
        }
    }
}
