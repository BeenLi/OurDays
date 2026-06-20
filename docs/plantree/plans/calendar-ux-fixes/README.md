# Plan: calendar-ux-fixes

「日历」体验三连修：joint 事件可评论、邀请乐观发送、今天 now-indicator 红线。

链接 baseline：[../../baseline/README.md](../../baseline/README.md)（权威 baseline 仍是仓库根 `CLAUDE.md`：两人制、userRecordID 身份、Plan enum 约定、单条 CKShare）。

## 范围（Scope）
本轮三个用户需求，作为同一 plan 的三个 phase（用户决定 2026-06-20，顺序 req3 → req2 → req1，由浅入深）：

- **req3 — 今天红线（now-indicator）**：打开「日历」tab 且当前展示的是今天时，在 `DayAlignedTimelineView` 里画一条横跨当前时刻的红线，左侧 rail 标注当前时刻；仿 iOS 自带日历。
- **req2 — 邀请乐观发送**：`EventDetailView.createInvite()` 当前要等 `await cloudKit.saveInvitationForSync` 整个 CloudKit 往返才显示「已发送」。改为本地保存后立即显示成功，上传转后台，失败由下次同步自愈。
- **req1 — joint 事件可评论（共享同一评论串）**：timeline 里绿色「共同日程」块（`DayTimelineJointEventBlock` / `JointEventCard`）当前无点击手势，点不开；且 joint 事件没有 `EventMirror`，评论系统按 `EventMirror.id` 索引，双方 mirror id 不同会导致评论串不对齐。需让 joint 事件可点开详情，并把评论串绑定到**双方都认得的锚**（候选：`invitation.id`），实现双方同串。

## Non-goals
- 不动两人制 / userRecordID 身份模型 / 单条 CKShare 架构（CLAUDE.md 铁律）。
- 不引入第三方依赖、不新增 SwiftData 实体（除非 req1 决定必须，见 open-questions）。
- 不做推送/系统通知（属 [notifications plan](../notifications/)）。

## 文件地图
- [roadmap.md](roadmap.md) — Done / In Progress / Next / Deferred + 三 phase 状态。
- [implementation-status.md](implementation-status.md) — 操作性 handoff（仅 In Progress 期间维护）。
- [open-questions.md](open-questions.md) — 未决问题（主要是 req1 评论路由）。
- topics/
  - [req3-now-indicator.md](topics/req3-now-indicator.md)
  - [req2-optimistic-invite.md](topics/req2-optimistic-invite.md)
  - [req1-joint-event-comments.md](topics/req1-joint-event-comments.md)
- decisions/
  - [0001-joint-event-comments-shared-thread.md](decisions/0001-joint-event-comments-shared-thread.md)
  - [0002-optimistic-invite-send.md](decisions/0002-optimistic-invite-send.md)

## 阅读路径
1. 本 README（范围/边界）。
2. `roadmap.md` 看 phase 状态与下一目标。
3. 做哪个 phase 读对应 `topics/req*.md`；动评论模型前先读 `decisions/0001`。
