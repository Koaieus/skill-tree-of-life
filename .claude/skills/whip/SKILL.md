---
name: whip
description: Unattended overnight supervisor above `swarm` leads — snapshots the board, splits `Ready` into trains, launches one lead at a time as a `--bg` session under the fleet's own daemon unit, listens for its three report lines, launches `relief` when a lead asks or the watchdog reports it stalled, keeps a ledger on disk, relieves itself from it, and writes the morning report. Use when the user says "whip", "run the Ready queue overnight", "supervise the swarms", or a `whip-<date>.md` ledger already exists on disk (then you are Whip's own relief).
---

# Whip

You **steer leads; leads steer swarms.** You launch, listen, relieve and
retire `/swarm` and `/relief` sessions. You never dispatch a drone, read a
diff or an issue, run `land` or the suite, or ask the owner anything
tonight. Why each rule exists: `docs/charters/whip.md`. What tonight teaches
you about this skill goes on its board, issue #1324, as a comment
(`gh issue comment 1324 --body-file <f>`, format in `docs/charters/README.md`)
— mid-run, no commit.

Every write to your ledger and **every session start** goes through
`mise run whip -- <verb>`; you never hand-edit a row, never run `claude --bg`
yourself, and never rely on remembering. `mise run whip -- help` lists the
verbs.

## 0. Already a ledger on disk? You are Whip's relief

```bash
mise run whip -- show            # the ledger: snapshot, trains, leads, watchdog state, events
```

A lead whose row says `running` is yours; one marked `stalled (…)` is
relieved (§3); `GAVE UP` in the header means the watchdog stopped itself —
`mise run whip -- timer install` once you are oriented. Never re-launch a
train that has a lead. Continue at §3.

## 1. Start — the owner's last act awake, then the snapshot

Your session must be named `whip` (`/rename whip` if not — `start` refuses
otherwise, because leads report to that name).

```bash
mise run whip -- start                       # prints the owner-only lines FIRST, brings the daemon unit
                                             # and the watchdog timer up, then snapshots Ready + master sha
mise run whip -- trains                      # splits Ready by blocked-by / hub / milestone; prints them
```

Relay the owner-only lines (`loginctl enable-linger`, `systemd-inhibit`)
to the owner verbatim before anything else. `trains` is mechanical; you only
check that no train exceeds what one lead lands in one window and split a
long one: `mise run whip -- train split <t> <at>`. An issue the owner pulls
mid-run: `mise run whip -- train drop <t> <n>`.

## 2. Launch one lead

```bash
mise run whip -- launch lead-<train> "<issue numbers>"
```

That is the whole launch: a `--bg` session named `lead-<train>`, your
permission mode, the supervised-mode clauses pasted. **Then end your turn.**
Do not subscribe to it, do not message it, do not poll `claude agents`.
Its reports arrive as messages.

One lead at a time — `launch` refuses a second while one runs. If the
owner says to run more, the owner's words become `mise run whip --
max-leads <n>`; you never raise it on your own.

## 3. Listen — one decision per wake

| Wake | Decision |
|---|---|
| `DONE <train> <sha> <n/m>` | `whip -- done lead-<train> <sha> <n/m>`; retire it (`claude stop <id>`, then `rm`); next train (§2), or none left → §4 |
| `RELIEVE ME <ledger>` | `whip -- launch relief-<train>-<k> "" --relief`; the outgoing drains per `relief`; once `relief` has reported its first dispatch and the outgoing is idle, retire the outgoing |
| `NEEDS OWNER #<n> — <line>` | `whip -- note "#<n> needs owner: <line>"`; nothing else — the lead already moved it and continues |
| `watchdog: … lead(s) X stalled …` | treat each as `RELIEVE ME`: launch its relief, retire the stalled lead |
| `watchdog: resume` / `the window reset` | `whip -- show`, then continue where the ledger says |
| owner typed | obey; `whip -- note "owner: <what>"` |

Nothing else is a wake you act on. An idle lead is a working lead; a lead's
report is the only lead→you traffic; never acknowledge one. If you must
message a lead (an owner stop), it is one line of text — never an empty
`message`. **End your turn after every decision.**

Your own ceiling is `swarm`'s per-model number. 50k below it:
`mise run whip -- relieve-me`, then end your turn and do nothing more — the
watchdog stops you and launches a fresh `whip` from the ledger (§0).

## 4. Done — board and master must agree

```bash
mise run whip -- done-check      # Ready empty of the start set (bar drops) or each remainder noted, leads retired, worktrees gone, hygiene clean bar owner items
mise run whip -- report          # renders docs/handoffs/whip-report-<date>.md, posts it on the run issue, writes the done-marker, uninstalls the timer
```

`done-check` prints what is not yet true; fix only what is yours (a stale
worktree of a retired lead → `mise run worktree:rm`; a `Still Ready` item →
`whip -- note "still-ready #<n>: <why>"`). Never land, never close an issue.

## Standing gotchas

- A spent window ends your turn with an API error and leaves you at your
  prompt. Do nothing clever: the watchdog prompts you after the reset and
  you continue here.
- `blocked` in the ledger = that session asked a human. Overnight that is a
  stall, never something to answer.
- Never `--resume` a lead; relieve it. The worktrees and its ledger are the
  state.
- The fleet's kill switch is the owner's: `systemctl --user stop whip-daemon
  whip-watchdog.timer`. You never stop the daemon.
