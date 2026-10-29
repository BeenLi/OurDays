import SwiftUI

/// Tokens for the paper-and-two-lines look: a warm paper ground, ink text, and one
/// identity color per person (taken from the app icon's teal and coral). Every token
/// has a dark-mode twin so the system appearance keeps working.
enum OurDaysTheme {
    static let paper = Color(light: 0xF6F3EE, dark: 0x15161B)
    static let surface = Color(light: 0xFFFFFF, dark: 0x202128)
    static let sunken = Color(light: 0xEFEBE4, dark: 0x2B2C34)
    static let hairline = Color(light: 0xEEEAE3, dark: 0x30313A)
    static let border = Color(light: 0xE2DDD4, dark: 0x3A3B45)
    static let ink = Color(light: 0x1E2233, dark: 0xECEDF2)
    static let secondaryInk = Color(light: 0x5B6072, dark: 0xA3A7B5)
    /// Fill for primary buttons; `onInkFill` is the text on top of it.
    static let inkFill = Color(light: 0x1E2233, dark: 0xE9EAF0)
    static let onInkFill = Color(light: 0xFFFFFF, dark: 0x1E2233)
    /// Joint ("共同") events: the place where the two lines meet.
    static let joint = Color(light: 0x1E2233, dark: 0x3A4468)
    static let onJoint = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let onJointSecondary = Color(light: 0xC9CCD6, dark: 0xC9CCD6)
    static let destructive = Color(light: 0xB3283A, dark: 0xFF8592)

    static let cornerRadius: CGFloat = 20

    static func displayFont(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

enum OurDaysIdentity {
    case me
    case partner

    /// Rings, dots and avatar fallbacks.
    var color: Color {
        switch self {
        case .me: Color(light: 0x1F7A84, dark: 0x5CC3CC)
        case .partner: Color(light: 0xC93E4E, dark: 0xFF8592)
        }
    }

    /// Event blocks and chips.
    var tint: Color {
        switch self {
        case .me: Color(light: 0xE1F1F2, dark: 0x173A3E)
        case .partner: Color(light: 0xFBE6E8, dark: 0x4A1E25)
        }
    }

    /// Text drawn on `tint` (passes 4.5:1 on it).
    var onTint: Color {
        switch self {
        case .me: Color(light: 0x1A6871, dark: 0x8ED8DE)
        case .partner: Color(light: 0xB3283A, dark: 0xFFB0B9)
        }
    }
}

extension AvatarBackground {
    var fill: Color {
        switch self {
        case .sand: Color(light: 0xEFE6D6, dark: 0x4A4234)
        case .teal: OurDaysIdentity.me.tint
        case .coral: OurDaysIdentity.partner.tint
        case .sage: Color(light: 0xE3EEDF, dark: 0x2F3D2B)
        case .lavender: Color(light: 0xE9E6F5, dark: 0x37334D)
        case .ink: Color(light: 0x1E2233, dark: 0xE9EAF0)
        }
    }

    var onFill: Color {
        self == .ink ? Color(light: 0xFFFFFF, dark: 0x1E2233) : OurDaysTheme.ink
    }
}

struct OurDaysCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = OurDaysTheme.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: OurDaysTheme.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func ourDaysCard(padding: CGFloat = 16, fill: Color = OurDaysTheme.surface) -> some View {
        modifier(OurDaysCardModifier(padding: padding, fill: fill))
    }

    /// Paper ground behind a List/Form, with rows sitting on white cards.
    func ourDaysListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(OurDaysTheme.paper)
    }

    /// Paper behind the status bar on a tab whose navigation bar is hidden, so rows
    /// scrolled up slide under it instead of running into the clock.
    func ourDaysStatusBarCover() -> some View {
        // A zero-height inset sits right under the status bar; its background reaches
        // up into the safe area and covers exactly the status bar's height.
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(OurDaysTheme.paper.ignoresSafeArea(edges: .top))
        }
    }
}

struct OurDaysPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(OurDaysTheme.onInkFill)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .background(OurDaysTheme.inkFill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

struct OurDaysSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(OurDaysTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .background(OurDaysTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(OurDaysTheme.border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct OurDaysChip: View {
    let title: String
    var foreground: Color = OurDaysTheme.ink
    var background: Color = OurDaysTheme.sunken

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }
}

/// Small grey section label above a card group.
struct OurDaysSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.bold))
            .foregroundStyle(OurDaysTheme.secondaryInk)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Serif page title with an optional one-line subtitle above it, replacing the
/// default large navigation title so every tab opens the same way.
struct OurDaysPageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let subtitle {
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(OurDaysTheme.secondaryInk)
                    .lineLimit(1)
            }
            Text(title)
                .font(OurDaysTheme.displayFont(32))
                .foregroundStyle(OurDaysTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A member's avatar: photo, or text on a palette tint, or the name's first character on
/// the identity tint. The identity color always rings it, so a custom avatar never hides
/// whose event or comment it is.
struct MemberAvatarView: View {
    let avatar: MemberAvatar?
    let fallbackText: String
    let identity: OurDaysIdentity
    var size: CGFloat = 32

    private var ringWidth: CGFloat { size >= 80 ? 4 : (size >= 40 ? 2.5 : 2) }

    var body: some View {
        ZStack {
            Circle().fill(OurDaysTheme.surface)
            content
                .clipShape(Circle())
                .padding(size >= 80 ? ringWidth + 3 : ringWidth)
        }
        .overlay(Circle().stroke(identity.color, lineWidth: ringWidth))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        let normalized = MemberAvatarPolicy.normalized(avatar)
        if let imageData = normalized?.imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let text = normalized?.text {
            let background = normalized?.background
            ZStack {
                (background?.fill ?? identity.tint)
                Text(text)
                    .font(OurDaysTheme.displayFont(size * (text.count >= 3 ? 0.3 : 0.38)))
                    .foregroundStyle(background?.onFill ?? identity.onTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.08)
            }
        } else {
            ZStack {
                identity.tint
                Text(fallbackText)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(identity.onTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

extension SettingsStore {
    var myAvatarFallbackText: String {
        MemberAvatarPolicy.initials(from: currentDisplayName, fallback: strings.meTitle)
    }

    var partnerAvatarFallbackText: String {
        MemberAvatarPolicy.initials(from: partnerDisplayName, fallback: strings.partnerTitle)
    }
}

/// Avatar for whoever owns `memberID` (me or the partner), resolved from settings.
struct MemberAvatarForID: View {
    @Environment(SettingsStore.self) private var settings
    let memberID: String
    var size: CGFloat = 32

    var body: some View {
        if memberID == settings.currentMemberID {
            MemberAvatarView(avatar: settings.currentAvatar, fallbackText: settings.myAvatarFallbackText, identity: .me, size: size)
        } else {
            MemberAvatarView(avatar: settings.partnerAvatar, fallbackText: settings.partnerAvatarFallbackText, identity: .partner, size: size)
        }
    }
}

extension Color {
    /// A color that follows the system appearance, from two 0xRRGGBB literals.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }

        guard raw.count == 6, let value = Int(raw, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
