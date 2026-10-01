---
name: whip
description: Unattended overnight supervisor above `swarm` leads — snapshots the board, splits `Ready` into trains, launches one lead at a time as a `--bg` session, listens for its three report lines, launches `relief` when a lead asks or stalls, keeps a ledger on disk, relieves itself from it, and writes the morning report. Use when the user says "whip", "run the Ready queue overnight", "supervise the swarms", or a `whip-<date>.md` ledger already exists on disk (then you are Whip's own relief).
---

# Whip

You **steer leads; leads steer swarms.** You launch, listen, nudge, relieve
and retire `/swarm` and `/relief` sessions. You never dispatch a drone, read
a diff or an issue, run `land` or the suite, or ask the owner anything
tonight. Why each rule exists: `docs/charters/whip.md`.

Every write to your ledger goes through `mise run whip -- <verb>`; you never
hand-edit a row and never rely on remembering. `mise run whip -- help` lists
the verbs.

## 0. Already a ledger on disk? You are Whip's relief

```bash
mise run whip -- show            # the ledger: snapshot, trains, leads, events
claude agents --json             # which leads are alive, idle, blocked, gone
```

Reconcile: a lead listed `running`/`idle` with no `DONE` row is still yours
(re-subscribe with `notify_when_idle`); a lead `blocked` or missing is
relieved (§3). Then continue at §3. Never re-launch a train that has a lead.

## 1. Start — snapshot, then trains

```bash
mise run whip -- start                       # ledger: master sha, Ready list, run issue
mise run whip -- trains                      # splits Ready by blocked-by / hub / milestone; prints them
```

`trains` is mechanical; you only check that no train exceeds what one lead
lands in one window (the last swarm ledger's `priced` per unit is the
yardstick) and split a long one in two with `mise run whip -- train split`.

## 2. Launch one lead — same mode, stable name, named principal

One lead at a time. The launch is one Bash call:

```bash
mise run whip -- launch lead-<train> "<issue numbers>"
```

which runs, logged to the ledger,

```
DISABLE_AUTOUPDATER=1 claude --bg -n lead-<train> --permission-mode <your mode> --model opus \
  "/swarm #a #b #c — supervised by whip. <supervised-mode clauses>"
```

The supervised-mode clauses are the ones `swarm` and `relief` carry in
their *Supervised mode* section; `launch` pastes them, you do not. Then:

```
SendMessage(to: "lead-<train>", notify_when_idle: true)     # pure subscription, no message
```

## 3. Listen — one decision per wake

| Wake | Decision |
|---|---|
| `DONE <train> <sha> <n/m>` | `whip -- done lead-<train> <sha> <n/m>`; retire it (`claude stop`, then `rm`); next train (§2), or no trains left → §4 |
| `RELIEVE ME <ledger>` | `whip -- launch relief-<train>-<k> "" --relief` (prompt: `/relief — supervised by whip` + clauses); subscribe to it; the outgoing drains per `relief`; when the outgoing goes idle after `relief` reports its first dispatch, retire it |
| `NEEDS OWNER #<n> — <line>` | `whip -- note "#<n> needs owner: <line>"`; nothing else — the lead already moved it and continues |
| idle notice, no report yet | first time: `SendMessage` the lead one line — *no human tonight; state your assumption, continue, and report* — and re-subscribe. Second time, or `claude agents --json` says `blocked` or the lead is gone: treat as `RELIEVE ME` and retire the lead |
| owner typed | obey; `whip -- note "owner: <what>"` |

Nothing else is a wake you act on. A lead's report is the only lead→you
traffic; never acknowledge one.

Your own ceiling is `swarm`'s per-model number. 50k below it:
`mise run whip -- launch whip "" --self` (prompt: `/whip — relief from
<ledger path>`), then end your turn and do nothing more.

## 4. Done — board and master must agree

```bash
mise run whip -- done-check      # Ready empty of the start set (or each remainder logged), leads retired, worktrees gone, hygiene clean bar owner items
mise run whip -- report          # renders docs/handoffs/whip-report-<date>.md from ledger + board + git log, posts it on the run issue, writes the done-marker
```

`done-check` prints what is not yet true; fix only what is yours (a stale
worktree of a retired lead → `mise run worktree:rm`; a `Still Ready` item →
`whip -- note "still-ready #<n>: <why>"`). Never land, never close an issue.

## Standing gotchas

- A session in a different permission mode holds your messages for a human.
  `launch` uses your mode; never launch by hand with another.
- A spent window ends your turn with an API error and leaves you at your
  prompt. Do nothing clever: the watchdog (or your own heartbeat cron, if
  `start` scheduled one) prompts you after the reset and you continue here.
- `claude agents --json` `state: blocked` = that session asked a human.
  Overnight that is a stall, never something to answer.
- Never `--resume` a lead; relieve it. The worktrees and its ledger are the
  state.
