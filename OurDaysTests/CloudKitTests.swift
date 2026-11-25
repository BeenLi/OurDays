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
        XCTAssertNil(decoded.stableKey, "a record from an older version has no stable key")

        mirror.stableKey = "s1:abc"
        XCTAssertEqual(try EventMirrorRecordMapper.eventMirror(from: EventMirrorRecordMapper.record(from: mirror, zoneID: zoneID)).stableKey, "s1:abc")

        // Writing a mirror without a key never clears one another device wrote.
        let existing = EventMirrorRecordMapper.record(from: mirror, zoneID: zoneID)
        mirror.stableKey = nil
        let rewritten = EventMirrorRecordMapper.record(from: mirror, zoneID: zoneID, existingRecord: existing)
        XCTAssertEqual(rewritten[EventMirrorRecordMapper.Key.stableKey] as? String, "s1:abc")
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

final class CloudKitStopSharingPolicyTests: XCTestCase {
    func testNoopsWhenRootHasNoShareReference() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )

        XCTAssertNil(CloudKitStopSharingPolicy.shareRecordIDToDelete(from: root))
    }

    func testDeletesActiveShareRecordWhenRootIsShared() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)

        XCTAssertEqual(CloudKitStopSharingPolicy.shareRecordIDToDelete(from: root), share.recordID)
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

    @MainActor
    func testSharedOwnerDataCleanupAlsoDropsCommentsThePartnerWroteOnMyEvents() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.insert(cleanupMirror(owner: "_me", key: "mine"))
        context.insert(EventComment(eventMirrorID: "mine", authorMemberID: "_ex", body: "theirs on mine"))
        context.insert(EventComment(eventMirrorID: "mine", authorMemberID: "_me", body: "mine on mine"))
        context.insert(EventInvitation(
            creatorMemberID: "_me", inviteeMemberID: "_ex", title: "old invite",
            startDate: Date(timeIntervalSince1970: 1_000), endDate: Date(timeIntervalSince1970: 2_000),
            location: nil, notes: nil
        ))
        try context.save()

        try ShareCalLocalDataCleanupService.purgeSharedOwnerData(ownerMemberIDs: ["_ex"], modelContext: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<EventComment>()).map(\.body), ["mine on mine"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventInvitation>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventMirror>()).count, 1)
    }

    @MainActor
    func testForeignPartnerDataCleanupKeepsMeAndCurrentPartnerAndPlaceholders() throws {
        let container = try ShareCalModelContainer.make(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        context.insert(EventComment(eventMirrorID: "e", authorMemberID: "_me", body: "me"))
        context.insert(EventComment(eventMirrorID: "e", authorMemberID: "_partner", body: "partner"))
        context.insert(EventComment(eventMirrorID: "e", authorMemberID: "_ex", body: "ex"))
        context.insert(EventInvitation(
            creatorMemberID: "_me", inviteeMemberID: "partner", title: "placeholder invitee",
            startDate: Date(timeIntervalSince1970: 1_000), endDate: Date(timeIntervalSince1970: 2_000),
            location: nil, notes: nil
        ))
        context.insert(EventInvitation(
            creatorMemberID: "_ex", inviteeMemberID: "_me", title: "from ex",
            startDate: Date(timeIntervalSince1970: 1_000), endDate: Date(timeIntervalSince1970: 2_000),
            location: nil, notes: nil
        ))
        context.insert(CalendarAccessRequest(
            requesterMemberID: "_ex", ownerMemberID: "_me",
            requestedStartDate: Date(timeIntervalSince1970: 1_000), requestedEndDate: Date(timeIntervalSince1970: 2_000)
        ))
        context.insert(CalendarAccessRequest(
            requesterMemberID: "_partner", ownerMemberID: "_me",
            requestedStartDate: Date(timeIntervalSince1970: 1_000), requestedEndDate: Date(timeIntervalSince1970: 2_000)
        ))
        try context.save()

        try ShareCalLocalDataCleanupService.purgeForeignPartnerData(
            currentMemberID: "_me", partnerID: "_partner", modelContext: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<EventComment>()).map(\.body).sorted(), ["me", "partner"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<EventInvitation>()).map(\.title), ["placeholder invitee"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarAccessRequest>()).map(\.requesterMemberID), ["_partner"])
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

final class CloudKitExPartnerCleanupPolicyTests: XCTestCase {
    func testDeletesForeignCommentsAndEveryInvitationRecordButKeepsMyOwnComments() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let mine = CKRecord(recordType: CommentRecordMapper.recordType, recordID: CKRecord.ID(recordName: "c-mine", zoneID: zoneID))
        mine[CommentRecordMapper.Key.authorMemberID] = "_me" as CKRecordValue
        let theirs = CKRecord(recordType: CommentRecordMapper.recordType, recordID: CKRecord.ID(recordName: "c-theirs", zoneID: zoneID))
        theirs[CommentRecordMapper.Key.authorMemberID] = " _ex " as CKRecordValue
        let invitation = CKRecord(recordType: InvitationRecordMapper.recordType, recordID: CKRecord.ID(recordName: "inv", zoneID: zoneID))
        let transport = CKRecord(
            recordType: CalendarAccessRequestRecordMapper.transportRecordType,
            recordID: CKRecord.ID(recordName: "history-access-request:req", zoneID: zoneID)
        )

        let ids = CloudKitExPartnerCleanupPolicy.recordIDsToDelete(
            commentRecords: [mine, theirs],
            invitationRecords: [invitation, transport],
            currentMemberID: "_me"
        )

        XCTAssertEqual(ids.map(\.recordName).sorted(), ["c-theirs", "history-access-request:req", "inv"])
    }
}

final class CloudKitInvitationWritePolicyTests: XCTestCase {
    func testCreatorWritesInvitationToPrivateOwnerZone() {
        XCTAssertEqual(
            CloudKitInvitationWritePolicy.destination(creatorMemberID: "me", currentMemberID: "me"),
            .privateOwnerZone
        )
    }

    func testInviteeWritesInvitationStatusBackToAcceptedSharedZone() {
        XCTAssertEqual(
            CloudKitInvitationWritePolicy.destination(creatorMemberID: "partner", currentMemberID: "me"),
            .acceptedSharedZone
        )
    }
}

final class CloudKitAccessRequestWritePolicyTests: XCTestCase {
    func testRequesterWritesNewHistoryRequestToAcceptedSharedZone() {
        let request = CalendarAccessRequest(
            requesterMemberID: "me",
            ownerMemberID: "_partnerOwner",
            requestedStartDate: Date(timeIntervalSince1970: 10_000),
            requestedEndDate: Date(timeIntervalSince1970: 20_000),
            sourceRawValue: CalendarAccessRequestSource.localOutgoing.rawValue
        )

        XCTAssertEqual(
            CloudKitAccessRequestWritePolicy.destination(for: request, currentMemberID: "me"),
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
            CloudKitAccessRequestWritePolicy.destination(for: request, currentMemberID: "me"),
            .privateOwnerZone
        )
    }

    func testRequesterTargetsSharedZoneOwnedByHistoryOwner() {
        let staleZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_staleOwner")
        let targetZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_manuOwner")

        XCTAssertEqual(
            CloudKitAccessRequestSharedZonePolicy.targetZoneID(
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
            CloudKitAccessRequestSharedZonePolicy.targetZoneID(
                ownerMemberID: "_manuOwner",
                acceptedSharedZoneIDs: [staleZone, otherZone]
            )
        )
    }

    func testRequesterFallsBackToOnlyAcceptedSharedZoneForLegacyOwnerID() {
        let onlyZone = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_manuOwner")

        XCTAssertEqual(
            CloudKitAccessRequestSharedZonePolicy.targetZoneID(
                ownerMemberID: "马努",
                acceptedSharedZoneIDs: [onlyZone]
            ),
            onlyZone
        )
    }
}

final class CloudKitRootLookupPolicyTests: XCTestCase {
    func testOnlyUnknownItemMeansTheRootIsMissing() {
        let unknownItem = NSError(domain: CKError.errorDomain, code: CKError.Code.unknownItem.rawValue)
        let serverRejectedRequest = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue)

        XCTAssertTrue(CloudKitRootLookupPolicy.meansRecordMissing(unknownItem))
        // A rejected read used to count as "missing", which wrote a fresh root over a
        // shared one and then failed to share it again.
        XCTAssertFalse(CloudKitRootLookupPolicy.meansRecordMissing(serverRejectedRequest))
        XCTAssertTrue(CloudKitRootLookupPolicy.isWorthRetrying(serverRejectedRequest))
    }

    func testDoesNotRetryAuthenticationFailure() {
        let notAuthenticated = NSError(domain: CKError.errorDomain, code: CKError.Code.notAuthenticated.rawValue)

        XCTAssertFalse(CloudKitRootLookupPolicy.meansRecordMissing(notAuthenticated))
        XCTAssertFalse(CloudKitRootLookupPolicy.isWorthRetrying(notAuthenticated))
    }
}

final class CloudKitBatchSizePolicyTests: XCTestCase {
    func testSplitsIntoRequestsUnderCloudKitsLimit() {
        let batches = CloudKitBatchSizePolicy.batches(Array(0..<450))

        XCTAssertEqual(batches.map(\.count), [200, 200, 50])
        XCTAssertEqual(batches.flatMap { $0 }, Array(0..<450))
        XCTAssertTrue(CloudKitBatchSizePolicy.batches([Int]()).isEmpty)
    }
}

final class CloudKitZoneReadinessTests: XCTestCase {
    func testZoneMissingErrorsForgetTheConfirmedZone() {
        let zoneNotFound = NSError(domain: CKError.errorDomain, code: CKError.Code.zoneNotFound.rawValue)
        let userDeletedZone = NSError(domain: CKError.errorDomain, code: CKError.Code.userDeletedZone.rawValue)
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["mirror": zoneNotFound]]
        )

        XCTAssertTrue(CloudKitZoneReadinessPolicy.meansZoneMissing(zoneNotFound))
        XCTAssertTrue(CloudKitZoneReadinessPolicy.meansZoneMissing(userDeletedZone))
        XCTAssertTrue(CloudKitZoneReadinessPolicy.meansZoneMissing(partial))
    }

    func testOtherFailuresKeepTheConfirmedZone() {
        let unknownItem = NSError(domain: CKError.errorDomain, code: CKError.Code.unknownItem.rawValue)
        let networkFailure = NSError(domain: CKError.errorDomain, code: CKError.Code.networkFailure.rawValue)
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["mirror": unknownItem]]
        )

        XCTAssertFalse(CloudKitZoneReadinessPolicy.meansZoneMissing(unknownItem))
        XCTAssertFalse(CloudKitZoneReadinessPolicy.meansZoneMissing(networkFailure))
        XCTAssertFalse(CloudKitZoneReadinessPolicy.meansZoneMissing(partial))
        XCTAssertFalse(CloudKitZoneReadinessPolicy.meansZoneMissing(NSError(domain: "other", code: 26)))
    }

    func testReadinessIsRememberedPerContainerUntilReset() {
        let readiness = CloudKitZoneReadiness()
        XCTAssertFalse(readiness.isReady("a"))

        readiness.markReady("a")
        XCTAssertTrue(readiness.isReady("a"))
        XCTAssertFalse(readiness.isReady("b"))

        readiness.reset("a")
        XCTAssertFalse(readiness.isReady("a"))
    }
}

final class CloudKitSharePermissionPolicyTests: XCTestCase {
    func testConfiguresShareForInviteLinksUntilPartnerJoins() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)

        XCTAssertTrue(CloudKitSharePermissionPolicy.needsLinkInvitationUpgrade(share, acceptedParticipantCount: 0))

        CloudKitSharePermissionPolicy.configureForLinkInvitation(share)

        XCTAssertEqual(share.publicPermission, .readWrite)
        XCTAssertFalse(CloudKitSharePermissionPolicy.needsLinkInvitationUpgrade(share, acceptedParticipantCount: 0))
    }

    func testDoesNotReopenLinkInvitationAfterPartnerJoined() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let root = CKRecord(
            recordType: "CoupleSpace",
            recordID: CKRecord.ID(recordName: CloudKitCoupleSpaceService.rootRecordName, zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)

        XCTAssertFalse(CloudKitSharePermissionPolicy.needsLinkInvitationUpgrade(share, acceptedParticipantCount: 1))
    }

    func testControllerPermissionsOfferOnlyPublicReadWriteInviteLinks() {
        let permissions = CloudKitSharePermissionPolicy.controllerAvailablePermissions

        XCTAssertTrue(permissions.contains(.allowPublic))
        XCTAssertTrue(permissions.contains(.allowReadWrite))
        XCTAssertFalse(permissions.contains(.allowPrivate))
    }
}

final class CloudKitShareParticipantIdentityPolicyTests: XCTestCase {
    func testCountsOnlyAcceptedNonOwnerParticipantsAsShared() {
        let participantIDs = CloudKitShareParticipantIdentityPolicy.acceptedParticipantIDs(from: [
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

final class CloudKitShareRootMetadataPolicyTests: XCTestCase {
    func testWritesStableOwnerMemberIDToShareRoot() {
        let record = CKRecord(recordType: "CoupleSpace")

        CloudKitShareRootMetadataPolicy.applyOwnerMemberID("_me", to: record)

        XCTAssertEqual(record["ownerMemberID"] as? String, "_me")
    }

    func testReapplyingSameOwnerMemberIDLeavesRootUnchanged() {
        // A root that already carries the owner ID must not be re-saved on every sync:
        // each save of a shared record pushes the partner, whose sync saves their own
        // root, which pushes us back (a silent-push ping-pong).
        let record = CKRecord(recordType: "CoupleSpace")
        record["ownerMemberID"] = "_me" as CKRecordValue
        let changedBefore = Set(record.changedKeys())

        let didChange = CloudKitShareRootMetadataPolicy.applyOwnerMemberID("_me", to: record)

        XCTAssertFalse(didChange)
        XCTAssertEqual(Set(record.changedKeys()), changedBefore)
    }

    func testChangingOwnerMemberIDMarksRootForSave() {
        let record = CKRecord(recordType: "CoupleSpace")
        record["ownerMemberID"] = "_old" as CKRecordValue

        let didChange = CloudKitShareRootMetadataPolicy.applyOwnerMemberID("_me", to: record)

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
            MemberProfileDisplayPolicy.partnerSyncedDisplayName(
                from: [newerPartner, mine, olderPartner],
                partnerID: "_partner"
            ),
            "Newer name"
        )
        XCTAssertNil(
            MemberProfileDisplayPolicy.partnerSyncedDisplayName(
                from: [newerPartner, mine, olderPartner],
                partnerID: nil
            )
        )
    }
}

final class ShareCalSceneDelegateConfigurationTests: XCTestCase {
    func testAppDelegateUsesSceneDelegateForCloudKitShareAcceptance() {
        XCTAssertEqual(ShareCalSceneDelegateConfigurationPolicy.configurationName, "Default Configuration")
        XCTAssertTrue(ShareCalSceneDelegateConfigurationPolicy.acceptsColdStartShareMetadata)
        XCTAssertTrue(ShareCalSceneDelegateConfigurationPolicy.sceneDelegateClass === ShareCalSceneDelegate.self)
    }
}

final class CloudKitSharedDatabaseImportPolicyTests: XCTestCase {
    func testSelectsCoupleSpaceZonesForAcceptedSharesRegardlessOwnerName() {
        let acceptedShareZone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_partnerOwner"))
        let unrelatedZone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "OtherZone", ownerName: "_partnerOwner"))

        let zoneIDs = CloudKitSharedDatabaseImportPolicy.coupleSpaceZoneIDs(
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

        let localized = CloudKitSharedDatabaseImportPolicy.identifiedMirrors(
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

    func testAtomicSavePrefersTheFailingRecordOverAtomicFailureBystanders() {
        // Start Pairing saves the root and its new CKShare atomically. When the share
        // fails, the root fails too with "Atomic failure", which hid the real reason.
        let rootID = CKRecord.ID(recordName: "couple-space-root")
        let shareID = CKRecord.ID(recordName: "share-1")
        let atomicFailure = NSError(domain: CKError.errorDomain, code: CKError.Code.batchRequestFailed.rawValue)
        let shareFailure = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue)
        let results: CloudKitModifyRecordResults = (
            saveResults: [rootID: .failure(atomicFailure), shareID: .failure(shareFailure)],
            deleteResults: [:]
        )

        XCTAssertThrowsError(try CloudKitModifyRecordResultValidator.validate(results)) { error in
            XCTAssertEqual((error as NSError).code, CKError.Code.serverRejectedRequest.rawValue)
        }
    }
}

final class CloudKitShareRacePolicyTests: XCTestCase {
    func testShareConflictsInsideAtomicFailureMayMeanAnotherDeviceSharedTheRoot() {
        for code in [CKError.Code.alreadyShared, .serverRecordChanged, .serverRejectedRequest] {
            let error = NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.partialFailure.rawValue,
                userInfo: [CKPartialErrorsByItemIDKey: [
                    CKRecord.ID(recordName: "couple-space-root"): NSError(domain: CKError.errorDomain, code: CKError.Code.batchRequestFailed.rawValue),
                    CKRecord.ID(recordName: "share-1"): NSError(domain: CKError.errorDomain, code: code.rawValue)
                ]]
            )
            XCTAssertTrue(CloudKitShareRacePolicy.mayHaveLostShareRace(error), "\(code)")
        }
    }

    func testOtherFailuresAreNotTreatedAsARace() {
        XCTAssertFalse(CloudKitShareRacePolicy.mayHaveLostShareRace(NSError(domain: CKError.errorDomain, code: CKError.Code.quotaExceeded.rawValue)))
        XCTAssertFalse(CloudKitShareRacePolicy.mayHaveLostShareRace(NSError(domain: NSCocoaErrorDomain, code: 4)))
    }
}

final class CloudKitPrimaryErrorPolicyTests: XCTestCase {
    func testUnwrapsPartialFailureToTheNonAtomicItemError() {
        let atomicFailure = NSError(domain: CKError.errorDomain, code: CKError.Code.batchRequestFailed.rawValue)
        let quota = NSError(domain: CKError.errorDomain, code: CKError.Code.quotaExceeded.rawValue)
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [
                CKRecord.ID(recordName: "a"): atomicFailure,
                CKRecord.ID(recordName: "b"): quota
            ]]
        )

        XCTAssertEqual((CloudKitPrimaryErrorPolicy.primaryError(error) as NSError).code, CKError.Code.quotaExceeded.rawValue)
    }

    func testKeepsAtomicFailureWhenNothingElseIsThere() {
        let atomicFailure = NSError(domain: CKError.errorDomain, code: CKError.Code.batchRequestFailed.rawValue)

        XCTAssertEqual((CloudKitPrimaryErrorPolicy.primaryError(atomicFailure) as NSError).code, CKError.Code.batchRequestFailed.rawValue)
    }

    func testLeavesOtherErrorsAlone() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 4)

        XCTAssertTrue((CloudKitPrimaryErrorPolicy.primaryError(error) as NSError) === error)
    }
}

final class CloudKitSharingFailureMessageTests: XCTestCase {
    func testExplainsServerRejectedRequestAsEnvironmentOrSchemaProblem() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue)

        XCTAssertEqual(
            CloudKitSharingFailureMessage.userFacingMessage(for: error, environment: "Development", language: .english),
            "CloudKit rejected private database writes for this container. For Development builds, sign in on this simulator with an Apple Account that belongs to the Apple Developer team, or deploy the CloudKit schema and test a Production/TestFlight build."
        )
    }

    func testProductionServerRejectedRequestDoesNotMentionDevelopmentSetup() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue)

        let chinese = CloudKitSharingFailureMessage.userFacingMessage(for: error, environment: "Production", language: .chinese)
        let english = CloudKitSharingFailureMessage.userFacingMessage(for: error, environment: "Production", language: .english)

        XCTAssertTrue(chinese.contains("iCloud"))
        XCTAssertFalse(chinese.contains("Development"))
        XCTAssertFalse(english.contains("Development"))
        XCTAssertFalse(english.contains("simulator"))
    }

    func testProductionServerRejectedRequestCarriesServerReasonAndRequestID() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [
                "ServerErrorDescription": "Invalid share permission",
                NSLocalizedDescriptionKey: "Server Rejected Request"
            ]
        )

        let message = CloudKitSharingFailureMessage.userFacingMessage(for: error, environment: "Production", language: .chinese)

        XCTAssertTrue(message.hasPrefix("iCloud 暂时没有接受这次保存。"))
        XCTAssertTrue(message.hasSuffix("\nCKError 15 · Invalid share permission"))
    }

    func testServerDetailParsesMessageAndRequestIDFromDescription() {
        final class DescribedError: NSError {
            override var description: String {
                #"<CKError 0x1: "Server Rejected Request" (15/2000); server message = "Internal server error"; op = 1A2B; uuid = 0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0; container ID = "iCloud.x">"#
            }
        }
        let error = DescribedError(domain: CKError.errorDomain, code: 15)

        XCTAssertEqual(
            CloudKitSharingFailureMessage.serverDetail(for: error),
            "CKError 15 · Internal server error · 0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
        )
    }

    func testQuotaExceededSaysICloudStorageIsFullInAppLanguage() {
        let error = NSError(domain: CKError.errorDomain, code: CKError.Code.quotaExceeded.rawValue)

        XCTAssertTrue(
            CloudKitSharingFailureMessage.userFacingMessage(for: error, environment: "Production", language: .chinese)
                .hasPrefix("你的 iCloud 储存空间已满")
        )
        XCTAssertTrue(
            CloudKitSharingFailureMessage.userFacingMessage(for: error, environment: "Production", language: .english)
                .hasPrefix("Your iCloud storage is full")
        )
    }

    func testQuotaExceededInsidePartialFailureIsRecognized() {
        let itemError = NSError(domain: CKError.errorDomain, code: CKError.Code.quotaExceeded.rawValue)
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "a"): itemError]]
        )

        XCTAssertTrue(CloudKitSharingFailureMessage.isQuotaExceeded(error))
    }

    func testPartialFailureShowsTheRealItemReasonInsteadOfAtomicFailure() {
        let atomicFailure = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.batchRequestFailed.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Atomic failure"]
        )
        let shareFailure = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: ["ServerErrorDescription": "Invalid share permission"]
        )
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [
                CKRecord.ID(recordName: "couple-space-root"): atomicFailure,
                CKRecord.ID(recordName: "share-1"): shareFailure
            ]]
        )

        let message = CloudKitSharingFailureMessage.userFacingMessage(for: error, environment: "Production", language: .english)

        XCTAssertFalse(message.contains("Atomic failure"))
        XCTAssertTrue(message.hasSuffix("\nCKError 15 · Invalid share permission"))
    }

    func testOtherCloudKitErrorsCarryCodeForConsoleLookup() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.invalidArguments.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Bad field"]
        )

        XCTAssertEqual(CloudKitSharingFailureMessage.userFacingMessage(for: error), "Bad field\nCKError 12")
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

final class SyncCancellationPolicyTests: XCTestCase {
    func testCloudKitOperationCancelledIsCancellation() {
        // What the red banner showed: "Operation CACC1939BC788D68 was cancelled".
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.operationCancelled.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Operation CACC1939BC788D68 was cancelled"]
        )
        XCTAssertTrue(SyncCancellationPolicy.isCancellation(error))
    }

    func testSwiftAndURLCancellationAreCancellation() {
        XCTAssertTrue(SyncCancellationPolicy.isCancellation(CancellationError()))
        XCTAssertTrue(SyncCancellationPolicy.isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
    }

    func testPartialFailureIsCancellationOnlyWhenEveryItemWasCancelled() {
        let cancelled = NSError(domain: CKError.errorDomain, code: CKError.Code.operationCancelled.rawValue)
        let conflict = NSError(domain: CKError.errorDomain, code: CKError.Code.serverRecordChanged.rawValue)
        func partial(_ itemErrors: [Error]) -> NSError {
            let byID = Dictionary(uniqueKeysWithValues: itemErrors.enumerated().map { index, error in
                (CKRecord.ID(recordName: "record-\(index)") as AnyHashable, error)
            })
            return NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.partialFailure.rawValue,
                userInfo: [CKPartialErrorsByItemIDKey: byID]
            )
        }

        XCTAssertTrue(SyncCancellationPolicy.isCancellation(partial([cancelled, cancelled])))
        XCTAssertFalse(SyncCancellationPolicy.isCancellation(partial([cancelled, conflict])))
        XCTAssertFalse(SyncCancellationPolicy.isCancellation(partial([])))
    }

    func testRealFailuresAreNotCancellation() {
        XCTAssertFalse(SyncCancellationPolicy.isCancellation(
            NSError(domain: CKError.errorDomain, code: CKError.Code.networkUnavailable.rawValue)
        ))
        XCTAssertFalse(SyncCancellationPolicy.isCancellation(
            NSError(domain: CKError.errorDomain, code: CKError.Code.serverRejectedRequest.rawValue)
        ))
        XCTAssertFalse(SyncCancellationPolicy.isCancellation(
            NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        ))
    }
}

final class ShareCalLaunchDiagnosticPolicyTests: XCTestCase {
    func testParsesEventCommentArgumentsWithSmokeTitleDefault() {
        let arguments = ["ShareCal", "-ShareCalAddEventComment", "hello there", "-ShareCalEventCommentTitle", "Own Comment Event"]

        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.eventCommentBody(arguments: arguments), "hello there")
        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.eventCommentTitle(arguments: arguments), "Own Comment Event")
        XCTAssertEqual(
            ShareCalLaunchDiagnosticPolicy.eventCommentTitle(arguments: ["ShareCal"]),
            ShareCalSmokeTestEventPolicy.title
        )
        XCTAssertNil(ShareCalLaunchDiagnosticPolicy.eventCommentBody(arguments: ["ShareCal", "-ShareCalAddEventComment"]))
        XCTAssertTrue(ShareCalLaunchDiagnosticPolicy.shouldProbeEventComments(arguments: ["ShareCal", "-ShareCalProbeEventComments"]))
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.shouldProbeEventComments(arguments: ["ShareCal"]))
    }

    func testPurgeOnlyTargetsTheSmokeScriptsThrowawayEvents() {
        XCTAssertTrue(ShareCalLaunchDiagnosticPolicy.shouldPurgeSmokeTestData(arguments: ["ShareCal", "-ShareCalPurgeSmokeTestData"]))
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.shouldPurgeSmokeTestData(arguments: ["ShareCal"]))
        XCTAssertTrue(ShareCalLaunchDiagnosticPolicy.shouldHardDeleteOwnTombstones(arguments: ["ShareCal", "-ShareCalHardDeleteOwnTombstones"]))
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.shouldHardDeleteOwnTombstones(arguments: ["ShareCal"]))

        XCTAssertTrue(ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: "Own Comment Event 19346"))
        XCTAssertTrue(ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: "Series Comment Event 7"))
        // The shared smoke event is refreshed by every run, and anything without the
        // script's numbered title may be a person's own event.
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: ShareCalSmokeTestEventPolicy.title))
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: "Own Comment Event "))
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: "Own Comment Event dinner"))
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: "Dinner"))
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.isLeftoverSmokeEvent(title: nil))
    }

    func testParsesSeriesSmokeArguments() {
        let arguments = [
            "ShareCal", "-ShareCalSeedDailySeriesTitled", "Series", "-ShareCalMoveSeriesTitled", "Series",
            "-ShareCalMoveSeriesFromOccurrence", "0", "-ShareCalDeleteSeriesTitled", "Old Series",
            "-ShareCalEventCommentOccurrence", "3"
        ]

        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.seedDailySeriesTitle(arguments: arguments), "Series")
        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.moveSeriesTitle(arguments: arguments), "Series")
        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.moveSeriesFromOccurrence(arguments: arguments), 0)
        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.deleteSeriesTitle(arguments: arguments), "Old Series")
        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.eventCommentOccurrence(arguments: arguments), 3)
        // "All future events" from the third occurrence unless told otherwise; no occurrence
        // named means the first event found, as before.
        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.moveSeriesFromOccurrence(arguments: ["ShareCal"]), 2)
        XCTAssertNil(ShareCalLaunchDiagnosticPolicy.eventCommentOccurrence(arguments: ["ShareCal"]))
        XCTAssertNil(ShareCalLaunchDiagnosticPolicy.moveSeriesTitle(arguments: ["ShareCal"]))
    }

    func testPreparesPairingShareOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPolicy.shouldPreparePairingShare(
                arguments: ["ShareCal", "-ShareCalPreparePairingShare"]
            )
        )
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.shouldPreparePairingShare(arguments: ["ShareCal"]))
    }

    func testParsesAcceptShareURLArgumentValue() {
        XCTAssertEqual(
            ShareCalLaunchDiagnosticPolicy.acceptShareURL(
                arguments: ["ShareCal", "-ShareCalAcceptShareURL", "https://www.icloud.com/share/abc#Name"]
            ),
            URL(string: "https://www.icloud.com/share/abc#Name")
        )
        XCTAssertNil(
            ShareCalLaunchDiagnosticPolicy.acceptShareURL(arguments: ["ShareCal", "-ShareCalAcceptShareURL"])
        )
        XCTAssertNil(ShareCalLaunchDiagnosticPolicy.acceptShareURL(arguments: ["ShareCal"]))
    }

    func testForcesSyncOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPolicy.shouldForceSync(arguments: ["ShareCal", "-ShareCalForceSync"])
        )
        XCTAssertFalse(ShareCalLaunchDiagnosticPolicy.shouldForceSync(arguments: ["ShareCal"]))
    }

    func testRunsCloudKitWriteProbeOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPolicy.shouldRunCloudKitWriteProbe(
                arguments: ["ShareCal", "-ShareCalCloudKitWriteProbe"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPolicy.shouldRunCloudKitWriteProbe(
                arguments: ["ShareCal"]
            )
        )
    }

    func testSeedsCalendarEventOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPolicy.shouldSeedCalendarEvent(
                arguments: ["ShareCal", "-ShareCalSeedCalendarEvent"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPolicy.shouldSeedCalendarEvent(
                arguments: ["ShareCal"]
            )
        )
    }

    func testBuildsSeedCalendarDraftFromISODateArguments() throws {
        let draft = ShareCalLaunchDiagnosticPolicy.seedCalendarEventDraft(
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
        XCTAssertEqual(draft.notes, ShareCalSmokeTestEventPolicy.notes)
    }

    func testFallsBackToDefaultSeedDraftWhenISODateRangeIsInvalid() {
        let now = Date(timeIntervalSince1970: 1_000)
        let draft = ShareCalLaunchDiagnosticPolicy.seedCalendarEventDraft(
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

        XCTAssertEqual(draft, ShareCalSmokeTestEventPolicy.draft(now: now, title: "Fallback"))
    }

    func testCloudKitWriteProbeUsesRealShareRootRecordType() {
        XCTAssertEqual(ShareCalLaunchDiagnosticPolicy.cloudKitWriteProbeRecordType, "CoupleSpace")
    }

    func testRunsStopSharingProbeOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPolicy.shouldRunStopSharingProbe(
                arguments: ["ShareCal", "-ShareCalStopICloudSharing"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPolicy.shouldRunStopSharingProbe(
                arguments: ["ShareCal"]
            )
        )
    }

    func testRunsSharedReadProbeOnlyWhenLaunchArgumentIsPresent() {
        XCTAssertTrue(
            ShareCalLaunchDiagnosticPolicy.shouldRunSharedReadProbe(
                arguments: ["ShareCal", "-ShareCalSharedReadProbe"]
            )
        )
        XCTAssertFalse(
            ShareCalLaunchDiagnosticPolicy.shouldRunSharedReadProbe(
                arguments: ["ShareCal"]
            )
        )
    }
}

final class CloudKitBatchUpsertPolicyTests: XCTestCase {
    func testBuildsMirrorRecordIDsWithServerRecordNameFallback() {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpaceZone", ownerName: CKCurrentUserDefaultName)
        let existing = eventMirror(id: "event-1", cloudKitRecordName: "server-record")
        let new = eventMirror(id: "event-2", cloudKitRecordName: nil)

        let recordIDs = CloudKitBatchUpsertPolicy.recordIDs(forMirrors: [existing, new], zoneID: zoneID)

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

        let recordIDs = CloudKitBatchUpsertPolicy.recordIDs(forAccessRequests: [request], zoneID: zoneID)
        let record = CalendarAccessRequestRecordMapper.record(from: request, zoneID: zoneID)

        XCTAssertEqual(recordIDs.map(\.recordName), ["history-access-request:request-1"])
        XCTAssertEqual(record.recordID.recordName, "history-access-request:request-1")
    }

    func testDefinesMinimalDesiredKeysForEachForegroundQueryType() {
        XCTAssertEqual(
            CloudKitForegroundQueryPolicy.desiredKeys(forRecordType: EventMirrorRecordMapper.recordType),
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
                EventMirrorRecordMapper.Key.deletedAt,
                EventMirrorRecordMapper.Key.stableKey
            ]
        )
        XCTAssertEqual(
            CloudKitForegroundQueryPolicy.desiredKeys(forRecordType: CommentRecordMapper.recordType),
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
            CloudKitForegroundQueryPolicy.desiredKeys(forRecordType: MemberProfileRecordMapper.recordType),
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

final class CloudKitRecordQueryFailurePolicyTests: XCTestCase {
    func testTreatsMissingMemberProfileRecordTypeAsEmpty() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: MemberProfile"]
        )

        XCTAssertTrue(
            CloudKitRecordQueryFailurePolicy.canTreatMissingRecordTypeAsEmpty(
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
            CloudKitRecordQueryFailurePolicy.canTreatMissingRecordTypeAsEmpty(
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
            MemberProfileDisplayPolicy.partnerSyncedAvatar(from: [older, mine, newer], partnerID: " _partner "),
            MemberAvatar(text: "雨", background: .coral)
        )
        XCTAssertNil(MemberProfileDisplayPolicy.partnerSyncedAvatar(from: [older, mine, newer], partnerID: nil))
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

        XCTAssertTrue(MemberProfileAvatarSchemaFallbackPolicy.shouldRetryWithoutAvatar(error: invalid, profile: withAvatar))
        XCTAssertTrue(MemberProfileAvatarSchemaFallbackPolicy.shouldRetryWithoutAvatar(error: partial, profile: withAvatar))
        XCTAssertFalse(MemberProfileAvatarSchemaFallbackPolicy.shouldRetryWithoutAvatar(error: invalid, profile: withoutAvatar))
        XCTAssertFalse(MemberProfileAvatarSchemaFallbackPolicy.shouldRetryWithoutAvatar(error: CKError(.networkUnavailable), profile: withAvatar))
    }
}

final class ICloudAvailabilityPolicyTests: XCTestCase {
    func testMapsAccountStatusToActionableProblem() {
        XCTAssertNil(ICloudAvailabilityPolicy.problem(for: .available))
        XCTAssertNil(ICloudAvailabilityPolicy.problem(for: .couldNotDetermine))
        XCTAssertEqual(ICloudAvailabilityPolicy.problem(for: .noAccount), .unavailableForApp)
        XCTAssertEqual(ICloudAvailabilityPolicy.problem(for: .restricted), .restricted)
        XCTAssertEqual(ICloudAvailabilityPolicy.problem(for: .temporarilyUnavailable), .needsReauthentication)
    }
}

final class ShareInvitationLinkPolicyTests: XCTestCase {
    func testFindsShareURLInsideChatText() {
        let text = "我在 OurDays 邀请你配对：https://www.icloud.com/share/0aBcD_efGh#OurDays 点开就好"

        XCTAssertEqual(
            ShareInvitationLinkPolicy.shareURL(from: text)?.absoluteString,
            "https://www.icloud.com/share/0aBcD_efGh#OurDays"
        )
    }

    func testAcceptsChinaMainlandShareLinks() {
        let text = "我想和你一起用 OurDays 共享日程。② 复制这个链接：https://www.icloud.com.cn/share/0aBcD_efGh#OurDays"

        XCTAssertEqual(
            ShareInvitationLinkPolicy.shareURL(from: text)?.absoluteString,
            "https://www.icloud.com.cn/share/0aBcD_efGh#OurDays"
        )
        XCTAssertNil(ShareInvitationLinkPolicy.shareURL(from: "https://www.icloud.com.cn/notes/0aBcD"))
        XCTAssertNil(ShareInvitationLinkPolicy.shareURL(from: "https://icloud.com.cn.example.com/share/0aBcD"))
    }

    func testIgnoresNonShareLinks() {
        XCTAssertNil(ShareInvitationLinkPolicy.shareURL(from: "https://www.icloud.com/notes/0aBcD#Note"))
        XCTAssertNil(ShareInvitationLinkPolicy.shareURL(from: "https://example.com/share/0aBcD"))
        XCTAssertNil(ShareInvitationLinkPolicy.shareURL(from: "http://www.icloud.com/share/0aBcD"))
        XCTAssertNil(ShareInvitationLinkPolicy.shareURL(from: "no link here"))
    }

    func testInputStateTellsWhetherTheBoxHoldsALink() {
        XCTAssertEqual(ShareInvitationLinkPolicy.inputState(for: ""), .empty)
        XCTAssertEqual(ShareInvitationLinkPolicy.inputState(for: "  \n "), .empty)
        XCTAssertEqual(ShareInvitationLinkPolicy.inputState(for: "在吗？发我一下链接"), .noLink)
        XCTAssertEqual(
            ShareInvitationLinkPolicy.inputState(for: "② 复制这个链接：https://www.icloud.com.cn/share/0aBcD#OurDays"),
            .found(URL(string: "https://www.icloud.com.cn/share/0aBcD#OurDays")!)
        )
    }

    func testMapsCloudKitErrorsToFailures() {
        XCTAssertEqual(ShareInvitationLinkPolicy.failure(for: CKError(.notAuthenticated)), .iCloudUnavailable)
        XCTAssertEqual(ShareInvitationLinkPolicy.failure(for: CKError(.unknownItem)), .linkNoLongerValid)
        XCTAssertEqual(ShareInvitationLinkPolicy.failure(for: CKError(.participantMayNeedVerification)), .inviteOnly)
    }
}

final class OwnSettingsRecordMapperTests: XCTestCase {
    func testRoundTripComparesEqualSoAnUnchangedCopyIsNeverRewritten() throws {
        var settings = OwnRelayedSettings()
        settings.partnerNote = .init(
            partnerID: "_partner",
            noteName: "宝",
            avatarOverride: MemberAvatar(text: "宝", background: nil),
            updatedAt: OwnSettingsRelayClock.stamp(Date(timeIntervalSince1970: 1_700_000_000.75))
        )
        settings.calendars = .init(
            references: [CalendarReference(sourceTitle: "iCloud", title: "Work")],
            updatedAt: .distantPast
        )
        settings.lastSeenActivityAt = Date(timeIntervalSince1970: 1_700_000_123.456)
        let record = CKRecord(
            recordType: OwnSettingsRecordMapper.recordType,
            recordID: CKRecord.ID(recordName: OwnSettingsRecordMapper.recordName)
        )

        try OwnSettingsRecordMapper.apply(settings, to: record)
        let decoded = try OwnSettingsRecordMapper.settings(from: record)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(try OwnSettingsRecordMapper.encode(decoded), try OwnSettingsRecordMapper.encode(settings))
    }
}

final class ZoneChangeCachePolicyTests: XCTestCase {
    private let signature = "sig"
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(
        records: [String: Data] = ["a": Data([1]), "b": Data([2])],
        tokenData: Data? = Data([9]),
        signature: String = "sig",
        lastFullFetchAt: Date? = nil
    ) -> ZoneChangeSnapshot {
        ZoneChangeSnapshot(
            signature: signature,
            tokenData: tokenData,
            lastFullFetchAt: lastFullFetchAt ?? now,
            recordDataByName: records
        )
    }

    func testWholeDownloadBecomesTheSnapshot() {
        let merged = ZoneChangeCachePolicy.merged(
            base: nil,
            events: [.saved(recordName: "a", data: Data([1])), .saved(recordName: "b", data: Data([2]))],
            tokenData: Data([7]),
            signature: signature,
            now: now
        )

        XCTAssertEqual(merged.recordDataByName, ["a": Data([1]), "b": Data([2])])
        XCTAssertEqual(merged.tokenData, Data([7]))
        XCTAssertEqual(merged.lastFullFetchAt, now)
        XCTAssertEqual(merged.signature, signature)
    }

    /// The rule the calendar depends on: a fetch that reports nothing must leave every
    /// record in place, or the partner's events would be purged as "no longer there".
    func testRecordsTheFetchDidNotMentionStay() {
        let base = snapshot()

        let merged = ZoneChangeCachePolicy.merged(
            base: base,
            events: [],
            tokenData: Data([10]),
            signature: signature,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(merged.recordDataByName, base.recordDataByName)
        XCTAssertEqual(merged.tokenData, Data([10]))
        XCTAssertEqual(merged.lastFullFetchAt, base.lastFullFetchAt)
    }

    func testOnlyRecordsTheServerReportsDeletedLeave() {
        let merged = ZoneChangeCachePolicy.merged(
            base: snapshot(),
            events: [.deleted(recordName: "a"), .saved(recordName: "c", data: Data([3]))],
            tokenData: Data([10]),
            signature: signature,
            now: now
        )

        XCTAssertEqual(merged.recordDataByName, ["b": Data([2]), "c": Data([3])])
    }

    func testEventsApplyInTheOrderReported() {
        let merged = ZoneChangeCachePolicy.merged(
            base: snapshot(),
            events: [
                .saved(recordName: "a", data: Data([5])),
                .deleted(recordName: "b"),
                .saved(recordName: "b", data: Data([6])),
                .saved(recordName: "c", data: Data([3])),
                .deleted(recordName: "c")
            ],
            tokenData: Data([10]),
            signature: signature,
            now: now
        )

        XCTAssertEqual(merged.recordDataByName, ["a": Data([5]), "b": Data([6])])
    }

    func testContinuesFromAFreshMatchingSnapshot() {
        let base = snapshot()
        XCTAssertEqual(ZoneChangeCachePolicy.resumable(base, signature: signature, now: now.addingTimeInterval(3_600)), base)
    }

    func testDownloadsWholeZoneWhenSnapshotCannotBeContinued() {
        XCTAssertNil(ZoneChangeCachePolicy.resumable(nil, signature: signature, now: now))
        XCTAssertNil(ZoneChangeCachePolicy.resumable(snapshot(tokenData: nil), signature: signature, now: now))
        XCTAssertNil(ZoneChangeCachePolicy.resumable(snapshot(signature: "other keys"), signature: signature, now: now))

        var olderFormat = snapshot()
        olderFormat.format = ZoneChangeSnapshot.currentFormat - 1
        XCTAssertNil(ZoneChangeCachePolicy.resumable(olderFormat, signature: signature, now: now))
    }

    func testDownloadsWholeZoneAgainAfterTheRefetchInterval() {
        let base = snapshot()
        let justInside = now.addingTimeInterval(ZoneChangeCachePolicy.fullRefetchInterval - 1)
        let atLimit = now.addingTimeInterval(ZoneChangeCachePolicy.fullRefetchInterval)

        XCTAssertNotNil(ZoneChangeCachePolicy.resumable(base, signature: signature, now: justInside))
        XCTAssertNil(ZoneChangeCachePolicy.resumable(base, signature: signature, now: atLimit))
        // A clock set back must not keep a snapshot alive forever.
        XCTAssertNil(ZoneChangeCachePolicy.resumable(base, signature: signature, now: now.addingTimeInterval(-60)))
    }

    func testExpiredTokenMeansStartOver() {
        let expired = NSError(domain: CKError.errorDomain, code: CKError.Code.changeTokenExpired.rawValue)
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace")
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: [zoneID: expired]]
        )
        let network = NSError(domain: CKError.errorDomain, code: CKError.Code.networkUnavailable.rawValue)

        XCTAssertTrue(ZoneChangeCachePolicy.tokenIsUnusable(expired))
        XCTAssertTrue(ZoneChangeCachePolicy.tokenIsUnusable(partial))
        XCTAssertFalse(ZoneChangeCachePolicy.tokenIsUnusable(network))
        XCTAssertFalse(ZoneChangeCachePolicy.tokenIsUnusable(NSError(domain: NSURLErrorDomain, code: CKError.Code.changeTokenExpired.rawValue)))
    }

    func testEachAccountDatabaseAndZoneHasItsOwnFile() {
        func name(
            account: String = "_me",
            environment: String = "Production",
            scope: String = "shared",
            owner: String = "_partner"
        ) -> String {
            ZoneChangeCachePolicy.fileName(
                accountID: account,
                environment: environment,
                databaseScope: scope,
                zoneOwnerName: owner,
                zoneName: "CoupleSpace"
            )
        }

        XCTAssertEqual(name(), "_me.Production.shared._partner.CoupleSpace.plist")
        XCTAssertEqual(
            Set([name(), name(account: "_other"), name(environment: "Development"), name(scope: "private"), name(owner: "_ex")]).count,
            5
        )
        XCTAssertEqual(name(owner: "../__defaultOwner__"), "_me.Production.shared.---__defaultOwner__.CoupleSpace.plist")
    }

    func testOneZoneFetchAsksForTheKeysOfEveryTypeASyncReads() {
        let keys = Set(CloudKitForegroundQueryPolicy.zoneFetchDesiredKeys)
        for recordType in [
            EventMirrorRecordMapper.recordType,
            InvitationRecordMapper.recordType,
            CommentRecordMapper.recordType,
            MemberProfileRecordMapper.recordType,
            CalendarAccessRequestRecordMapper.transportRecordType
        ] {
            XCTAssertTrue(CloudKitForegroundQueryPolicy.zoneFetchRecordTypes.contains(recordType))
            let typeKeys = CloudKitForegroundQueryPolicy.desiredKeys(forRecordType: recordType) ?? []
            XCTAssertFalse(typeKeys.isEmpty)
            XCTAssertTrue(keys.isSuperset(of: typeKeys))
        }
    }

    func testSignatureChangesWithWhatIsAskedOfTheServer() {
        let base = ZoneChangeCachePolicy.signature(recordTypes: ["B", "A"], desiredKeys: ["y", "x"])
        XCTAssertEqual(base, ZoneChangeCachePolicy.signature(recordTypes: ["A", "B"], desiredKeys: ["x", "y"]))
        XCTAssertNotEqual(base, ZoneChangeCachePolicy.signature(recordTypes: ["A", "B"], desiredKeys: ["x", "y", "z"]))
        XCTAssertNotEqual(base, ZoneChangeCachePolicy.signature(recordTypes: ["A"], desiredKeys: ["x", "y"]))
    }
}

final class ZoneChangeSnapshotStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZoneChangeSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// A record read back from the snapshot must map exactly like the one the server sent.
    func testSnapshotKeepsRecordsReadableAcrossLaunches() throws {
        let zoneID = CKRecordZone.ID(zoneName: "CoupleSpace", ownerName: "_partner")
        let mirror = EventMirror(
            ownerMemberID: "_partner",
            mirrorKey: "work:event-1:1800",
            sourceCalendarID: "work",
            sourceCalendarTitle: "Work",
            occurrenceStartDate: Date(timeIntervalSince1970: 1_800),
            startDate: Date(timeIntervalSince1970: 1_800),
            endDate: Date(timeIntervalSince1970: 3_600),
            isAllDay: false,
            timeZoneIdentifier: "Asia/Shanghai",
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
        let data = try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
        let snapshot = ZoneChangeSnapshot(
            signature: "sig",
            tokenData: Data([1, 2, 3]),
            lastFullFetchAt: Date(timeIntervalSince1970: 1_000),
            recordDataByName: [record.recordID.recordName: data]
        )
        let store = ZoneChangeSnapshotStore(directory: directory)

        try store.save(snapshot, fileName: "zone.plist")
        let loaded = try XCTUnwrap(ZoneChangeSnapshotStore(directory: directory).load(fileName: "zone.plist"))

        XCTAssertEqual(loaded, snapshot)
        let loadedData = try XCTUnwrap(loaded.recordDataByName["mirror-record"])
        let loadedRecord = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: loadedData))
        XCTAssertEqual(loadedRecord.recordID, record.recordID)
        XCTAssertEqual(loadedRecord.recordType, EventMirrorRecordMapper.recordType)
        let decoded = try EventMirrorRecordMapper.eventMirror(from: loadedRecord)
        XCTAssertEqual(decoded.mirrorKey, mirror.mirrorKey)
        XCTAssertEqual(decoded.title, mirror.title)
        XCTAssertEqual(decoded.startDate, mirror.startDate)
        XCTAssertEqual(decoded.notes, mirror.notes)
    }

    func testMissingOrUnreadableFileReadsAsNoSnapshot() throws {
        let store = ZoneChangeSnapshotStore(directory: directory)
        XCTAssertNil(store.load(fileName: "zone.plist"))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: directory.appendingPathComponent("zone.plist"))
        XCTAssertNil(store.load(fileName: "zone.plist"))
    }

    func testRemoveForgetsTheZone() throws {
        let store = ZoneChangeSnapshotStore(directory: directory)
        let snapshot = ZoneChangeSnapshot(
            signature: "sig",
            tokenData: Data([1]),
            lastFullFetchAt: Date(timeIntervalSince1970: 1_000),
            recordDataByName: [:]
        )
        try store.save(snapshot, fileName: "zone.plist")

        store.remove(fileName: "zone.plist")

        XCTAssertNil(store.load(fileName: "zone.plist"))
        store.remove(fileName: "zone.plist")
    }
}
