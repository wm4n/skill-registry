# task-splitter Skill 設計文件

- 日期：2026-07-22
- 狀態：設計定案，待寫實作計畫
- 類型：判斷 + 拆分型 skill（繁體中文、slash 主呼叫，可被其他 skill 當子步驟叫用）

## 1. 目的

給定一段功能需求，**判斷它是否太大到不適合直接進實作**；若太大，依業界成熟的拆分手法把它切成更小、更具體、可獨立驗證的子任務，並為每個子任務建立明確的「串接契約」，讓 AI 自動化開發能一個接一個順暢進行、下游任務零歧義地接上上游產出。

一句話：**用 INVEST + right-sizing rubric 判大小，用 vertical slice + story-splitting patterns 拆，用 contract-first DAG 保證串接。**

## 2. 定位與邊界

- **獨立判斷閘門**（standalone gate），不綁死在 brainstorming 內，可單獨測試、單獨呼叫。
- 在工作流中的位置：`需求 → task-splitter（判大小＋拆分）→ 對每個葉任務跑 writing-plans → 實作`。
- **終點是交棒 writing-plans**。本 skill 自己不寫實作計畫、不寫程式碼、不碰型別/SQL/函式名等實作細節，避免與 writing-plans / TDD 職責重疊。
- 呼叫方式：`/task-splitter <輸入>`；也可被 brainstorming / writing-plans 當子步驟叫用。
- 語言：所有輸出與說明使用繁體中文。

### 非目標（YAGNI）

- 不產出實作計畫（那是 writing-plans）。
- 不寫測試程式（Gherkin 只停在行為規格層，交給 TDD skill 落地）。
- 不估算人力/工時數字。
- 不做專案管理排程（只給拓樸執行順序，不排日期）。

## 3. 目標粒度（何時「夠小、可以停」）

一個葉子任務的目標粒度 = **writing-plans 能單獨吃下並產出一份實作計畫**的大小（約對應一個可獨立審查、可合併的 PR）。遞迴拆分持續到每個葉節點都通過 right-sizing rubric 為止。

## 4. 輸入來源（自動辨識）

skill 解析 `$ARGUMENTS` 第一個 token 決定來源：

1. **檔案路徑**（存在的 `.md` 等檔案）→ 用 `Read` 讀進來。
2. **Jira ID**（符合 `[A-Z]+-\d+` 樣式）→ 呼叫 `jira-fetch` 取得結構化需求。
3. **其他** → 當作使用者直接貼上的純文字需求。

三者都正規化成一段「需求文字」後進入判定。

## 5. Phase 流程

1. **解析輸入**：依上節自動辨識來源，正規化成需求文字。
2. **Right-sizing 判定**：套用第 6 節 rubric，產出判定（`right-sized` / `too-big`）與命中的訊號理由。
3. **分岔**：
   - `right-sized` → 輸出「可直接進實作」結論 + 單一任務契約（含 Gherkin 驗收）→ 交棒 writing-plans，結束。
   - `too-big` → 進入拆分。
4. **拆分一層**：依第 7 節手法（優先 vertical slice；多平台套用第 8 節契約優先規則）切一層。
5. **遞迴**：對每個切片回到 Phase 2 判定，太大就再拆，**直到每片都 right-sized**。設安全上限（預設 4 層）防止過度拆解，超過則停並提醒人工介入。
6. **建 DAG 並輸出**：指派階層 ID、填每個葉任務契約、計算依賴邊與拓樸順序、產出第 9 節的完整結構化 markdown。

## 6. Right-sizing Rubric（判斷機制：明確檢查清單）

採「明確 rubric 檢查清單」而非加權評分或純 LLM 自由判斷，理由是 AI 自動化最需要**行為可重現**。

以 INVEST 的 **S**mall / **T**estable / **I**ndependent 為骨幹。**命中任一訊號 → 判定為候選過大，需拆分：**

- 驗收條件無法用單一情境講清，需要多個彼此無關的 AND 條件。
- 橫跨超過約 2 個架構層（UI＋API＋DB＋外部整合混在同一任務）。
- 描述含多個獨立可交付價值（可用「以及／並且／還要」切出多個獨立動詞目標）。
- happy path 與多種 error/edge case 全混在一個任務。
- 預估 writing-plans 會為它產出超過約 10 個實作步驟。
- 含多個 CRUD 操作，或多個業務規則變體。
- **Gherkin 訊號**：完整描述其行為需要超過約 3~5 個 `Scenario`（代表塞了太多職責或太多規則變體）。

判定輸出需附「命中哪幾條訊號」，讓結論可解釋。

## 7. 拆分手法（優先垂直切片，不切水平層）

借用業界 story-splitting patterns，**依序嘗試**，優先能形成「端到端一薄片可驗證價值」的切法：

1. 工作流步驟（workflow steps）
2. 業務規則變體（business rule variations）
3. happy path / error paths（天然對應 Gherkin 的 Scenario）
4. CRUD 操作
5. 介面 / 資料變體（含平台變體，見第 8 節）
6. 大小硬切（effort）— 最後手段

核心約束：**每個切片都要是垂直薄片**（跨層但窄），而不是水平層（「先做完所有 DB 再做所有 API」）。水平層對 AI 自動化最致命，因為中間狀態不可驗證。

## 8. 多平台切分規則（contract-first）

當需求橫跨多平台（android / ios / web / 後端）時：

1. **偵測到多平台 + 存在共享後端/契約** → 抽出一個 **contract-definition 任務**放上游（通常是後端 API / schema / 協定），各平台變成**平行消費同一契約的兄弟任務**。
2. **切分主軸仍是 feature（垂直），平台是第二軸** — 例如「Feature A：契約 →〔Android ∥ iOS ∥ Web〕」，而**不是**「先全部 Android，再全部 iOS」。每個 feature 都能獨立端到端出貨。
3. **平台當第一刀的例外**：平台間根本沒有共享契約（純客戶端、不同發版節奏、不同團隊）→ 才用純平台變體切成獨立兄弟任務。
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
        ┌── T2 Android
T1 契約 ┼── T3 iOS
        └── T4 Web
```

共享契約只被 T1 宣告一次成 Outputs，三支平台各自列進 Inputs；平台只依賴契約、不依賴彼此，因此可平行執行（適合搭配 dispatching-parallel-agents），下游永遠拿得到 T1 定義好的介面。

## 9. 任務契約格式（串接契約：結構化 artifact 層級）

每個葉任務輸出以下結構化契約。契約嚴謹度停在 **artifact / 介面名稱層級**，不碰型別簽名、SQL、內部實作。

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
- Inputs (consumes): [T1.1:OrderSchema]      # 空 = 無前置
- Outputs (produces): [OrderSchema, POST /orders]  # 給下游接的介面 / artifact
- Depends on: [T1.1]
- Right-sized: ✅ <理由>
```

Gherkin 規範：

- 停在**行為層**——只描述看得到的輸入 / 輸出 / 狀態，不提函式名、SQL、內部類別。
- 一條使用者可觀察的路徑對一個 `Scenario`；happy path 與 error path 各自成 Scenario。
- 若需要超過約 3~5 個 Scenario 才描述得完 → 觸發第 6 節過大訊號，應再拆。
- 這份 Gherkin 可直接餵給 TDD skill 當測試起點。

## 10. 最終輸出（結構化 markdown）

供下游 agent 或人消費，包含四塊：

1. **判定摘要**：`right-sized` / `too-big` + 命中的 rubric 訊號理由。
2. **任務樹**：深度不一的階層清單，葉節點都通過 right-sizing，每個葉節點含第 9 節完整契約。
3. **DAG 依賴圖 + 拓樸執行順序**：文字化依賴圖與建議執行序；標出可平行的兄弟任務。
4. **交棒註記**：建議對每個葉任務依拓樸序逐一跑 writing-plans；可平行者建議搭配 dispatching-parallel-agents。

## 11. ID 命名規則

- 階層式 ID：頂層 `T1`、`T2`；子層 `T1.1`、`T1.2`；再下層 `T1.1.1`。
- ID 在整棵樹內唯一，Inputs / Depends on 一律以 ID（可加 `:artifact` 後綴）引用，確保串接參照明確。

## 12. 檔案結構

```
skills/task-splitter/
  SKILL.md                       # 主檔：frontmatter + Phase 流程
  references/
    right-sizing-rubric.md       # 第 6 節訊號細則與判斷範例
    split-patterns.md            # 第 7、8 節拆分手法與多平台契約優先規則
    output-contract.md           # 第 9、10、11 節契約 / 輸出 / ID 規範與範例
```

### SKILL.md frontmatter（草案）

- `name: task-splitter`
- `argument-hint: "[需求文字 | spec 檔案路徑 | Jira-ID]"`
- `description`：多行 `>-`，明確描述「判斷功能需求是否過大並拆成 right-sized、含 Gherkin 驗收與 contract-first DAG 的子任務，交棒 writing-plans」與觸發時機。
- `allowed-tools`：`Read`（讀 spec 檔）、必要時 `Bash` 供 Jira 分支（或直接叫 jira-fetch skill）。

### 配套更新

- `README.md` 的 Available Skills 表加一列。
- `plugin.json` 與 `marketplace.json` 版本一起 bump（兩者必須一致）。

## 13. 設計依據（業界實務對照）

- **INVEST** — 使用者故事的 right-sizing 準則；本 skill 以 Small / Testable / Independent 為判斷骨幹。
- **Story Splitting Patterns**（工作流步驟、業務規則變體、happy/error path、CRUD、介面變體、大小）— 拆分手法來源。
- **Vertical Slicing** — 每片端到端可驗證，而非水平分層。
- **BDD / Gherkin (Given-When-Then)** — 讓驗收條件從模糊形容升級成可執行、零歧義的行為規格。
- **Contract-first / 依賴 DAG + 拓樸排序** — 保證「串接無礙」：下游只依賴上游宣告的介面契約，可平行、可自動化接力。
