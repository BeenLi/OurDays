# Decision 0002 — 头像：同步给对方 + 本地覆盖，优先级与昵称一致

- **日期**：2026-10-21　**状态**：Accepted，#3 已落地
- **范围**：MemberProfile、设置页头像编辑、所有头像显示位置

## 背景
昵称已经是"对方同步来的昵称 < 我本地给对方设的备注名"两层。头像要不要同步、要不要允许本地覆盖，用户选了"同步 + 本地覆盖"。

## 决策
1. 头像有两种形态：照片，或文字 + 背景色。
2. 通过 MemberProfile 新增三个字段同步：`avatarImage`（BYTES）、`avatarText`、`avatarBackground`。
3. 显示优先级与名字相同：**我本地给对方设的头像 > 对方同步来的头像 > 首字母**。本地覆盖只存在本机 UserDefaults。
4. 保存 MemberProfile 时若 CloudKit 返回 `invalidArguments`（Production schema 还没部署这三个字段），去掉头像字段重试，昵称同步不受影响。

## 影响
- 发 TestFlight / App Store 前必须先把 schema 部署到 Production（1.5 已于 2026-10-21 部署并核对）。
- 删除重装后本地覆盖会丢；对方同步来的头像会回来（见 [pairing-sync-integrity decision 0003](../../pairing-sync-integrity/decisions/0003-reinstall-recovers-from-icloud.md)）。
