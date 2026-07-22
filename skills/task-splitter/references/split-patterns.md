# 拆分手法（Split Patterns）

優先垂直切片（vertical slice），**不切水平層**。每個切片都要是「跨層但窄」的端到端一薄片可驗證價值，而不是「先做完所有 DB 再做所有 API」——水平層對 AI 自動化最致命，因為中間狀態不可驗證。

## Story-splitting patterns（依序嘗試）

1. 工作流步驟（workflow steps）
2. 業務規則變體（business rule variations）
3. happy path / error paths（天然對應 Gherkin 的 Scenario）
4. CRUD 操作
5. 介面 / 資料變體（含平台變體，見下節）
6. 大小硬切（effort）— 最後手段

## 多平台切分規則（contract-first）

當需求橫跨多平台（android / ios / web / 後端）時：

1. 偵測到多平台 + 存在共享後端/契約 → 抽出一個 contract-definition 任務放**上游**（通常是後端 API / schema / 協定），各平台變成**平行消費同一契約的兄弟任務**。
2. 切分主軸仍是 feature（垂直），平台是**第二軸**——「Feature A：契約 →〔Android ∥ iOS ∥ Web〕」，而**不是**「先全部 Android，再全部 iOS」。每個 feature 都能獨立端到端出貨。
3. 平台當第一刀的例外：平台間根本沒有共享契約（純客戶端、不同發版節奏、不同團隊）→ 才用純平台變體切成獨立兄弟任務。
4. 若共享契約任務本身太大 → 照常遞迴再拆。

### 範例

需求：「使用者可在 App 和網頁建立訂單」

```
T1 定義訂單 API 契約 (後端)
   Outputs: [OrderSchema, POST /orders, GET /orders/:id]
   Depends on: []

T2 Android 建立訂單畫面   Inputs: [T1:OrderSchema, T1:POST /orders]   Depends on: [T1]
T3 iOS 建立訂單畫面       Inputs: [T1:OrderSchema, T1:POST /orders]   Depends on: [T1]
T4 Web 建立訂單畫面       Inputs: [T1:OrderSchema, T1:POST /orders]   Depends on: [T1]
```

DAG（T2/T3/T4 平行、彼此零依賴）：

```
        +-- T2 Android
T1 契約 +-- T3 iOS
        +-- T4 Web
```

共享契約只被 T1 宣告一次成 Outputs，三支平台各自列進 Inputs；平台只依賴契約、不依賴彼此，因此可平行執行（適合搭配 dispatching-parallel-agents），下游永遠拿得到 T1 定義好的介面。
