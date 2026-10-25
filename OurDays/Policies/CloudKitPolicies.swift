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

enum CloudKitExpectedConfigurationPolicy {
    static var containerEnvironment: String {
        #if DEBUG
        "Development"
        #else
        "Production"
        #endif
    }
}

enum CloudKitSharePermissionPolicy {
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

enum CloudKitShareHierarchyPolicy {
    static func rootRecordID(zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
    }

    static func attach(_ record: CKRecord, toShareRoot parentRecordID: CKRecord.ID?) {
        guard let parentRecordID, record.parent?.recordID != parentRecordID else { return }
        record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
    }
}

enum CloudKitShareRootMetadataPolicy {
    static let ownerMemberIDKey = "ownerMemberID"

    /// Writes the owner ID only when the root doesn't already carry it. Returns whether
    /// the record changed: saving a shared record on every sync (even with identical
    /// values) pushes the partner, whose push-driven sync saves their root, which pushes
    /// us back — a silent-push ping-pong that burns the budget real changes need.
    @discardableResult
    static func applyOwnerMemberID(_ ownerMemberID: String, to record: CKRecord) -> Bool {
        guard (record[ownerMemberIDKey] as? String) != ownerMemberID else { return false }
        record[ownerMemberIDKey] = ownerMemberID as CKRecordValue
        return true
    }
}

enum CloudKitSharedDatabaseImportPolicy {
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

enum CloudKitCommentWritePolicy {
    static func destination(
        eventOwnerMemberID: String,
        currentMemberID: String
    ) -> CloudKitCommentWriteDestination {
        eventOwnerMemberID == currentMemberID ? .privateOwnerZone : .acceptedSharedZone
    }
}

enum CloudKitInvitationWritePolicy {
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

enum CloudKitAccessRequestWritePolicy {
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

enum CloudKitAccessRequestSharedZonePolicy {
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

enum CloudKitStopSharingPolicy {
    static func shareRecordIDToDelete(from rootRecord: CKRecord) -> CKRecord.ID? {
        rootRecord.share?.recordID
    }
}

struct CloudKitShareParticipantIdentity: Equatable {
    let role: CKShare.ParticipantRole
    let acceptanceStatus: CKShare.ParticipantAcceptanceStatus
    let identifier: String?
}

enum CloudKitShareParticipantIdentityPolicy {
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
        if let userRecordName = MemberIDPolicy.normalized(userIdentity.userRecordID?.recordName) {
            return userRecordName
        }
        if let emailAddress = MemberIDPolicy.normalized(userIdentity.lookupInfo?.emailAddress) {
            return emailAddress
        }
        if let phoneNumber = MemberIDPolicy.normalized(userIdentity.lookupInfo?.phoneNumber) {
            return phoneNumber
        }
        if let nameComponents = userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: nameComponents, style: .medium)
            return MemberIDPolicy.normalized(name)
        }
        return nil
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

/// A sync that was cancelled did not fail. The Swift task running it went away (an
/// event sheet closed while its open-sync ran, pull-to-refresh torn down, a
/// BGAppRefresh expired) and CloudKit's async calls turned that into an error; the
/// user's data and iCloud are fine and the next sync simply runs again, so it must
/// never reach the red sync banner. CloudKit reports it as `CKError.operationCancelled`
/// ("Operation <operationID> was cancelled"), possibly per item inside a
/// `partialFailure`; Swift as `CancellationError`.
enum SyncCancellationPolicy {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        guard nsError.domain == CKError.errorDomain else { return false }
        switch CKError.Code(rawValue: nsError.code) {
        case .operationCancelled:
            return true
        case .partialFailure:
            let itemErrors = (nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error])?.values
            guard let itemErrors, !itemErrors.isEmpty else { return false }
            return itemErrors.allSatisfy(isCancellation)
        default:
            return false
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

/// Which records to delete from MY private zone when the partner leaves (unpair, or a
/// pairing replacement). In a two-person space every invitation and history-access
/// request stored in my zone was exchanged with that partner, and every comment there
/// not written by me is theirs; none of it may ride along into the next CKShare.
/// My own comments on my own events stay: they are mine.
enum CloudKitExPartnerCleanupPolicy {
    static func recordIDsToDelete(
        commentRecords: [CKRecord],
        invitationRecords: [CKRecord],
        currentMemberID: String
    ) -> [CKRecord.ID] {
        let me = MemberIDPolicy.normalized(currentMemberID)
        let foreignComments = commentRecords.filter { record in
            MemberIDPolicy.normalized(record[CommentRecordMapper.Key.authorMemberID] as? String) != me
        }
        return (foreignComments + invitationRecords).map(\.recordID)
    }
}
