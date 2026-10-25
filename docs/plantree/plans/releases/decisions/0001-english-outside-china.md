# Decision 0001 — 中国以外的地区用英文

- **日期**：2026-10-25　**状态**：Accepted
- **范围**：App Store 商品页语言、App 首次启动的界面语言、权限弹窗、隐私政策页

## 背景（原本的工作方式）
- App Store 没有按国家选语言的开关：每个店面先找与它语言对应的本地化，找不到就显示 App 的**主要语言**。OurDays 的主要语言是简体中文，所以日本、欧美等店面看到的也是中文商品页。
- App 界面早就中英双语（`ShareCalStrings.text(english, chinese)`），但 `AppLanguagePreference.defaultLanguage` 写死为中文，不看系统语言；海外用户第一次打开就是中文，要自己去设置里切。
- 工程只登记了 `en` 一种区域，包里没有 `zh-Hans.lproj`：App Store 的「语言」一栏只写 English，`Info.plist` 里的日历权限说明也只有英文，中文用户看到的是英文弹窗。
- 隐私政策页是中英段落交错的一页，英文读者要在中文里找英文。

## 决策
1. App Store Connect：补全 English (U.S.) 本地化（名称、副标题、关键词、描述、宣传文本），再把主要语言改为 English (U.S.)。中国大陆店面仍显示简体中文，其他没有对应本地化的店面回落到英文。描述与关键词随 1.7 生效。
2. 首次启动跟随系统首选语言：首选语言以 `zh` 开头 → 中文，其余 → 英文；设置里选过语言的以用户选择为准（`AppLanguagePreference.read(from:preferredLanguages:)`）。
3. 新增 `Resources/InfoPlist.xcstrings`（en + zh-Hans）并在 `knownRegions` 加 `zh-Hans`：权限弹窗有中文，App Store 语言一栏列出简体中文。
4. 隐私政策拆成 `privacy.html`（中文）与 `privacy-en.html`（英文），互相链接；英文本地化的隐私政策 URL 指向英文页。

## 备选与理由
- 为每个英语店面（英、澳、加）单独加本地化：文案相同，只是多维护几份；改主要语言一次覆盖所有店面。
- 已经在用、但从没选过语言的老用户，若系统是英文会变成英文界面：不做迁移，设置里可以切回。

## 影响
- 港澳台店面用繁体中文，改主要语言后显示英文；需要的话再加繁体中文本地化。
