# Melee blade — PBD physics & deterministic preview

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
| Cheap (100 sub-steps in µs) | Verlet integration + constraint projection, all `PackedVector2Array` |
| Stable at any timestep | No mass/force inversion, no force explosion |
| Composable constraints | Distance, clamp, future custom — all behind one `project(positions, inv_masses)` interface |
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
│   ├── blade_clamp_constraint.gd      angular range — for SkillNode addon hook
│   ├── blade_driver.gd           abstract: apply(positions, t)
│   ├── blade_arc_driver.gd       circular sweep around a center
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

attack/plan/melee_attack_plan.gd  resolve() → builds BladeState → BladeSim.simulate
											→ BladeHitScan → AttackOutcome
```

## Data flow

```
				 ┌─ MeleeAttackPlan (UI selection)
				 │   pivot SkillNode + member SkillNodes + induced edges
				 ▼
			BladeState  ◄── pure descriptor (positions, inv_masses, edges, constraints)
				 │
				 ├──► BladeSim.simulate(state, drivers, duration)
				 │         │
				 │         ▼
				 │     BladeTrajectory (samples[step] = PackedVector2Array)
				 │         │
				 │         ├──► BladeHitScan.scan(trajectory, state, targets)
				 │         │         │
				 │         │         ▼
				 │         │     [HitEvent { t, particle/edge, target }]
				 │         │         │
				 │         │         ▼ (resolve only)
				 │         │     AttackOutcome
				 │         │
				 │         └──► SkillBlade.play(trajectory)  ◄── ghost or live
				 │                   │
				 │                   ▼
				 │             BladeNode visuals tween-driven over real time
				 │             hit signal emitted at each HitEvent.t (live only)
				 ▼
			(visuals)
```

## Module contracts

### `BladeState`

The descriptor handed to the sim. Constructed once per `simulate()` call;
mutates in place during stepping.

```gdscript
var positions: PackedVector2Array
var prev_positions: PackedVector2Array    # owned by BladeSim, do not touch
var inv_masses: PackedFloat32Array        # 0.0 = static (pivot)
var radii: PackedFloat32Array             # also used as hit radii
var pivot_index: int
var edges: Array[Vector2i]                # (particle_idx, particle_idx)
var constraints: Array[BladeConstraint]   # projected each iteration
```

Built via `BladeState.build(positions, pivot_idx, edges, radii)`. The
factory seeds one `BladeDistanceConstraint` per edge with `rest =
initial distance`. Callers append additional constraints before
simulating.

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

### `BladeClampConstraint` — extension point for SkillNode addons

A future SkillNode addon ("clamp node") will inject a clamp constraint
when its SkillNode is in the blade: the arm particle's angle around the
pivot is constrained to `[min_angle, max_angle]`. The hook lives at
**BladeState construction** — `MeleeAttackPlan._build_blade_state()`
walks the selected SkillNodes and asks each one for its contributed
constraints. Default contribution: none. Clamp addon overrides to
contribute a `BladeClampConstraint`. Same pattern can carry any future
constraint a SkillNode addon dreams up (motor, spring, breakaway).

The interface is **not yet wired** — `BladeClampConstraint` is a
working stub. The hook on SkillNode lands when the addon system does.

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

### `BladeSim.simulate(state, drivers, duration, dt, base_iterations, velocity_iter_ref)`

Stateless static. Steps `duration / dt` times. Each step:

1. Verlet integrate dynamic particles: `(p, prev) → (p + (p - prev), p)`.
2. Apply each driver at `t = step * dt`.
3. Project constraints `iterations` times.
4. Snapshot positions into trajectory.

**Velocity-scaled iterations.** Stiff constraints can drift when
particles are moving fast — the per-step correction has less time to
converge per unit of motion. Setting `velocity_iter_ref > 0` enables
adaptive iteration count:

```
iterations = base_iterations * (1 + max_particle_speed / velocity_iter_ref)
```

At `max_speed == velocity_iter_ref`, iterations double. At
`max_speed == 0`, base. Tune `velocity_iter_ref` to "the particle speed
above which you start seeing rubbery edges". Pass `0` to disable.

### `BladeTrajectory`

Pure data: `sample_dt: float`, `samples: Array[PackedVector2Array]`.
Indexed by step, each sample is the full particle position array.
`sample(t: float)` linear-interpolates between adjacent step samples
for arbitrary real-time playback.

### `BladeHitScan.scan(trajectory, state, targets) -> Array[HitEvent]`

Pure. `targets` is `Array[[Vector2, float, Object]]` — position,
radius, payload (the engine's `SkillNode` reference). Walks adjacent
trajectory samples; for each particle and edge tests proximity to each
target; per-element-per-target dedup so each blade element hits each
target at most once per swing. Emits time-stamped `HitEvent`s.

The trajectory step is fine enough (default `1/120s`) that point-vs-
segment proximity at each sample boundary is sufficient for hit
detection at game speeds; no full swept-volume continuous collision
needed.

## Engine-side wiring

### `SkillBlade` (visual + playback)

`build_from_skill_nodes(skill_nodes, pivot, induced_edges, owner)`
constructs `BladeState` and spawns BladeNode + BladeEdge visuals at
their initial positions. `simulate(duration)` runs the sim (drivers
auto-built from pivot-adjacent particles). `play(trajectory, hits,
ghostly)` tweens visual positions through the trajectory and emits
`hit` signals at scheduled times.

`BladeNode` and `BladeEdge` are pure `Node2D` visuals now — no
`RigidBody2D`, no `PinJoint2D`, no `Area2D` hitbox. Their positions are
written directly by `SkillBlade.play` each frame. Hit detection is the
deterministic scan, not Godot collision overlap.

### `MeleeAttackPlan.resolve()`

```
selection → BladeState → drivers → BladeSim.simulate → BladeHitScan
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

## Open questions / future work

- **Damping.** Currently Verlet has no velocity damping; chain whips
  forever within the swing duration. For longer sweeps add a `damping`
  parameter on `BladeSim.step` (multiply velocity by `1 - damping * dt`).
- **Clamp angular range semantics.** The stub clamps the arm's angle
  around the pivot — good enough for "this node is a hinge with range".
  More exotic addons (a "motor" that drives angular velocity directly)
  may want richer constraint shapes.
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
