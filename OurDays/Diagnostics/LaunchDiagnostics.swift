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
        #if DEBUG
        // First, so nothing later in this launch works on data about to be deleted.
        if ShareCalLaunchDiagnosticPolicy.shouldPurgeSmokeTestData(arguments: arguments) {
            do {
                let events = try services.calendarAccess.deleteLeftoverShareCalSmokeEvents()
                let records = try await services.cloudKit.purgeSmokeTestRecordsFromPrivateZone()
                NSLog("%@ purgeSmokeTestData succeeded records=%d events=%d", diag, records, events)
            } catch {
                NSLog("%@ purgeSmokeTestData failed: %@", diag, String(describing: error))
            }
        }
        if ShareCalLaunchDiagnosticPolicy.shouldHardDeleteOwnTombstones(arguments: arguments) {
            do {
                let records = try await services.cloudKit.hardDeleteOwnTombstonesForSmoke()
                NSLog("%@ hardDeleteOwnTombstones succeeded records=%d", diag, records)
            } catch {
                NSLog("%@ hardDeleteOwnTombstones failed: %@", diag, String(describing: error))
            }
        }
        #endif

        if ShareCalLaunchDiagnosticPolicy.shouldSeedCalendarEvent(arguments: arguments) {
            do {
                let eventID = try services.calendarAccess.ensureShareCalSmokeTestEvent(
                    draft: ShareCalLaunchDiagnosticPolicy.seedCalendarEventDraft(arguments: arguments)
                )
                NSLog("ShareCal seeded calendar event: \(eventID)")
            } catch {
                NSLog("ShareCal failed to seed calendar event: \(error)")
            }
        }

        if let title = ShareCalLaunchDiagnosticPolicy.deleteCalendarEventTitle(arguments: arguments) {
            do {
                let count = try services.calendarAccess.deleteShareCalEvents(titled: title)
                NSLog("%@ deleteCalendarEvent succeeded title=%@ count=%d", diag, title, count)
            } catch {
                NSLog("%@ deleteCalendarEvent failed: %@", diag, String(describing: error))
            }
        }

        if let title = ShareCalLaunchDiagnosticPolicy.moveCalendarEventTitle(arguments: arguments) {
            do {
                let count = try services.calendarAccess.moveShareCalEventsOneHourLater(titled: title)
                NSLog("%@ moveCalendarEvent succeeded title=%@ count=%d", diag, title, count)
            } catch {
                NSLog("%@ moveCalendarEvent failed: %@", diag, String(describing: error))
            }
        }

        if let prefix = ShareCalLaunchDiagnosticPolicy.dumpEventIdentifiersTitlePrefix(arguments: arguments) {
            let now = Date()
            let events = services.calendarAccess.authorizedEvents(
                from: now.addingTimeInterval(-60 * 86_400),
                to: now.addingTimeInterval(365 * 86_400)
            )
            let lines = ShareCalLaunchDiagnosticPolicy.eventIdentifierLines(events, titlePrefix: prefix)
            NSLog("%@ dumpEventIdentifiers prefix=%@ count=%d", diag, prefix, lines.count)
            for line in lines {
                NSLog("%@ eventIdentifiers %@", diag, line)
            }
        }

        if let title = ShareCalLaunchDiagnosticPolicy.seedDailySeriesTitle(arguments: arguments) {
            do {
                let eventID = try services.calendarAccess.ensureShareCalDailySeries(titled: title)
                NSLog("%@ seedDailySeries succeeded title=%@ id=%@", diag, title, eventID)
            } catch {
                NSLog("%@ seedDailySeries failed: %@", diag, String(describing: error))
            }
        }

        if let title = ShareCalLaunchDiagnosticPolicy.moveSeriesTitle(arguments: arguments) {
            let fromOccurrence = ShareCalLaunchDiagnosticPolicy.moveSeriesFromOccurrence(arguments: arguments)
            do {
                if let moved = try services.calendarAccess.moveShareCalSeriesOneHourLater(
                    titled: title,
                    fromOccurrence: fromOccurrence
                ) {
                    NSLog(
                        "%@ moveSeries succeeded title=%@ from=%d before=[%@] after=[%@]",
                        diag, title, fromOccurrence,
                        moved.before.joined(separator: " "), moved.after.joined(separator: " ")
                    )
                } else {
                    NSLog("%@ moveSeries failed: no occurrence %d titled '%@'", diag, fromOccurrence, title)
                }
            } catch {
                NSLog("%@ moveSeries failed: %@", diag, String(describing: error))
            }
        }

        if let title = ShareCalLaunchDiagnosticPolicy.deleteSeriesTitle(arguments: arguments) {
            do {
                let count = try services.calendarAccess.deleteShareCalSeries(titled: title)
                NSLog("%@ deleteSeries succeeded title=%@ count=%d", diag, title, count)
            } catch {
                NSLog("%@ deleteSeries failed: %@", diag, String(describing: error))
            }
        }

        if ShareCalLaunchDiagnosticPolicy.shouldRunCloudKitWriteProbe(arguments: arguments) {
            await services.cloudKit.runPrivateDatabaseWriteProbe()
        }

        if ShareCalLaunchDiagnosticPolicy.shouldRunSharedReadProbe(arguments: arguments) {
            let diagnostic = await services.cloudKit.sharedReadDiagnostic()
            NSLog("ShareCal shared read probe:\n\(diagnostic.displayText)")
            NSLog("ShareCal shared read probe proves no access: \(diagnostic.provesNoSharedCalendarReadAccess)")
        }

        if ShareCalLaunchDiagnosticPolicy.shouldRunStopSharingProbe(arguments: arguments) {
            do {
                try await services.cloudKit.stopSharing(ownerMemberID: settings.currentMemberID)
                NSLog("ShareCal stop sharing probe succeeded")
            } catch {
                NSLog("ShareCal stop sharing probe failed: \(error)")
            }
        }

        if ShareCalLaunchDiagnosticPolicy.shouldPreparePairingShare(arguments: arguments) {
            do {
                if !settings.hasSyncedMemberID {
                    settings.currentMemberID = try await services.cloudKit.fetchCurrentUserRecordID()
                }
                if PairingSettingsPolicy.normalizedDisplayName(settings.currentDisplayName) == nil {
                    settings.currentDisplayName = PairingSettingsPolicy.randomDisplayName()
                    settings.hasCompletedInitialProfilePrompt = true
                }
                let preparedShare = try await services.cloudKit.prepareShare(ownerMemberID: settings.currentMemberID)
                try await services.cloudKit.saveMemberProfileForSync(
                    ownerMemberID: settings.currentMemberID,
                    displayName: settings.currentDisplayName,
                    localUpdatedAt: settings.currentProfileUpdatedAt
                )
                settings.iCloudSharingEnabled = true
                settings.hasStartedPairing = true
                settings.markPairingDateIfNeeded()
                NSLog(
                    "%@ %@",
                    ShareCalLaunchDiagnosticPolicy.pairingShareURLLogPrefix,
                    preparedShare.share.url?.absoluteString ?? "missing"
                )
            } catch {
                NSLog("ShareCal prepare pairing share probe failed: \(error)")
            }
        }

        if let shareURL = ShareCalLaunchDiagnosticPolicy.acceptShareURL(arguments: arguments) {
            do {
                let metadata = try await services.cloudKit.fetchShareMetadata(from: shareURL)
                ShareCalCloudKitShareAcceptanceHandler.handle(metadata: metadata)
                NSLog("ShareCal accept share probe handled metadata owner=%@", metadata.share.recordID.zoneID.ownerName)
            } catch {
                NSLog("ShareCal accept share probe failed: \(error)")
            }
        }

        await runShareAccessRequestDiagnostics(services: services, arguments: arguments)

        if ShareCalLaunchDiagnosticPolicy.shouldForceSync(arguments: arguments) {
            // Reuses the accepted-share signal channel: RootView consumes it and
            // runs a foreground sync that bypasses the automatic-sync throttle.
            ShareCalAcceptedShareSignal.markAccepted(partnerOwnerID: nil)
        }

        // Joint-event / comment smoke flow. Each handler that needs current data runs
        // its own direct foreground sync (the force-sync signal above is consumed by
        // RootView asynchronously, so it can't be relied on within this task).
        if ShareCalLaunchDiagnosticPolicy.shouldRecoverExistingICloudData(arguments: arguments) {
            await recoverExistingICloudData(services: services, settings: settings, modelContext: modelContext)
        }
        if ShareCalLaunchDiagnosticPolicy.shouldSeedInvitation(arguments: arguments) {
            await seedInvitation(services: services, settings: settings, modelContext: modelContext, arguments: arguments)
        }
        if ShareCalLaunchDiagnosticPolicy.shouldAcceptInvitation(arguments: arguments) {
            await acceptInvitation(services: services, settings: settings, modelContext: modelContext)
        }
        if let invitationID = ShareCalLaunchDiagnosticPolicy.withdrawInvitationID(arguments: arguments) {
            await withdrawInvitation(id: invitationID, services: services, settings: settings, modelContext: modelContext)
        }
        if ShareCalLaunchDiagnosticPolicy.shouldProbeInvitations(arguments: arguments) {
            await probeInvitations(services: services, settings: settings, modelContext: modelContext)
        }
        if let body = ShareCalLaunchDiagnosticPolicy.jointCommentBody(arguments: arguments) {
            await addJointComment(body: body, services: services, settings: settings, modelContext: modelContext)
        }
        if ShareCalLaunchDiagnosticPolicy.shouldProbeJointComments(arguments: arguments) {
            await probeJointComments(services: services, settings: settings, modelContext: modelContext)
        }
        if let body = ShareCalLaunchDiagnosticPolicy.ordinaryCommentBody(arguments: arguments) {
            await seedOrdinaryComment(body: body, services: services, settings: settings, modelContext: modelContext)
        }
        if let body = ShareCalLaunchDiagnosticPolicy.eventCommentBody(arguments: arguments) {
            await addEventComment(
                body: body,
                title: ShareCalLaunchDiagnosticPolicy.eventCommentTitle(arguments: arguments),
                occurrence: ShareCalLaunchDiagnosticPolicy.eventCommentOccurrence(arguments: arguments),
                services: services, settings: settings, modelContext: modelContext
            )
        }
        if let edit = ShareCalLaunchDiagnosticPolicy.editEventComment(arguments: arguments) {
            await editEventComment(
                from: edit.from,
                to: edit.to,
                title: ShareCalLaunchDiagnosticPolicy.eventCommentTitle(arguments: arguments),
                services: services, settings: settings, modelContext: modelContext
            )
        }
        if let body = ShareCalLaunchDiagnosticPolicy.deleteEventCommentBody(arguments: arguments) {
            await deleteEventComment(
                body: body,
                title: ShareCalLaunchDiagnosticPolicy.eventCommentTitle(arguments: arguments),
                services: services, settings: settings, modelContext: modelContext
            )
        }
        if ShareCalLaunchDiagnosticPolicy.shouldProbeEventComments(arguments: arguments) {
            await probeEventComments(
                title: ShareCalLaunchDiagnosticPolicy.eventCommentTitle(arguments: arguments),
                occurrence: ShareCalLaunchDiagnosticPolicy.eventCommentOccurrence(arguments: arguments),
                services: services, settings: settings, modelContext: modelContext
            )
        }
    }

    private static let diag = ShareCalLaunchDiagnosticPolicy.diagnosticLogPrefix

    /// Share access requests: request (partner), list and approve (owner), in that order.
    private static func runShareAccessRequestDiagnostics(services: AppServices, arguments: [String]) async {
        let requestURL = ShareCalLaunchDiagnosticPolicy.requestShareAccessURL(arguments: arguments)
        let list = ShareCalLaunchDiagnosticPolicy.shouldListShareRequesters(arguments: arguments)
        let approve = ShareCalLaunchDiagnosticPolicy.shouldApproveShareRequesters(arguments: arguments)
        guard requestURL != nil || list || approve else { return }
        #if compiler(>=6.2)
        guard #available(iOS 26.0, macCatalyst 26.0, *) else {
            NSLog("%@ shareAccessRequests failed: needs iOS 26", diag)
            return
        }
        if let requestURL {
            let before = await services.cloudKit.shareMetadataAccessDescription(url: requestURL)
            NSLog("%@ shareMetadata before request %@", diag, before)
            do {
                try await services.cloudKit.requestShareAccess(url: requestURL)
                NSLog("%@ requestShareAccess succeeded", diag)
            } catch {
                NSLog("%@ requestShareAccess failed: %@", diag, describeCloudKitFailure(error))
            }
        }
        if list {
            do {
                let state = try await services.cloudKit.outgoingShareAccessState()
                NSLog("%@ shareRequesters %@", diag, state?.logDescription ?? "share=missing")
            } catch {
                NSLog("%@ shareRequesters failed: %@", diag, describeCloudKitFailure(error))
            }
        }
        if approve {
            do {
                let added = try await services.cloudKit.approveShareRequesters()
                let state = try await services.cloudKit.outgoingShareAccessState()
                NSLog("%@ approveShareRequesters succeeded added=%d after: %@", diag, added, state?.logDescription ?? "share=missing")
            } catch {
                NSLog("%@ approveShareRequesters failed: %@", diag, describeCloudKitFailure(error))
            }
        }
        #else
        NSLog("%@ shareAccessRequests failed: built without the iOS 26 SDK", diag)
        #endif
    }

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
        // The newest one, the same on both devices: accepted invitations from earlier
        // runs pile up, and an unordered pick let the two sides open different threads.
        return all
            .filter { $0.status == .accepted && $0.archivedAt == nil }
            .max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Owner side: create an invitation matching the owner's already-seeded smoke event
    /// (so the title/date fallback in `localEventExists` keeps it from being auto-canceled
    /// once the partner's acceptance syncs back), then upload it.
    private static func seedInvitation(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext, arguments: [String]
    ) async {
        do {
            _ = try? services.calendarAccess.ensureShareCalSmokeTestEvent()
            let title = ShareCalLaunchDiagnosticPolicy.seedInvitationTitle(arguments: arguments)
                ?? ShareCalSmokeTestEventPolicy.title
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
        guard InvitationInteractionPolicy.canWithdraw(invitation, currentMemberID: settings.currentMemberID) else {
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
    /// it (routed by `EventCommentAnchorPolicy`), and upload.
    private static func addJointComment(
        body: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        guard let invitation = acceptedInvitation(in: modelContext) else {
            NSLog("%@ addJointComment failed: no accepted invitation", diag)
            return
        }
        let anchor = EventCommentAnchorPolicy.anchor(forInvitation: invitation)
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
        let anchor = EventCommentAnchorPolicy.anchor(forInvitation: invitation)
        let comments = ((try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? [])
            .filter { $0.eventMirrorID == anchor.key && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let bodies = comments.map(\.body).joined(separator: "|")
        NSLog("%@ jointComments count=%d bodies=[%@]", diag, comments.count, bodies)
    }

    /// Either side: comment on the event with the given title. On the owner the event is
    /// found in EventKit and opened exactly like the calendar does — as a transient display
    /// mirror run through `EventDetailCommentPolicy` — so the comment is keyed by the mirrorKey
    /// whether or not the mirror has synced yet (that is the "start a thread on my own event"
    /// path). On the partner there is no such EventKit event, so the imported persisted mirror
    /// is used and the write routes into the owner's shared zone. A sync follows the upload so
    /// an unsynced own mirror lands too and the partner can find the event.
    private static func addEventComment(
        body: String, title: String, occurrence: Int?,
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        let persisted = (try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? []
        let selectedCalendarIDs = settings.selectedCalendarIDs
        let now = Date.now
        let ownEvents = services.calendarAccess.authorizedEvents(
            from: now.addingTimeInterval(-7 * 86_400),
            to: now.addingTimeInterval(7 * 86_400)
        ).filter { selectedCalendarIDs.contains($0.calendarIdentifier) && $0.title == title }
        let displayMirrors = pick(
            CalendarDisplayMirrorPolicy.displayMirrors(from: ownEvents, ownerMemberID: settings.currentMemberID),
            occurrence: occurrence
        )

        let anchor: EventCommentAnchor
        let resolution: String
        if let display = displayMirrors.first {
            let sharingWindows = CalendarSharingWindowPolicy.effectiveWindows(
                now: settings.pairingDate ?? PairingDatePolicy.normalizedPairingDate(now),
                accessRequests: (try? modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())) ?? []
            )
            switch EventDetailCommentPolicy.availability(for: display, mirrors: persisted, sharingWindows: sharingWindows) {
            case .available(let resolved):
                anchor = resolved
                let twin = EventDetailMirrorResolutionPolicy.persistedTwin(for: display, in: persisted)
                resolution = "own twin=\(twin?.id ?? "none")"
            case .notSharedWithPartner:
                NSLog("%@ addEventComment failed: own event '%@' is outside the sharing windows", diag, title)
                return
            }
        } else if let mirror = pick(
            persisted.filter {
                $0.deletedAt == nil && $0.title == title && !$0.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix)
            },
            occurrence: occurrence
        ).first {
            anchor = EventCommentAnchorPolicy.anchor(forMirror: mirror)
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

    /// Either side: delete my comment with the given body on the persisted mirror with the
    /// given title, exactly like the swipe in `EventCommentsSection`, then sync.
    private static func deleteEventComment(
        body: String, title: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let mirrors = (try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? []
        guard let mirror = mirrors.first(where: {
            $0.deletedAt == nil && $0.title == title && !$0.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix)
        }) else {
            NSLog("%@ deleteEventComment failed: no persisted mirror titled '%@'", diag, title)
            return
        }
        let anchor = EventCommentAnchorPolicy.anchor(forMirror: mirror)
        let comments = (try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? []
        guard let comment = comments.first(where: {
            $0.eventMirrorID == anchor.key && $0.body == body && $0.deletedAt == nil
        }) else {
            NSLog("%@ deleteEventComment failed: no live comment '%@' on '%@'", diag, body, title)
            return
        }
        guard CommentDeletionPolicy.canDelete(comment, currentMemberID: settings.currentMemberID) else {
            NSLog("%@ deleteEventComment failed: not the author of '%@'", diag, body)
            return
        }
        services.commentService.delete(comment)
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
            NSLog("%@ deleteEventComment failed: %@", diag, String(describing: error))
            return
        }
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let stillDeleted = (try? modelContext.fetch(FetchDescriptor<EventComment>()))?
            .first(where: { $0.id == comment.id })?.deletedAt != nil
        NSLog("%@ deleteEventComment succeeded title=%@ body=%@ stillDeletedAfterSync=%@",
              diag, title, body, stillDeleted ? "true" : "false")
    }

    /// Either side: edit my comment with body `from` to `to` on the persisted mirror with
    /// the given title, exactly like saving from the composer in `EventCommentsSection`,
    /// then sync and check the import kept the new body.
    private static func editEventComment(
        from: String, to: String, title: String,
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let mirrors = (try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? []
        guard let mirror = mirrors.first(where: {
            $0.deletedAt == nil && $0.title == title && !$0.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix)
        }) else {
            NSLog("%@ editEventComment failed: no persisted mirror titled '%@'", diag, title)
            return
        }
        let anchor = EventCommentAnchorPolicy.anchor(forMirror: mirror)
        let comments = (try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? []
        guard let comment = comments.first(where: {
            $0.eventMirrorID == anchor.key && $0.body == from && $0.deletedAt == nil
        }) else {
            NSLog("%@ editEventComment failed: no live comment '%@' on '%@'", diag, from, title)
            return
        }
        guard CommentEditPolicy.canEdit(comment, currentMemberID: settings.currentMemberID),
              let newBody = CommentEditPolicy.editedBody(original: comment.body, draft: to)
        else {
            NSLog("%@ editEventComment failed: not the author of '%@' or nothing to change", diag, from)
            return
        }
        services.commentService.edit(comment, body: newBody)
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
            NSLog("%@ editEventComment failed: %@", diag, String(describing: error))
            return
        }
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let afterSync = (try? modelContext.fetch(FetchDescriptor<EventComment>()))?
            .first(where: { $0.id == comment.id })
        let keptEdit = afterSync?.body == newBody && afterSync?.editedAt != nil
        NSLog("%@ editEventComment succeeded title=%@ from=%@ to=%@ keptEditAfterSync=%@",
              diag, title, from, newBody, keptEdit ? "true" : "false")
    }

    /// Either side: sync, then log the thread of the persisted mirror with the given title.
    private static func probeEventComments(
        title: String, occurrence: Int?,
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let mirrors = (try? modelContext.fetch(FetchDescriptor<EventMirror>())) ?? []
        guard let mirror = pick(
            mirrors.filter {
                $0.deletedAt == nil && $0.title == title && !$0.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix)
            },
            occurrence: occurrence
        ).first else {
            NSLog("%@ eventComments title=%@ count=0 (no persisted mirror)", diag, title)
            return
        }
        let anchor = EventCommentAnchorPolicy.anchor(forMirror: mirror)
        let comments = ((try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? [])
            .filter { $0.eventMirrorID == anchor.key && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let bodies = comments.map(\.body).joined(separator: "|")
        let edited = comments.filter { $0.editedAt != nil }.map(\.body).joined(separator: "|")
        NSLog(
            "%@ eventComments title=%@ count=%d bodies=[%@] edited=[%@] key=%@",
            diag, title, comments.count, bodies, edited, anchor.key
        )
    }

    /// The mirrors as they are, or only the `occurrence`-th in start order (none when
    /// there are fewer), for the events of a series, which share a title.
    private static func pick(_ mirrors: [EventMirror], occurrence: Int?) -> [EventMirror] {
        guard let occurrence else { return mirrors }
        let sorted = mirrors.sorted { $0.startDate < $1.startDate }
        return sorted.indices.contains(occurrence) ? [sorted[occurrence]] : []
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
                && !$0.id.hasPrefix(CalendarDisplayMirrorPolicy.transientIDPrefix)
        }) else {
            NSLog("%@ seedOrdinaryComment failed: no persisted mirror titled %@", diag, ordinaryCommentEventTitle)
            return
        }
        let anchor = EventCommentAnchorPolicy.anchor(forMirror: mine)
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
