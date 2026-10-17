---
name: swarm-train
description: >-
  Run the `Ready` queue unattended as a tree of subagents — `/swarm-train` from
  a session that stays up all night (a terminal, Remote Control, the web app)
  snapshots the board, puts `Ready` in one train (or `--size <n>` of them), and
  spawns one background `swarm-lead` per train, one at a time; the session
  itself is the top: it ticks on a scheduled wake, relieves a stalled or cut-off
  lead with a fresh one, records every outcome in the whip ledger, and the last
  `done` renders the morning report. Nothing runs outside the session. Use when
  the user says "swarm-train", "run the Ready queue overnight as a tree", "train
  the swarms"; a live `whip-<date>.md` ledger on disk makes the session its
  console, never a second start.
---

# Swarm-train

You are the **top** of a tree: you steer leads and nothing below them. Leads
steer swarms. The why behind every step: `docs/charters/swarm-train.md`.

```
top session   — this skill: trains, ledger, tick, relief, report
 └─ swarm-lead  one per train, BACKGROUND subagent, name lead-<t> / relief-<t>-<k>
     └─ drone × n  background, dispatched by the lead, never by you
         └─ Explore   haiku leaf
```

Two things hold the whole run together:

- **The ledger on disk is the shared state.** `docs/handoffs/whip-<date>.json`
  + `.md` (trains, lead table, events, cap), written only through
  `mise run whip -- <verb>`; beside it, one swarm ledger per lead,
  `docs/handoffs/swarm-<date>-<lead-name>.md`, written only by that lead. No
  message carries state; a relief orients from disk.
- **A tick is one cheap turn.** A turn that finds nothing says `noop` and
  ends. One line per event in the chat, never a re-summary.

## 0. Console or start?

1. `ls docs/handoffs/whip-*.md` — a ledger from the last 36 h whose header is
   not finished → `mise run whip -- show`. **This session is now that run's
   console**: go to §4 and run the tick table; never a second `start`.
2. No live ledger → §1.

## 1. Preflight (nothing is armed or started until it passes)

1. **Trigger tools.** `ToolSearch` for `mcp__claude-code-remote__create_trigger`,
   `get_trigger`, `delete_trigger`, `get_session`. Absent → the run is
   **`/loop` self-paced**: the same steps, the tick turn driven by `/loop`
   at `tick-minutes`, no wakes; for the model check read the configured-model
   line of your own system prompt, or tell the owner you cannot tell.
2. **Own record.** `get_session` with no id. Read three fields:
   - `external_metadata.permission_mode` — must be `auto`. Otherwise one
     line to the owner: *this session is in `<mode>`; switch it to auto, or
     say run anyway* — and arm nothing until they have or say so.
   - `session_context.model` (the configured model, not
     `last_served_model`) — an id starting `claude-opus` or `claude-sonnet`
     proceeds; anything else is one line to the owner before `start`, and
     `start` waits for their word exactly as the mode check does.
   - `external_metadata.rate_limit_info.resetsAt` (epoch seconds) — keep it
     for §3's boundary.
3. **Owner-stated reset.** If the owner has said when the window resets
   ("resets in 1 h 05", a time in chat), anchor it to the moment they said
   it and keep it for §3 — it is never dropped.
4. Scope you hold all night: you never dispatch a drone, read a diff, run
   `land` or the suite, or open an issue body; nothing is escalated to the
   owner overnight; no laundering.

## 2. Start

```
mise run whip -- start --cap 15 --stall-minutes 45 --tick-minutes 45 [--size <n>]
```

- `start` snapshots `Ready` and master, writes the ledger, opens the run
  issue, and launches nothing.
- `--size` defaults to `all`: every Ready issue in **one train**, no chain
  or milestone cut. `--size <n>` (issues per train) is a trial override only;
  you never split a train to fit a window.
- `--tick-minutes` is bounded `[15, 55]`; `--cap` and `--stall-minutes` are
  the run's hour cap and the disk-silence threshold.
- One chat line: `started <run issue> · <n> issues · train(s) <list>`.

## 3. Spawn the lead and arm the wakes

**One accepting lead at a time.** The next train starts only after the
lead's `done`.

1. `mise run whip -- next-train --lead lead-<t>` — marks the train running
   under that name and prints its issues (an empty train is skipped).
2. Spawn the lead, **background, depth 1**:

   ```
   Agent(subagent_type: "swarm-lead", name: "lead-<t>", run_in_background: true,
         prompt: "train mode, train <t>: #a, #b, #c — ledger docs/handoffs/whip-<date>.md — swarm ledger docs/handoffs/swarm-<date>-lead-<t>.md")
   ```

   The lead reads the swarm skill itself and applies its train-mode section;
   its final text is its session report. You spawn no Sage; drones' advisor
   is the `advisor` tool. The swarm-ledger path is the lead's key: you own
   the whip JSON and the names, the lead derives nothing.
3. Arm **at most two pending wakes**, both one-shot `create_trigger` with
   `run_once_at`, each prompt naming its kind:
   - **boundary** — the spent-window insurance. Its time, in this order:
     `resetsAt` from §1 → the owner-stated reset from §1 → run start + 5 h 05
     as the fallback; the boundary is that time **+ 5 min**. Prompt:
     `swarm-train boundary wake: run §5 of the skill`.
   - **tick** — `now + tick-minutes`. Prompt:
     `swarm-train tick wake: run §4 of the skill`.
4. Record each id at once:
   `mise run whip -- note "wakes: boundary <id> at <chosen time> (resetsAt <t|none> · owner <t|none> · fallback <t>)"`
   and `mise run whip -- note "wakes: tick <id> at <time>"`. The boundary
   note echoes the time chosen next to every time given.
5. Never a cron, never a recurring Routine, never a poll. Whichever wake
   fires re-arms its own successor while the run is live — a boundary the
   next boundary (under the cap), a tick the next tick — and notes the new id.
6. End the turn. One chat line: `lead-<t> spawned · wakes armed`.

## 4. The tick turn — the table, nothing else

Inputs: `ListAgents` (every descendant flat, `running / completed / killed`)
and the mtime of the deepest running transcript under
`~/.claude/projects/<project>/$CLAUDE_CODE_SESSION_ID/subagents/`
(`spawnDepth` and `parentAgentId` in each `.meta.json`). Run the table for
**each live lead of the train** — the accepting one and any `draining` one.

| Lead | Transcripts | Do |
|---|---|---|
| `running` | deepest fresher than `stall_minutes` | `noop` |
| `completed`, report already acted on | — | nothing: the report woke you |
| gone, train unfinished (a window cut it off), no `resumed <name>` note | — | `SendMessage(<name>, "continue")` · `mise run whip -- note "resumed <name>"` |
| gone, train unfinished, `resumed <name>` note already in the ledger | — | `mise run whip -- relieve --lead <name>` · spawn relief (§6) |
| `running` | every one older than `stall_minutes` | `TaskStop <name>` · `mise run whip -- relieve --lead <name>` · spawn relief (§6) |

- A `TaskStop`ped **draining** lead is not relieved again: its ledger is
  dead history from then on; tell the accepting lead by one `SendMessage`
  (`<name> stopped; its unlanded units are yours`) and record
  `mise run whip -- drained --lead <name>`.
- **Cap** (`--cap`, hours) is read every tick: past it nothing is spawned,
  the lead in flight finishes its train and its `done` ends the run.
  `CAPPED` in the header is a live run with a lead to watch, not a finished
  one.
- A lead napping in a ten-minute foreground command is not a stall.
- Never poll a drone's transcript; a silent drone is the lead's to
  reclassify, and the stall row is your net.
- If the run is live, arm the next tick (`now + tick-minutes`) and note its
  id. Chat: `noop` or the one line of what the table did. End the turn.
- **A wake that fires into a finished run** (header reads done / stopped /
  retired): `mise run whip -- note "wasted: <wake id>"`, say nothing else,
  stop. At most two such turns can exist.

## 5. The boundary turn

1. Run §4's table first — a lead cut off by the limit gets its one
   `SendMessage(<name>, "continue")` and its `resumed` note.
2. **Check the tick.** Read the newest `tick` id in the `wakes:` notes with
   `get_trigger`. Fired or ended, with no newer `tick` note after it, means
   that tick fired while you were rate-limited, ran nothing and armed
   nothing: arm a fresh tick now and note it.
3. **Re-arm the boundary**: `get_session` again, re-read
   `rate_limit_info.resetsAt`; fall back as §3 does; arm the next boundary
   at +5 min, under the cap; note chosen-vs-given.
4. End the turn on one line.

## 6. Relief — a fresh `swarm-lead` with the relief prompt

Only you launch a relief. The relief's name is the one `relieve` points the
train at: `relief-<t>-<k>`. Never `ledger adopt`, never a bare
`ledger show`; everything is by file name.

**Of a dead lead** (stopped, or cut off and not resumed):

```
Agent(subagent_type: "swarm-lead", name: "relief-<t>-<k>", run_in_background: true,
      prompt: "relief, train <t>: #… — ledger docs/handoffs/whip-<date>.md — outgoing lead-<t> is DEAD: read docs/handoffs/swarm-<date>-lead-<t>.md and its inbox docs/handoffs/swarm-<date>-lead-<t>.inbox/ (a report file there for a unit the ledger shows unlanded is a finished drone — land that branch, never redo it); its rows are history, not claims — re-dispatch its partials with rows in your own file — swarm ledger docs/handoffs/swarm-<date>-relief-<t>-<k>.md")
```

A second relief also names every file its predecessor read: the chain of
dead ledgers, each by name, is the train's lead history in the whip JSON.

**Of a `draining` lead** (it sent `relief now; I keep <units>`):

```
Agent(subagent_type: "swarm-lead", name: "relief-<t>-<k>", run_in_background: true,
      prompt: "relief, train <t>: #… — ledger docs/handoffs/whip-<date>.md — outgoing lead-<t> is DRAINING and still writes docs/handoffs/swarm-<date>-lead-<t>.md: read it by name, its rows are live claims — dispatch only units with no row there and not blocked by an outgoing unit not yet landed, up to the cap minus the outgoing's rows in state dispatched (no reported@, no landed), re-read before each dispatch; never message the outgoing, never land its units — swarm ledger docs/handoffs/swarm-<date>-relief-<t>-<k>.md")
```

The relief count is not spent on a draining lead you had to `TaskStop`.

## 7. What arrives from below, and the one verb each gets

| Arrives | Verb | Then |
|---|---|---|
| a lead's **session report** (final text) for a train it was accepting | `mise run whip -- done --lead <name> <master sha> <landed n/m>` | §8 if the run may end, else §3 for the next train |
| `relief now; I keep <unit list>` | `mise run whip -- relieve --lead <name>` (→ `draining`) | spawn the draining relief (§6) |
| the **draining** lead's session report | `mise run whip -- drained --lead <name>` (→ `relieved`), never `done` | `SendMessage(<accepting>, "<name> drained; its units are on master — continue")` — the outgoing never messages it |
| `blocked on <outgoing>` from the accepting lead | `mise run whip -- note "<name> blocked on <outgoing>"` | nothing; the `drained` line above is its wake |
| `interim: <n>/<m> landed, <k> in flight` | none | nothing — not a report |
| a lead moved an issue to Needs design | `mise run whip -- needs-owner --lead <name> <n> "<line>"` | one chat line |
| a **second** report from a lead the ledger shows `done` or `relieved`; any task notification from **below** a lead (a drone's completion report) | none | end the turn — no verb, no chat line |

One chat line per event, never the report re-summarised. A draining lead
counts as live with drones in flight, never as finished.

## 8. Run end

1. The last `done` re-reads the **live** `Ready` column (`gh`), not the
   snapshot. Issues that turned Ready since the start → `mise run whip --
   train add <t> <n…> [--head]` — a `<t>` not yet in the ledger creates a
   queued train, and only a queued train takes issues — then §3. A dropped
   issue never returns. Never a hand edit of the ledger.
2. The run ends only on an empty `Ready`, the owner's `mise run whip --
   stop [--now]`, or the cap — at the later of the last `done` and the last
   `drained`.
3. **Disarm**: `delete_trigger` every id still pending in the `wakes:`
   notes. A refused delete is `mise run whip -- note "wake <id> not deleted:
   <refusal>"` for the owner — never a retry; the stray will fire, read the
   header, note itself `wasted:` and stop.
4. `mise run whip -- report` renders the morning report; `wasted:` notes are
   counted in it. One chat line with the header.

## Never

- Dispatch a drone, read a diff, run `land` or the suite, open an issue body.
- Background a command. Only drone dispatch — inside a lead — is background.
- A cron, a recurring Routine, a third pending wake, a poll of any transcript.
- `ledger adopt`, a bare `ledger show`, a bare `land` — every lead call
  carries `SWARM_LEDGER`; that is the lead's rule, yours is never to look a
  ledger up by session.
- Treat a dead lead's rows as claims, or a live lead's rows as free.
- Run `done` on an `interim:` or `blocked on` line.
- Split a train to fit a window; edit the ledger by hand; import the tool.
- Re-summarise a report, or take a turn on a notification that needs none.
