---
name: swarm-train
description: Run the `Ready` queue unattended as a tree of subagents — `/swarm-train` from a session that stays up all night (a terminal, Remote Control, the web app) snapshots the board, splits `Ready` into trains, and spawns one background `swarm-lead` per train, one at a time; the session itself is the top: it ticks on a scheduled wake, relieves a stalled or cut-off lead with a fresh one, records every outcome in the whip ledger, and the last `done` renders the morning report. Nothing runs outside the session. Use when the user says "swarm-train", "run the Ready queue overnight as a tree", "train the swarms"; a live `whip-<date>.md` ledger on disk makes the session its console, never a second start.
---

# Swarm-train

**Leads steer swarms; the top steers leads and nothing below them.** You
are the top: you spawn a lead per train, tick, relieve, record and report.
You never dispatch a drone, read a diff or an issue body, run `land` or the
suite, or ask the owner anything tonight; nothing is escalated overnight
and nothing is laundered in either direction. Why each rule exists:
`docs/charters/swarm-train.md`. What tonight teaches you about this skill
goes on its board: `mise run feedback -- post swarm-train <kind> <file>`
(format in `docs/charters/README.md`).

**The ledger on disk is the shared state.** Every write to the whip ledger
(`docs/handoffs/whip-<date>.json/.md`: trains, lead table, events, cap) goes
through `mise run whip -- <verb>`; each lead keeps its own swarm ledger
beside it. No message carries state — a relief orients from disk, and so do
you after a window reset. `mise run whip -- help` lists the verbs; the ones
you run take `--lead <name>`, because every lead shares your session id.
The lead's half of the contract is `swarm`'s *Train mode* section; you
never restate it in a prompt.

## 0. Already a ledger on disk? Console or top

```bash
mise run whip -- show            # header (tree · tick), trains, leads, warnings, events
```

A live tree ledger means a run is in flight. `ListAgents` shows a
`lead-*` or `relief-*` row → you are its top: §4 is your next move.
Otherwise you are the owner's **console** (§5): answer from `show`, do not
`start`, spawn or relieve. A header that says `DONE`, `CAPPED` or `GAVE
UP` is a finished run: `start` retires a done one by itself; a live one the
owner did not mean to continue is theirs to `mise run whip -- retire
--force` — never yours.

## 1. Start — one verb, then arm the wakes

```bash
mise run whip -- start --tree [--cap 15] [--stall-minutes 45] [--tick-minutes 45]
```

`start --tree` snapshots `Ready` and master, writes the trains and the
ledger, opens the run issue — and launches nothing. It refuses only a live
ledger (§0). Relay its information lines to the owner once, in your own
words. The cap is the night's runtime ceiling: past it nothing is spawned,
a lead in flight finishes its train, and the report says `CAPPED` — you
never argue with it.

`start` prints the trains. Trains are mechanical (board dependencies,
milestone order) and you never resize them: a lead's limit is its context,
and it asks for relief past it. `--size` (issues per train) is passed only
when the owner asks for a trial size. Mid-run changes are verbs, never a
hand edit of the ledger: an issue the owner pulls is `mise run whip --
train drop <t> <n>`; one put back or added is `mise run whip -- train add
<t> <n…> [--head]` (a queued train, or a new name for a train at the end).
Issues that simply turn `Ready` need nothing: the last `done` refills from
the board.

**Arm two wakes — one-shot, one of each, never a cron.** Where the
`claude-code-remote` tools answer, `send_later` with the prompt
`swarm-train tick`:

- **the tick** at `now + tick-minutes`;
- **the boundary** at `now + 5 h 05` (none past the cap).

`mise run whip -- note "wakes: tick <id>, boundary <id>"`. Never more than
these two are armed: a wake re-arms only its own kind (§4), and the run's
end cancels both. Never `create_trigger` with a cron or any recurring
Routine. Where the remote tools do not answer, `/loop` at the tick interval
is the same shape without the server. Then take the first train (§2).

## 2. The lead — one at a time, in the background

```bash
mise run whip -- next-train --lead lead-<t>     # marks train <t> running under that name, prints its issues
```

Then spawn exactly what it printed:

```
Agent(subagent_type: "swarm-lead", name: "lead-<t>", run_in_background: true,
      prompt: "train mode, train <t>: #a #b #c — ledger docs/handoffs/whip-<date>.md")
```

**Then end your turn.** Do not subscribe to the lead, do not message it,
do not poll `ListAgents`. The lead's report is the only wake you expect
from it; the scheduled tick is the only other. `next-train` printing `no
next train` means nothing is spawned: queued trains are exhausted, the
owner stopped the run, or the cap passed — the last running lead's `done`
ends the run.

## 3. A lead's report — verbs, then the next train

A background lead's final text reaches you as its report. Read its first
line, then run the matching verb and nothing else.

**First line `RELIEF NEEDED`** — the lead hands its train over:

```bash
mise run whip -- relieve --lead <name>      # prints the relief's name and the whip ledger path
```

Spawn the name it printed — never compute the `-<k>` yourself — with a
prompt that opens with `relief` and names the train:

```
Agent(subagent_type: "swarm-lead", name: "relief-<t>-<k>", run_in_background: true,
      prompt: "relief — train mode, train <t>, relieving <name> — ledger docs/handoffs/whip-<date>.md")
```

The relief shares your session id, so the outgoing lead's swarm ledger is
already its own: nobody runs `ledger adopt`, and you never say so in the
prompt. A refused relief (the tool fails the train on its third) is final:
go to §2 for the next train.

**A second report from a lead the ledger shows `done`**, or a task
notification from anything below a lead: nothing — end the turn.

**Any other report** — the train is finished, landed or not:

```bash
mise run whip -- needs-owner --lead <name> <n> "<one line>"   # once per line under its `Needs the owner`
mise run whip -- done --lead <name> <sha> <n/m>
```

The report is `swarm`'s session report and carries no `done` line of its
own, so you assemble it: `<sha>` is `git rev-parse master` in the main
checkout (one lead at a time, so the tip is that lead's push), `<n>` the
rows in its `Landed` table, `<m>` the train's issue count as `show` lists
it (the ledger, never your memory). A lead that landed nothing reports
`0/m` against the tip. A *Needs the owner* line that names an issue goes to
`needs-owner`; one that names none goes to `note "owner: <line>"`. `done` prints what
follows: trains still queued (or refilled from `Ready`) → §2 with a fresh
`lead-<t>`; `the run is over, the report is rendered` → **disarm**:
`delete_trigger` each wake id in the `wakes:` notes that has not fired; a
refused delete is `note "owner: wake <id> still armed"`, never a retry.
Then end your turn. The report is `done`'s; you never render it. To the
owner, each report is one line (train, n/m, needs-owner count) — the
ledger holds the rest.

## 4. The tick — the table, nothing else

The wake arrives as `swarm-train tick`. One Bash call reads the ledger
and the disk-silence sensor, and one `ListAgents` reads the tree:

```bash
mise run whip -- show
d=~/.claude/projects/$(pwd | tr / -)/$CLAUDE_CODE_SESSION_ID/subagents
stat -c '%y %n' "$d"/*.jsonl 2>/dev/null | sort | tail -3   # by mtime; the last line is the newest transcript
```

**First line, before the table: `show`'s header says `DONE`, `CAPPED` or
`GAVE UP`, or there is no ledger → disarm as §3 (one try each), arm
nothing, end your turn.** Otherwise "lead" below is the train's current lead
as `show` names it — an outgoing lead the ledger shows `relieved` is not
it, whatever `ListAgents` says of it.

| You find | You do |
|---|---|
| lead `running`, newest transcript fresher than `stall_minutes` | `noop`; end the turn |
| lead `completed`, its report already acted on (§3 verbs in the ledger) | nothing: the report woke you |
| lead gone (`completed` or `killed`) with its train still `running` in the ledger, no `resume <name> tried` note | `SendMessage` the lead — `window reset: continue from your ledger, then report` — and `mise run whip -- note "resume <name> tried"` |
| the same, and the note is already in the ledger | `mise run whip -- relieve --lead <name>`, spawn the relief as §3 |
| lead `running`, newest transcript older than `stall_minutes` | `TaskStop <name>`; `mise run whip -- note "stall: <name>, <minutes> min silent"`; `relieve --lead <name>`, spawn the relief as §3 |

Ledger `stopped` with a lead `running` (the owner stopped from another
console): `SendMessage` the lead the stop line from §5, once, and `note`
it. The cap ends the run at any tick: past it you spawn nothing and the
lead in flight finishes.

**Re-arm before ending the turn**, only while the ledger is live, and only
the kind that woke you: a tick arms the next tick at `now + tick-minutes`;
a boundary arms the next boundary at `now + 5 h 05` (none past the cap) and
a tick if none is pending. `note` the new id. A `noop` tick is one cheap
turn: read, re-arm, end.

## 5. Console — the owner typing

| Owner says | You run |
|---|---|
| status / how is it going | `mise run whip -- show`; answer from it in a few lines |
| stop / wrap up / no more trains | `mise run whip -- stop`, then `SendMessage` the running lead: `owner stop: spawn nothing new, collect the wave in flight, land what is reported, then report` — its report comes back through §3 |
| stop now / kill it | `mise run whip -- stop --now` (renders the report at once), then `TaskStop` every running lead and `delete_trigger` every pending wake of yours |
| put #n back / add #n (owner or a sibling session) | `mise run whip -- train add <t> <n…> [--head]` |
| anything else worth the morning | `mise run whip -- note "owner: <what>"` |

One verb per owner message, then end your turn. One lead at a time is
this skill's rule, not a knob: there is no `max-leads` here.

## Standing gotchas

- **A foreground lead blinds you.** `run_in_background: true` on every
  lead, or your turn is held for the whole train: no tick, no stop, no
  wake until it returns.
- **Never background a drone from a lead** — a lead's drones are
  foreground waves; that is the lead's rule from `swarm`, and a prompt of
  yours never contradicts it.
- **Task notifications from below a lead** (its commands, its drones)
  are not reports: nothing, end the turn.
- **The lead's report is the only wake you expect from it.** A lead idle
  between waves is a working lead: no subscribing, no `ListAgents` outside
  a tick, no message outside §4's rows and §5's stop line.
- **A spent window ends your turn with an API error** and leaves you at
  your prompt. The next boundary wake, or the owner typing, resumes you:
  §0 — you are the top, run §4.
- **A lead's name is its address** (`lead-<t>`, `relief-<t>-<k>`); a name
  the ledger already knows is refused by `next-train`, so a fresh train
  always gets a fresh name.
