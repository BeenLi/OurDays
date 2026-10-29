import SwiftUI

/// 我们 › 数据与恢复: the rows needed only when troubleshooting a pairing or starting
/// over, moved off the 我们 tab so they don't sit between the everyday settings.
/// Reinstalling needs nothing here: the first launch asks whether to keep the
/// existing iCloud data.
struct DataRecoveryView: View {
    @Environment(SettingsStore.self) private var settings
    let isPreparingShare: Bool
    let canOpenSharedPeople: Bool
    let isDeletingICloudData: Bool
    let canDeleteICloudData: Bool
    let errorMessage: String?
    let onOpenSharedPeople: () -> Void
    let onDeleteICloudData: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        let strings = settings.strings

        List {
            Section {
                SettingsNavigationRow(
                    title: strings.sharedPeopleRowTitle,
                    isLoading: isPreparingShare,
                    action: onOpenSharedPeople
                ) {
                    Image(systemName: "person.2.badge.gearshape")
                }
                .accessibilityIdentifier("shared-people-official-share-button")
                .disabled(!canOpenSharedPeople)
            } header: {
                Text(strings.troubleshootingSection)
            } footer: {
                Text(strings.sharedPeopleFootnote)
            }
            .listRowBackground(OurDaysTheme.surface)

            Section {
                Button(
                    isDeletingICloudData ? strings.deletingICloudDataButton : strings.deleteICloudDataButton,
                    role: .destructive
                ) {
                    showDeleteConfirmation = true
                }
                .disabled(!canDeleteICloudData)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(OurDaysTheme.destructive)
                }
            } header: {
                Text(strings.startOverSection)
            } footer: {
                Text(strings.deleteICloudDataConfirmationMessage)
            }
            .listRowBackground(OurDaysTheme.surface)
        }
        .listSectionSpacing(20)
        .ourDaysListBackground()
        .navigationTitle(strings.dataRecoveryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert(strings.deleteICloudDataConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button(strings.deleteICloudDataButton, role: .destructive, action: onDeleteICloudData)
            Button(strings.cancelButton, role: .cancel) {}
        } message: {
            Text(strings.deleteICloudDataConfirmationMessage)
        }
    }
}
