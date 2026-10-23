# Roadmap — invitation-lifecycle

## Done
- ✅ **#21**（2026-10-23）已结束不可邀、待处理会过期、发起方可撤销。→ [0001](decisions/0001-ended-expired-withdraw.md)
- ✅ 冒烟 step 11：`-ShareCalWithdrawInvitation <id>` / `-ShareCalProbeInvitations`；必须排在 XCUITest 步骤之后（同标题的已取消邀请会排到已接受那行上面）。

## Deferred
- 撤销时给对方一条本地通知：只有当"创建者取消"与"本地事件消失导致取消"需要区分时再加。
- partner 模拟器的 zone 每跑一次冒烟会累积 2 条邀请，无害，可在 reset 步骤清理。
