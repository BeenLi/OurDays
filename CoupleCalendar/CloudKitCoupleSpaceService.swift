@preconcurrency import CloudKit
import Foundation
import SwiftUI
import UIKit

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

    static func record(from mirror: EventMirror, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordName = mirror.cloudKitRecordName ?? mirror.mirrorKey
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
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

    static func record(from invitation: EventInvitation, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordName = invitation.cloudKitRecordName ?? invitation.id
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
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

    static func record(from comment: EventComment, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordName = comment.cloudKitRecordName ?? comment.id
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        record["eventMirrorID"] = comment.eventMirrorID as CKRecordValue
        record["authorMemberID"] = comment.authorMemberID as CKRecordValue
        record["body"] = comment.body as CKRecordValue
        record["createdAt"] = comment.createdAt as CKRecordValue
        record["editedAt"] = comment.editedAt as CKRecordValue?
        record["deletedAt"] = comment.deletedAt as CKRecordValue?
        record["isRead"] = NSNumber(value: comment.isRead)
        return record
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
        try await engine?.sendChanges()
    }

    func fetchChangesNow() async throws {
        try await engine?.fetchChanges()
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            lastStateSerialization = update.stateSerialization
        case .sentRecordZoneChanges(let sent):
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
    let existingShare: CKShare?
    let container: CKContainer
    let service: CloudKitCoupleSpaceService

    var isExistingShare: Bool {
        existingShare != nil
    }
}

enum CloudKitSharingError: LocalizedError {
    case missingShareRecord(CKRecord.ID)
    case invalidShareRecord(CKRecord.ID)
    case missingSavedShare(CKRecord.ID)

    var errorDescription: String? {
        switch self {
        case .missingShareRecord(let recordID):
            "CloudKit share record \(recordID.recordName) could not be found."
        case .invalidShareRecord(let recordID):
            "CloudKit record \(recordID.recordName) is not a CKShare."
        case .missingSavedShare(let recordID):
            "CloudKit did not return saved share \(recordID.recordName)."
        }
    }
}

struct CloudKitAccountDiagnostic {
    let containerIdentifier: String
    let accountStatus: String
    let userRecordName: String?
    let errorDescription: String?

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
        return lines.joined(separator: "\n")
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

    init(container: CKContainer = CKContainer(identifier: containerIdentifier)) {
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
            containerIdentifier: Self.containerIdentifier,
            accountStatus: Self.describe(status),
            userRecordName: userRecordName,
            errorDescription: accountError ?? userRecordError
        )
    }

    private func ensureSyncDriverStarted() {
        guard !hasStartedSyncDriver else { return }
        syncDriver.start(database: privateDatabase, stateSerialization: nil)
        hasStartedSyncDriver = true
    }

    func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
    }

    func prepareShare(ownerMemberID: String) async throws -> PreparedCloudShare {
        try await ensureZone()

        let root = try await rootRecordForSharing(ownerMemberID: ownerMemberID)
        if let shareReference = root.share {
            let share = try await fetchShare(with: shareReference.recordID)
            return PreparedCloudShare(rootRecord: root, existingShare: share, container: container, service: self)
        }

        return PreparedCloudShare(rootRecord: root, existingShare: nil, container: container, service: self)
    }

    func saveNewShare(rootRecord: CKRecord) async throws -> CKShare {
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "ShareCal" as CKRecordValue
        share.publicPermission = .none

        let result = try await privateDatabase.modifyRecords(
            saving: [rootRecord, share],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )

        guard let shareSaveResult = result.saveResults[share.recordID] else {
            throw CloudKitSharingError.missingSavedShare(share.recordID)
        }

        let savedShareRecord = try shareSaveResult.get()
        guard let savedShare = savedShareRecord as? CKShare else {
            throw CloudKitSharingError.invalidShareRecord(share.recordID)
        }
        return savedShare
    }

    private func rootRecordForSharing(ownerMemberID: String) async throws -> CKRecord {
        let rootRecordID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
        if let existingRoot = try await fetchRecordIfPresent(with: rootRecordID) {
            existingRoot["schemaVersion"] = 1 as CKRecordValue
            existingRoot["ownerMemberID"] = ownerMemberID as CKRecordValue
            return existingRoot
        }

        let root = CKRecord(recordType: "CoupleSpace", recordID: rootRecordID)
        root["schemaVersion"] = 1 as CKRecordValue
        root["createdAt"] = Date() as CKRecordValue
        root["ownerMemberID"] = ownerMemberID as CKRecordValue
        return root
    }

    private func fetchShare(with recordID: CKRecord.ID) async throws -> CKShare {
        let record = try await fetchRecord(with: recordID)
        guard let share = record as? CKShare else {
            throw CloudKitSharingError.invalidShareRecord(recordID)
        }
        return share
    }

    private func fetchRecordIfPresent(with recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await fetchRecord(with: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func fetchRecord(with recordID: CKRecord.ID) async throws -> CKRecord {
        let results = try await withCheckedThrowingContinuation { continuation in
            privateDatabase.fetch(withRecordIDs: [recordID]) { result in
                continuation.resume(with: result)
            }
        }
        guard let recordResult = results[recordID] else {
            throw CloudKitSharingError.missingShareRecord(recordID)
        }
        return try recordResult.get()
    }

    func queueMirrorsForSync(_ mirrors: [EventMirror]) {
        ensureSyncDriverStarted()
        let records = mirrors.map { EventMirrorRecordMapper.record(from: $0, zoneID: zoneID) }
        syncDriver.queue(recordsToSave: records)
    }

    func queueInvitationsForSync(_ invitations: [EventInvitation]) {
        ensureSyncDriverStarted()
        let records = invitations.map { InvitationRecordMapper.record(from: $0, zoneID: zoneID) }
        syncDriver.queue(recordsToSave: records)
    }

    func queueCommentsForSync(_ comments: [EventComment]) {
        ensureSyncDriverStarted()
        let records = comments.map { CommentRecordMapper.record(from: $0, zoneID: zoneID) }
        syncDriver.queue(recordsToSave: records)
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
        let query = CKQuery(recordType: EventMirrorRecordMapper.recordType, predicate: NSPredicate(value: true))
        let records = try await fetchRecords(matching: query, in: zoneID, database: sharedDatabase)

        return try records.map {
            try EventMirrorRecordMapper.eventMirror(from: $0)
        }
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
        let controller: UICloudSharingController
        if let existingShare = preparedShare.existingShare {
            controller = UICloudSharingController(share: existingShare, container: preparedShare.container)
        } else {
            controller = UICloudSharingController { _, completion in
                Task {
                    do {
                        let share = try await preparedShare.service.saveNewShare(rootRecord: preparedShare.rootRecord)
                        completion(share, preparedShare.container, nil)
                    } catch {
                        completion(nil, nil, error)
                    }
                }
            }
        }
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
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
            onError(error.localizedDescription)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "ShareCal"
        }
    }
}
