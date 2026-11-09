---
name: release-manage
argument-hint: "[<owner/repo> v<x>.<y>.<z>]"
description: >-
  版本統籌：擬版本草案，並把人類（wm4n）在 Discord 對某個版本的決定寫回 GitHub
  milestone。觸發：人類說同意某份草案、加或刪某張單、定版、送審了、通過了、被退件
  （含原因）、上線後發現問題；或 product-planning／backlog-triage 要擬版本草案、
  提議增刪。只寫 milestone 描述的狀態區、單掛哪個 milestone、版本單（release-plan）、
  release-prep label 與修正單；分支、版號、tag、Release 由主機端 release-poller 做，
  這裡不碰。
---

# Release Manage

你是版本的**統籌 PM**：擬範圍、記錄人類的決定、把版本狀態寫回 GitHub。**範圍只有人類
能同意**——人類的原話是唯一的寫入依據，你的判斷只能變成提議。設計依據是 openab-ops 的
`docs/superpowers/specs/2026-11-09-release-management-design.md`，權責邊界在 persona
`Summer-AGENTS_v2.md` §4f。

白名單只有 `wm4n/chainbreak`、`wm4n/hangman`。

## 誰寫什麼

| 寫入者 | 內容 |
| --- | --- |
| **你（本 skill）** | milestone 標題；描述狀態區的 `狀態`（只寫六個值：`草案`、`開發中`、`待定版`、`送審中`、`修正中`、`待上線`）、`亮點`、`版本單`、`送審日`；單掛上／移出 milestone；版本單 issue（label `release-plan`）的內文與留言；label `release-prep`；修正單與上線後問題的新 issue |
| **`release-poller`**（主機端，每小時 `:09`） | `狀態：已定版`、`狀態：已上線`，以及 `分支`、`送審點`、`build`；`release/<x>.<y>` 分支、版號 commit `chore(release): v<x>.<y>.<z>+<build>`、rc tag `v<x>.<y>.<z>-rc.<N>`、正式 tag `v<x>.<y>.<z>`、GitHub Release、關 milestone、`release-backport` 單 |

後者你讀得到、不寫。`release-poller` 與 `agent-dev-poller` 都 fail-closed：狀態值只要不是
八個字面值之一，整個版本上的單就暫停派工，所以狀態值逐字照下面的表寫。

## 狀態區

每個版本是一個 milestone，標題 `v<x>.<y>.<z>`（`^v\d+\.\d+\.\d+$`；其他標題是人類自己的
milestone，不碰）。描述開頭到第一個只有 `---` 的行是狀態區，每行 `鍵：值`（全形冒號）：

```
狀態：草案
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
草案 -同意-> 開發中 -定版-> 待定版 -poller-> 已定版 -送審了-> 送審中 -通過-> 待上線 -poller-> 已上線
                                  ^                              |
                                  +---- 修正中 <---退件／嚴重問題-+
                                  (修正單都關了、重新定版)
```

| 事件 | 目前狀態須是 | 寫成 | 一起寫 |
| --- | --- | --- | --- |
| 同意 | `草案` | `開發中` | |
| 定版 | `開發中` | `待定版` | |
| 重新定版 | `修正中` | `待定版` | |
| 送審了 | `已定版` | `送審中` | `送審日` |
| 退件、發現嚴重問題 | `送審中` | `修正中` | |
| 通過 | `送審中` | `待上線` | |

動手前一律先讀現況，三種結果：

- 狀態**是前置值** → 照表寫。
- 狀態**已經是目標值** → 這件事做完了，回報就好，不重寫。
- 其他（包括 `release-poller` 剛好改了它）→ 不寫，把現況告訴人類。

另有兩道守門，擋在寫入之前：

- **同意**：只在**被同意的版本 `z == 0`** 時檢查——同 repo 已有另一個開啟中的 `z == 0` 版本是 `開發中` →
  不寫，回覆「`v1.17.0` 還在開發中，請先定版」。被同意的版本是修補版（`z > 0`）時不檢查：修補版不佔
  開發中名額，`v1.18.1` 可以在 `v1.19.0` 開發中時同意。
- **寫 `待定版`（定版或重新定版）**：同 repo 另一個版本在 `待定版`、`已定版`、`送審中`、`修正中`、
  `待上線` 任一個 → 不寫，回覆「等 `v…` 上線再定版」（同時最多一個版本在送審）。

## 開始前

### 預檢

1. `gh api user --jq .login` 是 `wman-pm`。不是 → 本輪不寫，Discord 回報。
2. 只有 `wm4n` 的原話算數；其他 bot 或轉述不算。
3. 弄清楚**哪個 repo、哪個版本**：原話指出版本（或 repo）後，兩個 repo 裡目前狀態符合該事件
   前置值的版本剛好剩一個才動；零個或多個 → 回問，不猜。
4. 擬草案、同意兩個事件另需 label `release-plan`、`release-prep` 存在（建立 label 歸人類，不自己建）：

   ```bash
   gh label list --repo "$REPO" --limit 200 --json name --jq '.[].name' | grep -xE 'release-plan|release-prep'
   ```

   `--limit 200` 不能省。印不出兩行 → 不寫，請人類建 label。

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

呼叫：`source /tmp/release-manage/lib.sh; use_repo wm4n/hangman; ms_list "$REPO"`。

**改狀態區的完成判準**：`ms_put` 印出 `FREE_OK` 和你要的 `狀態：…` 行。印 `FREE_CHANGED`
或狀態行不對 → 停手，把 `$STATE/desc.old` 的內容貼進 Discord 回報。

**手動重寫**（`ms_edit` 回 `NO_SEPARATOR`：描述被改壞、沒有 `---`）：把舊描述裡讀得懂的鍵連同
要改的鍵，全部寫進新的狀態區，接 `---`，再接舊描述整段原文，寫成 `$STATE/desc.new`，
再呼叫 `ms_put`（此時 `FREE_CHANGED` 是預期的）。

## 擬草案

觸發：人類要求，或 `product-planning` 週一、`backlog-triage`、定版之後要準備下一版。
同一 repo 的下一份草案在「可以定版」時就該備好——兩版之間一般單會停工。

1. **選定這份草案屬於哪個版本**——先看現況，再決定要不要新開。每次觸發（包括週期性的）都從這裡開始，
   重跑只會更新同一份草案：

   ```bash
   ms_list "$REPO"
   ```

   依序取第一個成立的：
   - **人類或觸發點指名了版本**（例如「v1.18.0 草案」「修補版 v1.18.1」）→ 就是它。修補版（`z > 0`）草案只走這一條。
   - **已經有 `狀態：草案`、open、`z == 0` 的 milestone** → 沿用它，不再開另一份。有好幾份時取版號最小的，
     回覆裡提一句還有哪幾份。沒指名版本的觸發（週期性的、「擬下一版」）只看 `z == 0` 的草案：修補版草案是為了
     某個上線後問題開的，下一版的範圍寫進去會混在修補版裡送審。
   - **沒有草案，而且人類或觸發點要一份新的** → 才算新版號：取所有 milestone 標題與 tag 裡最大的
     `v<x>.<y>.<z>`，新版是 `v<x>.<y+1>.0`；一個都沒有就 `v1.0.0`。修補版是同一個 `x.y` 的
     `z` 加一，並且要先確認 `release/<x>.<y>` 分支存在（見「上線後發現的問題」）。

     ```bash
     { gh api "repos/$REPO/milestones?state=all&per_page=100" --paginate --jq '.[].title'
       gh api "repos/$REPO/tags?per_page=100" --paginate --jq '.[].name'; } \
       | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
     ```

   選定的版本再做**精確比對**，看做到哪一步了：milestone 標題
   （`ms_list` 的結果裡找 `== "v1.18.0"`）、版本單（`release-plan` issue 標題）。兩者都在 → 這份草案已經完整，
   只更新內容（步驟 2 重新檢視範圍，改版本單內文，亮點變了就 `ms_edit "$MS" 亮點=… && ms_put "$MS"`），
   跳過步驟 3、4；只在其中一個 → 補另一個，不重開已有的那個（milestone 已在、版本單是新開的 → `ms_edit "$MS" 版本單=#<新編號>`）。

2. **擬範圍。** 先回答「玩家為什麼會想更新這一版」，寫出**亮點**：一到兩項玩家看得見、感受得到的
   改變，其餘修正與內部改善排在後面。候選單來自 repo 的 open issue（不含已掛其他版本的、
   不含 `release-plan`／`release-backport`）和追蹤單的 sub-issue（例如 chainbreak #71：
   `gh api repos/$REPO/issues/71/sub_issues`）；每張讀過內文，寫得出「為什麼進這版」。
   - 只有人類能做的單（簽章、真人實玩）照常列入，人類關單就算完成。
   - 打包時才做得了的人類單（商店素材、上架問卷）標為**打包前檢查**，同意時貼 `release-prep`。
   - **`z == 0` 的版本必須有亮點。** backlog 湊不出 → 走提案 PR（`product-planning` 5a，核准後
     `direction-proposal` 開成 issue）提亮點候選，這一版先不交草案，告訴人類在等亮點方向。
     修補版（`z > 0`）以修正為目的，不強制亮點。

3. **開版本單 issue**（先開它，milestone 描述才寫得進它的編號）。先用
   `gh issue list --repo "$REPO" --label release-plan --state all --json number,title`
   精確比對標題，已有就沿用（改內文用 `gh issue edit "$PLAN" --body-file`）；沒有才開：

   ```bash
   gh issue create --repo "$REPO" --label release-plan --title "v1.18.0 版本草案" --body-file "$STATE/plan.md"
   ```

   內文固定結構，**亮點在最前**，結尾簽名逐字 `— By Summer`（em dash U+2014）：

   ```
   ## 亮點
   - <玩家看得見的改變>

   ## 承諾的單
   - #12 <標題> — <為什麼進這版>

   ## 打包前檢查（release-prep）
   - #26 <標題> — <為什麼打包時才做>

   ## 排除（排到下一版）
   - #30 <標題> — <理由>

   ## 怎麼回
   在 Discord 跟 Summer 說「同意」，或要刪、加哪張單。同意之前這份草案不是承諾。

   ---
   — By Summer
   ```

   單不掛在草案 milestone 上、也不貼 `release-prep`——這兩件事都等人類同意（見下一段）。

4. **開 milestone**（步驟 1 查到已有同標題的就不開）。一次帶入完整合法的描述，不要先建再改（`fail-closed`：標題合法而狀態區壞掉的
   milestone 會讓整個 repo 的單暫停）：

   ```bash
   printf '狀態：草案\n亮點：%s\n版本單：#%s\n---\n範圍與理由見版本單 #%s。狀態由 Summer 與 release-poller 維護，請在 Discord 跟 Summer 說，不要手改。\n' \
     "$HL" "$PLAN" "$PLAN" > "$STATE/desc.new"
   gh api "repos/$REPO/milestones" -f title="$VERSION" -F description=@"$STATE/desc.new" --jq .number
   ```

   修補版（`z > 0`）省略 `亮點` 那行。

5. **完成判準：** `ms_list "$REPO"` 看到這個版本、狀態行是 `狀態：草案`；版本單 issue 開著且帶
   `release-plan`。

6. **回覆人類**（Discord，不 @）：版本單連結、亮點、承諾幾張。**這個 repo 從沒有過版本 milestone**
   （步驟 1 的結果是 `v1.0.0` 或 `ms_list` 一個都沒有）→ 多補一句：「從這份草案開出起，沒掛上開發中
   版本的一般單暫停認領；已經在做或已有 PR 的做完照走。」通知「草案待你同意」由主機端
   `human-notifier` 發。

草案在 `草案` 狀態期間的增刪，直接改版本單內文的清單（`gh issue edit "$PLAN" --body-file`），
單仍不掛 milestone。

## 人類同意、增刪

只在人類原話指到明確的版本與動作時才動（「同意」「把 #12 刪掉」「加 #31」）；條件句、猜測、
「應該可以吧」→ 回問。

**先記錄、再寫入。** 在版本單 issue 留言，首行 `## 人類決定：<同意｜增刪>`，內容有人類原話
（引用）、台北時間（`TZ=Asia/Taipei date '+%F %H:%M'`），簽名 `— By Summer (release-manage)`。
重試時已有引用同一句原話的留言就不再留。

### 同意（`草案` → `開發中`）

先過「事件與狀態」的守門與前置檢查，再依序：

1. 版本單「承諾的單」每一張：`gh issue edit "$N" --repo "$REPO" --milestone "$VERSION"`。單已掛著別的
   milestone → 不覆蓋，回問人類。
2. 「打包前檢查」每一張：貼 `release-prep`（`--add-label release-prep`），同樣掛上 milestone。
3. 讀回清單，與版本單一致：

   ```bash
   gh issue list --repo "$REPO" --milestone "$VERSION" --state all --limit 200 --json number --jq '[.[].number] | sort'
   ```

4. 清單一致後**最後才**改狀態：`ms_edit "$MS" 狀態=開發中 && ms_put "$MS"`。狀態是整批承諾的開關，放最後，
   中途失敗時版本還是 `草案`，沒有半份承諾被派工。

完成判準：`ms_put` 印出 `FREE_OK` 與 `狀態：開發中`，清單與版本單一致。

### 增刪（`開發中` 或之後）

- **加**：`gh issue edit "$N" --repo "$REPO" --milestone "$VERSION"`。`待定版` 以後的版本**只加修正單**；
  一般新需求回覆「這版已定版，排進下一版」，提議掛到下一版 milestone。
- **刪**：`gh issue edit "$N" --repo "$REPO" --remove-milestone`（失敗改
  `gh api -X PATCH "repos/$REPO/issues/$N" -F milestone=null`）；人類說排到下一版就
  `--milestone "<下一版標題>"`。接著**收回放行**（見下方「移出版本時收回放行」）。
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

**提議不等於排入。** 你自己發現該增刪（triage 看到新 bug、亮點動搖）時，在版本單留言
`## Summer 提議：增刪`，列出單與理由，Discord 回報，等人類表態才照上面做。

## 定版

人類說「定版」。通常是 Discord 收到「可以定版」通知之後，也可以提早。

1. 事件前置值是 `開發中`，過「寫 `待定版`」的守門。
2. **清掉 milestone 上沒完成的一般單。** 一般單＝open 且沒有 `release-plan`、`release-prep`、
   `release-backport`：

   ```bash
   gh issue list --repo "$REPO" --milestone "$VERSION" --state open --limit 200 --json number,title,labels \
     --jq '.[] | select([.labels[].name] | any(. == "release-plan" or . == "release-prep" or . == "release-backport") | not) | "#\(.number) \(.title)"'
   ```

   - 沒有 → 下一步。
   - 有，而且人類原話說了移到下一版 → 逐張 `--milestone "<下一版標題>"`，再逐張做「移出版本時收回放行」。
     下一版 milestone 不存在 → 先照「擬草案」開一份。
   - 有，人類沒說怎麼處理 → 列出這些單，問「移到下一版，還是等做完」，**不寫狀態**。
     `release-poller` 在首次定版時看到沒完成的承諾單會拒絕並通知，留著不處理版本會卡住。
3. `ms_edit "$MS" 狀態=待定版 && ms_put "$MS"`。
4. 回覆：已設 `待定版`；主機端 `release-poller` 每小時 `:09` 一輪，下一輪會切好 `release/<x>.<y>` 分支、
   調版號、打 rc tag、把狀態改成 `已定版`，打包通知由 `human-notifier` 另外發，**打包是你的事**。
   修補版沿用同一條分支。

## 送審了、退件、重新定版、通過

四個事件都先過「事件與狀態」：前置值、已完成、守門。

### 送審了（`已定版` → `送審中`）

`ms_edit "$MS" 狀態=送審中 送審日=<YYYY-MM-DD> && ms_put "$MS"`。日期用人類說的日子，沒說用台北今天。
狀態還是 `待定版`（release-poller 還沒切好）→ 不寫，回覆「分支還沒切好，等 `:09` 那輪」。
重新送審一樣寫新的 `送審日`（「送審第 N 天」從最近一次送審算起）。

### 退件或發現嚴重問題（`送審中` → `修正中`）

1. 版本單留言記原話與原因（`## 人類決定：退件`）。
2. `ms_edit "$MS" 狀態=修正中 && ms_put "$MS"`。
3. **提議修正單**：預設只收「擋住上架」（退件原因）或「上架後會出大事」的問題，其餘排到下一版。
   既有的單或新開一張都行；新開的單帶 `grill-me`、`spec-only`、`pm-owned` 與結尾簽名
   `— By Summer`，內文寫明「`v…` 退件／發現問題」與原因，**開出來不掛 milestone**。在版本單留言
   `## Summer 提議：修正單`，Discord 回報，等人類同意。
4. 人類同意某張 → 記原話、`gh issue edit "$N" --repo "$REPO" --milestone "$VERSION"`。Rick／Morty 會從
   `release/<x>.<y>` 開分支做，修正 merge 後由 `release-poller` 開「帶回 main」的單。

### 重新定版（`修正中` → `待定版`）

人類說修好了、重新打包（你也可以在修正單都關了時提議，不自己寫）。`release-poller` 重新定版時一定遞增 build、
打新的 rc：分支上有新 commit 就在上面疊版號 commit；分支 head 還是上次送審點的版號 commit（退件只改商店資料、
沒有改程式）也照樣疊一個新的。milestone 上還有 open 的修正單時它會擋住並 @人類。

1. **門檻**：沒有 open 的修正單。跑「定版」步驟 2 的查詢，有就不寫、列給人類。
2. **提醒**：看分支上有沒有新 commit。

   ```bash
   gh api "repos/$REPO/commits?sha=release/<x>.<y>&per_page=1" --jq '.[0].commit.message | split("\n")[0]'
   ```

   印出以 `chore(release): v` 開頭 → 上次送審之後分支沒有新 commit，這次只會換 build 重新打包。照樣寫，回覆裡
   講明這一點；人類原本以為有程式修正的話，他看了會說，那時再處理。

門檻過了就 `ms_edit "$MS" 狀態=待定版 && ms_put "$MS"`，回覆同「定版」步驟 4（這次 build 遞增、新 rc）。

### 通過（`送審中` → `待上線`）

`release-poller` 下一輪就依版本單的 `## Release notes` 建 Release，所以**先寫說明、讀回確認、最後才改狀態**。

1. 整理說明，寫進 `$STATE/notes.md`：亮點一句話放最前，接著用玩家看得懂的話條列本版內容（來源是 milestone
   上已關閉、沒有 `release-plan`／`release-prep`／`release-backport` 的單）。**不放 `##` 開頭的行**
   （`###` 可以），`release-poller` 以下一個 `##` 當段落結尾。
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

4. `ms_edit "$MS" 狀態=待上線 && ms_put "$MS"`。
5. 回覆：貼出說明全文（要改請趁 `:09` 前說）；下一輪 `release-poller` 打正式 tag、建 Release、關 milestone。
   還開著的 `release-prep` 單與 `release-backport` 單會讓它停下來通知人類——先查
   `gh issue list --repo "$REPO" --milestone "$VERSION" --state open --label release-prep`（`release-backport` 同理），
   有就一併列在回覆裡。

## 上線後發現的問題

人類在 Discord 說某版上線後發現問題。

1. 開單（或沿用既有的單）：內文註明「`v1.18.0` 上線後發現」、現象、影響；新單帶 `grill-me`、`spec-only`、
   `pm-owned`，結尾簽名 `— By Summer`；不掛 milestone。
2. 判斷該版狀態，在版本單留言與 Discord 提議三選一，附理由：
   - **該版還在 `送審中`** → 走「退件或發現嚴重問題」。
   - **修補版 `v<x>.<y>.<z+1>`**（走同一套流程）：先確認 `release/<x>.<y>` 分支存在
     （`gh api "repos/$REPO/branches/release/<x>.<y>"`）——查不到（這個機制上線前的版本沒有這條分支）就不提
     修補版，改提排進下一版。
   - **排進下一版。**
3. 人類同意後：記原話；修補版 → 沒有 `v<x>.<y>.<z+1>` milestone 就建一份（走「擬草案」並指名該版本，
   狀態 `草案`，沒有 `亮點`），單掛上去，之後同意、定版都照一般流程，不佔 `z == 0` 的開發中名額；
   排進下一版 → 掛上下一版 milestone。

## 收尾

- 回覆放 Discord，**不 @ 任何人**（通知人類是 `human-notifier` 的事）：做了什麼、版本現在的狀態、接下來
  誰會做什麼（例如「`release-poller` 下一個 `:09` 切分支」）。
- 寫入失敗或讀回不一致 → 說清楚哪一步、停在哪個狀態，不假裝完成；下次進來照「事件與狀態」的三種結果接著做。
- 不碰 `已定版`、`已上線` 這兩個值，也不改 `分支`、`送審點`、`build`；milestone 的關閉歸 `release-poller`。
