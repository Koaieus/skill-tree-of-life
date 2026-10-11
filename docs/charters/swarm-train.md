# Swarm-train — charter

The design behind `.claude/skills/swarm-train/SKILL.md` (the one session that
runs a night of trains), the `swarm-lead` agent definition
(`.claude/agents/swarm-lead.md`, the lead as a subagent), `swarm`'s *train
mode* section and the whip tool's *tree transport*. The files are derived from
this; change the wish here, then re-derive. See [README](README.md) for the
protocol. Sibling charters: [whip](whip.md) (the incumbent: the same night as
a relay of `--bg` sessions plus a watchdog; its ledger, trains, cap and report
are reused here unchanged), [swarm](swarm.md) (the lead's cycle),
[relief](relief.md) (the lead that takes a train over), [drone](drone.md).
**Feedback board: `swarm-train — skill feedback board`** (Discussions,
`Skill feedback`), created by the first `mise run feedback -- post swarm-train …`.

This charter was **designed from a spike, not mined** (#1518, 2026-10-09;
four corpus rows in [whip](whip.md) § Incident corpus, dated 2026-10-09). It
exists as a **tryout next to Whip**: the owner keeps one or both after a
night of each (owner, 2026-10-09: *"i think a 2nd skill as tryout might be
best, can then decide which to keep or both"*). Laws marked *probed* rest on
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
     └─ drone × n  (FOREGROUND wave, several Agent calls in one message)
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
- **Waves are the price of the tree.** A lead reacts per wave, not per
  drone: a fast drone's branch waits for the slowest in its wave, and a stop
  drains at the wave boundary. The alternative (background drones under a
  background lead) loses reports (law 4) and is not on the table.
- **One lead at a time**, as in Whip: every lead shares the top's session
  id (probed: `CLAUDE_CODE_SESSION_ID` inside a subagent is the parent's),
  so the swarm ledger's and the whip tool's session keying collide across
  concurrent leads. Sequential leads plus `ledger close` at train end need
  no code; two at once need a per-lead ledger path (fork A, below).

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
   it. No message carries state; relief orients from disk as it does today.

**Process model** (*probed*)

3. **A lead is a background subagent at depth 1.** That is the one depth
   where a background report is proven to reach its parent, and it leaves
   the top's turn free for the tick. A foreground lead would hold the top's
   turn for the whole train: no tick, no stop, no wake until it returned.
4. **A lead dispatches drones as foreground waves.** A background subagent
   never receives its own background children's reports (probed: one
   dropped, one bubbled to the top). Several `Agent` calls in one message
   run concurrently (starts 1.5–2 s apart) and all return in one turn.
   Drones keep their Explore leaves; nesting holds three deep.
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
   notification. Whether stopping a depth-2 foreground drone returns the
   lead's `Agent` call or wedges the lead is unmeasured: the first night's
   first measurement; the recovery path (stop the lead, relief from disk)
   exists either way.

**The tick** (*designed*)

8. **Wakes are one-shot, recorded, and all cancelled when the run ends —
   never a cron, never polled.** A recurring Routine outlives its run; so
   did run #1540's boundary wakes, when `delete_trigger` was refused
   "requires approval" without an allow rule (2026-10-10: two fired into
   the finished run, one uncached — owner, 2026-10-11: *"So you're forced
   to take uncached turns? Heresy."*). With the remote trigger tools
   allowlisted in `.claude/settings.json`, the first delete went through
   (2026-10-11, auto mode, n=1). So the top arms **every window boundary
   under the cap at start** (≈ 5 h 05, 10 h 05, 15 h 05 — the spent-window
   insurance, each one independent of the last) plus **the next tick**
   (`now + tick-minutes`, re-armed by the tick that consumes it while the
   run is live), records each id in a `wakes:` note, and when the run ends
   deletes every one that has not fired (owner, 2026-10-11: *"we can clear
   any unneeded"*). A refused delete is a `note` for the owner, never a
   retry; the stray then fires into a finished ledger, reads the header and
   stops. `/loop` self-paced is the same shape without the server. Which
   wake survives a spent window is still unmeasured.
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
   a lead to watch, not a finished one.
10. **Relief is a fresh `swarm-lead` with the relief prompt**, oriented
    from the ledger as `relief` already does — but never `ledger adopt`:
    a subagent shares the top's session id (probed, 2026-10-10), so
    `ledger show` already prints the outgoing lead's live ledger and an
    `adopt` fails as "already leads". The top launches it; nobody else.

**Reuse** (*designed*)

11. **The whip tool carries a tree transport, not a second tool.** `start
    --tree` snapshots, splits trains, writes the ledger and opens the run
    issue, and launches nothing — no daemon, no timer, no linger. `done`,
    `relieve` and `needs-owner` take `--lead <name>` from the top instead
    of keying on the caller's session; `show`, `report`, `train split/drop`,
    `note`, `stop`, `retire` and the cap are unchanged. An issue added
    mid-run is `train add <t> <n…> [--head]` — never a hand edit of the
    ledger (#1540: the top imported the tool from python to do it). The
    report is Whip's report, titles fetched at render.
12. **A lead is `swarm` in train mode.** The `swarm-lead` agent definition
    pins the model (opus) and tools and tells the lead to `cat` the swarm
    and relief skills and apply swarm's *train mode* section: drones as
    foreground waves, no `whip` verbs, report by returning its session
    report as final text, `ledger close` at train end. Slash expansion
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
    reach 150, 200, 250k"*. The lead takes waves until swarm's relief
    threshold, starts none past it, lands what is in flight and reports
    `RELIEF NEEDED` if its train is unfinished. The top never splits a train
    to fit a window; `--size` (issues per train) is a trial knob.
16. **Nothing in the tree backgrounds a command.** A subagent's turn end is
    its report, so a backgrounded suite or baseline ends a drone's turn
    early (the lead then polled its transcript) or outlives a lead's report
    and re-notifies the top with a duplicate (#1540, lead-a and lead-b). The
    lead runs the gate suite in the foreground; every train-mode brief says
    the same. That rule is swarm's (law 32); the top's half is: a second
    report from a lead the ledger shows `done`, and any task notification
    from below a lead, is nothing — end the turn.
17. **The top's chat is one line per event.** The owner is away; a lead's
    report goes to the ledger by verb and to the chat as one line, never
    re-summarised (#1540: ~600 tokens × 5 of prose nobody read).

## Knobs

- `whip start --tree --cap 15 --stall-minutes 45 --tick-minutes 45 [--size 4]` — the
  cap and stall threshold are Whip's; `tick-minutes` is new, bounded
  `[15, 55]` (law 8a: inside the one-hour cache lifetime); `--size` caps
  issues per train and is a trial knob (law 15).

## Open forks — options with costs, owner decides

**A. Concurrent leads.** One at a time needs no code. Two at once needs
either `SWARM_LEDGER=<path>` on every ledger call from the lead's brief, or
an `--as <lead>` identity flag on the ledger tool and the whip tool. Whip
fork A's lean (a second lead only for a cheap train) carries over.
**B. Whip or swarm-train, after a night of each.** The transport ADR
(#1316) is written from both nights' evidence.

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
| 2026-10-10 | run #1540 | drone-blob ended its turn on a backgrounded baseline → lead-a polled its transcript (owner killed it at 4 min); lead-b reported with a suite wait still running → a duplicate report 29 min later; lead-c2 ran the gate foreground and was clean | 16 |

## Fold digest — board `swarm-train — skill feedback board`

- 2026-10-11 · `law-candidate` lead limit is context, train size trial-only → law 15
- 2026-10-11 · `friction` no add/undrop verb mid-run → law 11, `whip train add`
- 2026-10-11 · `friction` wakes not disarmable; blank titles for added issues → law 8, titles at render
- 2026-10-11 · `autopsy` uncached stray wakes, `show` broken past midnight → law 8; `show` reads the newest ledger of 36 h
- 2026-10-11 · `law-candidate` watch ends when Ready is empty → law 14
