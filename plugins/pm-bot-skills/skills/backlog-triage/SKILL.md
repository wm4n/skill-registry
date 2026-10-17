---
name: backlog-triage
argument-hint: "[<owner/repo>#<N>]"
description: >-
  排序 grill-me-done 待辦並自己放行 ready-for-agent、修復 agent-failed 規格
  後自己放行重做、列出 poller 已升級與等人類決定的單。由 usercron 平日觸發
  （訊息「執行 backlog-triage skill」，sender_name＝SummerTriage，時程以
  CRONJOB.md 為準），或人類在 Discord 提出同類請求（如「排一下優先序」
  「看看卡住的單」「這張能改回去了嗎」）時觸發。放行不等人類點頭，但每次
  放行前必查三道限制：落在 needs-human 五類就改貼 needs-human 並 @ 人類、
  重做次數（agent-failed 次數加驗收不通過次數）達 2 就改貼 needs-human、
  兩個 repo 的 agent-active 加 ready-for-agent 合計達 2（WIP 上限）就停止
  放行。label 一律先加 ready-for-agent 再移除 grill-me-done／agent-failed。
  排序、修規格、放行、升級都在 issue 留言（簽名 — By Summer），Discord 只
  放摘要。ready-for-human 歸 product-planning，帶 needs-human 的單一律不動。
---

# Backlog Triage

> **本 skill 接手 `product-planning` 開單之後的下一段，並且自己放行**：
> 那邊開（或收養）的單、以及人類自己開的單，走完 grill 流程後落在
> `grill-me-done`；Rick/Morty 判定規格有問題的單落在 `agent-failed`。
> 這兩種單由本 skill **自己貼 `ready-for-agent` 放行**，不等人類點頭。
>
> `ready-for-agent` 一貼上，`agent-dev-poller` 就會認領並觸發 Rick/Morty
> 真的開發、燒額度、開 PR，是整條鏈最難回收的一步。所以放行權附帶三道
> 限制，**每一次放行前都要逐一檢查，沒有任何路徑可以跳過**：
>
> 1. **`needs-human` 五類**：落在五類的單不放行，改貼 `needs-human` 找人。
> 2. **重做上限 `REWORK_MAX = 2`**：同一張單累計 `agent-failed` 加驗收不
>    通過達 2 次，不再自動放行，改貼 `needs-human`（第 5 類）。自動修規格、
>    自動放行、驗收送回三條路接起來就是一個會一直燒 Rick/Morty 額度的迴圈，
>    這個上限是那個迴圈的費用防線。
> 3. **WIP 上限 `WIP_MAX = 2`**：兩個 repo 的 open `agent-active` 加
>    `ready-for-agent` 合計達 2（Rick、Morty 各一張）就停止放行，剩下的留到
>    下一輪。同時開太多張會讓兩隻 bot 同時撞用量上限，每張都做不完。

## 觸發與參數

`$ARGUMENTS`：

- 空 → **掃全部**：對 `wm4n/chainbreak`、`wm4n/hangman` 兩個白名單 repo，
  依下面「執行順序」跑段 2、段 1、段 3。段 4 不在掃全部的範圍內。
- `<owner/repo>#<N>` → **只處理這一張**，依它目前掛的 label 決定：

  | 這張單目前的 label | 怎麼做 |
  | --- | --- |
  | 帶 `needs-human`（不論還有什麼 label） | 一律不動，回報「等人類決定中」 |
  | `agent-failed` | 跑段 2 的單張邏輯 |
  | `grill-me-done` | 跑段 1 的單張邏輯（不用排序，直接走放行前檢查） |
  | `ready-for-human` | 段 4：依 `product-planning` 的規則處理 |
  | `agent-active` | 不動，回報「開發中，由 poller 負責」 |
  | 以上都沒有 | 說明「這張不在本 skill 的範圍」並停止，不要臆測要跑哪段 |

### ⚠️ 先把參數拆開：`gh` 不吃 `owner/repo#N`

`gh issue` 各子指令只接受 `{<number> | <url>}`，直接把 `owner/repo#N` 丟
進去會得到 `invalid issue format`。指定單張 issue 時先拆成兩個變數：

```bash
ISSUE_REF="wm4n/chainbreak#42"   # 從 $ARGUMENTS 取得
REPO="${ISSUE_REF%#*}"           # → wm4n/chainbreak
NUM="${ISSUE_REF##*#}"           # → 42
```

掃全部時，下面所有指令裡的 `REPO`、`NUM` 也是這兩個變數，換成當下處理的
那張單。

## 執行順序與失敗隔離

掃全部時固定依序：**段 2 → 段 1 → 段 3**。

段 2 排在段 1 前面，是因為 WIP 名額由兩段共用，名額先給已經做到一半的單：
`agent-failed` 的單放行後，poller 會優先送回原本做過它的那隻 bot，branch 與
worktree 都還在它的容器裡，接著做比從頭開一張新單省。段 3 排在最後，是要
列出段 1、段 2 處理完之後還剩下的單。

**失敗只影響那一張**：任何一段裡對單一 issue 的操作失敗（讀不到留言、
`gh` 呼叫出錯），只記錄那張 issue 並跳過，繼續同一段其餘 issue，也不影響
其他段。唯一跨段共用的是 WIP 計數，它每次放行前都重新查（見「WIP」）。

## 什麼時候找人：`needs-human` 五類

**要不要找人，唯一標準是 persona `Summer-AGENTS_v2.md` 的 `needs-human`
清單**，本 skill 不自創判準。五類的短標題（定義與細節以 persona 為準，
兩邊不一致時以 persona 為準）：

1. 費用
2. 權限與秘密
3. 對外發布或不可逆
4. 產品方向翻轉
5. 自動重做達上限

本 skill 用第 1–4 類檢查**單子的內容**（需求共識、body、Rick/Morty 指出的
規格問題），用第 5 類檢查**重做次數**（見「重做次數」）。清單以外的事，
產品問題由 Summer 自己決定，不要為了保險而丟給人類——把本來可以自決的事
推給人，就是讓整條自主閉環重新卡在人身上。

### 貼 `needs-human` 的固定順序（順序不可換）

1. **加 `needs-human` label**（`gh issue edit "$NUM" --repo "$REPO"
   --add-label needs-human`）。**這一步失敗就停在這裡**：不發 @、不留言、
   什麼都不留下。因為什麼都沒貼，下一輪看到的還是原樣，自然會重試；若先貼
   了留言或 @ 再發現 label 加不上，人類會被叫來看一張實際上沒有任何標記的單。
2. **在 `bot-notify`（頻道 ID `1526283579309690990`）發一則 @ 人類
   `<@824092654060830770>` 的訊息並附 issue 連結**，每張單用一句話寫明
   「卡在第幾類、要決定什麼」，讓人類不點進去也知道輕重。**整輪只發這一則
   @**：同一輪有多張就合併成一則，不要逐張各 @ 一次（合併後仍須 ≤ 2000
   字，真的放不下就把超出的連結接在同一則的後續訊息，@ 只放第一則）。
   Summer 若不是在 `bot-notify` 執行（人類在別的頻道／討論串要求、或 usercron
   的回覆頻道），那個地方照常貼**不帶 @ 的**純文字摘要，@ 只留給
   `bot-notify` 這一則——同一件事讓人類被通知兩次，只會讓人學會忽略通知。
3. **在 issue 上留言**，第一行固定寫 `## 需要人類決定（needs-human）`：

```bash
gh issue comment "$NUM" --repo "$REPO" --body "$(cat <<'EOF'
## 需要人類決定（needs-human）

卡在清單第 <N> 類（<短標題>）：<一句話說明卡點>

需要人類決定：<要決定的事>

選項：
- <選項一>
- <選項二>

處理方式：在本 issue 回覆決定，並移除 needs-human label。

---
— By Summer
EOF
)"
```

第 5 類的留言要寫出重做次數怎麼算出來的（幾次 `agent-failed`、幾則驗收
不通過），並提醒人類：`agent-failed` 的單在移除 `needs-human` 之後，
人類的回覆本身就會讓 poller 叫原本那隻 bot 續作，不用另外改 label。

**原本的 `grill-me-done`／`agent-failed` label 留著，不要移除**：
`needs-human` 一貼上，各 poller 都會跳過這張單；保留原 label，人類處理完
移除 `needs-human` 之後，這張單才回得到原本的流程（`agent-failed` 由 poller
依人類回覆續作，`grill-me-done` 由本 skill 下一輪依人類的決定放行）。

label 放第一步，是因為 label 一貼上，各 poller 就立刻開始跳過這張單、停止
燒額度；通知放在留言之前，是因為「人類盡快知道」比「說明寫完整」更要緊。
**接受的風險**：若在 @ 之後、留言之前被中斷，人類已經被通知、`needs-human`
也已在身上（poller 都會跳過），只是 issue 上少了那則說明——人類點進去
看不到細節，但 @ 訊息裡已有一句話的概要，不會卡死，也不需要補做。

**絕不重新加回 `needs-human`**：issue 上已有 Summer 的升級留言、但沒有
`needs-human` label，代表人類處理完並移除了它，不是「做到一半」。怎麼接著
處理見「人類處理過的升級」。

**帶著 `needs-human` 的 issue，本 skill 一律不動**：不排序、不修規格、不放行、
不留言、不改 label，只在段 3 列進提醒清單。它在等人類，任何自動化介入都可能
蓋過人類的決定，或在等人時繼續燒額度。

## 共用規則

### label 預檢——每個 repo 動手之前先確認 label 存在

每一輪開始時，對兩個 repo 各跑一次：

```bash
gh label list --repo wm4n/chainbreak --limit 200 --json name --jq '.[].name'
gh label list --repo wm4n/hangman    --limit 200 --json name --jq '.[].name'
```

`--limit 200` 不能省：`gh label list` 預設只回 30 個，repo 的 label 多一點就會
把存在的 label 誤判成缺漏。要確認的是 `ready-for-agent`（放行用）與
`needs-human`（升級用）。

某個 repo 缺其中任一個，或 `gh label list` 本身報錯（網路、權限）→ **這一輪
在那個 repo 段 1、段 2 什麼都不做**：不排序留言、不修規格、不放行、不升級。
放行做到一半卻發現升級用的 label 不存在，會讓一張該找人的單被當成一般單
放行；不要憑印象當作 label 存在。段 3 只讀不寫，照常列出。

缺的 label 不要自己建（改 repo 設定屬於 `needs-human` 第 2 類），改成：
摘要寫明哪個 repo 缺哪個 label（或「label 查詢失敗」），並在 `bot-notify`
的那一則 @ 裡請人類建立（與同輪的 `needs-human` 升級合併，整輪仍只 @ 一次）。

### 留言怎麼比對：固定標題

本 skill 靠下面幾個固定標題辨認留言，一律用「留言內容的第一行，去掉前後
空白後，以這串**完全相同的字串**開頭」判斷，並且只認作者是 `wman-pm`
（Summer 的 GitHub 帳號）的留言。所以寫這幾種留言時第一行必須逐字照抄、
不可改字或加前綴：

| 第一行 | 誰寫 | 本 skill 拿來做什麼 |
| --- | --- | --- |
| `## 需要人類決定（needs-human）` | Summer 升級時 | 認出「這張單升級過」 |
| `## Summer 已修正規格` | 本 skill 段 2 | 認出「這次失敗的規格已經修過」，不重修 |
| `## 驗收結果：不通過` | `acceptance-review` | 算重做次數 |
| `## Summer 收養此單`、`依人類決定不收養` | `product-planning` | 段 4 依該 skill 的規則判斷 |

人類是 `wm4n`；bot 帳號是 `wman-dev`（Rick）、`wman-review`（Morty）、
`wman-pm`（Summer）。

本 skill 用到的留言與 timeline 一律現查，不憑印象：清單指令用
`--json ...,comments` 一次撈齊，單張補查用
`gh issue view "$NUM" --repo "$REPO" --json comments`。

### 重做次數

**重做次數 ＝ issue timeline 裡 `labeled agent-failed` 的次數 ＋ `wman-pm`
貼過、第一行以 `## 驗收結果：不通過` 開頭的留言數**。用 GitHub 上已有的紀錄
現算，不另存狀態：

**每張單都把下面整段放在同一次 Bash 呼叫裡跑，不要拆開，也不要沿用上一張
單的變數**：變數若是空的或殘留上一張的值，`.createdAt > ""` 會比對到這張單
所有的 Rick/Morty 留言，把「bot 從沒回應」誤判成「有規格問題說明」。開頭先把
變數全部清空就是為了這個。

```bash
# 開頭清空：不沿用上一張單（或上一次呼叫）留下的值
REWORK=FAILED; FAILED_N=; REJECT_N=; LAST_FAILED_AT=; LAST_ACTIVE_AT=; WORKER_COMMENT=NOT_CHECKED
# timeline 會分頁；--paginate 時 --jq 是逐頁各跑一次，所以每個事件輸出一行再數行數，
# 不能在 jq 裡用 length（會變成每頁一個數字）
if EVENTS=$(gh api "repos/$REPO/issues/$NUM/timeline" --paginate \
  --jq '.[] | select(.event == "labeled" and (.label.name == "agent-failed" or .label.name == "agent-active")) | "\(.created_at) \(.label.name)"'); then
  EVENTS=$(printf '%s\n' "$EVENTS" | sort)
  FAILED_N=$(printf '%s\n' "$EVENTS" | grep -c ' agent-failed$')
  LAST_FAILED_AT=$(printf '%s\n' "$EVENTS" | grep ' agent-failed$' | tail -n 1 | cut -d' ' -f1)
  LAST_ACTIVE_AT=$(printf '%s\n' "$EVENTS" | grep ' agent-active$' | tail -n 1 | cut -d' ' -f1)
  # 兩個查詢都成功才換成數字；任何一個失敗 REWORK 都維持 FAILED，不會被當成 0
  if REJECT_N=$(gh issue view "$NUM" --repo "$REPO" --json comments \
    --jq '[.comments[] | select(.author.login == "wman-pm" and (.body | split("\n")[0] | sub("^\\s+"; "") | sub("\\s+$"; "") | startswith("## 驗收結果：不通過")))] | length'); then
    REWORK=$((FAILED_N + REJECT_N))
  fi
  # 段 2 步驟 4 用：最後一次認領之後，Rick/Morty 的最後一則留言（gh 會把 null 印成空行）
  if [ -n "$LAST_ACTIVE_AT" ]; then
    WORKER_COMMENT=$(gh issue view "$NUM" --repo "$REPO" --json comments \
      --jq "[.comments[] | select((.author.login == \"wman-dev\" or .author.login == \"wman-review\") and .createdAt > \"$LAST_ACTIVE_AT\")] | last | .body") || WORKER_COMMENT=QUERY_FAILED
  fi
fi
echo "rework=$REWORK failed=$FAILED_N reject=$REJECT_N last_failed=$LAST_FAILED_AT last_active=$LAST_ACTIVE_AT"
echo "--- worker_comment ---"
printf '%s\n' "$WORKER_COMMENT"
```

- **重做次數 ≥ 2 → 走「貼 `needs-human` 的固定順序」，第 5 類**，不放行。
- **`rework=FAILED`（任何一個查詢失敗）就當作算不出來：這張本輪不放行、也
  不升級**，記進摘要，下一輪重算。少算一次就可能多放行一次，所以查詢失敗絕不
  能當成 0。

`last_failed`（最後一次貼 `agent-failed` 的時間，下文寫作 `LAST_FAILED_AT`）、
`last_active`（最後一次被 poller 認領的時間，`LAST_ACTIVE_AT`）與
`worker_comment` 段 2 也會用到，一律取**這張單這一次**執行印出的值。

### WIP

**WIP ＝ 兩個 repo 的 open issue 裡，帶 `agent-active` 或 `ready-for-agent`
的張數合計**；帶 `needs-human` 的不算（它在等人，不佔開發名額）。同一張同時
帶兩個 label 只算一次：

```bash
WIP=0
for R in wm4n/chainbreak wm4n/hangman; do
  if N=$(gh issue list --repo "$R" --state open --limit 200 --json number,labels \
    --jq '[.[] | select(any(.labels[]; .name == "agent-active" or .name == "ready-for-agent") and all(.labels[]; .name != "needs-human"))] | length'); then
    WIP=$((WIP + N))
  else
    WIP=FAILED; break
  fi
done
echo "WIP=$WIP"
```

`gh issue list --label a --label b` 是「同時帶兩個」，不是「帶其中一個」，所以
這裡撈全部 open issue 再用 jq 篩。

- **WIP ≥ 2 → 本輪停止放行**，剩下的單留到下一輪（修規格、升級不受影響）。
- **查詢失敗（`WIP=FAILED`）→ 當作已滿，本輪不放行**，摘要寫明。
- **每放行一張就重查一次**，不要用一開始算的數字一路扣：poller 隨時可能在
  兩次放行之間認領或完成別的單。

### 人類處理過的升級（有升級留言、沒有 `needs-human`）

issue 上有 `wman-pm` 第一行為 `## 需要人類決定（needs-human）` 的留言、但目前
沒有 `needs-human` label → 人類已處理並移除了 label。**絕不重新加回**。先判斷
那次升級和現在是不是**同一件事**：

- **最後一則升級留言之後，沒有新的重做事件**（沒有更晚的 `labeled
  agent-failed`，也沒有更晚的 `## 驗收結果：不通過` 留言）→ 同一件事，人類已
  經處理過。**升級時那一類視為已解決，不得為同一件事重新升級**。
  - 段 1：只有在升級留言之後有 `wm4n` 的留言、且**明確表示可以做**（例如
    「可以做」「放行」「照選項一」）時，才繼續走放行前檢查並放行；五類檢查
    只看**新出現的、不同的卡點**（不同類，或同類但不同的具體事項），重做次數
    若就是當初升級的原因也視為已解決。沒有 `wm4n` 留言、或留言沒有明確說
    可以做（含明確說不做）→ 跳過、不動，摘要列一行「人類已處理但未明確放行」。
    人類只是拿掉 label 但沒說決定，不能替他腦補。
  - 段 2：跳過、不動。人類的回覆會由 poller 處理（見段 2）；沒有回覆就不猜。
- **最後一則升級留言之後，又出現新的重做事件** → 那是新的失敗、新的一件事，
  照一般流程完整檢查；重做次數 ≥ 2 照樣再走一次升級順序。這不是「加回」人類
  移除的 label，而是為新的事件升級，上限才不會被一次人類決定永久解除。

### 放行程序（段 1、段 2 共用）

`SRC` 是這張單原本的流程 label：段 1 是 `grill-me-done`，段 2 是
`agent-failed`。順序固定，任何一步失敗都停在那一步、記進摘要，不往下做。

**1. 放行前最後確認**（label 可能在你讀清單之後被 poller 或人類改過）：

```bash
gh issue view "$NUM" --repo "$REPO" --json state,labels,comments
```

必須同時成立：`state` 是 `OPEN`；帶著 `SRC`；**沒有** `needs-human`、
`ready-for-agent`、`agent-active`、`agent-done`。段 2 另外要確認這時最後一則
留言仍不是「晚於 `LAST_FAILED_AT` 的 `wm4n` 留言」（見段 2 步驟 2）。任一不
成立就不放行。

**2. 重查 WIP**（見「WIP」）。≥ 2 或查詢失敗 → 不放行，並結束本輪所有放行。

**3. 先加 `ready-for-agent`**：

```bash
gh issue edit "$NUM" --repo "$REPO" --add-label ready-for-agent
```

**4. 確認加上了**，才移除舊 label：

```bash
gh issue view "$NUM" --repo "$REPO" --json labels --jq '[.labels[].name]'
```

看到 `ready-for-agent` **或** `agent-active` 其中一個就算成功——poller 可能在
步驟 3 與步驟 4 之間就已經認領，把 `ready-for-agent` 換成了 `agent-active`。
兩個都沒看到 → 加 label 失敗，不移除 `SRC`，記進摘要。

**5. 移除舊 label**：

```bash
gh issue edit "$NUM" --repo "$REPO" --remove-label "$SRC"
```

先加後移除：順序反了、中間又失敗，這張單兩個 label 都沒有，**從此沒有任何
poller 撿得到它**，也不會有任何錯誤訊息。步驟 4 已經成功時一定要做步驟 5：
`agent-active` 與 `agent-failed` 同時在身上，poller 會當成「轉成
`agent-failed` 做到一半」而把 `agent-active` 拿掉，bot 明明在開發，單子卻
退回 `agent-failed`。

步驟 5 失敗時，依 `SRC` 分兩種：

- **`SRC`＝`grill-me-done`**：不重試，記進摘要；下一輪段 1 會補做（見段 1
  的「放行做到一半」）。`grill-me-done` 殘留不影響 poller 認領與開發。
- **`SRC`＝`agent-failed`**：**不能等下一輪**——poller 每 10 分鐘就會認領帶
  `ready-for-agent` 的單，本 skill 下一輪卻是下一個平日，等到那時單子幾乎一定
  已經變成 `agent-active`＋`agent-failed`。所以當場處理：
  1. 立刻再跑一次移除 `agent-failed`。成功就照常做步驟 6。
  2. 仍失敗 → 用 `gh issue view "$NUM" --repo "$REPO" --json labels` 看現況：
     - 還帶 `ready-for-agent`（poller 還沒認領）→ **回滾**：移除
       `ready-for-agent`，單子回到放行前的 `agent-failed`，不留放行留言，記進
       摘要。下一輪段 2 會從步驟 5 接著做、重新放行。
     - 已經變成 `agent-active`（poller 已認領）→ 不要再動 label，記進摘要並在
       `bot-notify` 的那一則 @ 裡請人類手動移除 `agent-failed`（併入整輪唯一
       的 @）。
     - 回滾也失敗 → 記進摘要並併入那一則 @。

**6. 最後在 issue 留言記錄放行**（label 都換好才留言，紀錄才不會寫到沒發生
的事）：

```bash
gh issue comment "$NUM" --repo "$REPO" --body "$(cat <<'EOF'
## Summer 放行開發

已貼上 ready-for-agent、移除 <grill-me-done 或 agent-failed>。

來源：<段 1：本輪排序第 N 順位／段 2：修正規格後放行重做，修正內容見「## Summer 已修正規格」留言>

放行前檢查：
- needs-human 五類：不落在任何一類（<一句話理由>）
- 重做次數：<K>（agent-failed <a> 次＋驗收不通過 <b> 次），上限 2
- WIP：放行前 <W>，上限 2

---
— By Summer
EOF
)"
```

留言失敗不回滾 label（放行已經發生），記進摘要。

## 段 1：`grill-me-done` → 排優先序、依序放行

```bash
gh issue list --repo wm4n/chainbreak --label grill-me-done --state open \
  --json number,title,body,labels,author,comments
gh issue list --repo wm4n/hangman    --label grill-me-done --state open \
  --json number,title,body,labels,author,comments
```

`--json` 一定要撈 `body`：`product-planning` 開單時把數據依據寫在 issue
**body**（見該 skill「5a. 新開 issue」），`jira-grill` 貼的「✅ 需求共識」
comment 只含背景、需求範圍、驗收條件、目標 repo，**不含數據依據**——只看
`comments` 找不到最初的數據佐證，排序時就沒有原始依據可引。

**先過濾**，下列單不進排序：

- 帶 `needs-human` → 不動（段 3 列進提醒）。
- **放行做到一半**：同時帶 `ready-for-agent` 或 `agent-active` → 上一輪放行時
  移除 `grill-me-done` 失敗。只補做 `gh issue edit "$NUM" --repo "$REPO"
  --remove-label grill-me-done`，不重留言、不佔 WIP、不重新檢查。
- 有升級留言、沒有 `needs-human` → 照「人類處理過的升級」判斷；判斷為跳過的
  （人類沒有明確說可以做）不進排序，摘要列一行。不然它每個平日都會收到一則
  「第 N 順位」的排序留言，看起來像 Summer 在推一張人類沒放行的單。
- 在 `comments` 裡找不到 `jira-grill` 貼的「✅ 需求共識」comment → **視為
  異常**，跳過、記錄，不要改看 issue 標題／描述自己臆測需求範圍，那不是共識
  的內容。

**排序**：

1. **有設定 GA4 的 property，本輪都重新跑一次 GA4 report**（preset
   `overview`，用法同 `product-planning` 的「3d. GA4」，property 對應這張
   issue 所屬的 repo）——不要嘗試判斷「這次要不要重跑」，固定重跑：排序理由
   要有「這一輪」的數據佐證。先用存在性檢查判斷有沒有設定（只輸出 `set` 或
   空白，不會印出值）：

   ```bash
   echo "${GA4_PROPERTY_CHAINBREAK:+set}"
   echo "${GA4_PROPERTY_HANGMAN:+set}"
   ```

   空白 → 該 property 沒有 GA4，不是錯誤，理由裡的數據部分寫「無 GA4 數據
   （未設定）」，改引用驗收條件與 body 的依據。
2. 彙整本輪掃到的所有 `grill-me-done` issue（兩個 repo 合在一起），依產品
   價值與數據排出順序。

**排序要附得出理由**：理由必須指得出是哪個 GA4 訊號或哪一點驗收條件的價值
更高，不能只寫「感覺比較急」這種無法覆核的說法。**查不到佐證就明說查不到，
不准用推測冒充數據依據**——GA4 查詢失敗，或這張 issue 的 body 本來就沒留下
數據依據，理由就寫「這部分無法查證」。

**排序結果要留在 GitHub**：對本輪排序的每一張 issue，各貼一則：

```bash
gh issue comment "$NUM" --repo "$REPO" --body "$(cat <<'EOF'
## 排序結果

本輪順序：第 <N> 順位（同批 grill-me-done 共 <M> 張）

理由：<具體 GA4 訊號，或引用的驗收條件／body 數據依據；查無佐證則寫「這部分無法查證」>

---
— By Summer
EOF
)"
```

**依序放行**：照排序由第 1 順位往下，對每一張依序做：

1. **WIP ≥ 2（或查詢失敗）→ 結束段 1 的放行**，這張與後面的單留到下一輪
   （排序留言已經貼了，不用再補）。
2. **五類檢查（第 1–4 類）**：讀需求共識與 body，這張單要做的事落在第 1–4
   類 → 走「貼 `needs-human` 的固定順序」，不放行，換下一張。過濾時判定為
   「人類明確說可以做」的單，只看新出現的、不同的卡點（見「人類處理過的升級」）。
3. **重做次數**（對這張單跑一次「重做次數」那整段）：≥ 2 → 升級第 5 類，不放行，
   換下一張（人類明確放行、而且升級之後沒有新重做事件的單除外，見「人類處理過
   的升級」）；`FAILED` → 跳過，換下一張。`grill-me-done` 的單也可能有過失敗
   紀錄（例如人類把失敗的單送回重新 grill），所以這一步不能省。
4. 都通過 → 走「放行程序」（`SRC`＝`grill-me-done`）。

升級的單不佔 WIP，升級完繼續看下一張。

## 段 2：`agent-failed` → 修規格、算重做次數、放行重做

```bash
gh issue list --repo wm4n/chainbreak --label agent-failed --state open \
  --json number,title,body,labels,author,comments
gh issue list --repo wm4n/hangman    --label agent-failed --state open \
  --json number,title,body,labels,author,comments
```

兩個 repo 合在一起，依 issue 編號由小到大逐張處理（固定順序，WIP 不夠時每次
先輪到的是同一批單）。對每一張依序做：

**1. 先看 label**：

- 帶 `needs-human` → 不動。
- 同時帶 `ready-for-agent` → **放行做到一半**（上一輪移除 `agent-failed` 失敗）。
  只補做 `gh issue edit "$NUM" --repo "$REPO" --remove-label agent-failed`，
  不重留言、不佔 WIP、不重新檢查。
- 同時帶 `agent-active` → 不動，交給 poller（poller 有自己的補做規則）。

**2. 人類已經回覆了就交給 poller**：先對這張單跑一次「重做次數」那整段
（同一次 Bash 呼叫），取得 `last_failed`、`last_active`、`worker_comment`
與重做次數，步驟 4、7 都用這次的結果（timeline 查詢失敗、`last_failed` 是
空的就跳過這張）。**最後一則留言的作者是 `wm4n`，
且時間晚於 `LAST_FAILED_AT`** → 跳過、不動。poller 看到人類在失敗之後回覆，
會自己把單子叫回原本那隻 bot 續作；Summer 這時再修規格、放行，兩條路會搶
同一張單。Summer 自己的留言（`wman-pm`）不會觸發 poller，所以 Summer 修完
規格之後要自己放行（下面步驟 7）。

**3. 有升級留言、沒有 `needs-human`** → 照「人類處理過的升級」判斷；它說
跳過就跳過。

**4. 找 Rick/Morty 的規格問題說明**：看步驟 2 那次執行印出的
`--- worker_comment ---` 底下的內容（最後一次被認領之後，作者是 `wman-dev`
或 `wman-review` 的最後一則留言）：

- **有內容** → 這是 persona `Rick-CLAUDE_v2.md`／`Morty-CLAUDE_v2.md` §4b 的
  規格問題說明（判定規格有問題時，留言說明、label 改 `agent-failed`、停手），
  繼續下一步。
- **空白** → 這不是規格問題：poller 叫了 bot 卻一直沒有下文，自己把單子轉成
  `agent-failed`，而且已經 @ 過人類。**不修、不放行**，段 3 會把它列出來。
  （它仍然算一次重做。）
- **`NOT_CHECKED`（`last_active` 是空的，timeline 找不到認領紀錄）或
  `QUERY_FAILED`** → 判斷不了是不是規格問題，**不修、不放行**，段 3 會把它
  列出來。不要退回去看「全部的 Rick/Morty 留言」：那會撈到 grill 階段的
  需求共識之類的舊留言，被誤當成規格問題說明。

**5. 這次失敗的規格修過了嗎？** `LAST_FAILED_AT` 之後已有 `wman-pm` 第一行為
`## Summer 已修正規格` 的留言 → 已經修過（多半是上一輪 WIP 滿了沒放行），
**不重修**，直接跳到步驟 7。

**6. 先過五類，再修規格**：

- Rick/Morty 指出的卡點、或補齊規格需要做的決定，落在第 1–4 類（例如需要
  新的 PAT scope、要接付費 API）→ 走「貼 `needs-human` 的固定順序」，**不修
  規格、不放行**——那是要人類做的決定，Summer 不能用改寫規格把它繞過去。
  這張到此為止。
- 不落在五類 → 修規格。只補齊／修正 Rick/Morty 指出的那個缺口（漏了驗收
  條件、範圍描述不清、跟現有功能衝突……），不整段砍掉重寫——除非讀完說明後
  發現整體方向就錯，才需要大改。
  - **issue 作者是 `wman-pm`**（Summer 自己開的單）→ 改 body：

    ```bash
    gh issue edit "$NUM" --repo "$REPO" --body "$UPDATED_BODY"
    ```

  - **作者不是 `wman-pm`**（人類開、Summer 收養的單）→ **不改 body**，把修正
    後的完整段落寫進下面那則留言。人類寫的 body 不由 bot 覆寫，與
    `product-planning` 收養時「不改人類開的 issue 的 body」同一條規則。

  修完立刻貼一則記錄變更的留言（第一行逐字照抄，步驟 5 靠它判斷修過了沒）：

```bash
gh issue comment "$NUM" --repo "$REPO" --body "$(cat <<'EOF'
## Summer 已修正規格

依 Rick/Morty 的規格問題（<留言連結>）調整規格。

變更摘要：<改了哪個段落，新增／刪除了什麼內容>

<作者不是 wman-pm 時：修正後的完整段落，取代 body 中的對應段落>

---
— By Summer
EOF
)"
```

`gh issue edit --body` 是整段覆蓋，不留紀錄的話事後沒有人分得出「這是誰、
什麼時候、為什麼改的」。變更摘要要點名**改了哪個段落、新增或刪除了什麼
內容**，不能只寫「已更新」。

**7. 看重做次數**（用步驟 2 那次執行印出的 `rework`）：

- ≥ 2 → 升級第 5 類，不放行。
- `FAILED` → 跳過，下一輪重算。
- < 2 → 走「放行程序」（`SRC`＝`agent-failed`）。WIP 已滿就留著，下一輪從
  步驟 5 接著做。poller 重新認領時會優先送回之前做過這張的 bot，這裡不用處理。

## 段 3：列出 poller 已升級與等人類決定的單

卡單偵測由 poller 確定性處理（認領後 bot 沒有下文，poller 會重送、@ 人類、
轉成 `agent-failed`），而且 poller **不在 issue 上留言**。這段只依 label
現況與留言列清單，**不自己判斷「卡太久」**，也不嘗試恢復、不貼任何東西到
GitHub。

段 1、段 2 做完之後重新查：

```bash
gh issue list --repo wm4n/chainbreak --label agent-failed --state open \
  --json number,title,labels,comments
gh issue list --repo wm4n/hangman    --label agent-failed --state open \
  --json number,title,labels,comments
gh issue list --repo wm4n/chainbreak --label needs-human --state open \
  --json number,title
gh issue list --repo wm4n/hangman    --label needs-human --state open \
  --json number,title
```

在 Discord 摘要裡列兩份清單：

1. **`agent-failed` 而且最後一則留言不是人類（`wm4n`）在失敗之後的回覆的單**
   ——沒有人在推它往前，需要人類知道。每張附一句原因（段 2 已經判斷過）：
   「poller 叫不醒 bot，已 @ 過人類」「WIP 已滿，規格已修，等下一輪放行」
   「人類已處理升級但沒有回覆」「找不到認領紀錄，無法判斷是否規格問題」
   「重做次數查詢失敗」等。最後一則留言是 `wm4n`、
   而且晚於最後一次 `labeled agent-failed` 的不列：段 2 的步驟 2 已經交給 poller
   續作。帶 `needs-human` 的不列在這裡，列在第 2 份。
2. **帶 `needs-human` 的 open 單**——提醒還有哪些在等人類決定。**只放在摘要，
   不再 @**：這些單升級當時已經 @ 過，每輪重 @ 只會讓人學會忽略通知。

## 段 4：`ready-for-human` 歸 `product-planning`

`ready-for-human` 的單由 `product-planning` 的「3c. `ready-for-human` 的單」
處理（落在五類就升級，不落在五類由 Summer 決定後收養）。**本 skill 掃全部時
不碰它**，避免兩支 skill 搶同一張單、做出不同的決定。

只有人類在參數裡明確點名一張 `ready-for-human` 的單（`<owner/repo>#<N>`）時，
本 skill 才處理那一張，而且**完全照 `product-planning` 的規則做**：候選的留言
檢查（`## Summer 收養此單`、`依人類決定不收養`、`## 需要人類決定（needs-human）`
三個固定標題）、label 預檢、滾動 7 天預算、收養的三個動作與順序。本 skill 不
另訂規則，兩邊不一致時以 `product-planning` 為準。

## Discord 摘要

整輪合併成**一則**精簡摘要，不逐張各發一則：本輪排序結果、放行了哪幾張、
修了哪幾張規格、升級了哪幾張、段 3 的兩份清單，以及因 WIP 已滿、label 缺漏、
查詢或操作失敗而沒做的項目與原因。每項一句話加 issue 連結，完整理由在 issue
留言裡，不要把留言全文貼進 Discord。

單則訊息上限 2000 字，超過會被截斷。@ 人類只有 `bot-notify` 那一則（規則見
「貼 `needs-human` 的固定順序」），其他地方的摘要不帶 @。Summer 若就是在
`bot-notify` 執行，摘要與那一則 @ 可以合併成同一則訊息，**但合併後必須 ≤ 2000
字**，超過就把 @ 單獨成一則先發，摘要另發一則。

## 鐵則

- **放行不等人類點頭，但每次放行前必查三道限制**：`needs-human` 五類、重做
  次數（≥ 2 升級）、WIP（≥ 2 停止）。三道都通過才放行，沒有任何路徑可以跳過，
  查詢失敗一律當作不通過。
- **GitHub 留痕，不無痕操作**：段 1 的排序理由、段 2 的規格修正、每一次放行、
  每一次升級，都要在對應的 GitHub issue 上貼一則帶 `— By Summer` 簽名的留言，
  記錄處理過程、決策依據與數據來源——這是 persona `Summer-AGENTS_v2.md`
  「資訊同步」鐵則的要求。**Discord 只放精簡摘要與連結，不是完整紀錄的所在**；
  反過來只在 Discord 講清楚、GitHub 上什麼都沒留下，就是違反這條鐵則。
  ⚠️ 簽名開頭是 **em dash（U+2014）**「—」，不是連字號「-」，直接複製本
  文件裡的 `— By Summer`，不要自己重打。
- **數據拿不到就明說，不准用推測冒充**（與 `product-planning` 共用同一條
  鐵則）：GA4 沒設定寫「無 GA4 數據（未設定）」，查詢失敗或 body 沒留下數據
  依據寫「這部分無法查證」，不編一個聽起來合理但沒有查證的訊號。
- **label 一律先加後移除**：放行先加 `ready-for-agent`、確認加上了，才移除
  `grill-me-done`／`agent-failed`。升級時原本的流程 label 留著不移除。
- **貼 `needs-human` 的順序固定：加 label → 單一 @ → 留言（第一行
  `## 需要人類決定（needs-human）`）**；加 label 失敗就整個停手。已有升級
  留言卻沒有 label，是人類處理完移除的，**絕不重新加回**；只有之後出現新的
  重做事件，才為那個新事件重新升級。
- **帶 `needs-human` 的 issue 一律不動**，只列進段 3 的提醒。
- **人類在 `agent-failed` 的單上回覆了，就交給 poller**，Summer 不修、不放行。
- **整輪只 @ 人類一次，且只在 `bot-notify`**。
- **排序只依產品價值與數據**，不做顆粒度拆解、不做技術可行性把關——那是
  實際執行開發的 Rick/Morty 的職責。WIP 上限是固定的費用防線，不是排序因素：
  不要因為「這張比較小」就讓它插隊。
- **不自己建 label**，缺 `ready-for-agent`／`needs-human` 的 repo 本輪段 1、
  段 2 不動作，請人類建立。
- 白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo。

## 不做什麼

- **不 approve、不 merge 任何 PR**——本 skill 完全不碰 PR，那是
  `acceptance-review` 掃 `agent-done` 之後的事。
- **不建 worktree、不切分支、不改程式碼**——只讀 issue、留言與 timeline，
  改 Summer 自己開的 issue 的描述文字，貼 issue 留言與 Discord 訊息，以及放行與
  升級的 label 操作。
- **不碰 `agent-active` 的單**：開發中的單、卡單的重送與升級都是 poller 的事。
- **掃全部時不碰 `ready-for-human` 的單**：那是 `product-planning` 的範圍（段 4）。
- **不用 `gh label create` 建 label**。

## 已知限制

- **usercron 已部署**：本 skill 依 Summer 容器內的 usercron 平日排程觸發
  （`sender_name`＝`SummerTriage`），時程以 `openab-ops` 的 `CRONJOB.md` 為準；
  人類在 Discord 要求時也能手動觸發，WIP 與重做次數每次都現查，手動多跑幾次
  不會繞過上限。
- **persona 需同步**：`Summer-AGENTS_v2.md` 若仍寫「絕不自行貼
  `ready-for-agent`」，那是改寫前的舊規定；`needs-human` 五類的定義仍以 persona
  為準。
- **`needs-human` label 需先存在於兩個 repo**：本 skill 不建 label，缺的話
  label 預檢會擋下該 repo 的段 1、段 2，並在 `bot-notify` 請人類建立。
- **放行時移除 `agent-failed` 失敗**：poller 每 10 分鐘認領一次，所以單子
  很容易變成 `agent-active`＋`agent-failed`，poller 會把它當成自己轉換到一半而
  移除 `agent-active`。本 skill 的對策是當場重試一次，還沒被認領就回滾
  `ready-for-agent`（見放行程序步驟 5）；已經被認領的話只能 @ 人類手動移除
  `agent-failed`。只有步驟 5 連續失敗才會走到這裡。
- **升級在「@ 之後、留言之前」被中斷**：人類已被通知、`needs-human` 已在
  身上，poller 都會跳過，只是 issue 上缺說明留言；這是接受的取捨，不補做。
  若人類之後只移除 label、沒有留言，這張單沒有升級留言可供辨認，可能再被升級
  一次、多發一次 @。機率極低，接受。
