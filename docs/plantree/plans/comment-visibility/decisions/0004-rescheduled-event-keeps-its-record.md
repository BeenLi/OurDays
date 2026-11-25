# Decision 0004 — 改了时间的日程沿用原来的记录，评论不丢

- **日期**：2026-11-24　**状态**：Accepted
- **范围**：`EventMirrorKeyPolicy.keptKeysForRescheduledEvents`；`SyncCoordinator.foregroundSync` 生成镜像和 shadow；日历页的显示镜像

## 背景（原本的工作方式）
镜像的 key 是 `calendarIdentifier:eventIdentifier:occurrenceEpoch`，它同时是 CloudKit 记录名，评论按它挂在日程上（`EventComment.eventMirrorID`）。`occurrenceEpoch` 取 EventKit 的 `occurrenceDate`，对不重复的日程它就等于开始时间。所以把一条普通日程从 20:00 挪到 21:00，key 就变了：旧记录被标成删除，新 key 建一条新记录，对方留的评论还挂在旧记录上，两边都看不到了。重复日程的单次改期不受影响，`occurrenceDate` 是这一次原来的日期，不会变。

## 决策
同步时先看每条不重复的日程：如果它算出来的 key 本地没有，而本地恰好有一条还活着的 shadow 或自己的镜像，日历 ID 和事件 ID 都和它一样，就继续用那条的 key。镜像和 shadow 照常更新成新的时间，记录原地更新，评论跟着走。以后每次同步都会按事件 ID 再找到这个 key。`LocalEventShadow.mirrorKey` 因此改为直接取 `id`，不再从字段推算（以前两者总是相等）。日历页显示自己日程时也用同样的规则，挪完还没同步时评论也在。

重装后的第一次同步，本地还没有 shadow 和镜像。这时先把自己 zone 里的镜像读下来，再生成 key，改过时间的日程同样能找回原来的记录名。以前这份云端镜像要到后面对账时才读，那时 key 已经按新时间算好了，旧记录会被当成删除。现在对账也用这同一份数据，不多读一次。

拿不准的情况都用自己的 key，和以前一样：重复日程（各次共用事件 ID）、事件 ID 为空、同一事件 ID 有两条活着的旧 key、旧 key 正被另一条当前日程使用。已经删除的镜像或 shadow 不会复活。

## 备选与理由
- 改 key 的算法，不重复的日程不带时间：所有已上传的记录名都会变，现有评论全部断开，旧版本也认不出。
- 改期时把评论迁到新记录：评论是对方写的记录，要改写别人的数据，还要处理对方离线时的冲突。
- 等第二步的 `stableKey`（`calendarItemExternalIdentifier`）：那是给多台设备一起上传用的别名，本身不改记录名。这次的规则和它不冲突，以后 stableKey 找到的也是这里保留下来的记录名。

## 影响
- 记录名格式没变，旧版本照常读取。对方那边只是看到同一条日程的时间变了。
- 这个版本之前已经改过时间的日程，旧记录已经删掉，评论找不回来。
- 整个重复系列一起改时间，仍然会换 key，那一系列上的评论会断开，暂不处理。
- Mac 不上传自己的日程，事件 ID 和 iPhone 的不同，不受影响。
