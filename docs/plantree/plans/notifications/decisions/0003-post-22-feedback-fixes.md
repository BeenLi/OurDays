# Decision 0003 — build-22 上线后反馈修复（图标角标 + 访问请求审批回退）

- **日期**：2026-06-16
- **状态**：Accepted + **Code landed（2026-06-16）** —— 236 单测全过；剩两真机端到端验证。
- **关系**：问题 1 是 [0002](0002-silent-push-and-background-sync.md) 移除 `shouldBadge` 的后续；问题 2 是访问请求同步正确性。

## 问题 1：App 图标红点「1」一直不消（已查看仍在）
**根因**：全仓**无任何 springboard 图标角标代码**（`setBadgeCount`/`applicationIconBadgeNumber`/`content.badge` grep 全空）。App 内 tab 角标（`.badge(unreadActivityCount)` / `.badge(pendingInviteBadgeCount)`，`RootView.swift:100/113`）是 SwiftUI tab-item 角标，实时计算、查看/处理后自动清。但**主屏图标角标**是独立的 OS 级计数，由 build≤21 的可见推送 `notificationInfo.shouldBadge = true` 设上后**从未被清零**。build 22 改静默推送后**不再设置**角标，但也**从不清除**遗留值 ⇒「1」永久残留。
**修**：`AppIconBadgePlan.badgeCount(unread, pending) = max(0, a+b)`（纯，3 测）；`RootView.syncAppIconBadge()` 调 `UNUserNotificationCenter.setBadgeCount(...)`，在 `.task`、scene 变 active、以及两个计数 `onChange` 时调用。既清遗留「1」，又让角标=真实未读/待办、可自清。

## 问题 2：点「同意」历史访问请求后又回到待处理，点几次才生效
**根因（竞态 + 无 last-writer-wins）**：owner 点同意 → `update()` 置 `status=.approved`（setter 顺带 `updatedAt=.now`，`Models.swift:2476-2479`）+ 本地 save + **未 await 的** fire-and-forget 上传 Task（写入 owner 自己 private zone）。与此同时任一 `foregroundSync` 的 `fetchCalendarAccessRequests` 会**连 owner private DB 一起重读**（`CloudKitCoupleSpaceService.swift:2531`，标 `.privateOwnerZone`），而 `upsert(accessRequests:)`（`AppServices.swift:884`）**按 id 无条件覆盖**。若同步发生在上传落库前 → 用服务器仍 `pending` 的旧值覆盖本地 `approved` → 请求重现。多点几次直到上传赢得竞态。
- 既有代码已护住**对称的 requester 侧**（`pendingOutgoingRequestsNotSupersededByTerminalCopies`，`Models.swift:1395`，不让 requester 用 stale pending 重传覆盖 owner 审批）；**owner 导入侧**是缺口。`updatedAt` 本就在审批时 bump，数据齐备只是没用上。
- 安全性：incoming 请求的 status **只有 owner 会改**（partner 只发 pending、之后不改），故按 `updatedAt` last-writer-wins 完全正确，不会误压制 partner 的合法更新。

**修（status-aware，非纯时间戳）**：`CalendarAccessRequestImportMergePlan.shouldApplyIncoming(existingStatus:existingUpdatedAt:incomingStatus:incomingUpdatedAt:)`（纯，4 测）；`upsert(accessRequests:)` 覆盖前 guard，false 则 `continue`。规则：
- **终态(approved/declined) 永远压过 pending**，无视时间戳——pending 永不回退已决；决定也总能落到 requester（即便 owner 时钟偏慢）。
- 同终态性（都终态 / 都 pending）→ last-writer-wins（`incoming >= existing`，相等应用）。
- **为何不能纯时间戳（Codex stop-review 二次发现）**：`updatedAt` 由各端各自 `.now` 盖戳，**跨端时钟偏移 / CloudKit Date 截断 / 时间戳相等**都会让 requester 的 pending 副本时间戳 ≥ owner 的 approved，纯 `incoming >= existing` 仍会回退审批。owner 是 incoming 请求**唯一**的终态改写者，故「终态 > pending」是精确判据，不依赖时钟。
- **上传可靠性（2026-06-16，Codex stop-review 三次发现 + 修复）**：merge guard 让「终态压过 pending」后，若 tab 动作的 **fire-and-forget 上传失败**，owner 本地 approved、服务器/partner 仍 pending，且 guard 拒绝让 pending 重现 ⇒ 失败上传**永久化**（旧的回退反而是「自纠正」：重现 → 用户重点 → 重传）。修：新增自限对账——同步导入服务器副本后，比对**本地终态决定**与刚取回的云副本，对「云端落后（缺失或状态不符）」者重传（`CalendarAccessRequestReuploadPlan.ownerDecisionsNeedingReupload` / `InvitationReuploadPlan.responsesNeedingReupload`，纯，6 测）。复用同步已取数据、无新模型字段；**自限**：服务器一旦一致即不再重传（无每次同步 churn）。失败上传在下次同步自愈。

## 复审推广（2026-06-16，重跑 code-review 发现）
重跑高 recall 复审发现 **`upsert(invitations:)` 有结构完全相同的竞态且无防护**：邀请被接受/拒绝由 invitee 本地置状态（`EventInvitation.status` setter 顺带 bump `updatedAt`，`Models.swift:2466`）+ fire-and-forget 上传，并发同步重读仍 `pending` 的服务器副本会回退「已接受」。⇒「我接受的邀请又变回待处理」会作为同类 bug 复现。
- **修（按 altitude 推广，非再贴一个特例）**：抽出通用 `StatusMergePlan.shouldApplyIncoming(existingIsTerminal:existingUpdatedAt:incomingIsTerminal:incomingUpdatedAt:)`；`CalendarAccessRequestImportMergePlan` 与新增 `InvitationImportMergePlan` 都委托它（各自算 `status != .pending`）。`upsert(invitations:)` 加同款 guard。邀请终态 = accepted/declined/canceled；pending 为唯一非终态。
- 邀请双方都可置终态（invitee accept/decline、creator cancel），但「终态压过 pending」仍安全；both-terminal 冲突走 LWW（罕见，合理）。「incoming 终态压过 pending」保证 creator 仍能收到 accept。
- 复审其余结论：①「guard 跳过非状态字段」**驳回**——访问请求/邀请的非状态字段创建后不可变，状态变更必 bump updatedAt，输家合并不会丢新字段。②4 个角标触发点**可接受**（`.task` 播种初值、scene-active 清零、两 onChange 监听不相交来源）。

## 已知平台限制（角标授权）
`UNUserNotificationCenter.setBadgeCount` 需 `.badge` 授权才生效：
- 用户**拒绝**通知 → 无法设/清角标（含清除旧版遗留「1」）。但遗留「1」只会出现在曾**授权过**（才收到带角标可见推送）的设备；之后转拒绝才会卡住，属罕见边缘，**iOS 平台约束、无代码解**。
- 全新安装首启 `.task` 播种可能早于授权解析 → 非零播种被丢；下次计数变化 / scene-active 自愈。
判断：不为平台约束加复杂度；记录于此。

## 受影响文件
- `Models.swift`：新增 `StatusMergePlan`（通用）、`CalendarAccessRequestImportMergePlan`、`InvitationImportMergePlan`、`AppIconBadgePlan`、`CalendarAccessRequestReuploadPlan`、`InvitationReuploadPlan`。
- `AppServices.swift`：`upsert(accessRequests:)` 与 `upsert(invitations:)` 各加 status-aware guard；`foregroundSync` 导入后加终态决定的自限对账重传。
- `RootView.swift`：`import UserNotifications` + `syncAppIconBadge()` + 4 处调用点。

## 验证
- 单测：16 新（badge 3 + 访问请求 merge 4 含跨端时钟偏移回退 + 邀请 merge 3 + 重传对账 6），全套 236 过。
- 两真机：owner 点同意一次即生效不回退；查看动态/处理邀请后主屏角标归零。
