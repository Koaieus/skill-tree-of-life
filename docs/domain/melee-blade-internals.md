# Melee blade — module internals

Per-class contracts for the melee solver and plan modules. The model and its invariants are in `melee-blade-sim.md`.

## Spike pop: `BladePopResolver`

Given the raw `BladeHitEvent`s of a swing scan, `BladePopResolver` decides which
of the attacker's own blade vertices die and which are then severed from the
driven handle and disintegrated.

- A blade vertex that sweeps into a spiked, allocated enemy node drains that
  node's remaining `spikes` pool by the vertex's own `blunting`. Remaining >=
  blunting: the pool depletes by blunting and the vertex **pops** (the vertex
  itself dies). Remaining < blunting: the remainder drains to 0 and the vertex
  is **not** popped; it passes through as an ordinary contact ("pop only if the
  full amount is removed", owner). A partial drain therefore never reaches
  `LiveGate._kill` or mints a `Pop`; `blunting_spent` on a `Pop` is always the
  vertex's full `blunting`.
- The contact deals damage to nobody but the defender it pops against: the
  spiked node takes none, and a popping vertex's own hit never lands
  (`BladeDamageInstance.land_on` returns as soon as `admit` refuses the
  contact, before `super.land_on`, the only place damage is applied).
- Killing a vertex disconnects everything downstream of it from the pivot.
  Every vertex no longer reachable through surviving edges is recorded as a
  **severance**: it keeps coasting on the same trajectory, because nothing pulls
  on it any more. It is not killed. The pivot is exempt (popping the wielder's
  own handle is out of scope). An unspiked node (no `spikes` pool; only
  `SpikeRingAddon` mints one) never pops anything at any stake level.
- The result is a record, not a solver: each dead vertex carries its death time
  (callers drop its hits from then on) and each severance the set it orphaned.
  Re-baking the trajectory around those facts is `MeleeAttackPlan.resolve_against`'s
  job (see `attack-timeline.md`).
- **`LiveGate` is the only implementation of these predicates.** The AI/preview
  estimate runs the same gate against a shadow `CombatWorld`, so the AI's
  shape-risk signal (`AttackOutcome.popped_nodes`) comes from the code that
  produces the real one. (A separate batch pass would drift: it could record a
  pop at t2 for a vertex that disintegrated at t1 < t2.)

## `BladeHitScan` determinism

`BladeHitScan` queries the 2D physics server: every particle as a circle at its
sampled position, every edge as a swept capsule between sampled endpoints
trimmed back to the rim of each endpoint's own disk, so a hub never deals vertex
plus one-per-incident-edge. A whole-blade bounding-box query short-circuits any
substep sweeping empty space (`_is_region_empty`). Targets publish a
`CollisionShape2D`; the module encodes no target geometry.

- **Purity holds only while no query hits `_MAX_HITS_PER_QUERY`.** Queries are a
  pure function of (sim positions, world state) as long as the world state is
  itself sim-driven and the cap is never reached; ghost previews work the same
  way because only the query shapes enter the physics world. The cap bounds one
  query (one element, one substep), not the sweep; it is a stop-gap against
  erroneous placement, not a knob. Reaching it is a determinism bug: dedup is on
  first contact across substeps, so a truncated query may pick the collider up
  later with a different `t`, corrupting the landing order, and which colliders
  survive the cap is broadphase-ordered. `_warn_if_truncated` is the alarm; the
  gap stays open (`test_gap_melee_hit_detection_truncates_a_physics_query`).
- **Result order is stabilised.** Godot documents no ordering for overlapping
  colliders, and `MeleeAttackPlan` pops spikes during its scan of these events,
  so raw order could change the hit set itself. `scan` stable-sorts its own
  output: `t` first, ties on `SkillNode.stable_id` (a value every peer agrees
  on), never collider identity or query position.
- **Dedup is the whole counting rule:** each particle or edge emits at most one
  event per collider across the whole sweep, on first contact. Nothing
  arbitrates between elements; edges carry no damage (ADR 0005), and a
  degree-6 hub is worth one damaging contact because the capsules are trimmed to
  the endpoints' rims (geometry), not because a tiebreak suppressed them.

## `MeleeAttackPlan.collect_target_excludes`: "is that node on my side"

The RIDs fed to `BladeHitScan` as the physics-query exclude list. They cover the
blade's own selection plus every node on the attacker's side: the attacker's
pre-mirrored owned subgraph (`Entity.navigator`'s `GraphMirror.get_mirrored_nodes`,
MINE) plus every allied entity's navigator (ALLY). Unallocated nodes are not
excluded: the scan sees them too, so a swing across ground that just died
mid-cascade produces the same events as against never-allocated ground. The live
ownership / allocation gate happens at consumption time
(`BladeDamageInstance.land_on`, `BladePopResolver.LiveGate`).

- **This is the one answer to "is that node on my side".** It is also the
  defender query's exclude list (`build_defender_zones`); a second implementation
  would let a blade bog down on its own wall when the two drift. Ownership bits,
  never `owned_by == attacker`.
- `selection_set()` is unioned explicitly: a blade member is MINE by construction
  (`_can_be_blade` gates selection on `owned_by == attacker`), so it is redundant
  today, but it keeps the exact "self OR MINE OR ALLY" membership.
- Allies are enumerated via `Entity.GROUP` (the whole-tree roll call
  `TurnManager`, `VictorySystem` and `GameRoot` use), not
  `Graph.entities_container`: a plan's `attacker` is not guaranteed to sit under
  that container (fixtures parent entities straight onto the graph), while every
  live `Entity` is in its group from `Entity._ready`.
- The union is sorted by `SkillNode.stable_id` before minting RIDs, because
  `get_mirrored_nodes` order is dictionary iteration. Physics exclude lists are
  unordered by nature, so this is a determinism / legibility choice.

## SwingResolve: one resumable chunked loop

`SwingResolve` (`attack/melee/swing_resolve.gd`) is the loop
`MeleeAttackPlan._resolve_swing` holds, hoisted into an object so it can be
driven straight through (the authoritative path: one optimistic bake of the
whole remaining swing per severance) or a slice at a time across frames (the
aim-time preview).

- **There is exactly ONE chunked loop.** Slicing is not a second code path:
  `advance` takes a step budget, and an unbounded budget (`<= 0`) is the
  whole-remainder bake. What the severance head-replay does to stitch a chunk
  boundary is what a slice boundary rides on: one `BladeSwingClock` instance
  carried across, one `BladeObstacleField` carried across, and
  `BladeState.speed_history` accumulated out of each bake's chunk-local array.
- **Those three histories are chunk-local by design:** `clock.history`,
  `obstacles.history` and `state.speed_history` are rebuilt per bake, so a sliced
  caller must stitch them. Getting it wrong is not a visible glitch: a fresh
  clock mid-swing un-banks a dragging wall's drag and silently stops it
  sheltering what is behind it (`test_blade_chunked_parity.gd`). That an
  arbitrary boundary is bit-identical to none is pinned by
  `test_a_dragged_swing_is_bit_identical_across_a_chunk_boundary`.
- A slice boundary differs from a severance boundary in one way: there is nothing
  to rewind to. The bake ran to the boundary and stopped, so state, clock and
  field are already where the next bake continues; nothing is restored.
- `result` is live: `outcome`, `pops`, `live_gate`, `clock` and `obstacles` are
  set before the first step; `trajectory`, `events` and `hits` the moment the
  guards pass, and they are the arrays the run appends to, so a partial run is
  readable (`MeleeAttackPlan.prediction_partial`).
