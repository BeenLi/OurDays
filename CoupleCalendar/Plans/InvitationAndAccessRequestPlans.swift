import Foundation

struct PairingHistoryRequestRange: Equatable {
    let start: Date
    let end: Date
}

enum PairingDatePlan {
    static func normalizedPairingDate(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Whole calendar days elapsed since pairing (0 on the pairing day). Used
    /// for the "D+N" style of counting.
    static func dayCount(since pairingDate: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: pairingDate)
        let end = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    /// The ordinal day of the pairing: the pairing day itself is day 1, the
    /// next day is day 2. Used for the "配对第 N 天 / Day N paired" headline,
    /// where day 0 reads as "not yet together".
    static func ordinalDayNumber(since pairingDate: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        dayCount(since: pairingDate, now: now, calendar: calendar) + 1
    }

    static func defaultHistoryRequestRange(
        pairingDate: Date,
        calendar: Calendar = .current
    ) -> PairingHistoryRequestRange {
        let normalizedPairingDate = normalizedPairingDate(pairingDate, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: -1, to: normalizedPairingDate) ?? normalizedPairingDate
        let start = calendar.date(byAdding: .day, value: -30, to: normalizedPairingDate) ?? end
        return PairingHistoryRequestRange(start: start, end: end)
    }

    static func exclusiveEndDate(forDisplayedEndDate displayedEndDate: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: displayedEndDate)
        return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
    }

    static func displayedEndDate(forExclusiveEndDate exclusiveEndDate: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: exclusiveEndDate)
        return calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
    }
}

enum PrePairingHistoryAccessPlan {
    enum Direction {
        case partnerSharedToMe
        case meSharedToPartner
    }

    enum Validation: Equatable {
        case valid
        case invalidRange
        case alreadyAuthorized
        case overlapsAuthorized
        case overlapsExistingRequest
    }

    static func contiguousAuthorizedStartDate(
        pairingDate: Date,
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        direction: Direction,
        calendar: Calendar = .current
    ) -> Date {
        let normalizedPairingDate = PairingDatePlan.normalizedPairingDate(pairingDate, calendar: calendar)
        let intervals = approvedIntervals(
            accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            direction: direction,
            calendar: calendar
        )

        var authorizedStartDate = normalizedPairingDate
        var didExpand = true
        while didExpand {
            didExpand = false
            for interval in intervals where interval.start < authorizedStartDate && interval.end >= authorizedStartDate {
                authorizedStartDate = interval.start
                didExpand = true
            }
        }
        return authorizedStartDate
    }

    static func defaultNextRequestRange(
        pairingDate: Date,
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        calendar: Calendar = .current
    ) -> PairingHistoryRequestRange {
        let authorizedStartDate = contiguousAuthorizedStartDate(
            pairingDate: pairingDate,
            accessRequests: accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            direction: .partnerSharedToMe,
            calendar: calendar
        )
        let displayedEndDate = PairingDatePlan.displayedEndDate(
            forExclusiveEndDate: authorizedStartDate,
            calendar: calendar
        )
        let startDate = calendar.date(byAdding: .day, value: -30, to: authorizedStartDate) ?? displayedEndDate
        return PairingHistoryRequestRange(start: startDate, end: displayedEndDate)
    }

    static func validation(
        requestedStartDate: Date,
        requestedEndDate: Date,
        pairingDate: Date,
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        calendar: Calendar = .current
    ) -> Validation {
        let normalizedStartDate = calendar.startOfDay(for: requestedStartDate)
        let normalizedEndDate = calendar.startOfDay(for: requestedEndDate)
        guard normalizedEndDate > normalizedStartDate else { return .invalidRange }

        let approvedRanges = mergedIntervals(approvedIntervals(
            accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            direction: .partnerSharedToMe,
            calendar: calendar
        ))
        if approvedRanges.contains(where: { interval in
            interval.start <= normalizedStartDate && normalizedEndDate <= interval.end
        }) {
            return .alreadyAuthorized
        }
        if approvedRanges.contains(where: { overlaps($0, start: normalizedStartDate, end: normalizedEndDate) }) {
            return .overlapsAuthorized
        }

        let existingPendingRanges = pendingOutgoingIntervals(
            accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            calendar: calendar
        )
        if existingPendingRanges.contains(where: { overlaps($0, start: normalizedStartDate, end: normalizedEndDate) }) {
            return .overlapsExistingRequest
        }

        return .valid
    }

    private static func approvedIntervals(
        _ accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        direction: Direction,
        calendar: Calendar
    ) -> [DateInterval] {
        accessRequests.compactMap { request in
            guard request.status == .approved,
                  matches(request, currentMemberID: currentMemberID, ownerMemberID: ownerMemberID, direction: direction) else {
                return nil
            }
            return interval(for: request, calendar: calendar)
        }
    }

    private static func pendingOutgoingIntervals(
        _ accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        calendar: Calendar
    ) -> [DateInterval] {
        accessRequests.compactMap { request in
            guard request.status == .pending,
                  request.source != .privateOwnerZone,
                  MemberIDPlan.normalized(request.requesterMemberID) == MemberIDPlan.normalized(currentMemberID),
                  matchesOwner(request, ownerMemberID: ownerMemberID) else {
                return nil
            }
            return interval(for: request, calendar: calendar)
        }
    }

    private static func matches(
        _ request: CalendarAccessRequest,
        currentMemberID: String,
        ownerMemberID: String?,
        direction: Direction
    ) -> Bool {
        switch direction {
        case .partnerSharedToMe:
            return request.source != .privateOwnerZone
                && MemberIDPlan.normalized(request.requesterMemberID) == MemberIDPlan.normalized(currentMemberID)
                && matchesOwner(request, ownerMemberID: ownerMemberID)
        case .meSharedToPartner:
            return request.source == .privateOwnerZone
        }
    }

    private static func interval(for request: CalendarAccessRequest, calendar: Calendar) -> DateInterval? {
        let startDate = calendar.startOfDay(for: request.requestedStartDate)
        let endDate = calendar.startOfDay(for: request.requestedEndDate)
        guard endDate > startDate else { return nil }
        return DateInterval(start: startDate, end: endDate)
    }

    private static func matchesOwner(_ request: CalendarAccessRequest, ownerMemberID: String?) -> Bool {
        guard let ownerMemberID = MemberIDPlan.normalized(ownerMemberID) else { return true }
        return MemberIDPlan.normalized(request.ownerMemberID) == ownerMemberID
    }

    private static func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        intervals.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
        .reduce(into: []) { partialResult, interval in
            guard let last = partialResult.last else {
                partialResult.append(interval)
                return
            }
            if interval.start <= last.end {
                partialResult[partialResult.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                partialResult.append(interval)
            }
        }
    }

    private static func overlaps(_ interval: DateInterval, start: Date, end: Date) -> Bool {
        interval.start < end && start < interval.end
    }
}

enum CalendarAccessRequestListPlan {
    private struct LogicalRequestKey: Hashable {
        let requesterMemberID: String
        let ownerMemberID: String
        let requestedStartDate: Date
        let requestedEndDate: Date
    }

    private static func logicalKey(for request: CalendarAccessRequest) -> LogicalRequestKey {
        LogicalRequestKey(
            requesterMemberID: request.requesterMemberID.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerMemberID: request.ownerMemberID.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedStartDate: request.requestedStartDate,
            requestedEndDate: request.requestedEndDate
        )
    }

    private static func preferredRequest(in requests: [CalendarAccessRequest]) -> CalendarAccessRequest? {
        requests.max { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                if lhs.status == .pending && rhs.status != .pending {
                    return true
                }
                if lhs.status != .pending && rhs.status == .pending {
                    return false
                }
                return lhs.id < rhs.id
            }
            return lhs.updatedAt < rhs.updatedAt
        }
    }

    private static func collapsedRequests(_ requests: [CalendarAccessRequest]) -> [CalendarAccessRequest] {
        Dictionary(grouping: requests, by: logicalKey(for:))
            .values
            .compactMap(preferredRequest(in:))
    }

    static func pendingIncoming(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        collapsedRequests(
            requests.filter { request in
                request.source == .privateOwnerZone
            }
        )
            .filter { $0.status == .pending }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func outgoing(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        collapsedRequests(
            requests.filter { request in
                request.requesterMemberID == currentMemberID && request.source != .privateOwnerZone
            }
        )
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func pendingOutgoingRequestsNotSupersededByTerminalCopies(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        let outgoingRequests = requests.filter { request in
            request.requesterMemberID == currentMemberID && request.source != .privateOwnerZone
        }
        let requestsByKey = Dictionary(grouping: outgoingRequests, by: logicalKey(for:))
        return outgoingRequests
            .filter { request in
                guard request.status == .pending else { return false }
                // Only requests not yet confirmed on the server need (re)uploading.
                // Once a request round-trips back from the shared zone it is
                // `.acceptedSharedZone`; re-uploading it would clobber the owner's
                // status update (e.g. an approval) with our stale `pending` copy.
                guard request.source == .localOutgoing else { return false }
                let matchingRequests = requestsByKey[logicalKey(for: request)] ?? []
                return !matchingRequests.contains { matchingRequest in
                    matchingRequest.status != .pending
                        && matchingRequest.updatedAt >= request.updatedAt
                }
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.updatedAt < rhs.updatedAt
            }
    }
}

enum CalendarAccessRequestCloudUploadPlan {
    static func requestsNeedingUpload(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        CalendarAccessRequestListPlan.pendingOutgoingRequestsNotSupersededByTerminalCopies(
            requests,
            currentMemberID: currentMemberID
        )
    }
}

/// Merge guard for importing an access-request copy from CloudKit onto a local copy
/// with the same `id`. Fixes the "approval reverts / needs several taps" bug: the
/// owner's approval is saved locally and uploaded fire-and-forget, while a concurrent
/// sync re-reads the still-`pending` server copy and would overwrite the decision.
///
/// The rule is STATUS-AWARE, not purely timestamp-based, because `updatedAt` is stamped
/// with each device's own `.now` — cross-device clock skew (or CloudKit `Date`
/// truncation, or equal timestamps) makes raw timestamp ordering unreliable for
/// comparing the requester's `pending` copy against the owner's `approved` copy. Since
/// the owner is the SOLE authority on terminal status (the requester only ever sends
/// `pending` and never mutates it):
///   - a decision (terminal) always beats `pending`, regardless of timestamp — so
///     `pending` can never roll back an approval, and a decision always lands on the
///     requester even if the owner's clock is behind;
///   - same terminality (both terminal, or both pending) falls back to last-writer-wins,
///     which is reliable because those are comparisons within one device's own writes.
/// Core terminality-aware merge policy, shared by every CloudKit-imported record whose
/// status is mutated locally and uploaded asynchronously (access requests AND
/// invitations — both have the same stale-overwrite race). Generalized rather than
/// duplicated per type so a new status-bearing record can't silently miss the guard.
enum StatusMergePlan {
    static func shouldApplyIncoming(
        existingIsTerminal: Bool,
        existingUpdatedAt: Date,
        incomingIsTerminal: Bool,
        incomingUpdatedAt: Date
    ) -> Bool {
        if existingIsTerminal != incomingIsTerminal {
            // A decision always wins over pending, in either direction, ignoring clocks.
            return incomingIsTerminal
        }
        // Both terminal or both pending: last-writer-wins; equal applies (idempotent).
        return incomingUpdatedAt >= existingUpdatedAt
    }
}

enum CalendarAccessRequestImportMergePlan {
    static func shouldApplyIncoming(
        existingStatus: CalendarAccessRequestStatus,
        existingUpdatedAt: Date,
        incomingStatus: CalendarAccessRequestStatus,
        incomingUpdatedAt: Date
    ) -> Bool {
        StatusMergePlan.shouldApplyIncoming(
            existingIsTerminal: existingStatus != .pending,
            existingUpdatedAt: existingUpdatedAt,
            incomingIsTerminal: incomingStatus != .pending,
            incomingUpdatedAt: incomingUpdatedAt
        )
    }
}

/// Same race as access requests: the invitee sets `.accepted`/`.declined` locally and
/// uploads fire-and-forget, so a concurrent sync re-reading the still-`pending` server
/// copy would roll the decision back. `pending` is the only non-terminal invitation
/// status; accepted/declined/canceled are terminal.
enum InvitationImportMergePlan {
    static func shouldApplyIncoming(
        existingStatus: InvitationStatus,
        existingUpdatedAt: Date,
        incomingStatus: InvitationStatus,
        incomingUpdatedAt: Date
    ) -> Bool {
        StatusMergePlan.shouldApplyIncoming(
            existingIsTerminal: existingStatus != .pending,
            existingUpdatedAt: existingUpdatedAt,
            incomingIsTerminal: incomingStatus != .pending,
            incomingUpdatedAt: incomingUpdatedAt
        )
    }
}

/// Companion to the import merge guards: makes the upload of a local terminal decision
/// reliable. A tab action (owner approving a history-access request; invitee
/// accepting/declining an invitation) uploads fire-and-forget, so a failed/missed
/// one-shot upload would be PERMANENT now that the merge guard refuses to let the stale
/// server `pending` copy resurface it (the old rollback was perversely self-correcting).
/// After a sync imports the server's current copies, these plans return the local
/// terminal decisions the server hasn't caught up to, to be re-uploaded. Self-limiting:
/// once the server's copy matches, nothing is returned, so there is no per-sync churn.
enum CalendarAccessRequestReuploadPlan {
    static func ownerDecisionsNeedingReupload(
        local: [CalendarAccessRequest],
        cloud: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        let cloudStatusByID = Dictionary(
            cloud.map { ($0.id, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
        return local.filter { request in
            request.ownerMemberID == currentMemberID
                && request.source == .privateOwnerZone
                && request.status != .pending
                // Only when the server has recorded NO decision yet (still pending, or the
                // record never landed). Never re-push over a terminal cloud copy. The
                // owner is the sole terminal authority here, so a terminal cloud value is
                // always our own already-uploaded decision — nothing to re-push.
                && (cloudStatusByID[request.id] ?? .pending) == .pending
        }
    }
}

enum InvitationReuploadPlan {
    static func responsesNeedingReupload(
        local: [EventInvitation],
        cloud: [EventInvitation],
        currentMemberID: String
    ) -> [EventInvitation] {
        let cloudStatusByID = Dictionary(
            cloud.map { ($0.id, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
        return local.filter { invitation in
            // The invitee is "anyone who is not the creator": the stamped
            // `inviteeMemberID` is the partner's hashed CloudKit ID and never equals the
            // recipient's own member ID, so identity must key off the creator (see
            // InvitationInteractionPlan.canRespond).
            //
            // Re-push my accept/decline ONLY while the creator's zone copy is still
            // `pending` (my upload never landed). If it already holds a terminal value
            // we must NOT overwrite it — that could be the creator's own `canceled`
            // (both parties set terminal status here); genuine terminal-vs-terminal
            // conflicts are resolved by the import merge (last-writer-wins), not by
            // re-pushing. A missing record means the creator deleted it — don't resurrect.
            invitation.creatorMemberID != currentMemberID
                && invitation.status != .pending
                && cloudStatusByID[invitation.id] == .pending
        }
    }

    /// Companion for the CREATE side (req2 optimistic send). The creator's own
    /// invitation lives in their PRIVATE zone, which `foregroundSync` never reads back,
    /// so we can't diff against fetched cloud copies the way `responsesNeedingReupload`
    /// does. Instead the local `needsCloudKitUpload` flag tracks "upload still owed":
    /// set on optimistic create, cleared once the background upload succeeds. This
    /// returns my creations still owing an upload so a later sync can re-push them.
    /// Self-limiting: once the flag is cleared, nothing is returned.
    static func creationsNeedingReupload(
        local: [EventInvitation],
        currentMemberID: String
    ) -> [EventInvitation] {
        local.filter { invitation in
            invitation.creatorMemberID == currentMemberID && invitation.needsCloudKitUpload
        }
    }
}

/// Keeps an invitation's end time trailing its start time by the previously
/// chosen duration (at least one hour), matching the system calendar editor so
/// moving Start no longer leaves End behind.
enum InviteTimeAdjustmentPlan {
    static let minimumDuration: TimeInterval = 60 * 60

    static func endDate(
        forNewStart newStart: Date,
        previousStart: Date,
        previousEnd: Date
    ) -> Date {
        let duration = max(minimumDuration, previousEnd.timeIntervalSince(previousStart))
        return newStart.addingTimeInterval(duration)
    }
}

enum InvitationInteractionPlan {
    static func canRespond(to invitation: EventInvitation, currentMemberID: String) -> Bool {
        // In a two-person space, anyone who is not the creator is the invitee.
        // The stored `inviteeMemberID` is the partner's hashed CloudKit ID (stamped
        // by the creator), which never equals the recipient's local owner ID, so we
        // identify the invitee by "not the creator" instead.
        invitation.status == .pending && invitation.creatorMemberID != currentMemberID
    }
}

enum InvitationLocalEventSyncPlan {

    static func cancelAcceptedInvitationsMissingLocalEvents(
        _ invitations: [EventInvitation],
        existingLocalEventIDs: Set<String>,
        now: Date
    ) -> [EventInvitation] {
        let trackableInvitations = invitations.filter { invitation in
            guard let localEventID = invitation.createdLocalEventID else { return false }
            return !localEventID.isEmpty
        }
        return cancelAcceptedInvitationsMissingLocalEvents(trackableInvitations, now: now) { invitation in
            guard let localEventID = invitation.createdLocalEventID,
                  !localEventID.isEmpty else {
                return false
            }
            return existingLocalEventIDs.contains(localEventID)
        }
    }

    static func cancelAcceptedInvitationsMissingLocalEvents(
        _ invitations: [EventInvitation],
        now: Date,
        localEventExists: (EventInvitation) -> Bool
    ) -> [EventInvitation] {
        let missing = invitations.filter { invitation in
            guard invitation.status == .accepted else {
                return false
            }
            return !localEventExists(invitation)
        }

        for invitation in missing {
            invitation.statusRawValue = InvitationStatus.canceled.rawValue
            invitation.updatedAt = now
        }

        return missing
    }
}

enum InvitationListPlan {
    static func visibleInvitations(_ invitations: [EventInvitation]) -> [EventInvitation] {
        invitations.filter { $0.archivedAt == nil }
    }

    /// Orders invitations so the schedule nearest to now (the most recent start date)
    /// sits at the top, instead of the oldest invitation leading the list.
    static func sortedForDisplay(_ invitations: [EventInvitation]) -> [EventInvitation] {
        invitations.sorted { $0.startDate > $1.startDate }
    }

    static func canOpenInCalendar(_ invitation: EventInvitation) -> Bool {
        invitation.status == .accepted
    }

    static func canDelete(_ invitation: EventInvitation) -> Bool {
        invitation.archivedAt == nil
    }
}

struct CreateInviteDraft: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

enum CreateInviteValidationError: LocalizedError, Equatable {
    case emptyTitle
    case invalidDateRange

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Invite title is required."
        case .invalidDateRange:
            return "Invite end time must be after the start time."
        }
    }
}

enum CreateInvitePlan {
    static func localCalendarDraft(from draft: CreateInviteDraft) throws -> LocalCalendarEventDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CreateInviteValidationError.emptyTitle }
        guard draft.endDate > draft.startDate else { throw CreateInviteValidationError.invalidDateRange }

        return LocalCalendarEventDraft(
            title: title,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            location: cleanOptional(draft.location),
            notes: cleanOptional(draft.notes)
        )
    }

    static func invitation(
        from draft: CreateInviteDraft,
        creatorMemberID: String,
        inviteeMemberID: String
    ) throws -> EventInvitation {
        let localDraft = try localCalendarDraft(from: draft)
        return EventInvitation(
            creatorMemberID: creatorMemberID,
            inviteeMemberID: inviteeMemberID,
            title: localDraft.title,
            startDate: localDraft.startDate,
            endDate: localDraft.endDate,
            isAllDay: localDraft.isAllDay,
            location: localDraft.location,
            notes: localDraft.notes,
            statusRawValue: InvitationStatus.pending.rawValue
        )
    }

    static func mirror(
        from draft: CreateInviteDraft,
        createdEvent: CreatedCalendarEvent,
        ownerMemberID: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> EventMirror {
        let localDraft = try localCalendarDraft(from: draft)
        let fingerprint = [
            createdEvent.eventIdentifier,
            "\(Int(localDraft.startDate.timeIntervalSince1970.rounded()))",
            "\(Int(localDraft.endDate.timeIntervalSince1970.rounded()))",
            localDraft.title
        ].joined(separator: "|")
        let mirrorKey = EventMirrorKeyPlan.makeMirrorKey(
            calendarIdentifier: createdEvent.calendarIdentifier,
            eventIdentifier: createdEvent.eventIdentifier,
            occurrenceStartDate: localDraft.startDate,
            fingerprint: fingerprint
        )

        return EventMirror(
            id: mirrorKey,
            ownerMemberID: ownerMemberID,
            mirrorKey: mirrorKey,
            sourceCalendarID: createdEvent.calendarIdentifier,
            sourceCalendarTitle: createdEvent.calendarTitle,
            occurrenceStartDate: localDraft.startDate,
            startDate: localDraft.startDate,
            endDate: localDraft.endDate,
            isAllDay: localDraft.isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            title: localDraft.title,
            location: localDraft.location,
            notes: localDraft.notes,
            urlString: nil,
            calendarColorHex: createdEvent.calendarColorHex,
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: mirrorKey
        )
    }

    static func conflictCandidateMirror(
        from draft: CreateInviteDraft,
        ownerMemberID: String
    ) throws -> EventMirror {
        let createdEvent = CreatedCalendarEvent(
            eventIdentifier: "new-invite-candidate",
            calendarIdentifier: ShareCalCalendarBootstrapPlan.calendarTitle,
            calendarTitle: ShareCalCalendarBootstrapPlan.calendarTitle,
            calendarColorHex: ShareCalCalendarBootstrapPlan.calendarColorHex
        )
        return try mirror(from: draft, createdEvent: createdEvent, ownerMemberID: ownerMemberID)
    }

    private static func cleanOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum InvitationConflictPlan {
    static func conflicts(
        for event: EventMirror,
        partnerMemberID: String,
        mirrors: [EventMirror]
    ) -> [EventMirror] {
        mirrors
            .filter { mirror in
                mirror.deletedAt == nil
                    && mirror.id != event.id
                    && mirror.ownerMemberID == partnerMemberID
                    && overlaps(
                        startA: event.startDate,
                        endA: event.endDate,
                        startB: mirror.startDate,
                        endB: mirror.endDate
                    )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func overlaps(startA: Date, endA: Date, startB: Date, endB: Date) -> Bool {
        startA < endB && startB < endA
    }
}

enum AcceptedInvitationMirrorPlan {
    static func mirror(
        from invitation: EventInvitation,
        createdEvent: CreatedCalendarEvent,
        ownerMemberID: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> EventMirror {
        let fingerprint = [
            invitation.id,
            createdEvent.eventIdentifier,
            "\(Int(invitation.startDate.timeIntervalSince1970.rounded()))",
            "\(Int(invitation.endDate.timeIntervalSince1970.rounded()))",
            invitation.title
        ].joined(separator: "|")
        let mirrorKey = EventMirrorKeyPlan.makeMirrorKey(
            calendarIdentifier: createdEvent.calendarIdentifier,
            eventIdentifier: createdEvent.eventIdentifier,
            occurrenceStartDate: invitation.startDate,
            fingerprint: fingerprint
        )

        return EventMirror(
            id: mirrorKey,
            ownerMemberID: ownerMemberID,
            mirrorKey: mirrorKey,
            sourceCalendarID: createdEvent.calendarIdentifier,
            sourceCalendarTitle: createdEvent.calendarTitle,
            occurrenceStartDate: invitation.startDate,
            startDate: invitation.startDate,
            endDate: invitation.endDate,
            isAllDay: invitation.isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            title: invitation.title,
            location: invitation.location,
            notes: invitation.notes,
            urlString: nil,
            calendarColorHex: createdEvent.calendarColorHex,
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: mirrorKey
        )
    }
}
