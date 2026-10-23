# Roadmap — releases

## In Progress
- 🚧 **1.6 (build 35)**：#7 评论头像 + #20 头像同步乒乓修复 + #21 邀请过期/撤回 + #22 重装恢复 + #23 解除配对清理 + #24 自己日程可评论。版本号 PR #27（基于 #26 之后的 main）。schema 自 1.5 无变化，不需要部署 Production。
  - 下一步：archive/upload → 更新 App Store 截图（[idea-003](../../ideas/inbox.md)）→ 填发布说明 → 提交审核（自动发布）。

## Done
- ✅ **1.5 (build 34)**（2026-10-21 上架，#6）：#3 UI 重设计 + #4 配对更换修复 + #5 日视图打磨。MemberProfile 三个头像字段已部署到 Production（cktool 核对）；archive/upload → 提交审核 → 自动发布。
- ✅ **1.4 (build 33)**（2026-07 上架，#2）：评论红点 + 我的日程可看/可回评论。提交前先合并 main 修了 TestFlight 导出 internal-only 的 bug。
- ✅ **1.3 (build 27 → 30)**（2026-06）：build 27 提交公开外测（含 calendar-ux-fixes 三特性）；2026-06-22 应用改名 OurDays，以 build 30 重新提交公开 App Store 审核（见 [public-launch](../public-launch/)）。
- 早期 build 15–26（2026-06-14 ～ 06-17）：动态 tab、通知 v1–v3 的逐 build 迭代，见 [notifications](../notifications/)。

## Deferred
- 每次上架后更新官网与 README 的版本说明（[docs-and-site](../docs-and-site/)）。
