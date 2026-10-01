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
## How deep a grazing grip disc dips into the plate's reach.
const _GRAZE_DEPTH := 6.0
## How many samples after first contact the owner's clamped jam must break by.
const _BREAK_WITHIN_SAMPLES := 20
## A plate on the grip's circle, clear of the start pose.
const _GRIP_TURNS := 0.2


## Since #847 there is one backend, the native one; a checkout without the
## binary fails every case here loudly rather than switching solvers. The
## per-substep `trace_rows` these cases used to read were a GDScript-loop
## diagnostic, so the same two quantities are now read off the per-SAMPLE
## [BladeObstacleField.Bank] history the sim returns (4 substeps per sample):
## `contact_samples` — samples that ended with a plate still banked (strain or
## residual on any zone; both reset the substep nothing is near) — where
## `rows` counted contact substeps, and `drive_peak` — the highest banked
## strain at any sample — where it was the running peak over substeps. Every
## threshold below carries the value the native run measured beside it.


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
	state.obstacles = field
	var clock := BladeSwingClock.new(_DURATION)
	var traj := BladeSim.simulate(
			state, _drivers(state, sweep), _DURATION, BladeSim.DEFAULT_DT,
			iters, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	var peak := 0.0
	var contact_samples := 0
	for b: BladeObstacleField.Bank in field.history:
		var banked := false
		for z in b.strain.size():
			peak = maxf(peak, b.strain[z])
			if b.strain[z] > 0.0 or not b.edge_residual[z].is_empty():
				banked = true
		if banked:
			contact_samples += 1
	return {traj = traj, field = field, clock = clock, contact_samples = contact_samples,
			drive_peak = peak,
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
			gut.p("[iters=%d] %-16s contact samples=%4d | drive peak=%7.2f | break edge=%d at step %d | max pen=%.2f"
					% [iters, cfg.name, r.contact_samples, r.drive_peak,
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
		assert_gt(r.contact_samples, 0, "the floppy blade must actually have met the plate")
		assert_false(r.broke, "a bare spine must flop around the plate, never break (sweep=%s)" % cfg.sweep)
		# Threshold unchanged from the substep-rate version. A per-sample peak
		# can only read LOWER than the per-substep one it replaces (it is the
		# same accumulator, observed less often): measured 0.51 / 0.24 / 0.94 px
		# on the native run 2026-09-11 against 0.74 / 0.42 / 1.68 on the last
		# GDScript-trace run, against a threshold of SHATTER_DISTANCE * 0.5.
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
	assert_gt(r.contact_samples, 0, "must have touched")
	# Was `rows < 60` contact substeps; 15 samples is the same span at the
	# sample rate. Measured on the native run 2026-09-11: 3 contact samples
	# (the substep-rate GDScript run read 12 rows), so the margin is unchanged.
	assert_lt(r.contact_samples, 15, "and must have flopped clear long before the swing ended")
	assert_gt(r.drive_peak, 0.0, "the transient hold did bank something while it lasted")
	assert_eq(r.field.max_strain(), 0.0,
			"once the blade has flopped past, the bank must read zero — not partial credit")


# ── The grip: the most rigid case, not a special case ──────────────────────

## The swing progress the drivers read at [param b]: the accumulator once the
## clock is warping, nominal time before it.
func _effective_progress(b: BladeSwingClock.Bank) -> float:
	return b.f if b.warping else b.last_t / _DURATION


func test_a_plate_on_the_grips_arc_breaks_an_edge_incident_to_the_grip() -> void:
	var state := _clamped_arm()
	var r := _run(state, 1, BladeSim.DEFAULT_ITERATIONS, _GRIP_TURNS)  # on the DRIVEN particle's circle
	assert_gt(r.contact_samples, 0, "the grip must have touched the plate")
	assert_true(r.broke, "a driven grip jammed on a plate breaks its edges (owner, 2026-10-01)")
	if r.broke:
		var e: Vector2i = state.edges[r.break_edge]
		assert_true(e.x == 1 or e.y == 1, "the broken edge is incident to the grip, got %s" % e)
	assert_eq(state.removed_vertices.size(), 0, "ADR 0005: a bunker never pops a vertex")


func test_nothing_ever_stalls_the_swing_while_drivers_remain() -> void:
	var cases := {
		"bare spine": [_arm(), 1],
		"clamped spine": [_clamped_arm(), 1],
		"truss": [_truss(), 1],
	}
	for name: String in cases:
		var state: BladeState = cases[name][0]
		var r := _run(state, cases[name][1], BladeSim.DEFAULT_ITERATIONS, _GRIP_TURNS)
		assert_gt(r.contact_samples, 0, "%s: must have touched" % name)
		var hist: Array[BladeSwingClock.Bank] = r.clock.history
		for k in range(1, hist.size()):
			var before := _effective_progress(hist[k - 1])
			var after := _effective_progress(hist[k])
			if after <= before:
				fail_test("%s: progress stopped at sample %d (%f -> %f)" % [name, k, before, after])
				break
		pass_test("%s checked" % name)


## A floppy blade whose GRIP only grazes a plate — sitting just outboard of the
## grip's circle, so the contact is near-radial and the grip's advance along
## its arc is barely refused — still never breaks. A grip driven SQUARELY into
## a plate does break, floppy or not: the driver is the most rigid case.
func test_a_floppy_blade_whose_grip_grazes_a_plate_never_breaks() -> void:
	var state := _arm()
	var field := BladeObstacleField.new()
	var graze_radius := _SPACING + _BUNKER_RADIUS + _RADIUS - _GRAZE_DEPTH
	field.add_zone(Vector2.from_angle(_GRIP_TURNS * TAU) * graze_radius, _BUNKER_RADIUS)
	state.obstacles = field
	var clock := BladeSwingClock.new(_DURATION)
	BladeSim.simulate(state, _drivers(state), _DURATION, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	var peak := 0.0
	for b: BladeObstacleField.Bank in field.history:
		for z in b.strain.size():
			peak = maxf(peak, b.strain[z])
	gut.p("grip graze peak strain %.2f px (SHATTER_DISTANCE %.1f)" % [peak, BladeObstacleField.SHATTER_DISTANCE])
	var square := _run(_arm(), 1, BladeSim.DEFAULT_ITERATIONS, _GRIP_TURNS)
	gut.p("floppy grip square hit: peak %.2f px, broke=%s" % [square.drive_peak, square.broke])
	assert_false(field._break_edge >= 0, "a grazing grip on a floppy blade must not break")


## The owner's case: `(0 pivot)=(1 clamped grip)=(2)-(3)`, the plate placed so
## the grip's disc AND vertex 2 both reach it (40-60% of a spacing inward from
## 2's arc) — through the real resolve loop, so the armed break is consumed,
## the edge severed and vertex 2 coasts free, within a bounded number of
## samples of the first contact.
func test_the_owners_clamped_chain_breaks_on_a_plate_both_grip_and_two_reach() -> void:
	for inward in [0.4, 0.5, 0.6]:
		_owners_case(inward)


func _owners_case(inward: float) -> void:
	var spacing := 100.0
	var disc := 30.0  # big enough that both discs reach across the 40-60% band
	var positions: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in 4:
		positions.append(Vector2(float(i) * spacing, 0.0))
		radii.append(disc)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	var state := BladeState.build(positions, 0, edges, radii)
	ClampAddon.append_weld_braces(state, 1)
	var field := BladeObstacleField.new()
	var center := Vector2.from_angle(0.15 * TAU) * (2.0 - inward) * spacing
	field.add_zone(center, _BUNKER_RADIUS)
	state.obstacles = field
	var ctx := SwingContext.new()
	ctx.state = state
	ctx.drivers = [BladeArcDriver.new(1, Vector2.ZERO, spacing, 0.0, TAU, ctx.swing_duration)]
	ctx.world = CombatWorld.shadow()
	var run := SwingResolve.new(ctx)
	run.advance(0)
	var reach := _BUNKER_RADIUS + disc
	var first_contact := -1
	var samples: Array = run.result.trajectory.samples
	for k in samples.size():
		var pose: PackedVector2Array = samples[k]
		if pose[1].distance_to(center) < reach or pose[2].distance_to(center) < reach:
			first_contact = k
			break
	assert_gt(first_contact, 0, "inward %.1f: the blade must reach the plate" % inward)
	var severances: Array = run.result.live_gate.result.severances
	assert_false(severances.is_empty(), "inward %.1f: the jam must sever an edge" % inward)
	var freed_at := -1.0
	for sev in severances:
		if Array(sev.vertices).has(2):
			freed_at = sev.t
			break
	assert_gte(freed_at, 0.0, "inward %.1f: vertex 2 coasts free of the pivot after the break" % inward)
	if freed_at >= 0.0 and first_contact > 0:
		var after := int(round(freed_at / ctx.dt)) - first_contact
		assert_lt(after, _BREAK_WITHIN_SAMPLES,
				"inward %.1f: the break fires within the contact (%d samples after it)" % [inward, after])
	assert_eq(state.removed_vertices.size(), 0, "ADR 0005: a bunker never pops a vertex")
	ctx.world.free_shadow()


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
