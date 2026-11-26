# Decision 0004 — 对方的新评论改由 iCloud 直接发可见推送

- **日期**：2026-11-26　**状态**：Accepted　**PR**：#82

## 背景（原本的工作方式）
[0002](0002-silent-push-and-background-sync.md) 之后所有通知走同一条路：`CKDatabaseSubscription` 静默推送 → iOS 决定是否唤醒 App → 跑完整条 `foregroundSync` → 管线尾部发本地通知。静默推送优先级低、有预算、低电量模式会推迟，App 被上滑关闭后完全不唤醒，所以评论提醒常常晚几分钟到几小时，用户反馈「不像微信那样及时」。

0002 认定「只为评论推送在订阅层做不到」，依据是共享库只支持数据库订阅。但通知的唯一评论触发是「对方评论**我的**日程」，这条评论写在**我的** zone，也就是我的私有库（`CloudKitCommentWritePolicy`），私有库支持 `CKQuerySubscription`。

## 决策
- 私有库新增一条 `CKQuerySubscription`（`CommentAlertPushPolicy`）：记录类型 `EventComment`、zone 为 `CoupleSpace`、只在**新建**时触发、谓词 `authorMemberID != 我`（排除我在另一台设备上写的评论）。推送标题是「<对方昵称> 评论了你的日程」，正文用 `alertLocalizationArgs = ["body"]` 直接取评论内容。
- 订阅保存成功后把当前 member ID 记在 `SettingsStore.commentAlertPushMemberID`；它与 `currentMemberID` 一致时，`LocalNotificationPolicy` 不再为评论发本地通知，避免同一条评论弹两次。邀请、邀请回应、历史申请三类不变。
- App 在前台时收到这条推送照常显示横幅，并触发一次同步。
- 两条静默数据库订阅和 `BGAppRefresh` 保留，数据同步仍靠它们。
- `authorMemberID` 在 schema 里加 QUERYABLE。Production 没部署这个索引时订阅保存会失败，标记不会写入，评论继续走原来的静默推送 + 本地通知。

## 备选与理由
- **自建推送中转服务器**：能覆盖所有通知类型，但评论要经过服务器，还要保管 APNs 密钥和设备 token，与「数据只在用户自己的 iCloud、不租服务器」冲突。可见推送实测不稳定时再考虑。
- **唤醒后先查评论再全量同步**：只省同步那几秒，静默推送本身的延迟还在。
- **Notification Service Extension 补日程标题**：需要 App Group 和新 target，留到以后。
- **按已送达通知去重，而不是停发本地通知**：用户划掉推送后再打开 App 仍会重复，放弃。

## 影响
- 推送标题在订阅保存时写定，改昵称或语言后下次启动刷新。
- 推送里没有日程标题（评论记录只存 `eventMirrorID`）。
- 同一账号的旧版本设备（例如还在 1.9 的 Mac）会同时收到推送和自己发的本地通知，升级后消失。
- 日程主人在评论串里回复对方仍然不提醒：那条评论在主人的 zone，对方只能经共享库看到。
- 发布前要把 `authorMemberID` 的 QUERYABLE 索引部署到 Production，并在两台真机上确认：推送在 App 关闭时到达、正文是评论内容、自己在 Mac 上发的评论不提醒 iPhone。
