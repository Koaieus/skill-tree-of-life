extends GutTest

## #798 — the differential test between BladeSim's two backends.
##
## The tolerance is ZERO. The native solver is a literal transliteration:
## same expressions, same evaluation order, same real_t(float32) vs double
## split as the GDScript it mirrors, and no FMA contraction in the build
## flags. That makes exact equality achievable, and exact equality is the
## only threshold that keeps the two paths interchangeable downstream —
## BladeHitScan turns positions into a hit SET, so a 1e-7 drift near a
## shape boundary is not a small error, it is a different attack.
##
## If this ever goes red, do NOT widen it to approx: find which expression
## stopped matching (suspect -ffp-contract / -march, then a "harmless"
## refactor of one of the two loops).
##
## On a checkout with no built binary the whole file self-skips — that is
## the supported fallback state, not a failure.

const SPACING := 60.0
const DURATION := 0.4


func before_all() -> void:
	if not BladeSim.native_available():
		gut.p("BladeSolverNative not loaded — skipping parity (GDScript-only checkout).")


func after_each() -> void:
	BladeSim.use_native = true


func _chain(k: int) -> BladeState:
	var pos: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in k:
		pos.append(Vector2(float(i) * SPACING, 0.0))
		radii.append(20.0)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	return BladeState.build(pos, 0, edges, radii)


## Chain plus an i-2 brace — exercises constraint ordering, not just a line.
func _mesh(k: int) -> BladeState:
	var s := _chain(k)
	for i in range(2, k):
		s.edges.append(Vector2i(i - 2, i))
		var rest: float = s.positions[i - 2].distance_to(s.positions[i])
		s.constraints.append(BladeDistanceConstraint.new(i - 2, i, rest))
	return s


func _drivers(s: BladeState) -> Array[BladeDriver]:
	var d: Array[BladeDriver] = [
		BladeArcDriver.new(1, s.positions[0], SPACING, 0.0, TAU, DURATION)
	]
	return d


func _run(meshed: bool, native: bool, dur: float, dt: float, iters: int, vel_ref: float) -> Array:
	BladeSim.use_native = native
	var s: BladeState = _mesh(8) if meshed else _chain(8)
	var traj := BladeSim.simulate(s, _drivers(s), dur, dt, iters, vel_ref)
	return [traj, s]


func _assert_identical(
		label: String, meshed: bool, dt: float, iters: int, vel_ref: float,
		dur: float = DURATION) -> void:
	if not BladeSim.native_available():
		pass_test("%s: skipped, no native binary" % label)
		return
	var gd: Array = _run(meshed, false, dur, dt, iters, vel_ref)
	var nat: Array = _run(meshed, true, dur, dt, iters, vel_ref)
	var gd_traj: BladeTrajectory = gd[0]
	var nat_traj: BladeTrajectory = nat[0]

	assert_eq(nat_traj.sample_dt, gd_traj.sample_dt, "%s: sample_dt" % label)
	assert_eq(nat_traj.samples.size(), gd_traj.samples.size(), "%s: sample count" % label)
	if nat_traj.samples.size() != gd_traj.samples.size():
		return
	for k in gd_traj.samples.size():
		var a: PackedVector2Array = gd_traj.samples[k]
		var b: PackedVector2Array = nat_traj.samples[k]
		# Comparing the packed arrays whole is the strict check: PackedVector2Array
		# == is elementwise exact, so this catches a last-ulp difference.
		assert_eq(b, a, "%s: sample %d" % [label, k])
		if b != a:
			return

	# simulate() advances the BladeState in place; both backends must leave it
	# in the same place, or a caller that re-simulates from it diverges.
	var gd_state: BladeState = gd[1]
	var nat_state: BladeState = nat[1]
	assert_eq(nat_state.positions, gd_state.positions, "%s: state.positions" % label)
	assert_eq(nat_state.prev_positions, gd_state.prev_positions, "%s: state.prev_positions" % label)


func test_chain_matches_bit_for_bit() -> void:
	_assert_identical("chain", false, 1.0 / 120.0, 16, 0.0)


func test_mesh_matches_bit_for_bit() -> void:
	_assert_identical("mesh", true, 1.0 / 120.0, 16, 0.0)


func test_adaptive_iterations_match() -> void:
	# vel_ref > 0 makes the iteration count itself a computed float — the one
	# place a double/float slip would change the WORK done, not just the result.
	_assert_identical("adaptive", false, 1.0 / 120.0, 16, 400.0)


func test_coarse_ai_tier_matches() -> void:
	# The knobs AiBladeRollout's coarse pass actually uses.
	_assert_identical("coarse", false, 1.0 / 30.0, 4, 0.0)


func test_zero_duration_matches() -> void:
	# 0 steps: samples is just the pre-step pose, and prev_positions must be
	# the duplicate simulate() takes up front rather than anything stepped.
	_assert_identical("zero duration", false, 1.0 / 120.0, 16, 0.0, 0.0)


func test_custom_ease_falls_back_to_gdscript() -> void:
	# A non-default ease is outside the transliterated subset. The native path
	# must decline it (return null) rather than silently substitute sine-in-out.
	if not BladeSim.native_available():
		pass_test("skipped, no native binary")
		return
	var s := _chain(6)
	var linear := func(f: float) -> float: return f
	var drivers: Array[BladeDriver] = [
		BladeArcDriver.new(1, s.positions[0], SPACING, 0.0, TAU, DURATION, linear)
	]
	BladeSim.use_native = true
	var traj := BladeSim.simulate(s, drivers, DURATION)
	assert_not_null(traj, "custom ease still simulates")

	var s2 := _chain(6)
	var drivers2: Array[BladeDriver] = [
		BladeArcDriver.new(1, s2.positions[0], SPACING, 0.0, TAU, DURATION, linear)
	]
	BladeSim.use_native = false
	var traj2 := BladeSim.simulate(s2, drivers2, DURATION)
	assert_eq(traj.samples[-1], traj2.samples[-1],
			"custom-ease swing took the GDScript path either way")


func test_backend_reports_gdscript_when_forced() -> void:
	BladeSim.use_native = false
	assert_eq(BladeSim.backend(), &"gdscript", "forced backend is reported")
