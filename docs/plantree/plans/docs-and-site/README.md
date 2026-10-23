# Plan: docs-and-site（README、官网、架构图）

面向读者的三样东西：仓库 README、两个官网（ourdays.cn 与 leeberty.uk/sharecal）、README 用的架构图。它们在 1.5 上架后随功能连续更新，这里记录每次改了什么和用户定下的口味。Baseline：[../../baseline/README.md](../../baseline/README.md)。

## Scope
- **README**：#17 badge + 定位语 + 重构后的代码结构；#19 截图换新 UI；#25 同步架构、记录类型、代码结构全面更新；#26 精简同步架构、PNG 重画图、新增「数据安全」、补 #22/#23；#28 代码结构合成一棵树（未合并）。
- **官网**：ourdays.cn 源码在 `docs/site/`（#11 换 1.5 截图与文案，tar over ssh 部署）；leeberty.uk/sharecal 在另一个仓库 BeenLi/BeenLi.github.io（同日更新）。
- **架构图**：`docs/diagrams/sync-architecture.{html,png}`、`sync-pipeline.{html,png}`，用 diagram-design 技能绘制，OurDaysTheme 配色。

## Non-goals
- 不在仓库里存宣传片（在项目文件 promo-video/）。
- 官网部署是手动步骤，合并 PR 不部署。

## File map
- [roadmap.md](roadmap.md)
- [decisions/0001-readme-style.md](decisions/0001-readme-style.md) — README 口味：精简、不写"为什么"长文、PNG 图、数据安全四问
- [decisions/0002-screenshots-from-site-renders.md](decisions/0002-screenshots-from-site-renders.md) — 截图来源：官网渲染图而非模拟器截图

## Status
- Status: **🚧 In Progress**（README 已对齐 main 至 #23；#28 待合并）
- Next: #28 合并；1.6 上架后刷新官网与 README 的版本说明；规则层重命名后更新代码结构树。
