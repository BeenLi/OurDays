# Topic: req3 — 今天 now-indicator 红线

## 用户需求
打开「日历」tab，若当前展示的是今天，UI 显示一条红线横跨当前时刻，左侧标注当前时刻，仿 iOS 自带日历 app。

## 代码现状（核实 2026-06-20）
- 日视图 `DayAlignedTimelineView`（`RootView.swift:1717`）：`ScrollView` 内 `ZStack(alignment: .topLeading)`，已叠 `DayTimelineHourGrid`（每小时分隔线，`RootView.swift:1991`）、两条 lane、joint 块。
- rail：`DayTimelineHourRail`（`RootView.swift:1974`），右对齐显示 `%02d:00` 时刻文字，`offset(y: mark.y - 7)`。
- 时间→y 的换算已存在：`DayTimelineLayoutPlan.eventFrame`（`Models.swift:894`），`pointsPerMinute = hourHeight / 60`，`y = minutesFromStart × pointsPerMinute`。`hourHeight = 58`，`dayHeight = 24 × hourHeight`。
- `dayStart` 已作为参数传入（即当前展示的那天的 0 点）。`Calendar.current.isDateInToday` 已在别处用（`RootView.swift:1168`）。

## 方案
1. 新增纯逻辑 `enum DayTimelineNowIndicatorPlan`（放 `Models.swift`，遵循 Plan-enum 约定）：
   - `static func placement(now: Date, dayStart: Date, hourHeight: CGFloat, calendar: Calendar = .current) -> DayTimelineNowIndicator?`
   - 返回 `nil` 当 `now` 不在 `[dayStart, dayStart+1day)`（即只在「今天且正展示今天」时显示）。
   - 否则返回 `{ y: CGFloat, /* 可选 */ timeText 由 View 用 .formatted 生成 }`，`y = (now - dayStart)/60 × (hourHeight/60)`，clamp 到 `[0, dayHeight]`。
2. UI：在 `DayAlignedTimelineView` 的 ZStack 里，`DayTimelineHourGrid` 之上叠一个 `DayTimelineNowIndicator` view：
   - 一条红色 1pt 横线（`Color.red`），从 rail 右缘到 contentWidth，`offset(y:)`。
   - 左端一个红色小圆点（仿系统）。
   - rail 侧：当前时刻文字（红色，`now.formatted(date:.omitted, time:.shortened)`），盖在 hour rail 对应 y 处。
3. 刷新：用 `TimelineView(.everyMinute)` 包裹该 indicator（iOS 自带的低频刷新，省电）；`now = context.date`。避免手写 Timer。

## 验收
- 展示今天：在当前分钟位置出现红线 + 左侧红色时刻；分钟推进后红线下移（手动等 1 分钟或改系统时间验证）。
- 切到非今天（左右翻天）：红线消失。
- 0:00 / 23:59 边界 y 在 `[0, dayHeight]` 内，不溢出。
- 单测覆盖 `DayTimelineNowIndicatorPlan`：今天/非今天、边界、y 计算与某已知值一致。

## 风险 / 注意
- `TimelineView(.everyMinute)` 只在视图可见时刷新，符合「每次打开看当前时刻」诉求；不需要常驻 timer。
- 与既有 `scrollToInitialTimelinePosition`（默认滚到 8:00 或 focused joint 事件）不冲突——红线是 overlay，不改滚动目标。是否「打开自动滚到 now」属增强，本 phase 不强求（可作 idea）。
- 周视图 `WeekAgendaView` / 双列 `TwoColumnTimelineList` 是列表式、非按小时定位，本 phase 红线只做日视图（`DayAlignedTimelineView`）。
