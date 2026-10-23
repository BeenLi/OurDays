# Plan: public-launch（外部 TestFlight + 介绍页）

> **📦 Archived（2026-10-23）**。目标已被超越：应用自 v1.3 (build 30) 起以 OurDays 名义公开上架 App Store（https://apps.apple.com/cn/app/id6772868166），外部 TestFlight 公开链接 `testflight.apple.com/join/42BdyA1N` 已退役；介绍页与域名的后续维护归 [docs-and-site](../docs-and-site/)。本文件保留为历史记录，不再更新。

把 ShareCal 从「仅内部邀请测试」推进到「任何人凭公开链接即可加入的外部 TestFlight」，并在 GitHub Pages 上线一个中英双语的 ShareCal 介绍页（含开源地址）。

## Scope
- **Track A — 外部 TestFlight 公开链接**：当前只有内部测试者（ASC 用户）可用；目标是创建/确认外部测试组、提交构建过 Beta App Review、开启 public link。
- **Track B — 介绍页 + 站点修复**：在 `BeenLi/BeenLi.github.io`（Hexo 生成、master 分支）发布 `sharecal/` 静态介绍页；并修复 `beenli.cn` 域名失效导致整站打不开的问题。
- **Track C — 自定义域名 leeberty.uk**：用户新购 `leeberty.uk`（Cloudflare 托管），接为整站 apex 自定义域名 + HTTPS + Cloudflare 代理。

## Non-goals
- ~~不重新提交公开 App Store 上架（之前 4.3 Spam 被拒，方向仍是 TestFlight）。~~ **已反转（2026-06-22，用户确认）**：v1.3 (build 30) 已作为 **OurDays**（由 ShareCal 改名）重新提交公开 App Store 审核（强化差异化描述/关键词/Review Notes 以应对当初 4.3(a)），状态 `WAITING_FOR_REVIEW`。
- 不引入第三人/多人共享（与 CLAUDE.md 铁律冲突）。
- 不续费/恢复 `beenli.cn`（已废弃；站点先回退 github.io，后改用 `leeberty.uk`，见 Track C / decision 0001 §1）。
- 不追求中国大陆 CDN 加速（`.uk` 不可备案、Cloudflare 免费版无大陆节点；仅取边缘缓存/稳定性）。

## 关键约束 / 已知事实
- 外部 TestFlight 公开链接**必须先过 Beta App Review**（独立于 App Store 审核，更轻量，约 1 天）。复用 `docs/testflight-review-notes.md` 的 beta 描述/审核说明。
- App：ShareCal，bundle `com.leeberty.CoupleCalendar`，当前 `MARKETING_VERSION 1.2` / build 26。
- ASC API key 已配置在 `~/.appstoreconnect/`，JWT 脚本 `asc_jwt.py`（见 memory `asc-api-access`、`testflight-release-process`）。
- `BeenLi.github.io` 是 **Hexo 构建产物仓库**（master/root）。历史 `CNAME=beenli.cn` 已在注册局层面未委派（DNS 全空），GitHub Pages 对自定义域名的 301 强制跳转曾导致 `*.github.io` 一并打不开 → 已删除该 CNAME。**当前自定义域名 = `leeberty.uk`**（Cloudflare 代理，见 Track C）。
- ⚠️ 该仓库是构建产物：直接提交的 `sharecal/` 与 `CNAME=leeberty.uk` 会被下次 `hexo deploy` 覆盖，需同步进 Hexo 源仓库 `source/`（见 roadmap Track C 待办）。

## Decisions
- [0001](decisions/0001-external-testflight-and-landing.md) — 关键决策（域名 → 现为 leeberty.uk/Cloudflare、介绍页语言、TestFlight 执行方式）。

## Roadmap / 进度
见 [roadmap.md](roadmap.md)。
