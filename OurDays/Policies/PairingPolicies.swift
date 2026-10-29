import Foundation

enum ICloudSharingTeardownPolicy {
    static func localOwnerIDsToPurge(partnerShareOwnerID: String?) -> Set<String> {
        var ownerIDs = Set([partnerShareOwnerID].compactMap { MemberIDPolicy.normalized($0) })
        ownerIDs.insert(MemberIDPolicy.unknownPartnerID)
        return ownerIDs
    }
}

/// Unpairing is two-sided: the partner leaves my share and deletes theirs. Seen from
/// my side, someone was on at least one half of the pairing and now nobody is on
/// either. A partner I never had (a link not yet opened) is not a departure.
enum PartnerDeparturePolicy {
    static func partnerHasLeft(
        previousPartnerID: String?,
        previousOutgoingParticipantIDs: [String],
        resolvedPartnerID: String?,
        outgoingParticipantIDs: [String]
    ) -> Bool {
        let hadSomeone = MemberIDPolicy.normalized(previousPartnerID) != nil
            || !MemberIDPolicy.normalizedList(previousOutgoingParticipantIDs).isEmpty
        let hasSomeone = MemberIDPolicy.normalized(resolvedPartnerID) != nil
            || !MemberIDPolicy.normalizedList(outgoingParticipantIDs).isEmpty
        return hadSomeone && !hasSomeone
    }
}

/// Where the "paste an invite link" entry shows. Any time before I have accepted
/// the partner's link I may be holding one to paste: before sending mine, while mine
/// waits to be opened (they sent theirs too), and above all at step 3, when their
/// link comes back.
enum PairingInviteLinkEntryPolicy {
    static func showsPasteEntry(status: PairingStatus) -> Bool {
        switch status {
        case .notPaired, .waitingForPartner, .waitingForPartnerToShare:
            true
        case .waitingForYouToShare, .paired:
            false
        }
    }
}

enum PairingStatus: Equatable {
    case notPaired
    case waitingForPartner
    case waitingForPartnerToShare
    case waitingForYouToShare
    case paired
}

enum PairingSettingsPolicy {
    static func status(
        hasStartedPairing: Bool,
        outgoingParticipantIDs: [String],
        incomingOwnerID: String?
    ) -> PairingStatus {
        let hasAcceptedOutgoingShare = !MemberIDPolicy.normalizedList(outgoingParticipantIDs).isEmpty
        let hasIncomingShare = MemberIDPolicy.normalized(incomingOwnerID) != nil
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
        if let noteName = MemberIDPolicy.normalized(partnerNoteName) {
            return noteName
        }
        if let syncedDisplayName = MemberIDPolicy.normalized(partnerSyncedDisplayName) {
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
        let displayName = MemberIDPolicy.normalized(partnerSyncedDisplayName) ?? fallback
        guard let noteName = MemberIDPolicy.normalized(partnerNoteName),
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
        MemberIDPolicy.normalized(displayName)
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

enum ExistingICloudDataRecoveryPolicy {
    static func recoveredState(
        shareRootCreatedAt: Date?,
        ownProfile: CloudKitMemberProfile?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ExistingICloudDataRecoveredState {
        var state = ExistingICloudDataRecoveredState()
        if let shareRootCreatedAt, shareRootCreatedAt <= now {
            state.pairingDate = PairingDatePolicy.normalizedPairingDate(shareRootCreatedAt, calendar: calendar)
        }
        if let ownProfile, let displayName = MemberIDPolicy.normalized(ownProfile.displayName) {
            state.displayName = displayName
            state.avatar = MemberAvatarPolicy.normalized(ownProfile.avatar)
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
        guard MemberIDPolicy.normalized(partnerShareOwnerID) == nil else { return false }
        guard !outgoingShareParticipantIDs.contains(where: { MemberIDPolicy.normalized($0) != nil }) else { return false }
        return lastSyncAt == nil
    }
}

enum PairingSafetyEducationPolicy {
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

enum SharedPeoplePresentationPolicy {
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
enum TwoPersonPairingPolicy {
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
        let storedPartnerID = MemberIDPolicy.normalized(storedPartnerID)
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
        Array(Set(ids.compactMap(MemberIDPolicy.normalized))).sorted()
    }
}

enum TwoPersonPairingConflictPresentationPolicy {
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

enum ShareAcceptanceGuardPolicy {
    static func requiresReplacementConfirmation(
        incomingOwnerID: String,
        storedPartnerID: String?,
        outgoingParticipantIDs: [String]
    ) -> Bool {
        let incomingOwnerID = incomingOwnerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingOwnerID.isEmpty else { return false }
        if let storedPartnerID = MemberIDPolicy.normalized(storedPartnerID) {
            return storedPartnerID != incomingOwnerID
        }
        let outgoingIDs = Set(outgoingParticipantIDs.compactMap(MemberIDPolicy.normalized).filter { $0.hasPrefix("_") })
        return !outgoingIDs.isEmpty && !outgoingIDs.contains(incomingOwnerID)
    }
}

/// Keeps a two-person space two-person across a partner change. Every record in my
/// private zone hangs off the one share root, so the CKShare created for a new partner
/// exposes everything the previous partner left there (their comments on my events, the
/// invitations and history requests we exchanged). The UI renders every member ID that
/// is not mine as "the partner", so on the new partner's device the old partner's words
/// would read as mine, and my old pending invitations would be answerable by them.
/// Two layers: delete the ex-partner's records from my zone when the partner leaves
/// (`CloudKitExPartnerCleanupPolicy`), and never import or keep a record whose other
/// party is neither me nor the current partner.
enum PartnerScopedDataPolicy {
    /// Only a real CloudKit userRecordID (`_`-prefixed) can be "someone else". The
    /// placeholders used before identities are known ("local-user", "partner") name
    /// nobody and are never treated as foreign.
    static func isForeign(_ memberID: String, currentMemberID: String, partnerID: String?) -> Bool {
        guard let id = MemberIDPolicy.normalized(memberID), id.hasPrefix("_") else { return false }
        if id == MemberIDPolicy.normalized(currentMemberID) { return false }
        if let partnerID = MemberIDPolicy.normalized(partnerID), id == partnerID { return false }
        return true
    }

    static func isForeign(_ comment: EventComment, currentMemberID: String, partnerID: String?) -> Bool {
        isForeign(comment.authorMemberID, currentMemberID: currentMemberID, partnerID: partnerID)
    }

    static func isForeign(_ invitation: EventInvitation, currentMemberID: String, partnerID: String?) -> Bool {
        isForeign(invitation.creatorMemberID, currentMemberID: currentMemberID, partnerID: partnerID)
            || isForeign(invitation.inviteeMemberID, currentMemberID: currentMemberID, partnerID: partnerID)
    }

    static func isForeign(_ request: CalendarAccessRequest, currentMemberID: String, partnerID: String?) -> Bool {
        isForeign(request.requesterMemberID, currentMemberID: currentMemberID, partnerID: partnerID)
            || isForeign(request.ownerMemberID, currentMemberID: currentMemberID, partnerID: partnerID)
    }

    static func scoped(_ comments: [EventComment], currentMemberID: String, partnerID: String?) -> [EventComment] {
        comments.filter { !isForeign($0, currentMemberID: currentMemberID, partnerID: partnerID) }
    }

    static func scoped(_ invitations: [EventInvitation], currentMemberID: String, partnerID: String?) -> [EventInvitation] {
        invitations.filter { !isForeign($0, currentMemberID: currentMemberID, partnerID: partnerID) }
    }

    static func scoped(_ requests: [CalendarAccessRequest], currentMemberID: String, partnerID: String?) -> [CalendarAccessRequest] {
        requests.filter { !isForeign($0, currentMemberID: currentMemberID, partnerID: partnerID) }
    }
}

/// Pairing is two link exchanges, not one handshake: each person's calendar lives in
/// their own iCloud, so each has to hand the other a share link. Whoever sends the
/// first link is the initiator; the guide shows the same four steps from either side.
enum PairingGuideRole: Equatable {
    case initiator
    case receiver
}

enum PairingGuideStep: Int, CaseIterable, Equatable {
    case firstLinkSent = 1
    case firstLinkAccepted
    case linkSentBack
    case linkBackAccepted

    /// Who has to act for this step to complete, seen from `role`.
    func actor(for role: PairingGuideRole) -> OurDaysPerson {
        switch (self, role) {
        case (.firstLinkSent, .initiator), (.linkBackAccepted, .initiator),
             (.firstLinkAccepted, .receiver), (.linkSentBack, .receiver):
            return .me
        default:
            return .partner
        }
    }
}

enum OurDaysPerson: Equatable {
    case me
    case partner
}

struct PairingGuideState: Equatable {
    let role: PairingGuideRole
    /// The step waiting to happen next.
    let currentStep: PairingGuideStep
    /// The step before it is shown done while CloudKit is still accepting it.
    var isConfirmingAccept = false
}

enum PairingGuidePolicy {
    /// `sentInviteBackToOwnerID` is the partner I last sent my own link to while I
    /// was the receiver. Comparing it to the current partner keeps a stale value from
    /// an earlier pairing from skipping the share-back step.
    static func state(
        status: PairingStatus,
        partnerShareOwnerID: String?,
        sentInviteBackToOwnerID: String?,
        isConfirmingAccept: Bool = false
    ) -> PairingGuideState? {
        switch status {
        case .notPaired:
            return PairingGuideState(role: .initiator, currentStep: .firstLinkSent)
        case .waitingForPartner:
            return PairingGuideState(role: .initiator, currentStep: .firstLinkAccepted)
        case .waitingForPartnerToShare:
            return PairingGuideState(role: .initiator, currentStep: .linkSentBack)
        case .waitingForYouToShare:
            let hasSentBack = hasSentInviteBack(
                partnerShareOwnerID: partnerShareOwnerID,
                sentInviteBackToOwnerID: sentInviteBackToOwnerID
            )
            return PairingGuideState(
                role: .receiver,
                currentStep: hasSentBack ? .linkBackAccepted : .linkSentBack,
                isConfirmingAccept: isConfirmingAccept
            )
        case .paired:
            return nil
        }
    }

    static func hasSentInviteBack(partnerShareOwnerID: String?, sentInviteBackToOwnerID: String?) -> Bool {
        guard let partnerID = MemberIDPolicy.normalized(partnerShareOwnerID) else { return false }
        return partnerID == MemberIDPolicy.normalized(sentInviteBackToOwnerID)
    }

    /// The one-time "last step: send your link back" sheet, right after I accept the
    /// partner's link and before I have sent mine.
    static func shouldPresentShareBackPrompt(
        status: PairingStatus,
        partnerShareOwnerID: String?,
        sentInviteBackToOwnerID: String?,
        shareBackPromptShownForOwnerID: String?
    ) -> Bool {
        guard let partnerID = MemberIDPolicy.normalized(partnerShareOwnerID) else { return false }
        guard state(
            status: status,
            partnerShareOwnerID: partnerID,
            sentInviteBackToOwnerID: sentInviteBackToOwnerID
        ) == PairingGuideState(role: .receiver, currentStep: .linkSentBack) else { return false }
        return MemberIDPolicy.normalized(shareBackPromptShownForOwnerID) != partnerID
    }

    /// Accepting this invite completes pairing when its sender already joined my share.
    static func inviteCompletesPairing(inviterID: String, outgoingParticipantIDs: [String]) -> Bool {
        guard let inviterID = MemberIDPolicy.normalized(inviterID) else { return false }
        return MemberIDPolicy.normalizedList(outgoingParticipantIDs).contains(inviterID)
    }

    /// The partner's name when I know one; nil before their profile has synced, so
    /// copy can say "TA" / "your partner" instead of a placeholder.
    static func knownPartnerName(partnerNoteName: String?, partnerSyncedDisplayName: String?) -> String? {
        MemberIDPolicy.normalized(partnerNoteName) ?? MemberIDPolicy.normalized(partnerSyncedDisplayName)
    }
}

enum PairingInviteMessagePolicy {
    static let appStoreURL = URL(string: "https://apps.apple.com/cn/app/id6772868166")!

    /// The text sent with the share link. A bare icloud.com link tells the other person
    /// nothing, and tapping it without the app, or inside WeChat, opens a web page that
    /// asks for an iCloud sign-in, so the message says what to do first.
    static func inviteMessage(shareURL: URL, isSendingBack: Bool, strings: ShareCalStrings) -> String {
        strings.pairingInviteMessage(
            appStoreURL: appStoreURL.absoluteString,
            shareURL: shareURL.absoluteString,
            isSendingBack: isSendingBack
        )
    }
}
