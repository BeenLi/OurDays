# Baseline — OurDays

权威 baseline 是仓库根的 **`../../../CLAUDE.md`**（两人制、userRecordID 身份模型、CloudKit 布局、纯规则类型约定、同步流水线、共享 helper）。面向读者的架构说明在仓库 `README.md` 的「同步架构」「记录类型」「数据安全」三节，配图源文件在 `docs/diagrams/`。本文件只保留**从代码核实过、且多个 plan 都会用到**的稳定事实；行号一律不写，以免过期。

## 已核实的稳定事实（2026-10-23，main @ #26）
- **Tab**：日历 → 动态 → 邀请 → 我们（原「设置」，1.5 起改名）。动态角标 = 对方评论的未读数（本地 lastSeen），邀请角标 = 可响应的邀请 + 待处理的历史访问请求；两者不重叠。
- **评论**：线程键是事件的 `mirrorKey`，它同时是 SwiftData id、CloudKit recordName 和评论锚（#24 起对自己的日程也成立，不必等同步）。共同日程（joint）的线程键是邀请 id。评论从我的 private zone 与对方的 shared zone 两边读。
- **通知**：静默推送（private + shared 两个 CKDatabaseSubscription）唤醒 App → 拉取变更 → 发本地通知；BGAppRefresh 兜底。前台同步有 60 s 节流。
- **共享记录写入规则**：根记录和 MemberProfile 在共享 zone 里，每次保存都会触发对方的静默推送；因此只在字段真正变化时才保存（#20）。新增任何"每次同步都写"的共享记录写入都会重新制造 sync → push → sync 乒乓。
- **本地缓存是纯缓存**：SwiftData 里的一切都能从 CloudKit 重建；删除重装后走「发现旧的 iCloud 数据」提示恢复（#22）。只有 UserDefaults 里的本地偏好（对方备注名/本地头像覆盖、选中的日历、配对日期等）需要单独恢复。
- **两人制**：我方分享出现伴侣之外的参与者时不再静默移除，而是报配对冲突让用户选择（#4）；解除配对会删掉我 zone 里与前任有关的评论/邀请/历史申请记录（#23）。
- **工程**：Xcode 工程是 legacy PBXGroup；非 UI 源文件要同时加进 App 与 Test 两个 target（测试直接编译源码，不 `@testable import`）。CI 跑单元 + UI 测试；两模拟器配对冒烟只在本地跑（`Scripts/dev-pairing-smoke.sh`）。

## 其余 baseline 维度
- module-map / storage-and-state / risk-hotspots：以 `CLAUDE.md` 与 README 为准，不在此重复。
