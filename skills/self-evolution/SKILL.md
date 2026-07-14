---
name: self-evolution
description: Use when the user corrects you or points out your work missed their intent (「不對」「不是這樣」「其實我要的是…」「你怎麼又…」, "that's wrong", "not what I asked", "you did it again"), when a task involved failed attempts or rework, when you notice doing the same type of work for the 3rd time, when you catch yourself reusing the same approach out of habit, or when finishing any task — run the quick screen.
---

# Self-Evolution

讓 agent 在持續工作中學習錯誤、復盤彎路、擴張能力、打破慣性。

<SUBAGENT-STOP>
若你是被派遣執行特定任務的 subagent，忽略此 skill（避免併發寫入衝突）。
</SUBAGENT-STOP>

## 快篩（每次任務結束執行，靜默）

依序自問四題，全「否」即結束——不留檔、不輸出、不向使用者報告：

| # | 問題 | 命中 → 讀取 |
|---|------|------------|
| 1 | 這次有被使用者糾正嗎？（含隱性的「其實我要的是…」） | references/error-learning.md |
| 2 | 有走彎路嗎？（失敗重試 2 次以上、推倒重做、方向修正） | references/retrospective.md |
| 3 | 這是第 3 次以上做同類工作嗎？（手動重複同套步驟） | references/capability-proposal.md |
| 4 | 我慣性地用了跟上次一樣的方法、沒想過別條路，且結果平庸嗎？ | references/retrospective.md（慣性反思節） |

多項命中依序處理。命中才讀取對應 reference；快篩本身不載入任何 reference。

## 儲存總覽

- **全域**：`~/.claude/evolution/`（INDEX.md、lessons/、retros/、proposals/、patterns/）
- **專案特定教訓** → 該專案 auto-memory（沿用其記憶檔格式與 recall 機制）
- **通用教訓精簡條列** → `~/.claude/CLAUDE.md` 的 `## Self-Evolution 教訓（由 self-evolution skill 維護）` 區塊

### Scope 判斷（寫入前必問）

「**換一個專案，這條還成立嗎？**」

- 成立（工作方法、安全原則、工具使用慣例）→ 全域 evolution + CLAUDE.md 區塊
- 不成立（專案命名慣例、特定 codebase 的坑）→ 專案 auto-memory

### 首次執行

`~/.claude/evolution/` 不存在時，先建立四個子目錄與 INDEX.md（分區：Lessons / Retros / Proposals / Patterns，每筆一行 `- [狀態] 標題 — 日期 — 路徑`）。狀態圖例：lesson 狀態為 active（在 CLAUDE.md 區塊中）/ archived（僅留完整記錄）/ repeated（二犯）；proposal 狀態為 pending / approved / rejected；retro 與 pattern 一律用 `[-]`。

## 鐵律

- **寫入前先查 `~/.claude/evolution/INDEX.md`**：同主題已存在 → 更新既有記錄，不新增
- **糾正 vs 需求變更**：「你做的不符合我原本要的」才是糾正；「改成藍色」是新需求，不存教訓
- **快篩靜默**：無產出時不產生任何對話輸出
- **CLAUDE.md 區塊**：只認 `## Self-Evolution 教訓` 標題定位；找不到就在檔案末尾重建；區塊內非 `[Exxx]` 開頭的行（使用者手動加的）保留不動
