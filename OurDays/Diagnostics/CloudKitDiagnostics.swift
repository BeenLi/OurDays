import Foundation

struct CloudKitSharedReadDiagnostic {
    let sharedZoneCount: Int
    let eventMirrorCount: Int
    let commentCount: Int
    let invitationCount: Int
    let accessRequestCount: Int
    let errorDescription: String?

    var provesNoSharedCalendarReadAccess: Bool {
        errorDescription == nil
            && sharedZoneCount == 0
            && eventMirrorCount == 0
            && commentCount == 0
            && invitationCount == 0
            && accessRequestCount == 0
    }

    var displayText: String {
        var lines = [
            "Shared Zones: \(sharedZoneCount)",
            "EventMirror: \(eventMirrorCount)",
            "EventComment: \(commentCount)",
            "EventInvitation: \(invitationCount)",
            "CalendarAccessRequest: \(accessRequestCount)"
        ]
        if let errorDescription {
            lines.append("Error: \(errorDescription)")
        }
        return lines.joined(separator: "\n")
    }
}

struct CloudKitAccountDiagnostic {
    let expectedContainerIdentifier: String
    let expectedEnvironment: String
    let expectedZoneName: String
    let runtimeContainerIdentifier: String
    let accountStatus: String
    let userRecordName: String?
    let privateDatabaseStatus: String
    let errorDescription: String?

    var isAccountAvailable: Bool {
        accountStatus == "available"
    }

    var displayText: String {
        var lines = [
            "Expected:",
            "Container: \(expectedContainerIdentifier)",
            "Environment: \(expectedEnvironment)",
            "Zone: \(expectedZoneName)",
            "",
            "Runtime:",
            "Container: \(runtimeContainerIdentifier)",
            "Account: \(accountStatus)"
        ]
        if let userRecordName {
            lines.append("User Record: \(userRecordName)")
        }
        lines.append("Private Database: \(privateDatabaseStatus)")
        if let errorDescription {
            lines.append("Error: \(errorDescription)")
        }
        return lines.joined(separator: "\n")
    }
}

/// What a user can send us when Start Pairing fails. CloudKit's logs in the Console do
/// not show every account, and the error on screen is one line; this is everything the
/// device knows about the failure, as text to paste into a chat.
struct PairingShareFailureReport {
    struct Device: Equatable {
        var appVersion: String
        var appBuild: String
        var systemName: String
        var systemVersion: String
        var model: String
        var localeIdentifier: String
        var preferredLanguages: [String]
        var timeZoneIdentifier: String
    }

    var createdAt: Date
    var environment: String
    var device: Device
    var accountStatus: String
    var userRecordName: String?
    var hasUbiquityIdentity: Bool
    /// Names of the private zones, or the error that stopped the listing.
    var privateZones: String
    /// The share root as the server has it now: present or not, shared or not.
    var rootState: String
    /// `describeCloudKitFailure` of the failure the user saw.
    var failure: String
    /// One line per step of `CloudKitCoupleSpaceService.shareCreationProbe`.
    var probeLines: [String]

    var text: String {
        var lines = [
            "OurDays pairing report",
            "Time: \(ISO8601DateFormatter().string(from: createdAt))",
            "App: \(device.appVersion) (\(device.appBuild)) \(environment)",
            "System: \(device.systemName) \(device.systemVersion) · \(device.model)",
            "Locale: \(device.localeIdentifier) · \(device.preferredLanguages.joined(separator: ",")) · \(device.timeZoneIdentifier)",
            "Account: \(accountStatus) · ubiquityIdentity=\(hasUbiquityIdentity)",
            "User Record: \(userRecordName ?? "missing")",
            "Private Zones: \(privateZones)",
            "Root: \(rootState)",
            "",
            "Failure:",
            failure
        ]
        if !probeLines.isEmpty {
            lines.append("")
            lines.append("Share probe:")
            lines.append(contentsOf: probeLines)
        }
        return lines.joined(separator: "\n")
    }
}
