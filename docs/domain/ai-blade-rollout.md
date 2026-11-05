# AI blade rollout

Melee candidate rollout for AI v1.

## Archetype generator and swing direction (`entity/controller/ai_blade_rollout.gd`)

The archetype generator. For each surviving [pivot, max_size] pair:
a single consecutive-from-pivot **handle** (rigidify first, budget rule
not a selection bias — see `_build_archetype`) plus whatever budget
is left spent on a naive greedy **reach** extension (child #824 refines
the preference; this issue only has to not enumerate). Each pivot then
contributes a **handful** of proposals, not every leaf-truncation of a
chain — a hard bound (#823 requirement 1): `_build_archetype`'s
single (members, clamps) result, plus (when the tail has a plain,
unclamped member to drop) one shorter variant, **in both swing
directions** — at most 4 proposals per pivot regardless of `max_size`,
which is what keeps #824's cap lift (16 -> 64) affordable. Each proposal is
[pivot, Array[SkillNode] blade_nodes, bool swing_cw, Array[SkillNode] clamp_nodes].

**Direction is part of a candidate's IDENTITY, not a choice made after
picking one.** Two things make it matter, and only the second is obvious:

  - The blade is a PBD chain, so it LAGS its driver — reversing the sweep
    traces a genuinely different path, not the same circle backwards.
    Measured on a 2-member chain against an off-axis enemy, the coarse
    metric below reads 0.048 one way and 9.210 the other. (A single rigid
    arm really is symmetric: 7.371861 vs 7.371915. So this buys nothing for
    a 1-member blade, and a great deal for anything longer.)
  - Order of contact decides what a defensive spike costs. A pop kills the
    vertex and severs everything downstream from that instant
    (`BladePopResolver`), so sweeping into a spiked hemisphere FIRST can
    zero a swing the other direction would have banked — the owner's #537
    report.

Nothing here estimates either effect. Both directions simply enter the same
ranking and the same gate-accurate finalist resolve, which is what keeps
this a wider search rather than a second scoring path (#537 D4).

## Melee candidate rollout (`entity/controller/ai_blade_rollout.gd`)

Melee candidate rollout for AI v1 (#378 slice C). Ranged/magic candidates
enumerate exhaustively (`AIController`'s `_gather_ranged_candidates` /
`_gather_magic_candidates`); melee can't — the candidate space is every
connected induced subgraph of the attacker's owned territory rooted at a
pivot, up to `blade_size` members, and a full `MeleeAttackPlan.resolve`
(sim + physics-server hit scan) is milliseconds, not microseconds, per
candidate (see the #378 melee-budget comment). This module bounds the
search instead of enumerating it:

  1. Free rejection — every owned node is a candidate PIVOT, but
     `_reach_bound` (BFS over owned territory, `blade_size` hops,
     summed edge length — a real upper bound: PBD constraints keep edges
     near rest length, so no swept particle can get farther than the sum
     of edges along the path that reached it) rejects any pivot whose
     farthest possible reach can't touch the nearest visible enemy, at
     zero simulation cost. `MeleeAttackPlan.build_drivers`'s arc
     drivers sweep a full TAU regardless of swing_cw, so a directional test
     collapses into this same distance check for REACH — a full sweep gets
     to the same places either way. Direction still matters to the swing's
     RESULT, though, and is a proposal dimension in (2) rather than a
     pruning one.
  2. Steerable proposals (#823 archetype generator) — surviving pivots each
     grow ONE consecutive path outward toward the visible-enemy centroid
     (closest-unselected-neighbour-of-the-tip-first, `_grow_path`),
     then `_build_archetype` rigidifies a HANDLE consecutive from
     the pivot (free where the joint is already triangulated or pre-
     clamped, else a phantom `ClampAddon` weld, up to a tier-rolled target
     length — D4) and spends whatever budget is left on a REACH extension
     that prefers spiked, far-from-core nodes (`_reach_score`,
     #824) — its own walk from the handle's tip, not a continuation of the
     centroid-directed path. A HANDFUL of proposals per pivot, not an
     enumeration: this archetype plus at most one shorter reach variant, in
     both swing directions — bounded independent of `blade_size`, which is
     what makes #824's cap lift (16 -> 64) affordable. See
     `.claude/rules/blade-budget-and-clamps.md`. No UCB/
     bandit allocation across pivots: the reach-bound in (1) is already a
     cheap admissible bound, and a cheap bound is exactly the case where
     best-first search beats rollout/bandit-style budget allocation (see
     the melee-budget comment's "On MCMC vs. Monte Carlo" section) — so
     ranking every proposal once and taking the top-K is the right amount
     of machinery, not a shortcut.
  3. Two-tier evaluation — every surviving proposal gets ONE coarse
     `BladeSim.simulate` pass (`dt`=1/30, 4 iterations — ~14x
     cheaper than full fidelity) on `WorkerThreadPool` (simulate() is pure:
     stateless over PackedVector2Array, no Node access, safe off-thread),
     ranked by closest particle-to-enemy approach across the swing. Only
     the top few finalists get a full-fidelity `MeleeAttackPlan.resolve`
     — the only place `BladeHitScan.scan` runs, and it ALWAYS runs here, on
     the calling (main) thread inside `gather_melee_candidates`'s
     synchronous call stack, never inside a WorkerThreadPool task. That's
     the #378 swarmify addendum's hard constraint: scan needs a live
     `PhysicsDirectSpaceState2D` and isn't thread-safe.

`popped_nodes` fed into `AiCombatScorer.score` is
`AttackOutcome.popped_nodes` — blade vertices a defensive spike
actually destroyed this swing (`BladePopResolver`), not blade_nodes.size()
and not the wider set of vertices a pop severed (#799).
Merely selecting nodes for a blade doesn't wound them; only a pop does
(see `AiCombatScorer._SHAPE_RISK_WEIGHT`'s "wound now, heals
~1/turn" doc) — so the risk term should read what the swing actually cost,
not what it merely risked.
