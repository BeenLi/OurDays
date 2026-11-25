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
enum OwnEventUploadPolicy {
    static func uploadsOwnEvents(isRunningOnMac: Bool) -> Bool {
        !isRunningOnMac
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
    static func expiredTombstones(
        localOwnMirrors: [EventMirror],
        cloudOwnMirrors: [EventMirror]?,
        liveKeys: Set<String>,
        uploadsOwnEvents: Bool,
        now: Date
    ) -> [EventMirror] {
        guard uploadsOwnEvents else { return [] }
        var expiredByKey: [String: EventMirror] = [:]
        var keptKeys = liveKeys
        for mirror in localOwnMirrors + (cloudOwnMirrors ?? []) {
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
