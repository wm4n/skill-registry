# 知識庫格式定義

本文件是 `learn-from-repo` skill 的權威參考，定義所有知識庫檔案的結構與格式。後續任務會引用本檔的章節編號與欄位名稱，格式必須完全一致。

---

## 章節 1：目標 repo 知識庫結構

知識庫位於目標 repo 的 `docs/knowledge/` 目錄下，組織方式如下：

```
docs/knowledge/
├── config.json
├── checkpoint.json      # 首批確認後才產生
├── INDEX.md
├── business-logic/      # 商務邏輯，按模組分檔（如 payment.md）
├── architecture/        # 架構決策，按模組分檔，記錄 what & why
└── lessons-learnt/      # 教訓，按模組分檔，跨模組的放 general.md
```

每個子目錄 `business-logic`、`architecture`、`lessons-learnt` 內的 Markdown 檔案對應一個知識模組。例如 `business-logic/orders.md` 存放訂單模組的商務邏輯知識。跨模組或通用知識放在 `general.md`。

---

## 章節 2：config.json schema

`config.json` 是知識庫的全域配置檔。以下為完整範例及欄位說明：

```json
{
  "jira": {
    "baseUrl": "https://yourcompany.atlassian.net",
    "projectKeys": ["PROJ", "OPS"],
    "emailEnv": "JIRA_EMAIL",
    "tokenEnv": "JIRA_API_TOKEN"
  },
  "branches": {
    "learnFrom": ["feature/*/CodeReview"],
    "pipeline": ["feature/*/CodeReview", "develop", "staging", "master"]
  },
  "modules": [
    { "name": "auth", "description": "登入與權限", "paths": ["src/auth/"] },
    { "name": "general", "description": "跨模組/通用", "paths": [] }
  ]
}
```

### 欄位說明

**jira 區塊**
- `baseUrl`：Jira instance 的根 URL
- `projectKeys`：此 repo 相關的 Jira project key 陣列
- `emailEnv`：環境變數**名稱**（不是值），存放 Jira 登入 email
- `tokenEnv`：環境變數**名稱**（不是值），存放 Jira API token

**branches 區塊**
- `learnFrom`：要學習的 base branch pattern（用 glob 語法）。Skill 會掃描從這些 branch 合併來的 PR，提取知識條目
- `pipeline`：流程鏈 branch pattern（用 glob 語法）。用來辨識晉升 PR（如 develop → staging → master）

**modules 陣列**
- 知識庫「模組軸」，每個 object 代表一個模組
- `name`：模組唯一識別符（如 `auth`、`orders`、`general`）
- `description`：模組的人類可讀描述（如「登入與權限」）
- `paths`：此模組對應的程式碼路徑（glob pattern）陣列。跨模組或通用知識的模組 `paths` 留空陣列
- **必須存在** `general` 模組，用於歸屬跨模組的知識

---

## 章節 3：glob 匹配語意

Branch pattern 和 paths pattern 使用 glob 語法。以下定義匹配規則：

**規則**
1. Pattern 中的 `*` 匹配任意字串，**包含 `/` 字元**
2. 匹配整個字串（非部分匹配），即 pattern 必須與完整 branch/path 相符
3. 用 bash `case` 陳述式實作

**驗證範例**

```bash
match_glob() { case "$2" in $1) return 0;; *) return 1;; esac; }
match_glob "feature/*/CodeReview" "feature/1.3.0/CodeReview"  # 0 (match)
match_glob "feature/*/CodeReview" "develop"                    # 1 (no match)
```

執行上述函數後，第一個呼叫回傳 0（匹配），第二個回傳 1（不匹配）。

---

## 章節 4：checkpoint.json schema

`checkpoint.json` 記錄知識庫的增量學習進度。以下為完整範例及說明：

```json
{
  "lastMergedAt": "2026-07-01T10:23:45Z",
  "lastPrNumber": 123,
  "updatedAt": "2026-07-11T08:00:00Z"
}
```

### 欄位說明

- `lastMergedAt`：最後一批已處理完成的 PR 中最晚的合併時間（該 PR 不一定產出知識）（ISO 8601 格式）。這是**唯一的增量判斷依據**，用於決定下次掃描的起點。Checkpoint 為**單一全域 checkpoint**，不逐 branch 分別記錄
- `lastPrNumber`：最後一次學習的 PR 編號。**僅供人閱讀**，無運算意義
- `updatedAt`：checkpoint 的最後更新時間（ISO 8601 格式）

**更新時機**
- Checkpoint 只在人工確認（例如透過 skill 的「確認並更新」指令）後才寫入
- `checkpoint.json` 不在 init 時建立；第一批候選經人工確認寫入後才首次產生

---

## 章節 5：知識條目範本

知識庫中的每一筆知識條目必須遵循以下範本。分為兩種類型：

### 5.1 商務邏輯 / 架構決策範本

位置：`business-logic/` 或 `architecture/` 目錄下的模組檔案中。

```markdown
## 訂單逾時自動取消機制
- **What**：訂單建立後 30 分鐘未付款自動取消，庫存回補
- **Why**：早期曾因手動取消延遲導致超賣（JIRA-123）
- **相關檔案**：`src/orders/timeout.py`
- **來源**：PR #45、JIRA-123（2026-03-10）
```

### 5.2 Lessons-learnt 範本

位置：`lessons-learnt/` 目錄下的模組檔案中。

```markdown
## 批次任務必須設定 DB connection timeout
- **問題**：夜間批次卡死導致連線池耗盡（JIRA-456）
- **根因**：長交易未設 timeout
- **教訓／如何避免**：所有批次任務使用 `with_timeout()` wrapper
- **來源**：PR #78、JIRA-456（2026-04-22）
```

### 5.3 知識條目共通規則

1. 標題為 Markdown h2 (`## `)，簡潔明確
2. **來源欄位必填**，格式：
   - PR 寫成完整 URL 的 Markdown 連結：`[PR #45](https://github.com/org/repo/pull/45)`
   - Jira 單同理：`[JIRA-123](https://yourcompany.atlassian.net/browse/JIRA-123)`
   - 日期格式 `YYYY-MM-DD`
3. **更新**：若已存在的知識條目需更新，直接在原條目**改寫**內文，並**追加**新的來源（保留舊來源）。即條目內文可隨新知識修訂，但來源清單為 append-only
4. 每筆知識必附**來源與日期**

---

## 章節 6：INDEX.md 格式

`INDEX.md` 是知識庫的全域導覽索引。以下為格式規範：

```markdown
# 知識庫索引

## business-logic
- [訂單逾時自動取消機制](business-logic/orders.md#訂單逾時自動取消機制) — 30 分鐘未付款自動取消並回補庫存

## architecture
（同格式）

## lessons-learnt
（同格式）
```

### 格式規則

1. 按知識庫目錄分類：`business-logic`、`architecture`、`lessons-learnt`，各為 h2 標題
2. 每筆知識為一行列表項
3. 列表項格式：`- [條目標題](相對路徑#條目錨點) — 30 字內摘要`
   - `條目標題`：與對應 .md 檔中的 h2 標題完全相同
   - `相對路徑`：從 `INDEX.md` 所在目錄（`docs/knowledge/`）到目標檔案的相對路徑
   - `條目錨點`：Markdown 標題轉 anchor（小寫、空格改連字號）
   - `摘要`：一句話概括條目核心，30 字內
4. **索引規模控制**：INDEX 總量需控制在 AI 一次可讀完的範圍內。超過約 200 條時，提醒使用者考慮整併條目

---

## 章節 7：CLAUDE.md 指引區塊模板

Skill 會在目標 repo 的 `CLAUDE.md` 中插入知識庫指引區塊。以下為模板及規則：

```markdown
<!-- knowledge-base:start -->
## 專案知識庫（由 learn-from-repo skill 維護，勿手動編輯此區塊）

修改程式碼前，先讀 `docs/knowledge/INDEX.md`，找出與本次修改模組相關的知識條目並閱讀對應檔案。特別注意 `docs/knowledge/lessons-learnt/`——這些是團隊實際踩過的坑，避免重蹈覆轍。

模組一覽：{此處由 skill 依 config.modules 產生「name — description」清單}
<!-- knowledge-base:end -->
```

### 更新規則

1. **Marker 存在**（已有 `<!-- knowledge-base:start -->` 和 `<!-- knowledge-base:end -->`）
   - 只替換 start/end marker 之間的內容
   - 保留 marker 本身
   
2. **Marker 不存在**（新增或 CLAUDE.md 不存在）
   - 追加至 CLAUDE.md 檔尾
   - 若 CLAUDE.md 不存在則建立檔案
   - 新增時應包含完整的 start/end marker

3. **模組一覽清單**：由 skill 根據 `config.json` 中的 `modules` 陣列動態產生，格式為 `name — description`
