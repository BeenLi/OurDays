# ourdays.cn 部署记录

官网静态站(`docs/site/` 下的 `index.html` / `privacy.html` / `support.html`)的线上部署与 HTTPS 配置说明。

## 线上环境

| 项 | 值 |
|---|---|
| 服务器 | `111.231.31.145`(腾讯云,大陆节点;SSH 别名 `tencent`) |
| 系统 | OpenCloudOS 9.6 |
| Web 服务 | 系统包 nginx 1.26.3(`/usr/sbin/nginx`,配置 `/etc/nginx/nginx.conf`) |
| 网站根目录 | `/usr/share/nginx/html`(注:**不是**宝塔的 `/www/wwwroot`;宝塔虽装但未接管 nginx) |
| 域名解析 | DNSPod(腾讯云);`@` 与 `www` 均 A 记录 → `111.231.31.145` |
| ICP 备案 | 沪ICP备2026030016号-2(网站备案,状态正常) |

## HTTPS / 证书

| 项 | 值 |
|---|---|
| 证书来源 | 腾讯云免费证书 · TrustAsia C1 DV Free(证书 ID `ZDIVHagT`) |
| 覆盖域名 (SAN) | `ourdays.cn`, `www.ourdays.cn` |
| 有效期 | **2026-07-15 ~ 2026-10-13(约 90 天,到期需手动续)** |
| 证书部署位置 | `/etc/nginx/ssl/ourdays.cn/fullchain.crt`(644)、`private.key`(600) |
| nginx 站点配置 | `/etc/nginx/conf.d/ourdays.conf`(本目录 `ourdays.conf` 为其副本) |
| 原配置备份 | 服务器 `/etc/nginx/nginx.conf.bak-2026-07-15-1357` |

验证通过项:`nginx -t` ok · 证书↔私钥 modulus 匹配 · 证书链 `Verify return code: 0 (ok)` ·
本地与外网 `https://ourdays.cn`、`https://www.ourdays.cn` 均 `HTTP/2 200` · `http://` 自动 `301` 跳 `https://`。

## 更新网站内容

```bash
# 在本机 docs/site/ 下改好 html 后:
scp docs/site/index.html docs/site/privacy.html docs/site/support.html \
    tencent:/usr/share/nginx/html/
scp docs/site/assets/*.webp docs/site/assets/*.jpg \
    tencent:/usr/share/nginx/html/assets/
# 静态文件无需 reload，nginx 直接读新文件

# 或者只开一条 SSH 连接把整站打包传过去（避免下面的 SSH 限流）：
tar czf - -C docs/site index.html privacy.html support.html assets \
  | ssh tencent 'tar xzf - -C /usr/share/nginx/html'
# 2026-10-22 起截图为 assets/*.webp（dayview / comments / pairing / profile）；旧 PNG 已删除
```

> ⚠️ **SSH 限流**:短时间频繁 ssh/scp(尤其大文件)会触发服务器 SSH 防爆破,报
> `Connection closed by ... port 22`。规避:连接间隔 ≥100s、每轮单连接;传大图优先
> 「让服务器自己 `curl` 从公网源拉取」而非本机 scp 推。首页/图资源:
> `https://leeberty.uk/sharecal/assets/{calendar,activity,invites}.png`。

## 证书续期(⚠️ 到期前必做,免费证书不自动续期)

TrustAsia DV Free 有效期仅 90 天。**2026-10-13 前**:

1. 腾讯云 SSL 证书控制台 → 重新申请免费证书(主域名 `ourdays.cn`)→ DNS 验证 → 下载 **Nginx 版**。
2. 解压后把新证书替换上去(文件名沿用 `fullchain.crt` / `private.key`,配置无需改):
   ```bash
   scp <新解压目录>/ourdays.cn_bundle.crt tencent:/etc/nginx/ssl/ourdays.cn/fullchain.crt
   scp <新解压目录>/ourdays.cn.key        tencent:/etc/nginx/ssl/ourdays.cn/private.key
   ssh tencent 'chmod 600 /etc/nginx/ssl/ourdays.cn/private.key && nginx -t && systemctl reload nginx'
   ```
3. 验证:`curl -I --resolve ourdays.cn:443:111.231.31.145 https://ourdays.cn/` 应返回 `HTTP/2 200`。

> 想彻底免除手动续期,可改用 `acme.sh` 或 `certbot`(HTTP-01/DNS-01 自动签发+cron 自动续期);
> 当前先沿用腾讯云免费证书,靠上面的日历提醒手动续。
