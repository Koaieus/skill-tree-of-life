# Post-LAN melee wave — the next DAG, and the briefs to dispatch it with

Written 2026-09-08 at the end of the ADR-0005 wave. **Spent when #799, #780, #781
and #782 have landed and #801 has a ruling.** Delete it then — every decision it
mentions lives on an issue, an ADR or a rule.

## Where things stand

master `186360c`, **7 commits ahead of origin, unpushed** — an owner call that
has been sitting since the previous wave; there is no foreign commit in it any
more, so pushing is now uncontroversial.

Suite baseline on `186360c`, fresh worktree with **no native binary**:
`0 failing · 3918 passed · 14 pending · 423 scripts` (~208s). The 14 pending are
correct — 13 are `test_blade_native_parity.gd` honestly reporting no binary, 1 is
a deliberate pin. With the binary built + `mise run refresh` the pending count
drops to 1 and the pass count rises accordingly; quote whichever you measured.

**Read first, before any of the briefs below:**

- [ADR 0005](../adr/0005-blade-parts-and-counters-are-orthogonal.md) — nodes deal
  damage, edges give rigidity; spikes pop vertices, bunkers break edges. Carries
  the dead grounds. Do not re-argue it.
- **#186's last comment** (`issuecomment-5590362670`) — the owner's own model of
  severance, verbatim, with the four code claims verified. It is the single most
  useful thing in this wave's context, and #781 in particular depends on it.
- **#801** — the restructure that model implies. Its ruling changes what #781
  costs, so read it before starting #781, not after.

## The DAG

```
#799  ────────────────────────────────────────────►  (independent, land any time)

#801 (Needs design, ruling pending)
  └──►  #781  ──┐
                ├──►  #782
#780  ──────────┘
```

| issue | state | why it sits where it does |
|---|---|---|
| #799 | Ready | Small and mechanical. Touches AI scoring only, collides with nothing. **Start here** if you want a warm-up landing. |
| #780 | Ready | Fortification drag. Touches the sim's damping/velocity path, which is also where #801 would land — see the conflict note below. |
| #781 | Ready **but hold for #801** | Bunker break. Under the current sequential resolve it needs its own copy of #186's scaffolding; under #801's interleaved model it is a constraint removal and nothing else. Doing #801 first makes this issue *smaller*, not merely cleaner. |
| #782 | Ready, but genuinely last | The preview predicts spike pops, bunker shatters **and** fortification drag. Two of those three do not exist until #780 and #781 land, so starting it first means writing a predictor for behaviour nobody has authored. |
| #801 | Needs design | A Fable analysis was commissioned 2026-09-08 and posts to the issue. It presents options with costs rather than one answer; the owner picks. |
| #796 | Ready | The authoritative resolve blocks the main thread. **Not in this wave** — #797 decomposed the premise (see below) and it should be re-read before anyone pulls it. |
| #771 | `design` | Retitled since the last handoff — now *"AI: build the weapon — clamp the first blade joints unless the pivot is already triangulated"*. Not Ready; not this wave. |

### The one file conflict to plan around

**#780 and #801 both land in the sim's velocity/damping path.** #780 adds drag
from fortified defenders; #801 (if the owner takes an interleaving option) changes
when and how the solver is stepped, and owns the home of #186's existing
`BladeFreeFlight.DRAG`. Do not run them concurrently. If #801 is still unruled,
land #780 first and let #801 rebase onto it — #780 is authored gameplay content
and #801 is a restructure, so the restructure should absorb the churn.

**#781 and #782 do not conflict with each other** (resolver vs. UI), but #782
*reads* whatever #781 produces, so it wants #781 merged rather than merely in
flight.

### Why #796 is not in this wave

#797 decomposed its premise and the numbers moved. There is no 2.4 s of
deliberation: an AI turn on the 4-node fixture is ~4979 ms wall but **32.8 ms of
compute**, with **654 of 707 frames parked on the presentation clock** and swing
playback alone 80% of the wall. Within one resolve, the solver is ~4%,
`BladeHitScan` ~22%, and the outcome build+apply pass **~71%**. Whether an NPC
should pay full swing playback is a **pacing** decision, not a perf bug, and
time-slicing is off the table (owner: the playtest laptop *"reached maybe 20-30fps
on average"*, so an AI turn has no idle budget to slice into). Anyone pulling #796
should read #797's comments first and expect to re-scope it.

## Standard rules block — paste into EVERY brief

> `cd <ABSOLUTE> && <everything>` in ONE command with `pwd` as its receipt (cwd
> does not persist; backgrounded commands do inherit it but never assume so).
> Always `git -C <absolute>`. **Never call `advisor`.** Any `Explore` subagent
> pinned `model: "haiku"`. Ladder: `mise run check` (~20s) → `test:one` →
> `test:dir` → **one** full `mise run test` at final green only. A new `.gd` test
> needs its `.gd.uid` committed (`mise run refresh`) or it vanishes silently.
> Never `gh --body` with backticks — heredoc to a file, `--body-file`.
> **The suite: launch it ONCE with `run_in_background: true`; then do nothing —
> no sleep, no tail, no ls, no re-reading the output file; then END YOUR TURN
> with no further output. The harness resumes you when it exits.** Do not push,
> do not merge, do not close the issue — the lead is the merge gate. Report in
> your own final message: branch, tip sha, suite verdict with script count, how
> each acceptance criterion is met, and anything left undone.

All three suite clauses are load-bearing and independent: on 2026-09-08 a brief
carrying the first and third but not the second still produced a worker that
polled ~a dozen times and was killed mid-run. See
`.claude/rules/long-running-commands.md`.

## BRIEF A — #799, popped_nodes (READY TO DISPATCH, Sonnet)

> You are a swarm worker on Skill Tree of Life (/home/bramh/skill-tree-of-life,
> repo Koaieus/skill-tree-of-life). Read CLAUDE.md and the `drone` skill first.
> Your unit: **GitHub issue #799**.
>
> `gh issue view 799` then `gh issue view 799 --comments` — two calls; the
> retargeting comment is the authoritative spec and it narrows the issue a long
> way from its original body. Then read #186's last comment for the model behind
> it.
>
> Two changes, landing together: **`thinned_nodes` counts pops only** — vertices a
> spiked defender actually destroyed, not the vertices those pops merely orphaned
> — and it is **renamed `popped_nodes`** (the owner's word). A `popped_nodes` that
> still counted orphans would be worse than the honest-but-wrong name it replaces,
> so do not split them.
>
> The reason an orphan is not a loss: since #186 a severed vertex keeps coasting,
> armed, and its hits already enter the score through the ordinary resolve path.
> Counting it as thinned makes the AI over-avoid spiked defenders.
>
> It is stamped from `BladePopResolver.LiveGate`'s result in
> `MeleeAttackPlan.resolve_against`. Follow every downstream reader of the old
> name — AI scoring is the one that matters, but grep for it. Pin the distinction
> with a test: a pop that orphans N vertices increments the counter by **one**,
> not by N+1.
>
> [standard rules block]

## BRIEF B — #780, fortification drag (READY TO DISPATCH, Opus)

> You are a swarm worker on Skill Tree of Life (/home/bramh/skill-tree-of-life,
> repo Koaieus/skill-tree-of-life). Read CLAUDE.md and the `drone` skill first.
> Your unit: **GitHub issue #780** — a wall of nodes bogs a blade down.
>
> `gh issue view 780` then `--comments`. Then
> `docs/adr/0005-blade-parts-and-counters-are-orthogonal.md` and
> `docs/domain/melee-blade-sim.md`.
>
> **ADR 0005 binds and constrains the shape of this:** fortification is a *third*
> defensive effect alongside spikes (which pop vertices) and bunkers (which break
> edges). Be explicit in your design about which blade part drag acts on and why —
> if the answer is "neither, it acts on the whole swing", say so and justify it
> against the orthogonal split rather than quietly sidestepping it.
>
> **Monotonic, never reverses** is in the issue title and is the acceptance that
> will be hardest to hold: a drag term integrated per step can overshoot and push
> a blade backwards. Pin it.
>
> **There is already an authored drag constant** — `BladeFreeFlight.DRAG` (0.8/s,
> owner-tunable), reaching the solver as `BladeSim.simulate(linear_damping:)`,
> with the property that **0 is bit-identical to the undamped integrator**.
> Decide deliberately whether fortification reuses that channel or needs its own,
> and preserve the "0 is exact" property either way — a test depends on it.
>
> **Owner tunes, agents test:** author the formula and the plumbing; do not pin a
> specific authored `.tres` value in a test as though it were a spec.
>
> **Native backend:** `BladeSolverNative::simulate` accepts neither damping nor
> seeded velocities today, and `test_blade_native_parity.gd` pins the two backends
> bit-identical. If your change touches the solver's integration, say explicitly
> in your report which backend you changed and what parity now means.
>
> **Heads up on churn:** #801 may restructure how the solver is stepped and owns
> the eventual home of the drag constant. You land first; it rebases onto you.
>
> [standard rules block]

## BRIEF C — #781, bunker break (DO NOT DISPATCH until #801 is ruled)

Everything it needs is already recorded; what is missing is only the #801
decision, which changes the implementation shape entirely.

- The **bunker ruling** is on #781 as an owner-attributed comment
  (`issuecomment-5588314071`): bunkers destroy **structure**, never **matter**;
  matter = vertices, structure = edges. On a rigid blade rammed into a bunker the
  contact is usually at a *vertex* (discs stick out past the capsules, which are
  trimmed to each endpoint's rim), that vertex **survives and cannot pass**, and
  the force goes into its incident edges — so **contact point and failure point
  need not be the same**. Failure criterion: the PBD distance-constraint
  **residual is the strain**; the edge that stays violated across the substeps
  because the bunker will not let the vertex move is the one that fails. No new
  concept needed.
- The **seam already exists and has no caller**: `LiveGate._sever_edge`,
  `BladeState.removed_edges`, `remove_edge()`, `Pop.edge_idx`,
  `Result.severed_at`. The ADR-0005 unit kept them deliberately and re-commented
  them as this issue's entry point. Severance is *recorded*, never spliced out of
  `state.edges`, so every `edge_idx` stays stable.
- **#186 consumes a severed fragment regardless of why it was severed**, so a
  bunker-born fragment already flies with no code in this issue — that is how
  #186's acceptance 5 was satisfied ahead of time.
- **What #801 changes:** under the current sequential resolve, a bunker break
  mid-swing needs its own version of #186's second-sim scaffolding. Under the
  interleaved model it is a constraint removal and the sim just carries on. Write
  the brief *after* the ruling, and say which model it is written against.

## BRIEF D — #782, melee preview (LAST, after #780 and #781 merge)

Not worth briefing yet: it predicts spike pops, bunker shatters **and**
fortification drag, and two of those three do not exist until the briefs above
land. When it is time, front-load the worker with: `MeleePreview` consumes
`last_damage_instances` **FIFO** as its live replay passes each event through the
same `LiveGate` sequence, which is what lets it show
`HitInstance.effective_amount` instead of re-deriving damage from a rebuilt blade
state; and since ADR 0005 an **edge event mints no `DamageInstance` at all**, so
`last_damage_instances` is a *subsequence* of `last_events`, not a parallel array
— a preview that zips the two together will desync.

## #801 — the Fable analysis landed; one owner call away from Ready

Full text on #801 (`issuecomment-5590543090`). Four options — A per-sample
interleave, B optimistic bake + re-bake at severance, C kinematic post-pass,
D keep `BladeFreeFlight` — each with perf / native / replay / #781 cost, plus an
8-point acceptance sketch and a table re-pointing every #186 test.

**It dissolved the crux this file originally stated.** Neither backend needs
per-*step* granularity: the state only changes shape at a severance, which is
rare, so what both need is **continue-from-state per chunk**. Native changes
become additive (~40 lines: `prev_positions` in, integer `step_offset` /
`step_count`, per-particle damping, `prev_samples` out), not a redesign. Time
must be computed as `float(step_offset + s) * dt`, never a float offset, or
parity breaks.

Three further facts it found, none of which were in the issue body, all verified
against master:

- The pop gate is fed by `OutcomeApplier` via `BladeDamageInstance.land_on`, not
  by the scan — so the interleave is sim/scan/**land**, and
  `_fly_severed_fragments` already demonstrates the per-batch idiom. No
  suspendable applier is needed.
- A death is already expressible with **zero C++**: `inv_mass 0` (a frozen corpse,
  which is #787's snapshot for free), incident constraints dropped, its
  `BladeArcDriver` dropped — all per-call inputs to native.
- A **mirror peer runs `plan.resolve()` on a throwaway shadow purely to draw**
  (`battle_system.gd:512-524`, verified). So the stepping core is the peer's draw
  path too — a GDScript-only tail costs peers as well, though the outcome is
  discarded so determinism is untouched.

**Recommended: B**, as two separable units — a GDScript restructure, then the
native continuation — with a cheaper intermediate that stops after unit one. B is
bit-identical to A (the bake is a pure function), costs a no-pop swing *nothing*,
and is strictly cheaper than today on a pop swing.

**Blocked only on the owner confirming B.** Once confirmed: split into the two
units, move to `Ready`, and write BRIEF C against the interleaved model.
