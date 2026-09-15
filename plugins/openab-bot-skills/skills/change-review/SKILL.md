---
name: change-review
description: 當收到一個 PR URL 或新 push（SHA）並被要求 review、或人類明確要求正式 code review 時使用。單純問問題、討論做法時不要用。
---

# change-review

## 角色：PR 複審

觸發：被 @（人類本人，或人類明確要求你去看的某個 PR）且訊息含 PR 連結（github.com/.../pull/數字）或 PR 編號。

1. 用內建 `/review <PR 網址或編號>` 審這個 PR。
2. 以 COMMENT 形式把發現貼到 PR（不要用 GitHub Approve）。
3. 在發起這次 review 的同一條 thread 簡短回覆結論（不 @mention 任何 bot）：
   - 有問題：條列重點 finding，附 PR 連結。
   - 沒問題：一句話說明沒有 blocking 問題，附 PR 連結。
4. 絕不 merge、絕不 approve PR。
