import Foundation

/// A calendar named the way every device of one Apple ID can recognize it. EventKit's
/// `calendarIdentifier` is only valid on the device that read it; the account it lives in
/// (the `EKSource` title: "iCloud", a Google address, an Exchange account) plus its own
/// title is the same on the iPhone and the Mac.
struct CalendarReference: Codable, Hashable, Comparable {
    let sourceTitle: String
    let title: String

    static func < (lhs: CalendarReference, rhs: CalendarReference) -> Bool {
        (lhs.sourceTitle, lhs.title) < (rhs.sourceTitle, rhs.title)
    }
}

/// The settings that follow the user from one of their devices to another, kept in a
/// private zone the partner can't read (pairing-sync-integrity decision 0013). Each part
/// carries the time it was last changed by a person, so the newer edit wins part by part.
struct OwnRelayedSettings: Codable, Equatable {
    struct PartnerNote: Codable, Equatable {
        /// The partner this note and avatar belong to; ignored once paired with someone else.
        let partnerID: String
        let noteName: String
        let avatarOverride: MemberAvatar?
        let updatedAt: Date
    }

    struct Calendars: Codable, Equatable {
        /// Sorted, so equal selections encode to equal bytes.
        let references: [CalendarReference]
        let updatedAt: Date
    }

    struct Value: Codable, Equatable {
        let rawValue: String
        let updatedAt: Date
    }

    /// The day the pairing with `partnerID` began, as the device that saw it begin
    /// recorded it (a date recovered from the share root is never relayed).
    struct Pairing: Codable, Equatable {
        let partnerID: String
        let date: Date
    }

    var partnerNote: PartnerNote?
    var calendars: Calendars?
    var defaultVisibility: Value?
    var language: Value?
    /// When the 动态 tab was last opened on any device; the later one wins.
    var lastSeenActivityAt: Date?
    var pairing: Pairing?
    /// When one of my devices last unpaired or switched partner; a pairing that began
    /// before that day is over and no longer relayed. The later one wins.
    var pairingClearedAt: Date?
    /// When a Mac of mine last uploaded its own events; the later one wins. Tells the
    /// iPhone to look for a record the Mac already made before starting one of its own
    /// (`OwnEventUploadPolicy`).
    var macUploadsOwnEventsAt: Date?

    static let empty = OwnRelayedSettings()
}

enum OwnSettingsRelayClock {
    /// Edit times are kept to whole seconds so a stored copy compares equal to the
    /// device's own after a round trip, and an unchanged record is never written again
    /// (every write pushes the user's other devices).
    static func stamp(_ date: Date = .now) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

enum OwnSettingsRelayMergePolicy {
    /// Part by part, the newer edit wins; on a tie the cloud copy is kept, so two devices
    /// holding the same settings never write each other back.
    static func merge(
        local: OwnRelayedSettings,
        cloud: OwnRelayedSettings?,
        calendar: Calendar = .current
    ) -> OwnRelayedSettings {
        guard let cloud else { return local }
        let clearedAt = [local.pairingClearedAt, cloud.pairingClearedAt].compactMap { $0 }.max()
        return OwnRelayedSettings(
            partnerNote: newer(local.partnerNote, cloud.partnerNote, \.updatedAt),
            calendars: newer(local.calendars, cloud.calendars, \.updatedAt),
            defaultVisibility: newer(local.defaultVisibility, cloud.defaultVisibility, \.updatedAt),
            language: newer(local.language, cloud.language, \.updatedAt),
            lastSeenActivityAt: [local.lastSeenActivityAt, cloud.lastSeenActivityAt].compactMap { $0 }.max(),
            pairing: PairingDateRelayPolicy.merge(
                local.pairing,
                cloud.pairing,
                clearedAt: clearedAt,
                calendar: calendar
            ),
            pairingClearedAt: clearedAt,
            macUploadsOwnEventsAt: [local.macUploadsOwnEventsAt, cloud.macUploadsOwnEventsAt].compactMap { $0 }.max()
        )
    }

    /// Only a merge that differs from what the cloud holds is written.
    static func needsUpload(merged: OwnRelayedSettings, cloud: OwnRelayedSettings?) -> Bool {
        merged != (cloud ?? .empty)
    }

    private static func newer<T>(_ local: T?, _ cloud: T?, _ time: KeyPath<T, Date>) -> T? {
        guard let local else { return cloud }
        guard let cloud else { return local }
        return local[keyPath: time] > cloud[keyPath: time] ? local : cloud
    }
}

/// Moves the calendar selection between devices. A device keeps choosing by its own
/// calendar IDs; what travels is the set of references. A reference is only matched when
/// exactly one calendar here has that account and title: two calendars of the same name
/// in one account are skipped instead of guessed.
enum CalendarSelectionRelayPolicy {
    static func reference(for calendar: CalendarDescriptor) -> CalendarReference? {
        let source = calendar.sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !title.isEmpty else { return nil }
        return CalendarReference(sourceTitle: source, title: title)
    }

    /// Calendars on this device that a reference names unambiguously.
    static func uniqueCalendars(_ calendars: [CalendarDescriptor]) -> [CalendarReference: CalendarDescriptor] {
        var groups: [CalendarReference: [CalendarDescriptor]] = [:]
        for calendar in calendars {
            guard let reference = reference(for: calendar) else { continue }
            groups[reference, default: []].append(calendar)
        }
        return groups.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    /// The selection to share with my other devices: what they chose among calendars this
    /// device can't see is kept; for the ones it can see, this device's choice counts.
    static func references(
        relayed: Set<CalendarReference>,
        localSelection: Set<String>,
        calendars: [CalendarDescriptor]
    ) -> Set<CalendarReference> {
        let unique = uniqueCalendars(calendars)
        let visibleHere = Set(unique.keys)
        let selectedHere = unique.filter { localSelection.contains($0.value.id) }.keys
        return relayed.subtracting(visibleHere).union(selectedHere)
    }

    /// This device's calendar IDs for a relayed selection.
    static func localIDs(for references: Set<CalendarReference>, calendars: [CalendarDescriptor]) -> Set<String> {
        let unique = uniqueCalendars(calendars)
        return Set(references.compactMap { unique[$0]?.id })
    }

    /// Chosen on another device but not available here, for the hint under the list.
    static func unavailable(_ references: Set<CalendarReference>, calendars: [CalendarDescriptor]) -> [CalendarReference] {
        let unique = uniqueCalendars(calendars)
        return references.filter { unique[$0] == nil }.sorted()
    }
}

/// What a relayed copy changes on this device. A part is taken only when it is newer than
/// this device's own edit (or this device never edited it).
enum OwnSettingsRelayAdoptionPolicy {
    static func shouldAdopt(relayedAt: Date, localAt: Date?) -> Bool {
        guard let localAt else { return true }
        return relayedAt > localAt
    }

    /// A note for the current partner means the user already went through the note and
    /// pairing-safety prompts on another device.
    static func adoptsPartnerNote(_ note: OwnRelayedSettings.PartnerNote, currentPartnerID: String?) -> Bool {
        guard let currentPartnerID = MemberIDPolicy.normalized(currentPartnerID) else { return false }
        return MemberIDPolicy.normalized(note.partnerID) == currentPartnerID
    }

    /// A relayed selection that matches nothing here leaves this device's own selection
    /// alone, so the app still has a calendar to show (e.g. the iPhone only shares its
    /// "On My iPhone" ShareCal calendar).
    static func calendarSelection(
        relayed: OwnRelayedSettings.Calendars,
        calendars: [CalendarDescriptor]
    ) -> Set<String>? {
        let ids = CalendarSelectionRelayPolicy.localIDs(for: Set(relayed.references), calendars: calendars)
        return ids.isEmpty ? nil : ids
    }
}

/// The pairing day follows the user to their other devices (decision 0014). A device
/// that joins later can't know it: the first sync there would count from today, and the
/// share root's creation date (used after a reinstall) is the day the invitation was
/// made, which can be days before the partner accepted.
enum PairingDateRelayPolicy {
    /// Same partner: the earliest day any device saw wins, because a device that joined
    /// later records the day it first synced. Different partners: the newer pairing.
    /// A pairing that began before the last unpair is dropped.
    static func merge(
        _ local: OwnRelayedSettings.Pairing?,
        _ cloud: OwnRelayedSettings.Pairing?,
        clearedAt: Date?,
        calendar: Calendar = .current
    ) -> OwnRelayedSettings.Pairing? {
        let live = [local, cloud].compactMap { $0 }.filter { isLive($0, clearedAt: clearedAt, calendar: calendar) }
        guard let first = live.first else { return nil }
        guard live.count == 2 else { return first }
        let (a, b) = (live[0], live[1])
        if MemberIDPolicy.normalized(a.partnerID) == MemberIDPolicy.normalized(b.partnerID) {
            return a.date <= b.date ? a : b
        }
        return a.date >= b.date ? a : b
    }

    static func isLive(_ pairing: OwnRelayedSettings.Pairing, clearedAt: Date?, calendar: Calendar = .current) -> Bool {
        guard let clearedAt else { return true }
        return pairing.date >= calendar.startOfDay(for: clearedAt)
    }

    /// Whether this device takes the relayed day: only for the current partner, and
    /// only over a day this device didn't see itself (none, recovered from the share
    /// root, or from before the last unpair) or a later one.
    static func adoptsPairingDate(
        _ relayed: OwnRelayedSettings.Pairing,
        currentPartnerID: String?,
        localDate: Date?,
        localDateIsRecovered: Bool,
        clearedAt: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let currentPartnerID = MemberIDPolicy.normalized(currentPartnerID),
              MemberIDPolicy.normalized(relayed.partnerID) == currentPartnerID,
              isLive(relayed, clearedAt: clearedAt, calendar: calendar) else { return false }
        guard let localDate, !localDateIsRecovered else { return true }
        if let clearedAt, localDate < calendar.startOfDay(for: clearedAt) { return true }
        return relayed.date < localDate
    }
}

/// A second device of the same Apple ID (or a reinstall) finds this record already written
/// by the device in use. There is nothing to choose then: the data is the user's own and
/// in use, and "delete" would wipe what the other device runs on, so the prompt is skipped
/// and the existing data is used.
enum ExistingICloudDataSecondDevicePolicy {
    static func continuesWithoutAsking(ownSettingsExist: Bool) -> Bool {
        ownSettingsExist
    }
}
