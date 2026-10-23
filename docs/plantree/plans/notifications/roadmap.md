# Roadmap — notifications

## Done（2026-06-16，v2 反馈修复，见 [decisions/0002](decisions/0002-silent-push-and-background-sync.md)）
目标：消除「幻影动态推送」（问题 1）+ 加后台同步（问题 2）；两者收敛为「可见推送 → 静默推送 + 后台同步」。
- ✅ 订阅改静默：`ensureDatabaseSubscription` 去掉 alert/sound/badge，置 `shouldSendContentAvailable = true`（`CloudKitCoupleSpaceService.swift:2766`）。配置每次启动跑 = 既有安装自动重配。
- ✅ 新增 `ShareCalBackgroundSyncRunner`（@MainActor，持**与 UI 同一** `ModelContainer`/`SettingsStore`/`AppServices`；置于 `AppServices.swift` 以便测试 target 可见）：`runSync()` 强制拉取 + 守恢复门；`scheduleAppRefresh()`；`handleAppRefresh()`（先排下一次→跑→`setTaskCompleted`，过期 cancel）。`CoupleCalendarApp.init` 配置之。
- ✅ `didReceiveRemoteNotification` 后台真跑 `runSync()` 再 `completionHandler(.newData/.noData)`；`didFinishLaunching` 注册 BGTask handler。
- ✅ **BGTask 排队挂 `ShareCalSceneDelegate.sceneDidEnterBackground`**（非 app delegate —— UIScene 生命周期下 `applicationDidEnterBackground` 不被调用；Codex review 修订，见 [decision 0002](decisions/0002-silent-push-and-background-sync.md)）。
- ✅ 新增 `BackgroundRefreshSchedulePolicy`（纯）+ 4 单测；`BGTaskSchedulerPermittedIdentifiers` 入 `Info.plist`（`com.leeberty.CoupleCalendar.refresh`）。
- ✅ `LocalNotificationPolicy` 补测 `testEventOnlyChangesProduceNoNotifications`：纯事件变更集 → 空（守住问题 1 抑制）。
- ✅ **Last Landed**：2026-06-16，`** TEST SUCCEEDED **`，220 单测全过（215→220，+5），无新增编译警告。

## Needs manual verification（v2，无法单测/单机覆盖）
- ⚠️ 两真机 + 两 iCloud：对方**改日历事件** → 我**不弹**通知（问题 1 修复）；对方**评论/邀请/访问** → 我弹富本地通知。
- ⚠️ 静默推送唤醒 → 后台 `runSync` 在 ~30s 预算内完成；App 被强杀时不唤醒（已知上限）。
- ⚠️ `BGAppRefresh` 真机调度（模拟器 `submit` 失败属预期，已 catch）。可用 Xcode debugger `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.leeberty.CoupleCalendar.refresh"]` 触发。
- ⚠️ APNs 生产链路 + TestFlight(prod entitlement) 静默推送送达。

## Done（2026-06-14，按推荐架构落地：静默推送唤醒 → 拉取变更 → 发本地通知）
- ✅ `LocalNotificationPolicy`（纯，4 类触发）+ 6 单测；`LocalNotificationContentPolicy`（kind→文案）+ 3 单测。
- ✅ `SettingsStore.lastNotifiedAt` 高水位游标（首次同步只建基线，不刷屏）。
- ✅ `LocalNotificationScheduling` + `UserNotificationScheduler`（UNUserNotificationCenter，按 id 去重）。
- ✅ `SyncCoordinator.foregroundSync` 成功尾部 `postPendingNotifications`：同步后拉取并发本地通知。
- ✅ `configureDatabaseSubscription()` 现订阅 **private + shared** 两个库（之前是 dead code）。
- ✅ `ShareCalAppDelegate`：`didReceiveRemoteNotification` → `ShareCalRemoteChangeSignal` + `.newData`；注册/失败回调；`UNUserNotificationCenterDelegate` 前台横幅。
- ✅ 启动 `ShareCalNotificationSetup.configure`：请求授权 + `registerForRemoteNotifications` + 订阅（gated by isCloudKitEnabled）。
- ✅ `RootView` 监听 `ShareCalRemoteChangeSignal` → 拉取同步。
- ✅ `remote-notification` 后台模式已在 Info.plist（原已配）。

## Needs manual verification（无法用单测/单机覆盖）
- ⚠️ 端到端静默推送 → 唤醒 → 本地通知:需**两台真机 + 两个 iCloud 账号**(Dev 环境用 `Scripts/dev-pairing-smoke.sh` 思路)。
- ⚠️ APNs 生产链路 + TestFlight(prod entitlement) 推送送达。
- ⚠️ 后台被杀场景下 `didReceiveRemoteNotification` 的执行窗口（当前 completion 立即回调，属 best-effort；如需可加 background task 包裹）。
- ✅ 可单机验证:前台/切到 tab 触发同步后，对方新数据会弹本地通知横幅(模拟器即可，需有已配对数据)。
