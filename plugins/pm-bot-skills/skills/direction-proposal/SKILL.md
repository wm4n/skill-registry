---
name: direction-proposal
argument-hint: "revise|materialize <owner>/<repo>#<pr>"
description: >-
  處理 Summer 的提案 PR（作者 wman-pm、分支 proposal/*、檔案在 docs/proposals/）
  被人類回覆之後的兩件事。revise：人類（wm4n）送了 Request changes，照意見修改
  提案檔、push 回原分支、在 PR 留言說明改了什麼。materialize：提案已被 merge，
  依人類 approve 時選的方案（沒選就用提案標「建議」的方案）開 issue，帶 grill-me
  與 spec-only，內文連回提案檔。由主機端 poller 觸發，訊息「執行 direction-proposal
  skill，參數：revise <owner>/<repo>#<pr>」或「執行 direction-proposal skill，參數：
  materialize <owner>/<repo>#<pr>」；人類在 Discord 要 Summer 改提案或把核准的提案
  開成 issue 時也觸發。不 merge、不 approve，除了 needs-human 不碰任何 label。
---

# Direction Proposal

> **本 skill 接在 `product-planning` 5a 後面**（2026-10-23 起，openab-ops Ruling R22）：
> Summer 自己的新想法不直接開 issue，先開提案 PR 讓人類審方向。人類有三種回覆，
> 寫在每張提案 PR 內文的結尾：
>
> | 人類動作 | 誰接手 | 本 skill |
> | --- | --- | --- |
> | Request changes＋想法 | `pr-review-poller.sh` 觸發 Summer | **revise**：改提案、push、留言，人類收到新 head 的通知再審 |
> | Approve | `merge-poller.sh` squash merge 提案 PR，再觸發 Summer | **materialize**：依選定的方案開 issue，之後照現行流程進 grill |
> | 關掉 PR、不 merge | 沒有人接手 | 不處理；`product-planning` 去重會讀到它，不再提 |
>
> 只有 `wm4n` 的 review 算數。merge 由主機端 merge-poller 執行，本 skill 不 merge、
> 不 approve。

## 參數與共同預檢

`$ARGUMENTS` 裡找 `revise` 或 `materialize`，後面接 `<owner>/<repo>#<pr>`。主機端的
觸發訊息是 `<@Summer> 執行 direction-proposal skill，參數：revise wm4n/chainbreak#12`
這種形狀。找不到這兩個模式之一，或 repo 不是 `wm4n/chainbreak`、`wm4n/hangman` →
回覆正確格式並結束，不臆測、不寫任何東西。

`gh` 不吃 `owner/repo#N`，先拆開。一輪會跨很多次 Bash 呼叫，值一律存進狀態目錄、
用時現讀，每次呼叫開頭都用同一組算式重設：

```bash
MODE=revise                       # 或 materialize
PR_REF="wm4n/chainbreak#12"       # 從 $ARGUMENTS 取得
REPO="${PR_REF%#*}"; PR="${PR_REF##*#}"
OWNER="${REPO%%/*}"; REPO_NAME="${REPO#*/}"
STATE="/tmp/direction-proposal/${OWNER}-${REPO_NAME}-${PR}"
mkdir -p "$STATE"
```

**預檢（兩個模式都做，任何一項不過就結束，不貼任何留言）**：

1. `gh api user --jq .login` 必須是 `wman-pm`。不是 → 本輪不寫，Discord 回報。
2. 確認是提案 PR，並記下分支、提案檔、head：

   ```bash
   gh pr view "$PR" --repo "$REPO" \
     --json state,author,headRefName,headRefOid,url,title,labels,mergeCommit \
     --jq '"\(.state)\n\(.headRefName)\n\(.headRefOid)\n\(.mergeCommit.oid // "")\n\(.author.login // "")\n\(.url)\n\([.labels[].name] | join(","))"' \
     > "$STATE/pr.txt" && cat "$STATE/pr.txt"
   BRANCH=$(sed -n 2p "$STATE/pr.txt")
   FILE="docs/proposals/${BRANCH#proposal/}.md"
   printf '%s' "$FILE" > "$STATE/file"
   if [ "$(sed -n 5p "$STATE/pr.txt")" = wman-pm ] \
     && printf '%s' "$BRANCH" | grep -Eq '^proposal/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$' \
     && FILES=$(gh api "repos/$REPO/pulls/$PR/files" --paginate --jq '.[].filename') \
     && [ "$FILES" = "$FILE" ]; then
     echo "PROPOSAL_OK file=$FILE"
   else
     echo "NOT_PROPOSAL files=[$FILES]"
   fi
   ```

   `NOT_PROPOSAL`（作者不是 `wman-pm`、分支不是 `proposal/<日期>-<slug>`、或 PR 動的檔案
   不是剛好那一個提案檔）→ 結束，Discord 回報。本 skill 只碰提案檔，PR 動到別的路徑就
   不是它能處理的。
3. PR 帶 `needs-human`（`pr.txt` 第 7 行）→ 人類正在決定，不動。revise 例外：貼一則
   `failed` 標記留言（見 revise「失敗處理」，原因寫「PR 帶 needs-human」）再結束，
   否則 pr-review-poller 會一直重送觸發。

## revise：照人類的 Request changes 修改提案

每一輪都要以 `done` 或 `failed` 標記收尾：`pr-review-poller.sh` 只看 PR 留言**首行**的
標記判斷這一輪處理了沒有——`start` 代表處理中，`done`、`failed` 代表已處理。停在
`start` 的一輪會在租約（250 分鐘）過後被重送。

| 首行（逐字） | 何時貼 |
| --- | --- |
| `<!-- direction-proposal:start -->` | R2，接手的第一個寫入 |
| `<!-- direction-proposal:done -->` | R7，改完並 push 之後 |
| `<!-- direction-proposal:failed -->` | R2 之後任何一步失敗；或預檢 3 |

標記是 HTML 註解，GitHub 畫面上看不到。簽名逐字 `— By Summer (direction-proposal)`
（em dash U+2014），直接複製本文件的字串。

### R1. 找出要處理的 review（PR 必須是 `OPEN`）

```bash
# （開頭照「參數與共同預檢」重設變數）
OK=yes; REV=; MARK=
# wm4n 最新一則 Request changes：<時間>\t<id>\t<commit_id>
if RAW=$(gh api "repos/$REPO/pulls/$PR/reviews" --paginate \
     --jq '.[] | select(.user.login == "wm4n" and .state == "CHANGES_REQUESTED") | "\(.submitted_at)\t\(.id)\t\(.commit_id)"'); then
  REV=$(printf '%s\n' "$RAW" | grep . | sort | tail -n 1)
else OK=no; fi
# 本 skill 最新的標記：<時間>\t<start|done|failed>\t<距今秒數>\t<已處理 review id，沒有就空白>
if RAW=$(gh api "repos/$REPO/issues/$PR/comments" --paginate --jq '.[] | select(.user.login == "wman-pm")
     | ((.body // "") | split("\n")) as $l
     | (($l[0] // "") | gsub("^[\t \u00a0\u3000]+|[\t\r \u00a0\u3000]+$"; "")) as $h
     | select($h | startswith("<!-- direction-proposal:"))
     | "\(.created_at)\t\($h | capture("direction-proposal:(?<k>[a-z]+)") | .k)\t\((now - (.created_at | fromdateiso8601)) | floor)\t\(([$l[] | capture("^已處理 review：(?<id>[0-9]+)") | .id] | first) // "")"'); then
  printf '%s\n' "$RAW" | grep . | sort > "$STATE/marks.tsv"
  MARK=$(tail -n 1 "$STATE/marks.tsv")
else OK=no; fi
HEAD_SHA=$(sed -n 3p "$STATE/pr.txt")
printf '%s' "$REV" > "$STATE/review"
echo "ok=$OK state=$(sed -n 1p "$STATE/pr.txt") head=$HEAD_SHA"
echo "review=$REV"
echo "mark=$MARK"
```

依序判斷，第一個符合的就照做（「review」指上面印出的那則，`id` 是第 2 欄）：

1. `ok=no` → 查詢失敗，結束，Discord 回報。不貼標記（查不到就不知道該不該做）。
2. PR 不是 `OPEN` → 結束：已 merge 的提案歸 materialize，關掉的提案不做了。
3. 沒有 review → 「沒有待處理的修改要求」，結束。
4. `marks.tsv` 裡有 `done` 標記的「已處理 review」等於這則的 `id` → 已處理過，結束。
5. review 的 `commit_id` 不等於目前 head → review 之後分支已經有新 commit，也就是改過
   了，結束。
6. 最新標記是 `start`、晚於 review、而且距今不到 15000 秒（250 分鐘，主機端
   `SUMMER_ACK_MIN` 的預設值）→ 另一輪還在處理，結束。
7. 以上都不符合 → 往下做。`failed` 標記不擋：人類排除原因後手動重觸發，這裡要能
   重做同一則 review。

步驟 1–6 的「結束」都不貼任何標記。

### R2. 貼 start 標記

```bash
# （開頭照「參數與共同預檢」重設變數）
RID=$(cut -f2 "$STATE/review")
printf '<!-- direction-proposal:start -->\n收到 review %s，開始修改提案。\n\n— By Summer (direction-proposal)\n' "$RID" \
  | gh pr comment "$PR" --repo "$REPO" --body-file -
```

貼出之後，任何一步失敗都走「失敗處理」，一定要留下 `failed` 才能結束。

### R3. 讀人類的意見

```bash
# （開頭照「參數與共同預檢」重設變數）
RID=$(cut -f2 "$STATE/review")
gh api "repos/$REPO/pulls/$PR/reviews/$RID" --jq '.body // ""'
# 這則 review 底下的行內留言
gh api "repos/$REPO/pulls/$PR/comments" --paginate \
  --jq ".[] | select(.pull_request_review_id == $RID) | \"\(.path):\(.line // .original_line // \"-\")\n\(.body)\n----\""
# wm4n 在 PR 對話裡的留言（補充脈絡；以 review 與行內留言為主）
gh api "repos/$REPO/issues/$PR/comments" --paginate \
  --jq '.[] | select(.user.login == "wm4n") | "\(.created_at)\n\(.body)\n----"'
```

人類的意見可能是改方向、加減方案、指定方案、問問題，或要求補數據依據。全部逐條
處理，不挑著做：問題在提案裡補答，也在 R7 的留言裡回答。人類在這裡提到的花錢或
權限事項不必另外升級：方向本來就由人類審，改好之後人類還會再看一次。

### R4. 在原分支開 worktree

```bash
# （開頭照「參數與共同預檢」重設變數）
BRANCH=$(sed -n 2p "$STATE/pr.txt"); HEAD_SHA=$(sed -n 3p "$STATE/pr.txt")
BASE="/home/node/repos/$OWNER/$REPO_NAME"
WT="/home/node/repos/$OWNER/$REPO_NAME-worktrees/proposal-pr-$PR"
printf '%s' "$WT" > "$STATE/wt"
[ -d "$BASE/.git" ] || gh repo clone "$REPO" "$BASE"
git -C "$BASE" fetch origin
git -C "$BASE" worktree prune
[ -e "$WT" ] && git -C "$BASE" worktree remove --force "$WT"
[ -e "$WT" ] && /bin/rm -rf "$WT" && git -C "$BASE" worktree prune
if git -C "$BASE" worktree add -B "$BRANCH" "$WT" "origin/$BRANCH" \
  && [ "$(git -C "$WT" rev-parse HEAD)" = "$HEAD_SHA" ]; then
  echo "WT_OK $WT"
else
  echo "WT_FAILED"
fi
```

`WT_FAILED`（含遠端分支的 head 已經不是預檢讀到的那個）→ 失敗處理。

### R5. 修改提案檔

只改 `$WT/$FILE` 這一個檔案，其他路徑一律不碰。

- 照 R3 的意見改內文。提案檔的段落與方案小標題格式以 `product-planning` 5a 第 3 步
  為準：兩個以上方案時，每個一行 `### 方案 <大寫字母>：<一句話>`，**恰好一個**行尾加
  `（建議）`。人類指定了方案 → 把 `（建議）` 移到那一個。
- 檔案最後（`— By Summer` 簽名之前）維護一段 `## 修訂紀錄`，每輪加一行：
  `- <YYYY-MM-DD>：依 review <id> <改了什麼，一句話>`（日期用 `TZ=Asia/Taipei date +%F`）。
  每輪一定有這一行，所以每輪一定產生新 commit：人類的「提案待審」通知綁在新的 head
  上，沒有新 head，人類就收不到「改好了，請再審」。
- 不寫關閉關鍵字接 issue 編號（`closes #N` 這類，規則同 `product-planning` 5a）。

### R6. commit、確認範圍、push

```bash
# （開頭照「參數與共同預檢」重設變數）
BRANCH=$(sed -n 2p "$STATE/pr.txt"); FILE=$(cat "$STATE/file"); WT=$(cat "$STATE/wt")
RID=$(cut -f2 "$STATE/review")
CLOSE_RE='(^|[^A-Za-z0-9_])(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+'
if grep -Eiq "$CLOSE_RE" "$WT/$FILE"; then
  echo "CLOSE_KEYWORD_IN_FILE"
else
  git -C "$WT" add -- "$FILE" && git -C "$WT" commit -q -m "docs(proposal): 依 review $RID 修改提案"
  CHANGED=$(git -C "$WT" diff --name-only origin/main...HEAD)
  if [ "$CHANGED" = "$FILE" ] && [ -z "$(git -C "$WT" status --porcelain)" ] \
    && [ "$(git -C "$WT" rev-list --count "origin/$BRANCH..HEAD")" = 1 ]; then
    git -C "$WT" push origin "HEAD:refs/heads/$BRANCH" \
      && git -C "$WT" rev-parse HEAD > "$STATE/new_sha" && echo "PUSH_OK $(cat "$STATE/new_sha")"
  else
    echo "SCOPE_BAD changed=[$CHANGED]"
  fi
fi
```

只有 `PUSH_OK` 才往下。`CLOSE_KEYWORD_IN_FILE` → 改掉那句再跑。`SCOPE_BAD`、commit
失敗（沒有任何變更也算：R5 漏了修訂紀錄）或 push 被拒 → 失敗處理。不加 `--force`、
不 rebase：提案分支只有 Summer 會推，被拒代表有人動過，交給人類看。

### R7. 貼 done 標記

```bash
# （開頭照「參數與共同預檢」重設變數）
RID=$(cut -f2 "$STATE/review")
{
printf '<!-- direction-proposal:done -->\n已依 review %s 修改提案（新 head：%s）：\n\n' "$RID" "$(cut -c1-7 "$STATE/new_sha")"
cat <<'EOF'
- <改了什麼>
- <人類的問題與回答>

請再審一次：照內文結尾的回覆規則 Approve、Request changes 或關掉 PR。
EOF
printf '\n已處理 review：%s\n\n— By Summer (direction-proposal)\n' "$RID"
} | gh pr comment "$PR" --repo "$REPO" --body-file -
```

`已處理 review：<id>` 這一行逐字照抄，R1 第 4 條靠它認出處理過的 review。不要 @ 人類：
新 head 一出現，主機端 `human-notifier.sh` 就會再發一次「提案待審」。

確認貼上了（印出網址才算）：

```bash
# （開頭照「參數與共同預檢」重設變數）
RID=$(cut -f2 "$STATE/review")
gh api "repos/$REPO/issues/$PR/comments" --paginate \
  --jq ".[] | select(.user.login == \"wman-pm\" and ((.body // \"\") | startswith(\"<!-- direction-proposal:done -->\")) and ((.body // \"\") | contains(\"已處理 review：$RID\"))) | .html_url"
```

沒有輸出 → 再貼一次；仍失敗 → Discord 回報（push 已完成，poller 會因為 head 變了而
不再重送）。

### R8. 移除 worktree，Discord 回報

```bash
# （開頭照「參數與共同預檢」重設變數）
BASE="/home/node/repos/$OWNER/$REPO_NAME"; WT=$(cat "$STATE/wt")
git -C "$BASE" worktree remove --force "$WT"; git -C "$BASE" worktree prune
[ ! -e "$WT" ] && echo "WT_REMOVED"
```

在觸發這一輪的 Discord thread 回一句：PR 連結、改了幾項，不帶 @。

### 失敗處理（R2 之後，以及預檢 3）

```bash
# （開頭照「參數與共同預檢」重設變數）
{
printf '<!-- direction-proposal:failed -->\n'
cat <<'EOF'
⚠️ 提案修改中斷：<卡在哪一步、錯誤摘要、已 push 的 commit（沒有就寫「無」）>

人類排除原因後，在 Discord 觸發「執行 direction-proposal skill，參數：revise <owner>/<repo>#<pr>」重跑。
EOF
printf '\n— By Summer (direction-proposal)\n'
} | gh pr comment "$PR" --repo "$REPO" --body-file -
```

接著做 R8（有建 worktree 的話）並在 Discord 回報。`failed` 不寫「已處理 review」：
poller 看到 `failed` 就不再自動重送，人類手動重觸發時 R1 會重做同一則 review。

## materialize：把核准的提案開成 issue

merge-poller 在 squash merge 提案 PR 之後觸發本模式；沒開成會依帳本重送，最多 3 次，
再不行就升級 `needs-human`。它判斷「開好了沒」的方式是：repo 裡有沒有 issue 的內文
含提案檔路徑。所以 issue 內文**一定要有一行字面路徑** `docs/proposals/<日期>-<slug>.md`。

### M1. 冪等：已經開過就不再開

PR 必須是 `MERGED`（`pr.txt` 第 1 行）。不是 → 結束，Discord 回報（還沒核准）。

```bash
# （開頭照「參數與共同預檢」重設變數）
FILE=$(cat "$STATE/file")
if RAW=$(gh issue list --repo "$REPO" --state all --limit 300 --json url,body \
     --jq ".[] | select((.body // \"\") | contains(\"$FILE\")) | .url"); then
  [ -n "$RAW" ] && echo "ALREADY $RAW" || echo "NOT_YET"
else
  echo "CHECK_FAILED"
fi
```

- `ALREADY` → 已開過，結束，Discord 回報那張 issue。
- `CHECK_FAILED` → 結束，不開（查不到就可能重複開）。
- `NOT_YET` → 往下。

用 `gh issue list` 讀列表、用 jq 比對，不用 `--search`：搜尋索引有延遲，重送時會
查不到剛開的單、再開一張。

### M2. label 預檢

```bash
gh label list --repo "$REPO" --limit 200 --json name --jq '.[].name'
```

`grill-me`、`spec-only`、`needs-human` 三個都要在。缺任一個或查詢失敗 → 結束，不開，
Discord 回報請人類建立（不自己建）。merge-poller 重送用完後會升級，人類會被通知。

### M3. 讀提案檔與人類選的方案

```bash
# （開頭照「參數與共同預檢」重設變數）
FILE=$(cat "$STATE/file"); MERGE_SHA=$(sed -n 4p "$STATE/pr.txt"); HEAD_SHA=$(sed -n 3p "$STATE/pr.txt")
gh api -H "Accept: application/vnd.github.raw+json" "repos/$REPO/contents/$FILE?ref=$MERGE_SHA" > "$STATE/proposal.md" \
  && echo "PROPOSAL_READ $(wc -l < "$STATE/proposal.md") lines"
# 提案裡的方案字母與標了（建議）的那一個（只有一個方案時兩者都是空的）
grep -E '^### 方案 [A-Z]：' "$STATE/proposal.md" | sed -E 's/^### 方案 ([A-Z])：.*/\1/' | tr -d '\n' > "$STATE/letters"
grep -E '^### 方案 [A-Z]：.*（建議）[[:space:]]*$' "$STATE/proposal.md" | sed -E 's/^### 方案 ([A-Z])：.*/\1/' | tr -d '\n' > "$STATE/recommended"
echo "letters=$(cat "$STATE/letters") recommended=$(cat "$STATE/recommended")"
# wm4n 的 Approve：優先取綁在最後 head 上的最新一則，沒有就取最新一則。<時間>\t<id>\t<commit_id>
gh api "repos/$REPO/pulls/$PR/reviews" --paginate \
  --jq '.[] | select(.user.login == "wm4n" and .state == "APPROVED") | "\(.submitted_at)\t\(.id)\t\(.commit_id)"' \
  | grep . | sort > "$STATE/approvals.tsv"
{ awk -F '\t' -v h="$HEAD_SHA" '$3 == h' "$STATE/approvals.tsv" | tail -n 1 | grep . \
  || tail -n 1 "$STATE/approvals.tsv"; } > "$STATE/approval"
echo "approval=$(cat "$STATE/approval")"
```

讀 approve 內文寫了哪個方案（全形字母先轉半形，同一個字母只算一次）：

```bash
# （開頭照「參數與共同預檢」重設變數）
AID=$(cut -f2 "$STATE/approval")
if [ -n "$AID" ]; then
  gh api "repos/$REPO/pulls/$PR/reviews/$AID" --jq '.body // ""' > "$STATE/approval_body"
  gh api "repos/$REPO/pulls/$PR/reviews/$AID" --jq '
    (.body // "") | explode
    | map(if . >= 65313 and . <= 65338 then . - 65248 elif . >= 65345 and . <= 65370 then . - 65248 else . end)
    | implode
    | [match("方案[\t \u00a0\u3000]*([A-Za-z])([^A-Za-z]|$)"; "g") | .captures[0].string | ascii_upcase] | unique
    | if length == 0 then "NONE" elif length == 1 then "ONE \(.[0])" else "MULTI \(join(","))" end'
else
  : > "$STATE/approval_body"; echo "NONE"
fi
```

依下表決定選定方案，第一個符合的就採用：

| 情況 | 選定方案 |
| --- | --- |
| `letters` 是空的（提案只有一個方案） | 唯一方案 |
| `ONE X`，而且 X 在 `letters` 裡 | 方案 X（人類指定） |
| `NONE`，`recommended` 剛好一個字母，而且 approve 內文沒有用別的說法指定方案（例如「第二個」「選比較便宜的」） | `recommended` 那個（人類沒指定，依建議） |
| 其他（`MULTI`、X 不在提案裡、`recommended` 不是剛好一個、內文用別的說法指定了方案） | **不明確** → M5 |

沒有任何 wm4n 的 Approve（人類自己按了 merge）也照「`NONE`」那一列處理：merge 本身就是
核准方向。approve 內文不論選了哪一列，都原文抄進 issue（M4），grill 時才看得到人類的
補充。

### M4. 開 issue

內文寫進 `$STATE/issue_body.md`，從提案檔取材，**只寫選定的方案**，其他方案不帶進來：

```bash
# （開頭照「參數與共同預檢」重設變數）
FILE=$(cat "$STATE/file"); PR_URL=$(sed -n 6p "$STATE/pr.txt")
{
cat <<'EOF'
## 背景

<提案的背景段>

## 需求描述

<提案的方向說明，加上選定方案的做法>

## 驗收條件

- <提案的驗收條件草稿，依選定方案與人類的意見調整>

## 數據依據

<提案的數據依據段>

## 方向核准
EOF
printf '\n提案檔：%s\n' "$FILE"
printf '提案 PR：%s\n' "$PR_URL"
printf '選定方案：%s\n' '<唯一方案／方案 X（人類指定）／方案 X（人類沒指定，依提案的建議方案）>'
printf '人類核准時的留言：\n\n'
if [ -s "$STATE/approval_body" ]; then sed 's/^/> /' "$STATE/approval_body"; else printf '（無）\n'; fi
printf '\n---\n— By Summer\n'
} > "$STATE/issue_body.md"
grep -qF "提案檔：$FILE" "$STATE/issue_body.md" && echo "BODY_OK"
```

- 五個段落缺一不可，驗收條件要具體、可驗證。
- `提案檔：<路徑>` 這一行是 merge-poller 與 M1 認「開過了」的依據，不能少、不能改寫成
  只有連結。
- 結尾逐字 `— By Summer`（em dash U+2014）：`summer-grill-responder` 靠它（以及作者
  `wman-pm`）認出這是 Summer 的單，讓 Summer 回答 grill 提問。

```bash
# （開頭照「參數與共同預檢」重設變數）
TITLE='<提案 PR 標題去掉開頭的「提案：」>'
gh issue create --repo "$REPO" --title "$TITLE" --label grill-me --label spec-only \
  --body-file "$STATE/issue_body.md"
```

確認：重跑 M1 的查詢要印出 `ALREADY <網址>`（剛好一張），再看 label：

```bash
gh issue view "<新 issue 編號>" --repo "$REPO" --json labels --jq '[.labels[].name]'
```

- 兩個 label 都在 → 完成。
- `gh issue create` 回報失敗、M1 卻查得到 → 已經開成了，照「完成」處理，不要再開。
- 單開成了但缺 label → 只對**這一輪剛開的這張**補上缺的那個（`gh issue edit
  --add-label`）。少了 `grill-me` 就不會進 grill，等於沒開。
- M1 查不到 → 失敗，Discord 回報；merge-poller 會重送。

最後在提案 PR 留一則（不是標記留言）讓之後讀 PR 的人找得到 issue：

```bash
printf '已依核准的提案開 issue：%s（選定方案：%s）\n\n— By Summer (direction-proposal)\n' \
  '<issue 網址>' '<選定方案>' | gh pr comment "$PR" --repo "$REPO" --body-file -
```

這則失敗只記進 Discord 回報，不影響結果。

### M5. 方案不明確：升級 needs-human

人類核准了方向，但看不出選哪個方案，猜錯就是做錯方向，所以問人。順序固定（同其他
pm-bot skill 的 R15 順序）：

1. 在**提案 PR** 加 `needs-human`：`gh issue edit "$PR" --repo "$REPO" --add-label needs-human`，
   再用 `gh pr view "$PR" --repo "$REPO" --json labels` 確認。失敗就停，什麼都不留下。
2. 在提案 PR 留言，首行 `## 需要人類決定（needs-human）`，**第二行逐字**
   `原因：提案核准的方案不明確`，內文列出提案裡的方案、approve 內文原文，以及處理方式：
   「在本 PR 留言寫『方案 X』，移除 needs-human label，再在 Discord 觸發『執行
   direction-proposal skill，參數：materialize <owner>/<repo>#<pr>』」。簽名
   `— By Summer (direction-proposal)`。
3. 不 @ 人類：通知由主機端 human-notifier 依 label 事件發。

**人類處理完之後**（PR 上有上面那則升級留言、`needs-human` 已被移除）：用 M3 那段
jq 讀**升級留言之後** `wm4n` 最新一則 PR 留言（`gh api "repos/$REPO/issues/$PR/comments"`），
`ONE X` 而且 X 在提案裡 → 選方案 X（記為「人類指定」），回到 M4。還是不明確 → 不再升級
（**絕不重新加回** `needs-human`），Discord 回報請人類直接開 issue。

## 鐵則

- **只處理提案 PR**：作者 `wman-pm`、分支 `proposal/<日期>-<slug>`、只動
  `docs/proposals/<日期>-<slug>.md` 一個檔。不是就結束。
- **只有 `wm4n` 的 review 算數**。
- **revise 只改那一個提案檔、只 push 回原分支**，不 force push、不 rebase、不碰其他
  路徑或分支；每輪都以 `done` 或 `failed` 標記收尾，標記放在留言首行、逐字照抄。
- **materialize 冪等**：先用 `gh issue list` 比對內文有沒有提案檔路徑，有就不開；
  開的 issue 內文一定有 `提案檔：<路徑>` 一行、結尾 `— By Summer`，帶 `grill-me` 與
  `spec-only`。
- **方案不明確就問人**，不猜。
- **不 merge、不 approve、不關 PR**；除了升級時加 `needs-human`、以及補上本輪剛開的
  issue 缺的 `grill-me`／`spec-only`，不碰任何 label。
- **不在 Discord @ 任何人**：通知人類是 `human-notifier.sh` 的事。
- 白名單只有 `wm4n/chainbreak`、`wm4n/hangman`。

## 已知限制

- **方案字母只認「方案 X」寫法**：人類寫「第二個」「便宜那個」不會被 jq 讀到，要靠
  Summer 讀 approve 內文時判斷成「不明確」；判斷漏了就會用建議方案。approve 內文原文
  會抄進 issue，grill 時還有一次機會被看到。
- **M1 只看最近 300 張 issue**（`gh issue list --limit 300`）：更早開的、內文含同一路徑
  的單讀不到。提案落地通常在 merge 後幾分鐘內，實務上不會發生。
- **revise 依賴 Summer 容器的 git 憑證**（`gh auth setup-git`），上線前用
  `git push --dry-run` 確認（openab-ops runbook）。
- **M5 升級是貼在 PR 上的 `needs-human`**：通知靠 `human-notifier.sh` 看 label 事件；
  它若只掃 issue、不掃 PR，人類收不到這則通知，只會在 Discord 回報裡看到。
