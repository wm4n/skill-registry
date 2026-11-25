---
name: self-evolution
description: Use when the user corrects you or says your work missed their intent (「不對」「其實我要的是…」, "not what I asked"), when a task needed failed attempts or rework, when you do the same kind of work for the 3rd time, when you reuse an approach out of habit, when finishing any task (run the quick screen), or when asked to review the lessons (`/self-evolution review`).
---

# Self-Evolution

把糾正與彎路變成**教訓**，並把每條教訓放到**強制力最高、範圍最窄**的位置；教訓會被引用、複審、退場。

<SUBAGENT-STOP>
若你是被派遣執行特定任務的 subagent，忽略此 skill（避免併發寫入衝突）。
</SUBAGENT-STOP>

## 執行環境：Claude Code 與 Codex

同一份 skill 兩邊共用（user 層安裝時，`~/.codex/skills/self-evolution` 以 symlink 指向 `~/.claude/skills/self-evolution`），紀錄都寫在 `~/.claude/evolution/`。差別只在各自載入什麼：

| 教訓放在 | Claude Code | Codex |
|---|---|---|
| 全域常駐條目 | `~/.claude/CLAUDE.md` 區塊，自動載入 | `~/.codex/AGENTS.md` 的 `<!-- self-evolution:start/end -->` 區塊，由檢查腳本從 CLAUDE.md 區塊產生，自動載入；**不手改** |
| 規則檔（`.claude/rules/`） | 自動載入，`paths:` 條件載入 | 不會自動載入；Codex 區塊內有一行指示，改檔前自行讀取 |
| Claude Code hook | 生效 | 不生效 |
| lint／測試／CI | 生效 | 生效 |

Codex 只讀 AGENTS.md 鏈（沒有 include，預設總量上限 32 KiB），所以 lint／測試是兩邊唯一都會被強制的保障——這是「機制優先」的理由之一。

## 檢查腳本

本 skill 目錄下的 `scripts/evolution.sh check`（Claude Code 載入 skill 時給的 base directory；Codex 為 SKILL.md 所在目錄）：驗證紀錄一致性、回報是否該複審，並同步 Codex 區塊。

- **每次寫入**（lessons 檔、INDEX、CLAUDE.md 區塊、規則檔）之後都跑
- 在 error-learning／review 流程中：exit 0 才算寫入完成，非 0 依訊息修正後重跑；輸出含 `REVIEW_DUE` → 讀 [references/review.md](references/review.md) 執行複審
- 只在快篩第 0 題改了日期時：有 `ERROR` 或 `REVIEW_DUE` 就向使用者說一行（「教訓紀錄需要複審，要現在做嗎？」），不在無關任務的結尾自行跑複審；同一個 session 只提一次

## 快篩（每次任務結束執行，靜默）

依序自問，全「否」即結束——不留檔、不輸出、不向使用者報告：

| # | 問題 | 命中 → |
|---|------|--------|
| 0 | 這次有哪條 `[Exxx]` 或規則檔實際改變了我的做法？ | 把該 lessons 檔的 `最後引用` 改成今天（只改日期，不輸出） |
| 1 | 這次有被使用者糾正嗎？（含隱性的「其實我要的是…」） | [references/error-learning.md](references/error-learning.md) |
| 2 | 有走彎路嗎？（失敗重試 2 次以上、推倒重做、方向修正） | [references/retrospective.md](references/retrospective.md) |
| 3 | 這是第 3 次以上做同類工作嗎？（手動重複同套步驟） | [references/capability-proposal.md](references/capability-proposal.md) |
| 4 | 同類問題我已連續第 3 次用同一招，且這次有返工嗎？ | [references/retrospective.md](references/retrospective.md)（慣性反思節） |

**糾正 vs 需求變更**：「你做的不符合我原本要的」才是糾正；「改成藍色」是新需求，第 1 題答否。

多項命中依序處理。命中才讀取對應 reference；快篩本身不載入任何 reference。使用者要求 `/self-evolution review` 時直接讀 [references/review.md](references/review.md)。

## 儲存

- `~/.claude/evolution/`：INDEX.md、lessons/、retros/、proposals/、patterns/
- 教訓的文字規則放哪一層、用什麼機制強制 → [references/placement.md](references/placement.md)（寫入或搬移任何教訓前讀）

### 首次執行

`~/.claude/evolution/` 不存在時，先建立四個子目錄與 INDEX.md（分區：Lessons / Retros / Proposals / Patterns，每筆一行 `- [狀態] 標題 — 日期 — 路徑`）。狀態圖例：

- lesson：`active`（CLAUDE.md 常駐條目）／`scoped`（在規則檔、流程步驟或 Codex 專用區）／`enforced`（已由機制強制）／`repeated`（二犯，仍常駐）／`archived`（僅留完整記錄）
- proposal：`pending`／`approved`／`rejected`
- retro、pattern：一律 `[-]`

## 鐵律

- **寫入前先查 `~/.claude/evolution/INDEX.md`**：同主題已存在 → 更新既有記錄，不新增
- **快篩靜默**：無產出時不產生任何對話輸出
- **寫入後跑檢查腳本**，exit 0 才算完成
