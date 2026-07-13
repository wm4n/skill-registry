# Jira REST API 整合指引

本文件定義 `learn-from-repo` skill 與 Jira 的整合方式，包含認證、連線驗證、issue 單號解析、資料撈取與錯誤處理。

---

## 章節 1：認證

從 config.json 讀取環境變數名稱，再讀取實際的認證值。執行任何 Jira 操作前，必須先驗證認證憑證。

**讀取認證環境變數**

```bash
EMAIL_VAR=$(jq -r '.jira.emailEnv' docs/knowledge/config.json)
TOKEN_VAR=$(jq -r '.jira.tokenEnv' docs/knowledge/config.json)
if [ -z "${!EMAIL_VAR}" ] || [ -z "${!TOKEN_VAR}" ]; then
  echo "缺少 Jira 認證環境變數：請設定 $EMAIL_VAR 與 $TOKEN_VAR"
fi
```

此腳本從 config.json 取出 `jira.emailEnv` 與 `jira.tokenEnv` 欄位值（這些是環境變數的名稱），然後用 bash 的 parameter expansion `${!EMAIL_VAR}` 取得環境變數的實際值。此腳本僅印出警告訊息，不會自行中止；呼叫方需自行檢查結果並決定是否中止後續流程。

**E001 安全警告：Token 值絕不可寫入 repo**

- Token 值**絕不可**寫入任何檔案（包括 config.json、知識庫檔案、日誌、臨時檔案等）
- 認證憑證僅透過環境變數傳遞，只在行程執行期間存在於記憶體中，行程結束即清除
- 所有含認證資訊的請求（curl、API 呼叫）僅在執行環境中進行，產出絕不記錄認證細節

---

## 章節 2：連線驗證

在初始化知識庫時，驗證 Jira 連線狀態與認證有效性。

**驗證指令**

```bash
curl -s -o /dev/null -w "%{http_code}" -u "${!EMAIL_VAR}:${!TOKEN_VAR}" \
  "$BASE_URL/rest/api/2/myself"
```

此指令向 Jira `/rest/api/2/myself` 端點發送認證請求，該端點回傳目前登入使用者的資訊。`-o /dev/null` 丟棄回應內容，`-w "%{http_code}"` 僅輸出 HTTP 狀態碼。

**期望結果與錯誤處理**

- **200**：連線成功，認證有效
- **401**：認證錯誤，檢查 email 與 token 是否正確，確認環境變數是否設定
- **404**：baseUrl 錯誤，檢查 `jira.baseUrl` 是否指向正確的 Jira instance

---

## 章節 3：單號解析

從 PR 資訊（title、head branch、body）提取相關的 Jira issue 編號。對 config.json 中 `jira.projectKeys` 陣列的每個 project key，應用對應的 regex 規則。

**解析規則**

對每個 project key `KEY`（如 `JIRA`、`OPS`），用以下 regex 掃描 PR 的三個部分，**依序進行**：

1. PR title
2. PR head branch 名稱（例如 `feature/1.3.0/JIRA-12345_adjust-login-flow` 中提取 `JIRA-12345`）
3. PR body

**Regex 模式**

```
\bKEY-[0-9]+\b
```

此模式為 case-sensitive，`\b` 為單詞邊界。例如若 `projectKeys` 為 `["JIRA", "OPS"]`，則分別掃描 `\bJIRA-[0-9]+\b` 和 `\bOPS-[0-9]+\b`。

**去重與聯集**

所有三部分的掃描結果合併，去除重複，得到該 PR 關聯的全部 issue 編號（無序集合）。例如若 title 含 `JIRA-123`，branch 含 `JIRA-456` 與 `JIRA-123`（重複），body 含 `OPS-789`，則最終集合為 `{JIRA-123, JIRA-456, OPS-789}`。

---

## 章節 4：撈取 issue

根據 issue 編號從 Jira 取得詳細資訊。優先使用 API v2；若伺服器不支援，降級到 API v3。

**API v2 指令（優先）**

```bash
curl -s -u "${!EMAIL_VAR}:${!TOKEN_VAR}" \
  "$BASE_URL/rest/api/2/issue/KEY-123?fields=summary,description,comment,issuetype,status" \
  | jq '{key: .key, summary: .fields.summary, type: .fields.issuetype.name, status: .fields.status.name, description: .fields.description, comments: [.fields.comment.comments[]? | {author: .author.displayName, body: .body}]}'
```

此指令請求 issue 的摘要（summary）、描述（description）、註解（comment）、類型（issuetype）、狀態（status）。回傳值經 jq 處理，輸出以下結構：

```json
{
  "key": "JIRA-123",
  "summary": "issue 標題",
  "type": "Bug",
  "status": "In Progress",
  "description": "描述內容（純文字）",
  "comments": [
    {"author": "使用者名稱", "body": "評論內容"},
    ...
  ]
}
```

**降級到 API v3**

若 API v2 端點回傳 404 或 410（Jira Cloud 或某些新版實例），改用以下指令：

```bash
curl -s -u "${!EMAIL_VAR}:${!TOKEN_VAR}" \
  "$BASE_URL/rest/api/3/issue/KEY-123?fields=summary,description,comment,issuetype,status"
```

API v3 中 `description` 欄位為 ADF 格式（Atlassian Document Format，JSON 結構）。遞迴收集所有 `text` 欄位並串接成純文字，丟棄其他格式資訊（markup、hyperlink 等）。

**註解處理**

- 僅取前 20 則註解，過長的註解清單截斷
- 每則註解記錄作者名稱與內容（body）

---

## 章節 5：錯誤處理

Jira API 呼叫失敗不應中斷整個批次處理流程。錯誤應被記錄為 warning，並繼續處理後續 PR。

**失敗場景與處理**

1. **Issue 不存在**：**v2 與 v3 皆回 404** 才記為 warning，該 issue 無法取得內容，並標注脈絡缺失；僅 v2 回 404/410 時，先依章節 4 改打 v3 端點重試，尚不算「不存在」
   
2. **API 網路錯誤或超時**（連線失敗、5xx 錯誤等）
   - 記為 warning，該 issue 暫時無法取得
   
3. **認證失敗**（401）
   - 記為 warning，提示檢查認證環境變數
   
4. **其他 API 錯誤**（如速率限制 429）
   - 記為 warning，不中斷流程

**知識條目標注**

當產出的知識條目引用無法取得的 Jira issue 時，應在**來源欄位**中加入說明標注。例如：

```markdown
- **來源**：[PR #45](https://github.com/org/repo/pull/45)、（Jira 脈絡缺失：JIRA-123 無法取得）、（Jira 脈絡缺失：OPS-456 無法取得）（2026-03-10）
```

若 issue 無法取得，知識條目**仍應產出**，但知識內容基於 PR 本身的文字內容與程式碼，缺少 Jira 的額外脈絡。

**不中斷原則**

任何單一 issue 的取得失敗或格式異常，均不應停止該 PR 的知識條目產出或影響後續 PR 的處理。Jira 是**補充資訊來源**，PR 內容的知識自身完整，Jira 資訊為強化。

