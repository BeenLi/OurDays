# Plan Tree — OurDays（原 ShareCal / CoupleCalendar）

planning 总入口（registry）。这里只放**持久的方向、决策、进度与未决问题**，不放一次性会话内容。

## 如何阅读
1. 先读本文件（registry + authority order）。
2. 读 `baseline/README.md` 了解项目结构边界。
3. 读相关 plan root（见下表）或 `ideas/inbox.md`。

## Authority order（权威顺序，冲突时以高者为准）
1. 代码本身 + 仓库根 `CLAUDE.md`（架构铁律：两人制、userRecordID 身份模型、Policy enum 约定）。
2. `baseline/`（从代码归纳出的稳定上下文）。
3. 各 plan root 的 `decisions/` > `roadmap.md` > `topics/`。
4. `ideas/inbox.md`（低承诺想法，未提升前不算计划）。

> `CLAUDE.md` 是项目的权威 baseline，本树**链接**它而不复制其内容。

## Baseline
- [baseline/README.md](baseline/README.md)

## Active plans
| Plan | Status | Current Phase | Last Landed | Next Target |
|------|--------|---------------|-------------|-------------|
| [releases](plans/releases/) | 🚧 1.7 审核中 | 1.7 (build 36)：#33 同步取消修复 + #35 跟随系统语言 / 中文权限弹窗 / 英文隐私政策；App Store 主要语言改 English (U.S.) | 2026-10-25：1.6 已上架；#36 版本号 | 过审自动上架后把主要语言改为 English (U.S.) |
| [docs-and-site](plans/docs-and-site/) | 🚧 In Progress | README 已对齐 main 至 #29 | 2026-10-23：#28 代码结构合成一棵树；#29 随改名更新 README / CLAUDE.md | 1.6 上架后刷新官网与 README 的版本说明 |

## Landed plans（已落地 / 已发布，只在回归时回看）
| Plan | Status | 发布于 | 备注 |
|------|--------|--------|------|
| [code-structure](plans/code-structure/) | ✅ Code landed | 1.6 起 | 瘦身 #8–#10、架构 A–E #12–#16、`Plans/` → `Policies/` 改名与分层目录 #29、工程改名 OurDays #37 |
| [pairing-sync-integrity](plans/pairing-sync-integrity/) | ✅ Code landed | #4 随 1.5；#20 #22 #23 随 1.6；#38 #39 #40 #41 #43 #44 待发布 | 配对冲突改由用户选择；共享记录只在变化时保存；重装恢复；解除配对清理前任数据；邀请链接的 iCloud 检查与粘贴入口；配对引导 |
| [invitation-lifecycle](plans/invitation-lifecycle/) | ✅ Code landed | 1.6 | 已结束的日程不可邀请、待处理邀请会过期、发起方可撤销 |
| [comment-visibility](plans/comment-visibility/) | ✅ 已发布 + 扩展 | 1.4；#24 随 1.6 | 评论红点、我的日程可看/可回评论；#24 起未同步也可先发起评论 |
| [ui-redesign](plans/ui-redesign/) | ✅ 已发布 | 1.5；#7 随 1.6 | 「纸上双线」视觉、身份泳道、头像同步、日视图打磨 |
| [calendar-ux-fixes](plans/calendar-ux-fixes/) | ✅ 已发布 | 1.3 | 今天红线、邀请乐观发送、共同日程可评论 |
| [notifications](plans/notifications/) | ✅ 已发布 | 1.3 | 静默推送 + 后台同步 + 本地通知；两机端到端已自动化（2026-06-17） |
| [activity-feed](plans/activity-feed/) | ✅ 已发布 | 1.3 | 「动态」tab；1.5 改为按天分组的聊天卡片样式 |
| [public-launch](plans/public-launch/) | 📦 Archived | — | 外部 TestFlight 已被 App Store 上架取代；介绍页/域名部分由 docs-and-site 接管 |

顺序：先 activity-feed，后 notifications（用户决定，2026-06-14）。v2（上线后反馈修复）见 [decision 0002](plans/notifications/decisions/0002-silent-push-and-background-sync.md)（2026-06-16）。

## PR 索引（#1 起，按主题归档）
每个 PR 自己那一行的合并列写「本 PR」，合并后由下一个 PR 改成日期，避免留下过期的"未合并"。
每个 PR 的详细"原本怎样 / 为什么改 / 改成怎样"记在对应 plan 的 `decisions/`；这里只做查找表。

| PR | 合并 | 主题 | 归属 plan |
|----|------|------|-----------|
| #1 | 2026-06-23 | CI：启动相关 UI 测试加重试与更长过渡超时 | [code-structure](plans/code-structure/roadmap.md) |
| #2 | 2026-07-04 | 评论红点 + 我的日程可看/可回评论 | [comment-visibility](plans/comment-visibility/) |
| #3 | 2026-10-21 | 「纸上双线」UI 重设计 + 头像自定义与同步 | [ui-redesign](plans/ui-redesign/) |
| #4 | 2026-10-21 | 配对更换：不再静默踢人，改为冲突弹窗由用户选择 | [pairing-sync-integrity](plans/pairing-sync-integrity/) |
| #5 | 2026-10-21 | 日视图打磨：打开定位、共享块让位、配对第 1 天 | [ui-redesign](plans/ui-redesign/) |
| #6 | 2026-10-21 | 版本号 1.5 (34) | [releases](plans/releases/) |
| #7 | 2026-10-21 | 我的评论气泡旁显示自己的头像 | [ui-redesign](plans/ui-redesign/) |
| #8–#10 | 2026-10-22 | 拆分 RootView / Models / 测试文件；删零引用代码 | [code-structure](plans/code-structure/) |
| #11 | 2026-10-22 | ourdays.cn 官网换 1.5 截图与文案 | [docs-and-site](plans/docs-and-site/) |
| #12–#16 | 2026-10-22 | 架构重构 A–E（拆 CloudKit 服务、拆 AppServices、Diagnostics/、去重、删 CKSyncEngine） | [code-structure](plans/code-structure/) |
| #17 | 2026-10-22 | README：badge、定位语、重构后的代码结构 | [docs-and-site](plans/docs-and-site/) |
| #18 | 2026-10-22 | 冒烟脚本：模拟器 iCloud token 过期时快速失败 | [code-structure](plans/code-structure/roadmap.md) |
| #19 | 2026-10-23 | README 截图换成新版 UI | [docs-and-site](plans/docs-and-site/) |
| #20 | 2026-10-23 | 根记录 / MemberProfile 只在真正变化时保存（消除推送乒乓） | [pairing-sync-integrity](plans/pairing-sync-integrity/) |
| #21 | 2026-10-23 | 邀请生命周期：已结束不可邀、待处理会过期、发起方可撤销 | [invitation-lifecycle](plans/invitation-lifecycle/) |
| #22 | 2026-10-23 | 删除重装后从 iCloud 恢复；消失的自有事件打墓碑 | [pairing-sync-integrity](plans/pairing-sync-integrity/) |
| #23 | 2026-10-23 | 解除配对时清掉前任留下的记录，导入时过滤 | [pairing-sync-integrity](plans/pairing-sync-integrity/) |
| #24 | 2026-10-23 | 自己的日程未同步也可先发起评论 | [comment-visibility](plans/comment-visibility/) |
| #25 | 2026-10-23 | README 全面更新（同步架构、记录类型、代码结构） | [docs-and-site](plans/docs-and-site/) |
| #26 | 2026-10-23 | README 精简同步架构、重画图、新增数据安全 | [docs-and-site](plans/docs-and-site/) |
| #27 | 2026-10-23 | 版本号 1.6 (35) | [releases](plans/releases/) |
| #28 | 2026-10-23 | README 代码结构合成一棵树 | [docs-and-site](plans/docs-and-site/) |
| #29 | 2026-10-23 | `Plans/` → `Policies/`、`…Plan` → `…Policy`；源码按 App/ Models/ Policies/ Services/ Views/ Diagnostics/ Resources/ 分目录 | [code-structure](plans/code-structure/) |
| #30 | 2026-10-23 | plantree 补录 PR #1–#28，归档过时的 plan | [docs-and-site](plans/docs-and-site/) |
| #31 | 2026-10-23 | CI 提速：文档改动不触发、PR 只跑单元测试、模拟器开机与编译并行 | [code-structure](plans/code-structure/roadmap.md) |
| #32 | 2026-10-23 | plantree：#27、#31 标为已合并，releases 状态改为审核中 | [code-structure](plans/code-structure/roadmap.md) |
| #33 | 2026-10-25 | 同步被取消不再显示红条「Operation … was cancelled」；界面触发的同步不随视图消失而取消 | [pairing-sync-integrity](plans/pairing-sync-integrity/decisions/0005-cancelled-sync-is-not-a-failure.md) |
| #34 | 2026-10-25 | README 增加英文版 README.en.md（含英文版两张架构图 docs/diagrams/*.en.*），中英文顶部互相切换 | [docs-and-site](plans/docs-and-site/) |
| #35 | 2026-10-25 | 中国以外用英文：首次启动跟随系统语言；权限弹窗与 App Store 语言栏加简体中文；隐私政策加英文页 | [releases](plans/releases/decisions/0001-english-outside-china.md) |
| #36 | 2026-10-25 | 版本号 1.7 (36)；英文界面截图（App Store 英文页、README.en.md） | [releases](plans/releases/) |
| #37 | 2026-10-25 | Xcode 工程、target、scheme、目录 `CoupleCalendar` → `OurDays`；bundle ID、iCloud 容器、BGTask 标识、日志 subsystem 保持不变 | [code-structure](plans/code-structure/roadmap.md) |
| #38 | 2026-10-29 | 邀请链接提示登录 iCloud：去掉"仅限受邀的人"、未配对时检查本 App 的 iCloud、粘贴邀请链接入口 | [pairing-sync-integrity](plans/pairing-sync-integrity/roadmap.md) |
| #39 | 2026-10-29 | 配对引导：四步进度卡、自己的邀请页与分享文案、收下后提示回发、打不开链接帮助页 | [pairing-sync-integrity](plans/pairing-sync-integrity/decisions/0007-pairing-guide-two-letters.md) |
| #40 | 2026-10-29 | 解除配对两边一起解除：同时退出对方的分享，对方回到未配对而不是停在「等待对方共享」 | [pairing-sync-integrity](plans/pairing-sync-integrity/roadmap.md) |
| #41 | 2026-10-29 | 被对方解除配对：不再误弹「回发邀请」，撤回我的分享，两边都回到第 1 步 | [pairing-sync-integrity](plans/pairing-sync-integrity/roadmap.md) |
| #42 | 2026-10-29 | 冒烟脚本：「Own Comment Event」每次用唯一标题并在用完后删除，评论自己事件那一步不再取到旧事件 | [code-structure](plans/code-structure/roadmap.md) |
| #43 | 2026-10-29 | 配对引导打磨：邀请页即点即开、取消不进到下一步、第 4 步标签、日历页小提示、回发提示带昵称 | [pairing-sync-integrity](plans/pairing-sync-integrity/roadmap.md) |
| #44 | 本 PR | 「粘贴邀请链接」入口在发出邀请后也保留（第 2、3 步），回寄的链接也能粘贴；粘贴识别中国区 icloud.com.cn 链接；解除配对时不再被正在进行的同步写回「邀请已寄出」；粘贴改为输入框 + 确认 | [pairing-sync-integrity](plans/pairing-sync-integrity/roadmap.md) |

## Ideas
- [ideas/inbox.md](ideas/inbox.md) — 待澄清/提升的想法
