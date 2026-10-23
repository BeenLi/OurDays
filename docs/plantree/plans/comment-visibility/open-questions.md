# Open Questions — comment-visibility

## 待验证（实现后）
- **V1a — 回归门（两真机 smoke）**：✅ **PASS（2026-07-04，run3）**。iCloud 会话恢复后（写探针 `writeProbe save succeeded` default+CoupleSpace zone 5s 内过），`SHARE_URL_TIMEOUT=900 Scripts/dev-pairing-smoke.sh --skip-build` 全绿：互相配对（owner `_441f89d3…` ↔ partner `_2be1ca3a…`）、双向同步（13/12 records）、joint 评论双向同串、两个 XCUITest（对方日历画出 owner 事件；joint 绿块点开评论串）。**证明本次改动未破坏真机渲染/同步/joint 评论**（两个 XCUITest 驱动的正是改过签名的 `CalendarTabView`/leaf 视图/`EventDetailView`）。
  - 曾阻断（已解决）：2026-07-04 早先 CloudKit 写通道不通（`CKError 20 operationCancelled`，`modifyRecords` 超时）——环境/iCloud 会话问题，非代码；用户重登 iCloud 后恢复。
- **V1b — 新路径直接验证**：✅ **PASS（2026-07-04）**。新增 `-ShareCalSeedOrdinaryComment <body>` 诊断（`CoupleCalendarApp.swift` 的 `seedOrdinaryComment`：造一个**全新普通事件** "V1B Ordinary Event"（无对应 invitation，故不被当 joint）→ 同步得到我的持久化 mirror → 挂一条 `_smoke_partner` 作者的评论并上传）+ 新 XCUITest `testOwnOrdinaryEventShowsPartnerCommentAndReply`。
  - **req1 红点**：截图确认 "V1B Ordinary Event"（我的普通事件，有对方评论）右上角红点亮；joint 事件（有评论）也亮；对方无评论事件不亮（阴性对照正确）。
  - **req2 详情**：XCUITest 断言通过——点开我的普通事件详情同时显示「邀请对方」+ 对方评论 "V1B partner comment"（作者 SmokePartner）+「添加评论」回复框。截图佐证。
  - 关键点：必须用**没有 invitation 的新普通事件**验，否则会被 `JointSchedulePolicy.ordinaryMirrors` 当 joint 处理、走 `JointEventDetailView`，绕开本次改的 `EventDetailView` 路径。
  - 证据截图：[req1 红点](screenshots/req1-red-dot-on-my-event.png) · [req2 详情评论区](screenshots/req2-own-event-comment-thread.png)。

## 已解决
- **Q1 — 红点视觉规格** → 落地为 topTrailing 8pt 红色圆点（`CommentIndicatorDot`，描边同背景色以在彩色块上清晰）。装饰性、`accessibilityHidden`（VoiceOver 语义见 roadmap Deferred）。
- **Q2 — 第二处详情宿主**（`RootView.swift:3044`）→ 该处是 `ActivityTabView`（动态 tab），本身即评论活动流，非日历面，**不需要红点**。已解决。
- 红点语义（任何评论 vs 未读）→ [decision 0001](decisions/0001-dot-marks-any-comment.md)（任何评论）。
- 我的事件详情「邀请」去留 → [decision 0002](decisions/0002-own-event-detail-resolves-persisted-mirror.md)（保留 + 下方加评论）。
