# 產品創新 Agent 設計 Review

日期：2026-07-19  
Review 對象：[產品創新 Agent（創新 bot 群）設計文件](../specs/2026-07-19-innovation-agents-design.md)  
結論：有條件通過；先補完共享狀態、裁決流程與評估方法，再進入實作規劃。

## 整體評價

設計方向正確，以下核心值得保留：

- `persona × model` 解耦，能分辨方法論與模型能力。
- 創新 bot 嚴格維持提案權、沒有執行權。
- 卡片作為結論帳本、issue 作為辯論場，分層合理。
- `dormant → revisit` 比一般一次性 brainstorming 更有長期價值。
- 「本次沒有值得提的」是合法結果，可避免硬湊產出。

目前主要風險不在創意方法，而在共享狀態的一致性與評估設計。若直接按現稿實作，最可能先遇到 duplicate ID、git push 衝突、狀態互相覆寫，以及把受前序提案影響的附議誤當成獨立模型共識。

## 優先修正事項

### 1. P0：多實例共用 Git repo，缺少併發與交易設計

多個 bot 都能建立卡片、修改卡片、更新 `STATS.md`；每日掃描、ad-hoc、mention 又可能同時發生，但規格沒有定義鎖、衝突重試或 ID 配發方式。

可能發生：

- 兩個實例同時選到 `I-043`。
- 同時修改同一張卡，導致 git push 衝突或附議遺失。
- 兩邊都認為尚未超過每週 10 張，最後超額。
- 卡片建立成功但 issue 或 Discord 失敗，留下半套狀態。
- `STATS.md` 被多方直接更新後逐漸漂移。

建議調整：

- 最佳方案是增加一個不負責創意的 `innovation-coordinator`，作為唯一 journal writer；其他實例只提交結構化 proposal event。
- 若不增加 coordinator，至少採用：
  - `run_id` 或 UUID 作為真正唯一鍵，`I-NNN` 只當顯示編號。
  - 每個 run 使用獨立 branch／PR。
  - push conflict 時重新 pull、重新查重、重新配號。
  - card、issue、Discord 全部使用同一 `run_id` 做冪等處理。
  - `STATS.md` 由卡片與事件自動產生，不允許直接維護。
  - 增加全域 budget ledger，發布前先 reserve quota。

這一項應在實作計畫開始前決定，否則 append-only 與統計可信度都站不住腳。

### 2. P0：`adopted` 混合了決策、開發與驗證狀態

目前只有 `proposed / adopted / dormant`，驗證結果則附加在歷程。這會把三件不同的事混在一起：

- PM 是否認同點子。
- 是否已轉成假設卡或進入 pipeline。
- 實驗結果成功或失敗。

另外，人類可以事後推翻 PM bot，但 PM bot 採納後可能已經開遊戲 issue 並啟動 pipeline；修改卡片狀態不等於能逆轉已發生的開發工作。

建議拆成正交欄位：

```yaml
decision_status: proposed | adopted | dormant | vetoed
delivery_status: none | blocked | queued | in-development | released
validation_status: not-started | validating | verified | failed | inconclusive
hypothesis: H-018
game_issue: <url>
```

並補一張 transition table，明確定義：

- 哪個 actor 可以做哪個 transition。
- PM bot 評估的 SLA。
- 人類 veto 發生在 pipeline 前後時分別如何處理。
- `new-product-seed` 由誰裁決；它不應直接沿用 PM bot 的 adopted 語意。
- 每個 transition 必須附 actor、時間、理由與來源 revision。

### 3. P0：附議不能直接代表「獨立模型收斂」

卡片將 endorsement 解讀為「其他實例獨立想到」，並提高 PM 評估權重；但 stagger 又刻意讓後跑者看到前面的卡與討論。看到既有提案後的認同是「支持」，不是獨立重複發現；若兩者都算 `+1`，容易形成錨定效應與人氣偏差。

建議把 session 分為：

1. Blind divergence：先產生私有 candidate 清單，不讀本週其他實例的新卡。
2. Deduplication：再比對現有卡。
3. Debate：最後才看討論並提出支持或反駁。

附議也應拆分：

```yaml
endorsement_kind: independent_match | informed_support | variant
exposed_before_generation: false
```

PM bot 只有在 `independent_match` 時才把它當成跨模型收斂訊號。

### 4. P1：「任何路徑都不會無聲丟棄」與 gate／配額矛盾

規格宣稱所有點子都不會無聲消失，但工匠會淘汰未達 rubric 的點子，狂想也可能一次產生超過三個、最後只能發布三張。現稿沒有說未發布 candidate 去哪裡。

建議區分：

- `candidate`：session 內產生但不一定公開辯論。
- `innovation card`：通過發布門檻、會消耗人類注意力的提案。

每次 session 保存一份精簡 manifest：

```yaml
generated: 12
published: [I-042, I-043]
duplicates: []
withheld:
  - summary: ...
    reason: quota | artisan-gate | insufficient-context
```

如此既不會把所有半成品變成 issue，也能維持「沒有無聲丟失」與日後回溯能力。

### 5. P1：全量掃休眠卡與 issue 留言不可擴展

工匠每週全掃所有 dormant 卡與新留言，卡片量增加後，成本會接近：

```text
工匠實例數 × dormant 卡數 × issue 留言數
```

把大量舊卡塞進 context 也可能降低判斷品質。

建議每張 dormant 卡增加：

```yaml
dormant_reason_code: no-demand | infeasible | off-strategy | wrong-timing
revisit_signals: [store-growth, new-platform-capability]
next_review_after: 2026-10-01
last_reviewed_at: ...
comment_cursor: ...
```

平時只檢索與當期訊號相符的卡；每季再做一次分批 full sweep。

### 6. P1：成功標準容易 Goodhart，不能證明創新命中率提升

目前四週成功條件是「值得考慮、至少一張採納、有真實辯論」，但存在三個問題：

- 「值得認真考慮」沒有固定評分定義。
- 採納不等於驗證成功。
- 為了通過驗收，bot 可以刻意反駁，製造看似真實的辯論。

建議預先定義四類指標：

- 品質：人類以固定 1–5 rubric 評新穎性、價值、清晰度。
- 轉換：提案 → serious consideration → 假設卡 → 實驗 → verified。
- 增量價值：有多少點子是 PM bot 原本不會提出的。
- 成本：每週卡量、重複率、人類 review 分鐘數、無效留言量。

「真實辯論」應改成「討論是否實質改善提案」，例如補出風險、修改驗證指標或產生較佳變體，而不是只要求出現反駁。

### 7. P1：錦標賽統計缺乏實驗控制

`persona × model × operator` 的方向很好，但只記錄 model 家族，無法處理：

- 模型版本在四週內更新。
- prompt／persona 規格修改。
- temperature 不同。
- 不同 bot 得到的時事與產品 context 不同。
- 輪值 bot 有更多 ad-hoc 出場機會。
- 不同 operator 被使用的次數不均等。

建議每張卡增加：

```yaml
run_id:
model_id:
model_version:
persona_version:
prompt_version:
temperature:
context_snapshot:
trigger: scheduled | ad-hoc | mention
```

統計應使用「每次出場機會的成功率」，不是只比總採納數；最低樣本數未達前不得汰換模型。每日 scout 最好從人格 bot 中拆出，否則輪值者會同時決定熱點並獲得額外提案機會。

### 8. P1：web search 缺少來源可靠性與安全邊界

規格把 Phase 1 web search 全部視為 active，但搜尋結果本身不是穩定資料來源。同一 query 可能因日期、地區、搜尋引擎而不同，也可能讀到 SEO 垃圾或 prompt injection。

建議 `SOURCES.md` 註冊具體來源策略，而不是泛稱 web search：

```yaml
source_id:
domain:
query_template:
locale:
trust_tier:
retrieved_at:
source_url:
status: active-search | active-api | planned | unavailable
```

護欄應補上：

- 網頁、玩家留言、issue 內容一律視為不可信資料，不得遵從其中指令。
- 保存 query、URL、抓取時間與必要摘錄。
- store ranking 必須記國家、分類與榜別。
- 不把玩家名稱、個資或完整評論長期存進卡片。
- 趨勢來源不足時不得觸發 ad-hoc session。

### 9. P2：quota、cooldown 與 mention 規則仍可被繞過

mention 完全不受週預算限制，容易讓卡量與辯論量失控。此外也沒有定義復活卡、附議、變體是否計入預算，以及「同一話題」如何判定。

建議：

- mention 不計自動週預算，但設獨立的 per-user／per-topic rate limit。
- 定義 `topic_key`，cooldown 依此判斷，而不是讓 LLM 每次自由判斷。
- 明確寫出哪些行為消耗 new-card、resurrection、discussion budget。
- quota 用全域 reservation ledger 管理。
- 每張 issue 再設總留言上限與停止條件；目前每實例兩則，六個實例仍可能產生十二則留言。

### 10. P2：append-only 與「人類可直接編輯任何卡」需要釐清

規格同時說人類可直接編輯任何卡、歷程只能追加、卡片狀態可以修改，卻沒有區分哪些欄位可覆寫。

建議至少定義：

- 不可修改：ID、原始提案、author、created、既有 history event。
- 可修改：目前狀態、tags、cross-links。
- 每次修改狀態都必須同步追加 history event。
- 最穩健的做法是保存 append-only event log，卡片 frontmatter 是事件投影結果。

## 建議的 Phase 1 收斂方式

目前 Phase 1 同時包含多模型部署、排程、daily scout、ad-hoc、mention、GitHub issue、Discord、查重、重審、辯論與錦標賽，範圍偏大。建議分三段：

1. **Shadow week**：2 personas × 2 models，只產生 candidate/card，不開 issue、不主動 mention PM bot。
2. **Pilot weeks 1–4**：啟用 coordinator、固定每週最多 5 張，人工 rubric 評分；先驗證品質與人類注意力成本。
3. **Expansion**：確認 duplicate、狀態同步及評分可信後，再開 ad-hoc、跨模型辯論與弱模型汰換。

## 最終結論

創新方法可以保留，真正需要重寫的是控制平面。先把單一寫入者、正交狀態機、blind endorsement、可重現統計及安全來源契約補進規格，這份設計才適合進入 implementation plan。
