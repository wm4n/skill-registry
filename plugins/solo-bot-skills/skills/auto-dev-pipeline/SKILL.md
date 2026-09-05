---
name: auto-dev-pipeline
argument-hint: "github-issue <owner/repo>#<number> | jira-ticket <JIRA-ticket-id>"
description: >-
  已完整分析、可直接開發的需求全自動落地。由獨立部署的 agent-dev-poller
  （K8s CronJob，不含 LLM）偵測到 Jira 票或 GitHub issue 貼上
  ready-for-agent-dev label 後，用 jira-grill-trigger bot @mention 觸發
  （不是人類 @mention、不在一般 Discord 對話）：把來源內容當作已定案的
  規格，不再跟人類確認，直接 openspec new → ff → apply → 獨立 subagent
  自我審查 → archive → 開 PR。獨立於三 bot 接力 pipeline，也獨立於
  solo-feature-pipeline（那支需要人類先在對話裡明確要求開發）。
---

# Auto Dev Pipeline

跟 `solo-feature-pipeline` 的差異只有一件事：**發起者不是活人、不用等
人類點頭**——`agent-dev-poller` 已經確認過這是真的新目標，且 label
`ready-for-agent-dev` 本身就代表「人類判斷這個需求已經分析完整、可以直接
交給 agent 開發」。除了跳過確認閘門、把回報媒介換成留言/comment 之外，
其餘開發紀律（TDD、worktree 隔離、獨立 subagent 審查、停損）全部沿用
Genie 本來就有的鐵則。

## 觸發方式（`$ARGUMENTS`）

- `github-issue <owner/repo>#<number>`：GitHub 側來源，repo 已知，不用解析。
- `jira-ticket <TICKET_ID>`：Jira 側來源，票本身沒有 repo 欄位，見下方
  「Repo 解析（僅 Jira 來源）」。

兩種來源都是 `agent-dev-poller`（見
`deployment-guides/k3s/agent-dev-poller/`）判斷該票/issue 貼了
`ready-for-agent-dev` label 且尚未認領後，原子性把 label 換成
`agent-dev-active`，再用 `jira-grill-trigger` bot 貼出這個指令觸發。這裡
不用再自己判斷「要不要處理」——只有下方步驟 1 的重複觸發防護例外。

## 步驟

### 1. 重複觸發防護

`agent-dev-poller` 沒有分散式鎖，GitHub 側「先加 active、後移除 ready」
兩步驟之間若第二步失敗，理論上可能在同一個 issue 還沒處理完前被重複觸發。
開始任何實質動作前，先檢查來源（GitHub issue comments / Jira 票留言）裡
有沒有已經帶簽名 `— By Genie (auto-dev-pipeline)` 的留言：

- 有 → 這是重複觸發，no-op 結束，輸出盡量精簡。
- 沒有 → 立刻貼一則「🧞 開始處理」留言（帶簽名，見下方「留言簽名」），
  當成本次的認領標記，然後繼續步驟 2。

### 2. 讀來源全文

- `github-issue`：`gh issue view <owner/repo>#<number> --json title,body,comments,labels`。
- `jira-ticket`：`jira-fetch <TICKET_ID> --comments 50`。

### 3. Repo 解析（僅 Jira 來源；GitHub 來源的 repo 已知，跳過本節）

沿用 `jira-grill` skill 同一套「Repo 解析與準備」優先序（票的欄位/GitHub
URL → `product-context` 背後的 `104cac-product-registry` 登錄表 → 都無法
決定），但收斂方式不同——這裡沒有人類即時對話可以問，全部由你自己判斷：

- **命中單一 repo** → 直接用，繼續步驟 4。
- **命中多個候選**（同一產品多個 repo/平台，或登錄表對應到不只一個
  產品）→ **不要停下來問人類**，用票的標題、描述、驗收條件裡的技術線索
  （提到的平台、程式語言、既有功能位置等）自行判斷最合理的一個。判斷
  依據要留在 archive 後的 PR 描述或 Jira/issue 回報留言裡，方便事後人類
  複查你選錯了沒有。
- **完全無法解析**（查無登錄表項目、`gh api` 抓取失敗、或登錄表本身
  對應不到任何 repo）→ 這是唯一允許在本 skill 停手的情況：貼一則說明
  「repo 無法解析，需要人類手動補齊 `104cac-product-registry` 或在票上
  明確指定 repo」的留言（帶簽名），label 從 `agent-dev-active` 改成
  `agent-dev-failed`，結束。人類處理好之後手動把 label 改回
  `ready-for-agent-dev`，下一輪 `agent-dev-poller` 會重新撿到。

### 4. Repo 帳號與準備

1. 依 repo owner 選 GitHub 帳號並 `gh auth switch`：`104corp`（或
   `openabdev`）用 `cac-william`，`wm4n` 用 `wm4n`——邏輯同
   `repo-identity` skill、同 `[[feedback-github-account-per-repo]]` 既有
   慣例。
2. Base clone 固定在 `/home/node/repos/<owner>/<repo>`：不存在就 clone，
   存在就 `git fetch`/`pull` 到最新（除非人類另有指示，這裡沒有人類在
   場給指示，永遠更新到最新）。
3. 每個任務／branch 開獨立 worktree（`/home/node/repos/<owner>/<repo>-worktrees/<branch>`），
   細節同 Genie 本來就有的「Repo 工作隔離（Worktree，Critical）」鐵則，
   不因為是自動觸發而放寬。
4. 讀該 repo 的 `CLAUDE.md`/`AGENTS.md`、可用 skill，掌握規範。若有
   `.mise.toml`/`.tool-versions` 跑 `mise install`；若是 Dockerfile/
   Makefile 模式改用 Docker 流程——都沿用 Genie 本來的「開工前準備」SOP，
   不重複規範。

### 5. 開發：openspec `new → ff → apply`

同 `solo-feature-pipeline` 步驟 2：若目標 repo 尚無 `openspec/` 先
`openspec init`；`/opsx:new "<依來源內容濃縮的規格描述>"` →
`/opsx:ff` → `/opsx:apply`。**archive 留到步驟 7 review 通過後才做。**

### 6. 自我審查：一定要派獨立 subagent

同 `solo-feature-pipeline` 步驟 3——絕不在同一個 context 自己審自己寫的
diff，一定用 Task/Agent 開全新 subagent 審查，findings 分類成「實作
bug」或「規格問題」。

### 7. 判斷結果與停損

```
review 結果？
├─ 全數 PASS → 進步驟 8（archive）
└─ 有 FAIL
    ├─ 任一 finding 是「規格問題」
    │     → 這裡沒有「回步驟 1 問人類」這條路（發起者不是活人）。
    │       停手：留言說明是規格問題、具體錯在哪、建議怎麼修規格
    │       （帶簽名），label 改 agent-dev-failed，結束。人類修好規格、
    │       手動改回 ready-for-agent-dev 才會被下一輪重新撿到。
    └─ 全部是「實作 bug」→ 用 systematic-debugging（或更適合的 skill）修
                          → 回步驟 6 重新審查，累計一輪
                          → 連續 3 輪都還是實作 bug 型失敗
                            → 停手：留言整理「試過什麼、為什麼還是不過」
                              （帶簽名），label 改 agent-dev-failed，結束。
```

### 8. Archive

Review 真的全數通過後才跑 `/opsx:archive`。

### 9. 建 PR + 收尾留言 + label

1. `gh pr create` 開 PR。
2. 在來源（GitHub issue / Jira 票）留言 PR 連結、這次改了什麼（簡短
   清單）、確認已通過自我審查（帶簽名）。
3. Label 從 `agent-dev-active` 改成 `agent-dev-done`。
4. 清理 worktree（同 Genie 鐵則，任務完成即清）。

## 留言簽名

固定 `— By Genie (auto-dev-pipeline)`——跟 persona 其他情境用的簽名或
`jira-grill` 用的 `— By Rick (jira-grill)` 都不同，本 skill 步驟 1 的
重複觸發防護靠這串文字判斷「這個目標是不是自己已經在處理」，改了格式
判斷會失效。

## 環境變數

- `JIRA_TOKEN`/`JIRA_EMAIL`/`JIRA_BASE_URL`：僅 `jira-ticket` 來源需要，
  同 `jira-fetch` skill。

## 已知限制

- **沒有「回頭問人類」的中間狀態**：`solo-feature-pipeline` 遇到規格問題
  會退回步驟 1 跟活人對話釐清；這裡沒有活人在對話裡，只能整個停手、留言
  說明、標成 `agent-dev-failed`，等人類修好規格再重新觸發，不是更聰明的
  自動修正。
- **多重 repo 候選靠 LLM 自行判斷，沒有二次確認**：判斷錯了不會有人在
  過程中攔下來，只能靠 PR 描述/回報留言裡寫清楚判斷依據，讓人類事後複查。
- **`agent-dev-active` 沒有逾時自動復原**：若 Genie 的 pod 在流程中途被
  殺，目標會卡在 `agent-dev-active`，需要人類手動改回
  `ready-for-agent-dev` 才會被 `agent-dev-poller` 重新撿到。
- **輪詢頻率、掃描的 project/repo 範圍不是本 skill 能決定**：由
  `agent-dev-poller` 的 K8s CronJob 設定決定，見
  `deployment-guides/k3s/agent-dev-poller/`。
