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


## Straight whip chain from the pivot (index 0) — the whippy extreme, and
## the shape [BladeState.pivot_eccentricity] should read as exactly n - 1
## hops, since every constraint is a chain link with no bracing to shorten
## the path.
static func _chain(n: int) -> BladeState:
	var pos: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in n:
		pos.append(Vector2(float(i) * SPACING, 0.0))
		radii.append(10.0)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	return BladeState.build(pos, 0, edges, radii)


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
	# The length axis is one multiplier on the sweep budget, `_length_factor`,
	# computed GDScript-side from the pivot eccentricity and handed to the
	# native solver as a number (#790 pin 3, #798). Until #847 this test
	# counted the solver's constraint projections through a counting subclass;
	# the native solver refuses subclasses, so the pin is on the factor itself,
	# read off the same hop counts the old fixtures had.
	var short_ecc := _chain(BladeSim.LENGTH_BASELINE_HOPS + 1).pivot_eccentricity()
	var long_ecc := _chain(BladeSim.LENGTH_ECC_CEILING + 1).pivot_eccentricity()
	var beyond_ecc := _chain(BladeSim.LENGTH_ECC_CEILING * 3).pivot_eccentricity()
	assert_eq(BladeSim._length_factor(short_ecc), 1.0,
			"a blade at the baseline hop count pays the length axis nothing")
	assert_gt(BladeSim._length_factor(long_ecc), BladeSim._length_factor(short_ecc),
			"a blade past the baseline hop count must get a bigger sweep budget than a short one")
	assert_eq(BladeSim._length_factor(beyond_ecc), BladeSim._length_factor(long_ecc),
			"budget must be clamped at LENGTH_ECC_CEILING — an even longer blade buys nothing more")
	# And the factor is what the swing actually consumes: a blade past the
	# baseline moves differently with the axis on than off, where the baseline
	# blade (next test) does not.
	var on := _chain(BladeSim.LENGTH_ECC_CEILING + 1)
	var off := _chain(BladeSim.LENGTH_ECC_CEILING + 1)
	BladeSim.simulate(on, _drivers_for(on), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true)
	BladeSim.simulate(off, _drivers_for(off), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, false)
	assert_ne(on.positions, off.positions,
			"a long blade's swing must differ with the length axis on — the factor reaches the solver")


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

func test_substeps_alone_hold_shape_better_than_flat_iterations() -> void:
	# A 55-hop whip — long enough that Gauss-Seidel propagation is the
	# bottleneck (owner's rationale: ~1 constraint per sweep). Length
	# scaling is explicitly OFF on both sides so this isolates exactly the
	# substep-vs-iteration claim (Macklin et al. 2019): same total sweep
	# budget, spent as smaller steps instead of more passes per step.
	# The "at equal-or-lower sweep cost" half of that claim was pinned by
	# counting projections through a constraint subclass, which the native
	# solver refuses (#847); it returns when #848's resident solver object
	# reports its iteration count. Only the shape-holding half is pinned here.
	var n := 56
	var old_state := _chain(n)
	BladeSim.simulate(old_state, _drivers_for(old_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, 1, false)
	var old_error := _total_stretch_error(old_state)

	var new_state := _chain(n)
	BladeSim.simulate(new_state, _drivers_for(new_state), DURATION,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, false)
	var new_error := _total_stretch_error(new_state)

	assert_lt(new_error, old_error,
			"substepping (smaller dt) must hold a long whip's shape better than the old flat-iteration config")
