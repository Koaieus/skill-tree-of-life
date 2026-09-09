---
id: 0014
title: One physics-built defender field — the solver consumes data, it does not query
status: accepted
date: 2026-09-09
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#811"
  - "#810"
  - "#808"
  - "#807"
  - "#780"
  - "#781"
  - "docs/domain/melee-blade-sim.md"
tags: [combat, melee, blade, physics, performance, determinism]
---

# ADR 0014 — One physics-built defender field

## Context

Three places in the melee path answered the same geometric question — *does this
blade vertex disc, or this rim-trimmed edge capsule, overlap that node's disc?* —
with three separate implementations:

- `BladeHitScan` asked `PhysicsDirectSpaceState2D.intersect_shape`. Authority for
  hit events, damage and pops.
- `BladeSwingClock.sense()` / `_zone_overlaps()` re-implemented it analytically,
  once per trajectory sample, to decide whether a Fortification wall drags the
  swing's clock (#780).
- `BladeObstacleField.project()` re-implemented it again, once per solver
  iteration, to push the blade out of a Bunker plate (#781).

They were kept in step by one shared `EDGE_RADIUS` const and comments asking them
not to drift, and their class docstrings said outright that the two models *are
allowed to disagree at the margin*.

The seam that justified this was explicit: **the solver must never touch the
physics space**, because `AiBladeRollout` runs `BladeSim.simulate` inside
`WorkerThreadPool` tasks, where a physics-server query is not safe.

Two further problems rode on top of the same design:

1. **Two O(map) walks.** `MeleeAttackPlan.build_swing_clock` and
   `build_obstacle_field` each walked all ~800 `SkillNode`s and resolved a stat
   on every one — 1744 us and 1701 us on `first_level`, measured with **zero**
   defenders present, i.e. entirely the cost of asking. `build_obstacle_field`
   ran inside `build_blade_state`, which the AI coarse pass calls up to 192 times
   per turn on the calling thread.
2. **A cull that was 65% short (#808).** Both walks bounded the swing by
   `_blade_reach` — the blade's *rest* reach. Swinging a floppy blade straightens
   it: a 5-node W blade whose rest reach is 432 px was measured whipping out to
   714.6 px. Fortified and bunkered nodes in that annulus silently failed to drag
   or deflect, while `BladeHitScan` — which senses off the **live** pose — damaged
   them normally.

Owner, 2026-09-09, on being shown that `sense()` is a hand-rolled reimplementation
of collision detection running alongside `BladeHitScan`:

> *"simulate range, sense(), zoneoverlaps, blade_reach, all of these awfully
> smelly things GONE? and you think that's even a question? of course we want
> that! they shouldve never existed in first place!"*

and, on where the candidate set should come from:

> *"consider this: collision layers. a skillnode that can e.g. deflect -> why not
> toggle 1 extra collision layer bit on? ... sounds EXACTLY like a case for
> collision layers/masks?!?"*

#810 landed that: a `SkillNode` toggles collision layer bit 2 (`swing_drag`) and
bit 3 (`deflection`) off the stat's own local value.

## Decision

**The defender field is built once, on the main thread, by a single
`intersect_shape` against those two collision bits — and the solver then consumes
it as plain arrays, including off-thread.**

Concretely:

- `BladeDefenderZones` is an immutable RefCounted holding centres, radii, drag
  magnitudes, deflect flags and source nodes. `BladeDefenderZones.query()` is the
  only place that touches the physics server.
- `BladeObstacleField` wraps one such zone set and owns every mutable
  accumulator. It is the **only** contact test left in the solver, and it serves
  both zone kinds: a plate is pushed out of and meters strain; a wall is sensed
  and its drag banked on `BladeSwingClock`, and is skipped in the pushout
  entirely. A wall spends the swing's budget; it does not stop the blade, and it
  never enters the `_near` set that arms breaks and stalls grips.
- `BladeSwingClock` keeps the warp accumulator and loses its sensing half
  outright — `sense`, `_zone_overlaps`, `_point_segment_distance_squared`,
  `zone_centers`, `zone_radii`, `zone_drags`.
- `MeleeAttackPlan._blade_reach` and `_is_blade_side` are deleted. The query
  radius is the **chain-length bound** (BFS over the blade's induced subgraph
  summing rest edge lengths, plus an XPBD stretch margin, plus the widest blade
  disc); the blade-side exclusion is `collect_target_excludes()`, the same RID
  list `BladeHitScan` already gets.
- **Zone order is by `SkillNode.stable_id`, and that is a contract.**
  `intersect_shape` returns colliders in undefined broadphase order, and two
  first-wins tie-breaks read that order.

**The grounds the old seam rested on are dead, and this is why.** The only
off-thread `BladeSim.simulate` caller in the repo is
`AiBladeRollout._coarse_rank_and_select` (`entity/controller/ai_blade_rollout.gd`).
Everything else — the preview, the commit, and the three finalist resolves,
explicitly *"never inside a WorkerThreadPool task"* — runs on the main thread. And
under this design the coarse pass does not query anything either: its field was
built for it, before the task started. "The solver must not touch the space
state" is still true; it just no longer implies "the solver must re-derive the
geometry".

## Consequences

- **The predicate is the index.** Finding defenders is O(defenders in range)
  instead of O(map): 36 us replaces 1744 + 1701 us, ~96x, and it is *correct*
  where the walks were not.
- **The radius stops being what makes the work cheap**, so it can be as generous
  as correctness wants. Degradation is one-directional: too large costs a few
  float compares, too small silently drops a defender. Do **not** reintroduce a
  tight rest-pose radius.
- **The coarse AI tier gains Fortification drag**, which it never had — it never
  built a swing clock at all, so a wall that bogs the real swing down used to
  rank as empty ground.
- **One query per PIVOT, not per proposal.** The zone set is immutable, so a
  pivot's ≤32 proposals share one instance while each holds its own mutable field
  wrapper and clock. 12682 us vs 18447 us at 192 proposals.
- **More swings take the GDScript solver path.** `BladeSim.simulate_range` gates
  the native backend on `clock == null and obstacles == null`, and under one
  merged field any swing near any defender has a field. Accepted here; giving the
  native backend a constraint hook is #813.
- **A generous field must be broad-phased.** Walked naively, dozens of zones ×
  every solver iteration cost +29% on a blade-size-4 prediction. `project()`
  recomputes the blade's AABB from the current pose each iteration and rejects
  zones outside it — exact, no safety margin, and it brings the cost back to
  noise. Keep it.
- **Drag sensing moved from per-sample to per-substep** (4x finer). Onset can
  only move earlier-or-equal, and the geometry is unchanged, so #780's boundary
  assertions all still hold. The seed `BladeSwingClock` takes on first contact
  reads `_last_t`, which `BladeSim._step` already advances per substep.

## Alternatives considered

- **A uniform spatial grid over node positions (#807's original step 2).**
  Rejected: it would answer the same *wrong* question faster and enshrine it —
  the region a swing can reach is not a disc centred on the pivot, and a severed
  fragment leaves from wherever it severed. Indexing by predicate dissolves the
  problem instead of accelerating it.
- **A hand-maintained registry or a scene group of carriers (#808's thread).**
  Viable and precedented (`Entity.READY_GROUP` is exactly that shape), but it
  needs its own writer hooked to the local value changing or membership rots
  silently, and `get_nodes_in_group` is tree-wide rather than graph-wide, which
  the frontmatter menu (#567) and the sandbox host's live tabs both break. The
  collision layer is the same predicate index with the engine maintaining the
  container and the space scoping it.
- **Keeping the analytic sensing and merely fixing the radius.** Rejected by the
  owner outright: it leaves three implementations of one geometry in place, and
  the reason they existed was never a real constraint.
- **Sharing one `BladeObstacleField` across a pivot's proposals.** Rejected: the
  field carries per-swing mutable state (`_strain`, `_edge_residual`,
  `_driven_last`, `_near`) and the coarse pass simulates proposals concurrently —
  that is a data race. Hence the immutable/mutable split.
- **Putting walls in `_near` (as #811's body literally said).** Rejected on
  review: `_near` gates the strain accumulator, so a wall would be able to shatter
  a blade and stall a grip, violating ADR 0005 and #781.
