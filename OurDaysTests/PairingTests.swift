import XCTest

final class ICloudSharingTeardownPolicyTests: XCTestCase {
    func testPurgesPartnerOwnerAndPlaceholderIDs() {
        let ownerIDs = ICloudSharingTeardownPolicy.localOwnerIDsToPurge(
            partnerShareOwnerID: "_partnerOwner"
        )

        XCTAssertEqual(ownerIDs, ["_partnerOwner", "partner"])
    }

    func testIgnoresMissingPartnerOwnerID() {
        let ownerIDs = ICloudSharingTeardownPolicy.localOwnerIDsToPurge(partnerShareOwnerID: " ")

        XCTAssertEqual(ownerIDs, ["partner"])
    }
}

final class PairingSettingsPolicyTests: XCTestCase {
    func testReportsNotPairedWhenNoPairingSignalsExist() {
        XCTAssertEqual(
            PairingSettingsPolicy.status(
                hasStartedPairing: false,
                outgoingParticipantIDs: [],
                incomingOwnerID: nil
            ),
            .notPaired
        )
    }

    func testReportsWaitingForPartnerAfterStartingOutgoingShare() {
        XCTAssertEqual(
            PairingSettingsPolicy.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: [],
                incomingOwnerID: nil
            ),
            .waitingForPartner
        )
    }

    func testReportsWaitingForPartnerToShareAfterOutgoingShareIsAccepted() {
        XCTAssertEqual(
            PairingSettingsPolicy.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: ["partner@example.com"],
                incomingOwnerID: nil
            ),
            .waitingForPartnerToShare
        )
    }

    func testReportsWaitingForYouToShareWhenOnlyIncomingShareIsAvailable() {
        XCTAssertEqual(
            PairingSettingsPolicy.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: [],
                incomingOwnerID: "icloud-owner"
            ),
            .waitingForYouToShare
        )
    }

    func testReportsPairedOnlyWhenIncomingAndOutgoingSharesAreAvailable() {
        XCTAssertEqual(
            PairingSettingsPolicy.status(
                hasStartedPairing: true,
                outgoingParticipantIDs: ["partner@example.com"],
                incomingOwnerID: "icloud-owner"
            ),
            .paired
        )
    }

    func testPartnerDisplayNamePrefersLocalNoteThenSyncedProfile() {
        XCTAssertEqual(
            PairingSettingsPolicy.partnerDisplayName(
                partnerNoteName: " Local note ",
                partnerSyncedDisplayName: "Remote name",
                fallback: "Partner"
            ),
            "Local note"
        )
        XCTAssertEqual(
            PairingSettingsPolicy.partnerDisplayName(
                partnerNoteName: " ",
                partnerSyncedDisplayName: " Remote name ",
                fallback: "Partner"
            ),
            "Remote name"
        )
        XCTAssertEqual(
            PairingSettingsPolicy.partnerDisplayName(
                partnerNoteName: "",
                partnerSyncedDisplayName: nil,
                fallback: "Partner"
            ),
            "Partner"
        )
    }

    func testPartnerStatusDisplayNameShowsNicknameWithOptionalNote() {
        XCTAssertEqual(
            PairingSettingsPolicy.partnerStatusDisplayName(
                partnerNoteName: " Home ",
                partnerSyncedDisplayName: " Yoki ",
                fallback: "Partner",
                language: .english
            ),
            "Yoki (Home)"
        )
        XCTAssertEqual(
            PairingSettingsPolicy.partnerStatusDisplayName(
                partnerNoteName: " ",
                partnerSyncedDisplayName: " Yoki ",
                fallback: "Partner",
                language: .chinese
            ),
            "Yoki"
        )
        XCTAssertEqual(
            PairingSettingsPolicy.partnerStatusDisplayName(
                partnerNoteName: " Yoki ",
                partnerSyncedDisplayName: "Yoki",
                fallback: "Partner",
                language: .chinese
            ),
            "Yoki"
        )
        XCTAssertEqual(
            PairingSettingsPolicy.partnerStatusDisplayName(
                partnerNoteName: " 宝宝 ",
                partnerSyncedDisplayName: nil,
                fallback: "对方",
                language: .chinese
            ),
            "对方（宝宝）"
        )
    }

    func testNormalizesCurrentDisplayNameForProfileSync() {
        XCTAssertEqual(PairingSettingsPolicy.normalizedDisplayName(" Manu "), "Manu")
        XCTAssertNil(PairingSettingsPolicy.normalizedDisplayName(" "))
        XCTAssertNil(PairingSettingsPolicy.normalizedDisplayName(nil))
    }

    func testRandomNicknameIsReadableAndStableLength() {
        let nickname = PairingSettingsPolicy.randomDisplayName(randomNumber: { 42 })

        XCTAssertEqual(nickname, "OurDays 0042")
    }
}

final class TwoPersonPairingPolicyTests: XCTestCase {
    func testMutualShareEstablishesPartnerAndLeavesStaleZones() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_partner"],
            sharedZoneOwnerIDs: ["_partner", "_oldFriend"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertEqual(resolution.sharedZoneOwnerIDsToLeave, ["_oldFriend"])
        XCTAssertNil(resolution.conflict)
    }

    func testSingleIncomingShareBecomesPartnerWithoutOutgoingShare() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: [],
            sharedZoneOwnerIDs: ["_partner"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertTrue(resolution.sharedZoneOwnerIDsToLeave.isEmpty)
        XCTAssertNil(resolution.conflict)
    }

    func testStoredPartnerSelectsAmongMultipleIncomingShares() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: "_partner",
            outgoingAcceptedParticipantIDs: [],
            sharedZoneOwnerIDs: ["_oldFriend", "_partner"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertEqual(resolution.sharedZoneOwnerIDsToLeave, ["_oldFriend"])
        XCTAssertNil(resolution.conflict)
    }

    func testMultipleIncomingSharesWithoutBindingIsAConflict() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: [],
            sharedZoneOwnerIDs: ["_personB", "_personA"]
        )

        XCTAssertNil(resolution.partnerID)
        XCTAssertTrue(resolution.sharedZoneOwnerIDsToLeave.isEmpty)
        XCTAssertEqual(
            resolution.conflict,
            .multipleIncomingShares(ownerIDs: ["_personA", "_personB"])
        )
    }

    func testOutgoingIncomingMismatchIsAConflictAndBlocksCleanup() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_personA"],
            sharedZoneOwnerIDs: ["_personB"]
        )

        XCTAssertNil(resolution.partnerID)
        XCTAssertTrue(resolution.sharedZoneOwnerIDsToLeave.isEmpty)
        XCTAssertEqual(
            resolution.conflict,
            .outgoingIncomingMismatch(outgoingIDs: ["_personA"], incomingOwnerIDs: ["_personB"])
        )
    }

    func testMismatchConflictCarriesAllOutgoingParticipantsAsCandidates() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_personB", "_personA"],
            sharedZoneOwnerIDs: ["_personC"]
        )

        XCTAssertEqual(
            resolution.conflict,
            .outgoingIncomingMismatch(outgoingIDs: ["_personA", "_personB"], incomingOwnerIDs: ["_personC"])
        )
        XCTAssertEqual(
            TwoPersonPairingConflictPresentationPolicy.candidateIDs(
                .outgoingIncomingMismatch(outgoingIDs: ["_personA", "_personB"], incomingOwnerIDs: ["_personC"])
            ),
            ["_personA", "_personB", "_personC"]
        )
    }

    func testOutgoingOnlyShareWaitsForPartnerWithoutConflict() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_partner"],
            sharedZoneOwnerIDs: []
        )

        XCTAssertNil(resolution.partnerID)
        XCTAssertTrue(resolution.sharedZoneOwnerIDsToLeave.isEmpty)
        XCTAssertNil(resolution.conflict)
    }

    func testMultipleOutgoingParticipantsWithoutBindingIsAConflict() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_personB", "_personA"],
            sharedZoneOwnerIDs: []
        )

        XCTAssertEqual(
            resolution.conflict,
            .multipleOutgoingParticipants(participantIDs: ["_personA", "_personB"])
        )
    }

    func testMultipleOutgoingParticipantsWithStoredPartnerIsStillAConflict() {
        // A newcomer on the outgoing share is never removed silently, even when
        // the stored partner is among the participants: the user decides.
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: "_partner",
            outgoingAcceptedParticipantIDs: ["_partner", "_newcomer"],
            sharedZoneOwnerIDs: []
        )

        XCTAssertNil(resolution.partnerID)
        XCTAssertEqual(
            resolution.conflict,
            .multipleOutgoingParticipants(participantIDs: ["_newcomer", "_partner"])
        )
    }

    func testNewcomerJoiningEstablishedMutualShareIsAConflictWithBothAsCandidates() {
        // A paired with B; C accepted A's link. Previously C was auto-removed
        // before A could confirm a replacement, so the replacement ended with
        // no participant at all. Now it is a conflict A resolves by choosing.
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: "_partner",
            outgoingAcceptedParticipantIDs: ["_newcomer", "_partner"],
            sharedZoneOwnerIDs: ["_partner"]
        )

        XCTAssertNil(resolution.partnerID)
        XCTAssertTrue(resolution.sharedZoneOwnerIDsToLeave.isEmpty)
        XCTAssertEqual(
            resolution.conflict,
            .outgoingIncomingMismatch(outgoingIDs: ["_newcomer", "_partner"], incomingOwnerIDs: ["_partner"])
        )
        XCTAssertEqual(
            TwoPersonPairingConflictPresentationPolicy.candidateIDs(
                .outgoingIncomingMismatch(outgoingIDs: ["_newcomer", "_partner"], incomingOwnerIDs: ["_partner"])
            ),
            ["_newcomer", "_partner"]
        )
    }

    func testStaleIncomingZonesStillLeaveWhenOutgoingHasOnlyThePartner() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: "_partner",
            outgoingAcceptedParticipantIDs: ["_partner"],
            sharedZoneOwnerIDs: ["_partner", "_oldFriend"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertEqual(resolution.sharedZoneOwnerIDsToLeave, ["_oldFriend"])
        XCTAssertNil(resolution.conflict)
    }

    func testNonCloudKitParticipantIdentifiersAreIgnoredForMatching() {
        let resolution = TwoPersonPairingPolicy.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["partner@example.com"],
            sharedZoneOwnerIDs: ["_partner"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertNil(resolution.conflict)
    }
}

final class ShareAcceptanceGuardPolicyTests: XCTestCase {
    func testFirstAcceptanceNeedsNoConfirmation() {
        XCTAssertFalse(
            ShareAcceptanceGuardPolicy.requiresReplacementConfirmation(
                incomingOwnerID: "_partner",
                storedPartnerID: nil,
                outgoingParticipantIDs: []
            )
        )
    }

    func testReacceptingCurrentPartnerNeedsNoConfirmation() {
        XCTAssertFalse(
            ShareAcceptanceGuardPolicy.requiresReplacementConfirmation(
                incomingOwnerID: "_partner",
                storedPartnerID: "_partner",
                outgoingParticipantIDs: []
            )
        )
    }

    func testAcceptingDifferentPersonThanStoredPartnerNeedsConfirmation() {
        XCTAssertTrue(
            ShareAcceptanceGuardPolicy.requiresReplacementConfirmation(
                incomingOwnerID: "_intruder",
                storedPartnerID: "_partner",
                outgoingParticipantIDs: []
            )
        )
    }

    func testAcceptingDifferentPersonThanOutgoingParticipantNeedsConfirmation() {
        XCTAssertTrue(
            ShareAcceptanceGuardPolicy.requiresReplacementConfirmation(
                incomingOwnerID: "_intruder",
                storedPartnerID: nil,
                outgoingParticipantIDs: ["_partner"]
            )
        )
    }

    func testNonCloudKitOutgoingIdentifiersDoNotBlockAcceptance() {
        XCTAssertFalse(
            ShareAcceptanceGuardPolicy.requiresReplacementConfirmation(
                incomingOwnerID: "_partner",
                storedPartnerID: nil,
                outgoingParticipantIDs: ["partner@example.com"]
            )
        )
    }
}

final class ExistingICloudDataRecoveryPolicyTests: XCTestCase {
    func testPromptsWhenFreshLocalStateFindsExistingCloudDataAfterProfileSetup() {
        XCTAssertTrue(
            ExistingICloudDataRecoveryPolicy.shouldPresent(
                snapshot: ExistingICloudDataSnapshot(
                    hasPrivateZoneData: true,
                    hasOutgoingShare: true,
                    acceptedSharedZoneCount: 1
                ),
                hasCompletedInitialProfilePrompt: true,
                hasResolvedPrompt: false,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                lastSyncAt: nil
            )
        )
    }

    func testDoesNotPromptWhenNoExistingCloudDataIsFound() {
        XCTAssertFalse(
            ExistingICloudDataRecoveryPolicy.shouldPresent(
                snapshot: ExistingICloudDataSnapshot(
                    hasPrivateZoneData: false,
                    hasOutgoingShare: false,
                    acceptedSharedZoneCount: 0
                ),
                hasCompletedInitialProfilePrompt: true,
                hasResolvedPrompt: false,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                lastSyncAt: nil
            )
        )
    }

    func testDoesNotPromptWhenLocalPairingStateAlreadyExists() {
        XCTAssertFalse(
            ExistingICloudDataRecoveryPolicy.shouldPresent(
                snapshot: ExistingICloudDataSnapshot(
                    hasPrivateZoneData: true,
                    hasOutgoingShare: true,
                    acceptedSharedZoneCount: 1
                ),
                hasCompletedInitialProfilePrompt: true,
                hasResolvedPrompt: false,
                hasStartedPairing: true,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                lastSyncAt: nil
            )
        )
    }

    func testDefersAutomaticSyncWhileFreshInstallCloudDecisionIsUnresolved() {
        XCTAssertTrue(
            ExistingICloudDataRecoveryPolicy.shouldDeferAutomaticSync(
                hasResolvedPrompt: false,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                lastSyncAt: nil
            )
        )
        XCTAssertFalse(
            ExistingICloudDataRecoveryPolicy.shouldDeferAutomaticSync(
                hasResolvedPrompt: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                lastSyncAt: nil
            )
        )
    }
}

final class ExistingICloudDataRecoveredStateTests: XCTestCase {
    func testRestoresPairingDateFromShareRootCreationAndProfileFromOwnZone() throws {
        let calendar = Calendar(identifier: .gregorian)
        let rootCreatedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 19)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9)))
        let avatar = MemberAvatar(text: "小鱼", background: nil, imageData: nil)

        let state = ExistingICloudDataRecoveryPolicy.recoveredState(
            shareRootCreatedAt: rootCreatedAt,
            ownProfile: CloudKitMemberProfile(ownerMemberID: "_me", displayName: "  阿狸 ", updatedAt: now, avatar: avatar),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(state.pairingDate, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8))))
        XCTAssertEqual(state.displayName, "阿狸")
        XCTAssertEqual(state.avatar?.text, "小鱼")
    }

    func testLeavesEverythingUnsetWhenNothingUsableIsInTheCloud() {
        let now = Date(timeIntervalSince1970: 1_000)

        let state = ExistingICloudDataRecoveryPolicy.recoveredState(
            shareRootCreatedAt: nil,
            ownProfile: CloudKitMemberProfile(ownerMemberID: "_me", displayName: "   ", updatedAt: now),
            now: now
        )

        XCTAssertEqual(state, ExistingICloudDataRecoveredState())
    }

    func testIgnoresAFutureRootCreationDate() {
        let now = Date(timeIntervalSince1970: 1_000)

        let state = ExistingICloudDataRecoveryPolicy.recoveredState(
            shareRootCreatedAt: now.addingTimeInterval(86_400),
            ownProfile: nil,
            now: now
        )

        XCTAssertNil(state.pairingDate)
    }
}

final class PartnerScopedDataPolicyTests: XCTestCase {
    func testOnlyARealUserRecordIDOutsideThePairIsForeign() {
        XCTAssertTrue(PartnerScopedDataPolicy.isForeign("_ex", currentMemberID: "_me", partnerID: "_partner"))
        XCTAssertFalse(PartnerScopedDataPolicy.isForeign("_me", currentMemberID: "_me", partnerID: "_partner"))
        XCTAssertFalse(PartnerScopedDataPolicy.isForeign(" _partner ", currentMemberID: "_me", partnerID: "_partner"))
        XCTAssertFalse(PartnerScopedDataPolicy.isForeign(MemberIDPolicy.unknownPartnerID, currentMemberID: "_me", partnerID: nil))
        XCTAssertFalse(PartnerScopedDataPolicy.isForeign(MemberIDPolicy.unsyncedMemberID, currentMemberID: "_me", partnerID: nil))
        XCTAssertFalse(PartnerScopedDataPolicy.isForeign("", currentMemberID: "_me", partnerID: nil))
    }

    func testWithoutAPartnerOnlyMyOwnRecordsPass() {
        XCTAssertTrue(PartnerScopedDataPolicy.isForeign("_old", currentMemberID: "_me", partnerID: nil))
        XCTAssertFalse(PartnerScopedDataPolicy.isForeign("_me", currentMemberID: "_me", partnerID: nil))
    }

    func testScopesCommentsInvitationsAndRequestsByEitherParty() {
        let comments = [
            EventComment(eventMirrorID: "e", authorMemberID: "_partner", body: "partner"),
            EventComment(eventMirrorID: "e", authorMemberID: "_ex", body: "ex")
        ]
        let invitations = [
            EventInvitation(creatorMemberID: "_me", inviteeMemberID: "_ex", title: "to ex", startDate: .distantPast, endDate: .distantFuture, location: nil, notes: nil),
            EventInvitation(creatorMemberID: "_partner", inviteeMemberID: "_me", title: "from partner", startDate: .distantPast, endDate: .distantFuture, location: nil, notes: nil)
        ]
        let requests = [
            CalendarAccessRequest(requesterMemberID: "_me", ownerMemberID: "_ex", requestedStartDate: .distantPast, requestedEndDate: .distantFuture),
            CalendarAccessRequest(requesterMemberID: "_me", ownerMemberID: "_partner", requestedStartDate: .distantPast, requestedEndDate: .distantFuture)
        ]

        XCTAssertEqual(PartnerScopedDataPolicy.scoped(comments, currentMemberID: "_me", partnerID: "_partner").map(\.body), ["partner"])
        XCTAssertEqual(PartnerScopedDataPolicy.scoped(invitations, currentMemberID: "_me", partnerID: "_partner").map(\.title), ["from partner"])
        XCTAssertEqual(PartnerScopedDataPolicy.scoped(requests, currentMemberID: "_me", partnerID: "_partner").map(\.ownerMemberID), ["_partner"])
    }
}

final class PairingSafetyEducationPolicyTests: XCTestCase {
    func testShowsOneTimePairingSafetyNoticeAfterNicknameAndPartnerNoteFlow() {
        XCTAssertTrue(
            PairingSafetyEducationPolicy.shouldPresentNotice(
                pairingStatus: .paired,
                hasPromptedPartnerNoteForCurrentPairing: true,
                hasShownPairingSafetyNoticeForCurrentPairing: false
            )
        )
    }

    func testDoesNotShowPairingSafetyNoticeBeforePairingFinishesOrWhenAlreadyShown() {
        XCTAssertFalse(
            PairingSafetyEducationPolicy.shouldPresentNotice(
                pairingStatus: .waitingForPartnerToShare,
                hasPromptedPartnerNoteForCurrentPairing: true,
                hasShownPairingSafetyNoticeForCurrentPairing: false
            )
        )
        XCTAssertFalse(
            PairingSafetyEducationPolicy.shouldPresentNotice(
                pairingStatus: .paired,
                hasPromptedPartnerNoteForCurrentPairing: false,
                hasShownPairingSafetyNoticeForCurrentPairing: false
            )
        )
        XCTAssertFalse(
            PairingSafetyEducationPolicy.shouldPresentNotice(
                pairingStatus: .paired,
                hasPromptedPartnerNoteForCurrentPairing: true,
                hasShownPairingSafetyNoticeForCurrentPairing: true
            )
        )
    }

    func testShowsPersistentWarningOnlyWhenPairingIsActive() {
        XCTAssertFalse(PairingSafetyEducationPolicy.shouldShowPersistentWarning(pairingStatus: .notPaired))
        XCTAssertTrue(PairingSafetyEducationPolicy.shouldShowPersistentWarning(pairingStatus: .waitingForPartner))
        XCTAssertTrue(PairingSafetyEducationPolicy.shouldShowPersistentWarning(pairingStatus: .paired))
    }
}

final class SharedPeoplePresentationPolicyTests: XCTestCase {
    func testOpensOfficialSharingOnlyWhenCloudKitIsAvailableAndNotBusy() {
        XCTAssertTrue(
            SharedPeoplePresentationPolicy.canOpenOfficialSharing(
                isCloudKitEnabled: true,
                isPreparingShare: false,
                isStoppingShare: false
            )
        )
        XCTAssertFalse(
            SharedPeoplePresentationPolicy.canOpenOfficialSharing(
                isCloudKitEnabled: false,
                isPreparingShare: false,
                isStoppingShare: false
            )
        )
        XCTAssertFalse(
            SharedPeoplePresentationPolicy.canOpenOfficialSharing(
                isCloudKitEnabled: true,
                isPreparingShare: true,
                isStoppingShare: false
            )
        )
        XCTAssertFalse(
            SharedPeoplePresentationPolicy.canOpenOfficialSharing(
                isCloudKitEnabled: true,
                isPreparingShare: false,
                isStoppingShare: true
            )
        )
    }
}

final class PairingDatePolicyTests: XCTestCase {
    func testNormalizesPairingDateToStartOfDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 19, minute: 30)))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))

        XCTAssertEqual(PairingDatePolicy.normalizedPairingDate(date, calendar: calendar), expected)
    }

    func testPairingDayCountUsesCalendarDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let pairingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let sameDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 23)))
        let laterDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 1)))

        XCTAssertEqual(PairingDatePolicy.dayCount(since: pairingDate, now: sameDay, calendar: calendar), 0)
        XCTAssertEqual(PairingDatePolicy.dayCount(since: pairingDate, now: laterDate, calendar: calendar), 3)
    }

    func testPairingOrdinalDayNumberStartsAtOneOnThePairingDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let pairingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 19)))
        let sameDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 23)))
        let nextMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 0, minute: 5)))

        XCTAssertEqual(PairingDatePolicy.ordinalDayNumber(since: pairingDate, now: sameDay, calendar: calendar), 1)
        XCTAssertEqual(PairingDatePolicy.ordinalDayNumber(since: pairingDate, now: nextMorning, calendar: calendar), 2)
    }

    func testDefaultHistoryRequestRangeEndsBeforePairingDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let pairingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))

        let range = PairingDatePolicy.defaultHistoryRequestRange(pairingDate: pairingDate, calendar: calendar)

        XCTAssertEqual(range.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9))))
        XCTAssertEqual(range.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7))))
    }
}

final class SettingsStoreIdentityMigrationTests: XCTestCase {
    func testStartsWithPlaceholderMemberIDAndPersistsFetchedCloudKitID() throws {
        let suiteName = "SettingsStoreIdentityMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunchSettings = SettingsStore(defaults: defaults)

        XCTAssertEqual(firstLaunchSettings.currentMemberID, MemberIDPolicy.unsyncedMemberID)
        XCTAssertFalse(firstLaunchSettings.hasSyncedMemberID)

        firstLaunchSettings.currentMemberID = "_cloudKitUser"
        let secondLaunchSettings = SettingsStore(defaults: defaults)

        XCTAssertEqual(secondLaunchSettings.currentMemberID, "_cloudKitUser")
        XCTAssertTrue(secondLaunchSettings.hasSyncedMemberID)
    }

    func testWipesLegacyLocalOwnerPairingStateAndRequestsLocalDataPurge() throws {
        let suiteName = "SettingsStoreIdentityMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("local-owner-legacy", forKey: "currentLocalOwnerID")
        defaults.set("pair-legacy", forKey: "pairingID")
        defaults.set("_oldPartner", forKey: "partnerShareOwnerID")
        defaults.set(["a@example.com"], forKey: "outgoingShareParticipantIDs")
        defaults.set(true, forKey: "hasStartedPairing")
        defaults.set("Display", forKey: "currentDisplayName")
        defaults.set(["calendar-1"], forKey: "selectedCalendarIDs")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertNil(defaults.string(forKey: "currentLocalOwnerID"))
        XCTAssertNil(defaults.string(forKey: "pairingID"))
        XCTAssertNil(settings.partnerShareOwnerID)
        XCTAssertTrue(settings.outgoingShareParticipantIDs.isEmpty)
        XCTAssertFalse(settings.hasStartedPairing)
        XCTAssertEqual(settings.currentMemberID, MemberIDPolicy.unsyncedMemberID)
        XCTAssertEqual(settings.currentDisplayName, "Display")
        XCTAssertEqual(settings.selectedCalendarIDs, ["calendar-1"])
        XCTAssertTrue(settings.consumeLegacyLocalDataPurgeFlag())
        XCTAssertFalse(settings.consumeLegacyLocalDataPurgeFlag())
    }

    func testPairingConflictPersistsAcrossLaunches() throws {
        let suiteName = "SettingsStoreIdentityMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.pairingConflict = .outgoingIncomingMismatch(
            outgoingIDs: ["_personA"],
            incomingOwnerIDs: ["_personB"]
        )

        let relaunchedSettings = SettingsStore(defaults: defaults)

        XCTAssertEqual(
            relaunchedSettings.pairingConflict,
            .outgoingIncomingMismatch(outgoingIDs: ["_personA"], incomingOwnerIDs: ["_personB"])
        )

        relaunchedSettings.pairingConflict = nil
        XCTAssertNil(SettingsStore(defaults: defaults).pairingConflict)
    }

    func testPartnerSyncedDisplayNameIsPersistedSeparatelyFromPartnerNoteName() throws {
        let suiteName = "SettingsStoreIdentityMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.partnerNoteName = "Home note"
        settings.partnerSyncedDisplayName = "Remote nickname"

        let relaunchedSettings = SettingsStore(defaults: defaults)

        XCTAssertEqual(relaunchedSettings.partnerNoteName, "Home note")
        XCTAssertEqual(relaunchedSettings.partnerSyncedDisplayName, "Remote nickname")
    }

    func testProfileAndPartnerNotePromptStatePersists() throws {
        let suiteName = "SettingsStoreIdentityMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.hasCompletedInitialProfilePrompt)
        XCTAssertFalse(settings.hasPromptedPartnerNoteForCurrentPairing)
        XCTAssertFalse(settings.hasShownPairingSafetyNoticeForCurrentPairing)

        settings.currentDisplayName = "New nickname"
        settings.hasCompletedInitialProfilePrompt = true
        settings.hasPromptedPartnerNoteForCurrentPairing = true
        settings.hasShownPairingSafetyNoticeForCurrentPairing = true

        let relaunchedSettings = SettingsStore(defaults: defaults)

        XCTAssertEqual(relaunchedSettings.currentDisplayName, "New nickname")
        XCTAssertTrue(relaunchedSettings.hasCompletedInitialProfilePrompt)
        XCTAssertTrue(relaunchedSettings.hasPromptedPartnerNoteForCurrentPairing)
        XCTAssertTrue(relaunchedSettings.hasShownPairingSafetyNoticeForCurrentPairing)
    }

    func testResetsCompletedInitialProfilePromptWhenDisplayNameIsMissing() throws {
        let suiteName = "SettingsStoreIdentityMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "hasCompletedInitialProfilePrompt")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.currentDisplayName, "")
        XCTAssertFalse(settings.hasCompletedInitialProfilePrompt)
        XCTAssertFalse(defaults.bool(forKey: "hasCompletedInitialProfilePrompt"))
    }
}

final class ShareCalAcceptedShareSignalTests: XCTestCase {
    func testMarkAcceptedCreatesPendingSyncSignalAndConsumeClearsIt() throws {
        let suiteName = "ShareCalAcceptedShareSignalTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))

        ShareCalAcceptedShareSignal.markAccepted(
            partnerOwnerID: nil,
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertTrue(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))
        XCTAssertFalse(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))
    }

    func testHasPendingReportsSignalWithoutConsumingIt() throws {
        let suiteName = "ShareCalAcceptedShareSignalTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ShareCalAcceptedShareSignal.hasPending(defaults: defaults))

        ShareCalAcceptedShareSignal.markAccepted(
            partnerOwnerID: nil,
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertTrue(ShareCalAcceptedShareSignal.hasPending(defaults: defaults))
        XCTAssertTrue(ShareCalAcceptedShareSignal.consumePending(defaults: defaults))
        XCTAssertFalse(ShareCalAcceptedShareSignal.hasPending(defaults: defaults))
    }

    func testStoresPendingPartnerOwnerIDForAcceptedShare() throws {
        let suiteName = "ShareCalAcceptedShareSignalTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ShareCalAcceptedShareSignal.markAccepted(
            partnerOwnerID: " _partnerOwner ",
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(
            ShareCalAcceptedShareSignal.consumePendingPartnerOwnerID(defaults: defaults),
            "_partnerOwner"
        )
        XCTAssertNil(ShareCalAcceptedShareSignal.consumePendingPartnerOwnerID(defaults: defaults))
    }
}

final class MemberDisplayNamePolicyTests: XCTestCase {
    func testSelfMemberUsesCurrentDisplayName() {
        let name = MemberDisplayNamePolicy.displayName(
            forMemberID: "_me",
            currentMemberID: "_me",
            currentDisplayName: "Wanli",
            selfFallback: "Me",
            partnerDisplayName: "小鱼干"
        )

        XCTAssertEqual(name, "Wanli")
    }

    func testSelfMemberFallsBackWhenDisplayNameBlank() {
        let name = MemberDisplayNamePolicy.displayName(
            forMemberID: "_me",
            currentMemberID: "_me",
            currentDisplayName: "   ",
            selfFallback: "Me",
            partnerDisplayName: "小鱼干"
        )

        XCTAssertEqual(name, "Me")
    }

    func testPartnerMemberUsesPartnerDisplayName() {
        let name = MemberDisplayNamePolicy.displayName(
            forMemberID: "_82828b1d87c3d5e8685ae3b8c5a6c80a",
            currentMemberID: "_me",
            currentDisplayName: "Wanli",
            selfFallback: "Me",
            partnerDisplayName: "小鱼干"
        )

        XCTAssertEqual(name, "小鱼干")
    }

    func testNeverReturnsRawMemberID() {
        let partnerID = "_82828b1d87c3d5e8685ae3b8c5a6c80a"
        let name = MemberDisplayNamePolicy.displayName(
            forMemberID: partnerID,
            currentMemberID: "_me",
            currentDisplayName: nil,
            selfFallback: "Me",
            partnerDisplayName: "Partner"
        )

        XCTAssertNotEqual(name, partnerID)
        XCTAssertEqual(name, "Partner")
    }
}

final class MemberIDPolicyTests: XCTestCase {
    func testNormalizedTrimsWhitespaceAndDropsBlankValues() {
        XCTAssertEqual(MemberIDPolicy.normalized("  _owner \n"), "_owner")
        XCTAssertNil(MemberIDPolicy.normalized("   "))
        XCTAssertNil(MemberIDPolicy.normalized(""))
        XCTAssertNil(MemberIDPolicy.normalized(nil))
        XCTAssertEqual(MemberIDPolicy.normalizedList([" a ", "", "b", "\t"]), ["a", "b"])
    }
}

final class PairingGuidePolicyTests: XCTestCase {
    func testInitiatorWalksThroughTheFirstThreeSteps() {
        XCTAssertEqual(
            PairingGuidePolicy.state(status: .notPaired, partnerShareOwnerID: nil, sentInviteBackToOwnerID: nil),
            PairingGuideState(role: .initiator, currentStep: .firstLinkSent)
        )
        XCTAssertEqual(
            PairingGuidePolicy.state(status: .waitingForPartner, partnerShareOwnerID: nil, sentInviteBackToOwnerID: nil),
            PairingGuideState(role: .initiator, currentStep: .firstLinkAccepted)
        )
        XCTAssertEqual(
            PairingGuidePolicy.state(status: .waitingForPartnerToShare, partnerShareOwnerID: nil, sentInviteBackToOwnerID: nil),
            PairingGuideState(role: .initiator, currentStep: .linkSentBack)
        )
        XCTAssertNil(PairingGuidePolicy.state(status: .paired, partnerShareOwnerID: "_a", sentInviteBackToOwnerID: nil))
    }

    func testReceiverOwesTheLinkBackUntilItIsSentToThisPartner() {
        XCTAssertEqual(
            PairingGuidePolicy.state(status: .waitingForYouToShare, partnerShareOwnerID: "_a", sentInviteBackToOwnerID: nil),
            PairingGuideState(role: .receiver, currentStep: .linkSentBack)
        )
        XCTAssertEqual(
            PairingGuidePolicy.state(status: .waitingForYouToShare, partnerShareOwnerID: "_a", sentInviteBackToOwnerID: "_a"),
            PairingGuideState(role: .receiver, currentStep: .linkBackAccepted)
        )
        // A link sent back to an earlier partner does not count for the new one.
        XCTAssertEqual(
            PairingGuidePolicy.state(status: .waitingForYouToShare, partnerShareOwnerID: "_b", sentInviteBackToOwnerID: "_a"),
            PairingGuideState(role: .receiver, currentStep: .linkSentBack)
        )
    }

    func testStepActorAlternatesBetweenUs() {
        XCTAssertEqual(PairingGuideStep.allCases.map { $0.actor(for: .initiator) }, [.me, .partner, .partner, .me])
        XCTAssertEqual(PairingGuideStep.allCases.map { $0.actor(for: .receiver) }, [.partner, .me, .me, .partner])
    }

    func testShareBackPromptShowsOncePerPartnerAndOnlyBeforeSendingBack() {
        XCTAssertTrue(PairingGuidePolicy.shouldPresentShareBackPrompt(
            status: .waitingForYouToShare,
            partnerShareOwnerID: "_a",
            sentInviteBackToOwnerID: nil,
            shareBackPromptShownForOwnerID: nil
        ))
        XCTAssertFalse(PairingGuidePolicy.shouldPresentShareBackPrompt(
            status: .waitingForYouToShare,
            partnerShareOwnerID: "_a",
            sentInviteBackToOwnerID: nil,
            shareBackPromptShownForOwnerID: "_a"
        ))
        XCTAssertFalse(PairingGuidePolicy.shouldPresentShareBackPrompt(
            status: .waitingForYouToShare,
            partnerShareOwnerID: "_a",
            sentInviteBackToOwnerID: "_a",
            shareBackPromptShownForOwnerID: nil
        ))
        XCTAssertTrue(PairingGuidePolicy.shouldPresentShareBackPrompt(
            status: .waitingForYouToShare,
            partnerShareOwnerID: "_b",
            sentInviteBackToOwnerID: nil,
            shareBackPromptShownForOwnerID: "_a"
        ))
        for status in [PairingStatus.notPaired, .waitingForPartner, .waitingForPartnerToShare, .paired] {
            XCTAssertFalse(PairingGuidePolicy.shouldPresentShareBackPrompt(
                status: status,
                partnerShareOwnerID: "_a",
                sentInviteBackToOwnerID: nil,
                shareBackPromptShownForOwnerID: nil
            ))
        }
    }

    func testKnownPartnerNamePrefersMyNoteAndIsNilWhenUnknown() {
        XCTAssertEqual(PairingGuidePolicy.knownPartnerName(partnerNoteName: " 小鱼 ", partnerSyncedDisplayName: "Yu"), "小鱼")
        XCTAssertEqual(PairingGuidePolicy.knownPartnerName(partnerNoteName: "", partnerSyncedDisplayName: "Yu"), "Yu")
        XCTAssertNil(PairingGuidePolicy.knownPartnerName(partnerNoteName: nil, partnerSyncedDisplayName: " "))
    }

    func testInviteMessageCarriesAppStoreLinkAndShareLink() {
        let shareURL = URL(string: "https://www.icloud.com/share/0abcDEF")!
        for language in [AppLanguage.chinese, .english] {
            let strings = ShareCalStrings(language: language)
            let first = PairingInviteMessagePolicy.inviteMessage(shareURL: shareURL, isSendingBack: false, strings: strings)
            XCTAssertTrue(first.contains(shareURL.absoluteString))
            XCTAssertTrue(first.contains(PairingInviteMessagePolicy.appStoreURL.absoluteString))
            let back = PairingInviteMessagePolicy.inviteMessage(shareURL: shareURL, isSendingBack: true, strings: strings)
            XCTAssertTrue(back.contains(shareURL.absoluteString))
            XCTAssertFalse(back.contains(PairingInviteMessagePolicy.appStoreURL.absoluteString))
        }
    }

    func testGuideCopyFallsBackToTAWhenThePartnerIsUnknown() {
        let strings = ShareCalStrings(language: .chinese)
        let state = PairingGuideState(role: .initiator, currentStep: .firstLinkAccepted)
        let visible = { (text: String) in text.replacingOccurrences(of: "\u{2060}", with: "") }
        XCTAssertEqual(visible(strings.pairingGuideHeadline(state, partnerName: nil)), "邀请已寄出，等TA点开")
        XCTAssertEqual(visible(strings.pairingGuideHeadline(state, partnerName: "小鱼")), "邀请已寄出，等小鱼点开")
        XCTAssertEqual(strings.pairingGuideSendBackButton("阿立"), "回发邀请给阿立")
    }

    func testGuideHeadlinesKeepTheVerbOnOneLine() {
        let strings = ShareCalStrings(language: .chinese)
        let headline = strings.pairingGuideHeadline(
            PairingGuideState(role: .initiator, currentStep: .linkSentBack),
            partnerName: nil
        )
        XCTAssertTrue(headline.contains("回\u{2060}寄"))
        XCTAssertEqual(ShareCalStrings.keepTogether("点开"), "点\u{2060}开")
    }
}

final class PartnerDeparturePolicyTests: XCTestCase {
    func testPartnerUnpairingFromPairedIsADeparture() {
        XCTAssertTrue(PartnerDeparturePolicy.partnerHasLeft(
            previousPartnerID: "_a",
            previousOutgoingParticipantIDs: ["_a"],
            resolvedPartnerID: nil,
            outgoingParticipantIDs: []
        ))
    }

    func testPartnerUnpairingHalfwayIsADeparture() {
        // They had opened my link but not sent theirs back.
        XCTAssertTrue(PartnerDeparturePolicy.partnerHasLeft(
            previousPartnerID: nil,
            previousOutgoingParticipantIDs: ["_a"],
            resolvedPartnerID: nil,
            outgoingParticipantIDs: []
        ))
        // I had opened their link but not sent mine back.
        XCTAssertTrue(PartnerDeparturePolicy.partnerHasLeft(
            previousPartnerID: "_a",
            previousOutgoingParticipantIDs: [],
            resolvedPartnerID: nil,
            outgoingParticipantIDs: []
        ))
    }

    func testAnUnopenedInvitationIsNotADeparture() {
        XCTAssertFalse(PartnerDeparturePolicy.partnerHasLeft(
            previousPartnerID: nil,
            previousOutgoingParticipantIDs: [],
            resolvedPartnerID: nil,
            outgoingParticipantIDs: []
        ))
    }

    func testOneHalfStillStandingIsNotADeparture() {
        XCTAssertFalse(PartnerDeparturePolicy.partnerHasLeft(
            previousPartnerID: "_a",
            previousOutgoingParticipantIDs: ["_a"],
            resolvedPartnerID: nil,
            outgoingParticipantIDs: ["_a"]
        ))
        XCTAssertFalse(PartnerDeparturePolicy.partnerHasLeft(
            previousPartnerID: "_a",
            previousOutgoingParticipantIDs: ["_a"],
            resolvedPartnerID: "_a",
            outgoingParticipantIDs: []
        ))
    }

    func testBlankIDsDoNotCountAsSomeone() {
        XCTAssertFalse(PartnerDeparturePolicy.partnerHasLeft(
            previousPartnerID: "  ",
            previousOutgoingParticipantIDs: [""],
            resolvedPartnerID: nil,
            outgoingParticipantIDs: []
        ))
    }
}
