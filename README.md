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

## Usage

After installing, invoke a skill by name:

```
/jira-fetch JIRA-12345
/jira-fetch JIRA-12345 --comments 10
```

## Required Environment Variables

| Variable | Description |
|----------|-------------|
| `JIRA_TOKEN` | Atlassian API token |
| `JIRA_EMAIL` | Atlassian account email |
| `JIRA_BASE_URL` | JIRA instance URL, e.g. `https://yourorg.atlassian.net` |
