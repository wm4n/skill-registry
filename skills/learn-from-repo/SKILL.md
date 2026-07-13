---
name: learn-from-repo
description: Use when the user wants to build or update a team knowledge base from a repo's merged PRs (with linked Jira tickets and GitHub issues) — extracts business logic, architecture decisions, and lessons-learnt into docs/knowledge/. 當使用者說「學習這個 repo」、「從 PR 學習」、「更新知識庫」、「建立知識庫」或執行 /learn-from-repo 時使用。
---

# learn-from-repo

## 總覽

此 skill 掃描 repo 中已合併的 PR（含關聯的 Jira 單與 GitHub issue），從中抽取商務邏輯、架構決策與教訓，寫入目標 repo 的 `docs/knowledge/` 目錄，並維護一份可增量更新的團隊知識庫。所有寫入動作皆須經人工確認；本文件僅定義流程骨架，格式與判準細節見 `references/` 下三份權威文件：

- `references/knowledge-format.md`：知識庫目錄結構、`config.json`／`checkpoint.json` schema、glob 語意、知識條目範本、`INDEX.md` 格式、`CLAUDE.md` 指引區塊模板
- `references/jira-integration.md`：Jira 認證、連線驗證、單號解析、issue 撈取、錯誤處理
- `references/extraction-guide.md`：知識抽取判準、候選呈現格式、去重與衝突處理、來源標注

執行本 skill 前，先依序完成章節 1 的 Preflight 檢查，再依 config.json 是否存在決定進入章節 2（init）或章節 3（learn）。

---

## 章節 1：Preflight 檢查

依序執行以下四項檢查，任一項失敗即依指示處理，不得跳過：

1. **確認在 git repo 內且有 GitHub remote**：執行 `git remote -v`，確認輸出包含指向 GitHub 的 remote。若不在 git repo 內或無 GitHub remote，停止並告知使用者。
2. **確認 GitHub CLI 已登入**：執行 `gh auth status`。成功則繼續；失敗則停止，並指引使用者執行 `gh auth login` 後重試。
3. **確認 `jq` 可用**：確認 `jq` 指令存在（如 `command -v jq`）。不存在則停止並指引安裝。
4. **檢查知識庫是否已初始化**：檢查 `docs/knowledge/config.json` 是否存在。
   - 不存在 → 進入章節 2「init 流程」
   - 存在 → 讀取 config，依 `references/jira-integration.md` 章節 1 檢查 Jira 認證環境變數（該檢查僅印出警告、不會自行中止）；缺少環境變數時停止並指引使用者設定後重試，完成後進入章節 3「learn 流程」

---

## 章節 2：init 流程

init 流程必須依序完成以下五步；每個標示「等待使用者回覆」的互動點，都必須先取得使用者明確回覆才能進行下一步。

### Step 1：詢問 Jira 設定

詢問使用者 Jira `baseUrl`、`projectKeys`、email 環境變數名稱（`emailEnv`）、token 環境變數名稱（`tokenEnv`）。**等待使用者回覆。**

取得回覆後，依 `references/jira-integration.md` 章節 2 的連線驗證指令測試連線。若回傳非 200，依該章節的錯誤碼指引（401 檢查認證、404 檢查 baseUrl）告知使用者具體修正方向，並重新詢問直到驗證成功。

### Step 2：Branch 策略偵測

執行以下指令，觀察目標 repo 的 branch 慣例：

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
gh pr list --state merged --limit 100 --json baseRefName,headRefName \
  | jq -r '.[].baseRefName' | sort | uniq -c | sort -rn
```

從 base branch 分佈歸納出 pattern（例如觀察到 `feature/1.2.0/CodeReview`、`feature/1.3.0/CodeReview` 等多個版本化分支，即歸納為 `feature/*/CodeReview`）。同時觀察 PR 的 head→base 對，找出「head branch 本身也是常見 base branch」的晉升鏈（例如 `feature/*/CodeReview` → `develop` → `staging` → `master`）。

依觀察結果提議 `branches.learnFrom` 與 `branches.pipeline`（glob 語意見 `references/knowledge-format.md` 章節 3），呈現給使用者確認或修改。**等待使用者回覆。**

### Step 3：模組提議

讀取目標 repo 的目錄結構與 README，依常見的功能邊界提議 `modules` 清單（每個模組含 `name`、`description`、`paths`），清單中**必須包含** `general` 模組（`paths` 為空陣列，用於歸屬跨模組知識）。呈現給使用者確認或修改。**等待使用者回覆。**

### Step 4：建立知識庫骨架

依使用者確認後的設定，依 `references/knowledge-format.md`：
- 建立 `docs/knowledge/` 目錄結構（章節 1）
- 寫入 `docs/knowledge/config.json`（章節 2）
- 建立空的 `INDEX.md`（僅含標題與 `business-logic`／`architecture`／`lessons-learnt` 三個空章節，格式見章節 6）
- 依章節 7 的模板，於目標 repo 的 `CLAUDE.md` 插入或更新知識庫指引區塊（模組一覽依本次確認的 `modules` 產生）

### Step 5：詢問回填範圍

詢問使用者回填範圍：最近 N 個 PR／從某日期起／全部歷史。**等待使用者回覆。**

取得回覆後，將回填起點換算為對應的 merge 時間下限（此時尚無 `checkpoint.json`，以此回填起點作為 learn 流程章節 3 Step 1 的起點依據），接著進入章節 3「learn 流程」。

---

## 章節 3：learn 流程

learn 流程必須依序完成以下七步。

### Step 1：讀 checkpoint、撈 PR

讀取 `docs/knowledge/checkpoint.json` 的 `lastMergedAt`（依 `references/knowledge-format.md` 章節 4）；若 checkpoint 不存在，使用 init 流程 Step 5 換算出的回填起點。以此時間下限撈取已合併 PR，`${LAST_MERGED_AT_DATE}` 由 checkpoint 的 `lastMergedAt`（完整 ISO 8601 timestamp）直接代入：

```bash
gh pr list --state merged --limit 200 \
  --json number,title,body,baseRefName,headRefName,mergedAt,url \
  --search "merged:>${LAST_MERGED_AT_DATE}" \
  | jq 'sort_by(.mergedAt)'
```

若回傳筆數等於 200，代表可能被 `--limit 200` 截斷：以本次回傳最舊一筆的 `mergedAt` 為上限分段重撈（search 條件改 `merged:${LOWER}..${UPPER}`），重複直到回傳筆數 < 200，合併結果後再排序過濾。

### Step 2：Client 端過濾

對撈回的 PR 清單做 client 端過濾（glob 匹配依 `references/knowledge-format.md` 章節 3），依序套用：
1. 保留 `baseRefName` 符合 `branches.learnFrom` 任一 pattern 者
2. 再從中排除 `headRefName` 符合 `branches.pipeline` 任一 pattern 的晉升 PR（排除優先：若同時符合 `learnFrom` 與 `pipeline`，仍排除），並記錄「跳過 N 個晉升 PR」讓使用者知道
3. 排除 `mergedAt` ≤ checkpoint `lastMergedAt` 者（同秒重複保護）

### Step 3：分批處理，取得完整討論脈絡

以每批預設 10 個 PR 分批處理；若 diff 普遍很大，可將批次大小降至 5。對批次內每個 PR：

1. 執行 `gh pr view <n> --json body,comments,reviews,files` 取得完整討論
2. 執行 `gh pr diff <n>` 取得 diff。若 diff 超過約 2000 行，退化為「檔案清單 + PR 描述 + review comments」，不整份讀入
3. 依 `references/jira-integration.md` 章節 3–4 解析 PR 關聯的 Jira 單號並撈取 Jira 脈絡
4. 依 body 中的 `[Cc]loses #N`、`[Ff]ixes #N` 等關鍵字解析關聯的 GitHub issue 編號，並執行 `gh issue view <N> --json title,body` 取得 issue 內容

### Step 4：抽取候選知識

依 `references/extraction-guide.md` 抽取候選知識。抽取前，先讀取目標模組現有的知識檔案與 `INDEX.md`（供章節 4 的去重與衝突判斷使用），再進行抽取；抽取時遵守「寧缺勿濫」原則，一個 PR 完全可能產出 0 筆知識。

### Step 5：呈現候選、人工確認

以 `references/extraction-guide.md` 章節 3 的候選格式，呈現本批次全部候選知識給使用者，詢問：全部接受／指定編號刪除／指定編號修改。可多輪來回直到使用者確認。**等待使用者回覆。**

若本批 0 筆候選，告知使用者後視同確認完成，逕行 Step 6 推進 checkpoint（知識檔與 INDEX 無須變更）。

### Step 6：寫入知識庫

使用者確認後，依固定順序寫入：

1. **知識檔**：依候選內容新增條目，或依 `references/knowledge-format.md` 章節 5.3 的更新規則改寫既有條目
2. **INDEX**：重建 `INDEX.md` 中對應的索引行（章節 6 格式）；若本批模組有異動，同步更新 `CLAUDE.md` 指引區塊的模組一覽（章節 7）
3. **checkpoint**：以本批次最後一個 PR 的 `mergedAt`／`number` 更新 `checkpoint.json`，並一併更新 `updatedAt` 欄位

**寫入順序固定為「知識檔 → INDEX → checkpoint」**，不可調換。此順序確保若流程在中途中斷，`checkpoint.json` 尚未推進，重新執行本 skill 時會安全地重新處理同一批次，不會遺漏知識。

### Step 7：回報進度、詢問是否繼續

告知使用者本批次進度（已處理／剩餘批次數）。若還有下一批，詢問是否繼續。**等待使用者回覆。**

全部批次完成時，總結本次執行：新增／更新知識條目數、跳過的晉升 PR 數、Jira 脈絡缺失清單，並提醒使用者自行決定何時將知識庫變更 commit 進 repo（本 skill 不自動 commit）。

---

## 章節 4：重要原則

1. **人工確認前絕不寫檔**：任何知識條目在使用者於章節 3 Step 5 明確確認前，一律不得寫入知識庫檔案。
2. **token 絕不落地**：Jira email／token 僅存在於環境變數與行程記憶體中，絕不可寫入 config.json、知識庫檔案、日誌或任何暫存檔（見 E001）。
3. **一個 PR 抽出 0 筆知識是正常結果**：不應為了湊數而強行產出低品質或無普遍性的條目。
4. **知識內容一律使用台灣正體中文撰寫**。
