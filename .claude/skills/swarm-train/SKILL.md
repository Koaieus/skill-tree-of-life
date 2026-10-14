---
name: swarm-train
description: Run the `Ready` queue unattended as a tree of subagents — `/swarm-train` from a session that stays up all night (a terminal, Remote Control, the web app) snapshots the board, puts `Ready` in one train (or `--size <n>` of them), and spawns one background `swarm-lead` per train, one at a time; the session itself is the top: it ticks on a scheduled wake, relieves a stalled or cut-off lead with a fresh one, records every outcome in the whip ledger, and the last `done` renders the morning report. Nothing runs outside the session. Use when the user says "swarm-train", "run the Ready queue overnight as a tree", "train the swarms"; a live `whip-<date>.md` ledger on disk makes the session its console, never a second start.
---

# Swarm-train

Why each step says what it says: `docs/charters/swarm-train.md`.

You are the **top**. You steer leads and nothing below them: spawn a lead
per train, tick, relieve, record, report. You never dispatch a drone, read
a diff, run `land` or the suite, or open an issue body. Nothing is
escalated overnight and nothing is laundered. The shared state is the
whip ledger on disk (`docs/handoffs/whip-<date>.json/.md`, written only by
`mise run whip -- <verb>`) plus one swarm ledger per lead beside it,
`docs/handoffs/swarm-<date>-<lead-name>.md`; no message carries state.
Your chat is **one line per event**, never a re-summary of a report.

## 0. Console, not a second start

A live `docs/handoffs/whip-<date>.md` already on disk makes this session
its console: `mise run whip -- show`, then continue at the step the ledger
header puts you in (a lead running → §4 tick; `DONE` → §8). Never `start`
over a live run.

## 1. Preflight

1. **Trigger tools**: confirm the `claude-code-remote` tools
   (`send_later`, `delete_trigger`, `get_session`) are callable. Absent →
   the run is `/loop` self-paced: the same steps, the tick driven by
   `/loop <tick-minutes>m` instead of a wake, and the model read from the
   configured-model line of your own system prompt (or say you cannot
   tell).
2. With the tools present, `get_session` with no id, and read two fields:
   - `external_metadata.permission_mode` must be `auto`. Anything else:
     one line to the owner asking them to switch this session to auto;
     arm nothing and run nothing until they have, or say run anyway.
   - `session_context.model` (not `last_served_model`) must start
     `claude-opus` or `claude-sonnet`. Anything else: one line to the
     owner before `start`; wait for their word exactly as for the mode.

## 2. Start

```
mise run whip -- start --cap 15 --stall-minutes 45 --tick-minutes 45 [--size <n>]
```

`start` snapshots `Ready` and master, writes the ledger, opens the run
issue, and launches nothing. `Ready` is one train by default (`--size
all`); `--size <n>` (issues per train) is a trial override only — never
split a train to fit a window. `tick-minutes` stays in `[15, 55]`.

## 3. Spawn the lead

One accepting lead at a time. Take the train and spawn its lead:

```
mise run whip -- next-train --lead lead-<t>
```

then one `Agent` call — `subagent_type: swarm-lead`, `name: lead-<t>`,
`run_in_background: true` — with this prompt and nothing more:

```
train mode, train <t>: #<n> #<n> … — ledger docs/handoffs/whip-<date>.md — swarm ledger docs/handoffs/swarm-<date>-lead-<t>.md
```

The lead's half of the contract (background drones, `SWARM_LEDGER`,
`relief now`, its nap, its report) is swarm's *train mode* section, which
the lead reads itself; never restate it in the prompt. The lead runs at
depth 1, in the background. Record the spawn as one chat line, then arm the wakes (§4) and end the turn.

## 4. Wakes and the tick

**Arming.** At most two wakes pending, both one-shot `send_later`, never
a cron, never polled:

- `boundary` — the next window boundary, run start + 5 h 05;
- `tick` — `now + tick-minutes`.

Each wake's message names its kind (`tick` / `boundary`) and the firing
turn re-arms its own successor while the run is live: a boundary arms the
next boundary (only under the cap), a tick the next tick. Every id goes
in the ledger as `mise run whip -- note "wakes: <kind> <id>"`, with the
spent id named on its re-arm.

**The tick is this table and nothing else.** `ListAgents` for the lead's
state; the mtime of the deepest `running` transcript under this session's
`subagents/` dir (`.meta.json` carries `parentAgentId` and `spawnDepth`)
for disk silence. Run the table for every live lead of the train — the
accepting one and a `draining` one alike:

| Lead | Deepest transcript | Do |
|---|---|---|
| `running` | fresher than `stall_minutes` | `noop`, end the turn (the watch, not waste) |
| gone, report already acted on | — | nothing: the report woke you |
| gone, train unfinished (cut off) | — | `SendMessage(<lead-name>, "continue")` once; no resume → §6 relief from disk |
| `running` | all older than `stall_minutes` | `TaskStop <lead-name>`, record, §6 relief |

Read the cap at every tick: past it spawn nothing — the lead in flight
finishes its train and its `done` ends the run. `CAPPED` in the header
is a live run with a lead to watch, not a finished one. A stalled
draining lead is stopped like any other; its ledger is dead history from
then on, and the accepting lead, told by you in one line, reclassifies its
units (its stop is recorded `drained --lead <name>`, and spends no relief
count). Never poll a drone's transcript: the lead's nap is the first net
for a silent drone, this stall tick the second.

## 5. What arrives, and the verb for each

| Arrives | Do |
|---|---|
| A lead's session report as its final text | `mise run whip -- done --lead <name> <sha> <landed/total>` (`needs-owner --lead <name> <n> "<line>"` first for each issue it moved to Needs design); one chat line |
| `relief now; I keep <units>` from a lead | `mise run whip -- relieve --lead <name>` (the lead is now `draining`), spawn the relief (§6, draining shape) |
| A draining lead's session report | `mise run whip -- drained --lead <name>` — never `done`; then `SendMessage(<accepting-lead>, "<name> drained; its units are on master — continue")` |
| `blocked on <outgoing>` from the accepting lead | `mise run whip -- note "…"`, nothing else; the `drained` line above is its wake |
| `interim: <n>/<m> landed, <k> in flight` from a lead | nothing: end the turn |
| A second report from a lead the ledger shows `done` or `relieved`; any task notification from below a lead, drones' ordinary completion reports included | nothing: end the turn, no verb, no chat line |
| An issue reinstated or added mid-run | `mise run whip -- train add <t> <n…> [--head]` — never a hand edit of the ledger |
| The owner's stop | `mise run whip -- stop [--now]` |

The run ends at the later of the last `done` and the last `drained`.
`done` itself re-reads the live `Ready` and queues trains for issues that
turned Ready since the start (a drop never returns). After any `done`
whose header is not `DONE`, `next-train --lead lead-<t+1>` (§3): it hands
out the next queued train or says there is none. Only an empty board,
the owner's stop or the cap ends the run.

## 6. Relief

Relief is a fresh `swarm-lead` named `relief-<t>-<k>` (the name `relieve`
printed), spawned by you and nobody else, `run_in_background: true`,
after `mise run whip -- relieve --lead <outgoing>`. Its prompt names the
outgoing's ledger to **read** and its own to **write**, and never uses
`ledger adopt` or a bare `ledger show`:

```
relief, train <t>, outgoing <outgoing-name> (<dead|draining>): read docs/handoffs/swarm-<date>-<outgoing-name>.md and docs/handoffs/swarm-<date>-<outgoing-name>.inbox/ — ledger docs/handoffs/whip-<date>.md — swarm ledger docs/handoffs/swarm-<date>-relief-<t>-<k>.md
```

- **Dead outgoing** (stalled and stopped, or cut off with no resume): its
  file is history, not claims — the relief re-dispatches its partials
  with rows in its own file, and a report file in the outgoing's inbox
  for a unit the ledger shows unlanded is a finished drone whose lead died
  first: the relief lands that branch, never redoes it.
- **Draining outgoing** (`relief now`): its file is live, its rows are
  claims. The incoming dispatches only units with no row there and not
  blocked by an outgoing unit not yet landed, up to the cap minus the
  outgoing's drones in flight; the outgoing lands its own reports, closes
  its ledger and returns — §5 `drained`.
- A second relief's prompt names its predecessor's file plus the ones that
  one read: the chain of dead ledgers is the train's lead history. One
  file per lead; only that lead writes it.

Sage is not in the tree; drones' advisor is the `advisor` tool.

## 7. Boundaries you hold

- A lead's limit is its context, not its train: you never resize a train
  for a window, and a lead whose train is done at its context notice
  simply finishes.
- Nothing in the tree backgrounds a command; only drone dispatch is
  background. Your side of it is the "nothing" rows of §5.
- Every verb you run is `mise run whip -- …` with `--lead <name>` where
  it takes one; `show`, `report`, `train split/drop/add`, `note`, `stop`,
  `retire` are as printed by `mise run whip -- help`.

## 8. Run end

1. Delete every pending wake named in the `wakes:` notes. A refused
   delete is `mise run whip -- note "wake <id> not deleted: <reason>"`
   for the owner, never a retry.
2. `mise run whip -- report` — the morning report, titles fetched at
   render, wasted turns counted from the notes.
3. A wake that fires into a finished run: `mise run whip -- note "wasted:
   <wake id>"`, then stop — read the header, no verb, no re-arm, one
   line at most. A `/loop` run ends its loop here.
