# Decision 0001 — 按领域拆文件，纯搬动可证明，非 UI 文件进两个 target

- **日期**：2026-10-22　**状态**：Accepted，#8 #9 #12 #13 #14 已落地

## 背景（原本的工作方式）
App 代码集中在几个巨型文件：RootView 6,079 行装着所有页面，Models 3,395 行装着 @Model 类、字符串和几十个规则枚举，CloudKit 服务 2,317 行装着 20 个规则枚举、scene delegate、分享控制器；单测是一个 5,670 行的文件。Xcode 工程用的是 legacy PBXGroup，测试 target 直接编译 App 的非 UI 源码而不是 `@testable import`。

## 决策
1. **按领域拆**：页面一文件进 `Views/`；规则类型按领域一文件；记录映射、诊断、设置存储、同步协调各自成文件；单测按同样的领域拆成 9 个文件，类名不改以保留 `-only-testing:` 路径。
2. **纯搬动要可证明**：每个搬动 PR 把前后所有非 import、非空行排序后 diff，差异必须为零（或逐行列出）。
3. **双 target 规则**：新增的非 UI 源文件必须同时加进 App 和 Test 两个 Sources phase；UI 文件只进 App。否则测试会悄悄编不过。
4. 诊断代码（启动参数驱动、探针）集中在 `Diagnostics/`，正常运行不使用。

## 备选与理由
- (否决) 改成 Xcode 16 的 file-system-synchronized group：一次性迁移风险大，且与现有 pbxproj 脚本不兼容；留作以后。
- (否决) 先拆成 SPM 模块：目标是可读性，不是编译隔离。

## 影响
- `CLAUDE.md` 列出了每个目录放什么，以及双 target 规则。
- 删掉的 `CoupleSpace` / `SyncState` 两个 @Model 从未插入过，删实体是轻量迁移，升级安装不受影响。
