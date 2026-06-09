import CoreGraphics
import Foundation
import SwiftData

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

struct ShareCalStrings {
    let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
    }

    var calendarTab: String { text("Calendar", "日历") }
    var invitesTab: String { text("Invites", "邀请") }
    var settingsTab: String { text("Settings", "设置") }
    var settingsTitle: String { text("Settings", "设置") }
    var modePicker: String { text("Mode", "模式") }
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
            "Allow calendar access, then choose which calendars ShareCal can share.",
            "请先授权日历访问，然后选择 ShareCal 可以共享哪些日历。"
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
    var calendarLabel: String { text("Calendar", "日历") }
    var startsLabel: String { text("Starts", "开始") }
    var endsLabel: String { text("Ends", "结束") }
    var locationLabel: String { text("Location", "地点") }
    var inviteSection: String { text("Invite", "邀请") }
    var invitePartnerButton: String { text("Invite partner", "邀请对方") }
    var sendingInvitationButton: String { text("Sending invitation...", "正在发送邀请...") }
    var invitationSentMessage: String { text("Invitation sent.", "邀请已发送。") }
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
    var acceptButton: String { text("Accept", "接受") }
    var declineButton: String { text("Decline", "拒绝") }
    var saveButton: String { text("Save", "保存") }
    var skipButton: String { text("Skip", "跳过") }
    var continueButton: String { text("Continue", "继续") }
    var profileSection: String { text("Profile", "个人资料") }
    var myNicknameLabel: String { text("My Nickname", "我的昵称") }
    var myICloudEmailLabel: String { text("My iCloud Email", "我的 iCloud 邮箱") }
    var myICloudEmailPlaceholder: String { text("name@icloud.com", "name@icloud.com") }
    var partnerNicknameEditLabel: String { text("Partner Note", "对方备注名") }
    var myDisplayNamePlaceholder: String { text("My nickname", "我的昵称") }
    var partnerDisplayNamePlaceholder: String { text("Partner note", "对方备注名") }
    var currentDisplayNameRequiredMessage: String { text("Enter your nickname before pairing.", "配对前请先填写我的昵称。") }
    var initialProfilePromptTitle: String { text("Set Your Nickname", "设置我的昵称") }
    var initialProfilePromptMessage: String {
        text(
            "This name helps your partner recognize you in ShareCal.",
            "这个昵称会用于让对方在 ShareCal 中认出你。"
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
            "ShareCal's iCloud sharing data is separate from your local calendars. Unpair before uninstalling or reinstalling this app. Deleting ShareCal iCloud data will not delete your original calendars or events in the system Calendar app.",
            "ShareCal 的 iCloud 共享数据与本地日历是隔离的。卸载或重装本 App 前，请先解除配对。删除 ShareCal 的 iCloud 数据不会删除系统日历中的原始日历或事件。"
        )
    }
    var existingICloudDataPromptTitle: String {
        text("Existing iCloud Data Found", "发现旧的 iCloud 数据")
    }
    var existingICloudDataPromptMessage: String {
        text(
            "This install looks new, but previous ShareCal iCloud data still exists for this Apple ID. If you no longer want to keep sharing, delete it now. ShareCal's iCloud data is separate from your local calendars, and deleting it will not delete your original calendars or events in the system Calendar app.",
            "这次安装看起来是全新的，但这个 Apple ID 之前的 ShareCal iCloud 数据仍然存在。如果你不打算继续共享，建议现在删除。ShareCal 的 iCloud 数据与本地日历是隔离的，删除它不会删除系统日历中的原始日历或事件。"
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
    var createShareCalCalendarButton: String { text("Create ShareCal Calendar", "创建 ShareCal 日历") }
    var noCalendarsLoaded: String { text("No calendars loaded", "没有已加载的日历") }
    var privacySection: String { text("Privacy", "隐私") }
    var defaultVisibilityPicker: String { text("Default visibility", "默认可见性") }
    var pairingSection: String { text("Pairing", "配对") }
    var pairingPartnerLabel: String { text("Pairing Partner", "配对对象") }
    var partnerNicknameLabel: String { text("Nickname", "昵称") }
    var partnerICloudIdentityLabel: String { text("iCloud Identity", "iCloud 身份") }
    var sharingMyCalendarLabel: String { text("Sharing My Calendar", "我共享给对方") }
    var partnersCalendarLabel: String { text("Partner's Calendar", "对方共享给我") }
    var pairingDayLabel: String { text("Pairing Date", "配对日") }
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
    var noICloudSharingIdentity: String { text("Not connected", "未连接") }
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
    var oldSharedCalendarsSection: String { text("Old Shared Calendars", "旧共享") }
    var sharedPeopleTitle: String { text("Shared People", "共享人") }
    var sharedPeopleDescription: String {
        text(
            "Manage people and invitation link with iCloud sharing.",
            "使用 iCloud 共享界面管理成员和邀请链接。"
        )
    }
    var pairingSafetySection: String { text("Before Uninstalling", "卸载前提醒") }
    var pairingSafetyPersistentWarningTitle: String {
        text("Unpair before uninstalling or reinstalling this app.", "卸载或重装本 App 前，请先解除配对。")
    }
    var pairingSafetyPersistentWarningMessage: String {
        text(
            "ShareCal's iCloud sharing data is separate from your local calendars. Removing ShareCal iCloud data will not delete your original calendars or events in the system Calendar app.",
            "ShareCal 的 iCloud 共享数据与本地日历是隔离的。删除 ShareCal 的 iCloud 数据不会删除系统日历中的原始日历或事件。"
        )
    }
    var oldSharedCalendarsCleanupPromptTitle: String {
        text("Old Shared Calendars Found", "发现旧共享")
    }
    var oldSharedCalendarsCleanupPromptMessage: String {
        text(
            "Your current pairing is active, but this device still has old accepted ShareCal shares. You can remove them now or later from Settings.",
            "当前配对已生效，但本设备仍有旧的 ShareCal accepted share。你可以现在移除，也可以稍后在设置中处理。"
        )
    }
    var cleanupOldSharedCalendarsConfirmationTitle: String {
        text("Remove Old Shared Calendars?", "移除旧共享？")
    }
    var cleanupOldSharedCalendarsConfirmationMessage: String {
        text(
            "This removes old accepted ShareCal shares from this device. It will not delete your original Calendar events or your current pairing.",
            "这会从本设备移除旧的 ShareCal accepted share。它不会删除系统日历中的原始日程，也不会删除当前配对。"
        )
    }
    var cleanupOldSharedCalendarsSucceeded: String { text("Old shared calendars removed.", "旧共享已移除。") }
    var deleteICloudDataButton: String { text("Delete My iCloud Data", "删除我的 iCloud 数据") }
    var deletingICloudDataButton: String { text("Deleting My iCloud Data...", "正在删除我的 iCloud 数据...") }
    var deleteICloudDataConfirmationTitle: String { text("Delete My iCloud Data?", "删除我的 iCloud 数据？") }
    var deleteICloudDataConfirmationMessage: String {
        text(
            "This stops sharing, deletes your ShareCal iCloud data, and clears the local ShareCal cache. It will not delete original events from the system Calendar app.",
            "这会停止共享、删除你上传到 iCloud 的 ShareCal 数据，并清除本地 ShareCal 缓存。它不会删除系统日历中的原始日程。"
        )
    }
    var deleteICloudDataSucceeded: String { text("iCloud data deleted.", "iCloud 数据已删除。") }
    var createsICloudShareDescription: String {
        text("Creates a pairing invitation for your partner.", "为对方创建配对邀请。")
    }
    var iCloudSharingUnavailableLocalBuild: String {
        text("Pairing is unavailable in this local build.", "当前本地构建不可用配对功能。")
    }
    var syncSection: String { text("Sync", "同步") }
    var lastSyncLabel: String { text("Last sync", "上次同步") }
    var never: String { text("Never", "从未") }
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
    var shareCalCalendarReady: String { text("ShareCal calendar is ready.", "ShareCal 日历已准备好。") }
    var shareCalCalendarCreationFailed: String { text("ShareCal calendar creation failed.", "ShareCal 日历创建失败。") }
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

    func pairingCalendarStatusTitle(for status: PairingCalendarStatus) -> String {
        switch status {
        case .off: text("Off", "未开启")
        case .waitingForPartner: text("Waiting for Partner", "等待对方接受")
        case .waitingForPartnerToShare: text("Waiting for Partner to Share", "等待对方共享")
        case .on: text("On", "已开启")
        case .unavailable: text("Unavailable", "不可用")
        }
    }

    func pairingDayCountText(_ dayCount: Int) -> String {
        "D+\(dayCount)"
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

    func calendarPairingStatusLine(dayCount: Int, dateText: String) -> String {
        text(
            "Paired \(pairingDayCountText(dayCount)) · Shared since \(dateText)",
            "配对 \(pairingDayCountText(dayCount)) · 共享自 \(dateText)"
        )
    }

    func incomingHistoryRequestText(requester: String, rangeText: String) -> String {
        text(
            "\(requester) wants to view \(rangeText)",
            "\(requester) 想查看 \(rangeText)"
        )
    }

    func pairingDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.timeZone = .current
        switch language {
        case .english:
            formatter.locale = Locale(identifier: "en_US")
            formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        case .chinese:
            formatter.locale = Locale(identifier: "zh_Hans")
            formatter.dateFormat = "yyyy年M月d日"
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

    func accessRequestStatusTitle(for status: CalendarAccessRequestStatus) -> String {
        switch status {
        case .pending: text("Pending", "待处理")
        case .approved: text("Approved", "已同意")
        case .declined: text("Declined", "已拒绝")
        }
    }

    func oldSharedCalendarsDescription(count: Int) -> String {
        text(
            "\(count) old accepted ShareCal share(s) are ignored by the current pairing.",
            "当前配对已忽略 \(count) 个旧 ShareCal accepted share。"
        )
    }

    func cleanupOldSharedCalendarsButton(isDeleting: Bool) -> String {
        isDeleting ? text("Removing Old Shares...", "正在移除旧共享...") : text("Remove Old Shares", "移除旧共享")
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

    private func text(_ english: String, _ chinese: String) -> String {
        switch language {
        case .english: english
        case .chinese: chinese
        }
    }
}

enum ShareCalAcceptedShareSignal {
    static let notificationName = Notification.Name("ShareCalAcceptedCloudKitShare")
    private static let pendingSyncKey = "ShareCalPendingAcceptedCloudKitShareSync"
    private static let pendingPartnerICloudEmailAddressKey = "ShareCalPendingAcceptedPartnerICloudEmailAddress"

    static func markAccepted(
        partnerICloudEmailAddress: String? = nil,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(true, forKey: pendingSyncKey)
        if let partnerICloudEmailAddress = ICloudSharingIdentityDisplayPlan.normalizedEmailAddress(partnerICloudEmailAddress) {
            defaults.set(partnerICloudEmailAddress, forKey: pendingPartnerICloudEmailAddressKey)
        }
        notificationCenter.post(name: notificationName, object: nil)
    }

    static func hasPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingSyncKey)
    }

    static func consumePending(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: pendingSyncKey) else { return false }
        defaults.set(false, forKey: pendingSyncKey)
        return true
    }

    static func consumePendingPartnerICloudEmailAddress(defaults: UserDefaults = .standard) -> String? {
        let emailAddress = ICloudSharingIdentityDisplayPlan.normalizedEmailAddress(
            defaults.string(forKey: pendingPartnerICloudEmailAddressKey)
        )
        defaults.removeObject(forKey: pendingPartnerICloudEmailAddressKey)
        return emailAddress
    }
}

struct DayTimelineHourMark: Equatable {
    let hour: Int
    let y: CGFloat
}

struct DayTimelineEventFrame: Equatable {
    let y: CGFloat
    let height: CGFloat
}

enum CalendarNavigationDirection {
    case previous
    case next
}

struct CalendarDateSelectionResult: Equatable {
    let selectedDate: Date
    let mode: CalendarMode
}

enum CalendarDateNavigationPlan {
    static func date(
        afterMoving selectedDate: Date,
        mode: CalendarMode,
        direction: CalendarNavigationDirection,
        calendar: Calendar = .current
    ) -> Date {
        let value: Int
        let component: Calendar.Component
        switch mode {
        case .day:
            value = direction == .next ? 1 : -1
            component = .day
        case .week:
            value = direction == .next ? 7 : -7
            component = .day
        }
        return calendar.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
    }

    static func dateStrip(
        around selectedDate: Date,
        range: ClosedRange<Int> = -3...3,
        calendar: Calendar = .current
    ) -> [Date] {
        let dayStart = calendar.startOfDay(for: selectedDate)
        return range.compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: dayStart)
        }
    }

    static func selectionResult(for date: Date) -> CalendarDateSelectionResult {
        CalendarDateSelectionResult(selectedDate: date, mode: .day)
    }

    static func title(for selectedDate: Date, mode: CalendarMode, calendar: Calendar = .current) -> String {
        switch mode {
        case .day:
            return selectedDate.formatted(date: .abbreviated, time: .omitted)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: selectedDate, duration: 7 * 24 * 60 * 60)
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    static func compactTitle(
        for selectedDate: Date,
        mode: CalendarMode,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        switch mode {
        case .day:
            return monthDayText(for: selectedDate, calendar: calendar, locale: locale)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
                ?? DateInterval(start: selectedDate, duration: 7 * 24 * 60 * 60)
            let weekStart = calendar.startOfDay(for: interval.start)
            let weekEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            if calendar.component(.year, from: weekStart) == calendar.component(.year, from: weekEnd),
               calendar.component(.month, from: weekStart) == calendar.component(.month, from: weekEnd) {
                return "\(monthText(for: weekStart, calendar: calendar, locale: locale)) \(dayText(for: weekStart, calendar: calendar, locale: locale))-\(dayText(for: weekEnd, calendar: calendar, locale: locale))"
            }
            return "\(monthDayText(for: weekStart, calendar: calendar, locale: locale))-\(monthDayText(for: weekEnd, calendar: calendar, locale: locale))"
        }
    }

    private static func monthDayText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    private static func monthText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private static func dayText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        String(calendar.component(.day, from: date))
    }
}

enum HierarchicalDatePickerLevel: Equatable {
    case month
    case months
    case years
}

struct HierarchicalMonthDay: Identifiable, Equatable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

struct HierarchicalDatePickerNavigation: Equatable {
    let level: HierarchicalDatePickerLevel
    let visibleMonth: Date
    let selectedDate: Date?
}

enum HierarchicalDatePickerPlan {
    static func normalizedMonth(containing date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [HierarchicalMonthDay] {
        let monthStart = normalizedMonth(containing: date, calendar: calendar)
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart),
              let weekInterval = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start) else {
            return []
        }

        let displayedMonth = calendar.component(.month, from: monthStart)
        return (0..<42).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) else {
                return nil
            }
            return HierarchicalMonthDay(
                date: calendar.startOfDay(for: day),
                isInDisplayedMonth: calendar.component(.month, from: day) == displayedMonth
            )
        }
    }

    static func months(inYearContaining date: Date, calendar: Calendar = .current) -> [Date] {
        let year = calendar.component(.year, from: date)
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    static func years(centeredOn date: Date, calendar: Calendar = .current) -> [Date] {
        let currentYear = calendar.component(.year, from: date)
        let firstYear = currentYear - 5
        return (0..<12).compactMap { offset in
            calendar.date(from: DateComponents(year: firstYear + offset, month: 1, day: 1))
        }
    }

    static func selectYear(_ date: Date, calendar: Calendar = .current) -> HierarchicalDatePickerNavigation {
        let year = calendar.component(.year, from: date)
        let visibleMonth = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? date
        return HierarchicalDatePickerNavigation(level: .months, visibleMonth: visibleMonth, selectedDate: nil)
    }

    static func selectMonth(_ date: Date, calendar: Calendar = .current) -> HierarchicalDatePickerNavigation {
        HierarchicalDatePickerNavigation(
            level: .month,
            visibleMonth: normalizedMonth(containing: date, calendar: calendar),
            selectedDate: nil
        )
    }

    static func selectDay(_ date: Date, calendar: Calendar = .current) -> HierarchicalDatePickerNavigation {
        HierarchicalDatePickerNavigation(
            level: .month,
            visibleMonth: normalizedMonth(containing: date, calendar: calendar),
            selectedDate: calendar.startOfDay(for: date)
        )
    }
}

struct DayTimelineJointPlacement: Equatable {
    let columnIndex: Int
    let columnCount: Int
}

enum DayTimelineJointLayoutPlan {
    static func placements(for events: [JointScheduleEvent]) -> [String: DayTimelineJointPlacement] {
        var placements: [String: DayTimelineJointPlacement] = [:]
        let sortedEvents = events.sorted {
            if $0.startDate == $1.startDate {
                return $0.id < $1.id
            }
            return $0.startDate < $1.startDate
        }

        for event in sortedEvents {
            let overlapping = sortedEvents.filter { candidate in
                overlaps(event, candidate)
            }
            let orderedOverlappingIDs = overlapping.map(\.id)
            let columnIndex = orderedOverlappingIDs.firstIndex(of: event.id) ?? 0
            placements[event.id] = DayTimelineJointPlacement(
                columnIndex: columnIndex,
                columnCount: max(1, overlapping.count)
            )
        }

        return placements
    }

    private static func overlaps(_ lhs: JointScheduleEvent, _ rhs: JointScheduleEvent) -> Bool {
        lhs.startDate < rhs.endDate && rhs.startDate < lhs.endDate
    }
}

enum DayTimelineScrollTargetPlan {
    static let defaultStartHour = 8

    static func defaultTargetY(hourHeight: CGFloat, startHour: Int = defaultStartHour) -> CGFloat {
        CGFloat(startHour) * hourHeight
    }

    static func targetY(
        for event: JointScheduleEvent,
        dayStart: Date,
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> CGFloat {
        guard !event.isAllDay else { return 0 }
        return DayTimelineLayoutPlan.eventFrame(
            startDate: event.startDate,
            endDate: event.endDate,
            dayStart: dayStart,
            hourHeight: hourHeight,
            calendar: calendar
        ).y
    }
}

enum DayTimelineLayoutPlan {
    static let hoursPerDay = 24

    static func dayHeight(hourHeight: CGFloat) -> CGFloat {
        CGFloat(hoursPerDay) * hourHeight
    }

    static func hourMarks(hourHeight: CGFloat) -> [DayTimelineHourMark] {
        (0..<hoursPerDay).map { hour in
            DayTimelineHourMark(hour: hour, y: CGFloat(hour) * hourHeight)
        }
    }

    static func eventFrame(
        startDate: Date,
        endDate: Date,
        dayStart: Date,
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> DayTimelineEventFrame {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        let visibleStart = max(startDate, dayStart)
        let visibleEnd = min(max(endDate, visibleStart), dayEnd)
        let minutesFromStart = visibleStart.timeIntervalSince(dayStart) / 60
        let visibleMinutes = max(visibleEnd.timeIntervalSince(visibleStart) / 60, 15)
        let pointsPerMinute = hourHeight / 60

        return DayTimelineEventFrame(
            y: CGFloat(minutesFromStart) * pointsPerMinute,
            height: CGFloat(visibleMinutes) * pointsPerMinute
        )
    }
}

enum EventVisibility: String, Codable, CaseIterable, Identifiable {
    case busyOnly
    case titleAndLocation
    case fullDetails
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .busyOnly: "Busy only"
        case .titleAndLocation: "Title + location"
        case .fullDetails: "Full details"
        case .hidden: "Hidden"
        }
    }
}

enum InvitationStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case declined
    case canceled

    var id: String { rawValue }
}

enum CalendarAccessRequestStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case approved
    case declined

    var id: String { rawValue }
}

enum CalendarAccessRequestSource: String, Codable, CaseIterable, Identifiable {
    case localOutgoing
    case privateOwnerZone
    case acceptedSharedZone

    var id: String { rawValue }
}

struct PairingHistoryRequestRange: Equatable {
    let start: Date
    let end: Date
}

enum PairingDatePlan {
    static func normalizedPairingDate(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func dayCount(since pairingDate: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: pairingDate)
        let end = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    static func defaultHistoryRequestRange(
        pairingDate: Date,
        calendar: Calendar = .current
    ) -> PairingHistoryRequestRange {
        let normalizedPairingDate = normalizedPairingDate(pairingDate, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: -1, to: normalizedPairingDate) ?? normalizedPairingDate
        let start = calendar.date(byAdding: .day, value: -30, to: normalizedPairingDate) ?? end
        return PairingHistoryRequestRange(start: start, end: end)
    }

    static func exclusiveEndDate(forDisplayedEndDate displayedEndDate: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: displayedEndDate)
        return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
    }

    static func displayedEndDate(forExclusiveEndDate exclusiveEndDate: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: exclusiveEndDate)
        return calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
    }
}

enum PrePairingHistoryAccessPlan {
    enum Direction {
        case partnerSharedToMe
        case meSharedToPartner
    }

    enum Validation: Equatable {
        case valid
        case invalidRange
        case alreadyAuthorized
        case overlapsAuthorized
        case overlapsExistingRequest
    }

    static func contiguousAuthorizedStartDate(
        pairingDate: Date,
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        direction: Direction,
        calendar: Calendar = .current
    ) -> Date {
        let normalizedPairingDate = PairingDatePlan.normalizedPairingDate(pairingDate, calendar: calendar)
        let intervals = approvedIntervals(
            accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            direction: direction,
            calendar: calendar
        )

        var authorizedStartDate = normalizedPairingDate
        var didExpand = true
        while didExpand {
            didExpand = false
            for interval in intervals where interval.start < authorizedStartDate && interval.end >= authorizedStartDate {
                authorizedStartDate = interval.start
                didExpand = true
            }
        }
        return authorizedStartDate
    }

    static func defaultNextRequestRange(
        pairingDate: Date,
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        calendar: Calendar = .current
    ) -> PairingHistoryRequestRange {
        let authorizedStartDate = contiguousAuthorizedStartDate(
            pairingDate: pairingDate,
            accessRequests: accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            direction: .partnerSharedToMe,
            calendar: calendar
        )
        let displayedEndDate = PairingDatePlan.displayedEndDate(
            forExclusiveEndDate: authorizedStartDate,
            calendar: calendar
        )
        let startDate = calendar.date(byAdding: .day, value: -30, to: authorizedStartDate) ?? displayedEndDate
        return PairingHistoryRequestRange(start: startDate, end: displayedEndDate)
    }

    static func validation(
        requestedStartDate: Date,
        requestedEndDate: Date,
        pairingDate: Date,
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        calendar: Calendar = .current
    ) -> Validation {
        let normalizedStartDate = calendar.startOfDay(for: requestedStartDate)
        let normalizedEndDate = calendar.startOfDay(for: requestedEndDate)
        guard normalizedEndDate > normalizedStartDate else { return .invalidRange }

        let approvedRanges = mergedIntervals(approvedIntervals(
            accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            direction: .partnerSharedToMe,
            calendar: calendar
        ))
        if approvedRanges.contains(where: { interval in
            interval.start <= normalizedStartDate && normalizedEndDate <= interval.end
        }) {
            return .alreadyAuthorized
        }
        if approvedRanges.contains(where: { overlaps($0, start: normalizedStartDate, end: normalizedEndDate) }) {
            return .overlapsAuthorized
        }

        let existingPendingRanges = pendingOutgoingIntervals(
            accessRequests,
            currentMemberID: currentMemberID,
            ownerMemberID: ownerMemberID,
            calendar: calendar
        )
        if existingPendingRanges.contains(where: { overlaps($0, start: normalizedStartDate, end: normalizedEndDate) }) {
            return .overlapsExistingRequest
        }

        return .valid
    }

    private static func approvedIntervals(
        _ accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        direction: Direction,
        calendar: Calendar
    ) -> [DateInterval] {
        accessRequests.compactMap { request in
            guard request.status == .approved,
                  matches(request, currentMemberID: currentMemberID, ownerMemberID: ownerMemberID, direction: direction) else {
                return nil
            }
            return interval(for: request, calendar: calendar)
        }
    }

    private static func pendingOutgoingIntervals(
        _ accessRequests: [CalendarAccessRequest],
        currentMemberID: String,
        ownerMemberID: String?,
        calendar: Calendar
    ) -> [DateInterval] {
        accessRequests.compactMap { request in
            guard request.status == .pending,
                  request.source != .privateOwnerZone,
                  normalizedID(request.requesterMemberID) == normalizedID(currentMemberID),
                  matchesOwner(request, ownerMemberID: ownerMemberID) else {
                return nil
            }
            return interval(for: request, calendar: calendar)
        }
    }

    private static func matches(
        _ request: CalendarAccessRequest,
        currentMemberID: String,
        ownerMemberID: String?,
        direction: Direction
    ) -> Bool {
        switch direction {
        case .partnerSharedToMe:
            return request.source != .privateOwnerZone
                && normalizedID(request.requesterMemberID) == normalizedID(currentMemberID)
                && matchesOwner(request, ownerMemberID: ownerMemberID)
        case .meSharedToPartner:
            return request.source == .privateOwnerZone
        }
    }

    private static func interval(for request: CalendarAccessRequest, calendar: Calendar) -> DateInterval? {
        let startDate = calendar.startOfDay(for: request.requestedStartDate)
        let endDate = calendar.startOfDay(for: request.requestedEndDate)
        guard endDate > startDate else { return nil }
        return DateInterval(start: startDate, end: endDate)
    }

    private static func matchesOwner(_ request: CalendarAccessRequest, ownerMemberID: String?) -> Bool {
        guard let ownerMemberID = normalizedID(ownerMemberID), !ownerMemberID.isEmpty else { return true }
        return normalizedID(request.ownerMemberID) == ownerMemberID
    }

    private static func normalizedID(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        intervals.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
        .reduce(into: []) { partialResult, interval in
            guard let last = partialResult.last else {
                partialResult.append(interval)
                return
            }
            if interval.start <= last.end {
                partialResult[partialResult.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                partialResult.append(interval)
            }
        }
    }

    private static func overlaps(_ interval: DateInterval, start: Date, end: Date) -> Bool {
        interval.start < end && start < interval.end
    }
}

enum CalendarSharingWindowPlan {
    static let defaultEndDate = Date.distantFuture

    static func defaultWindows(now: Date = .now) -> [DateInterval] {
        [
            DateInterval(
                start: now,
                end: defaultEndDate
            )
        ]
    }

    static func effectiveWindows(
        now: Date = .now,
        accessRequests: [CalendarAccessRequest]
    ) -> [DateInterval] {
        let approvedRequestWindows = accessRequests.compactMap { request -> DateInterval? in
            guard request.source == .privateOwnerZone,
                  request.status == .approved,
                  request.requestedEndDate > request.requestedStartDate else {
                return nil
            }
            return DateInterval(start: request.requestedStartDate, end: request.requestedEndDate)
        }
        return defaultWindows(now: now) + approvedRequestWindows
    }

    static func contains(_ date: Date, in windows: [DateInterval]) -> Bool {
        windows.contains { window in
            date >= window.start && date < window.end
        }
    }

    static func enclosingInterval(for windows: [DateInterval]) -> DateInterval {
        precondition(!windows.isEmpty, "Calendar sharing windows must not be empty.")
        let start = windows.map(\.start).min() ?? windows[0].start
        let end = windows.map(\.end).max() ?? windows[0].end
        return DateInterval(start: start, end: end)
    }
}

enum CalendarMirrorVisibilityPlan {
    static func memberMirrors(
        _ mirrors: [EventMirror],
        currentMemberID: String,
        partnerShareOwnerID: String?
    ) -> [EventMirror] {
        mirrors.filter { mirror in
            mirror.ownerMemberID == currentMemberID || mirror.ownerMemberID == partnerShareOwnerID
        }
    }
}

enum CalendarSetupGuidanceStep: Equatable {
    case calendarAccess
    case pairing
}

enum CalendarSetupGuidancePlan {
    static func step(
        hasCompletedInitialProfilePrompt: Bool,
        currentDisplayName: String,
        authorizationState: CalendarAuthorizationState,
        selectedCalendarIDs: Set<String>,
        pairingStatus: PairingStatus
    ) -> CalendarSetupGuidanceStep? {
        guard hasCompletedInitialProfilePrompt else { return nil }
        guard PairingSettingsPlan.normalizedDisplayName(currentDisplayName) != nil else { return nil }
        guard authorizationState.canReadEvents && !selectedCalendarIDs.isEmpty else {
            return .calendarAccess
        }

        switch pairingStatus {
        case .notPaired, .waitingForYouToShare:
            return .pairing
        case .waitingForPartner, .waitingForPartnerToShare, .paired:
            return nil
        }
    }
}

enum CalendarDisplayMirrorPlan {
    static let transientIDPrefix = "display:"

    static func displayMirrors(
        from events: [CalendarSourceEvent],
        ownerMemberID: String
    ) -> [EventMirror] {
        events.map { event in
            let fingerprint = EventMirrorService.fingerprint(for: event)
            let mirrorKey = EventMirrorService.makeMirrorKey(
                calendarIdentifier: event.calendarIdentifier,
                eventIdentifier: event.eventIdentifier,
                occurrenceStartDate: event.occurrenceStartDate,
                fingerprint: fingerprint
            )
            return EventMirror(
                id: "\(transientIDPrefix)\(mirrorKey)",
                ownerMemberID: ownerMemberID,
                mirrorKey: mirrorKey,
                sourceCalendarID: event.calendarIdentifier,
                sourceCalendarTitle: event.calendarTitle,
                occurrenceStartDate: event.occurrenceStartDate,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                timeZoneIdentifier: event.timeZoneIdentifier,
                title: event.title,
                location: event.location,
                notes: event.notes,
                urlString: event.url?.absoluteString,
                calendarColorHex: event.calendarColorHex,
                visibilityRawValue: EventVisibility.fullDetails.rawValue,
                deletedAt: nil,
                cloudKitRecordName: nil
            )
        }
    }
}

enum EventDetailInteractionPlan {
    static func canComment(on event: EventMirror) -> Bool {
        !event.id.hasPrefix(CalendarDisplayMirrorPlan.transientIDPrefix)
    }
}

enum CalendarAccessRequestListPlan {
    private struct LogicalRequestKey: Hashable {
        let requesterMemberID: String
        let ownerMemberID: String
        let requestedStartDate: Date
        let requestedEndDate: Date
    }

    private static func logicalKey(for request: CalendarAccessRequest) -> LogicalRequestKey {
        LogicalRequestKey(
            requesterMemberID: request.requesterMemberID.trimmingCharacters(in: .whitespacesAndNewlines),
            ownerMemberID: request.ownerMemberID.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedStartDate: request.requestedStartDate,
            requestedEndDate: request.requestedEndDate
        )
    }

    private static func preferredRequest(in requests: [CalendarAccessRequest]) -> CalendarAccessRequest? {
        requests.max { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                if lhs.status == .pending && rhs.status != .pending {
                    return true
                }
                if lhs.status != .pending && rhs.status == .pending {
                    return false
                }
                return lhs.id < rhs.id
            }
            return lhs.updatedAt < rhs.updatedAt
        }
    }

    private static func collapsedRequests(_ requests: [CalendarAccessRequest]) -> [CalendarAccessRequest] {
        Dictionary(grouping: requests, by: logicalKey(for:))
            .values
            .compactMap(preferredRequest(in:))
    }

    static func pendingIncoming(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        collapsedRequests(
            requests.filter { request in
                request.source == .privateOwnerZone
            }
        )
            .filter { $0.status == .pending }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func outgoing(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        collapsedRequests(
            requests.filter { request in
                request.requesterMemberID == currentMemberID && request.source != .privateOwnerZone
            }
        )
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func pendingOutgoingRequestsNotSupersededByTerminalCopies(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        let outgoingRequests = requests.filter { request in
            request.requesterMemberID == currentMemberID && request.source != .privateOwnerZone
        }
        let requestsByKey = Dictionary(grouping: outgoingRequests, by: logicalKey(for:))
        return outgoingRequests
            .filter { request in
                guard request.status == .pending else { return false }
                // Only requests not yet confirmed on the server need (re)uploading.
                // Once a request round-trips back from the shared zone it is
                // `.acceptedSharedZone`; re-uploading it would clobber the owner's
                // status update (e.g. an approval) with our stale `pending` copy.
                guard request.source == .localOutgoing else { return false }
                let matchingRequests = requestsByKey[logicalKey(for: request)] ?? []
                return !matchingRequests.contains { matchingRequest in
                    matchingRequest.status != .pending
                        && matchingRequest.updatedAt >= request.updatedAt
                }
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.updatedAt < rhs.updatedAt
            }
    }
}

enum CalendarAccessRequestCloudUploadPlan {
    static func requestsNeedingUpload(
        _ requests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> [CalendarAccessRequest] {
        CalendarAccessRequestListPlan.pendingOutgoingRequestsNotSupersededByTerminalCopies(
            requests,
            currentMemberID: currentMemberID
        )
    }
}

enum PendingActionBadgePlan {
    static func count(
        invitations: [EventInvitation],
        accessRequests: [CalendarAccessRequest],
        currentMemberID: String
    ) -> Int {
        let invitationCount = invitations.filter {
            InvitationInteractionPlan.canRespond(to: $0, currentMemberID: currentMemberID)
                && $0.archivedAt == nil
        }.count
        return invitationCount + CalendarAccessRequestListPlan.pendingIncoming(
            accessRequests,
            currentMemberID: currentMemberID
        ).count
    }
}

enum ICloudSharingIdentityDisplayPlan {
    static func displayValue(for identifiers: [String], emptyValue: String) -> String {
        let normalizedIdentifiers = identifiers
            .compactMap(normalizedEmailAddress)
        var seenIdentifiers = Set<String>()
        let uniqueIdentifiers = normalizedIdentifiers.filter { seenIdentifiers.insert($0).inserted }
        guard !uniqueIdentifiers.isEmpty else { return emptyValue }
        return uniqueIdentifiers.joined(separator: ", ")
    }

    static func displayValue(for identifier: String?, emptyValue: String) -> String {
        displayValue(for: [identifier].compactMap { $0 }, emptyValue: emptyValue)
    }

    static func emailAddresses(merging existingValues: [String], _ newValues: [String]) -> [String] {
        var seenEmailAddresses = Set<String>()
        return (existingValues + newValues)
            .compactMap(normalizedEmailAddress)
            .filter { seenEmailAddresses.insert($0).inserted }
    }

    static func normalizedEmailAddress(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        let parts = trimmedValue.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasSuffix(".") else {
            return nil
        }
        return trimmedValue
    }
}

enum ICloudSharingTeardownPlan {
    static func localOwnerIDsToPurge(
        partnerShareOwnerID: String?,
        legacyPartnerMemberID: String
    ) -> Set<String> {
        var ownerIDs = Set([partnerShareOwnerID].compactMap { normalizedID($0) })
        if let legacyID = normalizedID(legacyPartnerMemberID) {
            ownerIDs.insert(legacyID)
        }
        ownerIDs.insert("partner")
        return ownerIDs
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? nil : trimmedID
    }
}

enum PairingStatus: Equatable {
    case notPaired
    case waitingForPartner
    case waitingForPartnerToShare
    case waitingForYouToShare
    case paired
}

enum PairingCalendarStatus: Equatable {
    case off
    case waitingForPartner
    case waitingForPartnerToShare
    case on
    case unavailable
}

enum PairingSettingsPlan {
    static func status(
        hasStartedPairing: Bool,
        outgoingParticipantIDs: [String],
        incomingOwnerID: String?
    ) -> PairingStatus {
        let hasAcceptedOutgoingShare = !normalizedIDs(outgoingParticipantIDs).isEmpty
        let hasIncomingShare = normalizedID(incomingOwnerID) != nil
        if hasAcceptedOutgoingShare && hasIncomingShare {
            return .paired
        }
        if hasIncomingShare {
            return .waitingForYouToShare
        }
        if hasAcceptedOutgoingShare {
            return .waitingForPartnerToShare
        }
        if hasStartedPairing {
            return .waitingForPartner
        }
        return .notPaired
    }

    static func outgoingStatus(
        hasStartedPairing: Bool,
        outgoingParticipantIDs: [String]
    ) -> PairingCalendarStatus {
        if !normalizedIDs(outgoingParticipantIDs).isEmpty {
            return .on
        }
        return hasStartedPairing ? .waitingForPartner : .off
    }

    static func incomingStatus(incomingOwnerID: String?) -> PairingCalendarStatus {
        normalizedID(incomingOwnerID) == nil ? .unavailable : .on
    }

    static func partnerIdentity(
        incomingOwnerID: String?,
        outgoingParticipantIDs: [String],
        partnerICloudEmailAddresses: [String] = [],
        emptyValue: String
    ) -> String {
        let storedEmailDisplayValue = ICloudSharingIdentityDisplayPlan.displayValue(
            for: partnerICloudEmailAddresses,
            emptyValue: ""
        )
        if !storedEmailDisplayValue.isEmpty {
            return storedEmailDisplayValue
        }
        return ICloudSharingIdentityDisplayPlan.displayValue(
            for: outgoingParticipantIDs,
            emptyValue: emptyValue
        )
    }

    static func partnerDisplayName(
        partnerNoteName: String?,
        partnerSyncedDisplayName: String?,
        partnerICloudIdentity: String,
        fallback: String
    ) -> String {
        if let noteName = normalizedID(partnerNoteName) {
            return noteName
        }
        if let syncedDisplayName = normalizedID(partnerSyncedDisplayName) {
            return syncedDisplayName
        }
        if isReadableICloudIdentity(partnerICloudIdentity) {
            return partnerICloudIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallback
    }

    static func partnerStatusDisplayName(
        partnerNoteName: String?,
        partnerSyncedDisplayName: String?,
        partnerICloudIdentity: String,
        fallback: String,
        language: AppLanguage
    ) -> String {
        let displayName = partnerDisplayBaseName(
            partnerSyncedDisplayName: partnerSyncedDisplayName,
            partnerICloudIdentity: partnerICloudIdentity,
            fallback: fallback
        )
        guard let noteName = normalizedID(partnerNoteName),
              noteName != displayName else {
            return displayName
        }
        return ShareCalStrings(language: language).displayNameWithNote(
            displayName: displayName,
            note: noteName
        )
    }

    static func randomDisplayName(randomNumber: () -> Int = { Int.random(in: 0...9_999) }) -> String {
        let number = max(0, min(9_999, randomNumber()))
        return String(format: "ShareCal %04d", number)
    }

    static func normalizedDisplayName(_ displayName: String?) -> String? {
        normalizedID(displayName)
    }

    private static func partnerDisplayBaseName(
        partnerSyncedDisplayName: String?,
        partnerICloudIdentity: String,
        fallback: String
    ) -> String {
        if let syncedDisplayName = normalizedID(partnerSyncedDisplayName) {
            return syncedDisplayName
        }
        if isReadableICloudIdentity(partnerICloudIdentity) {
            return partnerICloudIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallback
    }

    private static func normalizedIDs(_ ids: [String]) -> [String] {
        ids.compactMap(normalizedID)
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? nil : trimmedID
    }

    private static func isReadableICloudIdentity(_ value: String) -> Bool {
        let identities = value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return !identities.isEmpty && identities.allSatisfy {
            ICloudSharingIdentityDisplayPlan.normalizedEmailAddress($0) != nil
        }
    }
}

enum OldSharedCalendarsCleanupPromptPlan {
    static func shouldPresent(
        pairingStatus: PairingStatus,
        inactiveSharedOwnerIDs: [String],
        hasPresentedPrompt: Bool
    ) -> Bool {
        pairingStatus == .paired
            && !inactiveSharedOwnerIDs.isEmpty
            && !hasPresentedPrompt
    }
}

struct ExistingICloudDataSnapshot: Equatable {
    let hasPrivateZoneData: Bool
    let hasOutgoingShare: Bool
    let acceptedSharedZoneCount: Int
    let lookupFailed: Bool

    init(
        hasPrivateZoneData: Bool,
        hasOutgoingShare: Bool,
        acceptedSharedZoneCount: Int,
        lookupFailed: Bool = false
    ) {
        self.hasPrivateZoneData = hasPrivateZoneData
        self.hasOutgoingShare = hasOutgoingShare
        self.acceptedSharedZoneCount = acceptedSharedZoneCount
        self.lookupFailed = lookupFailed
    }

    var hasRecoverableData: Bool {
        hasPrivateZoneData || hasOutgoingShare || acceptedSharedZoneCount > 0
    }
}

enum ExistingICloudDataRecoveryPlan {
    static func shouldPresent(
        snapshot: ExistingICloudDataSnapshot,
        hasCompletedInitialProfilePrompt: Bool,
        hasResolvedPrompt: Bool,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        pairingID: String?,
        inactiveSharedOwnerIDs: [String],
        lastSyncAt: Date?
    ) -> Bool {
        guard hasCompletedInitialProfilePrompt else { return false }
        guard !hasResolvedPrompt else { return false }
        guard looksLikeFreshLocalState(
            hasStartedPairing: hasStartedPairing,
            partnerShareOwnerID: partnerShareOwnerID,
            outgoingShareParticipantIDs: outgoingShareParticipantIDs,
            pairingID: pairingID,
            inactiveSharedOwnerIDs: inactiveSharedOwnerIDs,
            lastSyncAt: lastSyncAt
        ) else { return false }
        return snapshot.hasRecoverableData
    }

    static func shouldDeferAutomaticSync(
        hasResolvedPrompt: Bool,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        pairingID: String?,
        inactiveSharedOwnerIDs: [String],
        lastSyncAt: Date?
    ) -> Bool {
        guard !hasResolvedPrompt else { return false }
        return looksLikeFreshLocalState(
            hasStartedPairing: hasStartedPairing,
            partnerShareOwnerID: partnerShareOwnerID,
            outgoingShareParticipantIDs: outgoingShareParticipantIDs,
            pairingID: pairingID,
            inactiveSharedOwnerIDs: inactiveSharedOwnerIDs,
            lastSyncAt: lastSyncAt
        )
    }

    private static func looksLikeFreshLocalState(
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        pairingID: String?,
        inactiveSharedOwnerIDs: [String],
        lastSyncAt: Date?
    ) -> Bool {
        guard !hasStartedPairing else { return false }
        guard normalizedID(partnerShareOwnerID) == nil else { return false }
        guard !outgoingShareParticipantIDs.contains(where: { normalizedID($0) != nil }) else { return false }
        guard normalizedID(pairingID) == nil else { return false }
        guard inactiveSharedOwnerIDs.allSatisfy({ normalizedID($0) == nil }) else { return false }
        return lastSyncAt == nil
    }

    private static func normalizedID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

enum PairingSafetyEducationPlan {
    static func shouldPresentNotice(
        pairingStatus: PairingStatus,
        hasPromptedPartnerNoteForCurrentPairing: Bool,
        hasShownPairingSafetyNoticeForCurrentPairing: Bool
    ) -> Bool {
        guard pairingStatus == .paired else { return false }
        guard hasPromptedPartnerNoteForCurrentPairing else { return false }
        return !hasShownPairingSafetyNoticeForCurrentPairing
    }

    static func shouldShowPersistentWarning(pairingStatus: PairingStatus) -> Bool {
        pairingStatus != .notPaired
    }
}

enum SharedPeoplePresentationPlan {
    static func canOpenOfficialSharing(
        isCloudKitEnabled: Bool,
        isPreparingShare: Bool,
        isStoppingShare: Bool
    ) -> Bool {
        isCloudKitEnabled && !isPreparingShare && !isStoppingShare
    }
}

enum LegacyPairingIDMigrationPlan {
    static func partnerOwnerIDsForSelection(
        partnerShareOwnerID: String?,
        outgoingParticipantIDs: [String],
        hasStartedPairing: Bool
    ) -> [String] {
        if let partnerShareOwnerID = normalizedID(partnerShareOwnerID) {
            return [partnerShareOwnerID]
        }

        guard hasStartedPairing else { return [] }
        let outgoingIDs = normalizedUniqueIDs(outgoingParticipantIDs)
        return outgoingIDs.count == 1 ? outgoingIDs : []
    }

    static func shouldGeneratePairingID(
        currentPairingID: String?,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingParticipantIDs: [String],
        sharedZoneOwnerIDs: [String]
    ) -> Bool {
        guard normalizedID(currentPairingID) == nil else { return false }
        let partnerOwnerIDs = Set(
            partnerOwnerIDsForSelection(
                partnerShareOwnerID: partnerShareOwnerID,
                outgoingParticipantIDs: outgoingParticipantIDs,
                hasStartedPairing: hasStartedPairing
            )
        )
        guard !partnerOwnerIDs.isEmpty else { return false }
        let sharedOwnerIDs = Set(normalizedUniqueIDs(sharedZoneOwnerIDs))
        return !partnerOwnerIDs.isDisjoint(with: sharedOwnerIDs)
    }

    private static func normalizedUniqueIDs(_ ids: [String]) -> [String] {
        Array(Set(ids.compactMap(normalizedID))).sorted()
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? nil : trimmedID
    }
}

enum SyncPhase: String {
    case idle
    case syncing
    case failed
}

enum ForegroundSyncPlan {
    static let automaticThrottleInterval: TimeInterval = 5 * 60

    static func shouldRunAutomaticSync(
        lastSyncAt: Date?,
        now: Date,
        syncPhase: SyncPhase,
        hasPendingAcceptedShare: Bool
    ) -> Bool {
        guard syncPhase != .syncing else { return false }
        if hasPendingAcceptedShare { return true }
        guard let lastSyncAt else { return true }
        return now.timeIntervalSince(lastSyncAt) >= automaticThrottleInterval
    }
}

enum CloudKitForegroundSyncPlan {
    static func shouldRunCloudKit(
        iCloudSharingEnabled: Bool,
        hasStartedPairing: Bool,
        partnerShareOwnerID: String?,
        outgoingShareParticipantIDs: [String],
        forceCloudKit: Bool
    ) -> Bool {
        guard iCloudSharingEnabled else { return false }
        if forceCloudKit { return true }
        if hasStartedPairing { return true }
        if normalizedID(partnerShareOwnerID) != nil { return true }
        return outgoingShareParticipantIDs.contains { normalizedID($0) != nil }
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? nil : trimmedID
    }
}

struct CalendarDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

enum ShareCalSmokeTestEventPlan {
    static let title = "ShareCal E2E Smoke Test"
    static let notes = "Created by ShareCal simulator validation."

    static func draft(now: Date = .now, title: String = title) -> LocalCalendarEventDraft {
        LocalCalendarEventDraft(
            title: title,
            startDate: now.addingTimeInterval(15 * 60),
            endDate: now.addingTimeInterval(45 * 60),
            isAllDay: false,
            location: nil,
            notes: notes
        )
    }
}

enum ShareCalCalendarBootstrapPlan {
    static let calendarTitle = "ShareCal"
    static let calendarColorHex = "#FF2D55"

    static func shouldOfferCreation(calendars: [CalendarDescriptor]) -> Bool {
        !calendars.contains { calendar in
            isShareCalCalendar(calendar) && calendar.allowsContentModifications
        }
    }

    static func selectedCalendarIDs(
        afterEnsuring calendar: CalendarDescriptor,
        currentSelection: Set<String>
    ) -> Set<String> {
        var selection = currentSelection
        selection.insert(calendar.id)
        return selection
    }

    static func isShareCalCalendar(_ calendar: CalendarDescriptor) -> Bool {
        calendar.title.compare(calendarTitle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct CalendarSourceEvent: Hashable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
    let startDate: Date
    let endDate: Date
    let occurrenceStartDate: Date
    let isAllDay: Bool
    let timeZoneIdentifier: String
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
}

struct LocalCalendarEventDraft: Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
}

struct CreatedCalendarEvent: Equatable {
    let eventIdentifier: String
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
}

@Model
final class CoupleSpace {
    @Attribute(.unique) var id: String
    var schemaVersion: Int
    var createdAt: Date
    var ownerMemberID: String
    var cloudKitRecordName: String?
    var shareRecordName: String?

    init(
        id: String = UUID().uuidString,
        schemaVersion: Int = 1,
        createdAt: Date = .now,
        ownerMemberID: String,
        cloudKitRecordName: String? = nil,
        shareRecordName: String? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.ownerMemberID = ownerMemberID
        self.cloudKitRecordName = cloudKitRecordName
        self.shareRecordName = shareRecordName
    }
}

@Model
final class MemberProfile {
    @Attribute(.unique) var id: String
    var displayName: String
    var avatarColorHex: String
    var iCloudUserRecordName: String?
    var lastSeenAt: Date?

    init(
        id: String = UUID().uuidString,
        displayName: String,
        avatarColorHex: String,
        iCloudUserRecordName: String? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarColorHex = avatarColorHex
        self.iCloudUserRecordName = iCloudUserRecordName
        self.lastSeenAt = lastSeenAt
    }
}

@Model
final class EventMirror: Identifiable {
    @Attribute(.unique) var id: String
    var ownerMemberID: String
    var mirrorKey: String
    var sourceCalendarID: String
    var sourceCalendarTitle: String
    var occurrenceStartDate: Date
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var timeZoneIdentifier: String
    var title: String
    var location: String?
    var notes: String?
    var urlString: String?
    var calendarColorHex: String
    var visibilityRawValue: String
    var deletedAt: Date?
    var cloudKitRecordName: String?

    var visibility: EventVisibility {
        get { EventVisibility(rawValue: visibilityRawValue) ?? .fullDetails }
        set { visibilityRawValue = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        ownerMemberID: String,
        mirrorKey: String,
        sourceCalendarID: String,
        sourceCalendarTitle: String,
        occurrenceStartDate: Date,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        title: String,
        location: String?,
        notes: String?,
        urlString: String?,
        calendarColorHex: String,
        visibilityRawValue: String,
        deletedAt: Date?,
        cloudKitRecordName: String?
    ) {
        self.id = id
        self.ownerMemberID = ownerMemberID
        self.mirrorKey = mirrorKey
        self.sourceCalendarID = sourceCalendarID
        self.sourceCalendarTitle = sourceCalendarTitle
        self.occurrenceStartDate = occurrenceStartDate
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.title = title
        self.location = location
        self.notes = notes
        self.urlString = urlString
        self.calendarColorHex = calendarColorHex
        self.visibilityRawValue = visibilityRawValue
        self.deletedAt = deletedAt
        self.cloudKitRecordName = cloudKitRecordName
    }
}

@Model
final class LocalEventShadow {
    @Attribute(.unique) var id: String
    var localEventIdentifier: String
    var calendarIdentifier: String
    var occurrenceStartDate: Date
    var fingerprint: String
    var cloudKitRecordName: String
    var lastUploadedAt: Date?
    var isTombstone: Bool

    var mirrorKey: String {
        EventMirrorService.makeMirrorKey(
            calendarIdentifier: calendarIdentifier,
            eventIdentifier: localEventIdentifier,
            occurrenceStartDate: occurrenceStartDate,
            fingerprint: fingerprint
        )
    }

    init(
        id: String = UUID().uuidString,
        localEventIdentifier: String,
        calendarIdentifier: String,
        occurrenceStartDate: Date,
        fingerprint: String,
        cloudKitRecordName: String,
        lastUploadedAt: Date?,
        isTombstone: Bool
    ) {
        self.id = id
        self.localEventIdentifier = localEventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.occurrenceStartDate = occurrenceStartDate
        self.fingerprint = fingerprint
        self.cloudKitRecordName = cloudKitRecordName
        self.lastUploadedAt = lastUploadedAt
        self.isTombstone = isTombstone
    }
}

enum CloudKitMirrorSyncPlan {
    static func mirrorsNeedingUpload(
        _ mirrors: [EventMirror],
        activeShadows: [LocalEventShadow],
        existingShadows: [LocalEventShadow],
        existingLocalMirrors: [EventMirror]
    ) -> [EventMirror] {
        let activeShadowByID = Dictionary(activeShadows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingShadowByID = Dictionary(existingShadows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingMirrorByKey = Dictionary(existingLocalMirrors.map { ($0.mirrorKey, $0) }, uniquingKeysWith: { first, _ in first })

        return mirrors.filter { mirror in
            if mirror.deletedAt != nil { return true }
            guard let existingMirror = existingMirrorByKey[mirror.mirrorKey] else { return true }
            guard hasSameCloudKitPayload(mirror, as: existingMirror) else { return true }
            guard existingMirror.cloudKitRecordName != nil else { return true }
            guard let activeShadow = activeShadowByID[mirror.mirrorKey],
                  let existingShadow = existingShadowByID[mirror.mirrorKey] else {
                return true
            }
            return activeShadow.fingerprint != existingShadow.fingerprint
                || activeShadow.cloudKitRecordName != existingShadow.cloudKitRecordName
                || activeShadow.isTombstone != existingShadow.isTombstone
        }
    }

    private static func hasSameCloudKitPayload(_ lhs: EventMirror, as rhs: EventMirror) -> Bool {
        lhs.ownerMemberID == rhs.ownerMemberID
            && lhs.mirrorKey == rhs.mirrorKey
            && lhs.sourceCalendarID == rhs.sourceCalendarID
            && lhs.sourceCalendarTitle == rhs.sourceCalendarTitle
            && lhs.occurrenceStartDate == rhs.occurrenceStartDate
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
            && lhs.title == rhs.title
            && lhs.location == rhs.location
            && lhs.notes == rhs.notes
            && lhs.urlString == rhs.urlString
            && lhs.calendarColorHex == rhs.calendarColorHex
            && lhs.visibilityRawValue == rhs.visibilityRawValue
            && lhs.deletedAt == rhs.deletedAt
            && lhs.cloudKitRecordName == rhs.cloudKitRecordName
    }
}

@Model
final class EventInvitation: Identifiable {
    @Attribute(.unique) var id: String
    var creatorMemberID: String
    var inviteeMemberID: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var createdLocalEventID: String?
    var cloudKitRecordName: String?
    var archivedAt: Date?

    var status: InvitationStatus {
        get { InvitationStatus(rawValue: statusRawValue) ?? .pending }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    init(
        id: String = UUID().uuidString,
        creatorMemberID: String,
        inviteeMemberID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String?,
        notes: String?,
        statusRawValue: String = InvitationStatus.pending.rawValue,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        createdLocalEventID: String? = nil,
        cloudKitRecordName: String? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.creatorMemberID = creatorMemberID
        self.inviteeMemberID = inviteeMemberID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdLocalEventID = createdLocalEventID
        self.cloudKitRecordName = cloudKitRecordName
        self.archivedAt = archivedAt
    }
}

@Model
final class CalendarAccessRequest: Identifiable {
    @Attribute(.unique) var id: String
    var requesterMemberID: String
    var ownerMemberID: String
    var requestedStartDate: Date
    var requestedEndDate: Date
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var cloudKitRecordName: String?
    var sourceRawValue: String?

    var status: CalendarAccessRequestStatus {
        get { CalendarAccessRequestStatus(rawValue: statusRawValue) ?? .pending }
        set {
            statusRawValue = newValue.rawValue
            updatedAt = .now
        }
    }

    var source: CalendarAccessRequestSource {
        get { CalendarAccessRequestSource(rawValue: sourceRawValue ?? "") ?? .privateOwnerZone }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        requesterMemberID: String,
        ownerMemberID: String,
        requestedStartDate: Date,
        requestedEndDate: Date,
        statusRawValue: String = CalendarAccessRequestStatus.pending.rawValue,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        cloudKitRecordName: String? = nil,
        sourceRawValue: String? = nil
    ) {
        self.id = id
        self.requesterMemberID = requesterMemberID
        self.ownerMemberID = ownerMemberID
        self.requestedStartDate = requestedStartDate
        self.requestedEndDate = requestedEndDate
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cloudKitRecordName = cloudKitRecordName
        self.sourceRawValue = sourceRawValue
    }
}

@Model
final class EventComment: Identifiable {
    @Attribute(.unique) var id: String
    var eventMirrorID: String
    var authorMemberID: String
    var body: String
    var createdAt: Date
    var editedAt: Date?
    var deletedAt: Date?
    var isRead: Bool
    var cloudKitRecordName: String?

    init(
        id: String = UUID().uuidString,
        eventMirrorID: String,
        authorMemberID: String,
        body: String,
        createdAt: Date = .now,
        editedAt: Date? = nil,
        deletedAt: Date? = nil,
        isRead: Bool = false,
        cloudKitRecordName: String? = nil
    ) {
        self.id = id
        self.eventMirrorID = eventMirrorID
        self.authorMemberID = authorMemberID
        self.body = body
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.isRead = isRead
        self.cloudKitRecordName = cloudKitRecordName
    }
}

@Model
final class SyncState {
    @Attribute(.unique) var id: String
    var privateDatabaseTokenData: Data?
    var sharedDatabaseTokenData: Data?
    var syncEngineStateData: Data?
    var lastSyncAt: Date?
    var lastErrorMessage: String?
    var pendingMutationCount: Int

    init(
        id: String = "default",
        privateDatabaseTokenData: Data? = nil,
        sharedDatabaseTokenData: Data? = nil,
        syncEngineStateData: Data? = nil,
        lastSyncAt: Date? = nil,
        lastErrorMessage: String? = nil,
        pendingMutationCount: Int = 0
    ) {
        self.id = id
        self.privateDatabaseTokenData = privateDatabaseTokenData
        self.sharedDatabaseTokenData = sharedDatabaseTokenData
        self.syncEngineStateData = syncEngineStateData
        self.lastSyncAt = lastSyncAt
        self.lastErrorMessage = lastErrorMessage
        self.pendingMutationCount = pendingMutationCount
    }
}

@MainActor
enum ShareCalLocalDataCleanupService {
    private static let legacyReviewSampleSourceCalendarID = "sharecal-preview"

    static func purge(modelContext: ModelContext) throws {
        try deleteAll(CoupleSpace.self, modelContext: modelContext)
        try deleteAll(EventMirror.self, modelContext: modelContext)
        try deleteAll(LocalEventShadow.self, modelContext: modelContext)
        try deleteAll(EventComment.self, modelContext: modelContext)
        try deleteAll(EventInvitation.self, modelContext: modelContext)
        try deleteAll(CalendarAccessRequest.self, modelContext: modelContext)
        try deleteAll(SyncState.self, modelContext: modelContext)
        try modelContext.save()
    }

    static func purgeSharedOwnerMirrors(
        ownerMemberIDs: Set<String>,
        modelContext: ModelContext
    ) throws {
        guard !ownerMemberIDs.isEmpty else { return }

        let existingMirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
        var deletedMirrorIDs = Set<String>()
        for mirror in existingMirrors where ownerMemberIDs.contains(mirror.ownerMemberID) {
            deletedMirrorIDs.insert(mirror.id)
            modelContext.delete(mirror)
        }

        if !deletedMirrorIDs.isEmpty {
            let existingComments = try modelContext.fetch(FetchDescriptor<EventComment>())
            for comment in existingComments where deletedMirrorIDs.contains(comment.eventMirrorID) {
                modelContext.delete(comment)
            }
        }

        try modelContext.save()
    }

    static func purgeSharedOwnerData(
        ownerMemberIDs: Set<String>,
        modelContext: ModelContext
    ) throws {
        guard !ownerMemberIDs.isEmpty else { return }

        let existingMirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
        var deletedMirrorIDs = Set<String>()
        for mirror in existingMirrors where ownerMemberIDs.contains(mirror.ownerMemberID) {
            deletedMirrorIDs.insert(mirror.id)
            modelContext.delete(mirror)
        }

        if !deletedMirrorIDs.isEmpty {
            let existingComments = try modelContext.fetch(FetchDescriptor<EventComment>())
            for comment in existingComments where deletedMirrorIDs.contains(comment.eventMirrorID) {
                modelContext.delete(comment)
            }
        }

        let existingInvitations = try modelContext.fetch(FetchDescriptor<EventInvitation>())
        for invitation in existingInvitations
            where ownerMemberIDs.contains(invitation.creatorMemberID)
                || ownerMemberIDs.contains(invitation.inviteeMemberID) {
            modelContext.delete(invitation)
        }

        let existingAccessRequests = try modelContext.fetch(FetchDescriptor<CalendarAccessRequest>())
        for request in existingAccessRequests
            where ownerMemberIDs.contains(request.requesterMemberID)
                || ownerMemberIDs.contains(request.ownerMemberID) {
            modelContext.delete(request)
        }

        try modelContext.save()
    }

    static func purgeReviewSampleData(modelContext: ModelContext) throws {
        let existingMirrors = try modelContext.fetch(FetchDescriptor<EventMirror>())
        let sampleMirrorIDs = Set(
            existingMirrors
                .filter { $0.sourceCalendarID == legacyReviewSampleSourceCalendarID }
                .map(\.id)
        )
        for mirror in existingMirrors where sampleMirrorIDs.contains(mirror.id) {
            modelContext.delete(mirror)
        }

        let existingInvitations = try modelContext.fetch(FetchDescriptor<EventInvitation>())
        for invitation in existingInvitations where invitation.id.hasPrefix("\(legacyReviewSampleSourceCalendarID):") {
            modelContext.delete(invitation)
        }

        let existingComments = try modelContext.fetch(FetchDescriptor<EventComment>())
        for comment in existingComments where comment.id.hasPrefix("\(legacyReviewSampleSourceCalendarID):") || sampleMirrorIDs.contains(comment.eventMirrorID) {
            modelContext.delete(comment)
        }

        try modelContext.save()
    }

    private static func deleteAll<Model: PersistentModel>(
        _ modelType: Model.Type,
        modelContext: ModelContext
    ) throws {
        let models = try modelContext.fetch(FetchDescriptor<Model>())
        for model in models {
            modelContext.delete(model)
        }
    }
}

enum ShareCalModelContainer {
    static let schema = Schema([
        CoupleSpace.self,
        MemberProfile.self,
        EventMirror.self,
        LocalEventShadow.self,
        EventInvitation.self,
        CalendarAccessRequest.self,
        EventComment.self,
        SyncState.self
    ])

    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
