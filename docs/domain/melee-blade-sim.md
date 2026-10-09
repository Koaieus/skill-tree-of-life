# Melee blade — PBD physics & deterministic preview

> **Damage model:** blade **vertices** deal `blade_damage`; blade **edges** deal **nothing** — they collide as swept capsules and that is all they do ([ADR 0005](../adr/0005-blade-parts-and-counters-are-orthogonal.md): *nodes deal damage, edges give rigidity; spikes pop vertices, bunkers break edges*). There is no `edge_damage` stat. STR//10 scales per-vertex damage, multiplied by the per-contact speed curve ("Speed-scaled damage"). A face/cycle bonus is rejected as a geometric filled region ([legacy-mvp-decisions](../adr/legacy-mvp-decisions.md) §D-1). See "Edge collision".

Siblings: `blade-native.md` (the C++ backend and golden contract), `blade-perf.md` (cost numbers).

## Goal

Melee needs a *deterministic* outcome up front, like ranged and magic, so
`AttackPlan.resolve()` stays a synchronous, side-effect-free function the UI, the
AI and `BattleSystem.launch_attack` can all call. A blade is a graph of
pin-jointed bodies whose topology the player picked (a chain whips, a
triangulated mesh stays rigid), and the engine's physics server cannot be
crunched ahead of time. So a custom **Position-Based Dynamics solver** replaces
it: the same solver runs the preview, the AI scoring and the live swing, and the
same inputs give the same outputs.

## Why PBD

| Need | PBD answer |
|---|---|
| Deterministic per call | Pure function of positions + constraints + drivers |
| Cheap per sub-step | Verlet integration + constraint projection over `PackedVector2Array`s |
| Stable at any timestep | No mass/force inversion, no force explosion |
| Composable constraints | Distance constraints (welds included, as braces) behind one `project(positions, inv_masses)` interface |
| One solver, two callers | `resolve()` runs it for hits; the visual swing replays the trajectory |

The cost is fidelity: stiffness comes from solver iterations, not rigid-body
dynamics, so triangulated blades need iterations to *look* rigid and mass-ratio
whip cracking is softer than impulse-based physics. Acceptable for a
one-revolution sweep.

## Architecture

`attack/melee/sim/` is pure maths (no scene nodes, no globals): `BladeState`
(descriptor), `BladeConstraint` / `BladeDistanceConstraint`, `BladeDriver` /
`BladeArcDriver`, `BladeSwingClock`, `BladeObstacleField`, `BladeDefenderZones`,
`BladeSim` (static `simulate_range`), `BladeTrajectory`, `BladeHitScan`,
`BladePopResolver`, `BladeDamageInstance`. `attack/melee/` holds the scene side:
`SkillBlade` (visuals, `build_from_skill_nodes()`, `simulate()`, `play()`),
`BladeNode` / `BladeEdge` (pure `Node2D` visuals), `SwingResolve`, `SwingResult`,
`MeleePreview` (the level-mounted ghost loop). `attack/plan/melee_attack_plan.gd`
owns `resolve()`: build `BladeState`, bake, walk (scan, land), re-bake at each
severance, produce the `AttackOutcome`. See "Reading order".

```
 MeleeAttackPlan (pivot SkillNode + members + induced edges)
        ▼
   BladeState  ◄── pure descriptor
        ├──► BladeSim.simulate_range(state, drivers, step_offset, count)
        │         ▼
        │     BladeTrajectory (samples[step] = PackedVector2Array)
        │         ├──► BladeHitScan.Sweep.scan_sample(t, pose, speeds)
        │         │         ▼
        │         │     [HitEvent {t, particle/edge, target}]
        │         │         ▼ resolve only — landed per SAMPLE, so a pop re-bakes what follows
        │         │     AttackOutcome
        │         └──► SkillBlade.play(trajectory)   (ghost or live)
        │                   ▼  BladeNode visuals tweened over real time;
        │                      `hit` emitted at each HitEvent.t (live only)
```

## Sim/presentation invariant

**The sim owns business logic — positions and pre-scanned hits. Presentation may
interpolate, retime or re-sim freely without affecting outcomes.**
`BladeHitScan` pre-scans the whole swing into `Array[BladeHitEvent]` before
playback starts, so every hit's target, damage and trajectory-domain `t` is
decided. `play()` takes pre-scanned `hits` and never calls `BladeHitScan`;
`playback_rate` only changes the tween's wall-clock pace (the tween callback is
always trajectory time). If a playback change needs `BladeHitScan` to run again,
it has stopped being presentation.

## Module contracts

### `BladeState`

The descriptor handed to the sim (`attack/melee/sim/blade_state.gd`; built by
`BladeState.build(positions, pivot_idx, edges, radii)`, which seeds one
`BladeDistanceConstraint` per edge at its initial length; callers append more
constraints). Fields worth knowing: `inv_masses` (0 = static, the pivot and
frozen corpses), `vertex_damage` (a per-particle damage **coefficient**, not the
landing amount), `speed_history` (per-particle speed per sample),
`removed_edges` / `removed_vertices` (recorded sets, never splices), `damping`
(per-particle, severance only), `obstacles` (the defender field).

### Constraints and drivers

`BladeConstraint.project(positions, inv_masses)` mutates positions in place,
called once per iteration, order-independent at the limit. `BladeDistanceConstraint`
is standard PBD distance with `compliance` (0 = rigid, the default).
`BladeDriver.apply(positions, t)` runs *after* Verlet integration and overrides
the positions of the particles it owns: that is how the swing happens, and
everything else follows by constraint. `BladeArcDriver` drives one particle on a
circle (center, radius, start angle, sweep, duration, ease, default sine-in-out);
`MeleeAttackPlan` builds one per pivot-adjacent particle. Progress is `t /
duration` unless a `BladeSwingClock` is attached **and warping**, then
`clock.progress()` ("Fortification drag").

### `ClampAddon` — a weld is a brace

A node carrying a `ClampAddon` welds the joint it sits on. A weld at J between
two arms equals a distance constraint between the arm-tip particles, so
`ClampAddon` contributes one `BladeDistanceConstraint` per neighbour pair (one
brace at degree 2; higher degrees over-constrain, which PBD tolerates).

- **A brace is not a face.** Area-damage code traverses `state.edges`; braces live
  in `state.constraints` and stay invisible to it ("rigidity only, no face").
- **An already-triangulated joint gains nothing**: the braces are redundant, so a
  clamp spent there wastes an addon slot.
- **A brace dies with either edge it spans.** It records its joint
  (`BladeDistanceConstraint.joint`, `-1` on an edge's own constraint) and holds
  only the angle between `joint-a` and `joint-b`. `BladeState.remove_edge` drops
  every brace whose joint is one endpoint of the dead edge and whose `a`/`b` is
  the other; `remove_vertex` drops every brace whose joint dies. No constraint
  ties together two particles the edges say are apart, so
  `_reachable_from_pivot` (which walks `state.edges`) is truthful by construction.

### `BladeSim.simulate_range(state, drivers, step_offset, count, …)`

`simulate` is `simulate_range(0, ceil(duration / dt), …)`: one stepping loop, and
a continued chunk is the same call with a different **integer** `step_offset`.
`step_offset == 0` resets the Verlet history; any other offset **trusts
`state.prev_positions`**. Every substep's time is `float(step_offset +
local_step) * dt + float(s + 1) * sub_dt` — an integer global step, never a float
`t_start` accumulated across chunks, so a chunked run is bit-identical to an
unchunked one (`test_blade_chunked_parity.gd`). The backend is C++ only
(`blade-native.md`).

`dt` is the **trajectory sample rate** (`duration / dt` samples; `samples[0]` is
the pre-step pose, so `duration() = (samples.size() - 1) * sample_dt`). Each
sample interval runs `substeps` physics steps at `dt / substeps`: Verlet
integrate; apply drivers at the substep's own absolute time; project constraints;
after the last substep snapshot **one sample per interval, never one per
substep**. The iteration count per substep:

```
budget = base_iterations * (1 + max_particle_speed / velocity_iter_ref)   # 0 disables
budget *= length_factor
iters_per_substep = max(1, round(budget / substeps))
```

`DEFAULT_SUBSTEPS = 4`, `enable_length_scaling = true`; `substeps = 1` and
`enable_length_scaling = false` isolate each axis in tests. `BladeSim.DEFAULT_ITERATIONS`
is 16.

**Substeps, not iterations.** For one PBD/XPBD constraint, per-step error scales
with `dt²`, while extra Gauss-Seidel iterations at a fixed `dt` plateau (Macklin
et al., *Small Steps in Physics Simulation*, 2019). For a fixed sweep budget,
smaller timesteps beat more passes: 4 substeps x 4 iters converges far better
than 1 x 16. Do not "simplify" this back into a bigger `base_iterations`
(`test_substeps_alone_hold_shape_better_at_equal_or_lower_sweep_cost`).

**Length axis: hop count, not distance.** `BladeState.pivot_eccentricity()` (graph
eccentricity of the pivot within `state.constraints`; one BFS per resolve, never
per step) scales the budget. Gauss-Seidel propagates a correction roughly one
constraint per sweep, so a blade of eccentricity `L` needs on the order of `L`
sweeps just to transmit stiffness to its far vertex; no number of *fast* sweeps
fixes a sweep-*count* property. Not neighbour spacing (rest length is irrelevant
to propagation) and not euclidean distance (`velocity_iter_ref` already covers
it). `LENGTH_BASELINE_HOPS` (3) exempts short blades; `LENGTH_ECC_CEILING` (40)
clamps the climb so a ceiling-clamped blade costs roughly 4x the flat budget
(owner-tunable named constants; the multiple is a starting point). A truss pays
less than a whip of equal node count, since braces shorten paths. A long blade
costing more is the intended outcome; do not tune the multiplier down to squeeze
under the flat cost.

**Native contract in one line:** goldens (`blade-native.md`) pin the solver; a
test observes only what crosses the boundary (trajectory, `speed_history`,
`clock.history` / `field.history`, `_length_factor`).

### `BladeTrajectory`

`sample_dt`, `samples: Array[PackedVector2Array]`, and `prev_samples` (the exact
Verlet history after each step, parallel to `samples`, used to land a rewind on a
severance sample). `sample(t)` linearly interpolates, clamping at both ends.

### `BladeHitScan.scan(trajectory, state, space_state, graph, collision_mask, exclude, broad_phase)`

Returns `Array[BladeHitEvent]`. It **queries the physics server** (shape
intersections per element per sample; only the query shapes enter the physics
world), so it is not pure and **cannot be assumed safe from a `WorkerThreadPool`
task**: thread only `simulate` and batch the scans back on the main thread.
Dedup is per-element-per-collider: each particle/edge emits at most one event per
collider across the whole sweep, on first contact. The sample step (default
`1/120 s`) is fine enough that sample-boundary proximity suffices; no swept-volume
detection. Each event is stamped with `speed`: a vertex's own speed at its
contact sample (`state.speed_history`), or for an edge the mean of its two
endpoints'. A dead element is not scanned: `Sweep` skips a `removed_vertices`
disc, a `removed_edges` capsule and any edge with a removed endpoint, so
`last_events` holds no event that would be refused at land time and a pop swing
costs fewer queries.

**Broad phase.** Per substep one shape query over the blade's whole bounding box;
an empty result skips the ~300 narrow-phase queries. The box is a strict superset
of every narrow shape, so the flag changes **cost**, never the event set
(`bench_blade_hit_scan.gd` asserts it).

## Edge collision

Edges collide so a truss slamming a bunker cannot slip between its vertices
("no hitbox on the edge, it could slip in between", owner, 2026-09-07).

- **The model.** Each edge is a **capsule along the segment MINUS the two
  endpoint hitbox discs**: it starts at one vertex's rim and stops at the other's.
  A target on a hub is inside the hub's own disc and takes vertex damage only, so
  a degree-6 hub is worth one damaging contact, by geometry alone. Faces are
  rejected (`combat_system.md`: trigger off cycle presence, a graph fact).
- **No arbitration between elements.** Each element emits at most one event per
  collider across the sweep; nothing ranks elements against each other.
- **An edge contact mints no `DamageInstance`.** It stays in
  `MeleeAttackPlan.last_events` (a real contact; the bunker break consumes it),
  but `last_hits` / `AttackOutcome.hits` is the vertices-only subsequence. A
  zero-amount hit would buy a crit roll, a schedule entry and a record line: a
  change to the counting rule with no gameplay content (`combat_system.md`: tame
  runaway with the scalars, never the counting rule).
- **An edge carries no stats**: no `edge_damage` def, no per-edge array, no
  blunting, and no derivation from endpoints by MIN, MAX or mean. A truss and a
  chain with the same nodes differ only in edges, so a derivation would make
  triangulating for rigidity silently multiply damage. ADR 0005 holds the
  argument; **do not re-propose a gentler derivation.** Edge *geometry* does
  derive from the endpoints (physics, not offence).
- **A capsule contact never touches the spike system.** A spike destroys matter,
  a bunker destroys structure. `BladePopResolver.LiveGate._admit_edge` skips the
  spike ladder explicitly; giving an edge blunting `0` would make `remaining >=
  blunting` trivially true and sever on every contact.
- **Spacing luck is harmless for spikes** (owner, 2026-09-08: *"blades be floppy
  as heck, intentionally threading the spiked-defender needle would be close to
  impossible"*) but real for bunkers and walls, which capsules fix.
- **Severance is a set, not a splice.** Only the bunker break severs an edge
  today. `BladeState.removed_edges` records indices; `state.edges` is never
  spliced because a `BladeHitEvent` carries an `edge_idx` into it, and the
  adjacency map built once per swing stays valid. `_kill` and `_sever_edge` share
  `_disintegrate_unreachable`.

## Speed-scaled damage

`damage = blade_damage x f(speed)`, evaluated **per contact** from the contacting
vertex's own speed at its own contact time (not a blade-wide average or per-step
max):

```
f(v) = 1 + (M - 1) * v / (v + v_half)
```

`f(0) == 1` (a stationary vertex deals its base coefficient), `f(v_half)` is half
the bonus, `f(inf) = M` (bounded). `M` and `v_half` are board `ScalarStat`s
(`blade_speed_multiplier_max`, `blade_speed_half`), never hardcoded, floored at
`1.0` so a misconfigured `M < 1` cannot become a penalty.

- `BladeState.speed_damage_multiplier(speed, m, v_half)` is the curve (raw numbers,
  so an edge or any other hit reuses it); `BladeState.stat_value(board, id,
  fallback)` is the null-safe stat read.
- `vertex_damage[i]` is the wielder's localized `blade_damage`, a coefficient.
- `speed_history` keeps the **physics** rate: `_step` returns each particle's own
  speed per substep, `simulate_range` keeps the LAST substep's value per sample
  interval, index-parallel to `samples` (index 0 zero-filled). `BladeHitScan`
  stamps each event from `speed_history[i][p_idx]` at the event's own sample.
- Two damage sites multiply, for two audiences: `BladeDamageInstance.land_on`
  (`attack/melee/sim/blade_damage_instance.gd`) on the authority's resolve, once
  per hit, reading `M` / `v_half` off `attacker.stat_board`; and
  `SkillBlade._apply_playback_frame`'s `hit` signal for the cosmetic floater.

**Determinism is safe, and the reason is ADR 0002, not simple maths.** A position
now turns into a landing amount, but a peer re-simulates only to *draw*. Every
damage number and the hit set come off the `AttackRecord` the authority captured
post-apply; `AttackRecord.rebuild()` never constructs a `BladeDamageInstance` (a
plain `TRUE` `DamageInstance` carries the host's `effective_amount`), so a peer
cannot re-evaluate `f(speed)` against float-divergent positions
(`.claude/rules/attack-timeline.md`). **No peer may ever re-decide a landing from
its own sim** (`.claude/rules/multiplayer-sync.md`). Do not add quantization to
the curve: it is pure `+ - * /`, and `sqrt` (speed from `sp_sq`) is exempt from
`lint-transcendentals` as correctly rounded.

## Fortification drag

A wall of fortified nodes bogs a blade down. The magnitude is a defender-side,
node-local stat `swing_drag` (base 0; `FortificationAddon` authors the grant).

### It acts on the CLOCK

Bleeding velocity off the contacting particle does nothing to a rigid blade: the
distance constraints fight the damping, and `_step` re-applies drivers *after*
Verlet, so `BladeArcDriver.apply()` overwrites the damped position outright.
`BladeState.damping` is the **severance** knob, for particles no driver steers.
What drag can move is the driver's argument. `BladeSwingClock` owns the angular
progress `f` the driver evaluates its ease at; every fortified node touched adds
its `swing_drag` to a running total, and the clock advances

```
f += (sub_dt / duration) * 1 / (1 + drag)
```

for the rest of the swing. One clock per swing, shared by every arc driver (one
rigid body turning about one pivot; per-driver clocks would shear the blade).

- **Monotonic by construction**: `1 / (1 + drag)` is positive and at most 1, `f`
  clamps at 1. No wall reverses or freezes a swing; it spends the arc (five nodes
  at drag 1 leave a sixth of the sweep), which is how a wall protects what is
  behind it with no deletion or severance.
- **Causal**: a zone's drag is banked only once its own contact has happened, so
  it slows the rest of the arc and never the approach to itself.
- **Free when unmet**: `MeleeAttackPlan` attaches a clock only when the swing has
  a defender field; even then the clock is inert until first contact (the driver
  reads `t / duration` verbatim), so a swing that never touches its fortified
  node is bit-identical to one with no field. The warping clock's `_f` is carried
  in the native loop (`clock_tick` per substep).
- **Sensing is on discs AND rim-trimmed capsules.** A sweep's edges cross exactly
  the gaps between vertex arcs, so disc-only sensing would reintroduce spacing
  luck for drag *magnitude*, where threading a wall is the whole mechanic (it is
  the surviving half of "a capsule contact is a full contact for every defender
  effect"; ADR 0005 retired only the damage and spikes half).
- **Anti-double-dip, for drag only**: a zone contributes its `swing_drag` **at
  most once per swing** (a node touched by disc plus two capsules would
  otherwise bank three times). ADR 0005's "nothing to double-count" is about
  damage; do not delete the rule on its authority.
- Under ADR 0005 drag is a third defensive effect: it removes no blade part, so it
  cannot violate vertex/edge disjointness.

### One defender field, built by the physics engine (ADR 0014)

There is **one** contact test in the melee solver, and the physics engine finds
what it tests against ([ADR 0014](../adr/0014-one-physics-built-defender-field.md)
holds the decision and dead alternatives).

`BladeDefenderZones.query()` issues a single `intersect_shape` against the two
collision-layer bits a `SkillNode` toggles from its own `swing_drag` /
`deflection` values (bit 2 `swing_drag`, bit 3 `deflection`; bit 1 stays so
`intersect_point` mouse picking works). The result is an **immutable**
parallel-array table (centres, radii, drag magnitudes, deflect flags, source
nodes). `BladeObstacleField` wraps one and owns every mutable accumulator;
`BladeSwingClock` owns the banked drag.

- **Two zone kinds, asymmetric on purpose.** `deflection` is a BOOL (presence
  only); `swing_drag` a magnitude. A plate is pushed out of, meters strain, arms a
  break. A wall is **sensed and nothing more**: `project()` skips it in the
  pushout and banks its drag on the clock. A wall never enters the field's `_near`
  set, which gates the strain accumulator (a wall in it could shatter a blade, a
  plate-only effect). **A node with both stats is ONE zone of both kinds**,
  latched once (the drag latch keys on the zone index).
- **One query answers "who is in range"**, so `BladeHitScan` and the field agree by
  construction; the wall test runs per solver **substep**. Reach is `zone radius +
  particle radius` for a disc and `zone radius + EDGE_RADIUS` for a capsule, no
  slop, no hysteresis.
- **The query radius is generous on purpose — never re-tighten it.** A floppy
  blade straightens when swung (a 5-node W with rest reach 432 px whips to
  714.6 px), so a rest-reach bound silently let defenders in that annulus fail to
  defend while `BladeHitScan` damaged them normally (`test_blade_whip_reach.gd`
  derives the measurement). `MeleeAttackPlan.whip_bound()` is a BFS over the
  blade's induced subgraph summing rest edge lengths from the pivot, times
  `BladeDefenderZones.STRETCH_MARGIN`, plus the widest disc and an edge
  half-thickness. Too large costs a few float compares per substep; too small
  silently drops a defender. A severed fragment may coast beyond it; accepted
  ("coasting blade parts can go anywhere", owner, 2026-09-09).
- **A generous field must be broad-phased**: `project()` recomputes the blade AABB
  from the current pose each iteration and rejects any zone outside it grown by
  its radius (exact, no margin). Keep that reject if you touch `project()`.
- **Built once per pivot for the AI.** `AiBladeRollout` builds every proposal's
  state with an empty zone set (to get the whip bound), takes the widest bound per
  pivot, issues one query, and hands the same immutable instance to all of that
  pivot's proposals; each still gets its own `BladeObstacleField` and
  `BladeSwingClock`, so the concurrent `WorkerThreadPool` sims share only data
  nobody writes. The coarse tier senses drag too. The blade side is excluded by
  RID via `collect_target_excludes()`, the same list `BladeHitScan` gets.
- **Determinism and the mirror.** The field is read off the live graph at resolve
  time; a mirror peer re-runs `plan.resolve()` on a throwaway shadow purely to
  draw, from the same pre-attack node states. `MeleePreview` replays one
  prediction, so no per-cycle clock exists to bank anything.

### A defender the space hasn't seen yet

`intersect_shape` answers against the physics server's broadphase, and a
collider's new state (a just-added `Area2D`, or one that moved) only reaches it on
the next physics tick. Toggling a layer bit on a resting node is seen
immediately; **repositioning** it into range in the same frame is not
(`.claude/rules/melee-fixtures.md`'s "two extra teeth" is the fixture side).
The production correction is a dirty-frame fallback: the two collision writers on
`SkillNode` (radius sync, `_sync_defender_bit`) call
`BladeDefenderZones.mark_broadphase_dirty()`, and while the stamp is the current
physics frame `query()` fills the zones from a graph walk instead (release and
debug alike; a same-frame *position* move does not stamp). In a debug build
(`OS.is_debug_build()`) `query()` also re-walks `graph.get_skill_nodes()` for
`swing_drag > 0` / `deflection` nodes within its `whip_bound` disc and
`push_warning`s any the physics query dropped; that O(map) walk must never run in
release. No forced `await physics_frame` (the resolve must complete synchronously,
`.claude/rules/attack-timeline.md`).

## Bunker deflection

A node with `deflection > 0` (base 0; only `BunkerAddon` authors it) is a solid
obstacle. `BladeObstacleField` (`attack/melee/sim/blade_obstacle_field.gd`) pushes
every vertex disc and rim-trimmed edge capsule back out of the plate's disc every
solver iteration, **after** the distance constraints (the pass ends outside every
plate). Most blades flop around a bunker; a blade too rigid to yield is driven a
fixed distance into the plate and then **breaks** — never the vertex that touched
it (ADR 0005), but an edge. `build_defender_zones` + `attach_defender_field` in
`melee_attack_plan.gd` hang the field off `BladeState.obstacles`, and the resolve
loop's `consume_break` handling severs.

### The metric is the DRIVER's residual

A driven particle is not pinned during projection (only the pivot has `inv_mass 0`),
so a rigid body resolves a contact-point metric or ADR 0005's distance-constraint
residual **completely**, by rotating back as a whole; both read 0.00 on every rigid
case. Each substep the arc drivers place the grip where the swing *should* be, and
projection moves it to where the blade *can* be. A floppy blade absorbs a bunker
contact in a fold (unresolved advance ~0); a rigid one pushes back against the
driver (close to the full `speed * dt`). Summed over a contact, clamped at `>= 0`
(a step where the blade catches up *subtracts*, washing out a transient hold),
crossing `SHATTER_DISTANCE` arms a break. Whether the blade yielded *is* the
rigidity measurement. At default solver config (`test_bunker_deflect.gd`): a bare
spine peaks under 2 px, a clamped spine ~16 px and a truss ~40 px; more iterations
sharpen the separation and never shift the verdict.

### What breaks

Contact and failure need not coincide (ADR 0005). Each substep
`BladeObstacleField.end_substep` banks the unresolved drive onto every *live* edge
incident to a pushed vertex, in proportion to `|normal . edge_direction|`, and
onto any edge directly touched by its own capsule contact at full share. When a
zone's strain crosses `SHATTER_DISTANCE` (8 px), the most-strained live edge banked
against that zone breaks, ties to the lowest index (`_pick_edge`); on a truss that
is the outermost rung, whichever edge carried the load.

**The grip is the most rigid case, not a special case.** A contact on a *driven*
particle is metered like any other: the refused advance accumulates, its incident
edges bank load, `_pick_edge` arms the break. A grip driven squarely into a plate
breaks on any blade; one that grazes it does not. Once its last edge to the pivot
goes, `SwingResolve._surviving_drivers` drops its driver and it coasts with the
severed remainder. Nothing stalls the swing clock (owner, 2026-10-01, reversing
the grip hard-stall: *"these driven nodes … should break too"*, meaning its edges,
not the vertex). A stall also froze the drivers' targets and so the strain meter
for the whole blade. Picking the handle next to an enemy bunker is self-punishing:
the wielder dismembers their own blade at the handle.

### State, rewind, and where the sever lands

`BladeObstacleField` is sim state like `BladeSwingClock`: per-zone strain, edge-load
banks, driven-particle history and the pending break are captured/restored by its
`Bank`, with a chunk-local `history` of one bank per sample. A break is never
applied directly: `end_substep` only *arms* a `BladeObstacleField.Break` (edge
index, GLOBAL step, defender). The per-sample walk checks `obstacles.has_break_at(step)`
exactly alongside a pop, stops, and rewinds by *reading* the severance sample
(`chunk.samples[local]`, `prev_samples[local]`, `clock.history[local]`,
`obstacles.history[local]`); the loop then calls `consume_break()` and severs
through `BladePopResolver.LiveGate._sever_edge`, the call a spike pop takes, so the
same `_disintegrate_unreachable` cascade fires. The field never mutates
`state.constraints` or `state.edges`, so an optimistic bake stays a pure function.
Self-limiting: once the edge is gone that region is floppy and the blade flows past.

### Guards and budgets

- **Zero-bunker structural guard.** `attach_defender_field` hangs a field only when
  the query returned something (a wall or a plate). No field means no accumulator
  and no pushout, so a map without bunkers cannot produce a break at any blade size
  or speed (owner, 2026-09-08: *"a false positive would be devastating … a false
  negative is basically wallhacks like clipping through solids"*).
- **Penetration budget.** The pushout runs every iteration, so a vertex rests no
  deeper than `CONTACT_SLOP` (1 px) plus one substep's travel. `CONTACT_SLOP` is
  nonzero because `BladeHitScan` must *see* the overlap and it keeps resting
  contacts from jittering; `CONTACT_HYSTERESIS` (4 px) keeps a contact "ongoing"
  across slop-band jitter so strain does not reset mid-contact. Edge capsules get
  no slop.
- **The hit still lands.** The mitigated hit on a bunker is the ordinary
  `BladeHitScan` contact against its `armor` / `min_damage_taken`; the field adds
  deflection and the break and never suppresses it.
- **No pop budget — `node_health` is the budget.** A break costs the bunker nothing
  beyond the mitigated hit every contact already lands (owner, 2026-09-08: *"Bunker
  nodes still take damage! … they are not immortal. Spikes are offensively useful
  so we limit their defensive use."*). A dedicated `plate_integrity` pool is a
  possible later step; nothing anticipates it.
- **Residue.** Per-element-per-collider dedup means a second break by the same
  vertex against the same bunker lands no second hit; the break is real, the damage
  is not.
- **Tuning** is hand-driven: `test_bunker_deflect.gd` pins the classification
  (floppy yields, braced breaks), never the constant, and the melee sandbox tab
  (`addons/melee_sandbox/melee_sandbox_panel.tscn`) has **Bunker paint** (click adds
  or strips a real `BunkerAddon`), **Rigidity** (`Floppy` / `Braced`: strip or weld
  a `ClampAddon` on every owned node) and a **strain readout** (worst per-zone
  strain against `SHATTER_DISTANCE`, read off the live field at
  `MeleePreview.current_blade().state.obstacles`). **Do not tune against AI-built
  blades**: they sit at the floppy end and never trigger a break.

## Severance is a constraint removal

When a spike pop kills a blade vertex, everything downstream stops being reachable
from the driven pivot, and it **keeps going** (owner, 2026-09-08: *"leaf node sits
on blade, swinging. sim constraint ties it to its neighbour via edge. say its
neighbour gets popped … constraint: gone … it's the same old same old, just one
less restriction. keep simulating displacement and enforce the remaining
constraints"*). There is no fragment type, no second sim, no `is_unpinned`, and no
separation-velocity seeding.

**What a death is** (no C++ change needed):

1. `inv_mass = 0` — a frozen corpse, staying where it died (the pivot's expression).
2. Every constraint incident to it is dropped (`BladeState.remove_vertex`),
   including `ClampAddon` braces (a weld to a corpse is a weld to a wall) and
   braces whose *joint* it was.
3. Its `BladeArcDriver` is dropped if it was a driven pivot neighbour.
   `SwingResolve._surviving_drivers` also drops the driver of a merely **coasting**
   vertex (alive, no longer attached).

Everything downstream coasts by plain Verlet in the **same `last_trajectory`** at
the **same index** (index stability holds for the whole swing), so `SkillBlade.play`
draws it with no new code. `removed_vertices` is a recorded set, never a splice: a
`BladeHitEvent`'s `particle_idx` and `Pop.particle_idx` index `positions`.

**Orphans are COASTING, not dead.** `BladePopResolver.Result` says two things:
`dead_at` (a spike destroyed this vertex; its hits are refused from then on) and
`severances` (this *set* lost its path to the handle; still armed, still landing
speed-scaled hits, can be popped again). Only the **pivot** is exempt from popping.

**The seam is "what left, and when" — never "why".**
`BladePopResolver.LiveGate._disintegrate_unreachable` is the single place a
severance is born, whatever removed the vertex, and appends a
`BladePopResolver.Severance` of `{t, vertices}` only. A spike pop and the bunker
break both go through it.
`test_the_continuation_is_a_function_of_topology_not_of_trigger` pins it.

**The drag term is per particle.** There is no disconnection damage scale (owner,
2026-09-08: *"emergent from speed, no halving, but possible a slight drag on
disconnected pieces"*): a coasting vertex keeps its coefficient, and the speed
curve already gives it less than a driven blade (and more if flung). The one
authored term is `BladeState.SEVERED_DRAG` (0.8/s, owner-tunable) written into
`BladeState.damping` for the `_reachable_from_pivot` complement at each severance.
An **empty** array makes `_step` skip the multiply (the driven path is
bit-identical; the `severed_coasting_tail` golden pins it) and a **zero entry** is
a retention factor of exactly `1.0`. This is not the swing clock's drag: that slows
the clock and removes nothing; this bleeds a particle nothing is driving.

### The loop: sim → scan → LAND, re-baked at each severance

The pop gate is reached from `BladeDamageInstance.land_on` **inside**
`OutcomeApplier.apply`'s walk, so the interleave is sim / scan / **land**: only
applying produces the world the next pop decision reads. `MeleeAttackPlan.resolve_against`:

1. **Optimistically bake** the whole remaining swing in one `simulate_range` call; a
   swing that severs nothing pays nothing more.
2. Walk it sample by sample: `Sweep.scan_sample`, mint `BladeDamageInstance`s,
   compile, `OutcomeApplier.apply` with `sub.crit_stream` = the swing's **one** rng.
3. If a batch produced a `Pop` (or the field armed a break), **stop**, rewind,
   mutate the state at that sample, re-bake from it, continue.
4. One `OutcomeSchedule.compile` over the merged outcome.

A bake is a pure function of the state, so this is **bit-for-bit what a true
per-sample interleave would produce**. Solver calls per resolve: `1 + severances`,
against ~145 for a literal per-sample loop.

**Landing on the severance sample.** `prev_positions` at a sample is a mid-sample
pose (rewritten per substep), so the solver emits `BladeTrajectory.prev_samples[k]`;
the loop lands on local sample `j` by reading `samples[j]` / `prev_samples[j]`, and
restores the clock from `history[j]`. A rewind is two array copies.
`test_blade_chunked_parity.gd` pins that a continuation equals the run that never
stopped, and the **prefix property** (a short bake of `k` steps equals the first
`k` samples of a long one; `test_a_short_bake_is_a_prefix_of_a_long_one`) the
optimistic bake relies on.

**The `BladeSwingClock` is carried across chunks** — one instance, never rebuilt
(`_f`, banked `drag`, `touched`, `_warping`, `_last_t` all persist; a fresh clock
would un-bank a wall's drag), with a `capture()` per sample in `clock.history`.

**Ordering.** Everything lands in true `t` order on the shadow. Crits are rolled
per batch, after earlier landings applied, from one rng handed to every batch
(`OutcomeSchedule._sorted` breaks a same-`t` tie on insertion index;
`test_batched_crit_rolls_equal_one_global_roll`). Residue: if a swing friendly-fires
a node whose depletion changes the attacker's own `crit_chance` mid-swing, a late
crit can differ from a global up-front roll. That is the more correct order, not a
bug. Everything rides the **same `AttackOutcome`**, so `AttackRecord.capture` picks
up a coasting vertex's landings and a peer replays them without re-running a solver
(`.claude/rules/multiplayer-sync.md`).

## Engine-side wiring

### `SkillBlade`

`build_from_skill_nodes(skill_nodes, pivot, induced_edges, owner, fill)` builds the
`BladeState` and spawns BladeNode + BladeEdge visuals. `fill` is the plan's
`vertex_fill`, a `BladeVertexFill`: the one owner of per-vertex stat reads and the
addon dispatch, shared with `MeleeAttackPlan.build_blade_state`. `simulate(duration)`
auto-builds drivers from pivot-adjacent particles; `play(trajectory, hits, ghostly,
playback_rate)` tweens visual positions and emits `hit` at scheduled times. Hit
detection is the deterministic scan, never Godot collision overlap.

### `MeleeAttackPlan.resolve()`

```
selection → BladeState → drivers → bake (simulate_range)
   → per sample: Sweep.scan_sample → mint → compile → crit → apply
   → on a pop/break: rewind, sever, re-bake from that sample
   → AttackOutcome { hits: DamageInstance[], ap_cost }
```

Synchronous and pure, with the same call shape as `RangedAttackPlan.resolve` and
`MagicAttackPlan.resolve`. `_resolve_swing(world) -> SwingResult` (`SwingResult` is
`attack/melee/swing_result.gd`) is the one implementation; `resolve_against` is that
call plus publishing onto the `last_*` fields.

## The preview is a real resolve, replayed

**The ghost is not a lookalike of the swing. It is the swing.** Blade contact is
*"complex emergent movement resulting from the XPBD sim"* (kinks, lag, tail whip), so
no rule, tooltip or heuristic can tell a player what will hit; only the outcome of
*this specific swing* can. `MeleePreview` (mounted in the level like `AttackVFX`)
watches `ArmedStack.attack_plan_changed` / `attack_plan_state_changed`; for a valid
`MeleeAttackPlan` it spawns a translucent ghost `SkillBlade` over the selection and
loops fade-in, play, fade-out; it frees the ghost when the plan changes, becomes
invalid or is cancelled. Hit signals are ignored during ghost play.

Once per selection change `MeleeAttackPlan` resolves the selection against a
throwaway `CombatWorld.shadow()` and caches the result (`prediction()`); the ghost
**replays** that result's `BladeTrajectory` and hands the blade its
`BladePopResolver.Result` as `pop_result`. There is no second predictor. A per-cycle
re-simulation could not reproduce the resolved arc even in principle: the resolve
re-bakes from each severance, which a plain `simulate()` over an intact blade does
not. Replaying makes drag, break and severance equal by construction at no
per-cycle cost, and there is no per-cycle clock left to bank anything.

**Aim-time prediction is sliced.** A melee resolve is a ~72-sample physics scan, so
running it whole on every node click stalls the one input the player watches.
`MeleeAttackPlan.advance_prediction(max_steps)` resolves at most that many more
samples, holding a shadow world open across frames; `MeleePreview._pump_prediction`
spends `prediction_slice_steps` (default 12) per frame and keeps `_process` running
only while there is more to do. `prediction_partial()` returns the half-drawn arc
the in-flight run has produced (live arrays: read, never hold past an invalidation),
`prediction()` stays the strict complete-or-null accessor, and
`prediction_duration()` sizes the playback tween so the ghost mounted on the click
frame keeps arcing as slices land. Every input to the resolve routes through
`_invalidate_prediction`, which cancels the run and frees its shadow, so a
superseded slice can never overwrite a fresher prediction. A mirror's committed-swing
draw-only resim steps the same way (`replay_slice_steps`, `begin_replay`).

**What it shows:**

- The vertex that dies goes de-lit **at its pop time** (`pop_result.is_dead(i, t)`
  per frame in `_apply_playback_frame`); the edge that parts likewise via
  `pop_result.severed_at`.
- The node that does it is marked `HighlightRole.PREDICTED_THREAT` (read off
  `MeleeAttackPlan.get_node_role`); one role covers spikes and bunkers.
- **Fortification drag is shown by the arc alone**: a drag zone carries no `Pop`, so
  no node is marked (drag sensing and `BladeHitScan` are separate models, and a
  per-node claim could disagree with the scan).
- Spacing luck stays visible: the preview shows which side of it this selection landed on.

**The cache is pushed, never lazy.** `get_node_role` runs once per node per overlay
repaint, and a committed swing's forced-dealloc cascade emits `state_changed` per
step, so a repaint-driven rebuild would resolve a half-dead plan mid-swing. The
refresh is pushed by `MeleePreview._refresh` (gated on `_live_swing` and
`is_valid()`); `get_node_role` only reads. Every `state_changed` emitter goes
through `_notify_selection_changed`. A machine with no preview mounted (a headless
peer, an AI turn) never predicts.

**It is a prediction, not an authority.** A client's preview is a local resolve and
may differ from the host's (`blade_arc_driver.gd`'s float note; the preview runs on
the unstamped (0) crit stream while the committed swing stamps a fresh one, so a
crit-driven kill cascade can change a later defender's board). Both are accepted
mispredicts; the rule they must not break is that a peer *receives* or *reproduces*
a landing and never re-decides one (`.claude/rules/multiplayer-sync.md`).

## Open questions

- **Damping for a DRIVEN blade.** `BladeState.damping` is written only for severed
  particles; a driven chain whips for the whole swing because a driver overwrites a
  damped position. Doing it properly means the clock channel, not the particle one.
- **Richer constraint shapes for addons.** `ClampAddon` welds via braces (rigidity
  only). A motor or breakaway addon would want a real constraint class.

## Reading order

1. `docs/domain/melee-blade-sim.md` (this file), then `blade-native.md`, `blade-perf.md`
2. `attack/melee/sim/blade_state.gd`, `blade_sim.gd`
3. `blade_constraint.gd` + `blade_distance_constraint.gd`; `blade_driver.gd` + `blade_arc_driver.gd`
4. `blade_hit_scan.gd`, `blade_pop_resolver.gd`
5. `blade_swing_clock.gd`, `blade_obstacle_field.gd`, `blade_defender_zones.gd`
6. `attack/melee/skill_blade.gd`, `swing_resolve.gd`
7. `attack/plan/melee_attack_plan.gd` (`resolve()`, `build_defender_zones`, `whip_bound`, `prediction()`)
8. `attack/melee/melee_preview.gd` (ghost loop, prediction pump)
