# Melee blade — PBD physics & deterministic preview

> ⚠️ **Damage model:** blade **vertices** deal `blade_damage`; blade **edges** deal **nothing** — they collide as swept capsules and that is all they do ([ADR 0005](../adr/0005-blade-parts-and-counters-are-orthogonal.md): *nodes deal damage, edges give rigidity; spikes pop vertices, bunkers break edges*). There is no `edge_damage` stat. STR//10 scales per-vertex damage, and it is multiplied by the per-contact speed curve (#779 — see "Speed-scaled damage" below). Face/cycle bonus is deferred post-MVP and explicitly **rejected** as a geometric filled region. See [../design/mvp_decisions.md](../design/mvp_decisions.md) §D-1 and "Edge collision" below.

## Goal

Melee attacks need a *deterministic* outcome up front — same as ranged and
magic — so `AttackPlan.resolve()` stays a synchronous, side-effect-free
function that the UI, the AI, and `BattleSystem.launch_attack` can all call.

But a melee blade is a graph of pin-jointed bodies, and the player picked
the topology. A chain whips, a triangulated mesh stays rigid; that
expressiveness is the design intent (see `attack/melee/HANDOFF_OPUS.md`
before it was burned). Godot's `PinJoint2D` solver gives you that
expressiveness in real-time but provides no API to crunch the answer
ahead of time — the physics server steps on the engine clock and isn't
addressable from GDScript per-step.

So we replace the engine physics with a **custom Position-Based Dynamics
(PBD) solver**. Same solver runs the preview, the AI scoring, and the
live swing. Same inputs → same outputs.

## Why PBD

| Need | PBD answer |
|------|-----------|
| Deterministic per call | Pure function of positions + constraints + drivers |
| Cheap *per sub-step* | Verlet integration + constraint projection, all `PackedVector2Array` |
| Stable at any timestep | No mass/force inversion, no force explosion |
| — | **But a whole swing is milliseconds, not µs.** See "Measured cost" below. |
| Composable constraints | Distance today (welds included, as braces), future custom — all behind one `project(positions, inv_masses)` interface |
| One solver, two callers | `resolve()` runs it for hits; the visual swing replays the trajectory |

The cost is fidelity: PBD treats stiffness via solver iterations, not
true rigid-body dynamics. Triangulated blades need more iterations to
*look* rigid — currently 16 is fine; bump if blades visibly squish.
Mass-ratio whip cracking is softer than impulse-based physics. For a
one-revolution sweep at game speeds, both are acceptable.

## Architecture

```
attack/melee/
├── sim/                          PURE MATH — no scene nodes, no globals
│   ├── blade_state.gd            descriptor: positions, masses, edges, constraints
│   ├── blade_constraint.gd       abstract: project(positions, inv_masses)
│   ├── blade_distance_constraint.gd   pin-joint equivalent (rigid by default)
│   ├── blade_driver.gd           abstract: apply(positions, t)
│   ├── blade_arc_driver.gd       circular sweep around a center
│   ├── blade_swing_clock.gd      the swing's angular progress + Fortification drag
│   ├── blade_sim.gd              static simulate(state, drivers, duration, dt, ...) → Trajectory
│   ├── blade_trajectory.gd       per-step PackedVector2Array samples
│   └── blade_hit_scan.gd         deterministic hit events from trajectory + targets
│
├── blade_node.gd / .tscn         Node2D — visual circle, position-driven
├── blade_edge.gd / .tscn         Node2D — line draw between two BladeNodes
├── skill_blade.gd / .tscn        Node2D — owns visuals; build_from_skill_nodes(), simulate(), play()
└── melee_preview.gd              Mounted in the level; watches BattleSystem.
								  When the MELEE plan is valid, spawns a ghost
								  SkillBlade overlaid on the selection and loops
								  the same sim resolve() runs.

attack/plan/melee_attack_plan.gd  resolve() → builds BladeState → bake →
											walk (scan → land) → re-bake at each
											severance → AttackOutcome (#801)
```

## Data flow

```
				 ┌─ MeleeAttackPlan (UI selection)
				 │   pivot SkillNode + member SkillNodes + induced edges
				 ▼
			BladeState  ◄── pure descriptor (positions, inv_masses, edges, constraints)
				 │
				 ├──► BladeSim.simulate_range(state, drivers, step_offset, count)
				 │         │
				 │         ▼
				 │     BladeTrajectory (samples[step] = PackedVector2Array)
				 │         │
				 │         ├──► BladeHitScan.Sweep.scan_sample(t, pose, speeds)
				 │         │         │
				 │         │         ▼
				 │         │     [HitEvent { t, particle/edge, target }]
				 │         │         │
				 │         │         ▼ (resolve only) — landed per SAMPLE, so a
				 │         │     AttackOutcome         pop re-bakes what follows
				 │         │
				 │         └──► SkillBlade.play(trajectory)  ◄── ghost or live
				 │                   │
				 │                   ▼
				 │             BladeNode visuals tween-driven over real time
				 │             hit signal emitted at each HitEvent.t (live only)
				 ▼
			(visuals)
```

## Sim/presentation invariant

**The sim owns business logic — positions and pre-scanned hits. Presentation
may interpolate, retime, or re-sim freely without affecting outcomes.**

`BladeHitScan` pre-scans the whole swing into `Array[BladeHitEvent]` before
any playback happens (#502's timing, #619's write-up). By the time
`SkillBlade.play()` starts tweening, every hit's target, damage, and
trajectory-domain `t` is already decided. Playback's only job is to *replay*
that decision at whatever pace and fidelity looks good — a `playback_rate`
knob (#619), a future re-sim at a coarser `dt` for AI scoring, a slow-mo FX
on crits — none of it may resolve a NEW hit or move a WRONG target. If a
playback change ever needs `BladeHitScan` to run again, it has stopped being
presentation.

This is already structurally true — `play()` takes pre-scanned `hits` as a
parameter, never calls `BladeHitScan` itself — but was implicit until now.
Writing it down is what stops the next author resolving hits during playback.

## Module contracts

### `BladeState`

The descriptor handed to the sim. Constructed once per `simulate()` call;
mutates in place during stepping.

```gdscript
var positions: PackedVector2Array
var prev_positions: PackedVector2Array    # owned by BladeSim, do not touch
var inv_masses: PackedFloat32Array        # 0.0 = static (pivot)
var radii: PackedFloat32Array             # also used as hit radii
var vertex_damage: PackedFloat32Array     # per-particle damage COEFFICIENT (#779, see below)
var speed_history: Array[PackedFloat32Array]  # per-particle speed, one entry per sample (#779)
var pivot_index: int
var edges: Array[Vector2i]                # (particle_idx, particle_idx)
var constraints: Array[BladeConstraint]   # projected each iteration
```

Built via `BladeState.build(positions, pivot_idx, edges, radii)`. The
factory seeds one `BladeDistanceConstraint` per edge with `rest =
initial distance`. Callers append additional constraints before
simulating.

`vertex_damage[i]` is **not** the amount a contact lands — see "Speed-scaled
damage" below for what turns it into one.

### `BladeConstraint` (abstract)

```gdscript
@abstract func project(positions: PackedVector2Array,
					   inv_masses: PackedFloat32Array) -> void
```

Mutates `positions` in place to satisfy the constraint. Called N times
per sim step where N is the iteration count. Implementations must be
order-independent at the limit (more iterations = closer to satisfied).

### `BladeDistanceConstraint`

Standard PBD distance — the pin-joint replacement. `compliance` exposes
soft springiness: `0.0` = perfectly rigid, larger = more give per step.
Default `0.0`.

### `ClampAddon` — how a SkillNode addon stiffens the blade

A node carrying a `ClampAddon` **welds** the joint it sits on: the joint becomes
rigid instead of free-pin.

It does this without a new constraint class. A weld at joint J between two arms
is mathematically equivalent to a **distance constraint between the two arm-tip
particles**, so `ClampAddon` contributes one `BladeDistanceConstraint` per
neighbour pair and the existing PBD solver does the rest. Degree-2 — the typical
hinge — is one brace; higher degrees over-constrain, which PBD tolerates.

Two consequences worth knowing:

- **A brace is not a face.** Area-damage code traverses `state.edges`, the
  explicit edge list, and phantom braces live in `state.constraints` — so they
  stay invisible to it. That is the design doc's *"rigidity only, no face"*
  contract, upheld structurally rather than by convention.
- **An already-triangulated joint gains nothing.** The braces are redundant and
  PBD no-ops them, so a clamp spent there is a wasted addon slot. Anything
  choosing where to place clamps has to ask a graph question — is this joint in a
  triangle — before spending. That is #771.

> **Superseded design.** This section used to describe a `BladeClampConstraint`
> that clamped an arm particle's angle around the pivot to `[min_angle,
> max_angle]`, contributed via a hook on `MeleeAttackPlan._build_blade_state()`,
> and described it as *"not yet wired"*. The angular-range approach was dropped
> and `blade_clamp_constraint.gd` is gone from the tree; the phantom-brace weld
> above is what shipped. Corrected 2026-09-07, found while filing #771.

### `BladeDriver` (abstract)

```gdscript
@abstract func apply(positions: PackedVector2Array, t: float) -> void
```

Called *after* Verlet integration each step; overrides positions for
the particles a driver owns. Drivers are how the swing happens —
kinematic prescribed motion for select particles, everything else
follows via constraints.

### `BladeArcDriver`

Drives one particle in a circular arc around a center. Configured with
center, radius, start angle, sweep (default `TAU`), duration, and an
ease curve (default sine-in-out: 0 → max angular velocity at midpoint
→ 0). One per pivot-adjacent particle is what `MeleeAttackPlan` builds
for a swing.

Progress is `t / duration` unless a `BladeSwingClock` is attached AND that clock
is already warping, in which case the driver reads `clock.progress()` instead.
That is the whole of Fortification drag's reach into this class — see
"Fortification drag" below.

### `BladeSim.simulate(state, drivers, duration, dt, base_iterations, velocity_iter_ref, substeps, enable_length_scaling, clock)`

`simulate` is `simulate_range(state, drivers, 0, ceil(duration / dt), …)` — one
stepping loop, and a continued chunk is the same call with a different **integer**
`step_offset`. Per-particle damping lives on `BladeState.damping`, not in the
signature. See "Severance is a constraint removal" below.

Stateless static. `dt` is the **trajectory sample rate** — the caller's
contract for how many `traj.samples` come out (`duration / dt` of them),
unchanged by anything below. Internally, each sample interval runs `substeps`
physics steps at `dt / substeps`:

1. Verlet integrate dynamic particles: `(p, prev) → (p + (p - prev), p)`.
2. Apply each driver at the substep's own absolute time (finer-grained than
   the sample rate — a driver's kinematic position is exact at whatever time
   you ask it for, so more substeps is strictly more accurate here too, not
   just for constraint convergence).
3. Project constraints some number of times, then move to the next substep.
4. Once every substep in the interval has run, snapshot positions into
   trajectory — **one sample per interval, never one per substep.**

Two axes decide the per-substep iteration count, both multiplying a shared
sweep *budget* for the interval that then gets split across `substeps`
(see "Substeps, not iterations" below for why it's split rather than
multiplied):

**Velocity-scaled budget.** Stiff constraints can drift when particles are
moving fast — the per-step correction has less time to converge per unit of
motion. Setting `velocity_iter_ref > 0` enables adaptive scaling:

```
budget = base_iterations * (1 + max_particle_speed / velocity_iter_ref)
```

At `max_speed == velocity_iter_ref`, the budget doubles. At `max_speed == 0`,
it's `base_iterations`. Tune `velocity_iter_ref` to "the particle speed above
which you start seeing rubbery edges". Pass `0` to disable.

**Length-scaled budget** (#790) — see its own section below.

```
budget *= length_factor
iters_per_substep = max(1, round(budget / substeps))
```

`substeps` and `enable_length_scaling` are both new, defaulted parameters
(`DEFAULT_SUBSTEPS = 4`, `enable_length_scaling = true`), which is why none of
`skill_blade.gd`, `melee_attack_plan.gd`, or the AI's coarse rollout call site
needed to change: they inherit the new defaults automatically. Pass
`substeps = 1` to get exactly today's one-step-per-sample behaviour, or
`enable_length_scaling = false` to isolate the substep effect from the length
effect (this is how `test_blade_sim_substep.gd` proves the substep claim on
its own, and how `bench_blade_sim.gd` measures "today" as a baseline).

#### Substeps, not iterations

The naive fix for a blade that "looks stretchy" is to raise `base_iterations`.
That is the wrong lever, and the reasoning is a standard XPBD result (Macklin,
Müller, Chentanez, Kim & Macklin, *"Small Steps in Physics Simulation"*, 2019):
**for one PBD/XPBD constraint, per-step error scales with `dt²`, while adding
more Gauss-Seidel iterations at a fixed `dt` converges sub-linearly and
plateaus** — each additional pass fixes a shrinking fraction of what's left.
So for a *fixed total sweep budget* (`substeps × iterations_per_substep`),
spending it on smaller timesteps beats spending it on more passes per
timestep, usually by a lot: `4 substeps × 4 iters` (`dt/480`) converges far
better than `1 substep × 16 iters` (`dt/120`) at the *identical* total sweep
count — see `bench_blade_sim.gd`'s "isolated substep" comparison
(`test_substeps_alone_hold_shape_better_at_equal_or_lower_sweep_cost`, in
`test/unit/attack/test_blade_sim_substep.gd`), which measures a 55-hop whip
holding its shape at equal-or-lower cost purely from this swap, with the
length axis switched off so the two effects don't get conflated.

**Do not "simplify" this back into a bigger `base_iterations`.** That was
tried conceptually (the owner's original instinct — *"raising simulation
steps to idk 30"*) and costs roughly 2x for materially less benefit than the
substep redistribution, which is closer to free.

#### Length axis: hop count, not distance (#790)

Fidelity also has to scale with blade **length**, not only with swing speed —
a long, slow blade got no help from `velocity_iter_ref` even though it looked
just as stretchy as a fast one. "Length" here means **hop count from the
pivot**: `BladeState.pivot_eccentricity()`, the graph eccentricity of the
pivot within `state.constraints` (one BFS, computed once per `simulate()`
call, never per-step — that repeated cost is exactly what a sibling issue
found and fixed elsewhere, so don't reintroduce it here).

Two things it is deliberately **not**:

- **Not neighbour spacing** (one constraint's rest length) — a long
  constraint converges exactly as fast as a short one; rest length has
  nothing to do with propagation.
- **Not euclidean pivot-to-vertex distance** — that's what `velocity_iter_ref`
  already covers, via how fast a particle at that distance actually moves.
  Adding distance again buys nothing new.

Why hop count is the real bottleneck: this solver is Gauss-Seidel — each
constraint's projection uses whatever positions the *previous* constraint in
the sweep just wrote, so a positional correction propagates roughly **one
constraint per sweep**, in whatever direction `state.constraints`' order
happens to walk (not necessarily pivot-outward). A blade of eccentricity `L`
therefore needs on the order of `L` total sweeps just to transmit stiffness
from the pivot to its farthest vertex — below that, no number of *fast*
sweeps (small `dt`) fixes it, because propagation distance is a sweep-*count*
property, not a per-sweep-accuracy property. That is orthogonal to the
substep argument above: substeps buy numerical accuracy per already-propagated
constraint; the length axis buys the propagation depth itself.

`BladeSim.LENGTH_BASELINE_HOPS` (3) exempts short blades entirely — the
owner's own example, a stubby 3-hop blade, already converges at today's
budget and must keep costing exactly what it does today.
`BladeSim.LENGTH_ECC_CEILING` (40) clamps how far the budget can climb, so a
100+ member blade can't run it away; past the ceiling, more hops buy nothing
further. Both are named constants in `blade_sim.gd`, not inlined into the
scaling expression, specifically so a future tuning pass is a one-line edit
instead of an archaeology exercise. They're owner-tunable — chosen so a
maximally-long, ceiling-clamped blade costs roughly **4x** today's flat total
sweep count (measured in `bench_blade_sim.gd`'s worst-case chain benchmark);
that multiple is a starting point, not a spec.

**A rigidly trussed blade pays less than a whip of the same node count**,
for free: braces (e.g. `ClampAddon`'s phantom weld) shorten paths through
`state.constraints`, lowering eccentricity — so good bladesmithing already
buys a cheaper, better-converging sim on the same axis a sibling issue (#772)
wanted a gradient on.

**A long blade genuinely costs more total sweeps than it does today** once
past the baseline — that's the intended outcome, not a regression to guard
against. 16 sweeps cannot converge a 40-hop chain at any timestep; the owner
ruled to spend more on whips specifically because that's the only lever that
addresses propagation depth. Don't tune the length multiplier down to
squeeze under today's flat cost for a long blade — that defeats the axis.

#### Two backends, one meaning (#798)

Steps 1-3 above exist twice: in GDScript in `blade_sim.gd`, and in C++ in
`native/src/blade_solver_native.cpp`. The native one runs when the GDExtension
loaded and `BladeSim.use_native` is true; the GDScript one is the fallback and
is never removed. `BladeSim.backend()` reports which is live.

**This is not a fast/accurate pair.** The C++ is a literal transliteration --
same expressions, same evaluation order, same `real_t`(float32) vs `double`
split, no FMA contraction in the build flags -- and
`test/unit/attack/test_blade_native_parity.gd` pins the two to **bit-identical**
output, advanced state included. That threshold is not perfectionism:
`BladeHitScan` turns positions into a hit *set*, so a 1e-7 drift next to a shape
boundary is not a small error, it is a different attack. If parity ever goes
red, find the expression that stopped matching -- do not widen the test to
`approx`.

The build pins **`-ffp-contract=off`** (`native/SConstruct`) to hold that
threshold. It is not redundant: GCC and Clang default to `-ffp-contract=fast`,
and bit-identity survives today only because the baseline x86_64 target has no
FMA. `blade_sim.gdextension` already lists `linux.arm64` and macOS, where FMA
*is* baseline — there the default would fuse a multiply-add and drift the
solver on one platform only.

**Everything `simulate()` takes and everything it produces must cross the
boundary.** Both `simulate()` PARAMETERS and `BladeState` OUTPUTS are silent
failure modes rather than errors: a native path that ignored `substeps` or
`enable_length_scaling` (#790) would run different physics, and one that
omitted `speed_history` (#779) would zero blade damage — in both cases while a
GDScript-only test run stayed perfectly green. This is exactly what happened
between the port being written and #790/#779 landing, so when `simulate()`'s
signature or its state outputs change, the parity test gains a case for the new
axis in the *same* commit. `length_factor` is the one deliberate exception: it
crosses precomputed, because the pivot-eccentricity BFS behind it runs once per
resolve and duplicating it in C++ would put #790's rule in two places for no
measurable gain.

Note that `test_blade_sim_substep.gd` cannot serve as native coverage — it
counts projections through a `BladeDistanceConstraint` *subclass*, which the
fallback rule below deliberately refuses. The substep parity cases in
`test_blade_native_parity.gd` are what actually exercise the C++ substep loop.

Three ways to land on GDScript, all supported:

- **no binary built** -- the `ClassDB` lookup misses and the game runs anyway.
  This is why the native class is never written as a bare identifier in
  GDScript: that would make `blade_sim.gd` fail to *parse* on such a machine,
  which is the opposite of a fallback.
- **`BladeSim.use_native = false`** -- the differential-test and bench handle.
- **`BLADE_SIM_BACKEND=gdscript`** in the environment.

Plus one automatic fallback: a `BladeState` holding anything outside the
transliterated subset -- a constraint that is not exactly a
`BladeDistanceConstraint`, a driver that is not exactly a `BladeArcDriver`, or
an arc driver carrying a custom ease -- takes the GDScript path rather than
being quietly mis-simulated. The checks are `get_script() ==`, not `is`,
precisely so a subclass that overrides `project()`/`apply()` is not swallowed.

**`BladeHitScan` is deliberately NOT ported**, and this therefore does not
address #785. It calls `intersect_shape()` against the physics server, which is
neither freely thread-safe nor a numeric loop. Solver cost is `samples x
substeps x constraints`; hit-scan cost is `samples x edges`. The two add; only
the first one got cheap.

**Building it:** `mise run native:build` (append `-- template_release` for
exports). godot-cpp is a submodule at `native/godot-cpp`, so a fresh clone needs
a recursive submodule init first. Binaries are **not** committed --
`native/bin/` is gitignored.

### `BladeTrajectory`

Pure data: `sample_dt: float`, `samples: Array[PackedVector2Array]`.
`samples[k]` is the pose at simulated time `k * sample_dt` — `samples[0]`
is the pre-step pose (`BladeSim.simulate` prepends it, #633), so `duration()`
is `(samples.size() - 1) * sample_dt`, not `samples.size() * sample_dt`.
`sample(t: float)` linear-interpolates between adjacent step samples
for arbitrary real-time playback, clamping at both endpoints.

### `BladeHitScan.scan(trajectory, state, space_state, graph, collision_mask, exclude, broad_phase)`

Returns `Array[BladeHitEvent]`. **Queries the physics server** — it takes a
`PhysicsDirectSpaceState2D` and runs shape intersections per element per
sample; the blade itself never enters the physics world, only the query
shapes do. Per-element-per-collider dedup, so each particle/edge emits at
most one event per collider across the whole sweep, on first contact.

> This section previously described a pure point-vs-circle math scan taking
> a `targets` array. That is no longer the signature. The change matters
> beyond bookkeeping: **`scan` is not a pure function and cannot be assumed
> safe from a `WorkerThreadPool` task.** Space-state queries are valid during
> physics processing; anything planning to thread blade evaluation (#378)
> must confirm this before relying on it, or thread only `simulate` and batch
> the scans back on the main thread.

The trajectory step is fine enough (default `1/120s`) that sample-boundary
proximity is sufficient for hit detection at game speeds; no full
swept-volume continuous collision needed.

Each `BladeHitEvent` is also stamped with `speed` (#779, see "Speed-scaled
damage" below): for a vertex, that vertex's own speed at its contact sample,
read off `state.speed_history`; for an **edge**, the **mean of its two
endpoints'** — the segment midpoint's speed under rigid motion.

## Edge collision (#785)

Blade edges used to be inert ("D-1 MVP"). Two defects followed, both named on
#785, and both are properties of *vertex-only* contact rather than of tuning:

1. **Straddle.** Owner, 2026-09-07: *"say a truss blade slams into a bunker,
   but the initial nodes pass it -- no hitbox on the edge, it could slip in
   between; then it could hit in the 2nd part of the truss as it sweeps,
   causing bounces and largely chaotic behavior because the bunker is now in
   the center of the blade. […] we need SOMETHING against this"*
2. **Spacing luck.** Whether a spike bit depended on whether the defender
   happened to land on a vertex hitbox or in the gap between two — invisible,
   unchosen, and it cut both ways.

**The model.** Each edge is queried as a **capsule along the segment MINUS the
two endpoint hitbox disks** — it starts at one vertex's rim and stops at the
other's. That is the answer to "where do these capsules end?": a target sitting
*on* a hub is inside the hub's own circle and takes **vertex damage only**, so a
degree-6 hub is never worth vertex + 6× edge. **Faces are rejected** — the
design deliberately avoids geometric filled regions (`combat_system.md`: trigger
off cycle presence, a graph fact, not a region with no runtime planarity
guarantee), and polygon containment per sim step buys nothing capsules don't.

**No arbitration between elements — and the hub rule holds anyway.** #785 added a
per-substep "highest-damage element wins" pass so one contact could not be counted
as vertex + edge damage. [ADR 0005](../adr/0005-blade-parts-and-counters-are-orthogonal.md)
removed its premise by removing edge damage, so the pass went with it and the
counting rule is back to what it was before #785: **each element emits at most one
event per collider across the whole sweep, on first contact, and nothing ranks
elements against each other.** A degree-6 hub is still worth one *damaging*
contact, carried entirely by **geometry** — the capsules are trimmed back to the
rim of each endpoint's own disc, and whatever they still touch has no damage to
add. Deleting the rule also deleted the need for its own carve-out (*"particles
never arbitrate against each other"*, which existed because arbitrating vertices
let `test_ai_blade_rollout`'s pop-exempt pivot suppress the contact that was
supposed to pop).

**An edge contact mints no `DamageInstance` at all.** It stays in
`MeleeAttackPlan.last_events` — it is a real contact, and #781's bunker break is
its consumer — but `last_hits` / `AttackOutcome.hits` is a *subsequence* of the
event list, vertices only. A zero-amount hit would still buy a crit roll, a
schedule entry, a landing beat and a line in the `AttackRecord`: a change to the
counting rule with no gameplay content, which is exactly what
`combat_system.md`'s *"tame runaway with the scalars, never the counting rule"*
warns against.

**An edge carries no stats at all.** There is no `edge_damage` StatDef, no
per-edge damage array on `BladeState`, and no edge `blunting`. Not derived from
the endpoints by MIN, MAX or mean either — #785 shipped the MIN for a day and
[ADR 0005](../adr/0005-blade-parts-and-counters-are-orthogonal.md) struck it on
the owner's lever test (two spiked balls on a lever deal massive damage
naturally; the *beam* between them dealing massive damage *"orrrr no that makes
no sense??"*) and on a structural objection: a truss and a chain with the same
nodes differ only in their edges, so a derivation would make triangulating for
**rigidity** silently multiply **damage**, and "add a node for offence, add an
edge for structure" would stop being a choice. **This ground is dead — do not
re-propose a gentler derivation.** Edge *geometry* still derives from the
endpoints (capsule trimmed to each disc's rim, disc radius growing with
allocation level) because geometry is physics, not offence. If edge offence is
ever wanted back it is #409's job to argue against the ADR, with magnitude as an
`Entity` stat and placement as a boolean on `Edge`.

**A capsule contact never touches the spike system.** *A spike destroys matter, a
bunker destroys structure.* An edge sweeping over a spiked node drains nothing,
severs nothing and leaves `pool.current` exactly where it was, so a 10-node blade
still delivers ~10 spike interactions rather than ~19.
`BladePopResolver.LiveGate._admit_edge` implements this as an **explicit skip** of
the spike ladder, and it has to: giving an edge blunting `0` instead would make
`remaining >= blunting` trivially true, so every edge contact would `deplete(0)`
and sever — #778's "zero means unfilled" gotcha, inverted. There is no
`_blunting_for_edge`.

Spacing luck for spikes — whether a defender happened to land on a vertex disc or
in the gap between two — is **not** a defect this needs to fix. Owner,
2026-09-08: *"blades be floppy as heck, intentionally threading the
spiked-defender needle would be close to impossible […] so many moving parts it's
almost guaranteed to hit, and if not, no biggie."* Spacing luck for **bunkers**
was the real defect, and capsules fix it.

**Severance is a set, not a splice** — and since ADR 0005 the *only* thing that
will sever an edge is #781's bunker break, a rigid blade shattering against an
obstacle. `LiveGate._sever_edge`, `BladeState.removed_edges` and `remove_edge()`
are kept as that seam and currently have no production caller.
`BladeState.removed_edges` records severed indices; `state.edges` is never spliced, because a `BladeHitEvent` carries an
`edge_idx` *into* it and a splice would silently re-point every pending event.
That also keeps #795's cached adjacency map valid after a severance — the map
pairs each neighbour with its own edge index, so `_reachable_from_pivot` skips a
severed edge in O(1) as it walks and the map is built **once per swing**, never
rebuilt. Losing an edge severs a remainder by exactly the same criterion as
losing a vertex, so `_kill` and `_sever_edge` share one `_disintegrate_unreachable`.

**Broad phase.** Per substep, one shape query over the blade's whole bounding
box; if it comes back empty the ~300 narrow-phase queries are skipped entirely.
The box is a strict superset of every narrow-phase shape, so the flag can only
change **cost**, never the event set — `bench_blade_hit_scan.gd` asserts exactly
that, and reports both settings. See "Measured cost".

## Speed-scaled damage (#779)

`damage = blade_damage × f(speed)`, evaluated **per contact**, from the
contacting vertex's own speed at its own contact time — not a blade-wide
average and not a per-step maximum. The curve is a saturating hyperbolic,
owner-pinned:

```
f(v) = 1 + (M - 1) * v / (v + v_half)
```

`f(0) == 1` exactly (a stationary vertex deals its base coefficient, never a
penalty); `f(v_half) == 1 + (M-1)/2` (half the bonus collected at `v_half`);
`f(v → ∞) → M` (bounded — an artificially huge speed lands at the configured
max, never a proportional runaway number). `M` and `v_half` are `ScalarStat`s
on the board (`blade_speed_multiplier_max`, `blade_speed_half`; #772's
`.claude/rules/stat-knobs-and-bins.md`), never hardcoded. Floored at `1.0`
unconditionally — even a misconfigured `M < 1.0` cannot turn into a penalty;
that variant (`<1.0` for real, punishing a slow blade) is a separate,
deliberately parked future issue.

Implementation, entirely in `attack/melee/sim/`:

- **`BladeState.speed_damage_multiplier(speed, m, v_half)`** is the curve
  itself — a static helper taking raw numbers rather than a `BladeHitEvent`
  or a `StatBoard`, so an **edge** hit (#785 — landed) reuses the identical
  curve instead of a second inlined copy. `BladeState.stat_value(board, id, fallback)` is the
  matching stat-read guard (mirrors `CritRoll.multiplier_for`'s null
  handling), since this unit owns no file `CritRoll` lives in.
- **`vertex_damage[i]` is a per-particle COEFFICIENT, not the landing
  amount.** It used to be the full per-contact damage read directly by the
  hit sites; it is now the wielder's localized `blade_damage` (unchanged —
  this is a pure bonus, base damage was NOT rebalanced down) multiplied by
  `speed_damage_multiplier` at each hit site.
- **`speed_history` retains the PHYSICS rate, not the sample rate.**
  `BladeSim._step` already computed a per-particle `sp_sq` before this landed
  (feeding the existing velocity-scaled sweep budget) but only kept the
  step's aggregate max. `_step` now returns each particle's own speed for
  that substep; `BladeSim.simulate` keeps the LAST substep's return per
  sample interval — the physics-rate value closest to that sample's time —
  and appends it to `state.speed_history`, index-parallel to
  `BladeTrajectory.samples` (including a zero-filled entry at index 0, for
  the pre-step pose, mirroring `samples[0]`'s meaning, #633). Substeps matter
  here specifically because #790 made the substep count independent of the
  sample count — a caller with `substeps > 1` gets a materially better speed
  estimate than reading it off the sample-to-sample position delta would.
- **`BladeHitScan.scan` stamps each particle event's `speed`** off
  `state.speed_history[i][p_idx]` at the event's own sample index `i` —
  never a rescan, never an average.
- **The two real damage sites both multiply, at two different clocks, for
  two different audiences:**
  - `BladeDamageInstance.land_on` (the authority's own real damage,
    `attack/melee/sim/blade_damage_instance.gd`) multiplies `amount` — which
    `MeleeAttackPlan.resolve_against` stamped as the bare coefficient — by
    `speed_damage_multiplier(_event.speed, ...)`, reading `M`/`v_half` off
    `attacker.stat_board`, immediately before `super.land_on()` applies it.
    This runs exactly once per hit, on the authority's own resolve.
  - `SkillBlade._apply_playback_frame`'s `hit` signal (the VISUAL floater
    for a live or ghost swing) applies the identical curve, reading
    `owned_by.stat_board`, so a preview/ghost swing shows the number the real
    swing will land. It is cosmetic — nothing downstream of that signal is
    gameplay-authoritative.

### Determinism — safe, and why

Speed-scaled damage means a particle's float POSITION now turns into a
LANDING AMOUNT — a genuinely new category of consequence. `blade_arc_driver.gd`'s
`#547` comment used to claim *"a last-ulp difference here moves a particle,
not a landing"*; that is no longer literally true in spirit; damage now rides
on exactly the kind of position-derived number #547 was talking about.

**This is still safe, for one reason, and it is not "the math is simple
enough to agree across platforms."** ADR 0002 settles the actual reason: a
peer re-simulates the blade only to *draw* it. Every damage number and the
hit set itself come off the `AttackRecord` the authority captured
POST-APPLY — `AttackRecord.rebuild()` never constructs a
`BladeDamageInstance` (it rebuilds a plain `DamageInstance` typed `TRUE`,
carrying the host's already-computed `effective_amount` straight through
mitigation), so a peer is physically incapable of re-evaluating `f(speed)`
against its own, potentially float-divergent, re-simulated positions. The
authority resolves and lands on a shadow world exactly once; every peer,
including the host's own live world, replays that one recorded result
(`.claude/rules/attack-timeline.md`).

**No peer may ever re-decide a landing from its own sim.** If a future change
ever makes a peer call `BladeDamageInstance.land_on` (or otherwise
re-evaluate `speed_damage_multiplier` against locally-simulated positions)
to save wire bytes, that is the day this section's safety argument stops
holding — see `.claude/rules/multiplayer-sync.md`. Do not "fix" the #547
comment's cosine by adding quantization or avoiding transcendentals here:
the transcendental/float-divergence concern is void as a design driver for
this curve — `speed_damage_multiplier` itself is pure `+ - * /`, and the one
transcendental-adjacent op anywhere in this path (`sqrt`, deriving a scalar
speed from `sp_sq` in `BladeSim._step`) is exempt from `lint-transcendentals`
as IEEE-754 correctly-rounded. The hyperbolic form was chosen on feel, not on
determinism.

## Fortification drag (#780)

A wall of fortified nodes bogs a blade down. The magnitude is a defender-side,
node-local stat, `swing_drag`, base 0; `FortificationAddon` authors the grant, so
an ordinary node drags nothing.

### It acts on the CLOCK, and it had to

The obvious implementation — bleed velocity off the contacting particle — does
nothing to a rigid blade, i.e. nothing to exactly the blade it is meant to slow.
Two mechanisms defeat it, in order: the distance constraints fight the damping,
and then `_step` re-applies the drivers **after** the Verlet integration, so
`BladeArcDriver.apply()`, a pure function of its argument, overwrites the damped
position outright. `BladeState.damping` is the wrong channel for the same
reason — it is the **severance** knob, for a particle no driver is steering any
more, where there is nothing to overwrite it.

What drag can move is the argument. `BladeSwingClock` owns the angular progress
`f` the driver evaluates its ease at, and every fortified node the blade touches
adds its `swing_drag` to a running total. The clock then advances at

```
f += (sub_dt / duration) * 1 / (1 + drag)
```

for the rest of the swing. One clock per swing, shared by every arc driver: they
describe one rigid body turning about one pivot, so a per-driver clock would
shear the blade.

**Monotonic by construction.** `1 / (1 + drag)` is strictly positive for every
`drag >= 0` and at most 1, and `f` is clamped at 1, so `f` never decreases and
never overruns. No configuration of fortified nodes can reverse a swing, and
none can freeze one either — the *hard* stall is #781's bunker. What a wall does
instead is spend the arc: five nodes at drag 1 leave the swing at a sixth of its
nominal rate, so within the fixed swing duration it covers roughly a sixth of its
sweep and everything further round is simply never reached. That is how a wall
protects what is behind it — no deletion, no severance, no cascade.

**Causal, not global.** A zone's drag is banked only once its own contact has
happened, so it slows the rest of the arc and never the approach to itself. A
global warp would be paradoxical: a fortified node at the end of the sweep would
retroactively stop the swing from ever reaching it.

**Nothing is paid by a swing that never meets one.** `MeleeAttackPlan` attaches a
clock only when a fortified node is within the blade's reach; otherwise `clock`
is null, the driver runs its original expression, and the native backend still
takes the swing. Even an *attached* clock is inert until first contact — the
driver keeps reading `t / duration` verbatim, so a swing with a fortified node in
its field that it never touches is **bit-identical** to one with no field at all.
That exactness is deliberate: accumulating `f` from t=0 would drift in the last
bits and quietly make the mere presence of a wall change a swing that never met
it. A warping clock is the **one** thing that still forces the GDScript backend:
it accumulates `_f` in float after first contact by design, so the C++
transliteration does not model it. Per-particle damping and a continued Verlet
history (`step_offset > 0`) used to be on that list too; #803 taught the native
loop both, so a severed swing runs native end to end.

### Where it sits under ADR 0005

A spike destroys matter, a bunker destroys structure, and **a wall destroys
neither — it spends the swing's budget instead.** Drag removes no blade part, so
it is a *third* defensive effect that cannot violate the ADR's vertex/edge
disjointness rather than an exception to it.

**Sensing is on discs AND rim-trimmed capsules**, which is a question of what the
swing *touches*, not of which blade part is doing the defending, so it does not
disturb that either. This is the surviving half of #785's rule that *a capsule
contact is a full contact for every defender effect*: ADR 0005 retired the damage
and spikes half of that rule (an edge carries no stats) but never touched the
drag and bunker-break half, and #785 is now closed, so the rule lives here.
The gameplay reason it must survive for drag: a *sweep*'s edges cross exactly the
gaps between the vertex arcs, so disc-only sensing would reintroduce spacing luck
for drag **magnitude** against a wall. Spacing luck was ruled harmless for spikes
because threading a single spiked node is not a strategy — a wall is precisely
the case where it would be, and the density gradient is the whole mechanic.

**Anti-double-dip is live again, for drag only.** ADR 0005 says #785's
arbitration is unreachable because "with no edge damage there is nothing to
double-count". That is true of damage and false of drag: a fortified node touched
by its disc plus two incident capsules would otherwise bank three times. So a
zone contributes its `swing_drag` **at most once for the whole swing**. Do not
delete that rule as redundant on the ADR's authority — the ADR is talking about
damage.

### Two sensing models, and they can disagree

`BladeSwingClock.sense()` is **analytic** — point-in-disc and point-to-segment —
where `BladeHitScan` queries `PhysicsDirectSpaceState2D`. That is by necessity,
not preference: `AiBladeRollout` runs `BladeSim.simulate` from
`WorkerThreadPool` tasks, where a physics-server query is not safe, so the solver
must never touch the space state.

The consequence to know, because it will look like a bug: **at the margin a node
can drag the swing without producing a hit event, or produce a hit event without
having dragged.** `BladeHitScan` remains the sole authority for hit events,
damage and pops; the clock decides only how fast time runs. Keep the two
`_EDGE_RADIUS` constants equal.

Sensing runs once per **trajectory sample**, not per substep — a sample is
1/120 s against a 1.2 s swing, so the granularity costs under 1% of the arc,
while per-substep sensing would quadruple the only per-step work the solver does
outside its own constraint sweeps.

### Determinism and the mirror

The drag field is read off the live graph at resolve time. A mirror peer re-runs
`plan.resolve()` on a throwaway shadow purely to *draw* (`BattleSystem`'s apply
path), before the record lands, so it builds the field from the same pre-attack
node states the authority did. Nothing here is a fresh roll and nothing reads the
clock across a frame boundary; the same swing replays to the same arc.

`SkillBlade.simulate()` takes the clock too, and `MeleePreview` builds a fresh
one per ghost cycle (a clock banks what it has already touched, so reusing one
would start cycle 2 already dragged). Without that the ghost would promise an arc
the committed swing does not deliver.

## Severance is a constraint removal (#801, supersedes #186's free flight)

When a spike pop kills a blade vertex, everything downstream of it stops being
reachable from the driven pivot. Before #186 those vertices simply **vanished**,
which made the *single-spine* blade fail catastrophically: one spiked node
deleted most of a sweep. Owner, filing the #772 design pass:

> *"currently such a swing would fail so hard e.g. the first spiked node they
> encounter could neuter the entire thing, which is also not what we want"*

The partial-success dial is that the remainder **keeps going**. Owner, 2026-09-08:

> *"leaf node sits on blade, swinging. sim constraint ties it to its neighbour
> via edge. say its neighbour gets popped, taking its edges with it. leaf node is
> now fully dislocated. constraint: gone. do we need to track this component
> separately? no it's the same old same old, just one less restriction. keep
> simulating displacement and enforce the remaining constraints"*

That is exactly what happens now. **There is no fragment type, no second sim, no
`is_unpinned`, and no separation-velocity seeding** — the velocities were never
lost, because the particles never left the state.

### What a death is

Three things, none of which needs C++ (`inv_masses`, the constraint list and the
driver list are all per-call inputs to the native backend):

1. `inv_mass = 0` — a **frozen corpse**, staying exactly where it died. That is
   the same expression that pins the pivot, and it is #787's death-time snapshot
   for free.
2. every constraint **incident to it** dropped (`BladeState.remove_vertex`),
   including a `ClampAddon` phantom brace — a weld to a corpse is a weld to a
   wall.
3. its `BladeArcDriver` dropped, if it was one of the pivot's driven neighbours.
   `MeleeAttackPlan._surviving_drivers` also drops the driver of a merely
   **coasting** vertex: alive, but no longer attached to the handle, so nothing
   may keep swinging it.

Everything downstream then coasts by plain Verlet, because that is what Verlet
does to a particle nothing is pulling on. It is in the **same
`last_trajectory`**, at the **same index** — `#785`'s index-stability invariant
holds for the whole swing — so `SkillBlade.play` draws it with no new code, and
#186's "the fragment is not drawn" residue is closed.

`BladeState.removed_vertices` mirrors `removed_edges` exactly: a **recorded set,
never a splice**, because a `BladeHitEvent` carries a `particle_idx` into
`positions` and a splice would silently re-point every pending event — and would
invalidate `Pop.particle_idx`, which #799's counting and #781's bunker seam both
read.

### Orphans are COASTING, not dead

`BladePopResolver.Result` now says two separate things:

| | means |
|---|---|
| `dead_at` | a spike **destroyed** this vertex at this time. Its hits from then on are refused. |
| `severances` | this **set of vertices** lost its path to the handle at this time. They are not in `dead_at`; they are still armed, still land #779-scaled hits, and can be popped again. |

So `dead_at.size()` and `vertex_pop_count()` now agree by construction rather
than by filter — which is what #799 was filed about, and #801 removed its
premise. Only the **pivot** is exempt from popping, unconditionally: it is the
wielder's grip, and there is no second root to exempt any more.

### The seam is "what left, and when" — never "why"

`BladePopResolver.LiveGate._disintegrate_unreachable` is the single place a
severance is born, whatever removed the vertex. It appends a
`BladePopResolver.Severance` — `{t, vertices}` and nothing else. No trigger
information reaches the continuation, deliberately:

* a **spike pop** produces one today;
* **#781's bunker break** will produce one through the identical call, and needs
  no continuation code at all.

`test_the_continuation_is_a_function_of_topology_not_of_trigger` pins it: the
same constraint set and inverse masses reached by `remove_vertex` and reached by
hand (the shape an edge break leaves) continue **bit-identically**.

### The drag term, now per particle

There is still **no disconnection damage scale**. Owner, 2026-09-08:

> *"emergent from speed, no halving, but possible a slight drag on disconnected
> pieces"*

A coasting vertex carries the identical coefficient it had while attached, and
[#779's speed curve](#speed-scaled-damage-779) — applied at land time off the
contacting vertex's own speed — already gives it less than a driven blade,
continuously. And *more* if it happens to be flung fast, which is the fantasy.

The one authored term is **`BladeState.SEVERED_DRAG`** (0.8/s, owner-tunable),
written into **`BladeState.damping`**, a `PackedFloat32Array`, for exactly the
`_reachable_from_pivot` complement at each severance. Two exactness properties
hold and are pinned:

* an **empty** array — every ordinary swing — makes `_step` skip the multiply
  outright, so the driven path is bit-identical to one built before the member
  existed, native parity included;
* a **zero entry** yields a retention factor of exactly `1.0`, so a coasting
  vertex at drag 0 coasts undecelerated. #186's acceptance 4 survives, now as a
  *per-particle* claim.

**This is not `BladeSwingClock`'s drag** (#780). That one slows the swing's
**clock** and removes nothing from the blade; this one bleeds the velocity of a
particle nothing is driving any more. They cannot share a channel: a driven
particle's damping is fought by the distance constraints and then overwritten
outright by its `BladeArcDriver`.

### The loop: sim → scan → LAND, re-baked at each severance

The pop gate is reached from `BladeDamageInstance.land_on` **inside**
`OutcomeApplier.apply`'s walk — so the interleave is sim / scan / **land**, not
sim / scan / gate: only *applying* produces the world the next pop decision has
to read. No suspendable applier is needed; the per-batch idiom is
sub-`AttackOutcome` → `OutcomeSchedule.compile` → same crit rng → `apply` →
merge, which #186's free-flight round already demonstrated.

`MeleeAttackPlan.resolve_against`:

1. **Optimistically bake** the whole remaining swing in one
   `BladeSim.simulate_range` call — exactly today's call, so a swing that severs
   nothing pays **nothing**.
2. Walk it sample by sample. Per sample: `BladeHitScan.Sweep.scan_sample` →
   mint `BladeDamageInstance`s → compile → `CritRoll.decide_all` on the swing's
   **one** rng → `OutcomeApplier.apply`.
3. If that batch produced a `Pop`, **stop the walk**, rewind, mutate the state
   at that sample, and re-bake from it. Continue.
4. One `OutcomeSchedule.compile` over the merged outcome at the end.

Because a bake is a pure function of the state, the trajectory this produces is
**bit-for-bit what a true per-sample interleave would have produced** —
optimistic execution is an implementation strategy, not a compromise. Solver
calls per resolve: `1 + severances`, against `145` for a literal per-sample
loop, which would have spent the whole of #798's gain in marshalling.

### Landing on the severance sample: `prev_samples` (#803)

Rewinding to the severance sample needs the **exact Verlet history** there, and
`prev_positions` at a sample is not recoverable from `samples`: `_step` rewrites
it once per **substep**, so it is a mid-sample pose. So both backends emit it:
`BladeTrajectory.prev_samples[k]` is `prev_positions` as the state held it after
step `k`, parallel to `samples` index for index. The resolve loop lands on a
severance at local sample `j` by **reading** `samples[j]` / `prev_samples[j]`
off the bake it already has, and the swing clock — sim state too — keeps a
chunk-local `history` of `Bank`s the same way, so `restore(history[j])` rewinds
it without re-ticking. A rewind is two array copies; the parity suite pins that
a continuation seeded from `prev_samples` equals the run that never stopped, on
both backends.

Before #803 the native loop emitted no `prev_samples`, and #801 instead
snapshotted the chunk's start and **re-ran the head** to land on the sample —
one extra partial bake per severance, in GDScript. That replay is gone; it was a
workaround for a missing output, never the design. The **prefix property** it
rested on — a short bake of `k` steps equals the first `k` samples of a long one,
because nothing in the solver is a function of the run's total length — is still
worth keeping true (the optimistic bake itself assumes nothing downstream of a
sample affects it), and
`test_blade_chunked_parity.gd::test_a_short_bake_is_a_prefix_of_a_long_one`
still says so.

### `simulate_range`, and the integer step offset

`BladeSim.simulate` is `simulate_range(0, ceil(duration / dt))`. There is **one
stepping loop per backend**, not a second integrator for a continued chunk.
`step_offset == 0` resets the Verlet history; any other offset **trusts
`state.prev_positions`** as it stands.

Every substep's time is `float(step_offset + local_step) * dt + float(s + 1) *
sub_dt` — an **integer** global step, never a float `t_start` accumulated across
chunks, which would drift in the last bits and make a chunked run differ from an
unchunked one. `test_blade_chunked_parity.gd` pins them bit-identical.

**The `BladeSwingClock` is sim state and is carried across chunks** — one
instance, never rebuilt. `_f`, banked `drag`, `touched`, `_warping` and `_last_t`
all persist; a fresh clock mid-swing would un-bank a Fortification wall's drag
and silently stop it sheltering what is behind it. `simulate_range` records a
`capture()` per sample into `clock.history`, and `restore(history[j])` rewinds it
to a severance. (A *dragged* swing accumulates `_f` in float after
first contact **by design** and is GDScript-only; the integer-step rule applies
to the pre-contact segment and to the clock's seed.)

### A dead element is not scanned

`BladeHitScan.Sweep` skips a `removed_vertices` disc, a `removed_edges` capsule,
and any edge with a removed endpoint. So **`last_events` no longer contains
events that would be refused at land time** — a #801 change worth knowing for
#782, which inherits `last_hits` being a subsequence of `last_events`. It is also
where "a pop swing costs *fewer* physics queries than an unsevered one" comes
from: dead elements are never queried, and #186's second full scan of the
fragment tail is gone.

Per-element-per-collider dedup now spans the whole sweep **for a coasting vertex
too**: under #186 a fragment got a fresh scan and could re-hit a collider it had
already hit while driven. The documented counting rule says once; this makes it
true.

### Ordering: the residue is gone, and one new one is named

#186's ordering caveat — two landings on the same node, one driven and one free,
seeing each other's mitigation in *shadow* order — is **gone**: everything lands
in true `t` order on the shadow.

One new, deliberate order change replaces it: crits are now rolled per batch,
**after** earlier landings applied, rather than all up front. The stream is
identical (batches run in `t` order, `OutcomeSchedule._sorted` breaks a same-`t`
tie on insertion index, and one rng object is handed to every batch —
`test_batched_crit_rolls_equal_one_global_roll` pins it). The residue: if a swing
friendly-fires a node whose depletion changes the **attacker's own**
`crit_chance` mid-swing, a late hit's crit can differ from what the pre-#801
order would have given. That is arguably the more correct order; it is recorded
here so it is not filed as a bug. #186's per-round crit salt is gone with the
rounds it existed for.

Everything still rides the **same `AttackOutcome`**, so `AttackRecord.capture`
picks a coasting vertex's landings up like any other and a peer **replays** them
— it never re-runs a solver and never needs to know a severance happened.
Determinism holds under `.claude/rules/multiplayer-sync.md` unchanged.


## Engine-side wiring

### `SkillBlade` (visual + playback)

`build_from_skill_nodes(skill_nodes, pivot, induced_edges, owner)`
constructs `BladeState` and spawns BladeNode + BladeEdge visuals at
their initial positions. `simulate(duration)` runs the sim (drivers
auto-built from pivot-adjacent particles). `play(trajectory, hits,
ghostly, playback_rate)` tweens visual positions through the trajectory
and emits `hit` signals at scheduled times.

`playback_rate` (default `1.0`, #619) only changes the tween's wall-clock
pace — `tween_method`'s callback argument is always trajectory time
(`0..traj.duration()`), regardless of how many real seconds it takes to
sweep that range, so `_apply_playback_frame` and every hit comparison stay
in trajectory time unmodified. A rate of `0.5` takes twice the wall-clock
for the same swing; `MeleePreview`'s idle loop never passes a rate, so it
keeps today's pace exactly.

`BladeNode` and `BladeEdge` are pure `Node2D` visuals now — no
`RigidBody2D`, no `PinJoint2D`, no `Area2D` hitbox. Their positions are
written directly by `SkillBlade.play` each frame. Hit detection is the
deterministic scan, not Godot collision overlap.

### `MeleeAttackPlan.resolve()`

```
selection → BladeState → drivers → bake (simulate_range)
		→ per sample: Sweep.scan_sample → mint → compile → crit → apply
		→ on a pop: rewind, remove_vertex, re-bake from that sample
		→ AttackOutcome { hits: DamageInstance[], ap_cost }
```

Synchronous. Pure. Same call shape as `RangedAttackPlan.resolve` and
`MagicAttackPlan.resolve`.

### `MeleePreview` (live ghost loop)

Mounted in the level (same pattern as `AttackVFX`,
`AttackHighlightOverlay`). Watches `BattleSystem.attack_plan_changed`
and `attack_plan_state_changed`:

- When the active plan is a valid `MeleeAttackPlan`: spawn a ghost
  `SkillBlade` overlaid on the selection (translucent modulate, real
  position). Loop: simulate → play (ghost) → fade out → fade in → repeat.
- When the plan changes, becomes invalid, or is canceled: free the ghost
  and stop the loop.

The ghost uses the **same** `simulate()` call shape `resolve()` does,
so the player sees exactly the trajectory the AI scores. Hit signal is
ignored during ghost play — no damage during preview.

## Measured cost

### Hit scan (#785)

`test/perf/bench_blade_hit_scan.gd` — a `GutTest` rather than a bare SceneTree
script, because the scan needs a live `PhysicsDirectSpaceState2D` and that only
exists inside a scene tree (which is exactly why `bench_blade_sim.gd` excludes
it). Run: `mise run test:one -- res://test/perf/bench_blade_hit_scan.gd`.
RX 7900 XTX / Ryzen-class desktop, Godot 4.7.1, headless, 2026-09-08. Blade:
100 vertices / 197 edges (braced ladder), 145 substeps, 40 defender nodes,
5 reps.

| defender field | broad phase ON | OFF | speedup |
|---|---|---|---|
| dense (defenders on the swept arc) | 29.6 ms | 28.6 ms | 0.97x |
| empty sweep (defenders off-map) | 0.56 ms | 24.3 ms | **43.6x** |

Read it as a **bound, not a budget**: the dense row is the worst case (every
substep's bounding box hits something, so the broad phase can never reject and
costs ~3% for nothing), the empty row is the best. A real map lives between
them, and *which* end is a property of the map, not of this code. Two
consequences:

- **~30 ms per resolve at the 100-vertex scale the owner named makes #782's
  caching load-bearing rather than nice-to-have** — the preview rebuilds
  continuously, and it must not pay this per rebuild.
- The remaining cost is ~21600 physics-server shape queries per resolve
  (297 elements × 145 substeps). Collapsing that to an **analytic** narrow phase
  (gather the candidate defender set once over the swept arc's box, then
  point-vs-capsule: a clamped projection and a length compare) is the real fix,
  and it is the one thing that would let the scan leave the main thread. It is
  deliberately NOT done here: it would make this module encode target geometry,
  which it currently refuses to do — targets just publish a `CollisionShape2D`.

### Solver

`test/perf/bench_blade_sim.gd` (headless SceneTree script; run it, don't trust
this table after the solver changes). It prints **both backends** in one
invocation when the extension is built. Solver only — no hit scan. Ryzen-class
desktop CPU, Godot 4.7.1, 1.2s swing at `dt = 1/120`, 16 base iterations.

**All numbers below are at the SHIPPED defaults** (`substeps = 4`,
`enable_length_scaling = true`) — `_bench`/`_run` pass six positional args and
inherit the rest, so they measure what `resolve()` actually runs. They read
noticeably higher than the pre-#790 edition of this table for any `k` past
`LENGTH_BASELINE_HOPS`: more total work for a better-converged result, not a
regression. The apples-to-apples "before vs after #790" comparison is its own
section further down.

### Both backends, side by side (2026-09-08)

| config | GDScript | native | speedup |
|---|---|---|---|
| chain k=5 | 3.45 ms | 0.16 ms | 22x |
| chain k=10 | 9.83 ms | 0.48 ms | 21x |
| chain k=20 | 29.03 ms | **1.60 ms** | 18x |
| chain k=30 | 54.91 ms | 3.39 ms | 16x |
| chain k=20, adaptive iters (`velocity_iter_ref = 400`) | 58.61 ms | 3.34 ms | 18x |
| triangulated mesh k=20 | 35.16 ms | 1.58 ms | 22x |
| k=20, `dt=1/60`, 16 iters | 13.50 ms | 0.80 ms | 17x |
| k=20, `dt=1/30`, 16 iters | 6.85 ms | 0.42 ms | 16x |
| k=20, `dt=1/30`, 4 iters (the AI coarse tier) | 1.89 ms | **0.15 ms** | 13x |
| k=20, `dt=1/30`, 2 iters | 1.18 ms | 0.11 ms | 11x |

**GDScript is milliseconds per swing, not microseconds.** Cost is ≈ linear in
`steps × substeps × iterations × constraints`, which works out to ~0.28 µs per
constraint projection — that is the interpreter, not the algorithm, exactly as
#796 predicted. Native brings it to ~0.015 µs. Adaptive iterations roughly
double the work; a triangulated mesh roughly doubles it again (2× the
constraints).

Note the speedup **shrinks at the cheap end**: a 2-iteration coarse eval spends
a growing share of its time marshalling packed arrays across the extension
boundary, a cost fixed per `simulate()` call rather than per constraint. Two
consequences worth carrying forward. First, the coarse tier is **much less
necessary than it was** — full fidelity native (1.6 ms) is now cheaper than the
old GDScript *coarse* tier (1.9 ms), so re-measure before building more tiers on
top of it. Second, a two-tier scheme ranks on a different sim than `resolve()`
executes, so any divergence has to be deliberate and tested, not assumed
harmless.

### #803: what a severance costs (2026-09-09)

Same harness (`_bench_pop_swing`), same machine class (Ryzen 7 7800X3D), a
k=20 chain severed at vertex 8 on sample 48 of 144, run exactly as
`resolve_against` runs it: one optimistic whole bake, rewind off `prev_samples`,
`remove_vertex` + drag on the coasting set, re-bake the tail.

| | native | GDScript |
|---|---|---|
| no-pop swing (whole bake) | 1.61 ms | 29.0 ms |
| re-baked tail alone | 0.50 ms | 10.4 ms |
| **pop swing** (bake + rewind + tail) | **2.11 ms** | 39.4 ms |
| bound: whole + tail | 2.10 ms | 39.4 ms |

A pop swing costs the no-pop swing plus the tail and nothing measurable else —
the rewind is two array duplicates, ~10 µs. Before #803 the same severance on a
native machine paid the whole bake native, then the head replay **and** the tail
in GDScript (≈ 9.7 + 10.4 ms): roughly 22 ms of solver, now 2.1 ms.

### #790: substepped + length-scaled, today vs new — 100-node swing

`bench_blade_sim.gd`'s `_bench_substep_config` (same machine as above). Two
100-node fixtures: a **braced mesh** (246 constraints — the issue's "~250",
pivot eccentricity 49, past the ceiling) and a **pure chain/whip** (99
constraints, pivot eccentricity 99 — the worst case for the length axis).
"Today" = `dt=1/120, 16 iters, substeps=1, length off`. "#790" =
`dt=1/120, 16 iters, substeps=4, length on` (the shipped defaults).

| fixture | config | wall-clock | projections | stretch error (lower = better) |
|---|---|---|---|---|
| braced mesh, k=100 | today | 199 ms | 566,784 | 76.45 |
| braced mesh, k=100 | #790 | 792 ms | 2,267,136 | 35.33 |
| pure chain, k=100 | today | 81 ms | 228,096 | 9.85 |
| pure chain, k=100 | #790 | 324 ms | 912,384 | **0.017** |

Both fixtures land at **4.00x** projections and wall-clock — `LENGTH_ECC_CEILING`
/ `LENGTH_ITER_SCALE` were tuned to land near that multiple for a
ceiling-clamped blade, and this confirms it in practice. Shape-holding
improves substantially at both densities (2.2x lower stretch error on the
braced mesh, ~580x on the pure whip, where propagation depth was the whole
problem). **The 4x wall-clock cost at k=100 is real and worth an owner
opinion** — a single 100-node whip swing goes from ~80ms to ~320ms
solver-only (no hit-scan) on this machine; whether that is acceptable inside
a turn, and whether `LENGTH_ECC_CEILING` should sit closer to or further from
4x, is a tuning call this issue surfaces but does not make.
## Open questions / future work

- **Damping for a DRIVEN blade.** `BladeState.damping` exists (#801) but is
  written only for severed particles; a driven chain whips forever within the
  swing duration, because a driver overwrites the damped position anyway. Doing
  it properly means the clock channel (#780), not the particle one.
- **Richer constraint shapes for addons.** `ClampAddon` welds via phantom
  braces, which covers rigidity but nothing else. A "motor" addon that drives
  angular velocity directly, or a "breakaway" that yields past a load, would
  each want a real constraint class rather than a brace.
- **Real swept hit detection.** Sample-boundary proximity misses
  tunneling at high speeds. Not visible at current swing rates; revisit
  if/when angular velocities go up.
- **Inner-class promotion.** When constraint/driver types proliferate
  beyond what fits in a few files, or when external plugins want to
  register types, promote each subclass to its own `class_name` file.

## Reading order

1. `docs/domain/melee-blade-sim.md` (this file)
2. `attack/melee/sim/blade_state.gd` (descriptor)
3. `attack/melee/sim/blade_sim.gd` (solver)
4. `attack/melee/sim/blade_constraint.gd` + `blade_distance_constraint.gd`
5. `attack/melee/sim/blade_driver.gd` + `blade_arc_driver.gd`
6. `attack/melee/sim/blade_hit_scan.gd`
7. `attack/melee/skill_blade.gd` (visual wrapper)
8. `attack/plan/melee_attack_plan.gd` (`resolve()`)
9. `attack/melee/melee_preview.gd` (ghost loop)
