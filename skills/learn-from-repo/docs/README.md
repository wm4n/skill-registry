# learn-from-repo 開發紀錄

本 skill 以 [superpowers](https://github.com/obra/superpowers) 的 brainstorming → spec → plan → subagent-driven development 流程開發，原始開發 repo 為本機的 `skill-learn-from-pr` 專案。

| 文件 | 內容 |
|------|------|
| [2026-07-11-learn-from-repo-skill-design.md](2026-07-11-learn-from-repo-skill-design.md) | 設計文件（spec）：需求共識、架構方案、init/learn 流程、branch 策略、知識格式、錯誤處理 |
| [2026-07-11-learn-from-repo-skill.md](2026-07-11-learn-from-repo-skill.md) | 實作計畫（plan）：5 個任務的完整實作步驟與驗證方式 |

開發過程摘要：

- 每個任務由獨立 implementer subagent 實作、獨立 reviewer subagent 審查（spec 符合性 + 品質雙 verdict），共經歷 4 輪任務級修正迴圈
- 完成後執行最終整體 branch review，發現並修正 1 Critical（checkpoint 生命週期跨檔矛盾）+ 4 Important（Jira v2/v3 404 決策鏈、`--limit 200` 截斷保護等）
- 情境測試（subagent 閱讀理解驗證）四題全對後才發佈
