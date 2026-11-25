@preconcurrency import CloudKit
import Foundation

/// Where zone snapshots are kept on disk. In Caches on purpose: losing a file only costs
/// one whole download of that zone.
struct ZoneChangeSnapshotStore {
    let directory: URL

    static var standard: ZoneChangeSnapshotStore {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ZoneChangeSnapshotStore(directory: caches.appendingPathComponent("ZoneChanges", isDirectory: true))
    }

    func load(fileName: String) -> ZoneChangeSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? PropertyListDecoder().decode(ZoneChangeSnapshot.self, from: data)
    }

    func save(_ snapshot: ZoneChangeSnapshot, fileName: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    func remove(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}

/// What one `CKFetchRecordZoneChangesOperation` reported for a zone.
struct ZoneChangeDelta {
    enum Change {
        case saved(CKRecord)
        case deleted(CKRecord.ID)
    }

    var changes: [Change] = []
    var token: CKServerChangeToken?
    /// Records the server could not hand over. The token already points past them, so a
    /// fetch with any of these must not be remembered.
    var failedRecordCount = 0
}

/// Reads a zone the incremental way: the first read downloads it whole, later reads ask
/// only for what changed since and apply that to the remembered snapshot. Callers always
/// get every record of the zone, so "the partner no longer has this event" stays a plain
/// comparison against the full list, and a record disappears from that list only when
/// the server reports its deletion.
///
/// Reads of one zone that overlap share a single fetch: a sync asks for mirrors,
/// comments, invitations and profiles at once and pays one round trip per zone.
actor ZoneChangeFeed {
    private struct Zone {
        var snapshot: ZoneChangeSnapshot
        var token: CKServerChangeToken
        var recordsByName: [String: CKRecord]
    }

    private let store: ZoneChangeSnapshotStore
    private let recordTypes: Set<String>
    private let desiredKeys: [String]
    private let signature: String
    private let environment: String

    private var accountID: String?
    private var zonesByFileName: [String: Zone] = [:]
    private var inFlight: [String: Task<[CKRecord], Error>] = [:]

    init(
        store: ZoneChangeSnapshotStore = .standard,
        recordTypes: [String] = CloudKitForegroundQueryPolicy.zoneFetchRecordTypes,
        desiredKeys: [String] = CloudKitForegroundQueryPolicy.zoneFetchDesiredKeys,
        environment: String = CloudKitExpectedConfigurationPolicy.containerEnvironment
    ) {
        self.store = store
        self.recordTypes = Set(recordTypes)
        self.desiredKeys = desiredKeys
        self.signature = ZoneChangeCachePolicy.signature(recordTypes: recordTypes, desiredKeys: desiredKeys)
        self.environment = environment
    }

    /// Snapshots are kept per iCloud account. Until the account is known nothing is
    /// remembered and every read downloads the zone whole.
    func use(accountID: String?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        zonesByFileName.removeAll()
    }

    /// Every record of the zone (of the types a sync reads), sorted by record name.
    func records(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        let scope = database.databaseScope == .shared ? "shared" : "private"
        let fileName = accountID.map {
            ZoneChangeCachePolicy.fileName(
                accountID: $0,
                environment: environment,
                databaseScope: scope,
                zoneOwnerName: zoneID.ownerName,
                zoneName: zoneID.zoneName
            )
        }
        let flightKey = fileName ?? "unremembered.\(scope).\(zoneID.ownerName).\(zoneID.zoneName)"
        if let running = inFlight[flightKey] {
            return try await running.value
        }
        let task = Task {
            try await self.refresh(zoneID: zoneID, database: database, fileName: fileName, flightKey: flightKey)
        }
        inFlight[flightKey] = task
        return try await task.value
    }

    private func refresh(
        zoneID: CKRecordZone.ID,
        database: CKDatabase,
        fileName: String?,
        flightKey: String
    ) async throws -> [CKRecord] {
        // Cleared before the task ends, so a read that starts after this fetch finished
        // (say, right after a write) never gets this older answer.
        defer { inFlight[flightKey] = nil }

        let startedAt = Date()
        var base = fileName.flatMap { resumableZone(fileName: $0, now: startedAt) }
        let delta: ZoneChangeDelta
        do {
            delta = try await Self.fetchChanges(
                in: zoneID,
                database: database,
                since: base?.token,
                desiredKeys: desiredKeys
            )
        } catch let error where base != nil && ZoneChangeCachePolicy.tokenIsUnusable(error) {
            cloudKitSharingInfo("fetchZoneChanges token no longer usable; downloading whole zone=\(zoneID.zoneName) owner=\(zoneID.ownerName)")
            forget(fileName: fileName)
            base = nil
            delta = try await Self.fetchChanges(in: zoneID, database: database, since: nil, desiredKeys: desiredKeys)
        } catch {
            if CloudKitZoneReadinessPolicy.meansZoneMissing(error) {
                // The zone is gone and so is everything it held.
                forget(fileName: fileName)
            }
            cloudKitSharingError(
                "fetchZoneChanges failed zone=\(zoneID.zoneName) owner=\(zoneID.ownerName) error=\(describeCloudKitFailure(error))"
            )
            throw error
        }

        var recordsByName = base?.recordsByName ?? [:]
        var events: [ZoneChangeEvent] = []
        var canRemember = delta.failedRecordCount == 0
        var savedCount = 0
        var deletedCount = 0
        for change in delta.changes {
            switch change {
            case .saved(let record):
                guard recordTypes.contains(record.recordType) else { continue }
                let recordName = record.recordID.recordName
                recordsByName[recordName] = record
                savedCount += 1
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true) {
                    events.append(.saved(recordName: recordName, data: data))
                } else {
                    canRemember = false
                }
            case .deleted(let recordID):
                if recordsByName.removeValue(forKey: recordID.recordName) != nil {
                    deletedCount += 1
                }
                events.append(.deleted(recordName: recordID.recordName))
            }
        }

        if let fileName {
            if canRemember,
               let token = delta.token,
               let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                let snapshot = ZoneChangeCachePolicy.merged(
                    base: base?.snapshot,
                    events: events,
                    tokenData: tokenData,
                    signature: signature,
                    now: startedAt
                )
                if snapshot != base?.snapshot {
                    do {
                        try store.save(snapshot, fileName: fileName)
                    } catch {
                        cloudKitSharingError("fetchZoneChanges could not save snapshot error=\(error.localizedDescription)")
                    }
                }
                zonesByFileName[fileName] = Zone(snapshot: snapshot, token: token, recordsByName: recordsByName)
            } else if base == nil {
                // A whole download that cannot be remembered: nothing to continue from.
                forget(fileName: fileName)
            }
            // Otherwise the old snapshot and token stay, and the next read asks for the
            // same changes again.
        }

        cloudKitSharingInfo(
            String(
                format: "fetchZoneChanges zone=%@ owner=%@ scope=%@ mode=%@ changed=%d deleted=%d failed=%d total=%d elapsed=%.3fs",
                zoneID.zoneName,
                zoneID.ownerName,
                database.databaseScope == .shared ? "shared" : "private",
                base == nil ? "full" : "delta",
                savedCount,
                deletedCount,
                delta.failedRecordCount,
                recordsByName.count,
                Date().timeIntervalSince(startedAt)
            )
        )
        return recordsByName.values.sorted { $0.recordID.recordName < $1.recordID.recordName }
    }

    /// Drops what is remembered about a zone, e.g. after leaving the partner's share.
    func forget(zoneID: CKRecordZone.ID, database: CKDatabase) {
        guard let accountID else { return }
        forget(fileName: ZoneChangeCachePolicy.fileName(
            accountID: accountID,
            environment: environment,
            databaseScope: database.databaseScope == .shared ? "shared" : "private",
            zoneOwnerName: zoneID.ownerName,
            zoneName: zoneID.zoneName
        ))
    }

    private func forget(fileName: String?) {
        guard let fileName else { return }
        zonesByFileName[fileName] = nil
        store.remove(fileName: fileName)
    }

    private func resumableZone(fileName: String, now: Date) -> Zone? {
        if let zone = zonesByFileName[fileName] {
            guard ZoneChangeCachePolicy.resumable(zone.snapshot, signature: signature, now: now) != nil else {
                zonesByFileName[fileName] = nil
                return nil
            }
            return zone
        }
        guard let snapshot = ZoneChangeCachePolicy.resumable(store.load(fileName: fileName), signature: signature, now: now),
              let zone = Self.decoded(snapshot) else { return nil }
        zonesByFileName[fileName] = zone
        return zone
    }

    /// Nil when anything in the file cannot be read back: a snapshot with holes must not
    /// be continued from.
    private static func decoded(_ snapshot: ZoneChangeSnapshot) -> Zone? {
        guard let tokenData = snapshot.tokenData,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: tokenData) else {
            return nil
        }
        var recordsByName: [String: CKRecord] = [:]
        for (recordName, data) in snapshot.recordDataByName {
            guard let record = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data) else {
                return nil
            }
            recordsByName[recordName] = record
        }
        return Zone(snapshot: snapshot, token: token, recordsByName: recordsByName)
    }

    private static func fetchChanges(
        in zoneID: CKRecordZone.ID,
        database: CKDatabase,
        since token: CKServerChangeToken?,
        desiredKeys: [String]
    ) async throws -> ZoneChangeDelta {
        try await withCheckedThrowingContinuation { continuation in
            var delta = ZoneChangeDelta()
            var zoneError: Error?

            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = token
            config.desiredKeys = desiredKeys

            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )
            // Someone is looking at the sync spinner.
            operation.qualityOfService = .userInitiated

            operation.recordWasChangedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    delta.changes.append(.saved(record))
                case .failure(let error):
                    delta.failedRecordCount += 1
                    cloudKitSharingError(
                        "fetchZoneChanges record failed record=\(recordID.recordName) error=\(describeCloudKitFailure(error))"
                    )
                }
            }

            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                delta.changes.append(.deleted(recordID))
            }

            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let finished):
                    delta.token = finished.serverChangeToken
                case .failure(let error):
                    zoneError = error
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                if let zoneError {
                    continuation.resume(throwing: zoneError)
                    return
                }
                switch result {
                case .success:
                    continuation.resume(returning: delta)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }
}
