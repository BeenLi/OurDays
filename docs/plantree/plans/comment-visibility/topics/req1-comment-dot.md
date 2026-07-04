# Topic: req1 —— 有评论的日程显示小红点

## 用户需求
「在 tab『日历』中，对于有评论的日程不管是我的还是对方的，在日程上显示一个小红点。」
- 语义（用户选定 2026-07-03）：**标记任何有评论的日程**（≥1 条未删除评论即常驻红点，含自己发的），非「未读」语义。见 [decision 0001](../decisions/0001-dot-marks-any-comment.md)。

## 代码现状（核实 2026-07-03）
- 显示事件三类：我的普通事件 = `localDisplayMirrors`（display mirror，`id="display:<mirrorKey>"`，`RootView.swift:882` / `Models.swift:1324`）；对方普通事件 = 真实持久化 mirror（`visiblePartnerMirrors`, `RootView.swift:891`）；共同日程 = `JointScheduleEvent`（`id=invitation.id`，`EventServices.swift:456`）。
- 评论存储：`EventComment.eventMirrorID` = 锚 key（普通=真实 `mirror.id`；joint=`invitation.id`），`deletedAt` 标删除。`@Query comments` 已在多处可用（如 `RootView.swift:2686`）。
- 锚映射既有：`EventCommentAnchorPlan`（`Models.swift:1378`）。
- **关键难点**：我的 display mirror 的 `id`（`display:...`）≠ 评论里存的真实 `mirror.id`，直接用 `mirror.id` 查会漏掉「对方评论了我的事件」的红点。display 与真实 mirror **共享 `mirrorKey`**（`Models.swift:1337,2514`），可据此在持久化 mirrors 里解析出真实 id。

## 方案
1. 新 `EventCommentIndicatorPlan`（Plan enum，纯函数、可单测）：
   - `commentedAnchorKeys(comments)` → `Set<String>`（`deletedAt==nil` 的 `eventMirrorID`）。
   - `hasComments(mirror, commentedKeys, persistedIDByMirrorKey)`：resolvedKey = display 前缀 ? `persistedIDByMirrorKey[mirror.mirrorKey]` : `mirror.id`；命中即真。
   - `hasComments(jointEvent, commentedKeys)` = `commentedKeys.contains(jointEvent.id)`。
2. `CalendarTabView` 每次 body 预计算一次 `commentedKeys` 与 `[mirrorKey:id]`（持久化 mirrors 里 `!id.hasPrefix("display:")` 的），把 `hasComments: Bool` 下传 leaf 视图。
3. leaf 视图加小红点：`DayTimelineEventBlock`(`:2108`)、`DayTimelineJointEventBlock`(`:2150`)、`WeekAgendaItemCard`(`:2291`)。第二处日详情列表（`RootView.swift:3044` 的 sheet 宿主）如渲染事件行也接入。

## 验收
- 对方评论我的普通事件后同步 → 我的日历该事件出现红点（依赖 display→real 解析）。
- 我 / 对方评论对方事件、joint 事件 → 对应块出现红点。
- 删除某事件全部评论后红点消失；无评论事件无红点。
- 单测：display 解析命中 / partner 直接命中 / joint 命中 / 无孪生或空评论不命中。

## 风险
- 每次 render 遍历评论：情侣两人数据量小，body 内一次性建 `Set`/`Dict` 即可，无性能顾虑。
- 若「我的事件」尚未同步（无持久化孪生），无真实 id ⇒ 不可能有评论 ⇒ 无红点，符合预期。
