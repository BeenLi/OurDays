# Plan: ui-redesign（「纸上双线」）

1.5 的整体视觉重设计，加上随后的日视图打磨与评论气泡头像。设计稿由用户确认（2026-10-21）。Baseline：[../../baseline/README.md](../../baseline/README.md)。

## Scope
- **视觉系统**：纸色底 + 墨色文字，身份色固定为「我 = 青色、对方 = 珊瑚色」，标题与数字用衬线字体；主题集中在 `Views/DesignSystem.swift`。
- **日历**：日视图两条身份泳道，共同日程横跨两条；空闲的夜间时段折叠成「双方空闲」带；周条按人显示事件圆点。
- **其他页面**：动态改为按天分组的聊天卡片；邀请改为票据样式；设置页改名「我们」，顶部配对大卡片，解除配对放最底部；事件详情新头部 + 评论气泡。
- **头像**：照片或文字 + 背景色，经 MemberProfile 同步给对方；可以给对方设一个只有自己看得到的本地头像。
- **打磨（#5、#7）**：日视图打开定位、共享块与单方事件重叠时让位、「配对第 1 天」起算、我的评论气泡旁也显示头像。

## Non-goals
- 不动身份模型 / 同步管线（头像只是 MemberProfile 多三个字段）。
- 不做深色模式专门设计（跟随系统）。

## File map
- [roadmap.md](roadmap.md)
- [decisions/0001-paper-lines-palette-and-identity.md](decisions/0001-paper-lines-palette-and-identity.md) — 调色板与身份色
- [decisions/0002-avatar-sync-with-local-override.md](decisions/0002-avatar-sync-with-local-override.md) — 头像「同步 + 本地覆盖」
- [decisions/0003-joint-block-yields-half-lane.md](decisions/0003-joint-block-yields-half-lane.md) — 共享块让位的规则（App 与宣传片的差异）

## Status
- Status: **✅ 已发布**（#3 #5 随 1.5 于 2026-10-21 上架；#7 随 1.6）
- Evidence: #3 单元测试 271 全过（新增 16），两模拟器冒烟通过；CloudKit Production schema 的三个头像字段 2026-10-21 用 cktool 核对已部署。
