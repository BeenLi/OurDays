import Foundation
import Observation

@Observable
final class SettingsStore {
    var currentMemberID: String {
        didSet { defaults.set(currentMemberID, forKey: Key.currentMemberID) }
    }
    var currentDisplayName: String {
        didSet {
            defaults.set(currentDisplayName, forKey: Key.currentDisplayName)
            if currentDisplayName != oldValue { currentProfileUpdatedAt = .now }
        }
    }
    var currentICloudEmailAddress: String {
        didSet { defaults.set(currentICloudEmailAddress, forKey: Key.currentICloudEmailAddress) }
    }
    var partnerNoteName: String {
        didSet {
            defaults.set(partnerNoteName, forKey: Key.partnerNoteName)
            markRelayedEdit(\.partnerNoteUpdatedAt)
        }
    }
    var partnerShareOwnerID: String? {
        didSet { saveOptionalString(partnerShareOwnerID, forKey: Key.partnerShareOwnerID) }
    }
    var partnerSyncedDisplayName: String? {
        didSet { saveOptionalString(partnerSyncedDisplayName, forKey: Key.partnerSyncedDisplayName) }
    }
    /// My own avatar; synced to the partner inside my MemberProfile record.
    var currentAvatar: MemberAvatar? {
        didSet {
            saveAvatar(currentAvatar, forKey: Key.currentAvatar)
            if currentAvatar != oldValue { currentProfileUpdatedAt = .now }
        }
    }
    /// When this device last changed `currentDisplayName` / `currentAvatar`, or the cloud
    /// time of the copy it adopted. Another device on the same Apple ID writes the same
    /// MemberProfile record; `OwnMemberProfileMergePolicy` lets the newer edit win.
    var currentProfileUpdatedAt: Date? {
        didSet { saveOptionalDate(currentProfileUpdatedAt, forKey: Key.currentProfileUpdatedAt) }
    }
    /// The partner's avatar as they set it, imported from their MemberProfile record.
    var partnerSyncedAvatar: MemberAvatar? {
        didSet { saveAvatar(partnerSyncedAvatar, forKey: Key.partnerSyncedAvatar) }
    }
    /// A local-only avatar I picked for the partner; wins over `partnerSyncedAvatar`,
    /// like `partnerNoteName` wins over `partnerSyncedDisplayName`.
    var partnerAvatarOverride: MemberAvatar? {
        didSet {
            saveAvatar(partnerAvatarOverride, forKey: Key.partnerAvatarOverride)
            markRelayedEdit(\.partnerNoteUpdatedAt)
        }
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
        didSet {
            defaults.set(defaultVisibility.rawValue, forKey: Key.defaultVisibility)
            markRelayedEdit(\.defaultVisibilityUpdatedAt)
        }
    }
    var appLanguage: AppLanguage {
        didSet {
            AppLanguagePreference.write(appLanguage, to: defaults)
            markRelayedEdit(\.appLanguageUpdatedAt)
        }
    }
    /// When a person last changed each setting that follows them to their other devices
    /// (`OwnRelayedSettings`), or the edit time of the copy adopted from another device.
    var partnerNoteUpdatedAt: Date? {
        didSet { saveOptionalDate(partnerNoteUpdatedAt, forKey: Key.partnerNoteUpdatedAt) }
    }
    var calendarSelectionUpdatedAt: Date? {
        didSet { saveOptionalDate(calendarSelectionUpdatedAt, forKey: Key.calendarSelectionUpdatedAt) }
    }
    var defaultVisibilityUpdatedAt: Date? {
        didSet { saveOptionalDate(defaultVisibilityUpdatedAt, forKey: Key.defaultVisibilityUpdatedAt) }
    }
    var appLanguageUpdatedAt: Date? {
        didSet { saveOptionalDate(appLanguageUpdatedAt, forKey: Key.appLanguageUpdatedAt) }
    }
    /// The calendar selection of all my devices, by account and title. Holds the
    /// calendars this device doesn't have, so its own edits don't drop them.
    var relayedCalendarReferences: Set<CalendarReference> {
        didSet { saveCalendarReferences() }
    }
    /// True while a copy from another device is being applied: those writes are not
    /// this device's edits and must not get a new edit time.
    @ObservationIgnored private var isAdoptingRelayedSettings = false
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
    /// App Store rating moments already used on this install (`ReviewPromptPolicy`).
    /// Kept across unpair/re-pair: each moment asks once per install.
    /// Accepted invitations whose joint event this device has seen in its own system
    /// calendar; only those may be auto-canceled when the event disappears
    /// (`InvitationLocalEventSyncPolicy.reconcileAcceptedInvitations`).
    var invitationIDsWithLocalEventSeen: Set<String> {
        didSet {
            guard invitationIDsWithLocalEventSeen != oldValue else { return }
            defaults.set(invitationIDsWithLocalEventSeen.sorted(), forKey: Key.invitationIDsWithLocalEventSeen)
        }
    }
    var reviewPromptedMoments: Set<ReviewPromptMoment> {
        didSet { defaults.set(reviewPromptedMoments.map(\.rawValue).sorted(), forKey: Key.reviewPromptedMoments) }
    }
    var lastReviewPromptAt: Date? {
        didSet { saveOptionalDate(lastReviewPromptAt, forKey: Key.lastReviewPromptAt) }
    }
    var lastSyncError: String?
    var syncPhase: SyncPhase = .idle
    /// The partner whose share CloudKit is accepting right now. Not saved: it only lets
    /// the pairing card move on during the several-second accept, and a relaunch
    /// mid-accept simply shows the step it was on.
    var acceptingShareOwnerID: String?
    /// Why the last accept failed, shown on the pairing card it stepped back to.
    var shareAcceptanceFailureMessage: String?
    /// The incoming half of the pairing as the UI shows it: the accepted partner, or the
    /// one being accepted.
    var displayedIncomingOwnerID: String? {
        partnerShareOwnerID ?? acceptingShareOwnerID
    }
    /// True while the step shown is ahead of CloudKit.
    var isConfirmingShareAcceptance: Bool {
        partnerShareOwnerID == nil && acceptingShareOwnerID != nil
    }
    /// Bumped whenever this device changes the pairing itself: an unpair, or a share
    /// it just accepted. A sync that read the cloud before that change must not write
    /// its stale view of the pairing back (`SyncCoordinator`).
    var localPairingChangeCount = 0

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
        currentProfileUpdatedAt = defaults.object(forKey: Key.currentProfileUpdatedAt) as? Date
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
        partnerNoteUpdatedAt = defaults.object(forKey: Key.partnerNoteUpdatedAt) as? Date
        calendarSelectionUpdatedAt = defaults.object(forKey: Key.calendarSelectionUpdatedAt) as? Date
        defaultVisibilityUpdatedAt = defaults.object(forKey: Key.defaultVisibilityUpdatedAt) as? Date
        appLanguageUpdatedAt = defaults.object(forKey: Key.appLanguageUpdatedAt) as? Date
        relayedCalendarReferences = Set(
            (defaults.data(forKey: Key.relayedCalendarReferences)).flatMap {
                try? JSONDecoder().decode([CalendarReference].self, from: $0)
            } ?? []
        )
        lastSyncAt = defaults.object(forKey: Key.lastSyncAt) as? Date
        lastSeenActivityAt = defaults.object(forKey: Key.lastSeenActivityAt) as? Date
        lastNotifiedAt = defaults.object(forKey: Key.lastNotifiedAt) as? Date
        invitationIDsWithLocalEventSeen = Set(defaults.stringArray(forKey: Key.invitationIDsWithLocalEventSeen) ?? [])
        reviewPromptedMoments = Set((defaults.stringArray(forKey: Key.reviewPromptedMoments) ?? []).compactMap(ReviewPromptMoment.init(rawValue:)))
        lastReviewPromptAt = defaults.object(forKey: Key.lastReviewPromptAt) as? Date
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

    /// A person's pick in Settings. The automatic ShareCal selection elsewhere is not an
    /// edit, so it never wins over the selection made on another device.
    func toggleCalendarSelection(_ calendarID: String, isSelected: Bool) {
        if isSelected {
            selectedCalendarIDs.insert(calendarID)
        } else {
            selectedCalendarIDs.remove(calendarID)
        }
        markRelayedEdit(\.calendarSelectionUpdatedAt)
    }

    private func markRelayedEdit(_ stamp: ReferenceWritableKeyPath<SettingsStore, Date?>) {
        guard !isAdoptingRelayedSettings else { return }
        self[keyPath: stamp] = OwnSettingsRelayClock.stamp()
    }

    private func saveCalendarReferences() {
        if let data = try? JSONEncoder().encode(relayedCalendarReferences.sorted()) {
            defaults.set(data, forKey: Key.relayedCalendarReferences)
        }
    }

    // MARK: Settings that follow me to my other devices (pairing-sync-integrity 0013)

    /// Settings edited before edit times existed still travel, as the oldest possible
    /// edit: they win over a device that never set them and lose to any real edit.
    private var effectivePartnerNoteUpdatedAt: Date? {
        guard hasPromptedPartnerNoteForCurrentPairing else { return partnerNoteUpdatedAt }
        return partnerNoteUpdatedAt ?? .distantPast
    }

    private var effectiveCalendarSelectionUpdatedAt: Date? {
        guard !selectedCalendarIDs.isEmpty || !relayedCalendarReferences.isEmpty else { return calendarSelectionUpdatedAt }
        return calendarSelectionUpdatedAt ?? .distantPast
    }

    private var effectiveDefaultVisibilityUpdatedAt: Date? {
        defaultVisibilityUpdatedAt ?? (defaultVisibility == .fullDetails ? nil : .distantPast)
    }

    private var effectiveAppLanguageUpdatedAt: Date? {
        appLanguageUpdatedAt ?? (AppLanguagePreference.hasExplicitChoice(in: defaults) ? .distantPast : nil)
    }

    /// This device's copy of the relayed settings. `calendars` is nil without calendar
    /// access; the selection then travels as last relayed.
    func relayedSettingsSnapshot(calendars: [CalendarDescriptor]?) -> OwnRelayedSettings {
        var snapshot = OwnRelayedSettings()
        if hasPromptedPartnerNoteForCurrentPairing,
           let partnerID = MemberIDPolicy.normalized(partnerShareOwnerID),
           let updatedAt = effectivePartnerNoteUpdatedAt {
            snapshot.partnerNote = OwnRelayedSettings.PartnerNote(
                partnerID: partnerID,
                noteName: partnerNoteName,
                avatarOverride: MemberAvatarPolicy.normalized(partnerAvatarOverride),
                updatedAt: updatedAt
            )
        }
        let references = calendars.map {
            CalendarSelectionRelayPolicy.references(
                relayed: relayedCalendarReferences,
                localSelection: selectedCalendarIDs,
                calendars: $0
            )
        } ?? relayedCalendarReferences
        if !references.isEmpty, let updatedAt = effectiveCalendarSelectionUpdatedAt {
            snapshot.calendars = OwnRelayedSettings.Calendars(references: references.sorted(), updatedAt: updatedAt)
        }
        if let updatedAt = effectiveDefaultVisibilityUpdatedAt {
            snapshot.defaultVisibility = OwnRelayedSettings.Value(rawValue: defaultVisibility.rawValue, updatedAt: updatedAt)
        }
        if let updatedAt = effectiveAppLanguageUpdatedAt {
            snapshot.language = OwnRelayedSettings.Value(rawValue: appLanguage.rawValue, updatedAt: updatedAt)
        }
        snapshot.lastSeenActivityAt = lastSeenActivityAt
        return snapshot
    }

    /// Takes each part of `relayed` that is newer than this device's own edit. Safe to
    /// call again later in the same sync (after the partner is known); taken parts no
    /// longer compare newer.
    func adoptRelayedSettings(_ relayed: OwnRelayedSettings, calendars: [CalendarDescriptor]?) {
        isAdoptingRelayedSettings = true
        defer { isAdoptingRelayedSettings = false }

        if let note = relayed.partnerNote,
           OwnSettingsRelayAdoptionPolicy.adoptsPartnerNote(note, currentPartnerID: partnerShareOwnerID),
           OwnSettingsRelayAdoptionPolicy.shouldAdopt(relayedAt: note.updatedAt, localAt: effectivePartnerNoteUpdatedAt) {
            if partnerNoteName != note.noteName { partnerNoteName = note.noteName }
            let avatar = MemberAvatarPolicy.normalized(note.avatarOverride)
            if partnerAvatarOverride != avatar { partnerAvatarOverride = avatar }
            partnerNoteUpdatedAt = note.updatedAt
            // The note and pairing-safety prompts were answered on that device.
            if !hasPromptedPartnerNoteForCurrentPairing { hasPromptedPartnerNoteForCurrentPairing = true }
            if !hasShownPairingSafetyNoticeForCurrentPairing { hasShownPairingSafetyNoticeForCurrentPairing = true }
        }
        if let relayedCalendars = relayed.calendars,
           let calendars,
           OwnSettingsRelayAdoptionPolicy.shouldAdopt(
               relayedAt: relayedCalendars.updatedAt,
               localAt: effectiveCalendarSelectionUpdatedAt
           ) {
            if let ids = OwnSettingsRelayAdoptionPolicy.calendarSelection(relayed: relayedCalendars, calendars: calendars),
               ids != selectedCalendarIDs {
                selectedCalendarIDs = ids
            }
            let references = Set(relayedCalendars.references)
            if relayedCalendarReferences != references { relayedCalendarReferences = references }
            calendarSelectionUpdatedAt = relayedCalendars.updatedAt
        }
        if let visibility = relayed.defaultVisibility,
           let value = EventVisibility(rawValue: visibility.rawValue),
           OwnSettingsRelayAdoptionPolicy.shouldAdopt(relayedAt: visibility.updatedAt, localAt: effectiveDefaultVisibilityUpdatedAt) {
            if defaultVisibility != value { defaultVisibility = value }
            defaultVisibilityUpdatedAt = visibility.updatedAt
        }
        if let language = relayed.language,
           let value = AppLanguage(rawValue: language.rawValue),
           OwnSettingsRelayAdoptionPolicy.shouldAdopt(relayedAt: language.updatedAt, localAt: effectiveAppLanguageUpdatedAt) {
            if appLanguage != value { appLanguage = value }
            appLanguageUpdatedAt = language.updatedAt
        }
        if let seen = relayed.lastSeenActivityAt, seen > (lastSeenActivityAt ?? .distantPast) {
            lastSeenActivityAt = seen
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

    /// Back to not paired: everything this device knew about the partner and both
    /// halves of the pairing. Used when I unpair and when the partner unpairs me.
    func clearPairingState() {
        localPairingChangeCount += 1
        iCloudSharingEnabled = false
        hasStartedPairing = false
        partnerShareOwnerID = nil
        partnerNoteName = ""
        hasPromptedPartnerNoteForCurrentPairing = false
        hasShownPairingSafetyNoticeForCurrentPairing = false
        partnerSyncedDisplayName = nil
        clearPartnerAvatars()
        outgoingShareParticipantIDs = []
        pairingConflict = nil
        sentInviteBackToOwnerID = nil
        shareBackPromptShownForOwnerID = nil
        clearPairingDate()
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

    /// Takes the nickname/avatar another device of mine saved, keeping its edit time so
    /// this device doesn't count the copy as a newer local edit.
    func adoptOwnProfile(_ profile: CloudKitMemberProfile) {
        currentDisplayName = profile.displayName
        currentAvatar = MemberAvatarPolicy.normalized(profile.avatar)
        currentProfileUpdatedAt = profile.updatedAt
    }

    func markReviewPrompted(_ moment: ReviewPromptMoment, at date: Date = .now) {
        reviewPromptedMoments.insert(moment)
        lastReviewPromptAt = date
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
        static let currentProfileUpdatedAt = "currentProfileUpdatedAt"
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
        static let reviewPromptedMoments = "reviewPromptedMoments"
        static let invitationIDsWithLocalEventSeen = "invitationIDsWithLocalEventSeen"
        static let lastReviewPromptAt = "lastReviewPromptAt"
        static let partnerNoteUpdatedAt = "partnerNoteUpdatedAt"
        static let calendarSelectionUpdatedAt = "calendarSelectionUpdatedAt"
        static let defaultVisibilityUpdatedAt = "defaultVisibilityUpdatedAt"
        static let appLanguageUpdatedAt = "appLanguageUpdatedAt"
        static let relayedCalendarReferences = "relayedCalendarReferences"
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
