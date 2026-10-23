# Plan: pairing-sync-integrity（配对与同步的正确性）

四个在 1.5 上线前后发现、彼此相关的问题：配对更换时把人踢光、同步推送互相唤醒、删除重装后数据状态不对、解除配对后前任的记录泄露给下一任。共同点是它们都源于"两人制 + 单个共享根记录"这个结构，所以放在同一个 plan 里。Baseline：[../../baseline/README.md](../../baseline/README.md)。

## Scope
- **#4 配对更换**：我方分享出现伴侣之外的参与者时不再静默移除，改为配对冲突弹窗由用户选择保留谁。
- **#20 推送乒乓**：根记录和 MemberProfile 只在字段真正变化时保存。
- **#22 删除重装**：从 iCloud 恢复配对、身份、配对日期；卸载期间删掉的自有事件在云端打墓碑；恢复提示把「继续使用」放第一位。
- **#23 解除配对**：删掉我 zone 里与前任有关的评论、邀请、历史访问申请；导入时过滤既不是我也不是现任的记录。

## Non-goals
- 不改两人制身份模型（仍无 pairingID、无本地 UUID 身份）。
- 不改 CloudKit schema（1.5 以来没有 schema 变化，1.6 不需要部署 Production）。

## File map
- [roadmap.md](roadmap.md)
- [decisions/0001-conflict-alert-not-silent-lock.md](decisions/0001-conflict-alert-not-silent-lock.md)
- [decisions/0002-save-shared-records-only-on-change.md](decisions/0002-save-shared-records-only-on-change.md)
- [decisions/0003-reinstall-recovers-from-icloud.md](decisions/0003-reinstall-recovers-from-icloud.md)
- [decisions/0004-ex-partner-data-purged-and-filtered.md](decisions/0004-ex-partner-data-purged-and-filtered.md)

## Status
- Status: **✅ Code landed**（#4 随 1.5 上架；#20 #22 #23 合并 2026-10-23，随 1.6）
- Evidence: 各 PR 单元测试全过；#22 的冒烟 step 12（卸载 owner → 重装 → 恢复）在两模拟器上通过（恢复 tombstones=6、comments=26、invitations=19）。
- 未端到端验证：#4 的冲突弹窗、#23 的解除配对 → 换人重配，都需要第三个 iCloud 账号（见 [ideas idea-004](../../ideas/inbox.md)）。
