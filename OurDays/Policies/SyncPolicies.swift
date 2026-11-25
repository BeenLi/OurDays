import Foundation

/// Broadcast when a CloudKit silent push reports remote changes, so the live UI can
/// pull the latest data (which in turn posts any resulting local notifications).
enum ShareCalRemoteChangeSignal {
    static let notificationName = Notification.Name("ShareCalRemoteChange")

    static func notifyChanged(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: notificationName, object: nil)
    }
}

/// Pure policy for the `BGAppRefreshTask` fallback that keeps partner data fresh when
/// silent CloudKit pushes get throttled or dropped (notifications plan, decision 0002).
/// The OS glue (`BGTaskScheduler` register/submit, running the sync) lives in the app
/// delegate; this enum holds only the decisions worth unit-testing: whether scheduling
/// is even worthwhile, and the earliest the next refresh may run.
enum BackgroundRefreshSchedulePolicy {
    /// Must match the entry in Info.plist `BGTaskSchedulerPermittedIdentifiers`.
    static let taskIdentifier = "com.leeberty.CoupleCalendar.refresh"

    /// iOS treats BGAppRefresh as opportunistic and won't dispatch it more than roughly
    /// once every 15 minutes; requesting a shorter interval is silently ignored, so we
    /// clamp up to this floor instead of pretending we can sync more often.
    static let minimumInterval: TimeInterval = 15 * 60

    /// Only schedule when a CloudKit sync would actually pull partner data. An unpaired
    /// (or CloudKit-disabled) install has nothing to fetch, so arming a background task
    /// would just burn the system's background budget for no benefit.
    static func shouldSchedule(
        isCloudKitEnabled: Bool,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String]
    ) -> Bool {
        guard isCloudKitEnabled else { return false }
        return hasStartedPairing
            || partnerShareOwnerID != nil
            || !outgoingShareParticipantIDs.isEmpty
    }

    /// Earliest the next refresh may run. `requestedInterval` is clamped up to
    /// `minimumInterval` so we never ask iOS for a cadence it will discard.
    static func earliestBeginDate(
        from referenceDate: Date,
        requestedInterval: TimeInterval = minimumInterval
    ) -> Date {
        referenceDate.addingTimeInterval(max(requestedInterval, minimumInterval))
    }
}

enum ShareCalAcceptedShareSignal {
    static let notificationName = Notification.Name("ShareCalAcceptedCloudKitShare")
    private static let pendingSyncKey = "ShareCalPendingAcceptedCloudKitShareSync"
    private static let pendingPartnerOwnerIDKey = "ShareCalPendingAcceptedPartnerOwnerID"

    static func markAccepted(
        partnerOwnerID: String?,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(true, forKey: pendingSyncKey)
        if let partnerOwnerID, !partnerOwnerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(partnerOwnerID, forKey: pendingPartnerOwnerIDKey)
        }
        notificationCenter.post(name: notificationName, object: nil)
    }

    static func hasPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingSyncKey)
    }

    static func consumePending(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: pendingSyncKey) else { return false }
        defaults.set(false, forKey: pendingSyncKey)
        return true
    }

    /// The accepted partner, without consuming it: lets the UI show the new pairing
    /// while the follow-up sync is still waiting for a running one to finish.
    static func pendingPartnerOwnerID(defaults: UserDefaults = .standard) -> String? {
        guard hasPending(defaults: defaults) else { return nil }
        return MemberIDPolicy.normalized(defaults.string(forKey: pendingPartnerOwnerIDKey))
    }

    static func consumePendingPartnerOwnerID(defaults: UserDefaults = .standard) -> String? {
        let ownerID = defaults.string(forKey: pendingPartnerOwnerIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.removeObject(forKey: pendingPartnerOwnerIDKey)
        guard let ownerID, !ownerID.isEmpty else { return nil }
        return ownerID
    }
}

/// Accepting a share is one Apple round trip of several seconds. These tell the UI it has
/// started (show the next step now, marked as still confirming) and, rarely, that it
/// failed (step back). Success is `ShareCalAcceptedShareSignal`.
enum ShareCalShareAcceptanceProgressSignal {
    static let startedNotificationName = Notification.Name("ShareCalShareAcceptanceStarted")
    static let failedNotificationName = Notification.Name("ShareCalShareAcceptanceFailed")
    static let ownerIDKey = "ownerID"
    static let messageKey = "message"

    static func postStarted(ownerID: String, notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: startedNotificationName, object: nil, userInfo: [ownerIDKey: ownerID])
    }

    static func postFailed(ownerID: String, message: String, notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(
            name: failedNotificationName,
            object: nil,
            userInfo: [ownerIDKey: ownerID, messageKey: message]
        )
    }

    static func ownerID(in notification: Notification) -> String? {
        MemberIDPolicy.normalized(notification.userInfo?[ownerIDKey] as? String)
    }

    static func message(in notification: Notification) -> String? {
        notification.userInfo?[messageKey] as? String
    }
}

enum SyncPhase: String {
    case idle
    case syncing
    case failed
}

enum ForegroundSyncPolicy {
    // Re-foregrounding or switching tabs should reflect a partner's change
    // quickly. A short throttle keeps automatic syncs from stampeding while
    // still feeling live; manual pull-to-refresh bypasses this entirely.
    static let automaticThrottleInterval: TimeInterval = 60

    static func shouldRunAutomaticSync(
        lastSyncAt: Date?,
        now: Date,
        syncPhase: SyncPhase,
        hasPendingAcceptedShare: Bool
    ) -> Bool {
        guard syncPhase != .syncing else { return false }
        if hasPendingAcceptedShare { return true }
        guard let lastSyncAt else { return true }
        return now.timeIntervalSince(lastSyncAt) >= automaticThrottleInterval
    }
}

enum CloudKitForegroundSyncPolicy {
    static func shouldRunCloudKit(
        iCloudSharingEnabled: Bool,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        forceCloudKit: Bool
    ) -> Bool {
        guard iCloudSharingEnabled else { return false }
        if forceCloudKit { return true }
        if hasStartedPairing { return true }
        if MemberIDPolicy.normalized(partnerShareOwnerID) != nil { return true }
        return outgoingShareParticipantIDs.contains { MemberIDPolicy.normalized($0) != nil }
    }
}

enum CloudKitMirrorSyncPolicy {
    static func mirrorsNeedingUpload(
        _ mirrors: [EventMirror],
        activeShadows: [LocalEventShadow],
        existingShadows: [LocalEventShadow],
        existingLocalMirrors: [EventMirror]
    ) -> [EventMirror] {
        let activeShadowByID = Dictionary(activeShadows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingShadowByID = Dictionary(existingShadows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingMirrorByKey = Dictionary(existingLocalMirrors.map { ($0.mirrorKey, $0) }, uniquingKeysWith: { first, _ in first })

        return mirrors.filter { mirror in
            if mirror.deletedAt != nil { return true }
            guard let existingMirror = existingMirrorByKey[mirror.mirrorKey] else { return true }
            guard hasSameCloudKitPayload(mirror, as: existingMirror) else { return true }
            guard existingMirror.cloudKitRecordName != nil else { return true }
            guard let activeShadow = activeShadowByID[mirror.mirrorKey],
                  let existingShadow = existingShadowByID[mirror.mirrorKey] else {
                return true
            }
            // A shadow without an upload confirmation was recorded by a sync
            // that never reached CloudKit (e.g. before pairing).
            guard existingShadow.lastUploadedAt != nil else { return true }
            return activeShadow.fingerprint != existingShadow.fingerprint
                || activeShadow.cloudKitRecordName != existingShadow.cloudKitRecordName
                || activeShadow.isTombstone != existingShadow.isTombstone
        }
    }

    private static func hasSameCloudKitPayload(_ lhs: EventMirror, as rhs: EventMirror) -> Bool {
        lhs.ownerMemberID == rhs.ownerMemberID
            && lhs.mirrorKey == rhs.mirrorKey
            && lhs.sourceCalendarID == rhs.sourceCalendarID
            && lhs.sourceCalendarTitle == rhs.sourceCalendarTitle
            && lhs.occurrenceStartDate == rhs.occurrenceStartDate
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
            && lhs.title == rhs.title
            && lhs.location == rhs.location
            && lhs.notes == rhs.notes
            && lhs.urlString == rhs.urlString
            && lhs.calendarColorHex == rhs.calendarColorHex
            && lhs.visibilityRawValue == rhs.visibilityRawValue
            && lhs.deletedAt == rhs.deletedAt
            && lhs.cloudKitRecordName == rhs.cloudKitRecordName
            && lhs.stableKey == rhs.stableKey
    }
}

/// Decides when a sync must look at the EventMirror records already in the user's own
/// private zone before uploading. Normally the local `LocalEventShadow` rows remember
/// which events were uploaded, so a deleted event is tombstoned by diffing shadows
/// against the calendar. After a delete-and-reinstall (or any wipe of the local cache)
/// there is no such memory, so nothing would ever tombstone the records of events that
/// disappeared while the app was gone — the partner would keep seeing them forever.
/// Until one cloud write has been confirmed on this install (a shadow with
/// `lastUploadedAt`), the sync reads its own cloud mirrors and treats them as the
/// "previous state" for the ordinary tombstone diff. Shadows are written before the
/// cloud step, so "no shadows at all" would stop after the first attempt even if that
/// attempt failed; the upload stamp is the signal that the memory is trustworthy.
/// Which device of one Apple ID uploads my own events. A mirror's key is built from
/// EventKit's `calendarIdentifier` + `eventIdentifier`, which are only valid on the
/// device that read them, so the iPhone and a Mac reading the same iCloud calendar
/// would each upload their own copy and the partner would see every event twice.
/// The iPhone stays the only uploader; a Mac keeps its mirrors local (for its own
/// display) and its new events reach the partner through iCloud Calendar and the
/// iPhone (pairing-sync-integrity decision 0010). The delay is until the iPhone app
/// next syncs: EventKit changes don't wake it.
/// Every device of mine uploads its own events (decision 0017). The iPhone always could;
/// a Mac, whose EventKit identifiers differ from the iPhone's, uploads by first finding the
/// iPhone's record for the same event (`OwnRecordAdoptionPolicy`).
enum OwnEventUploadPolicy {
    /// How long a Mac's last upload makes the iPhone look for the Mac's records.
    static let macActivityLifetime: TimeInterval = 45 * 24 * 3_600
    /// The Mac restamps its relayed upload time at most this often (every write pushes
    /// my other devices).
    static let macActivityRestampInterval: TimeInterval = 24 * 3_600

    /// A Mac starts records of its own only once every live record in my zone carries a
    /// stable key: an iPhone still on an older version writes records without one, and
    /// the Mac would then upload the same events a second time.
    static func mayStartNewRecords(isRunningOnMac: Bool, cloudOwnMirrors: [EventMirror]?) -> Bool {
        guard isRunningOnMac else { return true }
        guard let cloudOwnMirrors else { return false }
        return !cloudOwnMirrors.contains { $0.deletedAt == nil && $0.stableKey == nil }
    }

    /// Whether the iPhone asks the cloud for records a Mac made before starting new ones.
    /// Only when a Mac uploaded lately: otherwise there is nothing to find and the query
    /// would only slow the sync.
    static func looksUpNewEventsInCloud(isRunningOnMac: Bool, macUploadsOwnEventsAt: Date?, now: Date) -> Bool {
        guard !isRunningOnMac, let macUploadsOwnEventsAt else { return false }
        return now.timeIntervalSince(macUploadsOwnEventsAt) < macActivityLifetime
    }

    /// The Mac's relayed upload time after this sync: unchanged while still fresh.
    static func macActivityStamp(previous: Date?, now: Date) -> Date {
        if let previous, now.timeIntervalSince(previous) < macActivityRestampInterval, previous <= now {
            return previous
        }
        return OwnSettingsRelayClock.stamp(now)
    }
}

/// Which record each of my events uses when another device of mine may have uploaded it
/// already. The record name is the event's identity (comments hang on it) and is never
/// derived on this device alone once another device knows the event: the stable key
/// (`EventStableKeyPolicy`) finds that device's record, and this device takes its name.
///
/// - An event this device has not confirmed in the cloud yet (no uploaded shadow) takes
///   the live record with its stable key if there is one. With only a deleted record
///   (my other device deleted the event and this calendar hasn't caught up), it is held:
///   neither uploaded nor kept, so the deletion isn't undone.
/// - With no record anywhere it starts a new one, if it may (`mayStartNewRecords`); a
///   Mac's new record names start with `mac:`. Otherwise it is held.
/// - When two devices started a record for the same event at once, the device that sees
///   my whole zone moves to the one that wins (not a Mac's, then the smaller name) and
///   its own is deleted through the usual tombstone. An iPhone never needs to: its
///   record wins over the Mac's.
/// - Two events here with one stable key, an empty key, or a record another event here
///   already uses: nothing is adopted.
enum OwnRecordAdoptionPolicy {
    static let macRecordPrefix = "mac:"

    struct Result: Equatable {
        /// `[derived key: record name]` for every event whose name isn't its derived key.
        var keptKeys: [String: String]
        /// Record names of events that are neither uploaded nor kept this sync, nor counted
        /// as gone.
        var heldKeys: Set<String>
        /// Record names taken from another device's live record this sync: the cloud copy
        /// stands until the event changes here.
        var adoptedKeys: Set<String>
    }

    /// - `confirmedKeys`: live shadows this device has seen through to the cloud;
    ///   `confirmedTombstoneKeys`: the deletions it uploaded itself. With a read of the
    ///   whole zone, a key counts as confirmed only if its record is really there: a
    ///   stamp alone (say, from a sync that saw no events at all) proves nothing.
    /// - `ownCalendarIDs`: this device's calendars. A Mac yields to records written
    ///   from another device's calendars.
    static func resolve(
        events: [CalendarSourceEvent],
        stableKeys: [String: String],
        keptKeys: [String: String],
        confirmedKeys: Set<String>,
        confirmedTombstoneKeys: Set<String> = [],
        cloudOwnMirrors: [EventMirror],
        cloudCoversWholeZone: Bool,
        mayStartNewRecords: Bool,
        isRunningOnMac: Bool,
        ownCalendarIDs: Set<String> = []
    ) -> Result {
        let derivedKeys = events.map { EventMirrorKeyPolicy.makeMirrorKey(for: $0) }
        let currentKeys = derivedKeys.map { keptKeys[$0] ?? $0 }
        let eventStableKeys = derivedKeys.map { stableKeys[$0] ?? "" }
        var stableKeyCounts: [String: Int] = [:]
        for key in eventStableKeys where !key.isEmpty {
            stableKeyCounts[key, default: 0] += 1
        }
        let cloudByStableKey = Dictionary(
            grouping: cloudOwnMirrors.filter { !($0.stableKey ?? "").isEmpty },
            by: { $0.stableKey ?? "" }
        )
        let cloudKeys = Set(cloudOwnMirrors.map(\.mirrorKey))
        let writtenHere = isRunningOnMac
            ? Set(cloudOwnMirrors.filter { ownCalendarIDs.contains($0.sourceCalendarID) }.map(\.mirrorKey))
            : []

        enum Proposal { case keep, adopt(String, fromCloud: Bool), hold }
        var proposals: [Proposal] = []
        for index in events.indices {
            let current = currentKeys[index]
            let stableKey = eventStableKeys[index]
            let unique = !stableKey.isEmpty && stableKeyCounts[stableKey] == 1
            let records = unique ? (cloudByStableKey[stableKey] ?? []) : []
            let live = records.filter { $0.deletedAt == nil }.map(\.mirrorKey)
            let winner = preferred(live, demoted: writtenHere)
            let isConfirmed = confirmedKeys.contains(current) && (!cloudCoversWholeZone || cloudKeys.contains(current))
            if isConfirmed {
                if cloudCoversWholeZone, let winner, winner != current {
                    proposals.append(.adopt(winner, fromCloud: false))
                } else {
                    proposals.append(.keep)
                }
                continue
            }
            if let winner {
                proposals.append(winner == current ? .keep : .adopt(winner, fromCloud: true))
            } else if confirmedTombstoneKeys.contains(current), records.contains(where: { $0.mirrorKey == current }) {
                // This device deleted it itself and the event is back: revive its record.
                proposals.append(.keep)
            } else if !records.isEmpty || !mayStartNewRecords {
                proposals.append(.hold)
            } else if isRunningOnMac, !current.hasPrefix(macRecordPrefix) {
                proposals.append(.adopt(macRecordPrefix + current, fromCloud: false))
            } else {
                proposals.append(.keep)
            }
        }

        // A record name stands for one event: an adoption that would share one is dropped.
        var claims: [String: Int] = [:]
        for (index, proposal) in proposals.enumerated() {
            switch proposal {
            case .keep: claims[currentKeys[index], default: 0] += 1
            case .adopt(let key, _): claims[key, default: 0] += 1
            case .hold: break
            }
        }
        var result = Result(keptKeys: keptKeys, heldKeys: [], adoptedKeys: [])
        for (index, proposal) in proposals.enumerated() {
            let derived = derivedKeys[index]
            let current = currentKeys[index]
            switch proposal {
            case .keep:
                continue
            case .hold:
                result.heldKeys.insert(current)
            case .adopt(let key, let fromCloud):
                guard claims[key] == 1 else {
                    if !confirmedKeys.contains(current) && !mayStartNewRecords {
                        result.heldKeys.insert(current)
                    }
                    continue
                }
                result.keptKeys[derived] = key
                if fromCloud { result.adoptedKeys.insert(key) }
            }
        }
        return result
    }

    /// Among live records for one event: an iPhone's before a Mac's (a `mac:` name, or on
    /// a Mac one written from its own calendars: `demoted`), then the smaller name.
    static func preferred(_ keys: [String], demoted: Set<String> = []) -> String? {
        keys.min { lhs, rhs in
            let lhsLate = lhs.hasPrefix(macRecordPrefix) || demoted.contains(lhs)
            let rhsLate = rhs.hasPrefix(macRecordPrefix) || demoted.contains(rhs)
            if lhsLate != rhsLate { return !lhsLate }
            return lhs < rhs
        }
    }
}

/// Of the mirrors a sync would upload, the ones the cloud already holds as they are.
/// Without a look at the cloud everything goes, as before.
enum OwnRecordUploadFilterPolicy {
    static func uploads(
        _ candidates: [EventMirror],
        cloudByKey: [String: EventMirror]?,
        adoptedKeys: Set<String>
    ) -> [EventMirror] {
        guard let cloudByKey else { return candidates }
        return candidates.filter { mirror in
            let cloud = cloudByKey[mirror.mirrorKey]
            if mirror.deletedAt != nil {
                return cloud?.deletedAt == nil
            }
            if let cloud, hasSameContent(mirror, as: cloud) { return false }
            // First seen here this sync: my other device's copy stands until the event
            // changes here (this calendar may simply not have caught up yet).
            return !adoptedKeys.contains(mirror.mirrorKey)
        }
    }

    /// Everything the partner sees; the calendar ID is this device's own.
    static func hasSameContent(_ lhs: EventMirror, as rhs: EventMirror) -> Bool {
        lhs.mirrorKey == rhs.mirrorKey
            && lhs.sourceCalendarTitle == rhs.sourceCalendarTitle
            && lhs.occurrenceStartDate == rhs.occurrenceStartDate
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
            && lhs.title == rhs.title
            && lhs.location == rhs.location
            && lhs.notes == rhs.notes
            && lhs.urlString == rhs.urlString
            && lhs.calendarColorHex == rhs.calendarColorHex
            && lhs.visibilityRawValue == rhs.visibilityRawValue
            && (lhs.deletedAt == nil) == (rhs.deletedAt == nil)
            && lhs.stableKey == rhs.stableKey
    }
}

enum OwnMirrorReconciliationPolicy {
    static func shouldReconcileWithCloud(existingShadows: [LocalEventShadow]) -> Bool {
        !existingShadows.contains { $0.lastUploadedAt != nil }
    }

    /// Cloud copies carry whatever `ownerMemberID` they were uploaded with; the
    /// current member ID is authoritative for the user's own zone.
    static func ownedMirrors(_ mirrors: [EventMirror], currentMemberID: String) -> [EventMirror] {
        CloudKitSharedDatabaseImportPolicy.identifiedMirrors(mirrors, sharedOwnerID: currentMemberID)
    }

    /// What a Mac keeps as its own mirrors: the ones it made this sync, and for every other
    /// record in my zone (calendars only my iPhone has, events held back) the cloud copy.
    static func persistedOwnMirrors(generated: [EventMirror], cloud: [EventMirror]) -> [EventMirror] {
        let generatedKeys = Set(generated.map(\.mirrorKey))
        return generated + cloud.filter { !generatedKeys.contains($0.mirrorKey) }
    }
}

/// When the record of a deleted event finally leaves the cloud. Deleting an event only
/// marks its `EventMirror` record (`deletedAt`, a tombstone) and nothing ever removed it,
/// so the title, notes and place of every deleted event stayed in the shared zone and
/// every full read of the zone carried them along.
///
/// Nobody learns of a deletion from the tombstone: the partner's device and my other
/// devices drop whatever a read no longer returns (`purgeStalePartnerMirrors`,
/// `replaceOwnMirrors`), in every released version. It is kept for a while only so that
/// an event undeleted in Calendar finds its record and comments again, and so another
/// device of mine whose calendar hasn't caught up can see that the event was deleted
/// rather than new. After `retention` the uploading device deletes the record, the
/// comments on it and its own local rows.
enum EventTombstonePurgePolicy {
    static let retention: TimeInterval = 30 * 24 * 3_600

    /// My tombstones old enough to delete, one per record. `cloudOwnMirrors` is what a
    /// reinstall reconciliation read from my zone (this install has no local rows for
    /// tombstones made before it). A record whose event exists again (`liveKeys`) and a
    /// `deletedAt` in the future (another device's clock) are left alone.
    ///
    /// Every device of mine uploads (decision 0017), so each purges only the records it
    /// looks after: ones it confirmed uploading (`confirmedKeys`), or last written from
    /// one of its own calendars (`ownCalendarIDs`; EventKit calendar IDs are per device
    /// and survive a reinstall). A Mac never purges the iPhone's tombstones or the reverse.
    static func expiredTombstones(
        localOwnMirrors: [EventMirror],
        cloudOwnMirrors: [EventMirror]?,
        liveKeys: Set<String>,
        confirmedKeys: Set<String>,
        ownCalendarIDs: Set<String>,
        now: Date
    ) -> [EventMirror] {
        var expiredByKey: [String: EventMirror] = [:]
        var keptKeys = liveKeys
        for mirror in localOwnMirrors + (cloudOwnMirrors ?? []) {
            guard confirmedKeys.contains(mirror.mirrorKey) || ownCalendarIDs.contains(mirror.sourceCalendarID) else {
                continue
            }
            guard let deletedAt = mirror.deletedAt,
                  now.timeIntervalSince(deletedAt) >= retention else {
                // Live, or deleted too recently, in either copy: the record stays.
                keptKeys.insert(mirror.mirrorKey)
                continue
            }
            if expiredByKey[mirror.mirrorKey] == nil {
                expiredByKey[mirror.mirrorKey] = mirror
            }
        }
        return expiredByKey.keys.sorted()
            .filter { !keptKeys.contains($0) }
            .compactMap { expiredByKey[$0] }
    }

    /// The comment threads that hang on the purged records (`EventCommentAnchorPolicy`:
    /// a thread is keyed by the mirror's id, which is its record name).
    static func commentsToPurge(_ comments: [EventComment], purged: [EventMirror]) -> [EventComment] {
        var anchors = Set(purged.map(\.id))
        anchors.formUnion(purged.map(\.mirrorKey))
        anchors.formUnion(purged.compactMap(\.cloudKitRecordName))
        return comments.filter { anchors.contains($0.eventMirrorID) }
    }
}
