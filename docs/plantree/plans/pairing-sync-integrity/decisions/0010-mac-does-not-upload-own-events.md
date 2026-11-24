# Decision 0010 — 自己的日程只由 iPhone 上传，Mac 不上传

- **日期**：2026-11-23　**状态**：Accepted　**PR**：#57
- **范围**：`SyncCoordinator.foregroundSync` 中自己日程的上传、对账删除和硬删除；`OwnEventUploadPolicy`

## 背景（原本的工作方式）
每次同步都从 EventKit 读出选中的日历，生成镜像（mirror），再把有变化的上传到自己的 zone。镜像的 key 由 `calendarIdentifier` 和 `eventIdentifier` 组成，这两个 ID 只在读出它们的那台设备上有效。如果 iPhone 和 Mac 读的是同一个 iCloud 日历，各自生成的 key 不同，上传后对方会看到每条日程出现两次。

## 决策
运行在 Mac 上时（`isMacCatalystApp` 或 `isiOSAppOnMac`），镜像照常在本地生成，供本机显示。但不上传、不做重装对账，也不在云端做硬删除。在 Mac 上新建的日程写进 iCloud 日历，同步到 iPhone 后，由 iPhone 上传。

## 备选与理由
- 把 key 改成跨设备一致的 `calendarItemExternalIdentifier`：两台设备都能上传，但已经上传的所有镜像都要迁移，对方那边的评论也是按 key 挂在日程上的。工作量和风险都大，等有需要再做。
- 两台设备都上传、靠对方那边去重：日程的标题和时间都可能被改，去重不可靠。

## 影响
- 现在的 App 还不能在 Mac 上运行，所以这次改动对现有用户没有影响。它是为 Mac 版准备的。
- Mac 上新建的日程，要等 iPhone 下次同步时对方才看得到。系统日历变化不会唤醒 iPhone 上的 App。
- 还没处理：Mac 本机显示自己日程时用的是本机的 key，对方在这些日程下的评论挂在 iPhone 的 key 上，Mac 上看不到。做 Mac 版时，要改成从云端读取自己的镜像来显示。iPhone 加 iPad 的组合仍然会两边都上传。
