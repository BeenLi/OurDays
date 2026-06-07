@preconcurrency import CloudKit
import Foundation
import OSLog
#if os(macOS)
import Security
#endif
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

struct CloudKitRuntimeEntitlementDiagnostic {
    let iCloudServices: [String]
    let containerIdentifiers: [String]
    let containerEnvironment: String?
    let apsEnvironment: String?

    var summary: String {
        [
            "services=\(iCloudServices.isEmpty ? "missing" : iCloudServices.joined(separator: ","))",
            "containers=\(containerIdentifiers.isEmpty ? "missing" : containerIdentifiers.joined(separator: ","))",
            "environment=\(containerEnvironment ?? "missing")",
            "aps=\(apsEnvironment ?? "missing")"
        ].joined(separator: " ")
    }
}

enum CloudKitRuntimeEntitlementReader {
    static func current() -> CloudKitRuntimeEntitlementDiagnostic {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault) else {
            return CloudKitRuntimeEntitlementDiagnostic(
                iCloudServices: [],
                containerIdentifiers: [],
                containerEnvironment: nil,
                apsEnvironment: nil
            )
        }

        return CloudKitRuntimeEntitlementDiagnostic(
            iCloudServices: arrayValue("com.apple.developer.icloud-services", task: task),
            containerIdentifiers: arrayValue("com.apple.developer.icloud-container-identifiers", task: task),
            containerEnvironment: stringValue("com.apple.developer.icloud-container-environment", task: task),
            apsEnvironment: stringValue("aps-environment", task: task)
        )
        #else
        return CloudKitRuntimeEntitlementDiagnostic(
            iCloudServices: ["unreadable"],
            containerIdentifiers: ["unreadable"],
            containerEnvironment: "unreadable",
            apsEnvironment: "unreadable"
        )
        #endif
    }

    #if os(macOS)
    private static func arrayValue(_ key: String, task: SecTask) -> [String] {
        SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? [String] ?? []
    }

    private static func stringValue(_ key: String, task: SecTask) -> String? {
        SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? String
    }
    #endif
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
                ShareCalAcceptedShareSignal.markAccepted()
            } catch {
                NSLog("ShareCal failed to accept CloudKit share: \(error)")
            }
        }
    }
}

final class ShareCalSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        ShareCalCloudKitShareAcceptanceHandler.accept(metadata: cloudKitShareMetadata)
    }
}

enum ShareCalSceneDelegateConfigurationPlan {
    static var sceneDelegateClass: AnyClass {
        ShareCalSceneDelegate.self
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

enum CloudKitSharedDatabaseImportPlan {
    static func coupleSpaceZoneIDs(from zones: [CKRecordZone], expectedZoneName: String) -> [CKRecordZone.ID] {
        zones
            .map(\.zoneID)
            .filter { $0.zoneName == expectedZoneName }
    }

    static func importableMirrors(_ mirrors: [EventMirror], currentMemberID: String) -> [EventMirror] {
        mirrors.filter { $0.ownerMemberID != currentMemberID }
    }

    static func localizedMirrors(_ mirrors: [EventMirror], partnerMemberID: String) -> [EventMirror] {
        mirrors.map { mirror in
            EventMirror(
                id: mirror.id,
                ownerMemberID: partnerMemberID,
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

enum CloudKitCommentWritePlan {
    static func destination(
        eventOwnerMemberID: String,
        currentMemberID: String
    ) -> CloudKitCommentWriteDestination {
        eventOwnerMemberID == currentMemberID ? .privateOwnerZone : .acceptedSharedZone
    }
}

enum ShareCalLaunchDiagnosticPlan {
    static let cloudKitWriteProbeArgument = "-ShareCalCloudKitWriteProbe"
    static let seedCalendarEventArgument = "-ShareCalSeedCalendarEvent"
    static let seedCalendarEventTitleArgument = "-ShareCalSeedCalendarEventTitle"
    static let cloudKitWriteProbeRecordType = "CoupleSpace"

    static func shouldRunCloudKitWriteProbe(arguments: [String]) -> Bool {
        arguments.contains(cloudKitWriteProbeArgument)
    }

    static func shouldSeedCalendarEvent(arguments: [String]) -> Bool {
        arguments.contains(seedCalendarEventArgument)
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
}

enum CloudKitRecordMappingError: Error {
    case missingField(String)
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

    static func record(
        from invitation: EventInvitation,
        zoneID: CKRecordZone.ID,
        parentRecordID: CKRecord.ID? = nil
    ) -> CKRecord {
        let recordName = invitation.cloudKitRecordName ?? invitation.id
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        CloudKitShareHierarchyPlan.attach(record, toShareRoot: parentRecordID)
        record["creatorMemberID"] = invitation.creatorMemberID as CKRecordValue
        record["inviteeMemberID"] = invitation.inviteeMemberID as CKRecordValue
        record["title"] = invitation.title as CKRecordValue
        record["startDate"] = invitation.startDate as CKRecordValue
        record["endDate"] = invitation.endDate as CKRecordValue
        record["isAllDay"] = NSNumber(value: invitation.isAllDay)
        record["location"] = invitation.location as CKRecordValue?
        record["notes"] = invitation.notes as CKRecordValue?
        record["statusRawValue"] = invitation.statusRawValue as CKRecordValue
        record["createdAt"] = invitation.createdAt as CKRecordValue
        record["updatedAt"] = invitation.updatedAt as CKRecordValue
        record["createdLocalEventID"] = invitation.createdLocalEventID as CKRecordValue?
        return record
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
                return "CloudKit Production schema is missing the CloudKit Sharing system record type. Create one Development share, run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Create or Open Share."
            }
            return "CloudKit Production schema is missing ShareCal record types. Run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Create or Open Share."
        }

        if nsError.domain == CKError.errorDomain,
           CKError.Code(rawValue: nsError.code) == .serverRejectedRequest {
            return "CloudKit rejected private database writes for this container. For Development builds, sign in on this simulator with an Apple Account that belongs to the Apple Developer team, or deploy the CloudKit schema and test a Production/TestFlight build."
        }

        return error.localizedDescription
    }
}

struct CloudKitAccountDiagnostic {
    let containerIdentifier: String
    let accountStatus: String
    let userRecordName: String?
    let errorDescription: String?
    let entitlementSummary: String

    var isAccountAvailable: Bool {
        accountStatus == "available"
    }

    var displayText: String {
        var lines = [
            "Container: \(containerIdentifier)",
            "Account: \(accountStatus)"
        ]
        if let userRecordName {
            lines.append("User Record: \(userRecordName)")
        }
        if let errorDescription {
            lines.append("Error: \(errorDescription)")
        }
        lines.append("Entitlements: \(entitlementSummary)")
        return lines.joined(separator: "\n")
    }
}

private extension CloudKitAccountDiagnostic {
    func alsoLog() -> Self {
        cloudKitSharingInfo(
            "accountDiagnostic container=\(containerIdentifier) status=\(accountStatus) userRecordPresent=\((userRecordName != nil).description) entitlements=\(entitlementSummary) error=\(errorDescription ?? "none")"
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

        return CloudKitAccountDiagnostic(
            containerIdentifier: CloudKitContainerDiagnosticPlan.displayIdentifier(
                runtimeIdentifier: container.containerIdentifier,
                fallbackIdentifier: Self.containerIdentifier
            ),
            accountStatus: Self.describe(status),
            userRecordName: userRecordName,
            errorDescription: accountError ?? userRecordError,
            entitlementSummary: CloudKitRuntimeEntitlementReader.current().summary
        ).alsoLog()
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

    func prepareShare(ownerMemberID: String) async throws -> PreparedCloudShare {
        cloudKitSharingInfo("prepareShare begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        try await ensureZone()

        let root = try await rootRecordForSharing(ownerMemberID: ownerMemberID)
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

    @discardableResult
    func ensureShareRoot(ownerMemberID: String) async throws -> CKRecord {
        try await ensureZone()
        let root = try await rootRecordForSharing(ownerMemberID: ownerMemberID)
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

    private func rootRecordForSharing(ownerMemberID: String) async throws -> ShareRootRecord {
        let rootRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        if let existingRoot = try await fetchRecordIfPresent(with: rootRecordID) {
            cloudKitSharingInfo("rootRecordForSharing found existing root=\(rootRecordID.recordName) hasShare=\((existingRoot.share != nil).description)")
            existingRoot["schemaVersion"] = 1 as CKRecordValue
            existingRoot["ownerMemberID"] = ownerMemberID as CKRecordValue
            return ShareRootRecord(record: existingRoot, state: .existing)
        }

        cloudKitSharingInfo("rootRecordForSharing creating new root=\(rootRecordID.recordName)")
        let root = CKRecord(recordType: "CoupleSpace", recordID: rootRecordID)
        root["schemaVersion"] = 1 as CKRecordValue
        root["createdAt"] = Date() as CKRecordValue
        root["ownerMemberID"] = ownerMemberID as CKRecordValue
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
        var records: [CKRecord] = []
        for mirror in mirrors {
            let recordName = mirror.cloudKitRecordName ?? mirror.mirrorKey
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
            let existingRecord = try await fetchRecordForUpsertIfPresent(with: recordID)
            records.append(
                EventMirrorRecordMapper.record(
                    from: mirror,
                    zoneID: zoneID,
                    parentRecordID: parentRecordID,
                    existingRecord: existingRecord
                )
            )
        }

        cloudKitSharingInfo(
            "saveMirrorsForSync saving records=\(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ","))"
        )
        _ = try await modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: false)
        cloudKitSharingInfo("saveMirrorsForSync succeeded count=\(records.count)")
    }

    func queueInvitationsForSync(_ invitations: [EventInvitation]) {
        ensureSyncDriverStarted()
        let parentRecordID = CloudKitShareHierarchyPlan.rootRecordID(zoneID: zoneID)
        let records = invitations.map {
            InvitationRecordMapper.record(from: $0, zoneID: zoneID, parentRecordID: parentRecordID)
        }
        syncDriver.queue(recordsToSave: records)
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
        var records: [CKRecord] = []
        for comment in comments {
            let recordName = comment.cloudKitRecordName ?? comment.id
            let recordID = CKRecord.ID(recordName: recordName, zoneID: targetZoneID)
            let existingRecord = try await fetchRecordForUpsertIfPresent(with: recordID, database: database)
            records.append(
                CommentRecordMapper.record(
                    from: comment,
                    zoneID: targetZoneID,
                    parentRecordID: parentRecordID,
                    existingRecord: existingRecord
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
        let zoneIDs = try await sharedCoupleSpaceZoneIDs()
        guard !zoneIDs.isEmpty else {
            cloudKitSharingInfo("fetchSharedEventMirrors skipped; no accepted share zones")
            return []
        }

        let query = CKQuery(recordType: EventMirrorRecordMapper.recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        for sharedZoneID in zoneIDs {
            cloudKitSharingInfo("fetchSharedEventMirrors querying zone=\(sharedZoneID.zoneName) owner=\(sharedZoneID.ownerName)")
            records.append(contentsOf: try await fetchRecords(matching: query, in: sharedZoneID, database: sharedDatabase))
        }

        cloudKitSharingInfo("fetchSharedEventMirrors fetched records=\(records.count)")
        return try records.map {
            try EventMirrorRecordMapper.eventMirror(from: $0)
        }
    }

    func fetchEventComments() async throws -> [EventComment] {
        let query = CKQuery(recordType: CommentRecordMapper.recordType, predicate: NSPredicate(value: true))
        var records = try await fetchRecords(matching: query, in: zoneID, database: privateDatabase)

        let sharedZoneIDs = try await sharedCoupleSpaceZoneIDs()
        for sharedZoneID in sharedZoneIDs {
            cloudKitSharingInfo("fetchEventComments querying shared zone=\(sharedZoneID.zoneName) owner=\(sharedZoneID.ownerName)")
            records.append(contentsOf: try await fetchRecords(matching: query, in: sharedZoneID, database: sharedDatabase))
        }

        cloudKitSharingInfo("fetchEventComments fetched records=\(records.count)")
        return try records.map {
            try CommentRecordMapper.comment(from: $0)
        }
    }

    private func sharedCoupleSpaceZoneIDs() async throws -> [CKRecordZone.ID] {
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

    private static func isUnknownItem(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CKError.errorDomain
            && CKError.Code(rawValue: nsError.code) == .unknownItem
    }

    private func fetchRecords(
        matching query: CKQuery,
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let recordsLock = NSLock()
            var fetchedRecords: [CKRecord] = []

            func add(_ operation: CKQueryOperation) {
                operation.zoneID = zoneID
                operation.recordMatchedBlock = { _, recordResult in
                    guard case .success(let record) = recordResult else { return }
                    recordsLock.withLock {
                        fetchedRecords.append(record)
                    }
                }
                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let cursor):
                        if let cursor {
                            add(CKQueryOperation(cursor: cursor))
                        } else {
                            let records = recordsLock.withLock { fetchedRecords }
                            continuation.resume(returning: records)
                        }
                    case .failure(let error):
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
