# Decision 0006 — 邀请链接要求登录 iCloud：先查本 App 的 iCloud，再给粘贴入口

- **日期**：2026-10-29　**状态**：Accepted
- **范围**：「我们」页未配对时的配对卡片、`UICloudSharingController` 的权限选项

## 背景（原本的工作方式）
用户反馈：点对方发来的 OurDays 邀请链接，提示需要登录 iCloud；但同一个人点开备忘录的协作链接，能直接看到邀请。

两种链接底层是同一套 CloudKit 共享（CKShare），差别在"谁来打开"和"检查哪个开关"：
- 邀请链接是 `https://www.icloud.com/share/<token>#OurDays`。这是苹果的通用链接，iPhone 系统自己接住它，用本机 iCloud 账号去 CloudKit 查 token，查到是 `iCloud.com.leeberty.CoupleCalendar` 容器，再把 `CKShare.Metadata` 交给 OurDays 的 `userDidAcceptCloudKitShareWith`。我们的 App 在这一步之前什么也做不了。
- 系统查 token 用的是"本机 iCloud 对这个容器是否可用"。iOS 17 起，设置 → 你的名字 → iCloud →「已存储到 iCloud」里每个 App 有自己的开关；OurDays 这一项关着，CloudKit 对我们的容器就报 `.noAccount`，系统只会说"请登录 iCloud"，哪怕人其实已经登录了。备忘录有自己的开关，几乎总是开着，所以备忘录能用不代表 OurDays 能用。
- 链接如果在微信里点开，微信内置浏览器不把通用链接交给系统，直接加载 icloud.com 网页；网页拿不到本机的 iCloud 身份，也只能要求登录 Apple 账户。
- 配对靠的是"任何拿到链接的人都可加入"（`publicPermission = .readWrite`）。但共享面板里还提供了 `.allowPrivate`，发起方可以把它切成"仅限受邀的人"：链接只对所选手机号/邮箱背后的 iCloud 账号开放，别的账号打开同样提示登录；而在已配对的分享上这样切，等于关掉链接，CloudKit 会把通过链接加入的伴侣移除。

## 决策
1. 共享面板只保留 `.allowPublic` + `.allowReadWrite`，去掉 `.allowPrivate`。
2. 未配对（含等待中）时，「我们」页读 `CKContainer.accountStatus`，经 `ICloudAvailabilityPolicy` 把 `.noAccount` / `.restricted` / `.temporarilyUnavailable` 翻译成具体的设置路径，显示在配对卡片里；从系统设置回到 App 时重新检查。
3. 未配对时卡片下方加「收到邀请链接？在这里粘贴」：`ShareInvitationLinkPolicy` 从剪贴板文字里找出第一个 `icloud.com/share/` 链接，`fetchShareMetadata` 后交给原有的 `ShareCalCloudKitShareAcceptanceHandler`（仍经过换人确认）。粘贴自己的链接会提示"请发给对方"；`notAuthenticated` / `unknownItem` / `participantMayNeedVerification` 分别给出 iCloud 设置、链接失效、只对受邀账号开放的提示。

## 备选与理由
- 让用户"在 Safari 中打开"：步骤多、依赖用户找到微信右上角菜单；粘贴入口在 App 内一步完成，且失败时能拿到具体的 CKError。
- 用私有邀请（像备忘录那样按联系人邀请）：要求对方 iCloud 账号与所填手机号/邮箱一致，正是这次报错的一种来源。

## 影响
- 代码无法替用户打开 App 的 iCloud 开关（也没有公开的跳转地址），只能提示路径。
- 未在真机上复现原始报错；三种原因按可能性排序，需用户确认对方的系统版本、链接是在哪里点开的、提示原文。
