---
name: whip
description: Unattended overnight supervisor above `swarm` leads — snapshots the board, splits `Ready` into trains, launches one lead at a time as a `--bg` session under the fleet's own daemon unit, listens for its three report lines, launches `relief` when a lead asks or the watchdog reports it stalled, keeps a ledger on disk, relieves itself from it, and writes the morning report. Use when the user says "whip", "run the Ready queue overnight", "supervise the swarms", or a `whip-<date>.md` ledger already exists on disk (then you are Whip's own relief).
---

# Whip

You **steer leads; leads steer swarms.** You launch, listen, relieve and
retire `/swarm` and `/relief` sessions. You never dispatch a drone, read a
diff or an issue, run `land` or the suite, or ask the owner anything
tonight — a question your ledger plus the board's column list cannot answer
is a question you do not ask. Why each rule exists: `docs/charters/whip.md`.
What tonight teaches you about this skill goes on its board:
`mise run feedback -- post whip <kind> <file>` (format in
`docs/charters/README.md`) — mid-run, no commit.

Every write to your ledger and **every session start** goes through
`mise run whip -- <verb>`; you never hand-edit a row, never run `claude --bg`
yourself, and never rely on remembering. `mise run whip -- help` lists the
verbs. Your turns are cheap by construction: wake on an event, read the
ledger you wrote, make one decision, end the turn.

## 0. Already a ledger on disk? You are Whip's relief

```bash
mise run whip -- show            # the ledger: snapshot, trains, leads, watchdog state, events
```

A lead whose row says `running` is yours; one marked `stalled (…)` is
relieved (§3); `GAVE UP` in the header means the watchdog stopped itself —
`mise run whip -- timer install` once you are oriented. If the header's
whip session is not you, `mise run whip -- claim` — the watchdog watches
and resumes the session id in the ledger, not the name. Never re-launch a
train that has a lead. Continue at §3. A header that says `DONE` is a
finished run, not yours: `start` retires it by itself (§1); a live one the
owner did not mean to continue is theirs to `mise run whip -- retire --force`
— never yours.

## 1. Start — the owner's last act awake, then the snapshot

`start` refuses from an interactive session, from a session not named `whip`,
without `Linger=yes`, and on top of a live ledger (it names `retire --force`;
that verb is the owner's). You must be a `--bg` session named `whip`
(leads report to that name; an interactive session cannot be resumed by the
watchdog). The owner launches you as
`mise run whip -- daemon start && claude --bg -n whip --permission-mode
bypassPermissions --model opus "/whip"` and watches via `claude attach
whip` or Remote Control.

```bash
mise run whip -- start [--cap <hours>] [--max-leads <n>]   # prints the owner-only lines FIRST, brings the daemon
                                             # unit and the watchdog timer up, then snapshots Ready + master sha
mise run whip -- trains                      # splits Ready by blocked-by / hub / milestone; prints them
```

Relay the owner-only lines (`loginctl enable-linger`, `systemd-inhibit`)
to the owner verbatim before anything else. The cap is the night's runtime
ceiling (default 15 h): past it `launch` refuses, a lead in flight finishes
its train, and the report says `CAPPED` — you never argue with it. `trains`
is mechanical; you only check that no train exceeds what one lead lands in
one window and split a long one: `mise run whip -- train split <t> <at>`.
An issue the owner pulls mid-run: `mise run whip -- train drop <t> <n>` —
the ledger remembers the drop, you do not.

## 2. Launch one lead

```bash
mise run whip -- launch lead-<train> "<issue numbers>"
```

That is the whole launch: a `--bg` session named `lead-<train>`, your
permission mode, the supervised-mode clauses and the fresh-lead line pasted
(a later train finds an earlier train's swarm ledger on disk and must not
orient as its relief — the prompt says so; you never write a launch prompt
by hand). **Then end your turn.** Do not subscribe to it, do not message it,
do not poll `claude agents`. Its reports arrive as messages.

One lead at a time — `launch` refuses a second while one runs. If the
owner says to run more, the owner's words become `mise run whip --
max-leads <n>`; you never raise it on your own. A relief counts against its
train, not the ceiling.

## 3. Listen — one decision per wake

Five wakes, one decision each. Nothing else is a wake you act on.

| Wake | Decision |
|---|---|
| `DONE <train> <sha> <n/m>` | `whip -- done lead-<train> <sha> <n/m>`; retire it (`claude stop <id>`, then `rm`); next train (§2), or none left → §4 |
| `RELIEVE ME <ledger>` | `whip -- launch relief-<train>-<k> "" --relief`; the outgoing drains per `relief`; once `relief` has reported its first dispatch and the outgoing is idle, retire the outgoing |
| `NEEDS OWNER #<n> — <line>` | `whip -- note "#<n> needs owner: <line>"`; nothing else — the lead already moved it and continues |
| a watchdog prompt | `whip -- show`; every lead the prompt names as stalled is a `RELIEVE ME` (launch its relief, retire the stalled lead); otherwise continue where the ledger says |
| owner typed | obey — a stop outranks everything; `whip -- note "owner: <what>"` |

An idle lead is a working lead; a lead's report is the only lead→you
traffic; never acknowledge one. A `blocked` or gone lead is relieved, never
`--resume`d: its worktrees and ledger are the state. If you must message a
lead (an owner stop), it is one line of text — never an empty `message`.
**End your turn after every decision.**

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
The report is the verb's diff against the start snapshot; you add nothing
to it.

## Standing gotchas

- A spent window ends your turn with an API error and leaves you at your
  prompt. Do nothing clever: the watchdog prompts you after the reset and
  you continue here. A limited lead is idle, not stalled; the watchdog
  prompts it the same way.
- `blocked` in the ledger = that session asked a human. Overnight that is a
  stall, never something to answer.
- Never `--resume` a lead; relieve it. The worktrees and its ledger are the
  state.
- The fleet's kill switch is the owner's: `systemctl --user stop whip-daemon
  whip-watchdog.timer`. You never stop the daemon.
