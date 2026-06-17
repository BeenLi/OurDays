# Decision 0003 — build-22 上线后反馈修复（图标角标 + 访问请求审批回退）

- **日期**：2026-06-16
- **状态**：Accepted + **Code landed（2026-06-16）** —— 236 单测全过。**两机端到端验证已自动化并通过（2026-06-17，见末节）**。
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
  - **身份判据修订（2026-06-16，Codex stop-review 四次发现）**：邀请重传初版用 `inviteeMemberID == currentMemberID` 判定「我的回应」——但 `inviteeMemberID` 是 creator 盖的**对方 hashed CloudKit id，永不等于收件人本地 member id**（见 `InvitationInteractionPlan.canRespond` 注释）⇒ 该判据**恒为 false**，邀请重传形同死代码。改为 `creatorMemberID != currentMemberID`（两人制：非创建者即受邀者）。访问请求侧的 `ownerMemberID == currentMemberID` 不同——access request 的 owner id 确等于本机 id（通知 trigger 4 亦依赖之），故保留。
  - **触发条件收紧（2026-06-16，Codex stop-review 五次发现）**：重传条件初版为「云端状态 != 本地状态」。但邀请**双方都可置终态**（受邀者 accept/decline、创建者 cancel），故当创建者**真的取消**（云=canceled）而我本地=accepted 时，旧条件会把 accepted 回推、**覆盖对方真实的取消决定**。重传的职责只是修「上传失败」（服务器尚无决定），不该越过真实终态。改为**仅当云端仍 `pending`（或访问请求记录缺失）时**重传；终态-对-终态冲突交由导入 merge（LWW）裁决，不由重传推平。访问请求侧 owner 是唯一终态权威，云端终态必是自己已传的决定，故同样安全。

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

## 两机端到端 UI 验证 + 冒烟夹具修复（2026-06-17）
背景：把上面承诺的「两真机端到端验证」**自动化**。此前 `Scripts/dev-pairing-smoke.sh` 只断言存储字段（`partnerShareOwnerID`）与日志行——属**状态层**，从未验证 SwiftUI 日历**真的渲染**了对方事件。新增 **step 7**：配对成功后在 partner 机重启 app 跑一条门控 XCUITest（`testPairedPartnerCalendarShowsOwnerEvent`，仅当 runner 设 `TEST_RUNNER_SHARECAL_SMOKE_UI=1` 时跑，否则 `XCTSkip`，使常规 UI 套件在未配对机上仍绿），断言日历出现 owner 播种的事件。

逐个根因（按调试顺序，每个都先取证再修）：
1. **跨区 502 让 accept 偶发硬失败**：China↔US 账号的 CKShare accept 跨数据中心，偶返回 `serverRejectedRequest`（HTTP 502 / `ServerHTTPError` 2001 / CKError code 15）——瞬时基础设施错误，非 app bug、非死锁、非弹窗。修：`accept_share_with_retry`——侦测到 `acceptShare failed` 且匹配瞬时标记（`http status code 5xx`/`ServerHTTPError`/`code 15`）即重启重试（默认 4 次、15s 退避），并**短路**掉原本要等满 `ACCEPT_TIMEOUT` 才失败的慢失败；**非瞬时**失败立即硬失败，不掩盖真 bug。
2. **配对后多个咨询性 sheet 盖住日历**：全新启动后**异步**叠出 ①系统通知授权弹窗（SpringBoard 持有，不在 app 元素树内）②「设置对方备注名」sheet ③「卸载或重装前请先解除配对」安全提示。原 `-ShareCalSeedProfileName` 只播种 `hasCompletedInitialProfilePrompt` / `hasResolvedExistingICloudDataPrompt`，未盖后两者的 flag；测里一次性 dismiss 又跑得太早。修（按 altitude，非在测里逐个敲按钮）：seed 路径补播 `hasPromptedPartnerNoteForCurrentPairing` + `hasShownPairingSafetyNoticeForCurrentPairing`——这两 flag **仅在换伴**（`confirmShareReplacement`）时重置，已建立配对的普通同步不动它，故启动播种后稳定。系统通知弹窗无 flag → 测内经 `springboard` 代理点掉（保留 Skip/继续 兜底）。
3. **冒烟事件夹具陈旧（「对方」列恒 0 的真因）**：`ensureShareCalSmokeTestEvent` 按标题在 draft 日期 **±24h** 内找已有事件并**原样复用、不刷新日期**。系统日历在卸载/重装后**仍存活**，故昨日跑出的同名事件落在 ±24h 窗内被复用 ⇒ 冒烟事件停在旧日期、不在「今天」视图。直接查 partner SwiftData 实锤：最新 owner `ShareCal E2E Smoke Test` 停在 6/16（昨日），今日「对方」列=0；partner 自己的事件因时区（UTC+8）凑巧落在今日 00:14 才显示。修：命中已有事件时把 start/end 刷到本次 draft 的 now+15min，每跑必落「今天」。

验证：完整两机跑 `✅ PASS`——accept 第 1 次撞 502、重试第 2 次过；双向同步；partner 日历 `对方=1`，UI 测 **8.4s** 内匹配到 owner 事件（截图存 `build/dev-smoke/ui-verify.xcresult`）。

测内取舍：断言用 `.exists`（元素入 a11y 树即过），**不用** `.isHittable`——后者需先清所有弹窗、且耦合日历 ScrollView 的滚动位置（午夜/全天事件可能渲染了却滚出视口），会引入时序脆性，得不偿失。`.exists` + 表头「对方 1」已足证后台同步抵达渲染层。截图前清残留弹窗（仅产物美观，不改断言）。

受影响文件（本次，**均为测试夹具 / 自动化**，对生产惰性、无 build 号变更）：
- `Scripts/dev-pairing-smoke.sh`：`accept_share_with_retry`（502 重试，env 可调 `ACCEPT_MAX_ATTEMPTS`/`ACCEPT_RETRY_BACKOFF`）；step 7 XCUITest UI 验证。
- `CoupleCalendarUITests/CoupleCalendarUITests.swift`：`testPairedPartnerCalendarShowsOwnerEvent`（`SHARECAL_SMOKE_UI` 门控、弹窗消解循环、截图前清弹窗）。
- `CoupleCalendarApp.swift`：seed 路径补播两个配对后 sheet 的 flag（仅 `-ShareCalSeedProfileName` 在场时，正常启动惰性）。
- `CalendarAccessService.swift`：`ensureShareCalSmokeTestEvent` 复用事件时刷新日期到 now+15min。
