import Foundation

enum ShareCalLaunchDiagnosticPolicy {
    static let cloudKitWriteProbeArgument = "-ShareCalCloudKitWriteProbe"
    static let seedCalendarEventArgument = "-ShareCalSeedCalendarEvent"
    static let seedCalendarEventTitleArgument = "-ShareCalSeedCalendarEventTitle"
    static let seedCalendarEventStartDateArgument = "-ShareCalSeedCalendarEventStart"
    static let seedCalendarEventEndDateArgument = "-ShareCalSeedCalendarEventEnd"
    static let stopSharingProbeArgument = "-ShareCalStopICloudSharing"
    static let sharedReadProbeArgument = "-ShareCalSharedReadProbe"
    static let preparePairingShareArgument = "-ShareCalPreparePairingShare"
    static let acceptShareURLArgument = "-ShareCalAcceptShareURL"
    static let forceSyncArgument = "-ShareCalForceSync"
    /// Test-harness only: seed a display name + mark onboarding/recovery prompts resolved
    /// in the app's own UserDefaults at launch, so automation isn't blocked by the
    /// first-run profile sheet. Inert without the argument (normal launches ignore it).
    static let seedProfileNameArgument = "-ShareCalSeedProfileName"
    static let cloudKitWriteProbeRecordType = "CoupleSpace"
    /// Marker for scripts that grep the unified log for the share invitation URL.
    static let pairingShareURLLogPrefix = "ShareCalPairingShareURL:"

    // Joint-event / comment smoke diagnostics (drive an invitation → accept → joint
    // event → cross-device comment thread). All log a `ShareCalDiag ...` marker the
    // smoke script greps. Inert without their argument.
    static let seedInvitationArgument = "-ShareCalSeedInvitation"
    static let seedInvitationTitleArgument = "-ShareCalSeedInvitationTitle"
    static let acceptInvitationArgument = "-ShareCalAcceptInvitation"
    /// Creator side: withdraw the pending invitation with the given id (`<arg> <id>`).
    static let withdrawInvitationArgument = "-ShareCalWithdrawInvitation"
    /// Either side: sync, then log every invitation as `<id>:<status>` for the smoke
    /// script to assert on (e.g. that a withdrawn invitation reads `canceled`).
    static let probeInvitationsArgument = "-ShareCalProbeInvitations"
    static let addJointCommentArgument = "-ShareCalAddJointComment"
    static let probeJointCommentsArgument = "-ShareCalProbeJointComments"
    /// V1b visual check: seed a partner-authored comment on a fresh ORDINARY (non-joint) event
    /// of my own, so a single simulator can show the red dot on my event + the comment thread in
    /// its `EventDetailView` (the path that joint events bypass). Inert without the argument.
    static let seedOrdinaryCommentArgument = "-ShareCalSeedOrdinaryComment"
    /// Either side: add a comment (`<arg> <body>`) on the event titled by
    /// `-ShareCalEventCommentTitle` (default: the smoke event). On the event's owner the
    /// event is resolved the way the calendar opens it — as a transient display mirror
    /// via `EventDetailCommentPolicy`, synced or not — so this exercises "I start the
    /// thread on my own event"; on the partner it resolves the imported mirror and writes
    /// into the owner's shared zone (the reply).
    static let addEventCommentArgument = "-ShareCalAddEventComment"
    static let eventCommentTitleArgument = "-ShareCalEventCommentTitle"
    /// Either side: sync, then log the comment thread of the event titled by
    /// `-ShareCalEventCommentTitle` as `eventComments title=… count=N bodies=[…]`.
    static let probeEventCommentsArgument = "-ShareCalProbeEventComments"
    /// Either side: delete my comment with this body on the event titled by
    /// `-ShareCalEventCommentTitle`, the way the swipe does (author check, soft delete,
    /// upload to the comment's zone), then sync.
    static let deleteEventCommentArgument = "-ShareCalDeleteEventComment"
    /// Either side: edit my comment with this body on the event titled by
    /// `-ShareCalEventCommentTitle` to the body after `-ShareCalEditEventCommentBody`, the
    /// way the composer does (author check, `editedAt`, upload to the comment's zone),
    /// then sync.
    static let editEventCommentArgument = "-ShareCalEditEventComment"
    static let editEventCommentBodyArgument = "-ShareCalEditEventCommentBody"
    /// Reinstall smoke: delete the ShareCal events with this title from the system calendar
    /// WITHOUT syncing (the automatic launch sync is throttled right after a sync), so the
    /// next install has to discover the deletion from its own cloud mirrors.
    static let deleteCalendarEventTitledArgument = "-ShareCalDeleteCalendarEventTitled"
    /// Reschedule smoke: move the ShareCal events with this title one hour later WITHOUT
    /// syncing, so the next sync has to update the already-uploaded record in place.
    static let moveCalendarEventTitledArgument = "-ShareCalMoveCalendarEventTitled"
    /// Series smoke: create a five-day daily series with this title in the ShareCal
    /// calendar (replacing one from an earlier run), WITHOUT syncing.
    static let seedDailySeriesTitledArgument = "-ShareCalSeedDailySeriesTitled"
    /// Series smoke: move the series with this title one hour later from its
    /// `-ShareCalMoveSeriesFromOccurrence`-th occurrence on (0 = the whole series; default
    /// 2, which EventKit splits into a new series), WITHOUT syncing. Logs the event
    /// identifiers before and after.
    static let moveSeriesTitledArgument = "-ShareCalMoveSeriesTitled"
    static let moveSeriesFromOccurrenceArgument = "-ShareCalMoveSeriesFromOccurrence"
    /// Series smoke: remove the series with this title, WITHOUT syncing.
    static let deleteSeriesTitledArgument = "-ShareCalDeleteSeriesTitled"
    /// With `-ShareCalAddEventComment` / `-ShareCalProbeEventComments`: which of the
    /// events with the title is meant, counted from 0 in start order. Without it, the
    /// first one found.
    static let eventCommentOccurrenceArgument = "-ShareCalEventCommentOccurrence"
    /// Reinstall smoke: on a fresh install, run the 「继续使用现有 iCloud 数据」 path
    /// (restore identity from the private zone + forced sync) and log what came back.
    static let recoverExistingICloudDataArgument = "-ShareCalRecoverExistingICloudData"
    /// Smoke setup: the two test accounts are reused by every run, so comments,
    /// invitations and half-finished test events pile up. This deletes every comment and
    /// invitation record from MY private zone and the leftover smoke events from the
    /// ShareCal calendar. DEBUG builds only; run it on both simulators before pairing.
    static let purgeSmokeTestDataArgument = "-ShareCalPurgeSmokeTestData"
    /// Smoke only: deletes every already-deleted event (tombstone) record from MY private
    /// zone right now, without waiting out the 30 days. It is the one way the script can
    /// make the server report real record deletions, which the partner's incremental
    /// read must apply without losing anything else. DEBUG builds only.
    static let hardDeleteOwnTombstonesArgument = "-ShareCalHardDeleteOwnTombstones"
    /// Titles the smoke script gives its throwaway events (`<prefix><random number>`). A
    /// run that fails halfway never reaches its own cleanup, so the purge removes them.
    static let leftoverSmokeEventTitlePrefixes = ["Own Comment Event ", "Series Comment Event "]
    /// Common prefix for the new diagnostics' log markers.
    static let diagnosticLogPrefix = "ShareCalDiag"

    static func shouldRunCloudKitWriteProbe(arguments: [String]) -> Bool {
        arguments.contains(cloudKitWriteProbeArgument)
    }

    static func shouldSeedCalendarEvent(arguments: [String]) -> Bool {
        arguments.contains(seedCalendarEventArgument)
    }

    static func shouldRunStopSharingProbe(arguments: [String]) -> Bool {
        arguments.contains(stopSharingProbeArgument)
    }

    static func shouldRunSharedReadProbe(arguments: [String]) -> Bool {
        arguments.contains(sharedReadProbeArgument)
    }

    static func shouldPreparePairingShare(arguments: [String]) -> Bool {
        arguments.contains(preparePairingShareArgument)
    }

    static func shouldForceSync(arguments: [String]) -> Bool {
        arguments.contains(forceSyncArgument)
    }

    static func shouldSeedInvitation(arguments: [String]) -> Bool {
        arguments.contains(seedInvitationArgument)
    }

    static func seedInvitationTitle(arguments: [String]) -> String? {
        value(after: seedInvitationTitleArgument, arguments: arguments)
    }

    static func shouldAcceptInvitation(arguments: [String]) -> Bool {
        arguments.contains(acceptInvitationArgument)
    }

    static func withdrawInvitationID(arguments: [String]) -> String? {
        value(after: withdrawInvitationArgument, arguments: arguments)
    }

    static func shouldProbeInvitations(arguments: [String]) -> Bool {
        arguments.contains(probeInvitationsArgument)
    }

    static func jointCommentBody(arguments: [String]) -> String? {
        value(after: addJointCommentArgument, arguments: arguments)
    }

    static func ordinaryCommentBody(arguments: [String]) -> String? {
        value(after: seedOrdinaryCommentArgument, arguments: arguments)
    }

    static func eventCommentBody(arguments: [String]) -> String? {
        value(after: addEventCommentArgument, arguments: arguments)
    }

    static func deleteEventCommentBody(arguments: [String]) -> String? {
        value(after: deleteEventCommentArgument, arguments: arguments)
    }

    /// The (old, new) bodies of an edit; nil unless both are given.
    static func editEventComment(arguments: [String]) -> (from: String, to: String)? {
        guard let from = value(after: editEventCommentArgument, arguments: arguments),
              let to = value(after: editEventCommentBodyArgument, arguments: arguments)
        else { return nil }
        return (from, to)
    }

    static func eventCommentTitle(arguments: [String]) -> String {
        value(after: eventCommentTitleArgument, arguments: arguments) ?? ShareCalSmokeTestEventPolicy.title
    }

    static func shouldProbeEventComments(arguments: [String]) -> Bool {
        arguments.contains(probeEventCommentsArgument)
    }

    static func shouldProbeJointComments(arguments: [String]) -> Bool {
        arguments.contains(probeJointCommentsArgument)
    }

    static func deleteCalendarEventTitle(arguments: [String]) -> String? {
        value(after: deleteCalendarEventTitledArgument, arguments: arguments)
    }

    static func moveCalendarEventTitle(arguments: [String]) -> String? {
        value(after: moveCalendarEventTitledArgument, arguments: arguments)
    }

    static func seedDailySeriesTitle(arguments: [String]) -> String? {
        value(after: seedDailySeriesTitledArgument, arguments: arguments)
    }

    static func moveSeriesTitle(arguments: [String]) -> String? {
        value(after: moveSeriesTitledArgument, arguments: arguments)
    }

    static func moveSeriesFromOccurrence(arguments: [String]) -> Int {
        max(value(after: moveSeriesFromOccurrenceArgument, arguments: arguments).flatMap { Int($0) } ?? 2, 0)
    }

    static func deleteSeriesTitle(arguments: [String]) -> String? {
        value(after: deleteSeriesTitledArgument, arguments: arguments)
    }

    static func eventCommentOccurrence(arguments: [String]) -> Int? {
        value(after: eventCommentOccurrenceArgument, arguments: arguments).flatMap { Int($0) }.map { max($0, 0) }
    }

    static func shouldPurgeSmokeTestData(arguments: [String]) -> Bool {
        arguments.contains(purgeSmokeTestDataArgument)
    }

    static func shouldHardDeleteOwnTombstones(arguments: [String]) -> Bool {
        arguments.contains(hardDeleteOwnTombstonesArgument)
    }

    /// Only the script's numbered throwaway titles: the shared smoke event and anything a
    /// person typed into the ShareCal calendar stay.
    static func isLeftoverSmokeEvent(title: String?) -> Bool {
        guard let title else { return false }
        return leftoverSmokeEventTitlePrefixes.contains { prefix in
            guard title.hasPrefix(prefix) else { return false }
            let suffix = title.dropFirst(prefix.count)
            return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
        }
    }

    static func shouldRecoverExistingICloudData(arguments: [String]) -> Bool {
        arguments.contains(recoverExistingICloudDataArgument)
    }

    static func seedProfileName(arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        value(after: seedProfileNameArgument, arguments: arguments)
    }

    static func acceptShareURL(arguments: [String]) -> URL? {
        guard let urlString = value(after: acceptShareURLArgument, arguments: arguments) else {
            return nil
        }
        return URL(string: urlString)
    }

    static func seedCalendarEventTitle(arguments: [String]) -> String? {
        value(after: seedCalendarEventTitleArgument, arguments: arguments)
    }

    static func seedCalendarEventDraft(arguments: [String], now: Date = .now) -> LocalCalendarEventDraft {
        let title = seedCalendarEventTitle(arguments: arguments) ?? ShareCalSmokeTestEventPolicy.title
        guard let startDate = dateValue(after: seedCalendarEventStartDateArgument, arguments: arguments),
              let endDate = dateValue(after: seedCalendarEventEndDateArgument, arguments: arguments),
              endDate > startDate else {
            return ShareCalSmokeTestEventPolicy.draft(now: now, title: title)
        }

        return LocalCalendarEventDraft(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: nil,
            notes: ShareCalSmokeTestEventPolicy.notes
        )
    }

    private static func dateValue(after argument: String, arguments: [String]) -> Date? {
        guard let rawValue = value(after: argument, arguments: arguments) else { return nil }
        return ISO8601DateFormatter().date(from: rawValue)
    }

    private static func value(after argument: String, arguments: [String]) -> String? {
        guard let argumentIndex = arguments.firstIndex(of: argument) else {
            return nil
        }

        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        let rawValue = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return rawValue.isEmpty ? nil : rawValue
    }
}
