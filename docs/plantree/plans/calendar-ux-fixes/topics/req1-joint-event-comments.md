# Topic: req1 — joint 事件可评论（共享同一评论串）

## 用户需求
「邀请的共同日历无法点开进一步操作，比如评论。」点开 joint（共同日程）事件后，双方应**共享同一条评论串**（用户选定，2026-06-20）。

## 代码现状（核实 2026-06-20）
- 绿色「共同日程」块 `DayTimelineJointEventBlock`（`RootView.swift:2115`）与 `JointEventCard`（`RootView.swift:2193`）**没有任何点击手势**，因此点不开。对比：普通 lane 事件 `DayTimelineLane`（`RootView.swift:2010`）有 `onSelect(event)`。
- joint 事件来源：`JointSchedulePlan.jointEvents`（`EventServices.swift:461`）由 **accepted `EventInvitation`** 生成，`JointScheduleEvent.id = invitation.id`，**不携带 `EventMirror`**（`EventServices.swift:450`）。
- 详情/评论 UI `EventDetailView`（`RootView.swift:2802`）只接 `EventMirror`，评论按 `EventComment.eventMirrorID == event.id` 过滤（`RootView.swift:2819`），`canComment` 仅排除 transient 显示 mirror（`Models.swift:1316`）。
- 评论同步：`saveCommentForSync`（`CloudKitCoupleSpaceService.swift:2171`）按 `CloudKitCommentWritePlan.destination` 路由（我的事件→private zone；对方事件→shared zone）。
- **关键不对齐**：joint 事件下，双方各有一份 `EventMirror`（mirror id 不同），评论按 mirror id 索引 ⇒ 各写各的，不同串。普通「对方事件」之所以能同串，是因为双方引用的是**同一个 owner 记录 id**；joint 没有这个共同 id —— 除了 `invitation.id`（双方 import 后 recordName 相同，见 `InvitationRecordMapper` / `CloudKitCoupleSpaceService.swift:869`）。

## 决策
见 [decisions/0001-joint-event-comments-shared-thread.md](../decisions/0001-joint-event-comments-shared-thread.md)：以 `invitation.id` 作为 joint 评论串的共享锚。

## 方案（草案，受 open-questions Q1/Q2/Q3 约束）
1. **可点击**：给 `DayTimelineJointEventBlock` / `JointEventCard` 加 tap → 通过回调上抛 `JointScheduleEvent`（`DayAlignedTimelineView` 与 `TwoColumnTimelineList` 都要透传 `onSelectJoint`）。
2. **详情入口**：让 `EventDetailView`（或抽出的通用详情）接受一个「评论锚」抽象，而不是写死 `EventMirror.id`。joint 情况锚 = `invitation.id`，并展示 invitation 的标题/时间/备注（joint 没有 mirror 的字段全来自 invitation）。
3. **评论锚 + 路由**：`EventComment.eventMirrorID = invitation.id`；写入/拉取走 invitation 实际所在 zone（见 open-question Q1，需 spike 确认双向可写可读）。
4. **保持两人制不变**：不新增实体、尽量不改部署 schema（Q2：必要时用 recordName 前缀区分，仿 `history-access-request:`）。

## 验收
- timeline 点绿色 joint 块 → 打开详情，能看到标题/时间，能输入并发送评论。
- A 在 joint 事件评论后，B 打开同一 joint 事件能看到 A 的评论并可回复，A 也能看到 B 的回复（**同一串**；两真机端到端验证）。
- 不影响普通事件评论既有行为。
- 单测：joint 锚解析（invitation→锚）、评论按 `invitation.id` 过滤、路由 Plan 的 destination 选择。

## 回归修复（2026-06-20，Codex stop-time review 发现）
- **Bug**：joint 评论锚到 `invitation.id`（无 `EventMirror`）。`ActivityFeedPlan.items` 旧逻辑 `guard let mirror = mirrorsByID[id]` 把 joint 评论**丢弃**，但 `unreadCount` 旧逻辑统计**所有**非自己评论 ⇒ 角标 +1 但「动态」tab 显示不出来（幽灵未读）。
- **修复**：`ActivityFeedPlan.items`/`unreadCount` 都改为按 **mirror ∪ invitation** 解析锚（`threadTitle`/`displayableAnchors`）。joint 评论用 invitation.title 进 feed 并计入未读；orphan（既无 mirror 也无 invitation）不再计入角标（顺带修了删 mirror 残留评论的旧隐患）。`ActivityTabView` 加 `selectedJointEvent` sheet，点 joint 动态行开 `JointEventDetailView`。`RootView` 补 `@Query mirrors` 给 `unreadActivityCount`。
- **单测**：`ActivityFeedPlanTests` 新增 `testSurfacesJointEventCommentsViaInvitationAndCountsThemUnread` + `testUnreadCountIgnoresUndisplayableOrphanComments`；其余 items/unreadCount 测试同步签名。
- **遗留（Deferred，非本次）**：`LocalNotificationPlan`「partner 评论了我的事件」要求 `mirror.ownerMemberID == currentMemberID`，joint 评论无 mirror ⇒ 目前**不发本地推送**。joint 推送语义（「我们的共同事件」）需单独设计，见 roadmap Deferred。

## 风险 / 注意
- **这是三个 phase 里最深的**：触碰评论同步与两人制路由，先解 open-questions Q1/Q2 的 spike 再写代码（避免 figure-it-out-while-coding）。
- `creatorMemberID` 用创建方词汇存储、接收方无法 match 真实 userRecordID（`EventServices.swift:467`）⇒ 路由不能依赖 member id 比对，要依赖 invitation 记录实际所在 zone。
- 未读/动态聚合不在本 phase（Deferred，复用 activity-feed）。
