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
#813 added four more entries to that list; the whole of it is under
"The GDScript-backend consequence — retired by #813" below.

##### The defender half crosses as DATA, never as a callback (#813)

`simulate_range_field` is the second C++ entry point: the same stepping loop
with a `BladeSwingClock` and/or a `BladeObstacleField` riding along. There is
still **one** loop — `run_range` takes a `FieldCtx *` that is null for a
fieldless swing — because a second integrator would be two definitions of the
thing the bit-exactness contract is about.

The issue offered an alternative: a generic per-iteration constraint callback
across the boundary. Rejected on cost. `BladeObstacleField.project()` runs once
per constraint-projection *iteration* — the innermost loop, millions of
crossings a swing — so a callback there eats most of what the backend buys. So
the state crosses instead: `native_inputs()` for the immutable half (zones,
live edges, driven particles, `prepare()`'s incidence flattened to a CSR, and
`CONTACT_SLOP` / `CONTACT_HYSTERESIS` / `SHATTER_DISTANCE` / `EDGE_RADIUS`
**passed rather than restated in C++**, for the same one-definition reason
`length_factor` is precomputed), `native_state()` in, and `clock_state` /
`field_state` / `clock_history` / `field_history` back. `native_state()` /
`bank_from_native()` / `apply_native_state()` on both classes are `capture()` /
`restore()` in Dictionary clothing — change those, and the C++ `FieldCtx`,
together.

One shape decision worth keeping: the zone set crosses as
`BladeDefenderZones`' four plain parallel arrays under their own keys, not as a
solver-private blob. `BladeHitScan` consumes the same disc / rim-trimmed-capsule
geometry and is the last piece that cannot leave the main thread, so nothing
here forecloses building it on the same input.

Four transliteration traps this half has and the plain solver does not:

- **`_strain` is float32 storage with double arithmetic.** The read widens, the
  add and the `maxf` happen in double, the **store narrows**, and
  `< SHATTER_DISTANCE` then compares the narrowed value. Keeping a double
  accumulator "for accuracy" is a different solver. `_edge_residual`'s values
  are the opposite — plain GDScript floats, i.e. doubles.
- **`_contact_particles` / `_contact_edges` / `_contact_normals` iterate in
  INSERTION order, and that order is a summation order.** Several particles can
  bank onto one edge in a substep, and a particle pushed by zone 3 and then
  zone 7 keeps zone 7's *value* at zone 3's *insertion position*. A key-sorted
  map is not equivalent; the C++ uses godot `Dictionary`s for exactly this, and
  the Variant cost is per *contact*, not per iteration.
  `test_a_multi_zone_cluster_matches_bit_for_bit` is what pins it — every
  single-zone case agrees no matter how the walk is ordered.
- **Two sqrt precisions inside one function.** `delta.length()` is the engine's
  float32 `Vector2::length()`; `var d := sqrt(d2)` is GDScript's double `sqrt`
  of a float32-valued double. Call the godot-cpp `Vector2` methods
  (`length`, `distance_squared_to`, `dot`), never hand-expand either.
- **The pushout mutates `positions` in place mid-loop.** Zone z+1 sees zone z's
  correction, and a zone's capsule pass sees its own disc pushouts. Batching the
  pushes and applying them at the end is a different solver.

Measured, `bench_blade_sim.gd`'s `#813` row (k=100, one wall + one plate placed
on the blade's own trajectory, solver only): braced mesh 1134.6 ms GDScript vs
**49.5 ms** native; whip 723.0 ms vs **30.8 ms**. Both rows print the banked
`drag` and the peak `strain`, because a zone placed at the rest span is one a
whipped k=100 blade never reaches — that row times the broad-phase reject and
still shows a plausible speedup.

**`BladeHitScan` is deliberately NOT ported**, and this therefore does not
address #785. It calls `intersect_shape()` against the physics server, which is
neither freely thread-safe nor a numeric loop. Solver cost is `samples x
substeps x constraints`; hit-scan cost is `samples x edges`. The two add; only
the first one got cheap.

**Building it:** `mise run native:build` (append `-- template_release` for
exports, and a platform after that -- `-- template_release windows` -- to
cross-compile, on the llvm-mingw toolchain `mise.toml` pins). godot-cpp is a submodule at
`native/godot-cpp`, so a fresh clone needs a recursive submodule init first.
Binaries are **not** committed -- `native/bin/` is gitignored.

##### `build_profile` is a SCons Variable, not an Import

Passing it in `SConscript("godot-cpp/SConstruct", {...})` is **silently
ignored** — godot-cpp's SConstruct only `Import()`s `api_version`,
`binding_hooks` and `customs` — and you get all ~1000 engine classes generated
and compiled (2072 files, ~10 min) instead of 28 (~1 min).

**How to apply:** `ARGUMENTS.setdefault("build_profile", "build_profile.json")`
before the `SConscript` call. The profile must list the classes **godot-cpp's
own `src/`** includes (`Engine`, `OS`, `SceneTree`, `EditorPlugin`) as well as
yours; base classes come along automatically, siblings do not. Omitting one
fails as a missing `godot_cpp/classes/*.hpp`, which reads like nothing to do
with the blade.

##### `git worktree remove` now fails on any worktree that inited the submodule

Since `native/godot-cpp` exists, a worktree where someone ran
`git submodule update --init` cannot be torn down the normal way — git refuses
with *"working trees containing submodules cannot be moved or removed"*, and
`--force` does not help. This bites teardown, not setup, so it surfaces at the
end of a unit when the branch is already merged.

**How to apply:** confirm the branch is merged first (`git -C <repo> log
--oneline master..<branch>` prints nothing, or you have a diffstat receipt that
its content landed rebased), then delete the worktree directory and let git
notice: `rm -rf <worktree-dir> && git -C <repo> worktree prune && git -C <repo>
branch -d <branch>`. Verify the branch is merged **before** the delete — a
worktree directory is unrecoverable, and unstaged work inside it doubly so.

##### mise's `pipx:` backend needs `pipx` listed too

`"pipx:scons"` alone makes **every** mise task abort with "pipx is required but
was not found", not just the build. List `pipx = "latest"` in `[tools]` beside
it.


A missing binary is a supported state at *runtime*, but not at *export*: the
exporter hard-fails on a `.gdextension` key whose file is absent, so
`mise run build` refuses up front for every platform it is asked to export
(#806, [exporting.md](exporting.md)). And the library ships *beside* the
executable rather than inside the pck, so a build handed over without it runs
on the GDScript solver with nothing to say so.

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
severs an edge is #781's bunker break, a rigid blade shattering against an
obstacle. `LiveGate._sever_edge`, `BladeState.removed_edges` and `remove_edge()`
were kept as that seam through #785/#799/#801 with no production caller;
`BladeObstacleField` (see "Bunker deflection (#781)" below) is now its first
and, per ADR 0005, only caller.
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
clock only when the swing has a defender field at all (since #811 the clock and
the field travel together); otherwise `clock` is null, the driver runs its original expression, and the native backend still
takes the swing. Even an *attached* clock is inert until first contact — the
driver keeps reading `t / duration` verbatim, so a swing with a fortified node in
its field that it never touches is **bit-identical** to one with no field at all.
That exactness is deliberate: accumulating `f` from t=0 would drift in the last
bits and quietly make the mere presence of a wall change a swing that never met
it. A warping clock used to be the **one** thing that still forced the GDScript
backend, because it accumulates `_f` in float after first contact by design.
#813 transliterated exactly that: `clock_tick` advances the accumulator per
substep inside the C++ loop, and the six fields `BladeSwingClock.Bank` carries
cross the boundary and come back advanced. Per-particle damping and a continued
Verlet history (`step_offset > 0`) were on that list before it; #803 taught the
native loop both. A severed, dragged, defended swing now runs native end to
end — see "Two backends, one meaning" for what is left on the decline list.

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

### One defender field, built by the physics engine (#811, ADR 0014)

There is **one** contact test in the melee solver and the physics engine finds
what it tests against. Read
**[ADR 0014](../adr/0014-one-physics-built-defender-field.md)** for the decision
and its dead alternatives; this section is what the code does.

`BladeDefenderZones.query()` issues a single `intersect_shape` against the two
collision layer bits a `SkillNode` toggles off its own `swing_drag` /
`deflection` local values (#810: bit 2 `swing_drag`, bit 3 `deflection`; bit 1,
Godot's default, is untouched so `intersect_point` mouse picking keeps working).
The result is an **immutable** parallel-array table — centres, radii, drag
magnitudes, deflect flags, source nodes. `BladeObstacleField` wraps one and owns
every mutable accumulator; `BladeSwingClock` owns the banked drag.

**Two zone kinds, asymmetric on purpose.** `deflection` is a BOOL stat (presence
only); `swing_drag` is a magnitude. A plate is pushed out of, meters strain, arms
a break and can stall the grip. A wall is **sensed and nothing more** —
`project()` skips it in the pushout and banks its drag on the clock instead.
A wall never enters the field's `_near` set, which is not a neutral "was sensed"
set: it gates the strain accumulator, so a wall in it could shatter a blade,
which is a plate-only effect (ADR 0005, #781). **A node carrying both stats is
ONE zone of both kinds**, latched once — the drag latch keys on the zone index,
so a doubled zone would double its wall.

**Where the models used to disagree, they cannot now.** Before #811,
`BladeSwingClock.sense()` re-implemented the geometry analytically and its own
docstring admitted that at the margin a node could drag without producing a hit
event, or produce one without having dragged. That whole class of divergence is
gone: `BladeHitScan` is still the sole authority for hit events, damage and pops,
but it and the field now agree on *who is in range* by construction, because one
query answers it.

**Cadence.** The wall test runs inside `project()`, i.e. once per solver
**substep** rather than #780's once per trajectory sample — four times finer.
The reach is unchanged (`zone radius + particle radius` for a disc, `zone radius
+ EDGE_RADIUS` for a capsule, no slop, no hysteresis), so only onset moved, and
only earlier-or-equal. The `_f` seed a first contact takes reads `_last_t`, which
`BladeSim._step` already advances per substep — that is what makes the finer
cadence safe.

### The query radius is generous on purpose — never re-tighten it

`MeleeAttackPlan._blade_reach` bounded both deleted zone walks by the blade's
**rest** reach. Swinging a floppy blade straightens it: a 5-node W blade whose
rest reach is 432 px was measured whipping to 714.6 px, so every fortified or
bunkered node in that 65%-wide annulus silently failed to defend while
`BladeHitScan` — sensing off the live pose — damaged it normally (#808).
`test/unit/attack/test_blade_whip_reach.gd` is that fixture, and it derives the
measurement rather than pasting it.

What replaces it is `MeleeAttackPlan.whip_bound()`: BFS over the blade's own
induced subgraph (at most `blade_size + 1` vertices) summing rest edge lengths
from the pivot — 721.1 px for that W, within 1% of the measured whip — times
`BladeDefenderZones.STRETCH_MARGIN` for XPBD's soft constraints, plus the widest
blade disc and an edge half-thickness.

**With the predicate on the collision mask, the radius is no longer what makes
the work cheap**, so it is a pure trade with graceful degradation in one
direction only: too large costs a few float compares per substep, too small
silently drops a defender. A severed fragment can coast outside even this
bound — "coasting blade parts can go anywhere", owner, 2026-09-09 — and is
covered iff the radius happens to cover it. That is accepted, not a bound anyone
relies on.

**A generous field must be broad-phased.** On `first_level` (114 `swing_drag`
carriers, 89 `deflection`, 18 both) a size-4 blade pulls dozens of zones in, and
`project()` runs per solver iteration. Walked naively that cost +29% on a
prediction. `project()` therefore recomputes the blade's AABB from the current
pose each iteration and rejects any zone outside it grown by its own radius —
exact, needing no safety margin, and it brings the cost back to noise. Keep that
reject if you touch `project()`.

### Building it once per pivot, and why that is safe

`MeleeAttackPlan.build_blade_state()` normally queries for itself. `AiBladeRollout`
does not: it builds every proposal's state with an **empty** zone set first (which
is how it gets the whip bound), takes the widest bound per pivot, issues **one**
query per pivot, and hands the same immutable instance to all of that pivot's
proposals. Each proposal still gets its own `BladeObstacleField` wrapper and its
own `BladeSwingClock`, so the ≤32 concurrent `WorkerThreadPool` sims share only
data nobody writes. 12682 us vs 18447 us at 192 proposals.

**The coarse tier gained Fortification drag here**, which it never had — it built
no clock at all, so a wall that bogs the real swing down ranked as empty ground.

**The blade side is excluded by RID**, via `collect_target_excludes()` — the same
list `BladeHitScan` gets. The old `_is_blade_side` predicate was a second
implementation of that membership and is deleted; a blade bogging down on its own
wall would have been the symptom of the two drifting apart.

**The native backend stays off for any swing that has a field — until #813.**
`BladeSim.simulate_range` gated native on `clock == null and obstacles == null`,
and one merged field meant most swings on a shipped map hit that gate. Accepted
under #811 as a deliberate trade, and closed by #813, which transliterated the
field's pushout and its strain metering rather than exposing a per-iteration
constraint callback: the callback would fire in the solver's innermost loop and
cost more than the backend saves. Measured k=100, solver only, one wall and one
plate on the blade's own trajectory: 1134.6 ms GDScript vs 49.5 ms native on a
braced mesh, 723.0 ms vs 30.8 ms on a whip (`bench_blade_sim.gd`'s `#813` row).

**ADR 0014's Consequences predicted this would stand** — *"the native backend is
off for any swing that HAS a field"* — and #813 resolved it. The ADR is not
edited (`.claude/rules/adr.md`: superseded, never rewritten), so a reader
following that trail should arrive here for the correction.

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

### A defender the space hasn't seen yet (#814)

`intersect_shape` answers against the physics server's broadphase, and a
collider's *new state* — a just-added `Area2D`, or an existing one that moved or
flipped a collision-layer bit — only reaches that broadphase on the next physics
tick, not the instant the script call returns. Measured directly while building
this guard: toggling `swing_drag` on a `SkillNode` already resting in the space
was picked up immediately (layer bits are read per-candidate at query time, not
part of broadphase indexing), but **repositioning** that same node into range in
the same frame was not — `intersect_shape` still returned the pre-move miss.
`.claude/rules/melee-fixtures.md`'s "two extra teeth" is this same gap from the
fixture side (`test_blade_whip_reach.gd`'s addon-then-`physics_frame` dance
exists because of it); this is the production side, which had no guard at all
before #814.

**The fix is a debug-only cross-check, not a production-side correction.**
`BladeDefenderZones.query()` — the only call site, gated `OS.is_debug_build()` —
re-walks `graph.get_skill_nodes()` for anything carrying `swing_drag > 0` or
`deflection` within the query's own `whip_bound` disc, diffs it against what
`intersect_shape` actually returned, and `push_warning`s the node's name for
anything the physics query silently dropped. The gate matters: that walk is
exactly the O(map) cost ADR 0014 deleted from the release path (36 us vs. 1744 +
1701 us), so it must never run outside a debug build.

**Deliberately warn-only — no forced sync, no graph-walk fallback in
production.** Two ways to go further were considered and rejected:

- **Force the node into the space** (e.g. `await get_tree().physics_frame`
  before querying) would make `_resolve_swing` yield. `.claude/rules/
  attack-timeline.md` requires the resolve complete synchronously before the
  mutation loop replays the `AttackRecord` — turning that into a structural
  change far larger than this issue, to close a window the turn-based cadence
  (addons attach at allocation/procgen time, frames before any swing) makes
  narrow in practice.
- **Fall back to a graph walk when the query looks incomplete** would
  re-introduce, in production, the second contact model ADR 0014 spent #811
  deleting — one week old at the time of #814, and undoing its whole point to
  guard a window this narrow.

So production stays exactly as ADR 0014 left it: one physics query, silent
in release, loud in debug. If this ever needs revisiting, it is a new decision,
not a reopening of ADR 0014 — that ADR is unedited by #814.

## Bunker deflection (#781)

A node with `deflection > 0` — base 0, only `BunkerAddon` authors it — is a
solid obstacle. `BladeObstacleField` (`attack/melee/sim/blade_obstacle_field.gd`)
pushes every vertex disc and every rim-trimmed edge capsule back out of the
plate's disc, every solver iteration, **after** the distance constraints —
`BladeSim._step` runs it last in the pass so the pass ends outside every plate.
Most blades flop around a bunker and nothing happens; a blade too rigid to yield
gets driven a fixed distance into the plate and then **breaks** — never the
vertex that touched it (ADR 0005: a spike destroys matter, a bunker destroys
structure). This is `attack/plan/melee_attack_plan.gd`'s
`build_defender_zones` + `attach_defender_field` hanging a field off
`BladeState.obstacles` (one query, both zone kinds — see "One defender field"
above), and the resolve loop's `consume_break` handling inside `resolve_against`
(below) is what actually severs it.

### The metric is the DRIVER's residual, never the contact point or the constraint residual

The issue's own first formulation measured the *contacting vertex's* own
unresolved pushout (`required - |final - pre-projection|`), and ADR 0005 named
the PBD *distance-constraint residual* as the strain. Both are wrong for the
same reason: a driven particle is not pinned during the projection pass — only
the pivot carries `inv_mass 0` — so a rigid body resolves either metric
**completely**, by rotating back **as a whole**, and both read "fully resolved"
in exactly the case that should shatter.

Measured 2026-09-09 on hand-built blades (`test/unit/attack/test_bunker_deflect.gd`),
default solver config — `BladeSim.DEFAULT_ITERATIONS` 16 over `DEFAULT_SUBSTEPS`
4, 60px node spacing, 24px vertex radius, 32px plate:

| blade | driver residual (peak, px) |
|---|---|
| bare spine, 4 nodes | 0.74 |
| bare spine, 8 nodes | 0.42 |
| bare spine, 8 nodes, double sweep speed | 1.68 |
| clamped spine (welded joints) | 16.31 — breaks its tip edge |
| truss (induced) | 40.18 — breaks edge 10, the tip rung |

At 32 iterations the same five rows read 0.84 / — / — / 37.94 / 71.62: more
sweeps make a floppy blade resolve the pushout *more* completely (its number
falls toward 0) and leave a rigid one exactly as stalled, so raising fidelity
**sharpens the separation, never shifts the verdict** — this is what
`SHATTER_DISTANCE`'s doc comment means by "bounded, not eliminated" (see
"#790: substepped + length-scaled" above for the fidelity axis itself).
**The issue body's contact-point metric and ADR 0005's distance-constraint
residual both read exactly 0.00 on every rigid case measured** — the clamped
spine and the truss alike — while the driver residual is the only one of the
three that separates floppy (under 2px) from rigid (16–72px).

The metric in one sentence: each substep, the arc drivers place the grip
particles where the swing *should* be, and the projection pass then moves them
to where the blade *can* be. For a floppy blade a bunker contact is absorbed by
a fold — the grip keeps up with its own driver and the unresolved advance is
~0. For a rigid blade no fold exists — the whole body pushes back against the
driver, so the grip ends the substep roughly where it started, and the
unresolved advance is close to the full `speed * dt`. Summed over a contact,
clamped at `>= 0` (a step where the blade catches up *subtracts*, which is the
bleed that washes out a transient hold — acceptance item 12 in the issue),
crossing `SHATTER_DISTANCE` arms a break. No rigidity computation is needed —
whether the blade yielded *is* the rigidity measurement, per the issue's "do
not add a hop-count or rigidity rule" decision.

### What breaks, and how the edge is chosen

ADR 0005: contact and failure need not coincide. The contact is usually at a
vertex — discs stick out past the capsules, which are trimmed to each
endpoint's rim — so the vertex survives and the force goes into its incident
edges. Each substep `BladeObstacleField.end_substep` banks the unresolved drive
onto every *live* edge incident to a pushed vertex, in proportion to
`|normal . edge_direction|` — how squarely the plate's push runs along it — and
onto any edge directly touched by its own capsule contact, at full share. Once
a zone's accumulated strain crosses `SHATTER_DISTANCE` (8px), the most-strained
live edge banked against that zone breaks, ties going to the lowest index
(`_pick_edge`). On a truss this is the outermost triangulated rung, not
necessarily the edge nearest the contact vertex — whichever edge actually
carried the load.

### The grip: a hard stall, not a break

A contact on a *driven* particle — a pivot neighbour, per `BladeArcDriver` —
calls `BladeSwingClock.stall()` instead of accumulating strain: the clock
freezes (`warp()` returns exactly 0 from then on, still monotonic — `_f` gains
nothing, never loses it), the grip sits on the plate, nothing pops or breaks,
and everything outboard keeps simulating on its own momentum. Owner,
2026-09-07: *"hard stall works and is less punishing than a shatter; remainder
of blade parts continue simulating and can flail and whip."* This is what
dissolves the exploit the owner named — *"picking handle directly next to
enemy bunker so driven handle guarantees to clip the bunker"* — because doing
so stalls your own swing on the first substep and sweeps almost nothing.
Self-punishing, no exemption, no third mechanic.

### Sim state, rewind, and where the sever actually lands

`BladeObstacleField` is sim state, exactly like `BladeSwingClock`: per-zone
strain, per-zone edge-load banks, the driven-particle history and the pending
break are captured/restored by its own `Bank` class, and it keeps a chunk-local
`history` of those banks — one per sample, appended by `BladeSim.simulate_range`
right where `BladeSwingClock.history` and `prev_samples` are (#803). A break is
never applied directly — `end_substep` only *arms* a `BladeObstacleField.Break`
(edge index, the GLOBAL step it armed on, the defender). The resolve loop's
per-sample walk checks `obstacles.has_break_at(step)` exactly alongside a pop
(`gate.result.pops.size()` changing): either one stops the walk and rewinds to
the severance sample by *reading* it — `chunk.samples[local]`,
`chunk.prev_samples[local]`, `clock.history[local]`, `obstacles.history[local]`
— with nothing re-run. The field banks once per sample, **after** that sample's
substeps, so the bank at `local` already holds the break armed; the loop then
calls `obstacles.consume_break()` and severs through
`BladePopResolver.LiveGate._sever_edge` — the identical call a spike pop
takes, so the identical `_disintegrate_unreachable` cascade fires and every
`edge_idx`/`particle_idx` stability invariant from #785/#799/#801 is
untouched. `BladeObstacleField` itself never mutates `state.constraints` or
`state.edges`; an optimistic bake stays a pure function the loop can rewind.
Self-limiting by construction, same as any severance: once the edge is gone
that region is floppy, so the next contact yields, and the blade flows past —
one break, then through.

### The zero-bunker structural guard

`attach_defender_field` hangs a field off `BladeState.obstacles` only when the
defender query came back with something — since #811 that means a wall *or* a
plate; with neither, `obstacles` stays null. No field means no accumulator is ever allocated and no pushout
ever runs — the strain metric is never "did this vertex move?" in general,
only ever "how much of *this bunker's* requested pushout went unmet," so a map
with zero bunkers cannot produce a break by construction, at any blade size or
speed. This is the owner's false-positive concern, 2026-09-08, answered
structurally rather than by tuning: *"a false positive would be devastating…
a false negative is basically wallhacks like clipping through solids."*

### The penetration budget

`SHATTER_DISTANCE` (8px) doubles as the visual penetration budget. Because the
pushout runs every solver iteration regardless of accumulated strain, a vertex
can never rest deeper than `CONTACT_SLOP` (1px) plus one substep's travel —
measured max observed penetration across the classification tests is 1.00px,
i.e. exactly the slop. `CONTACT_SLOP` is not zero on purpose: `BladeHitScan`
has to *see* the overlap for the ordinary mitigated hit to register (two
exactly-tangent circles are not a reliable physics-query overlap), and it also
keeps a resting contact from jittering. `CONTACT_HYSTERESIS` (4px) keeps a
contact "ongoing" across the jitter of entering and leaving the slop band every
substep, so strain doesn't spuriously reset mid-contact — only once nothing is
within the band does a zone's accumulator reset. Edge capsules get no slop:
an edge deals no damage, so nothing needs to see it touch.

### The hit still lands — this mechanism doesn't gate it

The mitigated hit the issue asks for ("still lands the hit [bunker reduces it
anyway]") is not something this mechanism produces — it is the ordinary
`BladeHitScan` contact between the vertex disc and the bunker's collision
shape, already running `Mitigation.compute` against the bunker's `armor` /
`min_damage_taken` before this issue existed. `BladeObstacleField` adds the
deflection and the break on top; it never suppresses or replaces that hit.

### Where you tune it: the melee sandbox tab

Threshold tuning is deliberately hand-driven, per the owner (*"Opt 1. The
tuning will in part need a test and in part an extension to the melee sandbox
tab"*), and the two halves are `test/unit/attack/test_bunker_deflect.gd` (which
pins the CLASSIFICATION — floppy yields, braced breaks — never the constant)
and three controls on `addons/melee_sandbox/melee_sandbox_panel.tscn`:

| Control | What it does |
|---|---|
| **Bunker paint** | While on, a left-click adds/strips a real `BunkerAddon` on the clicked node instead of selecting it. Paint the plates, then swing at them. |
| **Rigidity** | `Floppy` / `Braced` — strips or welds a `ClampAddon` onto every node the wielder owns, so one control moves the whole board between the ends of the range without hand-clicking a dozen nodes. |
| **strain readout** | Worst per-zone strain on the *ghost's* live field against `SHATTER_DISTANCE`, plus `GRIP STALLED` when a driven contact has frozen the swing clock. It reads the live `BladeObstacleField` off `MeleePreview.current_blade().state.obstacles` and the clock off `MeleePreview.last_clock` — never a mirror, so "no plate in reach" reports the structural zero above rather than printing `0.0` as though it had measured something. |

**Do not tune against AI-built blades** (#771): they sit at the floppy end and
will never trigger the break, so they report nothing about it.

### No pop budget — `node_health` IS the budget

Unlike `SpikeRingAddon`'s `spikes` pool (#778), a break costs the bunker
nothing beyond what it already pays every hit. Owner, 2026-09-08: *"Plate
integrity (or we would call it `tegridy` of course) is a great idea but i
think we could at best hint at it in a comment while we pick option 2. Bunker
nodes still take damage! Although likely less than usual they are not
immortal. Spikes are offensively useful so we limit their defensive use."*
Every contact still lands a mitigated hit (above), so a bunker that keeps
stopping blades chips its own `node_health` every time; `armor` /
`min_damage_taken` only slow that, never stop it. `BladeObstacleField`'s class
doc *hints*, rather than builds, a dedicated `plate_integrity` pool as the
coherent next step if HP ever proves too coarse a meter — a comment, not a
stat, not a def, not plumbing.

### The GDScript-backend consequence — retired by #813

This section used to say the native backend ran only when
`clock == null and obstacles == null and step_offset == 0 and damping.is_empty()`.
**All four conjuncts are gone:** #803 taught the C++ loop a continued Verlet
history and per-particle damping, and #813 taught it the swing clock and the
defender field. A swing with a bunker in reach now takes the native path like
any other.

What is left is a decline list, not a gate — every entry falls back to GDScript
rather than approximating, and each is a thing the transliteration deliberately
does not cover:

- a constraint or driver outside the subset (exact `get_script()`, so a
  subclass overriding `project()` or `apply()` can never be silently ignored) —
  including a `BladeArcDriver` with a custom ease, whose per-step Callable is
  the very cost the backend removes;
- a `BladeObstacleField` **subclass**, for the same reason;
- `field.trace` on: the diagnostic rows the classification test and the melee
  sandbox read are not transliterated;
- a `radii` array that does not parallel `positions` (the capsule pass indexes
  it unguarded on both sides);
- a binary that predates #813, via `BladeSim._native_field`. That is a *second*
  capability flag rather than a stricter `_acquire_native` on purpose: a `.so`
  built between #803 and #813 must keep its plain-swing native path, not lose
  it.

### The ghost jams, and does not break — superseded by #782

Until #782 `MeleePreview`'s loop built its own fresh `BladeObstacleField` and
`BladeSwingClock` per ghost cycle and ran its own `SkillBlade.simulate`. It
therefore **jammed** on a plate the way the committed swing would, but never
*broke* one, because the break is decided inside the resolve loop the ghost
never ran. That was the honest promise available at the time.

It is no longer what happens: the ghost now replays a real resolve, so it shows
the break. See "The preview is a real resolve, replayed (#782)" below.

### Known residue: a second break by the same vertex against the same bunker lands no second hit

`BladeHitScan`'s counting rule is per-element-per-collider dedup across the
*whole sweep*, on first contact ("Edge collision (#785)" above) — a vertex
that has already produced a hit event against a given collider does not
produce a second one against the same collider, however many more times they
touch. If a vertex's incident edge breaks against a bunker, and that same
vertex (now less constrained) drifts back into the *same* bunker's disc later
in the same swing, `BladeObstacleField` can still accumulate strain and arm a
second edge break there — but the mitigated hit that "still lands" alongside a
break does not repeat, because the vertex/bunker pair already emitted its one
event. The break is real; the damage from the second contact is not.

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
* **#781's bunker break** produces one through the identical call
  (`BladeObstacleField`'s pending break is severed via
  `BladePopResolver.LiveGate._sever_edge`, see "Bunker deflection" below), and
  needed no continuation code at all.

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
## The preview is a real resolve, replayed (#782)

**The ghost is not a lookalike of the swing. It is the swing.**

`MeleePreview` used to simulate: one `SkillBlade.simulate` per ghost cycle,
forever, with a fresh clock and a fresh obstacle field each time. What it could
show was therefore limited to what a bare sim produces — an arc, dragged and
stalled — and nothing a *defender* does. #772 established why that is not a
cosmetic gap:

> blade contact is *"complex emergent movement resulting from the XPBD sim"* —
> kinks, lag, tail whip — so **no rule, tooltip or heuristic can tell a player
> what will hit**.

You cannot teach a rule for chaotic output. You can only show the outcome of
*this specific swing*. And the AI already had exactly that: since #498 step 3
`AiCombatScorer` runs the pop gate against a shadow `CombatWorld`. The AI could
see what the player could not.

So the preview runs the same thing. Once per selection change,
`MeleeAttackPlan.refresh_prediction()` resolves the current selection against a
throwaway `CombatWorld.shadow()` and caches the result; the ghost loop replays
that result's `BladeTrajectory` and hands the blade its `BladePopResolver.Result`
as `pop_result`. There is **no second predictor** — see the repo rule against
parallel mirrors. `_resolve_swing(world) -> SwingResult` is the one
implementation; `resolve_against` is that call plus publishing onto the
`last_*` fields, and the preview is that call without the publishing.

### Replay, not re-simulation — and #801 is why

A per-cycle re-simulation could not reproduce the resolved arc even in
principle. Since #801 the resolve **re-bakes from each severance sample**: a
vertex that dies mid-swing is frozen, its constraints and driver dropped, and
the remaining chunk re-solved from that pose. A plain `simulate()` over an
intact blade takes a different path from that moment on. So a ghost that
simulated would diverge from the committed swing exactly when the interesting
thing happened.

Replaying the resolved trajectory makes them equal by construction — drag,
stall, severance and all — and costs nothing per cycle, which is a straight
improvement on the sim it replaced.

A consequence worth stating: the front-loaded warning that "a clock banks what
it has touched, so the preview must build a fresh one per cycle" is not broken
but **dissolved**. There is no per-cycle clock left to bank anything. The
prediction's own clock and obstacle field, at their end state, are what the
melee sandbox's stall/strain readout now reads.

### What it shows, and when

- **The vertex that dies** goes de-lit **at its pop time**, not pre-greyed:
  `SkillBlade._apply_playback_frame` already asks `pop_result.is_dead(i, t)` per
  frame. The player watches the spike take it, which is the informative read.
- **The edge that parts** likewise, via `pop_result.severed_at`.
- **The node that does it** is marked `HighlightRole.PREDICTED_THREAT`, read off
  `MeleeAttackPlan.get_node_role`. One role covers spikes and bunkers alike,
  because `LiveGate._sever_edge` mints a `Pop` with a `defender` exactly as
  `_kill` does — matter and structure fail differently but are reported the same
  way.
- **Fortification drag is shown by the arc alone.** A drag zone carries no
  `Pop`, so no node is marked for it. That is the deliberate answer to the
  "two sensing models" seam above: drag sensing is analytic and `BladeHitScan`
  is the physics-server authority, so a node can drag the swing without minting
  a hit event. Marking a node for drag would surface that disagreement as a
  per-node claim the scan may not honour. The arc, which is the thing drag
  actually changes, carries no such ambiguity.
- **Spacing luck stays visible.** Edges have collision since #785 but vertices
  and edges are still discrete, and #772 rejected making spikes strictly
  stronger to remove the thread-through. The preview does not remove the luck —
  it shows you which side of it this selection landed on.

### The cache: pushed, never lazy

`MagicAttackPlan` rebuilds its preview lazily, inside `get_node_role`. Melee
must not: a melee resolve is a ~70-sample physics scan (9-16 ms on the shipped
800-node level — `test/perf/bench_melee_prediction_cost.gd`), and
`get_node_role` runs once per node per overlay repaint. Worse, a committed
swing's forced-dealloc cascade emits `state_changed` per step, so a
repaint-driven rebuild would resolve a half-dead plan repeatedly, mid-swing.

So the refresh is **pushed** by the one surface that wants it —
`MeleePreview._refresh`, which already gates on `_live_swing` and `is_valid()`.
`get_node_role` only ever reads. Every site that emits `state_changed` goes
through `_notify_selection_changed`, so "the state changed" and "the prediction
is stale" cannot drift apart. A machine with no preview mounted (a headless
peer, an AI turn) never predicts and pays nothing.

### It is a prediction, not an authority

Under host-authoritative sync the host resolves and every peer replays the
`AttackRecord`. A client's preview is a **local** resolve and may in principle
differ from the host's — `blade_arc_driver.gd`'s #547 note warns *"don't start
relying on it to agree across platforms"*, and #779/#781 made particle floats
gameplay-relevant for the first time. A second, smaller source of the same
thing: the preview runs on the unstamped (0) crit stream while the committed
swing stamps a fresh one, so a crit-driven kill that cascades can change a later
defender's board and part the two.

Both are **accepted mispredicts**. The rule they must never break is the one in
`.claude/rules/multiplayer-sync.md`: a peer *receives* a landing or *reproduces*
it. Nothing here re-decides one.

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
7. `attack/melee/sim/blade_swing_clock.gd` (Fortification drag, #780)
8. `attack/melee/sim/blade_obstacle_field.gd` (Bunker deflection, #781)
9. `attack/melee/skill_blade.gd` (visual wrapper)
10. `attack/melee/sim/blade_defender_zones.gd` (the one physics query, #811)
11. `attack/plan/melee_attack_plan.gd` (`resolve()`, `build_defender_zones`, `whip_bound`)
12. `attack/melee/melee_preview.gd` (ghost loop, #782 prediction replay)
