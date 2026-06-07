import Foundation
import SwiftData

enum ShareCalAcceptedShareSignal {
    static let notificationName = Notification.Name("ShareCalAcceptedCloudKitShare")
    private static let pendingSyncKey = "ShareCalPendingAcceptedCloudKitShareSync"

    static func markAccepted(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(true, forKey: pendingSyncKey)
        notificationCenter.post(name: notificationName, object: nil)
    }

    static func consumePending(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: pendingSyncKey) else { return false }
        defaults.set(false, forKey: pendingSyncKey)
        return true
    }
}

enum EventVisibility: String, Codable, CaseIterable, Identifiable {
    case busyOnly
    case titleAndLocation
    case fullDetails
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .busyOnly: "Busy only"
        case .titleAndLocation: "Title + location"
        case .fullDetails: "Full details"
        case .hidden: "Hidden"
        }
    }
}

enum InvitationStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case declined
    case canceled

    var id: String { rawValue }
}

enum SyncPhase: String {
    case idle
    case syncing
    case failed
}

struct CalendarDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

enum ShareCalSmokeTestEventPlan {
    static let title = "ShareCal E2E Smoke Test"
    static let notes = "Created by ShareCal simulator validation."

    static func draft(now: Date = .now) -> LocalCalendarEventDraft {
        LocalCalendarEventDraft(
            title: title,
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(45 * 60),
            isAllDay: false,
            location: nil,
            notes: notes
        )
    }
}

enum ShareCalCalendarBootstrapPlan {
    static let calendarTitle = "ShareCal"
    static let calendarColorHex = "#FF2D55"

    static func shouldOfferCreation(calendars: [CalendarDescriptor]) -> Bool {
        !calendars.contains { calendar in
            isShareCalCalendar(calendar) && calendar.allowsContentModifications
        }
    }

    static func selectedCalendarIDs(
        afterEnsuring calendar: CalendarDescriptor,
        currentSelection: Set<String>
    ) -> Set<String> {
        var selection = currentSelection
        selection.insert(calendar.id)
        return selection
    }

    static func isShareCalCalendar(_ calendar: CalendarDescriptor) -> Bool {
        calendar.title.compare(calendarTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct CalendarSourceEvent: Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
    let startDate: Date
    let endDate: Date
    let occurrenceStartDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
}

struct LocalCalendarEventDraft: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

@Model
final class CoupleSpace {
    @Attribute(.unique) var id: String
    var schemaVersion: Int
    var createdAt: Date
    var ownerMemberID: String
    var cloudKitRecordName: String?
    var shareRecordName: String?

    init(
        id: String = UUID().uuidString,
        schemaVersion: Int = 1,
        createdAt: Date = .now,
        ownerMemberID: String,
        cloudKitRecordName: String? = nil,
        shareRecordName: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.ownerMemberID = ownerMemberID
        self.cloudKitRecordName = cloudKitRecordName
        self.shareRecordName = shareRecordName
    }
}

@Model
final class MemberProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    var avatarColorHex: String
    var iCloudUserRecordName: String?
    var lastSeenAt: Date?

    init(
        id: String = UUID().uuidString,
        displayName: String,
        avatarColorHex: String,
        iCloudUserRecordName: String? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
        self.iCloudUserRecordName = iCloudUserRecordName
        self.lastSeenAt = lastSeenAt
    }
}

@Model
final class EventMirror: Identifiable {
    @Attribute(.unique) var id: String
    var ownerMemberID: String
    var mirrorKey: String
    var sourceCalendarID: String
    var sourceCalendarTitle: String
    var occurrenceStartDate: Date
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var timeZoneIdentifier: String
    var title: String
    var location: String?
    var notes: String?
    var urlString: String?
    var calendarColorHex: String
    var visibilityRawValue: String
    var deletedAt: Date?
    var cloudKitRecordName: String?

    var visibility: EventVisibility {
        get { EventVisibility(rawValue: visibilityRawValue) ?? .fullDetails }
        set { visibilityRawValue = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        ownerMemberID: String,
        mirrorKey: String,
        sourceCalendarID: String,
        sourceCalendarTitle: String,
        occurrenceStartDate: Date,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        title: String,
        location: String?,
        notes: String?,
        urlString: String?,
        calendarColorHex: String,
        visibilityRawValue: String,
        deletedAt: Date?,
        cloudKitRecordName: String?
    ) {
        self.id = id
        self.ownerMemberID = ownerMemberID
        self.mirrorKey = mirrorKey
        self.sourceCalendarID = sourceCalendarID
        self.sourceCalendarTitle = sourceCalendarTitle
        self.occurrenceStartDate = occurrenceStartDate
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.title = title
        self.location = location
        self.notes = notes
        self.urlString = urlString
        self.calendarColorHex = calendarColorHex
        self.visibilityRawValue = visibilityRawValue
        self.deletedAt = deletedAt
        self.cloudKitRecordName = cloudKitRecordName
    }
}

@Model
final class LocalEventShadow {
    @Attribute(.unique) var id: String
    var localEventIdentifier: String
    var calendarIdentifier: String
    var occurrenceStartDate: Date
    var fingerprint: String
    var cloudKitRecordName: String
    var lastUploadedAt: Date?
    var isTombstone: Bool

    var mirrorKey: String {
        EventMirrorService.makeMirrorKey(
            calendarIdentifier: calendarIdentifier,
            eventIdentifier: localEventIdentifier,
            occurrenceStartDate: occurrenceStartDate,
            fingerprint: fingerprint
        )
    }

    init(
        id: String = UUID().uuidString,
        localEventIdentifier: String,
        calendarIdentifier: String,
        occurrenceStartDate: Date,
        fingerprint: String,
        cloudKitRecordName: String,
        lastUploadedAt: Date?,
        isTombstone: Bool
    ) {
        self.id = id
        self.localEventIdentifier = localEventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.occurrenceStartDate = occurrenceStartDate
        self.fingerprint = fingerprint
        self.cloudKitRecordName = cloudKitRecordName
        self.lastUploadedAt = lastUploadedAt
        self.isTombstone = isTombstone
    }
}

@Model
final class EventInvitation: Identifiable {
    @Attribute(.unique) var id: String
    var creatorMemberID: String
    var inviteeMemberID: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var createdLocalEventID: String?
    var cloudKitRecordName: String?

    var status: InvitationStatus {
        get { InvitationStatus(rawValue: statusRawValue) ?? .pending }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    init(
        id: String = UUID().uuidString,
        creatorMemberID: String,
        inviteeMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String?,
        notes: String?,
        statusRawValue: String = InvitationStatus.pending.rawValue,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdLocalEventID: String? = nil,
        cloudKitRecordName: String? = nil
    ) {
        self.id = id
        self.creatorMemberID = creatorMemberID
        self.inviteeMemberID = inviteeMemberID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdLocalEventID = createdLocalEventID
        self.cloudKitRecordName = cloudKitRecordName
    }
}

@Model
final class EventComment: Identifiable {
    @Attribute(.unique) var id: String
    var eventMirrorID: String
    var authorMemberID: String
    var body: String
    var createdAt: Date
    var editedAt: Date?
    var deletedAt: Date?
    var isRead: Bool
    var cloudKitRecordName: String?

    init(
        id: String = UUID().uuidString,
        eventMirrorID: String,
        authorMemberID: String,
        body: String,
        createdAt: Date = .now,
        editedAt: Date? = nil,
        deletedAt: Date? = nil,
        isRead: Bool = false,
        cloudKitRecordName: String? = nil
    ) {
        self.id = id
        self.eventMirrorID = eventMirrorID
        self.authorMemberID = authorMemberID
        self.body = body
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.isRead = isRead
        self.cloudKitRecordName = cloudKitRecordName
    }
}

@Model
final class SyncState {
    @Attribute(.unique) var id: String
    var privateDatabaseTokenData: Data?
    var sharedDatabaseTokenData: Data?
    var syncEngineStateData: Data?
    var lastSyncAt: Date?
    var lastErrorMessage: String?
    var pendingMutationCount: Int

    init(
        id: String = "default",
        privateDatabaseTokenData: Data? = nil,
        sharedDatabaseTokenData: Data? = nil,
        syncEngineStateData: Data? = nil,
        lastSyncAt: Date? = nil,
        lastErrorMessage: String? = nil,
        pendingMutationCount: Int = 0
    ) {
        self.id = id
        self.privateDatabaseTokenData = privateDatabaseTokenData
        self.sharedDatabaseTokenData = sharedDatabaseTokenData
        self.syncEngineStateData = syncEngineStateData
        self.lastSyncAt = lastSyncAt
        self.lastErrorMessage = lastErrorMessage
        self.pendingMutationCount = pendingMutationCount
    }
}

enum ShareCalModelContainer {
    static let schema = Schema([
        CoupleSpace.self,
        MemberProfile.self,
        EventMirror.self,
        LocalEventShadow.self,
        EventInvitation.self,
        EventComment.self,
        SyncState.self
    ])

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
