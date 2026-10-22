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
