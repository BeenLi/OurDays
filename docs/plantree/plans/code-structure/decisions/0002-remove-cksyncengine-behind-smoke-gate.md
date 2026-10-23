# Decision 0002 — 删除 CKSyncEngine 驱动，以两模拟器冒烟为合并门槛

- **日期**：2026-10-22　**状态**：Accepted，#16 已落地（冒烟 PASS 后用户确认合并）

## 背景（原本的工作方式）
同步协调器每次前台同步都先调用 `cloudKit.foregroundSync()` 启动一个 CKSyncEngine 驱动。但它的入队方法在全仓没有任何调用者，所以每次 `sendChanges()` 发的都是空集；事件回调只存 stateSerialization 并记日志，取回的变更从不应用；每次冷启动都以 `stateSerialization: nil` 从头拉。真正的 CloudKit 读写（zone/根记录/share 管理、批量修改、按 zone 全量拉取）全部走服务里显式的代码路径。它唯一的副作用是维护 private database 上一条 id 为 `couplecalendar-database-subscription` 的订阅，并设了 `automaticallySync=true`。

## 决策
1. 删掉驱动、`foregroundSync()`、启动它的两处属性和协调器里的调用与计时点；README 里"CKSyncEngine 推送变更"的说法改为"CKDatabaseSubscription 静默推送唤醒 App 拉取"。
2. 因为订阅 id 与通知设置每次启动创建的订阅相同（private 上同名、shared 上另一条），删引擎不会丢订阅；但这是 CloudKit 运行时行为变化，**必须先跑两模拟器配对冒烟再合并**，由用户确认。

## 结果
- 冒烟 2026-10-22 PASS（5 min 19 s）：双向配对、双向同步、对方 UI 渲染 owner 事件、共同日程评论对称、点块打开评论串；控制台 `syncEngine` 0 次出现。第一次跑失败只因两台模拟器 iCloud token 过期（→ #18 预检）。

## 影响
- #10 已先删了引擎的三个入队方法；#16 删剩下的驱动本身。
- 以后要做增量拉取，应基于 `CKFetchRecordZoneChangesOperation` 的 change token，而不是回到 CKSyncEngine。
