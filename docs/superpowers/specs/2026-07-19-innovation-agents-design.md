# 產品創新 Agent（創新 bot 群）設計文件

日期：2026-07-19
狀態：設計已確認，待實作規劃

## 背景與目標

延續 [PM bot 設計](2026-07-15-product-manager-agent-design.md)：現有遊戲產品的開發流程已 bot 化（openab + Discord），PM bot 負責數據驅動的成長迴圈（感知 → 假設卡 → 開 issue）。

本設計新增**創新 bot 群**：獨立於 PM bot 的平行 bot，專職產品創新發想——結合時事、與其他產品/玩法融合、新增/刪去/改變功能玩法，以及萌芽全新產品的種子。目標是為產品持續注入 PM bot 數據迴圈之外的創意來源，並以「天時地利人和重審」機制讓好點子在對的時機被撈回來，最大化創新命中率。

## 核心概念：人格 × 模型 = bot 實例

「人格」與「bot 實例」解耦：

```
人格規格（persona spec）×  模型（model）＝ bot 實例
     工匠規格             claude          工匠-claude
     工匠規格             gpt             工匠-gpt
     狂想規格             claude          狂想-claude
     狂想規格             gpt             狂想-gpt
     狂想規格             grok            狂想-grok
```

- **人格規格**是可複用的定義檔：方法論、守門規則、配額、session 流程。
- **bot 實例**＝人格規格 + 指定 model backend 的 openab 部署。
- Phase 1 直接多模型上線（claude / gpt / grok，以 openab 實際能接的 backend 為準；接不上的實例先不建）。多模型從第一天累積錦標賽統計與附議訊號，成功率優先，不為模型費用做取捨。

### 兩種人格

| | 工匠（Artisan） | 狂想（Maverick） |
|---|---|---|
| 性格 | 結構引導、系統性 | 天馬行空、自由發散 |
| 方法 | 創新運算子庫：每次 session 輪換/挑選運算子（時事結合、玩法融合、加法、減法、變形等；初版清單在實作計畫中定義，之後由 STATS.md 統計回饋優化）套用在產品功能清單上 | 無方法約束，高 temperature 自由腦暴 |
| 守門 | rubric 全維度達標才發卡 | **只查重**——不設可行性門檻、不設願景牴觸門檻；低可行性卡標 `moonshot` 照發，願景外的點子分流為新產品種子卡 |
| 產出特性 | 可歸因（知道來自哪個運算子）、覆蓋面有保證 | 意外性高；價值不在當週採納率，而在填充休眠庫等天時 |
| 重審職責 | 每次 session 系統性掃描休眠卡 | 自然重審：發散撞到休眠卡相似點子時轉為「重提 + 什麼變了」 |

共同點：**純提案者，零執行權**（詳見「權限與護欄」）。

### 角色關係

```
時事/市場/store 趨勢 ─┐
產品日誌（數據+質化）─┼→ 工匠實例們 ─┐
                      └→ 狂想實例們 ─┴→ 創新卡 + Discord 提案 ─→ PM bot 評估 → 假設卡 → issue → pipeline
                                                          └─→ 人類（否決權最高）
```

提案**雙發**：同時發給 PM bot（用其數據框架評估是否採納、轉假設卡與 issue）與人類。衝突優先權：**人類否決 > PM bot 評估**；人類未表態時 PM bot 的採納/否決即生效，人類事後可推翻（卡片狀態可改）。

## 創新 session 流程

所有實例共用同一骨架，只有「發散」一步依人格分岔：

1. **審視（Situate）**——重新認識天時地利人和，產出**當期脈絡快照**：
   - 人和（產品/用戶）：讀 product-journal 的 PRODUCT.md、近期日誌與快照、質化回饋摘要（PM bot 已蒐集，不重複拉取）
   - 天時（時事/趨勢）：當日 `trends/` 摘要 + web search 補充（時事、節慶、store 竄升榜）
   - 地利（市場/競品）：競品近期動態、同類遊戲新玩法
2. **重審（Revisit）**——發散前先看舊的：掃 `innovations/` 休眠卡與討論串新留言，對照當期脈絡快照；條件變化足夠大（例：當時否決理由是「市場無此需求」，現在 store 出現同類竄升產品）→ 復活重提，卡片追加「什麼變了」。工匠系統性全掃；狂想在撞題時觸發。
3. **發散（Diverge）**——工匠套運算子；狂想自由腦暴。
4. **守門（Gate）**——
   - 工匠：rubric 四維度評分（新穎性、可行性、產品契合度、時機性）達標才發。
   - 狂想：**只查重**。rubric 分數僅作為標註附在卡上（供 PM bot 參考與長期統計），不作淘汰。低可行性標 `moonshot`；與現有產品願景無關的分流為 `new-product-seed`。
   - 查重規則（全人格共用）：撞到 `proposed`/`adopted` 卡（真重複）→ 附議 +1；撞到 `dormant` 卡（相似但脈絡可能已變）→ 重提。**任何路徑都不會無聲丟棄點子。**
   - 配額：每實例每 session 最多發 3 張新卡；「本次沒有值得提的」是合法產出（狂想不必湊滿，也不必自我審查可行性）。
5. **提案（Propose）**——寫創新卡進 `innovations/`、開對應討論 issue、Discord 發提案文（@ PM bot + 人類）：一段話講點子、靈感來源（運算子或外部訊號引用）、預期效果、建議驗證指標（餵 PM bot 假設卡機制）。

## 創新卡：紀錄層 + 辯論層

存於 product-journal repo（與 PM bot 共用，不另立 repo）：

```
product-journal/
├── innovations/
│   ├── I-NNN-<slug>.md     # 創新卡
│   └── STATS.md            # 錦標賽記分板（persona × model × operator 統計）
└── trends/
    └── YYYY-MM-DD.md       # 每日趨勢摘要（輪值掃描產出）
```

### 卡片格式

```markdown
---
id: I-042
title: 節慶限時玩法融合
status: proposed              # proposed / adopted / dormant
scope: product                # product / new-product-seed
author: {persona: 工匠, model: claude}
operator: 玩法融合             # 工匠卡才有；狂想卡標 freeform
tags: [moonshot]              # 視情況
endorsements:                 # 附議：其他實例獨立想到同點子
  - {persona: 狂想, model: gpt, date: 2026-07-24}
discussion: <issue-url>       # 對應討論 issue
created: 2026-07-20
---

## 點子
## 靈感來源            # 運算子 or 外部訊號引用（時事連結、store 趨勢、玩家評論引文）
## 當期脈絡快照         # 提案當下的天時地利人和——重審的比對基準
## 預期效果與驗證指標   # 餵 PM bot 假設卡
## 歷程                # 只能追加：提案／否決＋脈絡／附議／復活理由／驗證結果
```

### 狀態機

```
proposed ──→ adopted（PM bot 採納 → 轉假設卡，卡上互相連結）
    │            └→ 驗證結果（verified / failed）回寫歷程
    └──→ dormant（否決或擱置——不是死刑，是休眠）
              └──→ proposed（重審復活，追加「什麼變了」）
```

### 討論 issue（辯論層）

- 每張卡建立時，提案實例在 **product-journal repo**（不是遊戲 repo）開對應 issue，標籤 `innovation-card`，與卡片互相連結。
- **issue 是辯論場**：PM bot 的評估意見以留言發表；其他 persona × model 實例可留言附議、反駁、補充變體；人類隨時加入。多模型互相 challenge 是提升成功率的槓桿。
- **卡片是結論帳本**：issue 裡可以雜訊，卡片只追加經確認的結論。每次 session 的重審步驟讀討論串新留言，把重要結論寫回卡片歷程。
- **issue 狀態鏡射卡片**：`proposed` = open；`adopted`/`dormant` = closed（帶標籤）；復活 = reopen。休眠不等於討論終結——人類在 closed issue 的留言，下次重審會撈到。

### 維護規則

- **誰寫**：創新實例寫提案與重審；PM bot 寫採納/否決與驗證回寫；人類可直接編輯任何卡（第二控制通道）。
- **永不刪除**：卡片只增不減、歷程只追加——重審機制的前提（沒有休眠庫就沒有東西可復活），也讓錦標賽統計可信。
- **否決必附脈絡**：理由 + 當時市場/產品條件，否則日後重審沒有比對基準。
- **附議權重**：附議數高＝多模型收斂訊號，PM bot 評估與重審時提高權重。
- **種子卡流向**：`new-product-seed` 只發人類，PM bot 可讀不裁決（其決策框架綁定當前產品）；一樣休眠、一樣重審。未來若立項，新產品的 journal 從種子卡起家。
- **STATS.md**：由 bot 維護，按 persona × model × operator 統計提案數、採納率、moonshot 復活數——優化運算子庫與汰換弱模型的依據。

## 觸發機制與排程

三種觸發並存，沿用 openab usercron（`cronjob.toml`，熱重載，與 PM bot 同理由）：

1. **每週定期 session（主節奏）**：每實例每週一次完整 session。**stagger 表**（放 config，人類可調）把實例錯開到一週不同天——後跑者看得到先跑者的卡與討論串，一週內形成接力式辯論而非同日互撞。
2. **每日輕量時事掃描（事件觸發）**：由**輪值實例**（輪值順序與 stagger 表一併定義在 config）每日跑輕量掃描（時事、節慶、store 趨勢榜），產出 `trends/YYYY-MM-DD.md`（同時是所有 session 審視步驟的現成輸入）。偵測到與產品高度相關的熱點 → 觸發一次 ad-hoc 完整 session（輪值實例執行，Discord 說明觸發原因）。**冷卻**：同一話題 72 小時內不重複觸發；ad-hoc 產出計入全域週預算。
3. **人類 mention（隨時）**：mention 任一實例即跑一輪，可帶主題提示（「想想聖誕節玩法」）——審視與發散以主題為錨。不受週預算限制，卡片照常走查重與附議。

## 訊號來源：擴充 SOURCES.md

不另立新表，在 product-journal 既有註冊表的三類之外新增第四類：

**4. 市場與時事訊號**：store 趨勢（排行榜/竄升榜/同類新品）、時事與節慶（節慶日曆屬可預測天時，應提前數週觸發發想）、遊戲圈動態（媒體、Reddit/巴哈姆特、競品更新日誌）。每條照既有格式登記：取得方式、更新頻率、狀態（`active`/`planned`/`unavailable`）。

- **Phase 1 全部走 web search 起步**（`active`）；穩定 API 管道之後補（缺口比照既有流程：標 `planned` + 向人類提案）。
- 創新實例對註冊表**只有提案權**，修改由人類或 PM bot 執行——避免多實例改表打架。
- 質化回饋（評論、願望）由 PM bot 蒐集進 journal，創新實例直接讀，不重複拉取。

## 權限與護欄

**🟢 自主執行**
- 寫 `innovations/` 卡片、開/留言/reopen 討論 issue、寫 `trends/` 摘要（全在 product-journal repo）
- web search 研究時事、市場、競品
- Discord 發提案、附議、參與辯論
- 重審復活休眠卡（附「什麼變了」論證）

**🚫 永遠不做（零執行權）**
- 開遊戲 repo 的 issue、mention 需求分析 bot、觸碰開發 pipeline
- 修改 PRODUCT.md、METRICS_BASELINE.md、SOURCES.md（只能提案）
- 刪除卡片、修改卡片歷程（只能追加）
- 直接產出對外內容（商店文案、公告）——這類點子以提案形式給人類
- 任何花錢的事

**護欄**
- **注意力預算**：每實例每 session ≤ 3 張新卡；全體實例全域每週 ≤ 10 張（含 ad-hoc；mention 觸發不計入）。起始值，人類可在 config 調。
- **ad-hoc 冷卻**：同一熱點 72 小時內不重複觸發。
- **辯論防迴圈**：每實例對同一張卡每週最多 2 則留言，不得連續回覆自己。
- **異常煞車連動**：session 開始先讀 journal 最新狀態，若 PM bot 處於異常煞車（崩潰率暴增、評分驟降）→ 本次只做重審與卡片維護，不發新提案——產品著火時不端創意菜。
- **查重底線**：真重複轉附議、休眠相似轉重提——不產生垃圾重複卡。

## 錯誤處理與可觀測性

- **來源拉取失敗**：脈絡快照標 `partial`，提案文明講缺了什麼，只用拿得到的部分分析，**不腦補**趨勢。
- **session 心跳**：每次 session 結束必發 Discord 摘要（即使是「本次無值得提的」）。沒看到摘要＝該實例掛了；journal commit 可查最後成功時間。
- **實例隔離**：某 model backend 故障 → 只跳過該實例並在 Discord 報告，其他實例照常（多模型天然容錯）；同一實例連續 2 次 session 失敗 → @ 人類。
- **判斷可回溯**：每張卡必須引用當期脈絡快照與具體訊號（哪則時事、哪個趨勢、哪條評論）；歷程只追加。
- **憑證管理**：各家 model API key 走環境變數注入 openab 容器，絕不進 journal repo 或 prompt。

## Phase 劃分與成功標準

### Phase 1（本設計的實作範圍）
- 兩份 persona 規格（工匠／狂想）＋多模型實例（claude／gpt／grok，以 openab 能接的為準）
- 週 session（stagger）＋每日輪值掃描（ad-hoc 觸發）＋ mention 觸發
- 創新卡雙層結構（md 卡＋討論 issue）、重審機制、附議、`STATS.md`
- `SOURCES.md` 第四類，web search 起步
- **成功標準**：連續四週，(a) 每週至少 1 張卡被人類認為「值得認真考慮」；(b) 期間至少 1 張卡被採納轉假設卡進入開發；(c) 討論串有真實辯論（不同實例間有反駁或補充，非各說各話）。

### Phase 2（本設計不含，僅預告）
- 穩定 API 管道取代 web search（store 趨勢 API 等）
- 錦標賽統計驅動優化：運算子庫調整、弱模型汰換建議
- 種子卡孵化流程（新產品立項 playbook、新 journal repo 自動起建）

## 非目標（本設計明確不包含）

- 開發與規格細化（需求分析 bot 的事）
- 商店文案／ASO／社群公告的產出（PM bot Phase 2 範疇；創新 bot 只能提點子）
- openab 本身的功能修改
- 新產品的實際立項與資源決策（永遠是人類的事）
