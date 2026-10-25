# Plan: releases（版本与上架）

每个版本带了哪些 PR、何时上架、发布前要做什么。版本号 PR 只改 `project.pbxproj` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`（Debug 与 Release 两份）并在这里记一行。

## 流程（用户习惯）
- 跳过 TestFlight，直接提交 App Store 审核并自动发布。
- archive / upload 在用户的 Mac 上做（通过 Remote Control），Xcode 已登录。
- 有 CloudKit schema 变化时，发布前先在 CloudKit Console 部署 Production 并用 cktool 核对；没有新字段就不用部署。
- 推广文案的定位：完全开源、永久免费、没有服务器（数据在用户自己的 iCloud 里），唯一固定开销是开发者账号年费。

## File map
- [roadmap.md](roadmap.md) — 各版本一行

## Status
- Status: **🚧 1.7 (build 36) 审核中**（2026-10-25 提交）（版本号 PR #36）
