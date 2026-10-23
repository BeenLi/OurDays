import Foundation

enum ShareCalLaunchDiagnosticPlan {
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
    /// via `EventDetailCommentPlan`, synced or not — so this exercises "I start the
    /// thread on my own event"; on the partner it resolves the imported mirror and writes
    /// into the owner's shared zone (the reply).
    static let addEventCommentArgument = "-ShareCalAddEventComment"
    static let eventCommentTitleArgument = "-ShareCalEventCommentTitle"
    /// Either side: sync, then log the comment thread of the event titled by
    /// `-ShareCalEventCommentTitle` as `eventComments title=… count=N bodies=[…]`.
    static let probeEventCommentsArgument = "-ShareCalProbeEventComments"
    /// Reinstall smoke: delete the ShareCal events with this title from the system calendar
    /// WITHOUT syncing (the automatic launch sync is throttled right after a sync), so the
    /// next install has to discover the deletion from its own cloud mirrors.
    static let deleteCalendarEventTitledArgument = "-ShareCalDeleteCalendarEventTitled"
    /// Reinstall smoke: on a fresh install, run the 「继续使用现有 iCloud 数据」 path
    /// (restore identity from the private zone + forced sync) and log what came back.
    static let recoverExistingICloudDataArgument = "-ShareCalRecoverExistingICloudData"
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

    static func eventCommentTitle(arguments: [String]) -> String {
        value(after: eventCommentTitleArgument, arguments: arguments) ?? ShareCalSmokeTestEventPlan.title
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
        let title = seedCalendarEventTitle(arguments: arguments) ?? ShareCalSmokeTestEventPlan.title
        guard let startDate = dateValue(after: seedCalendarEventStartDateArgument, arguments: arguments),
              let endDate = dateValue(after: seedCalendarEventEndDateArgument, arguments: arguments),
              endDate > startDate else {
            return ShareCalSmokeTestEventPlan.draft(now: now, title: title)
        }

        return LocalCalendarEventDraft(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: nil,
            notes: ShareCalSmokeTestEventPlan.notes
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
