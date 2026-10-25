import PhotosUI
import SwiftUI

/// Edits one avatar: a photo, or up to three letters on a palette tint. The identity ring
/// stays fixed around the preview, because it is what tells the two people apart.
struct AvatarEditorSheet: View {
    private enum Mode: Hashable {
        case photo
        case text
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    let title: String
    let defaultAvatar: MemberAvatar?
    let fallbackText: String
    let identity: OurDaysIdentity
    let footnote: String
    let onSave: (MemberAvatar?) -> Void
    @State private var mode: Mode
    @State private var imageData: Data?
    @State private var text: String
    @State private var background: AvatarBackground
    @State private var isReset: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false

    init(
        title: String,
        avatar: MemberAvatar?,
        defaultAvatar: MemberAvatar? = nil,
        fallbackText: String,
        identity: OurDaysIdentity,
        footnote: String,
        onSave: @escaping (MemberAvatar?) -> Void
    ) {
        self.title = title
        self.defaultAvatar = defaultAvatar
        self.fallbackText = fallbackText
        self.identity = identity
        self.footnote = footnote
        self.onSave = onSave
        let normalized = MemberAvatarPolicy.normalized(avatar)
        _mode = State(initialValue: normalized?.imageData != nil ? .photo : .text)
        _imageData = State(initialValue: normalized?.imageData)
        _text = State(initialValue: normalized?.text ?? "")
        _background = State(initialValue: normalized?.background ?? (identity == .me ? .teal : .coral))
        _isReset = State(initialValue: normalized == nil)
    }

    /// What Done saves: nil means "no custom avatar", so the default shows again.
    private var draft: MemberAvatar? {
        guard !isReset else { return nil }
        switch mode {
        case .photo:
            return imageData.map { MemberAvatar(imageData: $0) }
        case .text:
            return MemberAvatarPolicy.normalized(MemberAvatar(text: text, background: background))
        }
    }

    var body: some View {
        let strings = settings.strings

        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    MemberAvatarView(
                        avatar: draft ?? defaultAvatar,
                        fallbackText: fallbackText,
                        identity: identity,
                        size: 132
                    )
                    .padding(.top, 8)

                    Picker("", selection: $mode) {
                        Text(strings.avatarPhotoTab).tag(Mode.photo)
                        Text(strings.avatarTextTab).tag(Mode.text)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Group {
                        switch mode {
                        case .photo:
                            photoContent(strings: strings)
                        case .text:
                            textContent(strings: strings)
                        }
                    }
                    .ourDaysCard()

                    Label {
                        Text(footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)

                    Button(strings.resetAvatarButton) {
                        isReset = true
                        imageData = nil
                        text = ""
                        pickerItem = nil
                    }
                    .buttonStyle(OurDaysSecondaryButtonStyle())
                    .disabled(isReset)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(OurDaysTheme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(strings.cancelButton) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(strings.doneButton) {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoadingPhoto)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                isLoadingPhoto = true
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    await MainActor.run {
                        isLoadingPhoto = false
                        if let data, let jpeg = AvatarImageRenderer.squareJPEG(from: data) {
                            imageData = jpeg
                            isReset = false
                        }
                    }
                }
            }
        }
    }

    private func photoContent(strings: ShareCalStrings) -> some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 10) {
                if isLoadingPhoto {
                    ProgressView()
                } else {
                    Image(systemName: "photo.on.rectangle")
                }
                Text(imageData == nil ? strings.choosePhotoButton : strings.changePhotoButton)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(OurDaysPrimaryButtonStyle())
    }

    private func textContent(strings: ShareCalStrings) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(strings.avatarTextLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                TextField(fallbackText, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(OurDaysTheme.border, lineWidth: 1)
                    )
                    .onChange(of: text) { _, newValue in
                        let limited = MemberAvatarPolicy.normalizedText(newValue) ?? ""
                        if limited != newValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                            text = limited
                        }
                        isReset = false
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(strings.avatarBackgroundLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                HStack {
                    ForEach(AvatarBackground.allCases) { option in
                        Button {
                            background = option
                            isReset = false
                        } label: {
                            Circle()
                                .fill(option.fill)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle().strokeBorder(
                                        option == background ? OurDaysTheme.ink : OurDaysTheme.border,
                                        lineWidth: option == background ? 2 : 1
                                    )
                                )
                                .overlay {
                                    if option == background {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(option.onFill)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(strings.avatarBackgroundName(option))
                        .accessibilityAddTraits(option == background ? .isSelected : [])
                        if option != AvatarBackground.allCases.last {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

/// Turns a picked photo into the stored avatar: center-cropped square, 256 px, JPEG.
enum AvatarImageRenderer {
    static func squareJPEG(from data: Data, compressionQuality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let targetSide = MemberAvatarPolicy.imagePixelSize
        let scale = targetSide / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (targetSide - drawSize.width) / 2, y: (targetSide - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide), format: format)
        return renderer.jpegData(withCompressionQuality: compressionQuality) { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
