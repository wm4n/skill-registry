# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is a **Claude Code plugin marketplace** that distributes reusable agent skills. It contains no application code and no build/test/lint tooling — the "source" is skill definitions (markdown + frontmatter) and two JSON manifests. Skills are consumed by installing the plugin, then invoked by name (e.g. `/jira-fetch JIRA-12345`).

Distribution identifiers (keep these consistent when editing):
- GitHub repo / install slug: `wm4n/skill-registry`
- Marketplace name: `wm4n-skill-registry` (`.claude-plugin/marketplace.json`)
- Plugin name: `skill-registry` (`.claude-plugin/plugin.json`)

## Architecture

Three coordinated pieces:

1. `.claude-plugin/marketplace.json` — marketplace manifest. Lists installable plugins and their `source` (this repo's git URL) and `version`.
2. `.claude-plugin/plugin.json` — the plugin manifest (name, version, author, keywords).
3. `skills/<skill-name>/SKILL.md` — one directory per skill. This is where the actual behavior lives.

`version` appears in **both** `plugin.json` and `marketplace.json`. Bump them together — they must match.

## SKILL.md conventions

Each skill is a single `SKILL.md` with YAML frontmatter followed by phased instructions. Follow the `jira-fetch` skill as the reference pattern:

- **Frontmatter fields**: `name`, `argument-hint` (e.g. `"[JIRA-ticket-id] [--comments N]"`), `description` (multi-line `>-` block — this is what the agent matches on, so make it specific), and `allowed-tools` (a whitelist scoping which Bash commands the skill may run, e.g. `Bash(curl *)`, `Bash(jq *)`).
- **Dynamic command execution**: prefix a shell command with `!` inside backticks to run it and inline the output, e.g. `` !`echo "${JIRA_TOKEN:+set}"` `` for env-var presence checks.
- **Arguments**: parse from the `$ARGUMENTS` variable (first token = primary arg; flags like `--comments N` parsed positionally).
- **Structure**: numbered `## Phase N:` sections that run in order — validate env → build request → fetch → transform → emit structured markdown.
- **Output contract**: skills emit **structured markdown for a calling agent to consume**, not prose for a human. Keep the output template exact.

## Design principles observed in existing skills

When adding or editing skills, preserve these patterns:

- **Fail loud and early, then offer a fallback.** Validate required env vars up front; on any missing var or API error, stop and prompt the user to paste content manually rather than proceeding with bad data.
- **Explicit HTTP/error handling.** Capture status codes and map each (401/403 → auth, 404 → not found, else → generic) to a distinct, actionable message.
- **Cross-platform bash.** Support both GNU coreutils and macOS BSD — e.g. `base64 -w 0 || base64 | tr -d '\n'`. Don't assume GNU-only flags.
- **Secrets via env vars only.** Credentials (`JIRA_TOKEN`, `JIRA_EMAIL`, `JIRA_BASE_URL`) are read from the environment, never hardcoded or committed.

## Adding a new skill

1. Create `skills/<new-skill>/SKILL.md` with frontmatter + phases per the conventions above.
2. Add a row to the **Available Skills** table in `README.md`, and document any new required env vars there.
3. Bump `version` in both `plugin.json` and `marketplace.json`.
