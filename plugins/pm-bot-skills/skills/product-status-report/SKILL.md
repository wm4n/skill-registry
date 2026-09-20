---
name: product-status-report
argument-hint: "[--since <days>]"
description: >-
  彙整 chainbreak 與 hangman 的近況，發一則 Discord 定期回報。由規劃中
  的 usercron 週五 17:00 觸發（訊息「執行 product-status-report
  skill」，sender_name＝SummerReport；cronjob.toml 尚未寫入，見「已知
  限制」），或人類在 Discord 提出同類請求（如「這週進度如何」「整理一份
  週報」「上次回報之後有什麼進展」）時觸發：兩個 GA4 property 的關鍵
  指標（分開報告，不平均、不加總）、backlog 各 label 的張數、本期
  merged PR、卡單與 agent-failed 清單、下期建議，全部濃縮進**一則**
  Discord 訊息。訊息長度是硬性上限 2000 字元（超過會被截斷並導致重複
  觸發，這是本 skill 唯一會不斷撞到的坑）。數據拿不到就明說查無資料，
  不推測冒充。
---

# Product Status Report

> **本 skill 的完整輸出就是這則 Discord 訊息本身**，不是「GitHub 已有
> 完整紀錄、Discord 只放精簡摘要」那種模式——沒有對應的單一 issue／PR
> 可以承載完整版本，這則訊息就是全部。這也是為什麼下方「2000 字元
> 上限」被反覆強調：其他 skill 超字數頂多是摘要不夠精簡，這支 skill
> 超字數等於整份報告直接消失，只剩一句被截斷的殘句，還可能觸發重複
> 送出。

## 觸發與參數

`$ARGUMENTS`：

- 空 → 回報期間預設**過去 7 天**。
- `--since <days>` → 回報期間改成過去 `<days>` 天（例如
  `--since 14` 看過去兩週）。

白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo。

## 流程

### 1. 算出回報起始日期

```bash
SINCE_DAYS="${SINCE_DAYS:-7}"   # 由 $ARGUMENTS 的 --since 覆蓋，預設 7
CUTOFF_DATE=$(node -e '
const days = Number(process.argv[1]);
const d = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
process.stdout.write(d.toISOString().slice(0, 10));
' "$SINCE_DAYS")
echo "回報區間：$CUTOFF_DATE 至今"
```

用 `node -e` 算日期，不假設 `date` 指令的 GNU／BSD 參數形式一致（容器
是 Linux，開發機常是 macOS，兩邊 `date -d`／`date -v` 語法不同，
`node` 內建的 `Date` 沒有這個落差）。

### 2. GA4 關鍵指標——兩個 property 分開查，不准平均

```bash
node /etc/openab/ga4/ga4-report.js --property "$GA4_PROPERTY_CHAINBREAK" --days "$SINCE_DAYS" --preset overview
node /etc/openab/ga4/ga4-report.js --property "$GA4_PROPERTY_HANGMAN"    --days "$SINCE_DAYS" --preset overview
```

`--days` 直接帶 `$SINCE_DAYS`，回報期間跟查詢期間對齊。看想強調的訊號
決定要不要另外跑 `--preset retention`／`pages`，不必每次都跑滿三個
preset——回報要精簡，查詢也不必比需要的多。

**chainbreak 與 hangman 是兩個獨立產品，任何指標（成長率、留存率、
事件次數）一律各自報告，不做兩者平均或加總**——平均出來的數字對應不到
任何一個真實產品，會誤導看報告的人以為兩個產品表現接近。

查詢失敗或某段時間沒有資料，回報裡對應欄位寫「查無資料」，**不准用
推測冒充**——猜一個聽起來合理的數字，比誠實承認「這段沒查到」更糟，
會讓看報告的人依據假數據做下一步判斷。

### 3. Backlog 各 label 張數

```bash
gh issue list --repo wm4n/chainbreak --state open --json number,labels --limit 200
gh issue list --repo wm4n/hangman    --state open --json number,labels --limit 200
```

對每個 repo 各自算出下列七個 label 各自的張數（一張 open issue 在正常
情況下只會落在其中一個狀態，直接數 `labels` 陣列裡出現該 label 名稱
的 issue 數即可）：`grill-me`、`grill-me-active`、`grill-me-done`、
`ready-for-agent`、`agent-active`、`agent-done`、`agent-failed`。

**固定用下面這組縮寫，兩個產品各一行**，不要中途改字或省略前綴——
`grill-me-active`／`agent-active` 只差一個字首，若各自砍成「active」
會分不出是哪一個：

| 縮寫 | 對應 label |
| --- | --- |
| G | `grill-me` |
| GA | `grill-me-active` |
| GD | `grill-me-done` |
| R | `ready-for-agent` |
| AA | `agent-active` |
| AD | `agent-done` |
| AF | `agent-failed` |

這組縮寫在整份回報裡通用，模板見下方「Discord 訊息模板」。

### 4. 本期 merged PR

```bash
gh pr list --repo wm4n/chainbreak --state merged --limit 30 --json number,title,mergedAt
gh pr list --repo wm4n/hangman    --state merged --limit 30 --json number,title,mergedAt
```

只保留 `mergedAt` 落在 `$CUTOFF_DATE` 之後的項目（讀 JSON 直接比對，
不需要額外工具）。`--limit 30` 是抓寬一點的安全邊界；若剛好 30 筆全部
落在區間內，代表這期間量異常大，在回報裡註明「merged 數量達查詢上限
30，實際可能更多」，不要默默漏算。

### 5. 卡單與 `agent-failed` 清單

```bash
gh issue list --repo wm4n/chainbreak --label agent-failed --state open --json number,title,url
gh issue list --repo wm4n/hangman    --label agent-failed --state open --json number,title,url
gh issue list --repo wm4n/chainbreak --label agent-active --state open --json number,title,updatedAt,url
gh issue list --repo wm4n/hangman    --label agent-active --state open --json number,title,updatedAt,url
```

`agent-failed` 直接列出（等的是人類或 `backlog-triage` 去修規格）。
`agent-active` 沿用 `backlog-triage` 段 3 同樣的 24 小時門檻：
`updatedAt` 距現在超過 24 小時列為**疑似卡單**（措辭同樣要留查證空間，
不寫成「已確認卡住」，理由同 `backlog-triage`）。

### 6. 下期建議

依步驟 2–5 蒐集到的訊號，寫 1–2 句具體建議（例如「hangman 留存率連續
兩週下滑，建議優先排 #23」「chainbreak 目前 3 張 agent-failed 卡著，
建議先清規格債」）。**查不到明確訊號就直接說「本期無明顯異常訊號」**，
不要為了填滿這一段硬湊一個聽起來像洞見但沒有數據支撐的建議。

### 7. 組訊息、檢查字數、送出

依下方「Discord 訊息模板」組出**一則**訊息，送出前確認總字元數（含
emoji、換行、markdown 符號）在 2000 字元以內。逼近或超過上限時，按
下面順序砍到符合為止，**不要整段從頭改寫**：

1. 先砍「下期建議」的細節，只留一句話結論。
2. merged PR 只列數量與代表性的 2–3 個編號，其餘寫「其餘 N 個略」。
3. 卡單／`agent-failed` 清單每個產品最多列 3 張，其餘寫「還有 N 張，
   詳見 GitHub 對應 label」。
4. 仍然超過 → GA4 指標只留最關鍵的 1 個數字，其餘訊號留到下次或另外
   在 Discord 追問時展開。

## Discord 訊息模板

```
📊 產品週報｜<CUTOFF_DATE> 至今
標籤縮寫：G=grill-me／GA=grill-me-active／GD=grill-me-done／
R=ready-for-agent／AA=agent-active／AD=agent-done／AF=agent-failed

**Chainbreak**
GA4：<核心指標 1–2 個，例如「活躍使用者 -12%、結算完成率 68%」>
Backlog：G1／GA0／GD2／R1／AA1／AD0／AF1
Merged：3 個（#101 #103 #107）
卡單：AF 1 張（#88）；疑似卡住 0 張

**Hangman**
GA4：<核心指標>
Backlog：G0／GA1／GD0／R0／AA2／AD1／AF0
Merged：1 個（#19）
卡單：AF 0 張；疑似卡住 1 張（#22，逾 30 小時未更新，建議核實 pod 狀態）

下期建議：<1–2 句具體建議，查無訊號就寫「本期無明顯異常訊號」>
```

**Backlog 與卡單兩行一律用縮寫，不要在同一則訊息裡一邊寫縮寫一邊寫
全名**——`GA`（`grill-me-active`）跟 `AA`（`agent-active`）只差一個
字首，若卡單那行單獨寫回「agent-failed」而 Backlog 那行寫「AF」，
容易讓人以為是兩個不同的東西。

**這個模板的骨架本身不到 500 字元，但套用真實資料後很容易膨脹到接近
甚至超過上限**——GA4 指標描述變長、merged PR 或卡單張數變多，每一項
都在往上加，範例看起來精簡不代表套用真實資料後一定在限額內。這正是
「送出前一定要實測字元數」這條規則存在的原因，不能只憑模板長度的
直覺判斷。

## 鐵則

- **兩個產品永遠分開報告，不平均、不加總**——chainbreak 與 hangman 是
  兩個獨立產品，混在一起的數字對應不到任何一個真實產品。
- **數據拿不到就明說查無資料，不推測冒充**：GA4 查詢失敗、某段時間沒
  事件記錄、或 `gh` 查詢出錯，對應欄位直接寫「查無資料」／「這部分
  無法查證」，不編一個聽起來合理但沒查過的數字或結論。
- **訊息長度 2000 字元是硬性上限**：超過會被截斷並導致重複觸發（見
  persona `Summer-AGENTS_v2.md` §2「訊息長度」鐵則）。送出前務必實際
  數過字元數，逼近上限時依上方「組訊息、檢查字數、送出」的順序砍，不
  是送出去撞牆才回頭改。
- **一輪只送一則 Discord 訊息**，不要因為想塞更多細節就拆成多則
  ——多則訊息一樣有重複觸發的風險，且不符合「精簡回報」的設計初衷。
- 白名單只有 `wm4n/chainbreak`、`wm4n/hangman` 兩個 repo。

## 不做什麼

- **不開 issue、不改任何 label、不貼 PR comment**——這支 skill 純粹
  彙整既有數據發報告，不對 backlog 或 PR 做任何動作，那些是
  `product-planning`／`backlog-triage`／`acceptance-review` 的職責。
- **不 clone repo、不建 worktree**——只讀 GA4 報表與 `gh issue`／
  `gh pr` 的列表資訊。
- **不把兩個產品的數字合併成單一總表**——即使只是並排列出方便閱讀，
  每個數字也必須看得出來屬於哪個產品。
- **不為了填滿模板硬湊訊號或建議**——查無資料、查無異常訊號，就照實
  寫「查無資料」「本期無明顯異常訊號」。

## 已知限制

- **backlog 張數假設每張 open issue 只掛一個狀態 label**：正常流程下
  七個狀態 label 互斥，但若因為某次操作中途失敗留下同時掛兩個 label
  的邊界情況（例如 `backlog-triage` 「先加後移除」中間失敗），統計會
  對那張 issue 重複計數。這是沿用現有 label 狀態機設計的已知邊界，本
  skill 不額外偵測或修正。
- **merged PR 統計靠 `--limit 30` 抓寬邊界，不是精確分頁查詢**：查詢
  期間內 merged 數量正常情況遠低於 30，超過時回報裡會註明「達查詢
  上限」，但不會自動翻頁抓完整清單。
- **`agent-active` 逾時只是訊號，不是已核實的事實**：跟
  `backlog-triage` 段 3 相同的限制——Summer 看不到 Mac mini／k3s 上
  實際的 pod 狀態，`updatedAt` 逾時多數情況代表卡住，但也可能只是
  剛好這一輪還沒留言。
- **usercron 排程尚未部署**：目前只有規劃值（週五 17:00，
  `sender_name`＝`SummerReport`），實際要寫進 Summer 容器內的
  `/home/node/.openab/cronjob.toml` 才會生效（見
  `docs/superpowers/specs/2026-09-20-summer-pm-pipeline-design.md`
  的觸發機制總表）；部署前，這支 skill 只能靠人類在 Discord 主動要求
  觸發。
