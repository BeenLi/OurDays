import CryptoKit
import Foundation

struct CalendarDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
    /// The account the calendar lives in (`EKSource.title`); with `title` it names the
    /// calendar on every device of the user (`CalendarSelectionRelayPolicy`).
    var sourceTitle: String = ""
}

enum ShareCalSmokeTestEventPolicy {
    static let title = "ShareCal E2E Smoke Test"
    static let notes = "Created by ShareCal simulator validation."

    static func draft(now: Date = .now, title: String = title) -> LocalCalendarEventDraft {
        LocalCalendarEventDraft(
            title: title,
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(45 * 60),
            isAllDay: false,
            location: nil,
            notes: notes
        )
    }
}

enum ShareCalCalendarBootstrapPolicy {
    static let calendarTitle = "ShareCal"
    static let calendarColorHex = "#FF2D55"

    static func shouldOfferCreation(calendars: [CalendarDescriptor]) -> Bool {
        !calendars.contains { calendar in
            isShareCalCalendar(calendar) && calendar.allowsContentModifications
        }
    }

    static func selectedCalendarIDs(
        afterEnsuring calendar: CalendarDescriptor,
        currentSelection: Set<String>
    ) -> Set<String> {
        var selection = currentSelection
        selection.insert(calendar.id)
        return selection
    }

    static func isShareCalCalendar(_ calendar: CalendarDescriptor) -> Bool {
        calendar.title.compare(calendarTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// Which calendar the "+" sheet adds an event of one's own to. An invitation's event
/// always goes to the app's own calendar, where the partner's accepted copy lands too.
///
/// Only calendars the user already shares are offered: creating the event in an
/// unshared calendar would have to switch that whole calendar on for the partner.
enum InviteCalendarChoicePolicy {
    static func candidates(
        calendars: [CalendarDescriptor],
        selectedCalendarIDs: Set<String>
    ) -> [CalendarDescriptor] {
        calendars.filter { $0.allowsContentModifications && selectedCalendarIDs.contains($0.id) }
    }

    /// Last calendar the user picked, else the system's default calendar, else the
    /// app's own calendar, else the first shared one. Nil when nothing writable is
    /// shared; the caller then creates the app's own calendar as before.
    static func defaultCalendarID(
        candidates: [CalendarDescriptor],
        lastUsedCalendarID: String?,
        systemDefaultCalendarID: String?
    ) -> String? {
        let ids = Set(candidates.map(\.id))
        if let lastUsedCalendarID, ids.contains(lastUsedCalendarID) { return lastUsedCalendarID }
        if let systemDefaultCalendarID, ids.contains(systemDefaultCalendarID) { return systemDefaultCalendarID }
        if let own = candidates.first(where: ShareCalCalendarBootstrapPolicy.isShareCalCalendar) { return own.id }
        return candidates.first?.id
    }
}

struct CalendarSourceEvent: Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
    let startDate: Date
    let endDate: Date
    let occurrenceStartDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    /// Part of a repeating series: its occurrences share `eventIdentifier`, so only
    /// the occurrence date tells them apart.
    var isRecurring: Bool = false
    /// `EKCalendarItem.calendarItemExternalIdentifier`: the server's identifier for the
    /// event (the iCalendar UID on iCloud and CalDAV), the same on every device of the
    /// user, unlike `eventIdentifier` and `calendarIdentifier`. Nil or empty when the
    /// calendar has none.
    var externalIdentifier: String? = nil
    /// One occurrence of a series that was changed on its own (`EKEvent.isDetached`).
    /// It shares the series' external identifier; its original date tells it apart.
    var isDetached: Bool = false

    var occurrenceEpoch: Int {
        Int(occurrenceStartDate.timeIntervalSince1970.rounded())
    }
}

struct LocalCalendarEventDraft: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

struct CreatedCalendarEvent: Equatable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
}

enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess
    case legacyAuthorized
    case unknown

    var canReadEvents: Bool {
        switch self {
        case .fullAccess, .legacyAuthorized:
            true
        default:
            false
        }
    }
}

/// Builds the stable key that identifies one EventKit occurrence across syncs.
/// Shared by the mirror generator, the SwiftData models and the display policies, so
/// it lives with the other calendar-source policies rather than in `EventMirrorService`.
/// The cross-device identity hint of an occurrence (`EventMirror.stableKey`). The record
/// name stays what it was first uploaded as (`EventMirrorKeyPolicy`); this is how my other
/// devices, whose EventKit identifiers differ, find that record for the same event.
///
/// Made from the external identifier, plus the original occurrence date for occurrences
/// of a series (they share the identifier); a one-off event keeps its key when moved.
/// All-day occurrences use the calendar day, so a device in another time zone agrees.
/// When two events in the list would get the same key (one invitation in two calendars),
/// the calendar title is mixed in. Hashed: the partner can read the record and has no use
/// for the raw identifier. "" when the event has no external identifier.
enum EventStableKeyPolicy {
    static let version = "s1"

    /// `[derived mirror key: stable key]` for `events`.
    static func stableKeys(
        for events: [CalendarSourceEvent],
        calendar: Calendar = .current
    ) -> [String: String] {
        let bases = events.map { base(for: $0, calendar: calendar) }
        var counts: [String: Int] = [:]
        for base in bases.compactMap({ $0 }) {
            counts[base, default: 0] += 1
        }
        var keys: [String: String] = [:]
        for (event, base) in zip(events, bases) {
            let mirrorKey = EventMirrorKeyPolicy.makeMirrorKey(for: event)
            guard let base else {
                keys[mirrorKey] = ""
                continue
            }
            let material = (counts[base] ?? 0) > 1 ? "\(base)\n\(event.calendarTitle)" : base
            keys[mirrorKey] = "\(version):\(digest(material))"
        }
        return keys
    }

    static func base(for event: CalendarSourceEvent, calendar: Calendar = .current) -> String? {
        guard let external = event.externalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !external.isEmpty else {
            return nil
        }
        guard event.isRecurring || event.isDetached else { return external }
        if event.isAllDay {
            let day = calendar.dateComponents([.year, .month, .day], from: event.occurrenceStartDate)
            return "\(external)\nday:\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
        }
        return "\(external)\nat:\(event.occurrenceEpoch)"
    }

    private static func digest(_ material: String) -> String {
        SHA256.hash(data: Data(material.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum EventMirrorKeyPolicy {
    static func makeMirrorKey(
        calendarIdentifier: String,
        eventIdentifier: String,
        occurrenceStartDate: Date,
        fingerprint: String
    ) -> String {
        let stableEventID = eventIdentifier.isEmpty ? fingerprint : eventIdentifier
        return "\(eventPrefix(calendarIdentifier: calendarIdentifier, eventIdentifier: stableEventID))\(epoch(occurrenceStartDate))"
    }

    static func makeMirrorKey(for event: CalendarSourceEvent) -> String {
        makeMirrorKey(
            calendarIdentifier: event.calendarIdentifier,
            eventIdentifier: event.eventIdentifier,
            occurrenceStartDate: event.occurrenceStartDate,
            fingerprint: fingerprint(for: event)
        )
    }

    /// The key every event gets: its own key, or the key it was first uploaded under
    /// when its occurrence date has since moved (`keptKeysForRescheduledEvents`).
    static func mirrorKey(for event: CalendarSourceEvent, keptKeys: [String: String]) -> String {
        let key = makeMirrorKey(for: event)
        return keptKeys[key] ?? key
    }

    /// The record name is an occurrence's identity: comments hang on it. It is derived
    /// from EventKit only the first time. Afterwards the local shadows (and own mirrors)
    /// are the name book: each remembers its record name and which occurrence it stands
    /// for now. Whatever moves the occurrence date would otherwise mint a new name (a new
    /// record for the partner, the comments left behind on the old one):
    ///
    /// - a one-off event moved to another time (its occurrence date is its start date);
    /// - a whole repeating series moved (every occurrence date shifts);
    /// - "all future events" moved, which EventKit turns into a new series with a new
    ///   event identifier for the later half.
    ///
    /// Returns `[key the event would get now: key it keeps]`, only for events whose name
    /// differs from the derived one. Three steps, each only for events whose derived key
    /// is not live already:
    ///
    /// 1. Name book: a live entry recorded for exactly this calendar, event and
    ///    occurrence date keeps its name.
    /// 2. Moved: within one event identifier, occurrences that appeared pair with the
    ///    entries that disappeared. A one-off pairs with its single entry at any distance;
    ///    a series pairs nearest to nearest, closer than the series' own spacing, so a
    ///    deleted occurrence is never mistaken for a moved one.
    /// 3. Split (`matchesMovedSeries` only): a series seen for the first time pairs the
    ///    same way with the disappeared entries of one other series in its calendar that
    ///    has the same title, location, notes and URL.
    ///
    /// A kept key is never one a current event derives for itself, and never shared, so
    /// keys stay unique. Anything ambiguous gets its own key, as before.
    ///
    /// `matchesMovedSeries` is off where only a slice of the calendar is known (the
    /// calendar tab's visible week): entries outside the slice would look disappeared.
    static func keptKeysForRescheduledEvents(
        _ events: [CalendarSourceEvent],
        existingShadows: [LocalEventShadow],
        existingMirrors: [EventMirror],
        matchesMovedSeries: Bool = true
    ) -> [String: String] {
        let derivedKeys = events.map { makeMirrorKey(for: $0) }
        let derivedKeySet = Set(derivedKeys)
        let entries = nameBook(existingShadows: existingShadows, existingMirrors: existingMirrors)
        var liveKeys = Set(existingShadows.filter { !$0.isTombstone }.map(\.id))
        liveKeys.formUnion(existingMirrors.filter { $0.deletedAt == nil }.map(\.mirrorKey))
        let currentOccurrences = Set(events.map { OccurrenceID(event: $0) })
        let eventIndexesBySeries = Dictionary(grouping: events.indices, by: { SeriesID(event: events[$0]) })

        // Entries a moved event may take: not the derived key of any current event.
        var freeEntries = entries.filter { !derivedKeySet.contains($0.key) }
        var kept: [String: String] = [:]
        var pending: [Int] = []

        // 1. Name book.
        let entriesByOccurrence = Dictionary(grouping: freeEntries, by: \.occurrence)
        var claimedKeys = Set<String>()
        for index in events.indices {
            let event = events[index]
            guard !event.eventIdentifier.isEmpty, !liveKeys.contains(derivedKeys[index]) else { continue }
            if let matches = entriesByOccurrence[OccurrenceID(event: event)] {
                if matches.count == 1 {
                    kept[derivedKeys[index]] = matches[0].key
                    claimedKeys.insert(matches[0].key)
                }
                continue
            }
            pending.append(index)
        }
        // What is left disappeared: no current event stands where the entry was recorded.
        freeEntries.removeAll { claimedKeys.contains($0.key) || currentOccurrences.contains($0.occurrence) }

        // 2. Moved within the same event identifier.
        let pendingBySeries = Dictionary(grouping: pending, by: { SeriesID(event: events[$0]) })
        var unmatched: [Int] = []
        for series in pendingBySeries.keys.sorted() {
            let indexes = pendingBySeries[series] ?? []
            let seriesIndexes = eventIndexesBySeries[series] ?? []
            let candidates = freeEntries.filter { $0.occurrence.series == series }
            let isSeries = seriesIndexes.count > 1 || seriesIndexes.contains { events[$0].isRecurring }
            guard isSeries else {
                if candidates.count == 1, let index = indexes.first {
                    kept[derivedKeys[index]] = candidates[0].key
                    claimedKeys.insert(candidates[0].key)
                }
                continue
            }
            guard matchesMovedSeries else { continue }
            let pairs = nearestPairs(
                indexes.map { events[$0] },
                candidates,
                closerThan: spacing(of: seriesIndexes.map { events[$0].occurrenceEpoch }, or: candidates.map(\.occurrence.epoch))
            )
            var matchedEpochs = Set<Int>()
            for (event, entry) in pairs {
                kept[makeMirrorKey(for: event)] = entry.key
                claimedKeys.insert(entry.key)
                matchedEpochs.insert(event.occurrenceEpoch)
            }
            unmatched.append(contentsOf: indexes.filter { !matchedEpochs.contains(events[$0].occurrenceEpoch) })
        }
        guard matchesMovedSeries, !unmatched.isEmpty else { return kept }
        freeEntries.removeAll { claimedKeys.contains($0.key) }

        // 3. Split: a series nothing in the name book knows yet.
        let knownSeries = Set(entries.map(\.occurrence.series))
        let unmatchedBySeries = Dictionary(grouping: unmatched, by: { SeriesID(event: events[$0]) })
        for series in unmatchedBySeries.keys.sorted() where !knownSeries.contains(series) {
            let seriesIndexes = eventIndexesBySeries[series] ?? []
            let indexesByContent = Dictionary(grouping: unmatchedBySeries[series] ?? [], by: { content(for: events[$0]) })
            for sharedContent in indexesByContent.keys.sorted() {
                let candidates = freeEntries.filter { entry in
                    entry.content == sharedContent
                        && entry.occurrence.series.calendarIdentifier == series.calendarIdentifier
                        && entry.occurrence.series != series
                }
                // Two old series with this content: no way to tell which one this continues.
                guard Set(candidates.map(\.occurrence.series)).count == 1 else { continue }
                let pairs = nearestPairs(
                    (indexesByContent[sharedContent] ?? []).map { events[$0] },
                    candidates,
                    closerThan: spacing(of: seriesIndexes.map { events[$0].occurrenceEpoch }, or: candidates.map(\.occurrence.epoch))
                )
                for (event, entry) in pairs {
                    kept[makeMirrorKey(for: event)] = entry.key
                    claimedKeys.insert(entry.key)
                }
                freeEntries.removeAll { claimedKeys.contains($0.key) }
            }
        }
        return kept
    }

    // MARK: Name book

    private struct SeriesID: Hashable, Comparable {
        let calendarIdentifier: String
        let eventIdentifier: String

        init(calendarIdentifier: String, eventIdentifier: String) {
            self.calendarIdentifier = calendarIdentifier
            self.eventIdentifier = eventIdentifier
        }

        init(event: CalendarSourceEvent) {
            self.init(calendarIdentifier: event.calendarIdentifier, eventIdentifier: event.eventIdentifier)
        }

        static func < (lhs: SeriesID, rhs: SeriesID) -> Bool {
            (lhs.calendarIdentifier, lhs.eventIdentifier) < (rhs.calendarIdentifier, rhs.eventIdentifier)
        }
    }

    private struct OccurrenceID: Hashable {
        let series: SeriesID
        let epoch: Int

        init(series: SeriesID, epoch: Int) {
            self.series = series
            self.epoch = epoch
        }

        init(event: CalendarSourceEvent) {
            self.init(series: SeriesID(event: event), epoch: event.occurrenceEpoch)
        }
    }

    /// One live record this device knows: its name, the occurrence it stands for now, and
    /// the content it was last uploaded with, when that is known.
    private struct NameBookEntry {
        let key: String
        let occurrence: OccurrenceID
        let content: String?
    }

    /// Live shadows first: they record the event identifier the occurrence has now. An own
    /// mirror without a shadow (the cloud copies on a reinstall's first sync) only has the
    /// identifier its key was first derived from.
    private static func nameBook(existingShadows: [LocalEventShadow], existingMirrors: [EventMirror]) -> [NameBookEntry] {
        var entryByKey: [String: NameBookEntry] = [:]
        for shadow in existingShadows where !shadow.isTombstone && !shadow.localEventIdentifier.isEmpty {
            entryByKey[shadow.id] = NameBookEntry(
                key: shadow.id,
                occurrence: OccurrenceID(
                    series: SeriesID(
                        calendarIdentifier: shadow.calendarIdentifier,
                        eventIdentifier: shadow.localEventIdentifier
                    ),
                    epoch: epoch(shadow.occurrenceStartDate)
                ),
                content: content(
                    ofFingerprint: shadow.fingerprint,
                    eventIdentifier: shadow.localEventIdentifier,
                    calendarIdentifier: shadow.calendarIdentifier
                )
            )
        }
        for mirror in existingMirrors where mirror.deletedAt == nil && entryByKey[mirror.mirrorKey] == nil {
            let key = mirror.mirrorKey
            let head = "\(mirror.sourceCalendarID):"
            guard key.hasPrefix(head),
                  let separator = key.lastIndex(of: ":"),
                  Int(key[key.index(after: separator)...]) != nil else { continue }
            let eventIdentifier = String(key.dropFirst(head.count).dropLast(key.distance(from: separator, to: key.endIndex)))
            guard !eventIdentifier.isEmpty else { continue }
            entryByKey[key] = NameBookEntry(
                key: key,
                occurrence: OccurrenceID(
                    series: SeriesID(calendarIdentifier: mirror.sourceCalendarID, eventIdentifier: eventIdentifier),
                    epoch: epoch(mirror.occurrenceStartDate)
                ),
                // Only a full-details copy still says what the event said.
                content: mirror.visibility == .fullDetails
                    ? [mirror.title, mirror.location ?? "", mirror.notes ?? "", mirror.urlString ?? ""].joined(separator: "|")
                    : nil
            )
        }
        return entryByKey.keys.sorted().compactMap { entryByKey[$0] }
    }

    /// The smallest gap between a series' occurrences: a move is recognised below it.
    /// With a single current occurrence, the gap of the disappeared ones; else a day.
    private static func spacing(of epochs: [Int], or fallbackEpochs: [Int]) -> Int {
        smallestGap(epochs) ?? smallestGap(fallbackEpochs) ?? 24 * 60 * 60
    }

    private static func smallestGap(_ epochs: [Int]) -> Int? {
        let sorted = Set(epochs).sorted()
        return zip(sorted.dropFirst(), sorted).map { $0 - $1 }.min()
    }

    /// Pairs each appeared occurrence with the disappeared entry nearest in time, when the
    /// entry's nearest occurrence is that one too and they are less than `limit` apart.
    private static func nearestPairs(
        _ events: [CalendarSourceEvent],
        _ entries: [NameBookEntry],
        closerThan limit: Int
    ) -> [(CalendarSourceEvent, NameBookEntry)] {
        let eventByEpoch = Dictionary(events.map { ($0.occurrenceEpoch, $0) }, uniquingKeysWith: { first, _ in first })
        // Two entries recorded at one date: no way to tell which is the occurrence's.
        let entryByEpoch = Dictionary(grouping: entries, by: \.occurrence.epoch)
            .compactMapValues { $0.count == 1 ? $0[0] : nil }
        let eventEpochs = eventByEpoch.keys.sorted()
        let entryEpochs = entryByEpoch.keys.sorted()
        var pairs: [(CalendarSourceEvent, NameBookEntry)] = []
        for eventEpoch in eventEpochs {
            guard let entryEpoch = nearest(to: eventEpoch, in: entryEpochs),
                  nearest(to: entryEpoch, in: eventEpochs) == eventEpoch,
                  abs(entryEpoch - eventEpoch) < limit,
                  let event = eventByEpoch[eventEpoch],
                  let entry = entryByEpoch[entryEpoch] else { continue }
            pairs.append((event, entry))
        }
        return pairs
    }

    /// The value of the sorted `values` closest to `target`; the earlier one on a tie.
    private static func nearest(to target: Int, in values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low + high) / 2
            if values[middle] < target { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return values[0] }
        if low == values.count { return values[values.count - 1] }
        return target - values[low - 1] <= values[low] - target ? values[low - 1] : values[low]
    }

    private static func epoch(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }

    private static func eventPrefix(calendarIdentifier: String, eventIdentifier: String) -> String {
        "\(calendarIdentifier):\(eventIdentifier):"
    }

    static func fingerprint(for event: CalendarSourceEvent) -> String {
        [
            event.eventIdentifier,
            event.calendarIdentifier,
            "\(Int(event.startDate.timeIntervalSince1970.rounded()))",
            "\(Int(event.endDate.timeIntervalSince1970.rounded()))",
            content(for: event)
        ].joined(separator: "|")
    }

    /// What the event says, apart from when and which event it is: the tail of its
    /// fingerprint.
    static func content(for event: CalendarSourceEvent) -> String {
        [
            event.title,
            event.location ?? "",
            event.notes ?? "",
            event.url?.absoluteString ?? ""
        ].joined(separator: "|")
    }

    /// The content part of a stored fingerprint (`content(for:)` of the event it was made
    /// from); nil when the fingerprint is not in that form.
    static func content(ofFingerprint fingerprint: String, eventIdentifier: String, calendarIdentifier: String) -> String? {
        let head = "\(eventIdentifier)|\(calendarIdentifier)|"
        guard fingerprint.hasPrefix(head) else { return nil }
        let parts = fingerprint.dropFirst(head.count).split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, Int(parts[0]) != nil, Int(parts[1]) != nil else { return nil }
        return String(parts[2])
    }
}
