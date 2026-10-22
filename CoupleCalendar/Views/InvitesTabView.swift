import CloudKit
import SwiftData
import SwiftUI

struct InvitesTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventInvitation.startDate) private var invitations: [EventInvitation]
    @Query(sort: \CalendarAccessRequest.createdAt) private var accessRequests: [CalendarAccessRequest]
    @State private var errorMessage: String?
    let openInCalendar: (EventInvitation) -> Void

    private var pendingIncomingAccessRequests: [CalendarAccessRequest] {
        CalendarAccessRequestListPlan.pendingIncoming(
            accessRequests,
            currentMemberID: settings.currentMemberID
        )
    }

    var body: some View {
        let strings = settings.strings
        let visibleInvitations = InvitationListPlan.visibleInvitations(invitations)
        let pendingInvitations = InvitationListPlan.sortedForDisplay(
            visibleInvitations.filter { $0.status == .pending }
        )
        let handledInvitations = InvitationListPlan.sortedForDisplay(
            visibleInvitations.filter { $0.status != .pending }
        )
        let answerableCount = pendingInvitations.filter {
            InvitationInteractionPlan.canRespond(to: $0, currentMemberID: settings.currentMemberID)
        }.count

        List {
            OurDaysPageHeader(
                title: strings.invitesTab,
                subtitle: answerableCount > 0 ? strings.pendingInvitationsSubtitle(answerableCount) : nil
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            if !pendingIncomingAccessRequests.isEmpty {
                Section {
                    ForEach(pendingIncomingAccessRequests) { request in
                        HistoryRequestRow(
                            request: request,
                            requesterDisplayName: displayName(forRequesterMemberID: request.requesterMemberID),
                            rangeText: accessRequestRangeText(for: request)
                        ) {
                            update(request, status: .approved)
                        } decline: {
                            update(request, status: .declined)
                        }
                        .invitesRowStyle()
                    }
                } header: {
                    OurDaysSectionLabel(title: strings.pendingAccessRequestsLabel).textCase(nil)
                }
            }

            if !pendingInvitations.isEmpty {
                Section {
                    ForEach(pendingInvitations) { invitation in
                        InvitationTicket(invitation: invitation, currentMemberID: settings.currentMemberID) {
                            accept(invitation)
                        } decline: {
                            decline(invitation)
                        }
                        .invitesRowStyle()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if InvitationListPlan.canDelete(invitation) {
                                Button(role: .destructive) {
                                    archive(invitation)
                                } label: {
                                    Label(strings.deleteButton, systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    OurDaysSectionLabel(title: strings.invitationStatusTitle(for: .pending)).textCase(nil)
                }
            }

            if !handledInvitations.isEmpty {
                Section {
                    ForEach(handledInvitations) { invitation in
                        InvitationRow(invitation: invitation, currentMemberID: settings.currentMemberID) {
                            accept(invitation)
                        } decline: {
                            decline(invitation)
                        } openInCalendar: {
                            openInCalendar(invitation)
                        }
                        .invitesRowStyle(vertical: 3)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if InvitationListPlan.canDelete(invitation) {
                                Button(role: .destructive) {
                                    archive(invitation)
                                } label: {
                                    Label(strings.deleteButton, systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    OurDaysSectionLabel(title: strings.handledInvitationsSection).textCase(nil)
                }
            }

            if visibleInvitations.isEmpty && pendingIncomingAccessRequests.isEmpty {
                ContentUnavailableView(strings.noInvitations, systemImage: "envelope.open")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(OurDaysTheme.destructive)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .ourDaysListBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await performSync()
        }
    }

    private func performSync() async {
        // foregroundSync sets syncPhase = .syncing synchronously on entry, and
        // everything here runs on the main actor, so this single guard already
        // prevents overlapping/reentrant syncs from this screen.
        guard settings.syncPhase != .syncing else { return }
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
    }

    private func accept(_ invitation: EventInvitation) {
        do {
            let draft = services.invitationService.draft(from: invitation)
            let createdEvent = try services.calendarAccess.createShareCalEvent(from: draft)
            _ = try services.invitationService.accept(invitation, createdLocalEventID: createdEvent.eventIdentifier)
            let mirror = AcceptedInvitationMirrorPlan.mirror(
                from: invitation,
                createdEvent: createdEvent,
                ownerMemberID: settings.currentMemberID
            )
            try upsertAcceptedMirror(mirror)
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
                afterEnsuring: CalendarDescriptor(
                    id: createdEvent.calendarIdentifier,
                    title: createdEvent.calendarTitle,
                    colorHex: createdEvent.calendarColorHex,
                    allowsContentModifications: true
                ),
                currentSelection: settings.selectedCalendarIDs
            )
            try modelContext.save()
            saveInvitationStatusToCloudKit(invitation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsertAcceptedMirror(_ mirror: EventMirror) throws {
        let mirrorKey = mirror.mirrorKey
        let descriptor = FetchDescriptor<EventMirror>(
            predicate: #Predicate { $0.mirrorKey == mirrorKey }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.ownerMemberID = mirror.ownerMemberID
            existing.sourceCalendarID = mirror.sourceCalendarID
            existing.sourceCalendarTitle = mirror.sourceCalendarTitle
            existing.occurrenceStartDate = mirror.occurrenceStartDate
            existing.startDate = mirror.startDate
            existing.endDate = mirror.endDate
            existing.isAllDay = mirror.isAllDay
            existing.timeZoneIdentifier = mirror.timeZoneIdentifier
            existing.title = mirror.title
            existing.location = mirror.location
            existing.notes = mirror.notes
            existing.urlString = mirror.urlString
            existing.calendarColorHex = mirror.calendarColorHex
            existing.visibilityRawValue = mirror.visibilityRawValue
            existing.deletedAt = mirror.deletedAt
            existing.cloudKitRecordName = mirror.cloudKitRecordName
        } else {
            modelContext.insert(mirror)
        }
    }

    private func decline(_ invitation: EventInvitation) {
        services.invitationService.decline(invitation)
        do {
            try modelContext.save()
            saveInvitationStatusToCloudKit(invitation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive(_ invitation: EventInvitation) {
        invitation.archivedAt = .now
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveInvitationStatusToCloudKit(_ invitation: EventInvitation) {
        guard let cloudKit = services.cloudKitIfAvailable else { return }
        Task {
            do {
                try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
            } catch {
                errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            }
        }
    }

    private func update(_ request: CalendarAccessRequest, status: CalendarAccessRequestStatus) {
        request.status = status
        do {
            try modelContext.save()
            saveAccessRequestToCloudKit(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAccessRequestToCloudKit(_ request: CalendarAccessRequest) {
        guard let cloudKit = services.cloudKitIfAvailable else { return }
        Task {
            do {
                try await cloudKit.saveCalendarAccessRequestForSync(
                    request,
                    currentMemberID: settings.currentMemberID
                )
            } catch {
                errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
            }
        }
    }

    private func accessRequestRangeText(for request: CalendarAccessRequest) -> String {
        let start = settings.strings.abbreviatedDateText(request.requestedStartDate)
        let displayedEndDate = PairingDatePlan.displayedEndDate(forExclusiveEndDate: request.requestedEndDate)
        let end = settings.strings.abbreviatedDateText(displayedEndDate)
        return "\(start) - \(end)"
    }

    private func displayName(forRequesterMemberID requesterMemberID: String) -> String {
        MemberDisplayNamePlan.displayName(
            forMemberID: requesterMemberID,
            currentMemberID: settings.currentMemberID,
            currentDisplayName: settings.currentDisplayName,
            selfFallback: settings.strings.meTitle,
            partnerDisplayName: settings.partnerStatusDisplayName
        )
    }
}

private extension View {
    func invitesRowStyle(vertical: CGFloat = 6) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: vertical, leading: 16, bottom: vertical, trailing: 16))
    }
}

struct HistoryRequestRow: View {
    @Environment(SettingsStore.self) private var settings
    let request: CalendarAccessRequest
    let requesterDisplayName: String
    let rangeText: String
    let approve: () -> Void
    let decline: () -> Void

    var body: some View {
        let strings = settings.strings

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MemberAvatarForID(memberID: request.requesterMemberID, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.incomingHistoryRequestText(
                        requester: requesterDisplayName,
                        rangeText: rangeText
                    ))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(strings.prePairingHistoryLabel)
                        .font(.caption)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                }
            }
            HStack(spacing: 10) {
                Button(strings.declineButton, action: decline)
                    .buttonStyle(OurDaysSecondaryButtonStyle())
                Button(strings.approveButton, action: approve)
                    .buttonStyle(OurDaysPrimaryButtonStyle())
            }
        }
        .ourDaysCard()
    }
}

/// A pending invitation drawn as a ticket stub: the date block on the left, a dashed
/// tear line, the details on the right, and the answer buttons under a second tear —
/// an invitation is, after all, a ticket handed to the other person.
struct InvitationTicket: View {
    @Environment(SettingsStore.self) private var settings
    let invitation: EventInvitation
    let currentMemberID: String
    let accept: () -> Void
    let decline: () -> Void

    private var isFromMe: Bool { invitation.creatorMemberID == currentMemberID }
    private var senderIdentity: OurDaysIdentity { isFromMe ? .me : .partner }

    var body: some View {
        let strings = settings.strings
        let locale = settings.appLanguage.locale
        let canRespond = InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: currentMemberID)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(invitation.startDate.formatted(.dateTime.month(.abbreviated).locale(locale)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(senderIdentity.onTint)
                    Text(invitation.startDate.formatted(.dateTime.day()))
                        .font(OurDaysTheme.displayFont(38))
                        .foregroundStyle(OurDaysTheme.ink)
                    Text(invitation.startDate.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(senderIdentity.onTint)
                }
                .frame(width: 88)
                .frame(maxHeight: .infinity)
                .background(senderIdentity.tint)

                TicketTearLine(axis: .vertical)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        MemberAvatarForID(memberID: invitation.creatorMemberID, size: 20)
                        Text(isFromMe ? strings.sentByMeLabel : strings.invitedYouLine(settings.partnerDisplayName))
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Text(invitation.title)
                        .font(.headline)
                        .foregroundStyle(OurDaysTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(invitation.isAllDay
                         ? strings.allDay
                         : "\(strings.shortTimeText(invitation.startDate)) – \(strings.shortTimeText(invitation.endDate))")
                        .font(.subheadline)
                        .foregroundStyle(OurDaysTheme.ink.opacity(0.8))
                    if let location = invitation.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

            TicketTearLine(axis: .horizontal)

            Group {
                if canRespond {
                    HStack(spacing: 10) {
                        Button(strings.declineButton, action: decline)
                            .buttonStyle(OurDaysSecondaryButtonStyle())
                            .frame(maxWidth: 120)
                        Button(strings.acceptAndAddButton, action: accept)
                            .buttonStyle(OurDaysPrimaryButtonStyle())
                    }
                } else {
                    Text(strings.waitingForReplyLine(settings.partnerDisplayName))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
            }
            .padding(14)
        }
        .background(OurDaysTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

struct TicketTearLine: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis

    var body: some View {
        switch axis {
        case .horizontal:
            Line(axis: .horizontal)
                .stroke(OurDaysTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 1.5)
        case .vertical:
            Line(axis: .vertical)
                .stroke(OurDaysTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 1.5)
        }
    }

    private struct Line: Shape {
        let axis: Axis

        func path(in rect: CGRect) -> Path {
            var path = Path()
            switch axis {
            case .horizontal:
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            case .vertical:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
            return path
        }
    }
}

/// A handled (accepted / declined / canceled) invitation: a compact row with its status.
struct InvitationRow: View {
    @Environment(SettingsStore.self) private var settings
    let invitation: EventInvitation
    let currentMemberID: String
    let accept: () -> Void
    let decline: () -> Void
    let openInCalendar: () -> Void

    var body: some View {
        let strings = settings.strings
        let canOpenInCalendar = InvitationListPlan.canOpenInCalendar(invitation)
        let isFromMe = invitation.creatorMemberID == currentMemberID

        HStack(spacing: 12) {
            Text(invitation.startDate.formatted(.dateTime.day()))
                .font(OurDaysTheme.displayFont(20))
                .foregroundStyle(OurDaysTheme.ink)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.ink)
                    .lineLimit(1)
                Text("\(isFromMe ? strings.sentByMeLabel : strings.invitedYouLine(settings.partnerDisplayName)) · \(settings.strings.abbreviatedDateTimeText(invitation.startDate))")
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            OurDaysChip(
                title: strings.invitationStatusTitle(for: invitation.status),
                foreground: invitation.status == .accepted ? OurDaysTheme.ink : OurDaysTheme.secondaryInk,
                background: invitation.status == .accepted ? OurDaysTheme.sunken : OurDaysTheme.paper
            )

            if canOpenInCalendar {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
            }
        }
        .ourDaysCard(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canOpenInCalendar else { return }
            openInCalendar()
        }
    }
}
