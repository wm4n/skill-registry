---
name: openab-schedule
description: Use whenever a human asks the bot to notify them or do something later — a one-time future reminder, a recurring report (daily PR summary, weekly report), a periodic alert scan, or any deferred/cyclical action — or to create, modify, view, disable, or delete such a schedule. This is the bot's only scheduling mechanism, one-time requests included (see Runtime contract — never CronCreate/CronList/CronDelete/ScheduleWakeup, never /remind). Not for plain questions/code reading, or work to do right now.
---

# openab-schedule

## Runtime contract

Schedules live in **one file** — `~/.openab/cronjob.toml` (openab's built-in **usercron**). The scheduler polls the file's mtime every minute and hot-reloads it; when a job fires it injects that job's `message` as a **brand-new prompt** (zero memory of this conversation) — you act on it and post the result to the job's `channel`.

- **Only ever read/write `~/.openab/cronjob.toml`.** Never `CronCreate`/`CronList`/`CronDelete`/`ScheduleWakeup` or any Claude-Code-native scheduler: those are session-scoped, die with the session, and never reach Discord — a "schedule/remind/notify me" request is never theirs here, however directly they seem to fit.
- **Never `/remind`.** It's a human-only slash command (bots are rejected), and even for a human it only tags someone at a fixed time — it never runs agent logic. Anything needing the agent to *act* later, one-time or recurring, belongs in a usercron job.
- **You CAN** (no restart): create/modify/view/disable/delete jobs — editing the file hot-reloads within a minute.
- **You CANNOT** enable usercron itself: that needs `[cron]` in `config.toml` plus a **container restart**, outside the container. You can't read the live config or restart yourself — so never fake it; say so plainly.
- **The only proof a schedule fires is the step-3 ping** — not this doc, not any config you happen to read. "It's set up" right after writing the file is wrong.

## Hard Gate — one confirmation card

This card gates **creating a schedule or changing its content** — disable/delete/list follow steps 5–6, not this card. Resolve **every** field below (parse what the human gave, default the rest), post them as **one** summary card, and wait for confirmation. Never write first and explain after; never confirm field-by-field; never drop a field because it "obviously" defaults. On any correction, re-show the **whole** card — don't silently patch one field and proceed.

```
📋 排程確認
- 執行內容：<self-contained instruction — the full deferred action, not just a ping>
- 提及：<"<@USER_ID>（<name>，預設 mention 提出請求的人）" or "不 mention 任何人">
- 通知時間：<computed absolute next fire — date, weekday, time>
- 時區：<IANA timezone>
- 通知頻道：<channel name>（<channel ID>）<"（預設）" if you picked it, not the human>
- 重複：<"不重複（一次性）" or the recurring pattern in plain language + raw cron>
- 顯示名稱：<sender_name>
- 討論串：<"開新討論串" or "沿用目前討論串">

以上正確嗎？
```

- **執行內容 (`message`)** — the entire self-contained instruction to run at fire time, including any lookup/research asked for. If the request bundles a delayed notify *with work* ("remind me in 5 min, then list my Jira tickets"), the work goes **entirely** here — never do it now and leave this a bare "time's up" ping.
- **提及 (mention)** — the fired turn has zero memory, so a mention must be baked into `message` as literal `<@USER_ID>` syntax now; it can't be reconstructed later. Resolve the requester's Discord ID from the same context you read the timestamp from — never a plain-text `@william` (never renders), never a guess; if you can't find a reliable ID, ask them to right-click their name → Copy User ID. Default: a personal one-time reminder mentions the requester; a recurring report to a shared/team channel gets **no** mention unless asked.
- **通知時間 / 重複 (`schedule`)** — compute the real next fire yourself, never eyeball; state one-time vs. recurring, and for recurring give the plain-language pattern **and** the raw cron.
- **時區 (`timezone`)** — never leave unstated; default `Asia/Taipei`. Unset = UTC = 8 h off.
- **通知頻道 (`channel`)** — a real **channel ID**, never a thread ID (Discord rejects a thread under a thread: `failed to create thread: Cannot execute action on this channel type`). Never silently default to "wherever this conversation is". If several channels are allowed and one is clearly purpose-matched (e.g. a `*-notify` channel for a reminder ask), you may default to it but show it `（預設）` for veto; if none obviously fits, ask before building the card; if reusing an existing job's channel because the human said "this channel", confirm once.
- **顯示名稱 (`sender_name`)** — short label shown in the fire (`🕐 [sender_name]: message`); auto-generate one from the instruction if not given, but still show it.
- **討論串 (`thread_id`)** — default is a **new thread** under `channel`; reuse the current/an existing thread only if the human asked, and say which explicitly. To target an existing thread, set `channel` (real channel) **and** `thread_id` together.

## Steps

### 1. Don't stall on "is usercron enabled?" — the ping is the only judge

Go straight to step 2 and let the step-3 ping decide: it appears → enabled and the whole chain works; nothing → probably disabled, ask a human to enable it. You usually can't read the live config from inside the container, so don't burn time guessing paths. Only if you *happen* to read a config (`~/.openab/config.toml`, `/home/node/config.toml`, `/etc/openab/config.toml`) that clearly shows `usercron_enabled = false` or no `[cron]` at all, stop early and ask the human to add this and redeploy (you can't edit live config or restart):

```toml
[cron]
usercron_enabled = true
usercron_path = "cronjob.toml"
```

### 2. Write the job — only after the card is confirmed; read the file first, never clobber

```bash
mkdir -p ~/.openab
cat ~/.openab/cronjob.toml 2>/dev/null   # keep any existing [[jobs]]
```

Multiple schedules = multiple `[[jobs]]` in one file. Write the **entire file** (existing jobs untouched + yours); add or replace **your own** entry by `id` — never overwrite the file with just your block.

```toml
[[jobs]]
id = "daily-merged-pr-summary"     # required, for reliable scheduler writeback
enabled = true
schedule = "0 9 * * 1-5"
channel = "1490282656913559673"    # quote the snowflake — avoids float precision loss
message = "Summarize yesterday's merged PRs: use gh to find PRs merged in the previous calendar day, list number, title, author, and a one-line highlight; say so plainly if there were none. Report in the requested language."
sender_name = "DailyPR"
timezone = "Asia/Taipei"
```

- `message` is a **self-contained natural-language instruction** — at fire time it's a fresh prompt that must work out "yesterday", the no-data case, and reply language entirely on its own.
- Don't bake shell, `date -d`, or crontab `%` escaping into `message`: it's plain TOML, not crontab, and the container's `date` (BSD vs GNU) isn't guaranteed — leave date math to the fire-time agent.
- **One-off / "run once" / "remind me in N min"**: cron has **no year field**, so even an exact minute/hour/day/month fires again next year — not truly one-time. Don't reach for `disable_on_success = true` (invalid — see Quick reference). Instead, like `verify-ping` below: create it, let it fire once, confirm, then **manually delete it**. It won't stop itself.

### 3. End-to-end test — the only trustworthy verification

You can't read `docker logs`, so verify by **observed behavior** — add a once-a-minute ping and watch the channel for 1–2 minutes.

```toml
[[jobs]]
id = "verify-ping"
enabled = true
schedule = "* * * * *"
channel = "1490282656913559673"
message = "usercron self-test ping, please ignore"
sender_name = "verify"
timezone = "Asia/Taipei"
```

- **It shows up** → the whole chain works (usercron on, path/channel correct, bot present). But confirm it's **real** first: a genuine fire is always the fixed `🕐 [sender_name]: message` — a fresh standalone message, never a reply. Text you generated yourself (ran `date`, typed something ping-like, or glued onto a reply) is **not** a real signal — usercron never fired. Once confirmed real, delete `verify-ping`, keep only the real job(s), save again. Later fires of the same job all land in the **same thread the first fire created** (the scheduler writes `thread_id` back) — expected, not a bug.
- **Nothing shows up** → usercron probably disabled (back to step 1), or the channel ID is wrong / the bot isn't in that channel.

### 4. Report back — never just "it's set up"

- **Exact fire date/time** in the confirmed timezone, spelled out — not the bare cron (e.g. "fires 2026-07-25 23:58 Asia/Taipei", not "`*/5 * * * *`").
- **Next fire** — the same moment for a one-time job; for a recurring job, the **next 3 fire times**, so the human can sanity-check without cron math.
- **One-line instruction summary** — paraphrase `message`, don't paste it.
- That you verified with a **real ping** (step 3), and that future changes (time, disable, delete) go through you — no restart.

**Computing fire times:** never eyeball a cron against a clock in your head — a wrong tool plus a time asserted without real computation is exactly how this goes wrong. Compute in the confirmed timezone: prefer a real tool if the container has one (e.g. `python3` + `zoneinfo`, verified available); otherwise reason the fields by hand (minute → hour → day-of-month → month → day-of-week) against the current date and show your work. This is for your report only — never bake it into `cronjob.toml`.

### 5. Disable or delete — report what stops

1. Read the file; identify the job by `id`. Any ambiguity about which job → ask, never guess.
2. `enabled = false` to disable (keeps the block for re-enabling), or remove the block entirely for a real delete.
3. Report explicitly: which job (`id` + one-line summary) and what it cancels — e.g. "disabled `daily-merged-pr-summary`: would otherwise have next fired 2026-07-28 09:00 Asia/Taipei (and every weekday after) — that won't happen now." Never silently disable or delete.

### 6. List — a consistent table, never raw TOML

| id | schedule | next run | channel | instruction |
|---|---|---|---|---|
| daily-merged-pr-summary | weekdays 9am (`0 9 * * 1-5`) | 2026-07-27 09:00 Asia/Taipei | 1490282656913559673 | Summarize yesterday's merged PRs… |

- **schedule** — plain language first, raw cron in parens.
- **next run** — computed (see step 4), never guessed.
- **instruction** — first ~10 words of `message`, `…` for truncation.
- Include disabled jobs, marked (e.g. `(disabled)` prefix on the `id`) — show the full picture, not just active ones.

## Quick reference

| Need | Value |
|---|---|
| Weekdays 9am | `0 9 * * 1-5` |
| Every day 6pm | `0 18 * * *` |
| Sunday midnight | `0 0 * * 0` |
| Every 30 min | `*/30 * * * *` |
| 1st of month, 9am | `0 9 1 * *` |
| View current jobs | `cat ~/.openab/cronjob.toml` |
| Disable a job | that block's `enabled = false` (or delete the block) |
| Post into an existing thread | set `channel` (real channel) **and** `thread_id` together |
| Only Discord in use | omit `platform` (defaults `"discord"`; set `"slack"` only for Slack) |

**`disable_on_success`** (goal-driven auto-disable, needs `id`): the value **must be a shell command string** (e.g. `"npm test && echo DONE"`) paired with `disable_on_success_match` — the command must exit 0 **and** its output must contain that string before openab writes `enabled = false` back. It is **not a boolean**, can't be bare `true`, and does not apply to a "run once and see" job (manual delete instead — step 2). Full fields/limits: the openab runtime repo's `docs/cronjob.md` or `deployment-guides/CRONJOB.md`.

⚠️ No mixed numeric/name weekdays (`1,Mon` ❌); no wrap-around ranges (`5-2` ❌); don't schedule long-running tasks (>5 min) too tightly (overlap protection skips the next tick).

## Failure guards

The body's rules cover the mechanics; these cover the **temptation** — the excuses agents reach for under pressure.

| Rationalization | What happens | Instead |
|---|---|---|
| "This is obviously a scheduling request" → `CronCreate`/`ScheduleWakeup`/any Claude-native scheduler | Wrong system — session-scoped, dies with the session, never reaches Discord | Only read/write `~/.openab/cronjob.toml` |
| "A one-time 'remind me in N min' isn't for this / it's `/remind`'s job" | `/remind` is human-only (bots rejected) and never runs agent logic — the follow-up never happens, the human gets nothing | A one-off usercron job (step 2), manual delete once confirmed |
| "File's written — I'll tell them it's set up" | No proof it fires — silent failure the human won't notice for days | Run the step-3 ping first |
| "I ran `date` / replied and it looks like a fire" | Proves nothing — the real mechanism was never exercised | Trust only a standalone `🕐 [sender_name]: message` |
| "`disable_on_success = true` will stop the one-off" | Invalid syntax; auto-disables nothing; still fires next year (no year field) | Manually delete after it fires once |
| "Do the work now, then a 'time's up' ping as `message`" | The action runs at the wrong time (now); the real fire carries no content | Put the full deferred instruction in `message`; your reply only confirms |
| "Plain-text 'notify them' / `@name` is fine" | The fired turn has zero memory — can't invent a mention, so it never pings | Bake the literal `<@USER_ID>` into `message` at confirmation |

**Red flags — STOP** (each sends you back to the rule in parens):
- About to call a Claude-native scheduler, or to point the human at `/remind` → read/write `cronjob.toml` only (Runtime contract).
- "I'll do the lookup now, then set the reminder" → that work belongs in `message` (Hard Gate · 執行內容).
- "File's written, I'll say it's set up" / "my `date` reply looks like a fire" → only a real standalone `🕐 …` counts (step 3).
- "`@william` will ping them" → resolve and bake in `<@USER_ID>` (Hard Gate · 提及).
- "Just use this conversation's channel" → never default the channel when several are plausible; ask (Hard Gate · 通知頻道).
- About to write the file, or confirm fields one at a time → resolve all fields, one card, wait (Hard Gate).

Never fake the two things that aren't yours: enabling usercron (config + restart), and "it's live" before a real ping.
