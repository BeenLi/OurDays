# Decision 0001 — joint 事件评论：双方共享同一评论串，锚定 invitation.id

- **日期**: 2026-06-20
- **状态**: Accepted（用户在澄清问题中选定「双方共享同一评论串（推荐）」）
- **范围**: req1 / Phase 3

## 背景
joint（共同日程）事件由 accepted `EventInvitation` 派生，不携带 `EventMirror`；而评论系统按 `EventMirror.id` 索引、按事件归属路由 zone。双方各有一份 mirror（id 不同），naive 实现会导致评论各写各的、不同串。

## 决策
1. joint 事件可点开详情并支持评论。
2. joint 评论串绑定到**双方都认得的共享锚 `invitation.id`**（双方 import 后 recordName 一致），而非各自的 mirror id —— 保证 A/B 看到并能回复同一条评论串。

## 备选与理由
- **(选中) 锚定 invitation.id**：唯一双方一致的标识；不需新增实体，体验正确（对称同串）。代价：评论路由需按 invitation 实际所在 zone 决定（见 open-questions Q1），工作量较大。
- (否决) 锚定「我的 mirror」：改动小但评论不对称，对方看不到——与用户诉求相悖。
- (否决) 新建共享「canonical mirror」实体：引入 schema/实体复杂度，违背 non-goals。

## 影响
- `EventDetailView`（或抽出的详情）需支持「评论锚」抽象，不再写死 `EventMirror.id`。
- 评论 fetch/save 需支持以 `invitation.id` 为 key、按 invitation zone 路由。
- 不新增 SwiftData 实体；尽量不改部署 schema（必要时用 recordName 前缀区分，仿 `history-access-request:`）。

## Spike 结论 + 落地（2026-06-20，已实现）
- **路由可行**：`fetchEventComments` 同时读 private + shared zone（`CloudKitCoupleSpaceService.swift:2480`）。以 `EventCommentAnchorPlan.anchor(forInvitation:)` 得 `key=invitation.id`、`ownerMemberID=invitation.creatorMemberID`、`recordName=invitation.id`；`CloudKitCommentWritePlan.destination` 用 ownerMemberID 与 currentMemberID 比相等：creator→private zone，partner→creator 的 shared zone。双方读回两 zone ⇒ 对称。**无需新 record type / schema 改动**。
- `creatorMemberID` 接收方无法解读不影响路由——只用到「是否等于自己」的相等判断。
- **代码**：`Models.swift`（`EventCommentAnchor` + `EventCommentAnchorPlan`）、`RootView.swift`（抽出 `EventCommentsSection`、新增 `JointEventDetailView`、日视图 joint 块加 `onTapGesture`、`CalendarTabView` 加 `selectedJointEvent` sheet）。
- **单测**：`EventCommentAnchorPlanTests`（锚映射 + 双角色 destination）。全量 `CoupleCalendarTests` TEST SUCCEEDED。
- **未完**：两真机端到端对称性验证（见 open-questions V1）。
