# 產品創新 Agent 設計 Review v2

日期：2026-07-19  
Review 對象：[產品創新 Agent（創新 bot 群）設計文件](../specs/2026-07-19-innovation-agents-design.md)  
前次 Review：[產品創新 Agent 設計 Review](2026-07-19-innovation-agents-design-review.md)  
結論：創意流程已大致成立，但控制平面仍有 3 個 P0；修正後才建議進入 implementation plan。

## 整體評價

本次修訂有實質改善，不是只補文字。以下設計已可接受：

- 創意平面與控制平面分離，創意實例不再直接寫 journal。
- 決策、交付、驗證拆成三條狀態軸。
- blind divergence、附議分類與 session manifest 解決了大部分錨定及無聲丟棄問題。
- dormant 卡改為訊號檢索並保留季度 full sweep，具備可擴展性。
- scout 不再輪值於人格實例，避免額外出場機會污染錦標賽。
- 來源契約、provenance、prompt injection 邊界、留言總上限都有明確規則。
- `STATS.md` 改為衍生投影，不再多方手動維護。
- Phase 1 成功標準已從單一採納數，擴成品質、轉換、增量價值及成本四類。

目前最大的問題已不是「創新 bot 如何發想」，而是 coordinator 是否真的能安全、可靠地充當控制平面。現稿把幾個需要機械式保證的能力寫成語意承諾，但尚未定義能實現承諾的介面與持久化模型。

## 前次 Review 處理狀態

| 前次項目 | v2 判定 | 說明 |
|---|---|---|
| 多實例併發寫入 | 部分解決 | 唯一 writer 與 quota ledger 方向正確；event transport、outbox、reservation lifecycle 尚未定義 |
| 三種狀態混用 | 大致解決 | 已拆三軸；個別 transition 仍需補完整 |
| 附議不獨立 | 部分解決 | 已有 blind divergence 與附議分類；仍缺實際 exposure 記錄 |
| 點子無聲丟棄 | 已解決 | candidate／card 分層與 manifest 足夠 |
| 休眠卡全量掃描 | 已解決 | 訊號檢索、到期檢索、季度分批 full sweep 合理 |
| 成功標準 Goodhart | 部分解決 | 已改成四類指標；部分指標仍無基準或通過門檻 |
| 錦標賽實驗控制 | 部分解決 | run metadata 與最低樣本數已補；quota 公平性與零產出 run 仍會造成偏差 |
| web search 可靠性／安全 | 部分解決 | 來源契約已補；但 privileged coordinator 同時讀不可信網頁，形成新的權限風險 |
| quota／cooldown／mention | 部分解決 | topic key、rate limit 已補；mention 預算語意矛盾，先到先得也不公平 |
| append-only 定義 | 部分解決 | 欄位規則已補；人類直改與唯一 writer／event source 仍矛盾 |

## 必須修正的 P0

### 1. P0：scout 與 privileged coordinator 不應是同一個 agent

規格將 coordinator 定義為 journal 唯一寫入者，能寫卡、改狀態、開關 issue、發 Discord、管理 quota；同時又讓它直接執行 web search、讀取不可信頁面並判斷是否觸發 ad-hoc session（原規格 L46–55、L183、L210、L219–222）。

這破壞了設計原本想建立的權限隔離。即使 prompt 明訂「資料不是指令」，只要同一個 LLM execution context 同時接觸不可信內容與高權限工具，prompt injection 或模型誤判仍能直接轉化成 repo、GitHub 與 Discord 寫入。

建議調整：

- `coordinator` 改為低自由度、最好不使用 LLM 的 deterministic service，只做 schema validation、狀態轉移、quota、持久化與外部 side effect。
- `scout` 是獨立的低權限 agent，只能產出 `trend_event`，不能寫 journal、開 issue、發 Discord 或直接觸發創意實例。
- coordinator 驗證 `trend_event` 必填來源數、trust tier、provenance、topic key 與內容長度後，才決定是否建立 trigger job。
- scout 與 coordinator 使用不同 token、不同容器或至少不同工具 allowlist。
- 創意實例提交的 persona、model、trigger 身分由 coordinator 根據已驗證 caller identity 填入，不信任 payload 自報。

建議架構：

```text
web / store ─→ low-privilege scout ─→ validated trend_event ─┐
creative instances ────────────────→ proposal_event ────────┼→ deterministic coordinator
human / PM bot ────────────────────→ control_event ─────────┘        │
                                                                      └→ journal / GitHub / Discord
```

### 2. P0：proposal event 的 transport、持久化與 outbox 尚未定義

規格多次使用「提交」、「排隊重送」、「reserve」、「安全重試」等語意（原規格 L50–55、L79–81、L244），但沒有定義：

- event 透過什麼提交：Discord、HTTP、檔案、GitHub issue，還是另一個 queue。
- event 在 coordinator 收到前由誰持久化。
- 如何認證來源、排序、acknowledge、retry 與 dead-letter。
- coordinator crash 後如何知道 GitHub issue 或 Discord message 是否已經成功送出。
- quota reservation 何時 commit、何時 release、多久 expiry。

Git repo、GitHub issue 與 Discord 是三個不同系統，不可能靠同一個 `run_id` 達成真正的原子交易。「不留半套狀態」應改成「允許中間狀態，透過 durable outbox 最終收斂」。尤其 Discord 若送出成功、但尚未記錄 message ID 就 crash，直接 retry 仍可能重複發文。

建議定義一個明確的 event/outbox 狀態機：

```yaml
event_id: <proposal_id>
event_type: proposal | endorsement | transition | trend | control
status: received | validated | reserved | card-written | issue-created | discord-sent | completed | failed
attempts: 0
next_retry_at: ...
external_refs:
  card_path: ...
  issue_url: ...
  discord_message_id: ...
last_error: ...
```

必要規則：

- event 在回覆 accepted 前必須 durable persist。
- 每完成一個 side effect 就立即 checkpoint external ID。
- retry 前先以 `proposal_id` 搜尋既有 card／issue／message reference，再決定是否重送。
- reservation 必須有 TTL；event failed、被拒或逾時時釋放額度。
- coordinator 每次啟動先跑 reconciliation，修復未完成 event。
- dead-letter 超過門檻時停止該 event，通知人類，不得無限重試洗版。

這個 transport 可以留到 implementation plan 決定具體技術，但設計文件必須先確定契約與 delivery semantics，否則 coordinator 架構尚未閉合。

### 3. P0：`run_id` 不能直接作為每張卡的唯一鍵

一個 session 最多可發布三張卡，但卡片格式寫成 `uuid: <run_id 衍生的唯一鍵>`（原規格 L79、L102–117）。若 `run_id` 代表一次 session，同一 run 的多張卡會得到相同或語意不清的 UUID；若 `run_id` 代表單張 proposal，又無法作為 session manifest 與零產出 run 的識別鍵。

建議拆成三層：

```yaml
session_id: <一次 scheduled/ad-hoc/mention session>
candidate_id: <session 內局部 ID>
proposal_id: <session_id + candidate_id，或獨立 UUID>
```

- session manifest 以 `session_id` 為主鍵。
- 每張卡的 `uuid` 與所有發布 side effect 以 `proposal_id` 為冪等鍵。
- endorsement、variant、transition 各自有獨立 `event_id`，並引用 `proposal_id`。
- 同一 proposal 的 retry 沿用原 `proposal_id`，新的變體不可重用舊 ID。

## 應在實作規劃前補完的 P1

### 4. P1：first-come-first-served quota 會污染錦標賽

全域每週最多十張、每個 session 最多三張，但 reservation 採先到先得；session 又依 stagger 先後執行（原規格 L51、L182、L186）。較早執行的實例可能先吃掉大部分名額，較晚實例即使產生高品質 candidate 也只能 withheld，這會把排程順序誤當成模型能力。

此外規格同時說 mention 產卡不計自動週預算，又說所有新卡與復活都消耗全域 new-card 預算（L184–186），語意互相衝突。

建議調整：

- 明確拆成 `automated_budget` 與 `human_requested_budget`，說明 mention 是否有獨立卡片上限。
- 自動週預算採公平配置，例如每個 active instance 先保留一個 base slot，其餘進 shared pool。
- reservation 設 TTL 並在未發布時釋放。
- manifest 記錄 `quota_offered`、`quota_used`、`quota_denied`，STATS 用實際出場機會作分母。
- 如果仍採先到先得，至少每週輪換 stagger 順序，不可固定同一批實例先跑。

### 5. P1：blind divergence 仍缺 exposure-level 證據

規格只禁止讀「本週新卡」，但 Situate 允許讀歷史卡，Dedup 又把任何撞到 proposed／adopted 的 candidate 標成 `independent_match`（原規格 L71–78）。若實例在發散前看過一張兩週前的 proposed 卡，再產生相似 candidate，它仍會被錯記為獨立收斂。

建議：

- blind divergence 前不要讀任何 `proposed`／`adopted` 卡內文；休眠檢索只暴露被檢索命中的 dormant 卡。
- context snapshot 保存 `exposed_card_ids` 或可驗證的 exposure set。
- 只有目標 card 不在 exposure set 時，才可標 `independent_match`；否則只能是 `informed_support` 或 `variant`。
- endorsement event 應保存 `session_id`、model/persona version 與 exposure evidence，不只記 persona、model、date。

### 6. P1：「唯一 writer」與「人類直接 commit、照單全收」互相矛盾

規格一方面說 coordinator 是唯一 writer，另一方面允許人類直接修改卡片，並要求 coordinator 下次 pull 後「照單全收」及補記歷程（原規格 L16–17、L166–171）。這會帶來兩個問題：

- coordinator 已經不是唯一 writer，event log 也不再是完整 source of truth。
- 如果人類誤改不可變欄位或刪掉歷程，coordinator 的「照單全收」與不可變規則衝突。

建議二選一：

1. 人類也提交 `control_event`，由 coordinator 寫入；這最符合唯一 writer。
2. 保留直接 commit，但改成「唯一 automated writer」，並以 CI 驗證不可變欄位、狀態 transition 與 append-only history；違規 commit 阻擋或 quarantine，不得照單全收。

若採第二種，coordinator 補記時應引用 human commit SHA 與 author，不能自行推測修改理由。

### 7. P1：三軸狀態已拆開，但 transition 還不是完整狀態機

目前只列出主要 decision transition，`delivery_status` 與 `validation_status` 則概括為「各值」（原規格 L141–156）。仍需回答：

- `delivery_status` 是否只能 `none → blocked/queued → in-development → released`，可否回退。
- `blocked` 是卡在 instrumentation、pipeline capacity，還是人工決策；應有 `blocked_reason`。
- `validation_status` 的 `failed`／`inconclusive` 是否終態，重新實驗是否建立新 hypothesis。
- PM bot 採納後、pipeline 前反悔時，能否 `adopted → dormant`。
- `vetoed` 能否由人類撤銷；若能，回到哪一狀態。
- 已 released 後 veto 只能記錄決策，不得暗示 PM bot 可自動 rollback 或下架。

建議為三軸各畫一張合法 transition graph，coordinator 對非法 transition fail closed。

### 8. P1：Phase 1 成功標準仍有無法客觀驗收的項目

新版四類指標方向正確，但「重複率不惡化」、「review 時間可接受」、「無效留言比例可控」仍沒有 baseline 或通過門檻；1–5 rubric 也沒有評分錨點（原規格 L256–260）。因此四週後仍可能無法一致判定通過或失敗。

建議在上線前固定：

- rubric 每一分的文字錨點、各維度權重及缺評分的處理方式。
- 至少多少比例的發布卡必須完成人類評分。
- 人類每週 review 時間上限。
- 無效 bot 留言比例上限。
- duplicate rate 的公式，以及「不惡化」所比較的 baseline；第一週沒有 baseline 時如何處理。
- 未達成功標準時的動作：調 prompt、停用單一實例、全域 pause，或延長觀察；不得只留下主觀討論。

「PM bot 不會產生的點子」本質上是人類反事實判斷，可以保留，但應標示為主觀指標，不宜單獨用於模型汰換。

## 建議補強的 P2

### 9. P2：統計事件必須涵蓋零產出、失敗與 quota denial

`STATS.md` 雖改為自動產生，但規格未展示來源 event 的存放位置與完整 schema。若只從已發布卡統計，會漏掉零產出 session、backend failure、被 gate 淘汰及 quota denied，形成 survivorship bias。

建議所有 session 都保存 manifest，至少包含：

```yaml
session_id:
persona_version:
model_id:
model_version:
prompt_version:
trigger:
started_at:
completed_at:
status: completed | partial | failed
generated_count:
gate_passed_count:
published_count:
quota_denied_count:
failure_reason:
```

STATS 的分母是 eligible session／candidate opportunity，不是發布卡數。

### 10. P2：全量首日上線仍需要立即可用的 operational kill switch

設計已明確否決 shadow／pilot 分段上線，這是可以接受的產品決策；本 review 不再要求改變 rollout 方式。但 coordinator 集中處理風險，只能降低資料競爭，不能避免錯誤提案、Discord 洗版或錯誤狀態轉移。

建議保留全量上線，同時補上：

- 全域 `pause_writes` 與每實例 `enabled` 開關，可熱重載。
- coordinator `read-only/reconcile` 模式。
- 每小時 GitHub issue／Discord message hard limit，超過即 circuit break。
- queue backlog 上限與告警。
- schema validation 或非法 transition 連續失敗時自動 fail closed。
- 人類可用單一 Discord command 或 config commit 立即停止所有 side effect。

這些是全量上線的必要煞車，不等於要求分段上線。

## 最小修訂清單

進入 implementation plan 前，建議至少在原設計補上以下內容：

1. 將 scout 與 coordinator 拆成不同權限域。
2. 定義 event transport、認證、durable inbox/outbox、ack/retry/dead-letter 與 reconciliation。
3. 將 `run_id` 拆成 `session_id`、`candidate_id`、`proposal_id`。
4. 修正 mention budget 語意，加入公平 quota 與 reservation TTL。
5. 以 exposure set 判斷 `independent_match`。
6. 決定人類修改走 control event，或用 CI 保護 direct commit。
7. 補完整三軸 transition graph。
8. 為成功標準補數值門檻與未達標處置。
9. 補全量上線 kill switch 與 circuit breaker。

## 最終結論

本次版本已把創意方法、資料模型與評估框架推進到可實作的程度，前次 review 的核心建議大多已被正確吸收。現在剩下的是控制平面的工程契約，而不是再次重做產品概念。

在拆開 scout 權限、定義 durable event/outbox、修正 proposal 唯一鍵這 3 個 P0 前，仍不建議直接開始 implementation plan；三項完成後，其餘 P1 可在 implementation plan 的前置 task 中落地，整體設計即可通過。
