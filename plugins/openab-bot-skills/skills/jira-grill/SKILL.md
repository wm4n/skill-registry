---
name: jira-grill
argument-hint: "discover | ticket <JIRA-ticket-id> [repo=<owner/repo>]"
description: >-
  Jira grill-me 需求審視。由 discovery/per-ticket cron job 觸發（不是
  @mention、不在 Discord 對話）：票貼 grill-me label 後，先解析並準備好
  對應的 GitHub repo，再在 Jira comment 上用 grilling 式連續追問（design
  tree/frontier，見 mattpocock-skills:grilling），收斂或人類喊停後只貼
  結論通知人類，不自動開發、不交棒。獨立於三 bot 接力 pipeline。
---

# Jira Grill

Jira 是唯一真相來源：每次執行都重新從 Jira 撈完整內容與留言判斷目前進度，
不依賴 session 記憶本身的正確性。Session 延續只是效率紅利。

## 兩種觸發模式（`$ARGUMENTS`）

- `discover`：由固定的 discovery cron job 呼叫，找出新貼 `grill-me` label
  的票並啟動它們。
- `ticket <TICKET_ID> [repo=<owner/repo>]`：由該票專屬的 cron job 呼叫，
  檢查這張票是否有新回覆並推進下一輪；`repo=` 有帶就是已知的目標
  repo（見下）。

## Repo 解析與準備

產出第一輪問題前，先確定這個需求要動到哪個 repo、把它準備好——grilling
要根據實際程式碼提問，不是憑空對需求文字發問。

**解析優先序**（比照 `requirement-analysis` skill，少了即時人類對話這個
管道）：

1. Jira 票的欄位（描述、custom field）裡有明確的 `owner/repo` 或 GitHub
   URL → 直接用。
2. 用 `product-context` skill 背後的登錄表解析：即時抓取（不 clone、不
   落地）：
   ```bash
   gh auth switch --hostname github.com --user cac-william
   gh api repos/104corp/104cac-product-registry/contents/products.yaml \
     -H "Accept: application/vnd.github.raw+json"
   ```
   以票號的 project key（`TICKET_ID` 連字號前的部分，如 `CACJOB-123` →
   `CACJOB`）比對各產品的 `jira.project`——這裡輸入是已知的 project
   key，不是 `product-context` 原本設計吃的「使用者自由語句比對
   name/aliases」，比對邏輯換掉，登錄表這個單一真相來源不換：
   - 命中單一產品、且該產品只有一個 repo → 直接用。
   - 命中單一產品但 `repos[]` 有多個（依 role，如 android/ios/backend）
     → 把「這個需求對應哪個 repo/平台」併入第一輪 frontier。
   - 命中多個產品共用同一個 project key、完全沒命中、或 `gh api` 抓取
     失敗（比照 `product-context` 自己的 edge case：不臆測、不中斷任務）
     → 都視為未解析，繼續步驟 3。
3. 都無法決定 → **repo 未定**。把「這個需求要動到哪個 repo？」併入第一輪
   frontier（跟其他問題貼在同一則 comment），當成一般 frontier 問題處理，
   不是特殊流程，等 Jira 回覆。

**repo 一旦確定，立刻準備**（比照 Rick 的「開工前準備」SOP）：

1. 用 `repo-identity` skill 依 owner 選 GitHub 帳號、`gh auth switch`。
2. Base clone 固定在 `/home/node/repos/<owner>/<repo>`：不存在就 clone，
   存在就 `git fetch`/`pull` 到最新。**只在 base clone 上讀，不建
   worktree**——這裡不改檔案、不切分支，不落入「repo 相關工作一律用
   worktree」那條鐵則要管的範圍。
3. 讀該 repo 的 `CLAUDE.md`/`AGENTS.md`、相關程式碼與既有實作，把查得到
   的事實（檔案結構、既有慣例、技術限制）寫進問題內容。你自己查得到的
   事實不該變成丟給人類的問題，只有真正的決策才問人類。

**discovery 建立 per-ticket cron job 時**，把已解析出的 repo 一併寫進
`message`（`執行 jira-grill skill，參數：ticket <TICKET_ID> repo=
<owner/repo>`），之後每輪直接讀這個值、只做 `git fetch`/`pull`，不用
重跑解析。若當時還沒解析出來，`message` 不帶 `repo=`，流程二會在拿到
回覆後自己補上（見流程二 步驟 6）。

## 提問格式與簽名標記

沿用 `mattpocock-skills:grilling` 的 design tree/frontier 方法論：每輪只
問前提已經 settled 的問題（frontier），問完就等下一則留言；新留言到了才
重算下一輪 frontier；frontier 真正清空——每個分支都有明確答案，不是「問到
差不多就好」——才算收斂。

一輪的所有 frontier 問題合併成同一則 comment：

```
❓ **Q1** - **<問題標題>**：<問題內容，可多段、可列選項>

➡️ <你的建議答案>
```

多題就重複這組 `❓`/`➡️`，最後只收尾一次：

```
---
目前還有 {N} 個分支未決。

— By Rick (jira-grill)
```

第一輪（剛偵測到 `grill-me`、還沒有任何回覆）以票的標題、描述、驗收條件
與「Repo 解析與準備」查到的程式碼事實為輸入直接產出 frontier，不要等
留言。

**簽名是機器可辨識標記，不是裝飾**：結尾固定 `— By Rick (jira-grill)`
（不是 persona 其他情境用的 `— By Rick`）。流程二靠這串文字判斷「留言區塊
最上面那則是不是自己剛貼的」，沒有新回覆時直接結束、省掉整輪 Jira 呼叫。
改了格式，no-op 判斷會失效，導致同一輪問題重複問或漏判新回覆。

## 環境變數

- `JIRA_TOKEN` / `JIRA_EMAIL` / `JIRA_BASE_URL`：同 `jira-fetch` skill。
- `JIRA_GRILL_CHANNEL`：discovery job 建立 per-ticket cron job 時要用的
  Discord channel ID（Rick 既有頻道）。
- `JIRA_GRILL_PROJECTS`：discovery 掃描的 Jira project key 清單，逗號
  分隔（如 `CACJOB,CACVIP,CACATS`）。**只掃這些 project**，不掃 Jira
  帳號能存取的其他專案——避免跨專案的 `grill-me` label 誤觸發。

執行前用與 `jira-fetch` 相同的方式確認四個變數存在（`${VAR:+set}`
寫法，不要用 skill frontmatter 的 load-time inline shell 檢查，會被權限層
擋下）：

```bash
echo "JIRA_TOKEN: ${JIRA_TOKEN:+set}"
echo "JIRA_EMAIL: ${JIRA_EMAIL:+set}"
echo "JIRA_BASE_URL: ${JIRA_BASE_URL:+set}"
echo "JIRA_GRILL_CHANNEL: ${JIRA_GRILL_CHANNEL:+set}"
echo "JIRA_GRILL_PROJECTS: ${JIRA_GRILL_PROJECTS:+set}"
```

任一缺少：說明缺什麼變數並停止，不繼續嘗試。

## Jira API 慣例

沿用 `jira-fetch` 的寫法：`curl -u "${JIRA_EMAIL}:${JIRA_TOKEN}"` 做 Basic
Auth，一律用 `node -e` 解析/組 JSON，不假設 `jq`／`python3`／GNU-only
coreutils 存在。讀票內容與留言一律呼叫 `jira-fetch` skill（`jira-fetch
<TICKET_ID> --comments 50`），不要自己重寫一份讀取邏輯。

以下三個動作是 `jira-fetch` 沒有的，本 skill 自己實作：

### 改 label

```bash
# 範例：把 grill-me 換成 grill-me-active（收斂/中止時把 grill-me-active
# 換成 grill-me-done，remove/add 的值換掉即可）
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -X PUT "${JIRA_BASE_URL}/rest/api/2/issue/${TICKET_ID}" \
  -H "Content-Type: application/json" \
  -d '{"update":{"labels":[{"remove":"grill-me"},{"add":"grill-me-active"}]}}')
if [ "$STATUS" != "204" ]; then
  echo "ERROR: 改 label 失敗（HTTP ${STATUS}），停止處理這張票，留給下次 discovery/poll 重試。"
fi
```

### 貼 comment

```bash
# COMMENT_BODY 是要貼的完整文字（含結尾簽名，見上方「提問格式與簽名標記」）
node -e '
const body = process.argv[1];
process.stdout.write(JSON.stringify({ body }));
' "$COMMENT_BODY" > /tmp/jira-grill-comment.json

STATUS=$(curl -s -o /dev/null -w '%{http_code}' -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -X POST "${JIRA_BASE_URL}/rest/api/2/issue/${TICKET_ID}/comment" \
  -H "Content-Type: application/json" \
  -d @/tmp/jira-grill-comment.json)
if [ "$STATUS" != "201" ]; then
  echo "ERROR: 貼 comment 失敗（HTTP ${STATUS}）。"
fi
```

### JQL 搜尋（只有 discovery 流程用）

```bash
PROJECTS_CLAUSE=$(node -e '
const keys = process.env.JIRA_GRILL_PROJECTS.split(",").map(s => s.trim()).filter(Boolean);
console.log("project IN (" + keys.map(k => JSON.stringify(k)).join(",") + ")");
')
JQL="${PROJECTS_CLAUSE} AND labels = \"grill-me\" AND labels != \"grill-me-active\""
ENCODED_JQL=$(node -e 'console.log(encodeURIComponent(process.argv[1]))' "$JQL")
RESPONSE=$(curl -s -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -w '\n%{http_code}' \
  "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&fields=key")

printf '%s' "$RESPONSE" | node -e '
const raw = require("fs").readFileSync(0, "utf8");
const nl = raw.lastIndexOf("\n");
const status = raw.slice(nl + 1).trim();
const body = raw.slice(0, nl);
if (status !== "200") { console.log("ERROR: JQL 搜尋失敗（HTTP " + status + "）"); process.exit(0); }
const issues = (JSON.parse(body).issues) || [];
if (!issues.length) { console.log("(no new tickets)"); process.exit(0); }
for (const i of issues) console.log(i.key);
'
```

沒有搜到任何票 → 印出 `(no new tickets)` 後直接結束，不做任何其他動作
（no-op，控制成本）。

## 流程一：Discovery（`$ARGUMENTS = discover`）

1. 確認環境變數（含 `JIRA_GRILL_CHANNEL`、`JIRA_GRILL_PROJECTS`）。
2. 執行上面的 JQL 搜尋，取得所有符合的 `TICKET_ID` 清單。清單為空就結束。
3. 對每個 `TICKET_ID` 依序：
   a. 呼叫 `jira-fetch ${TICKET_ID} --comments 50` 取得標題/描述/驗收條件/
      現有留言。
   b. 把 label 從 `grill-me` 換成 `grill-me-active`（改 label 失敗 → 跳過
      這張票，印出錯誤，繼續下一張，不建立 cron job，留給下次 discovery
      重試）。
   c. 依「Repo 解析與準備」決定並準備目標 repo（可能成功解析並 clone/
      fetch，也可能未定、留給第一輪 frontier 去問）。
   d. 以描述、驗收條件、（若已知）repo 裡查到的程式碼事實為輸入，產出
      第一輪 frontier 問題（格式見上文「提問格式與簽名標記」；repo 未定
      時把「哪個 repo」併入這一輪一起問），貼成第一則 comment。
   e. 用 `openab-schedule` skill 的 `[[jobs]]` TOML 語法（**不要**套用它
      文件裡「先跟人類確認卡片」那段流程——discovery 是無人在場的自動
      觸發，人類已經透過核准這份 spec 一次性授權這套自動建立/清理 job
      的行為），在 `~/.openab/cronjob.toml` 新增：
      ```toml
      [[jobs]]
      id = "jira-grill-<TICKET_ID>"
      enabled = true
      schedule = "*/10 * * * *"
      channel = "<JIRA_GRILL_CHANNEL 的值>"
      message = "執行 jira-grill skill，參數：ticket <TICKET_ID>"
      sender_name = "jira-grill-<TICKET_ID>"
      timezone = "Asia/Taipei"
      ```
      repo 已在步驟 c 解析出來的話，`message` 改成
      `"執行 jira-grill skill，參數：ticket <TICKET_ID> repo=<owner/repo>"`。
      讀取既有檔案內容、保留其他 job，只新增這一筆（絕不覆蓋整個檔案）。
4. 全部處理完，不需要額外摘要輸出（discovery thread 本身沒有人在看）。

## 流程二：Per-ticket（`$ARGUMENTS = ticket <TICKET_ID> [repo=<owner/repo>]`）

1. 確認環境變數。
2. 呼叫 `jira-fetch ${TICKET_ID} --comments 50`，取得完整內容（含
   labels、全部留言，留言依 `jira-fetch` 慣例新到舊排序）。
3. **中止訊號 1（label 被人類改掉）**：若回傳的 labels 不含
   `grill-me-active`，視為人類已手動中止 → 跳到步驟 8b。
4. **判斷有沒有新回覆**：看留言區塊最上面（最新）那一則，若含簽名標記
   `— By Rick (jira-grill)` → 還沒有新回覆 → 直接結束（no-op，這是最
   常見的情況，輸出盡量精簡以控制成本）。否則有新回覆，繼續步驟 5。
5. **中止訊號 2（人類文字喊停）**：若這則新回覆明確表達停止意圖（例如
   「先這樣」「夠了」「不用再問了」「停止」「stop」「that's enough」
   「no more questions」等同義表達，靠語意判斷、不是精確關鍵字比對）→
   跳到步驟 8b（人類中止，非自然收斂）。否則繼續步驟 6。
6. **repo 是否已知**：`$ARGUMENTS` 有帶 `repo=<owner/repo>` 就已知；沒有
   就檢查這則新回覆有沒有回答「哪個 repo」這一題：
   - 有回答 → 依「Repo 解析與準備」的準備步驟 clone/fetch 該 repo；讀
     `~/.openab/cronjob.toml`，把 `id = "jira-grill-<TICKET_ID>"` 這筆
     的 `message` 改成帶 `repo=<owner/repo>`（其他 job、其他欄位都不動）
     寫回，之後每輪就不用再解析。
   - 沒有回答 → repo 仍未定，這一題留在下一步的 frontier 重算裡繼續問。
   - `$ARGUMENTS` 已帶 `repo=` → 直接 `git fetch`/`pull` 該 repo 保持
     最新。
7. 依 grilling 方法論，用完整留言串（含新回覆、含 repo 裡查到的事實）
   重新計算 design tree：
   - 還有未決分支（可能包含還沒回答的「哪個 repo」）→ 產出下一輪
     frontier 問題，貼成新 comment（格式見上文），結尾附「目前還有 N
     個分支未決」的進度摘要 → 結束（label、cron job 都不動）。
   - Frontier 已清空（雙方對需求達成共識）→ 跳到步驟 8a。
8. **收斂/中止收尾**（8a 自然收斂 / 8b 人類中止，兩者都要做完下面全部）：
   a. 自然收斂：貼一則「✅ 需求共識」comment，把整輪問答蒸餾成結構化的
      最終需求描述（背景、確認的需求範圍、驗收條件、目標 repo），附簽名。
      人類中止：貼一則「🛑 已中止 grill-me（人類要求停止）」comment，
      簡述目前已釐清到哪裡、還有哪些分支未決，附簽名。
      兩者都在文末加一行 plain-text 提及
      `@{reporter 的 displayName} @{assignee 的 displayName}`（純文字，
      不是真正會觸發通知的 Jira `[~accountId]` mention——見「已知限制」）。
   b. 把 label 從 `grill-me-active` 換成 `grill-me-done`。
   c. 讀 `~/.openab/cronjob.toml`，移除 `id = "jira-grill-<TICKET_ID>"`
      這個 `[[jobs]]` 區塊（保留其他 job），寫回檔案——這張票不再需要
      輪詢。

## 已知限制

- **repo 解析只涵蓋現有慣例**：104corp 任務靠 `104cac-product-registry`
  的登錄表（以 project key 比對 `jira.project`）；wm4n 個人任務沒有登錄
  表可查，公司任務查不到對應項目、或一個產品對到多個 repo/平台時也一
  樣——一律把「哪個 repo」併入 frontier 問人類，這是設計上的正常路徑，
  不是失敗。
- **收斂/中止通知不是真正的 Jira @mention**：只是純文字寫 reporter/
  assignee 的 displayName，不是會觸發 Jira 通知的 `[~accountId]` 語法。
  實務上 Jira 預設會對「有新留言」通知 reporter/assignee/watcher，這則
  純文字提及只是方便人類在畫面上找到自己，不是通知機制本身。
- **中止/收斂路徑沒有回頭鍵，但這是可接受的**：把 label 改回 `grill-me`
  會被下次 discovery 當成全新票重新處理——這是設計上允許的行為，不是
  bug。
- **成本隨並行票數線性增加**：每張正在 grill 的票每 10 分鐘觸發一次
  agent 推理（多數是「沒有新留言→no-op」的低成本輸出），票數一多會累積
  明顯的 Claude 用量；已知 repo 的票每輪還多一次 `git fetch`，成本略高
  於純文字問答。
- **`--comments 50` 是硬上限**：單張票的往返超過 50 則留言會讓最早的
  歷史看不到；純粹靠 Jira 留言串本身作為真相來源，理論上仍可能因為超過
  這個上限而遺漏極早期的脈絡，但一輪 grilling 通常遠低於 50 則留言，
  接受此限制。
- **JQL/label 慣例依賴 Jira 實例設定**：若組織的 label 使用慣例、Jira
  帳號權限範圍與本設計假設不同，discovery 的 JQL 需要對應調整。
- **新專案要開放要改部署設定，不是 skill 自己能決定**：`JIRA_GRILL_PROJECTS`
  是白名單，故意不掃帳號能存取的其他專案，避免跨專案的 `grill-me` label
  誤觸發；要新增專案得改 Rick 的部署環境變數，不是這個 skill 的職責範圍。
