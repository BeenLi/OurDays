import CloudKit
import SwiftData
import SwiftUI

struct CreateInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @Binding var selectedDate: Date
    @Binding var mode: CalendarMode
    @Query(sort: \EventMirror.startDate) private var mirrors: [EventMirror]
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay = false
    @State private var location = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var conflictMessage: String?
    @State private var isShowingConflict = false
    @State private var isSending = false
    @State private var calendarChoices: [CalendarDescriptor] = []
    @State private var calendarID: String?

    init(selectedDate: Binding<Date>, mode: Binding<CalendarMode>) {
        _selectedDate = selectedDate
        _mode = mode
        let defaultStart = Self.defaultStartDate(for: selectedDate.wrappedValue)
        _title = State(initialValue: "")
        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: defaultStart.addingTimeInterval(60 * 60))
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            Form {
                Section(strings.createInviteSection) {
                    TextField(strings.titleLabel, text: $title)

                    DatePicker(
                        strings.dateLabel,
                        selection: dayBinding,
                        displayedComponents: .date
                    )

                    Toggle(strings.allDay, isOn: $isAllDay)

                    DatePicker(
                        strings.startsLabel,
                        selection: startTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(isAllDay)

                    DatePicker(
                        strings.endsLabel,
                        selection: $endDate,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(isAllDay)

                    TextField(strings.locationLabel, text: $location)
                    TextField(strings.notesLabel, text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if !calendarChoices.isEmpty {
                    Section {
                        Picker(strings.inviteCalendarLabel, selection: $calendarID) {
                            ForEach(calendarChoices) { calendar in
                                Text(calendar.title).tag(Optional(calendar.id))
                            }
                        }
                        .accessibilityIdentifier("create-invite-calendar-picker")
                    } footer: {
                        Text(strings.inviteCalendarFootnote)
                    }
                }

                Section(strings.inviteSection) {
                    HStack(spacing: 12) {
                        MemberAvatarView(
                            avatar: settings.partnerAvatar,
                            fallbackText: settings.partnerAvatarFallbackText,
                            identity: .partner,
                            size: 36
                        )
                        Text(settings.partnerDisplayName)
                            .foregroundStyle(OurDaysTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(strings.invitePartnerRowHint(isPaired: isPaired))
                            .font(.footnote)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("create-invite-partner-row")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .ourDaysListBackground()
            .navigationTitle(strings.newInviteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(strings.cancelButton) {
                        dismiss()
                    }
                    .disabled(isSending)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(strings.sendInviteButton) {
                    sendInvite()
                }
                .buttonStyle(OurDaysPrimaryButtonStyle())
                .disabled(isSending || !isPaired)
                .accessibilityIdentifier("create-invite-send-button")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(OurDaysTheme.paper)
            }
            .onAppear(perform: loadCalendarChoices)
            .overlay {
                if isSending {
                    ProgressView()
                        .padding(18)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .alert(strings.invitationConflictTitle, isPresented: $isShowingConflict) {
                Button(strings.cancelButton, role: .cancel) {}
                Button(strings.inviteAnywayButton) {
                    sendInvite(skipConflictCheck: true)
                }
            } message: {
                if let conflictMessage {
                    Text(conflictMessage)
                }
            }
            .onChange(of: isAllDay) { _, newValue in
                adjustForAllDay(newValue)
            }
        }
    }

    private var isPaired: Bool {
        settings.partnerShareOwnerID != nil
    }

    private func loadCalendarChoices() {
        let choices = InviteCalendarChoicePolicy.candidates(
            calendars: services.calendarAccess.calendars(),
            selectedCalendarIDs: settings.selectedCalendarIDs
        )
        calendarChoices = choices
        calendarID = InviteCalendarChoicePolicy.defaultCalendarID(
            candidates: choices,
            lastUsedCalendarID: settings.lastInviteCalendarID,
            systemDefaultCalendarID: services.calendarAccess.defaultCalendarIDForNewEvents()
        )
    }

    private var dayBinding: Binding<Date> {
        Binding {
            startDate
        } set: { newDate in
            moveInvite(toDayContaining: newDate)
        }
    }

    // Moving the start time slides the end time to keep the chosen duration,
    // matching the system calendar editor. The day row uses `dayBinding`, which
    // preserves duration separately, so this stays scoped to the time picker.
    private var startTimeBinding: Binding<Date> {
        Binding {
            startDate
        } set: { newStart in
            // All-day invites own start/end via `adjustForAllDay`; ignore any
            // stray time-picker writes entirely so startDate can't drift.
            guard !isAllDay else { return }
            let previousStart = startDate
            let previousEnd = endDate
            startDate = newStart
            endDate = InviteTimeAdjustmentPolicy.endDate(
                forNewStart: newStart,
                previousStart: previousStart,
                previousEnd: previousEnd
            )
        }
    }

    private static func defaultStartDate(for selectedDate: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: selectedDate)
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(10 * 60 * 60)
    }

    private func moveInvite(toDayContaining newDate: Date) {
        let calendar = Calendar.current
        let currentDuration = max(60 * 60, endDate.timeIntervalSince(startDate))
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)
        let newDayStart = calendar.startOfDay(for: newDate)
        startDate = calendar.date(
            bySettingHour: startComponents.hour ?? 10,
            minute: startComponents.minute ?? 0,
            second: startComponents.second ?? 0,
            of: newDayStart
        ) ?? newDayStart
        endDate = startDate.addingTimeInterval(currentDuration)
        if isAllDay {
            adjustForAllDay(true)
        }
    }

    private func adjustForAllDay(_ enabled: Bool) {
        if enabled {
            let dayStart = Calendar.current.startOfDay(for: startDate)
            startDate = dayStart
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
                ?? dayStart.addingTimeInterval(24 * 60 * 60)
        } else if endDate <= startDate {
            endDate = startDate.addingTimeInterval(60 * 60)
        }
    }

    private func currentDraft() -> CreateInviteDraft {
        CreateInviteDraft(
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            location: location,
            notes: notes
        )
    }

    private func sendInvite(skipConflictCheck: Bool = false) {
        guard !isSending else { return }
        errorMessage = nil
        let draft = currentDraft()

        do {
            _ = try CreateInvitePolicy.localCalendarDraft(from: draft)

            if !skipConflictCheck {
                let candidate = try CreateInvitePolicy.conflictCandidateMirror(
                    from: draft,
                    ownerMemberID: settings.currentMemberID
                )
                let conflicts = InvitationConflictPolicy.conflicts(
                    for: candidate,
                    partnerMemberID: settings.partnerOwnerIDForLocalData,
                    mirrors: mirrors
                )
                if let firstConflict = conflicts.first {
                    conflictMessage = settings.strings.invitationConflictMessage(
                        eventTitle: firstConflict.title,
                        timeText: EventTimeRangeTextPolicy.text(for: firstConflict, strings: settings.strings),
                        additionalConflictCount: conflicts.count - 1
                    )
                    isShowingConflict = true
                    return
                }
            }

            isSending = true
            let localDraft = try CreateInvitePolicy.localCalendarDraft(from: draft)
            let createdEvent = try services.calendarAccess.createEvent(from: localDraft, inCalendarWithID: calendarID)
            let mirror = try CreateInvitePolicy.mirror(
                from: draft,
                createdEvent: createdEvent,
                ownerMemberID: settings.currentMemberID
            )
            let invitation = try CreateInvitePolicy.invitation(
                from: draft,
                creatorMemberID: settings.currentMemberID,
                inviteeMemberID: settings.partnerOwnerIDForLocalData
            )
            invitation.createdLocalEventID = createdEvent.eventIdentifier
            // Mark "upload owed" so a failed/optimistic send self-heals on the next sync.
            let cloudKit = services.cloudKitIfAvailable
            invitation.needsCloudKitUpload = cloudKit != nil
            try EventMirrorStore.upsert(mirror, modelContext: modelContext)
            modelContext.insert(invitation)
            settings.selectedCalendarIDs = ShareCalCalendarBootstrapPolicy.selectedCalendarIDs(
                afterEnsuring: CalendarDescriptor(
                    id: createdEvent.calendarIdentifier,
                    title: createdEvent.calendarTitle,
                    colorHex: createdEvent.calendarColorHex,
                    allowsContentModifications: true
                ),
                currentSelection: settings.selectedCalendarIDs
            )
            try modelContext.save()
            settings.lastInviteCalendarID = createdEvent.calendarIdentifier
            selectedDate = localDraft.startDate
            mode = .day

            // Optimistic send, as in the event detail: the event is in the calendar and
            // the invitation in the local store, so the sheet closes now. The upload runs
            // in the background; if it fails, `needsCloudKitUpload` keeps the invitation
            // queued (InvitationReuploadPolicy.creationsNeedingReupload) and the next sync
            // regenerates and uploads the mirror.
            dismiss()

            guard let cloudKit else { return }
            let currentMemberID = settings.currentMemberID
            let modelContext = modelContext
            Task {
                do {
                    try await cloudKit.ensureShareRoot(ownerMemberID: currentMemberID)
                    try await cloudKit.saveMirrorsForSync([mirror])
                    try await cloudKit.saveInvitationForSync(invitation, currentMemberID: currentMemberID)
                    invitation.needsCloudKitUpload = false
                    try? modelContext.save()
                } catch {
                    // Leave the flag set; the next sync retries.
                }
            }
        } catch {
            errorMessage = validationMessage(for: error)
            isSending = false
        }
    }

    private func validationMessage(for error: Error) -> String {
        if let validationError = error as? CreateInviteValidationError {
            switch validationError {
            case .emptyTitle:
                return settings.strings.emptyTitleError
            case .invalidDateRange:
                return settings.strings.invalidDateRangeError
            case .alreadyEnded:
                return settings.strings.inviteAlreadyEndedError
            }
        }
        return error.localizedDescription
    }

}
