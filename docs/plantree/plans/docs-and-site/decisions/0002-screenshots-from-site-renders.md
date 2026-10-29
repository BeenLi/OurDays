# Decision 0002 — 截图统一用官网的 promo 渲染图，不用模拟器截图

- **日期**：2026-10-23　**状态**：Accepted，#11 #19 已落地

## 背景
模拟器截图里是冒烟测试数据（"ShareCal E2E Smoke Test" 之类的事件名），不适合展示；宣传片的源页（项目文件 promo-video/source/promo.html）已按真实 SwiftUI 组件重绘了四个页面，且有固定人设（阿力 / 小鱼）。

## 决策
- 官网、README 用同一组 WebP：从 promo 源页用 Playwright 在 deviceScaleFactor 2 下定位到对应时间点截 `#ph5/#ph2/#ph3/#ph4`，圆角遮罩后输出；存在 `docs/site/assets/`，README 直接引用，不重复存一份。
- 用户选择官网图而非真实模拟器截图（2026-10-23）。

## 影响
- UI 变化后要先改 promo 源页再重出图；宣传片里共同块不让位、与 App 的已知差异见 [ui-redesign decision 0003](../../ui-redesign/decisions/0003-joint-block-yields-half-lane.md)。
- App Store 截图可沿用同一流程按设备尺寸出图（idea-003）。
