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
  - Bash(node *)
---

# JIRA Issue Fetch

Fetch a JIRA issue and output structured markdown for the calling agent to continue processing.

## Required Environment Variables

- `JIRA_TOKEN` — Atlassian API token
- `JIRA_EMAIL` — Atlassian account email (must be the token owner)
- `JIRA_BASE_URL` — JIRA instance URL, e.g. `https://yourorg.atlassian.net`

> Do **not** read these with skill-frontmatter inline execution (`` !`...` ``). The
> permission layer blocks that path at load time because it contains `${...}`
> expansion, and the skill never starts. Check the variables inside Phase 1 as a
> normal Bash step instead.

## JSON parsing

Parse all JSON responses with `node` (`node -e`). It is the assumed baseline on
target machines. Do **not** assume `jq`, `python3`, or GNU-only coreutils flags
(`head -n -1`, `base64 -w 0`) are available — the snippets below avoid them all.

## Argument Parsing

- `TICKET_ID`: first token from `$ARGUMENTS` (e.g. `JIRA-12345`)
- `COMMENTS_COUNT`: value of `--comments N` if present; defaults to `5`; set to `0` to skip comments

## Phase 1: Validate Environment Variables

Run this check. `${VAR:+set}` prints `set` when the variable is non-empty and prints
nothing otherwise — it never reveals the value:

```bash
echo "JIRA_TOKEN: ${JIRA_TOKEN:+set}"
echo "JIRA_EMAIL: ${JIRA_EMAIL:+set}"
echo "JIRA_BASE_URL: ${JIRA_BASE_URL:+set}"
```

A blank value after the colon means that variable is **not set**. If any variable
is not set, stop immediately and output:

```
Missing required environment variable(s): {list}.
Please provide the content of {TICKET_ID} manually (title, description, acceptance criteria) to continue.
```

## Phase 2: Fetch and Render the Issue

Let curl do Basic Auth with `-u` (no manual base64 needed), and append the HTTP
status code so `node` can split body from status in one pass:

```bash
RESPONSE=$(curl -s -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -w '\n%{http_code}' \
  "${JIRA_BASE_URL}/rest/api/2/issue/${TICKET_ID}?fields=summary,status,priority,assignee,reporter,labels,fixVersions,description,customfield_10016,customfield_10020,customfield_10014" \
  -H "Content-Type: application/json")
```

Render it with `node`. If the output starts with `ERROR:`, relay that message to
the user, prompt them to paste the ticket content manually, and stop:

```bash
printf '%s' "$RESPONSE" | node -e '
const raw = require("fs").readFileSync(0, "utf8");
const nl = raw.lastIndexOf("\n");
const status = raw.slice(nl + 1).trim();
const body = raw.slice(0, nl);
if (status !== "200") {
  const msg = {
    "401": "JIRA authentication failed (HTTP 401). Verify JIRA_TOKEN is a valid Atlassian API token and JIRA_EMAIL matches the token owner.",
    "403": "JIRA authentication failed (HTTP 403). Verify JIRA_TOKEN is a valid Atlassian API token and JIRA_EMAIL matches the token owner.",
    "404": "Ticket not found (HTTP 404). Verify the ticket key and your access permissions."
  }[status] || ("JIRA API returned an unexpected error (HTTP " + status + ").");
  console.log("ERROR: " + msg);
  process.exit(0);
}
// ADF (Atlassian Document Format) or plain string -> plain text
function txt(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (Array.isArray(v)) return v.map(txt).join("");
  let s = v.text || "";
  if (v.content) s += txt(v.content);
  if (v.type === "paragraph") s += "\n";
  return s;
}
const d = JSON.parse(body);
const f = d.fields || {};
const labels = (f.labels || []).join(", ") || "none";
const fixv = (f.fixVersions && f.fixVersions[0] && f.fixVersions[0].name) || "not set";
const sprint = (f.customfield_10020 && f.customfield_10020[0] && f.customfield_10020[0].name) || f.customfield_10014 || "not set";
const base = fixv !== "not set" ? fixv : (sprint !== "not set" ? sprint : "unknown — please confirm base branch with a human");
const desc = txt(f.description).trim() || "(no description)";
const ac = txt(f.customfield_10016).trim() || "(no acceptance criteria)";
console.log(`## JIRA Issue: ${d.key}

**Title:** ${f.summary || ""}
**Status:** ${(f.status && f.status.name) || ""}  **Priority:** ${(f.priority && f.priority.name) || "none"}
**Assignee:** ${(f.assignee && f.assignee.displayName) || "Unassigned"}
**Reporter:** ${(f.reporter && f.reporter.displayName) || ""}
**Labels:** [${labels}]
**Fix Version:** ${fixv}
**Sprint:** ${sprint}
**Base Branch Hint:** ${base}

### Description
${desc}

### Acceptance Criteria
${ac}`);
'
```

## Phase 3: Fetch and Render Latest Comments (skip if COMMENTS_COUNT = 0)

```bash
COMMENTS_RESPONSE=$(curl -s -u "${JIRA_EMAIL}:${JIRA_TOKEN}" \
  -w '\n%{http_code}' \
  "${JIRA_BASE_URL}/rest/api/2/issue/${TICKET_ID}/comment?maxResults=${COMMENTS_COUNT}&orderBy=-created" \
  -H "Content-Type: application/json")
```

```bash
printf '%s' "$COMMENTS_RESPONSE" | node -e '
const raw = require("fs").readFileSync(0, "utf8");
const nl = raw.lastIndexOf("\n");
const status = raw.slice(nl + 1).trim();
const body = raw.slice(0, nl);
if (status !== "200") { console.log("(could not fetch comments, HTTP " + status + ")"); process.exit(0); }
function txt(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (Array.isArray(v)) return v.map(txt).join("");
  let s = v.text || "";
  if (v.content) s += txt(v.content);
  if (v.type === "paragraph") s += "\n";
  return s;
}
const comments = (JSON.parse(body).comments) || [];
if (!comments.length) { console.log("(no comments)"); process.exit(0); }
for (const c of comments) {
  const date = (c.created || "").slice(0, 10);
  const who = (c.author && c.author.displayName) || "Unknown";
  console.log(`**[${date}] ${who}**`);
  console.log(txt(c.body).trim());
  console.log("\n---");
}
'
```

## Output

The final structured markdown is the concatenation of the Phase 2 issue block and,
unless `COMMENTS_COUNT = 0`, a `### Latest {COMMENTS_COUNT} Comments` heading
followed by the Phase 3 comment blocks. Emit it for the calling agent to consume.
