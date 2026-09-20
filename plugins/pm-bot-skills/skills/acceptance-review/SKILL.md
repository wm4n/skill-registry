---
name: acceptance-review
argument-hint: "[<owner/repo>#<N>]"
description: >-
  掃描 agent-done issue 對應的 PR，逐條核對是否滿足當初的驗收條件（規格
  符合度，不是程式碼品質）。由規劃中的 usercron 平日 10:30 觸發（訊息
  「執行 acceptance-review skill」，sender_name＝SummerAcceptance；
  cronjob.toml 尚未寫入，見「已知限制」），或人類在 Discord 提出同類請求
  （如「驗收一下」「這張 PR 符合需求嗎」「看看 agent-done 的單」）時觸發：
  agent-done 是 auto-dev-pipeline 在 PR 開好、自我審查通過後才貼的
  label，代表「PR 已開、等人類 merge」。先查 PR 上有沒有已帶
  — By Summer (acceptance-review) 簽名的留言，有就跳過（冪等，不新增
  label）；沒有才讀 issue 的驗收條件與 PR 的 diff、描述，逐條標示滿足／
  不滿足／無法判斷，貼在 PR 上並附相同簽名，Discord 貼精簡結論摘要。
  只看規格符合度，不做 code review；不滿足時只提議、不自行改 label；
  永不 approve、永不 merge。
---

# Acceptance Review

> **本 skill 是責任鏈收尾前的最後一道檢查，不是最後一道閘門**：
> `agent-done` 代表 Rick/Morty 的 `auto-dev-pipeline` 已經自己審過一輪
> 程式碼（TDD、獨立 subagent code review）並開好 PR，本 skill 要回答的
> 是另一個維度的問題——**當初在 issue 上定案的需求，PR 真的做到了嗎**。
> 兩個維度刻意分開：code review 已經有人做過，這裡重做一次只會製造
> 角色衝突，也讓「規格對不對」這個真正還沒人看過的問題被稀釋掉。
> 唯一的人類閘門仍在 merge 這一步——本 skill 只提供判斷依據，
> **永不 approve、永不 merge**：這既是角色分工的設計決定，也是現實
> 限制——Summer 與 PR 作者目前共用同一個 wm4n GitHub 帳號，GitHub 本來
> 就不允許帳號 approve 自己開的 PR（見
> [wm4n/openab-ops#3](https://github.com/wm4n/openab-ops/issues/3)）。

## 觸發與參數

`$ARGUMENTS`：

- 空 → **掃全部**：對 `wm4n/chainbreak`、`wm4n/hangman` 兩個白名單 repo，
  各自列出所有帶 `agent-done` label 的 open issue。
- `<owner/repo>#<N>` → **只處理這一張**。若它目前沒有 `agent-done`
  label，說明「這張不在 agent-done 狀態」並停止，不要臆測要不要繼續看。

```bash
gh issue list --repo wm4n/chainbreak --label agent-done --state open \
  --json number,title,body,comments
gh issue list --repo wm4n/hangman    --label agent-done --state open \
  --json number,title,body,comments
```

### ⚠️ 先把參數拆開：`gh` 不吃 `owner/repo#N`

`gh issue`／`gh pr` 各子指令只接受 `{<number> | <url>}`，指定單張時先拆
成兩個變數，repo 用 `--repo` 旗標指定：

```bash
ISSUE_REF="wm4n/chainbreak#42"   # 從 $ARGUMENTS 取得
REPO="${ISSUE_REF%#*}"           # → wm4n/chainbreak
NUM="${ISSUE_REF##*#}"           # → 42
```

下面所有指令都用這組 `$REPO` / `$NUM`。

## 流程

對範圍內的每一張 `agent-done` issue，依序做完下面五步，任一步驟判定
「異常」就記錄下來、跳過這一張，繼續處理範圍內其餘的，不讓一張的問題
擋住整輪：

### 1. 找出對應 PR

`gh issue view` 沒有可靠的「這張 issue 對應哪個 PR」欄位，改成在
`comments`（`gh` 慣例是舊到新排序，最新一則是陣列最後一個）裡找
`auto-dev-pipeline` 完成時貼的收尾留言——它會包含一個
`https://github.com/<owner>/<repo>/pull/<N>` 形式的連結。取**最新**一則
含這種連結的留言。

**找不到視為異常**：`agent-done` 已經貼上卻找不到對應 PR 連結，代表
留言格式跟預期不符或流程中斷，記錄下來並跳過這張，不要憑 issue 標題
或猜測去湊一個 PR 編號。

### 2. 冪等檢查

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json number,title,body,url,comments
```

看 PR 的 `comments` 裡有沒有已經帶 `— By Summer (acceptance-review)`
簽名的留言：

- 有 → 這張已經驗收過（可能是排程重複觸發，也可能是驗收完還沒
  merge）→ **no-op 跳過**，不重貼，輸出盡量精簡。
- 沒有 → 繼續步驟 3。

### 3. 取得驗收條件

依序判斷來源，找到就停止往下找：

1. 若留言串裡有 `backlog-triage` 貼的「依 Rick/Morty 的規格問題調整了
   描述」留言（代表這張經歷過 `agent-failed` → 修描述 → 重新開發的
   迴圈），驗收條件以**目前 issue body** 的「## 驗收條件」段為準——
   那是最新版本，比留言串裡較早的版本可靠。
2. 否則以留言串裡 `jira-grill` 貼的「✅ 需求共識」comment 所列的驗收
   條件為準。
3. 兩者都找不到 → 視為異常，記錄並跳過，不要憑 issue 標題或描述自己
   腦補一組驗收條件。

### 4. 取得 PR 內容

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json number,title,body,url
gh pr diff "$PR_NUM" --repo "$REPO"
```

只需要文字 diff 與 PR 描述，**不 clone repo、不建 worktree、不切
分支**——這支 skill 讀規格符合度，不需要在本地執行或瀏覽完整程式碼庫。

### 5. 逐條比對並輸出

對步驟 3 找到的驗收條件清單，**逐條**對照步驟 4 的 diff 與描述，三選一
判定：

- ✅ **滿足**：diff 或描述明確做到了這一條，寫下具體依據（改了哪個
  檔案／哪段邏輯）。
- ❌ **不滿足**：diff 或描述看不出做到，或明確跟這一條衝突，寫下缺了
  什麼。
- ❓ **無法判斷**：光看 diff 與描述無法確認（例如要求的是執行期行為，
  純讀程式碼看不出結果），寫下為什麼判斷不了，**不要為了湊出結論硬猜
  一個滿足或不滿足**。

按下方模板貼 PR comment，並把這輪處理過的（含跳過的、含異常的）彙整成
**一則** Discord 摘要——同一輪掃到多張，合併成一則訊息，不要逐張各發
一則（同 `backlog-triage` 的慣例，也是避免 Discord 2000 字限制被輕易
用完的做法）。

## 送回開發（人類點頭後才執行）

若某張的結果含「不滿足」，PR comment 與 Discord 摘要都只**提議**送回
`ready-for-agent`，不自行改 label。只有人類在後續對話明確點頭（例如
「同意，退回去修」「送回 ready-for-agent」）之後，才在**後續 turn**
執行：

```bash
gh issue edit "$NUM" --repo "$REPO" --add-label ready-for-agent
gh issue edit "$NUM" --repo "$REPO" --remove-label agent-done
```

**先加後移除**（同 `backlog-triage` 既有的順序鐵則）：中間若失敗，至少
不會讓這張 issue 兩個 label 都沒有、變成沒有任何 poller 撿得到。改完
label 後，在 issue 上貼一則說明「驗收發現哪些條件不滿足、經人類確認
送回開發」的留言，簽名用一般的 `— By Summer`（不是
`— By Summer (acceptance-review)`——這是新一輪處理的起點，不是同一次
驗收紀錄的延伸）。

**已開的舊 PR 不會自動關閉**，要不要關閉、要不要留著給下一輪開發參考，
留給人類決定，本 skill 不處理。

## PR comment 模板與簽名協定

```
## 驗收結果

對照 issue #<N> 的驗收條件：

| # | 驗收條件 | 結果 | 依據 |
| --- | --- | --- | --- |
| 1 | <驗收條件原文> | ✅ 滿足 | <引用具體改動或 PR 描述段落> |
| 2 | <驗收條件原文> | ❌ 不滿足 | <說明缺了什麼> |
| 3 | <驗收條件原文> | ❓ 無法判斷 | <說明為何從 diff／描述判斷不出來> |

總結：<M> 條中滿足 <X> 條、不滿足 <Y> 條、無法判斷 <Z> 條。

---
— By Summer (acceptance-review)
```

**簽名字串一律逐字使用 `— By Summer (acceptance-review)`**（開頭是 em
dash「—」，不是連字號「-」；括號裡固定是 `acceptance-review`）。這串
簽名同時是步驟 2 的冪等依據，改了格式下一輪掃描會判斷失準——同一張會
被重複驗收，或反過來被誤判成已驗收而永遠跳過。

⚠️ **不可以誤用 `jira-grill` 的 `(jira-grill)` 結尾**，即便如此，
`gh issue list` 預設不會回傳 PR（PR 在 GitHub API 裡雖然底層也是
issue，但 `gh` CLI 的 issue 子指令會過濾掉它們），所以貼在 PR 上的這則
留言本來就不在 `grill-poller`／`agent-dev-poller` 任何一個以
issue label 為條件的掃描範圍內，不會誤觸發它們。

## Discord 摘要模板

只放結論與可定位的 issue／PR 編號（`repo#N`／`PR #N`，白名單只有兩個
repo，不需要完整 URL 也能定位），完整的逐條依據留在 PR 留言裡：

```
📋 驗收完成 <M> 張：
✅ chainbreak#12（PR #34）— 3/3 滿足
⚠️ hangman#8（PR #19）— 2/3 滿足，1 條不滿足（結算頁未做防抖），
   建議送回 ready-for-agent，待人類點頭
（跳過 2 張：已驗收過或找不到對應 PR，詳見各自 PR／issue）
```

單輪超過約 8 張時，只列前幾張的細節，其餘改成「還有 N 張，結果同上
分類，詳見各自 PR 留言」——避免逐張列到超過 Discord 2000 字上限。

## 鐵則

- **只看規格符合度，不做 code review**——那是 Rick/Morty
  `auto-dev-pipeline` 步驟 6 自我審查的職責。不評論程式碼風格、效能、
  測試覆蓋率、命名，只回答「PR 做出來的東西是不是當初 issue 定案的
  需求」。
- **不滿足時只提議、不自行改 label**——`ready-for-agent` 是整條閉環的
  人類閘門，見上方「送回開發」一節，要等人類明確點頭才動手。
- **永不 approve、永不 merge**——見文首說明，這是角色分工的設計決定，
  不只是帳號限制帶來的技術死結；即便未來
  [wm4n/openab-ops#3](https://github.com/wm4n/openab-ops/issues/3)
  的帳號分離落地、技術上能 approve 了，這條鐵則依然不變。
- **冪等靠簽名，不靠 label**：不新增任何 label 當作「已驗收」的標記，
  判斷依據就是 PR 上那則帶 `— By Summer (acceptance-review)` 簽名的
  留言存不存在。
- 白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo。

## 不做什麼

- **不做 code review**、不檢查程式碼風格、效能、測試覆蓋率——那些是
  Rick/Morty 自我審查該做的事。
- **不 approve、不 merge 任何 PR**。
- **不自行貼／移除 `ready-for-agent`、`agent-done`**，除非人類已在
  Discord 明確點頭送回開發（見「送回開發」）。
- **不 clone repo、不建 worktree、不切分支**——`gh pr diff` 讀到的文字
  diff 就夠。
- **不逐張各發一則 Discord 訊息**——同一輪的結果彙整成一則摘要。

## 已知限制

- **簽名冪等不辨識「PR 有沒有更新過」**：PR 驗收後若又被推了新
  commit，留言裡的簽名依然存在，下一輪掃描仍會判定「已驗收」而跳過。
  想要求重新驗收，目前只能由人類指名單張參數
  `<owner/repo>#<N>` 觸發，並在 PR 上額外說明要重新驗收——這裡沒有
  「先刪舊留言再重跑」的自動機制，是刻意接受的限制。
- **PR 連結靠留言文字比對，不是 GitHub 原生的關聯欄位**：若
  `auto-dev-pipeline` 收尾留言的措辭改了、不再包含可辨識的 PR 連結，
  步驟 1 的比對邏輯要跟著更新。
- **驗收發現不滿足、人類點頭送回開發後，舊 PR 不會自動關閉**，處理方式
  留給人類決定。
- **與 GitHub 帳號共用問題同源於
  [wm4n/openab-ops#3](https://github.com/wm4n/openab-ops/issues/3)**：
  待該 issue 的帳號分離方案落地後，approve 的技術限制才會解除，但如
  「鐵則」所述，本 skill「永不 approve」本身是角色分工的設計決定，
  不會因此改變。
