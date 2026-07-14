# Self-Evolution Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立一個專案無關的全域 skill `self-evolution`，讓 agent 在持續工作中學習錯誤、復盤彎路、擴張能力、打破慣性。

**Architecture:** 單一 skill + 分層 references（SKILL.md 為快篩入口，命中才載入對應 reference）；雙層儲存（全域 `~/.claude/evolution/` + 專案 auto-memory）；通用教訓精簡條列注入全域 `~/.claude/CLAUDE.md` 專屬區塊（上限 20 條）。

**Tech Stack:** 純 Markdown skill 檔案（無程式碼）。規範文件：`~/.claude/skills/self-evolution/DESIGN.md`（已批准的設計）。

## Global Constraints

- 所有產出檔案為 Markdown；skill 內文以繁體中文撰寫，SKILL.md 的 frontmatter `description` 為英文（含中文糾正語句實例）
- CLAUDE.md 注入區塊標題固定為 `## Self-Evolution 教訓（由 self-evolution skill 維護）`，條目格式 `- [Exxx] 一行摘要（詳: evolution/lessons/YYYYMMDD-slug.md）`，上限 20 條
- 教訓 scope 判斷準則：「換一個專案，這條還成立嗎？」成立 → 全域；不成立 → 專案 auto-memory
- subagent 情境不觸發此 skill
- `~/.claude` 不是 git repo：無 commit 步驟，每個 task 以 shell 檢查驗證
- 快篩無產出時不產生任何對話輸出

---

### Task 1: 初始化全域儲存結構 `~/.claude/evolution/`

**Files:**
- Create: `~/.claude/evolution/INDEX.md`
- Create: `~/.claude/evolution/lessons/.gitkeep`
- Create: `~/.claude/evolution/retros/.gitkeep`
- Create: `~/.claude/evolution/proposals/.gitkeep`
- Create: `~/.claude/evolution/patterns/.gitkeep`

**Interfaces:**
- Consumes: 無
- Produces: `INDEX.md` 的固定分區格式（Lessons / Retros / Proposals / Patterns），後續所有 task 與 skill 執行期都依此格式讀寫索引

- [ ] **Step 1: 建立目錄結構**

```bash
mkdir -p ~/.claude/evolution/lessons ~/.claude/evolution/retros \
  ~/.claude/evolution/proposals ~/.claude/evolution/patterns
touch ~/.claude/evolution/lessons/.gitkeep ~/.claude/evolution/retros/.gitkeep \
  ~/.claude/evolution/proposals/.gitkeep ~/.claude/evolution/patterns/.gitkeep
```

- [ ] **Step 2: 寫入 INDEX.md**

完整內容：

```markdown
# Evolution Index

每筆記錄一行，格式：`- [狀態] 標題 — 日期 — 路徑`

- lesson 狀態：active（在 CLAUDE.md 區塊中）/ archived（僅留完整記錄）/ repeated（二犯）
- proposal 狀態：pending / approved / rejected
- retro / pattern 無狀態，一律 `[-]`

## Lessons

## Retros

## Proposals

## Patterns
```

- [ ] **Step 3: 驗證**

Run: `ls ~/.claude/evolution/ && head -5 ~/.claude/evolution/INDEX.md`
Expected: 四個子目錄 + INDEX.md 存在，INDEX.md 首行為 `# Evolution Index`

---

### Task 2: 建立 SKILL.md（觸發入口 + 快篩 + 分流）

**Files:**
- Create: `~/.claude/skills/self-evolution/SKILL.md`

**Interfaces:**
- Consumes: Task 1 的 `INDEX.md` 格式
- Produces: 快篩四問與分流表；三個 reference 檔名（`references/error-learning.md`、`references/retrospective.md`、`references/capability-proposal.md`），Task 3–5 必須使用這些確切檔名

- [ ] **Step 1: 寫入 SKILL.md**

完整內容：

````markdown
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

`~/.claude/evolution/` 不存在時，先建立四個子目錄與 INDEX.md（分區：Lessons / Retros / Proposals / Patterns，每筆一行 `- [狀態] 標題 — 日期 — 路徑`）。

## 鐵律

- **寫入前先查 `~/.claude/evolution/INDEX.md`**：同主題已存在 → 更新既有記錄，不新增
- **糾正 vs 需求變更**：「你做的不符合我原本要的」才是糾正；「改成藍色」是新需求，不存教訓
- **快篩靜默**：無產出時不產生任何對話輸出
- **CLAUDE.md 區塊**：只認 `## Self-Evolution 教訓` 標題定位；找不到就在檔案末尾重建；區塊內非 `[Exxx]` 開頭的行（使用者手動加的）保留不動
````

- [ ] **Step 2: 驗證**

Run: `head -4 ~/.claude/skills/self-evolution/SKILL.md && grep -c "references/" ~/.claude/skills/self-evolution/SKILL.md`
Expected: frontmatter 含 `name: self-evolution`；references/ 出現次數 ≥ 4

---

### Task 3: 建立 references/error-learning.md（錯誤學習流程）

**Files:**
- Create: `~/.claude/skills/self-evolution/references/error-learning.md`

**Interfaces:**
- Consumes: SKILL.md 的 Scope 判斷規則、INDEX.md 格式、CLAUDE.md 區塊格式
- Produces: lessons 檔案格式（含「最後引用」欄位），Task 4 的復盤流程步驟 2 直接沿用本檔的寫入流程；Task 6 遷移資料依此格式

- [ ] **Step 1: 寫入 error-learning.md**

完整內容：

````markdown
# 錯誤學習流程

被使用者糾正時執行。目標：同樣的錯不犯第二次。

## 流程

### 1. 根因分析

不是記「我做錯了 X」，而是問：「**為什麼我當時會認為那樣是對的？**」

- 錯誤的假設？（我以為 A，實際是 B）
- 缺失的檢查？（動手前少確認了什麼）
- 知識空缺？（不知道存在某規則/工具/慣例）

### 2. 寫防範規則

一條**可執行**的規則：「做 Y 之前先確認 Z」。
「要更小心」「注意 X」不是規則，是空話——會被退回重寫。

### 3. 二犯檢查

查 `~/.claude/evolution/INDEX.md`：這次違反的是不是**已記錄的教訓**？

- 是 → 最強訊號：規則本身寫得不夠有效。必須**改寫規則**（例如把事後提醒改成
  流程中的事前檢查步驟），在 lessons 檔標記「二犯」+ 日期，INDEX 狀態改 `repeated`
- 否 → 繼續步驟 4

### 4. Scope 判斷與寫入

「換一個專案，這條還成立嗎？」

**成立（通用）**，做三件事：

a. 寫 `~/.claude/evolution/lessons/YYYYMMDD-<slug>.md`：

```markdown
# <一行標題>

- 日期：YYYY-MM-DD
- 情境：<發生什麼事，2-3 句>
- 使用者糾正：<原話或摘要>
- 根因：<步驟 1 的結論>
- 防範規則：<步驟 2 的規則>
- 適用範圍：<什麼情況下適用>
- 最後引用：YYYY-MM-DD（每次此教訓實際發揮作用或被違反時更新）
- 二犯記錄：（無 / YYYY-MM-DD + 改寫說明）
```

b. `INDEX.md` 的 Lessons 區加一行：`- [active] <標題> — YYYY-MM-DD — lessons/YYYYMMDD-<slug>.md`

c. `~/.claude/CLAUDE.md` 區塊加一行（見下方「CLAUDE.md 區塊維護」）

**不成立（專案特定）**：寫入當前專案的 auto-memory（沿用其 frontmatter 格式，
type 用 `feedback`），並更新該專案 MEMORY.md 索引。不動全域檔案。

## CLAUDE.md 區塊維護

區塊位於 `~/.claude/CLAUDE.md`，標題 `## Self-Evolution 教訓（由 self-evolution skill 維護）`。

- 條目格式：`- [Exxx] <一行摘要>（詳: evolution/lessons/YYYYMMDD-<slug>.md）`
- 編號取現有最大值 +1；區塊不存在 → 在檔案末尾建立
- 區塊內非 `[Exxx]` 開頭的行保留不動
- **上限 20 條**。加入新條目後若超限，依序執行：
  1. 合併同類條目（合併後指向較新的 lessons 檔，舊檔補「已併入」註記）
  2. 仍超限 → 降級「最後引用日期最舊」的條目：從區塊移除，
     lessons 檔保留，INDEX 狀態改 `archived`

## 完成後

向使用者一句話報告：「已記錄教訓 [Exxx]：<摘要>」（專案層則說明存入專案記憶）。
````

- [ ] **Step 2: 驗證**

Run: `grep -c "二犯\|最後引用\|上限 20" ~/.claude/skills/self-evolution/references/error-learning.md`
Expected: ≥ 4（關鍵機制都在檔內）

---

### Task 4: 建立 references/retrospective.md（完整復盤 + 慣性反思）

**Files:**
- Create: `~/.claude/skills/self-evolution/references/retrospective.md`

**Interfaces:**
- Consumes: Task 3 的教訓寫入流程（步驟 2 直接引用）、INDEX.md 格式
- Produces: retros/ 與 patterns/ 檔案格式

- [ ] **Step 1: 寫入 retrospective.md**

完整內容：

````markdown
# 完整復盤流程

快篩命中「彎路」（失敗重試 2 次以上、推倒重做、方向修正）或「慣性」時執行。

## 彎路復盤

### 1. 還原決策點

- 在哪一步選錯了方向？
- 當時已有什麼資訊，其實足以避開這條彎路？
- 是沒看到資訊，還是看到了但判斷錯？

### 2. 提煉教訓

走 error-learning.md 的完整寫入流程（根因 → 防範規則 → 二犯檢查 → scope 判斷與寫入）。
若彎路純屬外部因素（環境故障、第三方變更）且無可預防，不寫教訓，僅留復盤記錄。

### 3. 創造力反思

- 這次的解法是慣性還是最佳解？
- 如果重來一次，有沒有更優雅、更省力的路徑？

**有具體洞見**才寫入 `~/.claude/evolution/patterns/<slug>.md`：

```markdown
# <思考模式標題>

- 日期：YYYY-MM-DD
- 情境類型：<什麼類型的問題>
- 慣性做法：<原本會怎麼做>
- 更好的路徑：<具體替代方案與適用條件>
- 來源：<哪次任務的洞見>
```

空泛感想（「下次要多想想」）不寫。寫入後在 INDEX.md 的 Patterns 區加一行。

### 4. 產出復盤記錄

寫 `~/.claude/evolution/retros/YYYYMMDD-<slug>.md`（一頁以內）：

```markdown
# <任務一行描述>

- 日期：YYYY-MM-DD
- 彎路：<發生什麼>
- 決策點：<步驟 1 的結論>
- 教訓：<指向 lessons 檔，或「純外部因素，無教訓」>
- 創造力反思：<指向 patterns 檔，或「無新洞見」>
```

INDEX.md 的 Retros 區加一行。

## 慣性反思（快篩第 4 題命中時）

不需要完整復盤，只做：

1. 問：「同類問題我已連續用同一方法幾次？結果真的好嗎？」
2. 花一分鐘想 1-2 條別的路徑：有沒有工具/角度/順序上的替代方案？
3. 查 `~/.claude/evolution/patterns/`：已有相關模式 → 下次任務開始時套用
4. 有新洞見 → 依上方格式寫入 patterns/；沒有 → 結束，不留檔

## 完成後

向使用者一句話報告復盤結論（有產出檔案時附路徑）。
````

- [ ] **Step 2: 驗證**

Run: `grep -c "決策點\|patterns/\|error-learning.md" ~/.claude/skills/self-evolution/references/retrospective.md`
Expected: ≥ 5

---

### Task 5: 建立 references/capability-proposal.md（能力提案流程）

**Files:**
- Create: `~/.claude/skills/self-evolution/references/capability-proposal.md`

**Interfaces:**
- Consumes: INDEX.md 格式（Proposals 區、pending/approved/rejected 狀態）
- Produces: proposals/<slug>/ 資料夾格式（PROPOSAL.md + 草稿 SKILL.md）

- [ ] **Step 1: 寫入 capability-proposal.md**

完整內容：

````markdown
# 能力提案流程

快篩偵測到「第 3 次以上做同類工作」時執行。目標：把重複勞動固化成新能力，
但生效與否由使用者把關。

## 流程

### 1. 防重複檢查

查 `~/.claude/evolution/INDEX.md` 的 Proposals 區：

- 同主題已 `pending` → 不重複提案，提醒使用者有提案待審即可
- 同主題已 `rejected` → 不重提，直接結束（除非情境明顯改變——例如當初否決的
  理由已不存在，此時說明變化後再提）
- 同主題已 `approved` → 檢查為何既有 skill 沒被觸發，這本身可能是一個教訓

### 2. 確認模式

- 這三次的共同步驟是什麼？
- 變動的部分能參數化嗎？
- 未來還會再發生嗎？（一次性的批量工作不值得固化）

三題有任一「否」→ 不提案，結束。

### 3. 寫提案

建 `~/.claude/evolution/proposals/<slug>/PROPOSAL.md`：

```markdown
# <提案標題>

- 日期：YYYY-MM-DD
- 狀態：pending
- 觀察到的重複：<三次分別是什麼時候、做了什麼>
- 共同模式：<可固化的步驟>
- 建議形態：<skill / 既有 skill 的擴充 / script>
- 預期效益：<省下什麼>
```

### 4. 寫 skill 草稿

依 superpowers:writing-skills 的規範，在同資料夾寫好可用的 `SKILL.md` 草稿
（含 frontmatter name/description、完整流程）。草稿放在 proposals/ 內**不生效**。

### 5. 告知使用者

「我注意到 <模式> 已重複三次，已備好 skill 草稿在
`~/.claude/evolution/proposals/<slug>/`，要啟用嗎？」

- **批准** → 搬進 `~/.claude/skills/<slug>/SKILL.md`，PROPOSAL.md 狀態改
  `approved`，INDEX 同步；然後**真實跑一輪驗證**（用真實情境走一次新 skill，
  確認觸發與流程正確）
- **否決** → 狀態改 `rejected`，記下否決理由，INDEX 同步，留檔不重提

INDEX.md 的 Proposals 區維護一行：`- [狀態] <標題> — YYYY-MM-DD — proposals/<slug>/`
````

- [ ] **Step 2: 驗證**

Run: `grep -c "pending\|rejected\|approved" ~/.claude/skills/self-evolution/references/capability-proposal.md`
Expected: ≥ 6

---

### Task 6: 初始化 CLAUDE.md 區塊 + 遷移第一筆真實教訓

**Files:**
- Modify: `~/.claude/CLAUDE.md`（末尾追加區塊）
- Create: `~/.claude/evolution/lessons/20260410-no-client-side-api-keys.md`
- Modify: `~/.claude/evolution/INDEX.md`（Lessons 區加一行）

**Interfaces:**
- Consumes: Task 3 定義的 lessons 檔格式與 CLAUDE.md 區塊格式；來源資料：hangman 專案 `agents/lessons.md` Entry 001
- Produces: `[E001]` 條目——第一筆真實資料，驗證整條寫入鏈

- [ ] **Step 1: 寫 lessons 檔**

寫入 `~/.claude/evolution/lessons/20260410-no-client-side-api-keys.md`：

```markdown
# 絕不在 client 端注入 API Key / Token 等敏感資料

- 日期：2026-04-10
- 情境：word_translation_service.dart 透過 --dart-define=GEMINI_API_KEY=...
  將 Gemini API Key 注入 Flutter app，從手機裝置直接呼叫 Gemini API。
- 使用者糾正：這樣不對，API Key 不應該放在 client 端。
- 根因：錯誤假設——以為 --dart-define 的值是安全的。實際上會被編譯進 binary，
  可透過 decompile APK/IPA 提取，等同公開 API Key。
- 防範規則：任何第三方 API 呼叫，實作前先確認 Key 的存放位置——只能在 server 端
  （後端 proxy：Cloud Function / Cloud Run 等）。--dart-define、hardcode、
  環境變數注入 client 一律禁止。
- 適用範圍：所有 mobile/client app 對外部 API 的呼叫（不限 Flutter）。
- 最後引用：2026-07-07（遷移入庫）
- 二犯記錄：無
- 來源：hangman 專案 agents/lessons.md Entry 001（原記錄保留於該專案）
```

- [ ] **Step 2: 更新 INDEX.md**

在 `## Lessons` 標題下加：

```markdown
- [active] 絕不在 client 端注入 API Key — 2026-04-10 — lessons/20260410-no-client-side-api-keys.md
```

- [ ] **Step 3: 在 ~/.claude/CLAUDE.md 末尾追加區塊**

先 Read 現有檔案確認末尾內容，然後追加：

```markdown

## Self-Evolution 教訓（由 self-evolution skill 維護）

- [E001] 絕不在 client 端注入 API Key / Token，第三方 API 一律走後端 proxy（詳: evolution/lessons/20260410-no-client-side-api-keys.md）
```

- [ ] **Step 4: 驗證**

Run: `grep -A3 "Self-Evolution 教訓" ~/.claude/CLAUDE.md && grep "E001\|no-client-side" ~/.claude/evolution/INDEX.md ~/.claude/evolution/lessons/*.md | head -3`
Expected: CLAUDE.md 區塊含 `[E001]`；INDEX.md 有對應行；lessons 檔存在

---

### Task 7: 真實驗證（需使用者參與）

**Files:**
- 無新檔案（驗證行為）

**Interfaces:**
- Consumes: Task 1–6 的全部產出
- Produces: 驗證結論；發現問題則修正對應檔案

- [ ] **Step 1: 靜默路徑驗證**

請使用者給一個順利的小任務（或以剛完成的 Task 1–6 收尾當場跑快篩）。
Expected: 快篩四題全「否」→ 無任何多餘輸出、evolution/ 無新檔案產生。

- [ ] **Step 2: 錯誤學習路徑驗證**

請使用者故意糾正一次（例如指出某個產出不符合他原本要的）。
Expected 檢查清單：
- 觸發 self-evolution skill 並讀取 error-learning.md
- 根因分析回答「為什麼當時認為是對的」而非「做錯了什麼」
- scope 判斷正確（通用 → 全域；專案特定 → auto-memory）
- 全域路徑時：lessons 檔 + INDEX 行 + CLAUDE.md `[E002]` 三處一致
- 向使用者一句話報告

- [ ] **Step 3: 觸發率驗證（新 session）**

請使用者開新 session、做一個會被糾正的小互動，確認 description 能在
沒有本對話 context 的情況下觸發。
Expected: 新 session 中被糾正時 skill 被調用。

- [ ] **Step 4: 修正與收尾**

任一步驗證失敗 → 修正對應檔案（description 措辭、流程步驟）後重測該步。
全部通過 → 向使用者報告驗證結果，skill 正式生效。
能力提案路徑（需自然累積三次重複）留待日常使用驗證。
