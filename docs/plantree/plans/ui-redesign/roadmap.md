# Roadmap — ui-redesign

## Done
- ✅ **#3 重设计 + 头像**（2026-10-21）：调色板、身份泳道、夜间折叠、周条圆点、动态/邀请/我们/详情四个页面重做；头像照片或文字 + 背景色，同步字段 `avatarImage` / `avatarText` / `avatarBackground`；Production schema 未部署时保存会去掉头像字段重试。
- ✅ **#5 日视图打磨**（2026-10-21）：打开位置 = 今天停在当前时间、别的日子停在第一条有时间的事件、没有事件回 08:00（上方留 30 分钟）；共享块与某一侧泳道事件重叠时让出外侧一半（见 [decision 0003](decisions/0003-joint-block-yields-half-lane.md)）；「配对第 N 天」从 1 起算（D+N 形式仍用过去整天数）。
- ✅ **#7 我的评论头像**（2026-10-21）：我的气泡右侧显示青色描边头像，与对方左侧的珊瑚色头像对称；纯视图改动。

## Verify
- ✅ 两模拟器冒烟（配对、双向同步、对方日历渲染、共同日程评论）在 #3 后通过。
- ⚠️ 1.5 上线后用户反馈对方头像到得很慢 → 根因不在头像，而是同步推送乒乓，见 [pairing-sync-integrity decision 0002](../pairing-sync-integrity/decisions/0002-save-shared-records-only-on-change.md)。

## Deferred
- 宣传片（项目文件 promo-video/）里的共享块是横跨两条泳道不让位的，与 App 的让位规则不同；宣传片是用户明确要的，不改。
- App Store 截图换新 UI → [ideas idea-003](../../ideas/inbox.md)。
