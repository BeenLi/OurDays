import XCTest

final class AppLanguageSettingsTests: XCTestCase {
    func testFollowsChineseSystemLanguageWhenNoPreferenceExists() {
        let suiteName = "AppLanguageSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppLanguagePreference.read(from: defaults, preferredLanguages: ["zh-Hans-CN", "en-US"]), .chinese)
        XCTAssertEqual(AppLanguagePreference.read(from: defaults, preferredLanguages: ["zh-Hant-TW"]), .chinese)
    }

    func testFollowsNonChineseSystemLanguageAsEnglish() {
        let suiteName = "AppLanguageSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppLanguagePreference.read(from: defaults, preferredLanguages: ["en-GB", "zh-Hans-CN"]), .english)
        XCTAssertEqual(AppLanguagePreference.read(from: defaults, preferredLanguages: ["ja-JP"]), .english)
        XCTAssertEqual(AppLanguagePreference.read(from: defaults, preferredLanguages: []), .english)
    }

    func testSelectedLanguageOverridesSystemLanguage() {
        let suiteName = "AppLanguageSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguagePreference.write(.chinese, to: defaults)

        XCTAssertEqual(AppLanguagePreference.read(from: defaults, preferredLanguages: ["en-US"]), .chinese)
    }

    func testPersistsSelectedEnglishLanguage() {
        let suiteName = "AppLanguageSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguagePreference.write(.english, to: defaults)

        let language = AppLanguagePreference.read(from: defaults)

        XCTAssertEqual(language, .english)
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
        XCTAssertEqual(strings.currentDisplayNameRequiredMessage, "Enter your nickname before pairing.")
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
        XCTAssertEqual(strings.sharingMyCalendarLabel, "Sharing My Calendar")
        XCTAssertEqual(strings.partnersCalendarLabel, "Partner's Calendar")
        XCTAssertEqual(strings.startPairingButton(isPreparing: false), "Start Pairing")
        XCTAssertEqual(strings.defaultVisibilityLabel(for: .fullDetails), "Full details")
        XCTAssertEqual(strings.unpairButton, "Unpair")
        XCTAssertEqual(strings.pairingConflictTitle, "Pairing Conflict")
        XCTAssertEqual(strings.keepPartnerButton("Yoki"), "Keep Yoki")
        XCTAssertEqual(strings.pairingReplacementTitle, "Replace Current Pairing?")
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
        XCTAssertEqual(strings.currentDisplayNameRequiredMessage, "配对前请先填写我的昵称。")
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
        XCTAssertEqual(strings.sharingMyCalendarLabel, "我共享给对方")
        XCTAssertEqual(strings.partnersCalendarLabel, "对方共享给我")
        XCTAssertEqual(strings.startPairingButton(isPreparing: false), "发起配对")
        XCTAssertEqual(strings.defaultVisibilityLabel(for: .fullDetails), "完整详情")
        XCTAssertEqual(strings.unpairButton, "解除配对")
        XCTAssertEqual(strings.pairingConflictTitle, "配对冲突")
        XCTAssertEqual(strings.keepPartnerButton("Yoki"), "保留 Yoki")
        XCTAssertEqual(strings.pairingReplacementTitle, "更换配对对象？")
        XCTAssertEqual(strings.deleteICloudDataButton, "删除我的 iCloud 数据")
        XCTAssertEqual(strings.deleteICloudDataSucceeded, "iCloud 数据已删除。")
    }
}

final class MemberAvatarPolicyTests: XCTestCase {
    func testNormalizedTextKeepsThreeLettersOrTwoWideCharacters() {
        XCTAssertEqual(MemberAvatarPolicy.normalizedText("  Leeroy "), "Lee")
        XCTAssertEqual(MemberAvatarPolicy.normalizedText("小雨同学"), "小雨")
        XCTAssertEqual(MemberAvatarPolicy.normalizedText("A雨b"), "A雨")
        XCTAssertNil(MemberAvatarPolicy.normalizedText("   "))
        XCTAssertNil(MemberAvatarPolicy.normalizedText(nil))
    }

    func testNormalizedPrefersPhotoAndDropsEmptyAvatars() {
        let photo = Data([0x01, 0x02])
        XCTAssertEqual(
            MemberAvatarPolicy.normalized(MemberAvatar(text: "Lee", background: .teal, imageData: photo)),
            MemberAvatar(imageData: photo)
        )
        XCTAssertEqual(
            MemberAvatarPolicy.normalized(MemberAvatar(text: " 雨 ", background: .coral)),
            MemberAvatar(text: "雨", background: .coral)
        )
        XCTAssertNil(MemberAvatarPolicy.normalized(MemberAvatar(text: " ", background: .sage, imageData: Data())))
        XCTAssertNil(MemberAvatarPolicy.normalized(nil))
    }

    func testPartnerAvatarPrefersLocalOverrideOverSyncedAvatar() {
        let override = MemberAvatar(text: "雨", background: .coral)
        let synced = MemberAvatar(text: "Rain", background: .lavender)

        XCTAssertEqual(MemberAvatarPolicy.resolvedPartnerAvatar(override: override, synced: synced), override)
        XCTAssertEqual(MemberAvatarPolicy.resolvedPartnerAvatar(override: nil, synced: synced), MemberAvatar(text: "Rai", background: .lavender))
        XCTAssertEqual(
            MemberAvatarPolicy.resolvedPartnerAvatar(override: MemberAvatar(text: " "), synced: synced),
            MemberAvatar(text: "Rai", background: .lavender)
        )
        XCTAssertNil(MemberAvatarPolicy.resolvedPartnerAvatar(override: nil, synced: nil))
    }

    func testInitialsUseFirstCharacterOrFallback() {
        XCTAssertEqual(MemberAvatarPolicy.initials(from: " lee", fallback: "我"), "L")
        XCTAssertEqual(MemberAvatarPolicy.initials(from: "小雨", fallback: "我"), "小")
        XCTAssertEqual(MemberAvatarPolicy.initials(from: "  ", fallback: "我"), "我")
        XCTAssertEqual(MemberAvatarPolicy.initials(from: nil, fallback: "TA"), "TA")
    }
}

final class OurDaysRedesignPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    func testCollapsedTimelineStartsAtEarliestOfDefaultEventsAndNow() {
        let dayStart = date(16)
        let otherDay = date(20)

        XCTAssertEqual(
            DayTimelineCollapsePolicy.visibleStartHour(eventStartDates: [date(16, 10)], dayStart: dayStart, now: otherDay, isExpanded: false, defaultStartHour: 8, calendar: calendar),
            8
        )
        XCTAssertEqual(
            DayTimelineCollapsePolicy.visibleStartHour(eventStartDates: [date(16, 6, 30), date(17, 1)], dayStart: dayStart, now: otherDay, isExpanded: false, defaultStartHour: 8, calendar: calendar),
            6
        )
        XCTAssertEqual(
            DayTimelineCollapsePolicy.visibleStartHour(eventStartDates: [], dayStart: dayStart, now: date(16, 5, 10), isExpanded: false, defaultStartHour: 8, calendar: calendar),
            5
        )
    }

    func testTimelineShowsWholeNightWhenExpandedOrAnEventCrossesMidnight() {
        let dayStart = date(16)

        XCTAssertEqual(
            DayTimelineCollapsePolicy.visibleStartHour(eventStartDates: [date(15, 22)], dayStart: dayStart, now: date(20), isExpanded: false, defaultStartHour: 8, calendar: calendar),
            0
        )
        XCTAssertEqual(
            DayTimelineCollapsePolicy.visibleStartHour(eventStartDates: [date(16, 12)], dayStart: dayStart, now: date(20), isExpanded: true, defaultStartHour: 8, calendar: calendar),
            0
        )
    }

    func testWeekStripFlagsWhoHasEventsEachDay() {
        let days = WeekStripPolicy.days(
            containing: date(17, 12),
            mine: [DateInterval(start: date(15, 9), end: date(15, 10))],
            partner: [DateInterval(start: date(16, 23), end: date(17, 1))],
            joint: [DateInterval(start: date(18, 0), end: date(18, 0))],
            calendar: calendar
        )

        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.date, date(15))
        XCTAssertEqual(days.map(\.hasMine), [true, false, false, false, false, false, false])
        XCTAssertEqual(days.map(\.hasPartner), [false, true, true, false, false, false, false])
        XCTAssertEqual(days.map(\.hasJoint), [false, false, false, true, false, false, false])
    }

    func testWeekStripEventEndingAtMidnightDoesNotSpillIntoNextDay() {
        let event = DateInterval(start: date(16, 22), end: date(17))
        XCTAssertTrue(WeekStripPolicy.overlaps(event, DateInterval(start: date(16), end: date(17))))
        XCTAssertFalse(WeekStripPolicy.overlaps(event, DateInterval(start: date(17), end: date(18))))
    }

    func testActivityFeedSectionsGroupByDayNewestFirst() {
        func item(_ id: String, _ at: Date) -> ActivityFeedItem {
            ActivityFeedItem(
                eventMirrorID: id,
                eventTitle: id,
                latestCommentAt: at,
                latestCommentBody: "",
                latestCommentAuthorMemberID: "_partner",
                commentCount: 1,
                unreadCount: 0
            )
        }

        let sections = ActivityFeedSectionPolicy.sections(
            [item("a", date(15, 9)), item("b", date(16, 21)), item("c", date(16, 8))],
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.dayStart), [date(16), date(15)])
        XCTAssertEqual(sections.map { $0.items.map(\.eventMirrorID) }, [["b", "c"], ["a"]])
    }

    func testEventDetailTimeCombinesStartAndEndOnOneLine() {
        let strings = ShareCalStrings(language: .english)
        let locale = Locale(identifier: "en_US_POSIX")

        let sameDay = EventDetailTimePolicy.text(startDate: date(16, 19, 30), endDate: date(16, 21, 30), isAllDay: false, strings: strings, locale: locale, calendar: calendar)
        XCTAssertTrue(sameDay.contains(" · "), sameDay)
        XCTAssertFalse(sameDay.contains(" – Jun"), sameDay)

        let allDay = EventDetailTimePolicy.text(startDate: date(16), endDate: date(17), isAllDay: true, strings: strings, locale: locale, calendar: calendar)
        XCTAssertTrue(allDay.hasSuffix(strings.allDay), allDay)
        XCTAssertFalse(allDay.contains("–"), allDay)
    }
}
