# 輸出契約（Output Contract）

## 葉任務契約格式

每個葉任務輸出以下結構化契約。嚴謹度停在 **artifact / 介面名稱層級**，不碰型別簽名、SQL、內部實作。

```
### T1.2 <標題>
- Goal: <一句話目標>
- Acceptance Criteria (Gherkin):
    Scenario: 成功建立訂單
      Given 已存在有效的購物車
      When 呼叫 POST /orders
      Then 回傳 201 且訂單狀態為 pending
    Scenario: 購物車為空時拒絕
      Given 購物車沒有品項
      When 呼叫 POST /orders
      Then 回傳 400 並附錯誤訊息
- Inputs (consumes): [T1.1:OrderSchema]
- Outputs (produces): [OrderSchema, POST /orders]
- Depends on: [T1.1]
- Right-sized: OK <理由>
```

（`Inputs` 空 = 無前置；`Outputs` = 給下游接的介面 / artifact。）

## Gherkin 規範

- 停在**行為層**——只描述看得到的輸入 / 輸出 / 狀態，不提函式名、SQL、內部類別。
- 一條使用者可觀察的路徑對一個 Scenario；happy path 與 error path 各自成 Scenario。
- 若需要超過約 3~5 個 Scenario 才描述得完 → 觸發過大訊號（見 right-sizing-rubric），應再拆。
- 這份 Gherkin 可直接餵給 TDD skill 當測試起點。

## 最終輸出（結構化 markdown，四塊）

1. 判定摘要：`right-sized` / `too-big` + 命中的 rubric 訊號理由。
2. 任務樹：深度不一的階層清單，葉節點都通過 right-sizing，每個葉節點含上方完整契約。
3. DAG 依賴圖 + 拓樸執行順序：文字化依賴圖與建議執行序；標出可平行的兄弟任務。
4. 交棒註記：建議對每個葉任務依拓樸序逐一跑 writing-plans；可平行者建議搭配 dispatching-parallel-agents。

## ID 命名規則

- 階層式 ID：頂層 `T1`、`T2`；子層 `T1.1`、`T1.2`；再下層 `T1.1.1`。
- ID 在整棵樹內唯一，Inputs / Depends on 一律以 ID（可加 `:artifact` 後綴）引用，確保串接參照明確。
