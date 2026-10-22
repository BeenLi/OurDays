import CoreGraphics
import Foundation

/// Fixed palette for text avatars. Raw values are synced in `MemberProfile.avatarBackground`,
/// so never rename a case; unknown values decode as nil and fall back to the identity tint.
enum AvatarBackground: String, Codable, CaseIterable, Identifiable {
    case sand
    case teal
    case coral
    case sage
    case lavender
    case ink

    var id: String { rawValue }
}

/// A member's avatar: a small square JPEG, or a short text mark on a palette background.
/// `imageData` wins over `text` when both are present.
struct MemberAvatar: Codable, Equatable {
    var text: String?
    var background: AvatarBackground?
    var imageData: Data?

    init(text: String? = nil, background: AvatarBackground? = nil, imageData: Data? = nil) {
        self.text = text
        self.background = background
        self.imageData = imageData
    }
}

enum MemberAvatarPlan {
    /// Longest edge of a stored avatar photo, in pixels. Keeps the synced record small.
    static let imagePixelSize: CGFloat = 256

    /// "最多 3 个字母或 2 个汉字": ASCII-only marks keep 3 characters, anything wider keeps 2.
    static func normalizedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let limit = trimmed.allSatisfy(\.isASCII) ? 3 : 2
        return String(trimmed.prefix(limit))
    }

    /// Nil when the avatar carries nothing to draw, so callers fall back to initials.
    static func normalized(_ avatar: MemberAvatar?) -> MemberAvatar? {
        guard let avatar else { return nil }
        if let imageData = avatar.imageData, !imageData.isEmpty {
            return MemberAvatar(imageData: imageData)
        }
        guard let text = normalizedText(avatar.text) else { return nil }
        return MemberAvatar(text: text, background: avatar.background)
    }

    /// Same precedence as the partner's name: my local override > partner's synced avatar.
    static func resolvedPartnerAvatar(override: MemberAvatar?, synced: MemberAvatar?) -> MemberAvatar? {
        normalized(override) ?? normalized(synced)
    }

    /// Fallback mark drawn when no avatar is set: the first character of the display name.
    static func initials(from displayName: String?, fallback: String) -> String {
        guard let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              let first = trimmed.first else {
            return fallback
        }
        return String(first).uppercased()
    }
}

/// Placeholder member IDs used before the CloudKit identities are known.
enum MemberIDPlan {
    /// Placeholder member ID used until the CloudKit userRecordID is known
    /// (and permanently in LOCAL_SIGNING builds without CloudKit).
    static let unsyncedMemberID = "local-user"
    /// Placeholder owner ID for partner-owned local records created before the
    /// partner's CloudKit identity is known.
    static let unknownPartnerID = "partner"
}

/// Resolves a member ID (the CloudKit `_`-prefixed userRecordID) to a
/// human-readable nickname. Member IDs must never be shown raw in the UI.
enum MemberDisplayNamePlan {
    static func displayName(
        forMemberID memberID: String,
        currentMemberID: String,
        currentDisplayName: String?,
        selfFallback: String,
        partnerDisplayName: String
    ) -> String {
        if memberID == currentMemberID {
            return PairingSettingsPlan.normalizedDisplayName(currentDisplayName) ?? selfFallback
        }
        return partnerDisplayName
    }
}
