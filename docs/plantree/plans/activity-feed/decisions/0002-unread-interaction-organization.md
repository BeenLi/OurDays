# Decision 0002 — 未读 / 互动 / 组织 / 范围 / 角标

- **日期**：2026-06-14
- **状态**：Accepted（用户确认 OQ2/OQ3a/OQ3b；OQ1/OQ4 由实现侧依据代码事实定，用户未反对）

## OQ1 未读机制 → 本地 `lastSeenActivityAt`（不复用 `isRead`）
- 在 `SettingsStore`（UserDefaults-backed）新增 `lastSeenActivityAt: Date?`。
- 未读 = 满足全部：`authorMemberID != currentMemberID`（对方发的）、`deletedAt == nil`、`createdAt > lastSeenActivityAt`。
- 查看动态 tab 时把 `lastSeenActivityAt` 置为 `now`。
- **不**用 `EventComment.isRead`：它是 CloudKit **同步**字段、导入时被直接覆盖（`AppServices.swift:749`、mapper `CloudKitCoupleSpaceService.swift:976/994`），且 `CommentService.markRead`（`EventServices.swift:733`）**从未被调用**。用它会把已读状态串到对方。
- **不**用 `MemberProfile.lastSeenAt`（那是对方在线/presence 语义，`Models.swift:1915`）。
- 取舍：已读状态**按设备本地**，不跨自己的多设备同步 —— v1 接受。

## OQ2 互动形式 → 先跳转，后续内联
- v1：动态行点击 → `NavigationLink` 进入现有事件详情评论区（`RootView.swift:2814` Section + 输入/删除/`syncOnOpenIfNeeded`），复用现成逻辑，不另造输入组件。
- 后续增强（Deferred）：动态流内「快速回复」内联输入。

## OQ3a 组织 → 按事件分组的会话列表
- 每个有评论的事件一行：最新评论摘要 + 作者 + 时间 + 未读点；按该事件最新评论时间倒序。
- 点击进入该事件的评论线（衔接 OQ2 跳转）。

## OQ3b 范围 → 所有有评论的事件（双向）
- 列表纳入任意方向有评论的事件（对方评论我的 + 我评论对方的）。
- 但未读角标只计 OQ1 定义的「对方发的、晚于 lastSeen」的评论；我自己发的不算未读。

## OQ4 角标并存 → 两套独立角标，互不重叠
- 邀请 tab 继续用 `PendingActionBadgePolicy`（邀请 + 历史访问请求），不动。
- 动态 tab 用新的 `ActivityFeedPolicy.unreadCount`。评论从不在邀请角标里，结构上不会重复计数。
