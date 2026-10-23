# Decision 0001 — README 口味：尽可能精简，不写"为什么"长文，图用 PNG，数据安全答四问

- **日期**：2026-10-23　**状态**：Accepted（用户在 #25 → #26 的反馈中定下），#26 已落地

## 背景
#25 把 README 写成了"同步架构教程"：三节"为什么"长文、三列表格、两张 Mermaid 图、10 步流水线正文。用户反馈要精简。

## 决策
1. **精简优先**：说清"是什么、怎么用"，不写"为什么这样设计"的长文；设计依据放 `CLAUDE.md` 与本规划树的 decisions。
2. **不用稀疏表格**：三列以内、行数少的表格改成短列表。
3. **图用 PNG**：Mermaid 在 GitHub 上渲染不受控；用 diagram-design 技能画 HTML 再导出 PNG，源文件一并入库（`docs/diagrams/`），配色用 OurDaysTheme。流程步骤并入流程图，正文只留几条细节。
4. **「数据安全」一节固定回答四个问题**：数据在哪里；App 升级后数据还在吗；解除配对后数据有什么变化；删除 App 后数据有什么变化。放在「记录类型」之后。
5. 致谢保留 plan-tree（本树即其产物）。

## 影响
- 导出 PNG 在云端容器里要 `playwright.chromium.launch(executable_path='/opt/pw-browsers/chromium')`。
- 以后每个影响同步/数据的 PR 合并后，检查「数据安全」四问是否仍成立。
