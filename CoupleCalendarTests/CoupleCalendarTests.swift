import CloudKit
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
        XCTAssertEqual(strings.createOrOpenShareButton(isPreparing: false), "Create or Open Share")
        XCTAssertEqual(strings.defaultVisibilityLabel(for: .fullDetails), "Full details")
    }

    func testChineseProvidesPrimaryLabels() {
        let strings = ShareCalStrings(language: .chinese)

        XCTAssertEqual(strings.calendarTab, "日历")
        XCTAssertEqual(strings.invitesTab, "邀请")
        XCTAssertEqual(strings.settingsTitle, "设置")
        XCTAssertEqual(strings.createOrOpenShareButton(isPreparing: false), "创建或打开共享")
        XCTAssertEqual(strings.defaultVisibilityLabel(for: .fullDetails), "完整详情")
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

    func testSummarizesRuntimeEntitlements() {
        let diagnostic = CloudKitRuntimeEntitlementDiagnostic(
            iCloudServices: ["CloudKit"],
            containerIdentifiers: ["iCloud.com.leeberty.CoupleCalendar"],
            containerEnvironment: "Development",
            apsEnvironment: "development"
        )

        XCTAssertEqual(
            diagnostic.summary,
            "services=CloudKit containers=iCloud.com.leeberty.CoupleCalendar environment=Development aps=development"
        )
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
}

final class ShareCalSceneDelegateConfigurationTests: XCTestCase {
    func testAppDelegateUsesSceneDelegateForCloudKitShareAcceptance() {
        XCTAssertTrue(ShareCalSceneDelegateConfigurationPlan.sceneDelegateClass === ShareCalSceneDelegate.self)
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

        let localized = CloudKitSharedDatabaseImportPlan.localizedMirrors(
            [first, second],
            partnerMemberID: "partner"
        )

        XCTAssertEqual(localized.map(\.mirrorKey), ["first", "second"])
        XCTAssertEqual(localized.map(\.ownerMemberID), ["partner", "partner"])
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
            "CloudKit Production schema is missing ShareCal record types. Run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Create or Open Share."
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
            "CloudKit Production schema is missing the CloudKit Sharing system record type. Create one Development share, run Scripts/import-cloudkit-schema.sh development, deploy schema changes to Production in CloudKit Console, then retry Create or Open Share."
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
