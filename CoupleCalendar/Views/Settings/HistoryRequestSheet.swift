import SwiftUI

struct HistoryRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let pairingDate: Date
    let onSend: (Date, Date) -> Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var validationMessage: String?

    init(
        pairingDate: Date,
        initialRange: PairingHistoryRequestRange? = nil,
        onSend: @escaping (Date, Date) -> Bool
    ) {
        self.pairingDate = pairingDate
        self.onSend = onSend
        let range = initialRange ?? PairingDatePlan.defaultHistoryRequestRange(pairingDate: pairingDate)
        _startDate = State(initialValue: range.start)
        _endDate = State(initialValue: range.end)
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            Form {
                Section {
                    Text(strings.prePairingHistoryRequestDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    DatePicker(
                        strings.accessRequestStartLabel,
                        selection: $startDate,
                        in: ...maxSelectableDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        strings.accessRequestEndLabel,
                        selection: $endDate,
                        in: ...maxSelectableDate,
                        displayedComponents: .date
                    )

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(strings.sendRequestButton) {
                        send()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .ourDaysListBackground()
            .navigationTitle(strings.prePairingHistoryRequestTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.cancelButton) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var maxSelectableDate: Date {
        PairingDatePlan.displayedEndDate(
            forExclusiveEndDate: PairingDatePlan.normalizedPairingDate(pairingDate)
        )
    }

    private func send() {
        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let exclusiveEndDate = PairingDatePlan.exclusiveEndDate(forDisplayedEndDate: endDate, calendar: calendar)
        guard exclusiveEndDate > normalizedStartDate else {
            validationMessage = settings.strings.invalidAccessRequestRangeMessage
            return
        }
        validationMessage = nil
        if onSend(startDate, endDate) {
            dismiss()
        }
    }
}
