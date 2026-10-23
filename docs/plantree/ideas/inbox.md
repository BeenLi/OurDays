# Ideas Inbox

低承诺想法。澄清足够后再 `promote` 成 `plans/<name>/`。链接 baseline：[../baseline/README.md](../baseline/README.md)。

---

## idea-001 「动态」tab：突出对方对我日程的评论并支持继续互动
- **录入**：2026-06-14
- **状态**：✅ 已提升 → [plans/activity-feed/](../plans/activity-feed/)（2026-06-14，内容范围=仅评论互动）
- **原话**：在「日历」和「邀请」之间加一个「动态」tab，凸显对方评论了我的日程，我也能接着互动。
- **可行性快照（已核实）**：数据已具备（`EventComment` 含 `isRead`，CloudKit 已同步）；tab/角标基础设施已存在。主要新增 = 一个聚合视图 + 一个「动态流排序/未读」Policy enum（遵循项目 Policy enum 约定）+ 本地化字符串 + `ShareCalTab` 新增 case。**不需要新基础设施**。
- **开放问题**：
  - Q1 动态流内容范围：仅评论互动？还是合并邀请/历史访问请求？（用户原话暗示保留独立「邀请」tab）
  - Q2 未读如何呈现：动态 tab 角标用 `isRead` 聚合？是否需要 `lastSeenAt`？
  - Q3 互动形式：在动态流内直接回复评论，还是跳转到事件详情？
  - Q4 是否区分「对方评论我的」与「我评论对方的」两类条目？
- **建议提升目标**：`plans/activity-feed/`

---

## idea-002 把邀请/动态做成 App 系统级提醒（推送/通知）
- **录入**：2026-06-14
- **状态**：✅ 已提升 → [plans/notifications/](../plans/notifications/)（2026-06-14，Deferred phase 2，触发范围=全选4类）
- **原话**：邀请/动态能不能做成 App 的系统级提醒？
- **可行性快照（已核实）**：推送权限已配；`CKDatabaseSubscription`（静默推送）已定义但**从未调用**=dead code；缺 `registerForRemoteNotifications` / 远程通知回调 / `UNUserNotification` 授权与本地通知 / 后台模式。推荐架构：**静默 CloudKit 推送唤醒 App → 拉取变更 → 发本地通知**（CloudKit 共享/私有数据无法可靠把内容塞进推送 payload）。
- **开放问题**：
  - Q1 触发范围：哪些事件要通知？（新邀请 / 邀请被接受拒绝 / 对方新评论 / 历史访问请求）
  - Q2 交付方式：静默推送+本地通知（推荐，内容可定制）vs 直接 CKSubscription alert（内容受限、共享 zone 可靠性存疑）。
  - Q3 范围与阶段：v1 必须有推送，还是先做 idea-001 的 in-app 动态+角标、推送作为 phase 2？
  - Q4 APNs 环境：dev/prod entitlements 已分离，需确认 TestFlight(prod) 推送链路与证书。
- **依赖**：通知文案/触发器依赖 idea-001 定义「什么算一条动态」。
- **建议提升目标**：`plans/notifications/`（建议在 idea-001 落地后或同步规划）

---

## idea-003 App Store 截图换成新版 UI
- **录入**：2026-10-22（用户）
- **状态**：✅ 2026-10-23 完成：1.6 用官网四张渲染图（`docs/site/assets/*.webp` 居中铺到纸色画布，6.3" 1206×2622 + 6.7" 1290×2796），见 `docs/screenshots/appstore/` 与 [plans/releases/](../plans/releases/)
- **原话**：下个版本把 App Store 的截图更新成新 UI。
- **可行性快照**：官网 / README 已用 `docs/site/assets/*.webp`（由 promo 源页渲染）；App Store 需要按设备尺寸出图，可沿用同一渲染流程。

---

## idea-004 各 plan 的 Deferred 汇总（未提升）
- 周视图里共同日程块可点开评论串（calendar-ux-fixes V2）。
- 动态流内联快速回复；已读状态跨自己多设备同步（activity-feed D1/D2）。
- 共同日程评论的本地推送语义（calendar-ux-fixes / comment-visibility）。
- 评论红点的 VoiceOver 语义（comment-visibility）。
- 撤销邀请时通知对方（invitation-lifecycle）。
- 解除配对 → 换人重新配对的端到端冒烟需要第三个 iCloud 账号（pairing-sync-integrity）。
