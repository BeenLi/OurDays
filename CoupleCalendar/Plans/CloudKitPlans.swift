@preconcurrency import CloudKit
import Foundation
import UIKit

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

enum CloudKitExpectedConfigurationPlan {
    static var containerEnvironment: String {
        #if DEBUG
        "Development"
        #else
        "Production"
        #endif
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
        share[CKShare.SystemFieldKey.title] = "OurDays" as CKRecordValue
        share.publicPermission = linkInvitationPublicPermission
    }

    static func needsLinkInvitationUpgrade(_ share: CKShare, acceptedParticipantCount: Int) -> Bool {
        acceptedParticipantCount == 0 && share.publicPermission != linkInvitationPublicPermission
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

enum CloudKitShareRootMetadataPlan {
    static let ownerMemberIDKey = "ownerMemberID"

    static func applyOwnerMemberID(_ ownerMemberID: String, to record: CKRecord) {
        record[ownerMemberIDKey] = ownerMemberID as CKRecordValue
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

enum CloudKitAccessRequestSharedZonePlan {
    static func targetZoneID(
        ownerMemberID: String,
        acceptedSharedZoneIDs: [CKRecordZone.ID]
    ) -> CKRecordZone.ID? {
        let trimmedOwnerMemberID = ownerMemberID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOwnerMemberID.isEmpty else { return nil }

        if let matchingZoneID = acceptedSharedZoneIDs.first(where: { $0.ownerName == trimmedOwnerMemberID }) {
            return matchingZoneID
        }

        return acceptedSharedZoneIDs.count == 1 ? acceptedSharedZoneIDs[0] : nil
    }
}

enum CloudKitStopSharingPlan {
    static func shareRecordIDToDelete(from rootRecord: CKRecord) -> CKRecord.ID? {
        rootRecord.share?.recordID
    }
}

struct CloudKitShareParticipantIdentity: Equatable {
    let role: CKShare.ParticipantRole
    let acceptanceStatus: CKShare.ParticipantAcceptanceStatus
    let identifier: String?
}

enum CloudKitShareParticipantIdentityPlan {
    static func acceptedParticipantIDs(from share: CKShare) -> [String] {
        acceptedParticipantIDs(
            from: share.participants.map { participant in
                CloudKitShareParticipantIdentity(
                    role: participant.role,
                    acceptanceStatus: participant.acceptanceStatus,
                    identifier: identifier(for: participant)
                )
            }
        )
    }

    static func acceptedParticipantIDs(from participants: [CloudKitShareParticipantIdentity]) -> [String] {
        unique(
            participants
                .filter { $0.role != .owner && $0.acceptanceStatus == .accepted }
                .compactMap(\.identifier)
        )
    }

    static func identifier(for participant: CKShare.Participant) -> String? {
        let userIdentity = participant.userIdentity
        // Only the CloudKit user record name is comparable with shared-zone
        // owner names; the contact fallbacks just keep pairing status visible
        // when CloudKit withholds it.
        if let userRecordName = normalized(userIdentity.userRecordID?.recordName) {
            return userRecordName
        }
        if let emailAddress = normalized(userIdentity.lookupInfo?.emailAddress) {
            return emailAddress
        }
        if let phoneNumber = normalized(userIdentity.lookupInfo?.phoneNumber) {
            return phoneNumber
        }
        if let nameComponents = userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: nameComponents, style: .medium)
            return normalized(name)
        }
        return nil
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
