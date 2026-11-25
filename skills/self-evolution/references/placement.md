# 教訓放置：範圍 × 強制層級

寫入新教訓、或複審時搬移教訓前讀。每條教訓做兩個判斷：**範圍**決定文字規則放哪，**強制層級**決定用什麼讓它被遵守。

## 1. 範圍

問：「**這條描述的是 agent 的工作方式，還是某個 codebase／技術棧的事實？**」

| 範圍 | 判準 | 例子 | 文字規則放哪 |
|---|---|---|---|
| 全域 | agent 的工作方式，跟用什麼技術無關 | 付費 API 先問；刪除前先驗證能重建 | `~/.claude/CLAUDE.md` 區塊（Codex 由腳本鏡像） |
| 技術棧 | 只在碰到某項技術時成立 | Element Plus 的 teleport；Docker BuildKit 的 CA | `~/.claude/rules/evolution/<stack>.md` |
| repo | 這個 repo 的團隊規範 | Android UI 一律用 Jetpack Compose | `<repo>/.claude/rules/lessons/<slug>.md` |
| 個人 × repo | 只有使用者自己在這個 repo 的偏好 | — | 該專案 auto-memory（type `feedback`），並更新其 MEMORY.md 索引 |
| 只給 Codex | 只跟 Codex 的工具有關（apply_patch、unified exec、`~/.codex/prompts/`） | 長時間指令保留 session id | `~/.codex/AGENTS.md` 的「Codex 專用教訓」區，在 `self-evolution` 標記區塊**外面**（檢查腳本不會覆寫） |

repo 層一律寫在 `.claude/rules/lessons/`，既有的 `AGENTS.md`／`CLAUDE.md` 保持原樣。

### 規則檔格式

```markdown
---
paths:
  - "**/*.kt"
---
# <規則標題>

<一到三行，寫要做什麼>

強制方式：<lint 規則名／測試路徑／無（理由）>
```

- `paths:` 是規則檔唯一會被讀取的 frontmatter；只在 Claude 讀寫符合的檔案時載入
- 跟**檔案類型**綁定的規則才加 `paths:`；跟**指令**綁定的規則（「跑 `docker compose` 前…」）省略 `paths:`，讓它常駐
- repo 規則檔會進版控給團隊看：只寫規則本身，個人紀錄的路徑留在 lessons 檔

## 2. 強制層級：機制優先

由強到弱，放在**做得到的最高層**：

1. **機制**：違規會被擋下
   - repo 規範 → lint rule、測試、CI、pre-commit，且接進 repo 既有的 lint／test 指令
   - agent 行為 → Claude Code PreToolUse hook（以 exit 2 或 `permissionDecision: "deny"` 擋下）
2. **流程步驟**：寫進觸發該情境、且由使用者自己維護的 skill（例：「review 前先確認目標環境」寫進 review skill）
3. **規則檔**：`.claude/rules/`，能加 `paths:` 就加
4. **常駐條目**：CLAUDE.md 區塊——只留給無法往上做的 agent 行為（例：「被問問題時先回答，不直接改成品」）

放在第 2 層以下時，在 lessons 檔的 `強制方式` 用一句話寫明上一層為何做不到。

### 機制的安裝

| 機制 | 安裝方式 |
|---|---|
| repo 的 lint／測試 | 直接做，放在目前分支的**獨立 commit**（message 註明出自哪條教訓）；PR review 就是核准 |
| 全域 hook（`~/.claude/settings.json`） | 只寫草稿到 `~/.claude/evolution/proposals/hook-<slug>/`：腳本、settings 片段、會擋什麼、可能誤擋什麼。告知使用者，**核准後**才安裝，INDEX Proposals 區記一行 |
| 第三方 skill | 不改；教訓留在規則檔或常駐條目 |

### 生效確認

裝好後**實際觸發一次**：hook 擋下一個違規指令、lint 對一個違規範例報錯。親眼看到被擋，才：

1. 把對應條目移出 CLAUDE.md 區塊
2. lessons 檔的 `強制方式` 填上機制位置
3. INDEX 狀態改 `enforced`

## 3. CLAUDE.md 區塊維護

區塊位於 `~/.claude/CLAUDE.md`，標題 `## Self-Evolution 教訓（由 self-evolution skill 維護）`。

- 只認 `## Self-Evolution 教訓` 標題定位；找不到就在檔案末尾建立
- 條目格式：`- [Exxx] <一行規則>（詳: evolution/lessons/YYYYMMDD-<slug>.md）`，一條只放一個規則
- 編號取現有最大值 +1
- 區塊內非 `[Exxx]` 開頭的行（使用者手動加的）保留不動
- 上限 20 條，由檢查腳本驗證；超限時走 [review.md](review.md)
- `~/.codex/AGENTS.md` 的鏡像區塊由檢查腳本產生，只改 CLAUDE.md 這一份
