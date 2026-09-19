---
name: grill-respond
argument-hint: "github-issue <owner/repo#N>"
description: >-
  回答 Rick/Morty 用 jira-grill 對 Summer 開的需求 issue 提出的逼問。由獨立
  部署的 summer-grill-responder（Mac cron，不含 LLM）偵測到 issue 最後一則
  留言帶 (jira-grill) 簽名時，用專屬 Discord 訊息觸發（不是人類
  @mention）：讀完整 issue 與留言，逐題回答最新一輪規格類問題，需要人類
  商業判斷的明說「這題要人類決定」並 @ issue author、不硬掰，貼一則以
  — By Summer (grill-respond) 結尾的回覆——這串簽名是 grill-poller.sh
  判斷「該不該換 Rick/Morty 問下一輪」的唯一依據，絕不能用 jira-grill 的
  (jira-grill) 簽名收尾。不改 label、不開發、不碰程式碼、不開 PR。
---

# Grill Respond

> **本 skill 是 `jira-grill` 的另一半**：Rick/Morty 在 issue 上用
> `jira-grill` 連續追問，Summer 用這支 skill 回答。兩邊靠 comment 結尾的
> **簽名協定**互相辨識輪到誰——簽名寫錯，整套機制會無聲失效（見下方
> 「回覆格式與簽名協定」）。來源只有 GitHub issue 一種（Summer 的需求單
> 都開在 GitHub，沒有 Jira 分支）。

**本 skill 假設過濾已經做完**：`summer-grill-responder` 只在「issue body
含 `— By Summer`（這是 Summer 開的單）且最新留言含 `(jira-grill)` 簽名」
兩個條件都成立時才觸發這支 skill。執行到這裡，不必也不要重複判斷這兩點，
只管讀最新那一輪問題、作答、貼出去。

## 觸發與參數

`$ARGUMENTS` 固定形狀 `github-issue <owner/repo#N>`（例如
`github-issue wm4n/chainbreak#42`），由 `summer-grill-responder` 貼出下面
這則 Discord 訊息觸發——**不是人類 @mention**：

```
執行 grill-respond skill，參數：github-issue <owner/repo>#<number>
```

### ⚠️ 先把參數拆開：`gh` 不吃 `owner/repo#N`

`gh issue` 各子指令只接受 `{<number> | <url>}`，直接把 `owner/repo#N` 丟
進去會得到 `invalid issue format`（`jira-grill` 的「GitHub API 慣例」一節
有同一個坑）。每次都先拆成兩個變數，repo 用 `--repo` 旗標指定：

```bash
ISSUE_REF="wm4n/chainbreak#42"   # 從 $ARGUMENTS 取得
REPO="${ISSUE_REF%#*}"           # → wm4n/chainbreak
NUM="${ISSUE_REF##*#}"           # → 42
```

下面所有指令都用這組 `$REPO` / `$NUM`。

## 流程

1. **拆參數**：見上方「先把參數拆開」，得到 `$REPO`／`$NUM`。

2. **確認留言權限**：開始讀 issue、分析問題**之前**，先確認目前帳號對
   `$REPO` 有留言權限：

   ```bash
   gh auth status
   gh api "repos/${REPO}" --jq '.permissions' 2>/dev/null || echo "NO_ACCESS"
   ```

   每次執行都重新檢查，不假設沿用之前某次觸發（例如 `product-planning`
   開單當下）已經確認過的權限——PAT 可能被輪替或收回，而同一張單的
   grill 可能橫跨數天。

   ⚠️ **這是最容易卡住的地方**：能讀 issue ≠ 能留言。若目前帳號的 PAT
   沒有 `Issues: Read and write`，前面的分析全部會做完、最後貼留言那一
   步才失敗，白燒一整輪（`jira-grill` 的「GitHub 來源」踩過同一個坑）。
   **發現沒有權限就立刻停止並明講缺什麼，不要先做完分析再撞牆。**

3. **讀 issue 全文與留言**：

   ```bash
   gh issue view "$NUM" --repo "$REPO" \
     --json number,title,body,labels,author,comments
   ```

   ⚠️ **排序陷阱**：`comments` 是**舊到新**排序，最新一則是陣列的**最後
   一個**，不是第一個——這是兩種留言來源之間最容易寫反的地方（`jira-grill`
   讀 Jira 留言是新到舊，方向相反）。

4. **重複觸發防護**：檢查最新那一則留言（陣列最後一個）的結尾是不是已經
   是自己的簽名 `— By Summer (grill-respond)`。
   - 是 → 代表這次觸發是 race 造成的重複觸發（上一輪回覆已經貼出，
     `summer-grill-responder` 卻又觸發一次）→ **no-op 結束**，輸出盡量
     精簡以控制成本。
   - 不是 → 繼續步驟 5。

5. **找出要回答的提問**：最新那一則留言就是 Rick/Morty 這一輪的
   `(jira-grill)` 提問，逐一找出裡面的 `❓ **Qn** - **<標題>**：<內容>`
   區塊。一個都找不到 → 不是預期格式，說明狀況並停止，不要臆測要回答
   什麼。

6. **逐題作答**：只回答步驟 5 找到的這一輪問題，逐題對應，不多答、不少
   答。判斷依據是 issue 的標題／描述／驗收條件、留言串裡累積的脈絡，以及
   Summer 對產品與數據的判斷——不需要讀程式碼或 clone repo（Summer 開的
   單設計上只問規格類問題，見設計文件「Label 狀態機」的決策 #5）。

   **答不出來的處理**：凡是需要人類做商業決定的題目（例如砍不砍某個範圍、
   要不要多花預算、上線時間怎麼取捨）——**明說「這題要人類決定」，
   `@` 該 issue 的 author（`gh issue view` 讀到的 `author.login`，真正
   會觸發 GitHub 通知），不硬掰答案**。硬掰一個聽起來合理但沒有依據的
   答案，比誠實承認「不知道」更糟：對方會照著錯的答案往下做。

7. **組回覆並貼出**：格式與簽名見下方「回覆格式與簽名協定」，最後執行：

   ```bash
   if ! COMMENT_OUTPUT=$(gh issue comment "$NUM" --repo "$REPO" \
       --body "$COMMENT_BODY" 2>&1); then
     echo "ERROR: 貼留言失敗 issue=${REPO}#${NUM}"
     echo "$COMMENT_OUTPUT"
   fi
   ```

   貼留言失敗時，照上面這樣印出**明確包含 issue 編號與 `gh` 原始錯誤
   輸出**的訊息就停止，不要重試、也不要安靜結束。這支 skill 是無人
   看管的自動觸發：`summer-grill-responder` 一觸發就記下這則留言的 id
   （`summer-grill-responder.sh` 的 `mark_responded`），**不等這裡回覆
   成功**，所以貼留言失敗不會被自動重試。若這裡的失敗只是安靜結束，
   後果跟簽名寫錯一樣——整條 grill 靜悄悄停住、沒有人會發現，只是失敗點
   從簽名比對換成了這一步。印出清楚的錯誤訊息，是讓人翻 log 時還能發現、
   手動補救的唯一機會。

## 回覆格式與簽名協定（不可搞錯的一段）

逐題對照 `jira-grill` 的 `❓`／`➡️` 風格，先複述問題再回答，能答的每題一組：

```
❓ **Q1** - **<原問題標題>**

💬 <Summer 的回答>
```

答不出來、需要人類決定的題目用 `🙋` 取代 `💬`：

```
❓ **Q1** - **<原問題標題>**

🙋 這題要人類決定 — @<issue author 的 login>
```

多題就重複這組區塊，全部答完後，結尾固定收在同一行：

```
---
— By Summer (grill-respond)
```

**簽名字串一律逐字使用 `— By Summer (grill-respond)`**（開頭是 em dash
「—」，不是連字號「-」；括號裡固定是 `grill-respond`，不代入其他值）。

⚠️ **絕對不可以讓這則回覆用 `(jira-grill)` 結尾**——那是 Rick/Morty 的
簽名，不是 Summer 的。`grill-poller.sh` 靠「最後一則留言是不是
`(jira-grill)` 簽名」判斷該不該觸發 Rick/Morty 問下一輪；一旦這裡簽錯成
`(jira-grill)`，`grill-poller.sh` 會誤判成「Rick/Morty 剛剛已經回過
了」而不再觸發，**整條 grill 會靜悄悄停在這裡，沒有任何錯誤訊息、沒有人
會發現**，直到很久以後有人手動去翻 issue 才會注意到。

## 不做什麼

- **不改任何 label**（`grill-me-active` → `grill-me-done` 的轉換歸
  `jira-grill` 那側，看到規格 frontier 清空是它的判斷，不是這支 skill
  的責任）。
- **不開發、不碰程式碼、不開 PR**——這支 skill 只回答問題，不做任何
  工程動作。
- **不主動起新的問題或幫忙補問題**——只回答步驟 4 找到的那一輪，其餘一律
  留給 `jira-grill` 下一輪自己決定要不要問。
