# Decision 0001 — 外部 TestFlight 与介绍页的三项关键决策

日期：2026-06-17　状态：已定（用户确认）

## 1. 站点域名 → 先删 beenli.cn 恢复 github.io；后改用 leeberty.uk（Cloudflare）
- 背景：`beenli.cn` 在 DNS 注册局层面已无委派（`dig @8.8.8.8 beenli.cn A/NS` 全空，SOA 落在 `cn.` 父级），GitHub Pages 对 `CNAME=beenli.cn` 的 301 强制跳转使 `beenli.github.io` 一并不可达。
- 第一步决策（已执行）：删除仓库 `CNAME` 文件并清空 Pages 自定义域名，站点恢复为 `https://beenli.github.io/`。放弃 `beenli.cn`（不续费/不恢复）。
- **更新（2026-06-17，超越上条）**：用户新购 `leeberty.uk`（托管在 Cloudflare），决定接为整站 apex 自定义域名。见 Track C。最终站点 = `https://leeberty.uk/`，ShareCal = `https://leeberty.uk/sharecal/`。
  - 加速预期：Cloudflare 免费版无中国大陆节点（需企业版 + ICP），`.uk` 不可备案 ⇒ 对国内仅边缘缓存/稳定性收益，非大幅提速；境外良好。
  - 关键配置：apex A→GitHub Pages 4 IP + AAAA + `www` CNAME→`beenli.github.io`；先灰云签发 GitHub 证书（已 approved，Enforce HTTPS on），后翻橙云代理；Cloudflare SSL=Full + Always Use HTTPS=on。

## 2. 介绍页语言 → 中英双语
- 与 App 的中英双语定位一致，覆盖更多外部 TestFlight 用户。页面内可切换或并排。

## 3. TestFlight 执行方式 → 我用 ASC API 代为操作
- 用已配置的 ASC API key 核查构建、创建/确认外部测试组、提交 Beta App Review、审核通过后开启 public link。
- **安全闸**：任何对 Apple 的提交动作（提交 Beta App Review、开启公开链接）执行前先向用户确认。

## 4. 介绍页落点 → BeenLi.github.io 仓库 `sharecal/` 子目录
- 自包含静态页（HTML + 内嵌样式 + 截图），直接提交进 master。
- 注意：该仓库是 Hexo 构建产物；若日后 `hexo deploy` 覆盖，需要把同样内容放进 Hexo 源仓库的 `source/`。提醒用户但本计划不处理源仓库。
