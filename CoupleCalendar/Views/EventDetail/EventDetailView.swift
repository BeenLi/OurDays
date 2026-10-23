import CloudKit
import SwiftData
import SwiftUI

/// Owner-tinted header of an event detail sheet: who it belongs to, a serif title,
/// and one line each for time and place.
struct EventDetailHeader: View {
    @Environment(SettingsStore.self) private var settings
    let title: String
    let ownerLabel: String
    let ownerMemberID: String?
    let timeText: String
    let location: String?
    let calendarTitle: String?
    let isJoint: Bool

    private var identity: OurDaysIdentity? {
        guard let ownerMemberID else { return nil }
        return ownerMemberID == settings.currentMemberID ? .me : .partner
    }

    private var primary: Color { isJoint ? OurDaysTheme.onJoint : OurDaysTheme.ink }
    private var secondary: Color { isJoint ? OurDaysTheme.onJointSecondary : (identity?.onTint ?? OurDaysTheme.secondaryInk) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isJoint {
                    HStack(spacing: -8) {
                        MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: 26)
                        MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: 26)
                    }
                } else if let ownerMemberID {
                    MemberAvatarForID(memberID: ownerMemberID, size: 26)
                }
                Text(ownerLabel)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(secondary)
            }

            Text(title)
                .font(OurDaysTheme.displayFont(28))
                .foregroundStyle(primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label(timeText, systemImage: "clock")
                if let location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                if let calendarTitle, !calendarTitle.isEmpty {
                    Label(calendarTitle, systemImage: "calendar")
                }
            }
            .font(.subheadline)
            .foregroundStyle(isJoint ? OurDaysTheme.onJointSecondary : OurDaysTheme.secondaryInk)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isJoint ? OurDaysTheme.joint : (identity?.tint ?? OurDaysTheme.surface),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @Query private var accessRequests: [CalendarAccessRequest]
    @State private var inviteError: String?
    @State private var inviteSuccessMessage: String?
    @State private var conflictMessage: String?
    @State private var isShowingInviteConflict = false
    let event: EventMirror

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                Section {
                    EventDetailHeader(
                        title: event.title,
                        ownerLabel: event.ownerMemberID == settings.currentMemberID
                            ? strings.myScheduleLabel
                            : strings.partnerScheduleLabel(settings.partnerDisplayName),
                        ownerMemberID: event.ownerMemberID,
                        timeText: detailTimeText,
                        location: event.location,
                        calendarTitle: event.sourceCalendarTitle,
                        isJoint: false
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.ink)
                            .ourDaysCard()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                // An invitation proposes something still to come: once the event has
                // ended there is nothing to invite the partner to, so the section is gone.
                if InvitationTimingPlan.canInvite(endDate: event.endDate, isAllDay: event.isAllDay, now: .now) {
                    Section {
                        Button {
                            createInviteAfterConflictCheck()
                        } label: {
                            Label(strings.invitePartnerButton, systemImage: "person.badge.plus")
                                .foregroundStyle(OurDaysTheme.ink)
                        }
                        // Optimistic send shows success instantly; disable to prevent a
                        // double-tap creating a duplicate invitation within this sheet.
                        .disabled(inviteSuccessMessage != nil)

                        if let inviteSuccessMessage {
                            Text(inviteSuccessMessage)
                                .font(.caption)
                                .foregroundStyle(OurDaysIdentity.me.onTint)
                        }

                        if let inviteError {
                            Text(inviteError)
                                .font(.caption)
                                .foregroundStyle(OurDaysTheme.destructive)
                        }
                    } header: {
                        Text(strings.inviteSection)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .textCase(nil)
                    }
                }

                // `event` may be my own transient "display:" mirror. Its thread is keyed by the
                // mirrorKey (== the persisted record's id on both devices), so I can start a
                // conversation on my own event before it has even synced; the partner reads the
                // comment from my shared zone once the mirror lands. Only an event the partner
                // can't see (outside the sharing windows) gets an explanation instead.
                switch EventDetailCommentPlan.availability(for: event, mirrors: mirrors, sharingWindows: sharingWindows) {
                case .available(let anchor):
                    EventCommentsSection(anchor: anchor)
                case .notSharedWithPartner:
                    Section {
                        Text(strings.commentsUnavailableNotShared)
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .listRowBackground(Color.clear)
                    } header: {
                        Text(strings.commentsSection)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .textCase(nil)
                    }
                }
            }
            .listSectionSpacing(16)
            .ourDaysListBackground()
            .navigationTitle(strings.eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Opening an event should surface the partner's latest comments;
                // run a throttled sync so it stays cheap on repeated opens.
                await syncOnOpenIfNeeded()
            }
            .refreshable {
                await SyncCoordinator.syncIfIdle(services: services, settings: settings, modelContext: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.doneButton) {
                        dismiss()
                    }
                }
            }
            .alert(strings.invitationConflictTitle, isPresented: $isShowingInviteConflict) {
                Button(strings.cancelButton, role: .cancel) {}
                Button(strings.inviteAnywayButton) {
                    createInvite()
                }
            } message: {
                if let conflictMessage {
                    Text(conflictMessage)
                }
            }
        }
    }

    /// The same windows `SyncCoordinator.foregroundSync` mirrors with: from the pairing day
    /// onward, plus any approved history request.
    private var sharingWindows: [DateInterval] {
        CalendarSharingWindowPlan.effectiveWindows(
            now: settings.pairingDate ?? PairingDatePlan.normalizedPairingDate(.now),
            accessRequests: accessRequests
        )
    }

    private var detailTimeText: String {
        EventDetailTimePlan.text(
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            strings: settings.strings,
            locale: settings.appLanguage.locale
        )
    }

    private func createInviteAfterConflictCheck() {
        inviteError = nil
        inviteSuccessMessage = nil
        let conflicts = InvitationConflictPlan.conflicts(
            for: event,
            partnerMemberID: settings.partnerOwnerIDForLocalData,
            mirrors: mirrors
        )
        guard let firstConflict = conflicts.first else {
            createInvite()
            return
        }

        conflictMessage = settings.strings.invitationConflictMessage(
            eventTitle: firstConflict.title,
            timeText: EventTimeRangeTextPlan.text(for: firstConflict, strings: settings.strings),
            additionalConflictCount: conflicts.count - 1
        )
        isShowingInviteConflict = true
    }

    private func createInvite() {
        inviteError = nil
        inviteSuccessMessage = nil
        let cloudKit = services.cloudKitIfAvailable
        let invitation = EventInvitation(
            creatorMemberID: settings.currentMemberID,
            inviteeMemberID: settings.partnerOwnerIDForLocalData,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            statusRawValue: InvitationStatus.pending.rawValue,
            // Mark "upload owed" so a failed/optimistic send self-heals on the next sync.
            needsCloudKitUpload: cloudKit != nil
        )
        modelContext.insert(invitation)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(invitation)
            inviteError = error.localizedDescription
            return
        }

        // Optimistic send (req2): the invitation is durably in the local store, so report
        // success immediately rather than blocking on the CloudKit round-trip. The upload
        // moves to the background; if it fails, `needsCloudKitUpload` keeps it queued for
        // self-heal on the next foregroundSync (InvitationReuploadPlan.creationsNeedingReupload).
        inviteSuccessMessage = settings.strings.invitationSentMessage

        guard let cloudKit else { return }
        Task {
            do {
                try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                invitation.needsCloudKitUpload = false
                try? modelContext.save()
            } catch {
                // Leave the flag set; the next sync retries. Don't surface an error that
                // would contradict the success already shown to the user.
            }
        }
    }

    private func syncOnOpenIfNeeded() async {
        guard ForegroundSyncPlan.shouldRunAutomaticSync(
            lastSyncAt: settings.lastSyncAt,
            now: .now,
            syncPhase: settings.syncPhase,
            hasPendingAcceptedShare: false
        ) else { return }
        await SyncCoordinator.syncIfIdle(services: services, settings: settings, modelContext: modelContext)
    }
}

/// Detail screen for a joint (共同) event. A joint event has no `EventMirror` of its own
/// (it's derived from an accepted `EventInvitation`), so it shows the invitation's fields
/// and a comments thread anchored to the invitation — letting both partners comment on
/// the same thread. No "invite partner" section: it's already a shared/accepted event.
struct JointEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    let event: JointScheduleEvent
    let invitation: EventInvitation

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            List {
                Section {
                    EventDetailHeader(
                        title: event.title,
                        ownerLabel: strings.jointScheduleLabel,
                        ownerMemberID: nil,
                        timeText: EventDetailTimePlan.text(
                            startDate: event.startDate,
                            endDate: event.endDate,
                            isAllDay: event.isAllDay,
                            strings: strings,
                            locale: settings.appLanguage.locale
                        ),
                        location: event.location,
                        calendarTitle: nil,
                        isJoint: true
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.ink)
                            .ourDaysCard()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                EventCommentsSection(anchor: EventCommentAnchorPlan.anchor(forInvitation: invitation))
            }
            .listSectionSpacing(16)
            .ourDaysListBackground()
            .navigationTitle(strings.eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await syncOnOpenIfNeeded()
            }
            .refreshable {
                await SyncCoordinator.syncIfIdle(services: services, settings: settings, modelContext: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.doneButton) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func syncOnOpenIfNeeded() async {
        guard ForegroundSyncPlan.shouldRunAutomaticSync(
            lastSyncAt: settings.lastSyncAt,
            now: .now,
            syncPhase: settings.syncPhase,
            hasPendingAcceptedShare: false
        ) else { return }
        await SyncCoordinator.syncIfIdle(services: services, settings: settings, modelContext: modelContext)
    }
}
