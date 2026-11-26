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

/// Unchecked: CloudKit records are handed between tasks but only read once made.
struct PreparedCloudShare: Identifiable, @unchecked Sendable {
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

/// One piece of CloudKit work started before the user asks for it, handed over when
/// they do. Used for my own invite link: it takes several round trips to make, and
/// Apple's accept of the partner's link leaves seconds of waiting to make it in.
@MainActor
final class ShareCalPrewarm<Value: Sendable> {
    static var maxAge: TimeInterval { 300 }

    private var pending: (key: String, startedAt: Date, task: Task<Value, Error>)?

    func start(key: String, now: Date = .now, work: @escaping @MainActor () async throws -> Value) {
        if let pending, pending.key == key, now.timeIntervalSince(pending.startedAt) < Self.maxAge { return }
        pending = (key, now, Task { try await work() })
    }

    /// The prewarmed value when one for this key is fresh and succeeded; otherwise `work`.
    /// Either way it is used once.
    func take(key: String, now: Date = .now, work: @MainActor () async throws -> Value) async throws -> Value {
        let prewarmed = pending
        pending = nil
        if let prewarmed, prewarmed.key == key, now.timeIntervalSince(prewarmed.startedAt) < Self.maxAge,
           let value = try? await prewarmed.task.value {
            return value
        }
        return try await work()
    }

    func discard() {
        pending = nil
    }
}

@MainActor
enum ShareCalOutgoingSharePrewarm {
    static let shared = ShareCalPrewarm<PreparedCloudShare>()
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
    private let zoneChanges = ZoneChangeFeed()

    init(container: CKContainer = CKContainer.default()) {
        self.container = container
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName)
    }

    /// Lets zone reads continue from what this device already downloaded for this
    /// iCloud account (`ZoneChangeFeed`). Without it every read downloads the whole zone.
    func rememberZoneChanges(forAccountID accountID: String) async {
        await zoneChanges.use(accountID: accountID)
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
        do {
            let share = try await saveNewShare(rootRecord: rootRecord, inviteOnly: Self.forcesInviteOnlyShare)
            return PreparedCloudShare(rootRecord: rootRecord, share: share, container: container)
        } catch where CloudKitShareRegionPolicy.refusesLinkShares(error) {
            // This account may not make link shares (China mainland iCloud). An
            // invite-only share is allowed; the partner is then added by phone or email.
            cloudKitSharingInfo("prepareShare link share refused for region; saving invite-only share")
            // The refused share left its reference on the in-memory root; start clean.
            let freshRoot = try await fetchRecordIfPresent(with: rootRecord.recordID) ?? rootRecord
            let share = try await saveNewShare(rootRecord: freshRoot, inviteOnly: true)
            return PreparedCloudShare(rootRecord: freshRoot, share: share, container: container)
        } catch {
            // Another device on the same Apple ID (or an earlier tap still in flight)
            // may have shared the root between our read and our save. Its share is
            // the one to use; only fail if the root still has none.
            guard CloudKitShareRacePolicy.mayHaveLostShareRace(error),
                  let latestRoot = try? await fetchRecordIfPresent(with: rootRecord.recordID),
                  let shareReference = latestRoot.share else {
                throw error
            }
            cloudKitSharingInfo("prepareShare reusing share created elsewhere share=\(shareReference.recordID.recordName)")
            let share = try await fetchShare(with: shareReference.recordID)
            let upgradedShare = try await ensureShareSupportsLinkInvitation(share)
            return PreparedCloudShare(rootRecord: latestRoot, share: upgradedShare, container: container)
        }
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
        try await deleteOwnSettingsZone()
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
        guard !CloudKitShareAccessRequestPolicy.isUninvitedStub(
            containerIdentifier: containerIdentifier,
            zoneOwnerName: metadata.share.recordID.zoneID.ownerName
        ) else {
            cloudKitSharingError("acceptShare refused; metadata is the stub CloudKit returns to someone not let into the share")
            throw CloudKitSharingError.notInvitedToShare
        }
        let started = ContinuousClock.now
        defer { cloudKitSharingInfo("acceptShare finished \(cloudKitElapsed(since: started))") }

        let acceptContainer = CKContainer(identifier: containerIdentifier)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            // The user is watching the card say "confirming"; never leave it there forever.
            let configuration = CKOperation.Configuration()
            configuration.qualityOfService = .userInitiated
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 45
            operation.configuration = configuration

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
                    recordType: EventMirrorRecordMapper.recordType,
                    in: sharedZoneID,
                    database: sharedDatabase
                ).count
                commentCount += try await fetchRecords(
                    recordType: CommentRecordMapper.recordType,
                    in: sharedZoneID,
                    database: sharedDatabase
                ).count
                let invitationRecords = try await fetchRecords(
                    recordType: InvitationRecordMapper.recordType,
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

    /// DEBUG builds only: `-ShareCalForceInviteOnlyShare YES` makes Start Pairing take
    /// the invite-only path, which otherwise needs an account Apple refuses link shares to.
    static var forcesInviteOnlyShare: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "ShareCalForceInviteOnlyShare")
        #else
        return false
        #endif
    }

    func saveNewShare(rootRecord: CKRecord, inviteOnly: Bool = false) async throws -> CKShare {
        cloudKitSharingInfo("saveNewShare begin root=\(rootRecord.recordID.recordName) inviteOnly=\(inviteOnly.description)")
        let share = CKShare(rootRecord: rootRecord)
        if inviteOnly {
            CloudKitSharePermissionPolicy.configureForInviteOnly(share)
        } else {
            CloudKitSharePermissionPolicy.configureForLinkInvitation(share)
        }

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

    // MARK: - Start Pairing failure report

    static let shareProbeZoneName = "OurDaysShareProbe"

    /// Everything this device can find out about a failed Start Pairing, for the user to
    /// send us. Never throws: each part that fails is written into the report instead.
    func pairingShareFailureReport(for error: Error, device: PairingShareFailureReport.Device) async -> PairingShareFailureReport {
        let account = await accountDiagnostic()
        let zones: String
        do {
            let names = try await privateDatabase.allRecordZones().map(\.zoneID.zoneName).sorted()
            zones = names.isEmpty ? "none" : names.joined(separator: ", ")
        } catch {
            zones = "error; \(describeCloudKitFailure(error))"
        }
        let rootState = await shareRootStateDescription()
        let probeLines = account.isAccountAvailable
            ? await shareCreationProbe()
            : ["skipped; account \(account.accountStatus)"]
        let report = PairingShareFailureReport(
            createdAt: Date(),
            environment: CloudKitExpectedConfigurationPolicy.containerEnvironment,
            device: device,
            accountStatus: account.accountStatus,
            userRecordName: account.userRecordName,
            hasUbiquityIdentity: FileManager.default.ubiquityIdentityToken != nil,
            privateZones: zones,
            rootState: rootState,
            failure: describeCloudKitFailure(error),
            probeLines: probeLines
        )
        cloudKitSharingInfo("pairingShareFailureReport \(report.text.replacingOccurrences(of: "\n", with: " | "))")
        return report
    }

    private func shareRootStateDescription() async -> String {
        let rootRecordID = CloudKitShareHierarchyPolicy.rootRecordID(zoneID: zoneID)
        do {
            let root = try await fetchRecord(with: rootRecordID)
            let formatter = ISO8601DateFormatter()
            return [
                "exists",
                "share=\(root.share?.recordID.recordName ?? "none")",
                "created=\(root.creationDate.map(formatter.string(from:)) ?? "unknown")",
                "modified=\(root.modificationDate.map(formatter.string(from:)) ?? "unknown")",
                "changeTag=\(root.recordChangeTag ?? "none")",
                "keys=\(root.allKeys().sorted().joined(separator: ","))"
            ].joined(separator: " ")
        } catch {
            return CloudKitRootLookupPolicy.meansRecordMissing(error)
                ? "missing"
                : "error; \(describeCloudKitFailure(error))"
        }
    }

    /// Tries to make shares in a throwaway zone, to tell apart the reasons a share save
    /// can be rejected. The same link share as Start Pairing working here means the
    /// trouble is what is in the `CoupleSpace` zone; it failing while an invite-only share
    /// works means the account may not make link shares; both failing means the account cannot
    /// share in this container at all. The zone is deleted afterwards.
    func shareCreationProbe() async -> [String] {
        let probeZoneID = CKRecordZone.ID(zoneName: Self.shareProbeZoneName)
        var lines: [String] = []
        // A probe zone left by an interrupted run would make these saves conflict.
        _ = try? await privateDatabase.modifyRecordZones(saving: [], deleting: [probeZoneID])
        do {
            _ = try await privateDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: probeZoneID)], deleting: [])
        } catch {
            return ["zone: failed; \(describeCloudKitFailure(error))"]
        }

        func probeRoot(_ name: String) -> CKRecord {
            let root = CKRecord(recordType: "CoupleSpace", recordID: CKRecord.ID(recordName: name, zoneID: probeZoneID))
            root["createdAt"] = Date() as CKRecordValue
            return root
        }
        let linkRoot = probeRoot("probe-link")
        let linkShare = CKShare(rootRecord: linkRoot)
        CloudKitSharePermissionPolicy.configureForLinkInvitation(linkShare)
        let privateRoot = probeRoot("probe-private")
        // What Start Pairing makes where link shares are refused (decision 0023).
        let requestsRoot = probeRoot("probe-requests")
        let requestsShare = CKShare(rootRecord: requestsRoot)
        CloudKitSharePermissionPolicy.configureForInviteOnly(requestsShare)
        let attempts: [(label: String, records: [CKRecord])] = [
            ("record only", [probeRoot("probe-plain")]),
            ("link share", [linkRoot, linkShare]),
            ("invite-only share", [privateRoot, CKShare(rootRecord: privateRoot)]),
            ("invite-only share + access requests", [requestsRoot, requestsShare])
        ]
        for attempt in attempts {
            let started = ContinuousClock.now
            do {
                _ = try await modifyRecords(saving: attempt.records, deleting: [], savePolicy: .changedKeys, atomically: true)
                lines.append("\(attempt.label): ok \(cloudKitElapsed(since: started))")
            } catch {
                lines.append("\(attempt.label): failed; \(describeCloudKitFailure(error))")
            }
        }

        do {
            _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [probeZoneID])
        } catch {
            lines.append("cleanup: failed; \(describeCloudKitFailure(error))")
        }
        return lines
    }

    /// An invite-only share made before access requests existed (or by an older build)
    /// gets them turned on, so the partner can ask to join from the link. Only that
    /// flag changes: `publicPermission` stays `.none`. A failed save leaves the share
    /// as it was; Apple's panel can still add the partner.
    private func ensureAllowsAccessRequests(_ share: CKShare) async -> CKShare {
        guard CloudKitSharePermissionPolicy.isInviteOnly(share),
              CloudKitSharePermissionPolicy.allowsAccessRequests(share) == false else { return share }
        CloudKitSharePermissionPolicy.configureForInviteOnly(share)
        do {
            let saved = try await saveShare(share)
            cloudKitSharingInfo("ensureAllowsAccessRequests turned on share=\(saved.recordID.recordName)")
            return saved
        } catch {
            cloudKitSharingError("ensureAllowsAccessRequests save failed share=\(share.recordID.recordName) error=\(describeCloudKitFailure(error))")
            return share
        }
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

        guard !Self.forcesInviteOnlyShare else { return await ensureAllowsAccessRequests(share) }
        cloudKitSharingInfo(
            "ensureShareSupportsLinkInvitation upgrading share=\(share.recordID.recordName) currentPermission=\(String(describing: share.publicPermission))"
        )
        CloudKitSharePermissionPolicy.configureForLinkInvitation(share)

        let result: CloudKitModifyRecordResults
        do {
            result = try await modifyRecords(saving: [share], deleting: [], savePolicy: .changedKeys, atomically: false)
        } catch where CloudKitShareRegionPolicy.refusesLinkShares(error) {
            // The invite-only share this account fell back to: it stays invite-only.
            cloudKitSharingInfo("ensureShareSupportsLinkInvitation link share refused for region; keeping invite-only share=\(share.recordID.recordName)")
            return await ensureAllowsAccessRequests(try await fetchShare(with: share.recordID))
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
        var attempt = 1
        while true {
            do {
                return try await fetchRecord(with: recordID)
            } catch {
                if CloudKitRootLookupPolicy.meansRecordMissing(error) {
                    cloudKitSharingInfo("root lookup found no record=\(recordID.recordName); creating root")
                    return nil
                }
                // A rejected read says nothing about whether the root exists (cross-region
                // China↔US requests return transient 15s). Treating it as missing used to
                // write a fresh root over a shared one and then fail to share it again.
                guard attempt < CloudKitRootLookupPolicy.maxAttempts,
                      CloudKitRootLookupPolicy.isWorthRetrying(error) else {
                    throw error
                }
                cloudKitSharingInfo("root lookup rejected record=\(recordID.recordName) attempt=\(attempt) error=\(describeCloudKitFailure(error)); retrying")
                attempt += 1
                try await Task.sleep(for: .seconds(2))
            }
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
            var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
            for batch in CloudKitBatchSizePolicy.batches(uniqueRecordIDs) {
                let batchResults = try await withCheckedThrowingContinuation { continuation in
                    targetDatabase.fetch(withRecordIDs: batch) { result in
                        continuation.resume(with: result)
                    }
                }
                results.merge(batchResults) { _, new in new }
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
        for batch in CloudKitBatchSizePolicy.batches(records) {
            _ = try await modifyRecords(saving: batch, deleting: [], savePolicy: .changedKeys, atomically: false)
        }
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
        for batch in CloudKitBatchSizePolicy.batches(recordIDs) {
            _ = try await modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
        }
        cloudKitSharingInfo("deleteMirrorsForSync succeeded count=\(recordIDs.count)")
    }

    /// Deletes comment records from MY private zone (the threads of events whose
    /// tombstones are purged, `EventTombstonePurgePolicy`).
    func deleteOwnZoneCommentsForSync(_ comments: [EventComment]) async throws {
        let recordIDs = CloudKitBatchUpsertPolicy.recordIDs(forComments: comments, zoneID: zoneID)
        guard !recordIDs.isEmpty else { return }
        for batch in CloudKitBatchSizePolicy.batches(recordIDs) {
            _ = try await modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
        }
        cloudKitSharingInfo("deleteOwnZoneCommentsForSync succeeded count=\(recordIDs.count)")
    }

    /// Saves my MemberProfile unless the copy in the cloud is the newer edit (made on
    /// another device of the same Apple ID); then nothing is written and that copy is
    /// returned for the caller to adopt (`OwnMemberProfileMergePolicy`).
    @discardableResult
    func saveMemberProfileForSync(
        ownerMemberID: String,
        displayName: String,
        avatar: MemberAvatar? = nil,
        localUpdatedAt: Date? = nil
    ) async throws -> CloudKitMemberProfile? {
        try await ensureZone()
        try await ensureShareRoot(ownerMemberID: ownerMemberID)
        let recordID = CKRecord.ID(
            recordName: MemberProfileRecordMapper.recordName(ownerMemberID: ownerMemberID),
            zoneID: zoneID
        )
        let cloudProfile = try await fetchRecordForUpsertIfPresent(with: recordID, database: privateDatabase)
            .flatMap { try? MemberProfileRecordMapper.memberProfile(from: $0) }
        switch OwnMemberProfileMergePolicy.decide(
            localDisplayName: displayName,
            localAvatar: avatar,
            localUpdatedAt: localUpdatedAt,
            cloud: cloudProfile
        ) {
        case .unchanged:
            cloudKitSharingInfo("saveMemberProfileForSync skipped; cloud copy matches")
            return nil
        case .adoptCloud(let newer):
            cloudKitSharingInfo("saveMemberProfileForSync skipped; cloud copy is newer updatedAt=\(newer.updatedAt)")
            return newer
        case .upload:
            break
        }
        let profile = CloudKitMemberProfile(
            ownerMemberID: ownerMemberID,
            displayName: displayName,
            updatedAt: localUpdatedAt ?? .now,
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
        return nil
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
            await sendNudge(
                PartnerNudgePolicy.nudge(afterSaving: invitation, currentMemberID: currentMemberID),
                partnerMemberID: invitation.inviteeMemberID,
                knownPartnerZoneID: nil
            )
        case .acceptedSharedZone:
            let targetZoneID = try await acceptedSharedZoneID(containingInvitationRecordName: invitation.cloudKitRecordName ?? invitation.id)
            try await saveInvitationsForSync([invitation], in: targetZoneID, database: sharedDatabase)
            await sendNudge(
                PartnerNudgePolicy.nudge(afterSaving: invitation, currentMemberID: currentMemberID),
                partnerMemberID: invitation.creatorMemberID,
                knownPartnerZoneID: targetZoneID
            )
        }
    }

    /// Drops a nudge into the partner's zone so iCloud shows them a push right away
    /// (notifications decision 0005). Best-effort and silent: a partner on an older
    /// schema, a nudge that already exists, or no accepted share just means they hear
    /// about it the old way, after their next sync.
    @MainActor
    private func sendNudge(
        _ nudge: PartnerNudge?,
        partnerMemberID: String,
        knownPartnerZoneID: CKRecordZone.ID?
    ) async {
        guard let nudge else { return }
        do {
            let partnerZoneID: CKRecordZone.ID
            if let knownPartnerZoneID {
                partnerZoneID = knownPartnerZoneID
            } else {
                partnerZoneID = try await acceptedSharedZoneID(ownerMemberID: partnerMemberID)
            }
            let record = CKRecord(
                recordType: PartnerNudgePolicy.recordType,
                recordID: CKRecord.ID(
                    recordName: PartnerNudgePolicy.recordName(kind: nudge.kind, subjectID: nudge.subjectID),
                    zoneID: partnerZoneID
                )
            )
            CloudKitShareHierarchyPolicy.attach(
                record,
                toShareRoot: CloudKitShareHierarchyPolicy.rootRecordID(zoneID: partnerZoneID)
            )
            record[PartnerNudgePolicy.kindKey] = nudge.kind.rawValue as CKRecordValue
            record[PartnerNudgePolicy.textKey] = nudge.text as CKRecordValue
            _ = try await modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: false,
                database: sharedDatabase
            )
            cloudKitSharingInfo("sendNudge saved record=\(record.recordID.recordName) zoneOwner=\(partnerZoneID.ownerName)")
        } catch {
            cloudKitSharingInfo("sendNudge skipped kind=\(nudge.kind.rawValue) error=\(describeCloudKitFailure(error))")
        }
    }

    /// Deletes the nudges in my zone older than `PartnerNudgePolicy.retention`; they
    /// only exist to fire a push once. Best-effort.
    func purgeExpiredPartnerNudges(now: Date = .now) async {
        do {
            // Only the record ID and creation date are used, so the type needs no
            // entry in CloudKitForegroundQueryPolicy (no keys are read).
            let expired = try await fetchRecords(
                recordType: PartnerNudgePolicy.recordType,
                in: zoneID,
                database: privateDatabase
            )
            .filter { PartnerNudgePolicy.isExpired(createdAt: $0.creationDate, now: now) }
            guard !expired.isEmpty else { return }
            _ = try await modifyRecords(
                saving: [],
                deleting: expired.map(\.recordID),
                savePolicy: .changedKeys,
                atomically: false
            )
        } catch {
            cloudKitSharingInfo("purgeExpiredPartnerNudges failed error=\(describeCloudKitFailure(error))")
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

    /// Write an existing comment back to the zone it was fetched from (see
    /// `fetchEventCommentsByZone`): my private zone, or the partner's shared zone.
    @MainActor
    func saveCommentForSync(_ comment: EventComment, inFetchedZone targetZoneID: CKRecordZone.ID) async throws {
        let database = targetZoneID == zoneID ? privateDatabase : sharedDatabase
        try await saveCommentsForSync([comment], in: targetZoneID, database: database)
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

    /// My own records for these stable keys (live or deleted), found by query instead of
    /// reading the whole zone: what the iPhone asks before starting a record for an event
    /// a Mac of mine may have uploaded already (`OwnRecordAdoptionPolicy`).
    func fetchOwnEventMirrors(stableKeys: Set<String>, currentMemberID: String) async throws -> [EventMirror] {
        let keys = stableKeys.filter { !$0.isEmpty }.sorted()
        guard !keys.isEmpty else { return [] }
        var records: [CKRecord] = []
        do {
            for batch in CloudKitBatchSizePolicy.batches(keys, size: 100) {
                let query = CKQuery(
                    recordType: EventMirrorRecordMapper.recordType,
                    predicate: NSPredicate(format: "%K IN %@", EventMirrorRecordMapper.Key.stableKey, batch)
                )
                var page = try await privateDatabase.records(
                    matching: query,
                    inZoneWith: zoneID,
                    desiredKeys: CloudKitForegroundQueryPolicy.desiredKeys(forRecordType: EventMirrorRecordMapper.recordType)
                )
                while true {
                    records.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
                    guard let cursor = page.queryCursor else { break }
                    page = try await privateDatabase.records(continuingMatchFrom: cursor)
                }
            }
        } catch {
            guard CloudKitRecordQueryFailurePolicy.isMissingZone(error) else {
                cloudKitSharingError("fetchOwnEventMirrors(stableKeys:) failed error=\(describeCloudKitFailure(error))")
                throw error
            }
            return []
        }
        let mirrors = try records.map { try EventMirrorRecordMapper.eventMirror(from: $0) }
        cloudKitSharingInfo("fetchOwnEventMirrors(stableKeys:) keys=\(keys.count) records=\(mirrors.count)")
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
        // Every nudge in my zone was written by the ex-partner.
        let nudgeRecordIDs = ((try? await fetchRecords(
            recordType: PartnerNudgePolicy.recordType,
            in: zoneID,
            database: privateDatabase
        )) ?? []).map(\.recordID)
        let recordIDs = CloudKitExPartnerCleanupPolicy.recordIDsToDelete(
            commentRecords: commentRecords,
            invitationRecords: invitationRecords,
            currentMemberID: currentMemberID
        ) + nudgeRecordIDs
        guard !recordIDs.isEmpty else {
            cloudKitSharingInfo("purgeExPartnerRecordsFromPrivateZone nothing to delete")
            return
        }
        for batch in CloudKitBatchSizePolicy.batches(recordIDs) {
            _ = try await modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
        }
        cloudKitSharingInfo("purgeExPartnerRecordsFromPrivateZone deleted records=\(recordIDs.count)")
    }

    #if DEBUG
    /// Test-harness only (`-ShareCalPurgeSmokeTestData`): deletes EVERY comment and
    /// invitation / history-access-request record from my private zone, so a smoke run on
    /// the reused test accounts starts without the threads of earlier runs. Event mirrors
    /// stay: the next sync rebuilds them from the calendar. Returns how many were deleted.
    func purgeSmokeTestRecordsFromPrivateZone() async throws -> Int {
        let records: [CKRecord]
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
            records = try await comments + invitations
        } catch {
            guard CloudKitRecordQueryFailurePolicy.isMissingZone(error) else { throw error }
            cloudKitSharingInfo("purgeSmokeTestRecordsFromPrivateZone zone missing; nothing to clean")
            return 0
        }
        for batch in CloudKitBatchSizePolicy.batches(records.map(\.recordID)) {
            _ = try await modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
        }
        cloudKitSharingInfo("purgeSmokeTestRecordsFromPrivateZone deleted records=\(records.count)")
        return records.count
    }

    /// Test-harness only (`-ShareCalHardDeleteOwnTombstones`): deletes every tombstoned
    /// event record from my private zone, so the partner's next read gets real record
    /// deletions from the server. Returns how many were deleted.
    func hardDeleteOwnTombstonesForSmoke() async throws -> Int {
        let recordIDs = try await fetchRecords(
            recordType: EventMirrorRecordMapper.recordType,
            in: zoneID,
            database: privateDatabase
        )
        .filter { ($0[EventMirrorRecordMapper.Key.deletedAt] as? Date) != nil }
        .map(\.recordID)
        for batch in CloudKitBatchSizePolicy.batches(recordIDs) {
            _ = try await modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
        }
        cloudKitSharingInfo("hardDeleteOwnTombstonesForSmoke deleted records=\(recordIDs.count)")
        return recordIDs.count
    }
    #endif

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
            for zoneID in zoneIDs {
                await zoneChanges.forget(zoneID: zoneID, database: sharedDatabase)
            }
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
        try await fetchEventCommentsByZone(sharedZoneIDs: sharedZoneIDs).flatMap(\.comments)
    }

    /// Comments grouped by the zone they were read from (my private zone first), so a
    /// later write to an existing comment (a delete re-upload) goes back to that zone.
    func fetchEventCommentsByZone(
        sharedZoneIDs: [CKRecordZone.ID]
    ) async throws -> [(zoneID: CKRecordZone.ID, comments: [EventComment])] {
        async let privateRecords = fetchRecords(
            recordType: CommentRecordMapper.recordType,
            in: zoneID,
            database: privateDatabase
        )
        async let sharedRecordsByZone = fetchRecordsByZone(
            recordType: CommentRecordMapper.recordType,
            in: sharedZoneIDs,
            database: sharedDatabase
        )
        let recordsByZone = try await [(zoneID: zoneID, records: privateRecords)] + sharedRecordsByZone

        cloudKitSharingInfo("fetchEventComments fetched records=\(recordsByZone.reduce(0) { $0 + $1.records.count })")
        return try recordsByZone.map { zone in
            (zoneID: zone.zoneID, comments: try zone.records.map { try CommentRecordMapper.comment(from: $0) })
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

    /// The zone's records of one type. The zone itself is read once per sync and only
    /// for what changed since the last read (`ZoneChangeFeed`), whatever the type asked.
    private func fetchRecords(
        recordType: String,
        in zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> [CKRecord] {
        try await zoneChanges.records(in: zoneID, database: database)
            .filter { $0.recordType == recordType }
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

    /// Visible push for the partner's new comments on MY events (notifications decision
    /// 0004). Those records are created in my own zone, so this is a private-database
    /// query subscription: one record type, creation only (edits and deletes stay
    /// quiet), with the comment text as the alert body. Saved under a fixed id, so
    /// calling it again just refreshes the title.
    func configureCommentAlertSubscription(currentMemberID: String, title: String) async throws {
        let subscription = CKQuerySubscription(
            recordType: CommentRecordMapper.recordType,
            predicate: NSPredicate(format: CommentAlertPushPolicy.predicateFormat, currentMemberID),
            subscriptionID: CommentAlertPushPolicy.subscriptionID,
            options: [.firesOnRecordCreation]
        )
        subscription.zoneID = zoneID
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.title = title
        notificationInfo.alertLocalizationKey = CommentAlertPushPolicy.bodyFormatKey
        notificationInfo.alertLocalizationArgs = CommentAlertPushPolicy.bodyArgumentKeys
        notificationInfo.soundName = "default"
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

    /// One visible-push subscription per nudge kind on my private database (decision
    /// 0005): each kind has its own fixed title, the body is the nudge's `text`.
    func configureNudgeSubscriptions(titles: [PartnerNudgeKind: String]) async throws {
        let subscriptions: [CKSubscription] = PartnerNudgeKind.allCases.compactMap { kind in
            guard let title = titles[kind] else { return nil }
            let subscription = CKQuerySubscription(
                recordType: PartnerNudgePolicy.recordType,
                predicate: NSPredicate(format: PartnerNudgePolicy.predicateFormat, kind.rawValue),
                subscriptionID: PartnerNudgePolicy.subscriptionID(for: kind),
                options: [.firesOnRecordCreation]
            )
            subscription.zoneID = zoneID
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.title = title
            notificationInfo.alertLocalizationKey = PartnerNudgePolicy.bodyFormatKey
            notificationInfo.alertLocalizationArgs = PartnerNudgePolicy.bodyArgumentKeys
            notificationInfo.soundName = "default"
            subscription.notificationInfo = notificationInfo
            return subscription
        }
        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: subscriptions,
            subscriptionIDsToDelete: nil
        )
        try await withCheckedThrowingContinuation { continuation in
            operation.modifySubscriptionsResultBlock = { result in
                continuation.resume(with: result)
            }
            privateDatabase.add(operation)
        }
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

// MARK: - Settings that follow me to my other devices (pairing-sync-integrity 0013)

extension CloudKitCoupleSpaceService {
    var ownSettingsZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: OwnSettingsRecordMapper.zoneName)
    }

    private var ownSettingsRecordID: CKRecord.ID {
        CKRecord.ID(recordName: OwnSettingsRecordMapper.recordName, zoneID: ownSettingsZoneID)
    }

    /// My settings as my other devices last saved them; nil when none has yet.
    func fetchOwnSettings() async throws -> OwnRelayedSettings? {
        guard let record = try await fetchOwnSettingsRecord() else { return nil }
        return try OwnSettingsRecordMapper.settings(from: record)
    }

    /// Writes `settings` over the stored copy. A copy another device saved in between
    /// makes this fail with `serverRecordChanged`; the next sync merges with it.
    func saveOwnSettings(_ settings: OwnRelayedSettings) async throws {
        let existing = try await fetchOwnSettingsRecord()
        if existing == nil {
            _ = try await privateDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: ownSettingsZoneID)], deleting: [])
        }
        let record = existing ?? CKRecord(recordType: OwnSettingsRecordMapper.recordType, recordID: ownSettingsRecordID)
        try OwnSettingsRecordMapper.apply(settings, to: record)
        let (saveResults, _) = try await privateDatabase.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        _ = try saveResults[record.recordID]?.get()
        cloudKitSharingInfo("saveOwnSettings succeeded")
    }

    private func fetchOwnSettingsRecord() async throws -> CKRecord? {
        do {
            return try await privateDatabase.record(for: ownSettingsRecordID)
        } catch {
            if CloudKitZoneReadinessPolicy.meansZoneMissing(error) { return nil }
            let nsError = error as NSError
            if nsError.domain == CKError.errorDomain, CKError.Code(rawValue: nsError.code) == .unknownItem {
                return nil
            }
            throw error
        }
    }

    func deleteOwnSettingsZone() async throws {
        do {
            _ = try await privateDatabase.modifyRecordZones(saving: [], deleting: [ownSettingsZoneID])
        } catch where CloudKitZoneReadinessPolicy.meansZoneMissing(error) {
            return
        } catch {
            let nsError = error as NSError
            if nsError.domain == CKError.errorDomain, CKError.Code(rawValue: nsError.code) == .unknownItem { return }
            throw error
        }
    }
}

// MARK: - Share access requests (iOS 26+)

/// What the owner's share looks like to the access-request flow, for diagnostics.
struct OutgoingShareAccessState {
    var shareRecordName: String
    var publicPermission: CKShare.ParticipantPermission
    var allowsAccessRequests: Bool?
    var urlPresent: Bool
    var participantLines: [String]
    var requesters: [ShareAccessRequesterIdentityPresence]

    var logDescription: String {
        [
            "share=\(shareRecordName)",
            "publicPermission=\(publicPermission.rawValue)",
            "allowsAccessRequests=\(allowsAccessRequests.map(String.init(describing:)) ?? "unavailable")",
            "url=\(urlPresent)",
            "participants=[\(participantLines.joined(separator: "; "))]",
            CloudKitShareAccessRequestPolicy.logDescription(requesters)
        ].joined(separator: " ")
    }
}

/// The access-request flow for callers that must also build without the iOS 26 SDK
/// and run on older systems: there each one does nothing.
extension CloudKitCoupleSpaceService {
    static var supportsShareAccessRequests: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macCatalyst 26.0, *) { return true }
        #endif
        return false
    }

    /// Partner side. Returns false where access requests do not exist.
    func requestShareAccessIfSupported(url: URL) async throws -> Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            try await requestShareAccess(url: url)
            return true
        }
        #endif
        return false
    }

    /// Owner side: who is asking to join my share, or nil when that cannot matter (no
    /// share, a link share, somebody already joined, or no access requests on this OS).
    func pendingShareAccessRequesters() async throws -> [ShareAccessRequester]? {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return try await currentShareAccessRequesters()
        }
        #endif
        return nil
    }

    /// Owner side: lets the requester in, read-write. False when they are no longer
    /// waiting (approved or withdrawn meanwhile).
    func approveShareAccessRequester(id: String) async throws -> Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return try await approveRequester(id: id)
        }
        #endif
        return false
    }

    /// Owner side: turns the request down. They may ask again.
    func denyShareAccessRequester(id: String) async throws {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            try await denyRequester(id: id)
        }
        #endif
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, macCatalyst 26.0, *)
extension CloudKitCoupleSpaceService {
    private func requesterValues(of share: CKShare) -> [(value: ShareAccessRequester, requester: CKShare.AccessRequester)] {
        share.requesters.enumerated().map { index, requester in
            let recordName = requester.participantLookupInfo.userRecordID?.recordName
                ?? requester.userIdentity.userRecordID?.recordName
            // Name components only: never the email address or phone number, and never
            // `requester.contact`, which asks for Contacts access (TCC kills the app).
            let name = requester.userIdentity.nameComponents.map {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
            }
            let value = ShareAccessRequester(
                id: recordName ?? "requester-\(index)",
                userRecordID: recordName,
                displayName: name
            )
            return (value, requester)
        }
    }

    fileprivate func currentShareAccessRequesters() async throws -> [ShareAccessRequester]? {
        try await ensureZone()
        guard let share = try await fetchOutgoingShare() else { return nil }
        let acceptedIDs = CloudKitShareParticipantIdentityPolicy.acceptedParticipantIDs(from: share)
        guard CloudKitShareAccessRequestPolicy.shouldCheckRequesters(
            shareIsInviteOnly: CloudKitSharePermissionPolicy.isInviteOnly(share),
            acceptedParticipantIDs: acceptedIDs
        ) else { return nil }
        let requesters = requesterValues(of: share).map(\.value)
        cloudKitSharingInfo("pendingShareAccessRequesters count=\(requesters.count)")
        return requesters
    }

    fileprivate func approveRequester(id: String) async throws -> Bool {
        try await ensureZone()
        guard let share = try await fetchOutgoingShare(),
              let match = requesterValues(of: share).first(where: { $0.value.id == id }) else {
            cloudKitSharingInfo("approveRequester skipped; requester no longer waiting")
            return false
        }
        // Two people only: someone may have joined since the card was drawn.
        guard CloudKitShareParticipantIdentityPolicy.acceptedParticipantIDs(from: share).isEmpty else {
            cloudKitSharingInfo("approveRequester skipped; someone already joined")
            return false
        }
        let lookupInfo = match.requester.participantLookupInfo
        guard let lookup = try await container.shareParticipants(for: [lookupInfo])[lookupInfo] else {
            cloudKitSharingError("approveRequester lookup returned nothing")
            throw CloudKitSharingError.requesterLookupFailed
        }
        let participant = try lookup.get()
        participant.permission = .readWrite
        share.addParticipant(participant)
        do {
            _ = try await saveShare(share)
        } catch {
            cloudKitSharingError("approveRequester save failed error=\(describeCloudKitFailure(error))")
            throw error
        }
        cloudKitSharingInfo("approveRequester succeeded userRecordID=\(match.value.userRecordID != nil)")
        return true
    }

    fileprivate func denyRequester(id: String) async throws {
        try await ensureZone()
        guard let share = try await fetchOutgoingShare(),
              let match = requesterValues(of: share).first(where: { $0.value.id == id }) else { return }
        share.denyRequesters([match.requester])
        do {
            _ = try await saveShare(share)
        } catch {
            cloudKitSharingError("denyRequester save failed error=\(describeCloudKitFailure(error))")
            throw error
        }
        cloudKitSharingInfo("denyRequester succeeded")
    }

    /// Partner side: asks the owner of the share behind `url` to let me in. CloudKit
    /// answers the same whether or not the share exists (it does not disclose shares).
    func requestShareAccess(url: URL) async throws {
        cloudKitSharingInfo("requestShareAccess begin")
        let started = ContinuousClock.now
        let errors = CloudKitRequestAccessErrors()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKShareRequestAccessOperation(shareURLs: [url])
            operation.perShareAccessRequestResultBlock = { _, result in
                switch result {
                case .success:
                    cloudKitSharingInfo("requestShareAccess perShare succeeded")
                case .failure(let error):
                    cloudKitSharingError("requestShareAccess perShare failed error=\(describeCloudKitFailure(error))")
                    errors.set(error)
                }
            }
            operation.shareAccessRequestResultBlock = { result in
                cloudKitSharingInfo("requestShareAccess finished \(cloudKitElapsed(since: started))")
                switch result {
                case .success:
                    if let error = errors.first {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                case .failure(let error):
                    cloudKitSharingError("requestShareAccess failed error=\(describeCloudKitFailure(error))")
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    /// What `fetchShareMetadata` gives this account for `url`, field presence only.
    func shareMetadataAccessDescription(url: URL) async -> String {
        do {
            let metadata = try await fetchShareMetadata(from: url)
            let share = metadata.share
            return [
                "containerIdentifierEmpty=\(metadata.containerIdentifier.isEmpty)",
                "ownerNameEmpty=\(share.recordID.zoneID.ownerName.isEmpty)",
                "participantStatus=\(metadata.participantStatus.rawValue)",
                "participantRole=\(metadata.participantRole.rawValue)",
                "participantPermission=\(metadata.participantPermission.rawValue)",
                "rootRecordID=\(metadata.hierarchicalRootRecordID != nil)",
                "sharePublicPermission=\(share.publicPermission.rawValue)",
                "shareAllowsAccessRequests=\(share.allowsAccessRequests)",
                "shareParticipants=\(share.participants.count)",
                "ownerUserRecordID=\(metadata.ownerIdentity.userRecordID != nil)"
            ].joined(separator: " ")
        } catch {
            return "failed \(describeCloudKitFailure(error))"
        }
    }

    /// Owner side: the share as the server has it now, with who is asking to join.
    func outgoingShareAccessState() async throws -> OutgoingShareAccessState? {
        try await ensureZone()
        guard let share = try await fetchOutgoingShare() else {
            cloudKitSharingInfo("outgoingShareAccessState skipped; share missing")
            return nil
        }
        let participantLines = share.participants.map { participant in
            [
                "role=\(participant.role.rawValue)",
                "acceptance=\(participant.acceptanceStatus.rawValue)",
                "permission=\(participant.permission.rawValue)",
                "approvedRequester=\(participant.isApprovedRequester)",
                "userRecordID=\(participant.userIdentity.userRecordID != nil)"
            ].joined(separator: ",")
        }
        let requesters = share.requesters.map { requester in
            let identity = requester.userIdentity
            let lookup = requester.participantLookupInfo
            return ShareAccessRequesterIdentityPresence(
                hasNameComponents: identity.nameComponents != nil,
                hasEmailAddress: lookup.emailAddress != nil || identity.lookupInfo?.emailAddress != nil,
                hasPhoneNumber: lookup.phoneNumber != nil || identity.lookupInfo?.phoneNumber != nil,
                // `requester.contact` is not read: it asks for Contacts access, and an
                // app without NSContactsUsageDescription is killed by TCC.
                hasUserRecordID: lookup.userRecordID != nil || identity.userRecordID != nil
            )
        }
        let state = OutgoingShareAccessState(
            shareRecordName: share.recordID.recordName,
            publicPermission: share.publicPermission,
            allowsAccessRequests: share.allowsAccessRequests,
            urlPresent: share.url != nil,
            participantLines: participantLines,
            requesters: requesters
        )
        cloudKitSharingInfo("outgoingShareAccessState \(state.logDescription)")
        return state
    }

    /// Owner side: lets everyone who asked to join in, read-write. Returns how many
    /// were added. Each requester becomes a participant through a lookup of their
    /// `participantLookupInfo`; the share is saved once.
    func approveShareRequesters() async throws -> Int {
        try await ensureZone()
        guard let share = try await fetchOutgoingShare() else {
            cloudKitSharingInfo("approveShareRequesters skipped; share missing")
            return 0
        }
        let requesters = share.requesters
        cloudKitSharingInfo("approveShareRequesters begin requesters=\(requesters.count)")
        guard !requesters.isEmpty else { return 0 }

        let lookups = try await container.shareParticipants(for: requesters.map(\.participantLookupInfo))
        var added = 0
        for (_, result) in lookups {
            switch result {
            case .success(let participant):
                participant.permission = .readWrite
                share.addParticipant(participant)
                added += 1
            case .failure(let error):
                cloudKitSharingError("approveShareRequesters lookup failed error=\(describeCloudKitFailure(error))")
            }
        }
        guard added > 0 else { return 0 }
        do {
            _ = try await saveShare(share)
        } catch {
            cloudKitSharingError("approveShareRequesters save failed error=\(describeCloudKitFailure(error))")
            throw error
        }
        cloudKitSharingInfo("approveShareRequesters succeeded added=\(added)")
        return added
    }
}

/// The first per-share failure of a `CKShareRequestAccessOperation`, which reports the
/// overall result separately.
private final class CloudKitRequestAccessErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?

    func set(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        if stored == nil { stored = error }
    }

    var first: Error? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}
#endif
