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
enum BackgroundRefreshSchedulePlan {
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

    static func consumePendingPartnerOwnerID(defaults: UserDefaults = .standard) -> String? {
        let ownerID = defaults.string(forKey: pendingPartnerOwnerIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.removeObject(forKey: pendingPartnerOwnerIDKey)
        guard let ownerID, !ownerID.isEmpty else { return nil }
        return ownerID
    }
}

enum SyncPhase: String {
    case idle
    case syncing
    case failed
}

enum ForegroundSyncPlan {
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

enum CloudKitForegroundSyncPlan {
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
        if normalizedID(partnerShareOwnerID) != nil { return true }
        return outgoingShareParticipantIDs.contains { normalizedID($0) != nil }
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? nil : trimmedID
    }
}

enum CloudKitMirrorSyncPlan {
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
