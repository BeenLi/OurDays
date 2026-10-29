# Decision 0002 —— 我的事件详情：解析持久化孪生以放开评论；保留「邀请对方」

- **日期**: 2026-07-03
- **状态**: Accepted（用户在澄清问题中选定「保留邀请 + 下方加评论串」）
- **范围**: req2

## 背景
日历里「我的事件」是 transient display mirror（`id="display:..."`），`canComment` 排除 display 前缀，导致点开我的事件恒只有「邀请对方」、看不到对方写入我 private zone 的评论。见 topic req2。

## 决策
1. `EventDetailView` 内部把（可能是 display 的）传入事件按 `mirrorKey` **解析为持久化孪生**，用真实 mirror 建评论锚（拿到真实 `id` + `cloudKitRecordName` 供写入路由）。
2. 评论区显示条件从「非 display 前缀」改为「**存在持久化孪生**」。
3. **保留**「邀请对方」section 原样，评论串显示在其**下方**（邀请=升级为共同日程，与评论正交，两者并存）。

## 备选与理由
- **(选中) 详情内解析孪生 + 放宽 canComment**：改动集中在 `EventDetailView`（已有 `@Query mirrors`），tap/sheet 流程不动；与 req1 复用同一 display→real 解析。
- (否决) tap 时先把 display mirror 换成真实 mirror 再 present：逻辑分散到多个 `onSelect` 站点（day/week/两处 sheet 宿主），易漏、易漂移。
- (否决) 让 display mirror 直接携带真实 id：破坏「display mirror 是纯 EventKit 派生、无 CloudKit 绑定」的不变量，风险外溢到同步管线。

## 影响
- `EventDetailInteractionPlan.canComment` 语义改变（需同步改单测）。
- 未同步（无孪生）的我方新建事件：不显示评论区（对方此时也不可能已评论）；「同步后可评论」提示列 Deferred。
- 不改评论写入/路由（`CloudKitCommentWritePolicy`）、不改 schema。

## 落地（2026-07-04，已实现）
- 比「放宽 `canComment`」更进一步：直接**移除** `EventDetailInteractionPlan.canComment`，新增 `EventDetailMirrorResolutionPolicy.persistedTwin(for:in:)`（`Models.swift`）。`EventDetailView` 用 `if let commentMirror = persistedTwin(for: event, in: mirrors)` **一步合并**「是否显示评论区」与「评论锚绑定」——门槛=孪生存在，锚=真实 mirror，杜绝「用 display id 建错锚」的整类 bug。real mirror 解析为自身；display mirror 按 `mirrorKey` 找非-display 孪生；无孪生返回 nil。
- 单测：`EventDetailMirrorResolutionPolicyTests`（real→自身 / display→孪生 / 无孪生→nil）；原 `canComment` 的「孤立 display mirror 不可评论」断言迁移为 `XCTAssertNil(persistedTwin(..., in: []))`。
- 全量 `CoupleCalendarTests` TEST SUCCEEDED。**未完**：两真机 e2e（见 open-questions V1）。
