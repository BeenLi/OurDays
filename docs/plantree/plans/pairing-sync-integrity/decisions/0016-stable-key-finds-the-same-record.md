# Decision 0016 — 日程记录带上跨设备的「全局编号」stableKey

- **日期**：2026-11-25　**状态**：Accepted
- **范围**：`EventStableKeyPolicy`；`EventMirror.stableKey` 和 CloudKit 字段 `EventMirror.stableKey`；`OwnEventTwinPolicy.adoptingPersistedKeys`

## 背景（原本的工作方式）
日程记录名（`mirrorKey`）由 `calendarIdentifier`、`eventIdentifier` 和发生时间组成，起了就不变（comment-visibility 0004、0005），评论按它挂着。但这两个 ID 只在读出它们的那台设备上有效，同一个 iCloud 日程在 iPhone 和 Mac 上算出来的名字不同。所以 Mac 不上传自己的日程（0010），只读 iPhone 上传的那份，再按「标题 + 开始结束时间」去认（0011）。在 Mac 上改了标题或时间，或者有两条一模一样的日程，就认不出来，评论看不到。

## 决策
1. 每条日程多带一个 `stableKey`：取 EventKit 的 `calendarItemExternalIdentifier`（iCloud、CalDAV 上就是日程的 UID，各设备相同）。重复日程的每一次、单独改过的那一次（`isDetached`），再加上它原本的发生时间；全天的按日历上的日期，时区不同的设备也一致。不重复的日程只用 UID，所以挪了时间编号不变。
2. 同一批日程里两条算出同一个编号（同一个邀请出现在两个日历里）时，再混入日历名区分。
3. 存的是哈希（`s1:` + SHA-256 前 16 字节），对方能读这条记录，用不着原始 UID。没有外部 ID 的日程存空字符串；旧版本写的记录没有这个字段（nil），两者区分开，第二步要靠它判断 iPhone 是否已经补完。
4. 记录名不变，`stableKey` 只是找记录的线索：日程挪动、系列搬家时原地更新这个字段，记录名仍按 0004、0005 保留。
5. 上传时只在知道值的时候写这个字段（`.changedKeys`），不会把另一台设备写的清掉。它算作记录内容的一部分，所以升级后的第一次同步会把每条日程重新上传一次，顺带补上编号。
6. Mac 显示自己的日程时，key 对不上就先按 `stableKey` 找 iPhone 上传的那份，找到唯一一条就用它的 key；找不到（旧记录）才退回 0011 的标题和时间匹配。一条记录最多被一条显示日程认领。

## 备选与理由
- 直接把记录名换成外部 ID：所有已上传的记录名都会变，评论全部断开，旧版本也认不出（同 0004）。
- 编号放在私有的 `OwnSettings` 里，不加字段：不用部署 Production，但这份对照表要两台设备一起改，容易冲突，日程多时还会碰到单条记录的大小上限。
- 存原始 UID 不哈希：方便调试，但对方没有理由看到它。
- 编号里总带上账户名和日历名：Google 等账户在两台设备上的名字可能不同，反而对不上；只在真有重复时才带日历名。

## 影响
- 需要把 `EventMirror.stableKey`（STRING，QUERYABLE，第二步 iPhone 按它查询）部署到 Production，否则新版本写记录会失败。旧版本不认识这个字段，照常读写。
- 升级后的第一次同步会多写一遍全部日程。
- Exchange 等账户的外部 ID 在首次同步到服务器后可能变化，这时编号对不上，退回原来的行为。iPhone 和 Mac 上取到的值还没在真机上逐类核对（iCloud、Google、Exchange，普通、重复、单独改过的一次）。
- 这一步不改变谁上传：Mac 仍然不上传（0010）。第二步让 Mac 也上传，按 `stableKey` 认领 iPhone 已有的记录。
