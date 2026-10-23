import SwiftUI

struct InitialProfilePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @State private var nickname: String
    let onSave: (String) -> Void
    let onSkip: () -> Void

    init(
        initialNickname: String,
        onSave: @escaping (String) -> Void,
        onSkip: @escaping () -> Void
    ) {
        _nickname = State(initialValue: initialNickname)
        self.onSave = onSave
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.initialProfilePromptMessage)
                        .foregroundStyle(.secondary)
                    TextField(settings.strings.myDisplayNamePlaceholder, text: $nickname)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(settings.strings.myNicknameLabel)
                }
            }
            .navigationTitle(settings.strings.initialProfilePromptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(settings.strings.skipButton) {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.strings.saveButton) {
                        guard let normalizedNickname = PairingSettingsPolicy.normalizedDisplayName(nickname) else { return }
                        onSave(normalizedNickname)
                        dismiss()
                    }
                    .disabled(PairingSettingsPolicy.normalizedDisplayName(nickname) == nil)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct PartnerNotePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @State private var note: String
    let onSave: (String) -> Void
    let onSkip: () -> Void

    init(
        initialNote: String,
        onSave: @escaping (String) -> Void,
        onSkip: @escaping () -> Void
    ) {
        _note = State(initialValue: initialNote)
        self.onSave = onSave
        self.onSkip = onSkip
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.partnerNotePromptMessage)
                        .foregroundStyle(.secondary)
                    TextField(settings.strings.partnerDisplayNamePlaceholder, text: $note)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel(settings.strings.partnerNicknameEditLabel)
                }
            }
            .navigationTitle(settings.strings.partnerNotePromptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(settings.strings.skipButton) {
                        onSkip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(settings.strings.saveButton) {
                        let normalizedNote = PairingSettingsPolicy.normalizedDisplayName(note) ?? ""
                        onSave(normalizedNote)
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct PairingSafetyNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let onAcknowledge: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.pairingSafetyNoticeMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Button(settings.strings.continueButton) {
                        onAcknowledge()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(settings.strings.pairingSafetyNoticeTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

struct ExistingICloudDataRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @State private var isRunningAction = false
    @State private var actionError: String?
    let onDelete: () async throws -> Void
    let onKeep: () async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.strings.existingICloudDataPromptMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let actionError {
                        Text(actionError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    // Keeping the data is the safe, expected choice after a reinstall,
                    // so it comes first; deleting is the exception and stays destructive.
                    Button {
                        runAction(onKeep)
                    } label: {
                        if isRunningAction {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text(settings.strings.continueExistingICloudDataButton)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isRunningAction)

                    Button(role: .destructive) {
                        runAction(onDelete)
                    } label: {
                        Text(settings.strings.deleteICloudDataButton)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(isRunningAction)
                }
            }
            .navigationTitle(settings.strings.existingICloudDataPromptTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isRunningAction)
    }

    private func runAction(_ action: @escaping () async throws -> Void) {
        guard !isRunningAction else { return }
        isRunningAction = true
        actionError = nil
        Task {
            do {
                try await action()
                await MainActor.run {
                    isRunningAction = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRunningAction = false
                    actionError = error.localizedDescription
                }
            }
        }
    }
}
