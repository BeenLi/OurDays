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
| [notifications](plans/notifications/) | ✅ v3 Code landed | landed | 2026-06-16, 236 tests pass（v3） | 两真机端到端验证（事件改动不弹、评论/邀请弹、审批+邀请不回退且失败上传自愈、角标自清） |
| [public-launch](plans/public-launch/) | 🚧 In Progress | Track B/C 已上线；Track A v1.3 build 27 提交外测 | 2026-06-20：v1.3 (build 27) 上传 VALID + 加入外测组 `friends` + 提交 Beta Review（WAITING_FOR_REVIEW）。含 calendar-ux-fixes 三特性 | build 27 审核通过 → 公开链接自动服务 |
| [calendar-ux-fixes](plans/calendar-ux-fixes/) | ✅ 已发布 | 3 phase 落地 + 两真机 e2e 跑通；已随 v1.3 build 27 提交公开外测 | 2026-06-20：commit `aadd4bb`，推 origin/main，archive+upload，build 27 VALID 提交 Beta Review | （可选）周视图 joint 点击 Deferred；离线乐观自愈分支单独验 |
| [comment-visibility](plans/comment-visibility/) | ✅ 已提交 App Store 审核 | 代码+回归+新路径均验证；随 v1.4 build 33 提交 | 2026-07-04：合并 main → build 33（修 TestFlight 导出 internal-only bug）→ archive/upload → v1.4 提交 App Store（WAITING_FOR_REVIEW，发布说明含评论功能） | Apple 审核通过 → 手动发布上线 |
| v1.5 release（PR #3 UI 重设计 + #4 配对更换修复 + #5 日视图打磨） | 🚧 已上传 App Store Connect | 1.5 (build 34) 已 archive + upload，处理中 | 2026-10-21：三个 PR 合并 main；`MemberProfile.avatar*` 三字段已部署到 Production（cktool 核对）；archive/upload 成功 | build 34 处理完成 → 填发布说明 → 提交 App Store 审核 |

顺序：先 activity-feed，后 notifications（用户决定，2026-06-14）。v2（上线后反馈修复）见 [decision 0002](plans/notifications/decisions/0002-silent-push-and-background-sync.md)（2026-06-16）。

## Ideas
- [ideas/inbox.md](ideas/inbox.md) — 待澄清/提升的想法
