---
name: product-planning
argument-hint: "[--property chainbreak|hangman]"
description: >-
  依 GA4 數據與現有 backlog 規劃下一步該做什麼、開需求 issue。由規劃中的
  usercron 每週一 09:00 觸發（訊息「執行 product-planning skill」，
  sender_name＝SummerPlanning；cronjob.toml 尚未寫入，見「已知限制」），
  或人類在 Discord 提出同類請求（如「規劃一下需求」「看數據開單」「這週該
  做什麼」）時觸發：chainbreak 與 hangman 兩個 GA4 property 各自分析、不
  平均，比對兩個 repo 現有 issue 避免重複開單，找出 1–3 個寫得出驗收條件
  的需求開 issue，body 結尾簽名 — By Summer、貼 grill-me 與 spec-only
  兩個 label，Discord 貼精簡摘要與連結。數據拿不到就明說，不推測冒充依據。
---

# Product Planning

> **本 skill 是責任鏈的起點，`backlog-triage` 接手後段**：這裡開的每張
> issue 要帶兩個標記，各自餵給不同的下游消費者，缺一不可：
> - **body 結尾 `— By Summer` 簽名**——`summer-grill-responder` 用來辨識
>   「這張單是不是 PM 開的，該不該讓 Summer 搶答」（共用同一個 wm4n
>   GitHub 帳號，author 分不出來，只能靠簽名）。漏寫的後果不是報錯，是
>   `summer-grill-responder` 不會觸發 Summer 回答，沒有任何錯誤訊息。
> - **`spec-only` label**——`jira-grill` 用來判斷「規格共識後要不要跳過
>   工程階段」，是明確意圖標記，不依賴身份判斷。漏貼的後果同樣不是報錯，
>   是 grill 會多走一輪完整的工程階段提問——不會卡住或誤觸發，只是比
>   PM 單該有的流程多問一輪，交給 Rick/Morty 依 `jira-grill` 的分流各自
>   判斷怎麼答。

## 觸發與參數

`$ARGUMENTS`：

- 空 → **兩個 property 都看**（chainbreak 與 hangman 各自完整跑一輪，順序
  不影響結果）。
- `--property chainbreak` 或 `--property hangman` → 只看那一個。

白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo，開 issue、查現況都
只對這兩個 repo 動作。

## 流程

### 1. 拉 GA4 數據——兩個 property 分開看，不准平均

對每個要看的 property，各自跑一次：

```bash
node /etc/openab/ga4/ga4-report.js --property "$GA4_PROPERTY_CHAINBREAK" --days 28 --preset overview
node /etc/openab/ga4/ga4-report.js --property "$GA4_PROPERTY_HANGMAN"    --days 28 --preset overview
```

`--preset` 另有 `pages`（頁面／功能點流量）、`retention`（留存），看想找的
訊號決定用哪個，也可以對同一個 property 跑多個 preset。追問細節（例如
「掉下去的那個頁面流量從哪來」）用 `--raw-request '<runReport JSON>'` 自組
查詢，不要因為 preset 不夠細就放棄深挖。

**chainbreak 與 hangman 是兩個獨立產品**，任何統計（成長率、留存率、事件
次數）一律各自報告，**不做兩者平均或加總**——平均出來的數字對應不到任何一個
真實產品，會誤導後面的判斷。

### 2. 蒐集兩個 repo 現況

```bash
gh issue list --repo wm4n/chainbreak --state open --json number,title,labels
gh issue list --repo wm4n/hangman    --state open --json number,title,labels
gh pr list --repo wm4n/chainbreak --state merged --limit 20 --json number,title,mergedAt
gh pr list --repo wm4n/hangman    --state merged --limit 20 --json number,title,mergedAt
```

開放 issue 用來**避免重複開單**：新想法先跟這份清單比對主題，明顯重疊的
不重開，改成在既有 issue 底下留言補充數據佐證。近期 merged PR 用來確認
「這個功能是不是已經做過了」——GA4 顯示的訊號如果來自一個已經上線的修正，
代表數據還沒反映最新版本，不是新需求。

### 3. 從數據與現況找出 1–3 個需求想法

把步驟 1 的訊號（掉點、沒人用的功能、卡住的漏斗）對照步驟 2 的現況，產出
1 到 3 個需求想法。

**完成條件是可驗證的驗收條件，不是想法本身**：每個想法都要能寫出具體、
可驗證的驗收條件（例如「結算頁跳出率從 X% 降到 Y% 以下」「新手教學完成率
達到 Z%」），寫不出這種條件的想法直接捨棄，不開單、不硬湊一個模糊的驗收
條件充數。

### 4. 開 issue

```bash
gh issue create --repo wm4n/chainbreak \
  --title "<標題>" \
  --label grill-me \
  --label spec-only \
  --body "$(cat <<'EOF'
## 背景

<這個需求是從哪個 GA4 訊號或 backlog 缺口發現的>

## 需求描述

<要做成什麼樣子>

## 驗收條件

- <條件一>
- <條件二>

## 數據依據

<引用的 GA4 指標、時間範圍、property；沒有數據支撐的部分明說「無數據依據」>

---
— By Summer
EOF
)"
```

body 五個段落缺一不可：標題另外用 `--title`，背景、需求描述、驗收條件、
數據依據都要有內容。**結尾一定是 `— By Summer`**，`--label grill-me` 與
`--label spec-only` 跟建 issue 同一步做完，這步不用等人類點頭。

⚠️ **簽名開頭的是 em dash（U+2014）「—」，不是連字號「-」**。兩者肉眼幾乎
分不出來，但下游用字串比對、打錯一個字元就完全比對不上。直接複製本文件
裡的 `— By Summer` 貼過去，不要自己重打。

### 5. Discord 貼精簡摘要

只貼標題、一句話理由、issue 連結，不要把完整 body 貼進 Discord——單則
訊息有 2000 字限制，超過會被截斷，而截斷後的訊息內容不完整還可能被其他
poller 誤判成新事件、重複觸發。

## 鐵則

- **數據拿不到就明說拿不到**，例如某個 preset 查不到資料、或某段時間 GA4
  沒有事件記錄，直接寫「這段無數據依據」。**絕不用推測冒充數據依據**——
  掰一個聽起來合理但沒有查證的數字，比誠實說「不知道」更糟，會讓後面排
  優先序的人依據假數據做判斷。
- 兩個 property **永遠分開報告**，不平均、不加總。
- issue body 結尾**逐字** `— By Summer`（em dash 開頭），這是
  `summer-grill-responder` 判斷該不該搶答的依據。
- **貼齊 `grill-me` 與 `spec-only` 兩個 label**——後者是 `jira-grill`
  判斷要不要跳過工程階段的依據，兩者用途不同，不能只貼一個。

## 不做什麼

- **不 clone repo、不建 worktree、不切分支**——這支 skill 只讀 GA4 報表與
  `gh issue`／`gh pr` 的列表資訊，不需要讀程式碼。
- **不排優先序、不決定該不該投產**——找需求、開單、貼 `grill-me` 到此為止，
  之後規格共識、排優先序、貼 `ready-for-agent` 是 `backlog-triage` 的職責。
- **不自己回答 grill 提問**——那是 `grill-respond` 的職責，由
  `summer-grill-responder` 偵測到問題後另外觸發。

## 已知限制

- **usercron 排程尚未部署**：目前只有規劃值（每週一 09:00，
  `sender_name`＝`SummerPlanning`），實際要寫進 Summer 容器內的
  `/home/node/.openab/cronjob.toml` 才會生效（見
  `docs/superpowers/specs/2026-09-20-summer-pm-pipeline-design.md`
  的觸發機制總表；`openab-ops` 的 `CRONJOB.md` 也註明這四個 job
  尚未寫入 cronjob.toml、未部署）；部署前，這支 skill 只能靠人類在
  Discord 主動要求觸發。
