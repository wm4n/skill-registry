---
name: team-onboarding
argument-hint: "[path-or-url] [--interview] [--update]"
description: >-
  Use when a developer wants the bot to learn their team's development
  conventions, coding standards, workflow, or hard prohibitions from onboarding
  material — feeding new-hire docs, a folder, links, or an interview so the bot
  behaves like an onboarded team member across every repo. Triggers: "onboard
  the bot", "teach it our team's rules", "learn our conventions", 學團隊模式,
  新人文件, 團隊規範, team conventions, coding standards, dev norms.
allowed-tools: Read, Write, Edit, Glob, WebFetch
---

# Team Onboarding

## Overview

Treat the bot like a new hire on their first day: it reads the team's onboarding
material and remembers the rules for every future task. This skill distills that
material into a **global, cross-repo team profile** under `~/.claude/team-profile/`
and installs a persistent self-check block into `~/.claude/CLAUDE.md`, so the
knowledge applies in every repository without per-repo setup.

**Layered application:** hard prohibitions ("never do X") stay always-on in
`CLAUDE.md`; everything else lives in profile files that are recalled on demand.

**Scope:** this skill targets Claude Code — the `~/.claude/` paths below are Claude
Code conventions. It maintains a single team profile by design (multi-team switching
is a deliberate non-goal; if you ever need it, give profiles distinct directory
names). Porting to another agent means relocating these paths.

## When to Use

- A developer wants the bot to absorb team conventions, coding standards,
  workflow, or absolute don'ts from written docs or an interview.
- Onboarding a fresh bot to how a team works, before it touches any repo.
- Updating the team profile when norms change (`--update`).

**Not for:** repo-specific knowledge mined from git history (use `learn-from-repo`),
or lessons the bot learns from its own mistakes (use `self-evolution`). This skill
learns from **curated, human-authored onboarding material**.

## Where the Knowledge Lives

```
~/.claude/team-profile/
  INDEX.md      # entry counts + source list + updatedAt
  never.md      # absolute prohibitions  → MUST-NOT (always-on)
  standards.md  # conventions/preferences → SHOULD / MAY
  workflow.md   # how the team works (branching, PR, tests, release)
  glossary.md   # domain terms / jargon (optional; skip if empty)
```

Plus a fixed block in `~/.claude/CLAUDE.md` titled
`## 團隊規範（由 team-onboarding skill 維護）` — see the template below.

**Output language:** write skill logic in English, but write the *profile content*
in the language of the source material (do not force-translate the team's rules).

## Severity Tiers

| Kind | Level | Destination |
|---|---|---|
| Absolute prohibition | MUST-NOT | `never.md` + `CLAUDE.md` always-on list |
| Convention / standard | SHOULD | `standards.md` (recalled on demand) |
| Preference / suggestion | MAY | `standards.md` |
| Workflow / process | — | `workflow.md` (recalled when starting work) |

Every entry carries a stable id (`N###`/`S###`/`W###`, next = current max + 1) and a
**source tag** (which document or interview it came from).

**Tiering rules (apply to keep runs consistent):**

- **`never.md` is only for the truly catastrophic.** An entry goes to MUST-NOT
  *only* when the source explicitly frames it as an absolute/hard "don't" (e.g. a
  "never do X" list, or a rule tied to a stated incident). Prohibition *wording*
  alone does not qualify: a rule that uses "must not / 不可 / 別" but sits inside a
  conventions or style section stays a SHOULD in `standards.md`. When unsure, prefer
  `standards.md` — MUST-NOT is a short, high-signal list, not a dumping ground.
- **`workflow.md` vs `standards.md` tiebreaker.** If a rule is about the *sequence*
  of getting change shipped — branch/PR/review/release flow, env setup steps — it
  goes to `workflow.md`. If it's a rule about the *content* of code or commits —
  naming, style, module boundaries, commit-message format — it goes to
  `standards.md`. Pick one deterministically so `--update` re-runs don't reshuffle.
- **`never.md` is canonical.** The MUST-NOT list inside the `CLAUDE.md` block is a
  generated, condensed mirror of `never.md` (rule text only — drop the `source:` tag
  and any parenthetical detail). On conflict, `never.md` wins and the block is
  regenerated from it.

## Workflow

1. **Detect mode.** If `~/.claude/team-profile/INDEX.md` is missing → first-time
   onboard. If it exists or `--update` is passed → incremental update (load existing
   entries first, for dedup). Parse `$ARGUMENTS`: first token as a path/URL source;
   `--interview` for interview mode.
2. **Collect sources.** Folder/path → `Glob` for `*.md`/`*.txt`/`*.pdf`, read each.
   PDFs are read directly with the `Read` tool (use page ranges for long files); ask
   the user to export `.docx` to md/pdf first. URL → `WebFetch`, **confirm with the
   user before fetching**. `--interview` → ask the questions below, one at a time.
   Pasted text → use directly.
3. **Extract and tier.** Pull candidate entries; tag each with severity + category +
   source, following the extraction heuristics below.
4. **Confirm before writing.** Present candidates grouped by tier with temporary
   numbers; ask: accept all / delete #n / edit #n. Dedup against existing entries.
   On `--update`, a reworded version of an existing rule → edit in place, keeping its
   id; a genuine contradiction (new source says the opposite) → show both versions and
   let the user decide, defaulting to the newest source. **Never write any file before
   explicit confirmation.**
5. **Write in fixed order:** category files → `INDEX.md` → `CLAUDE.md` block. Each
   `never.md` entry is mirrored into the always-on list. This order makes a mid-run
   interruption safe to re-run.
6. **Report.** Summarize entries added/updated, counts per tier, and the source list.
   Do **not** auto-commit (`~/.claude/` is not this repo).

## Extraction Heuristics

What deserves to become an entry:

- **A durable rule or convention the team expects everyone to follow** — not a
  one-off instruction, not a description of what some code currently does.
- **Prefer quality over quantity.** A document may yield zero entries. Skip generic
  best practices ("write clean code"), tooling trivia already obvious from the repo,
  and step-by-step implementation detail that belongs in the docs, not the profile.
- **Tier by how the source frames it, not by wording** — see the tiering rules above.
  A stated incident or an explicit "never"/"絕對不可" → `never.md`; a preference or a
  "try to"/"盡量" → MAY.

Examples (from an onboarding doc):

| Source line | Decision |
|---|---|
| "Never commit `keystore` — we had a leak once" | `never.md` (MUST-NOT), incident-backed |
| "`presentation` 不可反向依賴" (under 程式碼規範) | `standards.md` SHOULD — prohibition-worded convention, not flagged absolute |
| "PR 盡量切小" | `standards.md` MAY — soft preference |
| "Use `./gradlew assembleDevelopDebug` to build" | **skip** — tooling trivia, not a rule |

## Interview Questions (`--interview`)

Ask one at a time; after each answer, ask whether it is an "absolute don't", a
convention, or a "suggestion" so it can be tiered.

**Core:**
1. Branch strategy? (trunk / feature branches / naming)
2. PR and code-review rules? (who reviews, required approvals, required checks)
3. Testing expectations? (coverage, which tests are mandatory, CI gates)
4. Absolute don'ts? (past incidents, hard prohibitions)
5. Naming and code-style conventions?
6. Team terminology / domain jargon?

**Optional extensions (ask if relevant, and invite the user to add their own):**
security & secret handling, logging/observability/monitoring, deployment & release
details, error handling & rollback habits, documentation standards.

## Entry & Block Templates

Profile entries:

```
never.md      - [N001] <rule> — source: <doc name / interview date>
standards.md  - [S001] (SHOULD|MAY) <rule> — source: <…>
workflow.md   - [W001] <process note> — source: <…>
glossary.md   - **<term>**: <definition> — source: <…>
```

`INDEX.md`:

```
# team-profile INDEX

updatedAt: <YYYY-MM-DD>

## Entry counts
- never.md (MUST-NOT): <n>
- standards.md (SHOULD/MAY): <n>
- workflow.md: <n>
- glossary.md: <n> terms

## Sources
- <doc name / URL / interview> — <one-line note> (imported <YYYY-MM-DD>)
```

`CLAUDE.md` block (fixed heading; the self-check instruction is what drives the
"active check"):

```
## 團隊規範（由 team-onboarding skill 維護）

主動回憶時機：**動工前**先掃 `~/.claude/team-profile/workflow.md`（流程）與相關
`standards.md` 條目；**寫 code 時**對照 `standards.md`；**commit / push 前**對照下列
「絕不可犯」清單自檢。需要細則時讀 `~/.claude/team-profile/`。

### 絕不可犯（MUST-NOT）
- [N001] <rule>
- [N002] <rule>

細則：standards → `~/.claude/team-profile/standards.md`；流程 → `workflow.md`；術語 → `glossary.md`。
```

## Iron Rules

- **Never write any file before the user confirms** the candidate list (step 4).
- **`CLAUDE.md` block maintenance:** locate by the exact heading above; if absent,
  rebuild it at the end of the file. Preserve any lines inside the block that the
  user added by hand (anything not starting with `[N###]`) — never delete them.
- **Global only.** Write under `~/.claude/` exclusively; never touch any repo file.
  Single team profile (no multi-team switching).

## Common Mistakes

- Translating the team's rules into English — keep the source language.
- Writing files before confirmation, or auto-committing to a repo.
- Dumping every entry into `CLAUDE.md` — only MUST-NOT rules go always-on; the rest
  stay in profile files to keep context lean.
- Overwriting a user's hand-edited lines in the `CLAUDE.md` block.

## Coexistence with self-evolution

Both maintain their own independent block in `~/.claude/CLAUDE.md` and their own
directory (`team-profile/` vs `evolution/`). They never overlap: `team-onboarding`
learns from onboarding material (one-time / incremental import); `self-evolution`
learns from the bot's own mistakes (post-task screen).
