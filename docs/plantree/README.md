# Plan Tree — ShareCal / CoupleCalendar

planning 总入口（registry）。这里只放**持久的方向、决策、进度与未决问题**，不放一次性会话内容。

## 如何阅读
1. 先读本文件（registry + authority order）。
2. 读 `baseline/README.md` 了解项目结构边界。
3. 读相关 plan root（见下表）或 `ideas/inbox.md`。

## Authority order（权威顺序，冲突时以高者为准）
1. 代码本身 + 仓库根 `CLAUDE.md`（架构铁律：两人制、userRecordID 身份模型、Plan enum 约定）。
2. `baseline/`（从代码归纳出的稳定上下文）。
3. 各 plan root 的 `decisions/` > `roadmap.md` > `topics/`。
4. `ideas/inbox.md`（低承诺想法，未提升前不算计划）。

> `CLAUDE.md` 是项目的权威 baseline，本树**链接**它而不复制其内容。

## Baseline
- [baseline/README.md](baseline/README.md)

## Active plans
| Plan | Status | Current Phase | Last Landed | Next Target |
|------|--------|---------------|-------------|-------------|
| [activity-feed](plans/activity-feed/) | ✅ Done | landed | 2026-06-14, 215 tests pass | — |
| [notifications](plans/notifications/) | ✅ v3 Code landed | landed | 2026-06-16, 230 tests pass（v3） | 两真机端到端验证（事件改动不弹、评论/邀请弹、审批+邀请不回退、角标自清） |

顺序：先 activity-feed，后 notifications（用户决定，2026-06-14）。v2（上线后反馈修复）见 [decision 0002](plans/notifications/decisions/0002-silent-push-and-background-sync.md)（2026-06-16）。

## Ideas
- [ideas/inbox.md](ideas/inbox.md) — 待澄清/提升的想法
