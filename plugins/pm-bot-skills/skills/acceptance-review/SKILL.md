---
name: acceptance-review
argument-hint: "[<owner/repo>#<N>]"
description: >-
  掃描 agent-done issue 對應的 PR，逐條核對是否滿足當初的驗收條件（規格
  符合度，不是程式碼品質）。由規劃中的 usercron 平日 10:30 觸發（訊息
  「執行 acceptance-review skill」，sender_name＝SummerAcceptance；
  cronjob.toml 尚未寫入，見「已知限制」），或人類在 Discord 提出同類請求
  （如「驗收一下」「這張 PR 符合需求嗎」「看看 agent-done 的單」）時觸發：
  agent-done 代表 Rick/Morty 走完 solo-feature-pipeline（經 persona §4b
  自動觸發、跳過確認閘門）開完 PR、自我審查通過的狀態——這條標籤鏈目前
  有已知缺口（成功路徑還沒有貼這個 label 的步驟，見「已知限制」），本
  skill 因此把「掃到 0 張」與「找不到對應 PR」都設計成看得見、不跟正常
  的冪等跳過混在一起。先查 PR 上有沒有已帶
  — By Summer (acceptance-review) 簽名的留言，有就跳過（冪等，不新增
  label）；沒有才以留言串裡「✅ 需求共識」comment 為基準取得驗收條件，
  讀 PR 的 diff、描述逐條標示滿足／不滿足／無法判斷，貼在 PR 上並附
  相同簽名，Discord 分類貼精簡結論摘要。只看規格符合度，
  不做 code review；不滿足時只提議、不自行改 label；永不 approve、
  永不 merge。
---

# Acceptance Review

> **本 skill 是責任鏈收尾前的最後一道檢查，不是最後一道閘門**：
> `agent-done` 代表 Rick/Morty 透過 `solo-feature-pipeline`（經 persona
> `Rick-CLAUDE_v2.md` §4b 自動觸發、跳過確認閘門）自己審過一輪程式碼
> （TDD、獨立 subagent code review）並開好 PR，本 skill 要回答的是
> 另一個維度的問題——**當初在 issue 上定案的需求，PR 真的做到了嗎**。
> 兩個維度刻意分開：code review 已經有人做過，這裡重做一次只會製造
> 角色衝突，也讓「規格對不對」這個真正還沒人看過的問題被稀釋掉。
> 唯一的人類閘門仍在 merge 這一步——本 skill 只提供判斷依據，
> **永不 approve、永不 merge**：這既是角色分工的設計決定，也是現實
> 限制——Summer 與 PR 作者目前共用同一個 wm4n GitHub 帳號，GitHub 本來
> 就不允許帳號 approve 自己開的 PR（見
> [wm4n/openab-ops#3](https://github.com/wm4n/openab-ops/issues/3)）。
>
> ⚠️ **`agent-done` 目前可能完全不會被貼上**：`solo-feature-pipeline`
> 步驟 6「建 PR + 通知」與 persona `Rick-CLAUDE_v2.md` §4b 的成功路徑，
> 目前都沒有寫「開完 PR 後貼 agent-done」這一步——§4b 只在**失敗**路徑
> 提到 label（改成 `agent-failed`），成功路徑完全沒提。補齊這段是另一個
> 任務的責任，不是本 skill 要修的範圍；但下方每一步刻意把「掃不到東西」
> 設計成看得見、不會安靜空轉（見「流程」步驟 0 與「已知限制」），這樣
> 缺口還沒補齊、或補齊後又鬆脫，都不會被忽略。

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

### 0. 定範圍，「零筆」與三類結果的分類

先依「觸發與參數」的查詢列出範圍內所有 `agent-done` issue，記下這輪的
張數 `$TOTAL`：

- **掃全部時 `$TOTAL` = 0**（兩個白名單 repo 都沒有任何 `agent-done`
  issue）→ **不要就這樣結束**。這代表兩種可能：(a) 這段期間真的沒有
  PR 完成到可以驗收的狀態，是正常的；(b) `agent-done` 這條標籤鏈斷了
  （見文首 ⚠️ 已知缺口），Rick/Morty 完成的 PR 根本沒被貼上這個
  label，本 skill 永遠看不到。這兩種情況在 Discord 上看起來會一模
  一樣（都是「沒有要驗收的」），所以**每次掃全部都要明確發一則
  Discord 訊息**講出「本輪掃描 agent-done：0 張」，不要默默什麼都不
  做——連續多輪都是 0 張，就是提醒人類去確認標籤鏈是否正常運作的訊號。
- `$TOTAL` > 0 → 對每一張依序做完下面步驟 1–5。每一張的結果最終只
  會落在三類之一，這三類在 Discord 摘要裡**分開列，不合併成一句籠統
  的「跳過 N 張」**（模板見「Discord 摘要模板」）：
  1. **本輪驗收完成**：走完步驟 1–5，貼出逐條對照表。
  2. **跳過（正常冪等）**：步驟 2 判定已經驗收過。
  3. **異常（需要人類關注）**：步驟 1 找不到對應 PR，或步驟 3 找不到
     驗收條件來源。這不是正常跳過，是需要人看見的訊號，尤其在標籤鏈
     缺口還沒補齊的現階段，「異常」的張數本身就是判斷缺口有沒有修好
     的觀察指標。

### 1. 找出對應 PR

`gh issue view` 沒有可靠的「這張 issue 對應哪個 PR」欄位，改成在
`comments`（`gh` 慣例是舊到新排序，最新一則是陣列最後一個）裡找
Rick/Morty 完成開發時貼的收尾留言（`solo-feature-pipeline` 步驟 6
「建 PR + 通知」——見文首已知缺口，這一步的留言格式屬於待補齊的部分，
一旦補齊預期會包含 PR 連結）——它會包含一個
`https://github.com/<owner>/<repo>/pull/<N>` 形式的連結。取**最新**一則
含這種連結的留言。

**找不到歸類為「異常」，不是「跳過」**（見步驟 0 的分類）：`agent-done`
已經貼上卻找不到對應 PR 連結，代表留言格式跟預期不符、流程中斷，或者
這張根本不是走正常路徑貼上這個 label 的。記錄下來，繼續處理範圍內
其餘 issue，但在 Discord 摘要裡要單獨列出，不要跟「已驗收過」的正常
跳過混在一起——不要憑 issue 標題或猜測去湊一個 PR 編號。

### 2. 冪等檢查

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json number,title,body,url,comments
```

看 PR 的 `comments` 裡有沒有已經帶 `— By Summer (acceptance-review)`
簽名的留言：

- 有 → 這張已經驗收過（可能是排程重複觸發，也可能是驗收完還沒
  merge）→ **跳過（正常冪等，不是異常）**，不重貼，輸出盡量精簡，
  Discord 摘要歸進「跳過」那一類。
- 沒有 → 繼續步驟 3。

### 3. 取得驗收條件——以「✅ 需求共識」為基準，疊加增量修正

`jira-grill` **從不寫回 issue body**——body 從頭到尾是 `product-planning`
（或人類）開單當下的原始草稿。留言串裡 `jira-grill` 貼的「✅ 需求
共識」comment，才是把整輪 grill Q&A **蒸餾**成的最終需求（背景、確認
的需求範圍、驗收條件、目標 repo），涵蓋範圍比原始 body 完整。

1. 以留言串裡「✅ 需求共識」comment 所列的驗收條件為**基準清單**。
   找不到這則 comment → 歸類為「異常」（見步驟 0），記錄並跳過，不要
   憑 issue 標題或描述自己腦補一組驗收條件。
2. 若留言串裡還有 `backlog-triage` 貼的「依 Rick/Morty 的規格問題
   調整了描述，變更摘要：……」留言（代表這張經歷過 `agent-failed` →
   修描述 → 重新開發的迴圈），把該留言點名的異動（新增、刪除或修改了
   哪一條）疊加到步驟 1 的基準清單上，得出目前應該逐條核對的完整
   清單。**不要改用目前的 issue body 整個取代基準**：body 只有
   `backlog-triage` 動過的那個缺口是新的，其餘部分是開單當下的原始
   草稿，精煉程度不如「✅ 需求共識」——直接改用 body 會遺失 grill
   階段對其他條件的精煉結果。
3. 沒有 `backlog-triage` 的變更留言 → 步驟 1 的基準清單就是最終清單，
   不用再對照 body。

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

按下方模板貼 PR comment，並把這輪的結果依步驟 0 的三個分類（本輪驗收
完成／跳過／異常）彙整成**一則** Discord 摘要——同一輪掃到多張，合併
成一則訊息，不要逐張各發一則（同 `backlog-triage` 的慣例，也是避免
Discord 2000 字限制被輕易用完的做法），但三個分類要分開列，不要把
「跳過」跟「異常」揉成同一句籠統的「跳過 N 張」。

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
`grill-poller.sh`／`agent-dev-poller.sh` 兩支 poller 都不是用 `gh`
CLI，而是直接 `curl` 打 GitHub REST API 的
`/repos/<owner>/<repo>/issues?labels=<label>` 端點——這個端點本身**會**
把符合 label 的 PR 一併吐回來（PR 在 GitHub API 底層也是 issue），兩支
poller 各自在處理回應的 `node -e` 裡用 `if (i.pull_request) continue;`
明確過濾掉，才不會把 PR 誤判成新目標。本 skill **從不對 PR 貼任何
label**，所以即使 PR 會被那個端點吐回來，也不會符合任何一支 poller
的 `labels=` 篩選條件，更不會被誤判成新目標觸發它們。

## Discord 摘要模板

只放結論與可定位的 issue／PR 編號（`repo#N`／`PR #N`，白名單只有兩個
repo，不需要完整 URL 也能定位），完整的逐條依據留在 PR 留言裡。三個
分類（見「流程」步驟 0）**分開列**，「跳過」與「異常」不可合併：

```
📋 驗收完成 <M> 張：
✅ chainbreak#12（PR #34）— 3/3 滿足
⚠️ hangman#8（PR #19）— 2/3 滿足，1 條不滿足（結算頁未做防抖），
   建議送回 ready-for-agent，待人類點頭

已跳過（已驗收過，正常）：2 張——chainbreak#20（PR #40）、hangman#5（PR #11）

⚠️ 異常（找不到對應 PR 或驗收條件，需要人類確認）：1 張——chainbreak#31
```

若這輪掃全部、`$TOTAL` = 0，改貼：

```
📋 本輪掃描 agent-done：0 張（chainbreak／hangman 皆無）
```

這則訊息本身就是完成條件，不是「沒事可做就不用發」——見「流程」步驟 0
對「零筆」的說明。

單輪超過約 8 張時，只列前幾張的細節，其餘改成「還有 N 張，結果同上
分類，詳見各自 PR 留言」——避免逐張列到超過 Discord 2000 字上限；
「異常」分類的項目不受此精簡影響，數量不多時應全部列出，因為這是
需要人類逐一確認的訊號，不是可以概括帶過的正常結果。

## 鐵則

- **只看規格符合度，不做 code review**——那是 Rick/Morty
  `solo-feature-pipeline` 步驟 3（自我審查，派獨立 subagent）的職責。
  不評論程式碼風格、效能、測試覆蓋率、命名，只回答「PR 做出來的東西是
  不是當初 issue 定案的需求」。
- **不滿足時只提議、不自行改 label**——`ready-for-agent` 是整條閉環的
  人類閘門，見上方「送回開發」一節，要等人類明確點頭才動手。
- **永不 approve、永不 merge**——見文首說明，這是角色分工的設計決定，
  不只是帳號限制帶來的技術死結；即便未來
  [wm4n/openab-ops#3](https://github.com/wm4n/openab-ops/issues/3)
  的帳號分離落地、技術上能 approve 了，這條鐵則依然不變。
- **冪等靠簽名，不靠 label**：不新增任何 label 當作「已驗收」的標記，
  判斷依據就是 PR 上那則帶 `— By Summer (acceptance-review)` 簽名的
  留言存不存在。
- **掃不到東西一定要講出來，不能安靜結束**：掃全部時 `$TOTAL` = 0、
  或任何一張落在「異常」分類（找不到對應 PR／找不到驗收條件），都要
  在 Discord 明確報出來（見「流程」步驟 0、「Discord 摘要模板」）——
  現階段 `agent-done` 標籤鏈有已知缺口，「這支 skill 一直沒東西可
  處理」跟「這條鏈根本沒在運作」在 Discord 上長得一模一樣，只有把
  「掃到 0 張」本身當成一則要發的訊息，才有機會被人類注意到。
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
- **不修補 `agent-done` 標籤鏈本身的缺口**——`solo-feature-pipeline`
  步驟 6／persona §4b 成功路徑沒有貼這個 label，是另一個任務要補的
  範圍。本 skill 的責任只到「缺口存在時，讓掃描結果看得見」為止（見
  「流程」步驟 0、「鐵則」）。

## 已知限制

- **`agent-done` 標籤鏈目前有確認過的缺口，掃描很可能長期是 0 張**：
  查證過 `solo-feature-pipeline/SKILL.md` 步驟 6「建 PR + 通知」與
  `Rick-CLAUDE_v2.md` §4b，兩處都只寫「開 PR、回報人類」，沒有任何
  一步會把 `agent-done` 貼上去——§4b 唯一提到 label 的地方是**失敗**
  路徑（改 `agent-failed`）。這代表在該缺口補齊之前，本 skill 掃全部
  極可能每次都是 0 張，這是預期中的已知狀態，不是本 skill 的邏輯錯誤；
  「流程」步驟 0 要求把「0 張」本身當成一則要發的 Discord 訊息，就是
  為了讓這個狀態被看見、被追蹤，而不是被誤讀成「沒有 PR 完成」。
- **簽名冪等不辨識「PR 有沒有更新過」**：PR 驗收後若又被推了新
  commit，留言裡的簽名依然存在，下一輪掃描仍會判定「已驗收」而跳過。
  想要求重新驗收，目前只能由人類指名單張參數
  `<owner/repo>#<N>` 觸發，並在 PR 上額外說明要重新驗收——這裡沒有
  「先刪舊留言再重跑」的自動機制，是刻意接受的限制。
- **PR 連結靠留言文字比對，不是 GitHub 原生的關聯欄位**：若
  `solo-feature-pipeline` 步驟 6 收尾留言的措辭改了、不再包含可辨識的
  PR 連結，步驟 1 的比對邏輯要跟著更新——這一點在標籤鏈缺口補齊、
  真正開始有留言可讀之後才有機會被驗證到。
- **驗收發現不滿足、人類點頭送回開發後，舊 PR 不會自動關閉**，處理方式
  留給人類決定。
- **與 GitHub 帳號共用問題同源於
  [wm4n/openab-ops#3](https://github.com/wm4n/openab-ops/issues/3)**：
  待該 issue 的帳號分離方案落地後，approve 的技術限制才會解除，但如
  「鐵則」所述，本 skill「永不 approve」本身是角色分工的設計決定，
  不會因此改變。
