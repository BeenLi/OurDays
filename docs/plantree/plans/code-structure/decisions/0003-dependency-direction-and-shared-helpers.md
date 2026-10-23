# Decision 0003 — 依赖方向 Views → Services → 规则 → Models；重复逻辑收成共享 helper

- **日期**：2026-10-22　**状态**：Accepted，#13 #15 已落地

## 背景（原本的工作方式）
架构分析（2026-10-22，项目文件 architecture/）在文件级找到 6 条反向引用：CloudKit 服务引用 SettingsStore，配对规则引用 SettingsStore 的占位 id，四个规则文件引用 EventServices 里的 9 个规则枚举，Models 引用 EventMirrorService 的 mirrorKey 生成，映射引用 CloudKit 的层级规则，日历显示规则引用服务里的授权状态。另有多处复制：四个视图各写一遍 `performSync()`，三处 upsert-by-mirrorKey，四处 `timeText(for:)`，十处 trim-nil-if-blank，四处每次调用都 new 一个 DateFormatter。

## 决策
1. **依赖只往下指**：Views → Services → 规则层（`Plans/`，重命名后为 `Policies/`）→ Models。规则层不引用服务和存储；为此把 mirrorKey 生成、占位 member id、日历授权状态下沉到规则层。
2. **共享 helper 只写一份**（`CLAUDE.md` 列出以便复用而不是再造）：空闲时同步、按 mirrorKey upsert、时间区间文本、ID 归一化（trim + 空则 nil）、按 format+locale+calendar+timeZone 缓存的 DateFormatter（加锁，缓存后不再修改）。
3. 一处细微等价：某个 ID 归一化原本对空白返回 `""` 而不是 `nil`，其调用点只有相等比较和 `guard let … !isEmpty`，用 `nil` 行为相同，故统一。

## 影响
- 重构后文件级反向引用为 0（仅剩 CloudKit 规则读服务上的一个常量、规则层与字符串互引）。
- 新规则默认写成无状态的纯静态函数并配单测，视图和服务保持薄。
