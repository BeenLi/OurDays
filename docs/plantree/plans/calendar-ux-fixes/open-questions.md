# Open Questions — calendar-ux-fixes

只放未决问题。已解决的移走（记录在 decisions / topics）。

## 已解决（2026-06-20）
- **Q4（Phase 2 自愈机制）** → 用户选 (A) 本地 `needsCloudKitUpload` 标记。已实现，见 [decisions/0002](decisions/0002-optimistic-invite-send.md)。
- **Q1/Q2（Phase 3 joint 评论路由）** → spike 结论：`fetchEventComments` 同时读 **private + shared zone**（`CloudKitCoupleSpaceService.swift:2480`）。以 `invitation.id` 为评论锚、按 `invitation.creatorMemberID` 路由（creator→private zone，partner→creator 的 shared zone），双方都能读回两个 zone ⇒ 评论串对称。无需新 record type / schema 改动。已实现，见 [decisions/0001](decisions/0001-joint-event-comments-shared-thread.md) 与 [topics/req1](topics/req1-joint-event-comments.md)。
- **Q3（joint 详情 UI）** → 新建 `JointEventDetailView` + 抽出可复用 `EventCommentsSection`（由 `EventCommentAnchor` 参数化），`EventDetailView` 也改用它，去重。

## 仍未决 / 后续
- ~~**V1：两真机端到端验证 joint 评论对称性。**~~ ✅ **已完成（2026-06-20）**。用户重登 iCloud 后，扩展 `Scripts/dev-pairing-smoke.sh` 新增 4 个诊断 launch arg（`-ShareCalSeedInvitation` / `-ShareCalAcceptInvitation` / `-ShareCalAddJointComment <body>` / `-ShareCalProbeJointComments`，实现于 `CoupleCalendarApp.swift` `ShareCalLaunchDiagnostics`）+ 新增脚本步骤 8-9。真机跑通：owner 建邀请→partner 接受（joint 建立、未被自愈误删）→owner 评论→**partner probe 看到 owner 评论**→partner 回复→**owner probe 同时看到两条**（对称）。`SMOKE3_EXIT=0 ✅ PASS`。
  - 历史：6/20 首次受阻是环境问题（owner 模拟器 iCloud 掉登录致 CloudKit 写超时，`prepareShare`/writeProbe 均 stall，host 网络正常）；与本 plan 代码无关，重登后同二进制即通过。
- **V2：周视图 joint 事件点击。** 本轮只接了**日视图**绿色 joint 块的点击（用户报告的主路径）。周视图 `WeekAgendaDaySection` 把 joint 项渲染为不可点的 `WeekAgendaItemCard`（`item.mirrorID == nil`）。若要周视图也能点开 joint 评论，需让 `WeekAgendaItem` 暴露 joint/ invitation id 并接 `onSelectJoint`。见 roadmap Deferred。
