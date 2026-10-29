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
    static let key = "appLanguage"

    /// A language picked in Settings wins; until then the app follows the iPhone's
    /// first preferred language, so it is Chinese for Chinese systems and English otherwise.
    static func read(from defaults: UserDefaults, preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: key) ?? "") ?? systemLanguage(preferredLanguages: preferredLanguages)
    }

    static func systemLanguage(preferredLanguages: [String]) -> AppLanguage {
        guard let first = preferredLanguages.first else { return .english }
        return first.lowercased().hasPrefix("zh") ? .chinese : .english
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
    var commentsUnavailableNotShared: String {
        text(
            "Your partner can't see this event yet, so there is no one to comment with. Events from the pairing day onward are shared.",
            "对方还看不到这条日程，所以暂时没法评论。配对日及之后的日程会共享给对方。"
        )
    }
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
    var pairingSafetyNoticeTitle: String { text("About Your iCloud Data", "关于你的 iCloud 数据") }
    var pairingSafetyNoticeMessage: String {
        text(
            "OurDays' iCloud sharing data is separate from your local calendars and lives in your own iCloud. If you ever delete and reinstall the app, choose “Keep Existing iCloud Data” on first launch and your pairing, comments and invitations come back. Deleting OurDays iCloud data never deletes your original calendars or events in the system Calendar app.",
            "OurDays 的 iCloud 共享数据与本地日历是隔离的，存放在你自己的 iCloud 里。如果以后删除并重装了 App，首次启动时选择「继续使用现有 iCloud 数据」，配对、评论和邀请都会回来。删除 OurDays 的 iCloud 数据不会删除系统日历中的原始日历或事件。"
        )
    }
    var existingICloudDataPromptTitle: String {
        text("Existing iCloud Data Found", "发现旧的 iCloud 数据")
    }
    var existingICloudDataPromptMessage: String {
        text(
            "This Apple ID already has OurDays iCloud data: your pairing, comments and invitations are still there. If you reinstalled the app, keep it and everything comes back without pairing again. Delete it only if you no longer want to share; that never deletes your original calendars or events in the system Calendar app.",
            "这个 Apple ID 下已经有 OurDays 的 iCloud 数据：配对、评论和邀请都还在。如果你是重装了 App，选择继续使用，一切都会回来，不需要重新配对。只有不打算再共享时才删除；删除也不会影响系统日历中的原始日历或事件。"
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
    var pairingSafetySection: String { text("If You Reinstall", "重装提醒") }
    var pairingSafetyPersistentWarningTitle: String {
        text("Deleting the app does not delete your shared data.", "删除 App 不会丢失共享数据。")
    }
    var pairingSafetyPersistentWarningMessage: String {
        text(
            "Your pairing, comments and invitations live in your own iCloud. After a reinstall, choose “Keep Existing iCloud Data” on first launch to get them back. Removing OurDays iCloud data will not delete your original calendars or events in the system Calendar app.",
            "配对、评论和邀请都保存在你自己的 iCloud 里。重装后首次启动时选择「继续使用现有 iCloud 数据」即可找回。删除 OurDays 的 iCloud 数据不会删除系统日历中的原始日历或事件。"
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

    func pasteInviteLinkButton(isAccepting: Bool) -> String {
        isAccepting
            ? text("Joining your partner...", "正在加入对方...")
            : text("Got an invite link? Open it here", "收到邀请链接？在这里打开")
    }

    var pasteInviteLinkHint: String {
        text(
            "If tapping the link in WeChat asks you to sign in to iCloud, copy the message, come back here and paste it in.",
            "如果在微信里点开链接提示登录 iCloud，复制对方的消息，回到这里粘贴进去即可。"
        )
    }

    var acceptInviteSheetTitle: String { text("Open Your Partner's Invite", "打开对方的邀请") }
    var acceptInviteSheetMessage: String {
        text(
            "Paste the message or link your partner sent. The whole message is fine; OurDays finds the link in it.",
            "把对方发来的消息或链接粘贴到下面，整段消息也可以，OurDays 会从里面找出链接。"
        )
    }
    var acceptInvitePlaceholder: String { text("Paste here", "粘贴到这里") }
    var acceptInviteClearButton: String { text("Clear", "清空") }
    var acceptInviteInputEmpty: String { text("Nothing pasted yet", "还没有粘贴内容") }
    var acceptInviteInputNoLink: String {
        text(
            "No invite link in this text. It starts with https://www.icloud.com/share/ or https://www.icloud.com.cn/share/.",
            "这段文字里没有邀请链接。链接以 https://www.icloud.com/share/ 或 https://www.icloud.com.cn/share/ 开头。"
        )
    }
    var acceptInviteInputFound: String { text("Invite link found", "已识别到邀请链接") }
    func acceptInviteOpenButton(isLookingUp: Bool) -> String {
        isLookingUp ? text("Checking the invite...", "正在查看邀请...") : text("Open Invite", "打开邀请")
    }
    func acceptInviteConfirmTitle(_ ownerName: String?) -> String {
        text("Open \(guidePartner(ownerName))'s invite?", "打开\(guidePartner(ownerName))的邀请？")
    }
    func acceptInviteConfirmMessage(_ ownerName: String?, completesPairing: Bool) -> String {
        let owner = guidePartner(ownerName)
        if completesPairing {
            return text(
                "\(owner) already accepted yours, so opening this one finishes pairing.",
                "\(owner)已经收下了你的信，收下这一封你们就配对完成了。"
            )
        }
        return text(
            "You'll see \(owner)'s calendar. To finish pairing, send your own link back to \(owner) afterwards.",
            "收下后你能看到\(owner)的日程。之后还要把你的邀请回发给\(owner)，才算配对完成。"
        )
    }
    var acceptInviteConfirmButton: String { text("Open", "收下") }

    var inviteLinkAccepted: String {
        text("Invite found. Joining your partner...", "已找到邀请，正在加入对方...")
    }

    func inviteLinkFailure(_ failure: ShareInvitationLinkPolicy.Failure) -> String {
        switch failure {
        case .noLinkFound:
            text(
                "No OurDays invite link on the clipboard. Copy the whole link your partner sent (it starts with https://www.icloud.com/share/ or https://www.icloud.com.cn/share/).",
                "剪贴板里没有 OurDays 邀请链接。请复制对方发来的完整链接（以 https://www.icloud.com/share/ 或 https://www.icloud.com.cn/share/ 开头）。"
            )
        case .ownLink:
            text("This is your own invite link. Send it to your partner instead.", "这是你自己的邀请链接，请把它发给对方。")
        case .iCloudUnavailable:
            iCloudUnavailableForAppSteps
        case .linkNoLongerValid:
            text(
                "This invite link no longer works. Ask your partner to tap Start Pairing again and send a new link.",
                "这个邀请链接已失效。请对方重新点「发起配对」，再发一次链接。"
            )
        case .inviteOnly:
            text(
                "This link only opens for the iCloud account it was sent to. Ask your partner to send a new link.",
                "这个链接只对受邀的 iCloud 账号开放。请对方重新发一次链接。"
            )
        case .other(let message):
            text("Couldn't open the invite link: \(message)", "无法打开邀请链接：\(message)")
        }
    }

    var iCloudUnavailableTitle: String {
        text("OurDays can't use your iCloud", "OurDays 暂时用不了你的 iCloud")
    }

    var iCloudUnavailableForAppSteps: String {
        text(
            "Pairing runs on iCloud, so invite links ask you to sign in until this is fixed. Open Settings → your name → iCloud, make sure you're signed in, then under Saved to iCloud tap See All and turn on OurDays. Notes and Photos have their own switches, so they can work while OurDays can't.",
            "配对通过 iCloud 完成，修好之前点开邀请链接都会提示登录 iCloud。请打开「设置」→ 你的名字 →「iCloud」，确认已登录，再在「已存储到 iCloud」里展开全部 App，打开 OurDays。备忘录、照片有各自的开关，所以它们能用不代表 OurDays 能用。"
        )
    }

    var iCloudRestrictedSteps: String {
        text(
            "iCloud is restricted on this iPhone (Screen Time or device management). Allow iCloud changes in Settings → Screen Time → Content & Privacy Restrictions, then come back.",
            "这台 iPhone 限制了 iCloud（屏幕使用时间或设备管理）。请在「设置」→「屏幕使用时间」→「内容和隐私访问限制」里允许更改 iCloud 账户，再回来。"
        )
    }

    var iCloudNeedsReauthenticationSteps: String {
        text(
            "iCloud needs you to sign in again. Open Settings → your name and follow the prompt to re-enter your Apple Account password, then come back.",
            "iCloud 需要你重新验证。请打开「设置」→ 你的名字，按提示重新输入 Apple 账户密码，再回来。"
        )
    }

    func iCloudProblemSteps(_ problem: ICloudAvailabilityPolicy.Problem) -> String {
        switch problem {
        case .unavailableForApp: iCloudUnavailableForAppSteps
        case .restricted: iCloudRestrictedSteps
        case .needsReauthentication: iCloudNeedsReauthenticationSteps
        }
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

// MARK: - Pairing guide

extension ShareCalStrings {
    /// The partner's name, or "TA" / "your partner" before it is known.
    func guidePartner(_ name: String?) -> String {
        name ?? text("your partner", "TA")
    }

    private func guidePartnerSubject(_ name: String?) -> String {
        name ?? text("Your partner", "TA")
    }

    func pairingGuideStepCounter(_ step: PairingGuideStep) -> String {
        text("Step \(step.rawValue) of 4", "第 \(step.rawValue) 步 · 共 4 步")
    }

    func pairingGuideStepLabel(_ step: PairingGuideStep, role: PairingGuideRole) -> String {
        switch (step, role) {
        case (.firstLinkSent, .initiator): text("You send", "你寄出")
        case (.firstLinkAccepted, .initiator): text("They accept", "TA 收下")
        case (.linkSentBack, .initiator): text("They send back", "TA 回寄")
        case (.linkBackAccepted, .initiator): text("You accept", "你收下")
        case (.firstLinkSent, .receiver): text("They send", "TA 寄出")
        case (.firstLinkAccepted, .receiver): text("You accept", "你收下")
        case (.linkSentBack, .receiver): text("You send back", "你回寄")
        case (.linkBackAccepted, .receiver): text("They accept", "TA 收下")
        }
    }

    func pairingGuideHeadline(_ state: PairingGuideState, partnerName: String?) -> String {
        let partner = guidePartner(partnerName)
        let subject = guidePartnerSubject(partnerName)
        switch (state.role, state.currentStep) {
        case (.initiator, .firstLinkSent):
            return text("Send your first letter", "寄出你的第一封信")
        case (.initiator, .firstLinkAccepted):
            return text("Invite sent. Waiting for \(partner) to open it", "邀请已寄出，等\(partner)\(Self.keepTogether("点开"))")
        case (.initiator, _):
            return text("\(subject) accepted. Waiting for one back", "\(subject)已收下你的信，等 TA \(Self.keepTogether("回寄一封"))")
        case (.receiver, .linkBackAccepted):
            return text("Sent back. Waiting for \(partner) to open it", "已回寄，等\(partner)\(Self.keepTogether("点开"))")
        case (.receiver, _):
            return text("Last step: send your link back", "最后一步：回寄你的信")
        }
    }

    func pairingGuideMessage(_ state: PairingGuideState, partnerName: String?) -> String {
        let partner = guidePartner(partnerName)
        switch (state.role, state.currentStep) {
        case (.initiator, .firstLinkSent):
            return text(
                "Your calendar stays in your own iCloud. Pairing means each of you sends the other a link: you send one, then \(partner) sends one back.",
                "你的日程只存在你自己的 iCloud 里。配对就是两个人互相寄一个链接：你先寄，\(partner)再回寄一个。"
            )
        case (.initiator, .firstLinkAccepted):
            return text(
                "Ask \(partner) to install and open OurDays once, then tap the link on iPhone. Nothing happened? Send it again.",
                "请\(partner)先安装并打开一次 OurDays，再在 iPhone 上点开链接。没反应可以再发一次。"
            )
        case (.initiator, _):
            return text(
                "Ask \(partner) to open OurDays and tap Send Invite Back on the Us tab. Open the link they send on your iPhone and you're paired.",
                "请\(partner)打开 OurDays，在「我们」点「回发邀请」。收到链接后在 iPhone 上点开，配对就完成了。"
            )
        case (.receiver, .linkBackAccepted):
            return text(
                "When \(partner) taps your link on their iPhone you're paired. Not working? Send it again.",
                "\(partner)在 iPhone 上点开你的链接，配对就完成了。不行的话可以再发一次。"
            )
        case (.receiver, _):
            return text(
                "You can already see \(partner)'s calendar; \(partner) can't see yours yet. Send your invite link back to finish pairing.",
                "你已经能看到\(partner)的日程，\(partner)还看不到你的。把你的邀请链接回发过去，配对就完成了。"
            )
        }
    }

    var pairingGuideResendButton: String { text("Send Again", "再发一次") }
    func pairingGuideRemindButton(_ partnerName: String?) -> String {
        text("Remind \(guidePartner(partnerName))", "提醒\(guidePartner(partnerName))回发")
    }
    func pairingGuideSendBackButton(_ partnerName: String?) -> String {
        text("Send Invite Back", "回发邀请给\(guidePartner(partnerName))")
    }
    var pairingGuideHelpLink: String { text("Link won't open?", "TA 打不开链接？") }

    var pairingGuideRemindMessage: String {
        text(
            "I accepted your OurDays invite, but I can't see your calendar yet. Open OurDays, tap Send Invite Back on the Us tab and send me the link.",
            "我已经收下你的 OurDays 邀请啦，但还看不到你的日程。打开 OurDays，在「我们」页点「回发邀请」，把链接发给我就好。"
        )
    }

    // Invite sheet

    func pairingInviteSheetTitle(isSendingBack: Bool) -> String {
        isSendingBack ? text("Send Your Letter Back", "回寄你的信") : text("Send Your First Letter", "寄出你的第一封信")
    }

    func pairingInviteSheetCounter(isSendingBack: Bool) -> String {
        isSendingBack ? text("Letter 2 of 2", "第 2 封 · 共 2 封") : text("Letter 1 of 2", "第 1 封 · 共 2 封")
    }

    func pairingInviteSheetMessage(isSendingBack: Bool, partnerName: String?) -> String {
        let partner = guidePartner(partnerName)
        return isSendingBack
            ? text(
                "This link carries the key to your calendar. Once \(partner) opens it, you're paired.",
                "链接里装着你日历的钥匙。\(partner)点开后，你们就配对好了。"
            )
            : text(
                "This link carries the key to your calendar. \(partner) sends one back after accepting, and then you're paired.",
                "链接里装着你日历的钥匙。\(partner)收下后也要回寄一封，你们才算配对。"
            )
    }

    var pairingInviteChecklistTitle: String { text("Ask them to do these first", "请对方先做好这三件事") }
    var pairingInviteChecklistInstall: String {
        text("Install OurDays on iPhone and open it once", "在 iPhone 上安装并打开一次 OurDays")
    }
    var pairingInviteChecklistICloud: String {
        text(
            "Keep iCloud on for OurDays (the app checks and shows the steps when it opens)",
            "iCloud 里 OurDays 的开关是打开的（App 打开时会自动检查并提示）"
        )
    }
    var pairingInviteChecklistWeChat: String {
        text(
            "Link in WeChat? Long-press › Copy, then paste it on the Us tab in OurDays. Tapping it inside WeChat opens a page asking for iCloud sign-in.",
            "链接在微信里？长按 › 复制，回到 OurDays「我们」页粘贴；在微信里直接点会跳到要求登录的网页。"
        )
    }
    var pairingInvitePreviewTitle: String { text("They'll receive", "对方会收到这段话") }
    var pairingInviteSendButton: String { text("Send Invite", "发送邀请") }
    var pairingInvitePreparingLink: String { text("Making your link...", "正在生成链接...") }
    /// The chip on the card once I have sent my link back: the status alone still reads
    /// "waiting for you to share", which contradicts the headline.
    var pairingGuideWaitingForPartnerToOpenChip: String { text("Waiting for Partner to Open", "等待对方点开") }
    var pairingGuideConfirmingAccept: String { text("Confirming with iCloud…", "正在和 iCloud 确认…") }

    /// Chinese wraps between any two characters; a word joiner keeps a short verb
    /// phrase such as 回寄 on one line in the large guide headlines.
    static func keepTogether(_ phrase: String) -> String {
        phrase.map(String.init).joined(separator: "\u{2060}")
    }

    func calendarAuthorizationStatusText(_ state: CalendarAuthorizationState) -> String {
        switch state {
        case .notDetermined: text("Not Requested", "尚未请求")
        case .denied: text("Denied", "已拒绝")
        case .restricted: text("Restricted", "受限制")
        case .writeOnly: text("Add Events Only", "仅可添加")
        case .fullAccess, .legacyAuthorized: text("Full Access", "完全访问")
        case .unknown: text("Unknown", "未知")
        }
    }
    var pairingInviteAppleSheetButton: String {
        text("Use Apple's Sharing Panel (Manage People)", "用苹果的共享面板（管理共享人）")
    }

    func pairingInviteMessage(appStoreURL: String, shareURL: String, isSendingBack: Bool) -> String {
        if isSendingBack {
            return text(
                "I accepted your OurDays invite. Here's mine back: open this link on your iPhone (in WeChat, copy it and paste it on the Us tab in OurDays):\n\(shareURL)",
                "我收下你的 OurDays 邀请啦，这是我的回信。在 iPhone 上点开这个链接（在微信里就复制，到 OurDays「我们」页粘贴）：\n\(shareURL)"
            )
        }
        return text(
            "Let's share our calendars with OurDays.\n1. Install it and open it once: \(appStoreURL)\n2. Copy this link and paste it on the Us tab in OurDays (or tap it on your iPhone): \(shareURL)\n3. After accepting, tap Send Invite Back and send it to me.",
            "我想和你一起用 OurDays 共享日程。\n① 先装 App 并打开一次：\(appStoreURL)\n② 复制这个链接，在 OurDays「我们」页粘贴（或在 iPhone 上直接点开）：\(shareURL)\n③ 收下后点「回发邀请」发给我。"
        )
    }

    // Share-back prompt

    func shareBackPromptTitle(_ partnerName: String?) -> String {
        text("You accepted \(guidePartner(partnerName))'s calendar", "你已收下\(guidePartner(partnerName))的日历")
    }
    var shareBackPromptWhyTitle: String { text("Why send one back?", "为什么还要回发？") }
    var shareBackPromptWhyMessage: String {
        text(
            "There's no server in between: each calendar lives in its owner's iCloud. You were handed a key; now hand one back.",
            "你们的日程各自存在自己的 iCloud 里，没有中间服务器。对方给了你一把钥匙，你也要给对方一把。"
        )
    }
    var shareBackPromptLaterButton: String { text("Later, from the Us tab", "稍后，在「我们」里继续") }

    // Calendar tab setup card

    var setupShareBackTitle: String { text("Send Your Invite Back", "回发你的邀请") }
    func setupShareBackMessage(_ partnerName: String?) -> String {
        let partner = guidePartner(partnerName)
        return text(
            "You accepted \(partner)'s calendar. Send your link back so \(partner) can see yours.",
            "你已收下\(partner)的日历。把你的链接回发过去，\(partner)就能看到你的日程。"
        )
    }

    // Link-won't-open help

    var inviteHelpTitle: String { text("Link asks for iCloud sign-in?", "点开链接要求登录 iCloud？") }
    var inviteHelpIntro: String {
        text(
            "The link is fine; it just went through the wrong door, the iCloud web page instead of OurDays. It's usually one of these.",
            "链接本身没问题。它只是走错了门：没进到 OurDays，而是进了 iCloud 网页。通常是下面三种原因之一。"
        )
    }
    var inviteHelpSwitchTitle: String { text("iCloud is off for OurDays", "OurDays 的 iCloud 开关是关的") }
    var inviteHelpSwitchMessage: String {
        text(
            "Settings › your name › iCloud › Saved to iCloud › See All › turn on OurDays. Notes has its own switch, so Notes links still open.",
            "设置 › 你的名字 › iCloud › 已存储到 iCloud › 显示全部 › 打开 OurDays。备忘录有自己的开关，所以备忘录链接照样能打开。"
        )
    }
    var inviteHelpWeChatTitle: String { text("Tapped inside WeChat", "在微信里点的") }
    var inviteHelpWeChatMessage: String {
        text(
            "WeChat's browser can't open apps. Long-press the link › Copy, then paste it on the Us tab in OurDays.",
            "微信的内置浏览器打不开 App。长按链接 › 复制，回到 OurDays「我们」页粘贴。"
        )
    }
    var inviteHelpInstallTitle: String { text("OurDays isn't installed yet", "还没装 OurDays") }
    var inviteHelpInstallMessage: String {
        text("Install it and open it once, then tap the link.", "先装好并打开一次，再点链接。")
    }
    var inviteHelpSendButton: String { text("Send These Tips", "把这段说明发给 TA") }

    func inviteHelpShareMessage(appStoreURL: String) -> String {
        text(
            "If my OurDays link asks you to sign in to iCloud:\n1. Install OurDays and open it once: \(appStoreURL)\n2. Settings › your name › iCloud › Saved to iCloud › See All › turn on OurDays\n3. Don't tap the link inside WeChat: copy it and paste it on the Us tab in OurDays.",
            "如果点开我的 OurDays 链接提示登录 iCloud：\n① 先装好并打开一次 OurDays：\(appStoreURL)\n② 设置 › 你的名字 › iCloud › 已存储到 iCloud › 显示全部 › 打开 OurDays\n③ 别在微信里直接点链接：复制后到 OurDays「我们」页粘贴。"
        )
    }
}
