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

## Usage

After installing, invoke a skill by name:

```
/jira-fetch JIRA-12345
/jira-fetch JIRA-12345 --comments 10
/learn-from-repo
```

`learn-from-repo` runs an interactive init on first use in a repo (Jira settings, branch-pattern detection, module list), then learns incrementally from a checkpoint on later runs. Prerequisites: inside a git repo with a GitHub remote, `gh` authenticated, `jq` installed.

## Required Environment Variables

| Variable | Description |
|----------|-------------|
| `JIRA_TOKEN` | Atlassian API token |
| `JIRA_EMAIL` | Atlassian account email |
| `JIRA_BASE_URL` | JIRA instance URL, e.g. `https://yourorg.atlassian.net` |

`learn-from-repo` reads Jira credentials from env vars whose **names** you register in the target repo's `docs/knowledge/config.json` during init (defaults suggested: `JIRA_EMAIL` / `JIRA_API_TOKEN`); token values never enter the repo.
