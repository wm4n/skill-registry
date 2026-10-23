---
name: acceptance-review
argument-hint: "[<owner/repo>#<N>]"
description: >-
  驗收 agent-done issue 對應的 PR：逐條核對驗收條件，並在 PR head 的乾淨
  checkout 自己跑 base branch 的 CLAUDE.md 規定的測試（Flutter 至少 flutter
  analyze、flutter test；環境跑不起來算無法驗證、絕不當通過）。由 usercron 觸發（訊息「執行
  acceptance-review skill」，sender_name＝SummerAcceptance，時程
  30 9-21 * * *，以 CRONJOB.md 為準），或人類在 Discord 提出同類請求（如
  「驗收一下」「這張 PR 符合需求嗎」）時觸發。驗收基準三層：「✅ 需求
  共識」→ issue body 驗收條件段、Summer 規格修正段與 wm4n 留言（標「基準
  較弱」）→ 都沒有就貼 needs-human 找人決定基準，只報一次。通過 → 在 PR
  貼「驗收結果：通過（待自動 merge）」（head SHA、逐條依據、測試指令與輸出
  結尾），issue 貼一行連結，由主機端 merge-poller 依這則結果自動 merge（不在
  本 skill）。測試失敗
  先對 base branch 跑同一組指令：base 也紅歸「無法驗證（基線紅）」，不算重做。
  不通過、有衝突或 base 綠 head 紅 → 先算重做次數，未達 2 次用綁 head SHA 的
  Request changes 送回 bot 作者（由主機端 pr-review-poller 觸發作者）；達 2 次
  改貼 needs-human、不送回；作者不是 bot 帳號只留言、不送回，由主機端
  human-notifier 通知人類處理。本 skill 不在 Discord @ 任何人。同一個 head SHA
  只驗一次；送回做到一半會續做，作者回應了卻沒推新 commit 就留停滯通報（每個
  SHA 最多 2 次）。本 skill 永不 approve、永不 merge。帶 needs-human 的單一律
  不動，不改任何 label。
---

# Acceptance Review

> **本 skill 是 Rick/Morty 開完 PR 之後的收尾**：`agent-done` 代表 Rick/Morty
> 走完 `solo-feature-pipeline`、開好 PR、自我審查通過。本 skill 回答兩個
> 問題：**當初定案的需求，PR 真的做到了嗎**，以及**該 repo 規定的測試在 PR
> head 上真的全綠嗎**。第二個問題由 Summer 自己跑：chainbreak 沒有 CI，這是
> merge 前唯一的客觀證據，不能只信作者自稱「已自審」。
>
> 🔀 **merge 由主機端 merge-poller 自動執行，不在本 skill**（2026-10-23 起，
> openab-ops Ruling R21，作廢 R14）：
>
> - 通過 → 在 PR 貼驗收通過的結果（head SHA、逐條依據、測試指令與輸出）。
>   Mac mini 上的 `merge-poller.sh` 讀到這則結果、確認 `head SHA：` 等於 PR
>   目前的 head，並檢查完它自己的條件（PR 已含最新 main、可合併、沒有費用或權限
>   風險、未達每日上限、沒有熔斷）後，用 `wman-pm` 的 token squash merge。
> - 不通過 → 用 Request changes 送回原作者（這不是 approve，可以做），受
>   重做上限約束。
>
> **本 skill 永不 approve、永不 merge**：本文件裡沒有任何 approve 或 merge 的
> 指令，也不要自己補上。merge 的決定全部由 merge-poller 依程式條件做。
>
> 🕘 2026-10-17 到 2026-10-23 之間，自動 approve＋merge 暫緩，通過標題是
> `## 驗收結果：通過（待人類 merge）`，由人類按 merge（自動模式的安全分類器以
> 「Merge Without Review」擋下 bot 自己 merge）。R21 把 merge 移到主機端程式，
> 標題直接改名，沒有新舊並存期（`wman-pm` 從未貼過舊標題）。
>
> 📡 **Discord 的觸發與 @人類 都不是本 skill 發的**（Ruling R17，2026-10-17）：
> 本 skill 由 usercron 在 `summer-pm` 的 thread 裡跑，輸出只回得到那個 thread，
> Rick／Morty 也收不到那裡的訊息。所以本 skill **只在 GitHub 上留痕**——送
> Request changes review、貼固定標題的留言、加 `needs-human` label——由 Mac mini
> 主機端的三支 poller 讀 GitHub 之後各自動作：
>
> - `pr-review-poller.sh`：看到 PR 上有還沒回應的 `wman-pm`（或 `wm4n`）Request
>   changes，就觸發作者跑 `pr-review-response`。
> - `merge-poller.sh`：讀 `## 驗收結果：通過（待自動 merge）` 與它的 `head SHA：`
>   決定要不要 merge（R21）。PR 落後 main 而且併不進去時，它會用 `wman-pm` 在 PR 送一則
>   首行為 `## 自動 merge 受阻：與 main 衝突` 的 Request changes；費用或權限風險則升級
>   `needs-human`（第二行 `原因：自動 merge 前偵測到可能的費用或權限風險（第 1／2 類）`）。
>   這兩種都是 merge-poller 寫的，**不是本 skill 的送回或升級**，本 skill 讀紀錄時要
>   排除它們（見步驟 3a、8a、8d）。
> - `human-notifier.sh`：`needs-human` 被加上、或 PR／issue 上出現 `wman-pm` 貼的
>   `## 驗收結果：無法驗證（測試環境）`、`## 驗收結果：無法驗證（基線紅）`、
>   `## 驗收停滯：PR head 未更新`、`## 驗收紀錄補記失敗`、
>   `## 驗收結果：不通過（作者非 bot，待人類處理）`，就 @ 人類一次（一般的
>   `## 驗收結果：不通過` 不通知）。通過**不通知**：通過已經不需要人類動作；只有通過
>   之後超過 12 小時 PR 還沒被 merge，它才 @ 人類一次（pass-stale）。
>
> 所以那幾個標題的第一行一個字都不能改：改了 merge-poller 就不 merge，人類也收不到
> 通知。本 skill 在 Discord 只回本輪摘要（不帶任何 @）。

## 觸發與參數

`$ARGUMENTS`：

- 空 → **掃全部**：對 `wm4n/chainbreak`、`wm4n/hangman` 兩個白名單 repo，
  各自列出所有帶 `agent-done` label 的 open issue。
- `<owner/repo>#<N>` → **只處理這一張**。它目前沒有 `agent-done` label →
  說明「這張不在 agent-done 狀態」並停止，不要臆測要不要繼續看。

```bash
gh issue list --repo wm4n/chainbreak --label agent-done --state open --limit 200 \
  --json number,title,body,labels,author,comments
gh issue list --repo wm4n/hangman    --label agent-done --state open --limit 200 \
  --json number,title,body,labels,author,comments
```

排程是 usercron `30 9-21 * * *`（每天 09:30–21:30 每小時一次，時程以 `openab-ops` 的
`CRONJOB.md` 為準）。一天跑 13 次，所以**同一個 head SHA 只驗一次**（見
步驟 3 的 R4），Discord 也只報有變化的事（見「Discord」）。

### ⚠️ 先把參數拆開：`gh` 不吃 `owner/repo#N`

`gh issue`／`gh pr` 各子指令只接受 `{<number> | <url>}`，先拆成變數，repo
用 `--repo` 旗標指定：

```bash
ISSUE_REF="wm4n/chainbreak#42"   # 從 $ARGUMENTS 取得
REPO="${ISSUE_REF%#*}"           # → wm4n/chainbreak
NUM="${ISSUE_REF##*#}"           # → 42
OWNER="${REPO%%/*}"              # → wm4n
REPO_NAME="${REPO#*/}"           # → chainbreak
```

掃全部時，下面所有指令裡的 `REPO`、`NUM`、`OWNER`、`REPO_NAME` 換成當下處理
的那張單；`PR_NUM` 是步驟 2 找到的 PR 編號。

### 狀態檔：跨 Bash 呼叫的值一律存檔、現讀

一張單的處理會跨很多次 Bash 呼叫，shell 變數不保證留得住，殘留上一張單的值
更危險（SHA 對錯 PR，驗收結果就貼到錯的 commit 上）。每張單開始時開一個狀態
目錄，head SHA、測試 log 都寫進去，要用時從檔案讀：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
/bin/rm -rf "$STATE"; mkdir -p "$STATE"
```

之後每次 Bash 呼叫開頭都重新設定 `STATE`（同一個算式）。**SHA 一律由指令寫入、
由指令讀出**（`$(cat "$STATE/head_sha")`），不要自己抄寫 40 個字元進留言——
抄錯一個字元，冪等就會失準。

## 帳號、固定 ID 與固定標題

- 人類是 `wm4n`；bot 帳號是 `wman-dev`（Rick）、`wman-review`（Morty）、
  `wman-pm`（Summer）。
- Discord：本 skill **不 @ 任何人**（人類、Rick、Morty 都不 @）。觸發作者與
  通知人類都由主機端 poller 發到 `bot-notify`（見文件開頭的 📡）。
- 簽名一律逐字 `— By Summer (acceptance-review)`（開頭是 em dash U+2014
  「—」，不是連字號「-」）。直接複製本文件裡的字串，不要自己重打。

本 skill 靠下面幾個固定標題辨認留言，一律用「**留言內容的第一行，去掉前後
空白後，以這串完全相同的字串開頭**」判斷，並且只認作者是 `wman-pm` 的留言
（「✅ 需求共識」除外，見步驟 4）。寫這幾種留言時第一行必須逐字照抄、不可
改字或加前綴：

| 第一行 | 貼在哪 | 拿來做什麼 |
| --- | --- | --- |
| `## 驗收結果：通過（待自動 merge）` | PR | 冪等（記下驗過的 SHA）；**主機端 merge-poller 據此自動 merge（不在本 skill）**；human-notifier 不通知，只在 12 小時未 merge 時提醒 |
| `## 驗收結果：不通過` | issue | 冪等；**`backlog-triage` 靠它算重做次數**；送回給 bot 作者的紀錄，不通知人類 |
| `## 驗收結果：不通過（作者非 bot，待人類處理）` | issue | PR 作者不是 bot 帳號時用這一行取代上一行（2026-10-17 fix round 1）：不送回、要人類處理；**human-notifier 通知**。它以 `## 驗收結果：不通過` 開頭，重做次數與冪等照樣算到 |
| `## 驗收結果：無法驗證（測試環境）` | PR | 冪等；Summer 環境跑不起來，不算重做；human-notifier 通知 |
| `## 驗收結果：無法驗證（基線紅）` | PR | 冪等；base branch 自己就紅（R18），不算重做；human-notifier 通知 |
| `## 需要人類決定（needs-human）` | issue | 升級紀錄（R15，見下）；第二行區分兩種升級。通知靠 label 事件，不靠這則。merge-poller 也會貼同一個首行（第二行是費用或權限風險），那則不是本 skill 的紀錄，3a 會排除 |
| `## 驗收停滯：PR head 未更新` | PR | 通報停滯（原因寫在內文）；每個 SHA 最多 2 則，去重規則見步驟 3；human-notifier 通知 |
| `## 驗收紀錄補記失敗` | PR | 8d 補記不通過紀錄失敗時通報人類；每個 SHA 只報一次；human-notifier 通知 |

`## 驗收結果：不通過` 這串字一個字元都不能改：`backlog-triage` 算重做次數時
就是用它比對（第一行以它開頭），改了就會少算，自動送回的迴圈就失去上限。
`## 驗收結果：不通過（作者非 bot，待人類處理）` 刻意以同一串開頭，所以作者非 bot 的那則也算一次重做、也是這個 SHA 的冪等
紀錄；只有它會被 human-notifier 通知，一般的不通過不會。標了「human-notifier
通知」的幾行也一樣：主機端 `human-notifier.sh` 只認作者 `wman-pm`、第一行以這幾串
開頭的留言，改了人類就收不到通知。舊版本貼過只有
`## 驗收結果` 的 PR 留言（沒有冒號後綴、沒有 SHA），**不符合上表任何一行，
視為「還沒驗過」**。

每則通過／不通過／無法驗證／停滯留言、以及第 5 類的 needs-human 留言，都要有
一行 `head SHA：<40 碼小寫 16 進位>`（全形冒號），冪等靠它。驗收基準那種
needs-human 留言**絕不能有這一行**（原因見步驟 3）。

## 什麼時候找人：`needs-human`

**要不要找人，唯一標準是 persona `Summer-AGENTS_v2.md` 的 `needs-human`
清單**，本 skill 不自創判準。五類的短標題（定義以 persona 為準，兩邊不一致
時以 persona 為準）：

1. 費用
2. 權限與秘密
3. 對外發布或不可逆
4. 產品方向翻轉
5. 自動重做達上限

本 skill 會走到的只有兩種：

- **第 5 類**：驗收不通過時，重做次數（含本次）達 `REWORK_MAX = 2`（見
  「重做次數」）。
- **找不到驗收基準**（見步驟 4 第三層）：不屬於五類，是設計明文允許的特例
  ——真的不知道要驗什麼，只能問人。**每張 issue 只報一次。**

### 貼 `needs-human` 的固定順序（順序不可換）

1. **加 `needs-human` label**：

   ```bash
   gh issue edit "$NUM" --repo "$REPO" --add-label needs-human
   gh issue view "$NUM" --repo "$REPO" --json labels --jq '[.labels[].name]'
   ```

   第二行看到 `needs-human` 才算成功。**這一步失敗就停在這裡**：不留言、
   也不貼 `## 驗收結果：不通過`，什麼都不留下。因為什麼都沒貼，
   下一輪看到的還是原樣，自然會重試。
2. **在 issue 上留言**，第一行固定 `## 需要人類決定（needs-human）`，**第二行
   固定**是下面兩種之一，逐字照抄（之後靠第二行分辨是哪一種升級）。兩種用
   不同的模板，不要混用。
3. **不要自己 @ 人類**（2026-10-17 改，Ruling R17：原本第 2 步是「在 `bot-notify`
   @ 人類一次」，但本 skill 跑在 `summer-pm` 的 thread，@ 送不到 `bot-notify`）。
   主機端 `human-notifier.sh` 看到 `labeled needs-human` 事件就會 @ 人類一次，
   並附上這則留言的連結。所以順序是 label → 留言 → poller @。

**第 5 類**（第二行 `原因：自動重做達上限（第 5 類）`，要寫 SHA）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 需要人類決定（needs-human）\n原因：自動重做達上限（第 5 類）\n\nhead SHA：%s\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
重做次數：agent-failed <a> 次＋驗收不通過 <b> 次＋本次 1 次，上限 2

本次不通過的項目：
- <驗收條件 #2：缺了什麼>
- <`flutter test` exit 1：失敗摘要>

需要人類決定：<要決定的事>

選項：
- <選項一>
- <選項二>

處理方式：在本 issue 回覆決定，並移除 needs-human label。
EOF
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh issue comment "$NUM" --repo "$REPO" --body-file -
```

**驗收基準**（第二行 `原因：需要人決定驗收基準`，**整則不得出現 `head SHA：`**）：

```bash
{
printf '## 需要人類決定（needs-human）\n原因：需要人決定驗收基準\n\n'
cat <<'EOF'
不屬 needs-human 五類，是驗收基準的特例：這張 issue 找不到可以拿來驗收的條件。

找過的來源：
- 「✅ 需求共識」留言：沒有
- issue body 的 `## 驗收條件`／`## Acceptance criteria`：沒有
- body 末尾的 Summer 規格修正段：沒有
- wm4n 指定驗收基準的留言：沒有

需要人類決定：這張 PR（#<PR 編號>）要用什麼條件驗收。

選項：
- 在本 issue 留言列出驗收條件（第一行寫 `## 指定驗收基準（人類決定）`）
- 在 issue body 補上 `## 驗收條件` 段
- 不驗收，由人類自己決定要不要 merge

處理方式：補好基準後移除 needs-human label，下一輪會照新的基準驗收。
EOF
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh issue comment "$NUM" --repo "$REPO" --body-file -
```

兩種都用同一個方式確認貼上了（把 `<第二行>` 換成那一則的第二行）：

```bash
gh api "repos/$REPO/issues/$NUM/comments" --paginate \
  --jq '.[] | select(.user.login == "wman-pm" and (.body | split("\n") | (.[0] | sub("^\\s+"; "") | sub("\\s+$"; "")) == "## 需要人類決定（needs-human）" and (.[1] // "" | sub("^\\s+"; "") | sub("\\s+$"; "")) == "<第二行>")) | .html_url'
```

**絕不重新加回 `needs-human`**：issue 上有 Summer 的升級留言、卻沒有
`needs-human` label，代表人類處理完並移除了它，不是「做到一半」。怎麼接著
處理：

- **驗收基準那一種**（作者 `wman-pm`、第一行 `## 需要人類決定（needs-human）`、
  第二行去掉前後空白後**完全等於** `原因：需要人決定驗收基準`）：
  照步驟 4 重新找基準——人類多半已經補了基準留言或 body 驗收條件段。還是找
  不到 → 跳過、不再升級（只報一次），摘要列一行「人類已處理升級但仍無驗收
  基準」。
- **第 5 類**：升級留言記了當時的 head SHA。PR head 還是同一個 SHA → 冪等
  跳過，等人類自己處理（要送回、要自己修、要關 PR 都由人決定，本 skill
  不替人類送回）。PR 有了**新的** SHA → 那是新的一輪，照常驗收；再不通過
  是新的失敗事件，重做次數一樣 ≥ 2，**照固定順序再升級一次**——這不是加回
  人類為上一件事移除的 label，而是為新事件升級，上限才不會被一次人類決定
  永久解除。

`backlog-triage`、`product-planning` 為別的事貼過的升級留言（簽名是
`— By Summer`、沒有 `head SHA：`）跟本 skill 無關，不影響上面的判斷。

**帶著 `needs-human` 的 issue，本 skill 一律不動**：不驗收、不跑測試、不留言、
不送回，只在摘要列出。它在等人類，任何自動化介入都可能蓋過人類的決定，或在
等人時繼續燒額度。

## 每輪開始前的預檢

### 1. GitHub 帳號必須是 `wman-pm`

```bash
gh api user --jq '.login'
```

不是 `wman-pm`（或查詢失敗）→ **本輪不做任何寫入**（不留言、不送 review、
不加 label），只在摘要寫明並請人類處理（摘要不帶 @，見「已知限制」）。冪等與重做
次數都只認 `wman-pm` 的留言，用別的帳號寫，下一輪就認不出來：同一個 SHA 被
重驗、重送，重做次數也少算。

### 2. label 預檢

```bash
gh label list --repo wm4n/chainbreak --limit 200 --json name --jq '.[].name'
gh label list --repo wm4n/hangman    --limit 200 --json name --jq '.[].name'
```

`--limit 200` 不能省：`gh label list` 預設只回 30 個，會把存在的 label 誤判成
缺漏。要確認的是 `needs-human`。缺 `needs-human`，或 `gh label list` 本身報錯
→ **那個 repo 本輪只讀不寫**：重做達上限時升級不了，卻照常送回，就會繞過上限，
所以整個 repo 都不寫。缺的 label 不要自己建（改 repo 設定屬於第 2 類），在本輪
摘要裡寫明、請人類建立（摘要不帶 @，見「已知限制」）。

（2026-10-17 移除原本的預檢 3「記下本輪的台北時間小時」：它只用來決定「升級做到
一半」要不要在 09 點那一輪併進 @。@ 人類改由主機端 `human-notifier.sh` 依
`labeled needs-human` 事件發送（Ruling R17），本 skill 不再需要知道現在幾點。）

## 流程（每張 issue 依序做）

**失敗只影響那一張**：對單一 issue 的任何查詢或寫入失敗，記下來、跳過這張，
繼續處理其餘的。**任何寫入都要用指令確認真的寫進去**（每一步附的確認指令），
確認不了就當作失敗、不往下做，記進摘要。

### 1. 先看 issue 本身

- 帶 `needs-human` → 不驗收、不送回、不留言，但先看是不是**升級做到一半**
  （R15 第 1 步加了 label，之後被中斷，沒有貼出這次的說明留言）。用時間判斷，
  不用「有沒有升級留言」判斷——issue 上可能留著**上一次**、人類早已處理完的
  升級留言：

  ```bash
  LBL_AT=; CMT_AT=; HALF=CHECK_FAILED
  # wman-pm 最後一次貼 needs-human 的時間，與 wman-pm 最後一則升級留言（任何簽名都算）的時間
  if RAW=$(gh api "repos/$REPO/issues/$NUM/timeline" --paginate \
       --jq '.[] | select(.event == "labeled" and .label.name == "needs-human" and .actor.login == "wman-pm") | .created_at') \
     && LBL_AT=$(printf '%s\n' "$RAW" | grep . | sort | tail -n 1) \
     && RAW=$(gh api "repos/$REPO/issues/$NUM/comments" --paginate \
       --jq '.[] | select(.user.login == "wman-pm" and (.body | split("\n")[0] | sub("^\\s+"; "") | startswith("## 需要人類決定（needs-human）"))) | .created_at'); then
    CMT_AT=$(printf '%s\n' "$RAW" | grep . | sort | tail -n 1)
    # label 是 Summer 貼的，而且晚於 Summer 最後一則升級留言（或根本沒有留言）→ 做到一半
    # ISO 8601 UTC 時間字串可以直接排序比大小（同 backlog-triage 的寫法）
    if [ -n "$LBL_AT" ] && { [ -z "$CMT_AT" ] || { [ "$LBL_AT" != "$CMT_AT" ] \
      && [ "$(printf '%s\n%s\n' "$LBL_AT" "$CMT_AT" | sort | tail -n 1)" = "$LBL_AT" ]; }; }; then
      HALF=yes
    else
      HALF=no
    fi
  fi
  echo "half=$HALF label_at=$LBL_AT comment_at=$CMT_AT"
  ```

  - `half=yes` → 升級做到一半：issue 上缺這次的說明。`human-notifier.sh` 看到
    label 事件時已經 @ 過人類（訊息會註明「尚無說明留言」），本 skill 不再 @，
    只在摘要**點名**列出「needs-human 已貼但沒有升級說明」。不補貼說明留言（不知道
    當初卡在什麼，補了只會亂寫）。
  - `half=no` → 摘要列出「等人類決定中」。
  - `half=CHECK_FAILED` → 摘要列出「等人類決定中（升級狀態查詢失敗）」。
- issue 不是 `OPEN` → 跳過。

### 2. 找出對應 PR——優先用 GraphQL 原生關聯，留言比對是 fallback

Rick/Morty 開 PR 時在描述寫 `Closes #<issue 編號>`，GitHub 會據此建立
issue↔PR 的原生關聯：

```bash
if ! GRAPHQL_OUTPUT=$(gh api graphql -f query='
query($owner:String!, $repo:String!, $issue:Int!) {
  repository(owner:$owner, name:$repo) {
    issue(number:$issue) {
      closedByPullRequestsReferences(first:5, includeClosedPrs:true) {
        nodes { number url title state headRefName author { login } }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO_NAME" -F issue="$NUM" \
  --jq '.data.repository.issue.closedByPullRequestsReferences.nodes[]
    | select(((.author.login // "") == "wman-pm" and ((.headRefName // "") | startswith("proposal/"))) | not)
    | "\(.number)\t\(.state)\t\(.url)\t\(.title)"' 2>&1); then
  echo "ERROR: GraphQL 查詢失敗 issue=${REPO}#${NUM}"
fi
echo "$GRAPHQL_OUTPUT"
```

輸出每行一張候選 PR：`<編號>\t<state>\t<網址>\t<標題>`。

- `issue` 一定用 `-F`（`Int!`），用 `-f` 會型別錯誤。`includeClosedPrs:true`
  讓已關閉的 PR 也回傳，下面才分得出「有 PR 但不是 OPEN」。
- **提案 PR 不算候選**（2026-10-23，R22）：作者 `wman-pm`、`headRefName` 以
  `proposal/` 開頭的是 Summer 的方向提案，不是這張 issue 的實作。上面的 jq 已經
  把它濾掉；它本來就不准寫 `Closes #`，濾掉是保證它就算被連上也不會讓下面的
  「超過一個 OPEN」誤判成異常。
- **查詢本身報錯** → 歸類「異常」，記下原始錯誤，**不要靜默滑進 fallback**：
  schema 變動、權限問題會被 fallback 吃掉、沒人發現。
- 剛好一個 `state` 為 `OPEN` 的候選 → 就是這張 PR。
- 沒有候選，或沒有一個是 `OPEN` → 走下面的 fallback。
- 超過一個 `OPEN` → 歸類「異常」，列出所有候選，不要自己猜一個。

**Fallback：留言文字比對**。在 issue `comments`（舊到新）裡找 Rick/Morty
收尾留言中的 `https://github.com/<owner>/<repo>/pull/<N>` 連結，取**最新**一則，
並用 `gh pr view "$N" --repo "$REPO" --json state,author,headRefName` 確認那張 PR 是
`OPEN`、而且不是提案 PR（作者 `wman-pm` 且分支以 `proposal/` 開頭）。兩條路都落空 →
歸類「異常」，不要憑標題湊一個 PR 編號。

### 3. 讀 PR 狀態，決定這一輪要不要驗

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
# 第一行是 head SHA、第二行是 PR 的 base 分支，其餘是 key=value；只用 gh 內建的 --jq，不依賴另外裝 jq
gh pr view "$PR_NUM" --repo "$REPO" \
  --json url,state,author,headRefOid,baseRefName,mergeable,mergeStateStatus \
  --jq '"\(.headRefOid)\n\(.baseRefName)\nurl=\(.url)\nstate=\(.state)\nauthor=\(.author.login)\nmergeable=\(.mergeable)\nmergeStateStatus=\(.mergeStateStatus)"' \
  > "$STATE/pr.txt" && head -n 1 "$STATE/pr.txt" > "$STATE/head_sha" \
  && sed -n 2p "$STATE/pr.txt" > "$STATE/base_ref" \
  && grep -Eq '^[0-9a-f]{40}$' "$STATE/head_sha" && [ -s "$STATE/base_ref" ] \
  && echo "head=$(cat "$STATE/head_sha") base=$(cat "$STATE/base_ref")"
cat "$STATE/pr.txt"
```

沒有印出 `head=<40 碼 SHA> base=<分支名>` → 查詢失敗，歸類「異常」。

**3a. 一次撈齊判斷要用的事實**（整段放在同一次 Bash 呼叫裡跑）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
HEAD_SHA=$(cat "$STATE/head_sha")
FACTS_OK=yes; MARK=; MARK_AT=; REV=; REV_AT=; REV_AGE=; HEAD_REC=; FAIL_AT=; FAIL_AGE=; AFTER_REV_N=
STALL_TOTAL=; STALL_AFTER_MARK=
# gh 失敗要先接住再 sort：寫成 X=$(gh … | sort) 的話，失敗會被 sort 的 exit 0 蓋掉
# (1) 最新的 pr-review-response 標記：時間、種類（start／done／failed）、距今秒數
if RAW=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq '.[] | (.body | split("\n")[0] | sub("^\\s+"; "") | sub("\\s+$"; "")) as $h | select($h | startswith("<!-- pr-review-response:")) | "\(.created_at) \($h | capture("pr-review-response:(?<k>[a-z]+)") | .k) \((now - (.created_at | fromdateiso8601)) | floor)"'); then
  MARK=$(printf '%s\n' "$RAW" | grep . | sort | tail -n 1)
  MARK_AT=$(printf '%s\n' "$MARK" | cut -d' ' -f1)
else FACTS_OK=no; fi
# (2) Summer 在目前這個 SHA 上最新一次 Request changes 的時間與距今秒數
#     排除 merge-poller 的衝突 review（首行 ## 自動 merge 受阻：與 main 衝突）：它也是 wman-pm 送的，
#     算進來的話 R2 會把它當成本 skill 送回做到一半，8d 補貼一則不通過、重做次數平白多一次
if RAW=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and .state == \"CHANGES_REQUESTED\" and .commit_id == \"$HEAD_SHA\") | select((.body // \"\") | split(\"\n\") | (.[0] // \"\") | gsub(\"^[\t \u00a0\u3000]+\"; \"\") | startswith(\"## 自動 merge 受阻：與 main 衝突\") | not) | \"\(.submitted_at) \((now - (.submitted_at | fromdateiso8601)) | floor)\""); then
  REV=$(printf '%s\n' "$RAW" | grep . | sort | tail -n 1)
  REV_AT=$(printf '%s\n' "$REV" | cut -d' ' -f1)
  REV_AGE=$(printf '%s\n' "$REV" | cut -s -d' ' -f2)
else FACTS_OK=no; fi
# (3) 紀錄留言（固定標題表的前五種、而且有 head SHA 的），PR 與 issue 兩邊都撈。
#     merge-poller 的 needs-human（第二行是費用或權限風險）不是本 skill 的紀錄，排除。
#     每行：<時間>\t<SHA>\t<標題>\t<距今秒數>
REC_JQ='.[] | select(.user.login == "wman-pm")
  | ((.body // "") | split("\n")) as $l
  | (($l[0] // "") | gsub("^[\t \u00a0\u3000]+|[\t\r \u00a0\u3000]+$"; "")) as $h
  | (($l[1] // "") | gsub("^[\t \u00a0\u3000]+|[\t\r \u00a0\u3000]+$"; "")) as $h2
  | select(($h | startswith("## 驗收結果：通過（待自動 merge）"))
      or ($h | startswith("## 驗收結果：不通過"))
      or ($h | startswith("## 驗收結果：無法驗證（測試環境）"))
      or ($h | startswith("## 驗收結果：無法驗證（基線紅）"))
      or (($h | startswith("## 需要人類決定（needs-human）"))
          and $h2 != "原因：自動 merge 前偵測到可能的費用或權限風險（第 1／2 類）"))
  | (((.body // "") | capture("head SHA：(?<s>[0-9a-f]{40})") | .s) // "none") as $s
  | select($s != "none")
  | "\(.created_at)\t\($s)\t\($h)\t\((now - (.created_at | fromdateiso8601)) | floor)"'
if PR_REC=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate --jq "$REC_JQ") \
  && ISSUE_REC=$(gh api "repos/$REPO/issues/$NUM/comments" --paginate --jq "$REC_JQ"); then
  ALL_REC=$(printf '%s\n%s\n' "$PR_REC" "$ISSUE_REC" | grep . | sort)
  # 目前這個 SHA 自己最新的一則紀錄（R4 用）。不能用「所有 SHA 裡最新的一則」：
  # force push X→Y→X 回到 X 時，最新的是 Y 的紀錄，會把早就驗過的 X 當成沒驗過、重貼一次
  HEAD_REC=$(printf '%s\n' "$ALL_REC" | awk -F '\t' -v s="$HEAD_SHA" '$2 == s {l = $0} END {print l}')
  # 目前這個 SHA 最新一則「不通過」紀錄的時間（R3 用）
  FAIL_AT=$(printf '%s\n' "$ALL_REC" | awk -F '\t' -v s="$HEAD_SHA" '$2 == s && index($3, "## 驗收結果：不通過") == 1 {t = $1} END {print t}')
  # 目前這個 SHA、不早於 rev_at 的最新一則「不通過」距今秒數（R3' 確認紀錄已補上用；沒有就空白）
  FAIL_AGE=$(printf '%s\n' "$ALL_REC" | awk -F '\t' -v s="$HEAD_SHA" -v r="$REV_AT" '$2 == s && $1 >= r && index($3, "## 驗收結果：不通過") == 1 {a = $4} END {print a}')
  # 目前這個 SHA、不早於 rev_at 的「不通過」或第 5 類升級紀錄有幾則（R2 用；沒有 rev_at 時無意義）
  AFTER_REV_N=$(printf '%s\n' "$ALL_REC" | awk -F '\t' -v s="$HEAD_SHA" -v r="$REV_AT" \
    '$2 == s && $1 >= r && (index($3, "## 驗收結果：不通過") == 1 || index($3, "## 需要人類決定（needs-human）") == 1) {n++} END {print n + 0}')
else FACTS_OK=no; fi
# (4) 這個 SHA 的停滯通報：總共幾則、晚於最新標記的有幾則
if RAW=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and (.body | split(\"\n\")[0] | sub(\"^\\\\s+\"; \"\") | startswith(\"## 驗收停滯：PR head 未更新\")) and (.body | contains(\"head SHA：$HEAD_SHA\"))) | .created_at"); then
  STALL_TOTAL=$(printf '%s\n' "$RAW" | grep -c .)
  STALL_AFTER_MARK=$(printf '%s\n' "$RAW" | awk -v m="$MARK_AT" 'NF && $1 > m {n++} END {print n + 0}')
else FACTS_OK=no; fi
echo "facts_ok=$FACTS_OK head=$HEAD_SHA"
echo "mark=$MARK"                # <時間> <start|done|failed> <距今秒數>，沒有標記就空白
echo "rev_at=$REV_AT"            # 目前 SHA 上 Summer 最新的 Request changes 時間，沒有就空白
echo "rev_age=$REV_AGE"          # 那則 review 距今秒數（R3' 用），沒有就空白
echo "after_rev_n=$AFTER_REV_N"  # 目前 SHA 上、不早於 rev_at 的不通過／第 5 類升級紀錄數
echo "head_rec=$HEAD_REC"        # 目前 SHA 最新的紀錄：<時間>\t<SHA>\t<標題>\t<距今秒數>，沒有就空白
echo "fail_at=$FAIL_AT"          # 目前 SHA 最新「不通過」紀錄的時間，沒有就空白
echo "fail_age=$FAIL_AGE"        # 目前 SHA、不早於 rev_at 的最新「不通過」距今秒數，沒有就空白
echo "stall_total=$STALL_TOTAL stall_after_mark=$STALL_AFTER_MARK"
# 作者在 rev_at 之後有沒有任何回應（R2、R3' 用）
if [ -n "$REV_AT" ] && [ -n "$MARK_AT" ] && [ "$MARK_AT" != "$REV_AT" ] \
  && [ "$(printf '%s\n%s\n' "$REV_AT" "$MARK_AT" | sort | tail -n 1)" = "$MARK_AT" ]; then
  echo "mark_after_rev=yes"
else
  echo "mark_after_rev=no"
fi
```

`facts_ok=no` → 判斷不了，**這張跳過**，歸類「異常」。不能當成「沒驗過」重跑：
會重送 review、多算一次重做。

`--paginate` 時 `--jq` 是逐頁各跑一次，所以 (4) 每則一行再用 `grep -c`／`awk`
數。ISO 8601 的 UTC 時間字串可以直接用字串比大小。

**3b. 依序判斷，第一個符合的就照做**（`mark` 的距今秒數 < 18000 叫「新的
`start`」（R1 用），≥ 57600 叫「逾時的 `start`」（R3 用）；介於兩者之間（5–16
小時）的 `start` 兩條都不符合，落到 R4，摘要計入「等作者回應（pr-review-poller
觸發中）」。5 小時是主機端 `pr-review-poller.sh` 的租約 `PR_REVIEW_LEASE_MIN=300`：
start 還在租約內，poller 也認定作者還在處理、不會重送。過了 5 小時 poller 會重送、
叫滿 3 次（約 15 小時）就自己 @ 人類，所以 R3 對「卡住的 start」要等到 16 小時
才通報，跟 R3' 同一個門檻，不搶在 poller 重送之前通報停滯。那邊改了這裡跟著改
（2026-10-17 R17 由 2 小時改成 5 小時；fix round 1 I3 把「逾時」拆出來改成 16 小時）。「參考時間」
＝`rev_at`，空白時用 `fail_at`。「可以通報停滯」＝`stall_after_mark` 是 0
**而且** `stall_total` < 2）：

| # | 條件 | 做什麼 |
| --- | --- | --- |
| R2 | `rev_at` 有值，而且 `after_rev_n` 是 0（目前 SHA 上沒有不早於那則 review 的不通過或第 5 類升級紀錄） | **送回做到一半**：Summer 在這個 SHA 送了 Request changes（送回已完成，作者由 `pr-review-poller` 觸發），之後的不通過留言沒貼成（失敗或被中斷）。走 8d「續做送回」，**不重跑測試、不再送第二則 review**，只補記不通過紀錄。排在 R1 前面也安全：8d 不碰作者、不發任何觸發，只補 issue 上的紀錄 |
| R1 | `mark` 是新的 `start` | **跳過**：Rick/Morty 正在原分支補 commit，現在的 head 可能只改到一半，驗了只會把半成品判成不通過、白白用掉重做額度。摘要計入「作者處理 review 中」 |
| R3 | `fail_at` 有值，`mark` 的時間晚於參考時間，而且 `mark` 是 `done`、`failed` 或逾時的 `start` | **停滯（作者已回應但未更新）**：作者回應了（提問、反駁、說超出範圍、失敗，或做到一半卡住），PR head 卻沒變。可以通報停滯 → 走 8e；否則跳過，摘要計入「停滯（已通報）」。**絕不重送** |
| R3' | `rev_at`、`rev_age` 與 `fail_age` 都有值，`mark_after_rev=no`（作者完全沒有回應），而且 `rev_age` ≥ 57600 | **停滯（作者未回應）**：review 送出超過 16 小時，作者連 `start` 都沒貼。`pr-review-poller` 在 review 之後約 10 分鐘內觸發、每 5 小時重送、叫滿 3 次（約 15 小時）就自己 @ 人類；過了 16 小時還完全沒有標記，代表 bot 一直沒醒，或 poller 本身沒在跑。這則是備援通報（poller 沒在跑時，它是唯一會讓人類知道的路）。可以通報停滯 → 8e（原因寫「作者未回應」）；否則跳過，摘要計入「停滯（已通報）」。**絕不重送**。還沒到 16 小時的不符合本列，會落到 R4（摘要改計入「等作者回應（pr-review-poller 觸發中）」，不要算成「已驗過」） |
| R4 | `head_rec` 有值（目前 SHA 有任何紀錄） | **冪等**，看 `head_rec` 的標題：`## 驗收結果：無法驗證（測試環境）` 或 `## 驗收結果：無法驗證（基線紅）`，而且這次是**指名單張**觸發 → 人類多半修好了環境或 base branch，繼續往下驗；這兩種、排程觸發 → 跳過，摘要計入「無法驗證（等環境修好）」或「無法驗證（等 base 修好）」；其他標題 → 跳過，摘要計入「已驗過」。**例外**：落到這裡的 5–16 小時 `start`（R1、R3 都不符合），以及送出未滿 16 小時、作者還沒有任何標記的送回（R3' 不符合），摘要計入「等作者回應（pr-review-poller 觸發中）」，不算「已驗過」（2026-10-18 補） |
| R5 | `mergeable` 是 `UNKNOWN`（剛 push 完常見） | 跳過，下一輪再看，不算失敗。摘要計入「待 GitHub 算合併狀態」 |
| — | 以上都不符合 | 繼續步驟 4 |

幾點說明：

- R2 只看「不早於 `rev_at`」的紀錄，不看「目前 SHA 有沒有紀錄」：同一個 SHA 先
  有一則「無法驗證」、之後人類指名重驗才送回；或是 force push X→Y→X 回到舊的
  SHA——這兩種情況下目前 SHA 上早就有舊紀錄，只看有沒有紀錄會把做到一半的送回
  誤判成「驗過了」。用 `>=`：同一秒寫下的紀錄也算是這則 review 之後的。
- R2 排在 R1 前面沒有例外（2026-10-17 改）：原本 8d 會補發 Discord 觸發，review
  與作者標記落在同一秒時會多觸發一次；現在觸發由 `pr-review-poller` 負責，8d 只
  補記紀錄，不會打擾正在處理的作者。
- R3 的參考時間用 `rev_at` 而不是 `fail_at`：作者收到觸發後，可能比 Summer 的
  不通過留言更早貼出 `start`；拿 review 時間比，才不會漏掉這一輪的回應。
- R3' 的時間基準是 `rev_age`（review 的年齡）（2026-10-17 改，R17）：原本用
  `fail_age`，因為當時觸發由本 skill 在 review 之後、紀錄之前發出，紀錄時間最接近
  「觸發完成」。現在觸發由 `pr-review-poller` 看到 review 就發（約 10 分鐘內），
  跟紀錄何時貼無關，所以改看 review 的年齡；門檻 16 小時大於 poller 的
  「3 次 × 5 小時」，讓 poller 先重送、先升級，本 skill 只當備援。`fail_age` 仍要
  有值：沒有紀錄的話是 R2 的事（先補記）。
- R3' 只在 `rev_at` 有值時成立：作者不是 bot 帳號、或第 5 類升級那兩條路沒有送
  review，poller 也就不會觸發，本來就不會有作者的標記，不能算「沒回應」。
- 停滯通報的去重：只看「晚於作者最新標記」的通報，每個 SHA 最多 2 則。先因為
  「作者未回應」通報過，作者之後才貼 `done`（標記比那則通報新）→ R3 還能再
  通報一次「作者已回應但未更新」，不會被先前那則吃掉；同一種情況不會重報。
- R3、R3' 只在 PR head **沒變**時成立：作者推了新 commit，SHA 就變了，`fail_at`
  是空的，直接走 R4 以後的正常驗收。
- 驗收基準那種 needs-human 留言**刻意不寫 SHA**：寫了的話，人類補上基準之後
  PR head 沒變，R4 就會把它當成「驗過了」永遠跳過。

### 4. 取得驗收基準——三層，依序找

**第一層：「✅ 需求共識」**。`jira-grill` 收斂時貼的共識留言：第一行去掉
前後空白、拿掉所有 `*` 之後以 `✅ 需求共識` 開頭（實際長相是
`✅ **需求共識**`，作者是 grill 的 bot，舊單可能是 `wm4n`），取最新一則。
它的「驗收條件」段就是基準清單，再疊加之後的修正：

- 它之後有 `wman-pm` 第一行 `## Summer 已修正規格` 的留言（`backlog-triage`
  修過規格）→ 修正寫在 issue **body**：Summer 自己開的單是直接改了 body
  的對應段落（留言的「變更摘要」點名改了哪段）；人類開的單是在 body 末尾
  附加 `## Summer 規格修正（YYYY-MM-DD）`。把修正疊加到基準清單上，衝突時以
  修正為準，多段修正段以日期最新的為準。不要拿整份 body 取代共識：body 其餘
  部分是開單當下的草稿，精煉程度不如共識。
- 它之後有 `wm4n` 明確指定或修改驗收基準的留言 → 照人類說的做，人類的明確
  指定永遠優先。

**第二層（沒有共識時）：issue body 與人類留言**，報告裡標明
**「基準較弱（沒有 grill 共識）」**：

- body 的驗收條件段：`## 驗收條件` 或 `## Acceptance criteria`；
- body 末尾的 `## Summer 規格修正（YYYY-MM-DD）` 段（日期最新的為準，衝突時
  修正段優先）；
- `wm4n` 的留言。**`wm4n` 明確指定驗收基準的留言優先於上面兩項**——例如
  `chainbreak#82` 2026-10-16 那則 `## 指定驗收基準（人類決定）`：照它列的來源
  與排除項目驗（它說 `## 已知缺口（這一張刻意不做）` 不算缺漏，就不能判成
  不滿足）。

**第三層：上面都拼不出一份具體的條件清單** → 不要憑標題或 PR 描述自己腦補。
先看有沒有本 skill 為驗收基準升級過（見「絕不重新加回」）：

- 沒有 → 走「貼 `needs-human` 的固定順序」，卡點寫「需要人決定驗收基準」，
  **不寫 SHA**。這不是驗收不通過：不送 review、不算重做、不貼
  `## 驗收結果：不通過`。
- 有，label 已被人類移除 → 跳過，摘要列「人類已處理升級但仍無驗收基準」。
  （label 還在的話，步驟 1 已經跳過，不會走到這裡。）

### 5. 逐條比對驗收條件

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json title,body
gh pr diff "$PR_NUM" --repo "$REPO"
```

對基準清單**逐條**對照 diff 與 PR 描述（步驟 6 的 checkout 也可以拿來讀完整
檔案），判定：

- ✅ **滿足**：寫下具體依據（哪個檔案、哪段邏輯、哪個測試）。
- ❌ **不滿足**：看不出做到、或明確衝突，寫下缺了什麼。「PR 沒有提供證據」
  也是不滿足。
- ❓ **需人類實機確認**：只限條件本身就要在實機上觀察（手感、聲音、畫面），
  程式碼與測試都無法驗證的。寫下為什麼只能實機確認。不要拿 ❓ 逃避判斷：
  能從程式碼或測試判斷的，就判 ✅ 或 ❌。

**只看規格符合度**，不評論程式碼風格、效能、命名——那是作者自我審查的職責。

### 6. 自己跑測試（spec D 條件 3）

**驗收條件已經有 ❌ 也要跑**：一次 Request changes 把所有問題列齊，作者一輪就
能修完。每送回一次就用掉一次重做額度，分兩次送回等於白白浪費一次。

**6a. 在乾淨的 worktree 檢出 PR head**（不在 base clone 上切分支）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
HEAD_SHA=$(cat "$STATE/head_sha")
BASE="/home/node/repos/$OWNER/$REPO_NAME"
WT="/home/node/repos/$OWNER/$REPO_NAME-worktrees/accept-pr-$PR_NUM"
printf '%s' "$WT" > "$STATE/wt"
[ -d "$BASE/.git" ] || gh repo clone "$REPO" "$BASE"
git -C "$BASE" fetch origin
git -C "$BASE" fetch origin "+refs/pull/$PR_NUM/head:refs/remotes/origin/accept-pr-$PR_NUM"
git -C "$BASE" worktree prune
# 上一輪被中斷留下的同名 worktree 先清掉；目錄還在、卻沒註冊成 worktree 的（remove 會失敗），直接刪目錄
[ -e "$WT" ] && git -C "$BASE" worktree remove --force "$WT"
[ -e "$WT" ] && /bin/rm -rf "$WT" && git -C "$BASE" worktree prune
if git -C "$BASE" worktree add --detach "$WT" "$HEAD_SHA" \
  && [ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_SHA" ]; then
  echo "WT_OK $WT"
else
  echo "WT_FAILED"
fi
```

`WT_FAILED` → 環境跑不起來（見 6c），不是作者的錯。

**6b. 測試指令一律從 PR 的 base branch 讀，不從 PR head 讀**：作者可以在同一張
PR 裡把 `CLAUDE.md` 的測試指令改弱或刪掉，從 PR head 讀等於讓被驗的人自己決定
怎麼驗。指令來自 PR 要合進去的那個分支（`baseRefName`，步驟 3 存在
`$STATE/base_ref`），**執行地點**才是 PR head 的 worktree：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
BASE="/home/node/repos/$OWNER/$REPO_NAME"; HEAD_SHA=$(cat "$STATE/head_sha"); BREF=$(cat "$STATE/base_ref")
if [ -n "$BREF" ] && git -C "$BASE" rev-parse --verify -q "origin/$BREF" >/dev/null; then
  echo "BASE_REF_OK origin/$BREF"
  for DOC in CLAUDE.md AGENTS.md; do
    git -C "$BASE" show "origin/$BREF:$DOC" > "$STATE/base-$DOC" 2>/dev/null && echo "BASE_DOC $DOC" || /bin/rm -f "$STATE/base-$DOC"
  done
  git -C "$BASE" cat-file -e "origin/$BREF:pubspec.yaml" 2>/dev/null && echo "FLUTTER_REPO"
  # PR 相對 base 動了哪些檔。--no-renames：改名會拆成 D（舊路徑）＋A（新路徑），
  # 把測試檔改名搬出 test/ 也會留下一行 D，不會因為只看新路徑而漏報
  git -C "$BASE" diff --no-renames --name-status "origin/$BREF...$HEAD_SHA" > "$STATE/changed.tsv" && echo "DIFF_OK"
else
  echo "BASE_REF_FAILED"
fi
```

- 讀 `$STATE/base-CLAUDE.md`（以及 `base-AGENTS.md`，有的話）找該 repo 規定的
  測試／檢查指令。**不要讀 worktree 裡的 `CLAUDE.md`／`AGENTS.md`。**
- 印出 `FLUTTER_REPO`（base 有 `pubspec.yaml`）→ **不論文件怎麼寫，至少要跑
  `flutter analyze` 與 `flutter test`**（先 `flutter pub get`）。
- repo 有 mise 設定檔（`.mise.toml`／`mise.toml`）時先在 worktree 跑
  `mise trust` 與 `mise install`。
- **最後的指令清單是空的**（不是 Flutter，文件裡也找不到任何測試指令），或印出
  `BASE_REF_FAILED`、沒印出 `DIFF_OK` → 沒有測試證據，**絕不算通過**：
  照「環境跑不起來」處理（6c），結果走 8c「無法驗證」。
- **把指令的實際來源寫進狀態檔**，結果留言照抄它，不要寫死「CLAUDE.md」：

  ```bash
  STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
  # 例：base branch `main` 的 CLAUDE.md＋Flutter 最低要求（flutter analyze、flutter test）
  printf '%s' '<base branch `<分支>` 的哪份文件（CLAUDE.md／AGENTS.md／兩者）＋是否套用 Flutter 最低要求>' > "$STATE/test_source"
  ```

**PR 動到測試、測試指令或測試設定，要讓人類看見**：指令雖然來自 base，執行時
讀的設定檔卻來自 PR head——`analysis_options.yaml` 可以關掉 lint、
`dart_test.yaml` 可以跳過測試、`pubspec.yaml`／`pubspec_overrides.yaml` 可以換掉
測試相依、`Makefile` 與工具版本設定（`.tool-versions`；mise 的 `mise.toml`、
`.mise.toml`、`mise.<env>.toml`、`.mise.<env>.toml`（含 `mise.local.toml`）、
`mise/config.toml`、`mise/config.<env>.toml`，以及 `.config/mise/`、`.mise/` 底下的
檔案）可以改掉指令實際做的事或用到的工具版本。這些一律列出來（2026-10-18 補
`mise.<env>.toml` 與 `mise/config.toml`）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
# 測試指令文件、測試設定檔、測試檔（test/、tests/、integration_test/、*_test.*、test_*）；D 開頭是刪除
awk -F '\t' '{p = $NF}
  p ~ /(^|\/)(CLAUDE|AGENTS)\.md$/ \
  || p ~ /(^|\/)(analysis_options\.yaml|dart_test\.yaml|pubspec\.yaml|pubspec_overrides\.yaml|Makefile|\.tool-versions)$/ \
  || p ~ /(^|\/)\.?mise(\.[^\/]+)?\.toml$/ \
  || p ~ /(^|\/)mise\/config(\.[^\/]+)?\.toml$/ \
  || p ~ /(^|\/)(\.config\/mise|\.mise)\// \
  || p ~ /(^|\/)(test|tests|integration_test)\// \
  || p ~ /(_test\.[a-z]+|(^|\/)test_[^\/]*)$/ {print}' \
  "$STATE/changed.tsv" > "$STATE/sensitive.tsv"
cat "$STATE/sensitive.tsv"
```

有輸出 → 在這張的結果留言（通過、不通過、無法驗證都一樣）加一段
「⚠️ 本 PR 動到測試或測試指令」，逐行列出（`D` 開頭的標明「刪除」）。這不會讓
結果變成不通過——改測試、改設定本來就常見——只是留下紀錄。2026-10-23 起 merge 由
merge-poller 自動執行（R21）。merge-poller 不讀這段留言，而是自己依 PR 的 files 清單
擋下削弱測試的情況（R24'）：刪除測試檔、把測試檔改名成非測試檔、修改
`analysis_options.yaml`／`dart_test.yaml`／`pytest.ini`／`jest.config.*`／
`vitest.config.*`／`flutter_test_config.dart`（有改就擋），以及 `CLAUDE.md`／`AGENTS.md`
的 patch `+`／`-` 行出現測試或檢查指令字樣（`flutter test`、`pytest`、`測試指令` 這類，
不分大小寫；只改設計紀錄不擋）；把檔案 rename 成或 rename 出 `CLAUDE.md`／`AGENTS.md`
也擋（等於新增或拿掉一份測試指令來源，純 rename 看不出內容）。命中就不 merge、升級 `needs-human`；GitHub 沒給 patch 的文字檔也擋，二進位
asset 不擋。一般的新增或修改測試不擋。這段列表給人類看是哪些檔、事後稽核用。
（2026-10-17 版本寫的是「人類 merge 前要看得到」，那時 merge 由人類按。）

**逐一執行**：每個指令都照這個模式跑，把 exit code 與 log 存進狀態目錄：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
WT=$(cat "$STATE/wt")
NAME=flutter-test                 # 每個指令一個名字：flutter-pub-get、flutter-analyze……
CMD='flutter test'                # 實際要跑的指令
( cd "$WT" && eval "$CMD" ) > "$STATE/$NAME.log" 2>&1
RC=$?
printf '%s\t%s\t%s\n' "$NAME" "$RC" "$CMD" >> "$STATE/tests.tsv"
echo "$NAME exit=$RC"
tail -n 15 "$STATE/$NAME.log"
```

**exit code 不是 0 就是失敗**，不要因為輸出「看起來只是警告」就放過。

**6b'. head 有指令失敗時，對 base branch 跑同一組指令（Ruling R18，2026-10-17）**：
base 自己就紅的話，每張 PR 都會被判不通過、白白燒掉重做額度，兩輪就全部轉成
`needs-human`。所以 head 上有任何指令 exit ≠ 0，就在另一個乾淨的 worktree 檢出
`origin/<base_ref>`，**照同一個順序跑同一組指令**（含 `flutter pub get`、`mise
install` 這類前置）。head 全部 exit 0 就不必跑——base 的結果只在 head 失敗時才有意義。

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
BASE="/home/node/repos/$OWNER/$REPO_NAME"; BREF=$(cat "$STATE/base_ref")
WTB="/home/node/repos/$OWNER/$REPO_NAME-worktrees/accept-pr-$PR_NUM-base"
printf '%s' "$WTB" > "$STATE/wt_base"
[ -e "$WTB" ] && git -C "$BASE" worktree remove --force "$WTB"
[ -e "$WTB" ] && /bin/rm -rf "$WTB" && git -C "$BASE" worktree prune
if git -C "$BASE" worktree add --detach "$WTB" "origin/$BREF" \
  && git -C "$WTB" rev-parse HEAD > "$STATE/base_sha" && grep -Eq '^[0-9a-f]{40}$' "$STATE/base_sha"; then
  echo "WTB_OK $WTB base=$(cat "$STATE/base_sha")"
else
  echo "WTB_FAILED"
fi
```

每個指令一樣存 exit code 與 log，只是檔名加 `base-` 前綴、寫進 `base-tests.tsv`：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
WTB=$(cat "$STATE/wt_base")
NAME=flutter-test; CMD='flutter test'   # 與 head 那次同名、同指令
( cd "$WTB" && eval "$CMD" ) > "$STATE/base-$NAME.log" 2>&1
RC=$?
printf '%s\t%s\t%s\n' "$NAME" "$RC" "$CMD" >> "$STATE/base-tests.tsv"
echo "base $NAME exit=$RC"
tail -n 15 "$STATE/base-$NAME.log"
```

**6c. 分清楚「測試失敗」「基線紅」與「環境跑不起來」**——三者都**絕不算通過**，
差別只在該由誰修。對 head 上**每一個** exit ≠ 0 的指令，依序判斷，第一個符合的
就是它的歸類：

1. **環境跑不起來（Summer 這邊的問題）**：`flutter`／`mise` 找不到（exit 127、
   `command not found`）、mise 報錯、`flutter pub get` 下載失敗、6a 的
   `WT_FAILED`、6b 拿不到測試指令（清單是空的、查不到 PR 的 base branch）。
2. **base 那邊跑不出可比的結果**：6b' 印出 `WTB_FAILED`，或 base 上同一個指令是
   上一項的環境問題 → 分不清是不是作者的錯，**當作環境跑不起來**。
3. **基線紅（base 的問題）**：base 上同一個指令也 exit ≠ 0（而且不是環境問題）。
   這不是作者造成的，送回只會讓 Rick/Morty 修不屬於這張單的東西、用掉重做額度。
4. **測試失敗（作者的問題）**：base 上同一個指令 exit 0、head 上卻失敗。**只有
   這一種算不通過的「測試失敗」。**

**前置指令壞了，後面的都不比**（fix round 1 I2）：同一邊（head 或 base）只要有一個
前置指令（`flutter pub get`、`mise trust`／`mise install` 這類準備環境、裝依賴的指令）
被歸為環境問題，**那一邊在它之後的所有指令一律算環境問題**，不拿來跟另一邊比——依賴
沒裝好，後面的 `analyze`／`test` 失敗只是連鎖反應，拿去比會被誤判成「測試失敗」或
「基線紅」。head 的前置壞了 → head 之後的失敗都是第 1 類；base 的前置壞了 → head
上失敗的指令都落在第 2 類。

分不清是哪一種時，**當作環境跑不起來**：送回給作者修不了 Summer 的環境，只會讓
Rick/Morty 白跑一輪、用掉重做額度。

**6d. 一定要移除 worktree**（測試過或沒過、中途出錯都要做；6b' 建過 base 的
worktree 也一起移除）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
BASE="/home/node/repos/$OWNER/$REPO_NAME"; ALL_GONE=yes
for F in wt wt_base; do
  [ -s "$STATE/$F" ] || continue
  W=$(cat "$STATE/$F")
  git -C "$BASE" worktree remove --force "$W"
  git -C "$BASE" worktree prune
  { [ ! -e "$W" ] && ! git -C "$BASE" worktree list | grep -qF "$W"; } || ALL_GONE=no
done
[ "$ALL_GONE" = yes ] && echo "WT_REMOVED"
```

沒印出 `WT_REMOVED` → 記進摘要（不影響驗收結果；下一輪 6a 會先清掉同名殘留）。

### 7. 合併條件與最後確認（2026-10-17 spec D 的條件，依序）

**最後確認（寫任何結果之前）**：重讀一次 PR：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
gh pr view "$PR_NUM" --repo "$REPO" --json headRefOid,mergeable,mergeStateStatus \
  --jq '"\(.headRefOid)\nmergeable=\(.mergeable)\nmergeStateStatus=\(.mergeStateStatus)"' > "$STATE/pr_final.txt" \
  && [ "$(head -n 1 "$STATE/pr_final.txt")" = "$(cat "$STATE/head_sha")" ] \
  && echo "SHA_SAME" || echo "SHA_MOVED_OR_FAILED"
cat "$STATE/pr_final.txt"
```

`SHA_MOVED_OR_FAILED`（驗收途中又有新 commit，或查詢失敗）→ **什麼都不貼**，
這張跳過，下一輪對新的 SHA 重驗。結果一定要綁在真的被驗過的那個 commit 上。
`mergeable` 變成 `UNKNOWN` → 一樣什麼都不貼，下一輪再看。

2026-10-17 設計（spec D）規定的五個合併條件，本 skill **照樣依序檢查、寫進
結果**，但本 skill 不 merge（條件 4 用上面 `pr_final.txt` 的值）。merge 由主機端
merge-poller 依它自己的條件（2026-10-23 spec B1）另外判斷，這裡寫的結果是給人類看的
紀錄，merge-poller 讀首行、head SHA 與 PR files（另外也看人類 `wm4n` 在目前 head 上的
Request changes：有就不 merge，R27）：

1. PR 作者是 bot 帳號（`wman-dev`／`wman-review`）、repo 在白名單、issue 沒有
   `needs-human`。**作者不是 bot 帳號不擋「通過」留言**，但要在結果裡寫「條件 1
   不成立：PR 作者是 <login>」，而且不通過時不送回（見步驟 8b）。merge-poller 只
   merge bot 作者的 PR（B1 條件 1），所以這種 PR 通過後仍由人類自己 merge；超過 12
   小時沒 merge，human-notifier 會提醒一次。例：`chainbreak#82` 的 PR #93 作者是
   `wm4n`（帳號分離前開的，body 雖然簽 Rick），就走這條。
2. 驗收對應的是 PR **目前的** head SHA——上面的最後確認。
3. Summer 自跑的測試全部 exit 0（步驟 6）。
4. 能合併：`mergeable` 是 `MERGEABLE`。`CONFLICTING`（`mergeStateStatus` 為
   `DIRTY`）→ 有衝突，算不通過，要求作者 rebase 到 PR 的 base 分支（`$STATE/base_ref`）最新版。其他
   `mergeStateStatus` 值照實寫進結果。
5. 每輪最多 merge 一張——本 skill 不 merge，寫「不適用：本 skill 不 merge；
   merge-poller 每個 repo 每天最多 3 張」。

### 8. 依結果寫回

先把結果歸成下列之一：

| 結果 | 條件（由上往下，第一個符合的） |
| --- | --- |
| **不通過** | 有任何 ❌、有 6c 歸類為「測試失敗」的指令（base 綠、head 紅）、或有衝突 |
| **無法驗證（基線紅）** | 沒有上一列任何一項，但有 6c 歸類為「基線紅」的指令（base 與 head 都紅） |
| **無法驗證（測試環境）** | 沒有上兩列任何一項，但測試因環境跑不起來，或拿不到測試指令（6b 清單是空的、查不到 PR 的 base branch） |
| **通過** | 每條驗收條件都是 ✅ 或 ❓、測試清單不是空的而且 head 上全部 exit 0、沒有衝突 |

「不通過」又碰上環境問題或基線紅時（例如有 ❌，而且某個指令 base 也紅）照
「不通過」處理，在理由裡註明哪些指令是 base 本身就失敗（不是作者造成的、不必修）、
哪些因環境沒跑成。**基線紅絕不算通過，也不算重做**（R18）。

#### 8a. 通過

**第 1 步：在 PR 貼結果**（第一行逐字照抄）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 驗收結果：通過（待自動 merge）\n\nhead SHA：%s\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
對照 issue #<N> 的驗收基準：<「✅ 需求共識」（附連結）／基準較弱（沒有 grill 共識）：<列出用了哪些來源>>

| # | 驗收條件 | 結果 | 依據 |
| --- | --- | --- | --- |
| 1 | <驗收條件原文> | ✅ 滿足 | <具體依據> |
| 2 | <驗收條件原文> | ❓ 需人類實機確認 | <為什麼只能實機確認> |

### 合併條件（依序）

1. PR 作者／白名單／needs-human：<成立／不成立：PR 作者是 <login>，不是 bot 帳號>
2. head SHA：測試前後讀到的是同一個 commit
3. 自跑測試：全部 exit 0（見下方）
4. 可合併：mergeable=MERGEABLE，mergeStateStatus=<值>
5. 每輪最多 merge 一張：不適用：本 skill 不 merge；merge-poller 每個 repo 每天最多 3 張
EOF
# PR 動到測試或測試指令（6b 產生的清單），有才印
if [ -s "$STATE/sensitive.tsv" ]; then
  printf '\n### ⚠️ 本 PR 動到測試或測試指令（刪除或改名測試檔、改測試設定、CLAUDE.md／AGENTS.md 動到測試指令字樣會由 merge-poller 擋下）\n\n'
  awk -F '\t' '{printf "- %s `%s`\n", ($1 == "D" ? "刪除" : $1), $NF}' "$STATE/sensitive.tsv"
fi
printf '\n### 測試（指令來源：%s；在上面那個 head SHA 的乾淨 checkout 執行）\n' "$( [ -s "$STATE/test_source" ] && cat "$STATE/test_source" || printf '未知' )"
while IFS="$(printf '\t')" read -r NAME RC CMD; do
  printf '\n`%s` → exit %s\n\n~~~\n' "$CMD" "$RC"
  tail -n 15 "$STATE/$NAME.log"
  printf '~~~\n'
done < "$STATE/tests.tsv"
# Summer 之前在舊 commit 上送過驗收的 Request changes 的話，寫明這則結果取代它
# （merge-poller 的衝突 review 不是驗收送回，排除）
if gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
  --jq '.[] | select(.user.login == "wman-pm" and .state == "CHANGES_REQUESTED") | select((.body // "") | split("\n") | (.[0] // "") | gsub("^[\t \u00a0\u3000]+"; "") | startswith("## 自動 merge 受阻：與 main 衝突") | not) | .id' | grep -q .; then
  printf '\n本結果取代 Summer 先前在舊 commit 上送出的 Request changes：那些項目已在上面這個 head SHA 重新驗過。GitHub 上那則 review 仍會顯示「Changes requested」；自動 merge 看的是本則結果與 head SHA，不看 Summer 的 review 狀態（2026-10-23 spec B1；只有人類 wm4n 綁在目前 head 的 Request changes 會擋，R27）。\n'
fi
cat <<'EOF'

本 skill 不 approve、不 merge：主機端 merge-poller 會依本結果與上面的 head SHA 自動 squash merge。<有 ❓ 時加一句：標 ❓ 的條目需要人類實機確認，自動 merge 不會等這一步；每日 merge 摘要會標出含 ❓ 的 merge，請在 merge 後實機確認，有問題再開 issue 或 revert。>
EOF
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
```

確認真的貼上了，並取得留言網址：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and ((.body // \"\") | startswith(\"## 驗收結果：通過（待自動 merge）\")) and ((.body // \"\") | contains(\"head SHA：$(cat "$STATE/head_sha")\"))) | .html_url"
```

沒有輸出 → 失敗，不做第 2 步，記進摘要（下一輪沒有紀錄會重驗）。

**第 2 步：在 issue 貼一行連結**（`<第 1 步的留言網址>` 換成上面印出的網址）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '驗收通過，待自動 merge：%s（head SHA %s）\n' '<第 1 步的留言網址>' "$(cut -c1-7 "$STATE/head_sha")"
printf '\n— By Summer (acceptance-review)\n'
} | gh issue comment "$NUM" --repo "$REPO" --body-file -
```

失敗 → 記進摘要，不重試（PR 上的結果已經在，下一輪冪等跳過，不會補貼）。

**第 3 步：不要自己 @ 人類，也不 merge**。第 1 步那則
`## 驗收結果：通過（待自動 merge）` 一貼上，就交給主機端 `merge-poller.sh` 依它的
條件 merge（R21）；通過不需要人類動作，`human-notifier.sh` 不通知，只在這則留言
超過 12 小時 PR 仍 open 時 @ 人類一次（pass-stale）。本輪摘要照常列出（不帶 @）。
（🕘 2026-10-17 到 2026-10-23：舊標題一貼上，human-notifier 就 @ 人類去 merge。）

**issue 的 `agent-done` 不動**：merge 之後 PR 的 `Closes #` 會自動關閉 issue。

#### 8b. 不通過

**第 1 步：先算重做次數**（任何寫入之前，見「重做次數」）。`rework=FAILED` →
**這張本輪什麼都不寫**（不送回、不留言），歸類「異常」，下一輪重算。少算一次
就可能多送回一次，查詢失敗絕不能當成 0。

**第 2 步：依情況選一條路**，從上往下第一個符合的：

| 情況 | 做什麼 |
| --- | --- |
| PR 作者不是 `wman-dev`／`wman-review` | **不送回**：只貼不通過留言（第 3 步），**第一行用 `## 驗收結果：不通過（作者非 bot，待人類處理）`**。`human-notifier.sh` 依這個標題通知人類處理；本 skill 不 @ |
| `rework_after` ≥ 2 | **不送回**：走「貼 `needs-human` 的固定順序」（第 5 類，留言要寫 SHA）。label 加不上就整張停手，連不通過留言都不貼；加上了，等 needs-human 留言貼好，再貼不通過留言（第 3 步）。@ 由 human-notifier 依 label 事件發 |
| `rework_after` < 2 | **送回**：下面 i → ii |

作者不是 bot 帳號時連 Request changes 都不送：`pr-review-poller` 對帳號分離
（2026-10-03）之前開的舊 PR 會認 PR body 的 bot 簽名（例如 `chainbreak#93`，作者
`wm4n`、body 簽 Rick），看到 Request changes 一樣會叫 bot 回來改，等於繞過「不送回」。

**「送回完成」的定義（2026-10-17 改，R17）**：目前的 head SHA 上存在 `wman-pm` 的
`CHANGES_REQUESTED` review。觸發作者不是本 skill 的事——主機端 `pr-review-poller.sh`
看到這則還沒被回應的 review，就會在 `bot-notify` 觸發作者跑 `pr-review-response`、
沒下文就重送、叫滿 3 次就 @ 人類。本 skill **不發任何 Discord 觸發**（原本的
「ii. 在 `bot-notify` 觸發作者」已移除：本 skill 跑在 `summer-pm` 的 thread，那則
觸發從來送不到 Rick／Morty）。

**送回的兩步（順序固定，任一步失敗就停在那一步，記進摘要）**：

i. **送 Request changes review，綁在驗過的 head SHA 上**，逐條列出未滿足的驗收
   條件、失敗的測試（指令與輸出結尾；base 也紅的指令另外標明不必修）、或要求
   rebase 到 PR 的 base 分支（`$STATE/base_ref`，例如 `main`）最新版解衝突。
   用 `gh api` 帶 `commit_id` 送，不用 `gh pr review`：後者綁的是送出當下的 head，
   驗收途中若有人 push，review 會落在沒驗過的 commit 上（final review M2）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '驗收不通過（head SHA：%s）\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
請在原分支修正下列項目：

- <驗收條件 #2：缺了什麼>
- <`flutter test` exit 1：失敗的測試與錯誤摘要>
- <有衝突：請 rebase 到最新的 <base_ref 的值> 解衝突>
EOF
printf '\n— By Summer (acceptance-review)\n'
} | gh api "repos/$REPO/pulls/$PR_NUM/reviews" -f commit_id="$(cat "$STATE/head_sha")" -f event=REQUEST_CHANGES -F body=@- --jq '.id'
gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and .state == \"CHANGES_REQUESTED\" and .commit_id == \"$(cat "$STATE/head_sha")\") | .id"
```

   第二個指令（綁在目前 head SHA 上的 `wman-pm` Request changes）有印出 id 才算
   成功——這就是「送回完成」。失敗 → 停，不留言；下一輪沒有紀錄會重驗、重送。

ii. **在 issue 貼不通過留言**（第 3 步）。

**第 3 步：在 issue 貼不通過留言**（三條路都要貼——它記下這個 SHA 驗過了，也是
重做次數的計數來源）。第一行逐字照抄，依路線二選一：PR 作者不是 bot 帳號 →
`## 驗收結果：不通過（作者非 bot，待人類處理）`（human-notifier 會通知人類）；其他兩條路（送回、第 5 類）→
`## 驗收結果：不通過`（不通知：送回由 pr-review-poller 觸發作者、第 5 類由 label 事件通知）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
HEADING='## 驗收結果：不通過'   # PR 作者不是 bot 帳號時改成 '## 驗收結果：不通過（作者非 bot，待人類處理）'
{
printf '%s\n\nhead SHA：%s\n\n' "$HEADING" "$(cat "$STATE/head_sha")"
cat <<'EOF'
PR：#<PR 編號>
驗收基準：<「✅ 需求共識」／基準較弱（沒有 grill 共識）：<來源>>

不通過的項目：
- <驗收條件 #2：缺了什麼>
- <`flutter test` exit 1：失敗摘要>
- <有衝突：需 rebase 到最新的 <base_ref 的值>>

重做次數：本次後 <rework_after>（agent-failed <a> 次＋驗收不通過 <b> 次，含本次），上限 2

處理：<已送 Request changes（綁上面這個 head SHA），主機端 pr-review-poller 會觸發 <Rick／Morty> 回原分支修正／PR 作者是 <login>，不是 bot 帳號，不自動送回，請人類處理／重做次數已達上限，已貼 needs-human，不再送回>
EOF
# 8d 續做時沒有跑測試、沒有 sensitive.tsv，這段自然不印
if [ -s "$STATE/sensitive.tsv" ]; then
  printf '\n⚠️ 本 PR 動到測試或測試指令：\n\n'
  awk -F '\t' '{printf "- %s `%s`\n", ($1 == "D" ? "刪除" : $1), $NF}' "$STATE/sensitive.tsv"
fi
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh issue comment "$NUM" --repo "$REPO" --body-file -
gh api "repos/$REPO/issues/$NUM/comments" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and (.body | startswith(\"## 驗收結果：不通過\")) and (.body | contains(\"head SHA：$(cat "$STATE/head_sha")\"))) | .html_url"
```

確認指令沒有輸出 → 立刻再貼一次；仍失敗 → 記進摘要。這則留言是冪等紀錄，也是
重做次數的計數來源：送回路徑上漏貼的話，這個 SHA 有 Summer 的 Request changes
卻沒有紀錄，下一輪步驟 3 的 R2 會走 8d 把它補上，不會重跑測試、不會再送第二則
review。（作者不是 bot、或第 5 類那兩條路沒有 review，漏貼時下一輪會重驗一次、
再貼一次。）

**不改任何 label**：issue 留著 `agent-done`。作者在原分支補 commit 後 PR head
會變，下一輪就會對新的 SHA 重驗。

#### 8c. 無法驗證（測試環境）

Summer 的環境跑不起來，作者修不了，所以**不送回、不算重做**，但也**絕不當成
通過**。在 PR 貼一則（第一行逐字照抄；不用 `## 驗收結果：不通過`，那會被
`backlog-triage` 算成一次重做）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 驗收結果：無法驗證（測試環境）\n\nhead SHA：%s\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
Summer 的測試環境跑不起來，這個 commit 沒有自跑測試的證據，不能算通過。

驗收條件逐條比對：<全部 ✅／❓ 的摘要>

跑不起來的原因：
- <`flutter analyze` exit 127：flutter: command not found／base branch 的 CLAUDE.md 找不到任何測試指令／查不到 PR 的 base branch>

需要人類處理（修好 Summer 的測試環境，或在 base branch 的 CLAUDE.md 寫明測試指令），之後在 Discord 指名重驗：「執行 acceptance-review skill <owner>/<repo>#<issue 編號>」。
EOF
if [ -s "$STATE/sensitive.tsv" ]; then
  printf '\n⚠️ 本 PR 動到測試或測試指令：\n\n'
  awk -F '\t' '{printf "- %s `%s`\n", ($1 == "D" ? "刪除" : $1), $NF}' "$STATE/sensitive.tsv"
fi
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
```

用 8a 第 1 步同樣的確認指令確認貼上了（`startswith` 的標題換成這一則的）。不要
自己 @ 人類：`human-notifier.sh` 會依這個標題通知。同一個 SHA 之後的排程掃描都會
跳過；只有人類指名單張時才重驗（見步驟 3 的 R4）。

#### 8c'. 無法驗證（基線紅）（Ruling R18）

head 上失敗的指令，在 base branch 上也失敗（6c 第 3 類）：base 本身就是紅的，
不是作者造成的，所以**不送回、不算重做**，也**絕不當成通過**。在 PR 貼一則
（第一行逐字照抄；不用 `## 驗收結果：不通過`，那會被 `backlog-triage` 算成一次
重做）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 驗收結果：無法驗證（基線紅）\n\nhead SHA：%s\n' "$(cat "$STATE/head_sha")"
printf 'base：`%s` @ %s\n\n' "$(cat "$STATE/base_ref")" "$(cut -c1-7 "$STATE/base_sha")"
cat <<'EOF'
下列指令在 base branch 上就失敗，PR head 上也失敗。這不是本 PR 造成的，不算重做；但 head 沒有全綠的證據，不能算通過。

驗收條件逐條比對：<全部 ✅／❓ 的摘要>
EOF
# 只列 base 與 head 都失敗的指令（base 紅、head 綠的是這張 PR 修好的，不列）
while IFS="$(printf '\t')" read -r NAME RC CMD; do
  [ "$RC" = 0 ] && continue
  HRC=$(awk -F '\t' -v n="$NAME" '$1 == n {print $2}' "$STATE/tests.tsv")
  [ "$HRC" = 0 ] && continue
  printf '\n`%s` → base exit %s、head exit %s（base 的輸出結尾）\n\n~~~\n' "$CMD" "$RC" "$HRC"
  tail -n 15 "$STATE/base-$NAME.log"
  printf '~~~\n'
done < "$STATE/base-tests.tsv"
cat <<'EOF'

需要人類處理：先讓 base branch 上這些指令恢復全綠（開 issue 或自己修）。修好後在 Discord 指名重驗「執行 acceptance-review skill <owner>/<repo>#<issue 編號>」；作者 rebase 之後 head SHA 變了，下一輪也會自動重驗。
EOF
if [ -s "$STATE/sensitive.tsv" ]; then
  printf '\n⚠️ 本 PR 動到測試或測試指令：\n\n'
  awk -F '\t' '{printf "- %s `%s`\n", ($1 == "D" ? "刪除" : $1), $NF}' "$STATE/sensitive.tsv"
fi
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
```

用 8a 第 1 步同樣的確認指令確認貼上了（`startswith` 的標題換成這一則的）。不要
自己 @ 人類：`human-notifier.sh` 會依這個標題通知。同一個 SHA 之後的排程掃描都會
跳過（R4）；base 修好之後**不會自動重驗**同一個 head SHA——要人類指名，或作者
rebase 讓 SHA 變。

#### 8d. 續做送回（步驟 3 的 R2）

上一輪在這個 SHA 送了 Request changes（送回已完成），之後的不通過留言沒貼成。
**不重跑測試、不再送第二則 review、不觸發作者**（作者由 `pr-review-poller` 依那則
review 觸發，跟這裡補不補記無關），只把紀錄補上：

1. **算重做次數**（「重做次數」一節）。`rework=FAILED` → 本輪不寫，歸類「異常」。
   `rework_after`（含這次還沒記下的不通過）≥ 2 → 照 8b 第 2 步的第 5 類那一條
   處理（升級）；理論上不會發生，上一輪送回時就是 < 2。
2. **取回上一輪的 review 內容**，拿它當不通過的項目：

   ```bash
   STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
   # 跟 3a (2) 一樣排除 merge-poller 的衝突 review
   gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
     --jq ".[] | select(.user.login == \"wman-pm\" and .state == \"CHANGES_REQUESTED\" and .commit_id == \"$(cat "$STATE/head_sha")\") | select((.body // \"\") | split(\"\n\") | (.[0] // \"\") | gsub(\"^[\t \u00a0\u3000]+\"; \"\") | startswith(\"## 自動 merge 受阻：與 main 衝突\") | not) | \"\(.submitted_at)\n\(.body)\n----\""
   ```

3. （2026-10-17 移除原本的「先補觸發，只在作者還沒回應時」：觸發改由主機端
   `pr-review-poller.sh` 看 review 決定，本 skill 不再發 Discord 觸發，R17。）
4. **貼不通過留言**：用 8b 第 3 步的模板與確認指令，「不通過的項目」照抄
   上面最新一則 review 的項目，「處理」寫「續做：上一輪已於 <review 時間> 送
   Request changes，本輪補記不通過紀錄」。這一步把冪等紀錄與重做計數補回來。
   失敗 → 記進摘要，下一輪 R2 會再試，並照下面第 5 步通報人類（每個 SHA 一次）。
5. **補記失敗時通報人類一次**：補記一直失敗，R2 每輪都會成立，重做次數一直少算
   一次，人類卻看不到原因。所以第 4 步失敗時，先查這個 SHA 通報過沒有：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
if RAW=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and (.body | split(\"\n\")[0] | sub(\"^\\\\s+\"; \"\") | startswith(\"## 驗收紀錄補記失敗\")) and (.body | contains(\"head SHA：$(cat "$STATE/head_sha")\"))) | .id"); then
  echo "already_notified=$(printf '%s\n' "$RAW" | grep -c .)"
else
  echo "already_notified=FAILED"
fi
```

- `already_notified=0` → 在 PR 貼一則（第一行逐字照抄），再用上面同一個查詢確認
  變成 1。不要自己 @ 人類：`human-notifier.sh` 會依這個標題通知一次。確認失敗就
  記進摘要（下一輪 `already_notified` 仍是 0，會再貼一次）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 驗收紀錄補記失敗\n\nhead SHA：%s\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
這個 SHA 上一輪已送 Request changes，但 issue #<issue 編號> 的「驗收結果：不通過」紀錄一直貼不上去（<錯誤摘要>）。

在補上之前，本 skill 每輪都會再試一次（不會重送 review），重做次數在補上前少算一次。請人類確認 Summer 的 GitHub 權限或 API 狀態，必要時手動在 issue 補記。
EOF
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
```

- `already_notified` ≥ 1 或 `FAILED` → 不再通報，只記進摘要。

（2026-10-17 移除「順序為什麼是先觸發、後留言」：那段處理的是「本 skill 的觸發
失敗、紀錄卻已貼上」會安靜卡住的問題。觸發改由 `pr-review-poller` 依 review 本身
發送之後，紀錄貼不貼得上都不影響作者收不收得到。）

#### 8e. 通報停滯（步驟 3 的 R3、R3'）

上一輪送了 Request changes，PR head 卻沒有新的 commit。兩種原因：

- **R3：作者已回應但未更新**——作者提問、反駁、認為超出範圍、
  `pr-review-response` 失敗，或 `start` 超過 16 小時沒有下文（poller 的重送與升級
  已經用完）。
- **R3'：作者未回應**——review 送出超過 16 小時，作者連 `start` 都沒貼
  （`pr-review-poller` 應已重送 3 次並 @ 過人類；這則是 poller 沒在跑時的備援）。

**絕不重送**：同一個 SHA 再送一次，只會得到同樣的回應，而且每送一次都
燒 Rick/Morty 的額度。改成讓人類知道，每個 SHA 最多通報 2 次（去重規則見步驟 3
的「停滯通報的去重」：先報「作者未回應」、作者之後才貼標記時，還能再報一次「作者已
回應但未更新」；同一種情況不重報）。（2026-10-18 改：原文「每個 SHA 只通報一次」與
實作不符。）

在 PR 貼一則（第一行逐字照抄）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
HEAD_SHA=$(cat "$STATE/head_sha")
# 跟 3a (4) 同一個查詢：這個 SHA 的停滯通報，一則一行（--paginate 時 jq 逐頁跑，不能在 jq 裡數）
STALL_Q=".[] | select(.user.login == \"wman-pm\" and (.body | split(\"\n\")[0] | sub(\"^\\\\s+\"; \"\") | startswith(\"## 驗收停滯：PR head 未更新\")) and (.body | contains(\"head SHA：$HEAD_SHA\"))) | .html_url"
# 先數貼之前有幾則：第 2 則通報時，第 1 則已經在了，只看「有沒有印出網址」會把貼失敗誤判成成功
if BEFORE=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate --jq "$STALL_Q"); then
BEFORE_N=$(printf '%s\n' "$BEFORE" | grep -c .)
{
printf '## 驗收停滯：PR head 未更新\n\nhead SHA：%s\n\n' "$HEAD_SHA"
cat <<'EOF'
上一輪驗收不通過（issue #<issue 編號> 的「驗收結果：不通過」留言），已送 Request changes 給作者。

停滯原因：<R3：作者已回應但未更新——pr-review-response 最新標記是 done／failed，或 start 已超過 16 小時，時間 <標記時間>／R3'：作者未回應——Request changes 於 <時間> 送出，超過 16 小時沒有任何 pr-review-response 標記（pr-review-poller 應已重送並通報；若沒收到它的通報，請確認 Mac mini 上 pr-review-poller 的 cron 有在跑）>。PR head 仍是上面這個 SHA，沒有新的 commit。

本 skill 不會對同一個 SHA 再送回。需要人類看作者在 review thread 的回覆（或確認作者 bot 是否正常），決定要回覆作者、重新觸發、自己修改，還是關閉 PR。作者推了新 commit 之後，下一輪會自動重新驗收。
EOF
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
# 重新數一次：剛好比貼之前多 1 則才算成功
if AFTER=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate --jq "$STALL_Q"); then
  AFTER_N=$(printf '%s\n' "$AFTER" | grep -c .)
  if [ "$AFTER_N" -eq $((BEFORE_N + 1)) ]; then
    echo "8e 成功：$(printf '%s\n' "$AFTER" | grep . | tail -n 1)"
  else
    echo "8e 失敗：貼之前 ${BEFORE_N} 則、之後 ${AFTER_N} 則"
  fi
else
  echo "8e 失敗：確認查詢失敗"
fi
else
  echo "8e 失敗：貼之前的計數查詢失敗，沒有貼"
fi
```

兩種原因共用同一個中性的第一行（3a 的 `stall_total`／`stall_after_mark` 只認它；
`human-notifier.sh` 也靠它通知人類），原因寫在內文。**只有印出「8e 成功：<網址>」才算
成功**：判斷方式是貼之前、之後各數一次這個 SHA 的停滯通報，之後必須剛好是之前加 1
（2026-10-18 改：原本只看「確認查詢有沒有印出網址」，第 2 則通報時第 1 則已經在了，
貼失敗也會印出網址、被誤判成成功）。不要自己 @ 人類；失敗 → 記進摘要，下一輪
R3／R3' 會再試。

## 重做次數

**重做次數 ＝ issue timeline 裡 `labeled agent-failed` 的次數 ＋ `wman-pm` 貼過、
第一行以 `## 驗收結果：不通過` 開頭的留言數**，和 `backlog-triage` 用同一個
公式，用 GitHub 上已有的紀錄現算，不另存狀態。

**整段放在同一次 Bash 呼叫裡跑**，開頭清空變數，不沿用上一張單的值：

```bash
REWORK=FAILED; FAILED_N=; REJECT_N=; EVENTS=
# timeline 會分頁；--paginate 時 --jq 逐頁各跑一次，所以每個事件輸出一行再數行數
if EVENTS=$(gh api "repos/$REPO/issues/$NUM/timeline" --paginate \
  --jq '.[] | select(.event == "labeled" and .label.name == "agent-failed") | "\(.created_at) agent-failed"'); then
  FAILED_N=$(printf '%s\n' "$EVENTS" | grep -c ' agent-failed$')
  # 兩個查詢都成功才換成數字；任何一個失敗 REWORK 都維持 FAILED，不會被當成 0
  if REJECT_N=$(gh issue view "$NUM" --repo "$REPO" --json comments \
    --jq '[.comments[] | select(.author.login == "wman-pm" and (.body | split("\n")[0] | sub("^\\s+"; "") | sub("\\s+$"; "") | startswith("## 驗收結果：不通過")))] | length'); then
    REWORK=$((FAILED_N + REJECT_N))
  fi
fi
echo "rework=$REWORK failed=$FAILED_N reject=$REJECT_N"
[ "$REWORK" != FAILED ] && echo "rework_after=$((REWORK + 1))"
```

**判斷用 `rework_after`（含本次這一次不通過）**：`rework_after ≥ 2` → 第 5 類，
不送回。這和 `backlog-triage` 一致——它判斷時，觸發判斷的那次 `agent-failed`
已經在 timeline 上、已經算進去；這裡觸發判斷的是本次不通過，它的留言還沒貼，
所以要加 1。結果是：從沒失敗過的單，第一次驗收不通過會送回一次；第二次（或
之前已經 `agent-failed` 過一次）就交給人類。

## Discord

**本 skill 不 @ 任何人**（2026-10-17 改，Ruling R17）：本 skill 由 usercron 在
`summer-pm` 的 thread 裡跑，原本寫的「在 `bot-notify` 發整輪那一則 @ 人類」與
「`pr-review` 觸發」實際上都送不到。要人類動手的事，一律靠 GitHub 上的固定標題
（與 `needs-human` label）讓主機端 `human-notifier.sh` 通知；觸發作者靠 Request
changes review 讓 `pr-review-poller.sh` 發。

一天跑 13 次，**只報有變化的事**，沒變化就不要每小時重報一樣的清單。**本輪摘要**
（回在觸發這一輪的地方，不帶任何 @）：本輪寫了什麼（通過、不通過、送回、續做送回、
升級、無法驗證（測試環境／基線紅）、通報停滯）、異常（GraphQL 報錯、找不到 PR、
多個候選 PR、步驟 3a 或重做次數查詢失敗、SHA 中途變動）、寫入失敗、**需要人類處理
但不在 human-notifier 通知範圍內的事**（缺 `needs-human` label、gh 帳號不對——見
「已知限制」），以及 **needs-human 已貼但沒有升級說明的
issue（逐張點名）**。只有跳過的時候，回一行就好：「acceptance-review：本輪無新結果
（agent-done <N> 張：已驗過 <a>、無法驗證（等環境修好）<b>、無法驗證（等 base 修好）
<g>、停滯（已通報）<c>、作者處理 review 中 <d>、等作者回應（pr-review-poller 觸發中）
<h>、等人類決定 <e>、待 GitHub 算合併狀態 <f>）」。各類分開計數，「無法驗證」「停滯」
「等作者回應」不可併進「已驗過」——那幾種是在等人，不是驗完了。掃全部時兩個 repo
都沒有 `agent-done`，也照這行回「agent-done 0 張」，不要完全不回。

摘要 ≤ 2000 字。完整依據留在 GitHub 留言裡，不要把留言全文貼進 Discord。

## 鐵則

- **本 skill 永不 approve、永不 merge**：通過時只貼結果，merge 由主機端
  `merge-poller.sh` 依結果與 head SHA 自動執行（2026-10-23 R21，不在本 skill）。
  Request changes 不是 approve，可以送。
- **merge-poller 寫的東西不是本 skill 的紀錄**：首行 `## 自動 merge 受阻：與 main 衝突`
  的 Request changes、第二行是費用或權限風險的 needs-human 留言，讀送回與升級紀錄時
  一律排除（3a、8a、8d）。
- **驗收要有可檢查的證據**：逐條依據加 Summer 自己在 PR head 跑的測試。測試
  跑不起來、或拿不到測試指令，絕不當通過，也不跳過。
- **head 失敗先對 base 跑同一組指令**（R18）：base 也紅歸「無法驗證（基線紅）」，
  不算重做、絕不算通過；只有 base 綠、head 紅才算作者的測試失敗。
- **測試指令從 base branch 讀**，不從 PR head 讀；PR 動到測試或測試指令要在結果
  裡標出來。
- **結果綁 head SHA**：每則結果都記 `head SHA：`，寫之前重讀一次 head，變了就
  什麼都不貼；同一個 SHA 只驗一次。
- **自動送回一定先算重做次數**：`rework_after ≥ 2` 一律改貼 `needs-human`，查詢
  失敗一律不送回，沒有任何路徑可以跳過。
- **送回 = 綁 head SHA 的 Request changes**（`gh api … -f commit_id=`）；觸發作者
  是 `pr-review-poller` 的事。同一個 SHA 只送回一次：送回後紀錄沒貼成就續做（8d），
  不重跑測試、不送第二則 review；作者回應了卻沒推新 commit 就通報停滯（8e），絕不重送。
- **貼 `needs-human` 的順序固定：加 label → 留言（第一行
  `## 需要人類決定（needs-human）`）**，@ 人類由 `human-notifier.sh` 依 label 事件發；
  加 label 失敗就整個停手。已有升級留言卻沒有 label，是人類處理完移除的，**絕不為
  同一件事重新加回**。
- **帶 `needs-human` 的 issue 一律不動**。
- **不改任何 label**：issue 留著 `agent-done`，不通過也不改；只有升級時加
  `needs-human`。
- **worktree 一定移除**，不在 base clone 上切分支。
- **不在 Discord @ 任何人**（人類與 bot 都不 @）：觸發與通知都由主機端 poller 發。
  固定標題的第一行逐字照抄，poller 才認得。
- **每個寫入都用指令確認**，確認不了就當失敗，不往下做，記進摘要。
- 白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo。

## 不做什麼

- **不 approve、不 merge 任何 PR**，也不關 PR、不刪分支。
- **不做 code review**：不評論程式碼風格、效能、測試覆蓋率、命名。
- **不改程式碼、不 push**：worktree 只拿來讀檔與跑測試。
- **不貼、不移除任何流程 label**；只有升級時加 `needs-human`。
- **不建 label**（缺 `needs-human` 時請人類建立）。
- **不替人類送回**：作者不是 bot 帳號、或重做達上限時，交給人類決定。
- **不逐張各發一則 Discord 摘要**；也不每小時重報沒有變化的事。
- **不發 Discord 觸發、不 @ 人類**：那是 `pr-review-poller.sh`、`human-notifier.sh`
  的事（R17）。

## 已知限制

- **Summer 的測試環境還沒實機驗證過**：Summer 容器裝了 mise＋Flutter，但沒
  確認過能在 PR checkout 裡跑完 `flutter test`。跑不起來時本 skill 走「無法驗證
  （測試環境）」（human-notifier 會通知人類），不會誤判通過。
- **送回、通知與 merge 依賴 Mac mini 上的三支 poller**（R17、R21）：
  - `pr-review-poller.sh` 沒在跑，送回的 review 不會有人觸發作者——R3' 在 16 小時後
    貼停滯通報當備援。
  - `human-notifier.sh` 沒在跑，固定標題與 `needs-human` 都不會有人 @ 人類，只剩本輪
    摘要（不帶 @）。
  - `merge-poller.sh` 沒在跑（包括回滾拿掉 cron 之後），通過的 PR 就停在 open；
    `human-notifier.sh` 會在通過留言超過 12 小時後 @ 人類一次（pass-stale），由人類
    自己 merge。
  上線 runbook 要先確認三支 cron 都在跑。
- **❓ 條目不擋自動 merge**（2026-10-23 起，R24）：❓ 是只能在實機確認的條目，擋下
  所有含 ❓ 的 PR 會讓 UI 類的工作全部回到等人類。通過的條件沒有改（spec B2「其他內容
  不變」），所以有 ❓ 的 PR 一樣會被自動 merge；每日 merge 摘要會標出含 ❓ 的 merge，
  由人類事後實機確認。
- **削弱測試由 merge-poller 擋，不由本 skill 擋**（R24'）：
  - 有改就擋：刪除測試檔、測試檔改名成非測試檔、修改 `analysis_options.yaml`／
    `dart_test.yaml`／`pytest.ini`／`jest.config.*`／`vitest.config.*`／
    `flutter_test_config.dart`（R25）。
  - 把檔案 rename 成或 rename 出 `CLAUDE.md`／`AGENTS.md` 也擋：等於新增或拿掉一份測試
    指令來源，純 rename 沒有 patch、看不出內容。
  - `CLAUDE.md`／`AGENTS.md` 只在 patch 的 `+`／`-` 行出現測試或檢查指令字樣時才擋：
    `flutter test`、`flutter analyze`、`dart test`、`dart analyze`、`npm test`、
    `npm run test`、`pnpm test`、`yarn test`、`pytest`、`unittest`、`node --test`、
    `jest`、`vitest`、`make test`、`測試指令`、`test command`（不分大小寫）。只改設計
    紀錄不擋。
  - GitHub 沒提供 patch 的文字檔也擋；二進位 asset 不擋。
  - 命中就升級 `needs-human`，誤擋由人類移除 label 放行。一般的新增或修改測試不擋——
    測試內容改弱（例如把 assert 改鬆）、或在 `CLAUDE.md` 用不在清單裡的寫法改掉測試
    指令，都比對不出來，只能靠 6b 的列表讓人類事後看。
- **不在 human-notifier 通知範圍內、只會出現在摘要的事**（摘要不帶 @，人類不會被
  叫）：缺 `needs-human` label、gh 帳號不是 `wman-pm`。前者是上線前置的問題，後者
  發生時 Summer 什麼都寫不進 GitHub，也沒有東西可通知。接受；runbook 的上線步驟會先
  確認 label 與帳號。（作者不是 bot 帳號的不通過，fix round 1 起改用獨立標題、由
  human-notifier 通知。）
- **R3' 與 poller 升級可能各通知一次**：bot 一直沒醒時，`pr-review-poller` 約 15
  小時後 @ 人類，本 skill 16 小時後再貼一則停滯通報（human-notifier 再通知一次）。
  後者是 poller 沒在跑時的備援，重複一次可接受。
- **作者在 review thread 回「問」或「反駁」之後要等人類**：本 skill 不回覆 review
  thread；作者貼 `done` 但沒推 commit，R3 會貼停滯通報讓人類接手（見 spec「已知
  限制」I3）。
- **送回後不通過留言貼失敗**：當場重貼一次；仍失敗，下一輪步驟 3 的 R2 看到「這個
  SHA 有 Summer 的 Request changes，之後卻沒有不通過紀錄」就走 8d 補記。R2 只看
  **目前的** head SHA：作者若在下一輪執行之前就推了新 commit，那一次就沒有記到，
  重做次數少算一次。下一輪最晚是一小時後；21:30 那一輪之後要等到隔天 09:30，
  這段期間窗口最長。要連續兩次寫入失敗才會發生，接受。
- **停滯靠 `pr-review-response` 的標記與時間判斷**：
  - 作者有貼標記：`done`／`failed`，或 `start` 超過 16 小時 → R3 通報「作者已回應
    但未更新」。`start` 在 5–16 小時之間時不通報：`pr-review-poller` 正在重送，摘要
    計入「等作者回應」。
  - 作者完全沒有標記：review 送出超過 16 小時 → R3' 通報「作者未回應」。作者若
    其實回應了、只是沒走 `pr-review-response`（例如在 PR 上手動回覆、沒有標記），
    本 skill 分不出來，一樣報成「作者未回應」，人類點進 PR 就看得到實情。
  - 每個 SHA 最多通報 2 則：R3' 先報過、作者之後才貼標記時，R3 還能再報一次；
    同一種情況不重報。
  - 「新的 start」的 5 小時對齊 `pr-review-poller` 的租約，「逾時的 start」的 16
    小時大於 poller 的 3 次重送；`pr-review-response` 自己的並行防護仍寫 2 小時（那支
    skill 不在本次改動範圍），只影響人類手動重觸發時能不能並行，不影響這裡的判斷。
- **R2 續做與作者的 `start` 標記**：R2 排在 R1 前面。作者在 Summer 貼不通過留言
  之前就開始處理時，R2 先成立，8d 只補記、不碰作者；之後作者推了新 commit 就走
  正常驗收，沒推就在 `done`／`failed` 之後由 R3 通報停滯。
- **PR 自己改了 `pubspec.yaml` 等設定，導致 `flutter pub get` 失敗**：目前一律歸為
  環境問題（6c 的前置指令規則），走「無法驗證（測試環境）」通知人類，**不會送回**給
  作者——Summer 分不清是 PR 改壞了依賴，還是自己的網路／快取壞了。人類看到再決定。
- **基線紅會蓋掉 PR 自己帶進的新失敗**（R18）：base 本來就紅、PR 又讓同一個指令
  多壞了別的地方，兩邊都 exit ≠ 0，一樣歸成基線紅——PR 造成的回歸被蓋掉、不會送回。
  但它**不會通過**，human-notifier 會通知人類；base 修好後重驗就看得出來。
- **基線紅之後 base 修好，同一個 head SHA 不會自動重驗**（R18）：R4 對
  `## 驗收結果：無法驗證（基線紅）` 只在人類指名時重驗；作者 rebase 讓 SHA 變了，
  下一輪也會重驗。
- **通過後 issue 那行連結貼失敗不會補**：PR 上的結果已經在，下一輪冪等跳過。
- **第 5 類升級後，人類移除 label、PR head 沒變**：本 skill 一直跳過這個 SHA，
  後續（送回、自己修、關 PR）完全由人類決定。
- **升級在「label 之後、留言之前」被中斷**：`needs-human` 已在身上，poller 都會
  跳過；`human-notifier.sh` 依 label 事件照樣 @ 人類（訊息註明「尚無說明留言」）。
  只是 issue 上缺說明留言；不補做（不知道當初卡在什麼），步驟 1 會在摘要點名列出。
  第 5 類這時也還沒貼不通過留言，人類移除 label 後同一個 SHA 會再驗一次、再升級
  一次，機率極低，接受。
- **找 PR 依賴 `Closes #N`**：沒寫時退到留言比對，兩者都落空才是「異常」。
- **usercron 必須設定 `timezone = "Asia/Taipei"`**：`30 9-21 * * *` 要以台北時間
  解讀。`timezone` 不設的話預設是 UTC（`CRONJOB.md` 欄位表），整個排程差 8 小時，
  會跑在台北時間 17:30–05:30。部署時在 `cronjob.toml` 確認這一項（時程與設定以
  `openab-ops` 的 `CRONJOB.md` 為準）。（2026-10-17 起本 skill 不再依賴「09 點那
  一輪」，見預檢段落的說明。）
