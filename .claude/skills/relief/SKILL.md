---
name: relief
description: Take over a running `swarm` as a fresh orchestrator session — drones still in the field, worktrees open, merges pending, the outgoing session too deep in context to keep going. Orients from the outgoing orchestrator's continuous briefing (never by re-reading the issues), takes over dispatch/review/merge/test, and lets the outgoing session drain its own in-flight drones and go quiet. Use when the user says "relief", "take over the swarm", "relieve <session>", or an outgoing orchestrator's brief redirects you here.
---

# Relief

`handoff` is the **exit** half — a session closing out because the work is
done or paused. Relief is the **entry** half — a fresh session picking up a
swarm that is still *running*: drones in flight, worktrees open, merges
pending. The two compose; neither subsumes the other. See `handoff`'s "What
this is not" for the same distinction from its side.

## Why this exists — the constraint that shapes everything below

An outgoing orchestrator holds two assets a fresh session cannot inherit any
other way:

1. **The knowledge bank.** Decisions, swings, and dead ends made in
   conversation that no issue, board, or git log carries.
2. **In-flight subagents.** Confirmed non-transferable, both directions
   (2026-08-27): a fresh session cannot reach another session's live
   subagent, and a resumed subagent cannot be handed to a new parent.

Asset 1 is solved by a **briefing** (below). Asset 2 is *not* solvable — it
means the outgoing orchestrator **must stay alive until its drones drain**,
which is the one thing it is still allowed to do. Everything about the
**retiring** state below falls out of that constraint; it is not a
preference.

## The retiring state — the outgoing orchestrator's side of the handover

The moment relief is requested (see thresholds below), the outgoing
orchestrator enters **retiring**. Its whole contract, described from `swarm`'s
side in that skill's "Stop compliance and relief" section:

- **Let in-flight subagents finish. Take no other action.** No new
  dispatches, no merges, no test runs, no reviews. Target one to two turns
  per drained drone — reading its report and closing it out.
- **Redirect every in-flight drone to report to relief, not to it.** This
  redirect is the outgoing orchestrator's last deliberate act before going
  quiet: message every live worker that on completion it should
  `SendMessage`/report to the relief session.
- **Merging, reviewing, and the authoritative test run move to relief
  immediately** — not after the last drone drains. Relief owns those from
  the moment it goes live, even while the outgoing session is still watching
  its last workers finish.

This is the scope answer: relief takes over *everything except draining the
outgoing session's own in-flight drones*, because that one thing cannot be
handed off any other way.

## Requesting relief — thresholds

- **Request relief at ~180k context.** Deliberately earlier than the
  degradation point below — 180k ≈ 250k minus one orientation window, so
  relief is oriented *before* the outgoing session degrades, not after.
- **Hard stop at 250k: no new dispatch, ever**, relief-requested or not. 250k
  is the measured point real orchestrators lost track of their own in-flight
  work (below).
- **The duplicate-dispatch tripwire overrides every number, and needs no
  instrumentation.** If a drone replies "already done" / "I already executed
  this" to a fresh dispatch, relief is overdue *now* — the orchestrator has
  lost track of what it already sent out. Two real cases (`tooltip-fan`,
  `participant-id`) both fired north of ~250k.
- **A manual owner trigger always overrides** every number above, in either
  direction — the owner can call for relief early, or tell an orchestrator to
  stand down, and that wins.
- The context-size signal makes 180k/250k self-observable without guessing
  (see `drone`'s context-budget section); treat the numbers above as the
  thresholds to act on once you can see them, not as a reason to estimate
  blindly if you can't yet.

## The briefing — bounded, continuous, and the point of the whole exercise

**Relief does not re-read the issues.** Doing so is the failure mode this
skill exists to prevent: full research arrives relief pre-bloated, exactly as
expensive as the session it's replacing. Relief's orientation is exactly two
things:

1. **`docs/handoffs/swarm-<date>.md`** — one file per swarm run, both the
   briefing and the dispatch ledger. See `swarm`'s dispatch section for who
   writes it and when; relief only reads it.
2. **`mise gh-project -- list in-progress`** — the persistent board, to
   cross-check the ledger against reality.

That's the whole orientation. **Target: relief oriented under ~60k context
before its first dispatch.** If reading the file plus the board leaves you
short of orientation, the gap is a bug in the file (it's stale, or missing a
decision) — go fix the file, don't go read the issues to compensate.

The file itself (owned and updated by `swarm`, not written by this skill)
carries a roster table (unit / brief file / drone name / state), unpersisted
decisions and swings — each reduced to a pointer once it lands in its real
home, per `.claude/rules/handoffs.md` — and next steps / queue order. It is
rewritten in place on every dispatch, report, merge, and owner call, never
appended to, and stays bounded to roughly 1.5k tokens. Because it's
continuous rather than a death-bed dump, the outgoing orchestrator's
retiring-state briefing act shrinks to "confirm the file is current, add the
last-mile delta" rather than composing a knowledge dump from scratch at 250k.

## Overlap window — bounded, not open-ended

The measured baseline (`relief-1`, below) took **39 minutes** from going live
to its first dispatch — during which the outgoing orchestrator was still
spawning drones it had already been told to stop spawning. That is the
number to beat, not the target: the continuous briefing above is what makes a
short overlap achievable, since relief no longer has to reconstruct state
from a death-bed message written under time pressure.

## Fable advisor — optional colour, not contract

`relief-1` used a Fable advisor subagent for strategy, and the owner credited
it with the clean overview. Nothing measured isolates the advisor's
contribution from "fresh context + a good briefing," which is what the
owner's own framing names as load-bearing. Use one if you like — it's a
reasonable enhancement — but it is not part of this skill's contract, and its
absence is not a deviation.

## Worked example — `relief-1`, 2026-08-27

`swarm-v2` reached 319,941 tokens across 369 turns, having dispatched ~10
drones and executed 17 merges, when the owner spun up `relief-1` by hand —
this skill formalizes what was then improvised.

| | swarm-v2 (outgoing) | relief-1 (incoming) |
|---|---|---|
| assistant turns | 369 | 181 |
| output tokens | 309k | 177k |
| peak context | **320k** | **200k** |
| full suites run | 11 | 0 |
| merges executed | 17 | 0 |

`relief-1` stayed in healthy territory for its entire life — 200k peak vs
swarm-v2's 320k — but the handover itself was expensive and manual: it took
an explicit owner message ("you are the one that should be launching drones
now"), and even then `relief-1` took 7–8 turns before its first dispatch,
then never merged at all — dispatch moved, review and merge stayed on
`swarm-v2` the whole run. This skill's job is to make the parts that were
manual (the redirect, the scope split, the trigger) automatic, and the part
that was slow (orientation) fast, via the continuous briefing rather than a
death-bed one.

## What this is not

- **Not a way to avoid ever hitting a context limit.** It moves the limit's
  cost, it doesn't remove it — a swarm still ends when nobody is left to run
  it.
- **Not `handoff`.** `handoff` closes a session that is *done*; relief takes
  over one that is still running. See `handoff`'s cross-reference.
- **Not a replacement for sizing the swarm correctly in the first place**
  (`swarm`'s "Size the swarm to the window"). Relief is the recovery path,
  not a reason to size more aggressively.
