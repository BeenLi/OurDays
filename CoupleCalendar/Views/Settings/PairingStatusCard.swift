import CloudKit
import SwiftUI

/// The hero card of the 我们 tab: the two avatars linked together, how many days the
/// pairing has lasted, and the sync state. Actions that change the pairing live in the
/// list below it, so the card only shows state plus the one next step.
struct PairingStatusCard: View {
    @Environment(SettingsStore.self) private var settings
    let status: PairingStatus
    let pairingDate: Date?
    let partnerName: String
    let syncStatusText: String
    let isCloudKitEnabled: Bool
    let isPreparingShare: Bool
    let isCheckingCloudKitAccount: Bool
    let isSyncing: Bool
    let cloudKitDiagnosticMessage: String?
    let onStartPairing: () -> Void
    let onCheckCloudKitStatus: () -> Void
    let onSync: () -> Void
    let onEditMyAvatar: () -> Void
    let onEditPartnerAvatar: () -> Void
    let onHideCloudKitDiagnostic: () -> Void

    var body: some View {
        let strings = settings.strings

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: -14) {
                    Button(action: onEditMyAvatar) {
                        MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.myAvatarLabel)
                    .zIndex(1)

                    if status != .notPaired {
                        Button(action: onEditPartnerAvatar) {
                            MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: 56)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(strings.partnerAvatarLabel(partnerName))
                    } else {
                        Circle()
                            .strokeBorder(OurDaysTheme.border, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .background(Circle().fill(OurDaysTheme.surface))
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "plus").font(.headline).foregroundStyle(OurDaysTheme.secondaryInk))
                            .accessibilityHidden(true)
                    }
                }

                Spacer()

                Button(action: onSync) {
                    Group {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(OurDaysTheme.ink)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(OurDaysTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .accessibilityLabel(strings.syncAccessibilityLabel)
            }

            if status == .paired {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.pairingDayHeadline(pairingDate.map { PairingDatePlan.ordinalDayNumber(since: $0) } ?? 1))
                        .font(OurDaysTheme.displayFont(32))
                        .foregroundStyle(OurDaysTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let pairingDate {
                        Text(strings.pairedSinceLine(partnerName: partnerName, dateText: strings.pairingDateText(for: pairingDate)))
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pairing-day-count")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.pairingStatusTitle(for: status))
                        .font(OurDaysTheme.displayFont(28))
                        .foregroundStyle(OurDaysTheme.ink)
                    Text(status == .waitingForYouToShare ? strings.pairingWaitingForYouToShareDescription : strings.pairingDescription)
                        .font(.subheadline)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pairingDate {
                        Text(strings.pairingDateLine(strings.pairingDateText(for: pairingDate)))
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
            }

            HStack(spacing: 8) {
                OurDaysChip(
                    title: strings.pairingStatusTitle(for: status),
                    foreground: status == .paired ? OurDaysTheme.onInkFill : OurDaysTheme.ink,
                    background: status == .paired ? OurDaysTheme.inkFill : OurDaysTheme.sunken
                )
                OurDaysChip(title: syncStatusText, foreground: OurDaysTheme.secondaryInk)
            }

            if status == .notPaired || status == .waitingForYouToShare {
                HStack(spacing: 10) {
                    Button {
                        onStartPairing()
                    } label: {
                        Label(strings.startPairingButton(isPreparing: isPreparingShare), systemImage: "person.badge.plus")
                    }
                    .buttonStyle(OurDaysPrimaryButtonStyle())
                    .disabled(!isCloudKitEnabled || isPreparingShare)

                    checkICloudButton(strings: strings)
                }
            } else if status != .paired {
                HStack {
                    Spacer()
                    checkICloudButton(strings: strings)
                }
            }

            if !isCloudKitEnabled {
                Text(strings.iCloudSharingUnavailableLocalBuild)
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.destructive)
            }

            if let cloudKitDiagnosticMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(strings.diagnosticsTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                        Spacer()
                        Button {
                            onHideCloudKitDiagnostic()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(strings.cancelButton)
                    }
                    Text(cloudKitDiagnosticMessage)
                        .font(.caption2.monospaced())
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(OurDaysTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OurDaysTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private func checkICloudButton(strings: ShareCalStrings) -> some View {
        Button {
            onCheckCloudKitStatus()
        } label: {
            Image(systemName: "icloud.and.arrow.up")
                .font(.headline)
                .foregroundStyle(OurDaysTheme.ink)
                .frame(width: 48, height: 48)
                .overlay(Circle().stroke(OurDaysTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isCloudKitEnabled || isCheckingCloudKitAccount)
        .accessibilityLabel(strings.checkICloudStatusButton(isChecking: isCheckingCloudKitAccount))
    }
}

struct SharingScopeRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(OurDaysTheme.ink)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A tappable settings row with a leading glyph and a trailing chevron.
struct SettingsNavigationRow<Leading: View>: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var isLoading = false
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                    .foregroundStyle(OurDaysTheme.ink)
                    .frame(minWidth: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(OurDaysTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                }
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
