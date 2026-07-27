# team-onboarding skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一支通用、跨 repo 的 `team-onboarding` skill——吃團隊 onboarding 文件，消化成全域 `~/.claude/team-profile/` 並在 `~/.claude/CLAUDE.md` 掛常駐自檢區塊。

**Architecture:** 純 markdown skill（方向 A，零 hooks）。`SKILL.md` 承載 5 個 Phase 的流程骨架，指向兩份 reference：`profile-format.md`（檔案結構、條目範本、INDEX 與 CLAUDE.md 區塊模板、嚴重度分級）與 `onboarding-guide.md`（來源收集細節、訪談題庫、抽取判準、去重/衝突規則）。發佈時更新 README 一列並同步 bump 兩份 manifest 版本。

**Tech Stack:** Claude Code plugin skill（YAML frontmatter + markdown）；工具僅用 `Read`/`Write`/`Edit`/`Glob`/`WebFetch`。此 repo 無 build/test/lint 工具，驗證＝人工/機械式檢查。

## Global Constraints

- 產物全程使用**台灣正體中文**撰寫。
- **絕不在 SKILL.md（或任何 skill 檔）寫出 inline-exec 字面量**（驚嘆號緊接反引號包住 shell 命令的那個語法）——即使當範例也不行；Claude Code 會掃全檔並執行它（見 memory `skill-file-bang-backtick-scanner`）。本 skill 不需要動態命令執行。
- **人工確認前絕不寫檔**：任何 profile 條目在使用者明確確認前，一律不得落地。
- 只寫全域 `~/.claude/`，**不碰、不修改任何 repo 內檔案**；單一團隊 profile（不做多團隊切換）。
- `version` 必須在 `.claude-plugin/plugin.json` 與 `.claude-plugin/marketplace.json`（skill-registry plugin 那筆，目前皆為 `1.3.0`）**同步 bump 到 `1.4.0`**。
- 遵循 `jira-fetch`/`learn-from-repo` 既有 skill 慣例：frontmatter 欄位 `name`、`argument-hint`、`description`（多行 `>-`），`allowed-tools` 白名單。
- 權威來源設計文件：`docs/superpowers/specs/2026-07-27-team-onboarding-skill-design.md`。

---

### Task 1: 建立兩份 reference 檔（格式與判準的權威來源）

**Files:**
- Create: `skills/team-onboarding/references/profile-format.md`
- Create: `skills/team-onboarding/references/onboarding-guide.md`

**Interfaces:**
- Produces（供 Task 2 的 SKILL.md 引用）：
  - `references/profile-format.md`：定義 `~/.claude/team-profile/` 目錄結構、`INDEX.md` 格式、`never.md`/`standards.md`/`workflow.md`/`glossary.md` 各自的條目範本、嚴重度分級表、`~/.claude/CLAUDE.md` 常駐區塊模板（標題 `## 團隊規範（由 team-onboarding skill 維護）`）。
  - `references/onboarding-guide.md`：定義來源收集三種模式細節、訪談題庫、抽取判準（寧缺勿濫）、候選呈現格式、去重與衝突處理、來源標注規則。

- [ ] **Step 1: 撰寫 `references/profile-format.md`**

內容需包含以下五節，全繁中：

````markdown
# team-profile 格式規範

## 1. 目錄結構
`~/.claude/team-profile/`
- `INDEX.md`：索引 + 來源清單 + `updatedAt`
- `never.md`：絕對不可犯 → MUST-NOT（critical）
- `standards.md`：規範/慣例 → SHOULD / MAY
- `workflow.md`：開發模式/流程（branching、PR、test、release）
- `glossary.md`：術語/領域知識（選用；無內容時不建）

## 2. 嚴重度分級（RFC-2119 精神）
| 類型 | 級別 | 落點 |
|---|---|---|
| 絕對不可犯 | MUST-NOT | never.md + CLAUDE.md 常駐清單 |
| 規範/慣例 | SHOULD | standards.md |
| 偏好/建議 | MAY | standards.md |
| 開發模式/流程 | —（流程類） | workflow.md |

## 3. 條目範本（每條含穩定 id、內容、來源）
- `never.md` 條目：`- [N001] <規則> — 來源：<文件名/訪談日期>`
- `standards.md` 條目：`- [S001] (SHOULD|MAY) <規則> — 來源：<…>`
- `workflow.md` 條目：`- [W001] <流程說明> — 來源：<…>`
- `glossary.md` 條目：`- **<術語>**：<定義> — 來源：<…>`
id 前綴：never=N、standards=S、workflow=W；三位數流水號，新增時取該檔現有最大號 +1。

## 4. INDEX.md 格式
```
# team-profile 索引

updatedAt: <ISO 8601>

## 條目統計
- never（MUST-NOT）：N 筆
- standards（SHOULD/MAY）：N 筆
- workflow：N 筆
- glossary：N 筆

## 來源清單
- <文件名/URL/訪談>（YYYY-MM-DD，貢獻 X 筆）
```

## 5. CLAUDE.md 常駐區塊模板
標題固定 `## 團隊規範（由 team-onboarding skill 維護）`，內容：
```
## 團隊規範（由 team-onboarding skill 維護）

動工前與 commit 前，對照下列「絕不可犯」清單自檢；需要細則時讀 `~/.claude/team-profile/`。

### 絕不可犯（MUST-NOT）
- [N001] <規則>
- [N002] <規則>

細則：standards → `~/.claude/team-profile/standards.md`；流程 → `workflow.md`；術語 → `glossary.md`。
```
維護規則：只認上述標題定位；找不到就在 CLAUDE.md 檔尾重建；區塊內非 `[N###]` 開頭、使用者手動加的行一律保留不動。
````

- [ ] **Step 2: 撰寫 `references/onboarding-guide.md`**

內容需包含以下四節，全繁中：

````markdown
# onboarding 收集與抽取指南

## 1. 來源收集（三模式）
- 本地資料夾/路徑：用 Glob 找 `*.md`/`*.txt`/`*.pdf`，逐份 Read（md/txt/pdf 直讀；docx 請使用者先匯出成 md/pdf）。
- URL：用 WebFetch；**抓取前必須向使用者確認**要抓哪些連結。
- 互動訪談（--interview）：一問一答，題庫見第 2 節。
- 貼上文字：直接採用使用者貼入內容。

## 2. 訪談題庫（至少涵蓋）
1. 分支策略？（主幹/feature 分支/命名）
2. PR / code review 規矩？（誰審、幾個 approve、必跑檢查）
3. 測試要求？（覆蓋率、必寫哪類測試、CI 門檻）
4. 絕對不可犯的雷？（歷史事故、硬性禁令）
5. 命名與程式風格慣例？
6. 團隊術語 / 領域黑話？
每題答完追問「這條的嚴重度是『絕不可犯』還是『建議』？」以利分級。

## 3. 抽取判準與候選呈現
- 寧缺勿濫：一份文件完全可能產出 0 筆；不為湊數產低品質條目。
- 每條標：severity（MUST-NOT/SHOULD/MAY）＋ category（never/standards/workflow/glossary）＋ 來源。
- 候選呈現格式（分類分級列出，附暫時編號供使用者點名）：
```
【never / MUST-NOT】
  1. <規則>（來源：<…>）
【standards / SHOULD】
  2. <規則>（來源：<…>）
...
請回覆：全部接受 / 刪除 #編號 / 修改 #編號 為 <新內容>
```

## 4. 去重與衝突
- 寫入前讀既有 profile 條目比對；語意重複則合併、不新增。
- 語意衝突（新舊規則矛盾）→ 並列兩版標記衝突，請使用者裁決保留哪版，不自行取捨。
- 來源標注一律保留，供日後追溯。
````

- [ ] **Step 3: 驗證兩份 reference 內容完整**

Run: `ls -1 skills/team-onboarding/references/ && grep -c "^#" skills/team-onboarding/references/profile-format.md skills/team-onboarding/references/onboarding-guide.md`
Expected: 列出兩檔；各自 heading 數 > 0（profile-format 至少 5 個 `##`、onboarding-guide 至少 4 個 `##`）。

- [ ] **Step 4: 驗證未混入 inline-exec 字面量**

Run: `grep -rn -e '![\x60]' skills/team-onboarding/references/ || echo "clean"`
Expected: 輸出 `clean`（無驚嘆號緊接反引號的字面量）。

- [ ] **Step 5: Commit**

```bash
git add skills/team-onboarding/references/
git commit -m "feat(team-onboarding): 新增 profile 格式與 onboarding 收集 reference

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 撰寫 `SKILL.md`（流程骨架）

**Files:**
- Create: `skills/team-onboarding/SKILL.md`

**Interfaces:**
- Consumes（Task 1 產出）：`references/profile-format.md`、`references/onboarding-guide.md`——SKILL.md 各 Phase 以「詳見 references/…」指向它們，不重複格式細節。
- Produces：可被 agent 依 `description` 匹配觸發的完整 skill 入口，含 5 個 Phase。

- [ ] **Step 1: 撰寫 `SKILL.md` frontmatter**

```yaml
---
name: team-onboarding
argument-hint: "[path-or-url] [--interview] [--update]"
description: >-
  Use when the user wants the bot to learn their team's development
  conventions, standards, or hard prohibitions from onboarding docs —
  「幫 bot 入職」、學團隊模式、消化新人文件、建立團隊規範。把團隊 onboarding
  文件（資料夾/貼上/連結/訪談）消化成全域 ~/.claude/team-profile/，並在
  ~/.claude/CLAUDE.md 掛常駐自檢區塊，讓任何 repo 開工都記得團隊規矩。
  Keywords: onboarding, team conventions, 新人文件, 團隊規範, 學團隊模式.
allowed-tools: Read, Write, Edit, Glob, WebFetch
---
```

- [ ] **Step 2: 撰寫 SKILL.md 本文（總覽 + 5 Phase + 鐵律）**

全繁中，結構如下（每個 Phase 為 `## Phase N:` 標題，順序執行）：

````markdown
# team-onboarding

讓 bot 像剛入職的團隊新人：讀完 onboarding 文件，記住團隊的開發模式、規範、絕對不可犯的錯。

<SUBAGENT-STOP>
若你是被派遣執行特定任務的 subagent，忽略此 skill（避免併發寫入 ~/.claude 衝突）。
</SUBAGENT-STOP>

## 總覽
本 skill 把團隊 onboarding 文件消化成全域團隊 profile，寫入 `~/.claude/team-profile/` 並在
`~/.claude/CLAUDE.md` 掛常駐自檢區塊。格式與判準的權威來源：
- `references/profile-format.md`：目錄結構、條目範本、INDEX 與 CLAUDE.md 區塊模板、嚴重度分級。
- `references/onboarding-guide.md`：來源收集、訪談題庫、抽取判準、去重與衝突處理。

## Phase 0：判斷模式
- 檢查 `~/.claude/team-profile/INDEX.md` 是否存在：不存在→首次 onboard；存在或帶 `--update`→增量（先讀入既有條目供去重）。
- 解析 `$ARGUMENTS`：第一個 token 若為路徑或 URL 即為來源；`--interview` 進訪談模式；`--update` 標記增量。

## Phase 1：收集來源
依 `references/onboarding-guide.md` 第 1、2 節收集：本地資料夾（Glob→Read）、URL（WebFetch，抓取前確認）、`--interview`（題庫一問一答）、貼上文字。

## Phase 2：抽取 + 分級
依 `references/onboarding-guide.md` 第 3 節逐份抽條目，每條標 severity＋category＋來源；遵守寧缺勿濫。

## Phase 3：呈現候選、人工確認
**鐵律：使用者明確確認前，一律不寫任何檔。** 依 guide 第 3 節候選格式列出，詢問全收/刪編號/改編號；依 guide 第 4 節與既有 profile 去重、衝突標記請使用者裁決。可多輪來回。

## Phase 4：寫入
使用者確認後，依**固定順序**寫入（中途中斷可安全重跑）：
1. 分類檔（never/standards/workflow/glossary，依 `references/profile-format.md` 條目範本，id 取現有最大號 +1）
2. `INDEX.md`（更新統計、來源清單、updatedAt）
3. `~/.claude/CLAUDE.md` 常駐區塊（`never.md` 每條同步進「絕不可犯」清單；維護規則見 profile-format 第 5 節）

## Phase 5：回報
總結：新增/更新條目數、各嚴重度筆數、本次來源清單。**不自動 commit**（`~/.claude/` 非本 repo）。

## 鐵律
- 人工確認前絕不寫檔。
- CLAUDE.md 區塊：只認 `## 團隊規範（由 team-onboarding skill 維護）` 標題定位；找不到就檔尾重建；區塊內非本 skill 產生、使用者手動加的行保留不動。
- 只寫全域、不碰任何 repo 檔；單一團隊。
- 全程台灣正體中文。
- 與 self-evolution 共存：各自維護獨立的 CLAUDE.md 區塊與獨立目錄，互不干擾。
````

- [ ] **Step 3: 驗證 frontmatter 為合法 YAML 且欄位齊備**

Run: `head -12 skills/team-onboarding/SKILL.md`
Expected: 目視確認 `name`/`argument-hint`/`description`/`allowed-tools` 四欄齊備，`---` 開閉正確。

- [ ] **Step 4: 驗證未混入 inline-exec 字面量、且 5 個 Phase 皆在**

Run: `grep -rn -e '![\x60]' skills/team-onboarding/SKILL.md || echo "clean"; grep -c "^## Phase" skills/team-onboarding/SKILL.md`
Expected: 第一段輸出 `clean`；第二段輸出 `5`。

- [ ] **Step 5: Commit**

```bash
git add skills/team-onboarding/SKILL.md
git commit -m "feat(team-onboarding): 新增 SKILL.md 流程骨架（5 Phase + 鐵律）

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 發佈（README 一列 + 版本 bump）

**Files:**
- Modify: `README.md`（Available Skills 表，約 line 24 之後新增一列）
- Modify: `.claude-plugin/plugin.json`（`version` 1.3.0 → 1.4.0）
- Modify: `.claude-plugin/marketplace.json`（skill-registry plugin 那筆 `version` 1.3.0 → 1.4.0，約 line 16）

**Interfaces:**
- Consumes：Task 1、2 完成的 skill。
- Produces：可安裝發佈的 marketplace 狀態。

- [ ] **Step 1: README 新增一列**

在 `self-evolution` 那列之後新增：

```markdown
| `team-onboarding` | 通用跨 repo 的「新人入職」skill：把團隊 onboarding 文件（本地資料夾/貼上/連結/互動訪談）依嚴重度消化成全域 `~/.claude/team-profile/`，並在 `~/.claude/CLAUDE.md` 掛常駐自檢區塊——「絕對不可犯」常駐、細則按需 recall，讓任何 repo 開工都記得團隊規矩。人工確認前絕不寫檔。 |
```

- [ ] **Step 2: bump `plugin.json`**

將 `.claude-plugin/plugin.json` 的 `"version": "1.3.0"` 改為 `"version": "1.4.0"`。

- [ ] **Step 3: bump `marketplace.json`（skill-registry 那筆）**

將 `.claude-plugin/marketplace.json` 中 `source.url` 為 `wm4n/skill-registry.git` 那個 plugin 物件的 `"version": "1.3.0"` 改為 `"version": "1.4.0"`（勿動 openab/solo/mac-disk-cleanup 的版本）。

- [ ] **Step 4: 驗證兩份 manifest 版本一致且其餘未受影響**

Run: `grep '"version"' .claude-plugin/plugin.json; grep -A3 'skill-registry.git' .claude-plugin/marketplace.json | grep '"version"'`
Expected: 兩者皆輸出 `1.4.0`。

- [ ] **Step 5: 驗證 JSON 合法**

Run: `cat .claude-plugin/plugin.json | python3 -m json.tool > /dev/null && cat .claude-plugin/marketplace.json | python3 -m json.tool > /dev/null && echo "both valid"`
Expected: `both valid`。

- [ ] **Step 6: Commit**

```bash
git add README.md .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat(team-onboarding): 登記 README 並 bump 版本至 1.4.0

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage：**
- 定位/來源缺口 → Task 2 SKILL.md 總覽 + Task 1 references。✓
- 全域儲存結構（team-profile 五檔 + CLAUDE.md 區塊）→ Task 1 profile-format.md。✓
- 三種文件來源 → Task 1 onboarding-guide 第 1 節 + Task 2 Phase 1。✓
- 分層 + 主動檢查 → Task 1 CLAUDE.md 區塊模板（常駐清單 + 自檢指令）。✓
- 嚴重度分級 → Task 1 profile-format 第 2 節。✓
- 5 Phase 流程 → Task 2 Step 2。✓
- 鐵律（確認前不寫檔、CLAUDE.md 維護、只寫全域、繁中、與 self-evolution 共存）→ Task 2 鐵律節。✓
- 收尾（README + 版本 bump）→ Task 3。✓
- 非目標（無多團隊、無 hooks）→ Global Constraints 已鎖。✓

**2. Placeholder scan：** 各 code step 皆含實際 markdown/JSON 內容，無 TBD/TODO/「類似 Task N」。✓

**3. Type consistency：** id 前綴（N/S/W）、CLAUDE.md 區塊標題、team-profile 檔名在 Task 1、2、3 三處一致。✓
