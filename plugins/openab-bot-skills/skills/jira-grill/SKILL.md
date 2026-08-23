---
name: jira-grill
argument-hint: "discover | ticket <JIRA-ticket-id>"
description: >-
  Rick 專屬、獨立於三 bot 接力 pipeline 之外的 Jira 需求審視能力。Jira 票貼上
  grill-me label 後，套用 mattpocock-skills:grilling 的 design-tree/frontier
  方法論對需求連續提問；提問與回答都透過 Jira comment 進行。靠 openab 的
  usercron（同一個 cron job 重複觸發永遠落在同一個 Discord thread、延續同一個
  ACP session）讓每張票的問答自成一條可長期接續的對話。收斂或人類喊停後貼出
  結論、通知人類，不自動進入開發、不自動交棒給任何 bot。
---

# Jira Grill

Jira 是唯一真相來源：每次執行都重新從 Jira 撈完整內容與留言判斷目前進度，
不依賴 session 記憶本身的正確性。Session 延續只是效率紅利。

## 兩種觸發模式（`$ARGUMENTS`）

- `discover`：由固定的 discovery cron job 呼叫，找出新貼 `grill-me` label
  的票並啟動它們。
- `ticket <TICKET_ID>`：由該票專屬的 cron job 呼叫，檢查這張票是否有新回覆
  並推進下一輪。

## 環境變數

- `JIRA_TOKEN` / `JIRA_EMAIL` / `JIRA_BASE_URL`：同 `jira-fetch` skill。
- `JIRA_GRILL_CHANNEL`：discovery job 建立 per-ticket cron job 時要用的
  Discord channel ID（Rick 既有頻道）。

執行前用與 `jira-fetch` 相同的方式確認三個 Jira 變數存在（`${VAR:+set}`
寫法，不要用 skill frontmatter 的 load-time inline shell 檢查，會被權限層
擋下）：

```bash
echo "JIRA_TOKEN: ${JIRA_TOKEN:+set}"
echo "JIRA_EMAIL: ${JIRA_EMAIL:+set}"
echo "JIRA_BASE_URL: ${JIRA_BASE_URL:+set}"
echo "JIRA_GRILL_CHANNEL: ${JIRA_GRILL_CHANNEL:+set}"
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
# COMMENT_BODY 是要貼的完整文字（含結尾簽名，見下方「Grilling 提問格式」）
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
JQL='labels = "grill-me" AND labels != "grill-me-active"'
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

1. 確認環境變數（含 `JIRA_GRILL_CHANNEL`）。
2. 執行上面的 JQL 搜尋，取得所有符合的 `TICKET_ID` 清單。清單為空就結束。
3. 對每個 `TICKET_ID` 依序：
   a. 呼叫 `jira-fetch ${TICKET_ID} --comments 50` 取得標題/描述/驗收條件/
      現有留言。
   b. 把 label 從 `grill-me` 換成 `grill-me-active`（改 label 失敗 → 跳過
      這張票，印出錯誤，繼續下一張，不建立 cron job，留給下次 discovery
      重試）。
   c. 用 grilling 方法論，以描述+驗收條件為輸入，產出第一輪 frontier
      問題（見下方「Grilling 提問格式」），貼成第一則 comment。
   d. 用 `openab-schedule` skill 的 `[[jobs]]` TOML 語法（**不要**套用它
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
      讀取既有檔案內容、保留其他 job，只新增這一筆（絕不覆蓋整個檔案）。
4. 全部處理完，不需要額外摘要輸出（discovery thread 本身沒有人在看）。

## 流程二：Per-ticket（`$ARGUMENTS = ticket <TICKET_ID>`）

1. 確認環境變數。
2. 呼叫 `jira-fetch ${TICKET_ID} --comments 50`，取得完整內容（含
   labels、全部留言，留言依 `jira-fetch` 慣例新到舊排序）。
3. **中止訊號 1（label 被人類改掉）**：若回傳的 labels 不含
   `grill-me-active`，視為人類已手動中止 → 跳到步驟 6b。
4. **判斷有沒有新回覆**：看留言區塊最上面（最新）那一則，若內容包含
   Rick 自己的簽名標記 `— By Rick (jira-grill)` → 目前最新一則是 Rick
   自己貼的，代表還沒有新回覆 → 直接結束（no-op，不做任何 Jira 呼叫以外
   的動作，這是最常見的情況，要盡量精簡輸出以控制成本）。若最新一則不含
   這個標記 → 有新回覆，繼續步驟 5。
5. **中止訊號 2（人類文字喊停）**：若步驟 4 判定的新回覆內容明確表達停止
   意圖（例如「先這樣」「夠了」「不用再問了」「停止」「stop」「that's
   enough」「no more questions」等同義表達，靠語意判斷、不是精確關鍵字
   比對）→ 跳到步驟 6b（人類中止，非自然收斂）。否則視為對上一輪 frontier
   的回答，依 grilling 方法論用完整留言串重新計算 design tree：
   - 還有未決分支 → 產出下一輪 frontier 問題，貼成新 comment（格式見下），
     結尾附「目前還有 N 個分支未決」的進度摘要 → 結束（label、cron job
     都不動）。
   - Frontier 已清空（雙方對需求達成共識）→ 跳到步驟 6a。
6. **收斂/中止收尾**（6a 自然收斂 / 6b 人類中止，兩者都要做完下面全部）：
   a. 自然收斂：貼一則「✅ 需求共識」comment，把整輪問答蒸餾成結構化的
      最終需求描述（背景、確認的需求範圍、驗收條件），附簽名。
      人類中止：貼一則「🛑 已中止 grill-me（人類要求停止）」comment，
      簡述目前已釐清到哪裡、還有哪些分支未決，附簽名。
      兩者都在文末加一行 plain-text 提及
      `@{reporter 的 displayName} @{assignee 的 displayName}`（純文字，
      不是真正會觸發通知的 Jira `[~accountId]` mention——見「已知限制」）。
   b. 把 label 從 `grill-me-active` 換成 `grill-me-done`。
   c. 讀 `~/.openab/cronjob.toml`，移除 `id = "jira-grill-<TICKET_ID>"`
      這個 `[[jobs]]` 區塊（保留其他 job），寫回檔案——這張票不再需要
      輪詢。

## Grilling 提問格式

沿用 `mattpocock-skills:grilling` 的格式，每一輪的所有 frontier 問題合併
成同一則 comment：

```
❓ **Q1** - **<問題標題>**：<問題內容，可多段、可列選項>

➡️ <你的建議答案>

❓ **Q2** - **<問題標題>**：<問題內容>

➡️ <你的建議答案>

---
目前還有 {N} 個分支未決。

— By Rick (jira-grill)
```

第一輪（`grill-me` 剛被偵測到、還沒有任何人類回覆）以 Jira 票本身的標題、
描述、驗收條件為輸入直接產出 frontier；不要等留言。

**簽名規則**：本 skill 貼的每一則 comment（提問、收斂、中止）結尾都必須是
`— By Rick (jira-grill)`（注意：不是 persona 檔裡其他情境用的
`— By Rick`，多了 `(jira-grill)` 是本 skill 判斷「新回覆 vs 自己的舊留言」
的機器可辨識依據，改了會讓 no-op 判斷失效，造成同一輪問題重複問或漏判新
回覆）。

## 已知限制

- **收斂/中止通知不是真正的 Jira @mention**：只是純文字寫 reporter/
  assignee 的 displayName，不是會觸發 Jira 通知的 `[~accountId]` 語法。
  實務上 Jira 預設會對「有新留言」通知 reporter/assignee/watcher，這則
  純文字提及只是方便人類在畫面上找到自己，不是通知機制本身。
- **中止訊號辨識靠語意判斷**，不是精確關鍵字比對，極端措辭可能誤判——但
  收斂/中止都會留下明確的 comment 記錄，人類事後可查、可用 label 手動
  介入（把 label 改回 `grill-me` 會被下次 discovery 當成全新票重新處理，
  這是可接受的行為，不是 bug）。
- **成本隨並行票數線性增加**：每張正在 grill 的票每 10 分鐘觸發一次
  agent 推理（多數是「沒有新留言→no-op」的低成本輸出），票數一多會累積
  明顯的 Claude 用量。
- **`--comments 50` 是硬上限**：單張票的往返超過 50 則留言會讓最早的
  歷史看不到；純粹靠 Jira 留言串本身作為真相來源，理論上仍可能因為超過
  這個上限而遺漏極早期的脈絡，但一輪 grilling 通常遠低於 50 則留言，
  接受此限制。
- **JQL/label 慣例依賴 Jira 實例設定**：若組織的 label 使用慣例、Jira
  帳號權限範圍與本設計假設不同，discovery 的 JQL 需要對應調整。
