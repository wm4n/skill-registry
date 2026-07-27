# skill-registry

Reusable AI agent skills for Claude Code, Codex, and compatible CLI tools.

## Install as a plugin

```bash
claude plugins install wm4n/skill-registry
```

## Add as a marketplace source

```bash
claude plugins marketplace add wm4n/skill-registry
```

## Available Skills

| Skill | Description |
|-------|-------------|
| `jira-fetch` | Fetch a JIRA issue and output structured markdown. Supports Atlassian Cloud Basic Auth. |
| `learn-from-repo` | Build a team knowledge base from a repo's merged PRs (with linked Jira tickets and GitHub issues) — extracts business logic, architecture decisions, and lessons-learnt into `docs/knowledge/`, with human confirmation before every write. |
| `task-splitter` | 判斷功能需求是否過大並遞迴拆成 right-sized 子任務。用 INVEST + rubric 判大小、vertical slice 拆分、多平台採 contract-first，每個葉任務含 Gherkin 驗收與 artifact 串接契約（DAG），交棒 `writing-plans`。 |
| `self-evolution` | Agent self-improvement loop: learns from user corrections (root-cause → prevention rule), retrospects on detours, proposes new skills when it notices repeated work, and detects habit/inertia — persisting lessons to `~/.claude/evolution/` and a capped block in the global `~/.claude/CLAUDE.md`. |
| `mac-disk-cleanup-scan` | macOS 磁碟空間分析（`mac-disk-cleanup` plugin）：唯讀掃描快取、日誌、暫存、垃圾桶、大檔/舊檔、node_modules、npm/pip/gradle/cargo 快取、Docker、Xcode DerivedData/Archives、iOS 備份、Time Machine 本機快照，產生分類 + 大小排序 + 風險徽章 + 可複製清理指令的報告。只掃描、只回報，絕不刪除。 |
| `team-onboarding` | Onboard the bot to a team like a new hire: ingest onboarding material (local folder, pasted text, links, or interactive interview), tier it by severity, and distill it into a global cross-repo profile under `~/.claude/team-profile/` plus an always-on self-check block in `~/.claude/CLAUDE.md`. MUST-NOT rules stay always-on; details are recalled on demand. Never writes before confirmation. |

## Usage

After installing, invoke a skill by name:

```
/jira-fetch JIRA-12345
/jira-fetch JIRA-12345 --comments 10
/learn-from-repo
```

`learn-from-repo` runs an interactive init on first use in a repo (Jira settings, branch-pattern detection, module list), then learns incrementally from a checkpoint on later runs. Prerequisites: inside a git repo with a GitHub remote, `gh` authenticated, `jq` installed.

`self-evolution` is trigger-based rather than slash-invoked: it activates automatically when the user corrects the agent, when a task involved rework, or at task end (a silent quick screen). It maintains its own storage at `~/.claude/evolution/` (created on first trigger) and manages a dedicated lessons block at the end of the global `~/.claude/CLAUDE.md` (max 20 entries; existing content is never touched). New-skill proposals it drafts only take effect after explicit user approval. Instructions are written in Traditional Chinese.

## Required Environment Variables

| Variable | Description |
|----------|-------------|
| `JIRA_TOKEN` | Atlassian API token |
| `JIRA_EMAIL` | Atlassian account email |
| `JIRA_BASE_URL` | JIRA instance URL, e.g. `https://yourorg.atlassian.net` |

`learn-from-repo` reads Jira credentials from env vars whose **names** you register in the target repo's `docs/knowledge/config.json` during init (defaults suggested: `JIRA_EMAIL` / `JIRA_API_TOKEN`); token values never enter the repo.
