import Foundation
import Observation
import SwiftData

@Observable
final class SettingsStore {
    var currentMemberID: String {
        didSet { defaults.set(currentMemberID, forKey: Key.currentMemberID) }
    }
    var partnerMemberID: String {
        didSet { defaults.set(partnerMemberID, forKey: Key.partnerMemberID) }
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
        currentMemberID = defaults.string(forKey: Key.currentMemberID) ?? "me"
        partnerMemberID = defaults.string(forKey: Key.partnerMemberID) ?? "partner"
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

    private enum Key {
        static let currentMemberID = "currentMemberID"
        static let partnerMemberID = "partnerMemberID"
        static let selectedCalendarIDs = "selectedCalendarIDs"
        static let defaultVisibility = "defaultVisibility"
        static let lastSyncAt = "lastSyncAt"
    }
}

extension SettingsStore {
    var strings: ShareCalStrings {
        ShareCalStrings(language: appLanguage)
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

    func foregroundSync(modelContext: ModelContext, settings: SettingsStore) async {
        settings.syncPhase = .syncing
        settings.lastSyncError = nil

        do {
            let syncedAt = Date()
            if settings.selectedCalendarIDs.isEmpty {
                let calendar = try calendarAccess.ensureShareCalCalendar()
                settings.selectedCalendarIDs = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
                    afterEnsuring: calendar,
                    currentSelection: settings.selectedCalendarIDs
                )
            }

            let window = CalendarAccessService.defaultSyncWindow()
            let sourceEvents = calendarAccess.events(
                from: window.start,
                to: window.end,
                selectedCalendarIDs: settings.selectedCalendarIDs
            )
            let mirrors = eventMirrorService.makeMirrors(
                from: sourceEvents,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                ownerMemberID: settings.currentMemberID,
                visibility: settings.defaultVisibility
            )
            let activeShadows = eventMirrorService.makeShadows(
                from: sourceEvents,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                uploadedAt: syncedAt
            )
            let currentMirrorKeys = Set(mirrors.map(\.mirrorKey))
            let existingShadows = try modelContext.fetch(FetchDescriptor<LocalEventShadow>())
            let deletedShadows = eventMirrorService.deletedShadows(
                existingEventKeys: currentMirrorKeys,
                shadows: existingShadows,
                selectedCalendarIDs: settings.selectedCalendarIDs,
                syncWindow: window
            )
            let existingLocalMirrors = try localMirrors(
                ownerMemberID: settings.currentMemberID,
                modelContext: modelContext
            )
            let deletedMirrorsFromShadows = eventMirrorService.deletedMirrorTombstones(
                for: deletedShadows,
                existingMirrors: existingLocalMirrors,
                deletedAt: syncedAt
            )
            let deletedMirrorsFromExistingLocalState = eventMirrorService.deletedMirrorTombstones(
                existingEventKeys: currentMirrorKeys,
                existingMirrors: existingLocalMirrors,
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

            try upsert(mirrors: mirrorsForSync, modelContext: modelContext)
            try upsert(shadows: activeShadows + deletedShadows, modelContext: modelContext)
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
            if let cloudKit {
                try await cloudKit.ensureShareRoot(ownerMemberID: settings.currentMemberID)
                try await cloudKit.saveMirrorsForSync(mirrorsForSync)
                for invitation in canceledInvitations {
                    try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                }
                try await cloudKit.foregroundSync()
                let sharedMirrors = try await cloudKit.fetchSharedEventMirrors()
                let importableSharedMirrors = CloudKitSharedDatabaseImportPlan.localizedMirrors(
                    sharedMirrors,
                    partnerMemberID: settings.partnerMemberID
                )
                try upsert(mirrors: importableSharedMirrors, modelContext: modelContext)
                let cloudComments = try await cloudKit.fetchEventComments()
                try upsert(comments: cloudComments, modelContext: modelContext)
                let cloudInvitations = try await cloudKit.fetchEventInvitations()
                try upsert(invitations: cloudInvitations, modelContext: modelContext)
            } else {
                settings.lastSyncError = settings.strings.cloudKitSyncDisabledLocalBuild
            }

            settings.lastSyncAt = .now
            settings.syncPhase = .idle
        } catch {
            settings.lastSyncError = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            settings.syncPhase = .failed
        }
    }

    private func localMirrors(ownerMemberID: String, modelContext: ModelContext) throws -> [EventMirror] {
        let descriptor = FetchDescriptor<EventMirror>(
            predicate: #Predicate { $0.ownerMemberID == ownerMemberID }
        )
        return try modelContext.fetch(descriptor)
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
}
