import Foundation
import SwiftData

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

enum CalendarAccessRequestStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case approved
    case declined

    var id: String { rawValue }
}

enum CalendarAccessRequestSource: String, Codable, CaseIterable, Identifiable {
    case localOutgoing
    case privateOwnerZone
    case acceptedSharedZone

    var id: String { rawValue }
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
        EventMirrorKeyPlan.makeMirrorKey(
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
    var archivedAt: Date?
    /// Local-only (never mapped to CloudKit / deployed schema). Set true when this
    /// device creates an invitation whose CloudKit upload is still in flight, so a
    /// failed/optimistic send self-heals on a later `foregroundSync` instead of being
    /// silently lost. Creator-only data lives in the creator's PRIVATE zone, which sync
    /// never reads back, so a local flag — not a cloud diff — is what tracks "uploaded".
    var needsCloudKitUpload: Bool = false

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
        cloudKitRecordName: String? = nil,
        archivedAt: Date? = nil,
        needsCloudKitUpload: Bool = false
    ) {
        self.id = id
        self.needsCloudKitUpload = needsCloudKitUpload
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
        self.archivedAt = archivedAt
    }
}

@Model
final class CalendarAccessRequest: Identifiable {
    @Attribute(.unique) var id: String
    var requesterMemberID: String
    var ownerMemberID: String
    var requestedStartDate: Date
    var requestedEndDate: Date
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var cloudKitRecordName: String?
    var sourceRawValue: String?

    var status: CalendarAccessRequestStatus {
        get { CalendarAccessRequestStatus(rawValue: statusRawValue) ?? .pending }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var source: CalendarAccessRequestSource {
        get { CalendarAccessRequestSource(rawValue: sourceRawValue ?? "") ?? .privateOwnerZone }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        requesterMemberID: String,
        ownerMemberID: String,
        requestedStartDate: Date,
        requestedEndDate: Date,
        statusRawValue: String = CalendarAccessRequestStatus.pending.rawValue,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        cloudKitRecordName: String? = nil,
        sourceRawValue: String? = nil
    ) {
        self.id = id
        self.requesterMemberID = requesterMemberID
        self.ownerMemberID = ownerMemberID
        self.requestedStartDate = requestedStartDate
        self.requestedEndDate = requestedEndDate
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cloudKitRecordName = cloudKitRecordName
        self.sourceRawValue = sourceRawValue
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

/// Insert-or-update an `EventMirror` by its `mirrorKey`. Mirrors are derived data
/// rebuilt every sync, so an existing row is overwritten field by field rather than
/// replaced (keeps the SwiftData identity stable for views holding a reference).
enum EventMirrorStore {
    static func upsert(_ mirror: EventMirror, modelContext: ModelContext) throws {
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
}

@MainActor
enum ShareCalLocalDataCleanupService {
    static func purge(modelContext: ModelContext) throws {
        try deleteAll(EventMirror.self, modelContext: modelContext)
        try deleteAll(LocalEventShadow.self, modelContext: modelContext)
        try deleteAll(EventComment.self, modelContext: modelContext)
        try deleteAll(EventInvitation.self, modelContext: modelContext)
        try deleteAll(CalendarAccessRequest.self, modelContext: modelContext)
        try modelContext.save()
    }

    static func purgeSharedOwnerMirrors(
        ownerMemberIDs: Set<String>,
        modelContext: ModelContext
    ) throws {
        guard !ownerMemberIDs.isEmpty else { return }

        let existingMirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
        var deletedMirrorIDs = Set<String>()
        for mirror in existingMirrors where ownerMemberIDs.contains(mirror.ownerMemberID) {
            deletedMirrorIDs.insert(mirror.id)
            modelContext.delete(mirror)
        }

        if !deletedMirrorIDs.isEmpty {
            let existingComments = try modelContext.fetch(FetchDescriptor<EventComment>())
            for comment in existingComments where deletedMirrorIDs.contains(comment.eventMirrorID) {
                modelContext.delete(comment)
            }
        }

        try modelContext.save()
    }

    static func purgeSharedOwnerData(
        ownerMemberIDs: Set<String>,
        modelContext: ModelContext
    ) throws {
        guard !ownerMemberIDs.isEmpty else { return }

        let existingMirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
        var deletedMirrorIDs = Set<String>()
        for mirror in existingMirrors where ownerMemberIDs.contains(mirror.ownerMemberID) {
            deletedMirrorIDs.insert(mirror.id)
            modelContext.delete(mirror)
        }

        if !deletedMirrorIDs.isEmpty {
            let existingComments = try modelContext.fetch(FetchDescriptor<EventComment>())
            for comment in existingComments where deletedMirrorIDs.contains(comment.eventMirrorID) {
                modelContext.delete(comment)
            }
        }

        let existingInvitations = try modelContext.fetch(FetchDescriptor<EventInvitation>())
        for invitation in existingInvitations
            where ownerMemberIDs.contains(invitation.creatorMemberID)
                || ownerMemberIDs.contains(invitation.inviteeMemberID) {
            modelContext.delete(invitation)
        }

        let existingAccessRequests = try modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())
        for request in existingAccessRequests
            where ownerMemberIDs.contains(request.requesterMemberID)
                || ownerMemberIDs.contains(request.ownerMemberID) {
            modelContext.delete(request)
        }

        try modelContext.save()
    }

    private static func deleteAll<Model: PersistentModel>(
        _ modelType: Model.Type,
        modelContext: ModelContext
    ) throws {
        let models = try modelContext.fetch(FetchDescriptor<Model>())
        for model in models {
            modelContext.delete(model)
        }
    }
}

enum ShareCalModelContainer {
    static let schema = Schema([
        MemberProfile.self,
        EventMirror.self,
        LocalEventShadow.self,
        EventInvitation.self,
        CalendarAccessRequest.self,
        EventComment.self
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
