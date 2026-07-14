# 能力提案流程

快篩偵測到「第 3 次以上做同類工作」時執行。目標：把重複勞動固化成新能力，
但生效與否由使用者把關。

## 流程

### 1. 防重複檢查

查 `~/.claude/evolution/INDEX.md` 的 Proposals 區：

- 同主題已 `pending` → 不重複提案，提醒使用者有提案待審即可
- 同主題已 `rejected` → 不重提，直接結束（除非情境明顯改變——例如當初否決的
  理由已不存在，此時說明變化後再提）
- 同主題已 `approved` → 檢查為何既有 skill 沒被觸發，這本身可能是一個教訓

### 2. 確認模式

- 這三次的共同步驟是什麼？
- 變動的部分能參數化嗎？
- 未來還會再發生嗎？（一次性的批量工作不值得固化）

三題有任一「否」→ 不提案，結束。

### 3. 寫提案

建 `~/.claude/evolution/proposals/<slug>/PROPOSAL.md`：

```markdown
# <提案標題>

- 日期：YYYY-MM-DD
- 狀態：pending
- 觀察到的重複：<三次分別是什麼時候、做了什麼>
- 共同模式：<可固化的步驟>
- 建議形態：<skill / 既有 skill 的擴充 / script>
- 預期效益：<省下什麼>
```

### 4. 寫 skill 草稿

依 superpowers:writing-skills 的規範，在同資料夾寫好可用的 `SKILL.md` 草稿
（含 frontmatter name/description、完整流程）。草稿放在 proposals/ 內**不生效**。

### 5. 告知使用者

「我注意到 <模式> 已重複三次，已備好 skill 草稿在
`~/.claude/evolution/proposals/<slug>/`，要啟用嗎？」

- **批准** → 搬進 `~/.claude/skills/<slug>/SKILL.md`，PROPOSAL.md 狀態改
  `approved`，INDEX 同步；然後**真實跑一輪驗證**（用真實情境走一次新 skill，
  確認觸發與流程正確）。搬移前先確認 `~/.claude/skills/<slug>/` 不存在同名
  skill，撞名則先與使用者確認改名
- **否決** → 狀態改 `rejected`，記下否決理由，INDEX 同步，留檔不重提

INDEX.md 的 Proposals 區維護一行：`- [狀態] <標題> — YYYY-MM-DD — proposals/<slug>/`
