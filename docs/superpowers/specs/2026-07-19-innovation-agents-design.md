# 產品創新 Agent（創新 bot 群）設計文件

日期：2026-07-19
狀態：設計已確認，並依 [設計 review](../reviews/2026-07-19-innovation-agents-design-review.md) 修訂（採納 8 項、合併 2 項為 coordinator 方案、否決分段上線建議），待實作規劃

## 背景與目標

延續 [PM bot 設計](2026-07-15-product-manager-agent-design.md)：現有遊戲產品的開發流程已 bot 化（openab + Discord），PM bot 負責數據驅動的成長迴圈（感知 → 假設卡 → 開 issue）。

本設計新增**創新 bot 群**：獨立於 PM bot 的平行 bot，專職產品創新發想——結合時事、與其他產品/玩法融合、新增/刪去/改變功能玩法，以及萌芽全新產品的種子。目標是為產品持續注入 PM bot 數據迴圈之外的創意來源，並以「天時地利人和重審」機制讓好點子在對的時機被撈回來，最大化創新命中率。

## 架構總覽：創意平面與控制平面分離

系統分兩層：

- **創意平面**：多個創意實例（人格 × 模型），只負責發想、評估、辯論。**不直接寫 journal repo。**
- **控制平面**：一個不做創意的 **coordinator**（兼每日 scout），是 journal repo 中創新相關檔案的**唯一寫入者**。

### 人格 × 模型 = 創意實例

```
人格規格（persona spec）×  模型（model）＝ 創意實例
     工匠規格             claude          工匠-claude
     工匠規格             gpt             工匠-gpt
     狂想規格             claude          狂想-claude
     狂想規格             gpt             狂想-gpt
     狂想規格             grok            狂想-grok
```

- **人格規格**是可複用的定義檔（含版本號 `persona_version`）：方法論、守門規則、配額、session 流程。
- **創意實例**＝人格規格 + 指定 model backend 的 openab 部署。
- Phase 1 直接多模型上線（claude / gpt / grok，以 openab 實際能接的 backend 為準；接不上的實例先不建）。**此為明確決策**：多模型基準線正是要驗證的東西，成功率優先，不為模型費用做取捨；控制平面風險由 coordinator 集中處理，不以砍模型或分段上線來規避。

### 兩種人格

| | 工匠（Artisan） | 狂想（Maverick） |
|---|---|---|
| 性格 | 結構引導、系統性 | 天馬行空、自由發散 |
| 方法 | 創新運算子庫：每次 session 輪換/挑選運算子（時事結合、玩法融合、加法、減法、變形等；初版清單在實作計畫中定義，之後由統計回饋優化）套用在產品功能清單上 | 無方法約束，高 temperature 自由腦暴 |
| 守門 | rubric 全維度達標才發 | **只查重**——不設可行性門檻、不設願景牴觸門檻；低可行性卡標 `moonshot` 照發，願景外的點子分流為新產品種子卡 |
| 產出特性 | 可歸因（知道來自哪個運算子）、覆蓋面有保證 | 意外性高；價值不在當週採納率，而在填充休眠庫等天時 |
| 重審職責 | 每次 session 系統性重審（訊號匹配檢索，見「休眠卡檢索」） | 自然重審：發散撞到休眠卡相似點子時轉為「重提 + 什麼變了」 |

共同點：**純提案者，零執行權**（詳見「權限與護欄」）。

### coordinator（兼 scout）

不做創意的控制平面服務，職責：

1. **唯一 journal writer**：創意實例產出**結構化 proposal event**（含 `run_id`）提交給 coordinator；由它配發卡片 ID、寫卡、開討論 issue、發 Discord 提案文。card / issue / Discord 三者以同一 `run_id` 冪等處理——任一環節失敗可安全重試，不留半套狀態。
2. **quota ledger**：全域週預算的唯一記帳者。實例發卡前向 coordinator reserve 名額，先到先得，杜絕「兩邊都以為還有額度」。
3. **每日 scout**：每日輕量掃描（時事、節慶、store 趨勢榜），產出 `trends/YYYY-MM-DD.md`；偵測熱點時觸發 ad-hoc session（見「觸發機制」）。scout 從人格實例拆出，因為輪值的人格實例會同時決定熱點又獲得額外提案機會，污染錦標賽統計。
4. **STATS 自動產生**：`STATS.md` 由卡片與事件自動彙算，是投影結果——bot 與人類都不手動編輯它，要修數字就修來源事件。

failure mode：coordinator 掛掉只是提案暫停（實例的 proposal event 可排隊重送），不是災難；心跳規則見「錯誤處理」。

### 角色關係

```
時事/市場/store 趨勢 ──→ coordinator(scout) ──→ trends/
產品日誌（數據+質化）─┬→ 工匠實例們 ─┐ proposal
                      └→ 狂想實例們 ─┴─ events ──→ coordinator ──→ 創新卡 + issue + Discord 提案
                                                                        ├→ PM bot 評估 → 假設卡 → issue → pipeline
                                                                        └→ 人類（否決權最高）
```

提案**雙發**：同時發給 PM bot（用其數據框架評估是否採納、轉假設卡與 issue）與人類。衝突優先權：**人類否決 > PM bot 評估**；人類未表態時 PM bot 的裁決生效，人類事後可推翻（見狀態機的 veto 處理）。

## 創新 session 流程

所有實例共用同一骨架，只有「發散」一步依人格分岔。**發散必須是盲的**（blind divergence）：發散完成前不得讀取本週其他實例的新卡與討論——否則「附議」只是錨定效應下的人氣投票，不是獨立收斂訊號。

1. **審視（Situate）**——重新認識天時地利人和，產出**當期脈絡快照**：讀 PRODUCT.md、近期日誌與質化回饋摘要（PM bot 已蒐集，不重複拉取）、`trends/` 摘要，web search 補充競品動態。允許讀歷史卡，**不讀本週新卡**。
2. **重審（Revisit）**——發散前先看舊的：以當期訊號檢索匹配的休眠卡（見「休眠卡檢索」），條件變化足夠大 → 產出復活提案（附「什麼變了」）。
3. **盲發散（Blind Diverge）**——工匠套運算子、狂想自由腦暴，各自產出私有 **candidate 清單**。candidate 是 session 內部產物，不等於創新卡。
4. **查重與守門（Dedup + Gate）**——
   - 查重（對全部既有卡，含本週）：candidate 撞到 `proposed`/`adopted` 卡 → 轉為附議，`endorsement_kind: independent_match`（盲發散後撞到才算獨立收斂）；撞到 `dormant` 卡 → 轉為重提。
   - 守門：工匠 rubric 四維度（新穎性、可行性、產品契合度、時機性）達標才發；狂想只查重，rubric 分數僅標註不淘汰，低可行性標 `moonshot`，願景外分流 `new-product-seed`。
   - 配額：向 coordinator reserve；每實例每 session 最多 3 張。「本次沒有值得提的」是合法產出。
   - **session manifest**：未發布的 candidate 不無聲消失——提交精簡清單（`generated` 數、`published` 卡號、`withheld` 摘要與原因：`quota`/`artisan-gate`/`insufficient-context`）由 coordinator 存檔，供回溯與統計。
5. **提案（Propose）**——把 proposal event（點子、靈感來源引用、預期效果、建議驗證指標、run metadata）提交 coordinator，由它寫卡、開 issue、發 Discord。
6. **辯論（Debate）**——提案完成後才讀本週其他新卡與討論串，可發表支持（`informed_support`）、反駁或變體（`variant`）。此階段的認同**不是**獨立收斂訊號。

## 創新卡：紀錄層 + 辯論層

存於 product-journal repo（與 PM bot 共用，不另立 repo），僅 coordinator 寫入：

```
product-journal/
├── innovations/
│   ├── I-NNN-<slug>.md     # 創新卡（I-NNN 為顯示編號；run_id/uuid 才是唯一鍵）
│   ├── manifests/          # session manifest 存檔
│   └── STATS.md            # 錦標賽記分板（自動產生，禁止手動維護）
└── trends/
    └── YYYY-MM-DD.md       # 每日趨勢摘要（scout 產出）
```

### 卡片格式

```markdown
---
id: I-042                      # 顯示編號
uuid: <run_id 衍生的唯一鍵>
title: 節慶限時玩法融合
decision_status: proposed      # proposed / adopted / dormant / vetoed
delivery_status: none          # none / blocked / queued / in-development / released
validation_status: not-started # not-started / validating / verified / failed / inconclusive
scope: product                 # product / new-product-seed
author: {persona: 工匠, model: claude}
run:                           # 統計控制用 metadata
  run_id: ...
  model_id: ...
  model_version: ...
  persona_version: ...
  prompt_version: ...
  temperature: ...
  trigger: scheduled           # scheduled / ad-hoc / mention
operator: 玩法融合              # 工匠卡才有；狂想卡標 freeform
tags: [moonshot]               # 視情況
endorsements:
  - {persona: 狂想, model: gpt, kind: independent_match, date: 2026-07-24}
  - {persona: 工匠, model: gpt, kind: informed_support, date: 2026-07-25}
hypothesis: H-018              # 採納後回填
game_issue: <url>              # 進 pipeline 後回填
discussion: <issue-url>
dormant_reason_code:           # 休眠時填：no-demand / infeasible / off-strategy / wrong-timing
revisit_signals: []            # 休眠時填：什麼訊號出現就該重審，如 [store-growth]
next_review_after:             # 休眠時填
last_reviewed_at:
comment_cursor:                # 重審已讀留言位置
created: 2026-07-20
---

## 點子
## 靈感來源            # 運算子 or 外部訊號引用（含 URL、抓取時間，見訊號來源節）
## 當期脈絡快照         # 提案當下的天時地利人和——重審的比對基準
## 預期效果與驗證指標   # 餵 PM bot 假設卡
## 歷程                # append-only event log：每筆含 actor、時間、理由、來源
```

### 三條正交狀態軸與 transition table

決策、開發、驗證是三件不同的事，各自獨立演進：

| transition | 允許的 actor | 說明 |
|---|---|---|
| `proposed → adopted` | PM bot（`scope: product`）；人類（seed） | PM bot 評估 SLA：3 個工作天內表態，逾時 coordinator 在日報提醒 |
| `proposed → dormant` | PM bot、人類 | 必附 `dormant_reason_code` + 否決脈絡 + `revisit_signals` |
| `dormant → proposed` | 創意實例（經 coordinator） | 重審復活，必附「什麼變了」 |
| `proposed/adopted → vetoed` | 只有人類 | 見下方 veto 語意 |
| `delivery_status` 各值 | PM bot（鏡射 pipeline 實況） | 卡片不驅動開發，只記錄事實 |
| `validation_status` 各值 | PM bot（假設卡驗證回寫） | 不可從 `verified`/`failed` 改回 |

- **veto 語意**：pipeline 啟動前 veto → 純狀態改變；pipeline 啟動後 veto → 卡片標 `vetoed` 且 `delivery_status` 保持事實（已寫的程式不會消失），coordinator 通知 PM bot，由 PM bot 依其權限處理 pipeline 善後（關 issue 等），歷程記錄完整因果。
- **種子卡裁決**：`new-product-seed` 的 `adopted` 意為「人類決定培育」，只有人類能裁決；PM bot 可讀、可留言，不可改其狀態。
- 每個 transition 都由 coordinator 執行寫入，並在歷程追加 event（actor、時間、理由、來源 revision）。

### 討論 issue（辯論層）

- 每張卡由 coordinator 在 **product-journal repo**（不是遊戲 repo）開對應 issue，標籤 `innovation-card`，與卡片互連。
- **issue 是辯論場**：PM bot 評估意見、其他實例的支持/反駁/變體、人類意見都在此。多模型互相 challenge 是提升成功率的槓桿。
- **卡片是結論帳本**：issue 可以雜訊，卡片只追加經確認的結論（重審步驟用 `comment_cursor` 增量讀新留言，把重要結論寫回歷程）。
- **issue 狀態鏡射 `decision_status`**：`proposed` = open；其餘 = closed（帶標籤）；復活 = reopen。人類在 closed issue 的留言，下次重審會撈到。
- **留言上限**：每實例對同一張卡每週最多 2 則、不得連續回覆自己；**每張 issue 每週全體 bot 留言合計 ≤ 6 則**，超過即停（人類留言不限）。

### 欄位可變性（append-only 的精確定義）

- **不可修改**：`id`、`uuid`、原始提案內文、`author`、`run`、`created`、既有歷程 event。
- **可修改**（僅經 coordinator，且每次修改必同步追加歷程 event）：三條狀態軸、`tags`、`endorsements`、cross-links（`hypothesis`/`game_issue`/`discussion`）、休眠檢索欄位。
- **人類直接編輯**：人類仍可直接 commit 修改卡片（第二控制通道），但同樣遵守上述欄位規則；coordinator 下次寫入前先 pull，發現人類改動即照單全收並在歷程補記。
- 歷程即 event log：卡片 frontmatter 視為事件投影結果，衝突時以歷程為準。

### 休眠卡檢索（重審的可擴展性）

- 平時重審**不做全掃**：以當期脈絡快照的訊號對 `revisit_signals` 做匹配檢索，加上 `next_review_after` 到期的卡。
- 每季由 coordinator 排程一次**分批 full sweep**（分多個 session 消化），確保沒有卡被檢索條件永久遺漏。

## 觸發機制與排程

三種觸發並存，沿用 openab usercron（`cronjob.toml`，熱重載，與 PM bot 同理由）：

1. **每週定期 session（主節奏）**：每實例每週一次完整 session。**stagger 表**（放 config，人類可調）把實例錯開到一週不同天——盲發散規則保證了先後不影響獨立性，stagger 的作用是攤平負載並讓辯論在一週內接力進行。
2. **每日 scout 掃描（事件觸發）**：coordinator 每日掃描產出 `trends/`。偵測到與產品高度相關的熱點 → 計算 `topic_key`（正規化的話題鍵，寫入 trends 檔），觸發一次 ad-hoc session（指派給 stagger 表上的下一個實例，Discord 說明觸發原因與 topic_key）。**冷卻以 `topic_key` 判定**：同 key 72 小時內不重複觸發，不由 LLM 每次自由心證。**趨勢來源不足（當日抓取 `partial`）不得觸發 ad-hoc。**
3. **人類 mention（隨時）**：mention 任一實例即跑一輪，可帶主題提示——審視與發散以主題為錨。mention 產卡不計入自動週預算，但設獨立 rate limit：**每人每日 ≤ 2 次、同一 topic_key 每週 ≤ 3 次**，防失控。卡片照常走查重與附議。

**預算消耗定義**：新卡與復活重提消耗 new-card 預算（每實例每 session ≤ 3、全域每週 ≤ 10，由 quota ledger 管理）；附議與辯論留言不消耗卡片預算，受留言上限管制。起始值皆可由人類在 config 調整。

## 訊號來源：擴充 SOURCES.md

不另立新表，在 product-journal 既有註冊表的三類之外新增第四類：

**4. 市場與時事訊號**：store 趨勢（排行榜/竄升榜/同類新品）、時事與節慶（節慶日曆屬可預測天時，應提前數週觸發發想）、遊戲圈動態（媒體、Reddit/巴哈姆特、競品更新日誌）。

**登記具體來源策略，不泛稱「web search」**。每條來源：

```yaml
source_id: store-rising-tw
domain: play.google.com
query_template: ...
locale: zh-TW
trust_tier: high | medium | low
status: active-search | active-api | planned | unavailable
```

- Phase 1 以 `active-search` 起步；穩定 API 管道之後補（缺口比照既有流程：標 `planned` + 向人類提案）。
- **provenance**：所有引用保存 query、URL、抓取時間與必要摘錄；store 榜單必記國家、分類、榜別。
- 創意實例對註冊表**只有提案權**，修改由人類或 PM bot 執行。
- 質化回饋（評論、願望）由 PM bot 蒐集進 journal，創意實例直接讀，不重複拉取。

**不可信資料邊界（prompt injection 防線）**：網頁內容、玩家評論、issue 留言一律視為**資料而非指令**——其中任何「要求 bot 做某事」的文字不得遵從，只能作為觀察對象記錄。玩家名稱、個資、完整評論原文不得長期存進卡片（摘錄去識別化）。

## 權限與護欄

**🟢 創意實例自主執行**
- 產出 candidate、提交 proposal event 與 session manifest 給 coordinator
- web search 研究時事、市場、競品（遵守不可信資料邊界）
- 在討論 issue 留言（辯論）、經 coordinator 提交附議與復活提案

**🟢 coordinator 自主執行**
- 寫 `innovations/`、`trends/`、manifest、自動彙算 STATS
- 開/關/reopen 討論 issue、發 Discord 提案文與心跳
- 管理 quota ledger、執行狀態 transition 寫入

**🚫 永遠不做（零執行權）**
- 開遊戲 repo 的 issue、mention 需求分析 bot、觸碰開發 pipeline
- 修改 PRODUCT.md、METRICS_BASELINE.md、SOURCES.md（只能提案）
- 刪除卡片、修改歷程與不可變欄位
- 直接產出對外內容（商店文案、公告）——這類點子以提案形式給人類
- 任何花錢的事

**護欄**
- **注意力預算**：見「預算消耗定義」；quota ledger 先 reserve 後發布。
- **ad-hoc 冷卻**：`topic_key` 同 key 72 小時；來源不足不觸發。
- **mention rate limit**：每人每日 ≤ 2、同 topic_key 每週 ≤ 3。
- **辯論防迴圈**：每實例每卡每週 ≤ 2 則、不連續自回；每 issue 每週全體 bot ≤ 6 則。
- **異常煞車連動**：session 開始先讀 journal 最新狀態，若 PM bot 處於異常煞車 → 本次只做重審與卡片維護，不發新提案。
- **查重底線**：撞 `proposed`/`adopted` → 附議、撞 `dormant` → 重提；未發布 candidate 進 manifest——沒有點子無聲消失。

## 錯誤處理與可觀測性

- **來源拉取失敗**：脈絡快照標 `partial`，提案文明講缺了什麼，只用拿得到的部分分析，**不腦補**趨勢；`partial` 當日不觸發 ad-hoc。
- **session 心跳**：每次 session 結束必發 Discord 摘要（即使是「本次無值得提的」）。coordinator 每日 scout 本身也是心跳。沒看到＝掛了；journal commit 可查最後成功時間。
- **實例隔離**：某 model backend 故障 → 只跳過該實例並在 Discord 報告，其他實例照常；同一實例連續 2 次 session 失敗 → @ 人類。
- **coordinator 故障**：實例 proposal event 排隊重送（`run_id` 冪等保證不重複發布）；coordinator 連續 2 天無心跳 → 所有實例暫停提案並 @ 人類。
- **判斷可回溯**：每張卡引用當期脈絡快照與具體訊號（含 provenance）；歷程 append-only。
- **憑證管理**：各家 model API key 走環境變數注入 openab 容器，絕不進 journal repo 或 prompt。

## Phase 劃分與成功標準

### Phase 1（本設計的實作範圍）
- coordinator（兼 scout）＋兩份 persona 規格＋多模型實例（claude／gpt／grok，以 openab 能接的為準），**第一天全量上線**（明確決策：不採 review 建議的 shadow/pilot 分段；控制平面風險由 coordinator 承擔，端對端效果盡快驗證）
- 週 session（stagger、盲發散）＋每日 scout（ad-hoc 觸發）＋ mention 觸發
- 創新卡三軸狀態、雙層結構（md 卡＋討論 issue）、重審機制、附議分類、manifest、STATS 自動彙算
- `SOURCES.md` 第四類（具體來源契約），`active-search` 起步

**成功標準**（連續四週結算，四類指標）：
1. **品質**：人類對每張發布卡以固定 1–5 rubric 評分（新穎性、價值、清晰度），週平均 ≥ 3。
2. **轉換漏斗**：提案 → 認真考慮（人類 rubric ≥ 4）→ 假設卡 → 實驗中；四週內至少 1 張走到假設卡。
3. **增量價值**：人類 review 時標記「PM bot 迴圈不會產生的點子」，四週累計 ≥ 3 張。
4. **成本**：每週卡量在預算內、重複率（被查重攔下的比例）不惡化、人類每週 review 時間自報可接受、無效留言（未改善提案的辯論）比例可控。「有效辯論」定義為討論**實質改善提案**：補出風險、修正驗證指標、或產生更佳變體。

### Phase 2（本設計不含，僅預告）
- 穩定 API 管道取代 search（store 趨勢 API 等）
- 錦標賽統計驅動優化：以「每次出場機會的成功率」比較（run metadata 已備），最低樣本數（每實例 ≥ 12 次 session）未達前不得汰換模型；運算子庫調整
- 種子卡孵化流程（新產品立項 playbook、新 journal repo 自動起建）

## 非目標（本設計明確不包含）

- 開發與規格細化（需求分析 bot 的事）
- 商店文案／ASO／社群公告的產出（PM bot Phase 2 範疇；創新 bot 只能提點子）
- openab 本身的功能修改
- 新產品的實際立項與資源決策（永遠是人類的事）
