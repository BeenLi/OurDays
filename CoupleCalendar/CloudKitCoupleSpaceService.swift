@preconcurrency import CloudKit
import Foundation
import OSLog
import SwiftUI
import UIKit

private let cloudKitSharingLogger = Logger(
    subsystem: "com.leeberty.CoupleCalendar",
    category: "CloudKitSharing"
)

private func cloudKitSharingInfo(_ message: String) {
    #if DEBUG
    print("[CloudKitSharing] \(message)")
    #endif
    cloudKitSharingLogger.info("\(message, privacy: .public)")
}

private func cloudKitSharingError(_ message: String) {
    #if DEBUG
    print("[CloudKitSharing][error] \(message)")
    #endif
    cloudKitSharingLogger.error("\(message, privacy: .public)")
}

private func describeCloudKitFailure(_ error: Error) -> String {
    let nsError = error as NSError
    var parts = [
        "domain=\(nsError.domain)",
        "code=\(nsError.code)",
        "localized=\(nsError.localizedDescription)"
    ]

    if let ckError = error as? CKError {
        parts.append("ckCode=\(ckError.code)")
    }

    let userInfo = nsError.userInfo
        .compactMap { key, value -> String? in
            let keyDescription = "\(key)"
            if keyDescription == "CKDHTTPHeaders" {
                let headers = value as? [AnyHashable: Any]
                let requestUUID = headers?["x-apple-request-uuid"] ?? "missing"
                return "x-apple-request-uuid=\(requestUUID)"
            }
            return "\(keyDescription)=\(value)"
        }
        .sorted()
        .joined(separator: "; ")
    if !userInfo.isEmpty {
        parts.append("userInfo={\(userInfo)}")
    }

    if let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
        let described = partialErrors
            .map { "\($0.key)=\(describeCloudKitFailure($0.value))" }
            .sorted()
            .joined(separator: "; ")
        parts.append("partialErrors={\(described)}")
    }

    return parts.joined(separator: " | ")
}

enum CloudKitRootLookupPolicy {
    static func shouldCreateRootAfterLookupFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == CKError.errorDomain else { return false }

        switch CKError.Code(rawValue: nsError.code) {
        case .unknownItem, .serverRejectedRequest:
            return true
        default:
            return false
        }
    }
}

enum CloudKitShareRootState {
    case existing
    case created
}

enum CloudKitShareSaveStep: Equatable {
    case saveRootBeforeCreatingShare
    case saveShare
}

enum CloudKitShareSavePlan {
    static func steps(rootState: CloudKitShareRootState) -> [CloudKitShareSaveStep] {
        switch rootState {
        case .existing:
            [.saveShare]
        case .created:
            [.saveRootBeforeCreatingShare, .saveShare]
        }
    }
}

enum CloudKitContainerDiagnosticPlan {
    static func displayIdentifier(runtimeIdentifier: String?, fallbackIdentifier: String) -> String {
        runtimeIdentifier ?? fallbackIdentifier
    }
}

enum CloudKitExpectedConfigurationPlan {
    static var containerEnvironment: String {
        #if DEBUG
        "Development"
        #else
        "Production"
        #endif
    }
}

enum CloudKitShareAcceptancePlan {
    static func containerIdentifier(metadataContainerIdentifier: String?, fallbackIdentifier: String) -> String {
        metadataContainerIdentifier ?? fallbackIdentifier
    }
}

enum ShareCalCloudKitShareAcceptanceHandler {
    static func accept(metadata: CKShare.Metadata) {
        Task {
            do {
                try await CloudKitCoupleSpaceService().acceptShare(metadata: metadata)
                ShareCalAcceptedShareSignal.markAccepted(
                    partnerICloudEmailAddress: CloudKitShareParticipantIdentityPlan.ownerEmailAddress(from: metadata)
                )
            } catch {
                NSLog("ShareCal failed to accept CloudKit share: \(error)")
            }
        }
    }
}

final class ShareCalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata else { return }
        NSLog("ShareCal scene delegate received CloudKit share metadata at connection")
        ShareCalCloudKitShareAcceptanceHandler.accept(metadata: cloudKitShareMetadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NSLog("ShareCal scene delegate received CloudKit share metadata")
        ShareCalCloudKitShareAcceptanceHandler.accept(metadata: cloudKitShareMetadata)
    }
}

enum ShareCalSceneDelegateConfigurationPlan {
    static let configurationName = "Default Configuration"
    static let acceptsColdStartShareMetadata = true

    static var sceneDelegateClass: AnyClass {
        ShareCalSceneDelegate.self
    }

    static func sceneDelegateClassName(moduleName: String) -> String {
        "\(moduleName).ShareCalSceneDelegate"
    }
}

enum CloudKitSharePermissionPlan {
    static let linkInvitationPublicPermission: CKShare.ParticipantPermission = .readWrite
    static let controllerAvailablePermissions: UICloudSharingController.PermissionOptions = [
        .allowPrivate,
        .allowPublic,
        .allowReadWrite
    ]

    static func configureForLinkInvitation(_ share: CKShare) {
        share[CKShare.SystemFieldKey.title] = "ShareCal" as CKRecordValue
        share.publicPermission = linkInvitationPublicPermission
    }

    static func needsLinkInvitationUpgrade(_ share: CKShare) -> Bool {
        share.publicPermission != linkInvitationPublicPermission
    }
}

enum CloudKitShareHierarchyPlan {
    static func rootRecordID(zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
    }

    static func attach(_ record: CKRecord, toShareRoot parentRecordID: CKRecord.ID?) {
        guard let parentRecordID else { return }
        record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
    }
}

enum CloudKitShareRootICloudEmailPlan {
    static let ownerICloudEmailAddressKey = "ownerICloudEmailAddress"
    static let ownerMemberIDKey = "ownerMemberID"
    static let writesOwnerICloudEmailAddress = false

    static func ownerMemberIDValue(ownerMemberID: String, ownerICloudEmailAddress: String?) -> String {
        ICloudSharingIdentityDisplayPlan.normalizedEmailAddress(ownerICloudEmailAddress) ?? ownerMemberID
    }

    static func applyOwnerICloudEmailAddress(_ emailAddress: String?, to record: CKRecord) {
        guard writesOwnerICloudEmailAddress else { return }
        record[ownerICloudEmailAddressKey] = ICloudSharingIdentityDisplayPlan.normalizedEmailAddress(emailAddress) as CKRecordValue?
    }

    static func emailAddresses(from records: [CKRecord]) -> [String] {
        ICloudSharingIdentityDisplayPlan.emailAddresses(
            merging: [],
            records.flatMap {
                [
                    $0[ownerICloudEmailAddressKey] as? String,
                    $0[ownerMemberIDKey] as? String
                ].compactMap { $0 }
            }
        )
    }
}

enum CloudKitSharedDatabaseImportPlan {
    static func coupleSpaceZoneIDs(from zones: [CKRecordZone], expectedZoneName: String) -> [CKRecordZone.ID] {
        zones
            .map(\.zoneID)
            .filter { $0.zoneName == expectedZoneName }
    }

    static func importableMirrors(_ mirrors: [EventMirror], currentMemberID: String) -> [EventMirror] {
        mirrors.filter { $0.ownerMemberID != currentMemberID }
    }

    static func identifiedMirrors(_ mirrors: [EventMirror], sharedOwnerID: String) -> [EventMirror] {
        mirrors.map { mirror in
            EventMirror(
                id: mirror.id,
                ownerMemberID: sharedOwnerID,
                mirrorKey: mirror.mirrorKey,
                sourceCalendarID: mirror.sourceCalendarID,
                sourceCalendarTitle: mirror.sourceCalendarTitle,
                occurrenceStartDate: mirror.occurrenceStartDate,
                startDate: mirror.startDate,
                endDate: mirror.endDate,
                isAllDay: mirror.isAllDay,
                timeZoneIdentifier: mirror.timeZoneIdentifier,
                title: mirror.title,
                location: mirror.location,
                notes: mirror.notes,
                urlString: mirror.urlString,
                calendarColorHex: mirror.calendarColorHex,
                visibilityRawValue: mirror.visibilityRawValue,
                deletedAt: mirror.deletedAt,
                cloudKitRecordName: mirror.cloudKitRecordName
            )
        }
    }
}

enum CloudKitCommentWriteDestination: Equatable {
    case privateOwnerZone
    case acceptedSharedZone
}

enum CloudKitInvitationWriteDestination: Equatable {
    case privateOwnerZone
    case acceptedSharedZone
}

enum CloudKitCommentWritePlan {
    static func destination(
        eventOwnerMemberID: String,
        currentMemberID: String
    ) -> CloudKitCommentWriteDestination {
        eventOwnerMemberID == currentMemberID ? .privateOwnerZone : .acceptedSharedZone
    }
}

enum CloudKitInvitationWritePlan {
    static func destination(
        creatorMemberID: String,
        currentMemberID: String
    ) -> CloudKitInvitationWriteDestination {
        creatorMemberID == currentMemberID ? .privateOwnerZone : .acceptedSharedZone
    }
}

enum CloudKitAccessRequestWriteDestination: Equatable {
    case privateOwnerZone
    case acceptedSharedZone
}

enum CloudKitAccessRequestWritePlan {
    static func destination(
        for request: CalendarAccessRequest,
        currentMemberID: String
    ) -> CloudKitAccessRequestWriteDestination {
        switch request.source {
        case .privateOwnerZone:
            return .privateOwnerZone
        case .localOutgoing, .acceptedSharedZone:
            return .acceptedSharedZone
        }
    }

    static func destination(
        ownerMemberID: String,
        currentMemberID: String
    ) -> CloudKitAccessRequestWriteDestination {
        ownerMemberID == currentMemberID ? .privateOwnerZone : .acceptedSharedZone
    }
}

enum CloudKitStopSharingPlan {
    static func shareRecordIDToDelete(from rootRecord: CKRecord) -> CKRecord.ID? {
        rootRecord.share?.recordID
    }
}

enum CloudKitICloudDataCleanupStep: Equatable {
    case stopSharing
    case deletePrivateZone
}

enum CloudKitICloudDataCleanupPlan {
    static let steps: [CloudKitICloudDataCleanupStep] = [.stopSharing, .deletePrivateZone]

    static func zoneIDsToDelete(zoneID: CKRecordZone.ID) -> [CKRecordZone.ID] {
        [zoneID]
    }

    static func shouldIgnoreZoneDeletionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CKError.errorDomain
            && CKError.Code(rawValue: nsError.code) == .unknownItem
    }
}

enum ShareCalLaunchDiagnosticPlan {
    static let cloudKitWriteProbeArgument = "-ShareCalCloudKitWriteProbe"
    static let seedCalendarEventArgument = "-ShareCalSeedCalendarEvent"
    static let seedCalendarEventTitleArgument = "-ShareCalSeedCalendarEventTitle"
    static let seedCalendarEventStartDateArgument = "-ShareCalSeedCalendarEventStart"
    static let seedCalendarEventEndDateArgument = "-ShareCalSeedCalendarEventEnd"
    static let stopSharingProbeArgument = "-ShareCalStopICloudSharing"
    static let sharedReadProbeArgument = "-ShareCalSharedReadProbe"
    static let cloudKitWriteProbeRecordType = "CoupleSpace"

    static func shouldRunCloudKitWriteProbe(arguments: [String]) -> Bool {
        arguments.contains(cloudKitWriteProbeArgument)
    }

    static func shouldSeedCalendarEvent(arguments: [String]) -> Bool {
        arguments.contains(seedCalendarEventArgument)
    }

    static func shouldRunStopSharingProbe(arguments: [String]) -> Bool {
        arguments.contains(stopSharingProbeArgument)
    }

    static func shouldRunSharedReadProbe(arguments: [String]) -> Bool {
        arguments.contains(sharedReadProbeArgument)
    }

    static func seedCalendarEventTitle(arguments: [String]) -> String? {
        guard let argumentIndex = arguments.firstIndex(of: seedCalendarEventTitleArgument) else {
            return nil
        }

        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        let title = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func seedCalendarEventDraft(arguments: [String], now: Date = .now) -> LocalCalendarEventDraft {
        let title = seedCalendarEventTitle(arguments: arguments) ?? ShareCalSmokeTestEventPlan.title
        guard let startDate = dateValue(after: seedCalendarEventStartDateArgument, arguments: arguments),
              let endDate = dateValue(after: seedCalendarEventEndDateArgument, arguments: arguments),
              endDate > startDate else {
            return ShareCalSmokeTestEventPlan.draft(now: now, title: title)
        }

        return LocalCalendarEventDraft(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: nil,
            notes: ShareCalSmokeTestEventPlan.notes
        )
    }

    private static func dateValue(after argument: String, arguments: [String]) -> Date? {
        guard let argumentIndex = arguments.firstIndex(of: argument) else {
            return nil
        }

        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return ISO8601DateFormatter().date(from: arguments[valueIndex])
    }
}

struct CloudKitSharedReadDiagnostic {
    let sharedZoneCount: Int
    let eventMirrorCount: Int
    let commentCount: Int
    let invitationCount: Int
    let accessRequestCount: Int
    let errorDescription: String?

    var provesNoSharedCalendarReadAccess: Bool {
        errorDescription == nil
            && sharedZoneCount == 0
            && eventMirrorCount == 0
            && commentCount == 0
            && invitationCount == 0
            && accessRequestCount == 0
    }

    var displayText: String {
        var lines = [
            "Shared Zones: \(sharedZoneCount)",
            "EventMirror: \(eventMirrorCount)",
            "EventComment: \(commentCount)",
            "EventInvitation: \(invitationCount)",
            "CalendarAccessRequest: \(accessRequestCount)"
        ]
        if let errorDescription {
            lines.append("Error: \(errorDescription)")
        }
        return lines.joined(separator: "\n")
    }
}

enum CloudKitRecordMappingError: Error {
    case missingField(String)
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
        case CalendarAccessRequestRecordMapper.legacyRecordType:
            [
                CalendarAccessRequestRecordMapper.Key.requesterMemberID,
                CalendarAccessRequestRecordMapper.Key.ownerMemberID,
                CalendarAccessRequestRecordMapper.Key.requestedStartDate,
                CalendarAccessRequestRecordMapper.Key.requestedEndDate,
                CalendarAccessRequestRecordMapper.Key.statusRawValue,
                CalendarAccessRequestRecordMapper.Key.createdAt,
                CalendarAccessRequestRecordMapper.Key.updatedAt
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
        default:
            nil
        }
    }
}

enum CloudKitRecordQueryFailurePlan {
    static func canTreatMissingRecordTypeAsEmpty(recordType: String, error: Error) -> Bool {
        recordType == CalendarAccessRequestRecordMapper.legacyRecordType && isMissingRecordType(error)
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
    static let legacyRecordType = "CalendarAccessRequest"
    static let transportRecordType = InvitationRecordMapper.recordType
    static let transportRecordNamePrefix = "history-access-request:"

    enum Key {
        static let requesterMemberID = "requesterMemberID"
        static let ownerMemberID = "ownerMemberID"
        static let requestedStartDate = "requestedStartDate"
        static let requestedEndDate = "requestedEndDate"
        static let statusRawValue = "statusRawValue"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

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
        if isTransportRecord(record) {
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

        guard let requesterMemberID = record[Key.requesterMemberID] as? String else { throw CloudKitRecordMappingError.missingField(Key.requesterMemberID) }
        guard let ownerMemberID = record[Key.ownerMemberID] as? String else { throw CloudKitRecordMappingError.missingField(Key.ownerMemberID) }
        guard let requestedStartDate = record[Key.requestedStartDate] as? Date else { throw CloudKitRecordMappingError.missingField(Key.requestedStartDate) }
        guard let requestedEndDate = record[Key.requestedEndDate] as? Date else { throw CloudKitRecordMappingError.missingField(Key.requestedEndDate) }
        guard let statusRawValue = record[Key.statusRawValue] as? String else { throw CloudKitRecordMappingError.missingField(Key.statusRawValue) }
        guard let createdAt = record[Key.createdAt] as? Date else { throw CloudKitRecordMappingError.missingField(Key.createdAt) }
        guard let updatedAt = record[Key.updatedAt] as? Date else { throw CloudKitRecordMappingError.missingField(Key.updatedAt) }

        return CalendarAccessRequest(
            id: record.recordID.recordName,
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

final class CloudKitSyncDriver: NSObject, CKSyncEngineDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingRecords: [CKRecord.ID: CKRecord] = [:]
    private var pendingDeletes: Set<CKRecord.ID> = []
    private(set) var lastStateSerialization: CKSyncEngine.State.Serialization?
    private var engine: CKSyncEngine?

    func start(database: CKDatabase, stateSerialization: CKSyncEngine.State.Serialization?) {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = "couplecalendar-database-subscription"
        engine = CKSyncEngine(configuration)
    }

    func queue(recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID] = []) {
        cloudKitSharingInfo(
            "syncEngine queue saves=\(recordsToSave.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ",")) deletes=\(recordIDsToDelete.map(\.recordName).joined(separator: ","))"
        )

        lock.withLock {
            for record in recordsToSave {
                pendingRecords[record.recordID] = record
            }
            for recordID in recordIDsToDelete {
                pendingDeletes.insert(recordID)
            }
        }

        let changes: [CKSyncEngine.PendingRecordZoneChange] =
            recordsToSave.map { .saveRecord($0.recordID) } + recordIDsToDelete.map { .deleteRecord($0) }
        engine?.state.add(pendingRecordZoneChanges: changes)
    }

    func sendChangesNow() async throws {
        cloudKitSharingInfo("syncEngine sendChanges begin")
        try await engine?.sendChanges()
        cloudKitSharingInfo("syncEngine sendChanges finished")
    }

    func fetchChangesNow() async throws {
        cloudKitSharingInfo("syncEngine fetchChanges begin")
        try await engine?.fetchChanges()
        cloudKitSharingInfo("syncEngine fetchChanges finished")
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            lastStateSerialization = update.stateSerialization
        case .sentRecordZoneChanges(let sent):
            let failedSaves = sent.failedRecordSaves.map {
                "\($0.record.recordType):\($0.record.recordID.recordName)=\(describeCloudKitFailure($0.error))"
            }.joined(separator: "; ")
            let failedDeletes = sent.failedRecordDeletes.map {
                "\($0.key.recordName)=\(describeCloudKitFailure($0.value))"
            }.joined(separator: "; ")
            cloudKitSharingInfo(
                "syncEngine sentRecordZoneChanges saved=\(sent.savedRecords.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ",")) deleted=\(sent.deletedRecordIDs.map(\.recordName).joined(separator: ",")) failedSaves=\(failedSaves.isEmpty ? "none" : failedSaves) failedDeletes=\(failedDeletes.isEmpty ? "none" : failedDeletes)"
            )
            let savedChanges = sent.savedRecords.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0.recordID) }
            let deletedChanges = sent.deletedRecordIDs.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord($0) }
            syncEngine.state.remove(pendingRecordZoneChanges: savedChanges + deletedChanges)

            lock.withLock {
                for record in sent.savedRecords {
                    pendingRecords.removeValue(forKey: record.recordID)
                }
                for recordID in sent.deletedRecordIDs {
                    pendingDeletes.remove(recordID)
                }
            }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let (records, deletes) = lock.withLock {
            let records = pendingRecords.values.filter { context.options.scope.contains($0.recordID) }
            let deletes = pendingDeletes.filter { context.options.scope.contains($0) }
            return (records, deletes)
        }

        cloudKitSharingInfo(
            "syncEngine nextBatch records=\(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ",")) deletes=\(deletes.map(\.recordName).joined(separator: ","))"
        )
        guard !records.isEmpty || !deletes.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: Array(records),
            recordIDsToDelete: Array(deletes),
            atomicByZone: false
        )
    }
}

struct PreparedCloudShare: Identifiable {
    let id = UUID()
    let rootRecord: CKRecord
    let share: CKShare
    let container: CKContainer
}

struct CloudKitShareParticipantIdentitySnapshot: Equatable {
    let identifiers: [String]
    let emailAddresses: [String]
}

enum CloudKitShareParticipantIdentityPlan {
    static func sharedParticipantIdentifiers(from share: CKShare) -> [String] {
        sharedParticipantIdentitySnapshot(from: share).identifiers
    }

    static func sharedParticipantEmailAddresses(from share: CKShare) -> [String] {
        sharedParticipantIdentitySnapshot(from: share).emailAddresses
    }

    static func sharedParticipantIdentitySnapshot(from share: CKShare) -> CloudKitShareParticipantIdentitySnapshot {
        let participants = share.participants.filter { $0.role != .owner }
        return CloudKitShareParticipantIdentitySnapshot(
            identifiers: unique(participants.compactMap(identifier)),
            emailAddresses: unique(participants.compactMap { emailAddress(for: $0.userIdentity) })
        )
    }

    static func ownerEmailAddress(from metadata: CKShare.Metadata) -> String? {
        emailAddress(for: metadata.ownerIdentity)
    }

    private static func identifier(for participant: CKShare.Participant) -> String? {
        let userIdentity = participant.userIdentity
        if let emailAddress = emailAddress(for: userIdentity) {
            return emailAddress
        }
        if let phoneNumber = normalized(userIdentity.lookupInfo?.phoneNumber) {
            return phoneNumber
        }
        if let userRecordName = normalized(userIdentity.userRecordID?.recordName) {
            return userRecordName
        }
        if let nameComponents = userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: nameComponents, style: .medium)
            return normalized(name)
        }
        return nil
    }

    private static func emailAddress(for userIdentity: CKUserIdentity) -> String? {
        ICloudSharingIdentityDisplayPlan.normalizedEmailAddress(userIdentity.lookupInfo?.emailAddress)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func unique(_ values: [String]) -> [String] {
        var seenValues = Set<String>()
        return values.filter { seenValues.insert($0).inserted }
    }
}

private struct ShareRootRecord {
    let record: CKRecord
    let state: CloudKitShareRootState
}

typealias CloudKitModifyRecordResults = (
    saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
    deleteResults: [CKRecord.ID: Result<Void, any Error>]
)

enum CloudKitModifyRecordResultValidator {
    static func validate(_ results: CloudKitModifyRecordResults) throws {
        for result in results.saveResults.values {
            if case .failure(let error) = result {
                throw error
            }
        }

        for result in results.deleteResults.values {
            if case .failure(let error) = result {
                throw error
            }
        }
    }
}

final class CloudKitOperationCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    var shouldRunTimeout: Bool {
        lock.withLock { !didComplete }
    }

    func completeIfNeeded() -> Bool {
        lock.withLock {
            guard !didComplete else { return false }
            didComplete = true
            return true
        }
    }
}

enum CloudKitSharingError: LocalizedError {
    case missingShareRecord(CKRecord.ID)
    case invalidShareRecord(CKRecord.ID)
    case missingSavedShare(CKRecord.ID)
    case operationTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .missingShareRecord(let recordID):
            "CloudKit share record \(recordID.recordName) could not be found."
        case .invalidShareRecord(let recordID):
            "CloudKit record \(recordID.recordName) is not a CKShare."
        case .missingSavedShare(let recordID):
            "CloudKit did not return saved share \(recordID.recordName)."
        case .operationTimedOut(let operation):
            "CloudKit \(operation) timed out. Try again after iCloud finishes syncing."
        }
    }
}

enum CloudKitSharingFailureMessage {
    static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           CKError.Code(rawValue: nsError.code) == .invalidArguments,
            nsError.localizedDescription.localizedCaseInsensitiveContains("Cannot create new type") {
            if nsError.localizedDescription.localizedCaseInsensitiveContains("cloudkit.share") {
                return "CloudKit Production schema is missing the CloudKit Sharing system record type. Create one Development share, run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Start Pairing."
            }
            return "CloudKit Production schema is missing ShareCal record types. Run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Start Pairing."
        }

        if nsError.domain == CKError.errorDomain,
           CKError.Code(rawValue: nsError.code) == .serverRejectedRequest {
            return "CloudKit rejected private database writes for this container. For Development builds, sign in on this simulator with an Apple Account that belongs to the Apple Developer team, or deploy the CloudKit schema and test a Production/TestFlight build."
        }

        return error.localizedDescription
    }
}

struct CloudKitAccountDiagnostic {
    let expectedContainerIdentifier: String
    let expectedEnvironment: String
    let expectedZoneName: String
    let runtimeContainerIdentifier: String
    let accountStatus: String
    let userRecordName: String?
    let privateDatabaseStatus: String
    let errorDescription: String?

    var isAccountAvailable: Bool {
        accountStatus == "available"
    }

    var displayText: String {
        var lines = [
            "Expected:",
            "Container: \(expectedContainerIdentifier)",
            "Environment: \(expectedEnvironment)",
            "Zone: \(expectedZoneName)",
            "",
            "Runtime:",
            "Container: \(runtimeContainerIdentifier)",
            "Account: \(accountStatus)"
        ]
        if let userRecordName {
            lines.append("User Record: \(userRecordName)")
        }
        lines.append("Private Database: \(privateDatabaseStatus)")
        if let errorDescription {
            lines.append("Error: \(errorDescription)")
        }
        return lines.joined(separator: "\n")
    }
}

private extension CloudKitAccountDiagnostic {
    func alsoLog() -> Self {
        cloudKitSharingInfo(
            "accountDiagnostic expectedContainer=\(expectedContainerIdentifier) runtimeContainer=\(runtimeContainerIdentifier) status=\(accountStatus) userRecordPresent=\((userRecordName != nil).description) privateDatabase=\(privateDatabaseStatus) error=\(errorDescription ?? "none")"
        )
        return self
    }
}

final class CloudKitCoupleSpaceService {
    static let containerIdentifier = "iCloud.com.leeberty.CoupleCalendar"
    static let zoneName = "CoupleSpace"
    static let rootRecordName = "couple-space-root"

    let container: CKContainer
    let zoneID: CKRecordZone.ID
    private let syncDriver = CloudKitSyncDriver()
    private var hasStartedSyncDriver = false

    init(container: CKContainer = CKContainer.default()) {
        self.container = container
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName)
    }

    var privateDatabase: CKDatabase { container.privateCloudDatabase }
    var sharedDatabase: CKDatabase { container.sharedCloudDatabase }

    func accountDiagnostic() async -> CloudKitAccountDiagnostic {
        let (status, accountError) = await withCheckedContinuation { continuation in
            container.accountStatus { status, error in
                continuation.resume(returning: (status, error?.localizedDescription))
            }
        }

        var userRecordName: String?
        var userRecordError: String?
        if status == .available {
            (userRecordName, userRecordError) = await withCheckedContinuation { continuation in
                container.fetchUserRecordID { recordID, error in
                    continuation.resume(returning: (recordID?.recordName, error?.localizedDescription))
                }
            }
        }
        let privateDatabaseStatus = status == .available
            ? await privateDatabaseDiagnosticStatus()
            : "not checked"

        return CloudKitAccountDiagnostic(
            expectedContainerIdentifier: Self.containerIdentifier,
            expectedEnvironment: CloudKitExpectedConfigurationPlan.containerEnvironment,
            expectedZoneName: Self.zoneName,
            runtimeContainerIdentifier: CloudKitContainerDiagnosticPlan.displayIdentifier(
                runtimeIdentifier: container.containerIdentifier,
                fallbackIdentifier: Self.containerIdentifier
            ),
            accountStatus: Self.describe(status),
            userRecordName: userRecordName,
            privateDatabaseStatus: privateDatabaseStatus,
            errorDescription: accountError ?? userRecordError
        ).alsoLog()
    }

    private func privateDatabaseDiagnosticStatus() async -> String {
        await withCheckedContinuation { continuation in
            privateDatabase.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(returning: "error; \(describeCloudKitFailure(error))")
                    return
                }

                let hasCoupleSpaceZone = zones?.contains { $0.zoneID.zoneName == Self.zoneName } ?? false
                let zoneStatus = hasCoupleSpaceZone
                    ? "\(Self.zoneName) zone exists"
                    : "\(Self.zoneName) zone missing"
                continuation.resume(returning: "readable; \(zoneStatus)")
            }
        }
    }

    private func ensureSyncDriverStarted() {
        guard !hasStartedSyncDriver else { return }
        syncDriver.start(database: privateDatabase, stateSerialization: nil)
        hasStartedSyncDriver = true
    }

    func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
            cloudKitSharingInfo("ensureZone succeeded zone=\(Self.zoneName)")
        } catch {
            cloudKitSharingError("ensureZone failed zone=\(Self.zoneName) error=\(describeCloudKitFailure(error))")
            throw error
        }
    }

    func prepareShare(ownerMemberID: String, ownerICloudEmailAddress: String? = nil) async throws -> PreparedCloudShare {
        cloudKitSharingInfo("prepareShare begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        try await ensureZone()

        let root = try await rootRecordForSharing(
            ownerMemberID: ownerMemberID,
            ownerICloudEmailAddress: ownerICloudEmailAddress
        )
        if let shareReference = root.record.share {
            cloudKitSharingInfo("prepareShare found existing share root=\(root.record.recordID.recordName) share=\(shareReference.recordID.recordName)")
            let share = try await fetchShare(with: shareReference.recordID)
            let upgradedShare = try await ensureShareSupportsLinkInvitation(share)
            return PreparedCloudShare(rootRecord: root.record, share: upgradedShare, container: container)
        }

        var rootRecord = root.record
        for step in CloudKitShareSavePlan.steps(rootState: root.state) {
            switch step {
            case .saveRootBeforeCreatingShare:
                rootRecord = try await saveRootRecord(rootRecord)
            case .saveShare:
                cloudKitSharingInfo("prepareShare needs new share root=\(rootRecord.recordID.recordName)")
            }
        }
        let share = try await saveNewShare(rootRecord: rootRecord)
        return PreparedCloudShare(rootRecord: rootRecord, share: share, container: container)
    }

    func stopSharing(ownerMemberID: String) async throws {
        cloudKitSharingInfo("stopSharing begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        try await ensureZone()
        let rootRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        guard let root = try await fetchRecordIfPresent(with: rootRecordID) else {
            cloudKitSharingInfo("stopSharing skipped; root missing")
            return
        }
        root["schemaVersion"] = 1 as CKRecordValue
        root["ownerMemberID"] = ownerMemberID as CKRecordValue

        guard let shareRecordID = CloudKitStopSharingPlan.shareRecordIDToDelete(from: root) else {
            cloudKitSharingInfo("stopSharing skipped; share missing")
            return
        }

        do {
            _ = try await modifyRecords(
                saving: [root],
                deleting: [shareRecordID],
                savePolicy: .changedKeys,
                atomically: true
            )
            cloudKitSharingInfo("stopSharing succeeded share=\(shareRecordID.recordName)")
        } catch {
            guard Self.isUnknownItem(error) else {
                cloudKitSharingError("stopSharing failed share=\(shareRecordID.recordName) error=\(describeCloudKitFailure(error))")
                throw error
            }
            cloudKitSharingInfo("stopSharing ignored missing share=\(shareRecordID.recordName)")
        }
    }

    func fetchOutgoingShareParticipantIDs(ownerMemberID: String) async throws -> [String] {
        try await fetchOutgoingShareParticipantIdentitySnapshot(ownerMemberID: ownerMemberID).identifiers
    }

    func fetchOutgoingShareParticipantIdentitySnapshot(ownerMemberID: String) async throws -> CloudKitShareParticipantIdentitySnapshot {
        cloudKitSharingInfo("fetchOutgoingShareParticipantIDs begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        try await ensureZone()
        let rootRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        guard let root = try await fetchRecordIfPresent(with: rootRecordID) else {
            cloudKitSharingInfo("fetchOutgoingShareParticipantIDs skipped; root missing")
            return CloudKitShareParticipantIdentitySnapshot(identifiers: [], emailAddresses: [])
        }
        root["schemaVersion"] = 1 as CKRecordValue
        root["ownerMemberID"] = ownerMemberID as CKRecordValue

        guard let shareRecordID = CloudKitStopSharingPlan.shareRecordIDToDelete(from: root) else {
            cloudKitSharingInfo("fetchOutgoingShareParticipantIDs skipped; share missing")
            return CloudKitShareParticipantIdentitySnapshot(identifiers: [], emailAddresses: [])
        }

        let share = try await fetchShare(with: shareRecordID)
        let identitySnapshot = CloudKitShareParticipantIdentityPlan.sharedParticipantIdentitySnapshot(from: share)
        cloudKitSharingInfo("fetchOutgoingShareParticipantIDs succeeded count=\(identitySnapshot.identifiers.count)")
        return identitySnapshot
    }

    func deleteICloudData(ownerMemberID: String) async throws {
        cloudKitSharingInfo("deleteICloudData begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        for step in CloudKitICloudDataCleanupPlan.steps {
            switch step {
            case .stopSharing:
                try await stopSharing(ownerMemberID: ownerMemberID)
            case .deletePrivateZone:
                try await deletePrivateZone()
            }
        }
        cloudKitSharingInfo("deleteICloudData succeeded zone=\(Self.zoneName)")
    }

    private func deletePrivateZone() async throws {
        let zoneIDs = CloudKitICloudDataCleanupPlan.zoneIDsToDelete(zoneID: zoneID)
        do {
            _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: zoneIDs)
            cloudKitSharingInfo("deletePrivateZone succeeded zones=\(zoneIDs.map(\.zoneName).joined(separator: ","))")
        } catch {
            guard CloudKitICloudDataCleanupPlan.shouldIgnoreZoneDeletionError(error) else {
                cloudKitSharingError("deletePrivateZone failed zone=\(Self.zoneName) error=\(describeCloudKitFailure(error))")
                throw error
            }
            cloudKitSharingInfo("deletePrivateZone ignored missing zone=\(Self.zoneName)")
        }
    }

    @discardableResult
    func ensureShareRoot(ownerMemberID: String, ownerICloudEmailAddress: String? = nil) async throws -> CKRecord {
        try await ensureZone()
        let root = try await rootRecordForSharing(
            ownerMemberID: ownerMemberID,
            ownerICloudEmailAddress: ownerICloudEmailAddress
        )
        return try await saveRootRecord(root.record)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        let containerIdentifier = CloudKitShareAcceptancePlan.containerIdentifier(
            metadataContainerIdentifier: metadata.containerIdentifier,
            fallbackIdentifier: Self.containerIdentifier
        )
        cloudKitSharingInfo("acceptShare begin container=\(containerIdentifier)")

        let acceptContainer = CKContainer(identifier: containerIdentifier)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])

            operation.perShareResultBlock = { _, result in
                switch result {
                case .success(let share):
                    cloudKitSharingInfo("acceptShare perShare succeeded share=\(share.recordID.recordName)")
                case .failure(let error):
                    cloudKitSharingError("acceptShare perShare failed error=\(describeCloudKitFailure(error))")
                }
            }

            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    cloudKitSharingInfo("acceptShare succeeded container=\(containerIdentifier)")
                    continuation.resume()
                case .failure(let error):
                    cloudKitSharingError("acceptShare failed container=\(containerIdentifier) error=\(describeCloudKitFailure(error))")
                    continuation.resume(throwing: error)
                }
            }

            acceptContainer.add(operation)
        }
    }

    func runPrivateDatabaseWriteProbe() async {
        cloudKitSharingInfo("writeProbe begin")
        await runPrivateDatabaseWriteProbeRecord(label: "defaultZone", zoneID: nil)

        do {
            try await ensureZone()
            await runPrivateDatabaseWriteProbeRecord(label: Self.zoneName, zoneID: zoneID)
        } catch {
            cloudKitSharingError("writeProbe customZone skipped error=\(describeCloudKitFailure(error))")
        }
        cloudKitSharingInfo("writeProbe finished")
    }

    private func runPrivateDatabaseWriteProbeRecord(label: String, zoneID: CKRecordZone.ID?) async {
        let recordName = "sharecal-probe-\(UUID().uuidString)"
        let recordID = zoneID.map {
            CKRecord.ID(recordName: recordName, zoneID: $0)
        } ?? CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: ShareCalLaunchDiagnosticPlan.cloudKitWriteProbeRecordType, recordID: recordID)
        record["schemaVersion"] = 1 as CKRecordValue
        record["ownerMemberID"] = "write-probe" as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        cloudKitSharingInfo("writeProbe save begin label=\(label) record=\(recordName)")
        do {
            _ = try await modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
            cloudKitSharingInfo("writeProbe save succeeded label=\(label) record=\(recordName)")
            _ = try? await modifyRecords(saving: [], deleting: [recordID], savePolicy: .changedKeys, atomically: false)
        } catch {
            cloudKitSharingError("writeProbe save failed label=\(label) record=\(recordName) error=\(describeCloudKitFailure(error))")
        }
    }

    func sharedReadDiagnostic() async -> CloudKitSharedReadDiagnostic {
        do {
            let zoneIDs = try await sharedCoupleSpaceZoneIDs()
            var eventMirrorCount = 0
            var commentCount = 0
            var invitationCount = 0
            var accessRequestCount = 0

            for sharedZoneID in zoneIDs {
                eventMirrorCount += try await fetchRecords(
                    matching: CKQuery(recordType: EventMirrorRecordMapper.recordType, predicate: NSPredicate(value: true)),
                    in: sharedZoneID,
                    database: sharedDatabase
                ).count
                commentCount += try await fetchRecords(
                    matching: CKQuery(recordType: CommentRecordMapper.recordType, predicate: NSPredicate(value: true)),
                    in: sharedZoneID,
                    database: sharedDatabase
                ).count
                let invitationRecords = try await fetchRecords(
                    matching: CKQuery(recordType: InvitationRecordMapper.recordType, predicate: NSPredicate(value: true)),
                    in: sharedZoneID,
                    database: sharedDatabase
                )
                invitationCount += invitationRecords.filter { !CalendarAccessRequestRecordMapper.isTransportRecord($0) }.count
                accessRequestCount += invitationRecords.filter(CalendarAccessRequestRecordMapper.isTransportRecord).count
            }

            let diagnostic = CloudKitSharedReadDiagnostic(
                sharedZoneCount: zoneIDs.count,
                eventMirrorCount: eventMirrorCount,
                commentCount: commentCount,
                invitationCount: invitationCount,
                accessRequestCount: accessRequestCount,
                errorDescription: nil
            )
            cloudKitSharingInfo("sharedReadDiagnostic \(diagnostic.displayText.replacingOccurrences(of: "\n", with: " | "))")
            return diagnostic
        } catch {
            let diagnostic = CloudKitSharedReadDiagnostic(
                sharedZoneCount: 0,
                eventMirrorCount: 0,
                commentCount: 0,
                invitationCount: 0,
                accessRequestCount: 0,
                errorDescription: describeCloudKitFailure(error)
            )
            cloudKitSharingError("sharedReadDiagnostic failed error=\(diagnostic.errorDescription ?? "missing")")
            return diagnostic
        }
    }

    private func saveRootRecord(_ rootRecord: CKRecord) async throws -> CKRecord {
        cloudKitSharingInfo("saveRootRecord begin root=\(rootRecord.recordID.recordName)")
        let result: CloudKitModifyRecordResults
        do {
            result = try await modifyRecords(saving: [rootRecord], deleting: [], savePolicy: .changedKeys, atomically: false)
        } catch {
            cloudKitSharingError("saveRootRecord modifyRecords failed root=\(rootRecord.recordID.recordName) error=\(describeCloudKitFailure(error))")
            throw error
        }

        guard let rootSaveResult = result.saveResults[rootRecord.recordID] else {
            cloudKitSharingError("saveRootRecord missing saved root result root=\(rootRecord.recordID.recordName)")
            throw CloudKitSharingError.missingShareRecord(rootRecord.recordID)
        }
        let savedRoot = try rootSaveResult.get()
        cloudKitSharingInfo("saveRootRecord succeeded root=\(savedRoot.recordID.recordName)")
        return savedRoot
    }

    func saveNewShare(rootRecord: CKRecord) async throws -> CKShare {
        cloudKitSharingInfo("saveNewShare begin root=\(rootRecord.recordID.recordName)")
        let share = CKShare(rootRecord: rootRecord)
        CloudKitSharePermissionPlan.configureForLinkInvitation(share)

        let result: CloudKitModifyRecordResults
        do {
            result = try await modifyRecords(saving: [rootRecord, share], deleting: [], savePolicy: .changedKeys, atomically: true)
        } catch {
            cloudKitSharingError("saveNewShare modifyRecords failed root=\(rootRecord.recordID.recordName) share=\(share.recordID.recordName) error=\(describeCloudKitFailure(error))")
            throw error
        }

        guard let shareSaveResult = result.saveResults[share.recordID] else {
            cloudKitSharingError("saveNewShare missing saved share result share=\(share.recordID.recordName)")
            throw CloudKitSharingError.missingSavedShare(share.recordID)
        }

        let savedShareRecord = try shareSaveResult.get()
        guard let savedShare = savedShareRecord as? CKShare else {
            cloudKitSharingError("saveNewShare saved record is not CKShare share=\(share.recordID.recordName)")
            throw CloudKitSharingError.invalidShareRecord(share.recordID)
        }
        cloudKitSharingInfo(
            "saveNewShare succeeded share=\(savedShare.recordID.recordName) publicPermission=\(String(describing: savedShare.publicPermission)) url=\(savedShare.url?.absoluteString ?? "missing")"
        )
        return savedShare
    }

    private func ensureShareSupportsLinkInvitation(_ share: CKShare) async throws -> CKShare {
        guard CloudKitSharePermissionPlan.needsLinkInvitationUpgrade(share) else {
            cloudKitSharingInfo(
                "ensureShareSupportsLinkInvitation already enabled share=\(share.recordID.recordName) publicPermission=\(String(describing: share.publicPermission)) url=\(share.url?.absoluteString ?? "missing")"
            )
            return share
        }

        cloudKitSharingInfo(
            "ensureShareSupportsLinkInvitation upgrading share=\(share.recordID.recordName) currentPermission=\(String(describing: share.publicPermission))"
        )
        CloudKitSharePermissionPlan.configureForLinkInvitation(share)

        let result: CloudKitModifyRecordResults
        do {
            result = try await modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys, atomically: false)
        } catch {
            cloudKitSharingError("ensureShareSupportsLinkInvitation save failed share=\(share.recordID.recordName) error=\(describeCloudKitFailure(error))")
            throw error
        }

        guard let shareSaveResult = result.saveResults[share.recordID] else {
            cloudKitSharingError("ensureShareSupportsLinkInvitation missing saved share result share=\(share.recordID.recordName)")
            throw CloudKitSharingError.missingSavedShare(share.recordID)
        }

        let savedShareRecord = try shareSaveResult.get()
        guard let savedShare = savedShareRecord as? CKShare else {
            cloudKitSharingError("ensureShareSupportsLinkInvitation saved record is not CKShare share=\(share.recordID.recordName)")
            throw CloudKitSharingError.invalidShareRecord(share.recordID)
        }
        cloudKitSharingInfo(
            "ensureShareSupportsLinkInvitation succeeded share=\(savedShare.recordID.recordName) publicPermission=\(String(describing: savedShare.publicPermission)) url=\(savedShare.url?.absoluteString ?? "missing")"
        )
        return savedShare
    }

    private func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool,
        database: CKDatabase? = nil
    ) async throws -> CloudKitModifyRecordResults {
        try await withCheckedThrowingContinuation { continuation in
            let targetDatabase = database ?? privateDatabase
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
            operation.savePolicy = savePolicy
            operation.isAtomic = atomically

            let configuration = CKOperation.Configuration()
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 45
            operation.configuration = configuration

            let resultsLock = NSLock()
            var saveResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
            var deleteResults: [CKRecord.ID: Result<Void, any Error>] = [:]
            let completionGate = CloudKitOperationCompletionGate()

            func complete(_ result: Result<CloudKitModifyRecordResults, Error>) {
                guard completionGate.completeIfNeeded() else { return }

                switch result {
                case .success(let results):
                    continuation.resume(returning: results)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                guard completionGate.shouldRunTimeout else { return }
                cloudKitSharingError("modifyRecords timed out; cancelling operation")
                complete(.failure(CloudKitSharingError.operationTimedOut("share save")))
                DispatchQueue.global().async {
                    operation.cancel()
                }
            }

            operation.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success:
                    cloudKitSharingInfo("modifyRecords perRecordSave succeeded record=\(recordID.recordName)")
                case .failure(let error):
                    cloudKitSharingError("modifyRecords perRecordSave failed record=\(recordID.recordName) error=\(describeCloudKitFailure(error))")
                }
                resultsLock.withLock {
                    saveResults[recordID] = result
                }
            }
            operation.perRecordDeleteBlock = { recordID, result in
                resultsLock.withLock {
                    deleteResults[recordID] = result
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cloudKitSharingInfo("modifyRecords succeeded")
                    let results = resultsLock.withLock { (saveResults, deleteResults) }
                    do {
                        try CloudKitModifyRecordResultValidator.validate(results)
                        complete(.success(results))
                    } catch {
                        cloudKitSharingError("modifyRecords completed with per-record failure error=\(describeCloudKitFailure(error))")
                        complete(.failure(error))
                    }
                case .failure(let error):
                    cloudKitSharingError("modifyRecords failed error=\(describeCloudKitFailure(error))")
                    complete(.failure(error))
                }
            }

            targetDatabase.add(operation)
        }
    }

    private func rootRecordForSharing(
        ownerMemberID: String,
        ownerICloudEmailAddress: String?
    ) async throws -> ShareRootRecord {
        let rootRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        let rootOwnerMemberID = CloudKitShareRootICloudEmailPlan.ownerMemberIDValue(
            ownerMemberID: ownerMemberID,
            ownerICloudEmailAddress: ownerICloudEmailAddress
        )
        if let existingRoot = try await fetchRecordIfPresent(with: rootRecordID) {
            cloudKitSharingInfo("rootRecordForSharing found existing root=\(rootRecordID.recordName) hasShare=\((existingRoot.share != nil).description)")
            existingRoot["schemaVersion"] = 1 as CKRecordValue
            existingRoot["ownerMemberID"] = rootOwnerMemberID as CKRecordValue
            CloudKitShareRootICloudEmailPlan.applyOwnerICloudEmailAddress(ownerICloudEmailAddress, to: existingRoot)
            return ShareRootRecord(record: existingRoot, state: .existing)
        }

        cloudKitSharingInfo("rootRecordForSharing creating new root=\(rootRecordID.recordName)")
        let root = CKRecord(recordType: "CoupleSpace", recordID: rootRecordID)
        root["schemaVersion"] = 1 as CKRecordValue
        root["createdAt"] = Date() as CKRecordValue
        root["ownerMemberID"] = rootOwnerMemberID as CKRecordValue
        CloudKitShareRootICloudEmailPlan.applyOwnerICloudEmailAddress(ownerICloudEmailAddress, to: root)
        return ShareRootRecord(record: root, state: .created)
    }

    private func fetchShare(with recordID: CKRecord.ID) async throws -> CKShare {
        cloudKitSharingInfo("fetchShare begin share=\(recordID.recordName)")
        let record = try await fetchRecord(with: recordID)
        guard let share = record as? CKShare else {
            cloudKitSharingError("fetchShare invalid share record=\(recordID.recordName)")
            throw CloudKitSharingError.invalidShareRecord(recordID)
        }
        cloudKitSharingInfo("fetchShare succeeded share=\(recordID.recordName)")
        return share
    }

    private func fetchRecordIfPresent(with recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await fetchRecord(with: recordID)
        } catch {
            guard CloudKitRootLookupPolicy.shouldCreateRootAfterLookupFailure(error) else {
                throw error
            }
            cloudKitSharingInfo("root lookup failed recoverably record=\(recordID.recordName) error=\(describeCloudKitFailure(error)); creating root")
            return nil
        }
    }

    private func fetchRecordForUpsertIfPresent(
        with recordID: CKRecord.ID,
        database: CKDatabase? = nil
    ) async throws -> CKRecord? {
        do {
            return try await fetchRecord(with: recordID, database: database)
        } catch {
            let nsError = error as NSError
            if nsError.domain == CKError.errorDomain,
               CKError.Code(rawValue: nsError.code) == .unknownItem {
                cloudKitSharingInfo("upsert lookup found no existing record=\(recordID.recordName)")
                return nil
            }
            throw error
        }
    }

    private func fetchRecordsForUpsertIfPresent(
        with recordIDs: [CKRecord.ID],
        database: CKDatabase? = nil
    ) async throws -> [CKRecord.ID: CKRecord] {
        let uniqueRecordIDs = CloudKitBatchUpsertPlan.uniquedRecordIDs(recordIDs)
        guard !uniqueRecordIDs.isEmpty else { return [:] }

        do {
            let targetDatabase = database ?? privateDatabase
            let results = try await withCheckedThrowingContinuation { continuation in
                targetDatabase.fetch(withRecordIDs: uniqueRecordIDs) { result in
                    continuation.resume(with: result)
                }
            }

            var recordsByID: [CKRecord.ID: CKRecord] = [:]
            for (recordID, recordResult) in results {
                switch recordResult {
                case .success(let record):
                    recordsByID[recordID] = record
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == CKError.errorDomain,
                       CKError.Code(rawValue: nsError.code) == .unknownItem {
                        cloudKitSharingInfo("batch upsert lookup found no existing record=\(recordID.recordName)")
                    } else {
                        throw error
                    }
                }
            }
            cloudKitSharingInfo("batch upsert lookup fetched existing=\(recordsByID.count) requested=\(uniqueRecordIDs.count)")
            return recordsByID
        } catch {
            cloudKitSharingError("batch upsert lookup failed requested=\(uniqueRecordIDs.count) error=\(describeCloudKitFailure(error))")
            throw error
        }
    }

    private func fetchRecord(
        with recordID: CKRecord.ID,
        database: CKDatabase? = nil
    ) async throws -> CKRecord {
        do {
            let targetDatabase = database ?? privateDatabase
            let results = try await withCheckedThrowingContinuation { continuation in
                targetDatabase.fetch(withRecordIDs: [recordID]) { result in
                    continuation.resume(with: result)
                }
            }
            guard let recordResult = results[recordID] else {
                throw CloudKitSharingError.missingShareRecord(recordID)
            }
            return try recordResult.get()
        } catch {
            cloudKitSharingError("fetchRecord failed record=\(recordID.recordName) error=\(describeCloudKitFailure(error))")
            throw error
        }
    }

    func queueMirrorsForSync(_ mirrors: [EventMirror]) {
        ensureSyncDriverStarted()
        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        let records = mirrors.map {
            EventMirrorRecordMapper.record(from: $0, zoneID: zoneID, parentRecordID: parentRecordID)
        }
        syncDriver.queue(recordsToSave: records)
    }

    func saveMirrorsForSync(_ mirrors: [EventMirror]) async throws {
        guard !mirrors.isEmpty else {
            cloudKitSharingInfo("saveMirrorsForSync skipped; no mirrors")
            return
        }

        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPlan.recordIDs(forMirrors: mirrors, zoneID: zoneID)
        )
        var records: [CKRecord] = []
        for mirror in mirrors {
            let recordName = mirror.cloudKitRecordName ?? mirror.mirrorKey
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
            records.append(
                EventMirrorRecordMapper.record(
                    from: mirror,
                    zoneID: zoneID,
                    parentRecordID: parentRecordID,
                    existingRecord: existingRecordsByID[recordID]
                )
            )
        }

        cloudKitSharingInfo(
            "saveMirrorsForSync saving records=\(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ","))"
        )
        _ = try await modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: false)
        cloudKitSharingInfo("saveMirrorsForSync succeeded count=\(records.count)")
    }

    func deleteMirrorsForSync(_ mirrors: [EventMirror]) async throws {
        let recordIDs = mirrors.map { mirror in
            CKRecord.ID(recordName: mirror.cloudKitRecordName ?? mirror.mirrorKey, zoneID: zoneID)
        }
        guard !recordIDs.isEmpty else {
            cloudKitSharingInfo("deleteMirrorsForSync skipped; no mirrors")
            return
        }

        cloudKitSharingInfo("deleteMirrorsForSync deleting records=\(recordIDs.map(\.recordName).joined(separator: ","))")
        _ = try await modifyRecords(saving: [], deleting: recordIDs, savePolicy: .changedKeys, atomically: false)
        cloudKitSharingInfo("deleteMirrorsForSync succeeded count=\(recordIDs.count)")
    }

    func queueInvitationsForSync(_ invitations: [EventInvitation]) {
        ensureSyncDriverStarted()
        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        let records = invitations.map {
            InvitationRecordMapper.record(from: $0, zoneID: zoneID, parentRecordID: parentRecordID)
        }
        syncDriver.queue(recordsToSave: records)
    }

    @MainActor
    func saveInvitationForSync(
        _ invitation: EventInvitation,
        currentMemberID: String
    ) async throws {
        switch CloudKitInvitationWritePlan.destination(
            creatorMemberID: invitation.creatorMemberID,
            currentMemberID: currentMemberID
        ) {
        case .privateOwnerZone:
            try await ensureZone()
            try await ensureShareRoot(ownerMemberID: currentMemberID)
            try await saveInvitationsForSync([invitation], in: zoneID, database: privateDatabase)
        case .acceptedSharedZone:
            let targetZoneID = try await acceptedSharedZoneID(containingInvitationRecordName: invitation.cloudKitRecordName ?? invitation.id)
            try await saveInvitationsForSync([invitation], in: targetZoneID, database: sharedDatabase)
        }
    }

    @MainActor
    func saveCalendarAccessRequestForSync(
        _ request: CalendarAccessRequest,
        currentMemberID: String
    ) async throws {
        switch CloudKitAccessRequestWritePlan.destination(
            for: request,
            currentMemberID: currentMemberID
        ) {
        case .privateOwnerZone:
            try await ensureZone()
            try await ensureShareRoot(ownerMemberID: currentMemberID)
            try await saveCalendarAccessRequestsForSync([request], in: zoneID, database: privateDatabase)
        case .acceptedSharedZone:
            let targetZoneID = try await acceptedSharedZoneID()
            try await saveCalendarAccessRequestsForSync([request], in: targetZoneID, database: sharedDatabase)
        }
    }

    func queueCommentsForSync(_ comments: [EventComment]) {
        ensureSyncDriverStarted()
        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        let records = comments.map {
            CommentRecordMapper.record(from: $0, zoneID: zoneID, parentRecordID: parentRecordID)
        }
        syncDriver.queue(recordsToSave: records)
    }

    @MainActor
    func saveCommentForSync(
        _ comment: EventComment,
        eventOwnerMemberID: String,
        currentMemberID: String,
        eventRecordName: String
    ) async throws {
        switch CloudKitCommentWritePlan.destination(
            eventOwnerMemberID: eventOwnerMemberID,
            currentMemberID: currentMemberID
        ) {
        case .privateOwnerZone:
            try await ensureZone()
            try await ensureShareRoot(ownerMemberID: currentMemberID)
            try await saveCommentsForSync([comment], in: zoneID, database: privateDatabase)
        case .acceptedSharedZone:
            let targetZoneID = try await acceptedSharedZoneID(containingEventRecordName: eventRecordName)
            try await saveCommentsForSync([comment], in: targetZoneID, database: sharedDatabase)
        }
    }

    @MainActor
    private func saveInvitationsForSync(
        _ invitations: [EventInvitation],
        in targetZoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws {
        guard !invitations.isEmpty else {
            cloudKitSharingInfo("saveInvitationsForSync skipped; no invitations")
            return
        }

        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: targetZoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPlan.recordIDs(forInvitations: invitations, zoneID: targetZoneID),
            database: database
        )
        var records: [CKRecord] = []
        for invitation in invitations {
            let recordName = invitation.cloudKitRecordName ?? invitation.id
            let recordID = CKRecord.ID(recordName: recordName, zoneID: targetZoneID)
            records.append(
                InvitationRecordMapper.record(
                    from: invitation,
                    zoneID: targetZoneID,
                    parentRecordID: parentRecordID,
                    existingRecord: existingRecordsByID[recordID]
                )
            )
        }

        cloudKitSharingInfo(
            "saveInvitationsForSync saving records=\(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ",")) zoneOwner=\(targetZoneID.ownerName)"
        )
        _ = try await modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false,
            database: database
        )
        cloudKitSharingInfo("saveInvitationsForSync succeeded count=\(records.count)")
    }

    @MainActor
    private func saveCalendarAccessRequestsForSync(
        _ requests: [CalendarAccessRequest],
        in targetZoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws {
        guard !requests.isEmpty else {
            cloudKitSharingInfo("saveCalendarAccessRequestsForSync skipped; no requests")
            return
        }

        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: targetZoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPlan.recordIDs(forAccessRequests: requests, zoneID: targetZoneID),
            database: database
        )
        var records: [CKRecord] = []
        for request in requests {
            let recordName = request.cloudKitRecordName ?? request.id
            let recordID = CKRecord.ID(recordName: recordName, zoneID: targetZoneID)
            records.append(
                CalendarAccessRequestRecordMapper.record(
                    from: request,
                    zoneID: targetZoneID,
                    parentRecordID: parentRecordID,
                    existingRecord: existingRecordsByID[recordID]
                )
            )
        }

        cloudKitSharingInfo(
            "saveCalendarAccessRequestsForSync saving records=\(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ",")) zoneOwner=\(targetZoneID.ownerName)"
        )
        _ = try await modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false,
            database: database
        )
        cloudKitSharingInfo("saveCalendarAccessRequestsForSync succeeded count=\(records.count)")
    }

    @MainActor
    private func saveCommentsForSync(
        _ comments: [EventComment],
        in targetZoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws {
        guard !comments.isEmpty else {
            cloudKitSharingInfo("saveCommentsForSync skipped; no comments")
            return
        }

        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: targetZoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPlan.recordIDs(forComments: comments, zoneID: targetZoneID),
            database: database
        )
        var records: [CKRecord] = []
        for comment in comments {
            let recordName = comment.cloudKitRecordName ?? comment.id
            let recordID = CKRecord.ID(recordName: recordName, zoneID: targetZoneID)
            records.append(
                CommentRecordMapper.record(
                    from: comment,
                    zoneID: targetZoneID,
                    parentRecordID: parentRecordID,
                    existingRecord: existingRecordsByID[recordID]
                )
            )
        }

        cloudKitSharingInfo(
            "saveCommentsForSync saving records=\(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ",")) zoneOwner=\(targetZoneID.ownerName)"
        )
        _ = try await modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false,
            database: database
        )
        cloudKitSharingInfo("saveCommentsForSync succeeded count=\(records.count)")
    }

    func foregroundSync() async throws {
        ensureSyncDriverStarted()
        try await syncDriver.sendChangesNow()
        try await syncDriver.fetchChangesNow()
    }

    private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            "available"
        case .couldNotDetermine:
            "couldNotDetermine"
        case .noAccount:
            "noAccount"
        case .restricted:
            "restricted"
        case .temporarilyUnavailable:
            "temporarilyUnavailable"
        @unknown default:
            "unknown(\(status.rawValue))"
        }
    }

    func fetchSharedEventMirrors() async throws -> [EventMirror] {
        let sharedZoneIDs = try await fetchSharedCoupleSpaceZoneIDs()
        return try await fetchSharedEventMirrors(sharedZoneIDs: sharedZoneIDs)
    }

    func fetchSharedEventMirrors(sharedZoneIDs: [CKRecordZone.ID]) async throws -> [EventMirror] {
        guard !sharedZoneIDs.isEmpty else {
            cloudKitSharingInfo("fetchSharedEventMirrors skipped; no accepted share zones")
            return []
        }

        var mirrors: [EventMirror] = []
        let recordsByZone = try await fetchRecordsByZone(
            recordType: EventMirrorRecordMapper.recordType,
            in: sharedZoneIDs,
            database: sharedDatabase
        )
        for (sharedZoneID, records) in recordsByZone {
            let zoneMirrors = try records.map {
                try EventMirrorRecordMapper.eventMirror(from: $0)
            }
            mirrors.append(contentsOf: CloudKitSharedDatabaseImportPlan.identifiedMirrors(
                zoneMirrors,
                sharedOwnerID: sharedZoneID.ownerName
            ))
        }

        cloudKitSharingInfo("fetchSharedEventMirrors fetched records=\(mirrors.count)")
        return mirrors
    }

    func fetchSharedOwnerIDs() async throws -> [String] {
        sharedOwnerIDs(from: try await fetchSharedCoupleSpaceZoneIDs())
    }

    func sharedOwnerIDs(from zoneIDs: [CKRecordZone.ID]) -> [String] {
        zoneIDs.map(\.ownerName).sorted()
    }

    func fetchSharedOwnerICloudEmailAddresses(sharedZoneIDs: [CKRecordZone.ID]) async throws -> [String] {
        guard !sharedZoneIDs.isEmpty else { return [] }
        let rootRecordIDs = sharedZoneIDs.map(CloudKitShareHierarchyPlan.rootRecordID(zoneID:))
        let recordsByID = try await fetchRecordsForUpsertIfPresent(
            with: rootRecordIDs,
            database: sharedDatabase
        )
        let emailAddresses = CloudKitShareRootICloudEmailPlan.emailAddresses(from: Array(recordsByID.values))
        cloudKitSharingInfo("fetchSharedOwnerICloudEmailAddresses fetched count=\(emailAddresses.count)")
        return emailAddresses
    }

    func fetchEventComments() async throws -> [EventComment] {
        let sharedZoneIDs = try await fetchSharedCoupleSpaceZoneIDs()
        return try await fetchEventComments(sharedZoneIDs: sharedZoneIDs)
    }

    func fetchEventComments(sharedZoneIDs: [CKRecordZone.ID]) async throws -> [EventComment] {
        async let privateRecords = fetchRecords(
            recordType: CommentRecordMapper.recordType,
            in: zoneID,
            database: privateDatabase
        )
        async let sharedRecords = fetchRecords(
            recordType: CommentRecordMapper.recordType,
            in: sharedZoneIDs,
            database: sharedDatabase
        )
        let records = try await privateRecords + sharedRecords

        cloudKitSharingInfo("fetchEventComments fetched records=\(records.count)")
        return try records.map {
            try CommentRecordMapper.comment(from: $0)
        }
    }

    func fetchEventInvitations() async throws -> [EventInvitation] {
        let sharedZoneIDs = try await fetchSharedCoupleSpaceZoneIDs()
        return try await fetchEventInvitations(sharedZoneIDs: sharedZoneIDs)
    }

    func fetchEventInvitations(sharedZoneIDs: [CKRecordZone.ID]) async throws -> [EventInvitation] {
        async let privateRecords = fetchRecords(
            recordType: InvitationRecordMapper.recordType,
            in: zoneID,
            database: privateDatabase
        )
        async let sharedRecords = fetchRecords(
            recordType: InvitationRecordMapper.recordType,
            in: sharedZoneIDs,
            database: sharedDatabase
        )
        let records = try await privateRecords + sharedRecords
        let invitationRecords = records.filter { !CalendarAccessRequestRecordMapper.isTransportRecord($0) }

        cloudKitSharingInfo("fetchEventInvitations fetched records=\(invitationRecords.count)")
        return try invitationRecords.map {
            try InvitationRecordMapper.invitation(from: $0)
        }
    }

    func fetchCalendarAccessRequests() async throws -> [CalendarAccessRequest] {
        let sharedZoneIDs = try await fetchSharedCoupleSpaceZoneIDs()
        return try await fetchCalendarAccessRequests(sharedZoneIDs: sharedZoneIDs)
    }

    func fetchCalendarAccessRequests(sharedZoneIDs: [CKRecordZone.ID]) async throws -> [CalendarAccessRequest] {
        async let privateRecords = fetchRecords(
            recordType: CalendarAccessRequestRecordMapper.transportRecordType,
            in: zoneID,
            database: privateDatabase
        )
        async let sharedRecords = fetchRecords(
            recordType: CalendarAccessRequestRecordMapper.transportRecordType,
            in: sharedZoneIDs,
            database: sharedDatabase
        )
        let fetchedPrivateRecords = try await privateRecords.filter(CalendarAccessRequestRecordMapper.isTransportRecord)
        let fetchedSharedRecords = try await sharedRecords.filter(CalendarAccessRequestRecordMapper.isTransportRecord)

        cloudKitSharingInfo("fetchCalendarAccessRequests fetched records=\(fetchedPrivateRecords.count + fetchedSharedRecords.count)")
        let privateRequests = try fetchedPrivateRecords.map { record in
            let request = try CalendarAccessRequestRecordMapper.request(from: record)
            request.source = .privateOwnerZone
            return request
        }
        let sharedRequests = try fetchedSharedRecords.map { record in
            let request = try CalendarAccessRequestRecordMapper.request(from: record)
            request.source = .acceptedSharedZone
            return request
        }
        return privateRequests + sharedRequests
    }

    func fetchSharedCoupleSpaceZoneIDs() async throws -> [CKRecordZone.ID] {
        let zones = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecordZone], Error>) in
            sharedDatabase.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: zones ?? [])
                }
            }
        }
        return CloudKitSharedDatabaseImportPlan.coupleSpaceZoneIDs(
            from: zones,
            expectedZoneName: Self.zoneName
        )
    }

    private func sharedCoupleSpaceZoneIDs() async throws -> [CKRecordZone.ID] {
        try await fetchSharedCoupleSpaceZoneIDs()
    }

    private func acceptedSharedZoneID(containingEventRecordName eventRecordName: String) async throws -> CKRecordZone.ID {
        let zoneIDs = try await sharedCoupleSpaceZoneIDs()
        for sharedZoneID in zoneIDs {
            let recordID = CKRecord.ID(recordName: eventRecordName, zoneID: sharedZoneID)
            do {
                _ = try await fetchRecord(with: recordID, database: sharedDatabase)
                cloudKitSharingInfo("acceptedSharedZoneID matched event=\(eventRecordName) owner=\(sharedZoneID.ownerName)")
                return sharedZoneID
            } catch {
                guard Self.isUnknownItem(error) else { throw error }
            }
        }

        cloudKitSharingError("acceptedSharedZoneID failed event=\(eventRecordName) zones=\(zoneIDs.count)")
        throw NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "No accepted CloudKit share contains event \(eventRecordName)."]
        )
    }

    private func acceptedSharedZoneID() async throws -> CKRecordZone.ID {
        let zoneIDs = try await sharedCoupleSpaceZoneIDs()
        if let zoneID = zoneIDs.first {
            cloudKitSharingInfo("acceptedSharedZoneID selected owner=\(zoneID.ownerName)")
            return zoneID
        }

        cloudKitSharingError("acceptedSharedZoneID failed; no accepted share zones")
        throw NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "No accepted CloudKit share is available for calendar access requests."]
        )
    }

    private func acceptedSharedZoneID(containingInvitationRecordName invitationRecordName: String) async throws -> CKRecordZone.ID {
        let zoneIDs = try await sharedCoupleSpaceZoneIDs()
        for sharedZoneID in zoneIDs {
            let recordID = CKRecord.ID(recordName: invitationRecordName, zoneID: sharedZoneID)
            do {
                _ = try await fetchRecord(with: recordID, database: sharedDatabase)
                cloudKitSharingInfo("acceptedSharedZoneID matched invitation=\(invitationRecordName) owner=\(sharedZoneID.ownerName)")
                return sharedZoneID
            } catch {
                guard Self.isUnknownItem(error) else { throw error }
            }
        }

        cloudKitSharingError("acceptedSharedZoneID failed invitation=\(invitationRecordName) zones=\(zoneIDs.count)")
        throw NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "No accepted CloudKit share contains invitation \(invitationRecordName)."]
        )
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CKError.errorDomain
            && CKError.Code(rawValue: nsError.code) == .unknownItem
    }

    private func fetchRecords(
        recordType: String,
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        return try await fetchRecords(
            matching: query,
            in: zoneID,
            database: database,
            desiredKeys: CloudKitForegroundQueryPlan.desiredKeys(forRecordType: recordType)
        )
    }

    private func fetchRecords(
        recordType: String,
        in zoneIDs: [CKRecordZone.ID],
        database: CKDatabase
    ) async throws -> [CKRecord] {
        let recordsByZone = try await fetchRecordsByZone(recordType: recordType, in: zoneIDs, database: database)
        return recordsByZone.flatMap(\.records)
    }

    private func fetchRecordsByZone(
        recordType: String,
        in zoneIDs: [CKRecordZone.ID],
        database: CKDatabase
    ) async throws -> [(zoneID: CKRecordZone.ID, records: [CKRecord])] {
        guard !zoneIDs.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: (CKRecordZone.ID, [CKRecord]).self) { group in
            for zoneID in zoneIDs {
                group.addTask {
                    let records = try await self.fetchRecords(
                        recordType: recordType,
                        in: zoneID,
                        database: database
                    )
                    return (zoneID, records)
                }
            }

            var recordsByZone: [(zoneID: CKRecordZone.ID, records: [CKRecord])] = []
            for try await zoneRecords in group {
                recordsByZone.append(zoneRecords)
            }
            return recordsByZone.sorted { lhs, rhs in
                if lhs.zoneID.ownerName == rhs.zoneID.ownerName {
                    return lhs.zoneID.zoneName < rhs.zoneID.zoneName
                }
                return lhs.zoneID.ownerName < rhs.zoneID.ownerName
            }
        }
    }

    private func fetchRecords(
        matching query: CKQuery,
        in zoneID: CKRecordZone.ID,
        database: CKDatabase,
        desiredKeys: [String]? = nil
    ) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let recordsLock = NSLock()
            var fetchedRecords: [CKRecord] = []
            var pageCount = 0
            let startedAt = Date()

            func add(_ operation: CKQueryOperation) {
                operation.zoneID = zoneID
                operation.desiredKeys = desiredKeys
                operation.recordMatchedBlock = { _, recordResult in
                    guard case .success(let record) = recordResult else { return }
                    recordsLock.withLock {
                        fetchedRecords.append(record)
                    }
                }
                operation.queryResultBlock = { result in
                    pageCount += 1
                    switch result {
                    case .success(let cursor):
                        if let cursor {
                            add(CKQueryOperation(cursor: cursor))
                        } else {
                            let records = recordsLock.withLock { fetchedRecords }
                            cloudKitSharingInfo(
                                String(
                                    format: "fetchRecords recordType=%@ zone=%@ owner=%@ records=%d pages=%d elapsed=%.3fs desiredKeys=%d",
                                    query.recordType,
                                    zoneID.zoneName,
                                    zoneID.ownerName,
                                    records.count,
                                    pageCount,
                                    Date().timeIntervalSince(startedAt),
                                    desiredKeys?.count ?? 0
                                )
                            )
                            continuation.resume(returning: records)
                        }
                    case .failure(let error):
                        if CloudKitRecordQueryFailurePlan.canTreatMissingRecordTypeAsEmpty(
                            recordType: query.recordType,
                            error: error
                        ) {
                            cloudKitSharingError(
                                "fetchRecords missing optional recordType=\(query.recordType) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName); treating as empty"
                            )
                            continuation.resume(returning: [])
                            return
                        }
                        cloudKitSharingError(
                            "fetchRecords failed recordType=\(query.recordType) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName) error=\(describeCloudKitFailure(error))"
                        )
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }

            add(CKQueryOperation(query: query))
        }
    }

    func configureDatabaseSubscription() async throws {
        let subscription = CKDatabaseSubscription(subscriptionID: "couplecalendar-database-subscription")
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [subscription],
            subscriptionIDsToDelete: nil
        )

        try await withCheckedThrowingContinuation { continuation in
            operation.modifySubscriptionsResultBlock = { result in
                continuation.resume(with: result)
            }
            privateDatabase.add(operation)
        }
    }
}

struct CloudSharingController: UIViewControllerRepresentable {
    let preparedShare: PreparedCloudShare
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        cloudKitSharingInfo("CloudSharingController presenting active share=\(preparedShare.share.recordID.recordName)")
        let controller = UICloudSharingController(share: preparedShare.share, container: preparedShare.container)
        controller.availablePermissions = CloudKitSharePermissionPlan.controllerAvailablePermissions
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onError: (String) -> Void

        init(onError: @escaping (String) -> Void) {
            self.onError = onError
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            cloudKitSharingError("UICloudSharingController delegate failedToSaveShare error=\(describeCloudKitFailure(error))")
            onError(CloudKitSharingFailureMessage.userFacingMessage(for: error))
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "ShareCal"
        }
    }
}
