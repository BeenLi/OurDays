# Plan: comment-visibility —— 让评论在「日历」tab 可见 / 可操作

## 范围
两个相干需求，共享同一底层「显示事件 → 评论锚 key」解析：
1. **req1 — 评论红点**：日历 tab 里，任何有评论的日程（我的 / 对方的 / 共同日程）在事件块上显示一个小红点。
2. **req2 — 我的事件可看/可回评论**：点开「我自己的日程」详情时，除保留「邀请对方」外，在下方显示评论串（含对方对我事件的评论），本方可继续回复。

## Non-goals
- 不改两人制身份模型、不新增 SwiftData 实体、不改部署 CloudKit schema（复用现有 `EventComment` + 锚路由）。
- 不改「动态」tab 的未读聚合逻辑（`ActivityFeedPlan`）；红点语义是「有评论」而非「未读」（见 decision 0001）。
- 不做评论编辑/富文本/@提醒等增强。

## 根因（核实 2026-07-03，见 topics）
日历里「我的事件」来自 `localDisplayMirrors`（transient display mirror，`id` 带 `display:` 前缀、`cloudKitRecordName=nil`，`RootView.swift:882` / `Models.swift:1324`），「对方事件」来自真实持久化 mirror。评论开关 `EventDetailInteractionPlan.canComment` 排除 `display:` 前缀（`Models.swift:1362`）⇒ 点开我的事件永远只有「邀请对方」、看不到对方写进我 private zone 的评论。这是 req2 的根因，也是 req1 里「我的事件红点」需要 display→real mirror 映射的原因。

## 文件地图
- [roadmap.md](roadmap.md) — 分期状态
- [open-questions.md](open-questions.md) — 未决 / 待验证
- topics/[req1-comment-dot.md](topics/req1-comment-dot.md) · [req2-own-event-comments.md](topics/req2-own-event-comments.md)
- decisions/[0001-dot-marks-any-comment.md](decisions/0001-dot-marks-any-comment.md) · [0002-own-event-detail-resolves-persisted-mirror.md](decisions/0002-own-event-detail-resolves-persisted-mirror.md)

## 权威
本 plan 服从仓库 `CLAUDE.md` 铁律与 [baseline](../../baseline/README.md)。冲突时以代码 + `CLAUDE.md` 为准。
