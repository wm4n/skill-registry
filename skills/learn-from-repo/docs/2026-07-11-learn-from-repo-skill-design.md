# learn-from-repo Skill 設計文件

日期：2026-07-11
狀態：已與使用者逐段確認

## 目標

建立一個通用的 Claude Code skill（`learn-from-repo`），透過分析 repo 的 merged PR（連同其關聯的 Jira 單與 GitHub issue），萃取商務邏輯、架構決策（what & why）、lessons-learnt 等知識，累積成存放在 repo 內、團隊共用的長期知識庫。目的是讓之後與 AI 工具協作時能自動補充背景知識與先前規格，並避免重蹈已犯過的錯誤。

## 需求共識

| 面向 | 決策 |
|---|---|
| 定位 | 團隊共用，知識庫以 markdown 存在目標 repo 內，隨版本控制走 |
| 更新模式 | 首次回填歷史（範圍可指定）+ 之後手動執行增量學習，以 checkpoint 記錄進度 |
| 資料來源 | GitHub PR / issue（gh CLI）+ Jira（REST API），第一版皆支援 |
| 組織方式 | 知識類型 × 模組雙軸 + 全域 INDEX，每筆知識附來源連結 |
| 知識消費 | skill 同步維護目標 repo CLAUDE.md 中的指引區塊 + INDEX，任何 AI 工具開 session 即受益 |
| 品質控管 | AI 產出候選知識 → 人工確認/編輯 → 才寫入 |
| 通用性 | 不綁定特定 repo，首次執行走 init 流程，設定存於 repo 內 config |
| Branch 策略 | 以 glob pattern 設定學習對象與晉升鏈，init 時資料驅動提議 + 人工確認，不寫死任何團隊流程 |
| 觸發方式 | 手動執行 slash command |

## 架構：方案 C

單一 skill、主 agent 順序處理（分批控制 context），但把「知識抽取邏輯」抽成獨立 reference 檔，主流程與抽取邏輯解耦。抽取品質的迭代只需修改 reference；未來若需升級為 subagent 平行抽取，同一份指引可直接沿用。

### Skill 端檔案結構

```
learn-from-repo/
├── SKILL.md                      # 主流程 orchestration（init + learn 兩個入口）
└── references/
    ├── extraction-guide.md       # 知識抽取指引：什麼算商務邏輯/架構決策/教訓、
    │                             #   判斷標準、去重原則、與現有知識衝突時的處理
    ├── knowledge-format.md       # 知識庫檔案格式、範本、INDEX 與 CLAUDE.md 指引格式
    └── jira-integration.md       # Jira REST API 呼叫方式、單號解析規則、認證做法
```

開發於本專案，完成後安裝到 `~/.claude/skills/`。

### 目標 repo 端結構（skill 執行時建立與維護）

```
docs/knowledge/
├── config.json          # Jira base URL、project keys、模組清單、token 環境變數名稱、
│                        #   branch 策略（learnFrom / pipeline patterns，見「Branch 策略」節）
├── checkpoint.json      # 上次處理完的 PR merge 時間（單一全域 checkpoint；PR 編號順序
│                        #   與 merge 順序不一致，故以 merge 時間為準，另記 PR 編號供人閱讀）
├── INDEX.md             # 全知識索引：每筆一行（標題 + 連結 + 一句話摘要）
├── business-logic/      # 商務邏輯：按模組分檔（如 payment.md、auth.md）
├── architecture/        # 架構決策：按模組分檔，記錄 what & why
└── lessons-learnt/      # 教訓：按模組分檔，跨模組的放 general.md
```

目標 repo 的 `CLAUDE.md` 中維護一段以 HTML 註解 marker 包住的指引區塊（`<!-- knowledge-base:start -->` / `<!-- knowledge-base:end -->`），內容為「修改某模組前先讀 `docs/knowledge/INDEX.md` 及對應檔案」。marker 讓 skill 每次執行能精準更新該區塊，不動 CLAUDE.md 其他內容。

### 安全性

Jira 認證（email + API token）不進 repo：`config.json` 只記環境變數「名稱」（如 `JIRA_API_TOKEN`），實際值存於使用者本機環境變數。符合既有教訓 E001（token 不落地到可分享位置）。

## Branch 策略

不同團隊的 branch 流程差異很大（GitHub-flow 直接進 main；git-flow 經 develop；版本制團隊用動態產生的整合 branch 如 `feature/1.3.0/CodeReview`）。skill 不寫死任何流程，改用「pattern + 角色」抽象：

### config 欄位

```json
{
  "learnFrom": ["feature/*/CodeReview"],
  "pipeline": ["feature/*/CodeReview", "develop", "staging", "master"]
}
```

- `learnFrom`：要學習的 base branch pattern（glob）。PR 的 base branch 符合任一 pattern 即為學習對象。固定名稱（如 `main`）是 pattern 的特例，GitHub-flow 團隊填 `["main"]` 即可
- `pipeline`：流程鏈上的 branch pattern，用於辨識晉升 PR

### 判斷規則（僅兩條，與具體流程無關）

1. PR 的 **base** 符合 `learnFrom` → 學習對象
2. PR 的 **head** 符合 `pipeline` → 晉升 PR（如 `CodeReview → develop`、`develop → staging`），跳過——內容已從功能 PR 學過，重複學習只會製造雜訊

範例（版本制流程）：`feature/1.3.0/JIRA-12345_xxx → feature/1.3.0/CodeReview` 被學習；`CodeReview → develop → staging → master` 三段晉升自動跳過；未來新版本開新的 CodeReview branch 自動被 pattern 涵蓋，無須改設定。hotfix 直接進 `master` 的團隊把 `master` 加入 `learnFrom` 即可（hotfix branch 的 head 不符合 `pipeline`，不會被誤跳過）。

### init 時的資料驅動提議

init 時以 `gh repo view --json defaultBranchRef` 偵測預設 branch，並撈最近 100 個 merged PR 統計 base/head branch 分佈（`gh pr list --state merged --json baseRefName,headRefName`），由 AI 歸納樣態提議 pattern（例如觀察到 `feature/1.2.0/CodeReview`、`feature/1.3.0/CodeReview` 即提議 `feature/*/CodeReview`），連同晉升鏈觀察一併呈現給使用者確認或修改後寫入 config。資料驅動提議 + 人工確認，skill 本身對流程零假設。

## 流程設計

### init 流程（偵測到 `docs/knowledge/config.json` 不存在時自動進入）

1. 詢問 Jira 設定：base URL、project key（可多個）、認證環境變數名稱 → 立即以 REST API 打測試請求驗證連線
2. 偵測預設 branch 並統計近期 merged PR 的 base/head 分佈，提議 `learnFrom` / `pipeline` pattern 給使用者確認（詳見「Branch 策略」節）
3. 掃描 codebase（目錄結構、README、主要進入點），提議模組/領域分類清單給使用者確認或修改——此清單即知識庫「模組軸」的依據，寫入 config
4. 建立目錄結構、`config.json`、空 `INDEX.md`、CLAUDE.md 指引區塊
5. 詢問回填範圍（最近 N 個 PR、或從某日期起），接著直接進入 learn 流程

### learn 流程（回填與增量共用同一管線，只差起始點）

1. 讀 config 與 checkpoint，撈取 checkpoint 之後的全部 merged PR（含 `baseRefName`/`headRefName`），按 merge 時間由舊到新排序（知識演進有順序性，新知識可能修正舊知識），再依「Branch 策略」規則於 client 端過濾：base 符合 `learnFrom` 者保留，head 符合 `pipeline` 的晉升 PR 跳過。學習對象 branch 是動態的（如版本制的 CodeReview branch），故不逐 branch 記 checkpoint，只維護單一全域 merge 時間 checkpoint
2. 分批處理（預設每批約 10 個 PR，視 diff 大小調整）。對每個 PR 收集：
   - `gh pr view`：描述、review comments、討論串
   - `gh pr diff`：過大時退化為「檔案清單 + 描述」
   - 以 project key 正則從 PR 標題/branch/描述解析 Jira 單號 → REST API 撈 summary、description、comments
   - PR 描述中 `closes #N` 等關聯的 GitHub issue
3. 依 `extraction-guide.md` 抽取候選知識，分類到「類型 × 模組」，每筆標注來源（PR 編號、Jira 單號、日期）
4. 與現有知識庫比對，候選標記為：新增／更新（補充既有知識）／衝突（新變更推翻舊知識）
5. 呈現本批候選知識摘要給使用者確認——可整批接受、逐筆刪除或編輯
6. 確認後才寫入檔案、更新 `INDEX.md`、推進 checkpoint（確認前 checkpoint 不動，中斷重跑安全）
7. 尚有下一批時詢問是否繼續

### 範圍決策：PR-centric

第一版以 merged PR 為學習主軸；Jira 單與 GitHub issue 是作為 PR 的背景脈絡被拉入，不獨立掃描。理由：merge 進主幹的變更才代表真正落地的知識；獨立 issue/Jira 單（如討論後決定不做的方案）價值較低且雜訊多。「獨立 issue 學習」列為未來擴充。

## 知識格式

每筆知識為檔案中一個 `##` 區塊，依類型使用不同範本（定義於 `knowledge-format.md`）：

**商務邏輯 / 架構決策**：

```markdown
## 訂單逾時自動取消機制
- **What**：訂單建立後 30 分鐘未付款自動取消，庫存回補
- **Why**：早期曾因手動取消延遲導致超賣（JIRA-123）
- **相關檔案**：`src/orders/timeout.py`
- **來源**：PR #45、JIRA-123（2026-03-10）
```

**Lessons-learnt**：

```markdown
## 批次任務必須設定 DB connection timeout
- **問題**：夜間批次卡死導致連線池耗盡（JIRA-456）
- **根因**：長交易未設 timeout
- **教訓／如何避免**：所有批次任務使用 `with_timeout()` wrapper
- **來源**：PR #78、JIRA-456（2026-04-22）
```

共同原則：

- 每筆知識必附來源連結與日期（可追溯、可判斷新舊）
- 「更新」在原條目上改寫並追加來源
- 「衝突」由人工確認時決定改寫或保留歷史註記
- `INDEX.md` 每筆一行：`- [標題](business-logic/payment.md#anchor) — 一句話摘要`，總量控制在 AI 一次可讀完的大小

## 錯誤處理

| 情況 | 處理 |
|---|---|
| Jira API 失敗或單號不存在 | 記 warning 繼續處理，該知識標注「Jira 脈絡缺失」 |
| `gh` 未登入 / 無權限 | 開頭 preflight 檢查，明確報錯並指引修復 |
| PR diff 過大 | 退化為檔案清單 + PR 描述 + review comments |
| 執行中斷 | checkpoint 只在人工確認後推進，重跑冪等安全 |
| CLAUDE.md 無 marker 區塊 | 視為首次，追加至檔尾；有 marker 則僅替換區塊內容 |

## 驗證方式

依 `superpowers:writing-skills` 流程開發與驗證 skill 本身。完成後於實際 repo 執行 `init` + 小範圍回填（如最近 10 個 PR），檢查：

1. Jira 連線與單號解析正確
2. 候選知識品質（抽取指引是否需迭代）
3. 人工確認流程順暢
4. `INDEX.md` 與 CLAUDE.md 更新正確
5. checkpoint 增量行為正確（重跑不重複學習）
6. branch pattern 過濾正確：功能 PR 被學習、晉升 PR（如 `CodeReview → develop`）被跳過

## 未來擴充（不在第一版範圍）

- 獨立 GitHub issue / Jira 單學習模式（不經 PR）
- subagent 平行抽取（沿用 extraction-guide.md）
- 排程自動執行產出 draft
