# Decision 0002 — 邀请乐观发送 + 后台上传 + 失败自愈

- **日期**: 2026-06-20
- **状态**: Accepted（用户在澄清问题中选定「乐观发送，后台上传+自愈（推荐）」）
- **范围**: req2 / Phase 2

## 背景
`createInvite()` 本地已即时落库，但把 CloudKit 上传往返放在了成功 UI 的关键路径上，用户感知「等待太久」。

## 决策
1. 本地 `save()` 成功即显示「已发送」并允许关闭；CloudKit 上传转后台。
2. 上传失败不回滚本地邀请，由下次 `foregroundSync` 自愈重传。
3. 为安全实现 (2)，**先补「新建邀请上传失败自愈」路径**（现有 reupload 只覆盖响应，不覆盖创建），再做乐观化。

## 理由
- 体验最快；与项目既有「本地缓存 + 同步流水线自愈」架构一致（SwiftData 为本地缓存，CloudKit 为真相同步层）。
- 幂等：重传走 upsert，recordName=`invitation.id`，不会重复。

## 影响
- 改 `EventDetailView.createInvite()` 的时序与错误处理（错误从「阻断成功」改为「非阻断 + 自愈」）。
- 新增/扩展 reupload Plan + 单测；接入 `foregroundSync`。
- 风险见 [topics/req2-optimistic-invite.md](../topics/req2-optimistic-invite.md)。
