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

### 段 1：`grill-me-done` → 排優先序、Discord 提議

```bash
gh issue list --repo wm4n/chainbreak --label grill-me-done --state open \
  --json number,title,comments
gh issue list --repo wm4n/hangman    --label grill-me-done --state open \
  --json number,title,comments
```

對每一張：

1. 在 `comments` 裡找 `jira-grill` 貼的「✅ 需求共識」comment（含背景、
   需求範圍、驗收條件、目標 repo）。**找不到這則 comment 視為異常**——
   跳過、記錄，不要改看 issue 標題／描述自己臆測需求範圍，那不是共識
   的內容。
2. 需要時跑一次 GA4 report（preset `overview` 通常夠用，用法同
   `product-planning` 的「拉 GA4 數據」一節，property 對應這張 issue
   所屬的 repo）評估這個需求現在的產品價值。
3. 彙整本輪掃到的所有 `grill-me-done` issue，依產品價值與 GA4 數據排出
   建議順序。

**完成條件是排序附得出理由**，不是排出一份清單就算數：Discord 訊息要寫
成「建議先做 #42，理由：<具體訊號或驗收條件>」，理由必須指得出是哪個
GA4 訊號或哪一點驗收條件的價值更高，不能只寫「感覺比較急」這種無法覆核
的說法。

這一段**只提議，不碰任何 label**。

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
3. Discord 提議「issue 描述已更新，建議改回 `ready-for-agent`」，附上改了
   什麼。

跟段 1 一樣，**這一段也只提議，不碰 label**——修好描述不代表可以直接放行
重跑，仍要等人類點頭。

### 段 3：`agent-active` → 逾時卡單告警

```bash
gh issue list --repo wm4n/chainbreak --label agent-active --state open \
  --json number,title,updatedAt
gh issue list --repo wm4n/hangman    --label agent-active --state open \
  --json number,title,updatedAt
```

對每一張，若 `updatedAt`（或最後一則 comment 時間，取較新者）距現在**超過
24 小時**，列為卡單，Discord 告警列出這些 issue 與卡了多久。

**這段只告警，不嘗試恢復**：`auto-dev-pipeline` 自己列出的已知限制是
`agent-active` 沒有逾時自動復原，pod 中途被殺會永久卡住——本 skill 的職責
到「讓人類知道有這張卡住了」為止，實際去 Mac mini／k3s 查 pod 狀態是人類
或另一個 runbook 的事，不在這裡處理。

## 鐵則

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
