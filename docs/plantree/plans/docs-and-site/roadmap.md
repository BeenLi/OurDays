# Roadmap — docs-and-site

## In Progress
- 🚧 **#28** README「代码结构」由两个代码块合成一棵以仓库根为顶的树，补 `CoupleCalendar.xcodeproj`、`.github/workflows/ios-ci.yml`、`CLAUDE.md` 三行。

## Done
- ✅ **#11**（2026-10-22）ourdays.cn：四张旧 PNG 换成 promo 源页渲染的 WebP（dayview / comments / pairing / profile，资源从 ~760 KB 降到 ~255 KB）；九张功能卡，六张标「1.5 新」；新增「三步开始」与「开源、免费、没有服务器」；support 页去掉 TestFlight；部署文档改为单连接 `tar | ssh tencent 'tar x'`（服务器限制 SSH 频率，`COPYFILE_DISABLE=1`）。同日由用户在 Terminal 部署。
- ✅ **#17**（2026-10-22）README：App Store / 官网 / MIT badge，定位语，重构后的「代码结构」一节，云同步一行改为 CKDatabaseSubscription 静默推送。
- ✅ **#19**（2026-10-23）README 四张截图直接引用 `docs/site/assets/*.webp`，删 `docs/screenshots/`；表头改为 双栏日视图 / 日程详情与评论 / 我们 / 昵称与头像。
- ✅ **#25**（2026-10-23）纠错三处（配对冲突而非自动移除、可见性四档、按 zone 全量拉取而非 CKQuery）；跟上 #20 #21 #24 #12–#16；新增 6 种记录类型表、「一次同步做了什么」10 步、「同步什么时候触发」、CI/冒烟/LOCAL_SIGNING 说明。
- ✅ **#26**（2026-10-23）删「为什么要只写变化」「为什么不用 CKSyncEngine」「解除配对与重装时发生什么」三节；两张 Mermaid 换成 `docs/diagrams/` 的 PNG，10 步并入流程图；新增「数据安全」四问；功能列表补「删除重装可恢复」与解除配对清理。
- ✅ leeberty.uk/sharecal（2026-10-22，BeenLi/BeenLi.github.io#3）：App Store 链接、新截图、新文案、纸色调色板。

## Deferred
- 1.6 上架后：官网与 README 的版本说明、App Store 截图（[idea-003](../../ideas/inbox.md)）。
- 英文 README。
