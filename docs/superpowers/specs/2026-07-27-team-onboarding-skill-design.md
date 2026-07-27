# team-onboarding skill 設計

- 日期：2026-07-27
- 狀態：設計已核可，待寫實作計畫
- 產物：`skills/team-onboarding/SKILL.md`（＋必要的 reference/範本檔）、`README.md` 一列、版本 bump

## 1. 定位與動機

新增一支**通用、跨 repo** 的「新人入職」skill。開發者把團隊的 onboarding 文件餵給它，它消化成一份**全域團隊 profile**，並在 `~/.claude/CLAUDE.md` 掛一個常駐區塊，讓任何 repo 開工的 bot 都「記得團隊規矩」——把 bot 當成剛入職、讀完新人手冊的團隊新人。

此 skill 補足現有兩支學習型 skill 的**來源缺口**：

| Skill | 學習來源 | 學到的東西存哪 |
|---|---|---|
| self-evolution | Agent 自己工作中的錯誤／被糾正／走彎路（反應式、經驗式） | 全域 `~/.claude/evolution/` + `CLAUDE.md` 區塊 + 專案 memory |
| learn-from-repo | repo 的已合併 PR + Jira + issue（git 產物） | 該 repo 的 `docs/knowledge/` |
| **team-onboarding（本設計）** | **人工策劃的新人 onboarding 文件（手冊、規範、禁忌）** | **全域 `~/.claude/team-profile/` + `CLAUDE.md` 區塊** |

三者互補、不重疊：self-evolution 是「從犯錯學」、learn-from-repo 是「從歷史學」、本 skill 是「入職讀手冊學」。

## 2. 關鍵決策（已與使用者確認）

1. **知識存放與生效**：全域團隊檔（跨 repo）——寫進 `~/.claude/team-profile/` 並在 `~/.claude/CLAUDE.md` 掛指引區塊，任何 repo 開工都自動生效。
2. **文件來源**：三種都支援——本地檔案資料夾、貼上文字或貼連結、互動式訪談。
3. **套用方式**：分層 + 主動檢查——依嚴重度分級，「絕對不可犯」常駐 `CLAUDE.md`，其餘細則按需 recall；在關鍵時機（開工前、commit 前）主動對照。
4. **實作方向**：方向 A——純 skill + `CLAUDE.md` 常駐自檢指令，**不引入 hooks**（與現有三支 skill 一致，零 settings 侵入；且團隊規範多屬語意層面，hook 只能 grep 攔不到重點，判定為過度工程）。
5. **多團隊**：先只支援**單一團隊 profile**（多團隊切換 YAGNI，檔案結構保留擴充空間即可）。

## 3. Frontmatter

- `name: team-onboarding`
- `argument-hint: "[path-or-url] [--interview] [--update]"`
- `description`（多行 `>-` 區塊，供 agent 匹配）：使用者想讓 bot 學團隊開發模式／規範／禁忌、消化新人文件、「幫 bot 入職」時觸發。含中英關鍵字：學團隊模式、新人文件、onboarding、團隊規範、team conventions。
- `allowed-tools`：`Read`、`Write`、`Edit`、`Glob`、`WebFetch`（抓連結前需使用者確認）

## 4. 儲存結構

### `~/.claude/team-profile/`

```
INDEX.md      # 索引 + 來源清單 + updatedAt
never.md      # 絕對不可犯 → MUST-NOT（critical）
standards.md  # 規範/慣例 → SHOULD / MAY
workflow.md   # 開發模式/流程（branching、PR、test、release）
glossary.md   # 術語/領域知識（選用；無內容時可不建）
```

### `~/.claude/CLAUDE.md` 常駐區塊

標題固定為 `## 團隊規範（由 team-onboarding skill 維護）`，內容包含：

1. 逐條精簡的「絕不可犯」清單（來自 `never.md`，always-on）。
2. 一句自檢指令：「動工前與 commit 前，對照上列『絕不可犯』清單自檢；需要細則時讀 `~/.claude/team-profile/`。」
3. 指向 profile 各檔的指標。

**分層在此體現**：critical 常駐 context、細則按需 recall，避免 context 膨脹稀釋重點。**主動檢查機制**即由此常駐自檢指令驅動（沿用 self-evolution 靠 `CLAUDE.md` 常駐指令而非 hook 的成熟做法），而非重新入口叫 skill。

## 5. 嚴重度分級（RFC-2119 精神）

| 類型 | 級別 | 落點 |
|---|---|---|
| 絕對不可犯 | MUST-NOT | `never.md` + `CLAUDE.md` 常駐清單 |
| 規範/慣例 | SHOULD | `standards.md`，按需 recall |
| 偏好/建議 | MAY | `standards.md` |
| 開發模式/流程 | —（流程類，不套 MUST/SHOULD） | `workflow.md`，開工時 recall |

每個條目一律標注**來源**（哪份文件／哪次訪談），供日後追溯與去重。

## 6. 流程（Phases）

### Phase 0：判斷模式
- profile 不存在 → 首次 onboard 流程。
- profile 存在 → `--update` 增量流程（讀入既有條目供 Phase 3 去重）。
- 解析 `$ARGUMENTS`：第一個 token 若為路徑或 URL 即為來源；`--interview` 進訪談；`--update` 標記增量。

### Phase 1：收集來源
- **資料夾／路徑**：`Glob` 找 `md`/`txt`/`pdf`，逐份 `Read`（md/txt/pdf 直讀；docx 建議使用者先匯出成 md/pdf）。
- **URL**：`WebFetch`，抓取前向使用者確認。
- **`--interview`**：一問一答，題庫至少涵蓋——分支策略？PR/review 規矩？測試要求？絕對不可犯的雷？命名慣例？團隊術語？
- **貼上文字**：直接採用使用者貼入的內容。

### Phase 2：抽取 + 分級
- 逐份掃描，抽出條目；每條標 `severity`（MUST-NOT / SHOULD / MAY）＋ `category`（never / standards / workflow / glossary）＋ 來源標注。
- 遵守「寧缺勿濫」，一份文件完全可能產出 0 筆。

### Phase 3：呈現候選、人工確認
- **鐵律：使用者明確確認前，一律不寫任何檔。**
- 依分類分級列出候選，詢問：全部接受／刪某編號／改某編號，可多輪來回。
- 與既有 profile 條目去重；語意衝突則標記，讓使用者裁決保留哪一版。

### Phase 4：寫入
- **固定順序：分類檔 → INDEX → `CLAUDE.md` 區塊**（若中途中斷，重跑安全）。
- `never.md` 每條同步進 `CLAUDE.md` 常駐清單。
- 更新 `INDEX.md` 的來源清單與 `updatedAt`。

### Phase 5：回報
- 總結：新增／更新條目數、各嚴重度筆數、本次來源清單。
- **不自動 commit**（`~/.claude/` 本非本 repo）。

## 7. 鐵律（沿用現有 skill 慣例）

1. **人工確認前絕不寫檔**（沿用 learn-from-repo）。
2. **`CLAUDE.md` 區塊維護**：只認 `## 團隊規範（由 team-onboarding skill 維護）` 標題定位；找不到就在檔尾重建；區塊內非本 skill 產生、使用者手動加的行一律保留不動（沿用 self-evolution）。
3. **只寫全域、不碰任何 repo 的檔**；單一團隊 profile。
4. **全程台灣正體中文**。

## 8. 與 self-evolution 的共存

兩者各自維護 `~/.claude/CLAUDE.md` 中**獨立的區塊**與**獨立的目錄**（`team-profile/` vs `evolution/`），標題不同、互不干擾。來源與觸發時機清楚分工：team-onboarding＝入職讀手冊（一次性/增量匯入），self-evolution＝做中學（每次任務後快篩）。

## 9. 收尾（發佈）

1. 於 `README.md` 的 Available Skills 表新增一列。
2. bump `version`：`.claude-plugin/plugin.json` 與 `.claude-plugin/marketplace.json` 同步。

## 10. 非目標（YAGNI）

- 不做多團隊切換。
- 不做 hooks / settings.json 侵入。
- 不自動抓取整個 Confluence/Notion 空間（僅處理使用者明確給的連結）。
- 不碰、不修改任何 repo 內檔案。
