import CloudKit
import Foundation

enum CloudKitRecordMappingError: Error {
    case missingField(String)
}

struct CloudKitMemberProfile: Equatable {
    let ownerMemberID: String
    let displayName: String
    let updatedAt: Date
    var avatar: MemberAvatar? = nil
}

enum MemberProfileRecordMapper {
    static let recordType = "MemberProfile"

    enum Key {
        static let ownerMemberID = "ownerMemberID"
        static let displayName = "displayName"
        static let updatedAt = "updatedAt"
        static let avatarImage = "avatarImage"
        static let avatarText = "avatarText"
        static let avatarBackground = "avatarBackground"
        static let avatarKeys = [avatarImage, avatarText, avatarBackground]
    }

    static func recordName(ownerMemberID: String) -> String {
        "member-profile:\(normalizedRequired(ownerMemberID))"
    }

    static func record(
        from profile: CloudKitMemberProfile,
        zoneID: CKRecordZone.ID,
        parentRecordID: CKRecord.ID? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: recordName(ownerMemberID: profile.ownerMemberID),
            zoneID: zoneID
        )
        let record = existingRecord ?? CKRecord(recordType: recordType, recordID: recordID)
        CloudKitShareHierarchyPlan.attach(record, toShareRoot: parentRecordID)
        record[Key.ownerMemberID] = normalizedRequired(profile.ownerMemberID) as CKRecordValue
        record[Key.displayName] = normalizedDisplayName(profile.displayName) as CKRecordValue
        record[Key.updatedAt] = profile.updatedAt as CKRecordValue
        applyAvatar(profile.avatar, to: record)
        return record
    }

    /// Writes only the avatar keys whose value actually changed. The profile is re-saved on
    /// every paired sync, so this keeps the photo bytes from being re-uploaded each time, and
    /// a member without a custom avatar never sends the avatar fields at all (so an
    /// environment whose schema predates them keeps syncing names).
    static func applyAvatar(_ avatar: MemberAvatar?, to record: CKRecord) {
        let avatar = MemberAvatarPlan.normalized(avatar)
        let imageData = avatar?.imageData
        if (record[Key.avatarImage] as? Data) != imageData {
            record[Key.avatarImage] = imageData.map { $0 as NSData }
        }
        let text = avatar?.text
        if (record[Key.avatarText] as? String) != text {
            record[Key.avatarText] = text.map { $0 as NSString }
        }
        let background = avatar?.background?.rawValue
        if (record[Key.avatarBackground] as? String) != background {
            record[Key.avatarBackground] = background.map { $0 as NSString }
        }
    }

    static func avatar(from record: CKRecord) -> MemberAvatar? {
        MemberAvatarPlan.normalized(
            MemberAvatar(
                text: record[Key.avatarText] as? String,
                background: (record[Key.avatarBackground] as? String).flatMap(AvatarBackground.init(rawValue:)),
                imageData: record[Key.avatarImage] as? Data
            )
        )
    }

    static func memberProfile(from record: CKRecord) throws -> CloudKitMemberProfile {
        guard let ownerMemberID = record[Key.ownerMemberID] as? String else {
            throw CloudKitRecordMappingError.missingField(Key.ownerMemberID)
        }
        guard let displayName = record[Key.displayName] as? String else {
            throw CloudKitRecordMappingError.missingField(Key.displayName)
        }
        guard let updatedAt = record[Key.updatedAt] as? Date else {
            throw CloudKitRecordMappingError.missingField(Key.updatedAt)
        }
        return CloudKitMemberProfile(
            ownerMemberID: normalizedRequired(ownerMemberID),
            displayName: normalizedDisplayName(displayName),
            updatedAt: updatedAt,
            avatar: avatar(from: record)
        )
    }

    private static func normalizedRequired(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? value : trimmedValue
    }

    private static func normalizedDisplayName(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? "Partner" : trimmedValue
    }
}

enum MemberProfileDisplayPlan {
    static func partnerSyncedDisplayName(
        from profiles: [CloudKitMemberProfile],
        partnerID: String?
    ) -> String? {
        guard let partnerID = normalizedID(partnerID) else { return nil }
        return profiles
            .filter { profile in
                normalizedID(profile.ownerMemberID) == partnerID
                    && normalizedID(profile.displayName) != nil
            }
            .sorted {
                if $0.updatedAt == $1.updatedAt {
                    return $0.ownerMemberID < $1.ownerMemberID
                }
                return $0.updatedAt > $1.updatedAt
            }
            .first
            .map { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// The partner's own avatar from their newest profile record; nil when they never set one.
    static func partnerSyncedAvatar(
        from profiles: [CloudKitMemberProfile],
        partnerID: String?
    ) -> MemberAvatar? {
        guard let partnerID = normalizedID(partnerID) else { return nil }
        return profiles
            .filter { normalizedID($0.ownerMemberID) == partnerID }
            .max { $0.updatedAt < $1.updatedAt }
            .flatMap { MemberAvatarPlan.normalized($0.avatar) }
    }

    private static func normalizedID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

enum MemberProfileAvatarSchemaFallbackPlan {
    /// CloudKit rejects a write that introduces a field the Production schema doesn't have
    /// with `invalidArguments` (possibly wrapped in a `partialFailure`).
    static func shouldRetryWithoutAvatar(error: Error, profile: CloudKitMemberProfile) -> Bool {
        guard MemberAvatarPlan.normalized(profile.avatar) != nil else { return false }
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .invalidArguments { return true }
        if ckError.code == .partialFailure {
            return ckError.partialErrorsByItemID?.values.contains {
                ($0 as? CKError)?.code == .invalidArguments
            } ?? false
        }
        return false
    }
}

enum CloudKitBatchUpsertPlan {
    static func recordIDs(forMirrors mirrors: [EventMirror], zoneID: CKRecordZone.ID) -> [CKRecord.ID] {
        uniqued(
            mirrors.map { mirror in
                CKRecord.ID(recordName: mirror.cloudKitRecordName ?? mirror.mirrorKey, zoneID: zoneID)
            }
        )
    }

    static func recordIDs(forInvitations invitations: [EventInvitation], zoneID: CKRecordZone.ID) -> [CKRecord.ID] {
        uniqued(
            invitations.map { invitation in
                CKRecord.ID(recordName: invitation.cloudKitRecordName ?? invitation.id, zoneID: zoneID)
            }
        )
    }

    static func recordIDs(forAccessRequests requests: [CalendarAccessRequest], zoneID: CKRecordZone.ID) -> [CKRecord.ID] {
        uniqued(
            requests.map { request in
                CKRecord.ID(recordName: CalendarAccessRequestRecordMapper.recordName(for: request), zoneID: zoneID)
            }
        )
    }

    static func recordIDs(forComments comments: [EventComment], zoneID: CKRecordZone.ID) -> [CKRecord.ID] {
        uniqued(
            comments.map { comment in
                CKRecord.ID(recordName: comment.cloudKitRecordName ?? comment.id, zoneID: zoneID)
            }
        )
    }

    static func recordIDs(forMemberProfiles profiles: [CloudKitMemberProfile], zoneID: CKRecordZone.ID) -> [CKRecord.ID] {
        uniqued(
            profiles.map { profile in
                CKRecord.ID(
                    recordName: MemberProfileRecordMapper.recordName(ownerMemberID: profile.ownerMemberID),
                    zoneID: zoneID
                )
            }
        )
    }

    static func uniquedRecordIDs(_ recordIDs: [CKRecord.ID]) -> [CKRecord.ID] {
        var seen: Set<CKRecord.ID> = []
        return recordIDs.filter { seen.insert($0).inserted }
    }

    private static func uniqued(_ recordIDs: [CKRecord.ID]) -> [CKRecord.ID] {
        uniquedRecordIDs(recordIDs)
    }
}

enum CloudKitForegroundQueryPlan {
    static func desiredKeys(forRecordType recordType: String) -> [String]? {
        switch recordType {
        case EventMirrorRecordMapper.recordType:
            [
                EventMirrorRecordMapper.Key.ownerMemberID,
                EventMirrorRecordMapper.Key.mirrorKey,
                EventMirrorRecordMapper.Key.sourceCalendarID,
                EventMirrorRecordMapper.Key.sourceCalendarTitle,
                EventMirrorRecordMapper.Key.occurrenceStartDate,
                EventMirrorRecordMapper.Key.startDate,
                EventMirrorRecordMapper.Key.endDate,
                EventMirrorRecordMapper.Key.isAllDay,
                EventMirrorRecordMapper.Key.timeZoneIdentifier,
                EventMirrorRecordMapper.Key.title,
                EventMirrorRecordMapper.Key.location,
                EventMirrorRecordMapper.Key.notes,
                EventMirrorRecordMapper.Key.urlString,
                EventMirrorRecordMapper.Key.calendarColorHex,
                EventMirrorRecordMapper.Key.visibilityRawValue,
                EventMirrorRecordMapper.Key.deletedAt
            ]
        case InvitationRecordMapper.recordType:
            [
                InvitationRecordMapper.Key.creatorMemberID,
                InvitationRecordMapper.Key.inviteeMemberID,
                InvitationRecordMapper.Key.title,
                InvitationRecordMapper.Key.startDate,
                InvitationRecordMapper.Key.endDate,
                InvitationRecordMapper.Key.isAllDay,
                InvitationRecordMapper.Key.location,
                InvitationRecordMapper.Key.notes,
                InvitationRecordMapper.Key.statusRawValue,
                InvitationRecordMapper.Key.createdAt,
                InvitationRecordMapper.Key.updatedAt,
                InvitationRecordMapper.Key.createdLocalEventID
            ]
        case CommentRecordMapper.recordType:
            [
                CommentRecordMapper.Key.eventMirrorID,
                CommentRecordMapper.Key.authorMemberID,
                CommentRecordMapper.Key.body,
                CommentRecordMapper.Key.createdAt,
                CommentRecordMapper.Key.editedAt,
                CommentRecordMapper.Key.deletedAt,
                CommentRecordMapper.Key.isRead
            ]
        case MemberProfileRecordMapper.recordType:
            [
                MemberProfileRecordMapper.Key.ownerMemberID,
                MemberProfileRecordMapper.Key.displayName,
                MemberProfileRecordMapper.Key.updatedAt
            ] + MemberProfileRecordMapper.Key.avatarKeys
        default:
            nil
        }
    }
}

enum CloudKitRecordQueryFailurePlan {
    static func canTreatMissingRecordTypeAsEmpty(recordType: String, error: Error) -> Bool {
        recordType == MemberProfileRecordMapper.recordType && isMissingRecordType(error)
    }

    static func isMissingRecordType(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == CKError.errorDomain,
              CKError.Code(rawValue: nsError.code) == .unknownItem else {
            return false
        }

        let description = [
            nsError.localizedDescription,
            nsError.userInfo["ServerErrorDescription"] as? String,
            nsError.userInfo[NSDebugDescriptionErrorKey] as? String
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        return description.localizedCaseInsensitiveContains("Did not find record type")
    }
}

enum EventMirrorRecordMapper {
    static let recordType = "EventMirror"

    enum Key {
        static let ownerMemberID = "ownerMemberID"
        static let mirrorKey = "mirrorKey"
        static let sourceCalendarID = "sourceCalendarID"
        static let sourceCalendarTitle = "sourceCalendarTitle"
        static let occurrenceStartDate = "occurrenceStartDate"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let isAllDay = "isAllDay"
        static let timeZoneIdentifier = "timeZoneIdentifier"
        static let title = "title"
        static let location = "location"
        static let notes = "notes"
        static let urlString = "urlString"
        static let calendarColorHex = "calendarColorHex"
        static let visibilityRawValue = "visibilityRawValue"
        static let deletedAt = "deletedAt"
    }

    static func record(
        from mirror: EventMirror,
        zoneID: CKRecordZone.ID,
        parentRecordID: CKRecord.ID? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordName = mirror.cloudKitRecordName ?? mirror.mirrorKey
        let record = existingRecord ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        CloudKitShareHierarchyPlan.attach(record, toShareRoot: parentRecordID)
        record[Key.ownerMemberID] = mirror.ownerMemberID as CKRecordValue
        record[Key.mirrorKey] = mirror.mirrorKey as CKRecordValue
        record[Key.sourceCalendarID] = mirror.sourceCalendarID as CKRecordValue
        record[Key.sourceCalendarTitle] = mirror.sourceCalendarTitle as CKRecordValue
        record[Key.occurrenceStartDate] = mirror.occurrenceStartDate as CKRecordValue
        record[Key.startDate] = mirror.startDate as CKRecordValue
        record[Key.endDate] = mirror.endDate as CKRecordValue
        record[Key.isAllDay] = NSNumber(value: mirror.isAllDay)
        record[Key.timeZoneIdentifier] = mirror.timeZoneIdentifier as CKRecordValue
        record[Key.title] = mirror.title as CKRecordValue
        record[Key.location] = mirror.location as CKRecordValue?
        record[Key.notes] = mirror.notes as CKRecordValue?
        record[Key.urlString] = mirror.urlString as CKRecordValue?
        record[Key.calendarColorHex] = mirror.calendarColorHex as CKRecordValue
        record[Key.visibilityRawValue] = mirror.visibilityRawValue as CKRecordValue
        record[Key.deletedAt] = mirror.deletedAt as CKRecordValue?
        return record
    }

    static func eventMirror(from record: CKRecord) throws -> EventMirror {
        guard let ownerMemberID = record[Key.ownerMemberID] as? String else { throw CloudKitRecordMappingError.missingField(Key.ownerMemberID) }
        guard let mirrorKey = record[Key.mirrorKey] as? String else { throw CloudKitRecordMappingError.missingField(Key.mirrorKey) }
        guard let sourceCalendarID = record[Key.sourceCalendarID] as? String else { throw CloudKitRecordMappingError.missingField(Key.sourceCalendarID) }
        guard let sourceCalendarTitle = record[Key.sourceCalendarTitle] as? String else { throw CloudKitRecordMappingError.missingField(Key.sourceCalendarTitle) }
        guard let occurrenceStartDate = record[Key.occurrenceStartDate] as? Date else { throw CloudKitRecordMappingError.missingField(Key.occurrenceStartDate) }
        guard let startDate = record[Key.startDate] as? Date else { throw CloudKitRecordMappingError.missingField(Key.startDate) }
        guard let endDate = record[Key.endDate] as? Date else { throw CloudKitRecordMappingError.missingField(Key.endDate) }
        guard let timeZoneIdentifier = record[Key.timeZoneIdentifier] as? String else { throw CloudKitRecordMappingError.missingField(Key.timeZoneIdentifier) }
        guard let title = record[Key.title] as? String else { throw CloudKitRecordMappingError.missingField(Key.title) }
        guard let calendarColorHex = record[Key.calendarColorHex] as? String else { throw CloudKitRecordMappingError.missingField(Key.calendarColorHex) }
        guard let visibilityRawValue = record[Key.visibilityRawValue] as? String else { throw CloudKitRecordMappingError.missingField(Key.visibilityRawValue) }

        return EventMirror(
            id: mirrorKey,
            ownerMemberID: ownerMemberID,
            mirrorKey: mirrorKey,
            sourceCalendarID: sourceCalendarID,
            sourceCalendarTitle: sourceCalendarTitle,
            occurrenceStartDate: occurrenceStartDate,
            startDate: startDate,
            endDate: endDate,
            isAllDay: (record[Key.isAllDay] as? NSNumber)?.boolValue ?? false,
            timeZoneIdentifier: timeZoneIdentifier,
            title: title,
            location: record[Key.location] as? String,
            notes: record[Key.notes] as? String,
            urlString: record[Key.urlString] as? String,
            calendarColorHex: calendarColorHex,
            visibilityRawValue: visibilityRawValue,
            deletedAt: record[Key.deletedAt] as? Date,
            cloudKitRecordName: record.recordID.recordName
        )
    }
}

enum InvitationRecordMapper {
    static let recordType = "EventInvitation"

    enum Key {
        static let creatorMemberID = "creatorMemberID"
        static let inviteeMemberID = "inviteeMemberID"
        static let title = "title"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let isAllDay = "isAllDay"
        static let location = "location"
        static let notes = "notes"
        static let statusRawValue = "statusRawValue"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let createdLocalEventID = "createdLocalEventID"
    }

    static func record(
        from invitation: EventInvitation,
        zoneID: CKRecordZone.ID,
        parentRecordID: CKRecord.ID? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordName = invitation.cloudKitRecordName ?? invitation.id
        let record = existingRecord ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        CloudKitShareHierarchyPlan.attach(record, toShareRoot: parentRecordID)
        record[Key.creatorMemberID] = invitation.creatorMemberID as CKRecordValue
        record[Key.inviteeMemberID] = invitation.inviteeMemberID as CKRecordValue
        record[Key.title] = invitation.title as CKRecordValue
        record[Key.startDate] = invitation.startDate as CKRecordValue
        record[Key.endDate] = invitation.endDate as CKRecordValue
        record[Key.isAllDay] = NSNumber(value: invitation.isAllDay)
        record[Key.location] = invitation.location as CKRecordValue?
        record[Key.notes] = invitation.notes as CKRecordValue?
        record[Key.statusRawValue] = invitation.statusRawValue as CKRecordValue
        record[Key.createdAt] = invitation.createdAt as CKRecordValue
        record[Key.updatedAt] = invitation.updatedAt as CKRecordValue
        record[Key.createdLocalEventID] = invitation.createdLocalEventID as CKRecordValue?
        return record
    }

    static func invitation(from record: CKRecord) throws -> EventInvitation {
        guard let creatorMemberID = record[Key.creatorMemberID] as? String else { throw CloudKitRecordMappingError.missingField(Key.creatorMemberID) }
        guard let inviteeMemberID = record[Key.inviteeMemberID] as? String else { throw CloudKitRecordMappingError.missingField(Key.inviteeMemberID) }
        guard let title = record[Key.title] as? String else { throw CloudKitRecordMappingError.missingField(Key.title) }
        guard let startDate = record[Key.startDate] as? Date else { throw CloudKitRecordMappingError.missingField(Key.startDate) }
        guard let endDate = record[Key.endDate] as? Date else { throw CloudKitRecordMappingError.missingField(Key.endDate) }
        guard let isAllDayNumber = record[Key.isAllDay] as? NSNumber else { throw CloudKitRecordMappingError.missingField(Key.isAllDay) }
        guard let statusRawValue = record[Key.statusRawValue] as? String else { throw CloudKitRecordMappingError.missingField(Key.statusRawValue) }
        guard let createdAt = record[Key.createdAt] as? Date else { throw CloudKitRecordMappingError.missingField(Key.createdAt) }
        guard let updatedAt = record[Key.updatedAt] as? Date else { throw CloudKitRecordMappingError.missingField(Key.updatedAt) }

        return EventInvitation(
            id: record.recordID.recordName,
            creatorMemberID: creatorMemberID,
            inviteeMemberID: inviteeMemberID,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDayNumber.boolValue,
            location: record[Key.location] as? String,
            notes: record[Key.notes] as? String,
            statusRawValue: statusRawValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdLocalEventID: record[Key.createdLocalEventID] as? String,
            cloudKitRecordName: record.recordID.recordName
        )
    }
}

enum CalendarAccessRequestRecordMapper {
    static let transportRecordType = InvitationRecordMapper.recordType
    static let transportRecordNamePrefix = "history-access-request:"

    static func recordName(for request: CalendarAccessRequest) -> String {
        transportRecordName(from: request.cloudKitRecordName ?? request.id)
    }

    static func isTransportRecord(_ record: CKRecord) -> Bool {
        record.recordType == transportRecordType
            && record.recordID.recordName.hasPrefix(transportRecordNamePrefix)
    }

    private static func transportRecordName(from value: String) -> String {
        value.hasPrefix(transportRecordNamePrefix) ? value : "\(transportRecordNamePrefix)\(value)"
    }

    private static func requestID(fromTransportRecordName recordName: String) -> String {
        guard recordName.hasPrefix(transportRecordNamePrefix) else { return recordName }
        return String(recordName.dropFirst(transportRecordNamePrefix.count))
    }

    static func record(
        from request: CalendarAccessRequest,
        zoneID: CKRecordZone.ID,
        parentRecordID: CKRecord.ID? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordName = recordName(for: request)
        let record = existingRecord ?? CKRecord(recordType: transportRecordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        CloudKitShareHierarchyPlan.attach(record, toShareRoot: parentRecordID)
        record[InvitationRecordMapper.Key.creatorMemberID] = request.requesterMemberID as CKRecordValue
        record[InvitationRecordMapper.Key.inviteeMemberID] = request.ownerMemberID as CKRecordValue
        record[InvitationRecordMapper.Key.title] = "ShareCal History Access Request" as CKRecordValue
        record[InvitationRecordMapper.Key.startDate] = request.requestedStartDate as CKRecordValue
        record[InvitationRecordMapper.Key.endDate] = request.requestedEndDate as CKRecordValue
        record[InvitationRecordMapper.Key.isAllDay] = NSNumber(value: true)
        record[InvitationRecordMapper.Key.statusRawValue] = request.statusRawValue as CKRecordValue
        record[InvitationRecordMapper.Key.createdAt] = request.createdAt as CKRecordValue
        record[InvitationRecordMapper.Key.updatedAt] = request.updatedAt as CKRecordValue
        return record
    }

    static func request(from record: CKRecord) throws -> CalendarAccessRequest {
        guard let requesterMemberID = record[InvitationRecordMapper.Key.creatorMemberID] as? String else {
            throw CloudKitRecordMappingError.missingField(InvitationRecordMapper.Key.creatorMemberID)
        }
        guard let ownerMemberID = record[InvitationRecordMapper.Key.inviteeMemberID] as? String else {
            throw CloudKitRecordMappingError.missingField(InvitationRecordMapper.Key.inviteeMemberID)
        }
        guard let requestedStartDate = record[InvitationRecordMapper.Key.startDate] as? Date else {
            throw CloudKitRecordMappingError.missingField(InvitationRecordMapper.Key.startDate)
        }
        guard let requestedEndDate = record[InvitationRecordMapper.Key.endDate] as? Date else {
            throw CloudKitRecordMappingError.missingField(InvitationRecordMapper.Key.endDate)
        }
        guard let statusRawValue = record[InvitationRecordMapper.Key.statusRawValue] as? String else {
            throw CloudKitRecordMappingError.missingField(InvitationRecordMapper.Key.statusRawValue)
        }
        guard let createdAt = record[InvitationRecordMapper.Key.createdAt] as? Date else {
            throw CloudKitRecordMappingError.missingField(InvitationRecordMapper.Key.createdAt)
        }
        guard let updatedAt = record[InvitationRecordMapper.Key.updatedAt] as? Date else {
            throw CloudKitRecordMappingError.missingField(InvitationRecordMapper.Key.updatedAt)
        }

        return CalendarAccessRequest(
            id: requestID(fromTransportRecordName: record.recordID.recordName),
            requesterMemberID: requesterMemberID,
            ownerMemberID: ownerMemberID,
            requestedStartDate: requestedStartDate,
            requestedEndDate: requestedEndDate,
            statusRawValue: statusRawValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            cloudKitRecordName: record.recordID.recordName
        )
    }
}

enum CommentRecordMapper {
    static let recordType = "EventComment"

    enum Key {
        static let eventMirrorID = "eventMirrorID"
        static let authorMemberID = "authorMemberID"
        static let body = "body"
        static let createdAt = "createdAt"
        static let editedAt = "editedAt"
        static let deletedAt = "deletedAt"
        static let isRead = "isRead"
    }

    static func record(
        from comment: EventComment,
        zoneID: CKRecordZone.ID,
        parentRecordID: CKRecord.ID? = nil,
        existingRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordName = comment.cloudKitRecordName ?? comment.id
        let record = existingRecord ?? CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        CloudKitShareHierarchyPlan.attach(record, toShareRoot: parentRecordID)
        record[Key.eventMirrorID] = comment.eventMirrorID as CKRecordValue
        record[Key.authorMemberID] = comment.authorMemberID as CKRecordValue
        record[Key.body] = comment.body as CKRecordValue
        record[Key.createdAt] = comment.createdAt as CKRecordValue
        record[Key.editedAt] = comment.editedAt as CKRecordValue?
        record[Key.deletedAt] = comment.deletedAt as CKRecordValue?
        record[Key.isRead] = NSNumber(value: comment.isRead)
        return record
    }

    static func comment(from record: CKRecord) throws -> EventComment {
        guard let eventMirrorID = record[Key.eventMirrorID] as? String else { throw CloudKitRecordMappingError.missingField(Key.eventMirrorID) }
        guard let authorMemberID = record[Key.authorMemberID] as? String else { throw CloudKitRecordMappingError.missingField(Key.authorMemberID) }
        guard let body = record[Key.body] as? String else { throw CloudKitRecordMappingError.missingField(Key.body) }
        guard let createdAt = record[Key.createdAt] as? Date else { throw CloudKitRecordMappingError.missingField(Key.createdAt) }

        return EventComment(
            id: record.recordID.recordName,
            eventMirrorID: eventMirrorID,
            authorMemberID: authorMemberID,
            body: body,
            createdAt: createdAt,
            editedAt: record[Key.editedAt] as? Date,
            deletedAt: record[Key.deletedAt] as? Date,
            isRead: (record[Key.isRead] as? NSNumber)?.boolValue ?? false,
            cloudKitRecordName: record.recordID.recordName
        )
    }
}
