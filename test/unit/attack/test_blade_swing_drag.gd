extends GutTest

## #780 — Fortification's swing drag: a wall of fortified nodes bogs a blade
## down by slowing the SWING'S CLOCK, never a vertex's velocity.
##
## #811 re-pointed the SENSING half of these tests: the clock no longer holds
## zones or tests geometry — [BladeObstacleField] carries the merged defender
## field (walls + plates) and banks a wall contact onto the clock as its
## projection pass finds one. Every assertion below is still about the same
## quantity (`clock.drag`, `clock.touched`, `clock.progress()`, swept arc);
## what changed is that the zones are authored on the field via
## `add_drag_zone` and hang off `state.obstacles`.
##
## Everything here runs on HAND-BUILT blades and hand-placed drag zones, per the
## issue's own NOTES: AI-built blades sit at the floppy end and under-report
## drag's bite. Nothing pins an authored `.tres` magnitude — the number on
## `fortification_addon.tscn` is the owner's to tune, so these tests pin the
## SHAPE (more fortified nodes ⇒ more drag ⇒ less arc) and the invariants
## (monotonic, exactly inert when untouched).

## Records the clock's angular progress once per SUBSTEP, from inside the real
## sim. Appended after the arc drivers so it reads the same `f` they just used.
## This is how acceptance 3 gets asserted on the actual quantity rather than on
## a particle's angle, which the constraint sweeps nudge off the driven arc by
## ~1e-4 rad (they run AFTER the drivers, and a driven particle is not pinned).
class ProgressRecorder extends BladeDriver:
	var clock: BladeSwingClock
	var seen: Array[float] = []

	func _init(clock_: BladeSwingClock) -> void:
		clock = clock_

	func apply(_positions: PackedVector2Array, t: float) -> void:
		# -1.0 means "not warping yet"; normalise to nominal progress so the
		# recorded series is continuous across the moment drag first lands.
		var f := clock.progress()
		seen.append(f if f >= 0.0 else clampf(t / _DURATION, 0.0, 1.0))


const _DURATION := 1.2
const _SPACING := 60.0
const _RADIUS := 24.0


# ── Fixtures ───────────────────────────────────────────────────────────────

## A straight `n`-vertex arm along +X from the origin, pivot at index 0. Rigid
## (BladeState.build seeds a fully-rigid distance constraint per edge), which is
## exactly the blade drag is meant to act on and the one particle damping cannot
## touch.
func _arm(n: int = 4) -> BladeState:
	var positions: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in n:
		positions.append(Vector2(float(i) * _SPACING, 0.0))
		radii.append(_RADIUS)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	return BladeState.build(positions, 0, edges, radii)


## One arc driver per pivot-adjacent particle, mirroring
## [method MeleeAttackPlan.build_drivers]. A straight arm has exactly one.
func _drivers(state: BladeState, sweep: float = TAU) -> Array[BladeDriver]:
	var out: Array[BladeDriver] = []
	var pivot := state.positions[state.pivot_index]
	for e in state.edges:
		var other := -1
		if e.x == state.pivot_index:
			other = e.y
		elif e.y == state.pivot_index:
			other = e.x
		if other < 0:
			continue
		var offset := state.positions[other] - pivot
		out.append(BladeArcDriver.new(
				other, pivot, offset.length(), offset.angle(), sweep, _DURATION))
	return out


func _simulate(
		state: BladeState,
		clock: BladeSwingClock,
		recorder: ProgressRecorder = null) -> BladeTrajectory:
	var drivers := _drivers(state)
	if recorder != null:
		drivers.append(recorder)
	return BladeSim.simulate(
			state, drivers, _DURATION, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS,
			true, clock)


## `count` drag zones strung along the arc the DRIVEN particle sweeps, starting
## `from_turns` of a turn round and one every `step_turns`. On the driven
## particle's own circle, not the tip's, for the reason in [constant
## _DRIVEN_IDX]: a bare spine folds inward under a hard sweep, so a zone placed
## out at the tip's rest radius is simply not where the blade ends up.
func _clock_on_arc(
		state: BladeState,
		count: int,
		amount: float = 1.0,
		from_turns: float = 0.10,
		step_turns: float = 0.015) -> BladeSwingClock:
	var field := BladeObstacleField.new()
	var pivot := state.positions[state.pivot_index]
	var r := pivot.distance_to(state.positions[_DRIVEN_IDX])
	for i in count:
		var a := (from_turns + float(i) * step_turns) * TAU
		field.add_drag_zone(pivot + Vector2.from_angle(a) * r, _RADIUS, amount)
	state.obstacles = field
	return BladeSwingClock.new(_DURATION)


## A hand-built RIGID blade: a triangulated ladder that actually holds its shape
## where the bare spine folds. The issue's NOTES ask for both ends of the
## rigidity range and warn off AI-built blades, which sit at the floppy end.
func _truss() -> BladeState:
	var positions: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in 3:
		positions.append(Vector2(float(i + 1) * _SPACING, -_SPACING * 0.5))
		positions.append(Vector2(float(i + 1) * _SPACING, _SPACING * 0.5))
		radii.append(_RADIUS)
		radii.append(_RADIUS)
	positions.push_front(Vector2.ZERO)  # pivot
	radii.push_front(_RADIUS)
	edges.append(Vector2i(0, 1))
	edges.append(Vector2i(0, 2))
	edges.append(Vector2i(1, 2))
	for r in 2:
		var a := 1 + r * 2
		edges.append(Vector2i(a, a + 2))
		edges.append(Vector2i(a + 1, a + 3))
		edges.append(Vector2i(a, a + 3))
		edges.append(Vector2i(a + 2, a + 3))
	return BladeState.build(positions, 0, edges, radii)


## The pivot-adjacent particle — the one the arc driver prescribes, and so the
## one whose angle IS the swing's angular progress. Deliberately not the tip:
## a bare spine is FLOPPY (the issue's own NOTES), and under a hard sweep this
## arm curls in from 180px to under 100px of reach, so the tip measures the
## solver's compliance rather than the clock.
const _DRIVEN_IDX := 1

## Total angle the driven particle actually swept, unwrapped — the "how much arc
## did this swing complete" figure every acceptance below is phrased in.
func _swept(traj: BladeTrajectory, state_pivot: Vector2) -> float:
	return _cumulative_angles(traj, state_pivot, _DRIVEN_IDX)[-1]


## Per-sample cumulative signed angle of `tip_idx` about `state_pivot`,
## unwrapped so it grows past PI instead of folding. Sample 0 is 0.0.
func _cumulative_angles(
		traj: BladeTrajectory, state_pivot: Vector2, tip_idx: int) -> Array[float]:
	var out: Array[float] = [0.0]
	var total := 0.0
	var prev: float = (traj.samples[0][tip_idx] - state_pivot).angle()
	for i in range(1, traj.samples.size()):
		var a: float = (traj.samples[i][tip_idx] - state_pivot).angle()
		var d := a - prev
		# Unwrap: a per-sample step is far below PI at any sane swing rate, so a
		# jump past PI is the atan2 branch cut, not real motion.
		while d > PI:
			d -= TAU
		while d < -PI:
			d += TAU
		total += d
		out.append(total)
		prev = a
	return out


# ── Acceptance 5 (and the "0 is exact" property) ───────────────────────────

func test_a_drag_zone_that_is_never_touched_changes_nothing_bit_exactly() -> void:
	# The clock IS attached — so the clock code path runs for the whole swing —
	# but its one zone sits far outside the arm's reach and is never contacted.
	# Acceptance 5 is a BIT-EXACTNESS claim, not an approximate one: `f` must
	# still be derived from `t` character for character until first contact.
	var bare := _arm()
	var traj_bare := _simulate(bare, null)

	var clocked := _arm()
	var far_field := BladeObstacleField.new()
	far_field.add_drag_zone(Vector2(100000.0, 100000.0), _RADIUS, 5.0)
	clocked.obstacles = far_field
	var far := BladeSwingClock.new(_DURATION)
	var traj_clocked := _simulate(clocked, far)

	assert_false(far.is_warping(),
			"an untouched zone must never start the clock warping")
	assert_eq(far.drag, 0.0, "an untouched zone must bank no drag")
	assert_eq(traj_clocked.samples.size(), traj_bare.samples.size(),
			"an untouched clock must not change the sample count")
	for i in traj_bare.samples.size():
		assert_eq(traj_clocked.samples[i], traj_bare.samples[i],
				"sample %d must be BIT-identical to the unclocked run" % i)


func test_a_clock_with_no_zones_at_all_changes_nothing_bit_exactly() -> void:
	var bare := _arm()
	var traj_bare := _simulate(bare, null)
	var clocked := _arm()
	var traj_clocked := _simulate(clocked, BladeSwingClock.new(_DURATION))
	for i in traj_bare.samples.size():
		assert_eq(traj_clocked.samples[i], traj_bare.samples[i],
				"sample %d must be BIT-identical with an empty clock" % i)


# ── Acceptance 1 & 2: drag bites, and it stacks ────────────────────────────

func test_one_fortified_node_completes_a_smaller_arc_than_none() -> void:
	var bare := _arm()
	var pivot := bare.positions[bare.pivot_index]
	var swept_bare := _swept(_simulate(bare, null), pivot)

	var dragged := _arm()
	var clock := _clock_on_arc(dragged, 1)
	var swept_dragged := _swept(_simulate(dragged, clock), pivot)

	assert_true(clock.is_warping(), "the zone must actually have been contacted")
	assert_lt(swept_dragged, swept_bare,
			"one fortified node must cost the swing measurable arc")


func test_drag_stacks_three_fortified_nodes_slow_more_than_one() -> void:
	var pivot := Vector2.ZERO
	var one_state := _arm()
	var one_clock := _clock_on_arc(one_state, 1)
	var swept_one := _swept(_simulate(one_state, one_clock), pivot)

	var three_state := _arm()
	var three_clock := _clock_on_arc(three_state, 3)
	var swept_three := _swept(_simulate(three_state, three_clock), pivot)

	assert_eq(one_clock.touched.size(), 1, "the one-node case must touch one zone")
	assert_eq(three_clock.touched.size(), 3, "the three-node case must touch three")
	assert_lt(swept_three, swept_one,
			"a wall of three must bog the swing down harder than a single node")
	assert_gt(three_clock.drag, one_clock.drag, "banked drag must be cumulative")


func test_the_warp_factor_falls_as_drag_rises_and_stays_in_zero_one() -> void:
	var clock := BladeSwingClock.new(_DURATION)
	assert_eq(clock.warp(), 1.0, "no drag must be exactly nominal rate")
	var prev := clock.warp()
	for amount in [0.5, 1.0, 4.0, 50.0, 1.0e6]:
		clock.drag = amount
		var w := clock.warp()
		assert_lt(w, prev, "warp must fall as drag rises (drag=%s)" % amount)
		assert_gt(w, 0.0, "warp must stay STRICTLY positive — no hard stall here")
		assert_lte(w, 1.0, "warp must never exceed nominal rate")
		prev = w


# ── Acceptance 3: angular progress never decreases. The hard one. ──────────

func test_the_swings_angular_progress_never_decreases_in_any_configuration() -> void:
	# Acceptance 3, asserted DIRECTLY on `f` — the quantity the arc driver
	# evaluates its ease at — sampled every substep of a real sim, for a floppy
	# spine and a rigid truss, from no wall at all up to an absurd one.
	for rigid in [false, true]:
		for cfg in _WALL_CONFIGS:
			var state: BladeState = _truss() if rigid else _arm()
			var clock := _clock_on_arc(state, maxi(cfg.count, 1), cfg.amount, 0.04, 0.015)
			if cfg.count == 0:
				state.obstacles = null
				clock = BladeSwingClock.new(_DURATION)
			var rec := ProgressRecorder.new(clock)
			_simulate(state, clock, rec)
			assert_gt(rec.seen.size(), 100, "the recorder must have run")
			for i in range(1, rec.seen.size()):
				assert_gte(rec.seen[i], rec.seen[i - 1],
						"f fell at substep %d (rigid=%s, %s)" % [i, rigid, cfg])
			assert_lte(rec.seen[-1], 1.0, "f must never exceed a completed sweep")


## No wall, a nuisance, a wall, a heavy wall, an absurd one.
const _WALL_CONFIGS := [
	{count = 0, amount = 0.0},
	{count = 1, amount = 1.0},
	{count = 3, amount = 1.0},
	{count = 8, amount = 4.0},
	{count = 6, amount = 1000.0},
]


func test_the_blades_swept_angle_also_never_backtracks() -> void:
	# Asserted DIRECTLY, on the blade's own swept angle, sample by sample, for
	# every configuration below — including a wall dense enough to all but stop
	# the swing, and a wall whose zones all land at once.
	for cfg in _WALL_CONFIGS:
		var state := _arm()
		var pivot: Vector2 = state.positions[state.pivot_index]
		var clock: BladeSwingClock = null
		if cfg.count > 0:
			clock = _clock_on_arc(state, cfg.count, cfg.amount, 0.05, 0.015)
		var traj := _simulate(state, clock)
		var angles := _cumulative_angles(traj, pivot, _DRIVEN_IDX)
		for i in range(1, angles.size()):
			# Tolerance, deliberately: the constraint sweeps run AFTER the
			# drivers and a driven particle is not pinned, so its angle jitters
			# ~1e-4 rad off the driven arc. The exact claim is the test above.
			assert_gte(angles[i], angles[i - 1] - 1e-3,
					"swept angle fell between samples %d and %d (%s)"
					% [i - 1, i, cfg])


func test_angular_progress_is_non_decreasing_on_a_rigid_truss_too() -> void:
	# The other end of the rigidity range. A truss is the blade drag is REALLY
	# aimed at — the one particle damping provably cannot slow, because the
	# distance constraints fight the damping and the driver then overwrites it —
	# so the invariant has to hold here, not only on a floppy spine.
	var state := _truss()
	var pivot: Vector2 = state.positions[state.pivot_index]
	var clock := _clock_on_arc(state, 5, 3.0, 0.04, 0.02)
	var traj := _simulate(state, clock)
	assert_true(clock.is_warping(), "a truss must actually meet the wall")
	var angles := _cumulative_angles(traj, pivot, _DRIVEN_IDX)
	for i in range(1, angles.size()):
		assert_gte(angles[i], angles[i - 1] - 1e-3,
				"swept angle fell between samples %d and %d on a truss" % [i - 1, i])


func test_a_truss_is_slowed_by_a_wall_it_sweeps_into() -> void:
	var bare := _truss()
	var pivot: Vector2 = bare.positions[bare.pivot_index]
	var swept_bare := _swept(_simulate(bare, null), pivot)
	var dragged := _truss()
	var swept_dragged := _swept(
			_simulate(dragged, _clock_on_arc(dragged, 3, 1.0, 0.04, 0.02)), pivot)
	assert_lt(swept_dragged, swept_bare,
			"a rigid truss must bog down on a wall — this is the case particle "
			+ "damping cannot touch, which is why drag lives on the clock")


func test_a_stacked_wall_cannot_make_the_clock_run_backwards() -> void:
	# The invariant at its source: `f` itself, ticked directly with drag piled
	# on between ticks, including an absurd magnitude.
	var clock := BladeSwingClock.new(_DURATION)
	# Force the warping branch without needing a contact.
	clock.touched[0] = true
	clock.drag = 1.0
	clock._warping = true
	var prev := clock.progress()
	for i in 500:
		clock.drag += 3.0 if i % 7 == 0 else 0.0
		clock.tick(float(i) * 0.01, 1.0 / 480.0)
		var f := clock.progress()
		assert_gte(f, prev, "f fell at tick %d" % i)
		assert_lte(f, 1.0, "f must stay clamped to a completed sweep")
		prev = f


# ── Acceptance 4: a stalled swing never reaches what is behind the wall ────

func test_a_wall_stalls_the_swing_and_nodes_further_round_are_not_reached() -> void:
	var state := _arm()
	var pivot := state.positions[state.pivot_index]
	var arc_r := pivot.distance_to(state.positions[_DRIVEN_IDX])
	var field := BladeObstacleField.new()
	# A dense wall early in the arc...
	for i in 6:
		var a := (0.02 + float(i) * 0.012) * TAU
		field.add_drag_zone(pivot + Vector2.from_angle(a) * arc_r, _RADIUS, 4.0)
	# ...and one lone node most of the way round, behind it.
	var sheltered := field.zones.size()
	field.add_drag_zone(pivot + Vector2.from_angle(0.75 * TAU) * arc_r, _RADIUS, 4.0)
	state.obstacles = field
	var clock := BladeSwingClock.new(_DURATION)

	var traj := _simulate(state, clock)
	var swept := _swept(traj, pivot)

	assert_true(clock.touched.size() >= 1, "the wall itself must be contacted")
	assert_false(clock.touched.has(sheltered),
			"the node BEHIND the wall must never be reached — that is what a "
			+ "wall protecting its back line means")
	assert_lt(swept, 0.5 * TAU,
			"a stalled swing must fall well short of its full sweep")


func test_a_zone_banks_its_drag_at_most_once_however_many_parts_touch_it() -> void:
	# Anti-double-dip (ADR 0005's arbitration, reinstated for drag): a fortified
	# node touched by a disc AND both incident capsules is still one node's worth
	# of drag. Placed mid-edge so the capsule sees it too.
	var state := _arm()
	var field := BladeObstacleField.new()
	field.add_drag_zone(Vector2(_SPACING * 1.5, 0.0), _RADIUS, 2.0)
	state.obstacles = field
	var clock := BladeSwingClock.new(_DURATION)
	_simulate(state, clock)
	assert_eq(clock.touched.size(), 1, "one zone, one entry")
	assert_eq(clock.drag, 2.0,
			"a zone must bank its drag exactly once, never per touching element")


# ── Sensing geometry: capsules count, not just discs (#785's surviving half) ──

func test_a_node_in_the_gap_between_two_vertices_still_drags_via_the_capsule() -> void:
	# The whole reason sensing is not vertex-only: a SWEEP's edges cross exactly
	# the gaps between the vertex arcs, so disc-only sensing would reintroduce
	# spacing luck for drag magnitude against a wall.
	var state := _arm()
	# Midway between vertices 1 and 2, and small enough that neither disc
	# reaches it — only the rim-trimmed capsule between them can.
	var clock := _sense_once(state, Vector2(_SPACING * 1.5, 0.0), 2.0, 1.0)
	assert_eq(clock.touched.size(), 1,
			"a node sitting in the gap must be sensed by the edge capsule")


func test_a_severed_edge_senses_nothing() -> void:
	var state := _arm()
	state.remove_edge(1)  # the 1-2 edge
	var clock := _sense_once(state, Vector2(_SPACING * 1.5, 0.0), 2.0, 1.0)
	assert_eq(clock.touched.size(), 0,
			"a severed edge (#781) is gone and must touch nothing")


## One wall zone, one projection pass, at the blade's REST pose — the direct
## replacement for `BladeSwingClock.sense()`, which #811 deleted. The contact
## test now lives in [method BladeObstacleField.project], so exercising the
## geometry means running one pass of the field rather than calling the clock.
func _sense_once(state: BladeState, center: Vector2, radius: float,
		amount: float) -> BladeSwingClock:
	var field := BladeObstacleField.new()
	field.add_drag_zone(center, radius, amount)
	state.obstacles = field
	var clock := BladeSwingClock.new(_DURATION)
	field.prepare(state, [] as Array[BladeDriver], clock)
	field.project(state.positions, state.inv_masses)
	return clock


# ── Acceptance 6: determinism ──────────────────────────────────────────────

func test_the_same_dragged_swing_reproduces_identically() -> void:
	var a_state := _arm()
	var a_traj := _simulate(a_state, _clock_on_arc(a_state, 3))
	var b_state := _arm()
	var b_traj := _simulate(b_state, _clock_on_arc(b_state, 3))
	assert_eq(a_traj.samples.size(), b_traj.samples.size())
	for i in a_traj.samples.size():
		assert_eq(a_traj.samples[i], b_traj.samples[i],
				"sample %d must reproduce bit-identically" % i)


# ── The stat channel exists and is inert by default ────────────────────────

func test_swing_drag_is_a_registered_stat_that_defaults_to_no_drag() -> void:
	var def := StatRegistry.get_def(&"swing_drag")
	assert_not_null(def, "swing_drag must be in the StatDefRoster")
	if def != null:
		assert_eq(def.default_value, 0.0,
				"an ordinary node must drag nothing, or every swing pays for "
				+ "Fortification whether or not anyone built it")


func test_fortification_authors_a_swing_drag_modifier() -> void:
	# The MAGNITUDE is the owner's to tune and is deliberately not pinned; that
	# the addon carries the channel at all is the spec.
	var addon := preload("res://skill_node/addons/fortification_addon.tscn") \
			.instantiate() as FortificationAddon
	autofree(addon)
	var ids: Array[StringName] = []
	for m in addon.get_local_modifiers():
		ids.append(m.stat_id)
	assert_has(ids, &"swing_drag",
			"Fortification's characteristic second modifier is swing drag")
	assert_has(ids, &"node_health", "and it keeps its original node_health grant")
