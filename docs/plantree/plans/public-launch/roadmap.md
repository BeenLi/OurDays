# Roadmap — public-launch

## Archived（2026-10-23）
- Track A 的目标被 App Store 公开上架取代（v1.3 build 30 起，见 [releases](../releases/)）；TestFlight 公开链接已退役，官网 CTA 改为 App Store 链接（#11、BeenLi.github.io#3）。
- Track B4 的 Hexo 覆盖风险仍在：BeenLi.github.io 的 `sharecal/` 与 `CNAME` 需同步进 Hexo 源仓库；归 [docs-and-site](../docs-and-site/) 跟进。

## 历史记录

### Track A — 外部 TestFlight 公开链接（含 Apple 审核，确认后执行）
> 关键发现（2026-06-17 ASC 探测）：外部组 `friends` 已存在且 **public link 已开启**（`https://testflight.apple.com/join/42BdyA1N`），但 `publicLinkLimit=2`，且链接当前服务的是 **build 5**（Beta Review APPROVED）。builds 22–26 全部 VALID 但**从未提交 Beta Review、未加入任何组**；build 26 导出合规已就绪（`usesNonExemptEncryption=false`）。
- [x] A1. 校验 ASC API key + 构建状态：build 26 VALID，合规 OK。
- [x] A2. 合规信息齐全：zh-Hans beta 描述 + 反馈邮箱 + 联系邮箱 + 审核说明均已配置。
- [x] A3. build 26 加入 `friends` 外部组（204）+ 提交 Beta App Review（201，state=`WAITING_FOR_REVIEW`）。用户确认后于 2026-06-17 执行。
- [x] A4. `friends` 组 `publicLinkLimit` 2 → **100**，`publicLinkEnabled=true`。公开链接：`https://testflight.apple.com/join/42BdyA1N`。
- [x] A5.（已被 App Store 上架取代）build 26 审核通过后（WAITING_FOR_REVIEW → APPROVED，约 1 天），公开链接自动服务 build 26（URL 不变）。期间链接服务旧 build 5（已 APPROVED）。

## Done

### Track C — 自定义域名 leeberty.uk（2026-06-17 落地并验证）
- [x] C1. Cloudflare DNS（zone `c021a7ba…`）：删停放 A `204.44.122.117`；加 apex A×4（`185.199.108-111.153`）+ AAAA×4（`2606:50c0:8000-8003::153`）+ `www` CNAME→`beenli.github.io`。
- [x] C2. GitHub Pages：提交 `CNAME=leeberty.uk`（commit `fe6a5ae`）+ 设自定义域名；Let's Encrypt 证书 `CN=leeberty.uk` 已 approved，Enforce HTTPS=on。
- [x] C3. Cloudflare 全部记录翻橙云 Proxied；SSL/TLS=Full；Always Use HTTPS=on。公共 DNS 返回 CF anycast（`104.21.90.56`/`172.67.153.135`）= 代理生效。
- [x] C4. 验证 `https://leeberty.uk/` 与 `/sharecal/` 均 200（GitHub 源直测 + 公共 DNS 确认走 CF）。
- 待办（用户侧）：① 撤销/收好 Cloudflare token；② 见 B4 —— Hexo 源仓库需同时包含 `sharecal/` **和** `CNAME=leeberty.uk`，否则 `hexo deploy` 会清掉自定义域名 + 介绍页。③ 浏览器若仍跳 beenli.cn 是旧 301 缓存，无痕验证。

### Track B — 介绍页 + 站点修复（2026-06-17 落地并验证）
> 注：下列 `beenli.github.io` 是 Track B 当时的中间状态（先回退到默认域名）；**当前对外域名已由 Track C 的 `leeberty.uk` 取代**。
- [x] B1. 删除 `BeenLi.github.io` 仓库 `CNAME` + API 清空 Pages 自定义域名 → 站点恢复 `https://beenli.github.io/`（200，不再 301 跳 beenli.cn）。提交 `d9ddeb2`。
- [x] B2. 构建 `sharecal/index.html`（中英双语切换、功能网格、截图、隐私、开源 CTA、TestFlight CTA）。
- [x] B3. 4 张截图入 `sharecal/assets/`，已 push，`https://beenli.github.io/sharecal/` 验证 200、截图 200。
- [ ] B4.〔提醒用户〕该仓库是 Hexo 构建产物；若日后 `hexo deploy` 会覆盖。需把 `sharecal/` 同样放进 Hexo 源仓库 `source/` 才能长期存活。

## Deferred
- `beenli.cn` **永久弃用**（DNS 未委派，不续费/不恢复）；自定义域名已由 `leeberty.uk` 取代（Track C）。
- 重回公开 App Store 上架（需更强定位与非模板截图，见 `docs/testflight-review-notes.md`）。

## 依赖与顺序
- B 与 A 可并行；但介绍页 CTA 的最终公开链接来自 A4，故 B 先上线、A4 出 URL 后回填一次。
- A3/A4 是对 Apple 的外部动作，执行前需用户确认（见 decision 0001 §3）。
