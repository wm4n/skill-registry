# learn-from-repo Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立通用的 `learn-from-repo` skill：從 repo 的 merged PR（連同 Jira 單、GitHub issue 脈絡）萃取商務邏輯、架構決策、lessons-learnt，累積成存放在目標 repo 內的團隊知識庫。

**Architecture:** 單一 skill、主 agent 順序處理（分批控制 context）；知識抽取邏輯抽成獨立 reference 檔與主流程解耦（spec 方案 C）。skill 由 SKILL.md（orchestration）+ 三個 reference 檔（格式定義、Jira 整合、抽取指引）組成。

**Tech Stack:** Claude Code skill（markdown 指令文件）、gh CLI（GitHub 資料）、curl + Jira REST API v2（Jira 資料）、jq（JSON 處理）。

**Spec:** `docs/superpowers/specs/2026-07-11-learn-from-repo-skill-design.md`（本計畫所有需求的權威來源）

## Global Constraints

- 所有 skill 內容、與使用者的互動、產出的知識庫內容一律使用台灣正體中文
- Jira 認證絕不進 repo：config 只記環境變數「名稱」，實際值在使用者本機環境變數（教訓 E001）
- 人工確認後才寫入知識庫檔案、才推進 checkpoint；確認前中斷重跑必須安全（冪等）
- 不寫死任何團隊 branch 流程：branch 策略一律走 config 的 glob pattern
- checkpoint 以 PR **merge 時間**為準（PR 編號順序與 merge 順序不一致）
- PR-centric：只從 merged PR 學習；Jira 單/GitHub issue 僅作為 PR 的背景脈絡
- skill 開發於本 repo `skills/learn-from-repo/`，安裝方式為 symlink 至 `~/.claude/skills/learn-from-repo`

---

### Task 1: knowledge-format.md — 知識庫結構與所有檔案格式的權威定義

**Files:**
- Create: `skills/learn-from-repo/references/knowledge-format.md`

**Interfaces:**
- Consumes: 無（本任務是基礎，定義所有 schema）
- Produces: `config.json` schema、`checkpoint.json` schema、知識條目範本（2 種）、`INDEX.md` 格式、CLAUDE.md marker 區塊模板、glob 匹配語意。Task 2/3/4 都引用本檔定義的格式，欄位名稱必須與本檔完全一致。

- [ ] **Step 1: 撰寫 knowledge-format.md**

檔案必須包含以下全部章節與內容（連接性說明文字可自行撰寫，但 schema、範本、規則必須逐字包含）：

**章節 1「目標 repo 知識庫結構」**——目錄樹（與 spec 一致）：

```
docs/knowledge/
├── config.json
├── checkpoint.json
├── INDEX.md
├── business-logic/      # 商務邏輯，按模組分檔（如 payment.md）
├── architecture/        # 架構決策，按模組分檔，記錄 what & why
└── lessons-learnt/      # 教訓，按模組分檔，跨模組的放 general.md
```

**章節 2「config.json schema」**——完整範例 + 逐欄位說明：

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

欄位說明必須包含：`emailEnv`/`tokenEnv` 存的是環境變數**名稱**不是值；`learnFrom` = 要學習的 base branch pattern；`pipeline` = 流程鏈 branch pattern（辨識晉升 PR 用）；`modules` 是知識庫「模組軸」，`general` 模組必須存在（跨模組知識的歸屬）。

**章節 3「glob 匹配語意」**——必須明確定義：pattern 中 `*` 匹配任意字串（**含** `/`）；匹配整個 branch 名稱（非部分匹配）；用 bash 驗證範例：

```bash
match_glob() { case "$2" in $1) return 0;; *) return 1;; esac; }
match_glob "feature/*/CodeReview" "feature/1.3.0/CodeReview"  # 0 (match)
match_glob "feature/*/CodeReview" "develop"                    # 1 (no match)
```

**章節 4「checkpoint.json schema」**：

```json
{
  "lastMergedAt": "2026-07-01T10:23:45Z",
  "lastPrNumber": 123,
  "updatedAt": "2026-07-11T08:00:00Z"
}
```

說明：`lastMergedAt` 是唯一的增量判斷依據（單一全域 checkpoint）；`lastPrNumber` 僅供人閱讀；只在人工確認寫入後才更新。

**章節 5「知識條目範本」**——兩種範本逐字包含（與 spec 相同）：

商務邏輯 / 架構決策：

```markdown
## 訂單逾時自動取消機制
- **What**：訂單建立後 30 分鐘未付款自動取消，庫存回補
- **Why**：早期曾因手動取消延遲導致超賣（JIRA-123）
- **相關檔案**：`src/orders/timeout.py`
- **來源**：PR #45、JIRA-123（2026-03-10）
```

Lessons-learnt：

```markdown
## 批次任務必須設定 DB connection timeout
- **問題**：夜間批次卡死導致連線池耗盡（JIRA-456）
- **根因**：長交易未設 timeout
- **教訓／如何避免**：所有批次任務使用 `with_timeout()` wrapper
- **來源**：PR #78、JIRA-456（2026-04-22）
```

規則：每筆知識必附來源與日期；「更新」在原條目改寫並**追加**來源（保留舊來源）；PR 來源寫成完整 URL 的 markdown 連結（如 `[PR #45](https://github.com/org/repo/pull/45)`），Jira 單同理。

**章節 6「INDEX.md 格式」**：

```markdown
# 知識庫索引

## business-logic
- [訂單逾時自動取消機制](business-logic/orders.md#訂單逾時自動取消機制) — 30 分鐘未付款自動取消並回補庫存

## architecture
（同格式）

## lessons-learnt
（同格式）
```

規則：每筆一行、anchor 用條目標題、一句話摘要 30 字內；INDEX 總量需控制在 AI 一次可讀完（超過約 200 條時提醒使用者考慮整併）。

**章節 7「CLAUDE.md 指引區塊模板」**——逐字包含：

```markdown
<!-- knowledge-base:start -->
## 專案知識庫（由 learn-from-repo skill 維護，勿手動編輯此區塊）

修改程式碼前，先讀 `docs/knowledge/INDEX.md`，找出與本次修改模組相關的知識條目並閱讀對應檔案。特別注意 `docs/knowledge/lessons-learnt/`——這些是團隊實際踩過的坑，避免重蹈覆轍。

模組一覽：{此處由 skill 依 config.modules 產生「name — description」清單}
<!-- knowledge-base:end -->
```

更新規則：有 marker 則只替換 start/end 之間內容；無 marker（含 CLAUDE.md 不存在）則追加至檔尾（不存在則建立檔案）。

- [ ] **Step 2: 驗證檔案完整性**

Run: `grep -c 'knowledge-base:start' skills/learn-from-repo/references/knowledge-format.md && grep -c 'lastMergedAt' skills/learn-from-repo/references/knowledge-format.md && grep -c 'learnFrom' skills/learn-from-repo/references/knowledge-format.md && grep -c 'match_glob' skills/learn-from-repo/references/knowledge-format.md`
Expected: 每個 grep 都 ≥ 1（四行輸出皆非 0）

- [ ] **Step 3: Commit**

```bash
git add skills/learn-from-repo/references/knowledge-format.md
git commit -m "feat: 知識庫格式定義 reference（config/checkpoint schema、條目範本、INDEX、CLAUDE.md 區塊）"
```

---

### Task 2: jira-integration.md — Jira REST API 整合指引

**Files:**
- Create: `skills/learn-from-repo/references/jira-integration.md`

**Interfaces:**
- Consumes: Task 1 的 config schema（`jira.baseUrl`、`jira.projectKeys`、`jira.emailEnv`、`jira.tokenEnv`，欄位名逐字一致）
- Produces: 連線驗證指令、單號解析規則、單筆 issue 撈取指令與欄位、錯誤處理規則。Task 4 的 init/learn 流程直接引用。

- [ ] **Step 1: 撰寫 jira-integration.md**

檔案必須包含以下章節（指令與 regex 逐字包含）：

**章節 1「認證」**：從 config 讀 `emailEnv`/`tokenEnv` 取得環境變數名稱，再讀取實際值。執行前檢查：

```bash
EMAIL_VAR=$(jq -r '.jira.emailEnv' docs/knowledge/config.json)
TOKEN_VAR=$(jq -r '.jira.tokenEnv' docs/knowledge/config.json)
if [ -z "${!EMAIL_VAR}" ] || [ -z "${!TOKEN_VAR}" ]; then
  echo "缺少 Jira 認證環境變數：請設定 $EMAIL_VAR 與 $TOKEN_VAR"
fi
```

明確警告：token 值絕不可寫入任何會進 repo 的檔案、不可出現在 config.json 或知識庫內容中（E001）。

**章節 2「連線驗證」**（init 時用）：

```bash
curl -s -o /dev/null -w "%{http_code}" -u "${!EMAIL_VAR}:${!TOKEN_VAR}" \
  "$BASE_URL/rest/api/2/myself"
```

Expected: `200`。非 200 時的指引：401 = 認證錯誤（檢查 email/token）、404 = baseUrl 錯誤。

**章節 3「單號解析」**：對 config 的每個 project key `KEY`，用 regex `\bKEY-[0-9]+\b`（case-sensitive）依序掃描 PR 的：title、head branch 名稱（如 `feature/1.3.0/JIRA-12345_adjust-login-flow`）、body。所有命中結果聯集去重。

**章節 4「撈取 issue」**：

```bash
curl -s -u "${!EMAIL_VAR}:${!TOKEN_VAR}" \
  "$BASE_URL/rest/api/2/issue/KEY-123?fields=summary,description,comment,issuetype,status" \
  | jq '{key: .key, summary: .fields.summary, type: .fields.issuetype.name, status: .fields.status.name, description: .fields.description, comments: [.fields.comment.comments[]? | {author: .author.displayName, body: .body}]}'
```

說明：用 API v2（description/comment 為可讀文字）；若該 Jira 只支援 v3（v2 回 404/410），改打 `/rest/api/3/issue/`，description 會是 ADF JSON，遞迴收集所有 `text` 欄位串接成純文字。comments 只取前 20 則，過長截斷。

**章節 5「錯誤處理」**（與 spec 錯誤處理表一致）：單號不存在（404）或 API 失敗 → 記 warning、繼續處理該 PR，產出的知識條目在來源行標注「（Jira 脈絡缺失：KEY-123 無法取得）」；不可因 Jira 失敗中斷整批。

- [ ] **Step 2: 驗證檔案完整性**

Run: `grep -c 'rest/api/2/myself' skills/learn-from-repo/references/jira-integration.md && grep -c 'KEY-\[0-9\]' skills/learn-from-repo/references/jira-integration.md && grep -c 'Jira 脈絡缺失' skills/learn-from-repo/references/jira-integration.md`
Expected: 三行輸出皆 ≥ 1

- [ ] **Step 3: Commit**

```bash
git add skills/learn-from-repo/references/jira-integration.md
git commit -m "feat: Jira REST API 整合 reference（認證、連線驗證、單號解析、issue 撈取、錯誤處理）"
```

---

### Task 3: extraction-guide.md — 知識抽取指引

**Files:**
- Create: `skills/learn-from-repo/references/extraction-guide.md`

**Interfaces:**
- Consumes: Task 1 的知識條目範本與三種知識類型目錄名（`business-logic`/`architecture`/`lessons-learnt`）
- Produces: 抽取判準、候選知識的中間格式（候選清單呈現格式）、去重與衝突處理規則。Task 4 的 learn 流程第 3–5 步直接引用。

- [ ] **Step 1: 撰寫 extraction-guide.md**

檔案必須包含以下章節：

**章節 1「三類知識的判準」**——每類給定義 + 2 個正例 + 2 個反例：

- **business-logic**（商務邏輯）：領域規則、業務約束、計算邏輯背後的商業原因。正例：「訂單 30 分鐘未付款自動取消（防超賣）」「VIP 折扣不可與優惠券疊加（JIRA 單載明財務要求）」。反例：「修正 typo」「升級套件版本」。
- **architecture**（架構決策）：技術選型、模式採用、邊界劃分的 what & why。正例：「改用 outbox pattern 確保事件不遺失（曾因直接發送遺失事件）」「拆出 rate-limiter middleware 供多服務共用」。反例：純重構無決策意涵、格式化調整。
- **lessons-learnt**（教訓）：曾造成 bug/事故/rework 的原因與預防方式。訊號：PR 是 hotfix/revert/二次修正、review comments 中有「上次就是這裡出問題」類討論、Jira 單是 Bug 型且描述了根因。正例：「批次任務未設 DB timeout 導致連線池耗盡」。反例：一次性的環境問題、無普遍性的個案。

**章節 2「值得記 vs 不值得記」**——核心測試：「三個月後的新成員（或 AI）讀到這條，會做出不同的、更好的決定嗎？」不值得記：可直接從程式碼看出的事實、純機械性變更（rename、bump version、lint fix）、只描述「改了什麼」而說不出「為什麼」的變更。一個 PR 可能產出 0 筆知識——**寧缺勿濫，0 筆是正常結果**。

**章節 3「候選知識呈現格式」**（人工確認時用）——逐字包含：

```markdown
### 候選 N（新增｜更新｜衝突）
- **類型/模組**：lessons-learnt / payment
- **標題**：批次任務必須設定 DB connection timeout
- **摘要**：一句話
- **來源**：PR #78、JIRA-456（2026-04-22）
- **完整內容**：（依 knowledge-format.md 範本填好的完整條目）
- **若為更新/衝突**：指出既有條目位置（檔案 + 標題）與差異說明
```

**章節 4「去重與衝突」**：抽取前先讀目標模組的現有知識檔 + INDEX；語意重複（同一規則不同措辭）→ 標記為「更新」合併；新變更推翻既有知識（如「30 分鐘改為 15 分鐘」）→ 標記為「衝突」，由人工確認時決定改寫（預設）或保留歷史註記；同批次內多個 PR 觸及同一知識 → 先在批內合併再呈現。

**章節 5「來源標注」**：每筆候選必附 PR 編號 + URL、Jira 單號（若有）、merge 日期；Jira 撈取失敗時標注「（Jira 脈絡缺失：KEY-123 無法取得）」。

- [ ] **Step 2: 驗證檔案完整性**

Run: `grep -c '寧缺勿濫' skills/learn-from-repo/references/extraction-guide.md && grep -c '候選 N' skills/learn-from-repo/references/extraction-guide.md && grep -c '衝突' skills/learn-from-repo/references/extraction-guide.md`
Expected: 三行輸出皆 ≥ 1

- [ ] **Step 3: Commit**

```bash
git add skills/learn-from-repo/references/extraction-guide.md
git commit -m "feat: 知識抽取指引 reference（判準、寧缺勿濫原則、候選格式、去重與衝突）"
```

---

### Task 4: SKILL.md — 主流程 orchestration

**Files:**
- Create: `skills/learn-from-repo/SKILL.md`

**Interfaces:**
- Consumes: Task 1–3 的三個 reference 檔（以相對路徑 `references/<name>.md` 引用；引用的欄位名、格式名必須與各檔一致）
- Produces: 完整可執行的 skill。使用者以 `/learn-from-repo` 觸發。

- [ ] **Step 1: 撰寫 SKILL.md**

Frontmatter（逐字使用，description 需同時涵蓋中英觸發語）：

```yaml
---
name: learn-from-repo
description: Use when the user wants to build or update a team knowledge base from a repo's merged PRs (with linked Jira tickets and GitHub issues) — extracts business logic, architecture decisions, and lessons-learnt into docs/knowledge/. 當使用者說「學習這個 repo」、「從 PR 學習」、「更新知識庫」、「建立知識庫」或執行 /learn-from-repo 時使用。
---
```

本文必須包含以下章節：

**章節 1「Preflight 檢查」**：
1. 確認在 git repo 內且有 GitHub remote（`git remote -v`）
2. `gh auth status` 成功；失敗則停止並指引 `gh auth login`
3. `jq` 可用
4. 檢查 `docs/knowledge/config.json`：不存在 → 進入 init 流程；存在 → 讀取 config，再依 `references/jira-integration.md` 章節 1 檢查 Jira 環境變數，然後進入 learn 流程

**章節 2「init 流程」**（必須依序，每個互動點都要等使用者回覆）：
1. 詢問 Jira 設定（baseUrl、projectKeys、email/token 環境變數名稱），依 `references/jira-integration.md` 章節 2 驗證連線，失敗則依錯誤碼指引修正後重試
2. Branch 策略偵測：

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
gh pr list --state merged --limit 100 --json baseRefName,headRefName \
  | jq -r '.[].baseRefName' | sort | uniq -c | sort -rn
```

   從 base branch 分佈歸納 pattern（如觀察到 `feature/1.2.0/CodeReview`、`feature/1.3.0/CodeReview` → 提議 `feature/*/CodeReview`），並觀察 head→base 對找出晉升鏈（head 也是常見 base 者），提議 `learnFrom` 與 `pipeline` 給使用者確認或修改（glob 語意見 `references/knowledge-format.md` 章節 3）
3. 模組提議：讀目錄結構與 README，提議 `modules` 清單（含必備的 `general`）給使用者確認或修改
4. 依 `references/knowledge-format.md` 建立 `docs/knowledge/` 目錄結構、寫入 `config.json`、空的 `INDEX.md`（只有標題與三個空章節）、依章節 7 模板更新 CLAUDE.md 指引區塊
5. 詢問回填範圍（最近 N 個 PR / 從某日期起 / 全部），將起點換算為 merge 時間下限後進入 learn 流程（此時尚無 checkpoint.json，以回填起點為準）

**章節 3「learn 流程」**（必須依序）：
1. 讀 checkpoint（`lastMergedAt`；無 checkpoint 用 init 的回填起點）。撈 PR：

```bash
gh pr list --state merged --limit 200 \
  --json number,title,body,baseRefName,headRefName,mergedAt,url \
  --search "merged:>${LAST_MERGED_AT_DATE}" \
  | jq 'sort_by(.mergedAt)'
```

（實作後補記：--limit 200 有截斷風險，SKILL.md 已加入分段重撈保護，見最終審查 Important #4）

2. Client 端過濾（glob 匹配依 `references/knowledge-format.md` 章節 3）：保留 base 符合 `learnFrom` 者；再排除 head 符合 `pipeline` 的晉升 PR（記錄「跳過 N 個晉升 PR」讓使用者知道）；`mergedAt` ≤ checkpoint 者排除（同秒重複保護）
3. 分批處理（每批預設 10 個 PR，diff 普遍很大時可降至 5）。對批內每個 PR：`gh pr view <n> --json body,comments,reviews,files` 取得完整討論；`gh pr diff <n>` 取 diff（超過約 2000 行時退化為檔案清單 + 描述 + review comments）；依 `references/jira-integration.md` 章節 3–4 解析單號並撈 Jira 脈絡；依 body 中 `[Cc]loses #N`、`[Ff]ixes #N` 解析關聯 issue 並 `gh issue view <N> --json title,body`
4. 依 `references/extraction-guide.md` 抽取候選知識（先讀現有知識庫相關檔案再抽取；寧缺勿濫）
5. 以 extraction-guide 章節 3 的候選格式呈現本批全部候選，詢問使用者：全部接受 / 指定編號刪除 / 指定編號修改（可多輪直到確認）
6. 確認後：寫入知識檔（新增條目 or 改寫既有條目）、重建 `INDEX.md` 對應行、若 modules 有異動同步 CLAUDE.md 區塊、最後以本批最後一個 PR 的 `mergedAt`/`number` 更新 `checkpoint.json`。**順序固定：知識檔 → INDEX → checkpoint**（中斷時 checkpoint 未推進，重跑安全）
7. 告知進度（已處理/剩餘），詢問是否繼續下一批。全部完成時總結：新增/更新知識數、跳過的晉升 PR 數、Jira 缺失清單，並提醒使用者自行決定何時 commit 知識庫變更

**章節 4「重要原則」**：人工確認前絕不寫檔；token 絕不落地（E001）；一個 PR 抽出 0 筆知識是正常結果；知識內容一律台灣正體中文。

- [ ] **Step 2: 驗證檔案完整性與引用一致性**

Run: `grep -c 'references/extraction-guide.md' skills/learn-from-repo/SKILL.md && grep -c 'references/knowledge-format.md' skills/learn-from-repo/SKILL.md && grep -c 'references/jira-integration.md' skills/learn-from-repo/SKILL.md && grep -c 'learnFrom' skills/learn-from-repo/SKILL.md && grep -c 'mergedAt' skills/learn-from-repo/SKILL.md`
Expected: 五行輸出皆 ≥ 1

Run: `ls skills/learn-from-repo/references/`
Expected: `extraction-guide.md  jira-integration.md  knowledge-format.md`（三個引用目標都存在）

- [ ] **Step 3: Commit**

```bash
git add skills/learn-from-repo/SKILL.md
git commit -m "feat: learn-from-repo SKILL.md 主流程（preflight、init、learn、人工確認、checkpoint）"
```

---

### Task 5: 安裝與情境驗證

**Files:**
- Create: symlink `~/.claude/skills/learn-from-repo` → 本 repo `skills/learn-from-repo/`
- Create: `README.md`（repo 根目錄，安裝與使用說明）

**Interfaces:**
- Consumes: Task 1–4 的完整 skill
- Produces: 可用的已安裝 skill + 驗證紀錄

- [ ] **Step 1: 建立 symlink 安裝**

```bash
ln -sfn "$(pwd)/skills/learn-from-repo" ~/.claude/skills/learn-from-repo
ls -la ~/.claude/skills/learn-from-repo/
```

Expected: symlink 指向本 repo，目錄下可見 SKILL.md 與 references/

- [ ] **Step 2: 情境測試（subagent 閱讀理解驗證）**

派一個 general-purpose subagent，prompt：「閱讀 `skills/learn-from-repo/SKILL.md` 及其 references/，然後回答：(1) 在一個沒有 `docs/knowledge/config.json` 的 repo 執行時，你的前三個動作是什麼？(2) PR `feature/1.3.0/CodeReview → develop` 會被學習還是跳過？為什麼？(3) 什麼時機才能更新 checkpoint.json？(4) Jira API 回 404 時如何處理？」

Expected 正確答案：(1) preflight 後進 init、先問 Jira 設定並驗證連線 (2) 跳過，head 符合 pipeline pattern，是晉升 PR (3) 使用者確認本批候選知識且知識檔與 INDEX 寫入完成之後 (4) 記 warning 繼續，知識標注「Jira 脈絡缺失」。任一題答錯 → 回頭修正對應文件的表述（模糊處補明確），重測直到全對。

- [ ] **Step 3: 撰寫 README.md**

內容：skill 用途一段、安裝指令（上述 symlink）、前置需求（gh 已登入、jq、Jira email/token 環境變數）、使用方式（`/learn-from-repo`，首次自動 init）、知識庫結構簡圖、spec 與 plan 文件連結。

- [ ] **Step 4: 端對端驗證（真實 repo）**

在使用者實際的工作 repo 執行 `/learn-from-repo`，走完 init + 最近 10 個 PR 的回填，依 spec 驗證清單逐項檢查：

1. Jira 連線與單號解析正確
2. 候選知識品質可接受（不佳 → 迭代 extraction-guide.md）
3. 人工確認流程順暢
4. INDEX.md 與 CLAUDE.md 更新正確
5. 再跑一次 `/learn-from-repo`：checkpoint 生效，不重複學習
6. branch pattern 過濾正確：功能 PR 被學習、晉升 PR 被跳過

此步驟需使用者參與（提供 Jira 設定與確認候選知識），發現的問題記錄後修正對應檔案。

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: README（安裝、前置需求、使用方式）"
```

---

## Self-Review 紀錄

- **Spec coverage**：知識庫結構/config/checkpoint（Task 1）、Jira 整合與 E001（Task 2）、抽取與去重/衝突（Task 3）、init/learn/branch 策略/人工確認/錯誤處理（Task 4）、驗證清單全 6 項（Task 5 Step 4）——spec 各節皆有對應任務。「未來擴充」節不在本計畫範圍（符合 spec）。
- **Placeholder scan**：無 TBD/TODO；CLAUDE.md 模板中 `{此處由 skill 依 config.modules 產生…}` 是模板的執行期變數，非計畫佔位符。
- **一致性**：`learnFrom`/`pipeline`/`lastMergedAt`/`emailEnv`/`tokenEnv` 等欄位名在 Task 1 定義、Task 2/4 引用處逐字一致；三個 reference 檔名在 Task 4 引用處與 Task 1–3 建立的路徑一致。
