import CloudKit
import SwiftData
import XCTest

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

        XCTAssertEqual(record.recordType, "EventInvitation")
        XCTAssertEqual(record.recordID.recordName, "history-access-request:request-record")
        XCTAssertTrue(CalendarAccessRequestRecordMapper.isTransportRecord(record))
        XCTAssertEqual(Set(record.allKeys()), [
            "creatorMemberID",
            "inviteeMemberID",
            "title",
            "startDate",
            "endDate",
            "isAllDay",
            "statusRawValue",
            "createdAt",
            "updatedAt"
        ])
        XCTAssertEqual(decoded.id, "request-record")
        XCTAssertEqual(decoded.requesterMemberID, "partner")
        XCTAssertEqual(decoded.ownerMemberID, "me")
        XCTAssertEqual(decoded.requestedStartDate, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(decoded.requestedEndDate, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(decoded.status, .pending)
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 950))
        XCTAssertEqual(decoded.cloudKitRecordName, "history-access-request:request-record")
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

    @MainActor
    func testLocalICloudDataCleanupPurgesCachedShareCalModels() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
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
        try context.save()

        try ShareCalLocalDataCleanupService.purge(modelContext: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<EventMirror>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalEventShadow>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventComment>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventInvitation>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarAccessRequest>()).count, 0)
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

    private func cleanupMirror(
        owner: String,
        key: String,
        sourceCalendarID: String = "calendar"
    ) -> EventMirror {
        EventMirror(
            id: key,
            ownerMemberID: owner,
            mirrorKey: key,
            sourceCalendarID: sourceCalendarID,
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

final class CloudKitAccessRequestWritePlanTests: XCTestCase {
    func testRequesterWritesNewHistoryRequestToAcceptedSharedZone() {
        let request = CalendarAccessRequest(
            requesterMemberID: "me",
            ownerMemberID: "_partnerOwner",
            requestedStartDate: Date(timeIntervalSince1970: 10_000),
            requestedEndDate: Date(timeIntervalSince1970: 20_000),
            sourceRawValue: CalendarAccessRequestSource.localOutgoing.rawValue
        )

        XCTAssertEqual(
            CloudKitAccessRequestWritePlan.destination(for: request, currentMemberID: "me"),
            .acceptedSharedZone
        )
    }

    func testApproverWritesHistoryRequestStatusToPrivateOwnerZone() {
        let request = CalendarAccessRequest(
            requesterMemberID: "me",
            ownerMemberID: "me",
            requestedStartDate: Date(timeIntervalSince1970: 10_000),
            requestedEndDate: Date(timeIntervalSince1970: 20_000),
            statusRawValue: CalendarAccessRequestStatus.approved.rawValue,
            sourceRawValue: CalendarAccessRequestSource.privateOwnerZone.rawValue
        )

        XCTAssertEqual(
            CloudKitAccessRequestWritePlan.destination(for: request, currentMemberID: "me"),
            .privateOwnerZone
        )
    }

    func testRequesterTargetsSharedZoneOwnedByHistoryOwner() {
        let staleZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_staleOwner")
        let targetZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_manuOwner")

        XCTAssertEqual(
            CloudKitAccessRequestSharedZonePlan.targetZoneID(
                ownerMemberID: "_manuOwner",
                acceptedSharedZoneIDs: [staleZone, targetZone]
            ),
            targetZone
        )
    }

    func testRequesterDoesNotTargetFirstSharedZoneWhenOwnerDoesNotMatchAnyZone() {
        let staleZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_staleOwner")
        let otherZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_otherOwner")

        XCTAssertNil(
            CloudKitAccessRequestSharedZonePlan.targetZoneID(
                ownerMemberID: "_manuOwner",
                acceptedSharedZoneIDs: [staleZone, otherZone]
            )
        )
    }

    func testRequesterFallsBackToOnlyAcceptedSharedZoneForLegacyOwnerID() {
        let onlyZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_manuOwner")

        XCTAssertEqual(
            CloudKitAccessRequestSharedZonePlan.targetZoneID(
                ownerMemberID: "马努",
                acceptedSharedZoneIDs: [onlyZone]
            ),
            onlyZone
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

final class CloudKitSharePermissionPlanTests: XCTestCase {
    func testConfiguresShareForInviteLinksUntilPartnerJoins() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)

        XCTAssertTrue(CloudKitSharePermissionPlan.needsLinkInvitationUpgrade(share, acceptedParticipantCount: 0))

        CloudKitSharePermissionPlan.configureForLinkInvitation(share)

        XCTAssertEqual(share.publicPermission, .readWrite)
        XCTAssertFalse(CloudKitSharePermissionPlan.needsLinkInvitationUpgrade(share, acceptedParticipantCount: 0))
    }

    func testDoesNotReopenLinkInvitationAfterPartnerJoined() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)

        XCTAssertFalse(CloudKitSharePermissionPlan.needsLinkInvitationUpgrade(share, acceptedParticipantCount: 1))
    }

    func testControllerPermissionsExposePublicInviteLinks() {
        let permissions = CloudKitSharePermissionPlan.controllerAvailablePermissions

        XCTAssertTrue(permissions.contains(.allowPublic))
        XCTAssertTrue(permissions.contains(.allowPrivate))
        XCTAssertTrue(permissions.contains(.allowReadWrite))
    }
}

final class CloudKitShareParticipantIdentityPlanTests: XCTestCase {
    func testCountsOnlyAcceptedNonOwnerParticipantsAsShared() {
        let participantIDs = CloudKitShareParticipantIdentityPlan.acceptedParticipantIDs(from: [
            CloudKitShareParticipantIdentity(
                role: .owner,
                acceptanceStatus: .accepted,
                identifier: "_owner"
            ),
            CloudKitShareParticipantIdentity(
                role: .privateUser,
                acceptanceStatus: .pending,
                identifier: "_pending"
            ),
            CloudKitShareParticipantIdentity(
                role: .privateUser,
                acceptanceStatus: .unknown,
                identifier: "_unknown"
            ),
            CloudKitShareParticipantIdentity(
                role: .privateUser,
                acceptanceStatus: .accepted,
                identifier: "_accepted"
            )
        ])

        XCTAssertEqual(participantIDs, ["_accepted"])
    }
}

final class CloudKitAccountDiagnosticTests: XCTestCase {
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

final class CloudKitShareRootMetadataPlanTests: XCTestCase {
    func testWritesStableOwnerMemberIDToShareRoot() {
        let record = CKRecord(recordType: "CoupleSpace")

        CloudKitShareRootMetadataPlan.applyOwnerMemberID("_me", to: record)

        XCTAssertEqual(record["ownerMemberID"] as? String, "_me")
    }

    func testReapplyingSameOwnerMemberIDLeavesRootUnchanged() {
        // A root that already carries the owner ID must not be re-saved on every sync:
        // each save of a shared record pushes the partner, whose sync saves their own
        // root, which pushes us back (a silent-push ping-pong).
        let record = CKRecord(recordType: "CoupleSpace")
        record["ownerMemberID"] = "_me" as CKRecordValue
        let changedBefore = Set(record.changedKeys())

        let didChange = CloudKitShareRootMetadataPlan.applyOwnerMemberID("_me", to: record)

        XCTAssertFalse(didChange)
        XCTAssertEqual(Set(record.changedKeys()), changedBefore)
    }

    func testChangingOwnerMemberIDMarksRootForSave() {
        let record = CKRecord(recordType: "CoupleSpace")
        record["ownerMemberID"] = "_old" as CKRecordValue

        let didChange = CloudKitShareRootMetadataPlan.applyOwnerMemberID("_me", to: record)

        XCTAssertTrue(didChange)
        XCTAssertEqual(record["ownerMemberID"] as? String, "_me")
    }
}

final class MemberProfileRecordMapperTests: XCTestCase {
    func testBuildsDeterministicRecordNameFromOwnerID() {
        XCTAssertEqual(
            MemberProfileRecordMapper.recordName(ownerMemberID: "_owner123"),
            "member-profile:_owner123"
        )
    }

    func testEncodesAndDecodesMemberProfileRecord() throws {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let updatedAt = Date(timeIntervalSince1970: 1_800)
        let profile = CloudKitMemberProfile(
            ownerMemberID: "_owner123",
            displayName: " Manu ",
            updatedAt: updatedAt
        )

        let record = MemberProfileRecordMapper.record(from: profile, zoneID: zoneID)
        let decodedProfile = try MemberProfileRecordMapper.memberProfile(from: record)

        XCTAssertEqual(record.recordType, "MemberProfile")
        XCTAssertEqual(record.recordID.recordName, "member-profile:_owner123")
        XCTAssertEqual(record[MemberProfileRecordMapper.Key.ownerMemberID] as? String, "_owner123")
        XCTAssertEqual(record[MemberProfileRecordMapper.Key.displayName] as? String, "Manu")
        XCTAssertEqual(record[MemberProfileRecordMapper.Key.updatedAt] as? Date, updatedAt)
        XCTAssertEqual(decodedProfile, CloudKitMemberProfile(
            ownerMemberID: "_owner123",
            displayName: "Manu",
            updatedAt: updatedAt
        ))
    }

    func testSelectsNewestPartnerDisplayNameByOwnerID() {
        let mine = CloudKitMemberProfile(
            ownerMemberID: "_me",
            displayName: "Me",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let olderPartner = CloudKitMemberProfile(
            ownerMemberID: "_partner",
            displayName: "Older name",
            updatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let newerPartner = CloudKitMemberProfile(
            ownerMemberID: "_partner",
            displayName: "Newer name",
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )

        XCTAssertEqual(
            MemberProfileDisplayPlan.partnerSyncedDisplayName(
                from: [newerPartner, mine, olderPartner],
                partnerID: "_partner"
            ),
            "Newer name"
        )
        XCTAssertNil(
            MemberProfileDisplayPlan.partnerSyncedDisplayName(
                from: [newerPartner, mine, olderPartner],
                partnerID: nil
            )
        )
    }
}

final class ShareCalSceneDelegateConfigurationTests: XCTestCase {
    func testAppDelegateUsesSceneDelegateForCloudKitShareAcceptance() {
        XCTAssertEqual(ShareCalSceneDelegateConfigurationPlan.configurationName, "Default Configuration")
        XCTAssertTrue(ShareCalSceneDelegateConfigurationPlan.acceptsColdStartShareMetadata)
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
    func testParsesEventCommentArgumentsWithSmokeTitleDefault() {
        let arguments = ["ShareCal", "-ShareCalAddEventComment", "hello there", "-ShareCalEventCommentTitle", "Own Comment Event"]

        XCTAssertEqual(ShareCalLaunchDiagnosticPlan.eventCommentBody(arguments: arguments), "hello there")
        XCTAssertEqual(ShareCalLaunchDiagnosticPlan.eventCommentTitle(arguments: arguments), "Own Comment Event")
        XCTAssertEqual(
            ShareCalLaunchDiagnosticPlan.eventCommentTitle(arguments: ["ShareCal"]),
            ShareCalSmokeTestEventPlan.title
        )
        XCTAssertNil(ShareCalLaunchDiagnosticPlan.eventCommentBody(arguments: ["ShareCal", "-ShareCalAddEventComment"]))
        XCTAssertTrue(ShareCalLaunchDiagnosticPlan.shouldProbeEventComments(arguments: ["ShareCal", "-ShareCalProbeEventComments"]))
        XCTAssertFalse(ShareCalLaunchDiagnosticPlan.shouldProbeEventComments(arguments: ["ShareCal"]))
    }

    func testPreparesPairingShareOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPlan.shouldPreparePairingShare(
                arguments: ["ShareCal", "-ShareCalPreparePairingShare"]
            )
        )
        XCTAssertFalse(ShareCalLaunchDiagnosticPlan.shouldPreparePairingShare(arguments: ["ShareCal"]))
    }

    func testParsesAcceptShareURLArgumentValue() {
        XCTAssertEqual(
            ShareCalLaunchDiagnosticPlan.acceptShareURL(
                arguments: ["ShareCal", "-ShareCalAcceptShareURL", "https://www.icloud.com/share/abc#Name"]
            ),
            URL(string: "https://www.icloud.com/share/abc#Name")
        )
        XCTAssertNil(
            ShareCalLaunchDiagnosticPlan.acceptShareURL(arguments: ["ShareCal", "-ShareCalAcceptShareURL"])
        )
        XCTAssertNil(ShareCalLaunchDiagnosticPlan.acceptShareURL(arguments: ["ShareCal"]))
    }

    func testForcesSyncOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPlan.shouldForceSync(arguments: ["ShareCal", "-ShareCalForceSync"])
        )
        XCTAssertFalse(ShareCalLaunchDiagnosticPlan.shouldForceSync(arguments: ["ShareCal"]))
    }

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

    func testBuildsSeedCalendarDraftFromISODateArguments() throws {
        let draft = ShareCalLaunchDiagnosticPlan.seedCalendarEventDraft(
            arguments: [
                "ShareCal",
                "-ShareCalSeedCalendarEvent",
                "-ShareCalSeedCalendarEventTitle",
                "Pre pairing in range",
                "-ShareCalSeedCalendarEventStart",
                "2026-06-01T09:00:00Z",
                "-ShareCalSeedCalendarEventEnd",
                "2026-06-01T10:00:00Z"
            ],
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(draft.title, "Pre pairing in range")
        XCTAssertEqual(draft.startDate, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-01T09:00:00Z")))
        XCTAssertEqual(draft.endDate, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-01T10:00:00Z")))
        XCTAssertEqual(draft.notes, ShareCalSmokeTestEventPlan.notes)
    }

    func testFallsBackToDefaultSeedDraftWhenISODateRangeIsInvalid() {
        let now = Date(timeIntervalSince1970: 1_000)
        let draft = ShareCalLaunchDiagnosticPlan.seedCalendarEventDraft(
            arguments: [
                "ShareCal",
                "-ShareCalSeedCalendarEvent",
                "-ShareCalSeedCalendarEventTitle",
                "Fallback",
                "-ShareCalSeedCalendarEventStart",
                "2026-06-01T10:00:00Z",
                "-ShareCalSeedCalendarEventEnd",
                "2026-06-01T09:00:00Z"
            ],
            now: now
        )

        XCTAssertEqual(draft, ShareCalSmokeTestEventPlan.draft(now: now, title: "Fallback"))
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

final class CloudKitBatchUpsertPlanTests: XCTestCase {
    func testBuildsMirrorRecordIDsWithServerRecordNameFallback() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpaceZone", ownerName: CKCurrentUserDefaultName)
        let existing = eventMirror(id: "event-1", cloudKitRecordName: "server-record")
        let new = eventMirror(id: "event-2", cloudKitRecordName: nil)

        let recordIDs = CloudKitBatchUpsertPlan.recordIDs(forMirrors: [existing, new], zoneID: zoneID)

        XCTAssertEqual(recordIDs.map(\.recordName), ["server-record", "work:event-2:1800"])
    }

    func testBuildsAccessRequestRecordIDsWithoutDoubleTransportPrefix() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpaceZone", ownerName: CKCurrentUserDefaultName)
        let request = CalendarAccessRequest(
            id: "request-1",
            requesterMemberID: "me",
            ownerMemberID: "_partnerOwner",
            requestedStartDate: Date(timeIntervalSince1970: 1_000),
            requestedEndDate: Date(timeIntervalSince1970: 2_000),
            cloudKitRecordName: "history-access-request:request-1"
        )

        let recordIDs = CloudKitBatchUpsertPlan.recordIDs(forAccessRequests: [request], zoneID: zoneID)
        let record = CalendarAccessRequestRecordMapper.record(from: request, zoneID: zoneID)

        XCTAssertEqual(recordIDs.map(\.recordName), ["history-access-request:request-1"])
        XCTAssertEqual(record.recordID.recordName, "history-access-request:request-1")
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
        XCTAssertEqual(
            CloudKitForegroundQueryPlan.desiredKeys(forRecordType: MemberProfileRecordMapper.recordType),
            [
                MemberProfileRecordMapper.Key.ownerMemberID,
                MemberProfileRecordMapper.Key.displayName,
                MemberProfileRecordMapper.Key.updatedAt
            ] + MemberProfileRecordMapper.Key.avatarKeys
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
    func testTreatsMissingMemberProfileRecordTypeAsEmpty() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: MemberProfile"]
        )

        XCTAssertTrue(
            CloudKitRecordQueryFailurePlan.canTreatMissingRecordTypeAsEmpty(
                recordType: MemberProfileRecordMapper.recordType,
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

final class MemberProfileAvatarRecordTests: XCTestCase {
    private let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")

    func testRoundTripsTextAvatar() throws {
        let profile = CloudKitMemberProfile(
            ownerMemberID: "_owner",
            displayName: "Lee",
            updatedAt: Date(timeIntervalSince1970: 1_800),
            avatar: MemberAvatar(text: "Lee", background: .sand)
        )

        let record = MemberProfileRecordMapper.record(from: profile, zoneID: zoneID)

        XCTAssertEqual(record[MemberProfileRecordMapper.Key.avatarText] as? String, "Lee")
        XCTAssertEqual(record[MemberProfileRecordMapper.Key.avatarBackground] as? String, "sand")
        XCTAssertNil(record[MemberProfileRecordMapper.Key.avatarImage])
        XCTAssertEqual(try MemberProfileRecordMapper.memberProfile(from: record), profile)
    }

    func testRoundTripsPhotoAvatar() throws {
        let photo = Data([0xFF, 0xD8, 0xFF])
        let profile = CloudKitMemberProfile(
            ownerMemberID: "_owner",
            displayName: "Lee",
            updatedAt: Date(timeIntervalSince1970: 1_800),
            avatar: MemberAvatar(imageData: photo)
        )

        let record = MemberProfileRecordMapper.record(from: profile, zoneID: zoneID)

        XCTAssertEqual(record[MemberProfileRecordMapper.Key.avatarImage] as? Data, photo)
        XCTAssertEqual(try MemberProfileRecordMapper.memberProfile(from: record).avatar, MemberAvatar(imageData: photo))
    }

    func testProfileWithoutAvatarNeverTouchesAvatarKeys() {
        let profile = CloudKitMemberProfile(
            ownerMemberID: "_owner",
            displayName: "Lee",
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let record = MemberProfileRecordMapper.record(from: profile, zoneID: zoneID)

        for key in MemberProfileRecordMapper.Key.avatarKeys {
            XCTAssertFalse(record.changedKeys().contains(key), key)
        }
    }

    func testReapplyingSameAvatarLeavesOtherAvatarKeysUntouched() {
        let photo = Data([0x01, 0x02, 0x03])
        let record = CKRecord(recordType: MemberProfileRecordMapper.recordType)
        record[MemberProfileRecordMapper.Key.avatarImage] = photo as NSData
        let changedBefore = Set(record.changedKeys())

        MemberProfileRecordMapper.applyAvatar(MemberAvatar(imageData: photo), to: record)

        XCTAssertEqual(Set(record.changedKeys()), changedBefore)
    }

    func testClearingAvatarRemovesStoredValues() {
        let record = CKRecord(recordType: MemberProfileRecordMapper.recordType)
        MemberProfileRecordMapper.applyAvatar(MemberAvatar(text: "Lee", background: .ink), to: record)

        MemberProfileRecordMapper.applyAvatar(nil, to: record)

        XCTAssertNil(record[MemberProfileRecordMapper.Key.avatarText])
        XCTAssertNil(record[MemberProfileRecordMapper.Key.avatarBackground])
        XCTAssertNil(MemberProfileRecordMapper.avatar(from: record))
    }

    func testUnchangedProfileProducesNothingToSave() {
        // The profile is rebuilt on every paired sync. When nothing the partner can see
        // has changed, no key (not even updatedAt) may be touched, so the record is not
        // saved and no silent push reaches the partner.
        let photo = Data([0x01, 0x02, 0x03])
        let existing = CKRecord(recordType: MemberProfileRecordMapper.recordType)
        existing[MemberProfileRecordMapper.Key.ownerMemberID] = "_owner" as CKRecordValue
        existing[MemberProfileRecordMapper.Key.displayName] = "Lee" as CKRecordValue
        existing[MemberProfileRecordMapper.Key.updatedAt] = Date(timeIntervalSince1970: 1_000) as CKRecordValue
        existing[MemberProfileRecordMapper.Key.avatarImage] = photo as NSData
        let changedBefore = Set(existing.changedKeys())
        let profile = CloudKitMemberProfile(
            ownerMemberID: " _owner ",
            displayName: " Lee ",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            avatar: MemberAvatar(imageData: photo)
        )

        let didChange = MemberProfileRecordMapper.apply(profile, to: existing)

        XCTAssertFalse(didChange)
        XCTAssertEqual(Set(existing.changedKeys()), changedBefore)
        XCTAssertEqual(existing[MemberProfileRecordMapper.Key.updatedAt] as? Date, Date(timeIntervalSince1970: 1_000))
    }

    func testChangedAvatarBumpsUpdatedAtAndNeedsSave() {
        let existing = CKRecord(recordType: MemberProfileRecordMapper.recordType)
        existing[MemberProfileRecordMapper.Key.ownerMemberID] = "_owner" as CKRecordValue
        existing[MemberProfileRecordMapper.Key.displayName] = "Lee" as CKRecordValue
        existing[MemberProfileRecordMapper.Key.updatedAt] = Date(timeIntervalSince1970: 1_000) as CKRecordValue
        let profile = CloudKitMemberProfile(
            ownerMemberID: "_owner",
            displayName: "Lee",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            avatar: MemberAvatar(text: "Lee", background: .teal)
        )

        let didChange = MemberProfileRecordMapper.apply(profile, to: existing)

        XCTAssertTrue(didChange)
        XCTAssertEqual(existing[MemberProfileRecordMapper.Key.updatedAt] as? Date, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(existing[MemberProfileRecordMapper.Key.avatarText] as? String, "Lee")
    }

    func testChangedDisplayNameBumpsUpdatedAt() {
        let existing = CKRecord(recordType: MemberProfileRecordMapper.recordType)
        existing[MemberProfileRecordMapper.Key.ownerMemberID] = "_owner" as CKRecordValue
        existing[MemberProfileRecordMapper.Key.displayName] = "Lee" as CKRecordValue
        existing[MemberProfileRecordMapper.Key.updatedAt] = Date(timeIntervalSince1970: 1_000) as CKRecordValue
        let profile = CloudKitMemberProfile(
            ownerMemberID: "_owner",
            displayName: "Wild",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let didChange = MemberProfileRecordMapper.apply(profile, to: existing)

        XCTAssertTrue(didChange)
        XCTAssertEqual(existing[MemberProfileRecordMapper.Key.displayName] as? String, "Wild")
        XCTAssertEqual(existing[MemberProfileRecordMapper.Key.updatedAt] as? Date, Date(timeIntervalSince1970: 2_000))
    }

    func testNewProfileRecordIsAlwaysSaved() {
        let profile = CloudKitMemberProfile(
            ownerMemberID: "_owner",
            displayName: "Lee",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let record = MemberProfileRecordMapper.record(from: profile, zoneID: zoneID)

        XCTAssertEqual(record[MemberProfileRecordMapper.Key.updatedAt] as? Date, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(
            Set(record.changedKeys()),
            [MemberProfileRecordMapper.Key.ownerMemberID, MemberProfileRecordMapper.Key.displayName, MemberProfileRecordMapper.Key.updatedAt]
        )
    }

    func testPartnerSyncedAvatarComesFromNewestPartnerProfile() {
        let older = CloudKitMemberProfile(
            ownerMemberID: "_partner",
            displayName: "Rain",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            avatar: MemberAvatar(text: "Old")
        )
        let newer = CloudKitMemberProfile(
            ownerMemberID: "_partner",
            displayName: "Rain",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            avatar: MemberAvatar(text: "雨", background: .coral)
        )
        let mine = CloudKitMemberProfile(
            ownerMemberID: "_me",
            displayName: "Lee",
            updatedAt: Date(timeIntervalSince1970: 3_000),
            avatar: MemberAvatar(text: "Lee")
        )

        XCTAssertEqual(
            MemberProfileDisplayPlan.partnerSyncedAvatar(from: [older, mine, newer], partnerID: " _partner "),
            MemberAvatar(text: "雨", background: .coral)
        )
        XCTAssertNil(MemberProfileDisplayPlan.partnerSyncedAvatar(from: [older, mine, newer], partnerID: nil))
    }

    func testRetriesWithoutAvatarOnlyForSchemaRejections() {
        let withAvatar = CloudKitMemberProfile(
            ownerMemberID: "_me",
            displayName: "Lee",
            updatedAt: .now,
            avatar: MemberAvatar(text: "Lee")
        )
        let withoutAvatar = CloudKitMemberProfile(ownerMemberID: "_me", displayName: "Lee", updatedAt: .now)
        let invalid = CKError(.invalidArguments)
        let partial = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "member-profile:_me"): CKError(.invalidArguments)]
        ])

        XCTAssertTrue(MemberProfileAvatarSchemaFallbackPlan.shouldRetryWithoutAvatar(error: invalid, profile: withAvatar))
        XCTAssertTrue(MemberProfileAvatarSchemaFallbackPlan.shouldRetryWithoutAvatar(error: partial, profile: withAvatar))
        XCTAssertFalse(MemberProfileAvatarSchemaFallbackPlan.shouldRetryWithoutAvatar(error: invalid, profile: withoutAvatar))
        XCTAssertFalse(MemberProfileAvatarSchemaFallbackPlan.shouldRetryWithoutAvatar(error: CKError(.networkUnavailable), profile: withAvatar))
    }
}
