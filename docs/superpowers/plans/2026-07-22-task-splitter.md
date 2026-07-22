# task-splitter Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一個 `task-splitter` skill，判斷功能需求是否過大並遞迴拆成 right-sized、含 Gherkin 驗收與 contract-first DAG 的子任務，交棒 writing-plans。

**Architecture:** 一個 slash 主呼叫的判斷/拆分型 skill。主檔 `SKILL.md`（frontmatter + Phase 流程）將判斷細則、拆分手法、輸出契約三塊邏輯分別外置到 `references/` 三個檔，比照 repo 內 `self-evolution` skill 的拆檔慣例。無應用程式碼、無建置工具；產物皆為 markdown 與 JSON manifest。

**Tech Stack:** Markdown + YAML frontmatter（skill 定義）、JSON（plugin/marketplace manifest）、`node` 供 JSON/YAML 驗證（repo 的假設基線工具，勿假設 `jq`/`python3`）。

## Global Constraints

- 所有 skill 輸出與說明文字使用**繁體中文**（依 repo 既有 skill 慣例與使用者全域規則）。
- **絕不**在任何 `SKILL.md` 或 reference 內寫出「驚嘆號＋反引號」的 skill 載入期 inline shell 執行指示字面（Claude Code 會掃描整份檔案並因參數展開被權限層擋下，導致 skill 無法啟動；連當範例寫都會誤觸掃描器）。需要示範時用文字描述，勿寫字面。
- 參考範本：`skills/jira-fetch/SKILL.md`（frontmatter 欄位、fail-loud 風格）與 `skills/self-evolution/`（references 拆檔）。
- `version` 同時出現在 `.claude-plugin/plugin.json` 與 `.claude-plugin/marketplace.json`，**兩者必須一致**；本次由 `1.2.0` bump 到 `1.3.0`。
- Skill 契約嚴謹度停在 artifact / 介面名稱層級，不碰型別簽名、SQL、內部實作（避免與 writing-plans / TDD 職責重疊）。
- 對照 spec：`docs/superpowers/specs/2026-07-22-task-splitter-design.md`。

---

## File Structure

- `skills/task-splitter/references/right-sizing-rubric.md` — 建立：right-sizing 判斷訊號細則與判定範例（spec 第 6 節）。
- `skills/task-splitter/references/split-patterns.md` — 建立：拆分手法與多平台 contract-first 規則、範例（spec 第 7、8 節）。
- `skills/task-splitter/references/output-contract.md` — 建立：任務契約格式、Gherkin 規範、最終輸出四塊、ID 命名（spec 第 9、10、11 節）。
- `skills/task-splitter/SKILL.md` — 建立：frontmatter + Phase 流程，引用上述三個 reference。
- `README.md` — 修改：Available Skills 表加一列。
- `.claude-plugin/plugin.json` — 修改：`version` `1.2.0` → `1.3.0`。
- `.claude-plugin/marketplace.json` — 修改：`plugins[0].version` `1.2.0` → `1.3.0`。

先建三個 reference（下游 SKILL.md 依賴其路徑），再寫 SKILL.md，接著併入 marketplace，最後 dogfood 驗收。

---

### Task 1: Reference — right-sizing-rubric.md

**Files:**
- Create: `skills/task-splitter/references/right-sizing-rubric.md`

**Interfaces:**
- Consumes: 無。
- Produces: 檔案路徑 `skills/task-splitter/references/right-sizing-rubric.md`，供 Task 4 的 SKILL.md Phase 2 引用。內容包含 7 條過大訊號與判定輸出規範。

- [ ] **Step 1: 先寫結構化驗證檢查（此時應失敗）**

Run:
```bash
test -f skills/task-splitter/references/right-sizing-rubric.md && \
grep -c "訊號" skills/task-splitter/references/right-sizing-rubric.md
```
Expected: FAIL（檔案不存在，`test -f` 回非零、無輸出）。

- [ ] **Step 2: 建立檔案，寫入以下完整內容**

`skills/task-splitter/references/right-sizing-rubric.md`：
````markdown
# Right-sizing Rubric

判斷一段需求（或一個切片）是否過大到需要再拆。採「明確檢查清單」而非加權評分或純自由判斷，理由：AI 自動化最需要**行為可重現**。

以 INVEST 的 **S**mall / **T**estable / **I**ndependent 為骨幹。

## 目標粒度（何時停）

一個葉子任務 = writing-plans 能單獨吃下並產出一份實作計畫的大小（約對應一個可獨立審查、可合併的 PR）。遞迴拆分持續到每個葉節點都通過本 rubric。

## 過大訊號（命中任一 → 判定候選過大，需拆分）

1. 驗收條件無法用單一情境講清，需要多個彼此無關的 AND 條件。
2. 橫跨超過約 2 個架構層（UI＋API＋DB＋外部整合混在同一任務）。
3. 描述含多個獨立可交付價值（可用「以及／並且／還要」切出多個獨立動詞目標）。
4. happy path 與多種 error/edge case 全混在一個任務。
5. 預估 writing-plans 會為它產出超過約 10 個實作步驟。
6. 含多個 CRUD 操作，或多個業務規則變體。
7. Gherkin 訊號：完整描述其行為需要超過約 3~5 個 Scenario。

## 判定輸出

判定結果為 `right-sized` 或 `too-big`，且**必須附上命中哪幾條訊號**（引用編號與一句理由），讓結論可解釋、可重現。

## 範例

需求「使用者可在 App 和網頁建立訂單並可查詢歷史訂單」：
- 命中訊號 2（跨後端＋多前端）、3（建立 + 查詢兩個獨立價值）、6（多操作）→ 判定 too-big。
````

- [ ] **Step 3: 執行驗證檢查（應通過）**

Run:
```bash
test -f skills/task-splitter/references/right-sizing-rubric.md && \
grep -c "^[0-9]\. " skills/task-splitter/references/right-sizing-rubric.md
```
Expected: PASS，且輸出 `7`（七條編號訊號）。

- [ ] **Step 4: Commit**

```bash
git add skills/task-splitter/references/right-sizing-rubric.md
git commit -m "feat(task-splitter): 新增 right-sizing rubric reference"
```

---

### Task 2: Reference — split-patterns.md

**Files:**
- Create: `skills/task-splitter/references/split-patterns.md`

**Interfaces:**
- Consumes: 無。
- Produces: 檔案路徑 `skills/task-splitter/references/split-patterns.md`，供 Task 4 的 SKILL.md Phase 4 引用。內容含 6 種 story-splitting patterns（依序）與多平台 contract-first 規則、範例 DAG。

- [ ] **Step 1: 先寫結構化驗證檢查（此時應失敗）**

Run:
```bash
grep -c "contract-first" skills/task-splitter/references/split-patterns.md
```
Expected: FAIL（檔案不存在，grep 回非零、無輸出）。

- [ ] **Step 2: 建立檔案，寫入以下完整內容**

`skills/task-splitter/references/split-patterns.md`：
````markdown
# 拆分手法（Split Patterns）

優先垂直切片（vertical slice），**不切水平層**。每個切片都要是「跨層但窄」的端到端一薄片可驗證價值，而不是「先做完所有 DB 再做所有 API」——水平層對 AI 自動化最致命，因為中間狀態不可驗證。

## Story-splitting patterns（依序嘗試）

1. 工作流步驟（workflow steps）
2. 業務規則變體（business rule variations）
3. happy path / error paths（天然對應 Gherkin 的 Scenario）
4. CRUD 操作
5. 介面 / 資料變體（含平台變體，見下節）
6. 大小硬切（effort）— 最後手段

## 多平台切分規則（contract-first）

當需求橫跨多平台（android / ios / web / 後端）時：

1. 偵測到多平台 + 存在共享後端/契約 → 抽出一個 contract-definition 任務放**上游**（通常是後端 API / schema / 協定），各平台變成**平行消費同一契約的兄弟任務**。
2. 切分主軸仍是 feature（垂直），平台是**第二軸**——「Feature A：契約 →〔Android ∥ iOS ∥ Web〕」，而**不是**「先全部 Android，再全部 iOS」。每個 feature 都能獨立端到端出貨。
3. 平台當第一刀的例外：平台間根本沒有共享契約（純客戶端、不同發版節奏、不同團隊）→ 才用純平台變體切成獨立兄弟任務。
4. 若共享契約任務本身太大 → 照常遞迴再拆。

### 範例

需求：「使用者可在 App 和網頁建立訂單」

```
T1 定義訂單 API 契約 (後端)
   Outputs: [OrderSchema, POST /orders, GET /orders/:id]
   Depends on: []

T2 Android 建立訂單畫面   Inputs: [T1:OrderSchema, T1:POST /orders]   Depends on: [T1]
T3 iOS 建立訂單畫面       Inputs: [T1:OrderSchema, T1:POST /orders]   Depends on: [T1]
T4 Web 建立訂單畫面       Inputs: [T1:OrderSchema, T1:POST /orders]   Depends on: [T1]
```

DAG（T2/T3/T4 平行、彼此零依賴）：

```
        +-- T2 Android
T1 契約 +-- T3 iOS
        +-- T4 Web
```

共享契約只被 T1 宣告一次成 Outputs，三支平台各自列進 Inputs；平台只依賴契約、不依賴彼此，因此可平行執行（適合搭配 dispatching-parallel-agents），下游永遠拿得到 T1 定義好的介面。
````

- [ ] **Step 3: 執行驗證檢查（應通過）**

Run:
```bash
grep -q "contract-first" skills/task-splitter/references/split-patterns.md && \
grep -c "^[0-9]\. " skills/task-splitter/references/split-patterns.md
```
Expected: PASS，輸出 `10`（6 條 patterns + 4 條多平台規則）。

- [ ] **Step 4: Commit**

```bash
git add skills/task-splitter/references/split-patterns.md
git commit -m "feat(task-splitter): 新增 split-patterns 與多平台 contract-first 規則"
```

---

### Task 3: Reference — output-contract.md

**Files:**
- Create: `skills/task-splitter/references/output-contract.md`

**Interfaces:**
- Consumes: 無。
- Produces: 檔案路徑 `skills/task-splitter/references/output-contract.md`，供 Task 4 的 SKILL.md Phase 6 引用。定義葉任務契約格式、Gherkin 規範、最終輸出四塊、ID 命名規則。

- [ ] **Step 1: 先寫結構化驗證檢查（此時應失敗）**

Run:
```bash
grep -c "Gherkin" skills/task-splitter/references/output-contract.md
```
Expected: FAIL（檔案不存在，grep 回非零、無輸出）。

- [ ] **Step 2: 建立檔案，寫入以下完整內容**

`skills/task-splitter/references/output-contract.md`：
````markdown
# 輸出契約（Output Contract）

## 葉任務契約格式

每個葉任務輸出以下結構化契約。嚴謹度停在 **artifact / 介面名稱層級**，不碰型別簽名、SQL、內部實作。

```
### T1.2 <標題>
- Goal: <一句話目標>
- Acceptance Criteria (Gherkin):
    Scenario: 成功建立訂單
      Given 已存在有效的購物車
      When 呼叫 POST /orders
      Then 回傳 201 且訂單狀態為 pending
    Scenario: 購物車為空時拒絕
      Given 購物車沒有品項
      When 呼叫 POST /orders
      Then 回傳 400 並附錯誤訊息
- Inputs (consumes): [T1.1:OrderSchema]
- Outputs (produces): [OrderSchema, POST /orders]
- Depends on: [T1.1]
- Right-sized: OK <理由>
```

（`Inputs` 空 = 無前置；`Outputs` = 給下游接的介面 / artifact。）

## Gherkin 規範

- 停在**行為層**——只描述看得到的輸入 / 輸出 / 狀態，不提函式名、SQL、內部類別。
- 一條使用者可觀察的路徑對一個 Scenario；happy path 與 error path 各自成 Scenario。
- 若需要超過約 3~5 個 Scenario 才描述得完 → 觸發過大訊號（見 right-sizing-rubric），應再拆。
- 這份 Gherkin 可直接餵給 TDD skill 當測試起點。

## 最終輸出（結構化 markdown，四塊）

1. 判定摘要：`right-sized` / `too-big` + 命中的 rubric 訊號理由。
2. 任務樹：深度不一的階層清單，葉節點都通過 right-sizing，每個葉節點含上方完整契約。
3. DAG 依賴圖 + 拓樸執行順序：文字化依賴圖與建議執行序；標出可平行的兄弟任務。
4. 交棒註記：建議對每個葉任務依拓樸序逐一跑 writing-plans；可平行者建議搭配 dispatching-parallel-agents。

## ID 命名規則

- 階層式 ID：頂層 `T1`、`T2`；子層 `T1.1`、`T1.2`；再下層 `T1.1.1`。
- ID 在整棵樹內唯一，Inputs / Depends on 一律以 ID（可加 `:artifact` 後綴）引用，確保串接參照明確。
````

- [ ] **Step 3: 執行驗證檢查（應通過）**

Run:
```bash
grep -q "Gherkin" skills/task-splitter/references/output-contract.md && \
grep -qE "Inputs \(consumes\)" skills/task-splitter/references/output-contract.md && \
grep -qE "Outputs \(produces\)" skills/task-splitter/references/output-contract.md && \
echo OK
```
Expected: PASS，輸出 `OK`。

- [ ] **Step 4: Commit**

```bash
git add skills/task-splitter/references/output-contract.md
git commit -m "feat(task-splitter): 新增 output-contract（含 Gherkin 驗收與 DAG 輸出）"
```

---

### Task 4: SKILL.md 主檔

**Files:**
- Create: `skills/task-splitter/SKILL.md`

**Interfaces:**
- Consumes: 三個 reference 檔路徑（Task 1/2/3 的 Produces）：`references/right-sizing-rubric.md`、`references/split-patterns.md`、`references/output-contract.md`。
- Produces: 可被 `/task-splitter <輸入>` 呼叫的 skill。輸入為需求文字 / spec 檔路徑 / Jira-ID（自動辨識）；輸出為 output-contract 定義的四塊結構化 markdown。

- [ ] **Step 1: 先寫結構化驗證檢查（此時應失敗）**

Run:
```bash
node -e '
const fs=require("fs");
const p="skills/task-splitter/SKILL.md";
const s=fs.readFileSync(p,"utf8");
const m=s.match(/^---\n([\s\S]*?)\n---/);
if(!m) throw new Error("no frontmatter");
if(!/name:\s*task-splitter/.test(m[1])) throw new Error("bad name");
console.log("frontmatter OK");
'
```
Expected: FAIL（檔案不存在，node 拋 ENOENT）。

- [ ] **Step 2: 建立檔案，寫入以下完整內容**

`skills/task-splitter/SKILL.md`：
````markdown
---
name: task-splitter
argument-hint: "[需求文字 | spec 檔案路徑 | Jira-ID]"
description: >-
  判斷一段功能需求是否太大到不適合直接進實作；若太大，遞迴拆成 right-sized、可獨立驗證的子任務。
  用 INVEST + 明確 rubric 判大小，用 vertical slice + story-splitting patterns 拆，
  多平台採 contract-first（共享契約放上游、各平台平行）。
  每個葉任務含 Gherkin (Given-When-Then) 驗收與結構化 artifact 串接契約，形成依賴 DAG，
  讓 AI 自動化開發能一個接一個順暢接力。終點交棒 writing-plans。
  適用時機：拿到一段功能需求 / spec / Jira 票，在進 brainstorming 或 writing-plans 前想先確認顆粒度是否恰當並拆分。
allowed-tools:
  - Read
  - Bash(node *)
---

# Task Splitter

判斷功能需求是否過大並拆成 right-sized、串接無礙的子任務，交棒 writing-plans。所有輸出使用繁體中文。

本 skill 只做「判大小 + 拆分 + 建串接契約」。**不寫實作計畫**（那是 writing-plans）、不寫程式碼、不碰型別/SQL/函式名等實作細節。

## Phase 1: 解析輸入（自動辨識來源）

取 `$ARGUMENTS` 第一個 token，判斷來源並正規化成一段「需求文字」：

1. 若是**存在的檔案路徑** → 用 `Read` 讀入。
2. 若符合 Jira ID 樣式 `[A-Z]+-\d+` → 呼叫 `jira-fetch` skill 取得結構化需求。
3. 其他 → 當作使用者直接貼上的純文字需求。

## Phase 2: Right-sizing 判定

依 `references/right-sizing-rubric.md` 的 7 條過大訊號比對目前這段需求。輸出 `right-sized` 或 `too-big`，**並附上命中哪幾條訊號與一句理由**。

## Phase 3: 分岔

- `right-sized` → 產出「可直接進實作」結論 + 依 `references/output-contract.md` 的單一任務契約（含 Gherkin 驗收）→ 提示交棒 writing-plans，結束。
- `too-big` → 進入 Phase 4。

## Phase 4: 拆分一層

依 `references/split-patterns.md` 手法（優先 vertical slice；多平台套用 contract-first 規則）把目前需求切一層。

## Phase 5: 遞迴

對每個切片回到 Phase 2 判定；`too-big` 就再拆，直到每片都 `right-sized`。設安全上限：拆到第 4 層仍未收斂就停，並提醒人工介入檢視需求是否本身定義不清。

## Phase 6: 建 DAG 並輸出

依 `references/output-contract.md`：

1. 指派階層式 ID（`T1` / `T1.1` / `T1.1.1`）。
2. 為每個葉任務填契約（Goal、Gherkin 驗收、Inputs、Outputs、Depends on、Right-sized 理由）。
3. 計算依賴邊與拓樸執行順序，標出可平行的兄弟任務。
4. 輸出四塊結構化 markdown：判定摘要、任務樹、DAG + 拓樸順序、交棒 writing-plans 註記。

## 參考

- `references/right-sizing-rubric.md` — 過大訊號與判定規範。
- `references/split-patterns.md` — 拆分手法與多平台 contract-first 規則。
- `references/output-contract.md` — 契約格式、Gherkin 規範、輸出四塊、ID 命名。
````

- [ ] **Step 3: 執行驗證檢查（frontmatter 合法 + 引用的三個 reference 都存在）**

Run:
```bash
node -e '
const fs=require("fs");
const p="skills/task-splitter/SKILL.md";
const s=fs.readFileSync(p,"utf8");
const m=s.match(/^---\n([\s\S]*?)\n---/);
if(!m) throw new Error("no frontmatter");
if(!/name:\s*task-splitter/.test(m[1])) throw new Error("bad name");
for(const r of ["right-sizing-rubric","split-patterns","output-contract"]){
  if(!fs.existsSync("skills/task-splitter/references/"+r+".md")) throw new Error("missing ref "+r);
}
console.log("frontmatter + refs OK");
'
```
Expected: PASS，輸出 `frontmatter + refs OK`。

- [ ] **Step 4: 掃描 bang-backtick 字面（必須不存在）**

Run:
```bash
grep -rn '`!`' skills/task-splitter/ ; echo "exit=$?"
```
Expected: 無任何符合行，且 `echo` 顯示 `exit=1`（grep 找不到 = 正確）。若有任何輸出，移除該字面改用文字描述。

- [ ] **Step 5: Commit**

```bash
git add skills/task-splitter/SKILL.md
git commit -m "feat(task-splitter): 新增 SKILL.md 主檔（Phase 流程與自動辨識輸入）"
```

---

### Task 5: 併入 marketplace（README + 版本 bump）

**Files:**
- Modify: `README.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: skill 名稱 `task-splitter`（Task 4 的 Produces）。
- Produces: 對外可見的 skill 註冊（README 表格列 + 一致的 `1.3.0` 版本號）。

- [ ] **Step 1: 先寫版本一致性檢查（此時應失敗）**

Run:
```bash
node -e '
const a=require("./.claude-plugin/plugin.json").version;
const b=require("./.claude-plugin/marketplace.json").plugins[0].version;
const fs=require("fs");
const hasRow=/`task-splitter`/.test(fs.readFileSync("README.md","utf8"));
if(a!=="1.3.0"||b!=="1.3.0") throw new Error("version not 1.3.0: "+a+"/"+b);
if(!hasRow) throw new Error("README missing task-splitter row");
console.log("release wiring OK");
'
```
Expected: FAIL（版本仍為 `1.2.0`，且 README 尚無該列）。

- [ ] **Step 2: 在 `README.md` 的 Available Skills 表 `learn-from-repo` 列之後、`self-evolution` 列之前（或表尾）新增一列**

在 `README.md` Available Skills 表格內新增：
```markdown
| `task-splitter` | 判斷功能需求是否過大並遞迴拆成 right-sized 子任務。用 INVEST + rubric 判大小、vertical slice 拆分、多平台採 contract-first，每個葉任務含 Gherkin 驗收與 artifact 串接契約（DAG），交棒 `writing-plans`。 |
```

- [ ] **Step 3: 修改 `.claude-plugin/plugin.json`**

將第 4 行 `"version": "1.2.0",` 改為：
```json
  "version": "1.3.0",
```

- [ ] **Step 4: 修改 `.claude-plugin/marketplace.json`**

將 `plugins[0]` 內的 `"version": "1.2.0",` 改為：
```json
      "version": "1.3.0",
```

- [ ] **Step 5: 執行版本一致性檢查（應通過）**

Run:
```bash
node -e '
const a=require("./.claude-plugin/plugin.json").version;
const b=require("./.claude-plugin/marketplace.json").plugins[0].version;
const fs=require("fs");
const hasRow=/`task-splitter`/.test(fs.readFileSync("README.md","utf8"));
if(a!=="1.3.0"||b!=="1.3.0") throw new Error("version not 1.3.0: "+a+"/"+b);
if(!hasRow) throw new Error("README missing task-splitter row");
console.log("release wiring OK");
'
```
Expected: PASS，輸出 `release wiring OK`。

- [ ] **Step 6: Commit**

```bash
git add README.md .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat(task-splitter): 註冊 skill 並 bump 版本至 1.3.0"
```

---

### Task 6: 端到端 dogfood 驗收

**Files:**
- 無新增/修改（純驗證；若發現缺陷則回到對應 Task 修正）。

**Interfaces:**
- Consumes: 完整安裝的 `task-splitter` skill（Task 1-5 的 Produces）。
- Produces: 一份驗收記錄，確認 skill 對多平台需求能產出四塊輸出、Gherkin 與平行平台 DAG。

- [ ] **Step 1: 對樣本需求執行 skill**

在本 session 依 `skills/task-splitter/SKILL.md` 的 Phase 流程，對以下樣本需求跑一遍（純文字輸入）：

```
使用者可以在 Android、iOS 和網頁上建立訂單並查詢歷史訂單
```

- [ ] **Step 2: 檢查輸出契約（人工核對）**

確認輸出**同時**具備：
1. 判定摘要為 `too-big`，且列出命中的 rubric 訊號編號與理由。
2. 任務樹葉節點都標 `Right-sized`。
3. 至少一個共享後端契約任務在上游，Android / iOS / Web 三個平台任務為平行兄弟（各自 `Depends on` 指向該契約任務、彼此無依賴）。
4. 每個葉任務的 Acceptance Criteria 為 Gherkin（含 `Given` / `When` / `Then`），且 happy path 與 error path 各自成 Scenario。
5. 輸出含 DAG 依賴圖 + 拓樸執行順序，並有交棒 writing-plans 註記。

- [ ] **Step 3: 缺陷處理**

若任一項不符 → 回到對應 reference（rubric / split-patterns / output-contract）或 SKILL.md 修正並重跑，直到五項全通過。若有修正，依修正檔案重新 commit。

- [ ] **Step 4: 記錄驗收結果**

於本 session 回報五項核對結果（通過 / 修正內容），完成驗收。無程式碼變更則不需額外 commit。

---

## Self-Review

**1. Spec coverage（逐節對照 spec）：**
- 第 2 節定位/邊界 → SKILL.md 導言 + Global Constraints。
- 第 3 節目標粒度 → right-sizing-rubric.md「目標粒度」。
- 第 4 節輸入自動辨識 → SKILL.md Phase 1（Task 4）。
- 第 5 節 Phase 流程 → SKILL.md Phase 1-6（Task 4）。
- 第 6 節 rubric → Task 1。
- 第 7 節拆分手法 → Task 2。
- 第 8 節多平台 contract-first → Task 2（含範例 DAG）+ Task 6 驗收第 3 項。
- 第 9 節任務契約 + Gherkin → Task 3 + Task 6 驗收第 4 項。
- 第 10 節輸出四塊 → Task 3 + Task 6 驗收第 5 項。
- 第 11 節 ID 命名 → Task 3。
- 第 12 節檔案結構 / manifest bump → Task 4、Task 5。
- 第 13 節設計依據 → 已內化於各 reference 內容，無需獨立任務。
無未覆蓋的 spec 需求。

**2. Placeholder scan：** 各 reference 與 SKILL.md 內容均為完整可寫入文字；驗證步驟均為可執行指令與明確預期輸出；無 TBD/TODO/「類似 Task N」。

**3. Type/命名一致性：** 三個 reference 檔名於 File Structure、各 Task Interfaces、SKILL.md「參考」段一致；ID 命名（`T1`/`T1.1`）於 output-contract 與 SKILL.md Phase 6 一致；版本 `1.3.0` 於 Global Constraints、Task 5 各步一致；skill 名 `task-splitter` 全篇一致。
````
