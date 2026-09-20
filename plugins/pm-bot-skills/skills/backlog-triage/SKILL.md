---
name: backlog-triage
argument-hint: "[<owner/repo>#<N>]"
description: >-
  排序 grill-me-done 待辦、修復 agent-failed 規格、警示逾時卡單的 backlog
  巡查。由 usercron 平日 10:00 觸發（訊息「執行 backlog-triage skill」），
  或人類在 Discord 提出同類請求（如「排一下優先序」「看看卡住的單」「這張
  能改回去了嗎」）時觸發：三段各自獨立掃描 grill-me-done／agent-failed／
  agent-active 三個 label，在 Discord 提議排序、提議改回 ready-for-agent、
  或告警卡單，只提議、絕不自行貼 ready-for-agent——人類點頭後才在後續 turn
  貼上（先加 ready-for-agent 再移除 grill-me-done）。
---

# Backlog Triage

> **本 skill 接手 `product-planning` 開單之後的下一段**：那邊開的單（或人類
> 自己開的單）走完 grill 流程後會落在這裡的三個掃描目標之一。整條閉環從
> `grill-me`（`product-planning` 貼，無閘門）到 `ready-for-agent`（這裡貼，
> **唯一的人類閘門**）只有這一道關卡——`ready-for-agent` 一貼上，
> `agent-dev-poller` 就會認領並觸發 Rick/Morty 真的開發、燒額度、開 PR，
> 是整條鏈最難回收的一步。本 skill 的核心紀律就是**只提議，不動這道閘門**，
> 下面每一段都要守住這條線。

## 觸發與參數

`$ARGUMENTS`：

- 空 → **掃全部**：對 `wm4n/chainbreak`、`wm4n/hangman` 兩個白名單 repo，
  下面三段各自掃一輪。
- `<owner/repo>#<N>` → **只處理這一張**，依它目前掛的 label 落在三段的哪
  一段就跑哪段邏輯；三個 label 都沒有就說明「這張不在本 skill 的掃描範圍」
  並停止，不要臆測要跑哪段。

### ⚠️ 先把參數拆開：`gh` 不吃 `owner/repo#N`

`gh issue` 各子指令只接受 `{<number> | <url>}`，直接把 `owner/repo#N` 丟
進去會得到 `invalid issue format`。指定單張 issue 時先拆成兩個變數：

```bash
ISSUE_REF="wm4n/chainbreak#42"   # 從 $ARGUMENTS 取得
REPO="${ISSUE_REF%#*}"           # → wm4n/chainbreak
NUM="${ISSUE_REF##*#}"           # → 42
```

## 三段各自獨立、互不阻擋

三段分開跑，任何一段裡對單一 issue 的操作失敗（讀不到 comment、`gh` 呼叫
出錯），只記錄那張 issue 並跳過，繼續同一段其餘 issue，也不影響另外兩段
——一段的失敗不該讓另外兩段整段沒跑。

### 段 1：`grill-me-done` → 排優先序、GitHub 留痕、Discord 提議

```bash
gh issue list --repo wm4n/chainbreak --label grill-me-done --state open \
  --json number,title,body,comments
gh issue list --repo wm4n/hangman    --label grill-me-done --state open \
  --json number,title,body,comments
```

`--json` 一定要撈 `body`：`product-planning` 開單時把數據依據寫在 issue
**body**（見該 skill「4. 開 issue」），`jira-grill` 貼的「✅ 需求共識」
comment 只含背景、需求範圍、驗收條件、目標 repo，**不含數據依據**——只看
`comments` 找不到最初的數據佐證，排序時就沒有原始依據可引。

對每一張：

1. 在 `comments` 裡找 `jira-grill` 貼的「✅ 需求共識」comment。**找不到
   這則 comment 視為異常**——跳過、記錄，不要改看 issue 標題／描述自己
   臆測需求範圍，那不是共識的內容。
2. **本輪涉及到的每個 property，都重新跑一次 GA4 report**（preset
   `overview`，用法同 `product-planning` 的「拉 GA4 數據」一節，property
   對應這張 issue 所屬的 repo）——不要嘗試判斷「這次要不要重跑」，固定
   重跑：排序理由要有「這一輪」的數據佐證，不是沿用不知道多久以前、
   甚至只存在於印象裡的數字。
3. 彙整本輪掃到的所有 `grill-me-done` issue，依產品價值與 GA4 數據排出
   建議順序。

**完成條件是排序附得出理由**，不是排出一份清單就算數：理由必須指得出是
哪個 GA4 訊號或哪一點驗收條件的價值更高，不能只寫「感覺比較急」這種無法
覆核的說法。**查不到佐證就明說查不到，不准用推測冒充數據依據**——步驟 2
的 GA4 查詢失敗，或這張 issue 的 body 本來就沒留下數據依據，理由就寫
「這部分無法查證」，不要編一個聽起來合理但沒有查證的訊號。

**排序結果要留在 GitHub，不能只留在 Discord**：對本輪涉及的每一張 issue，
各貼一則記錄本次排序判斷的 comment：

```
## 排序建議

本輪建議順序：第 <N> 順位（同批 grill-me-done 共 <M> 張）

理由：<具體 GA4 訊號，或引用的驗收條件／body 數據依據；查無佐證則寫「這部分無法查證」>

---
— By Summer
```

Discord **只放精簡摘要與連結**（例如「建議先做 #42，理由見 issue 留言」），
完整的處理過程、決策依據、數據來源要在上面這則 GitHub comment 裡——這是
persona `Summer-AGENTS_v2.md`「資訊同步」鐵則明列「排序提議」也要完整記錄
在 GitHub 的要求，不是這支 skill 自訂的規矩。

這一段**只提議，不碰任何 label**——貼 comment 是留紀錄，不是往前推進閘門。

### 段 2：`agent-failed` → 修規格、提議轉回

```bash
gh issue list --repo wm4n/chainbreak --label agent-failed --state open \
  --json number,title,body,comments
gh issue list --repo wm4n/hangman    --label agent-failed --state open \
  --json number,title,body,comments
```

對每一張：

1. 讀 Rick/Morty 的 `auto-dev-pipeline` 留下的規格問題說明 comment，找出
   具體缺口在哪（漏了驗收條件、範圍描述不清、跟現有功能衝突……）。
2. 針對那個缺口修 issue 描述：

   ```bash
   gh issue edit "$NUM" --repo "$REPO" --body "$UPDATED_BODY"
   ```

   只補齊／修正 Rick/Morty 指出的那個缺口，不整段砍掉重寫——除非讀完
   規格問題說明後發現整體方向就錯，才需要大改。
3. **改完不能無痕覆寫**：`gh issue edit --body` 是整段覆蓋，覆蓋前後的
   差異若不留紀錄，事後沒有人分得出「這是誰、什麼時候、為什麼改的」——
   Summer 與人類在 `wm4n/*` 共用同一個 GitHub 帳號，這正是
   `product-planning` 當初要用 body 簽名解決的同一個「author 分不出來」
   問題，這裡不能重演。修完 body 立刻在同一張 issue 上貼一則說明變更的
   comment：

   ```
   依 Rick/Morty 的規格問題調整了描述，變更摘要：<改了哪個段落，新增／刪除了什麼內容>

   ---
   — By Summer
   ```

   變更摘要要點名**改了哪個段落、新增或刪除了什麼內容**，不能只寫
   「已更新」——這則 comment 是 persona「資訊同步」鐵則要求的完整紀錄，
   不是可有可無的附註。
4. Discord 提議「issue 描述已更新（詳見 issue 留言），建議改回
   `ready-for-agent`」。body 修改本身不受閘門保護（閘門只擋 label），這則
   Discord 摘要是人類核可前的第二道防線，一樣要點名改了哪個段落、新增或
   刪除了什麼，不能只寫「已更新」帶過。

跟段 1 一樣，**這一段也只提議，不碰 label**——修好描述、留完紀錄，不代表
可以直接放行重跑，仍要等人類點頭。

### 段 3：`agent-active` → 逾時卡單告警

```bash
gh issue list --repo wm4n/chainbreak --label agent-active --state open \
  --json number,title,updatedAt
gh issue list --repo wm4n/hangman    --label agent-active --state open \
  --json number,title,updatedAt
```

對每一張，若 `updatedAt` 距現在**超過 24 小時**，列為**疑似卡單**，Discord
告警列出這些 issue 與卡了多久，並提醒人類去核實 pod 狀態。

**是「疑似」，不是已核實的事實**：Summer 看不到 Mac mini／k3s 上實際的
pod 狀態，`updatedAt` 逾時只是一個訊號——多數情況下確實代表卡住，但也可能
是 Rick/Morty 正常開發中、剛好這一輪沒有留言（`auto-dev-pipeline` 全程只在
開頭與結尾留言，正常一輪遠短於 24 小時，機率低但不是零）。告警文字要用
「疑似卡單，建議核實 pod 狀態」這種留有查證空間的措辭，不要寫成「已確認
卡住」。

**這段只告警，不嘗試恢復**：`auto-dev-pipeline` 自己列出的已知限制是
`agent-active` 沒有逾時自動復原，pod 中途被殺會永久卡住——本 skill 的職責
到「讓人類知道有這張疑似卡住了」為止，實際去 Mac mini／k3s 查 pod 狀態是
人類或另一個 runbook 的事，不在這裡處理。

## 鐵則

- **GitHub 留痕，不無痕操作**：段 1 的排序理由、段 2 的描述變更，都要在
  對應的 GitHub issue 上貼一則帶 `— By Summer` 簽名的 comment，記錄處理
  過程、決策依據與數據來源——這是 persona `Summer-AGENTS_v2.md`「資訊
  同步」鐵則明列的要求（「排序提議」被明確點名）。**Discord 只放精簡摘要
  與連結，不是完整紀錄的所在**；反過來只在 Discord 講清楚、GitHub 上什麼
  都沒留下，就是違反這條鐵則。
  ⚠️ 簽名開頭是 **em dash（U+2014）**「—」，不是連字號「-」，直接複製本
  文件裡的 `— By Summer`，不要自己重打。
- **數據拿不到就明說，不准用推測冒充**（與 `product-planning` 共用同一條
  鐵則）：段 1 的 GA4 查詢失敗，或某張 issue 的 body 本來就沒留下數據
  依據，排序理由就寫「這部分無法查證」，不編一個聽起來合理但沒有查證的
  訊號。
- **只提議，絕不自行貼 `ready-for-agent`**。段 1 與段 2 都只在 Discord 提
  案；人類在 Discord 明確點頭（例如「好，做 #42」「可以改回」）之後，才
  在**後續 turn**執行貼 label 這件事——不能在同一次觸發裡自問自答直接貼，
  這是整條閉環唯一的人類閘門。
- **label 操作順序固定先加後移除**：拿到人類點頭後，

  ```bash
  gh issue edit "$NUM" --repo "$REPO" --add-label ready-for-agent
  gh issue edit "$NUM" --repo "$REPO" --remove-label grill-me-done
  ```

  先加 `ready-for-agent`，確認成功後才移除 `grill-me-done`。順序反了、
  中間又失敗，會讓這張 issue 兩個 label 都沒有——**從此沒有任何 poller
  撿得到它**，而且不會有任何錯誤訊息提醒。
- **排序只依產品價值與 GA4 數據**，不做顆粒度拆解、不做產能節流、不做
  技術可行性把關——這些是實際執行開發的 Rick/Morty 的職責，本 skill 越權
  判斷等於把決策從執行者手上拿走。
- 白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo。

## 不做什麼

- **不 approve、不 merge 任何 PR**——本 skill 完全不碰 PR，那是
  `acceptance-review` 掃 `agent-done` 之後的事。
- **不建 worktree、不切分支、不改程式碼**——只讀 issue 與 comment、改
  issue 描述文字、貼 Discord 訊息，以及人類點頭後的 label 操作。
- Discord 訊息維持精簡（2000 字上限），多張卡單或多個提議合併成一則摘要，
  不要逐張各發一則。
