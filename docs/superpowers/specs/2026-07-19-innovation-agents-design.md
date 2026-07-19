# 產品創新 Agent（創新 bot 群）設計文件

日期：2026-07-19
狀態：設計已確認，經兩輪 review 修訂（[review v1](../reviews/2026-07-19-innovation-agents-design-review.md)、[review v2](../reviews/2026-07-19-innovation-agents-design-review-v2.md)），待實作規劃

## 背景與目標

延續 [PM bot 設計](2026-07-15-product-manager-agent-design.md)：現有遊戲產品的開發流程已 bot 化（openab + Discord），PM bot 負責數據驅動的成長迴圈（感知 → 假設卡 → 開 issue）。

本設計新增**創新 bot 群**：獨立於 PM bot 的平行 bot，專職產品創新發想——結合時事、與其他產品/玩法融合、新增/刪去/改變功能玩法，以及萌芽全新產品的種子。目標是為產品持續注入 PM bot 數據迴圈之外的創意來源，並以「天時地利人和重審」機制讓好點子在對的時機被撈回來，最大化創新命中率。

## 架構總覽：三個權限域

系統分三個互相隔離的權限域（不同 token、不同容器或至少不同工具 allowlist）：

1. **創意實例**（LLM，低權限）：發想、評估、辯論。對 journal 唯讀；所有寫入意圖以事件提交給 coordinator。
2. **scout**（LLM，低權限）：每日掃描時事/市場/store 趨勢。**只能產出 `trend_event`**——不能寫 journal、不能開 issue、不能發 Discord、不能直接觸發創意實例。它是唯一常態接觸不可信網頁的元件，因此權限最低。
3. **coordinator**（**不使用 LLM 的 deterministic service**，高權限）：唯一 automated writer。只做 schema validation、狀態轉移檢查、quota 記帳、事件持久化與外部 side effect（寫 journal、開關 issue、發 Discord）。它不解讀自然語言、不做判斷，injection 對它無效。

> 此架構取代前版「scout 兼 coordinator」：高權限元件同時讀不可信網頁會讓 prompt injection 直通寫入權，故拆分（review v2 P0-1）。

**身分規則**：事件中的 `persona` / `model` / `trigger` 由 coordinator 依已驗證的 caller identity 填入，不信任 payload 自報。

```
web / store ──→ scout（低權限）──→ trend_event ────────┐
創意實例（工匠們/狂想們）─────────→ proposal / endorsement├→ deterministic coordinator ──→ journal / GitHub issue / Discord
                                   / comment event ─────┤        │
人類 / PM bot ────────────────────→ control event ──────┘        ├→ PM bot 評估 → 假設卡 → issue → pipeline
                                                                 └→ 人類（否決權最高）
```

提案**雙發**：同時發給 PM bot（用其數據框架評估）與人類。衝突優先權：**人類否決 > PM bot 評估**；人類未表態時 PM bot 的裁決生效，人類事後可推翻（見狀態機的 veto 處理）。

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
- Phase 1 直接多模型上線（claude / gpt / grok，以 openab 實際能接的 backend 為準；接不上的實例先不建）。**此為明確決策**：多模型基準線正是要驗證的東西，成功率優先，不為模型費用做取捨；不採分段上線，風險以 kill switch 與 circuit breaker 承接（見「護欄」）。

### 兩種人格

| | 工匠（Artisan） | 狂想（Maverick） |
|---|---|---|
| 性格 | 結構引導、系統性 | 天馬行空、自由發散 |
| 方法 | 創新運算子庫：每次 session 輪換/挑選運算子（時事結合、玩法融合、加法、減法、變形等；初版清單在實作計畫中定義，之後由統計回饋優化）套用在產品功能清單上 | 無方法約束，高 temperature 自由腦暴 |
| 守門 | rubric 全維度達標才發 | **只查重**——不設可行性門檻、不設願景牴觸門檻；低可行性卡標 `moonshot` 照發，願景外的點子分流為新產品種子卡 |
| 產出特性 | 可歸因、覆蓋面有保證 | 意外性高；價值不在當週採納率，而在填充休眠庫等天時 |
| 重審職責 | 每次 session 系統性重審（訊號匹配檢索） | 自然重審：發散撞到休眠卡相似點子時轉為「重提 + 什麼變了」 |

共同點：**純提案者，零執行權**（詳見「權限與護欄」）。

## 識別鍵：三層拆分

`run_id` 不足以同時識別 session 與單張卡（一個 session 可發多張卡、也可能零產出），拆成：

```yaml
session_id:   一次 scheduled / ad-hoc / mention session（manifest 的主鍵；零產出 session 也有）
candidate_id: session 內局部序號
proposal_id:  session_id + candidate_id 衍生（或獨立 UUID）——每張卡與其所有 side effect 的冪等鍵
```

- 卡片 `uuid` = `proposal_id`；同一 proposal 的 retry 沿用原 `proposal_id`；新變體必須配新 ID。
- endorsement、comment、transition、trend、control 各自有獨立 `event_id`，引用 `proposal_id`。

## 事件契約與 delivery semantics

git repo、GitHub issue、Discord 是三個系統，**不存在跨系統原子交易**。語意定為：**允許中間狀態，透過 durable outbox 最終收斂**。

事件類型：`proposal | endorsement | comment | transition | trend | control`。outbox 狀態機：

```yaml
event_id: ...
event_type: proposal
status: received | validated | reserved | card-written | issue-created | discord-sent | completed | failed
attempts: 0
next_retry_at: ...
external_refs:            # 每完成一個 side effect 立即 checkpoint
  card_path: ...
  issue_url: ...
  discord_message_id: ...
last_error: ...
```

規則：

- 事件在回覆 accepted 前必須 durable persist（inbox）；提交者收到 accepted 即可視為交付，coordinator 負責後續收斂。
- 每完成一個 side effect 立即 checkpoint external ID；retry 前先以 `proposal_id` 查既有 card / issue / message reference，再決定是否重送（防 Discord 重複發文）。
- quota reservation 有 TTL（24 小時）；event `failed`、被拒或逾時即釋放額度。
- coordinator 每次啟動先跑 **reconciliation**：掃描未完成事件、比對 external refs、修復或續傳。
- 同一事件重試超過門檻（5 次）→ dead-letter：停止重試、@ 人類，不得無限重試洗版。
- 具體 transport 技術（檔案佇列/HTTP/GitHub）留給實作計畫，但必須實現上述契約。

## 創新 session 流程

所有實例共用同一骨架，只有「發散」一步依人格分岔。**發散必須是盲的**，且盲的程度以 **exposure set** 機械式記錄，不靠自律：

1. **審視（Situate）**——產出**當期脈絡快照**：讀 PRODUCT.md、近期日誌與質化回饋摘要、`trends/` 摘要，web search 補充競品動態（遵守不可信資料邊界）。**不讀任何 `proposed`/`adopted` 卡內文**（含歷史卡）。
2. **重審（Revisit）**——以當期訊號檢索匹配的休眠卡 + `next_review_after` 到期卡；命中的 dormant 卡進入 exposure set；條件變化足夠大 → 產出復活提案（附「什麼變了」）。
3. **盲發散（Blind Diverge）**——工匠套運算子、狂想自由腦暴，產出私有 **candidate 清單**。脈絡快照保存 `exposed_card_ids`（本 session 發散前實際看過的卡）。
4. **查重與守門（Dedup + Gate）**——發散完成後才讀既有卡比對：
   - candidate 撞到 `proposed`/`adopted` 卡：目標卡 **不在** exposure set → 附議 `independent_match`（真正的獨立收斂）；**在** exposure set → 只能標 `informed_support` 或 `variant`。
   - 撞到 `dormant` 卡 → 轉為重提。
   - 守門：工匠 rubric 四維度（新穎性、可行性、產品契合度、時機性）達標才發；狂想只查重，rubric 分數僅標註不淘汰，低可行性標 `moonshot`，願景外分流 `new-product-seed`。
   - 向 coordinator reserve 配額（見「quota 設計」）。
5. **提案（Propose）**——提交 proposal event（點子、靈感來源引用、預期效果、建議驗證指標、run metadata、exposure evidence）；同時提交 **session manifest**（含零產出與被攔截的 candidate，見下）。
6. **辯論（Debate）**——提案完成後才讀本週其他新卡與討論，透過 comment / endorsement event 發表支持（`informed_support`）、反駁或變體（`variant`）。此階段的認同不是獨立收斂訊號。

**session manifest**（所有 session 必交，含零產出；statistics 的分母來源）：

```yaml
session_id: ...
persona_version: ...
model_id: ...
model_version: ...
prompt_version: ...
trigger: scheduled | ad-hoc | mention
started_at: ...
completed_at: ...
status: completed | partial | failed
generated_count: 12
gate_passed_count: 4
published: [I-042, I-043]
quota_offered: 3
quota_used: 2
quota_denied_count: 1
withheld:
  - summary: ...
    reason: quota | artisan-gate | insufficient-context
failure_reason: ...
```

## 創新卡：紀錄層 + 辯論層

存於 product-journal repo（與 PM bot 共用），僅 coordinator 寫入：

```
product-journal/
├── innovations/
│   ├── I-NNN-<slug>.md     # 創新卡（I-NNN 為顯示編號；uuid=proposal_id 才是唯一鍵）
│   ├── manifests/          # session manifest（以 session_id 為主鍵）
│   ├── events/             # durable inbox/outbox 事件紀錄
│   └── STATS.md            # 自動彙算的投影，bot 與人類都不手動編輯
└── trends/
    └── YYYY-MM-DD.md       # scout trend_event 經 coordinator 驗證後持久化
```

### 卡片格式

```markdown
---
id: I-042                      # 顯示編號
uuid: <proposal_id>
title: 節慶限時玩法融合
decision_status: proposed      # proposed / adopted / dormant / vetoed
delivery_status: none          # none / blocked / queued / in-development / released
validation_status: not-started # not-started / validating / verified / failed / inconclusive
blocked_reason:                # delivery=blocked 時必填：instrumentation / pipeline-capacity / human-decision
scope: product                 # product / new-product-seed
author: {persona: 工匠, model: claude}   # coordinator 依 caller identity 填入
run:
  session_id: ...
  candidate_id: ...
  model_id: ...
  model_version: ...
  persona_version: ...
  prompt_version: ...
  temperature: ...
  trigger: scheduled
operator: 玩法融合              # 工匠卡才有；狂想卡標 freeform
tags: [moonshot]
endorsements:
  - {persona: 狂想, model: gpt, kind: independent_match,
     session_id: ..., exposure_evidence: "I-042 不在該 session exposure set", date: 2026-07-24}
  - {persona: 工匠, model: gpt, kind: informed_support, session_id: ..., date: 2026-07-25}
hypothesis: H-018              # 採納後回填
game_issue: <url>
discussion: <issue-url>
dormant_reason_code:           # no-demand / infeasible / off-strategy / wrong-timing
revisit_signals: []
next_review_after:
last_reviewed_at:
comment_cursor:
created: 2026-07-20
---

## 點子
## 靈感來源            # 含 URL、抓取時間（provenance）
## 當期脈絡快照         # 含 exposed_card_ids
## 預期效果與驗證指標
## 歷程                # append-only event log：actor、時間、理由、來源（人類直改則引用 commit SHA + author）
```

### 三軸完整 transition graph

coordinator 對非法 transition **fail closed**（拒絕事件並記錄）。

**decision_status**（裁決軸）：

```
proposed ──→ adopted        # PM bot（product）／人類（seed）；SLA：3 個工作天內表態，逾時 coordinator 日報提醒
proposed ──→ dormant        # PM bot、人類；必附 dormant_reason_code + 脈絡 + revisit_signals
adopted  ──→ dormant        # 僅限 pipeline 啟動前（delivery=none/blocked）反悔；PM bot、人類
dormant  ──→ proposed       # 重審復活（創意實例提案、coordinator 執行）；必附「什麼變了」
proposed/adopted ──→ vetoed # 只有人類
vetoed   ──→ proposed       # 只有人類（撤銷否決）
```

- **veto 語意**：pipeline 啟動前 veto → 純狀態改變；啟動後 veto → decision 標 `vetoed`、delivery 保持事實，coordinator 通知 PM bot 依其權限善後（關 issue 等）；**已 `released` 後 veto 僅記錄決策，不暗示任何自動 rollback 或下架**。
- **種子卡**：`new-product-seed` 的 adopted 意為「人類決定培育」，只有人類能裁決；PM bot 可讀、可留言，不可改其狀態。

**delivery_status**（交付軸，由 PM bot 鏡射 pipeline 事實，卡片不驅動開發）：

```
none ──→ queued | blocked
blocked ⇄ queued            # blocked 必附 blocked_reason
queued ──→ in-development
in-development ──→ released # released 為終態
in-development ──→ blocked  # 開發中止（附 reason）
```

**validation_status**（驗證軸，由 PM bot 假設卡驗證回寫）：

```
not-started ──→ validating ──→ verified | failed | inconclusive   # 三者皆終態
```

重新實驗＝建立**新的假設卡**（歷程記新 hypothesis 連結），原終態不改——實驗紀錄不可改寫。

### 討論 issue（辯論層）

- 每張卡由 coordinator 在 **product-journal repo** 開對應 issue，標籤 `innovation-card`，與卡片互連。
- **issue 是辯論場**：PM bot 評估意見、實例的支持/反駁/變體、人類意見都在此。實例留言一律走 comment event 由 coordinator 代發——留言上限因此是機械強制，不是自律。
- **卡片是結論帳本**：重審用 `comment_cursor` 增量讀新留言，把重要結論寫回歷程。
- **issue 狀態鏡射 `decision_status`**：`proposed` = open；其餘 = closed（帶標籤）；復活 = reopen。
- **留言上限**：每實例每卡每週 ≤ 2 則、不連續自回；每 issue 每週全體 bot ≤ 6 則（人類不限）。

### 欄位可變性與人類直改（唯一 automated writer + CI 保護）

- **不可修改**：`id`、`uuid`、原始提案內文、`author`、`run`、`created`、既有歷程 event。
- **可修改**（僅經 coordinator，每次必追加歷程 event）：三條狀態軸、`tags`、`endorsements`、cross-links、休眠檢索欄位。
- **人類直改**：保留（第二控制通道），但 coordinator 的定位是「唯一 **automated** writer」，人類 commit 由 **journal repo CI** 把關：驗證不可變欄位未被動、transition 合法、歷程僅追加；**違規 commit 阻擋**（若已進 main，coordinator reconciliation 偵測後將卡片標 `quarantined` 並 @ 人類，不照單全收）。合法直改由 coordinator 補記歷程，引用 commit SHA 與 author，不自行推測理由。

### 休眠卡檢索

- 平時重審不全掃：以當期訊號對 `revisit_signals` 匹配 + `next_review_after` 到期。
- 每季由 coordinator 排程分批 full sweep，確保沒有卡被檢索條件永久遺漏。

## 觸發機制與排程

沿用 openab usercron（`cronjob.toml`，熱重載）：

1. **每週定期 session**：每實例每週一次。**stagger 表**（config，人類可調）錯開負載；**stagger 順序每週輪換**，避免固定同批實例先跑（quota 公平性）。
2. **每日 scout 掃描**：scout 產出 `trend_event`（來源引用、trust tier、provenance、`topic_key`、內容長度受限）；coordinator 驗證必填欄位與來源數（≥ 2 個獨立來源）後持久化到 `trends/` 並決定是否建立 ad-hoc trigger job（指派給輪換表下一實例）。**冷卻以 `topic_key` 判定**：同 key 72 小時內不重複觸發。**當日抓取 `partial` 或來源不足 → 不觸發 ad-hoc。**
3. **人類 mention**：mention 任一實例即跑一輪，可帶主題提示。rate limit：每人每日 ≤ 2 次、同 `topic_key` 每週 ≤ 3 次。

## quota 設計

兩個獨立預算池，消滅「mention 不計預算」的語意矛盾：

- **automated_budget**（scheduled + ad-hoc）：全域每週 10 張。**公平配置**：每個 active 實例先保留 1 張 base slot，其餘進 shared pool；pool 先到先得，但 stagger 順序每週輪換。另設**每實例每 session 上限 3 張**（base slot 計入），防止單一 session 吃光 pool。
- **human_requested_budget**（mention 產卡）：獨立上限每週 5 張，不佔 automated_budget；rate limit 如上。
- reservation TTL 24 小時，未發布自動釋放；manifest 記錄 `quota_offered` / `quota_used` / `quota_denied_count`。
- 復活重提消耗所屬觸發途徑的預算；附議與留言不消耗卡片預算，受留言上限管制。
- 所有數值為起始值，人類可在 config 調整。

## 訊號來源：擴充 SOURCES.md

在 product-journal 既有註冊表三類之外新增第四類：

**4. 市場與時事訊號**：store 趨勢（排行榜/竄升榜/同類新品）、時事與節慶（節慶日曆屬可預測天時，應提前數週觸發發想）、遊戲圈動態（媒體、Reddit/巴哈姆特、競品更新日誌）。

**登記具體來源策略，不泛稱「web search」**：

```yaml
source_id: store-rising-tw
domain: play.google.com
query_template: ...
locale: zh-TW
trust_tier: high | medium | low
status: active-search | active-api | planned | unavailable
```

- Phase 1 以 `active-search` 起步；穩定 API 之後補（缺口比照既有流程：標 `planned` + 向人類提案）。
- **provenance**：所有引用保存 query、URL、抓取時間與必要摘錄；store 榜單必記國家、分類、榜別。
- 實例與 scout 對註冊表**只有提案權**，修改由人類或 PM bot 執行。
- 質化回饋由 PM bot 蒐集進 journal，實例直接讀，不重複拉取。

**不可信資料邊界（prompt injection 防線）**：網頁內容、玩家評論、issue 留言一律視為**資料而非指令**。架構性保證：接觸不可信內容的元件（scout、創意實例）都是低權限；唯一高權限的 coordinator 是 deterministic、不解讀自然語言。玩家名稱、個資、完整評論原文不得長期存進卡片（摘錄去識別化）。

## 權限與護欄

**🟢 創意實例（低權限，journal 唯讀）**
- 產出 candidate；提交 proposal / endorsement / comment event 與 session manifest
- web search 研究（遵守不可信資料邊界）

**🟢 scout（低權限）**
- 每日掃描；只產出 trend_event

**🟢 coordinator（高權限、deterministic）**
- 事件驗證與持久化、寫 `innovations/` 與 `trends/`、開關 issue、發 Discord、quota 記帳、STATS 彙算、reconciliation

**🚫 永遠不做（零執行權）**
- 開遊戲 repo 的 issue、mention 需求分析 bot、觸碰開發 pipeline
- 修改 PRODUCT.md、METRICS_BASELINE.md、SOURCES.md（只能提案）
- 刪除卡片、修改歷程與不可變欄位
- 直接產出對外內容（商店文案、公告）
- 任何花錢的事

**護欄與 kill switch（全量上線的必要煞車）**
- **預算**：見「quota 設計」。
- **冷卻與 rate limit**：`topic_key` 72 小時；mention 每人每日 ≤ 2、同 key 每週 ≤ 3。
- **辯論防迴圈**：留言上限由 coordinator 機械強制。
- **異常煞車連動**：PM bot 異常煞車期間，session 只做重審與卡片維護，不發新提案。
- **circuit breaker**：GitHub issue 建立 ≤ 10/小時、Discord 訊息 ≤ 20/小時，超過即斷路並 @ 人類；事件佇列 backlog ≥ 50 告警。
- **fail closed**：schema validation 或 transition 檢查連續 5 次失敗 → coordinator 自動進 `read-only/reconcile` 模式。
- **kill switch**：全域 `pause_writes` 與每實例 `enabled` 開關（config 熱重載）；人類可用單一 Discord 指令或 config commit 立即停止所有 side effect。

## 錯誤處理與可觀測性

- **來源拉取失敗**：脈絡快照標 `partial`，明講缺什麼，只用拿得到的部分，不腦補；`partial` 當日不觸發 ad-hoc。
- **心跳**：每 session 結束必發 Discord 摘要（含「本次無值得提的」）；scout 每日 trend 摘要即其心跳；coordinator 心跳為每日事件處理統計。任一元件連續 2 天無心跳 → @ 人類（coordinator 無心跳時實例暫停提案，事件在 inbox 排隊）。
- **實例隔離**：某 model backend 故障只跳過該實例；同一實例連續 2 次 session 失敗 → @ 人類。
- **coordinator 恢復**：啟動即 reconciliation（掃未完成事件、比對 external refs、續傳或修復）；dead-letter 事件 @ 人類。
- **判斷可回溯**：每張卡引用脈絡快照與 provenance；歷程 append-only。
- **憑證管理**：各家 model API key 走環境變數注入 openab 容器，絕不進 journal repo 或 prompt。

## Phase 劃分與成功標準

### Phase 1（本設計的實作範圍）
- coordinator（deterministic）＋ scout ＋兩份 persona 規格＋多模型實例（claude／gpt／grok，以 openab 能接的為準），**第一天全量上線**（明確決策：不採分段；煞車靠 kill switch 與 circuit breaker）
- 週 session（stagger 輪換、盲發散 + exposure set）＋每日 scout（ad-hoc 觸發）＋ mention
- 事件契約（inbox/outbox、reconciliation）、創新卡三軸狀態機、雙層結構、重審、附議分類、manifest、STATS 自動彙算
- `SOURCES.md` 第四類（具體來源契約），`active-search` 起步

**成功標準**（連續四週結算；評分覆蓋率 ≥ 80% 的週才有效，無效週順延）：

1. **品質**：人類對每張發布卡以固定 rubric 評 1–5（錨點：1 = 離題或不可用；2 = 平庸、可預期；3 = 合格、有潛力；4 = 值得認真考慮，應進入評估；5 = 極具價值、想立刻做）。三維度（新穎性、價值、清晰度）等權平均。**門檻：週平均 ≥ 3。**
2. **轉換漏斗**：提案 → 認真考慮（rubric ≥ 4）→ 假設卡 → 實驗中。**門檻：四週內 rubric ≥ 4 的卡 ≥ 4 張，且至少 1 張走到假設卡。**
3. **增量價值**（標示為**主觀指標**，不單獨用於模型汰換）：人類 review 時標記「PM bot 迴圈不會產生的點子」。**門檻：四週累計 ≥ 3 張。**
4. **成本**：
   - 人類每週 review 時間 ≤ 60 分鐘（自報）。
   - 無效 bot 留言比例 ≤ 30%（人類抽樣判定；「有效」= 補出風險、修正驗證指標、或產生更佳變體）。
   - duplicate rate = 被查重攔下的 candidate 數 ÷ generated 總數；第一週值為 baseline，其後各週 ≤ baseline × 1.5。

**未達標處置（機械式，不留主觀討論空間）**：
- 品質連續 2 週未達 → 調整表現最差 persona 的 prompt/persona 版本（版本號進 run metadata，統計可分段）。
- 單一實例在樣本足夠（≥ 8 次 session）下持續墊底 → 停用該實例（config `enabled: false`）。
- 成本任一項連續 2 週超標 → 降低預算或全域 `pause_writes`。
- 四週結束未全數達標 → 延長觀察兩週；仍未達 → 回 brainstorming 檢討設計，不進 Phase 2。

### Phase 2（本設計不含，僅預告）
- 穩定 API 管道取代 search（store 趨勢 API 等）
- 錦標賽統計驅動優化：分母採 manifest 的出場機會（含零產出、failed、quota_denied——無 survivorship bias）；最低樣本數（每實例 ≥ 12 次 session）未達前不得汰換模型；運算子庫調整
- 種子卡孵化流程（新產品立項 playbook、新 journal repo 自動起建）

## 非目標（本設計明確不包含）

- 開發與規格細化（需求分析 bot 的事）
- 商店文案／ASO／社群公告的產出（PM bot Phase 2 範疇；創新 bot 只能提點子）
- openab 本身的功能修改
- 新產品的實際立項與資源決策（永遠是人類的事）
- 事件 transport 的具體技術選型（實作計畫決定，但必須滿足本文的事件契約）
