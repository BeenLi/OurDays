import XCTest

final class ICloudSharingTeardownPlanTests: XCTestCase {
    func testPurgesPartnerOwnerAndPlaceholderIDs() {
        let ownerIDs = ICloudSharingTeardownPlan.localOwnerIDsToPurge(
            partnerShareOwnerID: "_partnerOwner"
        )

        XCTAssertEqual(ownerIDs, ["_partnerOwner", "partner"])
    }

    func testIgnoresMissingPartnerOwnerID() {
        let ownerIDs = ICloudSharingTeardownPlan.localOwnerIDsToPurge(partnerShareOwnerID: " ")

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

    func testPartnerDisplayNamePrefersLocalNoteThenSyncedProfile() {
        XCTAssertEqual(
            PairingSettingsPlan.partnerDisplayName(
                partnerNoteName: " Local note ",
                partnerSyncedDisplayName: "Remote name",
                fallback: "Partner"
            ),
            "Local note"
        )
        XCTAssertEqual(
            PairingSettingsPlan.partnerDisplayName(
                partnerNoteName: " ",
                partnerSyncedDisplayName: " Remote name ",
                fallback: "Partner"
            ),
            "Remote name"
        )
        XCTAssertEqual(
            PairingSettingsPlan.partnerDisplayName(
                partnerNoteName: "",
                partnerSyncedDisplayName: nil,
                fallback: "Partner"
            ),
            "Partner"
        )
    }

    func testPartnerStatusDisplayNameShowsNicknameWithOptionalNote() {
        XCTAssertEqual(
            PairingSettingsPlan.partnerStatusDisplayName(
                partnerNoteName: " Home ",
                partnerSyncedDisplayName: " Yoki ",
                fallback: "Partner",
                language: .english
            ),
            "Yoki (Home)"
        )
        XCTAssertEqual(
            PairingSettingsPlan.partnerStatusDisplayName(
                partnerNoteName: " ",
                partnerSyncedDisplayName: " Yoki ",
                fallback: "Partner",
                language: .chinese
            ),
            "Yoki"
        )
        XCTAssertEqual(
            PairingSettingsPlan.partnerStatusDisplayName(
                partnerNoteName: " Yoki ",
                partnerSyncedDisplayName: "Yoki",
                fallback: "Partner",
                language: .chinese
            ),
            "Yoki"
        )
        XCTAssertEqual(
            PairingSettingsPlan.partnerStatusDisplayName(
                partnerNoteName: " 宝宝 ",
                partnerSyncedDisplayName: nil,
                fallback: "对方",
                language: .chinese
            ),
            "对方（宝宝）"
        )
    }

    func testNormalizesCurrentDisplayNameForProfileSync() {
        XCTAssertEqual(PairingSettingsPlan.normalizedDisplayName(" Manu "), "Manu")
        XCTAssertNil(PairingSettingsPlan.normalizedDisplayName(" "))
        XCTAssertNil(PairingSettingsPlan.normalizedDisplayName(nil))
    }

    func testRandomNicknameIsReadableAndStableLength() {
        let nickname = PairingSettingsPlan.randomDisplayName(randomNumber: { 42 })

        XCTAssertEqual(nickname, "OurDays 0042")
    }
}

final class TwoPersonPairingPlanTests: XCTestCase {
    func testMutualShareEstablishesPartnerAndLeavesStaleZones() {
        let resolution = TwoPersonPairingPlan.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_partner"],
            sharedZoneOwnerIDs: ["_partner", "_oldFriend"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertEqual(resolution.sharedZoneOwnerIDsToLeave, ["_oldFriend"])
        XCTAssertNil(resolution.conflict)
    }

    func testSingleIncomingShareBecomesPartnerWithoutOutgoingShare() {
        let resolution = TwoPersonPairingPlan.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: [],
            sharedZoneOwnerIDs: ["_partner"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertTrue(resolution.sharedZoneOwnerIDsToLeave.isEmpty)
        XCTAssertNil(resolution.conflict)
    }

    func testStoredPartnerSelectsAmongMultipleIncomingShares() {
        let resolution = TwoPersonPairingPlan.resolve(
            storedPartnerID: "_partner",
            outgoingAcceptedParticipantIDs: [],
            sharedZoneOwnerIDs: ["_oldFriend", "_partner"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertEqual(resolution.sharedZoneOwnerIDsToLeave, ["_oldFriend"])
        XCTAssertNil(resolution.conflict)
    }

    func testMultipleIncomingSharesWithoutBindingIsAConflict() {
        let resolution = TwoPersonPairingPlan.resolve(
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
        let resolution = TwoPersonPairingPlan.resolve(
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
        let resolution = TwoPersonPairingPlan.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_personB", "_personA"],
            sharedZoneOwnerIDs: ["_personC"]
        )

        XCTAssertEqual(
            resolution.conflict,
            .outgoingIncomingMismatch(outgoingIDs: ["_personA", "_personB"], incomingOwnerIDs: ["_personC"])
        )
        XCTAssertEqual(
            TwoPersonPairingConflictPresentationPlan.candidateIDs(
                .outgoingIncomingMismatch(outgoingIDs: ["_personA", "_personB"], incomingOwnerIDs: ["_personC"])
            ),
            ["_personA", "_personB", "_personC"]
        )
    }

    func testOutgoingOnlyShareWaitsForPartnerWithoutConflict() {
        let resolution = TwoPersonPairingPlan.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["_partner"],
            sharedZoneOwnerIDs: []
        )

        XCTAssertNil(resolution.partnerID)
        XCTAssertTrue(resolution.sharedZoneOwnerIDsToLeave.isEmpty)
        XCTAssertNil(resolution.conflict)
    }

    func testMultipleOutgoingParticipantsWithoutBindingIsAConflict() {
        let resolution = TwoPersonPairingPlan.resolve(
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
        let resolution = TwoPersonPairingPlan.resolve(
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
        let resolution = TwoPersonPairingPlan.resolve(
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
            TwoPersonPairingConflictPresentationPlan.candidateIDs(
                .outgoingIncomingMismatch(outgoingIDs: ["_newcomer", "_partner"], incomingOwnerIDs: ["_partner"])
            ),
            ["_newcomer", "_partner"]
        )
    }

    func testStaleIncomingZonesStillLeaveWhenOutgoingHasOnlyThePartner() {
        let resolution = TwoPersonPairingPlan.resolve(
            storedPartnerID: "_partner",
            outgoingAcceptedParticipantIDs: ["_partner"],
            sharedZoneOwnerIDs: ["_partner", "_oldFriend"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertEqual(resolution.sharedZoneOwnerIDsToLeave, ["_oldFriend"])
        XCTAssertNil(resolution.conflict)
    }

    func testNonCloudKitParticipantIdentifiersAreIgnoredForMatching() {
        let resolution = TwoPersonPairingPlan.resolve(
            storedPartnerID: nil,
            outgoingAcceptedParticipantIDs: ["partner@example.com"],
            sharedZoneOwnerIDs: ["_partner"]
        )

        XCTAssertEqual(resolution.partnerID, "_partner")
        XCTAssertNil(resolution.conflict)
    }
}

final class ShareAcceptanceGuardPlanTests: XCTestCase {
    func testFirstAcceptanceNeedsNoConfirmation() {
        XCTAssertFalse(
            ShareAcceptanceGuardPlan.requiresReplacementConfirmation(
                incomingOwnerID: "_partner",
                storedPartnerID: nil,
                outgoingParticipantIDs: []
            )
        )
    }

    func testReacceptingCurrentPartnerNeedsNoConfirmation() {
        XCTAssertFalse(
            ShareAcceptanceGuardPlan.requiresReplacementConfirmation(
                incomingOwnerID: "_partner",
                storedPartnerID: "_partner",
                outgoingParticipantIDs: []
            )
        )
    }

    func testAcceptingDifferentPersonThanStoredPartnerNeedsConfirmation() {
        XCTAssertTrue(
            ShareAcceptanceGuardPlan.requiresReplacementConfirmation(
                incomingOwnerID: "_intruder",
                storedPartnerID: "_partner",
                outgoingParticipantIDs: []
            )
        )
    }

    func testAcceptingDifferentPersonThanOutgoingParticipantNeedsConfirmation() {
        XCTAssertTrue(
            ShareAcceptanceGuardPlan.requiresReplacementConfirmation(
                incomingOwnerID: "_intruder",
                storedPartnerID: nil,
                outgoingParticipantIDs: ["_partner"]
            )
        )
    }

    func testNonCloudKitOutgoingIdentifiersDoNotBlockAcceptance() {
        XCTAssertFalse(
            ShareAcceptanceGuardPlan.requiresReplacementConfirmation(
                incomingOwnerID: "_partner",
                storedPartnerID: nil,
                outgoingParticipantIDs: ["partner@example.com"]
            )
        )
    }
}

final class ExistingICloudDataRecoveryPlanTests: XCTestCase {
    func testPromptsWhenFreshLocalStateFindsExistingCloudDataAfterProfileSetup() {
        XCTAssertTrue(
            ExistingICloudDataRecoveryPlan.shouldPresent(
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
            ExistingICloudDataRecoveryPlan.shouldPresent(
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
            ExistingICloudDataRecoveryPlan.shouldPresent(
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
            ExistingICloudDataRecoveryPlan.shouldDeferAutomaticSync(
                hasResolvedPrompt: false,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                lastSyncAt: nil
            )
        )
        XCTAssertFalse(
            ExistingICloudDataRecoveryPlan.shouldDeferAutomaticSync(
                hasResolvedPrompt: true,
                hasStartedPairing: false,
                partnerShareOwnerID: nil,
                outgoingShareParticipantIDs: [],
                lastSyncAt: nil
            )
        )
    }
}

final class PairingSafetyEducationPlanTests: XCTestCase {
    func testShowsOneTimePairingSafetyNoticeAfterNicknameAndPartnerNoteFlow() {
        XCTAssertTrue(
            PairingSafetyEducationPlan.shouldPresentNotice(
                pairingStatus: .paired,
                hasPromptedPartnerNoteForCurrentPairing: true,
                hasShownPairingSafetyNoticeForCurrentPairing: false
            )
        )
    }

    func testDoesNotShowPairingSafetyNoticeBeforePairingFinishesOrWhenAlreadyShown() {
        XCTAssertFalse(
            PairingSafetyEducationPlan.shouldPresentNotice(
                pairingStatus: .waitingForPartnerToShare,
                hasPromptedPartnerNoteForCurrentPairing: true,
                hasShownPairingSafetyNoticeForCurrentPairing: false
            )
        )
        XCTAssertFalse(
            PairingSafetyEducationPlan.shouldPresentNotice(
                pairingStatus: .paired,
                hasPromptedPartnerNoteForCurrentPairing: false,
                hasShownPairingSafetyNoticeForCurrentPairing: false
            )
        )
        XCTAssertFalse(
            PairingSafetyEducationPlan.shouldPresentNotice(
                pairingStatus: .paired,
                hasPromptedPartnerNoteForCurrentPairing: true,
                hasShownPairingSafetyNoticeForCurrentPairing: true
            )
        )
    }

    func testShowsPersistentWarningOnlyWhenPairingIsActive() {
        XCTAssertFalse(PairingSafetyEducationPlan.shouldShowPersistentWarning(pairingStatus: .notPaired))
        XCTAssertTrue(PairingSafetyEducationPlan.shouldShowPersistentWarning(pairingStatus: .waitingForPartner))
        XCTAssertTrue(PairingSafetyEducationPlan.shouldShowPersistentWarning(pairingStatus: .paired))
    }
}

final class SharedPeoplePresentationPlanTests: XCTestCase {
    func testOpensOfficialSharingOnlyWhenCloudKitIsAvailableAndNotBusy() {
        XCTAssertTrue(
            SharedPeoplePresentationPlan.canOpenOfficialSharing(
                isCloudKitEnabled: true,
                isPreparingShare: false,
                isStoppingShare: false
            )
        )
        XCTAssertFalse(
            SharedPeoplePresentationPlan.canOpenOfficialSharing(
                isCloudKitEnabled: false,
                isPreparingShare: false,
                isStoppingShare: false
            )
        )
        XCTAssertFalse(
            SharedPeoplePresentationPlan.canOpenOfficialSharing(
                isCloudKitEnabled: true,
                isPreparingShare: true,
                isStoppingShare: false
            )
        )
        XCTAssertFalse(
            SharedPeoplePresentationPlan.canOpenOfficialSharing(
                isCloudKitEnabled: true,
                isPreparingShare: false,
                isStoppingShare: true
            )
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

    func testPairingOrdinalDayNumberStartsAtOneOnThePairingDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let pairingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 19)))
        let sameDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 23)))
        let nextMorning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 0, minute: 5)))

        XCTAssertEqual(PairingDatePlan.ordinalDayNumber(since: pairingDate, now: sameDay, calendar: calendar), 1)
        XCTAssertEqual(PairingDatePlan.ordinalDayNumber(since: pairingDate, now: nextMorning, calendar: calendar), 2)
    }

    func testDefaultHistoryRequestRangeEndsBeforePairingDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let pairingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))

        let range = PairingDatePlan.defaultHistoryRequestRange(pairingDate: pairingDate, calendar: calendar)

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

        XCTAssertEqual(firstLaunchSettings.currentMemberID, SettingsStore.unsyncedMemberID)
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
        XCTAssertEqual(settings.currentMemberID, SettingsStore.unsyncedMemberID)
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

final class MemberDisplayNamePlanTests: XCTestCase {
    func testSelfMemberUsesCurrentDisplayName() {
        let name = MemberDisplayNamePlan.displayName(
            forMemberID: "_me",
            currentMemberID: "_me",
            currentDisplayName: "Wanli",
            selfFallback: "Me",
            partnerDisplayName: "小鱼干"
        )

        XCTAssertEqual(name, "Wanli")
    }

    func testSelfMemberFallsBackWhenDisplayNameBlank() {
        let name = MemberDisplayNamePlan.displayName(
            forMemberID: "_me",
            currentMemberID: "_me",
            currentDisplayName: "   ",
            selfFallback: "Me",
            partnerDisplayName: "小鱼干"
        )

        XCTAssertEqual(name, "Me")
    }

    func testPartnerMemberUsesPartnerDisplayName() {
        let name = MemberDisplayNamePlan.displayName(
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
        let name = MemberDisplayNamePlan.displayName(
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
