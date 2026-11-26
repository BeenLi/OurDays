# Decision 0023 — 仅受邀者分享靠「请求加入」配对，像备忘录那样

- **日期**：2026-11-26　**状态**：Accepted

## 背景（原本的工作方式）
0022 让中国大陆区 iCloud 账户在建链接分享被拒时改建仅受邀者分享（`publicPermission = .none`），然后打开 Apple 的共享面板，让用户填对方 Apple 账户的手机号或邮箱。我们自己的邀请文案（微信里发链接）这条路就没了；对方必须用登记在 Apple 账户上的手机号或邮箱，填错了对方就打不开。

iOS 26 给 CloudKit 分享加了「请求加入」（备忘录用的就是这个）：仅受邀者分享打开 `allowsAccessRequests` 后，没受邀的人拿到链接可以请求加入，主人同意后对方就进来了。

## 决策
1. 仅受邀者分享在 iOS 26+ 上总是打开 `allowsAccessRequests`；老系统上保持普通仅受邀者。能建链接分享的账户完全不变。已有的仅受邀者分享（0021 那一版建的）下次「发起配对」时补开这个开关，只改这一项，`publicPermission` 不动。
2. 这个开关要求 `com.apple.developer.icloud-extended-share-access = [InProcessShareAccessRequests]`（Xcode 里叫 iCloud Extended Share Access，公开能力，不需要 Apple 审批），已加进四个签名用的 entitlements 文件。没有它时设这个属性 CloudKit 直接 trap，所以单元测试进程传 `allowsAccessRequests: false`。
3. 主人端：仅受邀者分享也走我们自己的邀请文案（复制链接 / 系统分享）；「改用手机号或邮箱添加」留作次要按钮，打开 0021 的 Apple 面板（说明文字改成"请求一直没到时用"）。
4. 对方端：没受邀时 `fetchShareMetadata` 照样成功，但返回空壳（没有容器标识、没有 zone 主人，状态全是 0），拿它去接受会抛未捕获的 `CKException`。`CloudKitShareAccessRequestPolicy.isUninvitedStub` 认出空壳：粘贴链接和系统点开两条路都改成发加入请求（`CKShareRequestAccessOperation`），并把链接和当时已能读的共享 zone 存进 `SettingsStore`，「我们」页显示「已向对方发送加入请求，等对方同意」。同步里出现一个请求前没有的共享 zone 就清掉等待状态，后面交给原有的配对判定。`acceptShare` 也拒绝空壳。
5. 主人端读请求：主人收不到任何推送（实验里 owner 模拟器上没有通知也没有系统界面），所以在每次前台同步、下拉刷新、以及配对卡片在屏幕上时每 5 秒读一次 `share.requesters`。只在「仅受邀者分享 + 还没人加入」时读。卡片显示「X 请求加入」和「同意 / 拒绝」；名字只用 `nameComponents`，没有就写「对方」，不显示邮箱或手机号，也不读 `requester.contact`（会触发通讯录权限，App 没声明，TCC 直接杀进程）。同意 = 用 `participantLookupInfo` 查参与者，`addParticipant`（读写），保存分享；拒绝 = `denyRequesters`。实验里同意后对方立刻是已接受的参与者，不用再点接受就能读主人的 zone。
6. 两人规则在 `CloudKitShareAccessRequestPolicy.decisions`：已经有人加入就谁也不再给同意按钮，`approveRequester` 保存前再查一次。我已经加入了某人的 zone（`partnerShareOwnerID`）时，这个人的请求自动同意（回寄这一程不用点），同一人请求两次只放一次；其他请求照样显示给用户决定，因为请求者的 ID 和 zone 主人的 ID 是否同一空间还没在真机上核实，不能让真正的对方既不被同意也不被显示。只有 `_` 开头的 ID 参与自动同意；同意了陌生人就走原有的配对冲突提示。
7. 不改 schema，不加 record type，不在活分享上改 `publicPermission`。

## 备选与理由
- Apple 面板（手机号/邮箱）作为默认：要对方 Apple 账户上的手机号或邮箱，用户经常不知道或填错，而且发不了微信链接。保留为备用。
- 只发链接、不做请求：大陆区账户建不了链接分享，这条路走不通。
- 收到请求就自动同意：链接被转出去，陌生人请求也会被放进来。只有回寄这一程（请求者就是我已经加入的那个人）自动同意。
- 主人端靠推送得知请求：实验里没有收到任何推送，只能轮询；轮询只在需要时（仅受邀者、无人加入）进行。

## 影响
- 大陆区账户（iOS 26+）：和其他人一样发链接；对方粘贴后主人在卡片上点一次「同意」，回寄那一程自动完成。
- iOS 26 以下：仍是 0022 的手机号/邮箱流程。
- App ID 需要在开发者后台打开 iCloud Extended Share Access，否则签名的 profile 不含这个 entitlement。
- 模拟器实测（iOS 26.3，Development）：对方**点开**没受邀的链接时，iOS 自己弹「请求访问」（写明主人会看到对方的邮箱），点「发送请求」后由系统发出请求，App 收不到任何回调。所以未配对的 App 在回到前台时、以及「我们」页在屏幕上时，会看一眼有没有新出现的共享 zone，有就走原来「接受了分享」的同步路径（`shouldLookForApprovedShare`）。系统偶尔把空壳交给 App 时，空壳里没有 URL，只能提示对方去粘贴链接。
- 只发了请求、还没配对的一方原本不跑 CloudKit 同步（`CloudKitForegroundSyncPolicy`），所以等不到同意；现在「有待处理的请求」也算要同步。
- 主人拒绝后对方收不到任何通知，等待卡片会一直显示，直到对方点「不等了」。
