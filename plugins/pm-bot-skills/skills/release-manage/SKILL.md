---
name: release-manage
argument-hint: "[巡檢 | <owner/repo> v<x>.<y>.<z>]"
description: >-
  版本統籌：Summer 自主規劃版本——自己定版號、亮點、這一版要放的需求與修正、
  上架需要的資訊（商店新功能說明、素材／權限／隱私變動、審核備註），自己把版本轉成
  開發中、增刪範圍、承諾單做完時自己定版。觸發：backlog-triage 段 0 與
  product-planning 5c 每一輪的「巡檢」；人類在 Discord 說加或刪某張單、先不要定版、
  定版、送審了、通過了、被退件（含原因）、上線後發現問題。人類的話一律優先於 Summer
  的判斷。只寫 milestone 描述的狀態區、單掛哪個 milestone、版本單（release-plan）、
  release-prep label 與修正單；分支、版號、tag、Release 由主機端 release-poller 做，
  這裡不碰。
---

# Release Manage

你是版本的**統籌 PM，自己做決定**：排版本、定範圍、決定什麼時候定版，寫回 GitHub，並在 GitHub
上留下理由。**人類（wm4n）的話一律優先**：人類在 Discord 說要加、要刪、先不要定版，就照做並記錄；
你之後的自主判斷不能推翻人類記錄過的決定。設計依據是 openab-ops 的
`docs/superpowers/specs/2026-11-10-autonomous-release-planning-design.md`（取代
`2026-11-09-release-management-design.md` 裡「範圍只有人類能同意」的部分），權責邊界在 persona
`Summer-AGENTS_v2.md` §4f。

> 🕘 2026-11-09 的 1.5.0 版是「範圍只有人類能同意」：Summer 只擬草案，同意、增刪、定版都要等人類在 Discord 說。
> 2026-11-10（1.6.0）起人類要 Summer 完全自主規劃版本，人類只做打包、簽章、送審，並回報送審結果。

白名單只有 `wm4n/chainbreak`、`wm4n/hangman`。

## 誰決定、誰寫什麼

| 誰 | 決定什麼 | 寫什麼 |
| --- | --- | --- |
| **你（本 skill）** | 版號、亮點、範圍（需求、修正、打包前檢查）、上架資訊、什麼時候開始開發、範圍增刪、什麼時候定版、退件後修哪些、上線後問題走修補版還是下一版 | milestone 標題；描述狀態區的 `狀態`（只寫六個值：`草案`、`開發中`、`待定版`、`送審中`、`修正中`、`待上線`）、`亮點`、`版本單`、`送審日`；單掛上／移出 milestone；版本單 issue（label `release-plan`）的內文與留言；label `release-prep`；修正單與上線後問題的新 issue |
| **人類** | 推翻你的任何範圍決定；先不要定版；送審了、通過、退件（只有人類知道的事實）；打包、簽章、上傳商店、商店素材這類 `release-prep` 單 | 不碰 GitHub，在 Discord 跟你說 |
| **`release-poller`**（主機端，每小時 `:09`） | 照狀態執行 | `狀態：已定版`、`狀態：已上線`，以及 `分支`、`送審點`、`build`；`release/<x>.<y>` 分支、版號 commit `chore(release): v<x>.<y>.<z>+<build>`、rc tag `v<x>.<y>.<z>-rc.<N>`、正式 tag `v<x>.<y>.<z>`、GitHub Release、關 milestone、`release-backport` 單 |

`release-poller` 寫的你讀得到、不寫。`release-poller` 與 `agent-dev-poller` 都 fail-closed：狀態值只要不是
八個字面值之一，整個版本上的單就暫停派工，所以狀態值逐字照下面的表寫。

## 狀態區

每個版本是一個 milestone，標題 `v<x>.<y>.<z>`（`^v\d+\.\d+\.\d+$`；其他標題是人類自己的
milestone，不碰）。描述開頭到第一個只有 `---` 的行是狀態區，每行 `鍵：值`（全形冒號）：

```
狀態：開發中
亮點：毒蛙新關卡
版本單：#90
---
自由文字
```

七個鍵：`狀態`、`亮點`、`版本單`、`分支`、`送審點`、`build`、`送審日`。`---` 之後是自由文字，
改狀態區時**原樣保留**（下面的 `ms_edit` 用 `tail` 整段搬過去）。`送審日` 寫台北日期
`YYYY-MM-DD`。

### 事件與狀態

```
(擬版本) ─> 草案 ─上一版切好分支─> 開發中 ─承諾單完成─> 待定版 ─poller─> 已定版 ─送審了─> 送審中 ─通過─> 待上線 ─poller─> 已上線
        └──────── 沒有排隊的版本時直接開 ───────┘              ^                              |
                                                               +---- 修正中 <---退件／嚴重問題-+
                                                               (修正單都關了，你自己重新定版)
```

| 事件 | 誰觸發 | 目前狀態須是 | 寫成 | 一起寫 |
| --- | --- | --- | --- | --- |
| 開始開發 | **你**（巡檢） | `草案` | `開發中` | |
| 定版 | **你**（巡檢），或人類說「定版」 | `開發中` | `待定版` | Release notes、上架資訊 |
| 重新定版 | **你**（巡檢），或人類說 | `修正中` | `待定版` | |
| 送審了 | 人類 | `已定版` | `送審中` | `送審日` |
| 退件、發現嚴重問題 | 人類 | `送審中` | `修正中` | |
| 通過 | 人類 | `送審中` | `待上線` | |

送審了、退件、通過是**只有人類知道的事實**：只在 Discord 聽到人類說才寫，不自己判斷「應該已經送審了」。

動手前一律先讀現況，三種結果：

- 狀態**是前置值** → 照表寫。
- 狀態**已經是目標值** → 這件事做完了，回報就好，不重寫。
- 其他（包括 `release-poller` 剛好改了它）→ 不寫，在摘要或回覆裡講現況。

三道守門，擋在寫入之前（巡檢與人類指示都一樣）：

- **開始開發（`z == 0`）**：同 repo 已有另一個 open 的 `z == 0` 版本是 `開發中`，**或**有 open 的 `z == 0` 版本是
  `待定版` 而且 `分支` 鍵是空的（首次定版還沒切好分支）→ 不寫。理由：定版是從 main 當下切出來的，分支還沒切好
  之前讓下一版的單 merge 進 main，就會混進送審。修補版（`z > 0`）不檢查：它在 release 分支上做、不佔名額。
- **寫 `待定版`（定版或重新定版）**：同 repo 另一個版本在 `待定版`、`已定版`、`送審中`、`修正中`、`待上線`
  任一個 → 不寫（同時最多一個版本在送審），等那一版上線。
- **人類說過先不要定版**：版本單上最新的 `## 人類決定：` 留言是「先不要定版」，而且之後沒有「定版」或「可以定版了」→
  巡檢不寫 `待定版`。

## 開始前

### 預檢

1. `gh api user --jq .login` 是 `wman-pm`。不是 → 本輪不寫，回報。
2. **人類指示**只有 `wm4n` 的原話算數；其他 bot 或轉述不算。巡檢不需要人類原話。
3. 人類指示要弄清楚**哪個 repo、哪個版本**：原話指出版本（或 repo）後，兩個 repo 裡目前狀態符合該事件
   前置值的版本剛好剩一個才動；零個或多個 → 回問，不猜。
4. 擬版本、開始開發、定版另需 label `release-plan`、`release-prep` 存在（建立 label 歸人類，不自己建）：

   ```bash
   gh label list --repo "$REPO" --limit 200 --json name --jq '.[].name' | grep -xE 'release-plan|release-prep'
   ```

   `--limit 200` 不能省。印不出兩行 → 不寫，摘要請人類建 label。

### 輔助函式

一輪跨很多次 Bash 呼叫，shell 狀態不保留。第一次呼叫把函式寫進檔案，之後每次呼叫開頭
`source` 它並指定 repo：

```bash
mkdir -p /tmp/release-manage && cat > /tmp/release-manage/lib.sh <<'LIB'
use_repo() { REPO="$1"; STATE="/tmp/release-manage/${REPO//\//-}"; mkdir -p "$STATE"; }

# 一個 repo 的所有版本 milestone：編號、標題、open/closed、狀態行
ms_list() {
  gh api "repos/$1/milestones?state=all&per_page=100" --paginate --jq '.[]
    | select(.title | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    | [.number, .title, .state, ((.description // "") | split("\n")
        | map(select(test("^\\s*狀態\\s*[：:]"))) | first // "（沒有狀態行）")] | @tsv'
}

# 版本單的 issue 號
plan_no() {
  gh api "repos/$REPO/milestones/$1" | jq -j '.description // ""' \
    | sed -nE 's/^[[:space:]]*版本單[[:space:]]*(：|:)[[:space:]]*#?([0-9]+).*/\2/p' | head -n 1
}

# ms_edit <milestone 編號> 鍵=值 …（值留空＝移除該鍵）→ 新描述寫進 $STATE/desc.new。
# --- 行起的部分用 tail 整段搬過去，位元組不動；只改它上面的狀態區。
ms_edit() {
  local n="$1" pair sep; shift
  gh api "repos/$REPO/milestones/$n" | jq -j '.description // ""' > "$STATE/desc.old" || return 1
  sep=$(grep -nE '^[[:space:]]*---[[:space:]]*$' "$STATE/desc.old" | head -n 1 | cut -d: -f1)
  [ -n "$sep" ] || { echo "NO_SEPARATOR：描述裡沒有 --- 行，改用「手動重寫」"; return 2; }
  head -n $((sep - 1)) "$STATE/desc.old" > "$STATE/hdr"
  tail -n +"$sep" "$STATE/desc.old" > "$STATE/rest"
  for pair in "$@"; do
    K="${pair%%=*}" V="${pair#*=}" awk '
      BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"]; re = "^[ \t]*" k "[ \t]*(：|:)" }
      $0 ~ re { if (!done && v != "") print k "：" v; done = 1; next }
      { print }
      END { if (!done && v != "") print k "：" v }' "$STATE/hdr" > "$STATE/hdr.tmp" \
      && mv "$STATE/hdr.tmp" "$STATE/hdr" || return 1
  done
  cat "$STATE/hdr" "$STATE/rest" > "$STATE/desc.new"
}

# 寫回並讀回驗證：自由文字沒變，印出狀態行
ms_put() {
  local n="$1"
  gh api -X PATCH "repos/$REPO/milestones/$n" -F description=@"$STATE/desc.new" > /dev/null || return 1
  gh api "repos/$REPO/milestones/$n" | jq -j '.description // ""' > "$STATE/desc.chk" || return 1
  free_of() { local s; s=$(grep -nE '^[[:space:]]*---[[:space:]]*$' "$1" | head -n 1 | cut -d: -f1); [ -n "$s" ] && tail -n +"$s" "$1"; }
  if [ "$(free_of "$STATE/desc.old")" = "$(free_of "$STATE/desc.chk")" ]; then echo FREE_OK; else echo FREE_CHANGED; fi
  grep -m1 -E '^[[:space:]]*狀態[[:space:]]*(：|:)' "$STATE/desc.chk"
}
LIB
```

再補兩個巡檢用的函式（同一個檔案，接在後面）：

```bash
cat >> /tmp/release-manage/lib.sh <<'LIB'
# milestone 上還開著的「承諾單」：不含 release-plan／release-prep／release-backport。每行「編號<TAB>標題<TAB>labels<TAB>最後更新」
open_committed() {
  gh issue list --repo "$REPO" --milestone "$1" --state open --limit 200 --json number,title,labels,updatedAt \
    --jq '.[] | select([.labels[].name] | any(. == "release-plan" or . == "release-prep" or . == "release-backport") | not)
          | [.number, .title, ([.labels[].name] | join(",")), .updatedAt] | @tsv'
}
# 已關閉的承諾單數
closed_committed() {
  gh issue list --repo "$REPO" --milestone "$1" --state closed --limit 200 --json number,labels \
    --jq '[.[] | select([.labels[].name] | any(. == "release-plan" or . == "release-prep" or . == "release-backport") | not)] | length'
}
# 版本單上人類決定的留言標題（時間順序），用來看「先不要定版」與人類增刪過的單
human_decisions() {
  gh api "repos/$REPO/issues/$1/comments?per_page=100" --paginate \
    --jq '.[] | select(.body | test("^## 人類決定")) | [.created_at, (.body | split("\n") | .[0:6] | join(" / "))] | @tsv'
}
LIB
```

呼叫：`source /tmp/release-manage/lib.sh; use_repo wm4n/hangman; ms_list "$REPO"`。

**改狀態區的完成判準**：`ms_put` 印出 `FREE_OK` 和你要的 `狀態：…` 行。印 `FREE_CHANGED`
或狀態行不對 → 停手，把 `$STATE/desc.old` 的內容貼進回報。

**手動重寫**（`ms_edit` 回 `NO_SEPARATOR`：描述被改壞、沒有 `---`）：把舊描述裡讀得懂的鍵連同
要改的鍵，全部寫進新的狀態區，接 `---`，再接舊描述整段原文，寫成 `$STATE/desc.new`，
再呼叫 `ms_put`（此時 `FREE_CHANGED` 是預期的）。

## 巡檢（每一輪自主檢查）

`$ARGUMENTS` 是 `巡檢`，或 `backlog-triage` 段 0、`product-planning` 5c 叫你來。對兩個白名單 repo 各做一次，
一個 repo 失敗不影響另一個。**依序**做下面五步，每一步都重讀 `ms_list`（前一步可能改了狀態）：

0. `ms_list "$REPO"`。有標題合法、狀態不是八個字面值之一的版本 → 這個 repo 本輪不動（主機端已通知人類），
   摘要寫一行。
1. **重新定版**：`修正中` 的版本，`open_committed` 沒有任何單、而且版本單上修正單（退件後掛上來的）至少一張已關閉
   → 照「重新定版」做。
2. **定版**：open、`z == 0`、`開發中` 的版本，依序判斷：
   - 讀 `open_committed`。**沒有任何一張** 而且 `closed_committed` ≥ 1 → 可以定版。
   - 還有開著的單，**每一張**都屬於下面「可以移出」的情況 → 先照「範圍調整」把它們移到下一版（下一版還不存在就先
     照「擬版本」開一份 `草案`），再判斷一次。只要有一張不屬於，就不定版，摘要寫「`v…` 還差：#…」。
     **可以移出**：(a) 帶 `needs-human` 或 `ready-for-human`、最後更新超過 3 天；或 (b) 帶 `agent-failed` 而且重做次數已達上限
     （`backlog-triage`「重做次數」≥ 2）；而且 (c) 不是亮點的單（版本單 `## 亮點` 段點名的單不移，卡住就等，摘要講）；
     (d) 不是 `agent-active`、沒有開著的 PR（`gh pr list --repo "$REPO" --search "#$N in:body" --state open`）。
   - 可以定版，再過守門（另一個版本在送審流程中、人類說過先不要定版 → 不定版，摘要講原因）。過了就照「定版」做。
3. **開始開發**：沒有 open 的 `z == 0` `開發中` 版本，也沒有「首次定版還沒切好分支」的版本（守門第一條）時，
   取 open、`z == 0`、`草案` 裡版號最小的一個，照「開始開發」做。
4. **擬下一版**：做完 1–3 之後，open 的 `z == 0` 版本裡**沒有** `草案` 也沒有 `開發中` → 照「擬版本」開一份；
   守門允許就直接以 `開發中` 開出（不必經過 `草案`），不允許（上一版首次定版還沒切好分支）就以 `草案` 開出，
   等下一輪巡檢轉開發中。另外，`開發中` 的版本已經可以定版、卻被守門擋住（例如上一版還在送審）時，也先把下一版的
   `草案` 備好。

巡檢只在**狀態真的要變、或範圍真的要動**時寫入；每一步判斷都沒事就不寫任何東西。

摘要（給呼叫你的 skill 併進它的 Discord 摘要，不另發）：每個 repo 一行，寫做了什麼（「`v1.18.0` 開始開發」
「`v1.18.0` 定版，等 `:09` 切分支」「`#83` 卡住 5 天，移到 `v1.19.0`」）或「版本不用動」。

## 擬版本

觸發：巡檢第 4 步、第 2 步要移單但沒有下一版、`product-planning` 5c、人類要求。

1. **選定版號**——先看現況，再決定要不要新開。重跑只會更新同一份：

   ```bash
   ms_list "$REPO"
   ```

   依序取第一個成立的：
   - **人類或觸發點指名了版本**（例如「v1.18.0」「修補版 v1.18.1」）→ 就是它。修補版（`z > 0`）只走這一條。
   - **已經有 open、`z == 0`、`草案` 的 milestone** → 沿用它，不再開另一份。有好幾份時取版號最小的。
     沒指名版本的觸發只看 `z == 0`：修補版是為了某個上線後問題開的，下一版的範圍寫進去會混在修補版裡送審。
   - **都沒有** → 新版號：取所有 milestone 標題與 tag 裡最大的 `v<x>.<y>.<z>`，新版是 `v<x>.<y+1>.0`；
     一個都沒有就 `v1.0.0`。

     ```bash
     { gh api "repos/$REPO/milestones?state=all&per_page=100" --paginate --jq '.[].title'
       gh api "repos/$REPO/tags?per_page=100" --paginate --jq '.[].name'; } \
       | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
     ```

   選定的版本再做**精確比對**，看做到哪一步了：milestone 標題（`ms_list` 的結果裡找 `== "v1.18.0"`）、
   版本單（`release-plan` issue，標題 `v1.18.0 版本計畫`；1.5.0 開的叫 `v1.18.0 版本草案`，也算）。兩者都在 →
   只更新內容（步驟 2、3 重新檢視，改版本單內文，亮點變了就 `ms_edit "$MS" 亮點=… && ms_put "$MS"`）；
   只在其中一個 → 補另一個，不重開已有的那個。

2. **定範圍。** 先回答「玩家為什麼會想更新這一版」，寫出**亮點**：一到兩項玩家看得見、感受得到的改變。
   候選單來自 repo 的 open issue（不含已掛其他版本的、不含 `release-plan`／`release-backport`）和追蹤單的
   sub-issue（例如 chainbreak #71：`gh api repos/$REPO/issues/71/sub_issues`）；每張讀過內文，寫得出「為什麼進這版」。
   分三類：
   - **需求**：新功能、玩法、體驗改善。亮點從這裡挑。
   - **修正**：bug、崩潰、資料錯誤。**已知的崩潰與玩家看得到的錯誤優先進最近的一版**，不等湊齊需求。
   - **打包前檢查**：打包時才做得了的人類單（商店素材、截圖、上架問卷、隱私表單、簽章），貼 `release-prep`，
     不算進定版條件，但沒關掉版本不能標成已上線。上架資訊（步驟 3）發現要人類更新的東西，沒有現成的單就開一張
     （標題 `[release-prep] v1.18.0：<要做什麼>`，內文寫為什麼要做、在哪裡做，結尾 `— By Summer`，貼 `release-prep`）。
   - **大小**：承諾的需求加修正（不含打包前檢查）以 **3～8 張**為準，讓一版在一到兩週內做得完（WIP 3、每天 merge 上限 6）。
     超過就把優先度低的排到下一版，寫進「排除」。只有修正、沒有新需求也可以出版本，但 `z == 0` 一定要有亮點
     （修正本身玩家感受得到，例如「不再閃退」，也可以當亮點）。
   - **人類決定過的單照人類的**：讀這個 repo 所有版本單的 `human_decisions`，人類說過不要放、或排到某一版的單，
     照人類說的放。
   - **`z == 0` 必須有亮點。** backlog 湊不出 → 走提案 PR（`product-planning` 5a，核准後 `direction-proposal`
     開成 issue）提亮點候選，這一版先不開，摘要講「在等亮點方向」。修補版（`z > 0`）以修正為目的，不強制亮點。
   - 只有人類能做的單（真人實玩、簽章）照常列入，人類關單就算完成。

3. **上架資訊。** 只寫查得到的事，查不到寫「無法查證：<原因>」，不用推測冒充（persona「數據優先」）：

   ```bash
   # 預設分支、目前版號、平台、語系、上一個正式 tag
   DEF=$(gh api "repos/$REPO" --jq .default_branch)
   gh api "repos/$REPO/contents/pubspec.yaml?ref=$DEF" --jq .content | base64 -d | grep -E '^(name|version):'
   gh api "repos/$REPO/contents?ref=$DEF" --jq '.[] | select(.type == "dir") | .name' | grep -xE 'android|ios|web|macos|windows|linux'
   gh api "repos/$REPO/git/trees/$DEF?recursive=1" --jq '.tree[].path' \
     | grep -E '(\.arb$|^fastlane/metadata/|^docs/store|AndroidManifest\.xml$|Info\.plist$|PrivacyInfo\.xcprivacy$)' | head -n 40
   LAST=$(gh api "repos/$REPO/tags?per_page=100" --paginate --jq '.[].name' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
   echo "last=$LAST"
   ```

   版本單的 `## 上架資訊` 段寫這幾項（擬版本時是預估，定版時依實際 merge 的內容更新）：
   - **平台**：有哪幾個平台目錄。
   - **商店語系**：`.arb`／`fastlane/metadata` 看得出的語系；看不出寫無法查證。Release notes 用這些語系寫。
   - **商店素材要不要更新**：這一版改到的畫面（主選單、關卡、角色）會讓現有截圖過時嗎？會 → 開 `release-prep` 單。
   - **權限、隱私、資料安全**：有 `LAST` 時，比對 `gh api "repos/$REPO/compare/$LAST...$DEF" --jq '.files[].filename'`
     有沒有動到 `AndroidManifest.xml`、`Info.plist`、`PrivacyInfo.xcprivacy`、`pubspec.yaml` 的相依套件；有動就讀 diff 看是否新增
     權限、廣告／分析 SDK、蒐集的資料 → 有 → 開 `release-prep` 單（更新商店的資料安全／隱私表單）。沒有 `LAST`（第一版）→
     寫「首次上架：權限與資料安全表單要完整填一次」，開 `release-prep` 單。
   - **內容分級**：這一版有沒有新增暴力、內購、使用者互動等會影響分級問卷的內容。
   - **審核備註**：審核員需要知道的（隱藏功能怎麼開、需不需要測試帳號）；沒有寫「無」。

4. **開或更新版本單 issue**（先有它，milestone 描述才寫得進它的編號）。先用
   `gh issue list --repo "$REPO" --label release-plan --state all --json number,title`
   精確比對標題，已有就沿用（改內文用 `gh issue edit "$PLAN" --body-file`）；沒有才開：

   ```bash
   gh issue create --repo "$REPO" --label release-plan --title "v1.18.0 版本計畫" --body-file "$STATE/plan.md"
   ```

   內文固定結構，**亮點在最前**，`## 上架資訊` 在簽名前，結尾簽名逐字 `— By Summer`（em dash U+2014）。
   `## Release notes` 段在定版時才加，**一定放在最後**（簽名之後）：

   ```
   ## 亮點
   - <玩家看得見的改變>（#12）

   ## 需求
   - #12 <標題> — <為什麼進這版>

   ## 修正
   - #31 <標題> — <為什麼進這版>

   ## 打包前檢查（release-prep）
   - #26 <標題> — <為什麼打包時才做>

   ## 排除（排到下一版）
   - #30 <標題> — <理由>

   ## 上架資訊
   - 平台：Android、iOS
   - 商店語系：zh-TW、en
   - 商店素材：<要更新（#27）／不用更新：理由>
   - 權限、隱私、資料安全：<沒有變動／新增 … （#28）／無法查證：…>
   - 內容分級：<沒有影響／…>
   - 審核備註：<無／…>

   ## 怎麼調整
   範圍由 Summer 排定，承諾的單做完 Summer 會自動定版。要加、要刪、先不要定版，在 Discord 跟 Summer 說，以你說的為準。

   ---
   — By Summer
   ```

5. **開 milestone**（步驟 1 查到已有同標題的就不開）。一次帶入完整合法的描述，不要先建再改（fail-closed：
   標題合法而狀態區壞掉的 milestone 會讓整個 repo 的單暫停）。**一律先以 `草案` 開出**——單要先掛好，狀態才轉
   `開發中`；要直接開始開發的（巡檢第 4 步守門允許、修補版），做完步驟 6、7 再照「開始開發」改狀態：

   ```bash
   printf '狀態：草案\n亮點：%s\n版本單：#%s\n---\n範圍、理由與上架資訊見版本單 #%s。狀態由 Summer 與 release-poller 維護，要調整請在 Discord 跟 Summer 說，不要手改。\n' \
     "$HL" "$PLAN" "$PLAN" > "$STATE/desc.new"
   gh api "repos/$REPO/milestones" -f title="$VERSION" -F description=@"$STATE/desc.new" --jq .number
   ```

   修補版（`z > 0`）省略 `亮點` 那行。

6. **掛單**：版本單「需求」「修正」「打包前檢查」每一張 `gh issue edit "$N" --repo "$REPO" --milestone "$VERSION"`；
   打包前檢查另外 `--add-label release-prep`。單已掛著別的版本 milestone → 不覆蓋，從版本單拿掉並在摘要講。
   讀回清單，與版本單一致：

   ```bash
   gh issue list --repo "$REPO" --milestone "$VERSION" --state all --limit 200 --json number --jq '[.[].number] | sort'
   ```

   草案期間的單掛在 `草案` milestone 上，`agent-dev-poller` 不會認領（只認領開發中的版本），所以提早掛沒有副作用；
   好處是清單在 GitHub 上一眼看得到。

7. **在版本單留言** `## Summer 決定：排定版本`：版號、亮點、承諾幾張、為什麼是這個範圍（一兩句，數據依據照
   persona），以及接下來是直接開始開發、還是排在上一版定版之後。簽名 `— By Summer (release-manage)`。

8. **完成判準：** `ms_list "$REPO"` 看到這個版本、狀態行是預期值；版本單 issue 開著且帶 `release-plan`；
   milestone 上的單與版本單一致。

**這個 repo 從沒有過版本 milestone**（步驟 1 的結果是一個都沒有）→ 摘要多補一句：「從這個版本開出起，沒掛上開發中
版本的一般單暫停認領；已經在做或已有 PR 的做完照走。」通知人類（已排好下一版、開始開發）由主機端 `human-notifier` 發。

## 開始開發（`草案` → `開發中`）

巡檢第 3 步、擬版本做完要直接開始的（巡檢第 4 步、修補版），或人類說「開始 v…」。

1. 過守門第一條（`z == 0` 才檢查）。
2. 版本單的需求、修正、打包前檢查都已掛在 milestone 上（擬版本步驟 6 的讀回）；沒掛齊先補齊。
3. 重新檢視一次範圍：草案排好之後可能過了幾天，已經被別的方式解決（關掉）的單、人類後來說不要的單，照「範圍調整」處理。
4. **最後才**改狀態：`ms_edit "$MS" 狀態=開發中 && ms_put "$MS"`。狀態是整批承諾的開關，放最後，中途失敗時版本
   還是 `草案`，沒有半份承諾被派工。
5. 版本單留言 `## Summer 決定：開始開發`（一行說明為什麼是現在：上一版已切好分支／沒有排隊的版本）。

完成判準：`ms_put` 印出 `FREE_OK` 與 `狀態：開發中`。單的放行（貼 `ready-for-agent`）照舊歸 `backlog-triage`。

## 範圍調整（你自己決定）

`開發中`（或 `草案`）的版本，你可以自己增刪，不用等人類：

- **加修正**：triage 看到的新 bug、驗收發現的回歸，玩家看得到或會崩潰的 → 加進目前 `開發中` 的 `z == 0` 版本。
- **加需求**：新需求原則上進下一版（`草案`，沒有就照「擬版本」開一份）。只有跟目前版本的亮點直接相關、
  不加亮點就不完整的，才加進目前版本。
- **刪**：卡住的單（巡檢第 2 步的「可以移出」）、被別的單取代的、數據顯示不再值得做的 → 移到下一版或移出版本。
  亮點的單不移；`agent-active` 或有開著 PR 的單不移（它做完一樣會 merge 進 main、被這一版帶出去）。
- **人類決定過的單不動**：`human_decisions` 裡人類說過要放這一版的，你不刪；說過不要的，你不加。

做法：

- **加**：`gh issue edit "$N" --repo "$REPO" --milestone "$VERSION"`。`待定版` 以後的版本**只加修正單**（見「退件」）。
- **刪**：`gh issue edit "$N" --repo "$REPO" --remove-milestone`（失敗改
  `gh api -X PATCH "repos/$REPO/issues/$N" -F milestone=null`）；排到下一版就 `--milestone "<下一版標題>"`。
  接著**收回放行**（下一段）。
- 改版本單內文的清單（需求／修正／排除），並在版本單留言 `## Summer 決定：增刪`：哪張、加或刪、理由。
- 完成判準：`gh issue view "$N" --repo "$REPO" --json milestone,labels --jq '[.milestone.title, ([.labels[].name] | join(","))]'`
  的 milestone 是預期值（刪則為空）；照下一段收回放行的單，labels 有 `grill-me-done`、沒有 `ready-for-agent`。

**移出版本時收回放行。** 單移出版本（刪、排到下一版、定版前移到下一版），而且移到的地方不是 `開發中` 的版本
（沒掛 milestone、`草案`）時，`agent-dev-poller` 不會再認領它，`ready-for-agent` 留著只會佔住 `backlog-triage` 的
WIP 名額。單帶 `ready-for-agent`、**沒有** `agent-active` 時，換回 triage 放行前的 label，等它進了開發中的版本再由
triage 放行：

```bash
L=$(gh issue view "$N" --repo "$REPO" --json labels --jq '[.labels[].name] | join(",")')
case ",$L," in
  *,agent-active,*) ;;   # 已經在做：label 不動，做完照常走
  *,ready-for-agent,*) gh issue edit "$N" --repo "$REPO" --remove-label ready-for-agent \
                       && gh issue edit "$N" --repo "$REPO" --add-label grill-me-done ;;
esac
```

先移除再加：同時帶兩個 label 時 triage 會把它當成「放行做到一半」補完放行。`release-backport` 單不移出版本，不適用。

## 人類指示

人類在 Discord 說的，一律照做（過了守門才寫），而且**先記錄、再寫入**：在版本單 issue 留言，首行
`## 人類決定：<加｜刪｜先不要定版｜定版｜送審了｜退件｜通過｜…>`，內容有人類原話（引用）、台北時間
（`TZ=Asia/Taipei date '+%F %H:%M'`），簽名 `— By Summer (release-manage)`。重試時已有引用同一句原話的留言就不再留。
條件句、猜測、「應該可以吧」→ 回問。

- **加、刪** → 照「範圍調整」的做法寫（人類說的不受你的自主規則限制，例如人類要加需求進目前版本就加）。
- **先不要定版**（「等 #83 做完再定版」「v1.18.0 先別定版」）→ 只記錄，巡檢看到就不定版；人類之後說「定版」或
  「可以定版了」才恢復。
- **定版**（提早定版）→ 照「定版」做；還開著的承諾單人類沒說怎麼處理 → 移到下一版（人類說等就不定版）。
- **不同意這一版的範圍／亮點** → 照人類說的改版本單與 milestone；人類要整版重排就照「擬版本」重做那一份。
- **送審了、退件、通過** → 下面各段。

## 定版（`開發中` → `待定版`）

巡檢第 2 步，或人類說「定版」。

1. 事件前置值是 `開發中`，過「寫 `待定版`」與「先不要定版」的守門（人類親口說「定版」時，後者視為解除）。
2. **清掉 milestone 上沒完成的一般單**（`open_committed "$VERSION"`）：沒有 → 下一步；有 → 照「範圍調整」移到下一版
   （巡檢只移「可以移出」的單，人類說定版時全部移，除非人類說要等）。下一版 milestone 不存在 → 先照「擬版本」開一份 `草案`。
   `release-poller` 在首次定版時看到沒完成的承諾單會拒絕並通知，留著不處理版本會卡住。
3. **更新上架資訊**：照「擬版本」步驟 3 依實際已關閉的單重寫 `## 上架資訊` 段（素材、權限有沒有變以 `compare` 為準），
   要人類做的事都有 `release-prep` 單掛在這一版。
4. **寫 Release notes**（商店的「新功能」說明，也是 GitHub Release 的內文）：照下面「Release notes」寫進版本單最後。
5. `ms_edit "$MS" 狀態=待定版 && ms_put "$MS"`。
6. 版本單留言 `## Summer 決定：定版`（承諾幾張、完成幾張、移到下一版的單），摘要或回覆：已設 `待定版`；主機端
   `release-poller` 下一個 `:09` 會切好 `release/<x>.<y>` 分支、調版號、打 rc tag、把狀態改成 `已定版`，
   「可以打包送審」通知由 `human-notifier` 發（附版本單連結）。**打包、簽章、送審是人類的事。**修補版沿用同一條分支。
7. 巡檢第 3 步要等 `release-poller` 寫好 `分支` 才會讓下一版開始開發，最慢一小時。

### Release notes

`release-poller` 上線時用版本單的 `## Release notes` 段建 GitHub Release；人類打包時直接複製到商店。

1. 整理說明，寫進 `$STATE/notes.md`：亮點一句話放最前，接著用玩家看得懂的話條列本版內容（來源是 milestone
   上已關閉、沒有 `release-plan`／`release-prep`／`release-backport` 的單）。上架資訊有兩種以上語系時，每個語系一段，
   用 `### zh-TW`、`### en` 當小標。每個語系的內容 **500 字元以內**（Google Play「新功能」的上限）。
   **不放 `##` 開頭的行**（`###` 可以），`release-poller` 以下一個 `##` 當段落結尾。
2. 寫進版本單內文，**放在最後**（它後面的任何東西都會被收進 Release）；已有舊的 `## Release notes` 段先拿掉：

   ```bash
   PLAN=$(plan_no "$MS")
   gh issue view "$PLAN" --repo "$REPO" --json body --jq .body > "$STATE/plan.body"
   awk '/^##[ \t]+Release notes[ \t]*$/ {skip = 1; next} skip && /^##[ \t]/ {skip = 0} !skip {print}' "$STATE/plan.body" > "$STATE/plan.new"
   { cat "$STATE/plan.new"; printf '\n## Release notes\n\n'; cat "$STATE/notes.md"; } > "$STATE/plan.final"
   gh issue edit "$PLAN" --repo "$REPO" --body-file "$STATE/plan.final"
   ```

3. 讀回確認那段有內容、內容就是你寫的：

   ```bash
   gh issue view "$PLAN" --repo "$REPO" --json body --jq .body \
     | awk '/^##[ \t]+Release notes[ \t]*$/ {f = 1; next} f && /^##[ \t]/ {exit} f'
   ```

## 送審了、退件、重新定版、通過

送審了、退件、通過只在人類說時做；重新定版你自己做。都先過「事件與狀態」：前置值、已完成、守門。

### 送審了（`已定版` → `送審中`）

記錄人類決定，`ms_edit "$MS" 狀態=送審中 送審日=<YYYY-MM-DD> && ms_put "$MS"`。日期用人類說的日子，沒說用台北今天。
狀態還是 `待定版`（release-poller 還沒切好）→ 不寫，回覆「分支還沒切好，等 `:09` 那輪」。
重新送審一樣寫新的 `送審日`（「送審第 N 天」從最近一次送審算起）。

### 退件或發現嚴重問題（`送審中` → `修正中`）

1. 版本單留言記原話與原因（`## 人類決定：退件`）。
2. `ms_edit "$MS" 狀態=修正中 && ms_put "$MS"`。
3. **你決定修正單**：只收「擋住上架」（退件原因）或「上架後會出大事」的問題，其餘排到下一版。
   既有的單或新開一張都行；新開的單帶 `grill-me`、`spec-only`、`pm-owned` 與結尾簽名 `— By Summer`，內文寫明
   「`v…` 退件／發現問題」與原因。**掛上這個版本的 milestone**，版本單留言 `## Summer 決定：修正單`（哪幾張、為什麼）。
   Rick／Morty 會從 `release/<x>.<y>` 開分支做，修正 merge 後由 `release-poller` 開「帶回 main」的單。
   退件原因只是商店資料（截圖、說明文字、表單）而不是程式 → 不開修正單，改開 `release-prep` 單給人類，
   人類關掉那張後你照「重新定版」做（這次只會換 build）。
4. 回覆人類：記下了什麼、修正單是哪幾張；修好後你會自己重新定版。

### 重新定版（`修正中` → `待定版`）

巡檢第 1 步，或人類說修好了、重新打包。`release-poller` 重新定版時一定遞增 build、打新的 rc：分支上有新 commit 就
在上面疊版號 commit；分支 head 還是上次送審點的版號 commit（退件只改商店資料、沒有改程式）也照樣疊一個新的。
milestone 上還有 open 的修正單時它會擋住並 @人類。

1. **門檻**：`open_committed` 沒有單，而且這一版的 `release-prep` 單（退件後開的）都關了。有就不寫，摘要列出。
2. **提醒**：看分支上有沒有新 commit：

   ```bash
   gh api "repos/$REPO/commits?sha=release/<x>.<y>&per_page=1" --jq '.[0].commit.message | split("\n")[0]'
   ```

   印出以 `chore(release): v` 開頭 → 上次送審之後分支沒有新 commit，這次只會換 build 重新打包，在留言裡講明。
3. Release notes 要不要因修正改寫：修正是玩家看得到的才補一行。
4. `ms_edit "$MS" 狀態=待定版 && ms_put "$MS"`，版本單留言 `## Summer 決定：重新定版`。

### 通過（`送審中` → `待上線`）

`release-poller` 下一輪就依版本單的 `## Release notes` 建 Release，所以**先確認說明、最後才改狀態**。

1. 記錄人類決定。
2. Release notes 在定版時已寫好；讀回確認（「Release notes」步驟 3）。缺了或過時（退件後有修正）就照「Release notes」重寫。
3. `ms_edit "$MS" 狀態=待上線 && ms_put "$MS"`。
4. 回覆：貼出說明全文（要改請趁 `:09` 前說）；下一輪 `release-poller` 打正式 tag、建 Release、關 milestone。
   還開著的 `release-prep` 單與 `release-backport` 單會讓它停下來通知人類——先查
   `gh issue list --repo "$REPO" --milestone "$VERSION" --state open --label release-prep`（`release-backport` 同理），
   有就一併列在回覆裡。

## 上線後發現的問題

人類在 Discord 說某版上線後發現問題（或 triage 從 issue 看到標明上線版本的崩潰回報）。

1. 開單（或沿用既有的單）：內文註明「`v1.18.0` 上線後發現」、現象、影響；新單帶 `grill-me`、`spec-only`、
   `pm-owned`，結尾簽名 `— By Summer`。
2. **你決定**走哪條，版本單留言 `## Summer 決定：上線後問題`，附理由：
   - **該版還在 `送審中`** → 走「退件或發現嚴重問題」需要人類說退件或嚴重問題；你只能在回覆裡建議人類這麼說，
     不自己把狀態改成 `修正中`（送審狀態是人類知道的事實）。
   - **修補版 `v<x>.<y>.<z+1>`**：崩潰、資料遺失、付費功能壞掉這類等不了下一版的。先確認 `release/<x>.<y>` 分支存在
     （`gh api "repos/$REPO/branches/release/<x>.<y>"`），查不到（這個機制上線前的版本沒有這條分支）就排進下一版。
     沒有 `v<x>.<y>.<z+1>` milestone 就照「擬版本」指名該版本開一份（`開發中`，沒有 `亮點`），單掛上去；
     之後定版、送審照一般流程，不佔 `z == 0` 的開發中名額。
   - **排進下一版**：其他問題。照「範圍調整」加進目前 `開發中` 的版本（修正優先進最近一版）。

## 收尾

- 回覆或摘要**不 @ 任何人**（通知人類是 `human-notifier` 的事）：做了什麼、版本現在的狀態、接下來誰會做什麼
  （例如「`release-poller` 下一個 `:09` 切分支」）。
- 寫入失敗或讀回不一致 → 說清楚哪一步、停在哪個狀態，不假裝完成；下一輪巡檢照「事件與狀態」的三種結果接著做。
- 不碰 `已定版`、`已上線` 這兩個值，也不改 `分支`、`送審點`、`build`；milestone 的關閉歸 `release-poller`。
- 不建 release 分支、不改 `pubspec.yaml`、不打 tag、不建 GitHub Release、不建 label。
