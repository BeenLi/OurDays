import CloudKit
import SwiftData
import UIKit
import XCTest

final class EventMirrorServiceTests: XCTestCase {
    func testBuildMirrorsOnlySelectedCalendarsAndUsesStableOccurrenceKey() {
        let occurrence = CalendarSourceEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            url: URL(string: "https://example.com")
        )
        let ignored = CalendarSourceEvent(
            eventIdentifier: "event-2",
            calendarIdentifier: "private",
            calendarTitle: "Private",
            calendarColorHex: "#FF006E",
            startDate: Date(timeIntervalSince1970: 4_000),
            endDate: Date(timeIntervalSince1970: 5_000),
            occurrenceStartDate: Date(timeIntervalSince1970: 4_000),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Hidden",
            location: nil,
            notes: nil,
            url: nil
        )

        let mirrors = EventMirrorService().makeMirrors(
            from: [occurrence, ignored],
            selectedCalendarIDs: ["work"],
            ownerMemberID: "me",
            visibility: .fullDetails
        )

        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors[0].ownerMemberID, "me")
        XCTAssertEqual(mirrors[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(mirrors[0].title, "Planning")
        XCTAssertEqual(mirrors[0].location, "Cafe")
        XCTAssertEqual(mirrors[0].notes, "Bring notes")
    }

    func testBusyOnlyVisibilityStripsSensitiveFieldsBeforeUpload() {
        let event = CalendarSourceEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Sensitive title",
            location: "Home",
            notes: "Sensitive note",
            url: URL(string: "https://example.com")
        )

        let mirror = EventMirrorService().makeMirrors(
            from: [event],
            selectedCalendarIDs: ["work"],
            ownerMemberID: "me",
            visibility: .busyOnly
        )[0]

        XCTAssertEqual(mirror.title, "Busy")
        XCTAssertNil(mirror.location)
        XCTAssertNil(mirror.notes)
        XCTAssertNil(mirror.urlString)
    }

    func testDetectDeletedLocalEventsCreatesTombstones() {
        let shadow = LocalEventShadow(
            localEventIdentifier: "event-1",
            calendarIdentifier: "work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            fingerprint: "old",
            cloudKitRecordName: "record-1",
            lastUploadedAt: Date(timeIntervalSince1970: 2_000),
            isTombstone: false
        )

        let tombstones = EventMirrorService().deletedShadows(
            existingEventKeys: [],
            shadows: [shadow]
        )

        XCTAssertEqual(tombstones.map(\.cloudKitRecordName), ["record-1"])
        XCTAssertTrue(tombstones[0].isTombstone)
    }

    func testBuildsLocalEventShadowsForUploadedMirrors() {
        let event = CalendarSourceEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            url: URL(string: "https://example.com")
        )

        let shadows = EventMirrorService().makeShadows(
            from: [event],
            selectedCalendarIDs: ["work"],
            uploadedAt: Date(timeIntervalSince1970: 5_000)
        )

        XCTAssertEqual(shadows.count, 1)
        XCTAssertEqual(shadows[0].id, "work:event-1:1800")
        XCTAssertEqual(shadows[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(shadows[0].cloudKitRecordName, "work:event-1:1800")
        XCTAssertEqual(shadows[0].lastUploadedAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertFalse(shadows[0].isTombstone)
    }

    func testDeletedLocalEventProducesDeletedMirrorTombstone() {
        let deletedAt = Date(timeIntervalSince1970: 6_000)
        let existingMirror = EventMirror(
            id: "work:event-1:1800",
            ownerMemberID: "me",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            urlString: "https://example.com",
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "record-1"
        )
        let deletedShadow = LocalEventShadow(
            id: "work:event-1:1800",
            localEventIdentifier: "event-1",
            calendarIdentifier: "work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            fingerprint: "old",
            cloudKitRecordName: "record-1",
            lastUploadedAt: Date(timeIntervalSince1970: 5_000),
            isTombstone: true
        )

        let tombstones = EventMirrorService().deletedMirrorTombstones(
            for: [deletedShadow],
            existingMirrors: [existingMirror],
            deletedAt: deletedAt
        )

        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(tombstones[0].title, "Planning")
        XCTAssertEqual(tombstones[0].cloudKitRecordName, "record-1")
        XCTAssertEqual(tombstones[0].deletedAt, deletedAt)
    }

    func testMissingLocalMirrorProducesDeletedTombstoneEvenWithoutShadow() {
        let deletedAt = Date(timeIntervalSince1970: 6_000)
        let existingMirror = EventMirror(
            id: "work:event-1:1800",
            ownerMemberID: "me",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            urlString: nil,
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "record-1"
        )

        let tombstones = EventMirrorService().deletedMirrorTombstones(
            existingEventKeys: [],
            existingMirrors: [existingMirror],
            selectedCalendarIDs: ["work"],
            syncWindow: DateInterval(start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 5_000)),
            deletedAt: deletedAt
        )

        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones[0].mirrorKey, "work:event-1:1800")
        XCTAssertEqual(tombstones[0].deletedAt, deletedAt)
    }

    func testFiltersMirrorsAndShadowsToAllowedSharingWindows() {
        let pairingDate = Date(timeIntervalSince1970: 100_000)
        let window = CalendarSharingWindowPlan.defaultWindows(now: pairingDate)[0]
        let oldEvent = calendarEvent(id: "old", startDate: pairingDate.addingTimeInterval(-60))
        let pairedDayEvent = calendarEvent(id: "paired-day", startDate: pairingDate.addingTimeInterval(60))
        let futureEvent = calendarEvent(id: "future", startDate: pairingDate.addingTimeInterval(10 * 24 * 60 * 60))

        let mirrors = EventMirrorService().makeMirrors(
            from: [oldEvent, pairedDayEvent, futureEvent],
            selectedCalendarIDs: ["work"],
            ownerMemberID: "me",
            visibility: .fullDetails,
            sharingWindows: [window]
        )
        let shadows = EventMirrorService().makeShadows(
            from: [oldEvent, pairedDayEvent, futureEvent],
            selectedCalendarIDs: ["work"],
            uploadedAt: pairingDate,
            sharingWindows: [window]
        )

        XCTAssertEqual(mirrors.map(\.title), ["paired-day", "future"])
        XCTAssertEqual(shadows.map(\.localEventIdentifier), ["paired-day", "future"])
    }

    func testBuildsHardDeleteRecordNamesForOutOfWindowMirrorsWithoutTombstones() {
        let pairingDate = Date(timeIntervalSince1970: 100_000)
        let allowed = CalendarSharingWindowPlan.defaultWindows(now: pairingDate)
        let oldMirror = eventMirror(
            id: "old",
            ownerMemberID: "me",
            startDate: pairingDate.addingTimeInterval(-60),
            cloudKitRecordName: "old-record"
        )
        let pairedDayMirror = eventMirror(
            id: "paired-day",
            ownerMemberID: "me",
            startDate: pairingDate.addingTimeInterval(60),
            cloudKitRecordName: "paired-day-record"
        )

        let stale = EventMirrorService().mirrorsOutsideSharingWindows(
            [oldMirror, pairedDayMirror],
            sharingWindows: allowed
        )

        XCTAssertEqual(stale.map(\.cloudKitRecordName), ["old-record"])
        XCTAssertNil(stale[0].deletedAt)
        XCTAssertEqual(stale[0].title, "old")
    }

    private func calendarEvent(id: String, startDate: Date) -> CalendarSourceEvent {
        CalendarSourceEvent(
            eventIdentifier: id,
            calendarIdentifier: "work",
            calendarTitle: "Work",
            calendarColorHex: "#3A86FF",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            occurrenceStartDate: startDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: id,
            location: nil,
            notes: nil,
            url: nil
        )
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        startDate: Date,
        cloudKitRecordName: String
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: id,
            location: "Private",
            notes: "Sensitive",
            urlString: nil,
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: cloudKitRecordName
        )
    }
}

final class CalendarSharingWindowPlanTests: XCTestCase {
    func testDefaultWindowSharesFromPairingDateToDistantFuture() {
        let pairingDate = Date(timeIntervalSince1970: 1_000_000)

        let windows = CalendarSharingWindowPlan.defaultWindows(now: pairingDate)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].start, pairingDate)
        XCTAssertEqual(windows[0].end, Date.distantFuture)
        XCTAssertFalse(CalendarSharingWindowPlan.contains(pairingDate.addingTimeInterval(-60), in: windows))
        XCTAssertTrue(CalendarSharingWindowPlan.contains(pairingDate.addingTimeInterval(60), in: windows))
    }

    func testApprovedRequestsExpandEffectiveWindowsForRequestedOwnerOnly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let pairingDate = now.addingTimeInterval(-10 * 24 * 60 * 60)
        let approvedStart = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let approvedEnd = now.addingTimeInterval(-20 * 24 * 60 * 60)
        let approved = CalendarAccessRequest(
            requesterMemberID: "partner",
            ownerMemberID: "me",
            requestedStartDate: approvedStart,
            requestedEndDate: approvedEnd,
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue
        )
        let pending = CalendarAccessRequest(
            requesterMemberID: "partner",
            ownerMemberID: "me",
            requestedStartDate: now.addingTimeInterval(-60 * 24 * 60 * 60),
            requestedEndDate: now.addingTimeInterval(-50 * 24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue
        )
        let otherOwner = CalendarAccessRequest(
            requesterMemberID: "partner",
            ownerMemberID: "someone-else",
            requestedStartDate: now.addingTimeInterval(-90 * 24 * 60 * 60),
            requestedEndDate: now.addingTimeInterval(-80 * 24 * 60 * 60),
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue
        )

        let windows = CalendarSharingWindowPlan.effectiveWindows(
            now: pairingDate,
            accessRequests: [approved, pending, otherOwner],
            ownerMemberID: "me"
        )

        XCTAssertTrue(CalendarSharingWindowPlan.contains(approvedStart.addingTimeInterval(60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPlan.contains(now.addingTimeInterval(-55 * 24 * 60 * 60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPlan.contains(now.addingTimeInterval(-85 * 24 * 60 * 60), in: windows))
        XCTAssertTrue(CalendarSharingWindowPlan.contains(now.addingTimeInterval(30 * 24 * 60 * 60), in: windows))
        XCTAssertFalse(CalendarSharingWindowPlan.contains(pairingDate.addingTimeInterval(-60), in: windows))
    }

    func testEnclosingIntervalUsesEarliestStartAndLatestEnd() {
        let first = DateInterval(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20))
        let second = DateInterval(start: Date(timeIntervalSince1970: -10), end: Date(timeIntervalSince1970: 30))

        let enclosing = CalendarSharingWindowPlan.enclosingInterval(for: [first, second])

        XCTAssertEqual(enclosing.start, Date(timeIntervalSince1970: -10))
        XCTAssertEqual(enclosing.end, Date(timeIntervalSince1970: 30))
    }
}

final class ShareCalCalendarBootstrapPlanTests: XCTestCase {
    func testOffersCreationWhenShareCalCalendarIsMissing() {
        let calendars = [
            CalendarDescriptor(id: "work", title: "Work", colorHex: "#3A86FF", allowsContentModifications: true)
        ]

        XCTAssertTrue(ShareCalCalendarBootstrapPlan.shouldOfferCreation(calendars: calendars))
    }

    func testDoesNotOfferCreationWhenWritableShareCalCalendarExists() {
        let calendars = [
            CalendarDescriptor(id: "sharecal", title: "ShareCal", colorHex: "#FF2D55", allowsContentModifications: true)
        ]

        XCTAssertFalse(ShareCalCalendarBootstrapPlan.shouldOfferCreation(calendars: calendars))
    }

    func testSelectsEnsuredShareCalCalendar() {
        let selected = ShareCalCalendarBootstrapPlan.selectedCalendarIDs(
            afterEnsuring: CalendarDescriptor(id: "sharecal", title: "ShareCal", colorHex: "#FF2D55", allowsContentModifications: true),
            currentSelection: ["work"]
        )

        XCTAssertEqual(selected, ["sharecal", "work"])
    }
}

final class CalendarMirrorVisibilityPlanTests: XCTestCase {
    func testShowsOnlyCurrentMemberAndStablePartnerOwnerMirrors() {
        let current = mirror(owner: "me", key: "current")
        let sharedOwner = mirror(owner: "icloud-owner", key: "shared-owner")
        let partnerNickname = mirror(owner: "yoki", key: "partner-nickname")
        let staleNickname = mirror(owner: "partner", key: "stale-nickname")
        let stranger = mirror(owner: "someone-else", key: "stranger")

        let visible = CalendarMirrorVisibilityPlan.memberMirrors(
            [current, sharedOwner, partnerNickname, staleNickname, stranger],
            currentMemberID: "me",
            partnerShareOwnerID: "icloud-owner"
        )

        XCTAssertEqual(visible.map(\.mirrorKey), ["current", "shared-owner"])
    }

    func testHidesPartnerMirrorsWhenStablePartnerOwnerIsUnknown() {
        let current = mirror(owner: "me", key: "current")
        let partnerNickname = mirror(owner: "yoki", key: "partner-nickname")

        let visible = CalendarMirrorVisibilityPlan.memberMirrors(
            [current, partnerNickname],
            currentMemberID: "me",
            partnerShareOwnerID: nil
        )

        XCTAssertEqual(visible.map(\.mirrorKey), ["current"])
    }

    private func mirror(owner: String, key: String) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: owner,
            mirrorKey: key,
            sourceCalendarID: "calendar",
            sourceCalendarTitle: "Calendar",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_000),
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: key,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: key
        )
    }
}

final class ICloudSharingIdentityDisplayPlanTests: XCTestCase {
    func testDisplaysUniqueEmailAddressesForReadableICloudIdentity() {
        let value = ICloudSharingIdentityDisplayPlan.displayValue(
            for: [" partner@example.com ", "partner@example.com", "other@icloud.com"],
            emptyValue: "Not connected"
        )

        XCTAssertEqual(value, "partner@example.com, other@icloud.com")
    }

    func testHidesInternalOwnerNamesFromReadableICloudIdentity() {
        let value = ICloudSharingIdentityDisplayPlan.displayValue(
            for: [" _ee39c883ba88010c4ea25fd9a273af8d ", "+8613069043940", "not-an-email"],
            emptyValue: "Not connected"
        )

        XCTAssertEqual(value, "Not connected")
    }

    func testDisplaysEmptyValueWhenStableSharingIdentifierIsMissing() {
        let value = ICloudSharingIdentityDisplayPlan.displayValue(
            for: [nil, " ", ""].compactMap { $0 },
            emptyValue: "Not connected"
        )

        XCTAssertEqual(value, "Not connected")
    }
}

final class ICloudSharingTeardownPlanTests: XCTestCase {
    func testPurgesStableOwnerAndLegacyPartnerNicknameIDs() {
        let ownerIDs = ICloudSharingTeardownPlan.localOwnerIDsToPurge(
            partnerShareOwnerID: "icloud-owner",
            legacyPartnerMemberID: " yoki "
        )

        XCTAssertEqual(ownerIDs, ["icloud-owner", "partner", "yoki"])
    }

    func testDoesNotUseEmptyLegacyPartnerNicknameAsOwnerID() {
        let ownerIDs = ICloudSharingTeardownPlan.localOwnerIDsToPurge(
            partnerShareOwnerID: nil,
            legacyPartnerMemberID: " "
        )

        XCTAssertEqual(ownerIDs, ["partner"])
    }
}

final class PairingSettingsPlanTests: XCTestCase {
    func testReportsNotPairedWhenNoPairingSignalsExist() {
        XCTAssertEqual(
            PairingSettingsPlan.status(
                hasStartedPairing: false,
                outgoingParticipantIDs: [],
                incomingOwnerID: nil
            ),
            .notPaired
        )
    }

    func testReportsWaitingForPartnerAfterStartingOutgoingShare() {
        XCTAssertEqual(
            PairingSettingsPlan.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: [],
                incomingOwnerID: nil
            ),
            .waitingForPartner
        )
    }

    func testReportsWaitingForPartnerToShareAfterOutgoingShareIsAccepted() {
        XCTAssertEqual(
            PairingSettingsPlan.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: ["partner@example.com"],
                incomingOwnerID: nil
            ),
            .waitingForPartnerToShare
        )
    }

    func testReportsWaitingForYouToShareWhenOnlyIncomingShareIsAvailable() {
        XCTAssertEqual(
            PairingSettingsPlan.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: [],
                incomingOwnerID: "icloud-owner"
            ),
            .waitingForYouToShare
        )
    }

    func testReportsPairedOnlyWhenIncomingAndOutgoingSharesAreAvailable() {
        XCTAssertEqual(
            PairingSettingsPlan.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: ["partner@example.com"],
                incomingOwnerID: "icloud-owner"
            ),
            .paired
        )
    }

    func testBuildsOutgoingAndIncomingCalendarStatuses() {
        XCTAssertEqual(
            PairingSettingsPlan.outgoingStatus(hasStartedPairing: false, outgoingParticipantIDs: []),
            .off
        )
        XCTAssertEqual(
            PairingSettingsPlan.outgoingStatus(hasStartedPairing: true, outgoingParticipantIDs: []),
            .waitingForPartner
        )
        XCTAssertEqual(
            PairingSettingsPlan.outgoingStatus(hasStartedPairing: true, outgoingParticipantIDs: ["icloud-owner"]),
            .on
        )
        XCTAssertEqual(PairingSettingsPlan.incomingStatus(incomingOwnerID: nil), .unavailable)
        XCTAssertEqual(PairingSettingsPlan.incomingStatus(incomingOwnerID: "icloud-owner"), .on)
    }

    func testPartnerIdentityShowsReadableEmailAndHidesInternalOwnerName() {
        XCTAssertEqual(
            PairingSettingsPlan.partnerIdentity(
                incomingOwnerID: " icloud-owner ",
                outgoingParticipantIDs: ["partner@example.com"],
                partnerICloudEmailAddresses: [" partner@icloud.com "],
                emptyValue: "Not connected"
            ),
            "partner@icloud.com"
        )
        XCTAssertEqual(
            PairingSettingsPlan.partnerIdentity(
                incomingOwnerID: " _ee39c883ba88010c4ea25fd9a273af8d ",
                outgoingParticipantIDs: [" _participantRecordName "],
                partnerICloudEmailAddresses: [],
                emptyValue: "Not connected"
            ),
            "Not connected"
        )
    }
}

final class PairingDatePlanTests: XCTestCase {
    func testNormalizesPairingDateToStartOfDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 19, minute: 30)))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))

        XCTAssertEqual(PairingDatePlan.normalizedPairingDate(date, calendar: calendar), expected)
    }

    func testPairingDayCountUsesCalendarDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let pairingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let sameDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 23)))
        let laterDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 1)))

        XCTAssertEqual(PairingDatePlan.dayCount(since: pairingDate, now: sameDay, calendar: calendar), 0)
        XCTAssertEqual(PairingDatePlan.dayCount(since: pairingDate, now: laterDate, calendar: calendar), 3)
    }

    func testDefaultHistoryRequestRangeEndsBeforePairingDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let pairingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))

        let range = PairingDatePlan.defaultHistoryRequestRange(pairingDate: pairingDate, calendar: calendar)

        XCTAssertEqual(range.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9))))
        XCTAssertEqual(range.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7))))
    }
}

final class AppLanguageSettingsTests: XCTestCase {
    func testDefaultsToEnglishWhenNoPreferenceExists() {
        let suiteName = "AppLanguageSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let language = AppLanguagePreference.read(from: defaults)

        XCTAssertEqual(language, .english)
    }

    func testPersistsSelectedChineseLanguage() {
        let suiteName = "AppLanguageSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguagePreference.write(.chinese, to: defaults)

        let language = AppLanguagePreference.read(from: defaults)

        XCTAssertEqual(language, .chinese)
    }

}

final class ShareCalStringsTests: XCTestCase {
    func testEnglishKeepsCurrentPrimaryLabels() {
        let strings = ShareCalStrings(language: .english)

        XCTAssertEqual(strings.calendarTab, "Calendar")
        XCTAssertEqual(strings.invitesTab, "Invites")
        XCTAssertEqual(strings.settingsTitle, "Settings")
        XCTAssertEqual(strings.profileSection, "Profile")
        XCTAssertEqual(strings.myNicknameLabel, "My Nickname")
        XCTAssertEqual(strings.partnerNicknameEditLabel, "Partner Note")
        XCTAssertEqual(strings.memberColumnTitle(baseTitle: strings.meTitle, nickname: "partner"), "Me (partner)")
        XCTAssertEqual(strings.memberColumnTitle(baseTitle: strings.partnerTitle, nickname: "yoki"), "Partner (yoki)")
        XCTAssertEqual(strings.memberColumnTitle(baseTitle: strings.partnerTitle, nickname: " "), "Partner")
        XCTAssertEqual(strings.pairingSection, "Pairing")
        XCTAssertEqual(strings.pairingStatusTitle(for: .notPaired), "Not Paired")
        XCTAssertEqual(strings.pairingStatusTitle(for: .waitingForPartner), "Waiting for Partner")
        XCTAssertEqual(strings.pairingStatusTitle(for: .waitingForPartnerToShare), "Waiting for Partner to Share")
        XCTAssertEqual(strings.pairingStatusTitle(for: .waitingForYouToShare), "Waiting for You to Share")
        XCTAssertEqual(strings.pairingStatusTitle(for: .paired), "Paired")
        XCTAssertEqual(
            strings.pairingWaitingForYouToShareDescription,
            "You've accepted your partner's share. Share your calendar back to complete pairing."
        )
        XCTAssertEqual(strings.pairingPartnerLabel, "Pairing Partner")
        XCTAssertEqual(strings.partnerNicknameLabel, "Nickname")
        XCTAssertEqual(strings.partnerICloudIdentityLabel, "iCloud Identity")
        XCTAssertEqual(strings.sharingMyCalendarLabel, "Sharing My Calendar")
        XCTAssertEqual(strings.partnersCalendarLabel, "Partner's Calendar")
        XCTAssertEqual(strings.startPairingButton(isPreparing: false), "Start Pairing")
        XCTAssertEqual(strings.defaultVisibilityLabel(for: .fullDetails), "Full details")
        XCTAssertEqual(strings.noICloudSharingIdentity, "Not connected")
        XCTAssertEqual(strings.unpairButton, "Unpair")
        XCTAssertEqual(strings.deleteICloudDataButton, "Delete My iCloud Data")
        XCTAssertEqual(strings.deleteICloudDataSucceeded, "iCloud data deleted.")
    }

    func testChineseProvidesPrimaryLabels() {
        let strings = ShareCalStrings(language: .chinese)

        XCTAssertEqual(strings.calendarTab, "日历")
        XCTAssertEqual(strings.invitesTab, "邀请")
        XCTAssertEqual(strings.settingsTitle, "设置")
        XCTAssertEqual(strings.profileSection, "个人资料")
        XCTAssertEqual(strings.myNicknameLabel, "我的昵称")
        XCTAssertEqual(strings.partnerNicknameEditLabel, "对方备注名")
        XCTAssertEqual(strings.memberColumnTitle(baseTitle: strings.meTitle, nickname: "partner"), "我（partner）")
        XCTAssertEqual(strings.memberColumnTitle(baseTitle: strings.partnerTitle, nickname: "yoki"), "对方（yoki）")
        XCTAssertEqual(strings.memberColumnTitle(baseTitle: strings.partnerTitle, nickname: " "), "对方")
        XCTAssertEqual(strings.pairingSection, "配对")
        XCTAssertEqual(strings.pairingStatusTitle(for: .notPaired), "未配对")
        XCTAssertEqual(strings.pairingStatusTitle(for: .waitingForPartner), "等待对方接受")
        XCTAssertEqual(strings.pairingStatusTitle(for: .waitingForPartnerToShare), "等待对方共享")
        XCTAssertEqual(strings.pairingStatusTitle(for: .waitingForYouToShare), "等待你共享")
        XCTAssertEqual(strings.pairingStatusTitle(for: .paired), "已配对")
        XCTAssertEqual(
            strings.pairingWaitingForYouToShareDescription,
            "你已接收对方共享。请把你的日历共享给对方以完成配对。"
        )
        XCTAssertEqual(strings.pairingPartnerLabel, "配对对象")
        XCTAssertEqual(strings.partnerNicknameLabel, "昵称")
        XCTAssertEqual(strings.partnerICloudIdentityLabel, "iCloud 身份")
        XCTAssertEqual(strings.sharingMyCalendarLabel, "我共享给对方")
        XCTAssertEqual(strings.partnersCalendarLabel, "对方共享给我")
        XCTAssertEqual(strings.startPairingButton(isPreparing: false), "发起配对")
        XCTAssertEqual(strings.defaultVisibilityLabel(for: .fullDetails), "完整详情")
        XCTAssertEqual(strings.noICloudSharingIdentity, "未连接")
        XCTAssertEqual(strings.unpairButton, "解除配对")
        XCTAssertEqual(strings.deleteICloudDataButton, "删除我的 iCloud 数据")
        XCTAssertEqual(strings.deleteICloudDataSucceeded, "iCloud 数据已删除。")
    }
}

final class ShareCalSmokeTestEventPlanTests: XCTestCase {
    func testBuildsStableShortEventDraftNearNow() {
        let now = Date(timeIntervalSince1970: 2_000)
        let draft = ShareCalSmokeTestEventPlan.draft(now: now)

        XCTAssertEqual(draft.title, "ShareCal E2E Smoke Test")
        XCTAssertEqual(draft.startDate, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(draft.endDate, now.addingTimeInterval(45 * 60))
        XCTAssertFalse(draft.isAllDay)
        XCTAssertEqual(draft.notes, "Created by ShareCal simulator validation.")
    }

    func testUsesCustomLaunchSeedTitleWhenProvided() {
        let title = ShareCalLaunchDiagnosticPlan.seedCalendarEventTitle(
            arguments: [
                "ShareCal",
                "-ShareCalSeedCalendarEvent",
                "-ShareCalSeedCalendarEventTitle",
                "Owner bidirectional event"
            ]
        )

        XCTAssertEqual(title, "Owner bidirectional event")
    }
}

final class DayTimelineLayoutPlanTests: XCTestCase {
    func testProvidesTwentyFourAlignedHourMarks() {
        let marks = DayTimelineLayoutPlan.hourMarks(hourHeight: 60)

        XCTAssertEqual(marks.count, 24)
        XCTAssertEqual(marks.first?.hour, 0)
        XCTAssertEqual(marks.first?.y, 0)
        XCTAssertEqual(marks.last?.hour, 23)
        XCTAssertEqual(marks.last?.y, 23 * 60)
        XCTAssertEqual(DayTimelineLayoutPlan.dayHeight(hourHeight: 60), 24 * 60)
    }

    func testPositionsEventByMinutesSinceStartOfDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let start = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 30, second: 0, of: dayStart))
        let end = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 45, second: 0, of: dayStart))

        let frame = DayTimelineLayoutPlan.eventFrame(
            startDate: start,
            endDate: end,
            dayStart: dayStart,
            hourHeight: 48
        )

        XCTAssertEqual(frame.y, 9.5 * 48, accuracy: 0.001)
        XCTAssertEqual(frame.height, 1.25 * 48, accuracy: 0.001)
    }

    func testClampsEventFrameToVisibleDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let start = dayStart.addingTimeInterval(-30 * 60)
        let end = dayStart.addingTimeInterval(90 * 60)

        let frame = DayTimelineLayoutPlan.eventFrame(
            startDate: start,
            endDate: end,
            dayStart: dayStart,
            hourHeight: 60
        )

        XCTAssertEqual(frame.y, 0, accuracy: 0.001)
        XCTAssertEqual(frame.height, 90, accuracy: 0.001)
    }
}

final class JointSchedulePlanTests: XCTestCase {
    func testAcceptedInvitationCreatesJointEventForBothMembers() {
        let invitation = EventInvitation(
            id: "invite-1",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: "Bistro",
            notes: "Window seat",
            statusRawValue: InvitationStatus.accepted.rawValue
        )

        let jointEvents = JointSchedulePlan.jointEvents(
            from: [invitation],
            currentMemberID: "me",
            partnerMemberID: "partner"
        )

        XCTAssertEqual(jointEvents.count, 1)
        XCTAssertEqual(jointEvents[0].id, "invite-1")
        XCTAssertEqual(jointEvents[0].title, "Dinner")
        XCTAssertEqual(jointEvents[0].calendarTitle, "ShareCal")
        XCTAssertEqual(jointEvents[0].startDate, Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(jointEvents[0].endDate, Date(timeIntervalSince1970: 12_000))
    }

    func testOrdinaryMirrorsMatchingAcceptedJointEventAreHiddenFromSplitColumns() {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = Date(timeIntervalSince1970: 12_000)
        let jointEvent = JointScheduleEvent(
            id: "invite-1",
            title: "Dinner",
            startDate: start,
            endDate: end,
            isAllDay: false,
            location: nil,
            notes: nil
        )
        let myCopy = eventMirror(id: "my-copy", ownerMemberID: "me", title: "Dinner", startDate: start, endDate: end)
        let partnerCopy = eventMirror(id: "partner-copy", ownerMemberID: "partner", title: "Dinner", startDate: start, endDate: end)
        let unrelated = eventMirror(
            id: "unrelated",
            ownerMemberID: "me",
            title: "Focus",
            startDate: Date(timeIntervalSince1970: 20_000),
            endDate: Date(timeIntervalSince1970: 21_000)
        )

        let ordinary = JointSchedulePlan.ordinaryMirrors(
            [myCopy, partnerCopy, unrelated],
            excluding: [jointEvent]
        )

        XCTAssertEqual(ordinary.map(\.id), ["unrelated"])
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: id
        )
    }
}

final class AcceptedInvitationMirrorPlanTests: XCTestCase {
    func testCreatesCurrentMemberShareCalMirrorForAcceptedInvitation() {
        let invitation = EventInvitation(
            id: "invite-1",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            isAllDay: false,
            location: "Bistro",
            notes: "Window seat",
            statusRawValue: InvitationStatus.accepted.rawValue
        )
        let createdEvent = CreatedCalendarEvent(
            eventIdentifier: "local-1",
            calendarIdentifier: "sharecal-calendar",
            calendarTitle: "ShareCal",
            calendarColorHex: "#FF2D55"
        )

        let mirror = AcceptedInvitationMirrorPlan.mirror(
            from: invitation,
            createdEvent: createdEvent,
            ownerMemberID: "partner",
            timeZoneIdentifier: "Asia/Singapore"
        )

        XCTAssertEqual(mirror.ownerMemberID, "partner")
        XCTAssertEqual(mirror.mirrorKey, "sharecal-calendar:local-1:10000")
        XCTAssertEqual(mirror.id, mirror.mirrorKey)
        XCTAssertEqual(mirror.sourceCalendarID, "sharecal-calendar")
        XCTAssertEqual(mirror.sourceCalendarTitle, "ShareCal")
        XCTAssertEqual(mirror.calendarColorHex, "#FF2D55")
        XCTAssertEqual(mirror.title, "Dinner")
        XCTAssertEqual(mirror.startDate, Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(mirror.endDate, Date(timeIntervalSince1970: 12_000))
        XCTAssertEqual(mirror.location, "Bistro")
        XCTAssertEqual(mirror.notes, "Window seat")
        XCTAssertEqual(mirror.visibility, .fullDetails)
        XCTAssertNil(mirror.deletedAt)
        XCTAssertEqual(mirror.cloudKitRecordName, mirror.mirrorKey)
    }
}

final class DayTimelineJointLayoutPlanTests: XCTestCase {
    func testAssignsOverlappingJointEventsToSeparateColumns() {
        let first = jointEvent(
            id: "first",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000)
        )
        let second = jointEvent(
            id: "second",
            startDate: Date(timeIntervalSince1970: 11_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )
        let third = jointEvent(
            id: "third",
            startDate: Date(timeIntervalSince1970: 13_000),
            endDate: Date(timeIntervalSince1970: 14_000)
        )

        let placements = DayTimelineJointLayoutPlan.placements(for: [first, second, third])

        XCTAssertEqual(placements["first"], DayTimelineJointPlacement(columnIndex: 0, columnCount: 2))
        XCTAssertEqual(placements["second"], DayTimelineJointPlacement(columnIndex: 1, columnCount: 2))
        XCTAssertEqual(placements["third"], DayTimelineJointPlacement(columnIndex: 0, columnCount: 1))
    }

    private func jointEvent(id: String, startDate: Date, endDate: Date) -> JointScheduleEvent {
        JointScheduleEvent(
            id: id,
            title: id,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            location: nil,
            notes: nil
        )
    }
}

final class InvitationConflictPlanTests: XCTestCase {
    func testFindsOnlyOverlappingPartnerEvents() {
        let candidate = eventMirror(
            id: "candidate",
            ownerMemberID: "me",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000)
        )
        let partnerOverlap = eventMirror(
            id: "partner-overlap",
            ownerMemberID: "partner",
            title: "Gym",
            startDate: Date(timeIntervalSince1970: 11_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )
        let partnerBoundary = eventMirror(
            id: "partner-boundary",
            ownerMemberID: "partner",
            title: "No overlap",
            startDate: Date(timeIntervalSince1970: 12_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )
        let myOverlap = eventMirror(
            id: "my-overlap",
            ownerMemberID: "me",
            title: "Focus",
            startDate: Date(timeIntervalSince1970: 11_000),
            endDate: Date(timeIntervalSince1970: 13_000)
        )

        let conflicts = InvitationConflictPlan.conflicts(
            for: candidate,
            partnerMemberID: "partner",
            mirrors: [partnerOverlap, partnerBoundary, myOverlap]
        )

        XCTAssertEqual(conflicts.map(\.id), ["partner-overlap"])
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: id
        )
    }
}

final class CloudKitRecordMappingTests: XCTestCase {
    func testEventMirrorRoundTripsThroughCloudKitRecord() throws {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let mirror = EventMirror(
            ownerMemberID: "me",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            urlString: "https://example.com",
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "mirror-record"
        )

        let record = EventMirrorRecordMapper.record(from: mirror, zoneID: zoneID)
        let decoded = try EventMirrorRecordMapper.eventMirror(from: record)

        XCTAssertEqual(record.recordType, "EventMirror")
        XCTAssertEqual(record.recordID.recordName, "mirror-record")
        XCTAssertEqual(decoded.mirrorKey, mirror.mirrorKey)
        XCTAssertEqual(decoded.title, "Planning")
        XCTAssertEqual(decoded.urlString, "https://example.com")
    }

    func testEventMirrorRecordCanBeParentedToShareRoot() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let rootRecordID = CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        let mirror = EventMirror(
            ownerMemberID: "me",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            urlString: "https://example.com",
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "mirror-record"
        )

        let record = EventMirrorRecordMapper.record(from: mirror, zoneID: zoneID, parentRecordID: rootRecordID)

        XCTAssertEqual(record.parent?.recordID, rootRecordID)
    }

    func testEventMirrorRecordCanUpdateFetchedServerRecord() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let rootRecordID = CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        let recordID = CKRecord.ID(recordName: "mirror-record", zoneID: zoneID)
        let existing = CKRecord(recordType: "EventMirror", recordID: recordID)
        existing[EventMirrorRecordMapper.Key.title] = "Old title" as CKRecordValue
        let mirror = EventMirror(
            ownerMemberID: "me",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Planning",
            location: "Cafe",
            notes: "Bring notes",
            urlString: "https://example.com",
            calendarColorHex: "#3A86FF",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "mirror-record"
        )

        let record = EventMirrorRecordMapper.record(
            from: mirror,
            zoneID: zoneID,
            parentRecordID: rootRecordID,
            existingRecord: existing
        )

        XCTAssertTrue(record === existing)
        XCTAssertEqual(record.parent?.recordID, rootRecordID)
        XCTAssertEqual(record[EventMirrorRecordMapper.Key.title] as? String, "Planning")
    }

    func testEventCommentRoundTripsThroughCloudKitRecord() throws {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let comment = EventComment(
            id: "comment-1",
            eventMirrorID: "sharecal:event-1:1800",
            authorMemberID: "partner",
            body: "See you there",
            createdAt: Date(timeIntervalSince1970: 2_000),
            editedAt: Date(timeIntervalSince1970: 2_100),
            deletedAt: nil,
            isRead: true,
            cloudKitRecordName: "comment-record"
        )

        let record = CommentRecordMapper.record(from: comment, zoneID: zoneID)
        let decoded = try CommentRecordMapper.comment(from: record)

        XCTAssertEqual(record.recordType, "EventComment")
        XCTAssertEqual(record.recordID.recordName, "comment-record")
        XCTAssertEqual(decoded.id, "comment-record")
        XCTAssertEqual(decoded.eventMirrorID, "sharecal:event-1:1800")
        XCTAssertEqual(decoded.authorMemberID, "partner")
        XCTAssertEqual(decoded.body, "See you there")
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(decoded.editedAt, Date(timeIntervalSince1970: 2_100))
        XCTAssertTrue(decoded.isRead)
    }

    func testCommentRecordCanUpdateFetchedServerRecordAndStayParentedToShareRoot() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let rootRecordID = CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        let recordID = CKRecord.ID(recordName: "comment-record", zoneID: zoneID)
        let existing = CKRecord(recordType: "EventComment", recordID: recordID)
        existing["body"] = "Old body" as CKRecordValue
        let comment = EventComment(
            id: "comment-1",
            eventMirrorID: "sharecal:event-1:1800",
            authorMemberID: "partner",
            body: "Updated body",
            createdAt: Date(timeIntervalSince1970: 2_000),
            isRead: false,
            cloudKitRecordName: "comment-record"
        )

        let record = CommentRecordMapper.record(
            from: comment,
            zoneID: zoneID,
            parentRecordID: rootRecordID,
            existingRecord: existing
        )

        XCTAssertTrue(record === existing)
        XCTAssertEqual(record.parent?.recordID, rootRecordID)
        XCTAssertEqual(record["body"] as? String, "Updated body")
    }

    func testEventInvitationRoundTripsThroughCloudKitRecord() throws {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let invitation = EventInvitation(
            id: "invite-1",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            isAllDay: false,
            location: "Bistro",
            notes: "Window seat",
            statusRawValue: InvitationStatus.pending.rawValue,
            createdAt: Date(timeIntervalSince1970: 9_000),
            updatedAt: Date(timeIntervalSince1970: 9_100),
            createdLocalEventID: nil,
            cloudKitRecordName: "invite-record"
        )

        let record = InvitationRecordMapper.record(from: invitation, zoneID: zoneID)
        let decoded = try InvitationRecordMapper.invitation(from: record)

        XCTAssertEqual(record.recordType, "EventInvitation")
        XCTAssertEqual(record.recordID.recordName, "invite-record")
        XCTAssertEqual(decoded.id, "invite-record")
        XCTAssertEqual(decoded.creatorMemberID, "me")
        XCTAssertEqual(decoded.inviteeMemberID, "partner")
        XCTAssertEqual(decoded.title, "Dinner")
        XCTAssertEqual(decoded.startDate, Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(decoded.endDate, Date(timeIntervalSince1970: 12_000))
        XCTAssertEqual(decoded.location, "Bistro")
        XCTAssertEqual(decoded.notes, "Window seat")
        XCTAssertEqual(decoded.status, .pending)
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 9_100))
        XCTAssertEqual(decoded.cloudKitRecordName, "invite-record")
    }

    func testCalendarAccessRequestRoundTripsThroughCloudKitRecord() throws {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let request = CalendarAccessRequest(
            id: "request-1",
            requesterMemberID: "partner",
            ownerMemberID: "me",
            requestedStartDate: Date(timeIntervalSince1970: 1_000),
            requestedEndDate: Date(timeIntervalSince1970: 2_000),
            statusRawValue: CalendarAccessRequestStatus.pending.rawValue,
            createdAt: Date(timeIntervalSince1970: 900),
            updatedAt: Date(timeIntervalSince1970: 950),
            cloudKitRecordName: "request-record"
        )

        let record = CalendarAccessRequestRecordMapper.record(from: request, zoneID: zoneID)
        let decoded = try CalendarAccessRequestRecordMapper.request(from: record)

        XCTAssertEqual(record.recordType, "CalendarAccessRequest")
        XCTAssertEqual(record.recordID.recordName, "request-record")
        XCTAssertEqual(decoded.id, "request-record")
        XCTAssertEqual(decoded.requesterMemberID, "partner")
        XCTAssertEqual(decoded.ownerMemberID, "me")
        XCTAssertEqual(decoded.requestedStartDate, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(decoded.requestedEndDate, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(decoded.status, .pending)
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 950))
        XCTAssertEqual(decoded.cloudKitRecordName, "request-record")
    }
}

final class CloudKitStopSharingPlanTests: XCTestCase {
    func testNoopsWhenRootHasNoShareReference() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )

        XCTAssertNil(CloudKitStopSharingPlan.shareRecordIDToDelete(from: root))
    }

    func testDeletesActiveShareRecordWhenRootIsShared() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)

        XCTAssertEqual(CloudKitStopSharingPlan.shareRecordIDToDelete(from: root), share.recordID)
    }

    func testICloudDataCleanupStopsSharingBeforeDeletingPrivateZone() {
        XCTAssertEqual(
            CloudKitICloudDataCleanupPlan.steps,
            [.stopSharing, .deletePrivateZone]
        )
    }

    func testICloudDataCleanupDeletesOnlyCoupleSpacePrivateZone() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")

        XCTAssertEqual(CloudKitICloudDataCleanupPlan.zoneIDsToDelete(zoneID: zoneID), [zoneID])
    }

    func testICloudDataCleanupIgnoresMissingPrivateZone() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.unknownItem.rawValue)

        XCTAssertTrue(CloudKitICloudDataCleanupPlan.shouldIgnoreZoneDeletionError(error))
    }

    func testICloudDataCleanupDoesNotIgnorePermissionErrors() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.permissionFailure.rawValue)

        XCTAssertFalse(CloudKitICloudDataCleanupPlan.shouldIgnoreZoneDeletionError(error))
    }

    @MainActor
    func testLocalICloudDataCleanupPurgesCachedShareCalModels() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.insert(CoupleSpace(ownerMemberID: "me"))
        context.insert(MemberProfile(id: "profile", displayName: "Me", avatarColorHex: "#FF2D55"))
        context.insert(cleanupMirror(owner: "partner", key: "partner-event"))
        context.insert(LocalEventShadow(
            localEventIdentifier: "event",
            calendarIdentifier: "calendar",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_000),
            fingerprint: "fingerprint",
            cloudKitRecordName: "record",
            lastUploadedAt: Date(timeIntervalSince1970: 2_000),
            isTombstone: false
        ))
        context.insert(EventComment(
            eventMirrorID: "partner-event",
            authorMemberID: "partner",
            body: "cached",
            createdAt: Date(timeIntervalSince1970: 3_000)
        ))
        context.insert(EventInvitation(
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Invite",
            startDate: Date(timeIntervalSince1970: 4_000),
            endDate: Date(timeIntervalSince1970: 5_000),
            location: nil,
            notes: nil
        ))
        context.insert(CalendarAccessRequest(
            requesterMemberID: "partner",
            ownerMemberID: "me",
            requestedStartDate: Date(timeIntervalSince1970: 6_000),
            requestedEndDate: Date(timeIntervalSince1970: 7_000)
        ))
        context.insert(SyncState(lastSyncAt: Date(timeIntervalSince1970: 8_000)))
        try context.save()

        try ShareCalLocalDataCleanupService.purge(modelContext: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CoupleSpace>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventMirror>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalEventShadow>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventComment>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventInvitation>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarAccessRequest>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncState>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemberProfile>()).count, 1)
    }

    @MainActor
    func testSharedOwnerCleanupPurgesStableAndLegacyPartnerMirrorsOnly() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.insert(cleanupMirror(owner: "me", key: "mine"))
        context.insert(cleanupMirror(owner: "icloud-owner", key: "stable-partner"))
        context.insert(cleanupMirror(owner: "partner", key: "legacy-partner"))
        context.insert(cleanupMirror(owner: "someone-else", key: "stranger"))
        context.insert(EventComment(
            eventMirrorID: "stable-partner",
            authorMemberID: "icloud-owner",
            body: "cached",
            createdAt: Date(timeIntervalSince1970: 3_000)
        ))
        context.insert(EventComment(
            eventMirrorID: "mine",
            authorMemberID: "me",
            body: "keep",
            createdAt: Date(timeIntervalSince1970: 4_000)
        ))
        try context.save()

        try ShareCalLocalDataCleanupService.purgeSharedOwnerMirrors(
            ownerMemberIDs: ["icloud-owner", "partner"],
            modelContext: context
        )

        let remainingMirrors = try context.fetch(FetchDescriptor<EventMirror>()).map(\.mirrorKey).sorted()
        let remainingComments = try context.fetch(FetchDescriptor<EventComment>()).map(\.body).sorted()
        XCTAssertEqual(remainingMirrors, ["mine", "stranger"])
        XCTAssertEqual(remainingComments, ["keep"])
    }

    private func cleanupMirror(owner: String, key: String) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: owner,
            mirrorKey: key,
            sourceCalendarID: "calendar",
            sourceCalendarTitle: "Calendar",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_000),
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 1_800),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: key,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: key
        )
    }
}

final class CloudKitCommentWritePlanTests: XCTestCase {
    func testWritesOwnEventCommentsToPrivateOwnerZone() {
        XCTAssertEqual(
            CloudKitCommentWritePlan.destination(eventOwnerMemberID: "me", currentMemberID: "me"),
            .privateOwnerZone
        )
    }

    func testWritesPartnerEventCommentsToAcceptedSharedZone() {
        XCTAssertEqual(
            CloudKitCommentWritePlan.destination(eventOwnerMemberID: "partner", currentMemberID: "me"),
            .acceptedSharedZone
        )
    }
}

final class CloudKitInvitationWritePlanTests: XCTestCase {
    func testCreatorWritesInvitationToPrivateOwnerZone() {
        XCTAssertEqual(
            CloudKitInvitationWritePlan.destination(creatorMemberID: "me", currentMemberID: "me"),
            .privateOwnerZone
        )
    }

    func testInviteeWritesInvitationStatusBackToAcceptedSharedZone() {
        XCTAssertEqual(
            CloudKitInvitationWritePlan.destination(creatorMemberID: "partner", currentMemberID: "me"),
            .acceptedSharedZone
        )
    }
}

final class CloudKitRootLookupPolicyTests: XCTestCase {
    func testTreatsMissingRootAndRejectedServerLookupAsRecoverableLookupFailures() {
        let unknownItem = NSError(domain: CKError.errorDomain, code: CKError.Code.unknownItem.rawValue)
        let serverRejectedRequest = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue)

        XCTAssertTrue(CloudKitRootLookupPolicy.shouldCreateRootAfterLookupFailure(unknownItem))
        XCTAssertTrue(CloudKitRootLookupPolicy.shouldCreateRootAfterLookupFailure(serverRejectedRequest))
    }

    func testDoesNotTreatAuthenticationFailureAsRecoverableLookupFailure() {
        let notAuthenticated = NSError(domain: CKError.errorDomain, code: CKError.Code.notAuthenticated.rawValue)

        XCTAssertFalse(CloudKitRootLookupPolicy.shouldCreateRootAfterLookupFailure(notAuthenticated))
    }
}

final class CloudKitShareSavePlanTests: XCTestCase {
    func testSavesNewRootBeforeCreatingShare() {
        XCTAssertEqual(
            CloudKitShareSavePlan.steps(rootState: .created),
            [.saveRootBeforeCreatingShare, .saveShare]
        )
    }

    func testExistingRootCanCreateShareDirectly() {
        XCTAssertEqual(
            CloudKitShareSavePlan.steps(rootState: .existing),
            [.saveShare]
        )
    }
}

final class CloudKitSharePermissionPlanTests: XCTestCase {
    func testConfiguresShareForInviteLinks() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)

        XCTAssertTrue(CloudKitSharePermissionPlan.needsLinkInvitationUpgrade(share))

        CloudKitSharePermissionPlan.configureForLinkInvitation(share)

        XCTAssertEqual(share.publicPermission, .readWrite)
        XCTAssertFalse(CloudKitSharePermissionPlan.needsLinkInvitationUpgrade(share))
    }

    func testControllerPermissionsExposePublicInviteLinks() {
        let permissions = CloudKitSharePermissionPlan.controllerAvailablePermissions

        XCTAssertTrue(permissions.contains(.allowPublic))
        XCTAssertTrue(permissions.contains(.allowPrivate))
        XCTAssertTrue(permissions.contains(.allowReadWrite))
    }
}

final class CloudKitContainerDiagnosticPlanTests: XCTestCase {
    func testAccountDiagnosticDisplaySeparatesExpectedAndRuntimeChecks() {
        let diagnostic = CloudKitAccountDiagnostic(
            expectedContainerIdentifier: "iCloud.com.leeberty.CoupleCalendar",
            expectedEnvironment: "Production",
            expectedZoneName: "CoupleSpace",
            runtimeContainerIdentifier: "iCloud.com.leeberty.CoupleCalendar",
            accountStatus: "available",
            userRecordName: "_user",
            privateDatabaseStatus: "readable; CoupleSpace zone exists",
            errorDescription: nil
        )

        XCTAssertEqual(
            diagnostic.displayText,
            """
            Expected:
            Container: iCloud.com.leeberty.CoupleCalendar
            Environment: Production
            Zone: CoupleSpace

            Runtime:
            Container: iCloud.com.leeberty.CoupleCalendar
            Account: available
            User Record: _user
            Private Database: readable; CoupleSpace zone exists
            """
        )
        XCTAssertFalse(diagnostic.displayText.contains("Entitlements"))
    }

    func testDisplaysRuntimeContainerIdentifierWhenCloudKitProvidesOne() {
        XCTAssertEqual(
            CloudKitContainerDiagnosticPlan.displayIdentifier(
                runtimeIdentifier: "iCloud.runtime",
                fallbackIdentifier: "iCloud.fallback"
            ),
            "iCloud.runtime"
        )
    }

    func testFallsBackToExpectedContainerIdentifierWhenRuntimeIdentifierIsMissing() {
        XCTAssertEqual(
            CloudKitContainerDiagnosticPlan.displayIdentifier(
                runtimeIdentifier: nil,
                fallbackIdentifier: "iCloud.fallback"
            ),
            "iCloud.fallback"
        )
    }

}

final class CloudKitSharedReadDiagnosticTests: XCTestCase {
    func testDisplaysReadableSharedRecordCounts() {
        let diagnostic = CloudKitSharedReadDiagnostic(
            sharedZoneCount: 1,
            eventMirrorCount: 2,
            commentCount: 3,
            invitationCount: 4,
            accessRequestCount: 5,
            errorDescription: nil
        )

        XCTAssertEqual(
            diagnostic.displayText,
            """
            Shared Zones: 1
            EventMirror: 2
            EventComment: 3
            EventInvitation: 4
            CalendarAccessRequest: 5
            """
        )
        XCTAssertFalse(diagnostic.provesNoSharedCalendarReadAccess)
    }

    func testZeroSharedZonesAndRecordsProvesNoSharedCalendarReadAccess() {
        let diagnostic = CloudKitSharedReadDiagnostic(
            sharedZoneCount: 0,
            eventMirrorCount: 0,
            commentCount: 0,
            invitationCount: 0,
            accessRequestCount: 0,
            errorDescription: nil
        )

        XCTAssertTrue(diagnostic.provesNoSharedCalendarReadAccess)
    }

    func testErrorDoesNotProveNoSharedCalendarReadAccess() {
        let diagnostic = CloudKitSharedReadDiagnostic(
            sharedZoneCount: 0,
            eventMirrorCount: 0,
            commentCount: 0,
            invitationCount: 0,
            accessRequestCount: 0,
            errorDescription: "not authenticated"
        )

        XCTAssertFalse(diagnostic.provesNoSharedCalendarReadAccess)
        XCTAssertTrue(diagnostic.displayText.contains("Error: not authenticated"))
    }
}

final class CloudKitShareAcceptancePlanTests: XCTestCase {
    func testUsesMetadataContainerIdentifierWhenAcceptingShare() {
        XCTAssertEqual(
            CloudKitShareAcceptancePlan.containerIdentifier(
                metadataContainerIdentifier: "iCloud.shared",
                fallbackIdentifier: "iCloud.fallback"
            ),
            "iCloud.shared"
        )
    }

    func testFallsBackToAppContainerIdentifierWhenMetadataOmitsContainerIdentifier() {
        XCTAssertEqual(
            CloudKitShareAcceptancePlan.containerIdentifier(
                metadataContainerIdentifier: nil,
                fallbackIdentifier: "iCloud.fallback"
            ),
            "iCloud.fallback"
        )
    }
}

final class CloudKitShareRootICloudEmailPlanTests: XCTestCase {
    func testUsesReadableEmailForShareRootOwnerMemberIDWhenAvailable() {
        XCTAssertEqual(
            CloudKitShareRootICloudEmailPlan.ownerMemberIDValue(
                ownerMemberID: "me",
                ownerICloudEmailAddress: " owner@icloud.com "
            ),
            "owner@icloud.com"
        )
        XCTAssertEqual(
            CloudKitShareRootICloudEmailPlan.ownerMemberIDValue(
                ownerMemberID: "me",
                ownerICloudEmailAddress: "_ee39c883ba88010c4ea25fd9a273af8d"
            ),
            "me"
        )
    }

    func testDoesNotWriteOwnerICloudEmailAddressBeforeProductionSchemaSupportsIt() {
        let record = CKRecord(recordType: "CoupleSpace")

        CloudKitShareRootICloudEmailPlan.applyOwnerICloudEmailAddress(
            " owner@icloud.com ",
            to: record
        )

        XCTAssertNil(record["ownerICloudEmailAddress"] as? String)
    }

    func testDoesNotClearExistingOwnerICloudEmailAddressWhenWritesAreDisabled() {
        let record = CKRecord(recordType: "CoupleSpace")
        record["ownerICloudEmailAddress"] = "old@icloud.com" as CKRecordValue

        CloudKitShareRootICloudEmailPlan.applyOwnerICloudEmailAddress(
            "_ee39c883ba88010c4ea25fd9a273af8d",
            to: record
        )

        XCTAssertEqual(record["ownerICloudEmailAddress"] as? String, "old@icloud.com")
    }

    func testReadsOnlyEmailAddressesFromSharedRootRecords() {
        let emailRecord = CKRecord(recordType: "CoupleSpace")
        emailRecord["ownerICloudEmailAddress"] = " partner@icloud.com " as CKRecordValue
        let ownerMemberEmailRecord = CKRecord(recordType: "CoupleSpace")
        ownerMemberEmailRecord["ownerMemberID"] = " owner-member@icloud.com " as CKRecordValue
        let internalRecord = CKRecord(recordType: "CoupleSpace")
        internalRecord["ownerICloudEmailAddress"] = "_82828b1d87c3d5e8685ae3b8c5a6c80a" as CKRecordValue

        XCTAssertEqual(
            CloudKitShareRootICloudEmailPlan.emailAddresses(from: [emailRecord, ownerMemberEmailRecord, internalRecord]),
            ["partner@icloud.com", "owner-member@icloud.com"]
        )
    }
}

final class ShareCalAcceptedShareSignalTests: XCTestCase {
    func testMarkAcceptedCreatesPendingSyncSignalAndConsumeClearsIt() throws {
        let suiteName = "ShareCalAcceptedShareSignalTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))

        ShareCalAcceptedShareSignal.markAccepted(defaults: defaults, notificationCenter: NotificationCenter())

        XCTAssertTrue(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))
        XCTAssertFalse(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))
    }

    func testHasPendingReportsSignalWithoutConsumingIt() throws {
        let suiteName = "ShareCalAcceptedShareSignalTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ShareCalAcceptedShareSignal.hasPending(defaults: defaults))

        ShareCalAcceptedShareSignal.markAccepted(defaults: defaults, notificationCenter: NotificationCenter())

        XCTAssertTrue(ShareCalAcceptedShareSignal.hasPending(defaults: defaults))
        XCTAssertTrue(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))
        XCTAssertFalse(ShareCalAcceptedShareSignal.hasPending(defaults: defaults))
    }

    func testStoresPendingPartnerICloudEmailForAcceptedShare() throws {
        let suiteName = "ShareCalAcceptedShareSignalTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ShareCalAcceptedShareSignal.markAccepted(
            partnerICloudEmailAddress: " partner@icloud.com ",
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(
            ShareCalAcceptedShareSignal.consumePendingPartnerICloudEmailAddress(defaults: defaults),
            "partner@icloud.com"
        )
        XCTAssertNil(ShareCalAcceptedShareSignal.consumePendingPartnerICloudEmailAddress(defaults: defaults))
    }
}

final class ForegroundSyncPlanTests: XCTestCase {
    func testAllowsAutomaticSyncWhenThereIsNoPreviousSync() {
        XCTAssertTrue(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testSkipsAutomaticSyncWhenLastSyncIsWithinThrottleWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-299)

        XCTAssertFalse(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testAllowsAutomaticSyncWhenThrottleWindowHasElapsed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-ForegroundSyncPlan.automaticThrottleInterval)

        XCTAssertTrue(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testSkipsAutomaticSyncWhileSyncing() {
        XCTAssertFalse(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .syncing,
                hasPendingAcceptedShare: false
            )
        )
    }

    func testPendingAcceptedShareBypassesThrottleWhenIdle() {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastSyncAt = now.addingTimeInterval(-1)

        XCTAssertTrue(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: lastSyncAt,
                now: now,
                syncPhase: .idle,
                hasPendingAcceptedShare: true
            )
        )
    }

    func testPendingAcceptedShareDoesNotStartDuplicateSync() {
        XCTAssertFalse(
            ForegroundSyncPlan.shouldRunAutomaticSync(
                lastSyncAt: nil,
                now: Date(timeIntervalSince1970: 1_000),
                syncPhase: .syncing,
                hasPendingAcceptedShare: true
            )
        )
    }
}

final class CloudKitForegroundSyncPlanTests: XCTestCase {
    func testSkipsCloudKitWhenSharingDisabledEvenIfForced() {
        XCTAssertFalse(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: false,
                hasStartedPairing: true,
                partnerShareOwnerID: "partner-owner",
                outgoingShareParticipantIDs: ["participant"],
                forceCloudKit: true
            )
        )
    }

    func testSkipsCloudKitBeforePairingWhenThereIsNoAcceptedShareSignal() {
        XCTAssertFalse(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
    }

    func testRunsCloudKitForPairingSignalsOrAcceptedShareSignal() {
        XCTAssertTrue(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: true,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: "partner-owner",
                outgoingShareParticipantIDs: [],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: ["participant"],
                forceCloudKit: false
            )
        )
        XCTAssertTrue(
            CloudKitForegroundSyncPlan.shouldRunCloudKit(
                iCloudSharingEnabled: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                forceCloudKit: true
            )
        )
    }
}

final class ShareCalSceneDelegateConfigurationTests: XCTestCase {
    func testAppDelegateUsesSceneDelegateForCloudKitShareAcceptance() {
        XCTAssertEqual(ShareCalSceneDelegateConfigurationPlan.configurationName, "Default Configuration")
        XCTAssertTrue(ShareCalSceneDelegateConfigurationPlan.acceptsColdStartShareMetadata)
        XCTAssertTrue(ShareCalSceneDelegateConfigurationPlan.sceneDelegateClass === ShareCalSceneDelegate.self)
        XCTAssertEqual(
            ShareCalSceneDelegateConfigurationPlan.sceneDelegateClassName(moduleName: "CoupleCalendar"),
            "CoupleCalendar.ShareCalSceneDelegate"
        )
    }
}

final class CloudKitSharedDatabaseImportPlanTests: XCTestCase {
    func testSelectsCoupleSpaceZonesForAcceptedSharesRegardlessOwnerName() {
        let acceptedShareZone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_partnerOwner"))
        let unrelatedZone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "OtherZone", ownerName: "_partnerOwner"))

        let zoneIDs = CloudKitSharedDatabaseImportPlan.coupleSpaceZoneIDs(
            from: [acceptedShareZone, unrelatedZone],
            expectedZoneName: "CoupleSpace"
        )

        XCTAssertEqual(zoneIDs.map(\.zoneName), ["CoupleSpace"])
        XCTAssertEqual(zoneIDs.map(\.ownerName), ["_partnerOwner"])
    }

    func testMapsSharedDatabaseMirrorsToLocalPartnerMember() {
        let first = EventMirror(
            ownerMemberID: "me",
            mirrorKey: "first",
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: Date(timeIntervalSince1970: 1),
            startDate: Date(timeIntervalSince1970: 1),
            endDate: Date(timeIntervalSince1970: 2),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Mine",
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "first"
        )
        let second = EventMirror(
            ownerMemberID: "remote-owner",
            mirrorKey: "second",
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: Date(timeIntervalSince1970: 3),
            startDate: Date(timeIntervalSince1970: 3),
            endDate: Date(timeIntervalSince1970: 4),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: "Partner",
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: "second"
        )

        let localized = CloudKitSharedDatabaseImportPlan.identifiedMirrors(
            [first, second],
            sharedOwnerID: "icloud-owner"
        )

        XCTAssertEqual(localized.map(\.mirrorKey), ["first", "second"])
        XCTAssertEqual(localized.map(\.ownerMemberID), ["icloud-owner", "icloud-owner"])
        XCTAssertEqual(localized.map(\.cloudKitRecordName), ["first", "second"])
    }
}

final class CloudKitOperationCompletionGateTests: XCTestCase {
    func testAllowsOnlyOneCompletionAndSuppressesTimeoutAfterCompletion() {
        let gate = CloudKitOperationCompletionGate()

        XCTAssertTrue(gate.shouldRunTimeout)
        XCTAssertTrue(gate.completeIfNeeded())
        XCTAssertFalse(gate.shouldRunTimeout)
        XCTAssertFalse(gate.completeIfNeeded())
    }
}

final class CloudKitModifyRecordResultValidatorTests: XCTestCase {
    func testThrowsFirstPerRecordSaveFailureWhenOperationReportsSuccess() {
        let recordID = CKRecord.ID(recordName: "failed-record")
        let failure = NSError(domain: CKError.errorDomain, code: CKError.Code.invalidArguments.rawValue)
        let results: CloudKitModifyRecordResults = (
            saveResults: [recordID: .failure(failure)],
            deleteResults: [:]
        )

        XCTAssertThrowsError(try CloudKitModifyRecordResultValidator.validate(results)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, CKError.errorDomain)
            XCTAssertEqual(nsError.code, CKError.Code.invalidArguments.rawValue)
        }
    }

    func testAllowsAllSuccessfulPerRecordResults() {
        let record = CKRecord(recordType: "EventMirror", recordID: CKRecord.ID(recordName: "saved-record"))
        let results: CloudKitModifyRecordResults = (
            saveResults: [record.recordID: .success(record)],
            deleteResults: [CKRecord.ID(recordName: "deleted-record"): .success(())]
        )

        XCTAssertNoThrow(try CloudKitModifyRecordResultValidator.validate(results))
    }
}

final class CloudKitSharingFailureMessageTests: XCTestCase {
    func testExplainsServerRejectedRequestAsEnvironmentOrSchemaProblem() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue)

        XCTAssertEqual(
            CloudKitSharingFailureMessage.userFacingMessage(for: error),
            "CloudKit rejected private database writes for this container. For Development builds, sign in on this simulator with an Apple Account that belongs to the Apple Developer team, or deploy the CloudKit schema and test a Production/TestFlight build."
        )
    }

    func testUsesLocalizedDescriptionForOtherErrors() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing file"])

        XCTAssertEqual(CloudKitSharingFailureMessage.userFacingMessage(for: error), "Missing file")
    }

    func testExplainsMissingProductionSchemaRecordType() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.invalidArguments.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot create new type CoupleSpace in production schema"
            ]
        )

        XCTAssertEqual(
            CloudKitSharingFailureMessage.userFacingMessage(for: error),
            "CloudKit Production schema is missing ShareCal record types. Run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Start Pairing."
        )
    }

    func testExplainsMissingProductionCloudKitShareRecordType() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.invalidArguments.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot create new type cloudkit.share in production schema"
            ]
        )

        XCTAssertEqual(
            CloudKitSharingFailureMessage.userFacingMessage(for: error),
            "CloudKit Production schema is missing the CloudKit Sharing system record type. Create one Development share, run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Start Pairing."
        )
    }
}

final class ShareCalLaunchDiagnosticPlanTests: XCTestCase {
    func testRunsCloudKitWriteProbeOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPlan.shouldRunCloudKitWriteProbe(
                arguments: ["ShareCal", "-ShareCalCloudKitWriteProbe"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPlan.shouldRunCloudKitWriteProbe(
                arguments: ["ShareCal"]
            )
        )
    }

    func testSeedsCalendarEventOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPlan.shouldSeedCalendarEvent(
                arguments: ["ShareCal", "-ShareCalSeedCalendarEvent"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPlan.shouldSeedCalendarEvent(
                arguments: ["ShareCal"]
            )
        )
    }

    func testCloudKitWriteProbeUsesRealShareRootRecordType() {
        XCTAssertEqual(ShareCalLaunchDiagnosticPlan.cloudKitWriteProbeRecordType, "CoupleSpace")
    }

    func testRunsStopSharingProbeOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPlan.shouldRunStopSharingProbe(
                arguments: ["ShareCal", "-ShareCalStopICloudSharing"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPlan.shouldRunStopSharingProbe(
                arguments: ["ShareCal"]
            )
        )
    }

    func testRunsSharedReadProbeOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPlan.shouldRunSharedReadProbe(
                arguments: ["ShareCal", "-ShareCalSharedReadProbe"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPlan.shouldRunSharedReadProbe(
                arguments: ["ShareCal"]
            )
        )
    }
}

final class InvitationServiceTests: XCTestCase {
    func testAcceptPendingInvitationCreatesLocalCalendarDraftAndPreventsDuplicateAccept() throws {
        let invitation = EventInvitation(
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: "Bistro",
            notes: "Window seat",
            statusRawValue: InvitationStatus.pending.rawValue
        )
        let service = InvitationService()

        let draft = try service.accept(invitation, createdLocalEventID: "local-1")

        XCTAssertEqual(draft.title, "Dinner")
        XCTAssertEqual(draft.location, "Bistro")
        XCTAssertEqual(invitation.status, .accepted)
        XCTAssertEqual(invitation.createdLocalEventID, "local-1")
        XCTAssertThrowsError(try service.accept(invitation, createdLocalEventID: "local-2"))
    }

    func testOnlyInviteeCanRespondToPendingInvitation() {
        let invitation = EventInvitation(
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.pending.rawValue
        )

        XCTAssertTrue(InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: "partner"))
        XCTAssertFalse(InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: "me"))

        invitation.status = .accepted

        XCTAssertFalse(InvitationInteractionPlan.canRespond(to: invitation, currentMemberID: "partner"))
    }

    func testCancelsAcceptedInvitationWhenCreatedLocalEventIsMissing() {
        let missingLocalEvent = EventInvitation(
            id: "missing",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.accepted.rawValue,
            createdLocalEventID: "local-missing"
        )
        let existingLocalEvent = EventInvitation(
            id: "existing",
            creatorMemberID: "partner",
            inviteeMemberID: "me",
            title: "Lunch",
            startDate: Date(timeIntervalSince1970: 13_000),
            endDate: Date(timeIntervalSince1970: 14_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.accepted.rawValue,
            createdLocalEventID: "local-existing"
        )
        let pending = EventInvitation(
            id: "pending",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Pending",
            startDate: Date(timeIntervalSince1970: 15_000),
            endDate: Date(timeIntervalSince1970: 16_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.pending.rawValue,
            createdLocalEventID: "local-pending"
        )

        let canceled = InvitationLocalEventSyncPlan.cancelAcceptedInvitationsMissingLocalEvents(
            [missingLocalEvent, existingLocalEvent, pending],
            existingLocalEventIDs: ["local-existing"],
            now: Date(timeIntervalSince1970: 20_000)
        )

        XCTAssertEqual(canceled.map(\.id), ["missing"])
        XCTAssertEqual(missingLocalEvent.status, .canceled)
        XCTAssertEqual(missingLocalEvent.updatedAt, Date(timeIntervalSince1970: 20_000))
        XCTAssertEqual(existingLocalEvent.status, .accepted)
        XCTAssertEqual(pending.status, .pending)
    }

    func testKeepsAcceptedInvitationWhenFallbackLocalEventMatcherFindsIt() {
        let invitation = EventInvitation(
            id: "accepted",
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: nil,
            notes: nil,
            statusRawValue: InvitationStatus.accepted.rawValue,
            createdLocalEventID: "stale-local-id"
        )

        let canceled = InvitationLocalEventSyncPlan.cancelAcceptedInvitationsMissingLocalEvents(
            [invitation],
            now: Date(timeIntervalSince1970: 20_000),
            localEventExists: { candidate in
                candidate.title == "Dinner"
                    && candidate.startDate == Date(timeIntervalSince1970: 10_000)
                    && candidate.endDate == Date(timeIntervalSince1970: 12_000)
            }
        )

        XCTAssertTrue(canceled.isEmpty)
        XCTAssertEqual(invitation.status, .accepted)
    }
}

final class InvitationListPlanTests: XCTestCase {
    func testOnlyAcceptedInvitationsCanOpenInCalendar() {
        let accepted = invitation(id: "accepted", status: .accepted)
        let pending = invitation(id: "pending", status: .pending)
        let declined = invitation(id: "declined", status: .declined)

        XCTAssertTrue(InvitationListPlan.canOpenInCalendar(accepted))
        XCTAssertFalse(InvitationListPlan.canOpenInCalendar(pending))
        XCTAssertFalse(InvitationListPlan.canOpenInCalendar(declined))
    }

    func testAllVisibleInvitationsCanBeDeletedFromList() {
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "accepted", status: .accepted)))
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "declined", status: .declined)))
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "pending", status: .pending)))
        XCTAssertTrue(InvitationListPlan.canDelete(invitation(id: "canceled", status: .canceled)))
    }

    func testArchivedInvitationsAreHiddenFromInvitesList() {
        let visible = invitation(id: "visible", status: .accepted)
        let archived = invitation(
            id: "archived",
            status: .declined,
            archivedAt: Date(timeIntervalSince1970: 20_000)
        )

        let invitations = InvitationListPlan.visibleInvitations([visible, archived])

        XCTAssertEqual(invitations.map(\.id), ["visible"])
    }

    func testAcceptedInvitationBuildsCalendarFocusRequest() throws {
        let accepted = invitation(id: "accepted", status: .accepted)

        let request = try XCTUnwrap(CalendarFocusPlan.request(for: accepted))

        XCTAssertEqual(request.invitationID, "accepted")
        XCTAssertEqual(request.startDate, Date(timeIntervalSince1970: 10_000))
    }

    private func invitation(
        id: String,
        status: InvitationStatus,
        archivedAt: Date? = nil
    ) -> EventInvitation {
        EventInvitation(
            id: id,
            creatorMemberID: "me",
            inviteeMemberID: "partner",
            title: "Dinner",
            startDate: Date(timeIntervalSince1970: 10_000),
            endDate: Date(timeIntervalSince1970: 12_000),
            location: nil,
            notes: nil,
            statusRawValue: status.rawValue,
            archivedAt: archivedAt
        )
    }
}

final class DayTimelineScrollTargetPlanTests: XCTestCase {
    func testDefaultsInitialScrollTargetToEightAM() {
        let targetY = DayTimelineScrollTargetPlan.defaultTargetY(hourHeight: 58)

        XCTAssertEqual(targetY, 464, accuracy: 0.001)
    }

    func testTargetsEventStartTimeInsteadOfOffsetLayoutOrigin() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let startDate = dayStart.addingTimeInterval(15 * 60 * 60)
        let event = JointScheduleEvent(
            id: "invite-1",
            title: "Dinner",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(60 * 60),
            isAllDay: false,
            location: nil,
            notes: nil
        )

        let targetY = DayTimelineScrollTargetPlan.targetY(
            for: event,
            dayStart: dayStart,
            hourHeight: 58,
            calendar: calendar
        )

        XCTAssertEqual(targetY, 870, accuracy: 0.001)
    }
}

final class CloudKitMirrorSyncPlanTests: XCTestCase {
    func testSkipsUnchangedActiveMirrors() {
        let existing = eventMirror(id: "event-1", title: "Planning")
        let current = eventMirror(id: "event-1", title: "Planning")
        let shadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
            [current],
            activeShadows: [shadow],
            existingShadows: [shadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertTrue(mirrors.isEmpty)
    }

    func testUploadsNewActiveMirrors() {
        let current = eventMirror(id: "event-1", title: "Planning")
        let shadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
            [current],
            activeShadows: [shadow],
            existingShadows: [],
            existingLocalMirrors: []
        )

        XCTAssertEqual(mirrors.map(\.mirrorKey), ["work:event-1:1800"])
    }

    func testUploadsChangedActiveMirrors() {
        let existing = eventMirror(id: "event-1", title: "Planning")
        let current = eventMirror(id: "event-1", title: "Updated")
        let activeShadow = localShadow(id: "event-1", fingerprint: "new", isTombstone: false)
        let existingShadow = localShadow(id: "event-1", fingerprint: "old", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
            [current],
            activeShadows: [activeShadow],
            existingShadows: [existingShadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertEqual(mirrors.map(\.title), ["Updated"])
    }

    func testUploadsVisibilityOnlyChangesWhenFingerprintIsUnchanged() {
        let existing = eventMirror(id: "event-1", title: "Planning", visibility: .fullDetails)
        let current = eventMirror(id: "event-1", title: "Busy", visibility: .busyOnly)
        let shadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
            [current],
            activeShadows: [shadow],
            existingShadows: [shadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertEqual(mirrors.map(\.visibilityRawValue), [EventVisibility.busyOnly.rawValue])
    }

    func testUploadsDeletedMirrors() {
        let deletedAt = Date(timeIntervalSince1970: 5_000)
        let existing = eventMirror(id: "event-1", title: "Planning")
        let deleted = eventMirror(id: "event-1", title: "Planning", deletedAt: deletedAt)
        let existingShadow = localShadow(id: "event-1", fingerprint: "same", isTombstone: false)

        let mirrors = CloudKitMirrorSyncPlan.mirrorsNeedingUpload(
            [deleted],
            activeShadows: [],
            existingShadows: [existingShadow],
            existingLocalMirrors: [existing]
        )

        XCTAssertEqual(mirrors.count, 1)
        XCTAssertEqual(mirrors[0].deletedAt, deletedAt)
    }

    private func eventMirror(
        id: String,
        title: String,
        visibility: EventVisibility = .fullDetails,
        deletedAt: Date? = nil
    ) -> EventMirror {
        EventMirror(
            id: "work:\(id):1800",
            ownerMemberID: "me",
            mirrorKey: "work:\(id):1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: "Cafe",
            notes: "Bring notes",
            urlString: "https://example.com",
            calendarColorHex: "#3A86FF",
            visibilityRawValue: visibility.rawValue,
            deletedAt: deletedAt,
            cloudKitRecordName: "work:\(id):1800"
        )
    }

    private func localShadow(
        id: String,
        fingerprint: String,
        isTombstone: Bool
    ) -> LocalEventShadow {
        LocalEventShadow(
            id: "work:\(id):1800",
            localEventIdentifier: id,
            calendarIdentifier: "work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            fingerprint: fingerprint,
            cloudKitRecordName: "work:\(id):1800",
            lastUploadedAt: Date(timeIntervalSince1970: 2_000),
            isTombstone: isTombstone
        )
    }
}

final class CloudKitBatchUpsertPlanTests: XCTestCase {
    func testBuildsMirrorRecordIDsWithServerRecordNameFallback() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpaceZone", ownerName: CKCurrentUserDefaultName)
        let existing = eventMirror(id: "event-1", cloudKitRecordName: "server-record")
        let new = eventMirror(id: "event-2", cloudKitRecordName: nil)

        let recordIDs = CloudKitBatchUpsertPlan.recordIDs(forMirrors: [existing, new], zoneID: zoneID)

        XCTAssertEqual(recordIDs.map(\.recordName), ["server-record", "work:event-2:1800"])
    }

    func testDefinesMinimalDesiredKeysForEachForegroundQueryType() {
        XCTAssertEqual(
            CloudKitForegroundQueryPlan.desiredKeys(forRecordType: EventMirrorRecordMapper.recordType),
            [
                EventMirrorRecordMapper.Key.ownerMemberID,
                EventMirrorRecordMapper.Key.mirrorKey,
                EventMirrorRecordMapper.Key.sourceCalendarID,
                EventMirrorRecordMapper.Key.sourceCalendarTitle,
                EventMirrorRecordMapper.Key.occurrenceStartDate,
                EventMirrorRecordMapper.Key.startDate,
                EventMirrorRecordMapper.Key.endDate,
                EventMirrorRecordMapper.Key.isAllDay,
                EventMirrorRecordMapper.Key.timeZoneIdentifier,
                EventMirrorRecordMapper.Key.title,
                EventMirrorRecordMapper.Key.location,
                EventMirrorRecordMapper.Key.notes,
                EventMirrorRecordMapper.Key.urlString,
                EventMirrorRecordMapper.Key.calendarColorHex,
                EventMirrorRecordMapper.Key.visibilityRawValue,
                EventMirrorRecordMapper.Key.deletedAt
            ]
        )
        XCTAssertEqual(
            CloudKitForegroundQueryPlan.desiredKeys(forRecordType: CommentRecordMapper.recordType),
            [
                CommentRecordMapper.Key.eventMirrorID,
                CommentRecordMapper.Key.authorMemberID,
                CommentRecordMapper.Key.body,
                CommentRecordMapper.Key.createdAt,
                CommentRecordMapper.Key.editedAt,
                CommentRecordMapper.Key.deletedAt,
                CommentRecordMapper.Key.isRead
            ]
        )
    }

    private func eventMirror(
        id: String,
        cloudKitRecordName: String?
    ) -> EventMirror {
        EventMirror(
            id: "work:\(id):1800",
            ownerMemberID: "me",
            mirrorKey: "work:\(id):1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "UTC",
            title: "Planning",
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#4285F4",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: cloudKitRecordName
        )
    }
}

final class CloudKitRecordQueryFailurePlanTests: XCTestCase {
    func testTreatsMissingCalendarAccessRequestRecordTypeAsEmpty() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: CalendarAccessRequest"]
        )

        XCTAssertTrue(
            CloudKitRecordQueryFailurePlan.canTreatMissingRecordTypeAsEmpty(
                recordType: CalendarAccessRequestRecordMapper.recordType,
                error: error
            )
        )
    }

    func testDoesNotTreatCoreRecordTypesAsOptionalWhenSchemaIsMissing() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: EventMirror"]
        )

        XCTAssertFalse(
            CloudKitRecordQueryFailurePlan.canTreatMissingRecordTypeAsEmpty(
                recordType: EventMirrorRecordMapper.recordType,
                error: error
            )
        )
    }
}

final class CalendarDateNavigationPlanTests: XCTestCase {
    func testMovesByDayOrWeekAndBuildsStripAroundSelectedDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))

        XCTAssertEqual(
            CalendarDateNavigationPlan.date(afterMoving: selected, mode: .day, direction: .previous, calendar: calendar),
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 6)))
        )
        XCTAssertEqual(
            CalendarDateNavigationPlan.date(afterMoving: selected, mode: .week, direction: .next, calendar: calendar),
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14)))
        )

        let strip = CalendarDateNavigationPlan.dateStrip(around: selected, calendar: calendar)

        XCTAssertEqual(strip.first, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4))))
        XCTAssertEqual(strip.last, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))))
    }

    func testSelectingDateFromHierarchySwitchesToDayMode() throws {
        let calendar = Calendar(identifier: .gregorian)
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))

        let result = CalendarDateNavigationPlan.selectionResult(for: selected)

        XCTAssertEqual(result.selectedDate, selected)
        XCTAssertEqual(result.mode, .day)
    }

    func testBuildsCompactDayAndWeekTitles() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let locale = Locale(identifier: "en_US_POSIX")
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 25)))

        let dayTitle = CalendarDateNavigationPlan.compactTitle(
            for: selected,
            mode: .day,
            calendar: calendar,
            locale: locale
        )
        let weekTitle = CalendarDateNavigationPlan.compactTitle(
            for: selected,
            mode: .week,
            calendar: calendar,
            locale: locale
        )

        XCTAssertEqual(dayTitle, "Sep 25")
        XCTAssertEqual(weekTitle, "Sep 21-27")
    }
}

final class HierarchicalDatePickerPlanTests: XCTestCase {
    func testMonthGridIncludesLeadingAndTrailingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))

        let days = HierarchicalDatePickerPlan.monthGrid(containing: month, calendar: calendar)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.date, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31))))
        XCTAssertEqual(days.first { $0.isInDisplayedMonth }?.date, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))))
    }

    func testMonthAndYearSelectionNavigateWithoutProducingDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let visibleMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let selectedYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 1, day: 1)))
        let selectedMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2030, month: 11, day: 1)))

        let yearNavigation = HierarchicalDatePickerPlan.selectYear(selectedYear, calendar: calendar)
        let monthNavigation = HierarchicalDatePickerPlan.selectMonth(selectedMonth, calendar: calendar)
        let days = HierarchicalDatePickerPlan.months(inYearContaining: visibleMonth, calendar: calendar)

        XCTAssertEqual(yearNavigation.level, .months)
        XCTAssertEqual(calendar.component(.year, from: yearNavigation.visibleMonth), 2030)
        XCTAssertNil(yearNavigation.selectedDate)
        XCTAssertEqual(monthNavigation.level, .month)
        XCTAssertEqual(calendar.component(.month, from: monthNavigation.visibleMonth), 11)
        XCTAssertNil(monthNavigation.selectedDate)
        XCTAssertEqual(days.count, 12)
    }
}

final class WeekAgendaPlanTests: XCTestCase {
    func testBuildsSevenDayAgendaAndSortsMixedItemsByTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let myEvent = eventMirror(
            id: "me-late",
            ownerMemberID: "me",
            title: "Late",
            startDate: monday.addingTimeInterval(15 * 60 * 60),
            endDate: monday.addingTimeInterval(16 * 60 * 60)
        )
        let partnerEvent = eventMirror(
            id: "partner-early",
            ownerMemberID: "partner",
            title: "Early",
            startDate: monday.addingTimeInterval(9 * 60 * 60),
            endDate: monday.addingTimeInterval(10 * 60 * 60)
        )
        let jointEvent = JointScheduleEvent(
            id: "joint-mid",
            title: "Together",
            startDate: monday.addingTimeInterval(12 * 60 * 60),
            endDate: monday.addingTimeInterval(13 * 60 * 60),
            isAllDay: false,
            location: nil,
            notes: nil
        )

        let days = WeekAgendaPlan.days(
            containing: selected,
            mirrors: [myEvent, partnerEvent],
            jointEvents: [jointEvent],
            currentMemberID: "me",
            calendar: calendar
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days[0].date, monday)
        XCTAssertEqual(days[0].items.map(\.title), ["Early", "Together", "Late"])
        XCTAssertEqual(days[0].items.map(\.kind), [.partner, .joint, .currentMember])
    }

    private func eventMirror(
        id: String,
        ownerMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date
    ) -> EventMirror {
        EventMirror(
            id: id,
            ownerMemberID: ownerMemberID,
            mirrorKey: id,
            sourceCalendarID: "sharecal",
            sourceCalendarTitle: "ShareCal",
            occurrenceStartDate: startDate,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            timeZoneIdentifier: "Asia/Singapore",
            title: title,
            location: nil,
            notes: nil,
            urlString: nil,
            calendarColorHex: "#FF2D55",
            visibilityRawValue: EventVisibility.fullDetails.rawValue,
            deletedAt: nil,
            cloudKitRecordName: id
        )
    }
}

final class CreateInvitePlanTests: XCTestCase {
    func testBuildsFutureInviteArtifactsForShareCalCalendar() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let draft = CreateInviteDraft(
            title: "Weekend trip",
            startDate: start,
            endDate: start.addingTimeInterval(2 * 60 * 60),
            isAllDay: false,
            location: "Beach",
            notes: "Bring camera"
        )
        let createdEvent = CreatedCalendarEvent(
            eventIdentifier: "event-1",
            calendarIdentifier: "sharecal",
            calendarTitle: "ShareCal",
            calendarColorHex: "#FF2D55"
        )

        let localDraft = try CreateInvitePlan.localCalendarDraft(from: draft)
        let mirror = try CreateInvitePlan.mirror(
            from: draft,
            createdEvent: createdEvent,
            ownerMemberID: "me",
            timeZoneIdentifier: "Asia/Singapore"
        )
        let invitation = try CreateInvitePlan.invitation(
            from: draft,
            creatorMemberID: "me",
            inviteeMemberID: "partner"
        )

        XCTAssertEqual(localDraft.title, "Weekend trip")
        XCTAssertEqual(mirror.mirrorKey, "sharecal:event-1:20000")
        XCTAssertEqual(mirror.ownerMemberID, "me")
        XCTAssertEqual(invitation.status, .pending)
        XCTAssertEqual(invitation.title, "Weekend trip")
        XCTAssertEqual(invitation.location, "Beach")
    }

    func testRejectsEmptyTitleAndInvalidDateRange() {
        let start = Date(timeIntervalSince1970: 20_000)
        let emptyTitle = CreateInviteDraft(
            title: "  ",
            startDate: start,
            endDate: start.addingTimeInterval(60),
            isAllDay: false,
            location: nil,
            notes: nil
        )
        let invalidRange = CreateInviteDraft(
            title: "Weekend trip",
            startDate: start,
            endDate: start,
            isAllDay: false,
            location: nil,
            notes: nil
        )

        XCTAssertThrowsError(try CreateInvitePlan.localCalendarDraft(from: emptyTitle))
        XCTAssertThrowsError(try CreateInvitePlan.localCalendarDraft(from: invalidRange))
    }
}

final class CommentServiceTests: XCTestCase {
    func testCommentLifecycleCreateEditDeleteAndMarkRead() {
        let service = CommentService(now: { Date(timeIntervalSince1970: 100) })
        let comment = service.createComment(
            eventMirrorID: "mirror-1",
            authorMemberID: "me",
            body: "See you there"
        )

        XCTAssertEqual(comment.body, "See you there")
        XCTAssertFalse(comment.isRead)

        service.edit(comment, body: "See you at 6")
        XCTAssertEqual(comment.body, "See you at 6")
        XCTAssertNotNil(comment.editedAt)

        service.markRead(comment)
        XCTAssertTrue(comment.isRead)

        service.delete(comment)
        XCTAssertNotNil(comment.deletedAt)
    }
}

final class ShareCalReviewSampleDataTests: XCTestCase {
    func testBuildsReviewerPreviewWithBothMembersInvitationAndComment() {
        let now = Date(timeIntervalSince1970: 1_800)

        let sample = ShareCalReviewSampleData.build(
            now: now,
            currentMemberID: "me",
            partnerMemberID: "partner"
        )

        XCTAssertEqual(sample.mirrors.count, 4)
        XCTAssertEqual(Set(sample.mirrors.map(\.ownerMemberID)), ["me", "partner"])
        XCTAssertTrue(sample.mirrors.allSatisfy { $0.sourceCalendarTitle == "ShareCal Preview" })
        XCTAssertEqual(sample.invitations.count, 1)
        XCTAssertEqual(sample.invitations[0].creatorMemberID, "me")
        XCTAssertEqual(sample.invitations[0].inviteeMemberID, "partner")
        XCTAssertEqual(sample.comments.count, 1)
        XCTAssertEqual(sample.comments[0].authorMemberID, "partner")
    }
}

final class ShareCalModelContainerTests: XCTestCase {
    @MainActor
    func testMakesLocalContainerWhenCloudKitEntitlementsArePresent() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)

        XCTAssertNotNil(container)
    }
}
