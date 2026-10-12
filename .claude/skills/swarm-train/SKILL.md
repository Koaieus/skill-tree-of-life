---
name: swarm-train
description: Run the `Ready` queue unattended as a tree of subagents — `/swarm-train` from a session that stays up all night (a terminal, Remote Control, the web app) snapshots the board, puts `Ready` in one train (or `--size <n>` of them), and spawns one background `swarm-lead` per train, one at a time; the session itself is the top: it ticks on a scheduled wake, relieves a stalled or cut-off lead with a fresh one, records every outcome in the whip ledger, and the last `done` renders the morning report. Nothing runs outside the session. Use when the user says "swarm-train", "run the Ready queue overnight as a tree", "train the swarms"; a live `whip-<date>.md` ledger on disk makes the session its console, never a second start.
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
beside it, keyed by its name: `docs/handoffs/swarm-<date>-<lead-name>.md`,
`<date>` the whip ledger's, written by that lead alone; a relief reads its
predecessors' files by name and writes its own. No message carries state — a relief orients
from disk, and so do you after a window reset. `mise run whip -- help`
lists the verbs; the ones you run take `--lead <name>`, because every lead
shares your session id — which is also why a lead's prompt names its swarm
ledger path: the ledger tool's session lookup is blind inside the tree and
the lead derives nothing. The lead's half of the contract is `swarm`'s
*Train mode* section; you never restate it in a prompt.

**Your chat is one line per event.** The owner is away: a start, a spawn, a
report, a tick, a relief is one line to the chat (train, n/m, needs-owner
count) and the rest goes to the ledger by verb — never re-summarised.

## 0. Already a ledger on disk? Console or top

```bash
mise run whip -- show            # header (tree · tick), trains, leads, warnings, events
```

A live tree ledger means a run is in flight. `ListAgents` shows a
`lead-*` or `relief-*` row → you are its top: §4 is your next move.
Otherwise you are the owner's **console** (§5): answer from `show`, do not
`start`, spawn or relieve. A header that says `DONE` or `GAVE UP` is a
finished run: `start` retires a done one by itself; a live one the owner
did not mean to continue is theirs to `mise run whip -- retire --force` —
never yours.

## 1. Start — one verb, then arm the wakes

```bash
mise run whip -- start --tree [--cap 15] [--stall-minutes 45] [--tick-minutes 45] [--size <n>]
```

`start --tree` snapshots `Ready` and master, writes the trains and the
ledger, opens the run issue — and launches nothing. It refuses only a live
ledger (§0). One line to the owner, then on. The cap is the night's runtime
ceiling: past it nothing is spawned, a lead in flight finishes its train,
and the report says `CAPPED` — you never argue with it. `tick-minutes` is
bounded `[15, 55]`; take the default.

**`Ready` is one train.** `start --tree` puts every `Ready` issue in one
train (`--size all` is the default) and you never resize it: a lead's limit
is its context, not its train — it dispatches until its own relief
threshold and asks for relief the moment it lands. `--size <n>` (issues per train) is
passed only when the owner asks for a trial size. Mid-run changes are
verbs, never a hand
edit of the ledger: an issue the owner pulls is `mise run whip -- train
drop <t> <n>` (a drop never returns by itself); one put back or added is
`mise run whip -- train add <t> <n…> [--head]` (a queued train, or a new
name for a train at the end). Issues that simply turn `Ready` need nothing:
the last `done` refills from the live board.

**Arm the wakes — one-shot, recorded, never a cron, never polled.** First
check the `claude-code-remote` trigger tools (`send_later`,
`delete_trigger`) are in your tool list. Without them the run is `/loop`
self-paced — the same shape without the server, nothing to note or disarm.
With them, **at most two wakes are pending at any moment**, each a
`send_later` whose prompt names its kind:

- **the next window boundary** — `swarm-train boundary` at ≈ start + 5 h 05;
- **the next tick** — `swarm-train tick` at `now + tick-minutes`.

Whichever fires re-arms its own successor while the run is live (§4); you
never arm every boundary up front. Every id you arm, now and on each
re-arm, goes in a `wakes:` note by kind — `mise run whip -- note "wakes:
boundary <id>"`, `note "wakes: tick <id>"` — because the run's end deletes
the ones still pending (§3), the newest id of each kind. Never
`create_trigger` with a cron or any recurring Routine. Then take the first
train (§2).

## 2. The lead — one at a time, in the background

```bash
mise run whip -- next-train --lead lead-<t>     # marks train <t> running under that name, prints its issues
```

Then spawn exactly what it printed:

```
Agent(subagent_type: "swarm-lead", name: "lead-<t>", run_in_background: true,
      prompt: "train mode, train <t>: #a #b #c — you are lead-<t> — ledger docs/handoffs/whip-<date>.md — swarm ledger docs/handoffs/swarm-<date>-lead-<t>.md")
```

The prompt names the lead's own name (its drones' final `SendMessage`
goes to it) and its swarm ledger path, the lead's name under the whip
ledger's date; the lead exports it on every `ledger` and `land` call, and
its first dispatch creates the file. **Then end your turn.** Do not subscribe to the lead, do not message it,
do not poll `ListAgents`. Its report, its `relief now` and a `blocked on`
line are the only wakes you expect from it; the scheduled tick is the only
other. `next-train` skips a train
left empty by `train drop`; it printing `no next train` means nothing is
spawned: queued trains are exhausted, the owner stopped the run, or the
cap passed — the last running lead's `done` ends the run.

## 3. A lead's messages — verbs, then the next train

Two things come up from a lead: a mid-run `SendMessage` asking for relief,
and its final text, the report. Read the first line, then run the matching
verb and nothing else.

**`relief now; I keep <units>`** (a message from a running lead — its
context notice landed; it dispatches nothing more and lands what it has):

```bash
mise run whip -- relieve --lead <name>      # marks <name> draining, points the train at the relief, prints its name and the whip ledger path
```

Spawn the name it printed — never compute the `-<k>` yourself — with a
prompt that opens with `relief`, names the train and the outgoing:

```
Agent(subagent_type: "swarm-lead", name: "relief-<t>-<k>", run_in_background: true,
      prompt: "relief — train mode, train <t>, relieving <name> (draining) — you are relief-<t>-<k> — ledger docs/handoffs/whip-<date>.md — swarm ledger docs/handoffs/swarm-<date>-relief-<t>-<k>.md — read docs/handoffs/swarm-<date>-<name>.md")
```

Two swarm-ledger paths: the relief's own (its name) to write, and the
outgoing's (`<name>`) to read. Say `(draining)` when the outgoing is still
running — the relief then treats that file's rows as claims and dispatches
beside it; say `(dead)` when §4 relieved a lead that is gone. When the
outgoing was itself a relief, list every earlier lead of the train after
`read` too — the train's lead history in `show` — so the relief sees the
whole chain. Nobody runs `ledger adopt`, and you never say so in the
prompt. A refused relief (the tool fails the train on its third) is final:
go to §2 for the next train.

**The draining lead's final text** (it landed its last report and closed
its ledger) — never `done`, which is the accepting lead's:

```bash
mise run whip -- drained --lead <name>      # draining → relieved; refused from any other state
```

Then `SendMessage` the accepting lead one line — `<name> drained; its
units are on master — continue` — it is the only thing that wakes a lead
waiting on the outgoing. Its *Needs the owner* lines go to `needs-owner` /
`note` as for `done`. The run ends at the later of the last `done` and the
last `drained`.

**`blocked on <name>`** (the accepting lead's final text while the
outgoing drains — nothing in flight, every remaining unit behind an
outgoing one): `mise run whip -- note "<lead> blocked on <name>"`, nothing
else — never `done`; the `drained` line above is its wake.

**A second report from a lead the ledger shows `done` or `relieved`**, a
drone's six-line report reaching you (it goes to its lead by
`SendMessage`; its ordinary completion notice also surfaces here whenever
the lead's turn had ended), or any other task notification from below a
lead (its commands, its drones):
nothing — end the turn.

**Any other report** — the train is finished, landed or not:

```bash
mise run whip -- needs-owner --lead <name> <n> "<one line>"   # once per line under its `Needs the owner`
mise run whip -- done --lead <name> <sha> <n/m>
```

The report is `swarm`'s session report and carries no `done` line of its
own, so you assemble it: `<sha>` is `git rev-parse master` in the main
checkout (one accepting lead at a time, so the tip is that lead's push), `<n>` the
rows in its `Landed` table, `<m>` the train's issue count as `show` lists
it (the ledger, never your memory). A lead that landed nothing reports
`0/m` against the tip. A *Needs the owner* line that names an issue goes to
`needs-owner`; one that names none goes to `note "owner: <line>"`.

`done` prints what follows:

- trains still queued, or refilled from the live `Ready` → §2 with a fresh
  `lead-<t>`;
- `the run is over, the report is rendered` → **disarm**: `delete_trigger`
  the pending wakes — the newest `wakes:` id of each kind, at most two —
  once each; a refused delete is `note "owner: wake <id> still armed"`,
  never a retry. Then end your turn. The report is `done`'s; you never
  render it.

## 4. The tick — the table, nothing else

The wake arrives as `swarm-train tick` or `swarm-train boundary`; its
kind names the wake that fired (the newest `wakes:` id of that kind). One
Bash call reads the ledger and the disk-silence sensor, and one
`ListAgents` reads the tree:

```bash
mise run whip -- show
d=~/.claude/projects/$(pwd | tr / -)/$CLAUDE_CODE_SESSION_ID/subagents
stat -c '%y %n' "$d"/*.jsonl 2>/dev/null | sort | tail -3   # by mtime; the last line is the newest transcript
```

**First line, before the table: `show`'s header says `DONE` or `GAVE UP`
→ this turn is waste: `mise run whip -- note "wasted: <wake id>"` (the
report counts those notes), arm nothing, delete nothing, end your turn —
a stray reads the header and stops. No ledger → arm nothing, end your
turn.**
`CAPPED` is a live run: spawn nothing, run the table for the lead still
in flight, whose `done` ends the run. "Lead" below is each lead `show`
lists as `running` or `draining` — during a relief that is two, the
accepting one and the outgoing still landing its drones; one the ledger
shows `relieved` is not it, whatever `ListAgents` says of it. A
`draining` lead that stalls or is gone gets the same rows, with `drained
--lead` in place of `relieve --lead` (its drones' units then belong to
the accepting lead, which you tell in one line: `<name> is dead; its
ledger is history`).

| You find | You do |
|---|---|
| lead `running`, newest transcript fresher than `stall_minutes` | `noop`; end the turn |
| lead `completed`, its report already acted on (§3 verbs in the ledger) | nothing: the report woke you |
| lead gone (`completed` or `killed`) with its train still `running` in the ledger, no `resume <name> tried` note | `SendMessage` the lead — `window reset: continue from your ledger, then report` — and `mise run whip -- note "resume <name> tried"` |
| the same, and the note is already in the ledger | `mise run whip -- relieve --lead <name>`, spawn the relief as §3 with `(dead)` |
| lead `running`, newest transcript older than `stall_minutes` | `TaskStop <name>`; `mise run whip -- note "stall: <name>, <minutes> min silent"`; `relieve --lead <name>`, spawn the relief as §3 with `(dead)` |
| a `draining` lead gone or stalled the same way | `TaskStop` if running; `mise run whip -- drained --lead <name>`; one line to the accepting lead; no relief spawned |

Ledger `stopped` with a lead `running` (the owner stopped from another
console): `SendMessage` the lead the stop line from §5, once, and `note`
it.

**Re-arm your own successor before ending the turn**, only while the
ledger is live: a tick arms the next tick at `now + tick-minutes`; a
boundary arms the next boundary (≈ 5 h 05 on) if it falls under the cap,
else nothing. The id goes in a `wakes:` note by kind, as §1 — so at most
two wakes are ever pending. A `noop` tick is one cheap turn: read, re-arm,
end — the watch, not waste.

## 5. Console — the owner typing

| Owner says | You run |
|---|---|
| status / how is it going | `mise run whip -- show`; answer from it in a few lines |
| stop / wrap up / no more trains | `mise run whip -- stop`, then `SendMessage` each running or draining lead: `owner stop: dispatch nothing new, land each report as it arrives, then report` — its report comes back through §3 |
| stop now / kill it | `mise run whip -- stop --now` (renders the report at once), then `TaskStop` every running lead and disarm as §3 |
| put #n back / add #n (owner or a sibling session) | `mise run whip -- train add <t> <n…> [--head]` |
| anything else worth the morning | `mise run whip -- note "owner: <what>"` |

One verb per owner message, then end your turn. One lead at a time is
this skill's rule, not a knob: there is no `max-leads` here.

## Standing gotchas

- **A foreground lead blinds you.** `run_in_background: true` on every
  lead, or your turn is held for the whole train: no tick, no stop, no
  wake until it returns.
- **Nothing in the tree backgrounds a command; drone dispatch is the one
  background thing** — a lead's drones run in the background and wake it
  by `SendMessage`; its gate suite and `land` run in the foreground. That
  is the lead's rule from `swarm`, and a prompt of yours never contradicts
  it.
- **Task notifications from below a lead are not reports** — its
  commands, and its drones' ordinary completion reports, which reach you
  whenever the lead's turn had ended: nothing, end the turn. The drone's
  real report went to its lead.
- **A lead's report and its `relief now` are the only wakes you expect
  from it.** A lead idle between drone reports is a working lead: no
  subscribing, no `ListAgents` outside a tick, no message outside §3's
  drained line, §4's rows and §5's stop line.
- **A spent window ends your turn with an API error** and leaves you at
  your prompt. The next boundary wake, or the owner typing, resumes you:
  §0 — you are the top, run §4.
- **A lead's name is its address and its ledger key** (`lead-<t>`,
  `relief-<t>-<k>`); a name the ledger already knows is refused by
  `next-train`, so a fresh train always gets a fresh name. A prompt
  without a `swarm ledger` path spawns a lead whose ledger calls land in
  whichever file is newest — never spawn one.
