# Roadmap — activity-feed

## Done（2026-06-14，全部 TDD 落地，206 单测通过）
- ✅ OQ1–OQ4 → [decisions/0002](decisions/0002-unread-interaction-organization.md)。
- ✅ `ActivityFeedPolicy` + `ActivityFeedItem`（`Models.swift`）+ 6 个单测（`ActivityFeedPolicyTests`）。
- ✅ `SettingsStore.lastSeenActivityAt`（UserDefaults，per-device）+ 进入 tab `markActivitySeen()` 置 now。
- ✅ `ShareCalTab.activity` + `ActivityTabView`/`ActivityFeedRow`（`RootView.swift`）+ `.badge(unreadActivityCount)` + 本地化字符串；行点击 sheet → `EventDetailView`。
- ✅ 切到 activity tab 触发节流同步（`onChange(of: selectedTab)`）。

## In Progress
- （无）

## Next
- （无 —— 已完成）

## Deferred
- D1 动态流内「快速回复」内联输入（OQ2 后续增强）。
- D2 已读状态跨自己多设备同步（v1 为本地 per-device）。
- D3 系统级推送 → 见 [../notifications/](../notifications/)（phase 2）。
