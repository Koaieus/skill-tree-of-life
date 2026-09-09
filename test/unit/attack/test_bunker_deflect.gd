extends GutTest

## #781 — Bunker deflection: a blade cannot pass through a plate. A floppy
## blade flops around it and never breaks; a rigid one jams, is driven a fixed
## distance into it, and breaks an EDGE (ADR 0005: bunkers destroy structure,
## never matter). Hand-built blades throughout (the issue's NOTES: AI-built
## blades sit at the floppy end and report nothing about the shatter).
## Nothing here pins SHATTER_DISTANCE's value — only the classification.

const _DURATION := 1.2
const _SPACING := 60.0
const _RADIUS := 24.0
const _BUNKER_RADIUS := 32.0


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


## The same arm, welded at every joint by ClampAddon's phantom braces: a rigid
## rod. This is the "clamped spine" of the acceptance list.
func _clamped_arm(n: int = 4) -> BladeState:
	var s := _arm(n)
	for i in range(1, n - 1):
		ClampAddon.append_weld_braces(s, i)
	return s


## The triangulated ladder from test_blade_swing_drag — an induced truss.
func _truss() -> BladeState:
	var positions: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in 3:
		positions.append(Vector2(float(i + 1) * _SPACING, -_SPACING * 0.5))
		positions.append(Vector2(float(i + 1) * _SPACING, _SPACING * 0.5))
		radii.append(_RADIUS)
		radii.append(_RADIUS)
	positions.push_front(Vector2.ZERO)
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


## One plate on the arc the TIP sweeps, `turns` of a turn round.
func _field_on_arc(state: BladeState, turns: float, tip_idx: int) -> BladeObstacleField:
	var f := BladeObstacleField.new()
	var pivot := state.positions[state.pivot_index]
	var r := pivot.distance_to(state.positions[tip_idx])
	f.add_zone(pivot + Vector2.from_angle(turns * TAU) * r, _BUNKER_RADIUS)
	return f


func _simulate(state: BladeState, clock: BladeSwingClock = null, iters: int = BladeSim.DEFAULT_ITERATIONS) -> BladeTrajectory:
	return BladeSim.simulate(
			state, _drivers(state), _DURATION, BladeSim.DEFAULT_DT,
			iters, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)


func _run(state: BladeState, tip_idx: int, iters: int = BladeSim.DEFAULT_ITERATIONS,
		turns: float = 0.15, sweep: float = TAU) -> Dictionary:
	var field := _field_on_arc(state, turns, tip_idx)
	field.trace = true
	state.obstacles = field
	var clock := BladeSwingClock.new(_DURATION)
	var traj := BladeSim.simulate(
			state, _drivers(state, sweep), _DURATION, BladeSim.DEFAULT_DT,
			iters, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	var peak := 0.0
	var acc := 0.0
	var contact_peak := 0.0
	var contact_acc := 0.0
	for row in field.trace_rows:
		acc = maxf(0.0, acc + row[0])
		peak = maxf(peak, acc)
		contact_acc = maxf(0.0, contact_acc + row[1])
		contact_peak = maxf(contact_peak, contact_acc)
	return {traj = traj, field = field, clock = clock, rows = field.trace_rows.size(),
			drive_peak = peak, contact_peak = contact_peak,
			broke = field._break_edge >= 0,
			break_edge = field._break_edge, break_step = field._break_step}


## Deepest any vertex disc sits inside the plate over the whole trajectory.
func _max_penetration(traj: BladeTrajectory, state: BladeState, field: BladeObstacleField) -> float:
	var worst := 0.0
	for pose in traj.samples:
		for i in pose.size():
			if state.removed_vertices.has(i):
				continue
			for z in field.zone_radii.size():
				var pen := field.zone_radii[z] + state.radii[i] - pose[i].distance_to(field.zone_centers[z])
				worst = maxf(worst, pen)
	return worst


# ── Tuning readout (prints; asserts nothing beyond running) ─────────────────

func test_readout_the_strain_metric_across_the_rigidity_range() -> void:
	# The numbers behind SHATTER_DISTANCE. `drive` is the metric in use (the
	# grip's unresolved advance, px); `contact-point` is the issue's first
	# formulation, which reads 0 here because a rigid body resolves the pushout
	# completely by rotating back as a whole. Re-run when the solver config or
	# the threshold changes; the classification tests below are the pins.
	for iters in [BladeSim.DEFAULT_ITERATIONS, BladeSim.DEFAULT_ITERATIONS * 2]:
		for cfg in [
				{name = "bare spine 4", state = _arm(), tip = 3, sweep = TAU},
				{name = "bare spine 8", state = _arm(8), tip = 2, sweep = TAU},
				{name = "bare spine 8 x2", state = _arm(8), tip = 2, sweep = 2.0 * TAU},
				{name = "clamped spine", state = _clamped_arm(), tip = 3, sweep = TAU},
				{name = "truss", state = _truss(), tip = 6, sweep = TAU}]:
			var r := _run(cfg.state, cfg.tip, iters, 0.15, cfg.sweep)
			gut.p("[iters=%d] %-16s contact substeps=%4d | drive peak=%7.2f | contact-point peak=%5.2f | break edge=%d at step %d | max pen=%.2f"
					% [iters, cfg.name, r.rows, r.drive_peak, r.contact_peak,
					r.break_edge, r.break_step, _max_penetration(r.traj, cfg.state, r.field)])
	pass_test("readout only")


# ── Acceptance 1, 9: a floppy blade never breaks, at any speed ──────────────

func test_a_floppy_blade_yields_around_a_plate_and_never_breaks() -> void:
	for cfg in [
			{state = _arm(), tip = 3, sweep = TAU},
			# A long floppy arm curls in under a hard sweep (see
			# test_blade_swing_drag), so its plate sits on a mid-chain circle.
			{state = _arm(8), tip = 2, sweep = TAU},
			{state = _arm(8), tip = 2, sweep = 2.0 * TAU},
			{state = _arm(6), tip = 2, sweep = -2.0 * TAU}]:
		var r := _run(cfg.state, cfg.tip, BladeSim.DEFAULT_ITERATIONS, 0.15, cfg.sweep)
		assert_gt(r.rows, 0, "the floppy blade must actually have met the plate")
		assert_false(r.broke, "a bare spine must flop around the plate, never break (sweep=%s)" % cfg.sweep)
		assert_lt(r.drive_peak, BladeObstacleField.SHATTER_DISTANCE * 0.5,
				"a floppy blade's strain must stay well clear of the threshold, not merely under it")


# ── Acceptance 2, 3, 10: a rigid blade always breaks, and breaks an EDGE ───

func test_a_clamped_spine_breaks_an_edge_within_the_contact() -> void:
	var state := _clamped_arm()
	var r := _run(state, 3)
	assert_true(r.broke, "a clamped (welded) spine cannot fold, so it must break")
	assert_true(r.break_edge >= 0 and r.break_edge < state.edges.size(),
			"what breaks is an edge index into state.edges")
	assert_eq(state.removed_vertices.size(), 0, "ADR 0005: a bunker never pops a vertex")


func test_a_truss_breaks_the_end_rung_that_takes_the_plate_head_on() -> void:
	var state := _truss()
	var r := _run(state, 6)
	assert_true(r.broke, "an induced truss must break")
	# Edge 10 is (5, 6): the rung at the tip, perpendicular to the spine and so
	# squarely along the plate's push — the load-share selector's pick.
	assert_eq(r.break_edge, 10, "the most loaded edge is the tip rung")
	assert_true(r.break_step > 0, "the break is stamped with the sample that armed it")


func test_raising_solver_fidelity_sharpens_the_separation() -> void:
	# Owner's rule: iteration sensitivity is bounded, not eliminated — more
	# sweeps resolve a floppy contact MORE completely and leave a rigid one
	# stalled, so the verdict must not flip.
	var floppy_lo := _run(_arm(), 3, BladeSim.DEFAULT_ITERATIONS)
	var floppy_hi := _run(_arm(), 3, BladeSim.DEFAULT_ITERATIONS * 2)
	var rigid_lo := _run(_truss(), 6, BladeSim.DEFAULT_ITERATIONS)
	var rigid_hi := _run(_truss(), 6, BladeSim.DEFAULT_ITERATIONS * 2)
	assert_false(floppy_lo.broke)
	assert_false(floppy_hi.broke)
	assert_true(rigid_lo.broke)
	assert_true(rigid_hi.broke)
	assert_gt(rigid_hi.drive_peak - floppy_hi.drive_peak,
			rigid_lo.drive_peak - floppy_lo.drive_peak,
			"the gap between rigid and floppy must widen with fidelity")


# ── Acceptance 8: zero bunkers, zero field — structurally ───────────────────

func test_no_bunker_means_no_field_and_a_bit_identical_swing() -> void:
	var bare := _arm(8)
	var traj_bare := _simulate(bare)
	assert_null(bare.obstacles, "a state built with no bunker carries no field at all")
	var again := _arm(8)
	var traj_again := _simulate(again)
	for i in traj_bare.samples.size():
		assert_eq(traj_again.samples[i], traj_bare.samples[i])


func test_a_plate_the_blade_never_reaches_banks_nothing() -> void:
	var state := _arm()
	var field := BladeObstacleField.new()
	field.add_zone(Vector2(100000.0, 100000.0), _BUNKER_RADIUS)
	state.obstacles = field
	_simulate(state)
	assert_eq(field.max_strain(), 0.0, "an untouched plate must bank no strain")
	assert_false(field._break_edge >= 0)


# ── Acceptance 11: the visual penetration budget ───────────────────────────

func test_maximum_penetration_over_a_swing_stays_within_the_slop() -> void:
	for cfg in [{state = _arm(8), tip = 2}, {state = _truss(), tip = 6}]:
		var r := _run(cfg.state, cfg.tip)
		var pen := _max_penetration(r.traj, cfg.state, r.field)
		assert_lte(pen, BladeObstacleField.CONTACT_SLOP + 1.0,
				"no vertex disc may sit deeper in a plate than the slop (got %.2f)" % pen)
		assert_lt(pen, BladeObstacleField.SHATTER_DISTANCE, "and never near the threshold")


# ── Acceptance 12: a transient hold washes out, nothing stays banked ───────

func test_a_floppy_contact_leaves_the_accumulator_at_zero_once_released() -> void:
	# The short arm meets the plate for a dozen substeps and flops clear well
	# before the swing ends — so by the end nothing is near it and the bank
	# must have RESET, not kept the transient's partial credit.
	var r := _run(_arm(), 3)
	assert_gt(r.rows, 0, "must have touched")
	assert_lt(r.rows, 60, "and must have flopped clear long before the swing ended")
	assert_gt(r.drive_peak, 0.0, "the transient hold did bank something while it lasted")
	assert_eq(r.field.max_strain(), 0.0,
			"once the blade has flopped past, the bank must read zero — not partial credit")


# ── The grip: a hard stall, not a break ─────────────────────────────────────

func test_a_plate_on_the_grips_arc_stalls_the_swing_and_breaks_nothing() -> void:
	var state := _arm()
	var r := _run(state, 1, BladeSim.DEFAULT_ITERATIONS, 0.12)  # on the DRIVEN particle's circle
	assert_true(r.clock.is_stalled(), "a driven grip vertex touching a plate stalls the clock")
	assert_false(r.broke, "the grip stalls; it does not shatter (owner, 2026-09-07)")
	var pivot: Vector2 = state.positions[0]
	var last: PackedVector2Array = r.traj.samples[-1]
	var mid: PackedVector2Array = r.traj.samples[r.traj.samples.size() / 2]
	assert_almost_eq(last[1].distance_to(mid[1]), 0.0, 2.0 + BladeObstacleField.CONTACT_SLOP,
			"the stalled grip holds its place on the plate")
	assert_gt(last[3].distance_to(mid[3]), 5.0, "the free tip keeps flailing on its momentum")
	assert_eq(pivot, last[0])


func test_a_stalled_clock_never_advances_and_stays_monotonic() -> void:
	var clock := BladeSwingClock.new(_DURATION)
	clock.tick(0.3, 1.0 / 480.0)
	clock.stall()
	assert_true(clock.is_stalled())
	assert_eq(clock.warp(), 0.0)
	var f := clock.progress()
	assert_almost_eq(f, 0.25, 1e-6, "seeded from the nominal progress at the stall")
	for i in 100:
		clock.tick(0.3 + float(i) / 480.0, 1.0 / 480.0)
		assert_eq(clock.progress(), f, "a stalled clock is frozen")
	var bank := clock.capture()
	var fresh := BladeSwingClock.new(_DURATION)
	fresh.restore(bank)
	assert_true(fresh.is_stalled(), "the stall is sim state and rides the Bank")


# ── Acceptance 5: determinism, and the rewind contract ─────────────────────

func test_the_same_jam_reproduces_bit_identically() -> void:
	var a := _run(_truss(), 6)
	var b := _run(_truss(), 6)
	assert_eq(a.break_edge, b.break_edge)
	assert_eq(a.break_step, b.break_step)
	for i in a.traj.samples.size():
		assert_eq(a.traj.samples[i], b.traj.samples[i], "sample %d" % i)


func test_capture_and_restore_round_trip_the_field() -> void:
	var state := _truss()
	var field := _field_on_arc(state, 0.15, 6)
	state.obstacles = field
	var drivers := _drivers(state)
	var head := 20  # before the truss arms its break (~sample 31-33)
	BladeSim.simulate_range(state, drivers, 0, head)
	var bank := field.capture()
	var strain_then := field.max_strain()
	BladeSim.simulate_range(state, drivers, head, 30)
	field.restore(bank)
	assert_eq(field.max_strain(), strain_then, "restore rewinds the strain")
	var b := field.consume_break()
	assert_null(b, "nothing armed at the snapshot")
