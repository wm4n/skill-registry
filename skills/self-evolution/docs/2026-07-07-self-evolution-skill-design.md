# Self-Evolution Skill — 設計文件

- 日期：2026-07-07
- 狀態：已批准（brainstorming 完成）
- 定位：專案無關（project-independent）的全域 skill，讓 agent 在持續工作中
  學習錯誤、定期復盤、擴張能力、打破思考慣性。

## 1. 目標與範圍

一個完整的自我進化框架，涵蓋四個子系統：

1. **錯誤學習**：被使用者糾正時，根因分析並寫下可執行的防範規則。
2. **定期復盤**：任務走了彎路時，還原決策點、提煉教訓。
3. **能力擴張**：偵測重複工作模式，提案固化成新 skill（草稿就緒、使用者批准才生效）。
4. **慣性偵測**：發現自己慣性重複同一解法時，主動反思更好的路徑，沉澱思考模式。

### 與既有機制的分工

| 機制 | 分工 |
|---|---|
| auto-memory（依專案） | 專案特定教訓的儲存與 recall，本 skill 直接復用 |
| consolidate-memory | 整理 auto-memory；本 skill 的全域儲存自帶容量管理 |
| 專案層 tasks/lessons.md | 專案內慣例，不衝突；通用教訓由本 skill 升級到全域 |
| superpowers:brainstorming | 事前設計發散；本 skill 管事後沉澱與慣性警報，不重疊 |
| superpowers:writing-skills | 能力提案的 skill 草稿依其規範撰寫 |

## 2. 核心設計決策（brainstorming 結論）

1. 範圍：完整框架（四子系統），分層實作。
2. 觸發：全靠 skill description 自動觸發（無 hooks、無手動指令）。
3. 儲存：雙層——通用教訓存全域 `~/.claude/evolution/`；專案特定教訓存該專案 auto-memory。
4. 生效：教訓精簡條列注入全域 `~/.claude/CLAUDE.md` 專屬區塊（上限 20 條），
   完整記錄留 evolution 目錄。
5. 能力擴張：只提案 + 草稿就緒，使用者批准才搬進 `~/.claude/skills/` 並真實驗證。
6. 復盤粒度：兩級制——每任務結束跑零成本快篩，命中才進完整復盤。
7. 創造力：併入復盤的創造力反思 + 慣性偵測觸發，洞見沉澱成思考模式庫。
8. 結構：單一 skill + 分層 references（方案 B）。

## 3. 架構

### 3.1 Skill 結構

```
~/.claude/skills/self-evolution/
├── SKILL.md                      # 觸發條件 + 快篩清單 + 分流指引（精簡）
├── DESIGN.md                     # 本文件
└── references/
    ├── error-learning.md         # 錯誤學習完整流程
    ├── retrospective.md          # 完整復盤流程（含慣性反思、思考模式沉澱）
    └── capability-proposal.md    # 能力提案流程
```

SKILL.md 是唯一入口：description 涵蓋所有觸發時機，內文只有快篩清單與
「命中哪項就讀哪個 reference」的分流表。快篩不載入任何 reference。

### 3.2 全域儲存

```
~/.claude/evolution/
├── INDEX.md                      # 總索引：每筆一行（類型 + 標題 + 日期 + 狀態）
├── lessons/                      # 完整教訓（根因分析、防範規則、適用範圍）
│   └── YYYYMMDD-<slug>.md
├── retros/                       # 復盤記錄（只有完整復盤才產出，快篩不留檔）
│   └── YYYYMMDD-<slug>.md
├── proposals/                    # 能力提案（每提案一資料夾，內含草稿 SKILL.md）
│   └── <slug>/
│       ├── PROPOSAL.md           # 重複模式觀察、預期效益、狀態(pending/approved/rejected)
│       └── SKILL.md              # 就緒草稿（未生效）
└── patterns/                     # 思考模式庫
    └── <slug>.md
```

### 3.3 全域 CLAUDE.md 注入區塊

`~/.claude/CLAUDE.md` 末尾維護：

```markdown
## Self-Evolution 教訓（由 self-evolution skill 維護）
- [E001] 一行摘要（詳: evolution/lessons/YYYYMMDD-slug.md）
```

- 每條一行、`[Exxx]` 編號、附完整記錄指向。
- 上限 20 條；滿了先合併同類，仍超限則降級「最久未被引用也未被違反」的條目
  （從區塊移除，`lessons/` 完整記錄保留；lessons 檔內記錄最後引用日期供判斷）。
- 專案特定教訓不進此區塊，寫入該專案 auto-memory（沿用其格式與 recall）。

### 3.4 Scope 判斷規則

寫任何教訓前先問：「換一個專案，這條還成立嗎？」

- 成立（工作方法、安全原則、工具使用慣例）→ 全域 evolution + CLAUDE.md 區塊。
- 不成立（專案命名慣例、特定 codebase 的坑）→ 專案 auto-memory。

## 4. 子系統流程

### 4.1 快篩（SKILL.md 內建，每次任務結束執行）

四問，全「否」即結束、不留檔、不輸出：

1. 有被使用者糾正嗎？（含隱性的「其實我要的是…」）→ 讀 error-learning.md
2. 有走彎路嗎？（失敗重試 2 次以上、推倒重做、方向修正）→ 讀 retrospective.md
3. 第 3 次以上做同類工作嗎？→ 讀 capability-proposal.md
4. 慣性地用了跟上次一樣的方法且結果平庸嗎？→ 讀 retrospective.md 慣性反思節

多項命中依序處理。

### 4.2 錯誤學習（error-learning.md）

1. **根因分析**：問「為什麼我當時認為那樣是對的？」——錯誤假設、缺失檢查、或知識空缺。
2. **防範規則**：一條可執行的規則（「做 Y 前先確認 Z」），不是「要更小心」。
3. **Scope 判斷**：依 3.4 分流寫入。
4. **二犯檢查**：若違反的是已記錄教訓，必須改寫規則本身（事後提醒 → 事前檢查步驟），
   並標記「二犯」。
5. **糾正 vs 需求變更**：「你做的不符合我原本要的」才是糾正；
   「改成藍色」是新需求，不存教訓。

### 4.3 完整復盤（retrospective.md）

1. **還原決策點**：哪一步選錯方向？當時已有什麼資訊足以避開？
2. **提煉教訓**：走 error-learning 相同寫入流程。
3. **創造力反思**：「這次是慣性還是最佳解？重來有沒有更優雅的路？」
   有具體洞見才寫入 patterns/（如「遇 X 類問題先試 B 再考慮慣用的 A」），空泛感想不寫。
4. 產出 retros/ 記錄（一頁以內）。

### 4.4 能力提案（capability-proposal.md）

1. **確認模式**：三次的共同步驟？能參數化？未來還會發生？
2. **寫提案**：proposals/<slug>/PROPOSAL.md。
3. **寫草稿**：依 writing-skills 規範完成 SKILL.md 草稿（不生效）。
4. **告知使用者**：批准 → 搬進 ~/.claude/skills/ + 真實跑一輪驗證；
   否決 → 標記 rejected 留檔，不再重提（除非情境明顯改變）。

### 4.5 防重複 / 防爆炸

- 寫入前查 INDEX.md：同主題已存在 → 更新既有記錄，不新增。
- rejected 提案不重提。

## 5. 觸發設計

SKILL.md description 草案：

> Use when the user corrects you or expresses dissatisfaction (「不對」「不是這樣」
> 「其實我要的是」), when you complete a task that involved failed attempts or rework,
> when you notice doing the same type of work for the 3rd time, when you catch yourself
> reusing the same approach out of habit, or when finishing any task
> (run the quick screen).

- 列出中英文糾正語句實例以提升觸發率。
- 「任務結束跑快篩」為兜底條款。

## 6. 邊界情況

1. **首次執行**：evolution/ 不存在 → 建目錄結構 + 空 INDEX.md；
   CLAUDE.md 無區塊 → 追加到檔案末尾。
2. **區塊被手動改壞**：只認 `## Self-Evolution 教訓` 標題定位；找不到就重建；
   區塊內使用者手動加的行保留，只管理 `[Exxx]` 條目。
3. **subagent 情境**：被派遣為 subagent 時不觸發（與 superpowers 慣例一致），
   避免併發寫入衝突。
4. **快篩靜默**：無產出時不產生任何對話輸出。

## 7. 驗證計畫

1. **錯誤學習路徑**：使用者故意糾正一次 → 驗證觸發、根因品質、scope 分流、區塊格式。
2. **快篩靜默路徑**：順利小任務 → 驗證無多餘輸出、無檔案產生。
3. **資料遷移**：hangman `agents/lessons.md` Entry 001（client 端 API Key）
   遷入全域 lessons 作為第一筆真實資料，驗證儲存格式。
4. **能力提案路徑**：需自然情境（三次重複），留待日常使用驗證。
