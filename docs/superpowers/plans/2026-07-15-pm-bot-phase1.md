# PM Bot Phase 1（感知與發想）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立產品日誌 repo、商店/GitHub 數據蒐集器、PM bot 的完整工作手冊與 prompts，以及 openab（NAS）部署 checklist，讓 PM bot 的每日「蒐集→分析→決定→執行→回報」循環可上線試運行。

**Architecture:** 所有交付物集中在一個新的獨立 git repo（產品日誌 repo），包含：人類/bot 共用的日誌與模板、Python 蒐集器（輸出每日 JSON 快照）、PM bot 的 system prompt 與三種節奏的 prompt（日/週/月）、部署與憑證 checklist。openab 跑在另一台主機上，部署動作由人類照 `bot/DEPLOY.md` 執行。

**Tech Stack:** Python 3.11+（requests、google-auth、PyJWT、cryptography、jsonschema、pytest）、git、GitHub REST API、Google Play Developer Reporting / Android Publisher / GCS API、App Store Connect API、openab（usercron）。

**Spec:** `docs/superpowers/specs/2026-07-15-product-manager-agent-design.md`（skill-registry repo）

## Global Constraints

- **參數表**：以下佔位參數在**開始執行前**必須先向使用者取得實際值，並在產出的所有檔案中替換（計畫內文保留佔位形式）：
  - `$GAME_ORG` / `$GAME_REPO`：遊戲 repo 的 GitHub org 與名稱。journal repo 命名固定為 `$GAME_ORG/$GAME_REPO-journal`。
  - `$ANALYST_BOT`：openab 上需求分析 bot 的 Discord mention 名稱。
  - `$GPLAY_PACKAGE`：Android package name（例 `com.example.game`）。
  - `$ASC_APP_ID`：App Store Connect 的 app 數字 ID。
  - 尚未上架或暫缺的參數：對應來源在 `SOURCES.md` 與 `config.json` 維持非 active，不阻塞其他任務。
- **本機工作路徑**：journal repo 建在 `~/workspace/github/$GAME_REPO-journal`。
- **git 身分**：使用 wm4n 個人帳號（`wmandev@gmail.com`），不用公司帳號。
- **語言**：所有 bot-facing 與人類閱讀的 markdown 內容一律繁體中文。
- **秘密管理**：憑證只走環境變數或掛載檔案路徑（`GITHUB_TOKEN`、`GOOGLE_APPLICATION_CREDENTIALS`、`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY_PATH`、`ASC_VENDOR_NUMBER`），絕不進 repo、config.json 或 prompt。
- **測試指令**：一律在 journal repo 根目錄執行 `python -m pytest tools/tests -v`。
- **蒐集器統一介面**：每個蒐集器模組提供 `collect(config: dict) -> dict`，回傳 `{"status": "ok"|"error", "error": str|None, "data": dict|None}`；任何例外都在模組內捕捉並轉為 `error`，絕不讓例外冒出（對應 spec「絕不腦補缺失數據、fail loud」）。
- **護欄初始值**（寫入 PM_BOT.md，人類可改）：每日新 issue 配額 3；pipeline 在製上限 5；🟡 提案逾時 48 小時；同一來源連續失敗 3 天升級。

---

### Task 1: 產品日誌 repo 骨架與模板

**Files:**
- Create: `~/workspace/github/$GAME_REPO-journal/`（git init）
- Create: `README.md`、`PRODUCT.md`、`METRICS_BASELINE.md`、`SOURCES.md`
- Create: `templates/hypothesis.md`、`templates/decision.md`、`templates/daily-journal.md`
- Create: `metrics/.gitkeep`、`journal/.gitkeep`、`hypotheses/.gitkeep`、`decisions/.gitkeep`

**Interfaces:**
- Consumes: 無（第一個任務）
- Produces: repo 根目錄結構；`SOURCES.md` 的來源註冊表（後續 Task 6 的 `config.json`、Task 8 的 prompts 都引用其來源名稱：`github`、`google_play_metrics`、`google_play_reviews`、`app_store_metrics`、`app_store_reviews`、`in_game_analytics`、`player_report_channel`、`forums`）

- [ ] **Step 1: 建 repo 與目錄**

```bash
mkdir -p ~/workspace/github/$GAME_REPO-journal && cd ~/workspace/github/$GAME_REPO-journal
git init
git config user.name "William Chao" && git config user.email "wmandev@gmail.com"
mkdir -p templates metrics journal hypotheses decisions
touch metrics/.gitkeep journal/.gitkeep hypotheses/.gitkeep decisions/.gitkeep
```

- [ ] **Step 2: 寫 README.md**

```markdown
# $GAME_REPO 產品日誌

PM bot（產品管理 agent）與人類共用的產品狀態 repo。設計依據：skill-registry 的
`docs/superpowers/specs/2026-07-15-product-manager-agent-design.md`。

## 結構
- `PRODUCT.md` — 產品定位與當前策略（人類+bot 共同維護；人類直接編輯即可指導 bot 方向）
- `METRICS_BASELINE.md` — 生命線/成長/終止 三層指標門檻（人類定門檻，bot 對照數據）
- `SOURCES.md` — 訊號來源註冊表（量化數據/質化回饋/開發狀態）
- `metrics/YYYY-MM-DD.json` — 每日指標快照（蒐集器原始輸出，不可手改）
- `journal/YYYY-MM-DD.md` — 每日日誌（分析、行動、理由）
- `hypotheses/H-NNN-*.md` — 假設卡：PM bot 開的每個 issue 都必須掛在一張假設卡上
- `decisions/D-NNN-*.md` — 重大決策紀錄
- `templates/` — 上述文件的模板
- `tools/` — 數據蒐集器（Python）
- `bot/` — PM bot 的 system prompt、prompts 與部署文件

## 慣例
- 假設卡驗證結果只能追加、不可刪改
- 快照缺數據時標 `partial`，分析只用拿得到的部分
- 憑證一律環境變數，絕不進本 repo
```

- [ ] **Step 3: 寫 PRODUCT.md（骨架，人類 onboarding 時填）**

```markdown
# 產品：$GAME_REPO

> 本檔由人類與 PM bot 共同維護。「策略方向」段落的變更屬 🟡 級：bot 需提案、人類同意後才能改。

## 定位（一句話）
（人類填：這是什麼遊戲、解決什麼娛樂需求）

## 目標受眾
（人類填）

## 當前策略方向
（人類填：現階段最重要的一件事，例如「先把 D1 留存做到 40%」）

## 近期焦點（PM bot 每日發想的邊界）
（人類填：例如「只做既有玩法打磨，不開新模式」）
```

- [ ] **Step 4: 寫 METRICS_BASELINE.md（三層骨架，數值上線時共同訂定）**

```markdown
# 指標基準線與門檻

> 門檻由人類訂定與修改，PM bot 只負責誠實對照。數值欄空白代表「待訂」——
> 待訂期間 bot 不得用該指標做重大判斷。留存/DAU 等在遊戲內分析接入前標「待接入」。

## 生命線指標（跌破紅線 → 異常煞車：暫停發想、聚焦修復、通知人類）
| 指標 | 來源 | 紅線 | 備註 |
|---|---|---|---|
| 崩潰率 | google_play_metrics | （待訂） | |
| 商店評分（近 7 日評論均值） | google_play_reviews / app_store_reviews | （待訂） | 整體評分 API 不可得，以近期評論均值近似 |
| DAU | in_game_analytics | （待接入） | |

## 成長指標（假設卡驗證的主要對象）
| 指標 | 來源 | 目標方向 | 備註 |
|---|---|---|---|
| 每日下載 | google_play_metrics / app_store_metrics | 上升 | |
| D1 / D7 留存 | in_game_analytics | （待接入） | |
| 付費轉換 | in_game_analytics | （待接入） | |

## 終止條件（預先承諾；觸發 → bot 必須產出終止建議書，決定權在人類）
（待訂。範例格式：「連續 3 個月下載趨勢下滑，且近 5 張假設卡全部未達標」）

## 護欄參數（人類可調）
- 每日新 issue 配額：3
- pipeline 在製上限（open issues + open PRs 中屬開發中者）：5
- 🟡 提案逾時：48 小時（逾時不執行，日報持續追蹤）
- 來源連續失敗升級門檻：3 天
```

- [ ] **Step 5: 寫 SOURCES.md（訊號來源註冊表）**

```markdown
# 訊號來源註冊表

> PM bot 每日 Collect 步驟依本表拉取所有 `active` 來源。
> 來源缺口比照數據缺口處理：`unavailable` 的來源若被假設卡需要，
> 標準動作是開「建立管道」issue（🟢）或提案建立社群空間（🟡）。
> 機器參數（package name、repo 名等）在 `tools/collect/config.json`。

## 量化數據
| 來源 | 取得方式 | 頻率 | 狀態 |
|---|---|---|---|
| google_play_metrics（下載、崩潰） | API（Developer Reporting + GCS 報表） | 每日 | planned（待憑證，見 docs/CREDENTIALS.md） |
| app_store_metrics（下載、銷售） | API（App Store Connect salesReports） | 每日 | planned（待憑證） |
| in_game_analytics（DAU、留存、事件） | 待接入分析 SDK | — | unavailable（缺口 → 埋點 issue） |

## 質化回饋
| 來源 | 取得方式 | 頻率 | 狀態 |
|---|---|---|---|
| google_play_reviews（商店評論） | API（Android Publisher reviews） | 每日 | planned（待憑證） |
| app_store_reviews（商店評論） | API（customerReviews） | 每日 | planned（待憑證） |
| player_report_channel（玩家回報管道） | 待建立（遊戲內回報/Discord 頻道） | — | unavailable（缺口） |
| forums（論壇/社群討論） | 待建立（Reddit、巴哈姆特等） | — | unavailable（缺口） |

## 開發狀態
| 來源 | 取得方式 | 頻率 | 狀態 |
|---|---|---|---|
| github（issue/PR/merge 狀態） | API（GitHub REST，$GAME_ORG/$GAME_REPO） | 每日 | active |
```

- [ ] **Step 6: 寫三個模板**

`templates/hypothesis.md`：

```markdown
# H-NNN: （一句話假設標題）

- 狀態: draft | blocked-on-instrumentation | active | validating | success | failed | inconclusive
- 建立日期: YYYY-MM-DD
- 假設: 若（改動），則（指標）會在（期間）內（變化幅度）
- 驗證指標: （指標名；必填。對照 SOURCES.md ——目前可觀測: 是/否。否 → 狀態設 blocked-on-instrumentation 並開建立管道 issue）
- 依據: （哪些數據/評論/回報促成這個假設，引用快照日期或評論）
- 對應 issue: #NNN
- 發佈版本/日期: （發佈後填）

## 驗證紀錄（只能追加，不可刪改）
- YYYY-MM-DD: （對照驗證指標的實際數據與結論）
```

`templates/decision.md`：

```markdown
# D-NNN: （決策標題）

- 狀態: proposed | approved | rejected | executed
- 等級: 🟡（提案後執行）| 🔴（只能建議）
- 提案日期: YYYY-MM-DD

## 提案內容
## 數據依據（引用快照/假設卡）
## 人類回覆（日期＋原文摘錄）
## 執行紀錄
```

`templates/daily-journal.md`：

```markdown
# YYYY-MM-DD 日誌

## 數據摘要（引用 metrics/YYYY-MM-DD.json；partial 時明講缺了什麼）
## 質化訊號摘要（評論情緒、新回報議題；來源未 active 時寫「無管道」）
## 分析（與歷史快照比對的趨勢結論）
## 今日行動（每項附理由與數據引用；「今天不需要動作」是合法結論）
## 等待人類（未回覆的 🟡 提案、pipeline 塞住等）
```

- [ ] **Step 7: 建遠端 repo 並 commit push**

```bash
cd ~/workspace/github/$GAME_REPO-journal
git add -A && git commit -m "chore: 初始化產品日誌 repo（結構、註冊表、模板）"
gh repo create $GAME_ORG/$GAME_REPO-journal --private --source . --push
```

Expected: `gh repo view $GAME_ORG/$GAME_REPO-journal` 可看到 repo。

---

### Task 2: Python 底座＋快照 schema＋驗證器

**Files:**
- Create: `tools/requirements.txt`、`tools/__init__.py`、`tools/collect/__init__.py`、`tools/tests/__init__.py`
- Create: `tools/snapshot_schema.json`、`tools/validate_snapshot.py`
- Test: `tools/tests/test_validate_snapshot.py`

**Interfaces:**
- Consumes: Task 1 的 repo 結構
- Produces: `tools/validate_snapshot.py` 的 `validate_file(path: str) -> dict`（回傳解析後 snapshot；schema 不符時 raise `jsonschema.ValidationError`）；snapshot 格式契約：`{"date": "YYYY-MM-DD", "status": "complete"|"partial", "sources": {<name>: {"status": "ok"|"error", "error": str|None, "data": dict|None}}}`——Task 3–6 全部遵守

- [ ] **Step 1: 建底座檔案**

`tools/requirements.txt`：

```
requests>=2.31
google-auth>=2.29
PyJWT>=2.8
cryptography>=42.0
jsonschema>=4.21
pytest>=8.0
```

```bash
cd ~/workspace/github/$GAME_REPO-journal
touch tools/__init__.py tools/collect/__init__.py
mkdir -p tools/tests && touch tools/tests/__init__.py
python3 -m venv .venv && source .venv/bin/activate && pip install -r tools/requirements.txt
echo ".venv/" > .gitignore
```

- [ ] **Step 2: 寫快照 schema**

`tools/snapshot_schema.json`：

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["date", "status", "sources"],
  "additionalProperties": false,
  "properties": {
    "date": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$"},
    "status": {"enum": ["complete", "partial"]},
    "sources": {
      "type": "object",
      "minProperties": 1,
      "additionalProperties": {
        "type": "object",
        "required": ["status", "error", "data"],
        "additionalProperties": false,
        "properties": {
          "status": {"enum": ["ok", "error"]},
          "error": {"type": ["string", "null"]},
          "data": {"type": ["object", "null"]}
        }
      }
    }
  }
}
```

- [ ] **Step 3: 寫失敗測試**

`tools/tests/test_validate_snapshot.py`：

```python
import json
import pytest
from jsonschema import ValidationError
from tools.validate_snapshot import validate_file


def _write(tmp_path, obj):
    p = tmp_path / "snap.json"
    p.write_text(json.dumps(obj), encoding="utf-8")
    return str(p)


def test_valid_snapshot_passes(tmp_path):
    snap = {
        "date": "2026-07-15",
        "status": "partial",
        "sources": {"github": {"status": "ok", "error": None, "data": {"open_issues": []}}},
    }
    assert validate_file(_write(tmp_path, snap))["date"] == "2026-07-15"


def test_missing_sources_fails(tmp_path):
    with pytest.raises(ValidationError):
        validate_file(_write(tmp_path, {"date": "2026-07-15", "status": "complete"}))


def test_bad_source_status_fails(tmp_path):
    snap = {
        "date": "2026-07-15",
        "status": "complete",
        "sources": {"github": {"status": "maybe", "error": None, "data": None}},
    }
    with pytest.raises(ValidationError):
        validate_file(_write(tmp_path, snap))
```

- [ ] **Step 4: 跑測試確認失敗**

Run: `python -m pytest tools/tests/test_validate_snapshot.py -v`
Expected: FAIL（`ModuleNotFoundError: No module named 'tools.validate_snapshot'`）

- [ ] **Step 5: 寫實作**

`tools/validate_snapshot.py`：

```python
"""驗證每日快照是否符合 tools/snapshot_schema.json。

用法: python -m tools.validate_snapshot metrics/2026-07-15.json
"""
import json
import pathlib
import sys

from jsonschema import validate

_SCHEMA_PATH = pathlib.Path(__file__).resolve().parent / "snapshot_schema.json"


def validate_file(path: str) -> dict:
    snapshot = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    schema = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
    validate(snapshot, schema)
    return snapshot


def main() -> None:
    snap = validate_file(sys.argv[1])
    print(f"OK: {sys.argv[1]} date={snap['date']} status={snap['status']}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: 跑測試確認通過**

Run: `python -m pytest tools/tests/test_validate_snapshot.py -v`
Expected: 3 passed

- [ ] **Step 7: Commit**

```bash
git add tools/ .gitignore
git commit -m "feat: 快照 schema 與驗證器（蒐集器輸出契約）"
```

---

### Task 3: GitHub 蒐集器

**Files:**
- Create: `tools/collect/github_status.py`
- Test: `tools/tests/test_github_status.py`

**Interfaces:**
- Consumes: Task 2 的 snapshot source 格式契約
- Produces: `tools.collect.github_status.collect(config: dict) -> dict`，`config = {"repo": "$GAME_ORG/$GAME_REPO"}`，`data = {"open_issues": [...], "open_prs": [...], "merged_last_7d": [...]}`，各項目為 `{"number": int, "title": str, "labels": [str]}`；環境變數 `GITHUB_TOKEN`

- [ ] **Step 1: 寫失敗測試**

`tools/tests/test_github_status.py`：

```python
import datetime
import json

from tools.collect import github_status


class _Resp:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


def test_collect_ok(monkeypatch):
    monkeypatch.setenv("GITHUB_TOKEN", "t")
    recent = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).isoformat()
    old = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=30)).isoformat()

    def fake_get(url, headers=None, params=None, timeout=None):
        if url.endswith("/issues"):
            return _Resp([
                {"number": 1, "title": "bug", "labels": [{"name": "bug"}]},
                {"number": 2, "title": "pr-as-issue", "labels": [], "pull_request": {}},
            ])
        if params and params.get("state") == "open":
            return _Resp([{"number": 3, "title": "wip", "labels": []}])
        return _Resp([
            {"number": 4, "title": "merged-new", "labels": [], "merged_at": recent},
            {"number": 5, "title": "merged-old", "labels": [], "merged_at": old},
            {"number": 6, "title": "closed-unmerged", "labels": [], "merged_at": None},
        ])

    monkeypatch.setattr(github_status.requests, "get", fake_get)
    result = github_status.collect({"repo": "o/r"})
    assert result["status"] == "ok"
    assert [i["number"] for i in result["data"]["open_issues"]] == [1]
    assert [p["number"] for p in result["data"]["open_prs"]] == [3]
    assert [p["number"] for p in result["data"]["merged_last_7d"]] == [4]


def test_collect_error(monkeypatch):
    monkeypatch.setenv("GITHUB_TOKEN", "t")

    def boom(*a, **k):
        raise RuntimeError("api down")

    monkeypatch.setattr(github_status.requests, "get", boom)
    result = github_status.collect({"repo": "o/r"})
    assert result["status"] == "error"
    assert "api down" in result["error"]
    assert result["data"] is None
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m pytest tools/tests/test_github_status.py -v`
Expected: FAIL（module not found）

- [ ] **Step 3: 寫實作**

`tools/collect/github_status.py`：

```python
"""GitHub 開發狀態蒐集器：open issues / open PRs / 近 7 日 merged。"""
import datetime
import os

import requests

_API = "https://api.github.com"


def _headers() -> dict:
    return {
        "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
        "Accept": "application/vnd.github+json",
    }


def _brief(items: list) -> list:
    return [
        {"number": x["number"], "title": x["title"], "labels": [l["name"] for l in x.get("labels", [])]}
        for x in items
    ]


def collect(config: dict) -> dict:
    repo = config["repo"]
    try:
        issues = requests.get(
            f"{_API}/repos/{repo}/issues", headers=_headers(),
            params={"state": "open", "per_page": 100}, timeout=30)
        issues.raise_for_status()
        open_issues = [i for i in issues.json() if "pull_request" not in i]

        pulls = requests.get(
            f"{_API}/repos/{repo}/pulls", headers=_headers(),
            params={"state": "open", "per_page": 100}, timeout=30)
        pulls.raise_for_status()

        closed = requests.get(
            f"{_API}/repos/{repo}/pulls", headers=_headers(),
            params={"state": "closed", "sort": "updated", "direction": "desc", "per_page": 50},
            timeout=30)
        closed.raise_for_status()
        cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=7)
        merged = [
            p for p in closed.json()
            if p.get("merged_at")
            and datetime.datetime.fromisoformat(p["merged_at"].replace("Z", "+00:00")) >= cutoff
        ]
        return {
            "status": "ok",
            "error": None,
            "data": {
                "open_issues": _brief(open_issues),
                "open_prs": _brief(pulls.json()),
                "merged_last_7d": _brief(merged),
            },
        }
    except Exception as exc:  # 任何失敗都轉為 error，不讓例外冒出
        return {"status": "error", "error": str(exc), "data": None}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m pytest tools/tests/test_github_status.py -v`
Expected: 2 passed

- [ ] **Step 5: Commit**

```bash
git add tools/
git commit -m "feat: GitHub 開發狀態蒐集器"
```

---

### Task 4: Google Play 蒐集器＋憑證申辦文件（Google 段）

**Files:**
- Create: `tools/collect/google_play.py`
- Create: `docs/CREDENTIALS.md`（Google 段；Task 5 追加 Apple 段）
- Test: `tools/tests/test_google_play.py`

**Interfaces:**
- Consumes: Task 2 契約
- Produces: `tools.collect.google_play.collect(config)`，`config = {"package_name": "$GPLAY_PACKAGE", "gcs_bucket": "pubsite_prod_rev_<ID>"}`，`data = {"installs_daily": [{"date","installs"}], "crash": [{"date","crash_rate","distinct_users"}], "reviews": [{"date","rating","text"}]}`；純函式 `parse_installs_csv(text) -> list`、`summarize_crash_response(resp: dict) -> list`（供測試與重用）；環境變數 `GOOGLE_APPLICATION_CREDENTIALS`

- [ ] **Step 1: 寫失敗測試（針對純解析函式＋error 路徑）**

`tools/tests/test_google_play.py`：

```python
from tools.collect import google_play


def test_parse_installs_csv():
    text = (
        "Date,Package Name,Daily Device Installs,Daily Device Uninstalls\n"
        "2026-07-13,com.x.g,120,30\n"
        "2026-07-14,com.x.g,150,25\n"
    )
    rows = google_play.parse_installs_csv(text)
    assert rows == [
        {"date": "2026-07-13", "installs": 120},
        {"date": "2026-07-14", "installs": 150},
    ]


def test_summarize_crash_response():
    resp = {
        "rows": [
            {
                "startTime": {"year": 2026, "month": 7, "day": 14},
                "metrics": [
                    {"metric": "crashRate", "decimalValue": {"value": "0.012"}},
                    {"metric": "distinctUsers", "decimalValue": {"value": "340"}},
                ],
            }
        ]
    }
    assert google_play.summarize_crash_response(resp) == [
        {"date": "2026-07-14", "crash_rate": 0.012, "distinct_users": 340}
    ]


def test_collect_error_when_no_credentials(monkeypatch):
    monkeypatch.delenv("GOOGLE_APPLICATION_CREDENTIALS", raising=False)
    result = google_play.collect({"package_name": "com.x.g", "gcs_bucket": "b"})
    assert result["status"] == "error"
    assert result["data"] is None
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m pytest tools/tests/test_google_play.py -v`
Expected: FAIL（module not found）

- [ ] **Step 3: 寫實作**

`tools/collect/google_play.py`：

```python
"""Google Play 蒐集器：下載（GCS 統計報表）、崩潰率（Developer Reporting）、評論（Android Publisher）。"""
import csv
import datetime
import io
import os
import urllib.parse

import requests

_SCOPES = [
    "https://www.googleapis.com/auth/playdeveloperreporting",
    "https://www.googleapis.com/auth/androidpublisher",
    "https://www.googleapis.com/auth/devstorage.read_only",
]


def parse_installs_csv(text: str) -> list:
    rows = []
    for row in csv.DictReader(io.StringIO(text)):
        rows.append({"date": row["Date"], "installs": int(row["Daily Device Installs"])})
    return rows[-14:]


def summarize_crash_response(resp: dict) -> list:
    out = []
    for row in resp.get("rows", []):
        t = row["startTime"]
        date = f"{t['year']:04d}-{t['month']:02d}-{t['day']:02d}"
        metrics = {m["metric"]: float(m["decimalValue"]["value"]) for m in row["metrics"]}
        out.append({
            "date": date,
            "crash_rate": metrics.get("crashRate"),
            "distinct_users": int(metrics.get("distinctUsers", 0)),
        })
    return out


def _session() -> requests.Session:
    import google.auth.transport.requests
    from google.oauth2 import service_account

    creds = service_account.Credentials.from_service_account_file(
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"], scopes=_SCOPES)
    creds.refresh(google.auth.transport.requests.Request())
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {creds.token}"
    return session


def _installs(session, package: str, bucket: str) -> list:
    yyyymm = datetime.date.today().strftime("%Y%m")
    obj = urllib.parse.quote(f"stats/installs/installs_{package}_{yyyymm}_overview.csv", safe="")
    resp = session.get(
        f"https://storage.googleapis.com/storage/v1/b/{bucket}/o/{obj}?alt=media", timeout=60)
    resp.raise_for_status()
    return parse_installs_csv(resp.content.decode("utf-16"))


def _crash(session, package: str) -> list:
    end = datetime.date.today() - datetime.timedelta(days=1)
    start = end - datetime.timedelta(days=6)
    body = {
        "timelineSpec": {
            "aggregationPeriod": "DAILY",
            "startTime": {"year": start.year, "month": start.month, "day": start.day},
            "endTime": {"year": end.year, "month": end.month, "day": end.day},
        },
        "metrics": ["crashRate", "distinctUsers"],
        "pageSize": 14,
    }
    resp = session.post(
        f"https://playdeveloperreporting.googleapis.com/v1beta1/apps/{package}/crashRateMetricSet:query",
        json=body, timeout=60)
    resp.raise_for_status()
    return summarize_crash_response(resp.json())


def _reviews(session, package: str) -> list:
    resp = session.get(
        f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package}/reviews",
        params={"maxResults": 50}, timeout=60)
    resp.raise_for_status()
    out = []
    for review in resp.json().get("reviews", []):
        comment = review["comments"][0]["userComment"]
        out.append({
            "date": datetime.datetime.fromtimestamp(
                int(comment["lastModified"]["seconds"]), tz=datetime.timezone.utc).date().isoformat(),
            "rating": comment["starRating"],
            "text": comment.get("text", ""),
        })
    return out


def collect(config: dict) -> dict:
    try:
        session = _session()
        return {
            "status": "ok",
            "error": None,
            "data": {
                "installs_daily": _installs(session, config["package_name"], config["gcs_bucket"]),
                "crash": _crash(session, config["package_name"]),
                "reviews": _reviews(session, config["package_name"]),
            },
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc), "data": None}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m pytest tools/tests/test_google_play.py -v`
Expected: 3 passed

- [ ] **Step 5: 寫 docs/CREDENTIALS.md（Google 段）**

```markdown
# 商店 API 憑證申辦（人類執行）

> 憑證檔案放在 openab 主機上、掛載進 PM bot 容器；路徑用環境變數傳入。絕不進本 repo。

## Google Play（google_play_metrics / google_play_reviews）

1. 到 Google Cloud Console 建（或選）一個專案，啟用 **Google Play Android Developer API**、
   **Google Play Developer Reporting API**、**Cloud Storage JSON API**。
2. 建 service account，下載 JSON 金鑰 → 放到 openab 主機（例 `/secrets/gplay-sa.json`）。
3. 到 Play Console →「使用者與權限」→ 邀請該 service account 的 email，
   授予「查看應用程式資訊」與「查看財務數據」權限。
4. 到 Play Console →「下載報表」頁面找到 Cloud Storage URI（`gs://pubsite_prod_rev_<ID>/`），
   `pubsite_prod_rev_<ID>` 即 `config.json` 的 `gcs_bucket`。
5. 環境變數：`GOOGLE_APPLICATION_CREDENTIALS=/secrets/gplay-sa.json`。
6. 驗證：在 PM bot 容器內跑
   `python -m tools.collect.run_daily --only google_play_metrics`，快照該來源 status=ok。
7. 完成後把 `SOURCES.md` 中 google_play_metrics / google_play_reviews 改為 `active`，
   並把兩者加入 `tools/collect/config.json` 的 `active_sources`。
```

- [ ] **Step 6: Commit**

```bash
git add tools/ docs/
git commit -m "feat: Google Play 蒐集器與憑證申辦文件"
```

---

### Task 5: App Store Connect 蒐集器＋憑證文件（Apple 段）

**Files:**
- Create: `tools/collect/app_store.py`
- Modify: `docs/CREDENTIALS.md`（追加 Apple 段）
- Test: `tools/tests/test_app_store.py`

**Interfaces:**
- Consumes: Task 2 契約
- Produces: `tools.collect.app_store.collect(config)`，`config = {"app_id": "$ASC_APP_ID"}`，`data = {"units_yesterday": int|None, "sales_note": str|None, "reviews": [{"date","rating","title","text"}]}`；純函式 `parse_sales_tsv(raw: bytes) -> int`；環境變數 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY_PATH`、`ASC_VENDOR_NUMBER`

- [ ] **Step 1: 寫失敗測試**

`tools/tests/test_app_store.py`：

```python
import gzip

from tools.collect import app_store


def _gz(text: str) -> bytes:
    return gzip.compress(text.encode("utf-8"))


def test_parse_sales_tsv_sums_app_units():
    tsv = (
        "Provider\tSKU\tProduct Type Identifier\tUnits\n"
        "APPLE\tg1\t1\t3\n"
        "APPLE\tg1\t1F\t2\n"
        "APPLE\tg1.iap\tIA1\t9\n"  # IAP 不算下載
    )
    assert app_store.parse_sales_tsv(_gz(tsv)) == 5


def test_collect_error_without_env(monkeypatch):
    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH", "ASC_VENDOR_NUMBER"):
        monkeypatch.delenv(var, raising=False)
    result = app_store.collect({"app_id": "123"})
    assert result["status"] == "error"
    assert result["data"] is None
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `python -m pytest tools/tests/test_app_store.py -v`
Expected: FAIL（module not found）

- [ ] **Step 3: 寫實作**

`tools/collect/app_store.py`：

```python
"""App Store Connect 蒐集器：昨日下載（salesReports）、最新評論（customerReviews）。"""
import csv
import datetime
import gzip
import io
import os
import time

import jwt
import requests

_API = "https://api.appstoreconnect.apple.com"
# 下載量只計 App 安裝相關的 Product Type（1=App, 1F/1T=Universal/iPad, F1=免費更新裝置）
_APP_UNIT_TYPES = {"1", "1F", "1T", "F1"}


def parse_sales_tsv(raw: bytes) -> int:
    text = gzip.decompress(raw).decode("utf-8")
    total = 0
    for row in csv.DictReader(io.StringIO(text), delimiter="\t"):
        if row["Product Type Identifier"].strip() in _APP_UNIT_TYPES:
            total += int(float(row["Units"]))
    return total


def _token() -> str:
    with open(os.environ["ASC_PRIVATE_KEY_PATH"], encoding="utf-8") as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})


def _sales(headers: dict) -> tuple:
    yesterday = (datetime.date.today() - datetime.timedelta(days=1)).isoformat()
    resp = requests.get(
        f"{_API}/v1/salesReports", headers=headers, timeout=60,
        params={
            "filter[frequency]": "DAILY",
            "filter[reportDate]": yesterday,
            "filter[reportSubType]": "SUMMARY",
            "filter[reportType]": "SALES",
            "filter[vendorNumber]": os.environ["ASC_VENDOR_NUMBER"],
        })
    if resp.status_code == 404:  # 報表尚未產生（常見延遲），不算來源失敗
        return None, f"{yesterday} 報表尚未產生"
    resp.raise_for_status()
    return parse_sales_tsv(resp.content), None


def _reviews(headers: dict, app_id: str) -> list:
    resp = requests.get(
        f"{_API}/v1/apps/{app_id}/customerReviews", headers=headers, timeout=60,
        params={"limit": 50, "sort": "-createdDate"})
    resp.raise_for_status()
    out = []
    for item in resp.json().get("data", []):
        attr = item["attributes"]
        out.append({
            "date": attr["createdDate"][:10],
            "rating": attr["rating"],
            "title": attr.get("title") or "",
            "text": attr.get("body") or "",
        })
    return out


def collect(config: dict) -> dict:
    try:
        headers = {"Authorization": f"Bearer {_token()}"}
        units, note = _sales(headers)
        return {
            "status": "ok",
            "error": None,
            "data": {
                "units_yesterday": units,
                "sales_note": note,
                "reviews": _reviews(headers, config["app_id"]),
            },
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc), "data": None}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `python -m pytest tools/tests/test_app_store.py -v`
Expected: 2 passed

- [ ] **Step 5: docs/CREDENTIALS.md 追加 Apple 段**

在檔尾追加：

```markdown
## App Store Connect（app_store_metrics / app_store_reviews）

1. App Store Connect →「使用者與存取權」→「整合」→「App Store Connect API」→
   建一組 **團隊金鑰**，角色選「財務」（銷售報表需要）。記下 **Key ID** 與 **Issuer ID**，
   下載 `.p8` 私鑰（只能下載一次）→ 放到 openab 主機（例 `/secrets/asc-key.p8`）。
2. Vendor Number：App Store Connect →「付款與財務報表」左上角的供應商編號。
3. App ID：App Store Connect → App →「App 資訊」→ Apple ID（數字）。填入 `config.json` 的 `app_store.app_id`。
4. 環境變數：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_PRIVATE_KEY_PATH=/secrets/asc-key.p8`、`ASC_VENDOR_NUMBER`。
5. 驗證：`python -m tools.collect.run_daily --only app_store_metrics`，快照該來源 status=ok。
6. 完成後把 `SOURCES.md` 的 app_store_metrics / app_store_reviews 改為 `active`，
   並加入 `config.json` 的 `active_sources`。
```

- [ ] **Step 6: Commit**

```bash
git add tools/ docs/
git commit -m "feat: App Store Connect 蒐集器與憑證文件"
```

---

### Task 6: 每日蒐集 orchestrator（run_daily）＋config

**Files:**
- Create: `tools/collect/run_daily.py`、`tools/collect/config.json`
- Test: `tools/tests/test_run_daily.py`

**Interfaces:**
- Consumes: Task 3–5 的 `collect(config)` 介面、Task 2 的 schema 與 `validate_file`
- Produces: CLI `python -m tools.collect.run_daily [--only <source>]` → 寫 `metrics/YYYY-MM-DD.json` 並在 stdout 印出各來源狀態（PM bot 直接讀 stdout）；`build_snapshot(config, collectors, today) -> dict`（依賴注入供測試）。**來源名 → 模組對映**：`google_play_metrics` 與 `google_play_reviews` 共用 `google_play` 模組、`app_store_metrics` 與 `app_store_reviews` 共用 `app_store` 模組（同一 API 憑證一次拉齊，快照 source key 用模組名 `github`/`google_play`/`app_store`）

- [ ] **Step 1: 寫 config.json**

`tools/collect/config.json`（非秘密參數；`active_sources` 初期只有 github，憑證辦好後由 CREDENTIALS.md 步驟加入其他來源）：

```json
{
  "active_sources": ["github"],
  "github": {"repo": "$GAME_ORG/$GAME_REPO"},
  "google_play": {"package_name": "$GPLAY_PACKAGE", "gcs_bucket": "pubsite_prod_rev_TODO_FILL_ON_CREDENTIAL_SETUP"},
  "app_store": {"app_id": "$ASC_APP_ID"}
}
```

- [ ] **Step 2: 寫失敗測試**

`tools/tests/test_run_daily.py`：

```python
from tools.collect.run_daily import build_snapshot


def _ok(config):
    return {"status": "ok", "error": None, "data": {"x": 1}}


def _err(config):
    return {"status": "error", "error": "boom", "data": None}


def test_all_ok_is_complete():
    config = {"active_sources": ["github"], "github": {"repo": "o/r"}}
    snap = build_snapshot(config, collectors={"github": _ok}, today="2026-07-15")
    assert snap["status"] == "complete"
    assert snap["date"] == "2026-07-15"
    assert snap["sources"]["github"]["status"] == "ok"


def test_any_error_is_partial():
    config = {"active_sources": ["github", "google_play"], "github": {}, "google_play": {}}
    snap = build_snapshot(config, collectors={"github": _ok, "google_play": _err}, today="2026-07-15")
    assert snap["status"] == "partial"
    assert snap["sources"]["google_play"]["error"] == "boom"


def test_source_alias_maps_to_module():
    config = {"active_sources": ["google_play_metrics", "google_play_reviews"], "google_play": {}}
    snap = build_snapshot(config, collectors={"google_play": _ok}, today="2026-07-15")
    # 兩個 alias 共用同一模組，快照只有一個 google_play key，只呼叫一次
    assert list(snap["sources"].keys()) == ["google_play"]
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `python -m pytest tools/tests/test_run_daily.py -v`
Expected: FAIL（module not found）

- [ ] **Step 4: 寫實作**

`tools/collect/run_daily.py`：

```python
"""每日蒐集 orchestrator：依 config.active_sources 呼叫各蒐集器，寫入 metrics/YYYY-MM-DD.json。

用法: python -m tools.collect.run_daily [--only <source>]
stdout 摘要供 PM bot 直接閱讀；partial 時 exit code 仍為 0（缺數據要揭露、不算執行失敗）。
"""
import argparse
import datetime
import json
import pathlib
import sys

from jsonschema import validate

# SOURCES.md 來源名 → 蒐集器模組名（同模組的來源共用一次呼叫）
_SOURCE_TO_MODULE = {
    "github": "github_status",
    "google_play_metrics": "google_play",
    "google_play_reviews": "google_play",
    "app_store_metrics": "app_store",
    "app_store_reviews": "app_store",
}
_MODULE_KEY = {"github_status": "github", "google_play": "google_play", "app_store": "app_store"}

_ROOT = pathlib.Path(__file__).resolve().parents[2]


def _default_collectors() -> dict:
    from tools.collect import app_store, github_status, google_play
    return {"github": github_status.collect, "google_play": google_play.collect, "app_store": app_store.collect}


def build_snapshot(config: dict, collectors: dict | None = None, today: str | None = None) -> dict:
    collectors = collectors or _default_collectors()
    today = today or datetime.date.today().isoformat()
    modules = []
    for source in config["active_sources"]:
        key = _MODULE_KEY[_SOURCE_TO_MODULE[source]]
        if key not in modules:
            modules.append(key)
    sources = {key: collectors[key](config.get(key, {})) for key in modules}
    status = "complete" if all(s["status"] == "ok" for s in sources.values()) else "partial"
    return {"date": today, "status": status, "sources": sources}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="只跑單一來源（驗證憑證用）")
    args = parser.parse_args()

    config = json.loads((_ROOT / "tools/collect/config.json").read_text(encoding="utf-8"))
    if args.only:
        config["active_sources"] = [args.only]

    snapshot = build_snapshot(config)
    schema = json.loads((_ROOT / "tools/snapshot_schema.json").read_text(encoding="utf-8"))
    validate(snapshot, schema)

    out = _ROOT / "metrics" / f"{snapshot['date']}.json"
    out.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"快照已寫入 {out.relative_to(_ROOT)}（status={snapshot['status']}）")
    for name, s in snapshot["sources"].items():
        line = f"  {name}: {s['status']}"
        if s["error"]:
            line += f"（{s['error']}）"
        print(line)
    sys.exit(0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: 跑測試確認通過（全部）**

Run: `python -m pytest tools/tests -v`
Expected: 全部通過（validate 3 + github 2 + google_play 3 + app_store 2 + run_daily 3 = 13 passed）

- [ ] **Step 6: 端到端煙霧測試（真實 GitHub API）**

```bash
export GITHUB_TOKEN=<wm4n 的 token>
python -m tools.collect.run_daily
cat metrics/$(date +%F).json
python -m tools.validate_snapshot metrics/$(date +%F).json
```

Expected: 快照存在、`github` source 為 ok、驗證印出 OK。**測試產生的快照不要 commit**（`git checkout -- metrics/` 或直接刪除）。

- [ ] **Step 7: Commit**

```bash
git add tools/
git commit -m "feat: 每日蒐集 orchestrator 與來源設定"
```

---

### Task 7: PM bot 核心手冊（PM_BOT.md）

**Files:**
- Create: `bot/PM_BOT.md`

**Interfaces:**
- Consumes: Task 1 的模板與註冊表、Task 6 的 CLI
- Produces: PM bot 的 system prompt 本體（openab 掛給 agent 的核心指示）；Task 8 的三個 prompt 都以「你已載入 PM_BOT.md 的身分與規則」為前提

- [ ] **Step 1: 寫 bot/PM_BOT.md**

```markdown
# PM Bot — 產品管理 agent 核心手冊

你是 $GAME_REPO 的產品管理 agent，跑在 openab 上，透過 Discord 溝通。
你的唯一目標：**用數據驅動的假設實驗讓產品成長；當產品觸及預先承諾的終止條件時，誠實備齊材料建議終止。**

## 你的邊界（永遠成立）
- 你不寫程式、不做規格細節。你只產出「意圖與方向」層級的 GitHub issue，
  細節規格由 @$ANALYST_BOT 負責。
- 你的一切判斷必須引用數據（快照日期＋指標）或質化訊號（評論/回報原文），可回溯查證。
- 缺數據就明講缺什麼，**絕不腦補**。「今天不需要動作」是合法結論，不硬找事做。
- 工作目錄是產品日誌 repo（$GAME_ORG/$GAME_REPO-journal）。動工前先 `git pull`，寫完 journal/假設卡後 commit + push。

## 權限三級
### 🟢 自主執行（做完在日報揭露）
開 issue（掛 `pm-bot` 標籤）、調整 issue 優先序/標籤、關閉自己開的過時 issue、
mention @$ANALYST_BOT 啟動 pipeline、更新產品日誌、產出分析報告。
### 🟡 提案後執行（Discord 提案 → 人類明確回覆同意才動；記錄到 decisions/）
改 PRODUCT.md 策略段落、單日超過 issue 配額、任何對外內容（商店文案、社群公告、行銷素材）。
### 🔴 只能建議、永遠不執行
終止產品（只產出終止建議書）、任何花錢的事、刪除性操作（關別人開的 issue、刪 journal 歷史）。

## 護欄（數值以 METRICS_BASELINE.md 的「護欄參數」為準）
1. **每日 issue 配額**：預設 3。超過 → 剩餘的走 🟡 提案。
2. **pipeline 感知**：開新 issue 前看快照的 github 區塊；open issues（開發類）＋ open PRs ≥ 上限（預設 5）
   → 今天不餵新 issue，改在日報提醒「pipeline 塞住，等 merge」。
3. **提案逾時**：🟡 提案 48 小時無回應 → 不視為默許、不執行，改在日報「等待人類」持續追蹤。
4. **異常煞車**：任何生命線指標跌破紅線（或紅線待訂但數據明顯異常，如崩潰率倍增、評分驟降）
   → 當日暫停發想新功能，只開修復 issue，並在 Discord 明確 @ 人類。

## 假設卡規則（成長迴圈的核心）
- 你開的**每一個** issue 都必須掛在一張假設卡上（`hypotheses/H-NNN-<slug>.md`，用 templates/hypothesis.md）。
- 每張假設卡**必須宣告驗證指標**。對照 SOURCES.md：
  - 指標可觀測 → 狀態 `active`。
  - 指標不可觀測 → 狀態 `blocked-on-instrumentation`，並開「建立數據管道/回報管道」issue（🟢；
    需要建立對外社群空間則走 🟡 提案）。這是標準流程，不是特例。
- 對應功能發佈後進入 `validating`，在週結算時對照指標寫驗證紀錄（只能追加）。

## 質化訊號是一等公民
- 評論/回報中的明確 bug 或抱怨 → 直接開修復 issue（🟢）。
- 重複出現的願望與痛點 → 記為假設卡的「依據」。
- 日報必含質化摘要（今日評論情緒、新回報議題）。

## 數據操作
- 蒐集：在 journal repo 根目錄跑 `python -m tools.collect.run_daily`，讀 stdout 與當日快照。
- 快照 status=partial → 日報明講缺哪個來源與原因；分析只用拿得到的部分。
- 同一來源連續 3 天 error → 在 Discord @ 人類。
- 趨勢比對用 metrics/ 的歷史快照檔，不憑記憶。

## 節奏
- 每日：日報（只陳述數據與短期趨勢，不做生死判斷）→ prompts/daily.md
- 每週一：週報（假設驗證結算）→ prompts/weekly.md
- 每月 1 日:月評（四擋健康度）→ prompts/monthly.md
```

- [ ] **Step 2: 檢查必要段落齊全**

Run: `grep -c "🟢\|🟡\|🔴" bot/PM_BOT.md`（≥3）；`grep -n "blocked-on-instrumentation\|絕不腦補\|配額\|48 小時" bot/PM_BOT.md`
Expected: 全部命中。

- [ ] **Step 3: Commit**

```bash
git add bot/PM_BOT.md
git commit -m "feat: PM bot 核心手冊（身分、權限、護欄、假設卡規則）"
```

---

### Task 8: 三個節奏 prompt（daily / weekly / monthly）

**Files:**
- Create: `bot/prompts/daily.md`、`bot/prompts/weekly.md`、`bot/prompts/monthly.md`

**Interfaces:**
- Consumes: Task 7 的 PM_BOT.md（身分前提）、Task 6 的 CLI、Task 1 的模板
- Produces: 三個可被 openab cron 直接引用的 prompt 檔（cron 訊息內容即「讀取並執行 bot/prompts/<X>.md」）

- [ ] **Step 1: 寫 bot/prompts/daily.md**

```markdown
# 每日循環（依 PM_BOT.md 的身分與規則執行）

1. **同步**：`git pull`。
2. **蒐集**：`python -m tools.collect.run_daily`。讀 stdout 與 `metrics/今日.json`。
   status=partial → 記下缺哪個來源；某來源連續 3 天 error → 本日日報 @ 人類。
3. **分析**：與近 7/14 日快照比對趨勢；檢查 `hypotheses/` 中 `validating` 的卡片有無可更新的數據；
   讀質化訊號（評論），歸納情緒與重複主題。
4. **決定**（依序檢查）：
   a. 異常煞車條件（PM_BOT.md 護欄 4）→ 觸發則今日只做修復與通知。
   b. pipeline 感知（護欄 2）→ 塞住則今日不開新 issue。
   c. 從分析產出候選行動，每項標 🟢/🟡/🔴 與理由；🟢 的 issue 受每日配額限制。
   d. 沒有值得做的事 → 結論「今天不需要動作」。
5. **執行**：
   - 新假設 → 建假設卡（templates/hypothesis.md，編號接續現有最大 H-NNN）→
     `gh issue create --repo $GAME_ORG/$GAME_REPO --label pm-bot` （issue 內文引用假設卡）→
     在 Discord mention @$ANALYST_BOT 帶上 issue 連結啟動 pipeline。
   - 🟡 事項 → 在 Discord 發提案並建 decisions/ 紀錄（狀態 proposed）。
6. **回報**：寫 `journal/今日.md`（templates/daily-journal.md），commit + push（訊息格式
   `journal: YYYY-MM-DD 日誌`），然後在 Discord 頻道發日報，格式：

   **📊 [$GAME_REPO] YYYY-MM-DD 日報**
   - 數據：（下載/崩潰/評分的當日值與 7 日趨勢；partial 時：⚠️ 今日缺 <來源>（原因））
   - 質化：（評論情緒、新回報議題；無管道則略）
   - 行動：（今日開的 issue / 提案，各附一句理由；或「今天不需要動作」）
   - 等待人類：（未回覆的 🟡 提案含已等待時數、pipeline 狀態提醒）
```

- [ ] **Step 2: 寫 bot/prompts/weekly.md**

```markdown
# 週結算（每週一，依 PM_BOT.md 執行；先跑完當日 daily.md 再做本項）

1. 讀本週 7 天的快照與 journal。
2. **假設結算**：逐張檢查 `validating` 的假設卡——對照驗證指標的實際數據，
   在卡片追加驗證紀錄並更新狀態（success / failed / inconclusive）。數據還不足 → 保持 validating 並註明。
3. **學習沉澱**：從本週 success/failed 的卡片歸納「學到什麼」，寫進本週最後一天的 journal。
4. 在 Discord 發週報：

   **📈 [$GAME_REPO] 第 NN 週 週報**
   - 本週實驗結算：（每張卡一行：H-NNN 假設 → 結果與數據）
   - 學到什麼：（1-3 條）
   - 下週方向：（基於 PRODUCT.md 策略與本週學習）
   - 數據週覽：（關鍵指標的週對週變化）
```

- [ ] **Step 3: 寫 bot/prompts/monthly.md**

```markdown
# 月度健康總評（每月 1 日，依 PM_BOT.md 執行；先跑完當日 daily.md 再做本項）

1. 讀整月快照、journal、假設卡與 METRICS_BASELINE.md。
2. 對照三層指標，輸出四擋結論之一：
   `健康成長` / `持平觀察` / `衰退警戒` / `建議終止評估`。
   判斷必須逐條引用門檻與實際數據；門檻「待訂」的指標明講不納入判斷。
3. 後兩擋（衰退警戒 / 建議終止評估）→ 在 Discord 明確 @ 人類。
4. **終止條件觸發時**（METRICS_BASELINE.md 的終止條件成立）→ 產出終止建議書
   `decisions/D-NNN-termination-proposal.md`（🔴：只能建議），必含四節：
   數據論證／已嘗試假設清單與結果／剩餘選項及不建議的理由／終止方式選項（下架、停更維持、開源、出售）。
5. **防呆**：終止條件未觸發 → 不得建議終止、不重複嘮叨；月評聚焦成長。
6. 在 Discord 發月評：

   **🏥 [$GAME_REPO] YYYY-MM 健康總評：<四擋之一>**
   - 生命線：（逐指標：值 vs 紅線）
   - 成長：（逐指標：月趨勢；本月實驗成功率）
   - 結論與下月主軸
```

- [ ] **Step 4: 一致性檢查**

Run: `grep -rn "H-NNN\|D-NNN\|run_daily\|ANALYST_BOT" bot/prompts/`
Expected: 名稱與 Task 1/6/7 定義一致（模板檔名、CLI 指令、mention 名）。

- [ ] **Step 5: Commit**

```bash
git add bot/prompts/
git commit -m "feat: 日/週/月三個節奏 prompt"
```

---

### Task 9: 部署與驗收文件（DEPLOY.md）

**Files:**
- Create: `bot/DEPLOY.md`

**Interfaces:**
- Consumes: Task 1–8 的全部產出
- Produces: 人類在 openab 主機上照做的部署 checklist ＋ Phase 1 驗收標準

- [ ] **Step 1: 寫 bot/DEPLOY.md**

```markdown
# PM Bot 部署（openab 主機上人類執行）

> openab 的 config 鍵名以部署主機上該版本的 `docs/cronjob.md`、`docs/` 及既有 bot 設定為準；
> 下方片段是內容意圖，鍵名請比照既有 bot 的寫法調整。

## 1. 前置
- [ ] journal repo 已建立且最新（$GAME_ORG/$GAME_REPO-journal）
- [ ] 在 openab 主機 clone journal repo 到 PM bot 的 workspace 掛載目錄
- [ ] 容器內裝 Python 3.11+ 與 `pip install -r tools/requirements.txt`
- [ ] PM bot 有 git 身分與 push 權限（journal repo）、`gh` 已登入（可對 $GAME_ORG/$GAME_REPO 開 issue）
- [ ] 環境變數注入容器：`GITHUB_TOKEN`（商店憑證辦好後再加 Google/Apple 的，見 docs/CREDENTIALS.md）

## 2. openab bot 註冊
- [ ] 在 openab config 新增 agent `pm-bot`，system prompt 指向（或貼入）`bot/PM_BOT.md`
- [ ] Discord：建立（或選定）產品管理頻道，pm-bot 加入
- [ ] openab 訊息權限：pm-bot 可 mention @$ANALYST_BOT 與人類；
      開發/review bot 不需要接收 pm-bot 以外的新權限（維持既有 pipeline 分工）

## 3. 排程（usercron，熱重載）
在 pm-bot 的 `cronjob.toml` 新增三條（鍵名比照主機上的 docs/cronjob.md）：

    # 每日 09:00 日循環
    schedule = "0 9 * * *"
    prompt = "讀取 workspace 中 bot/prompts/daily.md 並照做"

    # 每週一 09:30 週結算
    schedule = "30 9 * * 1"
    prompt = "讀取 bot/prompts/weekly.md 並照做"

    # 每月 1 日 10:00 月評
    schedule = "0 10 1 * *"
    prompt = "讀取 bot/prompts/monthly.md 並照做"

## 4. Onboarding（首次上線，人類＋bot 一起）
- [ ] 人類填 PRODUCT.md（定位、受眾、策略方向、近期焦點）
- [ ] 人類與 bot 用第一週實際數據訂 METRICS_BASELINE.md 的紅線與終止條件
- [ ] 對 pm-bot 手動發一次「讀取 bot/prompts/daily.md 並照做」做監督試跑

## 5. 驗收（對應 spec 的 Phase 1 成功標準）
- [ ] 試跑後：`metrics/當日.json` 已 commit、`journal/當日.md` 已 commit、Discord 有日報
- [ ] 日報引用了具體數據（快照日期＋指標），partial 時有明講缺什麼
- [ ] bot 開的 issue 掛了 `pm-bot` 標籤且對應一張假設卡；@$ANALYST_BOT 有被觸發
- [ ] 單日 issue 數 ≤ 配額 3
- [ ] 連續兩週觀察：(a) 日報讓人類「更了解產品」；(b) pm-bot 開的 issue 至少一半被認可進入開發
- [ ] 未達標 → 回頭調整 PM_BOT.md / prompts，不進 Phase 2
```

- [ ] **Step 2: Commit push**

```bash
git add bot/DEPLOY.md
git commit -m "docs: 部署與 Phase 1 驗收 checklist"
git push
```

---

## Self-Review 紀錄

- **Spec 覆蓋**：每日五步循環（Task 6/8）、訊號來源註冊表與質化一等公民（Task 1/7/8）、數據缺口偵測（Task 7 假設卡規則）、journal repo 結構（Task 1）、三級權限與四護欄（Task 7）、三層節奏與四擋月評、終止建議書（Task 8）、錯誤處理 partial/3 天升級/心跳（Task 6/8）、憑證 env-only（Global Constraints、Task 4/5）、usercron（Task 9）、Phase 1 成功標準（Task 9 驗收）。spec 的 `SOURCES.md`、`METRICS_BASELINE.md`、模板均有對應任務。
- **佔位掃描**：`$GAME_ORG` 等為執行前參數替換（Global Constraints 明定），非未決事項；門檻「待訂」為 spec 明文設計。config.json 的 `gcs_bucket` TODO 值由 CREDENTIALS.md 步驟 4 補上，有明確歸屬。
- **型別/命名一致性**：`collect(config)` 契約、snapshot 格式、來源名（SOURCES.md ↔ config.json ↔ run_daily 對映表）、`pm-bot` 標籤、H-NNN/D-NNN 編號、CLI 指令在各任務間已核對一致。
