# Plan Tree — 设计决策记录

这里只放**决策**：某个行为原本怎么工作、为什么改、改成什么、放弃了哪些方案。这些在 git diff 和 PR 描述里是散的，拼不回来。

PR 列表、版本进度、待办不放这里：PR 看 GitHub，进度看 `git log`，架构铁律看仓库根 `CLAUDE.md`（冲突时以代码和 `CLAUDE.md` 为准）。

## 什么时候写
一个 PR 改了用户可见的行为、同步/配对/CloudKit 的规则，或者否决了一个看起来更顺手的方案时，在对应主题下新增 `plans/<主题>/decisions/NNNN-<slug>.md`（编号接着该目录往下排）。纯重构、文案、截图、版本号不写。

格式：

```markdown
# Decision NNNN — 一句话标题

- **日期**：YYYY-MM-DD　**状态**：Accepted（被取代时写 Superseded by NNNN）　**PR**：#N

## 背景（原本的工作方式）
## 决策
## 备选与理由
## 影响
```

已有的 decision 不改写；结论变了就新写一篇，并把旧的状态改成 Superseded。

## 主题
| 主题 | 范围 |
|------|------|
| [pairing-sync-integrity](plans/pairing-sync-integrity/decisions/) | 配对、解除配对、配对冲突、共享记录的保存与导入、重装恢复、邀请链接 |
| [invitation-lifecycle](plans/invitation-lifecycle/decisions/) | 共同日程邀请：何时可邀、过期、撤销 |
| [comment-visibility](plans/comment-visibility/decisions/) | 评论红点、谁的日程能评论 |
| [activity-feed](plans/activity-feed/decisions/) | 「动态」tab 的内容与未读 |
| [notifications](plans/notifications/decisions/) | 静默推送、后台同步、本地通知 |
| [calendar-ux-fixes](plans/calendar-ux-fixes/decisions/) | 共同日程评论串、邀请乐观发送 |
| [ui-redesign](plans/ui-redesign/decisions/) | 视觉、身份颜色、头像、日视图布局 |
| [code-structure](plans/code-structure/decisions/) | 目录分层、依赖方向、测试 target |
| [docs-and-site](plans/docs-and-site/decisions/) | README 风格、截图来源 |
| [releases](plans/releases/decisions/) | 上架、语言与地区 |
| [public-launch](plans/public-launch/decisions/) | 已归档：外部 TestFlight 与早期介绍页 |

新主题直接建目录，再在上表加一行。
