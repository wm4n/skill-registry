---
name: figma-fetch
argument-hint: "nodes|image|comments <figma-file-or-node-url>"
description: >-
  Use when a Figma file or frame link appears in a Jira ticket, GitHub
  issue, or conversation and the design content it points to — layer/text
  structure, a rendered image, or review comments — is needed to ground a
  question or an implementation decision in what the design actually shows,
  instead of guessing from the link alone.
---

# Figma Fetch

Read-only access to Figma's official REST API (`https://api.figma.com`).
Three independent actions — pick only the one(s) you actually need for the
question at hand, don't call all three by default.

## Actions (`$ARGUMENTS`)

There is no single fixed invocation format — pick whichever action(s)
answer the actual question, based on what's being asked, not on a rigid
per-call syntax:

- `nodes <figma-url>` — structured text: layer/component names and nested
  text content for the node the URL points to. Use this to find out what a
  screen is *called* and what text it contains.
- `image <figma-url>` — download a PNG render of the node to a local file,
  then use the `Read` tool on that file to actually look at it. Use this
  when the question is about layout, visual hierarchy, or anything you
  can't tell from names/text alone.
- `comments <figma-url>` — list every review comment left on the file.
  Use this when the question is about open feedback/discussion on the
  design, not the design itself.

A question can need more than one action (e.g. "what does this screen say
and look like" → `nodes` then `image`) — call each one you need.

## Required Environment Variable

- `FIGMA_TOKEN` — a Figma Personal Access Token.

Check it the same way as `jira-fetch`/`jira-grill` (`${VAR:+set}`, as a
normal Bash step — not the skill frontmatter's load-time inline shell
check, that path is blocked by the permission layer):

```bash
echo "FIGMA_TOKEN: ${FIGMA_TOKEN:+set}"
```

Not set → stop immediately and output (substituting the actual URL for
`{figma-url}`):

```
Missing required environment variable: FIGMA_TOKEN.
Please provide the content of {figma-url} manually (a screenshot or a
description of the relevant frame) to continue.
```

This check and the URL-parsing check below don't depend on each other —
either order is fine.

## JSON Parsing

Parse all JSON responses with `node -e`, same as `jira-fetch`. Do not
assume `jq`, `python3`, or GNU-only coreutils flags are available.

## Parsing the Figma URL

Figma URLs come in two path forms, both valid:

```
https://www.figma.com/file/<FILE_KEY>/<title>?node-id=<NODE_ID>
https://www.figma.com/design/<FILE_KEY>/<title>?node-id=<NODE_ID>
```

`FILE_KEY` is the path segment right after `/file/` or `/design/`.
`NODE_ID` is the `node-id` query param — **the URL writes it with a dash
(`43777-15`), but the API's `ids` parameter wants a colon
(`43777:15`)**. Convert before calling the API:

```bash
node -e '
const url = new URL(process.argv[1]);
const m = url.pathname.match(/\/(file|design)\/([^/]+)/);
if (!m) { console.log("ERROR: not a recognizable Figma URL"); process.exit(0); }
const fileKey = m[2];
const nodeIdRaw = url.searchParams.get("node-id");
const nodeId = nodeIdRaw ? nodeIdRaw.replaceAll("-", ":") : "";
console.log(JSON.stringify({ fileKey, nodeId }));
' "$FIGMA_URL"
```

If the URL doesn't match either path form at all (e.g. a FigJam board
link, or a shortened/forwarded URL), the snippet prints `ERROR: not a
recognizable Figma URL` — stop and output:

```
This doesn't look like a Figma file/design link. Please paste a direct
https://www.figma.com/file/... or /design/... URL, or describe the
relevant frame manually.
```

`nodes` and `image` both require a node id — if the URL has none, stop and
output:

```
The Figma URL doesn't include a node-id (no specific frame selected).
Please paste a link to the specific frame/node, or describe it manually.
```

`comments` doesn't need a node id — it lists every comment on the whole
file regardless of which frame the URL points to.

## Error Handling

Every call appends the HTTP status the same way as `jira-fetch`
(`-w '\n%{http_code}'`, then split status from body in `node -e`). Each
action's script below checks the status itself and maps 400/403/404/429
to a specific message, anything else to a generic one — the table isn't
repeated separately here because each action needs it inline in its own
one-shot `node -e` call, not as a cross-reference.

If the output starts with `ERROR:`, relay that message to the user, prompt
them to paste the relevant content manually, and stop — same fallback
policy as `jira-fetch`.

## Action: `nodes`

```bash
curl -s -H "X-Figma-Token: ${FIGMA_TOKEN}" -w '\n%{http_code}' \
  "https://api.figma.com/v1/files/${FILE_KEY}/nodes?ids=${NODE_ID}"
```

Response shape: `{ nodes: { "<NODE_ID>": { document: <Node> } } }`. Render
by walking `document` recursively — for every node print its `name` and
`type`; if `type === "TEXT"`, also print its `characters` (the actual text
content):

```bash
node -e '
const raw = require("fs").readFileSync(0, "utf8");
const nl = raw.lastIndexOf("\n");
const status = raw.slice(nl + 1).trim();
const body = raw.slice(0, nl);
if (status !== "200") {
  const msg = {
    "400": "Figma API rejected the request (HTTP 400). The file key or node id is probably malformed.",
    "403": "Figma authentication failed (HTTP 403). Verify FIGMA_TOKEN is a valid Personal Access Token with access to this file.",
    "404": "Figma file or node not found (HTTP 404). Verify the URL and that the token'"'"'s account has access to this file.",
    "429": "Figma API rate limit hit (HTTP 429). Wait a bit and retry, or fall back to asking the human for the content."
  }[status] || ("Figma API returned an unexpected error (HTTP " + status + ").");
  console.log("ERROR: " + msg);
  process.exit(0);
}
const nodeId = process.argv[1];
const root = (JSON.parse(body).nodes[nodeId] || {}).document;
if (!root) { console.log("(node not found in response — id may not exist in this file)"); process.exit(0); }
function walk(n, depth) {
  const indent = "  ".repeat(depth);
  let out = indent + "- " + n.name + " (" + n.type + ")";
  if (n.type === "TEXT" && n.characters) out += ": \"" + n.characters + "\"";
  console.log(out);
  for (const c of (n.children || [])) walk(c, depth + 1);
}
walk(root, 0);
' "$NODE_ID"
```

## Action: `image`

Two-step: Figma's images endpoint returns a signed URL, not the image
bytes — download that URL separately, then tell the caller the local path.

```bash
IMG_RESPONSE=$(curl -s -H "X-Figma-Token: ${FIGMA_TOKEN}" -w '\n%{http_code}' \
  "https://api.figma.com/v1/images/${FILE_KEY}?ids=${NODE_ID}&format=png")
```

```bash
IMG_URL=$(printf '%s' "$IMG_RESPONSE" | node -e '
const raw = require("fs").readFileSync(0, "utf8");
const nl = raw.lastIndexOf("\n");
const status = raw.slice(nl + 1).trim();
const body = raw.slice(0, nl);
if (status !== "200") {
  const msg = {
    "400": "Figma API rejected the request (HTTP 400). The file key or node id is probably malformed.",
    "403": "Figma authentication failed (HTTP 403). Verify FIGMA_TOKEN is a valid Personal Access Token with access to this file.",
    "404": "Figma file or node not found (HTTP 404). Verify the URL and that the token'"'"'s account has access to this file.",
    "429": "Figma API rate limit hit (HTTP 429). Wait a bit and retry, or fall back to asking the human for the content."
  }[status] || ("Figma API returned an unexpected error (HTTP " + status + ").");
  console.log("ERROR: " + msg);
  process.exit(0);
}
const nodeId = process.argv[1];
const url = (JSON.parse(body).images || {})[nodeId];
if (!url) { console.log("ERROR: Figma could not render this node (no renderable content, or the id does not exist)."); process.exit(0); }
console.log(url);
' "$NODE_ID")

if [[ "$IMG_URL" == ERROR:* ]]; then
  echo "$IMG_URL"
else
  OUT_PATH="/tmp/figma-${FILE_KEY}-$(echo "$NODE_ID" | tr ':' '-').png"
  curl -s -o "$OUT_PATH" "$IMG_URL"
  echo "Downloaded to ${OUT_PATH} — use the Read tool on this path to view it."
fi
```

## Action: `comments`

```bash
curl -s -H "X-Figma-Token: ${FIGMA_TOKEN}" -w '\n%{http_code}' \
  "https://api.figma.com/v1/files/${FILE_KEY}/comments"
```

Render each comment's `message` (the text), `user.handle` (author),
`created_at`, and whether `resolved_at` is set:

```bash
node -e '
const raw = require("fs").readFileSync(0, "utf8");
const nl = raw.lastIndexOf("\n");
const status = raw.slice(nl + 1).trim();
const body = raw.slice(0, nl);
if (status !== "200") {
  const msg = {
    "400": "Figma API rejected the request (HTTP 400). The file key or node id is probably malformed.",
    "403": "Figma authentication failed (HTTP 403). Verify FIGMA_TOKEN is a valid Personal Access Token with access to this file.",
    "404": "Figma file or node not found (HTTP 404). Verify the URL and that the token'"'"'s account has access to this file.",
    "429": "Figma API rate limit hit (HTTP 429). Wait a bit and retry, or fall back to asking the human for the content."
  }[status] || ("Figma API returned an unexpected error (HTTP " + status + ").");
  console.log("ERROR: " + msg);
  process.exit(0);
}
const comments = (JSON.parse(body).comments) || [];
if (!comments.length) { console.log("(no comments)"); process.exit(0); }
for (const c of comments) {
  const date = (c.created_at || "").slice(0, 10);
  const who = (c.user && c.user.handle) || "Unknown";
  const status2 = c.resolved_at ? "resolved" : "open";
  console.log(`**[${date}] ${who}** (${status2})`);
  console.log(c.message || "");
  console.log("\n---");
}
'
```

## Known Limitations

- **Only `/file/` and `/design/` URLs are recognized**: FigJam board links
  (`/board/...`) and any shortened/forwarded URL are treated as
  unrecognized and rejected up front (see "Parsing the Figma URL"). This
  is a deliberate scope limit for this first version, not a confirmed
  statement that Figma's REST API can't serve FigJam content at all —
  if FigJam support is needed later, verify against the API directly
  before assuming this skill's endpoints apply unchanged.
- **Requires a node-id for `nodes`/`image`**: no whole-file fallback —
  large files can have thousands of nodes, so this skill deliberately
  requires the caller to already know which frame it cares about
  (from the URL). If a Figma link has no `node-id`, ask the human for a
  link to the specific frame instead of fetching the entire file.
- **Single shared Personal Access Token**: same model as `JIRA_TOKEN` —
  one team/service Figma account's token, not per-user OAuth. Whatever
  files that account can see, the skill can read; nothing more.
- **Image URLs expire after 30 days**: irrelevant in practice since this
  skill downloads the image immediately after fetching the signed URL —
  noted here only so nobody tries to cache/reuse a URL from a previous
  run.
- **Rate limits**: Figma's API returns HTTP 429 under heavy use; this
  skill does not retry automatically, it surfaces the error and lets the
  caller decide whether to wait and re-run.
