# Decision 0011 — Mac 上自己的日程以 iPhone 上传的那份为准

- **日期**：2026-11-24　**状态**：Accepted　**PR**：#59
- **范围**：不上传自己日程的设备（Mac，见 0010）上，持久化的自己镜像，以及显示用镜像的 key

## 背景（原本的工作方式）
自己的日程显示时，直接从 EventKit 生成临时的 `display:` 镜像。评论、红点和动态都按 `mirrorKey` 找到持久化的那条（`EventDetailMirrorResolutionPolicy.persistedTwin`、`persistedMirrorIDByKey`）。`mirrorKey` 由本机的日历 ID 和事件 ID 组成。

0010 之后 Mac 不再上传自己的日程，但它的 SwiftData 里存的还是自己用 Mac key 生成的镜像。对方评论的是 iPhone 上传的那条，key 是 iPhone 的，所以 Mac 上找不到对应的日程，也看不到这些评论。

## 决策
1. 在 Mac 上，同步时不把本机生成的自己镜像写进 SwiftData，而是读取云端自己 zone 里的镜像（`fetchOwnEventMirrors`），用它替换本地自己的那部分（`replaceOwnMirrors`）。
2. 显示用镜像在 key 对不上的时候，如果持久化的自己镜像里恰好有一条标题、开始时间、结束时间和全天标记都相同、且没有被删除，就采用那条的 key（`OwnEventTwinPolicy.adoptingPersistedKeys`）。匹配到零条或者多条都不采用，保留自己的 key。
3. 每次同步完成后都重新生成显示用镜像（`localDisplayRefreshKey` 里加了 `lastSyncAt`），让新导入的 key 能及时用上。

## 备选与理由
- 在 Mac 上直接显示云端那份，不读 EventKit：Mac 上刚建的日程要等 iPhone 上传之后才会出现在 OurDays 里，体验太差。所以不采用。
- 所有地方都改成按标题和时间匹配：iPhone 上 key 本来就是对的，没必要改。现在只在 key 对不上的时候才退回去匹配。

## 影响
- iPhone 上行为不变，因为显示用镜像的 key 总能对上。
- Mac 上，iPhone 已经上传过的日程可以看到对方的评论和红点，也能在上面评论。还没上传的新日程暂时没有评论区，等 iPhone 同步之后才会出现。
- 两条标题和时间完全相同的日程不会互相认错，代价是它们在 Mac 上看不到评论。
