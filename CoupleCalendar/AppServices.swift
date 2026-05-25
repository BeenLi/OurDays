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
        guard !settings.selectedCalendarIDs.isEmpty else {
            settings.lastSyncError = "Select at least one calendar before syncing."
            settings.syncPhase = .failed
            return
        }

        settings.syncPhase = .syncing
        settings.lastSyncError = nil

        do {
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

            try upsert(mirrors: mirrors, modelContext: modelContext)
            if let cloudKit {
                cloudKit.queueMirrorsForSync(mirrors)
                try await cloudKit.foregroundSync()
            } else {
                settings.lastSyncError = "CloudKit sync is disabled in the Personal Team debug build."
            }

            settings.lastSyncAt = .now
            settings.syncPhase = .idle
        } catch {
            settings.lastSyncError = error.localizedDescription
            settings.syncPhase = .failed
        }
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
}
