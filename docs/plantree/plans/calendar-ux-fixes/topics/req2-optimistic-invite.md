# Topic: req2 — 邀请乐观发送

## 用户需求
创建邀请时「等待太久才发送成功」的体验。

## 根因（核实 2026-06-20）
`EventDetailView.createInvite()`（`RootView.swift:2958`）：
1. `modelContext.insert(invitation)` + `try modelContext.save()` —— 本地已即时落库。
2. 但 `isSendingInvite = true` 一直保持，且只有 `await cloudKit.saveInvitationForSync(...)` 整个 CloudKit 往返**返回后**才 `inviteSuccessMessage = ...; isSendingInvite = false`。
⇒ 用户感知的「等待」= 这次网络往返被放在了成功 UI 的关键路径上。

## 决策
见 [decisions/0002-optimistic-invite-send.md](../decisions/0002-optimistic-invite-send.md)：乐观发送 + 后台上传 + 失败下次同步自愈（用户选定）。

## 方案
1. `createInvite()`：本地 `save()` 成功后**立即** `inviteSuccessMessage = strings.invitationSentMessage`、`isSendingInvite = false`、可关闭 sheet。
2. CloudKit 上传放后台 `Task`（不 await 在 UI 关键路径上）；上传失败**不回滚本地邀请**，仅记日志（必要时一个不打断的轻提示），靠下次同步重传。
3. **前置必做（否则丢邀请）**：补「新建邀请上传失败自愈」。
   - 现状：`foregroundSync`（`AppServices.swift`）已有 `InvitationReuploadPlan.responsesNeedingReupload`（`AppServices.swift:715`）只重传**响应（accept/reject）**，未覆盖「本地存在但服务器没有的新建 pending 邀请」。

### ⚠️ 实现发现（核实 2026-06-20，推翻原「diff cloudInvitations」方案）
- 创建方自己的邀请路由到**创建方 private zone**（`CloudKitInvitationWritePlan.destination → .privateOwnerZone`，`CloudKitCoupleSpaceService.swift:2132`）。
- 但 `foregroundSync` 只从 **shared zone** 拉邀请（`fetchEventInvitations(sharedZoneIDs:)`，`AppServices.swift:693`）——那是**对方**的数据。
- ⇒ 创建方自己的新建邀请**永远不会出现在 `cloudInvitations` 里**，无法用「local 有 / cloud 无 → 重传」来判断是否上传成功（否则每次同步都重传＝churn）。这也是为什么既有 `responsesNeedingReupload` 只对**响应**成立：invitee 的响应写进 creator 的 zone，对 invitee 而言那是 shared zone，能被拉回来对比。
- **机制：用户选定 (A) 本地标记（2026-06-20），已实现。**
  - **(A) 本地 `needsCloudKitUpload` 标记** ✅：`EventInvitation` 加一个**本地 only**（不进 CloudKit mapper/部署 schema）的 Bool；创建时置 true，后台上传成功置 false，`foregroundSync` 重传所有仍为 true 的「我创建的」邀请（`InvitationReuploadPlan.creationsNeedingReupload`）。自限、幂等。SwiftData 模型加字段（additive，默认 false，轻量迁移；本地缓存 `cloudKitDatabase:.none`，不影响部署 schema）。
  - (B) 私有库读回比对（未采用）：新增「拉创建方 private zone 邀请」的 fetch，与本地比对缺失的重传。较重。

## 验收
- 点「邀请伙伴」→ 立即显示「已发送」、按钮恢复、可关闭，无可感知等待。
- 断网点发送：仍显示「已发送」，恢复网络后下次 `foregroundSync` 把邀请补传到云端，对方能收到（两真机或断网模拟验证）。
- 不产生重复邀请（重传走 upsert/`changedKeys`，recordName=`invitation.id` 幂等）。
- 单测覆盖新 reupload Plan：本地有云端无→重传；云端已有→不重传；对方已响应的不回退。

## 风险 / 注意
- 乐观 UI 的核心安全前提就是自愈路径，**phase 顺序里自愈先于乐观化**。
- `inviteError`/`CloudKitSharingFailureMessage` 现用于把上传错误展示给用户；乐观化后该错误不再阻断成功提示，改为非阻断处理，避免「显示已发送又弹红字」的矛盾观感。
