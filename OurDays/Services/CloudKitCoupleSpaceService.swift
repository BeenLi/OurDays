@preconcurrency import CloudKit
import Foundation
import OSLog
import SwiftUI
import UIKit

private let cloudKitSharingLogger = Logger(
    subsystem: "com.leeberty.CoupleCalendar",
    category: "CloudKitSharing"
)

func cloudKitSharingInfo(_ message: String) {
    #if DEBUG
    print("[CloudKitSharing] \(message)")
    #endif
    cloudKitSharingLogger.info("\(message, privacy: .public)")
}

func cloudKitSharingError(_ message: String) {
    #if DEBUG
    print("[CloudKitSharing][error] \(message)")
    #endif
    cloudKitSharingLogger.error("\(message, privacy: .public)")
}

func describeCloudKitFailure(_ error: Error) -> String {
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

/// "elapsed=1234ms", for timing the round trips a user waits on.
func cloudKitElapsed(since start: ContinuousClock.Instant) -> String {
    let duration = ContinuousClock.now - start
    let milliseconds = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
    return "elapsed=\(milliseconds)ms"
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
    /// False when an existing root already carries the current metadata: saving it again
    /// would only push the partner for nothing.
    let needsSave: Bool
}

/// Remembers, per container, that this launch already created or found the private zone.
/// Saving the zone is idempotent but costs a full round trip, and about ten service calls
/// paid it every time: three or more per sync, two of the waits before an invite opens.
final class CloudKitZoneReadiness: @unchecked Sendable {
    static let shared = CloudKitZoneReadiness()

    private let lock = NSLock()
    private var readyContainerIDs: Set<String> = []

    func isReady(_ containerID: String) -> Bool {
        lock.withLock { readyContainerIDs.contains(containerID) }
    }

    func markReady(_ containerID: String) {
        lock.withLock { _ = readyContainerIDs.insert(containerID) }
    }

    func reset(_ containerID: String) {
        lock.withLock { _ = readyContainerIDs.remove(containerID) }
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

    init(container: CKContainer = CKContainer.default()) {
        self.container = container
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName)
    }

    var privateDatabase: CKDatabase { container.privateCloudDatabase }
    var sharedDatabase: CKDatabase { container.sharedCloudDatabase }

    func accountStatus() async -> CKAccountStatus {
        await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

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
            expectedEnvironment: CloudKitExpectedConfigurationPolicy.containerEnvironment,
            expectedZoneName: Self.zoneName,
            runtimeContainerIdentifier: container.containerIdentifier ?? Self.containerIdentifier,
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

    private var zoneReadinessKey: String {
        container.containerIdentifier ?? Self.containerIdentifier
    }

    /// Forgets a confirmed zone when a failure says it is gone, so the next call creates it.
    private func noteZoneFailure(_ error: Error) {
        guard CloudKitZoneReadinessPolicy.meansZoneMissing(error) else { return }
        cloudKitSharingInfo("zone missing; will create it again zone=\(Self.zoneName)")
        CloudKitZoneReadiness.shared.reset(zoneReadinessKey)
    }

    func ensureZone() async throws {
        guard !CloudKitZoneReadiness.shared.isReady(zoneReadinessKey) else { return }
        let zone = CKRecordZone(zoneID: zoneID)
        let started = ContinuousClock.now
        do {
            _ = try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
            CloudKitZoneReadiness.shared.markReady(zoneReadinessKey)
            cloudKitSharingInfo("ensureZone succeeded zone=\(Self.zoneName) \(cloudKitElapsed(since: started))")
        } catch {
            cloudKitSharingError("ensureZone failed zone=\(Self.zoneName) error=\(describeCloudKitFailure(error))")
            throw error
        }
    }

    func prepareShare(ownerMemberID: String) async throws -> PreparedCloudShare {
        cloudKitSharingInfo("prepareShare begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        let started = ContinuousClock.now
        defer { cloudKitSharingInfo("prepareShare finished \(cloudKitElapsed(since: started))") }
        try await ensureZone()

        let root = try await rootRecordForSharing(ownerMemberID: ownerMemberID)
        if let shareReference = root.record.share {
            cloudKitSharingInfo("prepareShare found existing share root=\(root.record.recordID.recordName) share=\(shareReference.recordID.recordName)")
            let share = try await fetchShare(with: shareReference.recordID)
            let upgradedShare = try await ensureShareSupportsLinkInvitation(share)
            return PreparedCloudShare(rootRecord: root.record, share: upgradedShare, container: container)
        }

        var rootRecord = root.record
        if root.state == .created {
            rootRecord = try await saveRootRecord(rootRecord)
        }
        cloudKitSharingInfo("prepareShare needs new share root=\(rootRecord.recordID.recordName)")
        let share = try await saveNewShare(rootRecord: rootRecord)
        return PreparedCloudShare(rootRecord: rootRecord, share: share, container: container)
    }

    func stopSharing(ownerMemberID: String) async throws {
        cloudKitSharingInfo("stopSharing begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        try await ensureZone()
        let rootRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
        guard let root = try await fetchRecordIfPresent(with: rootRecordID) else {
            cloudKitSharingInfo("stopSharing skipped; root missing")
            return
        }

        guard let shareRecordID = CloudKitStopSharingPolicy.shareRecordIDToDelete(from: root) else {
            cloudKitSharingInfo("stopSharing skipped; share missing")
            return
        }

        do {
            _ = try await modifyRecords(
                saving: [],
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

    func fetchCurrentUserRecordID() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { recordID, error in
                if let recordID {
                    continuation.resume(returning: recordID.recordName)
                } else {
                    continuation.resume(throwing: error ?? CKError(.internalError))
                }
            }
        }
    }

    /// Resolves a share invitation URL to its metadata, bypassing the system
    /// acceptance prompt (used for pasted invite links and the scripted two-device smoke test).
    func fetchShareMetadata(from url: URL) async throws -> CKShare.Metadata {
        let started = ContinuousClock.now
        return try await withCheckedThrowingContinuation { continuation in
            container.fetchShareMetadata(with: url) { metadata, error in
                cloudKitSharingInfo("fetchShareMetadata finished found=\((metadata != nil).description) \(cloudKitElapsed(since: started))")
                if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: error ?? CKError(.internalError))
                }
            }
        }
    }

    func existingICloudDataSnapshot() async -> ExistingICloudDataSnapshot {
        var lookupFailed = false
        let privateZoneExists = await privateCoupleSpaceZoneExists(lookupFailed: &lookupFailed)
        var hasPrivateZoneData = false
        var hasOutgoingShare = false
        if privateZoneExists {
            let rootRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
            do {
                let rootRecord = try await fetchRecordForUpsertIfPresent(
                    with: rootRecordID,
                    database: privateDatabase
                )
                hasOutgoingShare = rootRecord?.share != nil
                hasPrivateZoneData = rootRecord != nil
            } catch {
                cloudKitSharingError("existingICloudDataSnapshot root lookup failed error=\(describeCloudKitFailure(error))")
                lookupFailed = true
            }
        }

        var acceptedSharedZoneCount = 0
        do {
            acceptedSharedZoneCount = try await fetchSharedCoupleSpaceZoneIDs().count
        } catch {
            cloudKitSharingError("existingICloudDataSnapshot shared zone lookup failed error=\(describeCloudKitFailure(error))")
            lookupFailed = true
        }

        return ExistingICloudDataSnapshot(
            hasPrivateZoneData: hasPrivateZoneData,
            hasOutgoingShare: hasOutgoingShare,
            acceptedSharedZoneCount: acceptedSharedZoneCount,
            lookupFailed: lookupFailed
        )
    }

    /// Fetches the accepted participants of the outgoing share. Read-only:
    /// an extra participant is reported to `TwoPersonPairingPolicy`, which raises
    /// a pairing conflict for the user to resolve. Nobody is removed from the
    /// share without the user choosing (see `removeOutgoingShareParticipants`).
    func fetchOutgoingShareParticipantIDs(ownerMemberID: String) async throws -> [String] {
        cloudKitSharingInfo("fetchOutgoingShareParticipantIDs begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        let started = ContinuousClock.now
        defer { cloudKitSharingInfo("fetchOutgoingShareParticipantIDs finished \(cloudKitElapsed(since: started))") }
        try await ensureZone()
        guard let share = try await fetchOutgoingShare() else {
            cloudKitSharingInfo("fetchOutgoingShareParticipantIDs skipped; share missing")
            return []
        }

        let participantIDs = CloudKitShareParticipantIdentityPolicy.acceptedParticipantIDs(from: share)
        cloudKitSharingInfo("fetchOutgoingShareParticipantIDs succeeded count=\(participantIDs.count)")
        return participantIDs
    }

    /// Removes accepted participants from the outgoing share, keeping only the
    /// given participant ID (used when resolving a pairing conflict).
    func removeOutgoingShareParticipants(keeping keptParticipantID: String?) async throws {
        try await ensureZone()
        guard let share = try await fetchOutgoingShare() else {
            cloudKitSharingInfo("removeOutgoingShareParticipants skipped; share missing")
            return
        }

        var didRemoveParticipant = false
        for participant in share.participants where participant.role != .owner {
            let identifier = CloudKitShareParticipantIdentityPolicy.identifier(for: participant)
            if let keptParticipantID, identifier == keptParticipantID { continue }
            cloudKitSharingInfo("removeOutgoingShareParticipants removing participant=\(identifier ?? "unknown")")
            share.removeParticipant(participant)
            didRemoveParticipant = true
        }
        guard didRemoveParticipant else { return }
        _ = try await saveShare(share)
    }

    private func fetchOutgoingShare() async throws -> CKShare? {
        let rootRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
        guard let root = try await fetchRecordIfPresent(with: rootRecordID),
              let shareRecordID = CloudKitStopSharingPolicy.shareRecordIDToDelete(from: root) else {
            return nil
        }
        return try await fetchShare(with: shareRecordID)
    }

    private func saveShare(_ share: CKShare) async throws -> CKShare {
        let result = try await modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys, atomically: false)
        guard let shareSaveResult = result.saveResults[share.recordID] else {
            throw CloudKitSharingError.missingSavedShare(share.recordID)
        }
        guard let savedShare = try shareSaveResult.get() as? CKShare else {
            throw CloudKitSharingError.invalidShareRecord(share.recordID)
        }
        return savedShare
    }

    func deleteICloudData(ownerMemberID: String) async throws {
        cloudKitSharingInfo("deleteICloudData begin ownerMemberIDPresent=\((!ownerMemberID.isEmpty).description)")
        try await stopSharing(ownerMemberID: ownerMemberID)
        try await deletePrivateZone()
        // Also leave every accepted share; otherwise the membership stays in
        // CloudKit, the partner still sees us as a participant, and the
        // partner's zone resurfaces if sharing is ever re-enabled.
        let acceptedSharedZoneIDs = try await fetchSharedCoupleSpaceZoneIDs()
        try await deleteAcceptedSharedZones(ownerIDs: acceptedSharedZoneIDs.map(\.ownerName))
        cloudKitSharingInfo("deleteICloudData succeeded zone=\(Self.zoneName)")
    }

    private func deletePrivateZone() async throws {
        do {
            CloudKitZoneReadiness.shared.reset(zoneReadinessKey)
            _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            cloudKitSharingInfo("deletePrivateZone succeeded zone=\(Self.zoneName)")
        } catch {
            guard Self.isUnknownItem(error) else {
                cloudKitSharingError("deletePrivateZone failed zone=\(Self.zoneName) error=\(describeCloudKitFailure(error))")
                throw error
            }
            cloudKitSharingInfo("deletePrivateZone ignored missing zone=\(Self.zoneName)")
        }
    }

    private func privateCoupleSpaceZoneExists(lookupFailed: inout Bool) async -> Bool {
        var didFail = false
        let result: Bool = await withCheckedContinuation { continuation in
            privateDatabase.fetchAllRecordZones { zones, error in
                if let error {
                    cloudKitSharingError("privateCoupleSpaceZoneExists failed error=\(describeCloudKitFailure(error))")
                    didFail = true
                    continuation.resume(returning: false)
                    return
                }
                let hasCoupleSpaceZone = zones?.contains { $0.zoneID.zoneName == Self.zoneName } ?? false
                continuation.resume(returning: hasCoupleSpaceZone)
            }
        }
        if didFail { lookupFailed = true }
        return result
    }

    @discardableResult
    func ensureShareRoot(ownerMemberID: String) async throws -> CKRecord {
        try await ensureZone()
        let root = try await rootRecordForSharing(ownerMemberID: ownerMemberID)
        guard root.needsSave else {
            cloudKitSharingInfo("ensureShareRoot unchanged root=\(root.record.recordID.recordName); skipping save")
            return root.record
        }
        return try await saveRootRecord(root.record)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        let containerIdentifier = metadata.containerIdentifier
        cloudKitSharingInfo("acceptShare begin container=\(containerIdentifier)")
        let started = ContinuousClock.now
        defer { cloudKitSharingInfo("acceptShare finished \(cloudKitElapsed(since: started))") }

        let acceptContainer = CKContainer(identifier: containerIdentifier)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            // The user is watching a spinner for this one.
            operation.qualityOfService = .userInitiated

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
        let record = CKRecord(recordType: ShareCalLaunchDiagnosticPolicy.cloudKitWriteProbeRecordType, recordID: recordID)
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
        CloudKitSharePermissionPolicy.configureForLinkInvitation(share)

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
        let acceptedParticipantCount = CloudKitShareParticipantIdentityPolicy.acceptedParticipantIDs(from: share).count
        guard CloudKitSharePermissionPolicy.needsLinkInvitationUpgrade(
            share,
            acceptedParticipantCount: acceptedParticipantCount
        ) else {
            cloudKitSharingInfo(
                "ensureShareSupportsLinkInvitation already enabled share=\(share.recordID.recordName) publicPermission=\(String(describing: share.publicPermission)) url=\(share.url?.absoluteString ?? "missing")"
            )
            return share
        }

        cloudKitSharingInfo(
            "ensureShareSupportsLinkInvitation upgrading share=\(share.recordID.recordName) currentPermission=\(String(describing: share.publicPermission))"
        )
        CloudKitSharePermissionPolicy.configureForLinkInvitation(share)

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
                        self.noteZoneFailure(error)
                        complete(.failure(error))
                    }
                case .failure(let error):
                    cloudKitSharingError("modifyRecords failed error=\(describeCloudKitFailure(error))")
                    self.noteZoneFailure(error)
                    complete(.failure(error))
                }
            }

            targetDatabase.add(operation)
        }
    }

    private func rootRecordForSharing(ownerMemberID: String) async throws -> ShareRootRecord {
        let rootRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
        if let existingRoot = try await fetchRecordIfPresent(with: rootRecordID) {
            cloudKitSharingInfo("rootRecordForSharing found existing root=\(rootRecordID.recordName) hasShare=\((existingRoot.share != nil).description)")
            let didChange = CloudKitShareRootMetadataPolicy.applyOwnerMemberID(ownerMemberID, to: existingRoot)
            return ShareRootRecord(record: existingRoot, state: .existing, needsSave: didChange)
        }

        cloudKitSharingInfo("rootRecordForSharing creating new root=\(rootRecordID.recordName)")
        let root = CKRecord(recordType: "CoupleSpace", recordID: rootRecordID)
        root["createdAt"] = Date() as CKRecordValue
        CloudKitShareRootMetadataPolicy.applyOwnerMemberID(ownerMemberID, to: root)
        return ShareRootRecord(record: root, state: .created, needsSave: true)
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
        let uniqueRecordIDs = CloudKitBatchUpsertPolicy.uniquedRecordIDs(recordIDs)
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
            noteZoneFailure(error)
            throw error
        }
    }

    func saveMirrorsForSync(_ mirrors: [EventMirror]) async throws {
        guard !mirrors.isEmpty else {
            cloudKitSharingInfo("saveMirrorsForSync skipped; no mirrors")
            return
        }

        let parentRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPolicy.recordIDs(forMirrors: mirrors, zoneID: zoneID)
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
            if mirror.cloudKitRecordName == nil {
                mirror.cloudKitRecordName = recordName
            }
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

    func saveMemberProfileForSync(
        ownerMemberID: String,
        displayName: String,
        avatar: MemberAvatar? = nil,
        updatedAt: Date = .now
    ) async throws {
        try await ensureZone()
        try await ensureShareRoot(ownerMemberID: ownerMemberID)
        let profile = CloudKitMemberProfile(
            ownerMemberID: ownerMemberID,
            displayName: displayName,
            updatedAt: updatedAt,
            avatar: avatar
        )
        do {
            try await saveMemberProfilesForSync([profile], in: zoneID, database: privateDatabase)
        } catch where MemberProfileAvatarSchemaFallbackPolicy.shouldRetryWithoutAvatar(error: error, profile: profile) {
            // The environment's schema doesn't have the avatar fields yet (Production not
            // deployed): keep the nickname syncing and drop the avatar for this save.
            cloudKitSharingInfo("saveMemberProfileForSync retrying without avatar error=\(error)")
            var profileWithoutAvatar = profile
            profileWithoutAvatar.avatar = nil
            try await saveMemberProfilesForSync([profileWithoutAvatar], in: zoneID, database: privateDatabase)
        }
    }

    @MainActor
    func saveInvitationForSync(
        _ invitation: EventInvitation,
        currentMemberID: String
    ) async throws {
        switch CloudKitInvitationWritePolicy.destination(
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
        switch CloudKitAccessRequestWritePolicy.destination(
            for: request,
            currentMemberID: currentMemberID
        ) {
        case .privateOwnerZone:
            try await ensureZone()
            try await ensureShareRoot(ownerMemberID: currentMemberID)
            try await saveCalendarAccessRequestsForSync([request], in: zoneID, database: privateDatabase)
        case .acceptedSharedZone:
            let targetZoneID = try await acceptedSharedZoneID(ownerMemberID: request.ownerMemberID)
            try await saveCalendarAccessRequestsForSync([request], in: targetZoneID, database: sharedDatabase)
        }
    }

    @MainActor
    func saveCommentForSync(
        _ comment: EventComment,
        eventOwnerMemberID: String,
        currentMemberID: String,
        eventRecordName: String
    ) async throws {
        switch CloudKitCommentWritePolicy.destination(
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

        let parentRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: targetZoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPolicy.recordIDs(forInvitations: invitations, zoneID: targetZoneID),
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

        let parentRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: targetZoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPolicy.recordIDs(forAccessRequests: requests, zoneID: targetZoneID),
            database: database
        )
        var records: [CKRecord] = []
        for request in requests {
            let recordName = CalendarAccessRequestRecordMapper.recordName(for: request)
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
    private func saveMemberProfilesForSync(
        _ profiles: [CloudKitMemberProfile],
        in targetZoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws {
        guard !profiles.isEmpty else {
            cloudKitSharingInfo("saveMemberProfilesForSync skipped; no profiles")
            return
        }

        let parentRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: targetZoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPolicy.recordIDs(forMemberProfiles: profiles, zoneID: targetZoneID),
            database: database
        )
        var records: [CKRecord] = []
        var unchangedCount = 0
        for profile in profiles {
            let recordName = MemberProfileRecordMapper.recordName(ownerMemberID: profile.ownerMemberID)
            let recordID = CKRecord.ID(recordName: recordName, zoneID: targetZoneID)
            let existingRecord = existingRecordsByID[recordID]
            let record = MemberProfileRecordMapper.record(
                from: profile,
                zoneID: targetZoneID,
                parentRecordID: parentRecordID,
                existingRecord: existingRecord
            )
            // An existing record whose keys didn't change is not re-saved: it would only
            // fire the partner's database subscription and start a sync ping-pong.
            if existingRecord != nil, record.changedKeys().isEmpty {
                unchangedCount += 1
                continue
            }
            records.append(record)
        }
        guard !records.isEmpty else {
            cloudKitSharingInfo("saveMemberProfilesForSync skipped; unchanged=\(unchangedCount)")
            return
        }

        cloudKitSharingInfo(
            "saveMemberProfilesForSync saving records=\(records.map { "\($0.recordType):\($0.recordID.recordName)" }.joined(separator: ",")) zoneOwner=\(targetZoneID.ownerName)"
        )
        _ = try await modifyRecords(
            saving: records,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: false,
            database: database
        )
        cloudKitSharingInfo("saveMemberProfilesForSync succeeded count=\(records.count)")
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

        let parentRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: targetZoneID)
        let existingRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: CloudKitBatchUpsertPolicy.recordIDs(forComments: comments, zoneID: targetZoneID),
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

    /// The user's own EventMirror records, read from their private zone. Used only by
    /// the reinstall reconciliation (`OwnMirrorReconciliationPolicy`): the regular sync
    /// never reads its own zone because the local shadows already know what is there.
    func fetchOwnEventMirrors(currentMemberID: String) async throws -> [EventMirror] {
        let records: [CKRecord]
        do {
            records = try await fetchRecords(
                recordType: EventMirrorRecordMapper.recordType,
                in: zoneID,
                database: privateDatabase
            )
        } catch {
            guard CloudKitRecordQueryFailurePolicy.isMissingZone(error) else { throw error }
            cloudKitSharingInfo("fetchOwnEventMirrors zone missing; nothing to reconcile")
            return []
        }
        let mirrors = try records.map { try EventMirrorRecordMapper.eventMirror(from: $0) }
        cloudKitSharingInfo("fetchOwnEventMirrors fetched records=\(mirrors.count)")
        return OwnMirrorReconciliationPolicy.ownedMirrors(mirrors, currentMemberID: currentMemberID)
    }

    /// Removes the previous partner's records from my private zone so they cannot be
    /// exposed through the next share (see `PartnerScopedDataPolicy`). Deletes the comments
    /// not authored by me and every invitation / history-access-request transport record.
    /// A missing zone means there is nothing to clean.
    func purgeExPartnerRecordsFromPrivateZone(currentMemberID: String) async throws {
        let commentRecords: [CKRecord]
        let invitationRecords: [CKRecord]
        do {
            async let comments = fetchRecords(
                recordType: CommentRecordMapper.recordType,
                in: zoneID,
                database: privateDatabase
            )
            async let invitations = fetchRecords(
                recordType: InvitationRecordMapper.recordType,
                in: zoneID,
                database: privateDatabase
            )
            commentRecords = try await comments
            invitationRecords = try await invitations
        } catch {
            guard CloudKitRecordQueryFailurePolicy.isMissingZone(error) else { throw error }
            cloudKitSharingInfo("purgeExPartnerRecordsFromPrivateZone zone missing; nothing to clean")
            return
        }
        let recordIDs = CloudKitExPartnerCleanupPolicy.recordIDsToDelete(
            commentRecords: commentRecords,
            invitationRecords: invitationRecords,
            currentMemberID: currentMemberID
        )
        guard !recordIDs.isEmpty else {
            cloudKitSharingInfo("purgeExPartnerRecordsFromPrivateZone nothing to delete")
            return
        }
        // CloudKit caps one modify operation at 400 records.
        for batch in stride(from: 0, to: recordIDs.count, by: 200).map({ Array(recordIDs[$0..<min($0 + 200, recordIDs.count)]) }) {
            _ = try await modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
        }
        cloudKitSharingInfo("purgeExPartnerRecordsFromPrivateZone deleted records=\(recordIDs.count)")
    }

    /// Best-effort read of what a fresh install can take back from its own private zone
    /// (see `ExistingICloudDataRecoveryPolicy.recoveredState`). Failures are logged and
    /// yield nils: recovery must still proceed without them.
    func fetchExistingICloudIdentity(ownerMemberID: String) async -> (shareRootCreatedAt: Date?, ownProfile: CloudKitMemberProfile?) {
        var shareRootCreatedAt: Date?
        var ownProfile: CloudKitMemberProfile?
        do {
            let rootRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
            if let root = try await fetchRecordForUpsertIfPresent(with: rootRecordID, database: privateDatabase) {
                shareRootCreatedAt = (root["createdAt"] as? Date) ?? root.creationDate
            }
        } catch {
            cloudKitSharingError("fetchExistingICloudIdentity root lookup failed error=\(describeCloudKitFailure(error))")
        }
        do {
            let profileRecordID = CKRecord.ID(
                recordName: MemberProfileRecordMapper.recordName(ownerMemberID: ownerMemberID),
                zoneID: zoneID
            )
            if let record = try await fetchRecordForUpsertIfPresent(with: profileRecordID, database: privateDatabase) {
                ownProfile = try MemberProfileRecordMapper.memberProfile(from: record)
            }
        } catch {
            cloudKitSharingError("fetchExistingICloudIdentity profile lookup failed error=\(describeCloudKitFailure(error))")
        }
        cloudKitSharingInfo(
            "fetchExistingICloudIdentity rootCreatedAt=\(shareRootCreatedAt.map { "\($0)" } ?? "nil") profile=\((ownProfile != nil).description)"
        )
        return (shareRootCreatedAt, ownProfile)
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
            mirrors.append(contentsOf: CloudKitSharedDatabaseImportPolicy.identifiedMirrors(
                zoneMirrors,
                sharedOwnerID: sharedZoneID.ownerName
            ))
        }

        cloudKitSharingInfo("fetchSharedEventMirrors fetched records=\(mirrors.count)")
        return mirrors
    }

    func deleteAcceptedSharedZones(ownerIDs: [String]) async throws {
        let ownerIDSet = Set(ownerIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !ownerIDSet.isEmpty else { return }
        let zoneIDs = try await sharedCoupleSpaceZoneIDs()
            .filter { ownerIDSet.contains($0.ownerName) }
        guard !zoneIDs.isEmpty else { return }

        // A participant leaves a share by deleting its CKShare record from the
        // shared database. Deleting only the zone leaves the membership intact,
        // so CloudKit re-syncs the owner's zone back and it reappears as a newly
        // discovered shared calendar.
        let rootRecordIDsByZone = zoneIDs.reduce(into: [CKRecordZone.ID: CKRecord.ID]()) { result, zoneID in
            result[zoneID] = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
        }
        let rootRecordsByID = try await fetchRecordsForUpsertIfPresent(
            with: Array(rootRecordIDsByZone.values),
            database: sharedDatabase
        )
        let shareRecordIDs = zoneIDs.compactMap { zoneID -> CKRecord.ID? in
            guard let rootRecordID = rootRecordIDsByZone[zoneID],
                  let rootRecord = rootRecordsByID[rootRecordID] else { return nil }
            return CloudKitStopSharingPolicy.shareRecordIDToDelete(from: rootRecord)
        }

        do {
            if !shareRecordIDs.isEmpty {
                _ = try await modifyRecords(
                    saving: [],
                    deleting: shareRecordIDs,
                    savePolicy: .changedKeys,
                    atomically: false,
                    database: sharedDatabase
                )
            }
            // Best-effort cleanup of the now membership-less zone from the shared cache.
            _ = try? await sharedDatabase.modifyRecordZones(saving: [], deleting: zoneIDs)
            cloudKitSharingInfo("deleteAcceptedSharedZones left shares owners=\(ownerIDSet.sorted().joined(separator: ",")) shares=\(shareRecordIDs.count) zones=\(zoneIDs.count)")
        } catch {
            cloudKitSharingError("deleteAcceptedSharedZones failed owners=\(ownerIDSet.sorted().joined(separator: ",")) error=\(describeCloudKitFailure(error))")
            throw error
        }
    }

    func fetchMemberProfiles(sharedZoneIDs: [CKRecordZone.ID]) async throws -> [CloudKitMemberProfile] {
        guard !sharedZoneIDs.isEmpty else { return [] }
        let recordsByZone = try await fetchRecordsByZone(
            recordType: MemberProfileRecordMapper.recordType,
            in: sharedZoneIDs,
            database: sharedDatabase
        )
        let profiles = try recordsByZone
            .flatMap(\.records)
            .map(MemberProfileRecordMapper.memberProfile(from:))
        cloudKitSharingInfo("fetchMemberProfiles fetched records=\(profiles.count)")
        return profiles
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
        return CloudKitSharedDatabaseImportPolicy.coupleSpaceZoneIDs(
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

    private func acceptedSharedZoneID(ownerMemberID: String) async throws -> CKRecordZone.ID {
        let zoneIDs = try await sharedCoupleSpaceZoneIDs()
        if let zoneID = CloudKitAccessRequestSharedZonePolicy.targetZoneID(
            ownerMemberID: ownerMemberID,
            acceptedSharedZoneIDs: zoneIDs
        ) {
            cloudKitSharingInfo("acceptedSharedZoneID matched accessRequestOwner=\(ownerMemberID) owner=\(zoneID.ownerName)")
            return zoneID
        }

        cloudKitSharingError("acceptedSharedZoneID failed accessRequestOwner=\(ownerMemberID) zones=\(zoneIDs.map(\.ownerName).joined(separator: ","))")
        throw NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "No accepted CloudKit share is available for calendar access requests owned by \(ownerMemberID)."]
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
            desiredKeys: CloudKitForegroundQueryPolicy.desiredKeys(forRecordType: recordType)
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
            var fetchedRecords: [CKRecord] = []
            let startedAt = Date()
            let targetRecordType = query.recordType

            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = nil
            config.desiredKeys = desiredKeys

            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            operation.recordWasChangedBlock = { _, result in
                guard case .success(let record) = result,
                      record.recordType == targetRecordType else { return }
                fetchedRecords.append(record)
            }

            operation.recordZoneChangeTokensUpdatedBlock = { _, _, _ in }

            operation.recordZoneFetchResultBlock = { _, result in
                if case .failure(let error) = result {
                    cloudKitSharingError(
                        "fetchRecords zone error recordType=\(targetRecordType) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName) error=\(describeCloudKitFailure(error))"
                    )
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    cloudKitSharingInfo(
                        String(
                            format: "fetchRecords recordType=%@ zone=%@ owner=%@ records=%d elapsed=%.3fs desiredKeys=%d",
                            targetRecordType,
                            zoneID.zoneName,
                            zoneID.ownerName,
                            fetchedRecords.count,
                            Date().timeIntervalSince(startedAt),
                            desiredKeys?.count ?? 0
                        )
                    )
                    continuation.resume(returning: fetchedRecords)
                case .failure(let error):
                    if CloudKitRecordQueryFailurePolicy.canTreatMissingRecordTypeAsEmpty(
                        recordType: targetRecordType,
                        error: error
                    ) {
                        cloudKitSharingError(
                            "fetchRecords missing optional recordType=\(targetRecordType) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName); treating as empty"
                        )
                        continuation.resume(returning: [])
                        return
                    }
                    cloudKitSharingError(
                        "fetchRecords failed recordType=\(targetRecordType) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName) error=\(describeCloudKitFailure(error))"
                    )
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    func configureDatabaseSubscription() async throws {
        // Subscribe on BOTH databases: the partner's writes to my zone land in my
        // private DB; new records the partner creates in their own zone land in my
        // shared DB. Silent (content-available) pushes wake the app to fetch + post
        // local notifications.
        try await ensureDatabaseSubscription(
            subscriptionID: "couplecalendar-database-subscription",
            database: privateDatabase
        )
        try await ensureDatabaseSubscription(
            subscriptionID: "couplecalendar-shared-database-subscription",
            database: sharedDatabase
        )
    }

    private func ensureDatabaseSubscription(subscriptionID: String, database: CKDatabase) async throws {
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        // Deliver a SILENT (content-available) push, NOT a visible alert (notifications
        // plan, decision 0002). A database subscription fires on EVERY record change and
        // cannot filter by record type or embed fields, so a visible alert was forced to
        // be generic ("有新的共享日程动态") — and it fired on the partner's *calendar
        // event* edits (the common case), steering users to the comments-only 动态 tab
        // where nothing had changed (the "phantom notification" feedback). Instead we
        // wake the app silently, run a sync, and let LocalNotificationPolicy decide what is
        // notification-worthy (comments / invites / access — never plain event edits).
        // The trade-off (accepted): silent pushes can be throttled/dropped and won't run
        // if the app is force-quit; the BGAppRefresh fallback (BackgroundRefreshSchedulePolicy)
        // narrows that window, and a foreground open remains the only guaranteed sync.
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
            database.add(operation)
        }
    }
}
