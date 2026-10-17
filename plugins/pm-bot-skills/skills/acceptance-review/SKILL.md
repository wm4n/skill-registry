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
  貼「驗收結果：通過（待人類 merge）」（head SHA、逐條依據、測試指令與輸出
  結尾），issue 貼一行連結，@ 人類 merge。不通過、有衝突或測試失敗 → 先算
  重做次數，未達 2 次用 Request changes 送回 bot 作者並在 Discord 觸發
  pr-review；達 2 次改貼 needs-human、不送回；作者不是 bot 帳號只留言。
  同一個 head SHA 只驗一次；送回做到一半會續做，作者回應了卻沒推新 commit
  就通報人類一次。永不 approve、永不 merge（自動 merge 暫緩，
  等人類決定是否開放）。帶 needs-human 的單一律不動，不改任何 label。
---

# Acceptance Review

> **本 skill 是 Rick/Morty 開完 PR 之後的收尾**：`agent-done` 代表 Rick/Morty
> 走完 `solo-feature-pipeline`、開好 PR、自我審查通過。本 skill 回答兩個
> 問題：**當初定案的需求，PR 真的做到了嗎**，以及**該 repo 規定的測試在 PR
> head 上真的全綠嗎**。第二個問題由 Summer 自己跑：chainbreak 沒有 CI，這是
> merge 前唯一的客觀證據，不能只信作者自稱「已自審」。
>
> ⏸️ **自動 approve＋merge 暫緩，等人類決定是否開放**（2026-10-17）：讓 bot
> 不經人工 review 就 merge 到 main，是整套自主閉環裡風險最高、最難回收的
> 一步，自動模式的安全分類器也以「Merge Without Review」擋下。所以這一版：
>
> - 通過 → 在 PR 貼驗收通過的結果（head SHA、逐條依據、測試指令與輸出），
>   **merge 留給人類**。人類只需確認那則結果、按一下 merge，不用再自己驗收。
> - 不通過 → 用 Request changes 送回原作者（這不是 approve，可以做），受
>   重做上限約束。
>
> **永不 approve、永不 merge**：本文件裡沒有任何 approve 或 merge 的指令，
> 也不要自己補上。

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
- Discord：`bot-notify` 頻道 `1526283579309690990`；人類
  `<@824092654060830770>`；Rick `<@1519868630064562278>`；Morty
  `<@1521431781641818202>`。
- 簽名一律逐字 `— By Summer (acceptance-review)`（開頭是 em dash U+2014
  「—」，不是連字號「-」）。直接複製本文件裡的字串，不要自己重打。

本 skill 靠下面幾個固定標題辨認留言，一律用「**留言內容的第一行，去掉前後
空白後，以這串完全相同的字串開頭**」判斷，並且只認作者是 `wman-pm` 的留言
（「✅ 需求共識」除外，見步驟 4）。寫這幾種留言時第一行必須逐字照抄、不可
改字或加前綴：

| 第一行 | 貼在哪 | 拿來做什麼 |
| --- | --- | --- |
| `## 驗收結果：通過（待人類 merge）` | PR | 冪等（記下驗過的 SHA） |
| `## 驗收結果：不通過` | issue | 冪等；**`backlog-triage` 靠它算重做次數** |
| `## 驗收結果：無法驗證（測試環境）` | PR | 冪等；Summer 環境跑不起來，不算重做 |
| `## 需要人類決定（needs-human）` | issue | 升級紀錄（R15，見下）；第二行區分兩種升級 |
| `## 驗收停滯：作者已回應但未更新` | PR | 每個 SHA 只通報一次停滯（見步驟 3） |

`## 驗收結果：不通過` 這串字一個字元都不能改：`backlog-triage` 算重做次數時
就是用它比對，改了就會少算，自動送回的迴圈就失去上限。舊版本貼過只有
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

   第二行看到 `needs-human` 才算成功。**這一步失敗就停在這裡**：不發 @、
   不留言、也不貼 `## 驗收結果：不通過`，什麼都不留下。因為什麼都沒貼，
   下一輪看到的還是原樣，自然會重試。
2. **在 `bot-notify`（`1526283579309690990`）@ 人類 `<@824092654060830770>`
   一次**，附 issue 連結，每張一句話寫明「卡在什麼、要決定什麼」。**整輪
   只發這一則 @**（和通過待 merge、缺 label 等要人處理的事合併，見
   「Discord」）。做法：處理每張單時先做完第 1 步，把要報的事記下來，整輪
   處理完再發這一則 @，發完才回頭對每張做第 3 步——每張單仍是
   label → @ → 留言的順序。
3. **在 issue 上留言**，第一行固定 `## 需要人類決定（needs-human）`，**第二行
   固定**是下面兩種之一，逐字照抄（之後靠第二行分辨是哪一種升級）。兩種用
   不同的模板，不要混用。

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
不加 label、不發 `pr-review` 觸發），只在摘要寫明並請人類處理。冪等與重做
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
所以整個 repo 都不寫。缺的 label 不要自己建（改 repo 設定屬於第 2 類），在整輪
那一則 @ 裡請人類建立。

## 流程（每張 issue 依序做）

**失敗只影響那一張**：對單一 issue 的任何查詢或寫入失敗，記下來、跳過這張，
繼續處理其餘的。**任何寫入都要用指令確認真的寫進去**（每一步附的確認指令），
確認不了就當作失敗、不往下做，記進摘要。

### 1. 先看 issue 本身

- 帶 `needs-human` → 不驗收、不送回、不留言，但先看是不是**升級做到一半**
  （R15 第 1 步加了 label，之後被中斷，issue 上沒有說明留言）：

  ```bash
  # 最後一次貼 needs-human 的人，以及 issue 上有沒有 Summer 的升級留言（任何簽名都算）
  gh api "repos/$REPO/issues/$NUM/timeline" --paginate \
    --jq '.[] | select(.event == "labeled" and .label.name == "needs-human") | "\(.created_at) \(.actor.login)"' | sort | tail -n 1
  gh api "repos/$REPO/issues/$NUM/comments" --paginate \
    --jq '[.[] | select(.user.login == "wman-pm" and (.body | split("\n")[0] | sub("^\\s+"; "") | startswith("## 需要人類決定（needs-human）")))] | length'
  ```

  - 最後貼 label 的是 `wman-pm`，**而且**第二個指令印 `0`（沒有任何 Summer 的
    升級留言）→ 升級做到一半：人類可能完全不知道這張在等他。摘要**點名**列出
    「needs-human 已貼但沒有升級說明」；**當天第一次排程（台北時間 09 點那一輪，
    `TZ=Asia/Taipei date +%H` 是 `09`）把它併進整輪那一則 @**，其他輪只列在摘要，
    不每小時 @。不補貼說明留言（不知道當初卡在什麼，補了只會亂寫）。
  - 其他情況 → 摘要列出「等人類決定中」。
  - 任一查詢失敗 → 摘要列出「等人類決定中（升級狀態查詢失敗）」。
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
        nodes { number url title state }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO_NAME" -F issue="$NUM" 2>&1); then
  echo "ERROR: GraphQL 查詢失敗 issue=${REPO}#${NUM}"
fi
echo "$GRAPHQL_OUTPUT"
```

- `issue` 一定用 `-F`（`Int!`），用 `-f` 會型別錯誤。`includeClosedPrs:true`
  讓已關閉的 PR 也回傳，下面才分得出「有 PR 但不是 OPEN」。
- **查詢本身報錯** → 歸類「異常」，記下原始錯誤，**不要靜默滑進 fallback**：
  schema 變動、權限問題會被 fallback 吃掉、沒人發現。
- 剛好一個 `state` 為 `OPEN` 的 node → 就是這張 PR。
- 沒有 node，或沒有一個是 `OPEN` → 走下面的 fallback。
- 超過一個 `OPEN` → 歸類「異常」，列出所有候選，不要自己猜一個。

**Fallback：留言文字比對**。在 issue `comments`（舊到新）裡找 Rick/Morty
收尾留言中的 `https://github.com/<owner>/<repo>/pull/<N>` 連結，取**最新**一則，
並用 `gh pr view` 確認那張 PR 是 `OPEN`。兩條路都落空 → 歸類「異常」，不要
憑標題湊一個 PR 編號。

### 3. 讀 PR 狀態，決定這一輪要不要驗

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
# 第一行是 head SHA，其餘是 key=value；只用 gh 內建的 --jq，不依賴另外裝 jq
gh pr view "$PR_NUM" --repo "$REPO" \
  --json url,state,author,headRefOid,mergeable,mergeStateStatus \
  --jq '"\(.headRefOid)\nurl=\(.url)\nstate=\(.state)\nauthor=\(.author.login)\nmergeable=\(.mergeable)\nmergeStateStatus=\(.mergeStateStatus)"' \
  > "$STATE/pr.txt" && head -n 1 "$STATE/pr.txt" > "$STATE/head_sha" \
  && grep -Eq '^[0-9a-f]{40}$' "$STATE/head_sha" && echo "head=$(cat "$STATE/head_sha")"
cat "$STATE/pr.txt"
```

沒有印出 `head=` 加 40 碼 SHA → 查詢失敗，歸類「異常」。

**3a. 一次撈齊判斷要用的事實**（整段放在同一次 Bash 呼叫裡跑）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
HEAD_SHA=$(cat "$STATE/head_sha")
FACTS_OK=yes; MARK=; REV_AT=; REC=; FAIL_AT=; STALL_N=
# gh 失敗要先接住再 sort：寫成 X=$(gh … | sort) 的話，失敗會被 sort 的 exit 0 蓋掉
# (1) 最新的 pr-review-response 標記：時間、種類（start／done／failed）、距今秒數
if RAW=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq '.[] | (.body | split("\n")[0] | sub("^\\s+"; "") | sub("\\s+$"; "")) as $h | select($h | startswith("<!-- pr-review-response:")) | "\(.created_at) \($h | capture("pr-review-response:(?<k>[a-z]+)") | .k) \((now - (.created_at | fromdateiso8601)) | floor)"'); then
  MARK=$(printf '%s\n' "$RAW" | grep . | sort | tail -n 1)
else FACTS_OK=no; fi
# (2) Summer 在目前這個 SHA 上最新一次 Request changes 的時間
if RAW=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and .state == \"CHANGES_REQUESTED\" and .commit_id == \"$HEAD_SHA\") | .submitted_at"); then
  REV_AT=$(printf '%s\n' "$RAW" | grep . | sort | tail -n 1)
else FACTS_OK=no; fi
# (3) 紀錄留言（固定標題表的前四種、而且有 head SHA 的），PR 與 issue 兩邊都撈
REC_JQ='.[] | select(.user.login == "wman-pm")
  | (.body | split("\n")[0] | sub("^\\s+"; "") | sub("\\s+$"; "")) as $h
  | select(($h | startswith("## 驗收結果：通過（待人類 merge）"))
      or ($h | startswith("## 驗收結果：不通過"))
      or ($h | startswith("## 驗收結果：無法驗證（測試環境）"))
      or ($h | startswith("## 需要人類決定（needs-human）")))
  | ((.body | capture("head SHA：(?<s>[0-9a-f]{40})") | .s) // "none") as $s
  | select($s != "none")
  | "\(.created_at)\t\($s)\t\($h)"'
if PR_REC=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate --jq "$REC_JQ") \
  && ISSUE_REC=$(gh api "repos/$REPO/issues/$NUM/comments" --paginate --jq "$REC_JQ"); then
  ALL_REC=$(printf '%s\n%s\n' "$PR_REC" "$ISSUE_REC" | grep . | sort)
  REC=$(printf '%s\n' "$ALL_REC" | tail -n 1)
  # 目前這個 SHA 最新一則「不通過」紀錄的時間
  FAIL_AT=$(printf '%s\n' "$ALL_REC" | awk -F '\t' -v s="$HEAD_SHA" '$2 == s && index($3, "## 驗收結果：不通過") == 1 {t = $1} END {print t}')
else FACTS_OK=no; fi
# (4) 這個 SHA 是不是已經通報過停滯
if RAW=$(gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq "[.[] | select(.user.login == \"wman-pm\" and (.body | split(\"\n\")[0] | sub(\"^\\\\s+\"; \"\") | startswith(\"## 驗收停滯：作者已回應但未更新\")) and (.body | contains(\"head SHA：$HEAD_SHA\")))] | length"); then
  STALL_N=$(printf '%s\n' "$RAW" | awk '{n += $1} END {print n + 0}')
else FACTS_OK=no; fi
echo "facts_ok=$FACTS_OK head=$HEAD_SHA"
echo "mark=$MARK"          # <時間> <start|done|failed> <距今秒數>，沒有標記就空白
echo "rev_at=$REV_AT"      # 目前 SHA 上 Summer 最新的 Request changes 時間，沒有就空白
echo "rec=$REC"            # 最新紀錄：<時間>\t<SHA>\t<標題>，沒有就空白
echo "fail_at=$FAIL_AT"    # 目前 SHA 最新「不通過」紀錄的時間，沒有就空白
echo "stall_n=$STALL_N"    # 目前 SHA 已通報停滯幾次
```

`facts_ok=no` → 判斷不了，**這張跳過**，歸類「異常」。不能當成「沒驗過」重跑：
會重送 review、多算一次重做。

`--paginate` 時 `--jq` 是逐頁各跑一次，`length` 會變成每頁一個數字，所以 (4)
用 `awk` 把各頁加總。

**3b. 依序判斷，第一個符合的就照做**（`mark` 的距今秒數 < 7200 叫「新的
`start`」，≥ 7200 叫「逾時的 `start`」；2 小時和 `pr-review-response` 的並行
防護、`pr-review-poller` 的 `PR_REVIEW_TTL_HOURS` 預設值相同，那邊改了這裡
跟著改。「參考時間」＝`rev_at`，空白時用 `fail_at`）：

| # | 條件 | 做什麼 |
| --- | --- | --- |
| R1 | `mark` 是新的 `start` | **跳過**：Rick/Morty 正在原分支補 commit，現在的 head 可能只改到一半，驗了只會把半成品判成不通過、白白用掉重做額度。摘要計入「作者處理 review 中」 |
| R2 | `rev_at` 有值，而且 `rec` 的 SHA 不是目前的 SHA（這個 SHA 沒有任何紀錄留言） | **送回做到一半**：上一輪送了 Request changes，之後的觸發或不通過留言沒做完（失敗或被中斷）。走 8d「續做送回」，**不重跑測試、不再送第二則 review** |
| R3 | `fail_at` 有值，`mark` 的時間晚於參考時間，而且 `mark` 是 `done`、`failed` 或逾時的 `start` | **停滯**：作者回應了（提問、反駁、說超出範圍、失敗，或做到一半卡住），PR head 卻沒變。`stall_n` 是 0 → 走 8e「通報停滯」；≥ 1 → 跳過，摘要計入「停滯（已通報）」。**絕不重送** |
| R4 | `rec` 的 SHA 等於目前的 SHA | **冪等**：標題是 `## 驗收結果：無法驗證（測試環境）` 而且這次是**指名單張**觸發 → 人類多半修好了環境，繼續往下驗；標題是無法驗證、排程觸發 → 跳過，摘要計入「無法驗證（等環境修好）」；其他標題 → 跳過，摘要計入「已驗過」 |
| R5 | `mergeable` 是 `UNKNOWN`（剛 push 完常見） | 跳過，下一輪再看，不算失敗。摘要計入「待 GitHub 算合併狀態」 |
| — | 以上都不符合 | 繼續步驟 4 |

幾點說明：

- R3 的參考時間用 `rev_at` 而不是 `fail_at`：送回的順序是 review → 觸發 → 留言，
  作者收到觸發後可能比 Summer 的不通過留言更早貼出 `start`；拿 review 時間比，
  才不會漏掉這一輪的回應。
- R3 只在 PR head **沒變**時成立：作者推了新 commit，SHA 就變了，`fail_at` 是空
  的，直接走 R4 以後的正常驗收。
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
[ -e "$WT" ] && /bin/rm -rf "$WT"
if git -C "$BASE" worktree add --detach "$WT" "$HEAD_SHA" \
  && [ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_SHA" ]; then
  echo "WT_OK $WT"
else
  echo "WT_FAILED"
fi
```

`WT_FAILED` → 環境跑不起來（見 6c），不是作者的錯。

**6b. 測試指令一律從 base branch 讀，不從 PR head 讀**：作者可以在同一張 PR
裡把 `CLAUDE.md` 的測試指令改弱或刪掉，從 PR head 讀等於讓被驗的人自己決定
怎麼驗。指令來自預設分支，**執行地點**才是 PR head 的 worktree：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
BASE="/home/node/repos/$OWNER/$REPO_NAME"; HEAD_SHA=$(cat "$STATE/head_sha")
if DEF=$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name') && [ -n "$DEF" ]; then
  printf '%s' "$DEF" > "$STATE/default_branch"
  for DOC in CLAUDE.md AGENTS.md; do
    git -C "$BASE" show "origin/$DEF:$DOC" > "$STATE/base-$DOC" 2>/dev/null && echo "BASE_DOC $DOC" || /bin/rm -f "$STATE/base-$DOC"
  done
  git -C "$BASE" cat-file -e "origin/$DEF:pubspec.yaml" 2>/dev/null && echo "FLUTTER_REPO"
  # PR 相對 base 動了哪些檔（A/M/D/R），給下面的「動到測試」檢查用
  git -C "$BASE" diff --name-status "origin/$DEF...$HEAD_SHA" > "$STATE/changed.tsv" && echo "DIFF_OK"
else
  echo "DEFAULT_BRANCH_FAILED"
fi
```

- 讀 `$STATE/base-CLAUDE.md`（以及 `base-AGENTS.md`，有的話）找該 repo 規定的
  測試／檢查指令。**不要讀 worktree 裡的 `CLAUDE.md`／`AGENTS.md`。**
- 印出 `FLUTTER_REPO`（base 有 `pubspec.yaml`）→ **不論文件怎麼寫，至少要跑
  `flutter analyze` 與 `flutter test`**（先 `flutter pub get`）。
- repo 有 mise 設定檔（`.mise.toml`／`mise.toml`）時先在 worktree 跑
  `mise trust` 與 `mise install`。
- **最後的指令清單是空的**（不是 Flutter，文件裡也找不到任何測試指令），或印出
  `DEFAULT_BRANCH_FAILED`、沒印出 `DIFF_OK` → 沒有測試證據，**絕不算通過**：
  照「環境跑不起來」處理（6c），結果走 8c「無法驗證」。

**PR 動到測試或測試指令，要讓人類看見**：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
# 動到 CLAUDE.md／AGENTS.md，或測試檔（test/、integration_test/、*_test.*、test_*）；D 開頭是刪除
awk -F '\t' '{p = $NF} p ~ /(^|\/)(CLAUDE|AGENTS)\.md$/ || p ~ /(^|\/)(test|tests|integration_test)\// || p ~ /(_test\.[a-z]+|(^|\/)test_[^\/]*)$/ {print}' \
  "$STATE/changed.tsv" > "$STATE/sensitive.tsv"
cat "$STATE/sensitive.tsv"
```

有輸出 → 在這張的結果留言（通過、不通過、無法驗證都一樣）加一段
「⚠️ 本 PR 動到測試或測試指令」，逐行列出（`D` 開頭的標明「刪除」）。這不會讓
結果變成不通過——改測試本來就常見——但人類 merge 前要看得到；刪掉測試檔、或
把 base 的測試指令改弱，人類可能就不該 merge。

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

**6c. 分清楚「測試失敗」與「環境跑不起來」**——兩者都**絕不算通過**，差別只在
該由誰修：

- **測試失敗（作者的問題）**：指令真的跑起來了，回報測試沒過、analyze 有問題。
- **環境跑不起來（Summer 這邊的問題）**：`flutter`／`mise` 找不到（exit 127、
  `command not found`）、mise 報錯、`flutter pub get` 下載失敗、6a 的
  `WT_FAILED`、6b 拿不到測試指令（清單是空的、查不到預設分支）。分不清是哪一種時，**當作環境跑不起來**：送回給作者修不了
  Summer 的環境，只會讓 Rick/Morty 白跑一輪、用掉重做額度。

**6d. 一定要移除 worktree**（測試過或沒過、中途出錯都要做）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
WT=$(cat "$STATE/wt"); BASE="/home/node/repos/$OWNER/$REPO_NAME"
git -C "$BASE" worktree remove --force "$WT"
git -C "$BASE" worktree prune
[ ! -e "$WT" ] && ! git -C "$BASE" worktree list | grep -qF "$WT" && echo "WT_REMOVED"
```

沒印出 `WT_REMOVED` → 記進摘要（不影響驗收結果；下一輪 6a 會先清掉同名殘留）。

### 7. 合併條件與最後確認（spec D 的條件，依序）

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

設計（spec D）原本規定全部成立才 merge 的五個條件，這一版**照樣依序檢查、寫進
結果**，只是最後不 merge（條件 4 用上面 `pr_final.txt` 的值）：

1. PR 作者是 bot 帳號（`wman-dev`／`wman-review`）、repo 在白名單、issue 沒有
   `needs-human`。**作者不是 bot 帳號不擋「通過」留言**（人類本來就要自己 merge），
   但要在結果裡寫「條件 1 不成立：PR 作者是 <login>」，而且不通過時不送回（見
   步驟 8b）。例：`chainbreak#82` 的 PR #93 作者是 `wm4n`（帳號分離前開的，body
   雖然簽 Rick），就走這條。
2. 驗收對應的是 PR **目前的** head SHA——上面的最後確認。
3. Summer 自跑的測試全部 exit 0（步驟 6）。
4. 能合併：`mergeable` 是 `MERGEABLE`。`CONFLICTING`（`mergeStateStatus` 為
   `DIRTY`）→ 有衝突，算不通過，要求作者 rebase 到最新 `main`。其他
   `mergeStateStatus` 值照實寫進結果。
5. 每輪最多 merge 一張——這一版不自動 merge，寫「不適用（自動 merge 暫緩）」。

### 8. 依結果寫回

先把結果歸成下列之一：

| 結果 | 條件 |
| --- | --- |
| **通過** | 每條驗收條件都是 ✅ 或 ❓、測試清單不是空的而且全部 exit 0、沒有衝突 |
| **不通過** | 有任何 ❌、測試失敗、或有衝突 |
| **無法驗證（測試環境）** | 沒有上一列任何一項，但測試因環境跑不起來，或拿不到測試指令（6b 清單是空的、查不到預設分支） |

「不通過」又碰上環境問題時（例如有 ❌，而且測試也跑不起來）照「不通過」處理，
在理由裡註明測試因環境沒跑成。

#### 8a. 通過

**第 1 步：在 PR 貼結果**（第一行逐字照抄）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 驗收結果：通過（待人類 merge）\n\nhead SHA：%s\n\n' "$(cat "$STATE/head_sha")"
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
5. 每輪最多 merge 一張：不適用（自動 merge 暫緩）
EOF
# PR 動到測試或測試指令（6b 產生的清單），有才印
if [ -s "$STATE/sensitive.tsv" ]; then
  printf '\n### ⚠️ 本 PR 動到測試或測試指令（merge 前請確認）\n\n'
  awk -F '\t' '{printf "- %s `%s`\n", ($1 == "D" ? "刪除" : $1), $NF}' "$STATE/sensitive.tsv"
fi
printf '\n### 測試（指令來自 base branch `%s` 的 CLAUDE.md，在上面那個 head SHA 的乾淨 checkout 執行）\n' "$(cat "$STATE/default_branch")"
while IFS="$(printf '\t')" read -r NAME RC CMD; do
  printf '\n`%s` → exit %s\n\n~~~\n' "$CMD" "$RC"
  tail -n 15 "$STATE/$NAME.log"
  printf '~~~\n'
done < "$STATE/tests.tsv"
# Summer 之前在舊 commit 上送過 Request changes 的話，寫明這則結果取代它
if gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
  --jq '.[] | select(.user.login == "wman-pm" and .state == "CHANGES_REQUESTED") | .id' | grep -q .; then
  printf '\n本結果取代 Summer 先前在舊 commit 上送出的 Request changes：那些項目已在上面這個 head SHA 重新驗過。GitHub 上那則 review 仍會顯示「Changes requested」，人類 merge 前可直接 dismiss。\n'
fi
cat <<'EOF'

自動 approve＋merge 暫緩中（等人類決定是否開放），請人類確認本結果後 merge。<有 ❓ 時加一句：merge 前請先實機確認標 ❓ 的條目。>
EOF
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
```

確認真的貼上了，並取得留言網址：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and (.body | startswith(\"## 驗收結果：通過（待人類 merge）\")) and (.body | contains(\"head SHA：$(cat "$STATE/head_sha")\"))) | .html_url"
```

沒有輸出 → 失敗，不做第 2 步，記進摘要（下一輪沒有紀錄會重驗）。

**第 2 步：在 issue 貼一行連結**（`<第 1 步的留言網址>` 換成上面印出的網址）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '驗收通過，待人類 merge：%s（head SHA %s）\n' '<第 1 步的留言網址>' "$(cut -c1-7 "$STATE/head_sha")"
printf '\n— By Summer (acceptance-review)\n'
} | gh issue comment "$NUM" --repo "$REPO" --body-file -
```

失敗 → 記進摘要，不重試（PR 上的結果已經在，下一輪冪等跳過，不會補貼）。

**第 3 步**：把這張列進整輪那一則 @ 人類的訊息（「驗收通過，待你 merge」附
PR 連結）。同一個 SHA 只會通過一次，所以每張 PR 只會因此 @ 一次。

**issue 的 `agent-done` 不動**：merge 之後 PR 的 `Closes #` 會自動關閉 issue。

#### 8b. 不通過

**第 1 步：先算重做次數**（任何寫入之前，見「重做次數」）。`rework=FAILED` →
**這張本輪什麼都不寫**（不送回、不留言），歸類「異常」，下一輪重算。少算一次
就可能多送回一次，查詢失敗絕不能當成 0。

**第 2 步：依情況選一條路**，從上往下第一個符合的：

| 情況 | 做什麼 |
| --- | --- |
| PR 作者不是 `wman-dev`／`wman-review` | **不送回**：只貼不通過留言（第 3 步），列進整輪那一則 @ 讓人類處理 |
| `rework_after` ≥ 2 | **不送回**：走「貼 `needs-human` 的固定順序」（第 5 類，留言要寫 SHA）。label 加不上就整張停手，連不通過留言都不貼；加上了，等那一則 @ 與 needs-human 留言照順序做完，再貼不通過留言（第 3 步） |
| `rework_after` < 2 | **送回**：下面 i → ii → iii |

作者不是 bot 帳號時連 Request changes 都不送：`pr-review-poller` 認 PR body 的
bot 簽名，看到 Request changes 一樣會叫 bot 回來改，等於繞過「不送回」。

**送回的三步（順序固定，任一步失敗就停在那一步，記進摘要）**：

i. **送 Request changes review**，逐條列出未滿足的驗收條件、失敗的測試（指令
   與輸出結尾）、或要求 rebase 到最新 `main` 解衝突：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '驗收不通過（head SHA：%s）\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
請在原分支修正下列項目：

- <驗收條件 #2：缺了什麼>
- <`flutter test` exit 1：失敗的測試與錯誤摘要>
- <有衝突：請 rebase 到最新 main>
EOF
printf '\n— By Summer (acceptance-review)\n'
} | gh pr review "$PR_NUM" --repo "$REPO" --request-changes --body-file -
gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and .state == \"CHANGES_REQUESTED\" and .commit_id == \"$(cat "$STATE/head_sha")\") | .id"
```

   第二個指令有印出 id 才算成功。失敗 → 停，不觸發、不留言；下一輪沒有紀錄會
   重驗、重送。

ii. **在 `bot-notify`（`1526283579309690990`）觸發作者**，一張 PR 一則，訊息
    只有這一行：

```
<@作者 ID> pr-review <owner>/<repo>#<PR 編號>
```

   作者 ID 由 PR author 的 login 決定：`wman-dev` → Rick `1519868630064562278`；
   `wman-review` → Morty `1521431781641818202`。例：
   `<@1519868630064562278> pr-review wm4n/chainbreak#93`。這是 @ bot，不是 @
   人類，不佔整輪那一則人類 @。觸發後作者走 `pr-review-response` 回原分支補
   commit。發送失敗 → 停，不留言，記進摘要。

iii. **在 issue 貼不通過留言**（第 3 步）。

**第 3 步：在 issue 貼不通過留言**（三條路都要貼——它記下這個 SHA 驗過了，也是
重做次數的計數來源）。第一行逐字照抄：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 驗收結果：不通過\n\nhead SHA：%s\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
PR：#<PR 編號>
驗收基準：<「✅ 需求共識」／基準較弱（沒有 grill 共識）：<來源>>

不通過的項目：
- <驗收條件 #2：缺了什麼>
- <`flutter test` exit 1：失敗摘要>
- <有衝突：需 rebase 到最新 main>

重做次數：本次後 <rework_after>（agent-failed <a> 次＋驗收不通過 <b> 次，含本次），上限 2

處理：<已送 Request changes，並在 Discord 觸發 <Rick／Morty> 回原分支修正／PR 作者是 <login>，不是 bot 帳號，不自動送回，請人類處理／重做次數已達上限，已貼 needs-human，不再送回>
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
- <`flutter analyze` exit 127：flutter: command not found／base branch 的 CLAUDE.md 找不到任何測試指令／查不到預設分支>

需要人類處理（修好 Summer 的測試環境，或在 base branch 的 CLAUDE.md 寫明測試指令），之後在 Discord 指名重驗：「執行 acceptance-review skill <owner>/<repo>#<issue 編號>」。
EOF
if [ -s "$STATE/sensitive.tsv" ]; then
  printf '\n⚠️ 本 PR 動到測試或測試指令：\n\n'
  awk -F '\t' '{printf "- %s `%s`\n", ($1 == "D" ? "刪除" : $1), $NF}' "$STATE/sensitive.tsv"
fi
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
```

用 8a 第 1 步同樣的確認指令確認貼上了（`startswith` 的標題換成這一則的）。列進
整輪那一則 @。同一個 SHA 之後的排程掃描都會跳過；只有人類指名單張時才重驗
（見步驟 3 的 R4）。

#### 8d. 續做送回（步驟 3 的 R2）

上一輪在這個 SHA 送了 Request changes，之後的觸發或不通過留言沒做完。**不重跑
測試、不再送第二則 review**，只把沒做完的補上：

1. **算重做次數**（「重做次數」一節）。`rework=FAILED` → 本輪不寫，歸類「異常」。
   `rework_after`（含這次還沒記下的不通過）≥ 2 → 照 8b 第 2 步的第 5 類那一條
   處理（升級，不觸發）；理論上不會發生，上一輪送回時就是 < 2。
2. **取回上一輪的 review 內容**，拿它當不通過的項目：

   ```bash
   STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
   gh api "repos/$REPO/pulls/$PR_NUM/reviews" --paginate \
     --jq ".[] | select(.user.login == \"wman-pm\" and .state == \"CHANGES_REQUESTED\" and .commit_id == \"$(cat "$STATE/head_sha")\") | \"\(.submitted_at)\n\(.body)\n----\""
   ```

3. **貼不通過留言**：用 8b 第 3 步的模板與確認指令，「不通過的項目」照抄上面
   最新一則 review 的項目，「處理」寫「續做：上一輪已於 <review 時間> 送
   Request changes，本輪補記不通過紀錄」。這一步把冪等紀錄與重做計數補回來。
   失敗 → 停，不觸發，下一輪 R2 會再試。
4. **補觸發，只在作者還沒回應時**：步驟 3a 的 `mark` 是空白，或 `mark` 的時間
   **不晚於** `rev_at` → 照 8b 步驟 ii 在 `bot-notify` 觸發作者（作者 ID 由 PR
   author login 決定；不是 `wman-dev`／`wman-review` 就不觸發）。`mark` 晚於
   `rev_at`，代表作者已經收到並回應過，不重發。

#### 8e. 通報停滯（步驟 3 的 R3）

作者回應了上一輪的 Request changes，PR head 卻沒有新的 commit。原因可能是作者
提問、反駁、認為超出範圍、`pr-review-response` 失敗，或 `start` 超過 2 小時沒有
下文。**絕不重送**：同一個 SHA 再送一次，只會得到同樣的回應，而且每送一次都
燒 Rick/Morty 的額度。改成讓人類知道，每個 SHA 只通報一次。

在 PR 貼一則（第一行逐字照抄）：

```bash
STATE="/tmp/acceptance-review/${OWNER}-${REPO_NAME}-${NUM}"
{
printf '## 驗收停滯：作者已回應但未更新\n\nhead SHA：%s\n\n' "$(cat "$STATE/head_sha")"
cat <<'EOF'
上一輪驗收不通過（issue #<issue 編號> 的「驗收結果：不通過」留言），已送 Request changes 給作者。

作者的回應：<pr-review-response 最新標記是 done／failed／start 且已超過 2 小時>，時間 <標記時間>，但 PR head 仍是上面這個 SHA，沒有新的 commit。

本 skill 不會對同一個 SHA 再送回。需要人類看作者在 review thread 的回覆，決定要回覆作者、自己修改，還是關閉 PR。作者推了新 commit 之後，下一輪會自動重新驗收。
EOF
printf '\n---\n— By Summer (acceptance-review)\n'
} | gh pr comment "$PR_NUM" --repo "$REPO" --body-file -
gh api "repos/$REPO/issues/$PR_NUM/comments" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and (.body | startswith(\"## 驗收停滯：作者已回應但未更新\")) and (.body | contains(\"head SHA：$(cat "$STATE/head_sha")\"))) | .html_url"
```

確認指令有印出網址才算成功。**成功才**把這張併進整輪那一則 @（「作者已回應但
沒有更新，需要你決定」附 PR 連結）；失敗 → 不 @，記進摘要，下一輪 R3 會再試
——先 @ 再留言的話，留言一直失敗就會每小時 @ 一次。

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

一天跑 13 次，**只報有變化的事**，沒變化就不要每小時重報一樣的清單：

1. **整輪那一則 @ 人類**（只在 `bot-notify`，整輪最多一則，有要人處理的事才發）：
   合併本輪所有要人類動手的事——新的 `needs-human` 升級、驗收通過待 merge、
   無法驗證（測試環境）、作者不是 bot 帳號的不通過、新通報的停滯（8e）、
   needs-human 已貼但沒有升級說明（步驟 1，只在當天 09 點那一輪）、缺
   `needs-human` label、gh 帳號不對。每項一句話加連結。≤ 2000 字，放不下就把
   超出的連結接在後續訊息，@ 只放第一則。
2. **`pr-review` 觸發**：每張送回的 PR 一則，@ 的是 bot，見 8b 步驟 ii。
3. **本輪摘要**（回在觸發這一輪的地方，不帶 @）：本輪寫了什麼（通過、不通過、
   送回、續做送回、升級、無法驗證、通報停滯）、異常（GraphQL 報錯、找不到 PR、
   多個候選 PR、步驟 3a 或重做次數查詢失敗、SHA 中途變動）、寫入失敗，以及
   **needs-human 已貼但沒有升級說明的 issue（逐張點名）**。只有跳過的時候，回
   一行就好：「acceptance-review：本輪無新結果（agent-done <N> 張：已驗過 <a>、
   無法驗證（等環境修好）<b>、停滯（已通報）<c>、作者處理 review 中 <d>、等人類
   決定 <e>、待 GitHub 算合併狀態 <f>）」。各類分開計數，「無法驗證」與「停滯」
   不可併進「已驗過」——那兩種是在等人，不是驗完了。掃全部時兩個
   repo 都沒有 `agent-done`，也照這行回「agent-done 0 張」，不要完全不回。

Summer 若就是在 `bot-notify` 執行，摘要與那一則 @ 可以合併成同一則，但合併後
必須 ≤ 2000 字，超過就把 @ 單獨成一則先發。完整依據留在 GitHub 留言裡，不要
把留言全文貼進 Discord。

## 鐵則

- **永不 approve、永不 merge**：自動 approve＋merge 暫緩，等人類決定是否開放
  （2026-10-17，安全分類器以「Merge Without Review」擋下）。通過時只貼結果、
  @ 人類 merge。Request changes 不是 approve，可以送。
- **驗收要有可檢查的證據**：逐條依據加 Summer 自己在 PR head 跑的測試。測試
  跑不起來、或拿不到測試指令，絕不當通過，也不跳過。
- **測試指令從 base branch 讀**，不從 PR head 讀；PR 動到測試或測試指令要在結果
  裡標出來。
- **結果綁 head SHA**：每則結果都記 `head SHA：`，寫之前重讀一次 head，變了就
  什麼都不貼；同一個 SHA 只驗一次。
- **自動送回一定先算重做次數**：`rework_after ≥ 2` 一律改貼 `needs-human`，查詢
  失敗一律不送回，沒有任何路徑可以跳過。
- **同一個 SHA 只送回一次**：送回做到一半就續做（8d），不重跑測試、不送第二則
  review；作者回應了卻沒推新 commit 就通報停滯（8e），絕不重送。
- **貼 `needs-human` 的順序固定：加 label → 單一 @ → 留言（第一行
  `## 需要人類決定（needs-human）`）**；加 label 失敗就整個停手。已有升級留言
  卻沒有 label，是人類處理完移除的，**絕不為同一件事重新加回**。
- **帶 `needs-human` 的 issue 一律不動**。
- **不改任何 label**：issue 留著 `agent-done`，不通過也不改；只有升級時加
  `needs-human`。
- **worktree 一定移除**，不在 base clone 上切分支。
- **整輪只 @ 人類一次，且只在 `bot-notify`**；`pr-review` 觸發 @ 的是 bot，另外算。
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

## 已知限制

- **Summer 的測試環境還沒實機驗證過**：Summer 容器裝了 mise＋Flutter，但沒
  確認過能在 PR checkout 裡跑完 `flutter test`。跑不起來時本 skill 走「無法驗證
  （測試環境）」並 @ 人類，不會誤判通過。
- **`pr-review` 可能被觸發兩次**：本 skill 在 Discord 觸發之外，若
  `pr-review-poller` 已部署，它看到 Request changes 也會觸發作者。
  `pr-review-response` 有 `start` 標記的並行防護，第二次會自己結束。
- **送回後不通過留言貼失敗**：當場重貼一次；仍失敗，下一輪步驟 3 的 R2 看到「這個
  SHA 有 Summer 的 Request changes 卻沒有紀錄」就走 8d 補記。補記之前若作者已經
  推了新 commit，那一次就沒有記到，重做次數少算一次——要連續兩次寫入失敗、而且
  作者在一小時內推完才會發生，接受。
- **停滯只靠 `pr-review-response` 的標記判斷**：作者沒有走那支 skill（例如人類
  手動在 PR 上回覆、沒有標記），本 skill 看不出作者回應過，這個 SHA 會一直算
  「已驗過」。Mac 組目前沒有部署 `pr-review-poller`，`start` 卡住也只能靠步驟 3
  的 2 小時逾時發現。
- **R2 續做與作者的 `start` 標記**：作者在 Summer 貼不通過留言之前就開始處理時，
  R1（新的 `start`）會先擋住；作者推了新 commit 就走正常驗收，沒推就在 `done`／
  `failed` 之後由 R2 補記、再由 R3 通報停滯。
- **通過後 issue 那行連結貼失敗不會補**：PR 上的結果已經在，下一輪冪等跳過。
- **第 5 類升級後，人類移除 label、PR head 沒變**：本 skill 一直跳過這個 SHA，
  後續（送回、自己修、關 PR）完全由人類決定。
- **升級在「@ 之後、留言之前」被中斷**：人類已被通知、`needs-human` 已在身上，
  poller 都會跳過，只是 issue 上缺說明留言；不補做（不知道當初卡在什麼）。步驟 1
  會點名列出這種 issue，當天 09 點那一輪併進 @，讓人類至少知道它在等人。第 5 類
  這時也還沒貼不通過留言，人類移除 label 後同一個 SHA 會再驗一次、再升級一次，
  機率極低，接受。
- **找 PR 依賴 `Closes #N`**：沒寫時退到留言比對，兩者都落空才是「異常」。
