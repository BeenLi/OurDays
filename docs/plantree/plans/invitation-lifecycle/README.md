# Plan: invitation-lifecycle（邀请的时间性与撤销）

邀请是"提议一件还没发生的事"，所以时间应当是它生命周期的一部分。起因：用户 2026-10-23 发现一条 10 月 15 日的邀请还挂在待处理里，并想要一个收回未答复邀请的办法。Baseline：[../../baseline/README.md](../../baseline/README.md)。

## Scope（#21）
- 已结束的日程不能再发起邀请：事件详情隐藏邀请区；创建邀请的表单拒绝结束时间已过的草稿。
- 待处理且事件已结束的邀请显示为「已过期」：进「已处理」、不可答复、不计入角标，两端一致。
- 发起方可以「撤销邀请」：仅限待处理且未过期的邀请。

## Non-goals
- 撤销时不通知对方（对方只在「已处理」里看到已取消）。
- 不改邀请记录的 schema。

## File map
- [roadmap.md](roadmap.md)
- [decisions/0001-ended-expired-withdraw.md](decisions/0001-ended-expired-withdraw.md)

## Status
- Status: **✅ Code landed**（2026-10-23，随 1.6）
- Evidence: 单元测试 298 全过（新增 9）；两模拟器冒烟通过，并新增 step 11 覆盖撤销（owner 撤销 → partner 看到已取消）。
