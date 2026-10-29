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
    let iCloudProblem: ICloudAvailabilityPolicy.Problem?
    let isAcceptingInviteLink: Bool
    let inviteLinkMessage: String?
    /// Where the link exchange stands; nil once paired.
    let guideState: PairingGuideState?
    /// The partner's name when known, nil before their profile syncs.
    let guidePartnerName: String?
    let onStartPairing: () -> Void
    let onShowInviteHelp: () -> Void
    let onPasteInviteLink: () -> Void
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
                    Text(strings.pairingDayHeadline(pairingDate.map { PairingDatePolicy.ordinalDayNumber(since: $0) } ?? 1))
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
            } else if let guideState {
                PairingProgressGuide(state: guideState, partnerName: guidePartnerName)
            }

            HStack(spacing: 8) {
                OurDaysChip(
                    title: guideState?.currentStep == .linkBackAccepted
                        ? strings.pairingGuideWaitingForPartnerToOpenChip
                        : strings.pairingStatusTitle(for: status),
                    foreground: status == .paired ? OurDaysTheme.onInkFill : OurDaysTheme.ink,
                    background: status == .paired ? OurDaysTheme.inkFill : OurDaysTheme.sunken
                )
                OurDaysChip(title: syncStatusText, foreground: OurDaysTheme.secondaryInk)
            }

            if let iCloudProblem, status != .paired {
                iCloudProblemNotice(iCloudProblem, strings: strings)
            }

            if let guideState {
                HStack(spacing: 10) {
                    guidePrimaryButton(for: guideState, strings: strings)
                    checkICloudButton(strings: strings)
                }

                if guideState.currentStep == .firstLinkAccepted || guideState.currentStep == .linkBackAccepted {
                    Button(strings.pairingGuideHelpLink, action: onShowInviteHelp)
                        .font(.subheadline)
                        .foregroundStyle(OurDaysIdentity.me.onTint)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("pairing-guide-help")
                }
            }

            if status == .notPaired {
                pasteInviteLinkSection(strings: strings)
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

    /// One button per step: send the first link, send it again, remind the partner to
    /// send theirs back, or send mine back.
    @ViewBuilder
    private func guidePrimaryButton(for state: PairingGuideState, strings: ShareCalStrings) -> some View {
        switch (state.role, state.currentStep) {
        case (.initiator, .linkSentBack):
            ShareLink(item: strings.pairingGuideRemindMessage) {
                Label(strings.pairingGuideRemindButton(guidePartnerName), systemImage: "bell")
            }
            .buttonStyle(OurDaysPrimaryButtonStyle())
            .accessibilityIdentifier("pairing-guide-remind")
        default:
            Button(action: onStartPairing) {
                Label(guideButtonTitle(for: state, strings: strings), systemImage: guideButtonIcon(for: state))
            }
            .buttonStyle(OurDaysPrimaryButtonStyle())
            .disabled(!isCloudKitEnabled || isPreparingShare)
            .accessibilityIdentifier("pairing-guide-primary")
        }
    }

    private func guideButtonTitle(for state: PairingGuideState, strings: ShareCalStrings) -> String {
        if isPreparingShare {
            return strings.startPairingButton(isPreparing: true)
        }
        switch (state.role, state.currentStep) {
        case (.initiator, .firstLinkSent):
            return strings.startPairingButton(isPreparing: false)
        case (.receiver, .linkSentBack):
            return strings.pairingGuideSendBackButton(guidePartnerName)
        default:
            return strings.pairingGuideResendButton
        }
    }

    private func guideButtonIcon(for state: PairingGuideState) -> String {
        switch (state.role, state.currentStep) {
        case (.initiator, .firstLinkSent): "person.badge.plus"
        case (.receiver, .linkSentBack): "arrowshape.turn.up.left"
        default: "arrow.clockwise"
        }
    }

    private func iCloudProblemNotice(_ problem: ICloudAvailabilityPolicy.Problem, strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(strings.iCloudUnavailableTitle, systemImage: "exclamationmark.icloud")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OurDaysTheme.destructive)
            Text(strings.iCloudProblemSteps(problem))
                .font(.caption)
                .foregroundStyle(OurDaysTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OurDaysTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("icloud-problem-notice")
    }

    private func pasteInviteLinkSection(strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onPasteInviteLink) {
                Label(strings.pasteInviteLinkButton(isAccepting: isAcceptingInviteLink), systemImage: "doc.on.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.ink)
            }
            .buttonStyle(.plain)
            .disabled(!isCloudKitEnabled || isAcceptingInviteLink)
            .accessibilityIdentifier("paste-invite-link")
            Text(inviteLinkMessage ?? strings.pasteInviteLinkHint)
                .font(.caption)
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
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
