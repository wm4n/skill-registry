---
name: pr-review-response
argument-hint: "pr-review <owner>/<repo>#<pr>"
description: >-
  收到 `pr-review <owner>/<repo>#<pr>` 觸發訊息時使用（pr-review-poller 自動
  觸發，或人類在 Discord 手打）：回到該 PR 的原分支，逐條回應人類按
  Request changes 留下的 review 意見——預設直接改、補 commit、push 回原分支；
  意見有歧義、超出原 issue 範圍、或技術上不認同時改成回 comment 說明。
  Rick／Morty／Genie 共用，不屬於任何 pipeline。
---

# pr-review-response

人類在 bot 開的 PR 上按 Request changes 之後，由這支 skill 讓 bot 回到原分支
把意見處理完。**PR 本身是唯一真相來源**：每次執行都重新從 GitHub 讀 PR、review
與留言判斷要做什麼，不依賴 session 記憶，也不假設本地還留著當初開發用的
worktree（persona 的 Repo 工作隔離規定 PR 開好就清掉 worktree）。

`<Bot>` 在本文件裡一律代入**執行本 skill 的 bot 自己的名字**（Rick／Morty／Genie）。

## 留言標記與簽名（poller 與本 skill 都靠這段判斷狀態）

本 skill 在 PR 上貼的每一則 PR 層級留言，**第一行**是下列三個標記之一，
**結尾**是簽名 `— By <Bot> (pr-review-response)`：

| 標記（第一行，逐字） | 何時貼 | 誰讀它 |
| --- | --- | --- |
| `<!-- pr-review-response:start -->` | 步驟 2，接手的第一個動作 | poller；步驟 1 的並行防護 |
| `<!-- pr-review-response:done -->` | 步驟 7，處理完 | poller；步驟 1 算待處理 review |
| `<!-- pr-review-response:failed -->` | 失敗時（見「失敗處理」） | poller；人類；步驟 1 的並行防護 |

- 標記是 HTML 註解，GitHub 畫面上看不到、API 的 `body` 裡原樣保留。標記後面接給
  人看的正文。
- **狀態只認標記，不認簽名**：review thread 裡的回覆也帶同一個簽名，但不帶標記，
  不代表任何狀態。
- **poller 怎麼讀**：三種標記的最新時間都算「已處理」，review 比它新才觸發；
  最新標記是 `start`、超過 TTL 且之後沒有新 commit，才當成卡住重新觸發。所以
  每一輪都要以 `done` 或 `failed` 收尾——停在 `start` 的一輪會在 TTL 後被重跑。
- 簽名開頭是 em dash（U+2014）「—」。Genie 也用這個簽名，不用 persona 平常的
  `— Instructed by …`——同 `auto-dev-pipeline`，這串文字是給程式比對的。
- 標記與簽名都直接複製本文件裡的字串，不要自己重打。

## 步驟

### 1. 解析參數與前置檢查（全部是輕量 API 呼叫）

1. **解析 `$ARGUMENTS`**：形狀必須是 `pr-review <owner>/<repo>#<pr>`（例：
   `pr-review wm4n/chainbreak#42`）。拆出 `REPO=<owner>/<repo>`、`PR=<pr>`。
   形狀不符 → 在 Discord 回覆正確格式並結束，不要臆測。
2. **帳號選擇（persona 優先）**：persona（`{home}/CLAUDE.md`／`AGENTS.md`）有為
   這個 repo owner 定義固定帳號規則（例如 Genie 的「104corp 固定用 104cac 帳號」）
   → `gh auth switch` 到該帳號；沒有 → 用 `repo-identity` skill 依 owner 選帳號。
3. **讀 PR 與權限**：

   ```bash
   gh pr view "$PR" --repo "$REPO" \
     --json number,url,state,headRefName,isCrossRepository,closingIssuesReferences
   gh api "repos/${REPO}" --jq '.permissions.push'
   gh api "repos/${REPO}/pulls/${PR}/reviews" --paginate
   gh api "repos/${REPO}/issues/${PR}/comments" --paginate   # PR 層級留言
   gh api "repos/${REPO}/pulls/${PR}/comments" --paginate    # line comments 與 thread 回覆
   ```

   - `state` 不是 `OPEN` → Discord 回覆「PR 已 merge／關閉，不處理」並結束。
   - `isCrossRepository` 是 `true`，或 `.permissions.push` 不是 `true` → 推不回原
     分支：貼 `failed` 留言說明缺什麼權限（格式見「失敗處理」，不用清 worktree），
     Discord 回報後結束。這個失敗要人類處理，留言也讓 poller 不再重觸發同一則 review。
4. **並行防護**：自己的標記留言裡，最新一則是 `start`、而且貼出不到 2 小時
   → 另一輪還在跑，Discord 回覆「另一輪處理中（開始於 <時間>），2 小時後仍無
   結果可再觸發」並結束。2 小時是 `pr-review-poller` 的 `PR_REVIEW_TTL_HOURS`
   預設值；poller 的 TTL 改了，這裡跟著改成同一個值。
5. **算出這一輪要處理什麼**，兩種來源：
   - **待處理 review**：`reviews` 裡 `state == "CHANGES_REQUESTED"`、而且 `id`
     沒有出現在任何一則自己的 `done` 留言「已處理 review」那一行裡的。
   - **待續 thread**：line comment thread 裡有自己帶本 skill 簽名的回覆（前幾輪
     「問」或「反駁」留下的），而且 thread 最新一則不是自己的——人類回覆了。

   兩種都沒有 → Discord 回覆「沒有尚未回應的 review」並結束。

除了權限失敗，以上「結束」都不貼任何標記留言。

### 2. 貼處理中留言

**在 clone、讀 diff、跑測試這些耗時動作之前**先貼，否則 poller 在這一輪跑完前
會再觸發一次：

```bash
gh pr comment "$PR" --repo "$REPO" --body-file - <<'EOF'
<!-- pr-review-response:start -->
🔧 收到 review，開始處理：<待處理 review 的作者與 id、待續 thread 的連結>

— By <Bot> (pr-review-response)
EOF
```

貼出之後，任何失敗都走「失敗處理」，一定要留下 `failed` 留言才能結束。

### 3. 重新準備 PR 分支的 worktree

不假設本地有任何殘留狀態，每次都從遠端重建：

```bash
BASE=/home/node/repos/<owner>/<repo>
WT=/home/node/repos/<owner>/<repo>-worktrees/pr-<pr>-review
[ -d "$BASE/.git" ] || gh repo clone "$REPO" "$BASE"
git -C "$BASE" fetch origin
git -C "$BASE" worktree prune
git -C "$BASE" worktree add -B "<headRefName>" "$WT" "origin/<headRefName>"
```

然後照 persona 的「開工前準備」：讀該 repo 的 `CLAUDE.md`／`AGENTS.md` 與可用
skill、需要時 `mise install` 或走 Docker 流程。`worktree add` 失敗（例如該分支
仍被別的 worktree 佔用）→ 失敗處理。

### 4. 讀取這一輪的所有項目

這一輪要處理的**項目**有三種：

- 每則待處理 review 的本文（`body`，非空時算一個項目）。
- 每則待處理 review 的 line comments，一則一個項目：步驟 1 抓到的
  `pulls/${PR}/comments` 裡 `pull_request_review_id` 等於該 review `id` 的。
  同一條 thread 裡人類後續的回覆（`in_reply_to_id` 指向該則）一起讀，它們是
  同一個項目的補充說明。
- 步驟 1 找到的每條待續 thread（整條 thread 讀完，人類的最新回覆就是這次要
  回應的內容）。

同時讀 PR 的 diff（`gh pr diff`）與 `closingIssuesReferences` 指到的原 issue
全文（`gh issue view`），後面判斷「超出範圍」要用。

### 5. 逐項判斷並處理

**每個項目恰好落在下列一種結果**，並且每個項目都要有結果——這一步的完成條件是
「步驟 4 列出的所有項目都有結果」：

| 結果 | 什麼時候 | 做什麼 |
| --- | --- | --- |
| **改** | 預設。意見明確、在原 issue 範圍內、你也認同 | 在 worktree 修改，照該 repo 的規範跑測試 |
| **問** | 意見有兩種以上合理讀法，選錯會做白工 | 回覆提問，列出你看到的讀法，這項先不改 |
| **超出範圍** | 意見要的東西不在原 issue 的需求裡 | 回覆指出超出範圍、建議另開 issue，這項不改 |
| **反駁** | 技術上不認同（會引入 bug、違反 repo 規範、與既有設計衝突…） | 回覆說明理由與你建議的做法，等人類回覆，這項先不改 |

- 「問」只留給真的有歧義的意見：每條都先問，人類就得再講一次話，這支 skill
  就白做了。
- 不認同就走「反駁」，讓人類決定：照做一個自己知道有問題的改法、或不吭聲地
  跳過，兩者都不是可接受的結果。
- **超出範圍的原 issue 連結**：`closingIssuesReferences` 有值 → 附上該 issue
  連結；是空的 → 照樣指出「超出這個 PR 當初的範圍」，只是不附連結。不要從 PR
  標題或內文裡提到的 issue 編號去猜——PR 常提到別張 issue，猜錯比不附更糟。
- **回覆位置**：line comment 與待續 thread 的項目回在該 thread 裡
  （`gh api "repos/${REPO}/pulls/${PR}/comments/<comment id>/replies" -f body=...`，
  `<comment id>` 用 thread 第一則的 id）；review 本文的項目寫進步驟 7 的完成留言。
  每則回覆結尾都帶簽名 `— By <Bot> (pr-review-response)`，不帶標記。
- **問、反駁的回覆要告訴人類怎麼接續**：結尾寫「回覆這則後，再按一次 Request
  changes 或在 Discord 打 `pr-review <REPO>#<PR>`，我會接著處理」——thread 回覆
  本身不會觸發 poller。「改」完成的待續 thread 也回一則說明改了什麼、commit SHA。

### 6. commit 與 push

所有指令都在 `$WT` 裡執行。

1. 「改」的項目照該 repo 的 commit 規範 commit；commit 訊息提到對應的 review 意見。
2. push 前跑一次該 repo 規定的測試／建置，全過才 push。
3. `git -C "$WT" push origin HEAD:<headRefName>`。被拒（遠端有新 commit）→
   `git -C "$WT" pull --rebase origin <headRefName>`、重跑測試、再 push 一次；
   還是失敗或 rebase 有衝突 → 失敗處理。

沒有任何「改」的項目（全部是問／超出範圍／反駁）→ 跳過本步驟。

### 7. 貼完成留言

```bash
gh pr comment "$PR" --repo "$REPO" --body-file - <<'EOF'
<!-- pr-review-response:done -->
@<這一輪回應到的每位人類> review 意見處理完畢：

- 改：<項目摘要> → <commit SHA>
- 問：<項目摘要>（見 thread）
- 超出範圍：<項目摘要>（建議另開 issue，原 issue：<連結或「查不到原 issue」>）
- 反駁：<項目摘要>（理由見 thread）
<review 本文項目的回覆，若有>

已處理 review：<待處理 review 的 id，逗號分隔>

— By <Bot> (pr-review-response)
EOF
```

「已處理 review」這一行是下一輪步驟 1 算待處理 review 的依據，只列**這一輪**
的待處理 review id，格式逐字照抄；這一輪只有待續 thread、沒有待處理 review 時寫
`已處理 review：無`。

### 8. 清理 worktree 並回報

```bash
git -C "$BASE" worktree remove --force "$WT"
git -C "$BASE" worktree prune
```

在觸發這次任務的 Discord thread 精簡回報：PR 連結、改／問／超出範圍／反駁各幾項。

## 失敗處理

步驟 2 之後任何一步失敗（worktree 建不起來、測試修不過、push 失敗、API 錯誤…）：

1. 貼失敗留言，說明卡在哪一步、錯誤訊息、已經做完哪些項目（已 push 的 commit
   SHA）。
2. 清理 worktree（步驟 8）。
3. Discord 回報失敗與 PR 連結。

```bash
gh pr comment "$PR" --repo "$REPO" --body-file - <<'EOF'
<!-- pr-review-response:failed -->
⚠️ review 處理中斷：<卡在哪一步、錯誤訊息、已完成的項目>

— By <Bot> (pr-review-response)
EOF
```

失敗留言**不列「已處理 review」**：poller 不會自動重跑失敗的一輪（`failed` 算
已處理），由人類排除原因後手打 `pr-review` 重新觸發，那一輪會重新處理同一批
review；已經 push 的修改在讀 diff 時會看到，判斷為已完成即可。

## 範圍

- 動作只限於：在 PR 分支上 commit／push、在 PR 上留言與回覆 thread。
- issue 與 PR 的 label、review 狀態（approve／dismiss／resolve thread）、merge
  與關閉 PR 都留給人類——label 的語意屬於 Summer 的需求驗收流程，這裡動了會讓
  那邊的狀態機出錯。
- 只 push 到 PR 原本的分支，不 force push。
