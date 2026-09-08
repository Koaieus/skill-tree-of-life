extends GutTest

## #790 — BladeSim spends its constraint-sweep budget on smaller physics
## timesteps rather than more iterations per timestep, scales that budget by
## blade length (pivot eccentricity, i.e. hop count from the pivot) as well
## as by speed, and samples the trajectory independently of the physics
## rate. See docs/domain/melee-blade-sim.md for the rationale these pin.
##
## test_blade_trajectory_timing.gd is the sibling regression gate: it proves
## sample_dt/sample count are UNCHANGED by this work (its fixture has no
## constraints, so substep/length scaling can't touch it either way).

const DURATION := 1.2
const SPACING := 40.0


## Counts constraint projections without touching blade_distance_constraint.gd
## (not owned by this unit) — wraps it, sharing a counter box across every
## constraint built for one state so a test can read total projections
## performed. Dividing by constraint count converts that into "sweeps"
## (one pass over every constraint), the unit the issue's budget is stated in.
class _CountingConstraint extends BladeDistanceConstraint:
	var _counter: Array

	func _init(a_: int, b_: int, rest_: float, counter: Array) -> void:
		super(a_, b_, rest_)
		_counter = counter

	func project(positions: PackedVector2Array, inv_masses: PackedFloat32Array) -> void:
		_counter[0] += 1
		super.project(positions, inv_masses)


## Straight whip chain from the pivot (index 0) — the whippy extreme, and
## the shape [BladeState.pivot_eccentricity] should read as exactly n - 1
## hops, since every constraint is a chain link with no bracing to shorten
## the path. `counter`, if given, makes every constraint a _CountingConstraint
## sharing that one box.
static func _chain(n: int, counter: Array = []) -> BladeState:
	var pos: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in n:
		pos.append(Vector2(float(i) * SPACING, 0.0))
		radii.append(10.0)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	var state := BladeState.build(pos, 0, edges, radii)
	if not counter.is_empty():
		var counted: Array[BladeConstraint] = []
		for c in state.constraints:
			var dc := c as BladeDistanceConstraint
			counted.append(_CountingConstraint.new(dc.a, dc.b, dc.rest, counter))
		state.constraints = counted
	return state


## One BladeArcDriver on the pivot-adjacent particle — mirrors what
## MeleeAttackPlan actually builds (one driver per pivot-adjacent particle),
## and what bench_blade_sim.gd's own chain fixture drives.
static func _drivers_for(state: BladeState) -> Array[BladeDriver]:
	return [BladeArcDriver.new(1, state.positions[0], SPACING, 0.0, TAU, DURATION)]


## Sum of |current distance - rest length| across every constraint — the
## "how far has this blade stretched away from rigid" metric. Read after a
## sim run so it reflects the FINAL pose, i.e. how well the swing held shape.
static func _total_stretch_error(state: BladeState) -> float:
	var positions := state.positions
	var total := 0.0
	for c in state.constraints:
		var dc := c as BladeDistanceConstraint
		var dist := positions[dc.a].distance_to(positions[dc.b])
		total += absf(dist - dc.rest)
	return total


# ── Sample rate / substep rate decoupling ───────────────────────────────────

func test_substep_count_and_sample_count_are_independently_configurable() -> void:
	var dt := BladeSim.DEFAULT_DT
	var state_one := _chain(6)
	var traj_one := BladeSim.simulate(
			state_one, _drivers_for(state_one), DURATION, dt, 16, 0.0, 1)
	var state_many := _chain(6)
	var traj_many := BladeSim.simulate(
			state_many, _drivers_for(state_many), DURATION, dt, 16, 0.0, 32)
	assert_eq(traj_one.samples.size(), traj_many.samples.size(),
			"raising substeps must not change how many trajectory samples come out")
	assert_eq(traj_one.sample_dt, dt, "sample_dt stays the caller's dt regardless of substeps")
	assert_eq(traj_many.sample_dt, dt, "sample_dt stays the caller's dt regardless of substeps")
	assert_gt(traj_one.samples.size(), 1, "fixture must actually run some sim steps")


# ── Blade-length axis ────────────────────────────────────────────────────────

func test_pivot_eccentricity_is_hop_count_not_distance() -> void:
	# A 6-particle chain: pivot=0, farthest particle is index 5, five hops away.
	var chain := _chain(6)
	assert_eq(chain.pivot_eccentricity(), 5)
	# A short (4-particle) chain sits at/under the baseline the length axis
	# exempts, per the owner's "3-hop stubby blade" example.
	var short_chain := _chain(4)
	assert_eq(short_chain.pivot_eccentricity(), 3)


func test_sweep_budget_rises_with_eccentricity_then_clamps_at_the_ceiling() -> void:
	# velocity_iter_ref = 0.0 disables the (unrelated, already-existing) speed
	# axis, so any budget difference below is attributable to length alone.
	var short_counter: Array = [0]
	var short_state := _chain(BladeSim.LENGTH_BASELINE_HOPS + 1, short_counter)
	BladeSim.simulate(short_state, _drivers_for(short_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS)
	var short_sweeps := float(short_counter[0]) / float(short_state.constraints.size())

	var long_counter: Array = [0]
	var long_state := _chain(BladeSim.LENGTH_ECC_CEILING + 1, long_counter)
	BladeSim.simulate(long_state, _drivers_for(long_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS)
	var long_sweeps := float(long_counter[0]) / float(long_state.constraints.size())

	var beyond_counter: Array = [0]
	var beyond_state := _chain(BladeSim.LENGTH_ECC_CEILING * 3, beyond_counter)
	BladeSim.simulate(beyond_state, _drivers_for(beyond_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS)
	var beyond_sweeps := float(beyond_counter[0]) / float(beyond_state.constraints.size())

	assert_gt(long_sweeps, short_sweeps,
			"a blade past the baseline hop count must get a bigger sweep budget than a short one")
	assert_almost_eq(long_sweeps, beyond_sweeps, 0.5,
			"budget must be clamped at LENGTH_ECC_CEILING — an even longer blade buys nothing more")


func test_short_blade_costs_no_more_than_it_did_before_length_scaling_existed() -> void:
	var state_scaled := _chain(BladeSim.LENGTH_BASELINE_HOPS + 1)
	var state_unscaled := _chain(BladeSim.LENGTH_BASELINE_HOPS + 1)
	var traj_scaled := BladeSim.simulate(
			state_scaled, _drivers_for(state_scaled), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true)
	var traj_unscaled := BladeSim.simulate(
			state_unscaled, _drivers_for(state_unscaled), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, false)
	# A blade at the baseline hop count is exempt from the length axis, so
	# turning length scaling on or off must produce the IDENTICAL trajectory.
	assert_eq(traj_scaled.samples.size(), traj_unscaled.samples.size())
	for k in traj_scaled.samples.size():
		for i in traj_scaled.samples[k].size():
			assert_almost_eq(
					traj_scaled.samples[k][i].distance_to(traj_unscaled.samples[k][i]), 0.0, 0.001,
					"length scaling must be a no-op at/under LENGTH_BASELINE_HOPS")


# ── Substeps-over-iterations, isolated from the length axis ─────────────────

func test_substeps_alone_hold_shape_better_at_equal_or_lower_sweep_cost() -> void:
	# A 55-hop whip — long enough that Gauss-Seidel propagation is the
	# bottleneck (owner's rationale: ~1 constraint per sweep). Length
	# scaling is explicitly OFF on both sides so this isolates exactly the
	# substep-vs-iteration claim (Macklin et al. 2019): same total sweep
	# budget, spent as smaller steps instead of more passes per step.
	var n := 56
	var old_counter: Array = [0]
	var old_state := _chain(n, old_counter)
	BladeSim.simulate(old_state, _drivers_for(old_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, 1, false)
	var old_sweeps: int = int(old_counter[0]) / old_state.constraints.size()
	var old_error := _total_stretch_error(old_state)

	var new_counter: Array = [0]
	var new_state := _chain(n, new_counter)
	BladeSim.simulate(new_state, _drivers_for(new_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, false)
	var new_sweeps: int = int(new_counter[0]) / new_state.constraints.size()
	var new_error := _total_stretch_error(new_state)

	assert_lte(new_sweeps, old_sweeps,
			"substepping must not cost MORE total sweeps than today for the same base_iterations")
	assert_lt(new_error, old_error,
			"substepping (smaller dt) must hold a long whip's shape better than the old flat-iteration config, at equal-or-lower sweep cost")
