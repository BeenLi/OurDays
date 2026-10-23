import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }

    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .chinese: Locale(identifier: "zh_Hans")
        }
    }
}

enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"

    var id: String { rawValue }
}

enum AppLanguagePreference {
    static let defaultLanguage: AppLanguage = .chinese
    static let key = "appLanguage"

    static func read(from defaults: UserDefaults) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: key) ?? "") ?? defaultLanguage
    }

    static func write(_ language: AppLanguage, to defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: key)
    }
}

enum AppLegalInfo {
    /// MIIT (信管〔2023〕105号) requires the APP filing number to be shown in a prominent
    /// place in-app with a link to the filing system below it. `nil` hides the row.
    static let icpFilingNumber: String? = "沪ICP备2026030016号-1A"
    static let icpFilingSystemURL = URL(string: "https://beian.miit.gov.cn")!

    static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }
}

struct ShareCalStrings {
    let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
    }

    var calendarTab: String { text("Calendar", "日历") }
    var activityTab: String { text("Activity", "动态") }
    var invitesTab: String { text("Invites", "邀请") }
    var activityTitle: String { text("Activity", "动态") }
    var activityEmptyTitle: String { text("No activity yet", "还没有动态") }
    var activityEmptyMessage: String {
        text("Comments on shared events show up here.", "共享日程下的评论会显示在这里。")
    }
    var notifCommentTitle: String { text("New comment", "新评论") }
    var notifInviteReceivedTitle: String { text("New invitation", "新邀请") }
    var notifInviteAcceptedTitle: String { text("Invitation accepted", "邀请已接受") }
    var notifInviteDeclinedTitle: String { text("Invitation declined", "邀请被拒绝") }
    var notifAccessRequestTitle: String { text("History access request", "历史访问请求") }
    var notifAccessRequestBody: String {
        text("Your partner asked to see more of your history.", "对方申请查看你更多的历史日程。")
    }
    var notifAccessApprovedTitle: String { text("History access approved", "历史访问已通过") }
    var notifAccessDeclinedTitle: String { text("History access declined", "历史访问被拒绝") }
    var notifAccessAnsweredBody: String {
        text("Your history access request was answered.", "你的历史访问申请有了回应。")
    }
    var settingsTitle: String { text("Settings", "设置") }
    var dayMode: String { text("Day", "日") }
    var weekMode: String { text("Week", "周") }
    var meTitle: String { text("Me", "我") }
    var partnerTitle: String { text("Partner", "对方") }
    var syncAccessibilityLabel: String { text("Sync", "同步") }
    var diagnosticsTitle: String { text("Diagnostics", "详情诊断") }
    var createInviteAccessibilityLabel: String { text("Create invite", "新建邀请") }
    var previousDateAccessibilityLabel: String { text("Previous date", "上一个日期") }
    var nextDateAccessibilityLabel: String { text("Next date", "下一个日期") }
    var selectDateAccessibilityLabel: String { text("Select date", "选择日期") }
    var todayButton: String { text("Today", "今天") }
    var datePickerTitle: String { text("Select Date", "选择日期") }
    var newInviteTitle: String { text("New Invite", "新建邀请") }
    var titleLabel: String { text("Title", "标题") }
    var dateLabel: String { text("Date", "日期") }
    var notesLabel: String { text("Notes", "备注") }
    var sendInviteButton: String { text("Send Invite", "发送邀请") }
    var createInviteSection: String { text("Details", "详情") }
    var emptyTitleError: String { text("Title is required.", "请输入标题。") }
    var invalidDateRangeError: String { text("End time must be after start time.", "结束时间必须晚于开始时间。") }
    var noSharedSchedulesTitle: String { text("No schedules today", "当前无日程") }
    var noSharedSchedulesDescription: String {
        text("There are no shared schedules for today.", "今天没有共享日程。")
    }
    var setupCalendarAccessTitle: String { text("Choose Calendars to Share", "选择要共享的日历") }
    var setupCalendarAccessMessage: String {
        text(
            "Allow calendar access, then choose which calendars OurDays can share.",
            "请先授权日历访问，然后选择 OurDays 可以共享哪些日历。"
        )
    }
    var setupCalendarAccessButton: String { text("Go to Calendar Settings", "前往日历设置") }
    var setupPairingTitle: String { text("Start Pairing", "开启配对") }
    var setupPairingMessage: String {
        text(
            "Calendar sharing is ready. Start pairing to invite your partner.",
            "日历共享设置已准备好。下一步发起配对，邀请对方加入。"
        )
    }
    var setupPairingButton: String { text("Go to Pairing", "前往配对") }
    var syncingSelectedCalendars: String { text("Syncing selected calendars...", "正在同步已选日历...") }
    var notSyncedYet: String { text("Not synced yet", "尚未同步") }
    var noEvents: String { text("No events", "暂无日程") }
    var allDay: String { text("All day", "全天") }
    var ownerLabel: String { text("Owner", "所有者") }
    var startsLabel: String { text("Starts", "开始") }
    var endsLabel: String { text("Ends", "结束") }
    var locationLabel: String { text("Location", "地点") }
    var inviteSection: String { text("Invite", "邀请") }
    var invitePartnerButton: String { text("Invite partner", "邀请对方") }
    var invitationSentMessage: String { text("Invitation sent.", "邀请已发送。") }
    var withdrawInvitationButton: String { text("Withdraw invitation", "撤销邀请") }
    var invitationWithdrawnMessage: String { text("Invitation withdrawn.", "邀请已撤销。") }
    var invitationExpiredTitle: String { text("Expired", "已过期") }
    var inviteAlreadyEndedError: String { text("Invitations can only be sent for events that haven't ended.", "只能为尚未结束的日程发出邀请。") }
    var inviteAnywayButton: String { text("Invite anyway", "仍然邀请") }
    var cancelButton: String { text("Cancel", "取消") }
    var invitationConflictTitle: String { text("Schedule conflict", "日程冲突") }
    var jointScheduleLabel: String { text("Together", "共同") }
    var commentsSection: String { text("Comments", "评论") }
    var deleteButton: String { text("Delete", "删除") }
    var addCommentPlaceholder: String { text("Add a comment", "添加评论") }
    var eventTitle: String { text("Event", "日程") }
    var doneButton: String { text("Done", "完成") }
    var noInvitations: String { text("No invitations", "暂无邀请") }
    var declineButton: String { text("Decline", "拒绝") }
    var saveButton: String { text("Save", "保存") }
    var skipButton: String { text("Skip", "跳过") }
    var continueButton: String { text("Continue", "继续") }
    var profileSection: String { text("Profile", "个人资料") }
    var myNicknameLabel: String { text("My Nickname", "我的昵称") }
    var partnerNicknameEditLabel: String { text("Partner Note", "对方备注名") }
    var myDisplayNamePlaceholder: String { text("My nickname", "我的昵称") }
    var partnerDisplayNamePlaceholder: String { text("Partner note", "对方备注名") }
    var currentDisplayNameRequiredMessage: String { text("Enter your nickname before pairing.", "配对前请先填写我的昵称。") }
    var initialProfilePromptTitle: String { text("Set Your Nickname", "设置我的昵称") }
    var initialProfilePromptMessage: String {
        text(
            "This name helps your partner recognize you in OurDays.",
            "这个昵称会用于让对方在 OurDays 中认出你。"
        )
    }
    var partnerNotePromptTitle: String { text("Set Partner Note", "设置对方备注名") }
    var partnerNotePromptMessage: String {
        text(
            "Add an optional local note for your partner. Your partner will not see it.",
            "你可以为对方设置一个本地备注名，对方不会看到。"
        )
    }
    var pairingSafetyNoticeTitle: String { text("Before You Reinstall", "卸载或重装前请先解除配对") }
    var pairingSafetyNoticeMessage: String {
        text(
            "OurDays' iCloud sharing data is separate from your local calendars. Unpair before uninstalling or reinstalling this app. Deleting OurDays iCloud data will not delete your original calendars or events in the system Calendar app.",
            "OurDays 的 iCloud 共享数据与本地日历是隔离的。卸载或重装本 App 前，请先解除配对。删除 OurDays 的 iCloud 数据不会删除系统日历中的原始日历或事件。"
        )
    }
    var existingICloudDataPromptTitle: String {
        text("Existing iCloud Data Found", "发现旧的 iCloud 数据")
    }
    var existingICloudDataPromptMessage: String {
        text(
            "This install looks new, but previous OurDays iCloud data still exists for this Apple ID. If you no longer want to keep sharing, delete it now. OurDays' iCloud data is separate from your local calendars, and deleting it will not delete your original calendars or events in the system Calendar app.",
            "这次安装看起来是全新的，但这个 Apple ID 之前的 OurDays iCloud 数据仍然存在。如果你不打算继续共享，建议现在删除。OurDays 的 iCloud 数据与本地日历是隔离的，删除它不会删除系统日历中的原始日历或事件。"
        )
    }
    var continueExistingICloudDataButton: String {
        text("Keep Existing iCloud Data", "继续使用现有 iCloud 数据")
    }
    var languageSection: String { text("Language", "语言") }
    var appLanguagePicker: String { text("App language", "应用语言") }
    var calendarAccessSection: String { text("Calendar Access", "日历访问") }
    var statusLabel: String { text("Status", "状态") }
    var openCalendarSettingsButton: String { text("Open Calendar Settings", "打开日历设置") }
    var calendarAccessGrantedButton: String { text("Calendar Access Granted", "已获得日历访问权限") }
    var requestFullCalendarAccessButton: String { text("Request Full Calendar Access", "请求完整日历访问权限") }
    var requestingCalendarAccess: String { text("Requesting calendar access...", "正在请求日历访问权限...") }
    var refreshCalendarsButton: String { text("Refresh Calendars", "刷新日历") }
    var calendarsToShareSection: String { text("Calendars to Share", "要共享的日历") }
    var createShareCalCalendarButton: String { text("Create Shared Calendar", "创建共享日历") }
    var noCalendarsLoaded: String { text("No calendars loaded", "没有已加载的日历") }
    var privacySection: String { text("Privacy", "隐私") }
    var defaultVisibilityPicker: String { text("Default visibility", "默认可见性") }
    var pairingSection: String { text("Pairing", "配对") }
    var pairingPartnerLabel: String { text("Pairing Partner", "配对对象") }
    var partnerNicknameLabel: String { text("Nickname", "昵称") }
    var sharingMyCalendarLabel: String { text("Sharing My Calendar", "我共享给对方") }
    var partnersCalendarLabel: String { text("Partner's Calendar", "对方共享给我") }
    var sharingScopeTitle: String { text("Sharing Scope", "共享范围") }
    var sharedAfterPairingDateValue: String { text("After pairing date", "配对日之后") }
    func sharedAfterDateValue(_ date: Date) -> String {
        text("After \(pairingDateText(for: date))", "\(pairingDateText(for: date))之后")
    }
    var prePairingHistoryLabel: String { text("Pre-pairing history", "配对前历史") }
    var requestRequiredValue: String { text("Request required", "需要申请") }
    func historyAuthorizedFromValue(_ date: Date) -> String {
        text("Authorized from \(pairingDateText(for: date))", "已授权自 \(pairingDateText(for: date))")
    }
    var pairingDescription: String {
        text(
            "After pairing, you can share calendars with each other from the pairing date. This version supports one pairing partner.",
            "配对后，你们可以从配对日开始互相共享日历。当前版本仅支持一位配对对象。"
        )
    }
    var pairingWaitingForYouToShareDescription: String {
        text(
            "You've accepted your partner's share. Share your calendar back to complete pairing.",
            "你已接收对方共享。请把你的日历共享给对方以完成配对。"
        )
    }
    var accessRequestSection: String { text("History Requests", "历史日程申请") }
    var requestHistoryAccessButton: String { text("Request Pre-Pairing History", "申请查看配对前历史") }
    var prePairingHistoryRequestTitle: String { text("Request Pre-Pairing History", "申请查看配对前历史") }
    var prePairingHistoryRequestDescription: String {
        text(
            "You can currently view schedules after the pairing date. To view earlier schedules, send a request to your partner.",
            "你当前只能查看配对日之后的日程。如果想查看更早的日程，需要向对方申请。"
        )
    }
    var accessRequestStartLabel: String { text("Start", "开始日期") }
    var accessRequestEndLabel: String { text("End", "结束日期") }
    var pendingAccessRequestsLabel: String { text("Pending Requests", "待处理申请") }
    var outgoingAccessRequestsLabel: String { text("My Requests", "我的申请") }
    var approveButton: String { text("Approve", "同意") }
    var sendRequestButton: String { text("Send Request", "发送申请") }
    var accessRequestSentMessage: String { text("Request sent.", "申请已发送。") }
    var accessRequestUpdatedMessage: String { text("Request updated.", "申请已更新。") }
    var invalidAccessRequestRangeMessage: String {
        text("End date must be after start date.", "结束日期必须晚于开始日期。")
    }
    var accessRequestAlreadyAuthorizedMessage: String {
        text("This range is already authorized.", "该范围已授权，无需重复申请。")
    }
    var accessRequestOverlapsAuthorizedMessage: String {
        text("This range overlaps authorized history. Please adjust the dates.", "申请范围与已授权历史重叠，请调整日期。")
    }
    var accessRequestOverlapsExistingRequestMessage: String {
        text("This range overlaps an existing request. Please adjust the dates.", "申请范围与已有申请重叠，请调整日期。")
    }
    var unpairButton: String { text("Unpair", "解除配对") }
    var unpairConfirmationTitle: String { text("Unpair?", "解除配对？") }
    var unpairConfirmationMessage: String {
        text(
            "After unpairing, you will no longer be able to view each other's calendars. To pair with someone else, unpair first.",
            "解除后，你们将不能继续互相查看日历。要和其他人配对，需要先解除当前配对。"
        )
    }
    var unpairSucceeded: String { text("Unpaired.", "已解除配对。") }
    var pairingSafetySection: String { text("Before Uninstalling", "卸载前提醒") }
    var pairingSafetyPersistentWarningTitle: String {
        text("Unpair before uninstalling or reinstalling this app.", "卸载或重装本 App 前，请先解除配对。")
    }
    var pairingSafetyPersistentWarningMessage: String {
        text(
            "OurDays' iCloud sharing data is separate from your local calendars. Removing OurDays iCloud data will not delete your original calendars or events in the system Calendar app.",
            "OurDays 的 iCloud 共享数据与本地日历是隔离的。删除 OurDays 的 iCloud 数据不会删除系统日历中的原始日历或事件。"
        )
    }
    var pairingConflictTitle: String { text("Pairing Conflict", "配对冲突") }
    var pairingConflictMismatchMessage: String {
        text(
            "The people who joined your calendar do not match the person whose calendar you accepted. Choose who to keep as your partner; the other connections will be removed.",
            "加入你日历的人与你接受的日历分享者不一致。请选择保留哪一位作为伴侣，其余连接将被移除。"
        )
    }
    var pairingConflictMultipleIncomingMessage: String {
        text(
            "You have accepted calendar shares from more than one person. Choose who to keep as your partner; the other shares will be removed.",
            "你接受了多个人的日历分享。请选择保留哪一位作为伴侣，其余分享将被移除。"
        )
    }
    var pairingConflictMultipleOutgoingMessage: String {
        text(
            "More than one person has joined your calendar share. Choose who to keep as your partner; the others will be removed.",
            "有多个人加入了你的日历分享。请选择保留哪一位作为伴侣，其余成员将被移除。"
        )
    }
    func keepPartnerButton(_ name: String) -> String {
        text("Keep \(name)", "保留 \(name)")
    }
    var pairingReplacementTitle: String { text("Replace Current Pairing?", "更换配对对象？") }
    func pairingReplacementMessage(currentPartner: String) -> String {
        text(
            "You are already paired with \(currentPartner). Accepting this new invitation will remove the current pairing and pair you with the new person instead.",
            "你已与 \(currentPartner) 配对。接受这个新邀请将解除当前配对，改为与新的对象配对。"
        )
    }
    var pairingReplacementConfirmButton: String { text("Replace Pairing", "更换配对") }
    var deleteICloudDataButton: String { text("Delete My iCloud Data", "删除我的 iCloud 数据") }
    var deletingICloudDataButton: String { text("Deleting My iCloud Data...", "正在删除我的 iCloud 数据...") }
    var deleteICloudDataConfirmationTitle: String { text("Delete My iCloud Data?", "删除我的 iCloud 数据？") }
    var deleteICloudDataConfirmationMessage: String {
        text(
            "This stops sharing, deletes your OurDays iCloud data, leaves your partner's share, and clears the local OurDays cache. It will not delete original events from the system Calendar app.",
            "这会停止共享、删除你上传到 iCloud 的 OurDays 数据、退出对方的共享，并清除本地 OurDays 缓存。它不会删除系统日历中的原始日程。"
        )
    }
    var deleteICloudDataSucceeded: String { text("iCloud data deleted.", "iCloud 数据已删除。") }
    var iCloudSharingUnavailableLocalBuild: String {
        text("Pairing is unavailable in this local build.", "当前本地构建不可用配对功能。")
    }
    var syncSection: String { text("Sync", "同步") }
    var lastSyncLabel: String { text("Last sync", "上次同步") }
    var never: String { text("Never", "从未") }
    var aboutSection: String { text("About", "关于") }
    var versionLabel: String { text("Version", "版本") }
    var icpFilingLabel: String { text("ICP Filing (China)", "APP 备案号") }
    var calendarAccessAlreadyEnabled: String { text("Calendar access is already enabled.", "日历访问权限已启用。") }
    var calendarAccessMustBeChanged: String {
        text("Calendar access must be changed in iPhone Settings.", "需要在 iPhone 设置中更改日历访问权限。")
    }
    var calendarAccessGrantedMessage: String {
        text("Calendar access granted. Select calendars below, then sync.", "已获得日历访问权限。请在下方选择日历，然后同步。")
    }
    var calendarAccessDeniedMessage: String {
        text("Calendar access was not granted. Open Settings to enable it.", "未获得日历访问权限。请打开设置启用。")
    }
    var calendarAccessRequestFailed: String { text("Calendar access request failed.", "日历访问权限请求失败。") }
    var shareCalCalendarReady: String { text("Shared calendar is ready.", "共享日历已准备好。") }
    var shareCalCalendarCreationFailed: String { text("Shared calendar creation failed.", "共享日历创建失败。") }
    var cloudKitSyncDisabledLocalBuild: String {
        text(
            "CloudKit sync is disabled in the Personal Team debug build.",
            "Personal Team 调试构建中已禁用 CloudKit 同步。"
        )
    }

    func languageDisplayName(for language: AppLanguage) -> String {
        switch language {
        case .english: "English"
        case .chinese: "中文"
        }
    }

    func modeLabel(for modeRawValue: String) -> String {
        switch modeRawValue {
        case "Day": dayMode
        case "Week": weekMode
        default: modeRawValue
        }
    }

    func lastSyncStatus(_ dateText: String) -> String {
        text("Last sync \(dateText)", "上次同步 \(dateText)")
    }

    func startPairingButton(isPreparing: Bool) -> String {
        isPreparing ? text("Preparing Pairing...", "正在准备配对...") : text("Start Pairing", "发起配对")
    }

    func checkICloudStatusButton(isChecking: Bool) -> String {
        isChecking ? text("Checking iCloud Status...", "正在检查 iCloud 状态...") : text("Check iCloud Status", "检查 iCloud 状态")
    }

    func memberColumnTitle(baseTitle: String, nickname: String) -> String {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return baseTitle }
        switch language {
        case .english:
            return "\(baseTitle) (\(trimmedNickname))"
        case .chinese:
            return "\(baseTitle)（\(trimmedNickname)）"
        }
    }

    func cloudKitShareFailed(_ message: String) -> String {
        text("CloudKit share failed: \(message)", "CloudKit 共享失败：\(message)")
    }

    func cloudKitAccountStatus(_ status: String) -> String {
        text("CloudKit account status is \(status).", "CloudKit 账户状态为 \(status)。")
    }

    func defaultVisibilityLabel(for visibility: EventVisibility) -> String {
        switch visibility {
        case .busyOnly: text("Busy only", "仅显示忙碌")
        case .titleAndLocation: text("Title + location", "标题和地点")
        case .fullDetails: text("Full details", "完整详情")
        case .hidden: text("Hidden", "隐藏")
        }
    }

    func pairingStatusTitle(for status: PairingStatus) -> String {
        switch status {
        case .notPaired: text("Not Paired", "未配对")
        case .waitingForPartner: text("Waiting for Partner", "等待对方接受")
        case .waitingForPartnerToShare: text("Waiting for Partner to Share", "等待对方共享")
        case .waitingForYouToShare: text("Waiting for You to Share", "等待你共享")
        case .paired: text("Paired", "已配对")
        }
    }

    func pairingDateLine(_ dateText: String) -> String {
        text("Pairing date: \(dateText)", "配对日：\(dateText)")
    }

    func displayNameWithNote(displayName: String, note: String) -> String {
        switch language {
        case .english:
            "\(displayName) (\(note))"
        case .chinese:
            "\(displayName)（\(note)）"
        }
    }

    func incomingHistoryRequestText(requester: String, rangeText: String) -> String {
        text(
            "\(requester) wants to view \(rangeText)",
            "\(requester) 想查看 \(rangeText)"
        )
    }

    func pairingDateText(for date: Date) -> String {
        let formatter: DateFormatter
        switch language {
        case .english:
            formatter = DateFormatterCache.formatter(
                template: "MMM d, yyyy",
                locale: Locale(identifier: "en_US"),
                calendar: .current,
                timeZone: .current
            )
        case .chinese:
            formatter = DateFormatterCache.formatter(
                dateFormat: "yyyy年M月d日",
                locale: Locale(identifier: "zh_Hans"),
                calendar: .current,
                timeZone: .current
            )
        }
        return formatter.string(from: date)
    }

    /// Abbreviated date (e.g. "6月9日" / "Jun 9, 2026") in the app's language.
    func abbreviatedDateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(language.locale))
    }

    /// Short time (e.g. "19:00") in the app's language.
    func shortTimeText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(language.locale))
    }

    /// Abbreviated date with short time in the app's language.
    func abbreviatedDateTimeText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(language.locale))
    }

    func invitationStatusTitle(for status: InvitationStatus) -> String {
        switch status {
        case .pending: text("Pending", "待处理")
        case .accepted: text("Accepted", "已接受")
        case .declined: text("Declined", "已拒绝")
        case .canceled: text("Canceled", "已取消")
        }
    }

    func invitationStatusTitle(for status: InvitationDisplayStatus) -> String {
        switch status {
        case .pending: invitationStatusTitle(for: InvitationStatus.pending)
        case .accepted: invitationStatusTitle(for: InvitationStatus.accepted)
        case .declined: invitationStatusTitle(for: InvitationStatus.declined)
        case .canceled: invitationStatusTitle(for: InvitationStatus.canceled)
        case .expired: invitationExpiredTitle
        }
    }

    func accessRequestStatusTitle(for status: CalendarAccessRequestStatus) -> String {
        switch status {
        case .pending: text("Pending", "待处理")
        case .approved: text("Approved", "已同意")
        case .declined: text("Declined", "已拒绝")
        }
    }

    func invitationConflictMessage(eventTitle: String, timeText: String, additionalConflictCount: Int) -> String {
        let suffix: String
        if additionalConflictCount > 0 {
            suffix = text(" and \(additionalConflictCount) more conflict(s)", "，另有 \(additionalConflictCount) 个冲突")
        } else {
            suffix = ""
        }
        return text(
            "Your partner already has \(eventTitle) at \(timeText)\(suffix).",
            "对方在 \(timeText) 已有 \(eventTitle)\(suffix)。"
        )
    }

    // MARK: Redesign ("纸上双线") strings

    var usTab: String { text("Us", "我们") }
    var usTitle: String { text("Us", "我们") }
    var usSubtitle: String { text("Pairing, sharing & settings", "配对、共享与设置") }
    var moreSection: String { text("More", "更多") }
    var sharedPeopleRowTitle: String { text("Shared People & Invite Link", "共享人与邀请链接") }
    var todaySectionTitle: String { text("Today", "今天") }
    var yesterdaySectionTitle: String { text("Yesterday", "昨天") }
    var activitySubtitle: String { text("Conversations around your schedules", "你们围绕日程的对话") }
    var myScheduleLabel: String { text("Mine", "我的日程") }
    var sentByMeLabel: String { text("Sent by me", "我发出") }
    var acceptAndAddButton: String { text("Accept & Add", "接受，加入日历") }
    var handledInvitationsSection: String { text("Handled", "已处理") }
    var myAvatarLabel: String { text("My Avatar", "我的头像") }
    var avatarPhotoTab: String { text("Photo", "照片") }
    var avatarTextTab: String { text("Text", "文字") }
    var avatarTextLabel: String { text("Avatar text · up to 3 letters or 2 characters", "头像文字 · 最多 3 个字母或 2 个汉字") }
    var avatarBackgroundLabel: String { text("Background", "底色") }
    var choosePhotoButton: String { text("Choose Photo", "从相册选择") }
    var changePhotoButton: String { text("Choose Another Photo", "换一张照片") }
    var resetAvatarButton: String { text("Use Default", "恢复默认") }
    var partnerAvatarFootnote: String { text("Only shown on this iPhone", "只在你的手机上显示") }

    func pairingDayHeadline(_ dayCount: Int) -> String {
        text("Day \(dayCount) paired", "配对第 \(dayCount) 天")
    }

    func pairedSinceLine(partnerName: String, dateText: String) -> String {
        text("You & \(partnerName) · since \(dateText)", "你和\(partnerName) · 自 \(dateText) 起")
    }

    func calendarHeaderSubtitle(weekdayText: String, pairingDayCount: Int?) -> String {
        guard let pairingDayCount else { return weekdayText }
        return "\(weekdayText) · \(pairingDayHeadline(pairingDayCount))"
    }

    func nightCollapsedLabel(untilHour: Int) -> String {
        let range = String(format: "00:00 – %02d:00", untilHour)
        return text("\(range) · Both free", "\(range) · 双方都空闲")
    }

    func laneEventCountText(_ count: Int) -> String {
        text("\(count)", "\(count) 项")
    }

    func commentCountText(_ count: Int) -> String {
        text(count == 1 ? "1 comment" : "\(count) comments", "\(count) 条评论")
    }

    func partnerScheduleLabel(_ partnerName: String) -> String {
        text("\(partnerName)'s", "\(partnerName)的日程")
    }

    func invitedYouLine(_ partnerName: String) -> String {
        text("\(partnerName) invited you", "\(partnerName)邀请你")
    }

    func waitingForReplyLine(_ partnerName: String) -> String {
        text("Waiting for \(partnerName)", "等待\(partnerName)回复")
    }

    func pendingInvitationsSubtitle(_ count: Int) -> String {
        text(count == 1 ? "1 to answer" : "\(count) to answer", "\(count) 张待回复")
    }

    func partnerAvatarLabel(_ partnerName: String) -> String {
        text("Avatar for \(partnerName)", "给\(partnerName)换个头像")
    }

    func avatarSyncFootnote(_ partnerName: String) -> String {
        text(
            "The ring is your identity color and stays no matter which avatar you pick, so \(partnerName) can always tell your events and comments apart. Your avatar syncs to \(partnerName).",
            "外圈是你的身份色，头像怎么换它都在，让\(partnerName)在日历和评论里一眼认出你。头像会同步给\(partnerName)。"
        )
    }

    func avatarBackgroundName(_ background: AvatarBackground) -> String {
        switch background {
        case .sand: text("Sand", "沙色")
        case .teal: text("Teal", "青")
        case .coral: text("Coral", "珊瑚")
        case .sage: text("Sage", "鼠尾草")
        case .lavender: text("Lavender", "薰衣草")
        case .ink: text("Ink", "墨")
        }
    }

    private func text(_ english: String, _ chinese: String) -> String {
        switch language {
        case .english: english
        case .chinese: chinese
        }
    }
}
