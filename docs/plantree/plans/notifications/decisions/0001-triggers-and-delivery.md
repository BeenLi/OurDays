# Decision 0001 — 通知触发范围与交付架构

- **日期**：2026-06-14
- **状态**：触发范围 Accepted（用户确认全选）；交付架构 Proposed（待 phase 2 验证）

## 触发范围（Accepted）
1. 对方评论了我的日程
2. 收到新邀请
3. 我的邀请被接受 / 拒绝
4. 历史访问请求 / 其回复

## 交付架构（Proposed，推荐）
**静默 CloudKit 推送（content-available）唤醒 App → App 拉取变更 → App 发本地通知（`UNUserNotification`）。**

理由：CloudKit 无法可靠把私有/共享数据内容塞进推送 payload；静默推送 + 本地通知能定制文案且适配两人制（对方写入会落到我的 private database）。

## 交付可靠性修订（2026-06-14，Codex review：静默推送会被节流/丢弃）
初版订阅只用 `shouldSendContentAvailable`（静默推送）→ 后台/被杀时会被系统后台预算**节流或丢弃**，用户可能收不到任何提醒。改为**可见 alert 推送**（`alertBody` + `shouldBadge` + `soundName` + `title`），由 APNs 直接展示，不依赖后台执行 ⇒ 可靠送达。
- 取舍：共享数据库订阅（`CKDatabaseSubscription`，shared DB 不支持 `CKQuerySubscription`）无法把记录字段塞进推送，故 alert 文案是**通用双语**（"有新的共享日程动态 · New shared activity"）。
- 富文本/逐条详情仍来自:in-app 动态 feed + 前台同步时 `postPendingNotifications` 发的本地通知。
- 去重:`willPresent` 对**远程推送**在前台返回 `[]`(本地富通知负责前台展示),本地通知正常展示。
- 前台到达修订(2026-06-14,Codex review):纯 alert 推送在前台到达时 `didReceiveRemoteNotification` 不触发;`willPresent` 仅抑制横幅会导致**不触发同步、富通知不发**。故 `willPresent` 抑制前先 `ShareCalRemoteChangeSignal.notifyChanged()` 触发同步(前台场景 `scenePhase` 不变不会自动同步)。后台点击通知 → 场景激活 → `scenePhase` 同步,已覆盖。
- 强制同步修订(2026-06-14,Codex review):推送信号原走 `syncAfterSceneBecameActiveIfNeeded`(受 `ForegroundSyncPlan.shouldRunAutomaticSync` 时间节流),刚同步过会被跳过 → 漏掉推送对应的新数据。改为 `runForegroundSync(forceCloudKit: true)` **强制**拉取(仅防并发,不做时间节流),因为推送本身即「确有新数据」的权威信号。
- 恢复门修订(2026-06-14,Codex review):`runForegroundSync` 是无门禁的核心路径,强制调用会**绕过 existing-iCloud-data 恢复门**(`shouldDeferAutomaticSyncForExistingICloudDecision`)——用户尚未决定如何处理已有 iCloud 数据时不应同步/合并。修为:推送处理在强制同步前仍 `guard !shouldDeferAutomaticSyncForExistingICloudDecision`(保留绕过时间节流,但恢复该门)。原则:按触发可信度匹配同步激进度,但**安全门(数据恢复决策)对所有自动触发都要保留**。
- 残留可接受冗余:后台收到通用 alert 后再打开 App,前台同步会补发富本地通知(带详情),视为增强而非缺陷。

## 触发 4 的 source 语义（修订 2026-06-14，Codex review 发现）
历史访问请求有三种 source：`localOutgoing`（我刚发出的本地副本）、`privateOwnerZone`（对方发来、落在我的 zone 的来件）、`acceptedSharedZone`（对方对我请求的**回复**副本，从对方 zone 导入）。
- 「收到来件」通知 = `source == .privateOwnerZone && owner == 我 && status == pending`。
- 「我的请求被回复」通知 = `source != .privateOwnerZone && requester == 我 && status != pending`（对齐 `CalendarAccessRequestListPlan.outgoing`）。

教训:初版把两个分支都套在 `source == .privateOwnerZone` 下,导致**回复通知永不触发**;且单测用例没设 source(默认 privateOwnerZone)与错误实现一致,所以没抓到——已改测试用真实 source 复现后再修。

## 顺序决定
用户选择「先动态后推送」：本 plan 整体 **Deferred 至 phase 2**，依赖 [../../activity-feed/](../../activity-feed/) 定义「什么算一条可通知的动态」。
