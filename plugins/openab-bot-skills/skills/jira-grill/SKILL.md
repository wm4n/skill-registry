---
name: jira-grill
argument-hint: "ticket <JIRA-ticket-id>"
description: >-
  Jira grill-me 需求審視。由獨立部署的 jira-grill-poller（K8s CronJob，
  不含 LLM）偵測到新票或人類新回覆後，用專用的 jira-grill-trigger bot
  @mention 觸發（不是人類 @mention、不在一般 Discord 對話）：先解析並準備
  好對應的 GitHub repo，再在 Jira comment 上用 grilling 式連續追問（design
  tree/frontier，見 mattpocock-skills:grilling），收斂或人類喊停後只貼
  結論通知人類，不自動開發、不交棒。獨立於三 bot 接力 pipeline。
---

# Jira Grill

Jira 是唯一真相來源：每次執行都重新從 Jira 撈完整內容與留言判斷目前進度，
不依賴 session 記憶本身的正確性。

## 觸發方式（`$ARGUMENTS`）

`ticket <TICKET_ID>`：由獨立部署的 `jira-grill-poller`（deterministic
K8s CronJob，見 `deployment-guides/k3s/jira-grill-poller/`）判斷這張票
需要處理後，用 `jira-grill-trigger` bot 貼出這個指令觸發。poller 已經
確認過這是真的新票或真的有新回覆，這裡不用再自己判斷要不要處理——只有
一個輕量防護例外，見下方流程步驟 3「重複觸發防護」。

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

**每一輪都重新走一次這個優先序**（不快取解析結果）：解析成本本身很低，
重算比維護快取簡單——沒有 per-ticket cron job 的 message 可以拿來存
`repo=` 這種狀態了。

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
（不是 persona 其他情境用的 `— By Rick`）。`jira-grill-poller` 跟下方
流程步驟 3 都靠這串文字判斷「留言區塊最上面那則是不是自己剛貼的」。改了
格式，兩邊的判斷都會失效，導致同一輪問題重複問或漏判新回覆。

## 環境變數

- `JIRA_TOKEN` / `JIRA_EMAIL` / `JIRA_BASE_URL`：同 `jira-fetch` skill。

執行前用與 `jira-fetch` 相同的方式確認三個變數存在（`${VAR:+set}`
寫法，不要用 skill frontmatter 的 load-time inline shell 檢查，會被權限層
擋下）：

```bash
echo "JIRA_TOKEN: ${JIRA_TOKEN:+set}"
echo "JIRA_EMAIL: ${JIRA_EMAIL:+set}"
echo "JIRA_BASE_URL: ${JIRA_BASE_URL:+set}"
```

任一缺少：說明缺什麼變數並停止，不繼續嘗試。

## Jira API 慣例

沿用 `jira-fetch` 的寫法：`curl -u "${JIRA_EMAIL}:${JIRA_TOKEN}"` 做 Basic
Auth，一律用 `node -e` 解析/組 JSON，不假設 `jq`／`python3`／GNU-only
coreutils 存在。讀票內容與留言一律呼叫 `jira-fetch` skill（`jira-fetch
<TICKET_ID> --comments 50`），不要自己重寫一份讀取邏輯。

以下兩個動作是 `jira-fetch` 沒有的，本 skill 自己實作：

### 改 label

```bash
# 範例：把 grill-me-active 換成 grill-me-done（防禦性補做 grill-me →
# grill-me-active 的認領時，remove/add 的值換掉即可）
STATUS=$(curl -s -o /dev/null -w '%{http_code}' -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -X PUT "${JIRA_BASE_URL}/rest/api/2/issue/${TICKET_ID}" \
  -H "Content-Type: application/json" \
  -d '{"update":{"labels":[{"remove":"grill-me-active"},{"add":"grill-me-done"}]}}')
if [ "$STATUS" != "204" ]; then
  echo "ERROR: 改 label 失敗（HTTP ${STATUS}）。"
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

## 流程（`$ARGUMENTS = ticket <TICKET_ID>`）

1. 確認環境變數。
2. 呼叫 `jira-fetch ${TICKET_ID} --comments 50`，取得完整內容（含
   labels、全部留言，留言依 `jira-fetch` 慣例新到舊排序）。
3. **重複觸發防護**：看留言區塊最上面（最新）那一則，若含簽名標記
   `— By Rick (jira-grill)` → 代表這次觸發是 race 造成的重複觸發
   （`jira-grill-poller` 偵測到變更、但上一輪 turn 尚未完成前又被觸發
   一次）→ no-op 結束，輸出盡量精簡以控制成本。否則繼續步驟 4。
4. **防禦性 label 檢查**：
   - 不含 `grill-me-active` 也不含 `grill-me`（已收斂/已中止/人類手動
     改過）→ 理論上不該被觸發（poller 的 JQL 只抓這兩種 label），印出
     警告並結束。
   - 只含 `grill-me`（poller 的認領 PUT 失敗了）→ 補做 label 轉換
     （`grill-me` → `grill-me-active`），當首輪繼續處理。
   - 含 `grill-me-active` → 繼續步驟 5。
5. **判斷首輪／續輪**：整串留言裡有沒有任何一則帶 Rick 簽名的留言：
   - 沒有 → **首輪**：依「Repo 解析與準備」決定並準備目標 repo（可能
     成功解析並 clone/fetch，也可能未定、留給第一輪 frontier 去問），
     以票的標題、描述、驗收條件與（若已知）repo 裡查到的程式碼事實
     為輸入，產出第一輪 frontier 問題（格式見上文「提問格式與簽名
     標記」；repo 未定時把「哪個 repo」併入這一輪一起問），貼成第一則
     comment。
   - 有 → **續輪**：
     a. **中止訊號 1（label 被人類改掉）**：若目前 labels 不含
        `grill-me-active`，視為人類已手動中止 → 跳到步驟 6b。
     b. **中止訊號 2（人類文字喊停）**：若最新那則非自己簽名的留言
        明確表達停止意圖（例如「先這樣」「夠了」「不用再問了」
        「停止」「stop」「that's enough」「no more questions」等同義
        表達，靠語意判斷、不是精確關鍵字比對）→ 跳到步驟 6b（人類
        中止，非自然收斂）。否則繼續。
     c. 依「Repo 解析與準備」重新走一次優先序，確認/更新目標 repo。
     d. 依 grilling 方法論，用完整留言串（含新回覆、含 repo 裡查到的
        事實）重新計算 design tree：
        - 還有未決分支（可能包含還沒回答的「哪個 repo」）→ 產出下一輪
          frontier 問題，貼成新 comment（格式見上文），結尾附「目前
          還有 N 個分支未決」的進度摘要 → 結束。
        - Frontier 已清空（雙方對需求達成共識）→ 跳到步驟 6a。
6. **收斂／中止收尾**（6a 自然收斂／6b 人類中止，兩者都要做完下面全部）：
   a. 自然收斂：貼一則「✅ 需求共識」comment，把整輪問答蒸餾成結構化的
      最終需求描述（背景、確認的需求範圍、驗收條件、目標 repo），附簽名。
      人類中止：貼一則「🛑 已中止 grill-me（人類要求停止）」comment，
      簡述目前已釐清到哪裡、還有哪些分支未決，附簽名。
      兩者都在文末加一行 plain-text 提及
      `@{reporter 的 displayName} @{assignee 的 displayName}`（純文字，
      不是真正會觸發通知的 Jira `[~accountId]` mention——見「已知限制」）。
   b. 把 label 從 `grill-me-active` 換成 `grill-me-done`。

## 已知限制

- **repo 解析只涵蓋現有慣例**：104corp 任務靠 `104cac-product-registry`
  的登錄表（以 project key 比對 `jira.project`）；wm4n 個人任務沒有登錄
  表可查，公司任務查不到對應項目、或一個產品對到多個 repo/平台時也一
  樣——一律把「哪個 repo」併入 frontier 問人類，這是設計上的正常路徑，
  不是失敗。
- **沒有獨立 Jira bot 身份**：Rick 用人類帳號回覆 Jira，判斷「這則留言
  是不是自己剛貼的」一律靠文字簽名標記，不是帳號身份——`jira-grill-poller`
  跟這裡的重複觸發防護都是靠這個機制，改了簽名格式兩邊都會失效。
- **重複觸發防護是機率性的**：`jira-grill-poller` 沒有分散式鎖，理論上
  仍存在極窄的競態窗口（poller 判斷完、Discord 訊息送出前，Rick 剛好
  完成上一輪並貼出新留言），但本 skill 步驟 3 的簽名檢查會在絕大多數
  情況下擋下重複處理。
- **收斂/中止通知不是真正的 Jira @mention**：只是純文字寫 reporter/
  assignee 的 displayName，不是會觸發 Jira 通知的 `[~accountId]` 語法。
  實務上 Jira 預設會對「有新留言」通知 reporter/assignee/watcher，這則
  純文字提及只是方便人類在畫面上找到自己，不是通知機制本身。
- **中止/收斂路徑沒有回頭鍵，但這是可接受的**：把 label 改回 `grill-me`
  會被下次 `jira-grill-poller` 的 Query 1 當成全新票重新處理——這是
  設計上允許的行為，不是 bug。
- **`--comments 50` 是硬上限**：單張票的往返超過 50 則留言會讓最早的
  歷史看不到；純粹靠 Jira 留言串本身作為真相來源，理論上仍可能因為超過
  這個上限而遺漏極早期的脈絡，但一輪 grilling 通常遠低於 50 則留言，
  接受此限制。
- **輪詢頻率、掃描的 project 範圍不是本 skill 能決定**：由
  `jira-grill-poller` 的 K8s CronJob 設定（`schedule`、
  `JIRA_GRILL_PROJECTS`）決定，見
  `deployment-guides/k3s/jira-grill-poller/`。
