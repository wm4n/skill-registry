---
name: product-planning
argument-hint: "[--property chainbreak|hangman]"
description: >-
  規劃下一步該做什麼、開需求 issue 或收養人類開的 issue。需求來源有四個，
  GA4 數據只是其中一個可選的加分項（沒設定 GA4 也照樣有產出）：產品 repo
  自己的文件（README／CLAUDE.md／docs）、人類開的無流程 label backlog、
  卡在 ready-for-human 的單，以及（有設定時）GA4。由 usercron 每週一
  09:00 觸發（訊息「執行 product-planning skill」，sender_name＝
  SummerPlanning），或人類在 Discord 提出同類請求（如「規劃一下需求」
  「看數據開單」「這週該做什麼」）時觸發：chainbreak 與 hangman 各自分析、
  不平均，比對兩個 repo 現有 issue 避免重複，找出寫得出驗收條件的需求，
  新開加收養合計每次最多 3 張，貼 grill-me 與 spec-only（收養另貼
  pm-owned）；ready-for-human 的單若落在 needs-human 五類就改貼
  needs-human 並 @ 人類，不落在五類由 Summer 決定後收養。新開的單 body
  結尾簽名 — By Summer。數據拿不到就明說，不推測冒充依據。
---

# Product Planning

> **本 skill 是責任鏈的起點，`backlog-triage` 接手後段**：這裡開（或收養）
> 的每張 issue 要帶齊下列標記，各自餵給不同的下游消費者，缺一不可：
> - **「這是 Summer 的單」的身份標記**——`summer-grill-responder` 用來判斷
>   該不該讓 Summer 搶答 Rick/Morty 的 grill 提問，只要符合三者之一就算：
>   author 是 `wman-pm`（Summer 的 GitHub 帳號，人類是 `wm4n`）、body 結尾
>   `— By Summer` 簽名、或帶 `pm-owned` label。**自己新開的單**三者天然
>   具備（仍照舊寫簽名，多一重保險）；**收養人類開的單**作者是 `wm4n`、
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

白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo，開 issue、收養、
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

### 貼 `needs-human` 的固定三步（順序不可換）

1. **在 issue 上留言**，寫明「卡在清單第幾類、需要人類決定什麼、有哪些
   選項」，以 `— By Summer` 簽名結尾。
2. **貼 `needs-human` label**（`gh issue edit --add-label needs-human`）。
3. **Discord 發一則訊息 `<@824092654060830770>`（人類）並附 issue 連結**，
   發在本次觸發 Summer 所在的回覆／討論串。若 Summer 當下不是在
   `bot-notify`（頻道 ID `1526283579309690990`）執行，同一則內容**也要**
   貼到 `bot-notify`——人類固定看那個頻道。每張 issue 只 @ 一次；同一輪
   有多張可合併成一則（單則上限 2000 字，附上全部連結即可）。

先留言再貼 label，是因為 label 一貼上，各 poller 就開始跳過這張單；若
label 先到、留言沒到，人類被通知後看不到要決定什麼。

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

這支 skill 曾因為只認 GA4 而在 GA4 沒設定的環境裡每週一都不開任何單
（2026-09-20 起），整條自主閉環因此沒有入口；所以 GA4 缺席時必須有
替代來源，不能再以「沒數據」為由收工。

### 2. 蒐集兩個 repo 現況

```bash
gh issue list --repo wm4n/chainbreak --state open --json number,title,body,labels
gh issue list --repo wm4n/hangman    --state open --json number,title,body,labels
gh pr list --repo wm4n/chainbreak --state merged --limit 20 --json number,title,mergedAt
gh pr list --repo wm4n/hangman    --state merged --limit 20 --json number,title,mergedAt
```

開放 issue 用來**避免重複開單**：新想法先跟這份清單比對主題，明顯重疊的
不重開，改成在既有 issue 底下留言補充佐證（既有 issue 若帶 `needs-human`
則不留言，見上）。近期 merged PR 用來確認「這個功能是不是已經做過了」——
訊號如果來自一個已經上線的修正，代表資料還沒反映最新版本，不是新需求。

### 3. 找需求來源——四選項，全部都讀、不必等 GA4

#### 3a. 產品 repo 自己的文件

不 clone，用 `gh api` 讀原文（raw 格式，不需要自己解 base64）：

```bash
gh api -H "Accept: application/vnd.github.raw+json" repos/wm4n/chainbreak/contents/README.md
gh api -H "Accept: application/vnd.github.raw+json" repos/wm4n/chainbreak/contents/CLAUDE.md
gh api repos/wm4n/chainbreak/contents/docs --jq '.[].path'   # 列出 docs/ 檔案，再挑 roadmap／規劃類的讀
```

hangman 同理把 repo 名換掉。找 roadmap、TODO、「之後要做」「待辦」「已知
限制」這類文字，對照步驟 2 的 open issue 與 merged PR，挑出**文件寫了要做、
但 backlog 裡沒有、也沒有做過**的項目。檔案不存在（404）是正常情況，
跳過即可，不當成錯誤。

#### 3b. 人類開的 backlog

步驟 2 的 open issue 裡，挑出**沒有任何流程 label** 的：不含 `grill-me`、
`grill-me-*`（含 `grill-me-done`）、`ready-for-agent`、`ready-for-human`、
`agent-*`（`agent-active`／`agent-failed`／`agent-done`…）、`needs-human`、
`pm-owned`。這些就是人類開了、但還沒有任何 bot 接手的單。含
`ready-for-human` 的歸 3c，已有 `pm-owned` 的是已收養過，都不重複處理。

#### 3c. `ready-for-human` 的單

```bash
gh issue list --repo wm4n/chainbreak --label ready-for-human --state open \
  --json number,title,body,labels,comments
gh issue list --repo wm4n/hangman    --label ready-for-human --state open \
  --json number,title,body,labels,comments
```

這是人類標記「要人來決定」而一直沒人處理的單（目前沒有任何 bot 會碰
它）。逐張讀完 body 與 comments，判斷**卡住的那個決定**落不落在
`needs-human` 五類：

- **落在五類** → 走「貼 `needs-human` 的固定三步」（留言、加 label、
  Discord @ 人類）；第 2 步確認 `needs-human` 已加上之後，才移除
  `ready-for-human`（先加後移除——反過來中途失敗，這張單兩個 label 都
  沒有，從此沒有任何自動化找得到它）。這**不計入**每次 3 張的上限。
- **不落在五類** → Summer 以 PM 身分把決定做掉，在收養留言裡寫明
  「原本卡在什麼決定、Summer 的決定、理由」（帶 `— By Summer`），然後
  走「收養」流程。收養**計入**每次 3 張的上限。

3b 的 backlog 單也一樣先過五類：落在五類的**不收養**（收養等於把它送進
Rick/Morty 的開發流程），改走「貼 `needs-human` 的固定三步」；不落在五類
才考慮收養。

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
   `grill-me` 的單（新想法）或收養（人類的單，見 3b／3c）。新想法的話，
   在 Discord 摘要裡單獨列一行「需人類決定，未開單：<一句話>」即可。
2. **可驗證的驗收條件**：每項都要能寫出具體、可驗證的驗收條件，**不限於
   GA4 指標**，功能性條件也算（例如「設定頁新增 X 開關，關閉後 Y 不再
   出現」「結算頁跳出率從 X% 降到 Y% 以下」）。寫不出這種條件的項目直接
   捨棄，不開單、不收養、不硬湊一個模糊的驗收條件充數。

**上限：新開加收養合計，每次執行最多 3 張**（本 skill 每週一跑一次，所以
也就是每週 3 張）。超過時依序保留：①`ready-for-human` 收養 ②backlog 收養
③新開的單——前兩者背後已經有人類明確的需求，新開的單只是 Summer 自己的
猜測，不該擠掉人類已經提出的需求。`needs-human` 的升級不計入上限。

一張都沒有也是合法結果：寫不出驗收條件就是寫不出，不要為了湊數開單。
Discord 摘要照實說「本輪無符合條件的需求」與原因。

### 5a. 新開 issue

```bash
gh issue create --repo wm4n/chainbreak \
  --title "<標題>" \
  --label grill-me \
  --label spec-only \
  --body "$(cat <<'EOF'
## 背景

<這個需求是從哪個來源發現的：repo 文件哪一段／哪張人類 issue／GA4 訊號>

## 需求描述

<要做成什麼樣子>

## 驗收條件

- <條件一>
- <條件二>

## 數據依據

<有 GA4 就引用指標、時間範圍、property；沒有 GA4 寫「無 GA4 數據（未設定）」
並說明替代依據（引用的文件檔名與段落、或相關 issue 編號）；沒有任何依據的
部分明說「無數據依據」>

---
— By Summer
EOF
)"
```

body 五個段落缺一不可：標題另外用 `--title`，背景、需求描述、驗收條件、
數據依據都要有內容。**結尾一定是 `— By Summer`**，`--label grill-me` 與
`--label spec-only` 跟建 issue 同一步做完，這步不用等人類點頭。

### 5b. 收養人類開的 issue（`pm-owned`）

收養 = 讓 Summer 接手把這張人類開的單推進 grill 流程。`gh issue` 子指令
不吃 `owner/repo#N`，先把目標拆成 `REPO`（例如 `wm4n/chainbreak`）與
`NUM`（例如 `42`）兩個變數，後面的指令都用這兩個變數。三個動作，**順序固定**：

1. **先留言**，說明收養與理由（`ready-for-human` 的單另寫原本卡住的
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

2. **再加三個 label**：

   ```bash
   gh issue edit "$NUM" --repo "$REPO" --add-label grill-me --add-label spec-only --add-label pm-owned
   ```

   `pm-owned` 讓 `summer-grill-responder` 把這張別人（`wm4n`）開的單當作
   Summer 的單，來回答 Rick/Morty 的 grill 提問；不貼這個，grill 開了
   卻沒人答，單子就停在那裡。

3. **只有 `ready-for-human` 來源的單才做，且最後才做**：先確認第 2 步成功
   （指令 exit 0，並用 `gh issue view "$NUM" --repo "$REPO" --json labels`
   看到三個 label 都在），才移除：

   ```bash
   gh issue edit "$NUM" --repo "$REPO" --remove-label ready-for-human
   ```

   先加後移除的理由同上：反過來中途失敗，這張單會兩邊都不屬、從此沒有人
   找得到。

**不改人類開的 issue 的 body**：不整段覆寫，也不補簽名。身份由 `pm-owned`
label 承擔，收養的紀錄由第 1 步的留言承擔。

**部分失敗的處理**：留言已貼、加 label 失敗（例如 repo 裡還沒有
`pm-owned` 這個 label，`gh` 會回報 label 找不到）→ **不要移除
`ready-for-human`**，也不要自己建 label（改 repo 設定屬於 `needs-human`
第 2 類），把失敗原因寫進 Discord 摘要請人處理。下一輪發現 issue 的 comments
裡已經有「## Summer 收養此單」就不要重貼同一則留言，直接補完第 2、3 步。

### 6. Discord 貼精簡摘要

只貼：新開的標題、收養的 issue、`needs-human` 升級的 issue、各一句話理由與
連結，不要把完整 body 貼進 Discord——單則訊息有 2000 字限制，超過會被截斷，
而截斷後的訊息內容不完整還可能被其他 poller 誤判成新事件、重複觸發。
貼 `needs-human` 的那一則（含 @ 人類）規則見前面「貼 `needs-human` 的固定
三步」，可與摘要合併成一則。

## 鐵則

- **數據拿不到就明說拿不到**，例如 GA4 沒設定、某個 preset 查不到資料、
  或某段時間沒有事件記錄，直接寫「無 GA4 數據（未設定）」「這段無數據依據」。
  **絕不用推測冒充數據依據**——掰一個聽起來合理但沒有查證的數字，比誠實說
  「不知道」更糟，會讓後面排優先序的人依據假數據做判斷。
- 兩個 property（repo）**永遠分開報告**，不平均、不加總。
- 新開的 issue body 結尾**逐字** `— By Summer`（em dash 開頭），這是
  `summer-grill-responder` 判斷該不該搶答的依據之一。
- **新開貼齊 `grill-me` 與 `spec-only`；收養貼齊 `grill-me`、`spec-only`、
  `pm-owned`**——`spec-only` 是 `jira-grill` 判斷要不要跳過工程階段的依據，
  `pm-owned` 是收養單被 `summer-grill-responder` 辨識的依據，用途各不同，
  不能漏貼。
- **新開加收養合計每次最多 3 張**；`needs-human` 升級不計入。
- **label 一律先加後移除**：收養 `ready-for-human` 的單最後才移除
  `ready-for-human`；`ready-for-human` 改貼 `needs-human` 也是先加
  `needs-human` 再移除 `ready-for-human`。
- **貼 `needs-human` 的順序固定：留言 → 貼 label → Discord @ 人類**；
  留言要說清楚第幾類與需要決定什麼。
- **帶 `needs-human` 的 issue 一律不動**。
- **清單以外的決定 Summer 自己做**，並把理由留在 issue 留言（帶
  `— By Summer`）——決定沒有留下理由，事後沒有人看得出為什麼這樣收養。
- 簽名開頭是 **em dash（U+2014）**「—」，不是連字號「-」。兩者肉眼幾乎
  分不出來，但下游用字串比對、打錯一個字元就完全比對不上；直接複製本文件裡
  的 `— By Summer` 貼過去，不要自己重打。

## 不做什麼

- **不 clone repo、不建 worktree、不切分支**——這支 skill 只讀 repo 文件
  （經 `gh api`）、`gh issue`／`gh pr` 的列表資訊，以及（有設定時）GA4
  報表，不需要讀程式碼。
- **不排優先序、不決定該不該投產**——找需求、開單、收養、貼 `grill-me`
  到此為止，之後規格共識、排優先序、貼 `ready-for-agent` 是
  `backlog-triage` 的職責。
- **不自己回答 grill 提問**——那是 `grill-respond` 的職責，由
  `summer-grill-responder` 偵測到問題後另外觸發。
- **不自己建 label**——`needs-human`、`pm-owned` 若 repo 裡不存在，回報給
  人類處理，不要用 `gh label create` 自行補上。

## 已知限制

- **usercron 已部署**：本 skill 每週一 09:00 由 Summer 容器內的
  usercron 觸發（`sender_name`＝`SummerPlanning`）；`backlog-triage`
  （平日 10:00）與 `acceptance-review`（平日 10:30）同樣已在跑。排程
  細節以 `openab-ops` 的 `CRONJOB.md` 為準，人類在 Discord 要求時也能
  手動觸發。
- **`needs-human`、`pm-owned` 兩個 label 需先存在於兩個 repo**：本 skill
  不建 label，缺的話加 label 那步會失敗，處理方式見「5b. 收養」的部分失敗
  段落。
- **repo 文件的需求是 Summer 自己的推論**，不像人類開的單有明確意圖；
  因此排在 3 張上限的最後順位，且驗收條件仍必須可驗證。
- **寫不出驗收條件的人類單不會被收養**，也不會自動升級給人類，下一輪會
  再被看到一次——這是刻意的：缺資訊不屬於 `needs-human` 五類。
