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

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sendInvite()
                    } label: {
                        Label(strings.sendInviteButton, systemImage: "paperplane.fill")
                    }
                    .disabled(isSending)
                }
            }
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
            let createdEvent = try services.calendarAccess.createShareCalEvent(from: localDraft)
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
            selectedDate = localDraft.startDate
            mode = .day

            guard let cloudKit = services.cloudKitIfAvailable else {
                dismiss()
                return
            }

            Task {
                do {
                    try await cloudKit.ensureShareRoot(ownerMemberID: settings.currentMemberID)
                    try await cloudKit.saveMirrorsForSync([mirror])
                    try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                    dismiss()
                } catch {
                    errorMessage = CloudKitSharingFailureMessage.userFacingMessage(for: error)
                    isSending = false
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
