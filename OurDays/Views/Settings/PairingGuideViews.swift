import SwiftUI
import UIKit

private extension OurDaysPerson {
    var identity: OurDaysIdentity {
        switch self {
        case .me: .me
        case .partner: .partner
        }
    }
}

/// Where the two of us are in the four-step link exchange: the step counter, one
/// sentence on what happens next, and a line of four dots in the colour of whoever
/// has to act (teal me, coral partner).
struct PairingProgressGuide: View {
    @Environment(SettingsStore.self) private var settings
    let state: PairingGuideState
    let partnerName: String?

    var body: some View {
        let strings = settings.strings

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(strings.pairingGuideStepCounter(state.currentStep))
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                Text(strings.pairingGuideHeadline(state, partnerName: partnerName))
                    .font(OurDaysTheme.displayFont(24))
                    .foregroundStyle(OurDaysTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(strings.pairingGuideMessage(state, partnerName: partnerName))
                    .font(.subheadline)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            progressLine(strings: strings)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("pairing-guide")
    }

    private func progressLine(strings: ShareCalStrings) -> some View {
        let steps = PairingGuideStep.allCases
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(steps, id: \.self) { step in
                    if step != steps.first {
                        connector(into: step)
                    }
                    dot(for: step)
                }
            }
            HStack(spacing: 0) {
                ForEach(steps, id: \.self) { step in
                    Text(strings.pairingGuideStepLabel(step, role: state.role))
                        .font(.caption2.weight(step == state.currentStep ? .semibold : .regular))
                        .foregroundStyle(step == state.currentStep ? color(for: step) : OurDaysTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: alignment(for: step))
                }
            }
        }
    }

    private func color(for step: PairingGuideStep) -> Color {
        step.actor(for: state.role).identity.color
    }

    private func alignment(for step: PairingGuideStep) -> Alignment {
        switch step {
        case .firstLinkSent: .leading
        case .linkBackAccepted: .trailing
        default: .center
        }
    }

    @ViewBuilder
    private func dot(for step: PairingGuideStep) -> some View {
        if step.rawValue < state.currentStep.rawValue {
            Circle().fill(color(for: step)).frame(width: 14, height: 14)
        } else if step == state.currentStep {
            Circle()
                .strokeBorder(color(for: step), lineWidth: 3)
                .background(Circle().fill(OurDaysTheme.surface))
                .frame(width: 16, height: 16)
        } else {
            Circle()
                .strokeBorder(OurDaysTheme.border, lineWidth: 2)
                .frame(width: 14, height: 14)
        }
    }

    @ViewBuilder
    private func connector(into step: PairingGuideStep) -> some View {
        if step.rawValue < state.currentStep.rawValue {
            Rectangle().fill(color(for: step)).frame(height: 3)
        } else if step == state.currentStep {
            Line()
                .stroke(color(for: step), style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                .frame(height: 3)
        } else {
            Rectangle().fill(OurDaysTheme.border).frame(height: 3)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// Which of the two letters is being written, and its link once CloudKit has made it.
/// The sheet opens on the tap and the link fills in a few seconds later, so the id
/// stays put while `preparedShare` arrives.
struct PairingInviteDraft: Identifiable {
    let id = UUID()
    let isSendingBack: Bool
    var preparedShare: PreparedCloudShare?

    var shareURL: URL? { preparedShare?.share.url }
}

/// Presents the system share sheet from UIKit, because `ShareLink` cannot say whether
/// anything was actually sent: a link only counts as sent when the sheet completes.
@MainActor
enum ActivitySharePresenter {
    static func present(_ text: String, onCompleted: @escaping @MainActor () -> Void) {
        guard let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { @MainActor in onCompleted() }
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 80, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// Shown before the link leaves the phone. The link alone tells the other person
/// nothing, so this says what they need first and sends the link inside a message
/// that repeats it. Apple's sharing panel stays one tap away for managing people.
struct PairingInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let draft: PairingInviteDraft
    let partnerName: String?
    let onSent: () -> Void
    let onUseAppleSheet: () -> Void

    var body: some View {
        let strings = settings.strings
        let message = draft.shareURL.map {
            PairingInviteMessagePolicy.inviteMessage(shareURL: $0, isSendingBack: draft.isSendingBack, strings: strings)
        }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(strings.pairingInviteSheetCounter(isSendingBack: draft.isSendingBack))
                            .font(.caption)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                        Text(strings.pairingInviteSheetTitle(isSendingBack: draft.isSendingBack))
                            .font(OurDaysTheme.displayFont(28))
                            .foregroundStyle(OurDaysTheme.ink)
                        Text(strings.pairingInviteSheetMessage(isSendingBack: draft.isSendingBack, partnerName: partnerName))
                            .font(.subheadline)
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !draft.isSendingBack {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(strings.pairingInviteChecklistTitle)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OurDaysTheme.secondaryInk)
                            checklistRow(1, strings.pairingInviteChecklistInstall)
                            checklistRow(2, strings.pairingInviteChecklistICloud)
                            checklistRow(3, strings.pairingInviteChecklistWeChat)
                        }
                        .ourDaysCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(strings.pairingInvitePreviewTitle)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OurDaysTheme.secondaryInk)
                        Text(message ?? strings.pairingInvitePreparingLink)
                            .font(.subheadline)
                            .foregroundStyle(OurDaysIdentity.me.onTint)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 18,
                                    bottomLeadingRadius: 6,
                                    bottomTrailingRadius: 18,
                                    topTrailingRadius: 18,
                                    style: .continuous
                                )
                                .fill(OurDaysIdentity.me.tint)
                            )
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    Button {
                        guard let message else { return }
                        ActivitySharePresenter.present(message) {
                            onSent()
                            dismiss()
                        }
                    } label: {
                        if message == nil {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(strings.pairingInvitePreparingLink)
                            }
                        } else {
                            Label(strings.pairingInviteSendButton, systemImage: "paperplane")
                        }
                    }
                    .buttonStyle(OurDaysPrimaryButtonStyle())
                    .disabled(message == nil)
                    .accessibilityIdentifier("pairing-invite-send")

                    Button(strings.pairingInviteAppleSheetButton) {
                        onUseAppleSheet()
                        dismiss()
                    }
                    .disabled(draft.preparedShare == nil)
                    .font(.subheadline)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(OurDaysTheme.paper)
            }
            .background(OurDaysTheme.paper)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(strings.cancelButton) { dismiss() }
                }
            }
        }
    }

    private func checklistRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(OurDaysIdentity.partner.onTint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(OurDaysIdentity.partner.tint))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(OurDaysTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Right after I accept the partner's link: they can't see my calendar until I send
/// my own link back, which nothing used to say.
struct ShareBackPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let partnerName: String?
    let onSendBack: () -> Void
    let onLater: () -> Void

    var body: some View {
        let strings = settings.strings
        let state = PairingGuideState(role: .receiver, currentStep: .linkSentBack)

        VStack(spacing: 22) {
            HStack(spacing: 0) {
                MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: 64)
                Rectangle().fill(OurDaysIdentity.partner.color).frame(width: 56, height: 3)
                MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: 64)
            }
            .padding(.top, 28)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(strings.pairingGuideStepCounter(state.currentStep))
                    .font(.caption)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                Text(strings.shareBackPromptTitle(partnerName))
                    .font(OurDaysTheme.displayFont(26))
                    .foregroundStyle(OurDaysTheme.ink)
                    .multilineTextAlignment(.center)
                Text(strings.pairingGuideMessage(state, partnerName: partnerName))
                    .font(.subheadline)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(strings.shareBackPromptWhyTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                Text(strings.shareBackPromptWhyMessage)
                    .font(.subheadline)
                    .foregroundStyle(OurDaysTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ourDaysCard()

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Button {
                    onSendBack()
                    dismiss()
                } label: {
                    Label(strings.pairingGuideSendBackButton(partnerName), systemImage: "arrowshape.turn.up.left")
                }
                .buttonStyle(OurDaysPrimaryButtonStyle())
                .accessibilityIdentifier("share-back-prompt-send")

                Button(strings.shareBackPromptLaterButton) {
                    onLater()
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OurDaysTheme.paper)
        .interactiveDismissDisabled()
    }
}

/// "Link won't open?": the three ways an invite link ends up on the icloud.com page
/// that asks for a sign-in, and a message the inviter can forward.
struct InviteLinkHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(strings.inviteHelpTitle)
                        .font(OurDaysTheme.displayFont(26))
                        .foregroundStyle(OurDaysTheme.ink)
                    Text(strings.inviteHelpIntro)
                        .font(.subheadline)
                        .foregroundStyle(OurDaysTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    reasonCard(1, strings.inviteHelpSwitchTitle, strings.inviteHelpSwitchMessage)
                    reasonCard(2, strings.inviteHelpWeChatTitle, strings.inviteHelpWeChatMessage)
                    reasonCard(3, strings.inviteHelpInstallTitle, strings.inviteHelpInstallMessage)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: strings.inviteHelpShareMessage(appStoreURL: PairingInviteMessagePolicy.appStoreURL.absoluteString)) {
                    Label(strings.inviteHelpSendButton, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(OurDaysPrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(OurDaysTheme.paper)
            }
            .background(OurDaysTheme.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(strings.doneButton) { dismiss() }
                }
            }
        }
    }

    private func reasonCard(_ number: Int, _ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(number) · \(title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OurDaysTheme.ink)
            Text(message)
                .font(.footnote)
                .foregroundStyle(OurDaysTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ourDaysCard()
    }
}
