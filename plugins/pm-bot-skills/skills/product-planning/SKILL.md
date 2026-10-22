---
name: product-planning
argument-hint: "[--property chainbreak|hangman]"
description: >-
  規劃下一步該做什麼：Summer 自己的新想法開成提案 PR 讓人類審方向，或收養
  人類開的 issue。需求來源有四個，
  GA4 數據只是其中一個可選的加分項（沒設定 GA4 也照樣有產出）：產品 repo
  自己的文件（README／CLAUDE.md／docs）、人類開的無流程 label backlog、
  卡在 ready-for-human 的單，以及（有設定時）GA4。由 usercron 定期
  觸發（訊息「執行 product-planning skill」，sender_name＝
  SummerPlanning，時程以 CRONJOB.md 為準），或人類在 Discord 提出同類請求（如「規劃一下需求」
  「看數據開單」「這週該做什麼」）時觸發：chainbreak 與 hangman 各自分析、
  不平均，比對兩個 repo 現有 issue 與所有提案 PR（含被人類關掉的）避免重複，
  找出寫得出驗收條件的需求，新開提案加收養合計（兩個 repo 加總、滾動 7 天）
  最多 3 張。新想法不直接開 issue：從 origin/main 切 proposal/<日期>-<slug>
  分支，只放一個 docs/proposals/ 提案檔，開標題「提案：」的 PR，內文結尾附回覆
  規則；人類 approve 後由 direction-proposal skill 開 issue。收養貼 grill-me、
  spec-only、pm-owned；ready-for-human 的單若落在 needs-human 五類就改貼
  needs-human 並留言說明（@ 人類由主機端 human-notifier 發，本 skill 不 @），
  不落在五類由 Summer 決定後收養。數據拿不到就明說，不推測冒充依據。
---

# Product Planning

> **本 skill 是責任鏈的起點，`backlog-triage` 接手後段**。兩條入口：
>
> - **Summer 自己的新想法 → 提案 PR**（5a，2026-10-23 起，openab-ops Ruling R22）：
>   人類只負責方向與花錢，所以 Summer 想做的新東西要先讓人類審方向，才投入 grill
>   與開發。這裡只開提案 PR；人類 approve、merge-poller merge 之後，由
>   `direction-proposal` skill（`materialize` 模式）開 issue。issue 該帶的標記
>   （下面三項）由那支 skill 負責。
> - **人類開的 issue → 收養**（5b）：人類開的單視為方向已確認，不走提案。
>
> 收養的（以及 `direction-proposal` 開的）每張 issue 要帶齊下列標記，各自餵給
> 不同的下游消費者，缺一不可：
> - **「這是 Summer 的單」的身份標記**——`summer-grill-responder` 用來判斷
>   該不該讓 Summer 搶答 Rick/Morty 的 grill 提問，只要符合三者之一就算：
>   author 是 `wman-pm`（Summer 的 GitHub 帳號，人類是 `wm4n`）、body 結尾
>   `— By Summer` 簽名、或帶 `pm-owned` label。**提案落地開的單**三者天然
>   具備；**收養人類開的單**作者是 `wm4n`、
>   body 也不能改寫成 Summer 的，所以只能靠 `pm-owned` label。漏標的後果不是
>   報錯，是 `summer-grill-responder` 不會觸發 Summer 回答，沒有任何錯誤訊息。
> - **`grill-me` label**——啟動 Rick/Morty 的 grill 流程。
> - **`spec-only` label**——`jira-grill` 用來判斷「規格共識後要不要跳過
>   工程階段」，是明確意圖標記，不依賴身份判斷。漏貼的後果同樣不是報錯，
>   是 grill 會多走一輪完整的工程階段提問——不會卡住或誤觸發，只是比
>   PM 單該有的流程多問一輪，交給 Rick/Morty 依 `jira-grill` 的分流各自
>   判斷怎麼答。

## 觸發與參數

`$ARGUMENTS`：

- 空 → **兩個 repo 都看**（chainbreak 與 hangman 各自完整跑一輪，順序
  不影響結果）。
- `--property chainbreak` 或 `--property hangman` → 只看那一個。

白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo，開提案、收養、
查現況都只對這兩個 repo 動作。

## 什麼時候找人：`needs-human` 五類

**要不要找人，唯一標準是 persona `Summer-AGENTS_v2.md` 的 `needs-human`
清單**，本 skill 不自創判準。五類的短標題（定義與細節以 persona 為準，
兩邊不一致時以 persona 為準）：

1. 費用
2. 權限與秘密
3. 對外發布或不可逆
4. 產品方向翻轉
5. 自動重做達上限

清單以外的事，產品問題由 Summer 自己決定，不要為了保險而丟給人類——
把本來可以自決的事推給人，就是讓整條自主閉環重新卡在人身上，這支 skill
改寫的目的正是要消除這個卡點。

### 貼 `needs-human` 的固定順序（順序不可換）

1. **加 `needs-human` label**（`gh issue edit --add-label needs-human`）。
   **這一步失敗就停在這裡**：不留言、什麼都不留下。因為什麼都沒貼，
   下一輪看到的還是原樣，自然會重試；若先貼了留言再發現 label 加不上，
   那則留言之後會被讀成「人類已處理完」。
2. **在 issue 上留言**，第一行固定寫 `## 需要人類決定（needs-human）`，接著
   寫明「卡在清單第幾類、需要人類決定什麼、有哪些選項」，以 `— By Summer`
   簽名結尾。這則留言同時是日後辨認「這張單 Summer 升級過」的記號（見
   步驟 3 的「人類處理完之後」）。
3. **來源是 `ready-for-human` 的單，最後才移除 `ready-for-human`**（來源
   是 3b 的單沒有這一步，它本來就沒有該 label）。
4. **不要自己 @ 人類**（2026-10-17 改，Ruling R17：原本第 2 步是「在 `bot-notify`
   @ 人類一次」，但本 skill 由 usercron 在 `summer-pm` 的 thread 裡跑，@ 送不到
   `bot-notify`）。主機端 `human-notifier.sh` 看到 `labeled needs-human` 事件就會
   在 `bot-notify` @ 人類一次，並附上第 2 步那則留言的連結。Discord 摘要不帶 @。

label 放第一步，是因為 label 一貼上，各 poller 就立刻開始跳過這張單、停止
燒額度；通知以 label 事件為準（不是留言），所以就算留言還沒貼，人類也會被通知。
**接受的風險**：若在 label 之後、留言之前被中斷，`needs-human` 已在身上（poller
都會跳過），human-notifier 照樣 @ 人類（訊息註明「尚無說明留言」），只是 issue
上少了那則說明——人類點進去看不到細節，不會卡死，也不需要補做。

**絕不重新加回 `needs-human`**：issue 上已有 Summer 的升級留言、但沒有
`needs-human` label，代表人類處理完並移除了它，不是「做到一半」。

**帶著 `needs-human` 的 issue，本 skill 一律不動**：不收養、不留言、不改
label。它在等人類，任何自動化介入都可能蓋過人類的決定，或在等人時繼續
燒額度。

## 流程

### 1. 檢查 GA4 是否有設定——可選，不是前提

兩個 property 各自用存在性檢查判斷（只輸出 `set` 或空字串，不會印出值）：

- chainbreak：!`echo "${GA4_PROPERTY_CHAINBREAK:+set}"`
- hangman：!`echo "${GA4_PROPERTY_HANGMAN:+set}"`

- 輸出 `set` → 該 property 有 GA4，**多一個數據來源**，用法見步驟 3 的
  GA4 小節。
- 輸出空白 → 該 property 沒有 GA4，**不是錯誤、不用停下來問人**，直接走
  步驟 3 的其他來源，需求的「數據依據」寫「無 GA4 數據（未設定）」。
- GA4 有設定但查詢失敗（報錯、查不到資料）→ 視同該 property 本輪沒有
  GA4，數據依據寫「GA4 查詢失敗，無法查證」並附上錯誤摘要，其餘來源照跑。

GA4 缺席時必須有替代來源，不能以「沒數據」為由收工——這支 skill 是整條
自主閉環的入口，它不提案也不收養，下游就沒有東西可跑。

> 上面兩行以驚嘆號加反引號開頭的檢查，會在 skill 載入時展開成 `set` 或空白。
> 若你看到的仍是未展開的原文（指令文字還在、沒有結果），自己用 Bash 把
> 那行指令跑一次再判斷，不要把「沒展開」當成「沒設定」。

### 2. 蒐集兩個 repo 現況

```bash
gh issue list --repo wm4n/chainbreak --state open --json number,title,body,labels,author,createdAt,comments
gh issue list --repo wm4n/hangman    --state open --json number,title,body,labels,author,createdAt,comments
gh pr list --repo wm4n/chainbreak --state merged --limit 20 --json number,title,mergedAt
gh pr list --repo wm4n/hangman    --state merged --limit 20 --json number,title,mergedAt
```

`comments` 要一次撈齊：下面候選的留言檢查與「人類處理完之後」判斷都要看
留言，全部用這份資料，不再逐張另外查。

開放 issue 用來**避免重複提案**：新想法先跟這份清單比對主題，明顯重疊的
不提，改成在既有 issue 底下留言補充佐證（既有 issue 若帶 `needs-human`
則不留言，見上）。近期 merged PR 用來確認「這個功能是不是已經做過了」——
訊號如果來自一個已經上線的修正，代表資料還沒反映最新版本，不是新需求。

**提案 PR 也要比對**（2026-10-23，spec A1）。Summer 開過的提案，不論狀態都撈：

```bash
for R in wm4n/chainbreak wm4n/hangman; do
  gh pr list --repo "$R" --author wman-pm --state all --limit 200 \
    --json number,title,state,headRefName,url \
    --jq '.[] | select((.headRefName // "") | startswith("proposal/")) | "\(.state)\t#\(.number)\t\(.title)\t\(.url)"'
done
```

新想法跟每一張比對主題，依 `state` 處理：

- `CLOSED`（關掉、沒有 merge）→ **人類說了不做**。同一件事不再提，換個說法也不提。
  這是人類唯一的「不做」訊號，不會另外留言，漏讀它就會一再拿同一件事去煩人類。
- `OPEN` → 還在等人類審，不重複提。
- `MERGED` → 方向已核准，issue 已開或即將由 `direction-proposal` 開，不重複提。

查詢失敗 → 這一輪不開任何新提案（收養照常），摘要寫明：沒有這份清單，就分辨不出
哪些是人類拒絕過的。

**做到一半的提案**：`gh api "repos/$R/git/matching-refs/heads/proposal/" --jq '.[].ref'`
列出的分支，扣掉上面清單（任何 state）的 `headRefName`，剩下的是「分支推上去了、PR 沒
開成」。這種分支照 5a 第 5 步把 PR 補開，不要換 slug 另開一份。

#### label 預檢——開提案、收養或升級之前先確認 label 存在

對每個 repo，在做任何開提案、收養或 `needs-human` 升級**之前**先跑：

```bash
gh label list --repo wm4n/chainbreak --limit 200 --json name --jq '.[].name'
gh label list --repo wm4n/hangman    --limit 200 --json name --jq '.[].name'
```

`--limit 200` 不能省：`gh label list` 預設只回 30 個，repo 的 label 多一點就會
把存在的 label 誤判成缺漏。要確認的是 `grill-me`、`spec-only`、`pm-owned`
（收養用）與 `needs-human`（升級用）。

某個 repo 缺這四個其中任一個 → **這一輪在那個 repo 不收養、不升級、不開新
提案**，該 repo 的相關候選全部跳過。理由：收養是先留言後加 label，若先貼了
留言才發現 label 加不上去，issue 上會留下一則「已收養」的留言，實際上卻沒有
任何 label、沒有任何下游動作，是一則說謊的紀錄；提案核准後 `direction-proposal`
開的 issue 要帶 `grill-me`／`spec-only`，缺 label 的 repo 先提了，核准後也落不了地。

缺的 label 不要自己建（改 repo 設定屬於 `needs-human` 第 2 類），改成：摘要寫明
哪個 repo 缺哪個 label，請人類建立。摘要不帶 @（見「已知限制」：這件事不在
human-notifier 的通知範圍內）。
`gh label list` 本身報錯（網路、權限）→ 同樣當作該 repo 本輪不能收養或升級，
跳過並在摘要寫明是「label 查詢失敗」，不要憑印象當作 label 存在。
**開提案也在這個預檢之內**：該 repo 缺 label（或查詢失敗）時本輪就不在那個 repo
開提案，摘要裡說明。

### 3. 找需求來源——四選項，全部都讀、不必等 GA4

#### 3a. 產品 repo 自己的文件

不 clone，用 `gh api` 讀原文（raw 格式，不需要自己解 base64）：

```bash
gh api -H "Accept: application/vnd.github.raw+json" repos/wm4n/chainbreak/contents/README.md
gh api -H "Accept: application/vnd.github.raw+json" repos/wm4n/chainbreak/contents/CLAUDE.md
# 列出 docs/ 檔案，再挑 roadmap／規劃類的讀
gh api repos/wm4n/chainbreak/contents/docs --jq '.[].path'
```

hangman 同理把 repo 名換掉。找 roadmap、TODO、「之後要做」「待辦」「已知
限制」這類文字，對照步驟 2 的 open issue 與 merged PR，挑出**文件寫了要做、
但 backlog 裡沒有、也沒有做過**的項目。檔案不存在（404）是正常情況，
跳過即可，不當成錯誤。

#### 候選的留言檢查（3b、3c 共用）

**最先看 opt-out（排在下面所有檢查之前）**：issue body 裡有任何一行，去掉前後
空白後**完全等於** `<!-- pm-skip -->`，代表人類明確要 Summer 別碰這張單——
**3b、3c 一律不動**：不收養、不升級 `needs-human`、不留言、不改 label，連 5b 的
「續做」也不補。這是人類手動寫進 body 的標記（寫成 HTML 註解，GitHub 畫面上
看不到，不會干擾閱讀），Summer 不會自己寫、也不會移除。它只擋「之後」的動作：
已經收養完成的單（`pm-owned` 等 label 已在）不會因此被撤銷，要撤銷由人類自己
移除 label。只有「完全等於」才算，正文裡提到這串字（例如在說明裡引用）不算。
（2026-10-18 新增，final review M3。選 body 字串而不是新 label：global
constraints 規定新 label 只有 `needs-human`、`pm-owned`；多一個 label 還得兩個
repo 都建、納入 label 預檢，body 字串零設定、人類隨手可加。）

接著用步驟 2 取回的 `comments`，對每張候選先看 Summer（作者 `wman-pm`）留過
什麼。**下面的檢查依序進行，第一個符合的就採用，不再往下看**：

1. **已有 `## Summer 收養此單` 留言** → 不是全新候選，轉去 5b 的「續做」路徑
   處理（符合續做條件才補，不符合就不動）。續做**不經過、也不受**步驟 4 的
   預算與排序。
2. **已有 `依人類決定不收養` 留言** → 以**最新一則** `依人類決定不收養` 留言為
   錨點，看它**之後**有沒有「推翻留言」：作者是 `wm4n`，而且留言第一行去掉前後
   空白（含全形空白）後，**整行完全等於**下列任一字串，句尾最多允許一個全形或
   半形的句號或驚嘆號（`。` `.` `！` `!`）：
   - `做`
   - `收養`

   例：`做`、`收養`、`做。`、`收養!`。**不算**推翻的例子：`做 不了`、`做不了`、
   `做：這個值得做`、`收養，先做手機版`、`做!!`、`我覺得可以`、`好`——第一行
   多任何一個字都不算。要補充理由請寫在第二行以後。人類對這張單的其他討論、
   補充、提問都不會讓它重新被收養。

   用下面這段判斷（不要自己目測；字串規則只寫在這裡的 jq，與上面的說明一致）。trim 用
   明確字元類（tab、空白、NBSP、全形空白）而不用 `\s`、空 body 先補空字串：`gh --jq`
   的 gojq 與系統 jq 對 `\s` 與 `"" | split` 的行為不同，寫明確才能兩邊結果一致：

   ```bash
   # 印出 REVERSED <推翻留言網址>、NOT_REVERSED（有錨點、沒有推翻）或 NO_ANCHOR；
   # 查詢失敗（指令非 0）→ 當作沒有推翻，跳過、不動。REPO／NUM 的拆法同 5b
   gh issue view "$NUM" --repo "$REPO" --json comments --jq '
     [.comments[] | {a: .author.login, at: .createdAt, u: .url,
        h: ((.body // "") | split("\n") | (.[0] // "") | gsub("^[\t \u00a0\u3000]+|[\t\r \u00a0\u3000]+$"; ""))}]
     | ([.[] | select(.a == "wman-pm" and (.h | startswith("依人類決定不收養"))) | .at] | max) as $anchor
     | if $anchor == null then "NO_ANCHOR"
       else ([.[] | select(.a == "wm4n" and .at > $anchor and (.h | test("^(做|收養)[。.！!]?$")))] | first) as $r
         | if $r == null then "NOT_REVERSED" else "REVERSED \($r.u)" end
       end'
   ```

   - **沒有推翻留言** → 跳過、不動。
   - **有推翻留言** → 直接走收養（算步驟 4 的預算、做 5b 三個動作），收養理由
     引用那則推翻留言。**不要**套用下面「人類處理完之後」：那段讀的是升級留言
     之後的第一則 `wm4n` 留言，讀到的正是當初那句「不做」。五類檢查只看推翻留言
     之後出現的、新的不同卡點（同「人類處理完之後」第一點）；預算不夠就留到
     下一輪，不另貼任何留言。
   （2026-10-18 改：原本「它之後只要有任何更新的 `wm4n` 留言」就算推翻，並「依
   那則留言照『人類處理完之後』重新判斷」。人類隨口補一句就會被當成推翻、可能在
   沒有明確同意下收養；而「人類處理完之後」的錨點是升級留言，會讀回原本的「不做」，
   再貼一則重複的 `依人類決定不收養`。改成只認明確表態，推翻就是收養，這兩個
   問題都不會再發生。）
   （🕘 同日稍後再收緊：第一版允許「`做`／`收養` 後接冒號或空白」，`做 不了` 這種
   寫法也會被當成推翻；改成整行完全等於、只容許一個句尾標點，並附 jq 讓判斷不靠目測。）
3. **已有 `## 需要人類決定（needs-human）` 留言、目前沒有 `needs-human`
   label** → 這代表**人類已處理並移除了 label**。**絕不重新加回**。處理方式
   見下面「人類處理完之後」。
4. 以上都不符合 → 全新候選，照下面 3b／3c 的篩選走。

**留言怎麼比對**：上面這幾個固定標題（`## Summer 收養此單`、
`## 需要人類決定（needs-human）`、`依人類決定不收養`）一律用「留言內容的
第一行，去掉前後空白後，以這串**完全相同的字串**開頭」判斷，所以寫這幾種
留言時第一行必須逐字照抄、不可改字或加前綴。

**人類處理完之後（3b、3c 都適用）**：在 Summer 的升級留言**之後**，若出現
`wm4n` 的留言，且單上沒有任何流程 label（`ready-for-human` 例外，見下），
這張單重新成為候選——Summer **照人類在留言裡寫明的決定做**。（升級時若
移除 `ready-for-human` 那步當時失敗，單上可能還留著它，視同沒有流程
label。）Summer 的升級留言之後沒有 `wm4n` 的留言，一律跳過、不動——人類
只是拿掉 label 但沒說決定，不能替他腦補。

- **升級時那一類，視為已解決。** 人類既然在留言裡就那個卡點做了決定，Summer
  不得為同一件事重新升級——否則等於把人類剛批准的事又擋回去，和「絕不重新
  加回 `needs-human`」自相矛盾。五類檢查只用來看**新出現的、不同的卡點**
  （不同類，或同類但不同的具體事項）；只有出現這種新卡點，才可以重新走
  升級順序。
- **人類決定「可以做」** → 走正常的收養路徑（算預算、5b 三個動作），收養
  理由裡引用人類的決定。
- **人類決定「不做」** → Summer **不收養、不動 label**，只**貼一次**簡短
  留言，第一行固定寫 `依人類決定不收養`，其後一句話說明依據哪則留言，以
  `— By Summer` 簽名結尾。這則留言的用途是讓之後每一輪都能認出「這張單已
  有結論」而跳過，不要每週重新評估一次；上面的留言檢查第 2 項看到它就略過，
  直到人類在它之後貼出明確的推翻留言（第一行整行就是 `做`／`收養`，格式見第 2 項）
  為止。

#### 3b. 人類開的 backlog

先套用上面的「候選的留言檢查」（含 opt-out）。步驟 2 的 open issue 裡，挑出
**沒有任何流程 label** 的：不含 `grill-me`、`grill-me-*`（含 `grill-me-done`）、
`ready-for-agent`、`ready-for-human`、`agent-*`（`agent-active`／`agent-failed`／
`agent-done`…）、`needs-human`、`pm-owned`。這些就是人類開了、但還沒有任何 bot
接手的單。含 `ready-for-human` 的歸 3c，已有 `pm-owned` 的是已收養過，都不重複
處理。

另外**作者必須是人類 `wm4n`**（看步驟 2 取回的 `author.login`，條件是
`author.login == "wm4n"`）：bot 自己開的單由各自的流程負責，收養它們等於
Summer 把別的 bot 的工作搶過來；其他帳號（外部貢獻者、已刪帳號 `ghost`、
其他自動化）開的單不是產品擁有者提出的需求，Summer 也不收養。（2026-10-18 改，
final review M3：原文是「作者不是 bot 帳號」，等於任何第三方開的單都會被收養進
開發流程。）不收養的單也不升級，一律不動。

#### 3c. `ready-for-human` 的單

```bash
gh issue list --repo wm4n/chainbreak --label ready-for-human --state open \
  --json number,title,body,labels,comments,author,createdAt
gh issue list --repo wm4n/hangman    --label ready-for-human --state open \
  --json number,title,body,labels,comments,author,createdAt
```

先套用上面的「候選的留言檢查」（含 opt-out）。這是人類標記「要人來決定」而一直
沒人處理的單。**先過濾**，下列任一成立就跳過、不動：同時帶 `needs-human`、
`grill-me*`（含 `grill-me-done`）、`agent-*`、`ready-for-agent`、`pm-owned`
（代表另有流程或人類已接手，貼標記會與之衝突）；或作者是 bot 帳號
（`wman-dev`、`wman-review`、`wman-pm`）。通過的才逐張讀完 body 與 comments，
判斷**卡住的那個決定**落不落在 `needs-human` 五類：

- **落在五類** → 走「貼 `needs-human` 的固定順序」（加 label、留言、最後移除
  `ready-for-human`；@ 人類由 human-notifier 發；先加後移除——反過來中途失敗，
  這張單兩個 label 都沒有，從此沒有任何自動化找得到它）。這**不計入**預算。
- **不落在五類** → Summer 以 PM 身分把決定做掉，在收養留言裡寫明
  「原本卡在什麼決定、Summer 的決定、理由」（帶 `— By Summer`），然後
  走「收養」流程。收養**計入**預算（見步驟 4）。

3b 的 backlog 單（作者是 `wm4n` 的）也一樣先過五類：落在五類的**不收養**（收養
等於把它送進 Rick/Morty 的開發流程），改走「貼 `needs-human` 的固定順序」（沒有
`ready-for-human` 要移除，那一步略過）；不落在五類才考慮收養。

#### 3d. GA4（僅限有設定的 property）

```bash
node /etc/openab/ga4/ga4-report.js --property "$GA4_PROPERTY_CHAINBREAK" --days 28 --preset overview
node /etc/openab/ga4/ga4-report.js --property "$GA4_PROPERTY_HANGMAN"    --days 28 --preset overview
```

只對步驟 1 輸出 `set` 的 property 跑。`--preset` 另有 `pages`（頁面／功能點
流量）、`retention`（留存），看想找的訊號決定用哪個，也可以對同一個
property 跑多個 preset。追問細節用 `--raw-request '<runReport JSON>'` 自組
查詢，不要因為 preset 不夠細就放棄深挖。

**chainbreak 與 hangman 是兩個獨立產品**，任何統計（成長率、留存率、事件
次數）一律各自報告，**不做兩者平均或加總**——平均出來的數字對應不到任何一個
真實產品，會誤導後面的判斷。GA4 的訊號（掉點、沒人用的功能、卡住的漏斗）
拿來佐證或補強 3a／3b 找到的想法，也可以單獨成為新想法。

### 4. 篩選：驗收條件寫得出來才算數，且不超過上限

把 3a–3d 的候選項各自過兩道檢查：

1. **五類檢查**：這項需求本身落在 `needs-human` 五類嗎？落在的不要開成
   提案（新想法）或收養（人類的單，見 3b／3c）。新想法的話，
   在 Discord 摘要裡單獨列一行「需人類決定，未開提案：<一句話>」即可。
2. **可驗證的驗收條件**：每項都要能寫出具體、可驗證的驗收條件，**不限於
   GA4 指標**，功能性條件也算（例如「設定頁新增 X 開關，關閉後 Y 不再
   出現」「結算頁跳出率從 X% 降到 Y% 以下」）。寫不出這種條件的項目直接
   捨棄，不提案、不收養、不硬湊一個模糊的驗收條件充數。

**上限：新開提案加收養，兩個 repo 加總、滾動 7 天最多 3 張**，不是每個 repo
各 3 張，也不是「這一輪」3 張。本 skill 依 usercron 排程（以 CRONJOB.md 為準）定期跑，
但人類也能在 Discord 隨時手動觸發，只算「這一輪」的話手動多跑幾次就能繞過每週上限。所以**開提案
或收養之前先算最近 7 天已用掉多少**（兩個 repo 加總）。提案在**開 PR 時**就計入，
之後被核准、落地成 issue 不再重複計算（spec A1）：

```bash
SINCE=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
for REPO in wm4n/chainbreak wm4n/hangman; do
  # Summer 近 7 天開的提案 PR（不論後來被 merge、關掉或還在審）
  gh pr list --repo "$REPO" --author wman-pm --state all --limit 200 --json headRefName,createdAt \
    --jq "[.[] | select(((.headRefName // \"\") | startswith(\"proposal/\")) and .createdAt >= \"$SINCE\")] | length"
  # Summer 近 7 天直接開的單（2026-10-23 以前的 5a）。body 含 docs/proposals/ 的是提案落地開的，
  # 已在開提案時算過，排除
  gh issue list --repo "$REPO" --author wman-pm --state all --limit 200 --json createdAt,body \
    --jq "[.[] | select(.createdAt >= \"$SINCE\" and ((.body // \"\") | contains(\"docs/proposals/\") | not))] | length"
  # Summer 近 7 天的收養（以「## Summer 收養此單」留言為準）
  gh issue list --repo "$REPO" --state all --limit 200 --json comments \
    --jq "[.[] | select(any(.comments[]; .author.login == \"wman-pm\" and (.body | startswith(\"## Summer 收養此單\")) and .createdAt >= \"$SINCE\"))] | length"
done
```

六個數字相加得「已用」，**本輪剩餘預算 ＝ 3 − 已用**，≤ 0 就這輪不開提案
也不收養（`needs-human` 升級不受影響）。任何一個查詢失敗 → 當作預算已用完，
本輪不開提案也不收養，摘要寫明。補開做到一半的提案（步驟 2 最後一段）一樣在開
PR 時計入，排在全新提案前面。**續做一個做到一半的收養（5b）
不受預算限制**：它的收養留言在貼出當時已經算進「已用」，所以剩餘預算是 0
也照樣補完。**下面的優先順序與同層排序，只對「全新的收養與新提案」生效，續做
候選不參與、不會被它們擠掉**——續做一定會跑。

預算不夠把候選全做完時，依序保留：①`ready-for-human` 收養 ②backlog 收養
③新提案——前兩者背後已經有人類明確的需求，新提案只是 Summer 自己的
猜測，不該擠掉人類已經提出的需求。**同一優先層內，兩個 repo 合在一起，
依 `createdAt` 由舊到新取**——最舊的單等得最久；不寫死規則的話，每次執行
挑的單會不一樣，同一張可能永遠輪不到。`needs-human` 的升級不計入預算。

一張都沒有也是合法結果：寫不出驗收條件就是寫不出（或預算已用完），不要為了湊數提案。
Discord 摘要照實說「本輪無符合條件的需求」與原因。

### 5a. 開提案 PR（Summer 自己的新想法）

2026-10-23 起（openab-ops Ruling R22），新想法不再直接開 issue，改開**提案 PR**
讓人類先審方向。人類怎麼回覆寫在 PR 內文結尾的回覆規則裡；之後依人類意見修改
提案、核准後開 issue，都是 `direction-proposal` skill 的事，本 skill 開完 PR 就結束
這一張。（🕘 2026-10-23 以前這一步是直接 `gh issue create --label grill-me --label
spec-only`；issue body 的格式與簽名規則搬到 `direction-proposal` 的 `materialize`。）

前提：該 repo 通過 label 預檢、步驟 2 的提案清單查得到、本輪剩餘預算 > 0。

**唯讀例外只有這一步**：本 skill 平常不碰 repo 內容。開提案時只准做兩件事：

- 在 `proposal/<YYYY-MM-DD>-<slug>` 分支上新增 `docs/proposals/<YYYY-MM-DD>-<slug>.md`
  這**一個**檔案，並 push 這個分支；
- 開一張 base 是 `main`、head 是這個分支的 PR。

其他路徑、其他分支（包括 `main`）一律不碰。主機端 merge-poller 只 merge「只動
`docs/proposals/*.md`」的提案 PR，動到別的路徑會被升級 `needs-human`。

**提案 PR 的標題、內文、提案檔、commit 訊息都不得出現關閉關鍵字接 issue 編號**
（`close`／`closes`／`closed`／`fix`／`fixes`／`fixed`／`resolve`／`resolves`／
`resolved` 後面接 `#N` 或 `owner/repo#N`，大小寫不拘）：提案 merge 之後 GitHub 會
直接關掉那張 issue，而且 `acceptance-review`、`backlog-triage` 會把這張提案誤當成
那張 issue 的實作 PR。要提到相關 issue，寫「相關：#N」。

#### 第 1 步：定名稱

```bash
REPO=wm4n/chainbreak        # 這張提案的 repo
SLUG='<英文小寫、數字、連字號，最多 40 字，例：daily-streak-reward>'
D=$(TZ=Asia/Taipei date +%F)
printf '%s' "$SLUG" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' && [ "${#SLUG}" -le 40 ] \
  && echo "NAME_OK REPO=$REPO D=$D SLUG=$SLUG" || echo "NAME_BAD"
```

印出 `NAME_BAD` 就換一個 slug。之後每次 Bash 呼叫開頭，都用這裡印出的值逐字重設
`REPO`、`D`、`SLUG`（`D` 不要重新取日期：跨過午夜會變），再用下面同一組算式得出其他
變數。**補開做到一半的提案**（步驟 2 最後一段）時，`D`、`SLUG` 從既有分支名
`proposal/<D>-<SLUG>` 拆出來，跳過第 2–4 步，直接做第 5 步。

```bash
OWNER="${REPO%%/*}"; REPO_NAME="${REPO#*/}"
BRANCH="proposal/$D-$SLUG"
FILE="docs/proposals/$D-$SLUG.md"
BASE="/home/node/repos/$OWNER/$REPO_NAME"
WT="/home/node/repos/$OWNER/$REPO_NAME-worktrees/proposal-$D-$SLUG"
STATE="/tmp/product-planning/proposal-$OWNER-$REPO_NAME-$D-$SLUG"
mkdir -p "$STATE"
```

#### 第 2 步：從 `origin/main` 開 worktree

```bash
[ -d "$BASE/.git" ] || gh repo clone "$REPO" "$BASE"
git -C "$BASE" fetch origin
git -C "$BASE" worktree prune
[ -e "$WT" ] && git -C "$BASE" worktree remove --force "$WT"
[ -e "$WT" ] && /bin/rm -rf "$WT" && git -C "$BASE" worktree prune
git -C "$BASE" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null; RC=$?
if [ "$RC" = 0 ]; then
  echo "BRANCH_EXISTS"
elif [ "$RC" != 2 ]; then
  echo "LS_REMOTE_FAILED rc=$RC"
elif git -C "$BASE" worktree add -B "$BRANCH" "$WT" origin/main; then
  echo "WT_OK $WT"
else
  echo "WT_FAILED"
fi
```

- `BRANCH_EXISTS` → 全新提案撞名，換一個 slug 重來。
- `LS_REMOTE_FAILED`、`WT_FAILED` → 這張本輪不開，記進摘要。

#### 第 3 步：寫提案檔

寫到 `$WT/$FILE`（先 `mkdir -p "$WT/docs/proposals"`）。格式固定：

````markdown
# 提案：<標題>

## 背景

<從哪個來源發現：repo 文件哪一段／哪張 issue（寫「相關：#N」）／GA4 訊號>

## 方向說明

<要做成什麼樣子、為什麼值得做>

## 方案

### 方案 A：<一句話>

<做法與取捨>

### 方案 B：<一句話>（建議）

<做法與取捨，以及為什麼建議這個>

## 驗收條件草稿

- <條件一>
- <條件二>

## 數據依據

<有 GA4 就引用指標、時間範圍、property；沒有 GA4 寫「無 GA4 數據（未設定）」
並說明替代依據（引用的文件檔名與段落、或相關 issue 編號）；沒有任何依據的
部分明說「無數據依據」>

---
— By Summer
````

- 六個段落缺一不可，驗收條件草稿要過步驟 4 的「可驗證」檢查。
- **方案小標題的格式固定**，`direction-proposal materialize` 靠它找出人類選的方案：
  - 只有一個方案 → 「## 方案」底下直接寫，**不加**任何 `### 方案 X` 小標題。
  - 兩個以上 → 每個一行 `### 方案 <大寫英文字母>：<一句話>`，字母從 A 起連續；
    **恰好一個**在行尾加 `（建議）`（全形括號）。人類 approve 時沒寫選哪個，就做這個。
- 結尾逐字 `— By Summer`（em dash U+2014），直接複製本文件的字串。

#### 第 4 步：commit、確認範圍、push

```bash
# （開頭先照第 1 步重設 REPO、D、SLUG 與那組算式）
CLOSE_RE='(^|[^A-Za-z0-9_])(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+'
if grep -Eiq "$CLOSE_RE" "$WT/$FILE"; then
  echo "CLOSE_KEYWORD_IN_FILE"
else
  git -C "$WT" add -- "$FILE" && git -C "$WT" commit -q -m "docs(proposal): <標題>"
  CHANGED=$(git -C "$WT" diff --name-only origin/main...HEAD)
  if [ "$CHANGED" = "$FILE" ] && [ -z "$(git -C "$WT" status --porcelain)" ]; then
    git -C "$WT" push origin "HEAD:refs/heads/$BRANCH" && echo "PUSH_OK"
  else
    echo "SCOPE_BAD changed=[$CHANGED]"
  fi
fi
```

只有印出 `PUSH_OK` 才往下做。`CLOSE_KEYWORD_IN_FILE` → 改掉那句再跑一次。
`SCOPE_BAD` 或 push 失敗 → 不 push（或停在這裡），這張本輪不開，記進摘要。push 不加
`--force`。commit 訊息同樣不得有關閉關鍵字。

#### 第 5 步：開 PR，內文結尾附回覆規則

內文先寫進檔案。**回覆規則是內文的最後一段，逐字照抄下面那段 heredoc、一字不改**：
人類要求每張提案都把怎麼回覆講一次（spec A1）。

```bash
# （開頭先照第 1 步重設 REPO、D、SLUG 與那組算式）
{
printf '%s\n\n' '<一段話摘要：想做什麼、為什麼>'
printf '提案檔：`%s`\n' "$FILE"
printf '方案：%s\n\n' '<只有一個方案／方案 A、方案 B，建議方案 B>'
printf '核准後 Summer 會依選定的方案開 issue，之後照現行流程進 grill 與開發。\n\n'
printf -- '— By Summer\n\n'
cat <<'EOF'
## 怎麼回覆這張提案
- **Approve** → 照做。有多個方案時，在 review 內文寫「方案 B」選定方案（沒寫就由 Summer 依提案中的建議方案）。
- **Request changes** ＋你的想法 → 不同意方向或想調整都用這個；Summer 會在這張 PR 修改後再請你重審，可以來回多次。
- **關掉 PR（不 merge）** → 整個不做；Summer 之後不會再提同一件事。
EOF
} > "$STATE/pr_body.md"
TITLE='提案：<標題>'
CLOSE_RE='(^|[^A-Za-z0-9_])(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+'
if printf '%s\n' "$TITLE" | cat - "$STATE/pr_body.md" | grep -Eiq "$CLOSE_RE"; then
  echo "CLOSE_KEYWORD_IN_PR"
else
  gh pr create --repo "$REPO" --base main --head "$BRANCH" --title "$TITLE" --body-file "$STATE/pr_body.md"
fi
```

確認開成了（作者、標題前綴、回覆規則在最後、沒有關閉關鍵字，全部成立才印 `PR_OK`）：

```bash
# （開頭先照第 1 步重設 REPO、D、SLUG 與那組算式）
gh pr list --repo "$REPO" --head "$BRANCH" --state open --json url,title,author,body --jq '
  .[] | ((.body // "") | gsub("[\t\r\n \u00a0\u3000]+$"; "")) as $b
  | if (.author.login // "") == "wman-pm"
       and (.title | startswith("提案："))
       and ($b | contains("\n## 怎麼回覆這張提案\n"))
       and ($b | endswith("**關掉 PR（不 merge）** → 整個不做；Summer 之後不會再提同一件事。"))
       and ((.title + "\n" + $b) | test("(^|[^A-Za-z0-9_])(close[sd]?|fix(e[sd])?|resolve[sd]?)[\t ]*:?[\t ]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+"; "i") | not)
    then "PR_OK \(.url)" else "PR_BAD \(.url)" end'
```

- `PR_OK` → 這張提案算進預算，完成。
- `PR_BAD` → 不要關 PR、不要改它，記進摘要請人類看（內文寫錯的提案 PR 由人類決定
  要關掉還是留著）。
- 沒有任何輸出（PR 沒開成）→ 記進摘要。分支已經 push 了，下一輪步驟 2 會把它列成
  「做到一半的提案」補開 PR。

**不要等人類、不要 @ 人類**：提案待審的通知由主機端 `human-notifier.sh` 發（作者
`wman-pm`、分支 `proposal/*`、目前 head 上還沒有 `wm4n` 的 review 就 @ 一次，附回覆
規則摘要）。

#### 第 6 步：移除 worktree（成功、失敗都做）

```bash
# （開頭先照第 1 步重設 REPO、D、SLUG 與那組算式）
git -C "$BASE" worktree remove --force "$WT"
git -C "$BASE" worktree prune
[ ! -e "$WT" ] && echo "WT_REMOVED"
```

沒印出 `WT_REMOVED` → 記進摘要，下一張照做（同名殘留會在第 2 步先清掉）。

### 5b. 收養人類開的 issue（`pm-owned`）

收養 = 讓 Summer 接手把這張人類開的單推進 grill 流程。前提：已通過 label
預檢、本輪（兩 repo 加總）剩餘預算 > 0、body 沒有 opt-out 標記，作者是 `wm4n`
（3b）或不是 bot 帳號（3c）。**續做一個做到
一半的收養不受預算限制**，剩餘預算是 0 也可以補完（見下方續做規則）。`gh issue` 子指令不吃
`owner/repo#N`，先把目標拆成 `REPO`（例如 `wm4n/chainbreak`）與 `NUM`
（例如 `42`）兩個變數，後面的指令都用這兩個變數。三個動作，**順序固定**。

**動作 1：先留言**，說明收養與理由（`ready-for-human` 的單另寫原本卡住的
決定與 Summer 的決定）、列出驗收條件，以 `— By Summer` 簽名結尾：

```bash
gh issue comment "$NUM" --repo "$REPO" --body "$(cat <<'EOF'
## Summer 收養此單

收養理由：<為什麼值得做、為什麼不落在 needs-human 五類>
<ready-for-human 的單加一段：原本卡住的決定是什麼、Summer 的決定、理由>

驗收條件：
- <條件一>
- <條件二>

---
— By Summer
EOF
)"
```

**動作 2：再加三個 label**：

```bash
gh issue edit "$NUM" --repo "$REPO" --add-label grill-me --add-label spec-only --add-label pm-owned
```

`pm-owned` 讓 `summer-grill-responder` 把這張別人（`wm4n`）開的單當作
Summer 的單，來回答 Rick/Morty 的 grill 提問；不貼這個，grill 開了
卻沒人答，單子就停在那裡。

**動作 3：只有 `ready-for-human` 來源的單才做，且最後才做**。先確認動作 2
成功（指令 exit 0，並用 `gh issue view "$NUM" --repo "$REPO" --json labels`
看到三個 label 都在），才移除：

```bash
gh issue edit "$NUM" --repo "$REPO" --remove-label ready-for-human
```

先加後移除的理由同上：反過來中途失敗，這張單會兩邊都不屬、從此沒有人
找得到。動作 3 若失敗，不重試、不影響其他單，把這張記進摘要請人類手動
移除。

**不改人類開的 issue 的 body**：不整段覆寫，也不補簽名。身份由 `pm-owned`
label 承擔，收養的紀錄由動作 1 的留言承擔。

**續做一個做到一半的收養**：留言已貼、動作 2 卻失敗（網路、權限…）時，
下一輪只有在**同時符合**「issue 上已有 `## Summer 收養此單` 留言」且
「`grill-me`、`spec-only`、`pm-owned` 三個 label 一個都沒有」且「沒有其他
流程 label（`grill-me-done`、`ready-for-agent`、`agent-*`、`needs-human`）」
時，才直接補動作 2、3，**不重貼留言、不消耗預算**。只要三個 label 其中任一個存在，就
當作已收養完成或是人類刻意調整過，**不補、不重加**——人類移掉的 label
不能被自動化悄悄加回來。label 預檢已經擋掉了「label 不存在」這個最常見的
失敗原因，這條只處理預檢之後的偶發失敗。

### 6. Discord 貼精簡摘要

只貼：新開的提案 PR（標題與連結）、收養的 issue、`needs-human` 升級的 issue、各一句話理由與
連結，不要把完整 body 貼進 Discord——單則訊息有 2000 字限制，超過會被截斷，
而截斷後的訊息內容不完整還可能被其他 poller 誤判成新事件、重複觸發。
**摘要不帶任何 @**（2026-10-17 改，R17）：`needs-human` 的通知由主機端
`human-notifier.sh` 依 label 事件發。這一輪若因預算用完、label 缺漏、動作失敗而
有沒做的項目，摘要一併寫明原因。

## 鐵則

- **數據拿不到就明說拿不到**，例如 GA4 沒設定、某個 preset 查不到資料、
  或某段時間沒有事件記錄，直接寫「無 GA4 數據（未設定）」「這段無數據依據」。
  **絕不用推測冒充數據依據**——掰一個聽起來合理但沒有查證的數字，比誠實說
  「不知道」更糟，會讓後面排優先序的人依據假數據做判斷。
- 兩個 property（repo）**永遠分開報告**，不平均、不加總。
- **新想法一律走提案 PR，不直接開 issue**（R22）。提案檔與 PR 內文結尾逐字
  `— By Summer`；PR 內文的最後一段是回覆規則，逐字照抄 5a 第 5 步；標題、內文、
  提案檔、commit 訊息都不得有關閉關鍵字接 issue 編號。核准後開的 issue 帶什麼
  label、body 怎麼簽名，以 `direction-proposal` 為準。
- **唯讀例外只限 5a**：只在 `proposal/<YYYY-MM-DD>-<slug>` 分支上新增
  `docs/proposals/` 底下那一個提案檔、push 那個分支、開 PR；其他路徑與分支一律不碰。
- **收養貼齊 `grill-me`、`spec-only`、`pm-owned`**——`spec-only` 是 `jira-grill`
  判斷要不要跳過工程階段的依據，`pm-owned` 是收養單被 `summer-grill-responder`
  辨識的依據，用途各不同，不能漏貼。
- **新開提案加收養合計（兩個 repo 加總）滾動 7 天最多 3 張**，開之前先算最近 7 天
  已用多少；提案在開 PR 時計入，落地成 issue 不重複算；`needs-human` 升級不計入。
- **被人類關掉、沒有 merge 的提案就是「不做」**：同一件事不再提。
- **label 一律先加後移除**：收養 `ready-for-human` 的單最後才移除
  `ready-for-human`；`ready-for-human` 改貼 `needs-human` 也是先加
  `needs-human` 再移除 `ready-for-human`。
- **貼 `needs-human` 的順序固定：加 label → 留言（標題
  `## 需要人類決定（needs-human）`）→（`ready-for-human` 來源才有）最後移除
  `ready-for-human`**，@ 人類由 `human-notifier.sh` 依 label 事件發；加 label 失敗
  就整個停手。已有升級留言卻沒有 label，
  是人類處理完移除的，**絕不重新加回**。
- **帶 `needs-human` 的 issue 一律不動**。
- **收養、升級、開提案之前先做 label 預檢**，缺 `grill-me`／`spec-only`／
  `pm-owned`／`needs-human` 任一個，那個 repo 本輪就不做這些動作。
- **續做做到一半的收養不受預算與排序限制**，一定會跑。
- **不在 Discord @ 任何人**：通知人類是主機端 `human-notifier.sh` 的事（R17）。
- **清單以外的決定 Summer 自己做**，並把理由留在 issue 留言（帶
  `— By Summer`）——決定沒有留下理由，事後沒有人看得出為什麼這樣收養。
- 簽名開頭是 **em dash（U+2014）**「—」，不是連字號「-」。兩者肉眼幾乎
  分不出來，但下游用字串比對、打錯一個字元就完全比對不上；直接複製本文件裡
  的 `— By Summer` 貼過去，不要自己重打。

## 不做什麼

- **除了 5a 開提案，不 clone repo、不建 worktree、不切分支**——其他步驟只讀
  repo 文件（經 `gh api`）、`gh issue`／`gh pr` 的列表資訊，以及（有設定時）GA4
  報表，不需要讀程式碼。5a 的 worktree 只用來寫提案檔，不碰程式碼。
- **不修改提案、不把提案落地成 issue、不 merge**——依人類 review 修改提案、核准後
  開 issue 是 `direction-proposal` 的事；merge 是主機端 merge-poller 的事。
- **不排優先序、不決定該不該投產**——找需求、開提案、收養、貼 `grill-me`
  到此為止，之後規格共識、排優先序、貼 `ready-for-agent` 是
  `backlog-triage` 的職責。
- **不自己回答 grill 提問**——那是 `grill-respond` 的職責，由
  `summer-grill-responder` 偵測到問題後另外觸發。
- **不自己建 label**——`needs-human`、`pm-owned` 若 repo 裡不存在，回報給
  人類處理，不要用 `gh label create` 自行補上。

## 已知限制

- **usercron 已部署**：本 skill 依 Summer 容器內的 usercron 排程觸發
  （`sender_name`＝`SummerPlanning`），`backlog-triage`、
  `acceptance-review` 同樣已在跑。排程時程以 `openab-ops` 的 `CRONJOB.md`
  為準，人類在 Discord 要求時也能手動觸發（手動觸發與排程共用同一份
  滾動 7 天預算）。
- **`needs-human`、`pm-owned` 兩個 label 需先存在於兩個 repo**：本 skill
  不建 label，缺的話 label 預檢會擋下該 repo 的收養與升級，並在摘要請人類
  建立（摘要不帶 @；human-notifier 不通知這件事，人類要看 `summer-pm` 的摘要）。
- **repo 文件的需求是 Summer 自己的推論**，不像人類開的單有明確意圖；
  因此排在 3 張上限的最後順位，且驗收條件仍必須可驗證。
- **升級在「label 之後、留言之前」被中斷**：`needs-human` 已在身上，poller 都會
  跳過，human-notifier 照樣 @ 人類，只是 issue 上缺說明留言；這是接受的取捨，不補做。
  若人類之後只移除 label、沒有留言，這張單沒有升級留言可供辨認，看起來像
  全新候選，可能再被升級一次、多一次通知。機率極低，接受，不為它加額外機制。
- **寫不出驗收條件的人類單不會被收養**，也不會自動升級給人類，下一輪會
  再被看到一次——這是刻意的：缺資訊不屬於 `needs-human` 五類。
- **提案去重靠主題比對**：被關掉的提案換了標題、換了 slug，仍要靠 Summer 讀標題
  判斷是不是同一件事；`gh pr list --limit 200` 只看最近 200 張 Summer 的 PR，更早被
  關掉的提案讀不到。
- **提案 PR 的 push 依賴 Summer 容器的 git 憑證**（`gh auth setup-git`）：上線前在
  容器內對 `proposal/*` 分支跑一次 `git push --dry-run` 確認（openab-ops runbook）。
