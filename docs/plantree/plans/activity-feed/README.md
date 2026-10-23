# Plan: activity-feed（「动态」tab）

由 [idea-001](../../ideas/inbox.md) 提升而来。Baseline：[../../baseline/README.md](../../baseline/README.md)。

## Scope
在「日历」和「邀请」之间新增「动态」tab，作为**评论互动**surface：聚合对方对我日程的评论与我的回复，并支持继续互动。**邀请 tab 保留不变**。

## Non-goals
- 不把邀请 / 历史访问请求并入动态流（见 [decisions/0001-feed-scope.md](decisions/0001-feed-scope.md)）。
- 不在本 plan 做系统级推送（见 [../notifications/](../notifications/)，phase 2）。

## File map
- [roadmap.md](roadmap.md) — 阶段状态
- [decisions/0001-feed-scope.md](decisions/0001-feed-scope.md) — 内容范围 = 仅评论互动
- [decisions/0002-unread-interaction-organization.md](decisions/0002-unread-interaction-organization.md) — 未读/互动/组织/范围/角标

## Status
- Status: **✅ Done / Landed**（2026-06-14）
- Evidence: 6 个 `ActivityFeedPolicyTests` 通过；全套 215 单测通过；模拟器启动验证 tab 顺序为 日历→动态→邀请→设置，无崩溃。
- Current Phase: landed；随 v1.3 上架。1.5 的 UI 重设计（#3）把动态流改成按天分组的聊天卡片，逻辑不变（见 [ui-redesign](../ui-redesign/)）。

## Resolved questions（见 decision 0002）
- OQ1 未读 → 本地 `SettingsStore.lastSeenActivityAt`；不复用同步的 `isRead`，不复用 `MemberProfile.lastSeenAt`。
- OQ2 互动 → v1 点击跳转事件详情评论区；内联回复后续。
- OQ3a 组织 → 按事件分组的会话列表，最新评论时间倒序。
- OQ3b 范围 → 所有有评论的事件（双向）；未读只计对方发的、晚于 lastSeen。
- OQ4 角标 → 动态 `ActivityFeedPolicy.unreadCount` 与邀请 `PendingActionBadgePolicy` 独立，无重叠。

## 实现切口（遵循 Policy enum + TDD 约定）
1. `ActivityFeedPolicy`（纯静态）：把 `[EventComment]` + `[EventMirror]` + `currentMemberID` + `lastSeenActivityAt` → 按事件分组、时间倒序的会话条目 + `unreadCount`。先写单测。
2. `SettingsStore.lastSeenActivityAt`（UserDefaults）+ 进入 tab 时置 now。
3. `ShareCalTab.activity` case + `TabView` 第二项（`RootView.swift:69`，calendar 与 invites 之间）+ `.badge(unreadCount)`。
4. `ActivityTabView`：渲染会话列表，行 `NavigationLink` → 现有事件详情评论区。
5. 本地化字符串（`ShareCalStrings.text(en, zh)`，如 `activityTab`）。
