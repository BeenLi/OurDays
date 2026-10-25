# Roadmap — releases

## In Progress
- ⏳ **1.7 (build 36)**：#33 同步被取消不再显示红条 + #35 首次启动跟随系统语言、权限弹窗中文、英文隐私政策。版本号 PR #36。schema 自 1.6 无变化，不需要部署 Production。
  - App Store Connect：English (U.S.) 副标题 / 描述 / 关键词、英文隐私政策 URL `https://ourdays.cn/privacy-en.html`，主要语言改为 English (U.S.)；中英文发布说明。

- 🚧 **中国以外用英文**（[decision 0001](decisions/0001-english-outside-china.md)）：#35 首次启动跟随系统语言、权限弹窗与 App Store 语言栏加简体中文、隐私政策拆出英文页。
  - 2026-10-25：English (U.S.) 商品页文案草稿给用户确认；确认后在 App Store Connect 填写并把主要语言改为 English (U.S.)，描述与关键词随 1.7 生效。

## Done
- ✅ **1.6 (build 35)**（2026-10 上架，#27）：#7 评论头像 + #20 头像同步乒乓修复 + #21 邀请过期/撤回 + #22 重装恢复 + #23 解除配对清理 + #24 自己日程可评论；App Store 截图换成官网四张。
- ✅ **1.5 (build 34)**（2026-10-21 上架，#6）：#3 UI 重设计 + #4 配对更换修复 + #5 日视图打磨。MemberProfile 三个头像字段已部署到 Production（cktool 核对）；archive/upload → 提交审核 → 自动发布。
- ✅ **1.4 (build 33)**（2026-07 上架，#2）：评论红点 + 我的日程可看/可回评论。提交前先合并 main 修了 TestFlight 导出 internal-only 的 bug。
- ✅ **1.3 (build 27 → 30)**（2026-06）：build 27 提交公开外测（含 calendar-ux-fixes 三特性）；2026-06-22 应用改名 OurDays，以 build 30 重新提交公开 App Store 审核（见 [public-launch](../public-launch/)）。
- 早期 build 15–26（2026-06-14 ～ 06-17）：动态 tab、通知 v1–v3 的逐 build 迭代，见 [notifications](../notifications/)。

## Deferred
- 每次上架后更新官网与 README 的版本说明（[docs-and-site](../docs-and-site/)）。
