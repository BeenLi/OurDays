# Decision 0002 — 改静默推送（抑制纯事件推送）+ 后台同步

- **日期**：2026-06-16
- **状态**：Accepted + **Code landed（2026-06-16）** —— 220 单测全过；剩两真机端到端验证（见 [roadmap](../roadmap.md)「Needs manual verification」）。
- **关系**：**部分推翻** [0001](0001-triggers-and-delivery.md) 的「交付可靠性修订（改为可见 alert 推送）」。触发范围（0001 的 4 类）不变。

## 背景（来自上线后用户反馈，2 条）
1. **动态推送不断，但点进「动态」tab 没有变化。**
2. **对方半天日程没更新**，用户怀疑对方是不是把 App 关了；问「ShareCal 后台能否同步本地日历」。

## 根因（已核实，见代码引用）
- **问题 1（语义错配）**：可见推送来自 `CKDatabaseSubscription`，在**任一**记录变更时由 APNs 直接展示通用文案「有新的共享日程动态 · New shared activity」（`CloudKitCoupleSpaceService.swift:2766-2780`）。但「动态」tab 只聚合**评论**（`ActivityFeedPolicy.items` / `unreadCount`，`Models.swift:1435-1480`；feed 范围见 [activity-feed/decisions/0001](../../activity-feed/decisions/0001-feed-scope.md)）。对方改**日历事件**（最常见）→ `EventMirror` 写入 → 触发 shared DB 订阅 → 用户收到推送，但变更其实在**日历 tab**，于是点进动态 tab「无变化」。
  - **CloudKit 硬约束**：shared database 只支持 `CKDatabaseSubscription`（不支持 `CKQuerySubscription`），且**无法按记录类型过滤、无法把字段塞进 payload**。⇒ 「只为评论推送」在订阅层做不到。
  - 已排除「重复写造成的噪声」：上传是变更门控的（`CloudKitMirrorSyncPolicy.mirrorsNeedingUpload` + shadow `lastUploadedAt`，`AppServices.swift:522/594`），推送对应**真实**变更，只是被错误标注/导向。
- **问题 2（架构限制）**：唯一同步管道 `SyncCoordinator.foregroundSync` 的所有调用都门控于 `scenePhase == .active` / 切 tab / 实时信号（`RootView.swift:147-160`）。**无任何后台执行路径**（无 `BGTaskScheduler`、无 `performFetchWithCompletionHandler`）。推送是**可见 alert 而非静默**，不会唤醒 App 拉取。⇒ 改了日历的一方**必须打开 App**，其 EventKit 变更才会镜像上云——这正是「对方半天没更新」。

## 决定
两项反馈的修复**收敛为同一架构**：可见推送 → 静默推送 + 后台同步，由设备端既有逻辑决定是否提醒。

### A. 抑制纯事件推送（问题 1）
- 订阅改回**静默**（`shouldSendContentAvailable = true`，去掉 `title`/`alertBody`/`soundName`/`shouldBadge`）。APNs 不再画横幅。
- 唤醒后跑同步，由**既有** `LocalNotificationPolicy`（`Models.swift:1516`，只有「评论我的事件 / 邀请 / 邀请回复 / 历史访问」4 类，**无**「对方改了日历事件」case）决定发什么本地通知。⇒ 纯事件变更 → **零通知**；用户拿到的每条通知都真实、准确。
- 抑制逻辑本就存在且正确，本次只是**停止那条无脑可见推送**绕过它。

### B. 后台同步（问题 2）—— 静默推送唤醒 + BGAppRefresh 兜底
- `didReceiveRemoteNotification:fetchCompletionHandler:` 需在**后台**真正跑同步：当前仅 `notifyChanged()` 依赖**存活的** SwiftUI 视图，挂起时无效。让 app delegate 直接持有共享 `ModelContainer` + `SyncCoordinator`，跑 `foregroundSync` 后回调 `completionHandler`。管道尾部 `postPendingNotifications` 负责发富本地通知。
- 注册 `BGAppRefreshTask`（新增 `BackgroundRefreshSchedulePolicy` 纯枚举 + glue）作为兜底：后台调度、每次跑完重排、跑同一同步。`Info.plist` 增加 `BGTaskSchedulerPermittedIdentifiers`（已有 `fetch`/`remote-notification`）。

### C. 可靠性上限（**接受**，用户已知情）
- 静默推送**可被节流/丢弃**；唤醒后仅约 **~30s 预算**，超时进程被杀（可能同步到一半）；**App 被强杀**则静默推送与 BGAppRefresh **都不会运行**。
- ⇒ **前台打开是唯一保证的同步**；两个后台机制只**收窄**未传播窗口，不能关闭它。
- 容忍中断的依据：`foregroundSync` 每次从头重跑（镜像重生成、上传变更门控）；`lastNotifiedAt` 仅在**成功发完通知后**才推进（`AppServices.swift:752`）——后台同步被杀也不丢通知，下次重评。**中断退化的是新鲜度，不是正确性。**
- 实现责任：① `completionHandler` 必定调用、尽快回调、不在窗口内做长任务；② 不新增「在工作 durably 完成前推进高水位」的逻辑。

## 取舍记录
- 放弃可见 alert 的「保证送达」换取「零幻影推送 + 真后台同步」。0001 当初改可见 alert 是因静默推送会被丢；本次接受该不可靠性并以 BGAppRefresh 兜底（用户在「Silent push + BG refresh combo」中明确接受 partial reliability）。
- `willPresent` 中针对**远程推送**的分支（`CoupleCalendarApp.swift:21-27`）在纯静默推送下基本失效（静默推送不触发 `willPresent`）；本地富通知仍走正常前台展示分支，保留。

## Scene 生命周期修订（2026-06-16，Codex stop-time review 发现）
BGAppRefresh 兜底原挂在 `UIApplicationDelegate.applicationDidEnterBackground` —— **错的回调**。本 App 采用 UIScene 生命周期（`ShareCalSceneDelegate: UIWindowSceneDelegate`，`Info.plist` `UIApplicationSceneManifest`），一旦有 scene delegate，UIKit **不再调用** app delegate 的 `applicationDidEnterBackground`，后台进入事件只走 scene delegate 的 `sceneDidEnterBackground`。⇒ 兜底原本只在「BGTask 自身重排」和「推送」时排队，**正常切后台永不排队**，形同虚设。
- 修：删 app delegate 的 `applicationDidEnterBackground`，在 `ShareCalSceneDelegate.sceneDidEnterBackground` 调 `scheduleAppRefresh()`。
- 连带：`ShareCalBackgroundSyncRunner` 从 `CoupleCalendarApp.swift`（`@main`，**非测试 target 成员**）移到 `AppServices.swift`（双 target 成员），否则 scene delegate（在 `CloudKitCoupleSpaceService.swift`，编入测试 bundle）在测试编译时看不到该类型（测试无 `@testable import`，靠双成员编译 app 源码）。

## 受影响文件（实现锚点）
- `CloudKitCoupleSpaceService.swift:2766` `ensureDatabaseSubscription` → 静默。
- `CoupleCalendarApp.swift:54-63` 后台同步真正落地 + BGTask 注册/调度；`:201` `@main` 共享容器对 delegate 可见。
- `Info.plist` `BGTaskSchedulerPermittedIdentifiers`。
- 新增 `BackgroundRefreshSchedulePolicy`（纯）+ 单测；`LocalNotificationPolicy` 针对「纯事件变更集 → 空」补测。

## 验证
- 单测：`BackgroundRefreshSchedulePolicy` 调度决策；`LocalNotificationPolicy` 纯事件变更不发通知。
- 两真机 + 两 iCloud：静默推送唤醒 → 后台同步 → 仅评论/邀请/访问类弹通知；纯日历改动不弹（思路见 `Scripts/dev-pairing-smoke.sh`）。
