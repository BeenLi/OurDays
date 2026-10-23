# Roadmap — code-structure

## In Progress
- （无）

## Done（2026-10-23）
- ✅ **#29 `Plans/` → `Policies/`、`…Plan` → `…Policy` 重命名**（86 个枚举；2026-10-23 用户在 Policies / Common / Routine / Utils 里选了 Policies），同时把 `CoupleCalendar/` 分成 App/ Models/ Policies/ Services/ Views/ Diagnostics/ Resources/ 七个目录（pbxproj 分组、Info.plist / entitlements 路径、冒烟脚本路径一并改）。#29 自带 CLAUDE.md / README 更新；本树里仍存在的类型名已同步改为 `…Policy`，已删除的旧类型（如 `EventDetailInteractionPlan`）保留原名作历史记录。

## Done（2026-06 ～ 10-22）
- ✅ **#1**（2026-06-23）CI：`xcodebuild test` 加 `-retry-tests-on-failure -test-iterations 3`；三个启动相关 UI 测试的 3 s 等待改为 30 s 过渡超时。起因是过载 runner 上 `app.launch()` 等了 45 s，零改动重跑即过。
- ✅ **#8**（2026-10-22）RootView 6,079 行拆成 18 个文件进 `Views/`（RootView 只剩 tab 容器与 sheet/alert 路由）。唯一非搬动改动：`Color(hex:)` 从 file-private 改 internal。
- ✅ **#9**（2026-10-22）Models 3,395 行拆为 @Model 类 + 字符串 + 按领域的规则文件；CloudKit 记录映射独立成文件；5,670 行的单测拆成 9 个文件，77 个测试类名不变。
- ✅ **#10**（2026-10-22）删 181 行零引用代码（重设计前的日历顶栏、废弃字符串、早期"接受邀请就在默认日历建事件"的路径、CKSyncEngine 的入队方法）。
- ✅ **#12 A**（2026-10-22）CloudKit 服务 2,317 → 1,735 行：规则类型、scene delegate、分享控制器各自成文件；三个日志 helper 改 internal。
- ✅ **#13 B**（2026-10-22）AppServices 拆成 SettingsStore / SyncCoordinator / 48 行容器；EventServices 里的规则类型全部移到规则层；去掉 mirrorKey 生成、占位 member id、日历授权状态三处反向引用。
- ✅ **#14 C**（2026-10-22）`Diagnostics/`（启动参数解析、运行器、CloudKit 探针）；删从未插入过的 `CoupleSpace` / `SyncState` 两个 @Model（schema 删实体 = 轻量迁移）和四个仅测试用的静态方法。
- ✅ **#15 D**（2026-10-22）四处 `performSync()`、三处按 mirrorKey upsert、四处时间文本、十处 trim-nil-if-blank、四处每次 new 的 DateFormatter 各收成一个共享 helper（见 [0003](decisions/0003-dependency-direction-and-shared-helpers.md)）。
- ✅ **#16 E**（2026-10-22）删 CKSyncEngine 驱动；冒烟 PASS 后用户确认合并（见 [0002](decisions/0002-remove-cksyncengine-behind-smoke-gate.md)）。
- ✅ **#18**（2026-10-22）冒烟脚本启动后检查每台模拟器最近 15 分钟的 cloudd 日志，发现 AuthTokenError 2011 立即失败；`SKIP_ICLOUD_PRECHECK=1` 跳过；`docs/development.md` 记录症状与手动检查命令。
- ✅ 架构图按重构后的 main 重画（2026-10-22，项目文件 architecture/）。

## 工程备忘（跨 PR 复用）
- 叠放的 PR：CI 只对指向 main 的 PR 自动跑，叠放分支要 `gh workflow run ios-ci.yml --ref <branch>`；基 PR 合并后 GitHub 不会自动改下一个的 base，要显式 PATCH 成 main。
- `gh pr merge/view` 走 GraphQL（环境里被挡），合并用 REST `gh api repos/BeenLi/OurDays/pulls/N/merge`。
- 两个线程都要用模拟器时冒烟要串行跑（脚本会卸载重装 App）。

## Deferred
- 把 `Policies/` 按领域再拆子目录（现在是一层平铺 12 个文件），等文件继续变大再看。
