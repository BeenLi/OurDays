# Roadmap — calendar-ux-fixes

顺序由用户定（2026-06-20）：req3 → req2 → req1（由浅入深）。每个 phase 遵循项目 Plan-enum 约定：纯逻辑进 `enum ...Plan` + 单测，View/Service 保持薄。

## Done（代码全部落地，全量 `CoupleCalendarTests` TEST SUCCEEDED，2026-06-20）
- **Phase 1 — req3 今天 now-indicator 红线** ✅
  - `DayTimelineNowIndicatorPlan`（纯函数）+ `DayTimelineNowIndicatorOverlay`（`TimelineView(.everyMinute)`）接入 `DayAlignedTimelineView`。3 单测。见 [topics/req3](topics/req3-now-indicator.md)。
- **Phase 2 — req2 邀请乐观发送** ✅（[decisions/0002](decisions/0002-optimistic-invite-send.md)）
  - 模型加本地 `needsCloudKitUpload`；`InvitationReuploadPlan.creationsNeedingReupload` + 接入 `foregroundSync`；`createInvite()` 乐观化（本地 save 即显示「已发送」，上传转后台，失败保留 flag 下次自愈）。2 单测。
- **Phase 3 — req1 joint 事件可评论（共享同一评论串）** ✅（[decisions/0001](decisions/0001-joint-event-comments-shared-thread.md)）
  - `EventCommentAnchor`/`EventCommentAnchorPlan` + 抽出 `EventCommentsSection` + 新 `JointEventDetailView`；日视图 joint 块加 `onTapGesture`；`CalendarTabView` `selectedJointEvent` sheet。1 单测（锚+路由）。

## Verify
- ✅ **两真机端到端（2026-06-20）**：扩展 `dev-pairing-smoke.sh`（+4 诊断 arg + 步骤 8-9）真机跑通 joint 评论对称性（owner 评论↔partner 回复双方同串）+ 邀请跨设备 seed→accept。`SMOKE3_EXIT=0 ✅ PASS`。见 [open-questions V1](open-questions.md)。
- ⏳ **肉眼确认**：Phase 1 红线位置/翻天消失（UI 视觉，单测+build 已绿；非阻塞）。
- ⏳ **未单独验**：Phase 2「断网乐观发送→恢复自愈」的离线路径（自愈逻辑有单测 `creationsNeedingReupload`；在线 seed→accept 已真机过，离线分支未单独跑）。

## Deferred
- **周视图 joint 事件点击**（[open-questions V2](open-questions.md)）：本轮只接日视图；周视图 `WeekAgendaItemCard` 仍不可点。
- **joint 评论的本地推送**：`LocalNotificationPlan` 现要求评论事件 `mirror.ownerMemberID == currentMemberID`，joint 评论无 mirror ⇒ 不发推送。需为「共同事件评论」设计推送语义后再加。见 [topics/req1](topics/req1-joint-event-comments.md#遗留deferred非本次)。
- joint 评论已进「动态」tab + 角标（2026-06-20 回归修复）；更复杂的动态流聚合仍归 [activity-feed plan](../activity-feed/)。
