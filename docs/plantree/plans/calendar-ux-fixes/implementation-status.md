# Implementation Status — calendar-ux-fixes

> 三个 phase 代码落地 + 两真机 e2e 跑通；剩可选肉眼/离线分支验收。

- **Current Phase**: 基本完成。3 phase 代码 + 单测 + 两真机端到端（joint 评论对称 + 邀请跨设备 seed/accept）均绿。
- **Next Target**:（可选）肉眼确认 Phase 1 红线；离线乐观发送自愈分支单独验；周视图 joint 点击（Deferred）。
- **Harness 扩展（2026-06-20）**：`CoupleCalendarApp.swift` 新增 4 个诊断 launch arg（seed/accept invitation、add/probe joint comment）；`Scripts/dev-pairing-smoke.sh` 加步骤 8-9 断言对称性。`SMOKE3_EXIT=0 ✅ PASS`。
- **回归修复（2026-06-20，Codex review）**：joint 评论原会刷未读角标却进不了「动态」tab。`ActivityFeedPlan.items`/`unreadCount` 改为按 mirror∪invitation 解析；`ActivityTabView` 可开 `JointEventDetailView`；`RootView` 补 `@Query mirrors`。新增 2 个单测，全量 `CoupleCalendarTests` 仍 **TEST SUCCEEDED**。详见 [topics/req1 回归修复](topics/req1-joint-event-comments.md#回归修复2026-06-20codex-stop-time-review-发现)。
- **Last Landed**: 2026-06-20，全量 `CoupleCalendarTests` **TEST SUCCEEDED**（含新 `DayTimelineNowIndicatorPlanTests` 3、`InvitationReuploadPlan.creationsNeedingReupload` 2、`EventCommentAnchorPlanTests` 1）。
  - Phase 1：`Models.swift`（`DayTimelineNowIndicatorPlan`+struct）、`RootView.swift`（`DayTimelineNowIndicatorOverlay` 接入 `DayAlignedTimelineView`）。
  - Phase 2：`Models.swift`（`EventInvitation.needsCloudKitUpload` 本地字段、`InvitationReuploadPlan.creationsNeedingReupload`）、`AppServices.swift`（foregroundSync 自愈段）、`RootView.swift`（`createInvite()` 乐观化 + 去掉 `isSendingInvite`）。
  - Phase 3：`Models.swift`（`EventCommentAnchor`+`EventCommentAnchorPlan`）、`RootView.swift`（`EventCommentsSection` 抽出、`JointEventDetailView`、joint 块 `onTapGesture`、`CalendarTabView` sheet）。
- **Active TODO**:
  1. 两真机：joint 评论 A↔B 同串 + 断网乐观发送→恢复自愈（[open-questions V1](open-questions.md)）。
  2. 肉眼：Phase 1 红线。
  3. （Deferred）周视图 joint 点击（[open-questions V2](open-questions.md)）。
- **Blocked By**: 无（代码层）。验收为人工/真机步骤。
- **Last Verified**: 2026-06-20 全量单测通过 + 全量 build SUCCEEDED。CloudKit 真实往返未验证（见 V1）。
