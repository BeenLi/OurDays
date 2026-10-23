import Foundation

enum ICloudSharingTeardownPlan {
    static func localOwnerIDsToPurge(partnerShareOwnerID: String?) -> Set<String> {
        var ownerIDs = Set([partnerShareOwnerID].compactMap { MemberIDPlan.normalized($0) })
        ownerIDs.insert(MemberIDPlan.unknownPartnerID)
        return ownerIDs
    }
}

enum PairingStatus: Equatable {
    case notPaired
    case waitingForPartner
    case waitingForPartnerToShare
    case waitingForYouToShare
    case paired
}

enum PairingSettingsPlan {
    static func status(
        hasStartedPairing: Bool,
        outgoingParticipantIDs: [String],
        incomingOwnerID: String?
    ) -> PairingStatus {
        let hasAcceptedOutgoingShare = !MemberIDPlan.normalizedList(outgoingParticipantIDs).isEmpty
        let hasIncomingShare = MemberIDPlan.normalized(incomingOwnerID) != nil
        if hasAcceptedOutgoingShare && hasIncomingShare {
            return .paired
        }
        if hasIncomingShare {
            return .waitingForYouToShare
        }
        if hasAcceptedOutgoingShare {
            return .waitingForPartnerToShare
        }
        if hasStartedPairing {
            return .waitingForPartner
        }
        return .notPaired
    }

    static func partnerDisplayName(
        partnerNoteName: String?,
        partnerSyncedDisplayName: String?,
        fallback: String
    ) -> String {
        if let noteName = MemberIDPlan.normalized(partnerNoteName) {
            return noteName
        }
        if let syncedDisplayName = MemberIDPlan.normalized(partnerSyncedDisplayName) {
            return syncedDisplayName
        }
        return fallback
    }

    static func partnerStatusDisplayName(
        partnerNoteName: String?,
        partnerSyncedDisplayName: String?,
        fallback: String,
        language: AppLanguage
    ) -> String {
        let displayName = MemberIDPlan.normalized(partnerSyncedDisplayName) ?? fallback
        guard let noteName = MemberIDPlan.normalized(partnerNoteName),
              noteName != displayName else {
            return displayName
        }
        return ShareCalStrings(language: language).displayNameWithNote(
            displayName: displayName,
            note: noteName
        )
    }

    static func randomDisplayName(randomNumber: () -> Int = { Int.random(in: 0...9_999) }) -> String {
        let number = max(0, min(9_999, randomNumber()))
        return String(format: "OurDays %04d", number)
    }

    static func normalizedDisplayName(_ displayName: String?) -> String? {
        MemberIDPlan.normalized(displayName)
    }
}

struct ExistingICloudDataSnapshot: Equatable {
    let hasPrivateZoneData: Bool
    let hasOutgoingShare: Bool
    let acceptedSharedZoneCount: Int
    let lookupFailed: Bool

    init(
        hasPrivateZoneData: Bool,
        hasOutgoingShare: Bool,
        acceptedSharedZoneCount: Int,
        lookupFailed: Bool = false
    ) {
        self.hasPrivateZoneData = hasPrivateZoneData
        self.hasOutgoingShare = hasOutgoingShare
        self.acceptedSharedZoneCount = acceptedSharedZoneCount
        self.lookupFailed = lookupFailed
    }

    var hasRecoverableData: Bool {
        hasPrivateZoneData || hasOutgoingShare || acceptedSharedZoneCount > 0
    }
}

/// What a fresh install can take back from the user's own private zone when they choose
/// to keep their existing iCloud data: the pairing date (the share root's creation
/// time) and the nickname/avatar the partner already knows them by. Neither is read by
/// the regular sync (which only imports the partner's zone), so the recovery path
/// restores them once, before the first forced sync runs.
struct ExistingICloudDataRecoveredState: Equatable {
    var pairingDate: Date?
    var displayName: String?
    var avatar: MemberAvatar?
}

enum ExistingICloudDataRecoveryPlan {
    static func recoveredState(
        shareRootCreatedAt: Date?,
        ownProfile: CloudKitMemberProfile?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ExistingICloudDataRecoveredState {
        var state = ExistingICloudDataRecoveredState()
        if let shareRootCreatedAt, shareRootCreatedAt <= now {
            state.pairingDate = PairingDatePlan.normalizedPairingDate(shareRootCreatedAt, calendar: calendar)
        }
        if let ownProfile, let displayName = MemberIDPlan.normalized(ownProfile.displayName) {
            state.displayName = displayName
            state.avatar = MemberAvatarPlan.normalized(ownProfile.avatar)
        }
        return state
    }

    static func shouldPresent(
        snapshot: ExistingICloudDataSnapshot,
        hasCompletedInitialProfilePrompt: Bool,
        hasResolvedPrompt: Bool,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        lastSyncAt: Date?
    ) -> Bool {
        guard hasCompletedInitialProfilePrompt else { return false }
        guard !hasResolvedPrompt else { return false }
        guard looksLikeFreshLocalState(
            hasStartedPairing: hasStartedPairing,
            partnerShareOwnerID: partnerShareOwnerID,
            outgoingShareParticipantIDs: outgoingShareParticipantIDs,
            lastSyncAt: lastSyncAt
        ) else { return false }
        return snapshot.hasRecoverableData
    }

    static func shouldDeferAutomaticSync(
        hasResolvedPrompt: Bool,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        lastSyncAt: Date?
    ) -> Bool {
        guard !hasResolvedPrompt else { return false }
        return looksLikeFreshLocalState(
            hasStartedPairing: hasStartedPairing,
            partnerShareOwnerID: partnerShareOwnerID,
            outgoingShareParticipantIDs: outgoingShareParticipantIDs,
            lastSyncAt: lastSyncAt
        )
    }

    private static func looksLikeFreshLocalState(
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        lastSyncAt: Date?
    ) -> Bool {
        guard !hasStartedPairing else { return false }
        guard MemberIDPlan.normalized(partnerShareOwnerID) == nil else { return false }
        guard !outgoingShareParticipantIDs.contains(where: { MemberIDPlan.normalized($0) != nil }) else { return false }
        return lastSyncAt == nil
    }
}

enum PairingSafetyEducationPlan {
    static func shouldPresentNotice(
        pairingStatus: PairingStatus,
        hasPromptedPartnerNoteForCurrentPairing: Bool,
        hasShownPairingSafetyNoticeForCurrentPairing: Bool
    ) -> Bool {
        guard pairingStatus == .paired else { return false }
        guard hasPromptedPartnerNoteForCurrentPairing else { return false }
        return !hasShownPairingSafetyNoticeForCurrentPairing
    }

    static func shouldShowPersistentWarning(pairingStatus: PairingStatus) -> Bool {
        pairingStatus != .notPaired
    }
}

enum SharedPeoplePresentationPlan {
    static func canOpenOfficialSharing(
        isCloudKitEnabled: Bool,
        isPreparingShare: Bool,
        isStoppingShare: Bool
    ) -> Bool {
        isCloudKitEnabled && !isPreparingShare && !isStoppingShare
    }
}

enum TwoPersonPairingConflict: Equatable, Codable {
    case outgoingIncomingMismatch(outgoingIDs: [String], incomingOwnerIDs: [String])
    case multipleIncomingShares(ownerIDs: [String])
    case multipleOutgoingParticipants(participantIDs: [String])
}

/// The single decision point for two-person pairing. The partner is the iCloud
/// user (CloudKit userRecordID) who owns the accepted shared zone, verified
/// against the accepted participant of my outgoing share.
enum TwoPersonPairingPlan {
    struct Resolution: Equatable {
        /// Owner of the active incoming shared zone; nil while waiting for the
        /// partner to share back (or when unpaired).
        let partnerID: String?
        let sharedZoneOwnerIDsToLeave: [String]
        let conflict: TwoPersonPairingConflict?

        static func partner(_ partnerID: String?, leaving ownerIDs: [String] = []) -> Resolution {
            Resolution(partnerID: partnerID, sharedZoneOwnerIDsToLeave: ownerIDs, conflict: nil)
        }

        static func conflicted(_ conflict: TwoPersonPairingConflict) -> Resolution {
            Resolution(partnerID: nil, sharedZoneOwnerIDsToLeave: [], conflict: conflict)
        }
    }

    static func resolve(
        storedPartnerID: String?,
        outgoingAcceptedParticipantIDs: [String],
        sharedZoneOwnerIDs: [String]
    ) -> Resolution {
        let storedPartnerID = MemberIDPlan.normalized(storedPartnerID)
        // Only CloudKit user record names (always "_"-prefixed) can be compared
        // against zone owner names; other identifier forms are display-only.
        let outgoingIDs = uniqueSorted(outgoingAcceptedParticipantIDs).filter { $0.hasPrefix("_") }
        let incomingOwnerIDs = uniqueSorted(sharedZoneOwnerIDs)

        let mutualIDs = incomingOwnerIDs.filter { outgoingIDs.contains($0) }
        if mutualIDs.count == 1, let partnerID = mutualIDs.first {
            // Someone besides the partner joined my share. Never remove them
            // silently: they may be the person I am about to switch to (their
            // share invitation can arrive before or after they join mine), and
            // removing them first leaves my share with no participant once the
            // replacement is confirmed. The user picks who stays.
            if outgoingIDs.contains(where: { $0 != partnerID }) {
                return .conflicted(
                    .outgoingIncomingMismatch(outgoingIDs: outgoingIDs, incomingOwnerIDs: incomingOwnerIDs)
                )
            }
            return .partner(partnerID, leaving: incomingOwnerIDs.filter { $0 != partnerID })
        }
        if mutualIDs.count > 1 {
            return .conflicted(.multipleIncomingShares(ownerIDs: mutualIDs))
        }

        if incomingOwnerIDs.isEmpty {
            if outgoingIDs.count > 1 {
                return .conflicted(.multipleOutgoingParticipants(participantIDs: outgoingIDs))
            }
            return .partner(nil)
        }

        if outgoingIDs.isEmpty {
            if let storedPartnerID, incomingOwnerIDs.contains(storedPartnerID) {
                return .partner(storedPartnerID, leaving: incomingOwnerIDs.filter { $0 != storedPartnerID })
            }
            if incomingOwnerIDs.count == 1 {
                return .partner(incomingOwnerIDs[0])
            }
            return .conflicted(.multipleIncomingShares(ownerIDs: incomingOwnerIDs))
        }

        return .conflicted(
            .outgoingIncomingMismatch(outgoingIDs: outgoingIDs, incomingOwnerIDs: incomingOwnerIDs)
        )
    }

    private static func uniqueSorted(_ ids: [String]) -> [String] {
        Array(Set(ids.compactMap(MemberIDPlan.normalized))).sorted()
    }
}

enum TwoPersonPairingConflictPresentationPlan {
    /// The people the user can choose between when resolving a conflict, in
    /// stable display order.
    static func candidateIDs(_ conflict: TwoPersonPairingConflict) -> [String] {
        switch conflict {
        case .outgoingIncomingMismatch(let outgoingIDs, let incomingOwnerIDs):
            return (outgoingIDs + incomingOwnerIDs).reduce(into: [String]()) { result, id in
                if !result.contains(id) { result.append(id) }
            }
        case .multipleIncomingShares(let ownerIDs):
            return ownerIDs
        case .multipleOutgoingParticipants(let participantIDs):
            return participantIDs
        }
    }
}

enum ShareAcceptanceGuardPlan {
    static func requiresReplacementConfirmation(
        incomingOwnerID: String,
        storedPartnerID: String?,
        outgoingParticipantIDs: [String]
    ) -> Bool {
        let incomingOwnerID = incomingOwnerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingOwnerID.isEmpty else { return false }
        if let storedPartnerID = MemberIDPlan.normalized(storedPartnerID) {
            return storedPartnerID != incomingOwnerID
        }
        let outgoingIDs = Set(outgoingParticipantIDs.compactMap(MemberIDPlan.normalized).filter { $0.hasPrefix("_") })
        return !outgoingIDs.isEmpty && !outgoingIDs.contains(incomingOwnerID)
    }
}
