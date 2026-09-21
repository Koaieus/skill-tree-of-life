# Relief — charter

The design behind `.claude/skills/relief/SKILL.md`. The skill is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol. Sibling charters: [swarm](swarm.md) (whose cycle relief
runs once it has oriented, and whose law 6 says when to request it),
[drone](drone.md) (the leaf whose worktree is the state relief recovers),
[relay](relay.md) (swarm at wave size 1 — relieved the same way).

This charter was **designed, not mined**: the owner asked for the skill's
shape to be revisited before a charter was lifted from it, and the shape
changed. The old file was a mirror of swarm written from the retiring
session's side — thresholds, an overlap-window narrative, a worked-example
table. What survives of it is its numbers, in the corpus.

## What relief is for

Relief is **the fresh session that continues a swarm whose lead is dead or
past its ceiling** — drones possibly still in flight, worktrees open,
branches reported but not landed. It is a **re-entry protocol, then swarm**:
orient from disk, reconcile the ledger to reality, classify every unit, and
from there run `swarm` with the partial units dispatched as resume-briefs.
One shape serves both cases. A crash (tokens ran out, the session and every
subagent under it died) is the disk path alone; a live handover (the lead
is at its ceiling but alive) is the same path plus a one-line ping per
drone as they drain. Owner, 2026-09-21: *"the relief is basically
'continuation of a swarm', possibly the skill itself is only about transfer
logic/instructions with instructions to call `swarm` later down the line
(else it would to a large extent just be a mirror of swarm?)"* — that is the
pick.

`handoff` is the exit half (a session closing out); relief is the entry
half (a session picking up a run still in motion). They compose.

## The cost model

A handover pays two things: **N wakes of the outgoing** (one per in-flight
drone, each a cache-read turn at the outgoing's peak context — about a
fresh agent's worth of tokens apiece) and **relief's orientation** (the
ledger, the board, the worktrees; target ~60k before the first dispatch).
Against that stands a lead compounding past its ceiling, where every
further turn costs more than the last and a duplicate dispatch is one turn
away. Everything after orientation is swarm's cost model, unchanged.

The drain-versus-stop question is decided by this arithmetic. Draining
never blocks relief: relief's dispatches are its own subagents, and stopping
a drone to restart it under relief makes that unit land *later*, never
sooner. A drain costs one outgoing wake per drone; a stop costs a
resume-drone's re-orientation plus the risk of misreading a half-done
worktree. Drain is cheaper for any drone past its first few calls, and
cheaper the more drones there are. What made draining look expensive
historically was the outgoing doing *other* things at 300k — reviewing,
landing, dispatching — not the wakes themselves.

Orientation reads disk, never issues: the ledger is ≤ ~1.5k tokens and the
worktrees are ground truth; an issue is ~5–10k each and says nothing about
what was done. A stale ledger is fixed from `git`, or with one question to a
live outgoing — never by reading issues to compensate.

## Laws

1. **Orient from disk only.** The ledger `docs/handoffs/swarm-<date>.md`,
   `mise gh-project -- list in-progress`, `git worktree list`, and per
   worktree `git log master.. --oneline` + `git status --short`. Never the
   issues. A gap between ledger and git is a stale ledger: fix the ledger
   from git (dead outgoing) or ask the outgoing one question (alive).
2. **Classify every unit before the first dispatch, and rewrite the ledger
   to say so.** Five classes: **landed** (sha on master — nothing to do);
   **branch-ready** (reported, not landed — relief reviews and
   `mise run land`); **partial** (commits or WIP in a worktree, no report —
   a resume-brief naming the worktree, the branch, and "read
   `git diff master...` first"); **unstarted** (a fresh brief); **in flight
   under a live outgoing** (wait for its ping).
3. **Uncommitted WIP in a dead drone's worktree is state, not garbage.**
   Relief commits it as `wip(<scope>):` in that worktree before dispatching
   a resume-drone; a resume-drone reads a commit, never a dirty tree.
4. **Then it is swarm.** Relief runs swarm's cycle from the reconciled
   ledger and restates nothing of it — briefs, tiers, `land`, the train,
   teardown are swarm's. The skill ends by invoking `swarm`.
5. **A live outgoing owes exactly one wake per in-flight drone.** On each
   drone's report: update that drone's ledger row, `SendMessage` relief one
   line (`#<n> reported @<sha>, row updated`), stop. No dispatch, no merge,
   no test, no review, and **no redirecting drones** — a drone's report
   reaches its spawner regardless, so the outgoing's wake *is* the relay
   and a redirect only adds an address every drone must learn. Relief
   states its own name in its first message to the outgoing so the ping
   has an address. "Stop the drones" is never a deliberate act: it is what
   a crash looks like, and law 1–3 handle it; the owner's manual stop stays
   as the override (swarm law 7).
6. **Sage does not cross the handover.** A subagent dies with its parent,
   so a dead outgoing's Sage is gone; a live outgoing's Sage keeps answering
   *its* drones until they drain and is not reachable by relief. Relief
   spawns its own if swarm's Sage rule says so; `APPROVED <sha>` lines
   already in the ledger stand.
7. **Relief carries no thresholds.** Swarm law 6 says when to request it
   (the per-model ceiling minus 50k); the duplicate-dispatch tripwire, a
   crash and the owner are the other triggers. Any number in the relief
   skill is a contradiction waiting to happen.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-08-27 | relief-1 | `swarm-v2` hit 320k / 369 turns / 11 full suites / 17 merges before the owner spun up `relief-1` by hand; relief-1 peaked at 200k but took 39 minutes and 7–8 turns to its first dispatch and never merged — review and landing stayed on the outgoing. The origin of the skill, and of orientation-from-a-continuous-ledger | 1, 2, 4 |
| 2026-09-10 | spend limit | two drones killed in one minute; one had committed nothing and was saved only by the lead committing its worktree by hand — the worktree is the state | 3 |
| 2026-09-19 | `f9` → `b6` | an Opus relief at the 200k ceiling; one in-flight drone was drained by redirecting it to the new session's address — the last run of the old shape, and the case for the N-wakes contract over a redirect | 1, 5 |
| 2026-09-21 | owner | "continuing swarm runs that crashed mid-run (including taking down all subagents) due to running out of tokens" and "have an active swarm but main orchestrator needs replacement … let its drones finish the work (better hard-stopping them and restarting in the relief session) and could bring the relief session's main agent up to speed via SendMessage"; on the drain answer: "yes"; on N wakes and nothing else: "yes"; on redirecting drones to relief: "the final message would always end up back at their original main" | 4, 5 |

## What the skill must not contain

- Any threshold (the old file's 180k / 250k contradicted swarm's per-model
  ceiling); it points at swarm's law.
- The retiring state written from swarm's side, the overlap-window
  narrative, the worked-example table, the "Fable advisor optional"
  section — all history, all here.
- Dead pointers: `.claude/rules/handoffs.md` does not exist; swarm has no
  "Stop compliance and relief" section.
- Any restatement of swarm's cycle or of drone-side rules.
- Any row above, any issue number, any date.

## Open follow-ups

- `/compact` with drones in flight is a swarm-charter follow-up; if it
  works, the live-handover case gets rarer and relief's shape is unchanged.
- Whether swarm should pre-create the ledger with a unit-class column so
  relief's classification is a diff, not a rewrite — a sibling if it bites.
