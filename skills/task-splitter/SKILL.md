---
name: task-splitter
argument-hint: "[需求文字 | spec 檔案路徑 | Jira-ID]"
description: >-
  判斷一段功能需求是否太大到不適合直接進實作；若太大，遞迴拆成 right-sized、可獨立驗證的子任務。
  用 INVEST + 明確 rubric 判大小，用 vertical slice + story-splitting patterns 拆，
  多平台採 contract-first（共享契約放上游、各平台平行）。
  每個葉任務含 Gherkin (Given-When-Then) 驗收與結構化 artifact 串接契約，形成依賴 DAG，
  讓 AI 自動化開發能一個接一個順暢接力。終點交棒 writing-plans。
  適用時機：拿到一段功能需求 / spec / Jira 票，在進 brainstorming 或 writing-plans 前想先確認顆粒度是否恰當並拆分。
allowed-tools:
  - Read
  - Bash(node *)
---

# Task Splitter

判斷功能需求是否過大並拆成 right-sized、串接無礙的子任務，交棒 writing-plans。所有輸出使用繁體中文。

本 skill 只做「判大小 + 拆分 + 建串接契約」。**不寫實作計畫**（那是 writing-plans）、不寫程式碼、不碰型別/SQL/函式名等實作細節。

## Phase 1: 解析輸入（自動辨識來源）

取 `$ARGUMENTS` 第一個 token，判斷來源並正規化成一段「需求文字」：

1. 若是**存在的檔案路徑** → 用 `Read` 讀入。
2. 若符合 Jira ID 樣式 `[A-Z]+-\d+` → 呼叫 `jira-fetch` skill 取得結構化需求。
3. 其他 → 當作使用者直接貼上的純文字需求。

## Phase 2: Right-sizing 判定

依 `references/right-sizing-rubric.md` 的 7 條過大訊號比對目前這段需求。輸出 `right-sized` 或 `too-big`，**並附上命中哪幾條訊號與一句理由**。

## Phase 3: 分岔

- `right-sized` → 產出「可直接進實作」結論 + 依 `references/output-contract.md` 的單一任務契約（含 Gherkin 驗收）→ 提示交棒 writing-plans，結束。
- `too-big` → 進入 Phase 4。

## Phase 4: 拆分一層

依 `references/split-patterns.md` 手法（優先 vertical slice；多平台套用 contract-first 規則）把目前需求切一層。

## Phase 5: 遞迴

對每個切片回到 Phase 2 判定；`too-big` 就再拆，直到每片都 `right-sized`。設安全上限：拆到第 4 層仍未收斂就停，並提醒人工介入檢視需求是否本身定義不清。

## Phase 6: 建 DAG 並輸出

依 `references/output-contract.md`：

1. 指派階層式 ID（`T1` / `T1.1` / `T1.1.1`）。
2. 為每個葉任務填契約（Goal、Gherkin 驗收、Inputs、Outputs、Depends on、Right-sized 理由）。
3. 計算依賴邊與拓樸執行順序，標出可平行的兄弟任務。
4. 輸出四塊結構化 markdown：判定摘要、任務樹、DAG + 拓樸順序、交棒 writing-plans 註記。

## 參考

- `references/right-sizing-rubric.md` — 過大訊號與判定規範。
- `references/split-patterns.md` — 拆分手法與多平台 contract-first 規則。
- `references/output-contract.md` — 契約格式、Gherkin 規範、輸出四塊、ID 命名。
