# Plan: code-structure（代码瘦身与架构重构）

2026-10-22 的两轮重构（#8–#10 瘦身、#12–#16 架构 A–E），加上围绕它们的工程设施（#1 CI 抗抖、#18 冒烟预检）。目标是让文件按职责拆开、依赖方向单一、删掉早期设计留下的死代码；全部是行为不变的搬动，除了 E 删除 CKSyncEngine。架构图与依据的分析见项目文件 architecture/。Baseline：[../../baseline/README.md](../../baseline/README.md)。

## Scope
- **瘦身**（#8 #9 #10）：RootView 拆成 `Views/` 按页面一文件；Models / CloudKit 记录映射 / 单测文件按领域拆；删零引用代码。
- **架构**（#12–#16）：A 拆 CloudKit 服务文件；B 拆 AppServices、把规则类型全部移出 EventServices、去掉 6 条"下层反向引用上层"的边；C 诊断代码归 `Diagnostics/`、删从未插入过的两个 @Model 与仅测试用的静态方法；D 视图样板、ID 归一化、DateFormatter 去重为共享 helper；E 删除从未搬运过数据的 CKSyncEngine 驱动。
- **工程设施**：#1 CI 对启动相关 UI 测试加重试与 30 s 过渡超时；#18 冒烟脚本在模拟器 iCloud token 过期（cloudd AuthTokenError 2011）时立刻失败并提示重新登录。
- **改名与分层（#29）**：`Plans/` 目录改名 `Policies/`，`…Plan` 类型改名 `…Policy`（用户 2026-10-23 选定；iOS 里 Policy 就是"给定输入决定怎么做"的纯规则）；源码按 App/ Models/ Policies/ Services/ Views/ Diagnostics/ Resources/ 分层。

## Non-goals
- 不改任何对外行为（E 除外，且 E 以两模拟器冒烟为合并门槛）。
- 不引入模块化 / SPM 拆包。

## File map
- [roadmap.md](roadmap.md)
- [decisions/0001-split-by-area-both-targets.md](decisions/0001-split-by-area-both-targets.md) — 拆分方式与 Xcode 双 target 规则
- [decisions/0002-remove-cksyncengine-behind-smoke-gate.md](decisions/0002-remove-cksyncengine-behind-smoke-gate.md) — 为什么能删、为什么要冒烟
- [decisions/0003-dependency-direction-and-shared-helpers.md](decisions/0003-dependency-direction-and-shared-helpers.md) — Views → Services → 规则 → Models，共享 helper 清单

## Status
- Status: **✅ Code landed**（瘦身与 A–E 于 2026-10-22 合并；#29 改名与分层于 2026-10-23 合并，main 602b99c）
- Evidence: 每个搬动 PR 都用"排序后的非 import 行 diff"证明纯搬动；CI 绿；E 的冒烟 2026-10-22 PASS（5 min 19 s）。重构后 0 条文件级反向引用，App 代码 14,657 行，最大文件 CloudKit 服务 1,551 行。
