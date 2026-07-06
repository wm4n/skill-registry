---
name: jira-fetch
argument-hint: "[JIRA-ticket-id] [--comments N]"
description: >-
  Fetch a JIRA issue and output structured markdown for downstream agent processing.
  Uses Atlassian Cloud Basic Auth (JIRA_EMAIL + JIRA_TOKEN).
  Output includes title, description, acceptance criteria, sprint, fixVersion, and latest N comments.
  Required env vars: JIRA_TOKEN, JIRA_EMAIL, JIRA_BASE_URL.
  Fallback to manual paste when env vars are missing or API returns an error.
allowed-tools:
  - Bash(curl *)
  - Bash(printf *)
  - Bash(echo *)
  - Bash(jq *)
---

# JIRA Issue Fetch

Fetch a JIRA issue and output structured markdown for the calling agent to continue processing.

## Environment

- JIRA_TOKEN: !`echo "${JIRA_TOKEN:+set}${JIRA_TOKEN:-[not set]}"`
- JIRA_EMAIL: !`echo "${JIRA_EMAIL:+set}${JIRA_EMAIL:-[not set]}"`
- JIRA_BASE_URL: !`echo "${JIRA_BASE_URL:+set}${JIRA_BASE_URL:-[not set]}"`

## Argument Parsing

- `TICKET_ID`: first token from `$ARGUMENTS` (e.g. `JIRA-12345`)
- `COMMENTS_COUNT`: value of `--comments N` if present; defaults to `5`; set to `0` to skip comments

## Phase 1: Validate Environment Variables

If any variable shows `[not set]`, stop immediately and output:

```
Missing required environment variable(s): {list}.
Please provide the content of {TICKET_ID} manually (title, description, acceptance criteria) to continue.
```

## Phase 2: Build Basic Auth Header

```bash
JIRA_AUTH=$(printf "%s:%s" "${JIRA_EMAIL}" "${JIRA_TOKEN}" | base64 -w 0 2>/dev/null \
  || printf "%s:%s" "${JIRA_EMAIL}" "${JIRA_TOKEN}" | base64 | tr -d '\n')
```

Compatibility: `base64 -w 0` (GNU coreutils) falls back to `base64 | tr -d '\n'` (macOS BSD).

## Phase 3: Fetch Issue

```bash
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET \
  "${JIRA_BASE_URL}/rest/api/2/issue/${TICKET_ID}?fields=summary,status,priority,assignee,reporter,labels,fixVersions,description,customfield_10016,customfield_10020,customfield_10014" \
  -H "Authorization: Basic ${JIRA_AUTH}" \
  -H "Content-Type: application/json")

HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
ISSUE_BODY=$(echo "${RESPONSE}" | head -n -1)
```

HTTP status handling:

| Code | Action |
|------|--------|
| 200 | Continue to Phase 4 |
| 401 / 403 | Output: `JIRA authentication failed (HTTP ${HTTP_CODE}). Verify JIRA_TOKEN is a valid Atlassian API token and JIRA_EMAIL matches the token owner.` Stop. |
| 404 | Output: `Ticket ${TICKET_ID} not found (HTTP 404). Verify the ticket key and your access permissions.` Stop. |
| other | Output: `JIRA API returned an unexpected error (HTTP ${HTTP_CODE}).` Stop. |

On any error: prompt the user to paste the ticket content manually.

## Phase 4: Fetch Latest Comments (skip if COMMENTS_COUNT = 0)

```bash
COMMENTS_RESPONSE=$(curl -s -X GET \
  "${JIRA_BASE_URL}/rest/api/2/issue/${TICKET_ID}/comment?maxResults=${COMMENTS_COUNT}&orderBy=-created" \
  -H "Authorization: Basic ${JIRA_AUTH}" \
  -H "Content-Type: application/json")
```

## Phase 5: Output Structured Markdown

Use `jq` to extract fields from `ISSUE_BODY`. For ADF (Atlassian Document Format) fields, concatenate `.content[].content[].text` as plain text. Output `null` fields with their default values below.

```
## JIRA Issue: {TICKET_ID}

**Title:** {fields.summary}
**Status:** {fields.status.name}  **Priority:** {fields.priority.name}
**Assignee:** {fields.assignee.displayName or "Unassigned"}
**Reporter:** {fields.reporter.displayName}
**Labels:** [{fields.labels[] comma-separated, or "none"}]
**Fix Version:** {fields.fixVersions[0].name or "not set"}
**Sprint:** {fields.customfield_10020[0].name or fields.customfield_10014 or "not set"}
**Base Branch Hint:** {Fix Version name (preferred) > Sprint name > "unknown — please confirm base branch with a human"}

### Description
{fields.description as plain text; null → "(no description)"}

### Acceptance Criteria
{fields.customfield_10016 as plain text; null → "(no acceptance criteria)"}

### Latest {COMMENTS_COUNT} Comments
{omit this entire section if COMMENTS_COUNT = 0}

**[{comment.created yyyy-mm-dd}] {comment.author.displayName}**
{comment.body as plain text}

---
{repeat for each comment up to COMMENTS_COUNT}
```
