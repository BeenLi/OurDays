# Decision 0008 — 接受邀请：藏起 Apple 的几秒，去掉我们自己多绕的路

- **日期**：2026-10-29　**状态**：Accepted，#47 落地
- **范围**：粘贴/点开邀请链接到第 3 步、回发链接的生成、所有调用 `ensureZone()` 的 CloudKit 路径

## 背景（原本的工作方式）
用户反馈：收下对方的邀请后要等 5～6 秒才进第 3 步。整段流程全是串行的 CloudKit 往返：
1. 「打开邀请」约 2.5 秒：先 `fetchShareMetadata` 查链接，再 `fetchOutgoingShareParticipantIDs` 看对方有没有收下我的信，而后者又是「存一次 zone → 读根记录 → 读分享」三次往返。
2. 「收下」约 5 秒，其中约 4.6 秒是 `CKAcceptSharesOperation`（跨区账号），这一段我们缩不短。
3. 第 3 步点「回发」以前量到 6～10 秒：`prepareShare` = 存 zone → 读/存根记录 → 存新分享，外加存昵称。

`ensureZone()` 每次都 `modifyRecordZones` 存一次私有 zone。zone 在第一次之后就一直在，这一步纯属白跑，而它排在约 10 个服务调用前面，一次普通同步也要白跑 3 次以上。

## 决策
1. zone 确认过一次就在本次启动内记住（`CloudKitZoneReadiness`）；读写报 `zoneNotFound` / `userDeletedZone` 时忘掉，下次调用重新建；自己删 zone 时也忘掉。代价：zone 在别的设备上被删后，第一次失败的操作不会自动重试，下一次同步就恢复。
2. 「打开邀请」时查链接和查我的分享同时发。
3. 点「收下」立刻进第 3 步：`acceptingShareOwnerID` 只存在内存里，卡片的状态读 `displayedIncomingOwnerID`，第 2 步下方显示「正在和 iCloud 确认…」。真正的 `partnerShareOwnerID`、回发提示和同步都等 CloudKit 接受成功后才动；失败就退回原来的步骤，卡片上写原因。接受操作加 45 秒超时，确认中不会一直挂着。
4. 接受的这几秒里提前做好我的分享（`ShareCalOutgoingSharePrewarm`），回发页直接拿来用，只用一次，5 分钟后或解除配对时作废，失败就当场重做。我的分享在对方加入之前不改变任何配对状态（状态只看已加入的参与者）。
5. 接受、查链接、做分享、建 zone、查我的分享都记 `elapsed=…ms`，方便以后对比。

## 影响
- 看到的流程不变，只是不再等那几秒。
- 一次普通同步少 3 次以上往返。
