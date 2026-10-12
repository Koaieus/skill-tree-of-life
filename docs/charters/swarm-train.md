# Swarm-train — charter

The design behind `.claude/skills/swarm-train/SKILL.md` (the one session that
runs a night of trains), the `swarm-lead` agent definition
(`.claude/agents/swarm-lead.md`, the lead as a subagent), `swarm`'s *train
mode* section and the whip tool's *tree transport*. The files are derived from
this; change the wish here, then re-derive. See [README](README.md) for the
protocol. Sibling charters: [whip](whip.md) (retired: the same night as
a relay of `--bg` sessions plus a watchdog, removed 2026-10-12, #1578; its
ledger, trains, cap and report live on here unchanged), [swarm](swarm.md) (the lead's cycle),
[relief](relief.md) (the lead that takes a train over), [drone](drone.md).
**Feedback board: `swarm-train — skill feedback board`** (Discussions,
`Skill feedback`), created by the first `mise run feedback -- post swarm-train …`.

This charter was **designed from a spike, not mined** (#1518, 2026-10-09;
four corpus rows in [whip](whip.md) § Incident corpus, dated 2026-10-09). It
began as a **tryout next to Whip**: the owner keeps one or both after a
night of each (owner, 2026-10-09: *"i think a 2nd skill as tryout might be
best, can then decide which to keep or both"*). Decided 2026-10-12, owner:
*"tree wins, retire whip"* — the relay transport is removed, not dormant
(#1578; ADR 0056, `docs/adr/0056-overnight-runs-are-one-session-over-a-subagent-tree.md`). Laws marked *probed* rest on
the spike; *designed* ones are picks the first night tests.

## What swarm-train is for

The same morning Whip promises — an empty `Ready` column, a night of commits
on master, one report — from **one session and a tree of subagents**, with
nothing outside it: no daemon unit, no systemd timer, no watchdog process, no
`--bg` identity, no cross-session message. Owner, 2026-10-09: *"considering
switching it to a subagent tree … instead of creating actual sessions and
needing a watchdog and god knows what massive blob of logic"*. The name:
owner, 2026-10-09, *"maybe `/swarm-train` might be apt enough"* — a train is
already Whip's word for a lead's batch, and this skill runs the trains end
to end.

The division of labour stays Whip's: **leads steer swarms; the top steers
leads** — and the top is a session the owner can see, in a terminal, on a
phone, or in the web app, that stays alive all night because it is a
process, not a baton.

```
top session  (/swarm-train: trains, ledger, tick, relief, report)
 └─ swarm-lead  (one per train, BACKGROUND subagent, opus)
     └─ drone × n  (BACKGROUND, several Agent calls in one message;
         │            final act SendMessage(<lead-name>, report))
         └─ Explore  (haiku leaf, foreground)
```

## The cost model

- **The top's context grows slowly, never small.** Only a subagent's final
  text enters its parent, but a lead's session report is 4–5.5 k chars and
  the skill, the start and the owner's chat sit underneath: #1540's top
  went 66k → 120k over four trains (2026-10-10). That is why an uncached
  wake is ~100k re-read, and why law 8 leaves none behind.
- **A tick is one cheap turn.** Reading `ListAgents` and a transcript mtime
  is a few hundred tokens; a tick that finds nothing says `noop` and ends.
- **A lead reacts per drone, not per wave.** Drones go out in the
  background and each wakes its lead by `SendMessage` (law 4), so a fast
  drone's branch lands while the slow one runs, a stop takes effect at
  once, and the 150k notice is acted on the moment it lands instead of at
  the next wave boundary (law 15). The price is a duplicate wake per drone
  (the drone's ordinary report, to the lead or the top) that both treat as
  nothing (laws 4, 16).
- **One accepting lead at a time.** Relief overlaps: the outgoing lead
  `draining` lands what it has and starts nothing; the incoming lead
  dispatches beside it, up to the cap minus the outgoing's drones in
  flight (law 10). The gain is about one wave, 20–40 min, per relief,
  0–3 reliefs a night.
- **One lead at a time**, as in Whip — but the ledger is keyed by name,
  not session. Every lead shares the top's session id (probed:
  `CLAUDE_CODE_SESSION_ID` inside a subagent is the parent's, and a
  subagent's env carries no agent id, probed 2026-10-12), so the swarm
  ledger's session lookup would hand every lead the same file. Inside a
  tree it is never consulted: each lead's ledger is
  `docs/handoffs/swarm-<date>-<lead-name>.md`, exported as `SWARM_LEDGER`
  on every `ledger` and `land` call (law 20). Whether two leads may run at
  once is a separate question (fork C's overlap, #1577), not a keying one.

## Laws

**Scope**

1. **The top steers leads and nothing below them.** It spawns a lead per
   train, ticks, relieves, records and reports; it never dispatches a
   drone, reads a diff, runs `land` or the suite, or opens an issue body.
   Whip's laws 1–3 hold verbatim (nothing escalated overnight; no
   laundering).
2. **The ledger is the shared state.** The whip ledger on disk
   (`docs/handoffs/whip-<date>.json/.md`: trains, lead table, events, cap)
   written by `mise run whip -- <verb>`, and each lead's swarm ledger beside
   it, `docs/handoffs/swarm-<date>-<lead-name>.md` (law 20). No message
   carries state; relief orients from disk as it does today.

**Process model** (*probed*)

3. **A lead is a background subagent at depth 1.** That is the one depth
   where a background report is proven to reach its parent, and it leaves
   the top's turn free for the tick. A foreground lead would hold the top's
   turn for the whole train: no tick, no stop, no wake until it returned.
4. **A lead dispatches drones in the background; each drone's final act
   is `SendMessage(<lead-name>, <its six-line report>)`.** A background
   subagent never receives its own background children's reports by
   itself (probed 2026-10-09: one dropped, one bubbled to the top), but a
   depth-2 background drone's `SendMessage` resumes its depth-1 background
   lead (spike 2026-10-12, n=1; owner: *"Confirm both"*), so the lead
   stays responsive between reports. The drone's ordinary completion
   report still arrives somewhere — at the lead if it is live at that
   moment, else at the top (hypothesis, n=1 each): **a second wake for a
   unit already handled is nothing, end the turn** — the lead's rule and
   the top's (law 16). A drone that ends without its final act is silent
   to its lead; the top's stall tick (law 9) is the net, never a lead-side
   poll. Several `Agent` calls in one message still start together
   (1.5–2 s apart); drones keep their Explore leaves; nesting holds three
   deep. Foreground waves (the first nights' shape) are replaced by this
   contract.
5. **A finished subagent resumes from its transcript.** `SendMessage` to a
   lead's name resumed it with full context after four minutes; a lead cut
   off by a spent window (its last record the limit error) is n=0 — the
   tick tries the resume once, then relieves from disk.
6. **The top sees the whole tree.** `ListAgents` lists every descendant
   flat with `running / completed / killed`; every transcript sits in the
   top session's `subagents/` dir with `parentAgentId` and `spawnDepth` in
   its `.meta.json`, so the deepest running transcript's mtime is the
   disk-silence sensor (Whip law 30, read by the top instead of a timer).
7. **A stall is stopped by name.** `TaskStop <lead-name>` from the top
   stopped a subagent wedged in a 500 s command at once, with a `killed`
   notification. Whether stopping a depth-2 drone wedges the lead is
   unmeasured; the recovery path (stop the lead, relief from disk) exists
   either way.

**The tick** (*designed*)

8. **Wakes are one-shot, recorded, and all cancelled when the run ends —
   never a cron, never polled.** A recurring Routine outlives its run; so
   did run #1540's boundary wakes, when `delete_trigger` was refused
   "requires approval" without an allow rule (2026-10-10: two fired into
   the finished run, one uncached — owner, 2026-10-11: *"So you're forced
   to take uncached turns? Heresy."*). Deleting is not reliable: with the
   remote trigger tools allowlisted in `.claude/settings.json` a delete
   goes through in **auto mode** (n=3, 2026-10-11/12) but was refused in
   **bypass mode with the rule present** (run #1565, ×4: four wakes fired
   into a finished run, one turn each). So a refusal must be cheap, not
   rare: the top keeps **at most two wakes pending — the next window
   boundary** (≈ start + 5 h 05; the spent-window insurance) **and the next
   tick** (`now + tick-minutes`). Whichever fires re-arms its own successor
   while the run is live (a boundary arms the next boundary under the cap;
   a tick the next tick). A wake's prompt and its `wakes:` note name its
   kind (`tick` / `boundary`), so the firing turn knows which successor to
   arm and which id is now spent. Each id goes in a `wakes:` note; when the run
   ends the top deletes the ones pending (owner, 2026-10-11: *"we can clear
   any unneeded"*). A refused delete is a `note` for the owner, never a
   retry; the stray fires into a finished ledger, reads the header and
   stops — at most two such turns. **Before arming, the top checks the
   trigger tools exist** (a CLI session may lack the claude-code-remote
   server, 2026-10-11); without them the run is `/loop` self-paced — the
   same shape without the server. Which wake survives a spent window is
   still unmeasured.
8a. **The tick interval sits inside the prompt-cache lifetime.** The cache
   lives one hour from the last request; a tick at 60 min plus scheduler
   jitter misses it every time and pays the uncached rate on the whole
   context. Default 45 min; in usage overage the lifetime is five minutes
   and the only lever is fewer ticks.

9. **A tick is a four-row table, nothing else.** Lead `running` and its
   deepest transcript fresher than `stall_minutes` → `noop`. Lead gone
   (`completed` with a report the top already acted on) → nothing: the
   report woke the top. Lead gone with its train unfinished (a window cut
   it off) → one `SendMessage` resume (law 5), else spawn relief. Lead
   `running` but every transcript older than `stall_minutes` → `TaskStop`
   it, record, spawn relief. The cap (15 h, Whip law 23) is read at every
   tick: past it nothing is spawned, the lead in flight finishes its train
   and its `done` ends the run — `CAPPED` in the header is a live run with
   a lead to watch, not a finished one. A train may hold two live leads
   during relief: the accepting one and a `draining` one (law 10). The
   table runs for each; a stalled draining lead is stopped like any other
   and its ledger is dead history from then on — the accepting lead, told
   by the top, reclassifies its units (its stop is `drained --lead`, the
   relief count is not spent on it).
10. **Relief of a dead lead reads that lead's ledger file by name**
    — never `ledger adopt`, never a bare `ledger show`: a subagent shares
    the top's session id (probed, 2026-10-10), so the session lookup is
    blind inside a tree and an `adopt` fails as "already leads". The relief
    is a fresh `swarm-lead` with the relief prompt, which names the dead
    outgoing's `swarm-<date>-<outgoing-name>.md` to **read** and the
    relief's own `swarm-<date>-<relief-name>.md` as its `SWARM_LEDGER` to
    **write**: it orients from the outgoing's file as `relief` already does
    and re-dispatches the dead lead's partials with rows in its own file —
    a dead lead's ledger is not live (law 21), so nothing there is a claim.
    A second relief reads its predecessor's file plus the ones that one
    read: the chain of dead ledgers is the train's lead history in the whip
    JSON, each by name. One file per lead, only that lead writes it. The
    top launches the relief; nobody else.
    **Relief of a `draining` lead** (strangler-fig; owner 2026-10-11, *"one
    accepting lead at a time"*, settled 2026-10-12, #1577) differs in one
    thing: the outgoing's file is **live**, so its rows are claims (law
    21). The incoming lead reads it by name while the outgoing still
    writes it, and dispatches only units with no row there and not blocked
    by an outgoing unit not yet landed, up to the cap minus the outgoing's
    drones in flight — the rows in the outgoing's file in state
    `dispatched` (no `reported@`, no `landed`), re-read before each
    dispatch since that file is still moving. The incoming never messages
    the outgoing and never lands its units: the outgoing lands each report
    as it arrives, runs `ledger close` once nothing of its is in flight, and
    returns its session report — the top records it with `drained --lead
    <name>` (`draining` → `relieved`), never `done`, and then resumes the
    accepting lead with one line, `<name> drained; its units are on master
    — continue`, since the outgoing never messages it. An accepting lead
    with nothing in flight and only units blocked on the outgoing ends its
    turn on the single line `blocked on <outgoing>` — not a report, so the
    top runs no `done` on it (a `note`, nothing else); that `drained` line
    is its wake. The run ends at the later of the last `done` and the
    last `drained`.

**Reuse** (*designed*)

11. **The whip tool carries the tree transport, not a second tool** — its
    only transport since the relay was removed (#1578); `--tree` is
    accepted and redundant. `start` snapshots, splits trains, writes the ledger and opens the run
    issue, and launches nothing — no daemon, no timer, no linger. `done`,
    `relieve`, `drained` and `needs-owner` take `--lead <name>` from the
    top instead of keying on the caller's session — `relieve` marks the old
    lead `draining` and points the train at `relief-<t>-<k>`; `drained`
    moves it `draining` → `relieved` on its return, and only from
    `draining`; a draining lead counts as live with drones in flight, never
    as finished; `show`, `report`, `train split/drop`,
    `note`, `stop`, `retire` and the cap are unchanged. An issue added
    mid-run is `train add <t> <n…> [--head]` — never a hand edit of the
    ledger (#1540: the top imported the tool from python to do it). The
    report is Whip's report, titles fetched at render.
12. **A lead is `swarm` in train mode.** The `swarm-lead` agent definition
    pins the model (opus) and tools and tells the lead to `cat` the swarm
    and relief skills and apply swarm's *train mode* section: drones in
    the background with the `SendMessage` final act, `SWARM_LEDGER` on
    every ledger/land call, `relief now` to the top at the 150k notice, no
    `whip` verbs, report by returning its session report as final text,
    `ledger close` at train end. Slash expansion
    inside an `Agent` prompt is unproven, so the lead reads the file.
13. **Sage is out of train mode for the tryout** (tentative, 2026-10-09):
    its `APPROVED` line goes to `main`, which in a tree is the top, not the
    lead, and a sibling-to-sibling resume is unprobed. Drones' advisor is
    the `advisor` tool.

**The run's shape** (*first night, 2026-10-10*)

14. **The watch ends when `Ready` is empty — the live board, not the
    snapshot.** Owner, 2026-10-11: *"Like when Ready queue is empty, your
    Watch ends. End of round."* The last `done` re-reads `Ready` and queues
    trains for issues that turned Ready since the start (a drop never
    returns); only an empty board, the owner's stop or the cap ends the
    run, and at that moment no wake of the top's is armed (law 8).
15. **A lead's limit is its context, not its train.** Owner, 2026-10-10:
    *"normally they could handle more or just should do waves until they
    call for relief between 150-200k ctx (gracefully landing some slack
    allowed but not starting more)"*; *"they are highly aware of when they
    reach 150, 200, 250k"*. The threshold is swarm's (its ceiling, relief
    50k below); what moved (2026-10-12, #1577) is the moment: with
    background drones the context notice lands mid-flight, not at a wave
    boundary, and the lead acts on it at once — dispatches nothing more,
    `SendMessage`s the top `relief now; I keep <unit list>`, lands each
    report as it arrives, closes its ledger, and returns its session
    report. `RELIEF NEEDED` as a report's first line is no longer the
    trigger; a lead whose train is done at the notice simply finishes. The
    top never splits a train to fit a window; `--size <n>` (issues per
    train) is an override of law 19's one train, for trials only.
16. **Nothing in the tree backgrounds a command; only drone dispatch is
    background.** A subagent's turn end is its report, so a backgrounded
    suite or baseline ends a drone's turn early (the lead then polled its
    transcript) or outlives a lead's report and re-notifies the top with a
    duplicate (#1540, lead-a and lead-b). The lead runs the gate suite and
    `land` in the foreground; every train-mode brief says the same. That
    rule is swarm's (law 32); the top's half is: a second report from a
    lead the ledger shows `done` or `relieved`, any task notification from
    below a lead — **the drones' ordinary completion reports included,
    which reach the top whenever their lead's turn has ended** (law 4) —
    is nothing: end the turn, never a verb, never a line to the chat.
17. **The top's chat is one line per event.** The owner is away; a lead's
    report goes to the ledger by verb and to the chat as one line, never
    re-summarised (#1540: ~600 tokens × 5 of prose nobody read).
18. **Every wasted top turn is counted in the report.** Owner, 2026-10-11:
    *"every wasted turn reported"*. A wake that fires into a finished run
    records itself as a `wasted: <wake id>` note before it stops; the report
    counts those notes at render, and one that fires after the render lives
    in the ledger alone. A noop tick of a live run is the watch, not waste.

**One train, per-lead ledgers** (*settled, owner 2026-10-12, #1576 —
fork C's first half; the overlap between leads stays open there*)

19. **`Ready` is one train by default.** Owner, 2026-10-11: *"the Ready
    bulk is one DAG"* — reviewed and taken as settled. `start --tree`
    defaults to `--size all`: every Ready issue in one train, no chain or
    milestone cut; `--size <n>` stays as an override. Nothing about trains
    is removed — a tree run simply has one, and `train merge` is not built
    because one train has no use for it. The drones-in-flight cap inside
    that train is swarm law 4's 2–5, unchanged (a tentative knob, recorded
    here, no code).
20. **A lead's swarm ledger is keyed by its name.** Owner: *"key by agent
    ID … each lead already has a unique name"*; a subagent's env has no
    agent id (probed 2026-10-12), so the name from the lead's prompt is the
    key. The path is `docs/handoffs/swarm-<date>-<lead-name>.md`, carried
    in the lead's prompt by the top (the top owns the whip JSON and the
    names; the lead derives nothing), and exported as `SWARM_LEDGER` on
    **every** `ledger` and `land` call the lead makes — `land` already
    inherits it into its ledger write. A bare call is a bug: the tool's
    session lookup would hand it whichever lead's file is newest, since
    every file's lineage is the top's id. The first `dispatch` creates the
    file. The ledger tool's session-id lookup is never consulted inside a
    tree.
21. **A claim is a ledger row written before dispatch** (swarm law 14). A
    lead never dispatches a unit that has a row in another **live** ledger
    — one whose lead is running or draining. A dead lead's file is not
    live: its rows are history a relief reads (law 10), never claims. With
    one lead at a time the rule never bites; the referee for two live
    leads is fork C.

## Knobs

- `whip start --cap 15 --stall-minutes 45 --tick-minutes 45 [--size <n>]` — the
  cap and stall threshold are Whip's; `tick-minutes` is new, bounded
  `[15, 55]` (law 8a: inside the one-hour cache lifetime); `--size`
  defaults to `all` (law 19: one train) and `<n>` caps issues per train as
  a trial override (law 15). The old default 4 plus the milestone/chain
  split cut 10 Ready issues into 2/2/2/4 (run #1565) and the owner folded
  the queue into one train by hand — hence the default. `next-train` skips
  a train left empty by `train drop` (#1565 left four).
- Drones in flight per lead: swarm law 4's 2–5 (law 19), no code.

## Open forks — options with costs, owner decides

**A. Concurrent leads — the keying half is settled** (law 20: `SWARM_LEDGER`
per lead, named in its brief; the `--as` flag was not built). Whether two
leads run at once, and how they share a train, is fork C's overlap (#1577).
Whip fork A's lean (a second lead only for a cheap train) carries over.
**B. Whip or swarm-train — closed** (owner, 2026-10-12: *"tree wins,
retire whip."*) → [ADR 0056](../adr/0056-overnight-runs-are-one-session-over-a-subagent-tree.md).
**C. Ready is one DAG — closed** (hub #1575; owner, 2026-10-11, folded
in two halves). One train, per-lead ledgers, claim = row → laws 19–21
(#1576). Strangler-fig overlap — background drones that wake their lead,
`relief now` at the notice, a `draining` lead state, the incoming's cap =
cap − the outgoing's in flight — → laws 4, 9, 10, 15, 16 (#1577; spike
2026-10-12 proved the wake; *b* "predict the last wave" and *c* "stay
sequential" were the rejected options). Not built, on purpose: `train
merge` (one train has no use for it), a referee in the top (two live files
plus law 21 need none while one lead accepts), the "run is a directory"
overview file (the whip ledger is it). Still open from the owner's model:
*"trains should be 4~8 issues, sized by issue size and parallelism"* is the
other end of the `--size` knob; the cap as a token-window budget (a spent
window kills every agent at once) is why the drone cap stays 2–5.

## What the files must not contain

- The skill: any probe narrative, issue number, date or corpus row; the
  tick's reasoning (the table, not the why); Whip's process model.
- The `swarm-lead` agent file: swarm's laws or cycle (it reads the skill);
  anything a brief would restate.
- Swarm's train-mode section: the top's tick or relief logic.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-10-09 | spike #1518 | the four probe rows live in [whip](whip.md) § Incident corpus, dated 2026-10-09 | 3–8 |
| 2026-10-10 | run #1540 | first night: 11/11 landed, 4 leads, 15 drones, 2 h 32 min, no relief, no stall; three noop ticks at ~4 calls each on a warm cache | 3, 4, 9 |
| 2026-10-10 | run #1540 | #1536 reinstated and #1549/#1550 added mid-run by a sibling session; no verb, so the top edited the ledger through a python import of the tool; report titles blank for the added issues | 11, 14 |
| 2026-10-10 | run #1540 | `delete_trigger` "requires approval" in a bypass session ×5; wakes fired 33 min and 2 h after the end, the second rebuilding 82.5k of cache; `show` said "no whip run" after midnight | 8 |
| 2026-10-11 | probes | a CLI bypass session had no claude-code-remote tools at all; an auto-mode session with the allow rule deleted a wake first call | 8 |
| 2026-10-11 | run #1565 | 10 Ready → 2/2/2/4 trains at `--size 4`; owner folded them by hand via drop/add, leaving 4 empty trains `next-train` still handed out | knobs, C |
| 2026-10-11 | run #1565 | finished 19:20 after 2 h of a 15 h cap; bypass-mode top, allow rule present, 4 deletes refused; the tick and three boundary wakes armed at start fired into the finished run (2 by 22:18; the last two deleted 2026-10-12 01:40 from an auto-mode session) | 8, 18 |
| 2026-10-10 | run #1540 | drone-blob ended its turn on a backgrounded baseline → lead-a polled its transcript (owner killed it at 4 min); lead-b reported with a suite wait still running → a duplicate report 29 min later; lead-c2 ran the gate foreground and was clean | 16 |

## Fold digest — board `swarm-train — skill feedback board`

- 2026-10-11 · `law-candidate` lead limit is context, train size trial-only → law 15
- 2026-10-11 · `friction` no add/undrop verb mid-run → law 11, `whip train add`
- 2026-10-11 · `friction` wakes not disarmable; blank titles for added issues → law 8, titles at render
- 2026-10-11 · `autopsy` uncached stray wakes, `show` broken past midnight → law 8; `show` reads the newest ledger of 36 h
- 2026-10-11 · `law-candidate` watch ends when Ready is empty → law 14
- 2026-10-11 · `gotcha` ×2 trigger tools absent / allowlisted delete works → law 8 (tool check, `/loop` fallback)
- 2026-10-11 · `autopsy` ×2 #1565 wasted wakes → law 8 (≤2 pending, re-armed by successor; bypass refuses), law 18
- 2026-10-11 · `friction` 2/2/2/4 trains, empty trains handed out → knobs (`--size all`, `next-train` skips empty)
- 2026-10-11 · `law-candidate` ×3 one DAG, window-budget cap, strangler-fig relief, run directory → fork C; one DAG and per-lead files settled 2026-10-12 (#1576) → laws 19–21, law 10 amended; the overlap settled 2026-10-12 (#1577, spike: a depth-2 background drone's `SendMessage` resumes its depth-1 lead) → laws 4, 9, 10, 15, 16, the cost model; fork C closed
