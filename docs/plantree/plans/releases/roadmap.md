# Roadmap — releases

## In Progress
- ⏳ **1.6 (build 35)**：#7 评论头像 + #20 头像同步乒乓修复 + #21 邀请过期/撤回 + #22 重装恢复 + #23 解除配对清理 + #24 自己日程可评论。版本号 PR #27（基于 #26 之后的 main）。schema 自 1.5 无变化，不需要部署 Production。
  - 2026-10-23：build 35 archive + upload 成功；App Store Connect 新建 1.6，选好构建 35，中英文发布说明已填；截图换成官网四张（日视图、评论、配对、我们），6.3" 与 6.7" 两组，见 `docs/screenshots/appstore/`，旧的 6.5" 截图已从 1.6 移除（[idea-003](../../ideas/inbox.md) ✅）。
  - 2026-10-23：中文描述里的 ShareCal 改为 OurDays；用户确认后提交 App 审核（WAITING_FOR_REVIEW，审核通过后自动发布）。
  - 下一步：审核通过 → 自动上架。

- 🚧 **中国以外用英文**（[decision 0001](decisions/0001-english-outside-china.md)）：#35 首次启动跟随系统语言、权限弹窗与 App Store 语言栏加简体中文、隐私政策拆出英文页。
  - 2026-10-25：English (U.S.) 商品页文案草稿给用户确认；确认后在 App Store Connect 填写并把主要语言改为 English (U.S.)，描述与关键词随 1.7 生效。

## Done
- ✅ **1.5 (build 34)**（2026-10-21 上架，#6）：#3 UI 重设计 + #4 配对更换修复 + #5 日视图打磨。MemberProfile 三个头像字段已部署到 Production（cktool 核对）；archive/upload → 提交审核 → 自动发布。
- ✅ **1.4 (build 33)**（2026-07 上架，#2）：评论红点 + 我的日程可看/可回评论。提交前先合并 main 修了 TestFlight 导出 internal-only 的 bug。
- ✅ **1.3 (build 27 → 30)**（2026-06）：build 27 提交公开外测（含 calendar-ux-fixes 三特性）；2026-06-22 应用改名 OurDays，以 build 30 重新提交公开 App Store 审核（见 [public-launch](../public-launch/)）。
- 早期 build 15–26（2026-06-14 ～ 06-17）：动态 tab、通知 v1–v3 的逐 build 迭代，见 [notifications](../notifications/)。

## Deferred
- 每次上架后更新官网与 README 的版本说明（[docs-and-site](../docs-and-site/)）。
