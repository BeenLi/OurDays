# Decision 0005 — 被取消的同步不算失败

- **日期**：2026-10-25　**状态**：Accepted
- **范围**：`SyncCoordinator.foregroundSync` 的错误处理、界面触发同步的任务归属

## 背景（原本的工作方式）
真机日历页顶部出现红条「Operation CACC1939BC788D68 was cancelled」。这是 `CKError.operationCancelled` 的原文，`CACC1939BC788D68` 是被取消的 CKOperation 的 operationID。

同步管线里大部分 CloudKit 调用是自己包的 `withCheckedThrowingContinuation` + CKOperation，不理会 Swift 任务取消；但 `ensureZone()` 用的是 async 版 `modifyRecordZones`，它会监听当前任务的取消，一旦任务被取消就取消底层操作并抛出上面这个错误。`ensureZone()` 在每次同步的 CloudKit 段最先执行（`fetchOutgoingShareParticipantIDs`、`ensureShareRoot` 都会先调它）。

同步在这些情况下会跑在一个会被取消的任务里：
- 事件详情页的 `.task { syncOnOpenIfNeeded() }`：打开日程触发同步，同步没跑完就关掉 sheet，`.task` 被 SwiftUI 取消。
- 各页的 `.refreshable`：下拉刷新的视图在同步中被替换时，任务被取消。
- RootView 的根 `.task`（接受分享后的首次同步）。
- BGAppRefresh 到期：`expirationHandler` 主动 `cancel()`。后台 runner 与界面共用同一个 `SettingsStore`，所以后台的失败会直接出现在下次打开的界面上。

`foregroundSync` 的 catch 不区分取消和真正的失败，一律 `syncPhase = .failed` 并把 `localizedDescription` 原样放进红条。

配对人备注（`partnerNoteName`）只存在本机 UserDefaults，只影响显示，不进 CloudKit、也不参与 `PartnerScopedDataPolicy` 的过滤，所以与这个报错无因果关系；时间上的重合多半是改备注时在「我们」和日历之间来回切、打开日程等操作触发了同步。

## 决策
1. 新增 `SyncCancellationPolicy.isCancellation`：`CancellationError`、`CKError.operationCancelled`、`NSURLErrorCancelled`，以及每一项都是取消的 `partialFailure`。
2. `foregroundSync` 遇到取消：`syncPhase` 回到 `.idle`，不设 `lastSyncError`，不更新 `lastSyncAt`（下一次自动同步不会被 60 s 节流挡掉）。
3. `SyncCoordinator.syncIfIdle` 与 RootView 的 `runForegroundSync` 把同步放进独立的 `Task` 再 `await .value`：视图消失不再取消已经在和 CloudKit 通信的同步；下拉刷新的转圈照旧等同步结束。
4. 后台 runner 不改：BGAppRefresh 到期时仍要能取消，只是取消不再显示成错误。

## 影响
- 真正的失败（网络、权限、schema）仍然显示红条。
- 管线本身是幂等的，被取消的同步没有写坏的中间状态，下一次同步会补齐。
