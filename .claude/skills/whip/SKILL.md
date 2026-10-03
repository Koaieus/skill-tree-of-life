---
name: whip
description: Run the `Ready` queue unattended as a relay of swarms — `/whip` from any session (a terminal, Remote Control on a phone, a `--bg` session) snapshots the board, splits `Ready` into trains, launches the first `swarm` lead as a detached session and sets up its own zero-token watchdog; each lead passes the baton by verb (next train, or its own relief), the watchdog relieves stalls, the last lead renders the morning report. The calling session is only the owner's console. Use when the user says "whip", "run the Ready queue overnight", "estafette", "chain the swarms"; a live `whip-<date>.md` ledger on disk makes you its console, never a second start.
---

# Whip

**Leads steer swarms; the relay hands the baton from lead to lead.** You
start the relay and then you are the owner's **console** — you decide
nothing, every decision is a verb's. Nothing in whip dispatches a drone,
reads a diff or an issue, runs `land` or the suite, or asks the owner
anything tonight; no laundering either way. Why each rule exists:
`docs/charters/whip.md`. What tonight teaches you about this skill goes
on its board: `mise run feedback -- post whip <kind> <file>` (format in
`docs/charters/README.md`).

Every write to the ledger and **every session start** goes through
`mise run whip -- <verb>`; nobody hand-edits a row, runs `claude --bg` by
hand, or relies on remembering. `mise run whip -- help` lists the verbs.
The lead-side half of the contract — what a lead runs where it would have
asked a human — is `swarm`'s *whip relay* section; you never restate it.

## 0. Already a ledger on disk? You are its console

```bash
mise run whip -- show            # snapshot, trains, leads, watchdog state, warnings, events
```

A live ledger means a run is in flight and needs no one: do not `start`,
do not launch, do not relieve. Answer the owner from `show`; a stop is
§2's verb. A header that says `DONE`, `CAPPED` or `GAVE UP` is a finished
run: `start` retires a done one by itself; a live one the owner did not
mean to continue is theirs to `mise run whip -- retire --force` — never
yours.

## 1. Start — one verb, from anywhere

```bash
mise run whip -- start [--cap <hours>] [--max-leads <n>] [--stall-minutes <m>]
```

That is the whole incantation. `start` brings the fleet's daemon unit and
the watchdog timer up, snapshots `Ready` and master, writes the trains,
opens the run issue, and launches the first lead(s) under the ceiling —
every lead is a detached session under the daemon unit, never a child of
yours, so you (a terminal, a phone, anything) may go away. It refuses only
a live ledger (§0).

Relay its information lines to the owner once, in your own words: the
kill switch, the sleep inhibit it cannot verify, a linger it could not
enable. They are information, not prerequisites — a warning rides in the
report. The cap is the night's runtime ceiling (default 15 h): past it
nothing launches, a lead in flight finishes its train, and the report says
`CAPPED` — you never argue with it.

`start` prints the trains. Trains are mechanical (board dependencies,
milestone order); your only check is that no train exceeds what one lead
lands in one window: `mise run whip -- train split <t> <at>` before the
first `done` reaches it. An issue the owner pulls mid-run: `mise run whip --
train drop <t> <n>` — the ledger remembers the drop, nobody else does.

**Then end your turn.** Do not subscribe to a lead, do not message it, do
not poll `claude agents`. Nothing wakes you but the owner.

## 2. Console — the owner typing is your only wake

| Owner says | You run |
|---|---|
| status / how is it going | `mise run whip -- show`; answer from it in a few lines |
| stop / wrap up / no more trains | `mise run whip -- stop` — nothing launches from now on, running leads drain and land what is reported, the last `done` renders the report |
| stop now / kill it | `mise run whip -- stop --now` — leads are stopped, the report is rendered at once |
| go HAM / run N at once | `mise run whip -- max-leads <n>` with the owner's number — never your own |
| anything else worth the morning | `mise run whip -- note "owner: <what>"` |

One verb per owner message, then end your turn. You never relieve a lead,
never answer a lead's question, never render the report yourself — the
watchdog relieves stalls with no tokens, and the report is the last
`done`'s, the watchdog's at cap or give-up, or `stop --now`'s.

## Standing gotchas

- An idle lead is a working lead; a `blocked` or silent one is the
  watchdog's to relieve. You never `--resume`, `stop` or message a lead.
- A spent window ends a session's turn with an API error and leaves it at
  its prompt; the watchdog prompts it after the reset. Nothing to do.
- The fleet's kill switch is the owner's: `systemctl --user stop
  whip-daemon whip-watchdog.timer`. You never stop the daemon.
