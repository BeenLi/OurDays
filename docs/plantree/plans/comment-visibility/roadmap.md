# Roadmap — comment-visibility

## Done（2026-07-04，代码落地 + 全量单测绿）
- **Phase 1 — `EventCommentIndicatorPlan`（`Models.swift`）**：`commentedAnchorKeys` + display→real 解析（按 `mirrorKey`）+ `hasComments(mirror:)` / `hasComments(jointEvent:)`。单测 `EventCommentIndicatorPlanTests`（6 例：display 解析命中 / partner 直接命中 / joint 命中 invitation.id / 无孪生 / 空评论 / 忽略已删）。
- **Phase 2 — req1 红点 UI**：`CalendarTabView` 加 `@Query comments`，预计算 `commentedAnchorKeys` + `persistedMirrorIDByKey`，把 `hasComments: Bool` 逐层下传。新增装饰性 `CommentIndicatorDot`；接入 `DayTimelineEventBlock`、`DayTimelineJointEventBlock`（day）、`WeekAgendaItemCard`（week，普通+joint，经 `WeekAgendaDaySection.itemHasComments`）。`ActivityTabView`（动态 tab）本身是评论流，无需红点（原 open-question Q2 → 已解决）。
- **Phase 3 — req2 我的事件详情可评论**：新增 `EventDetailMirrorResolutionPlan.persistedTwin(for:in:)`（替换并移除 `EventDetailInteractionPlan.canComment`）。`EventDetailView` 用 `if let commentMirror = persistedTwin(...)` **一步合并**「是否显示评论区」与「评论锚绑定」；anchor 用真实 mirror（真实 id + recordName 供路由）。保留「邀请对方」不变。单测 `EventDetailMirrorResolutionPlanTests`（3 例）+ 迁移原 `canComment` 断言。
- **Phase 4（自动化部分）**：全量 `CoupleCalendarTests` `** TEST SUCCEEDED **`。改动仅 `Models.swift` / `RootView.swift` / 测试（+333/−16），未触碰 CloudKit I/O 与同步管线。

- **两真机端到端验证** ✅（2026-07-04，V1a 回归冒烟 + V1b 新路径直验均 PASS，见 [open-questions](open-questions.md)）。随 v1.4 (build 33) 上架。

## Done（2026-10-23，#24 扩展）
- **我的日程不等同步也能先发起评论**：线程键改为 `mirrorKey`（两端一致、创建即已知），详情页按"对方事件 / 持久化镜像 / 共享窗口内的自有事件 / 对方看不到的自有事件"四种情况决定显示线程还是一行说明；红点同样回退到 `mirrorKey`。冒烟新增 step 9b。见 [decisions/0003](decisions/0003-own-events-comment-before-sync.md)。

## In Progress
- （无）

## Deferred
- **红点 VoiceOver 语义**：当前红点是装饰性（`accessibilityHidden`），避免打乱各事件 Button 既有的 accessibilityLabel。后续可把「有评论」追加进 Button label（需新增 `ShareCalStrings` 条目）。
- ~~「同步后可评论」占位提示（req2 未同步事件）~~ → #24 起未同步也可评论，不再需要。
- joint 事件「partner 评论了我们的共同事件」本地推送语义（沿用 calendar-ux-fixes 的既有 Deferred）。
