import Foundation
import Observation

@Observable
final class SettingsStore {
    var currentMemberID: String {
        didSet { defaults.set(currentMemberID, forKey: Key.currentMemberID) }
    }
    var currentDisplayName: String {
        didSet { defaults.set(currentDisplayName, forKey: Key.currentDisplayName) }
    }
    var currentICloudEmailAddress: String {
        didSet { defaults.set(currentICloudEmailAddress, forKey: Key.currentICloudEmailAddress) }
    }
    var partnerNoteName: String {
        didSet { defaults.set(partnerNoteName, forKey: Key.partnerNoteName) }
    }
    var partnerShareOwnerID: String? {
        didSet { saveOptionalString(partnerShareOwnerID, forKey: Key.partnerShareOwnerID) }
    }
    var partnerSyncedDisplayName: String? {
        didSet { saveOptionalString(partnerSyncedDisplayName, forKey: Key.partnerSyncedDisplayName) }
    }
    /// My own avatar; synced to the partner inside my MemberProfile record.
    var currentAvatar: MemberAvatar? {
        didSet { saveAvatar(currentAvatar, forKey: Key.currentAvatar) }
    }
    /// The partner's avatar as they set it, imported from their MemberProfile record.
    var partnerSyncedAvatar: MemberAvatar? {
        didSet { saveAvatar(partnerSyncedAvatar, forKey: Key.partnerSyncedAvatar) }
    }
    /// A local-only avatar I picked for the partner; wins over `partnerSyncedAvatar`,
    /// like `partnerNoteName` wins over `partnerSyncedDisplayName`.
    var partnerAvatarOverride: MemberAvatar? {
        didSet { saveAvatar(partnerAvatarOverride, forKey: Key.partnerAvatarOverride) }
    }
    var hasCompletedInitialProfilePrompt: Bool {
        didSet { defaults.set(hasCompletedInitialProfilePrompt, forKey: Key.hasCompletedInitialProfilePrompt) }
    }
    var hasPromptedPartnerNoteForCurrentPairing: Bool {
        didSet { defaults.set(hasPromptedPartnerNoteForCurrentPairing, forKey: Key.hasPromptedPartnerNoteForCurrentPairing) }
    }
    var hasShownPairingSafetyNoticeForCurrentPairing: Bool {
        didSet { defaults.set(hasShownPairingSafetyNoticeForCurrentPairing, forKey: Key.hasShownPairingSafetyNoticeForCurrentPairing) }
    }
    /// The partner I sent my own invite link back to (receiver side of the pairing guide).
    var sentInviteBackToOwnerID: String? {
        didSet { defaults.set(sentInviteBackToOwnerID, forKey: Key.sentInviteBackToOwnerID) }
    }
    /// The partner whose share I was last prompted to answer with my own link.
    var shareBackPromptShownForOwnerID: String? {
        didSet { defaults.set(shareBackPromptShownForOwnerID, forKey: Key.shareBackPromptShownForOwnerID) }
    }
    var hasResolvedExistingICloudDataPrompt: Bool {
        didSet { defaults.set(hasResolvedExistingICloudDataPrompt, forKey: Key.hasResolvedExistingICloudDataPrompt) }
    }
    var outgoingShareParticipantIDs: [String] {
        didSet { defaults.set(outgoingShareParticipantIDs, forKey: Key.outgoingShareParticipantIDs) }
    }
    var pairingConflict: TwoPersonPairingConflict? {
        didSet { savePairingConflict() }
    }
    var iCloudSharingEnabled: Bool {
        didSet { defaults.set(iCloudSharingEnabled, forKey: Key.iCloudSharingEnabled) }
    }
    var hasStartedPairing: Bool {
        didSet { defaults.set(hasStartedPairing, forKey: Key.hasStartedPairing) }
    }
    var pairingDate: Date? {
        didSet { saveOptionalDate(pairingDate, forKey: Key.pairingDate) }
    }
    var selectedCalendarIDs: Set<String> {
        didSet { saveSelectedCalendarIDs() }
    }
    var defaultVisibility: EventVisibility {
        didSet { defaults.set(defaultVisibility.rawValue, forKey: Key.defaultVisibility) }
    }
    var appLanguage: AppLanguage {
        didSet { AppLanguagePreference.write(appLanguage, to: defaults) }
    }
    var lastSyncAt: Date? {
        didSet { defaults.set(lastSyncAt, forKey: Key.lastSyncAt) }
    }
    /// Local, per-device marker for when the user last viewed the 动态 (activity) tab.
    /// Drives the unread comment count. Deliberately NOT synced (unlike EventComment.isRead).
    var lastSeenActivityAt: Date? {
        didSet { defaults.set(lastSeenActivityAt, forKey: Key.lastSeenActivityAt) }
    }
    /// Local high-water mark for the last time local notifications were evaluated, so
    /// the same partner activity is never notified twice. Nil until the first sync.
    var lastNotifiedAt: Date? {
        didSet { defaults.set(lastNotifiedAt, forKey: Key.lastNotifiedAt) }
    }
    var lastSyncError: String?
    var syncPhase: SyncPhase = .idle

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.resetLegacyPairingStateIfNeeded(defaults: defaults)
        currentMemberID = MemberIDPolicy.normalized(defaults.string(forKey: Key.currentMemberID)) ?? MemberIDPolicy.unsyncedMemberID
        let resolvedCurrentDisplayName = MemberIDPolicy.normalized(defaults.string(forKey: Key.currentDisplayName)) ?? ""
        currentDisplayName = resolvedCurrentDisplayName
        currentICloudEmailAddress = defaults.string(forKey: Key.currentICloudEmailAddress) ?? ""
        partnerNoteName = MemberIDPolicy.normalized(defaults.string(forKey: Key.partnerNoteName)) ?? ""
        partnerShareOwnerID = defaults.string(forKey: Key.partnerShareOwnerID)
        partnerSyncedDisplayName = MemberIDPolicy.normalized(defaults.string(forKey: Key.partnerSyncedDisplayName))
        currentAvatar = Self.storedAvatar(defaults: defaults, forKey: Key.currentAvatar)
        partnerSyncedAvatar = Self.storedAvatar(defaults: defaults, forKey: Key.partnerSyncedAvatar)
        partnerAvatarOverride = Self.storedAvatar(defaults: defaults, forKey: Key.partnerAvatarOverride)
        let storedHasCompletedInitialProfilePrompt = defaults.object(forKey: Key.hasCompletedInitialProfilePrompt) as? Bool ?? false
        if storedHasCompletedInitialProfilePrompt,
           MemberIDPolicy.normalized(resolvedCurrentDisplayName) == nil {
            hasCompletedInitialProfilePrompt = false
            defaults.set(false, forKey: Key.hasCompletedInitialProfilePrompt)
        } else {
            hasCompletedInitialProfilePrompt = storedHasCompletedInitialProfilePrompt
        }
        hasPromptedPartnerNoteForCurrentPairing = defaults.object(forKey: Key.hasPromptedPartnerNoteForCurrentPairing) as? Bool ?? false
        hasShownPairingSafetyNoticeForCurrentPairing = defaults.object(forKey: Key.hasShownPairingSafetyNoticeForCurrentPairing) as? Bool ?? false
        sentInviteBackToOwnerID = MemberIDPolicy.normalized(defaults.string(forKey: Key.sentInviteBackToOwnerID))
        shareBackPromptShownForOwnerID = MemberIDPolicy.normalized(defaults.string(forKey: Key.shareBackPromptShownForOwnerID))
        hasResolvedExistingICloudDataPrompt = defaults.object(forKey: Key.hasResolvedExistingICloudDataPrompt) as? Bool ?? false
        outgoingShareParticipantIDs = defaults.stringArray(forKey: Key.outgoingShareParticipantIDs) ?? []
        pairingConflict = (defaults.data(forKey: Key.pairingConflict)).flatMap {
            try? JSONDecoder().decode(TwoPersonPairingConflict.self, from: $0)
        }
        iCloudSharingEnabled = defaults.object(forKey: Key.iCloudSharingEnabled) as? Bool ?? true
        hasStartedPairing = defaults.object(forKey: Key.hasStartedPairing) as? Bool ?? false
        pairingDate = defaults.object(forKey: Key.pairingDate) as? Date
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendarIDs) ?? [])
        defaultVisibility = EventVisibility(rawValue: defaults.string(forKey: Key.defaultVisibility) ?? "") ?? .fullDetails
        appLanguage = AppLanguagePreference.read(from: defaults)
        lastSyncAt = defaults.object(forKey: Key.lastSyncAt) as? Date
        lastSeenActivityAt = defaults.object(forKey: Key.lastSeenActivityAt) as? Date
        lastNotifiedAt = defaults.object(forKey: Key.lastNotifiedAt) as? Date
    }

    var hasSyncedMemberID: Bool {
        currentMemberID != MemberIDPolicy.unsyncedMemberID
    }

    /// One-time reset for pre-userRecordID installs: the legacy local-owner-UUID
    /// identity cannot be mapped onto the CloudKit identity, so pairing state is
    /// wiped and the user re-pairs. Non-pairing preferences are preserved.
    private static func resetLegacyPairingStateIfNeeded(defaults: UserDefaults) {
        guard defaults.string(forKey: LegacyKey.localOwnerID) != nil else { return }
        for key in LegacyKey.allRemovedKeys {
            defaults.removeObject(forKey: key)
        }
        for key in [
            Key.partnerShareOwnerID,
            Key.partnerSyncedDisplayName,
            Key.partnerNoteName,
            Key.partnerSyncedAvatar,
            Key.partnerAvatarOverride,
            Key.outgoingShareParticipantIDs,
            Key.hasStartedPairing,
            Key.pairingDate,
            Key.hasPromptedPartnerNoteForCurrentPairing,
            Key.hasShownPairingSafetyNoticeForCurrentPairing,
            Key.hasResolvedExistingICloudDataPrompt,
            Key.lastSyncAt
        ] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: LegacyKey.needsLocalDataPurge)
    }

    func consumeLegacyLocalDataPurgeFlag() -> Bool {
        guard defaults.bool(forKey: LegacyKey.needsLocalDataPurge) else { return false }
        defaults.removeObject(forKey: LegacyKey.needsLocalDataPurge)
        return true
    }

    static func storedPartnerShareOwnerID(defaults: UserDefaults = .standard) -> String? {
        MemberIDPolicy.normalized(defaults.string(forKey: Key.partnerShareOwnerID))
    }

    static func storedOutgoingShareParticipantIDs(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: Key.outgoingShareParticipantIDs) ?? []
    }

    func toggleCalendarSelection(_ calendarID: String, isSelected: Bool) {
        if isSelected {
            selectedCalendarIDs.insert(calendarID)
        } else {
            selectedCalendarIDs.remove(calendarID)
        }
    }

    private func saveSelectedCalendarIDs() {
        defaults.set(Array(selectedCalendarIDs).sorted(), forKey: Key.selectedCalendarIDs)
    }

    private func saveOptionalString(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Forgets everything about the partner's avatar; called wherever pairing is torn down.
    func clearPartnerAvatars() {
        partnerSyncedAvatar = nil
        partnerAvatarOverride = nil
    }

    private func saveAvatar(_ avatar: MemberAvatar?, forKey key: String) {
        if let avatar = MemberAvatarPolicy.normalized(avatar), let data = try? JSONEncoder().encode(avatar) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func storedAvatar(defaults: UserDefaults, forKey key: String) -> MemberAvatar? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(MemberAvatar.self, from: $0) }
    }

    func markPairingDateIfNeeded(at date: Date = .now, calendar: Calendar = .current) {
        guard pairingDate == nil else { return }
        pairingDate = PairingDatePolicy.normalizedPairingDate(date, calendar: calendar)
    }

    func clearPairingDate() {
        pairingDate = nil
    }

    private func savePairingConflict() {
        if let pairingConflict, let data = try? JSONEncoder().encode(pairingConflict) {
            defaults.set(data, forKey: Key.pairingConflict)
        } else {
            defaults.removeObject(forKey: Key.pairingConflict)
        }
    }

    private func saveOptionalDate(_ value: Date?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private enum Key {
        static let currentMemberID = "currentMemberID"
        static let currentDisplayName = "currentDisplayName"
        static let currentICloudEmailAddress = "currentICloudEmailAddress"
        static let partnerNoteName = "partnerNoteName"
        static let partnerShareOwnerID = "partnerShareOwnerID"
        static let partnerSyncedDisplayName = "partnerSyncedDisplayName"
        static let currentAvatar = "currentAvatar"
        static let partnerSyncedAvatar = "partnerSyncedAvatar"
        static let partnerAvatarOverride = "partnerAvatarOverride"
        static let hasCompletedInitialProfilePrompt = "hasCompletedInitialProfilePrompt"
        static let hasPromptedPartnerNoteForCurrentPairing = "hasPromptedPartnerNoteForCurrentPairing"
        static let hasShownPairingSafetyNoticeForCurrentPairing = "hasShownPairingSafetyNoticeForCurrentPairing"
        static let sentInviteBackToOwnerID = "sentInviteBackToOwnerID"
        static let shareBackPromptShownForOwnerID = "shareBackPromptShownForOwnerID"
        static let hasResolvedExistingICloudDataPrompt = "hasResolvedExistingICloudDataPrompt"
        static let outgoingShareParticipantIDs = "outgoingShareParticipantIDs"
        static let pairingConflict = "pairingConflict"
        static let iCloudSharingEnabled = "iCloudSharingEnabled"
        static let hasStartedPairing = "hasStartedPairing"
        static let pairingDate = "pairingDate"
        static let selectedCalendarIDs = "selectedCalendarIDs"
        static let defaultVisibility = "defaultVisibility"
        static let lastSyncAt = "lastSyncAt"
        static let lastSeenActivityAt = "lastSeenActivityAt"
        static let lastNotifiedAt = "lastNotifiedAt"
    }

    private enum LegacyKey {
        static let localOwnerID = "currentLocalOwnerID"
        static let needsLocalDataPurge = "needsLegacyLocalDataPurge"
        static let allRemovedKeys = [
            localOwnerID,
            "pairingID",
            "partnerICloudEmailAddresses",
            "inactiveSharedOwnerIDs",
            "ShareCalPendingAcceptedPartnerICloudEmailAddress"
        ]
    }
}

extension SettingsStore {
    var strings: ShareCalStrings {
        ShareCalStrings(language: appLanguage)
    }

    var partnerDisplayName: String {
        PairingSettingsPolicy.partnerDisplayName(
            partnerNoteName: partnerNoteName,
            partnerSyncedDisplayName: partnerSyncedDisplayName,
            fallback: strings.partnerTitle
        )
    }

    var partnerStatusDisplayName: String {
        PairingSettingsPolicy.partnerStatusDisplayName(
            partnerNoteName: partnerNoteName,
            partnerSyncedDisplayName: partnerSyncedDisplayName,
            fallback: strings.partnerTitle,
            language: appLanguage
        )
    }

    var partnerOwnerIDForLocalData: String {
        partnerShareOwnerID ?? MemberIDPolicy.unknownPartnerID
    }

    var partnerAvatar: MemberAvatar? {
        MemberAvatarPolicy.resolvedPartnerAvatar(override: partnerAvatarOverride, synced: partnerSyncedAvatar)
    }
}
