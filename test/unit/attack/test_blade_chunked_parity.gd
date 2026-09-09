extends GutTest

## #801 — the ground the whole interleave stands on: a swing baked in CHUNKS
## must be BIT-IDENTICAL to one baked in a single call.
##
## `MeleeAttackPlan.resolve_against` bakes the swing optimistically, walks it
## scanning and landing, and on a death re-bakes from the severance sample. That
## is only "the same trajectory a true per-sample interleave would produce" if
## splitting the run changes nothing — so if these fail, option B is wrong and
## the issue goes back to design. They are deliberately assertions on raw
## floats: `assert_eq` on `Vector2`, never `is_equal_approx`.
##
## Two separate properties, because two separate things could break:
##
## 1. **Continuation** — `simulate_range(k, n-k)` picking up from
##    `state.prev_positions` equals steps k..n of the unchunked run. This is
##    what the integer `step_offset` buys: every substep's `t` is
##    `float(step_offset + local) * dt + float(s+1) * sub_dt`, so a chunk
##    computes the same times the unchunked run computed. A float `t_start`
##    accumulated across chunks would drift in the last bits and fail here.
## 2. **Prefix** — a SHORT bake of k steps equals the first k samples of a long
##    bake. `resolve_against`'s head-replay rests on exactly this (it re-runs
##    the head of a chunk to recover the exact Verlet history at the severance
##    sample), and it holds only because nothing in the solver is a function of
##    the run's total LENGTH: the adaptive sweep budget keys off
##    `velocity_iter_ref` and this substep's own speeds, never off `duration`.
##    If a length-dependent term ever appears, the head-replay silently starts
##    the re-baked tail from a lie and this is what says so.

const DURATION := 1.2
const SPACING := 40.0
const DT := BladeSim.DEFAULT_DT


## Straight whip chain from the pivot (index 0) — the whippy extreme, where a
## chunk boundary has the most stored velocity to carry across.
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


static func _drivers(state: BladeState) -> Array[BladeDriver]:
	var pivot := state.positions[state.pivot_index]
	var offset := state.positions[1] - pivot
	var out: Array[BladeDriver] = []
	out.append(BladeArcDriver.new(
			1, pivot, offset.length(), offset.angle(), TAU, DURATION))
	return out


static func _steps() -> int:
	return int(ceil(DURATION / DT))


## Every sample of [param a] equals [param b]'s sample at the same GLOBAL
## index, bit for bit. `offset` is where `a`'s local index 0 sits in `b`.
func _assert_samples_identical(
		a: BladeTrajectory, b: BladeTrajectory, offset: int, what: String) -> void:
	for j in a.samples.size():
		var mine: PackedVector2Array = a.samples[j]
		var theirs: PackedVector2Array = b.samples[offset + j]
		assert_eq(mine.size(), theirs.size(), "%s: particle count at sample %d" % [what, j])
		for i in mine.size():
			assert_eq(mine[i], theirs[i],
					"%s: particle %d at global sample %d" % [what, i, offset + j])


# ── 1. Continuation ────────────────────────────────────────────────────────

## The whole issue in one assertion.
func test_a_chunked_run_is_bit_identical_to_an_unchunked_one() -> void:
	var steps := _steps()
	var cut := steps / 3
	var whole_state := _chain(6)
	var whole := BladeSim.simulate(whole_state, _drivers(whole_state), DURATION, DT)

	var split_state := _chain(6)
	var split_drivers := _drivers(split_state)
	var head := BladeSim.simulate_range(split_state, split_drivers, 0, cut, DT)
	# No reset, no seeding: `simulate_range` trusts `state.prev_positions` for
	# every offset but 0, which is the continue-from-state path itself.
	var tail := BladeSim.simulate_range(
			split_state, split_drivers, cut, steps - cut, DT)

	assert_eq(head.samples.size(), cut + 1, "head covers 0..cut")
	assert_eq(tail.samples.size(), steps - cut + 1, "tail covers cut..end")
	_assert_samples_identical(head, whole, 0, "head")
	# The chunks overlap in exactly one sample — the tail's local 0 IS global
	# `cut`, the pose the head ended on.
	assert_eq(tail.samples[0], head.samples[cut], "the chunks share sample `cut`")
	_assert_samples_identical(tail, whole, cut, "tail")


## Three chunks, uneven — a swing can sever more than once, and each severance
## starts a new chunk at an arbitrary sample.
func test_three_uneven_chunks_are_bit_identical_too() -> void:
	var steps := _steps()
	var whole_state := _chain(5)
	var whole := BladeSim.simulate(whole_state, _drivers(whole_state), DURATION, DT)

	var s := _chain(5)
	var d := _drivers(s)
	var cuts := [17, 83]
	var a := BladeSim.simulate_range(s, d, 0, cuts[0], DT)
	var b := BladeSim.simulate_range(s, d, cuts[0], cuts[1] - cuts[0], DT)
	var c := BladeSim.simulate_range(s, d, cuts[1], steps - cuts[1], DT)
	_assert_samples_identical(a, whole, 0, "chunk 1")
	_assert_samples_identical(b, whole, cuts[0], "chunk 2")
	_assert_samples_identical(c, whole, cuts[1], "chunk 3")


# ── 2. Prefix ──────────────────────────────────────────────────────────────

## What the head-replay in `resolve_against` rests on. Named separately from
## the continuation case on purpose: this one dies the moment any solver term
## becomes a function of the run's total length, and it would take fork 1's
## whole strategy with it.
func test_a_short_bake_is_a_prefix_of_a_long_one() -> void:
	var cut := 40
	var long_state := _chain(6)
	var long := BladeSim.simulate(long_state, _drivers(long_state), DURATION, DT)
	var short_state := _chain(6)
	var short := BladeSim.simulate_range(
			short_state, _drivers(short_state), 0, cut, DT)
	assert_eq(short.samples.size(), cut + 1, "the short bake stops at `cut`")
	_assert_samples_identical(short, long, 0, "prefix")


## And the prefix property holds for the STATE, not just the samples — which is
## the half the head-replay actually consumes. `prev_positions` at a sample is a
## mid-sample pose (`_step` rewrites it once per SUBSTEP), so it is not
## recoverable from `samples` and the replay is the only way to get it.
func test_the_replayed_head_lands_on_the_exact_verlet_history() -> void:
	var cut := 40
	var a_state := _chain(6)
	var a_drivers := _drivers(a_state)
	BladeSim.simulate_range(a_state, a_drivers, 0, cut, DT)
	var a_pos := a_state.positions.duplicate()
	var a_prev := a_state.prev_positions.duplicate()

	# The same head reached the other way: bake it in two pieces.
	var b_state := _chain(6)
	var b_drivers := _drivers(b_state)
	BladeSim.simulate_range(b_state, b_drivers, 0, 11, DT)
	BladeSim.simulate_range(b_state, b_drivers, 11, cut - 11, DT)
	for i in a_pos.size():
		assert_eq(b_state.positions[i], a_pos[i], "positions at particle %d" % i)
		assert_eq(b_state.prev_positions[i], a_prev[i], "prev at particle %d" % i)


# ── 3. Per-particle damping ────────────────────────────────────────────────

## #186 acceptance 4, now a per-PARTICLE property (#801): an all-zero damping
## array must be bit-identical to no array at all, or every unsevered swing
## would start diverging from the native backend the moment the member existed.
func test_all_zero_damping_is_bit_identical_to_none() -> void:
	var bare_state := _chain(5)
	var bare := BladeSim.simulate(bare_state, _drivers(bare_state), DURATION, DT)
	var damped_state := _chain(5)
	damped_state.damping.resize(damped_state.positions.size())  # all zeros
	var damped := BladeSim.simulate(
			damped_state, _drivers(damped_state), DURATION, DT)
	_assert_samples_identical(damped, bare, 0, "zero damping")


## And a real drag on one coasting particle does bleed it — the same claim
## `test_drag_bleeds_a_coasting_fragment` made about a whole free-flight body,
## re-pointed onto the array. Vertex 4 of a chain whose driver was dropped is
## exactly what a severance leaves behind.
func test_damping_bleeds_only_the_particle_it_is_written_for() -> void:
	var no_drivers: Array[BladeDriver] = []
	var free_state := _chain(3)
	free_state.inv_masses[0] = 1.0  # unpinned everywhere — nothing is driving it
	free_state.prev_positions = free_state.positions.duplicate()
	for i in free_state.positions.size():
		free_state.prev_positions[i] = free_state.positions[i] - Vector2(2.0, 0.0)
	var dragged_state := _chain(3)
	dragged_state.inv_masses[0] = 1.0
	dragged_state.prev_positions = free_state.prev_positions.duplicate()
	dragged_state.set_damping(2, BladeState.SEVERED_DRAG)

	# step_offset 1: keep the seeded Verlet history rather than resetting it.
	var free := BladeSim.simulate_range(free_state, no_drivers, 1, 60, DT)
	var dragged := BladeSim.simulate_range(dragged_state, no_drivers, 1, 60, DT)
	var free_travel: float = (free.samples[60][2] - free.samples[0][2]).length()
	var drag_travel: float = (dragged.samples[60][2] - dragged.samples[0][2]).length()
	assert_lt(drag_travel, free_travel, "drag bleeds the particle it is set on")
	assert_gt(BladeState.SEVERED_DRAG, 0.0, "the shipped default is a real, small drag")


# ── 4. The swing clock is sim state ────────────────────────────────────────

## #780's clock carries `_f`, banked `drag` and `touched` — so a chunk boundary
## must hand the NEXT chunk the same instance, and rewinding for a head-replay
## must rewind the clock with it. A fresh clock mid-swing would un-bank a
## Fortification wall's drag and silently stop it sheltering what is behind it.
func test_a_dragged_swing_is_bit_identical_across_a_chunk_boundary() -> void:
	var steps := _steps()
	var cut := 50
	var whole_state := _chain(5)
	var whole := BladeSim.simulate(
			whole_state, _drivers(whole_state), DURATION, DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true,
			_wall_clock(whole_state))

	var split_state := _chain(5)
	var split_drivers := _drivers(split_state)
	var clock := _wall_clock(split_state)
	var head := BladeSim.simulate_range(
			split_state, split_drivers, 0, cut, DT, BladeSim.DEFAULT_ITERATIONS,
			0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	# The clock is NOT rebuilt here — that is the point.
	var tail := BladeSim.simulate_range(
			split_state, split_drivers, cut, steps - cut, DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	assert_true(clock.is_warping(), "fixture: the swing must actually touch the wall")
	_assert_samples_identical(head, whole, 0, "dragged head")
	_assert_samples_identical(tail, whole, cut, "dragged tail")


## Capture/restore is exact — the head-replay rewinds the clock and re-ticks it,
## and must land on the same bank it had before.
func test_the_clock_rewinds_and_re_ticks_to_the_same_bank() -> void:
	var cut := 50
	var state := _chain(5)
	var drivers := _drivers(state)
	var clock := _wall_clock(state)
	var snap_positions := state.positions.duplicate()
	var bank := clock.capture()
	BladeSim.simulate_range(
			state, drivers, 0, cut, DT, BladeSim.DEFAULT_ITERATIONS, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, true, clock)
	var f_after := clock.progress()
	var drag_after := clock.drag

	state.positions = snap_positions
	clock.restore(bank)
	assert_false(clock.is_warping(), "the rewind un-banks what the run banked")
	BladeSim.simulate_range(
			state, drivers, 0, cut, DT, BladeSim.DEFAULT_ITERATIONS, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, true, clock)
	assert_eq(clock.progress(), f_after, "warped progress replays exactly")
	assert_eq(clock.drag, drag_after, "banked drag replays exactly")


## A drag zone parked where the chain sweeps, so the clock actually warps.
## Since #811 the zone lives on the state's defender field, not on the clock —
## the clock is the accumulator half only.
func _wall_clock(state: BladeState) -> BladeSwingClock:
	var field := BladeObstacleField.new()
	field.add_drag_zone(Vector2(0.0, SPACING * 2.0), 30.0, 1.0)
	state.obstacles = field
	return BladeSwingClock.new(DURATION)
