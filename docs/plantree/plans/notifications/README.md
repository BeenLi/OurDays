# Plan: notifications（系统级提醒）

由 [idea-002](../../ideas/inbox.md) 提升而来。Baseline：[../../baseline/README.md](../../baseline/README.md)。

## Scope
把关键双人事件做成 App 系统级通知。触发范围（用户确认，全选）：
1. 对方评论了我的日程
2. 收到新邀请
3. 我的邀请被接受 / 拒绝
4. 历史访问请求 / 其回复

## Status
- Status: **✅ 已发布**（v3 随 build 23+ / v1.3 上架；两机端到端验证已于 2026-06-17 自动化进冒烟脚本 step 7，见 [decisions/0003](decisions/0003-post-22-feedback-fixes.md)）。1.5 起这些通知在 App Store 版本上运行，未再收到相关反馈。
- 历史：**✅ v2 Code landed（2026-06-16）** — 上线后两条反馈（幻影动态推送 + 后台同步）已落地，见 [decisions/0002](decisions/0002-silent-push-and-background-sync.md)；220 单测全过。**剩**：两真机端到端验证（见 [roadmap](roadmap.md)「Needs manual verification」v2）。
- 前序：v1 交付架构 **✅ Code landed（2026-06-14）** — 纯逻辑 9 单测通过、全套 215 通过、模拟器启动无崩溃。
- 依赖 [../activity-feed/](../activity-feed/) 已完成。

## File map
- [roadmap.md](roadmap.md)
- [decisions/0001-triggers-and-delivery.md](decisions/0001-triggers-and-delivery.md) — 触发范围 + 交付架构（v1）
- [decisions/0002-silent-push-and-background-sync.md](decisions/0002-silent-push-and-background-sync.md) — 改静默推送（抑制纯事件推送）+ 后台同步（v2，反馈修复）
- [decisions/0003-post-22-feedback-fixes.md](decisions/0003-post-22-feedback-fixes.md) — build-22 后反馈：图标角标残留 + 访问请求审批回退（v3）

## 现状（2026-10-23）
- 静默推送（private + shared 两条 CKDatabaseSubscription）唤醒 App → 拉取变更 → 本地通知；BGAppRefresh 兜底。2026-06-14 之前的『dead code』现状已不存在。
- 推送乒乓（每次同步都重写共享记录导致两机互相唤醒）已在 #20 修复，见 [pairing-sync-integrity decision 0002](../pairing-sync-integrity/decisions/0002-save-shared-records-only-on-change.md)。

## Open questions
- ~~OQ1 核实 `remote-notification` 后台模式~~ → 已在 Info.plist（roadmap v1）。
- OQ2 APNs 生产链路：App Store 版本已在线运行数月，未单独做过生产链路的对照验证。
- ~~OQ3 静默推送的系统节流与 App 被杀时的可靠性，是否需要兜底~~ → **已解决（[0002](decisions/0002-silent-push-and-background-sync.md)）**：接受可靠性上限（前台打开是唯一保证），加 `BGAppRefreshTask` 兜底收窄窗口。
- OQ4 通知与 in-app 角标的去重 / 已读联动。
- ~~OQ5 两端各自在 private database 上订阅~~ → 已实现（private + shared 两条订阅，每次启动重配）。
