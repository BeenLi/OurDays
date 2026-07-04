# Open Questions — comment-visibility

## 待验证（实现后）
- **V1a — 回归门（两真机 smoke）**：✅ **PASS（2026-07-04，run3）**。iCloud 会话恢复后（写探针 `writeProbe save succeeded` default+CoupleSpace zone 5s 内过），`SHARE_URL_TIMEOUT=900 Scripts/dev-pairing-smoke.sh --skip-build` 全绿：互相配对（owner `_441f89d3…` ↔ partner `_2be1ca3a…`）、双向同步（13/12 records）、joint 评论双向同串、两个 XCUITest（对方日历画出 owner 事件；joint 绿块点开评论串）。**证明本次改动未破坏真机渲染/同步/joint 评论**（两个 XCUITest 驱动的正是改过签名的 `CalendarTabView`/leaf 视图/`EventDetailView`）。
  - 曾阻断（已解决）：2026-07-04 早先 CloudKit 写通道不通（`CKError 20 operationCancelled`，`modifyRecords` 超时）——环境/iCloud 会话问题，非代码；用户重登 iCloud 后恢复。
- **V1b — 新路径直接验证（未做，可选）**：smoke 脚本的评论诊断**只覆盖 joint 事件**，未直接驱动本次两条**新**路径：①对方评论我的**普通**事件 → 我日历出现红点；②我的**普通**事件详情显示评论区并可回复。
  - 间接覆盖：决策逻辑（`EventCommentIndicatorPlan` / `EventDetailMirrorResolutionPlan`）已单测；评论 `saveCommentForSync` 往返由 joint 对称性 + 写探针证明；改过的视图由两个 XCUITest 驱动。
  - 若要直接验：新增「本地种子普通事件评论」launch arg + 截图/XCUITest（纯客户端渲染，不依赖分享）。列为可选。

## 已解决
- **Q1 — 红点视觉规格** → 落地为 topTrailing 8pt 红色圆点（`CommentIndicatorDot`，描边同背景色以在彩色块上清晰）。装饰性、`accessibilityHidden`（VoiceOver 语义见 roadmap Deferred）。
- **Q2 — 第二处详情宿主**（`RootView.swift:3044`）→ 该处是 `ActivityTabView`（动态 tab），本身即评论活动流，非日历面，**不需要红点**。已解决。
- 红点语义（任何评论 vs 未读）→ [decision 0001](decisions/0001-dot-marks-any-comment.md)（任何评论）。
- 我的事件详情「邀请」去留 → [decision 0002](decisions/0002-own-event-detail-resolves-persisted-mirror.md)（保留 + 下方加评论）。
