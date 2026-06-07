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
}

enum AppLanguagePreference {
    static let defaultLanguage: AppLanguage = .english
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
    var noSharedSchedulesTitle: String { text("No shared schedules", "暂无共享日程") }
    var noSharedSchedulesDescription: String {
        text("Preview a paired schedule or choose calendars in Settings.", "预览双方日程，或在设置中选择要共享的日历。")
    }
    var loadSampleScheduleButton: String { text("Load Sample Schedule", "加载示例日程") }
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
    var membersSection: String { text("Members", "成员") }
    var myDisplayNamePlaceholder: String { text("My display name", "我的显示名称") }
    var partnerDisplayNamePlaceholder: String { text("Partner display name", "对方显示名称") }
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
    var iCloudShareSection: String { text("iCloud Share", "iCloud 共享") }
    var createsICloudShareDescription: String {
        text("Creates an iCloud share for your partner.", "为对方创建 iCloud 共享。")
    }
    var iCloudSharingUnavailableLocalBuild: String {
        text("iCloud sharing is unavailable in this local build.", "当前本地构建不可用 iCloud 共享。")
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

    func createOrOpenShareButton(isPreparing: Bool) -> String {
        isPreparing ? text("Preparing Share...", "正在准备共享...") : text("Create or Open Share", "创建或打开共享")
    }

    func checkICloudStatusButton(isChecking: Bool) -> String {
        isChecking ? text("Checking iCloud Status...", "正在检查 iCloud 状态...") : text("Check iCloud Status", "检查 iCloud 状态")
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

    func invitationStatusTitle(for status: InvitationStatus) -> String {
        switch status {
        case .pending: text("Pending", "待处理")
        case .accepted: text("Accepted", "已接受")
        case .declined: text("Declined", "已拒绝")
        case .canceled: text("Canceled", "已取消")
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

    static func markAccepted(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(true, forKey: pendingSyncKey)
        notificationCenter.post(name: notificationName, object: nil)
    }

    static func consumePending(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: pendingSyncKey) else { return false }
        defaults.set(false, forKey: pendingSyncKey)
        return true
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

enum SyncPhase: String {
    case idle
    case syncing
    case failed
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

enum ShareCalModelContainer {
    static let schema = Schema([
        CoupleSpace.self,
        MemberProfile.self,
        EventMirror.self,
        LocalEventShadow.self,
        EventInvitation.self,
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
