# Topic: req2 —— 我的事件详情可看/可回评论

## 用户需求
「对于对方评论我的日程，点开后不应该只有『邀请对方』，而是显示对方的评论，并且本方可以在下面接着评论。」
- 决策（用户选定 2026-07-03）：**保留「邀请对方」，在其下方新增评论串**。见 [decision 0002](../decisions/0002-own-event-detail-resolves-persisted-mirror.md)。

## 根因（核实 2026-07-03）
- 日历里「我自己的事件」= `localDisplayMirrors`（display mirror，`id="display:..."`，`cloudKitRecordName=nil`）。tap → `selectedEvent`（`RootView.swift:1009,1046`）→ `EventDetailView(event:)`。
- `EventDetailView`（`RootView.swift:2781`）：详情 section + 「邀请对方」section（`:2813`，普通事件恒显）+ 评论 section（`:2836`，仅当 `EventDetailInteractionPlan.canComment(on:)` 为真）。
- `canComment`（`Models.swift:1361`）= `!id.hasPrefix("display:")` ⇒ **我的 display mirror 恒 false ⇒ 我永远看不到评论区**。而对方评论我的事件时，评论按 `CloudKitCommentWritePolicy.destination`（对方视角=我的事件→写入我的 private zone），我 `fetchEventComments` 能拉回，只是 UI 被 `canComment` 门槛挡住。
- 对比：点对方事件（真实 mirror）→ `canComment` true → 评论区正常。这是不对称 bug。

## 方案
1. `EventDetailView` 内部解析持久化孪生：已有 `@Query mirrors`(`:2786`)。若传入 `event.id` 带 `display:` 前缀，按 `mirrorKey` 找 `!id.hasPrefix("display:")` 的真实 mirror；否则用自身。
2. 放宽评论门槛：评论区显示条件从「非 display 前缀」改为「解析到持久化孪生」。anchor 用**解析出的真实 mirror** 建（`EventCommentAnchorPolicy.anchor(forMirror:)`），拿到真实 `id` + `recordName` 供写入路由。
3. 「邀请对方」section 保持不变，评论 section 显示在其下方（复用既有 `EventCommentsSection`，`RootView.swift:2682`——发送走 `saveCommentForSync`，路由：我的事件→我的 private zone，对方读回）。
4. 边界：事件尚未同步（无持久化孪生）⇒ 不显示评论区（此时对方也不可能已评论）。可选「同步后可评论」提示列 Deferred。

## 验收
- 对方在 A 的普通事件上评论 → A 在日历点开该事件，能看到对方评论并回复；对方能看到 A 的回复（同串，两真机验证）。
- 「邀请对方」按钮仍在、行为不变。
- 未同步的新建事件点开不崩、只显示邀请（无评论区）。
- 单测：`canComment`/门槛改判（display+存在孪生→可评论；display+无孪生→不可）；anchor 用真实 id。

## 风险 / 注意
- 别用 display mirror 的 `id` 建 anchor（会写错 key、路由缺 recordName）；必须用解析后的真实 mirror。
- 详情头部字段（标题/时间）用 display 或真实 mirror 皆可（内容一致）；anchor 必须用真实 mirror。
- 与 req1 复用同一「display→real by mirrorKey」解析——实现时抽同一处，避免两份逻辑漂移。
