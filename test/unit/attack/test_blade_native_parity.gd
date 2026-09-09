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
## On a checkout with no built binary every case reports PENDING, not pass.
## That state is supported — the game runs fine on the GDScript solver — but a
## vacuous parity run must be VISIBLE in the suite verdict, or "green" here
## means nothing on the machines that never ran `scons`.

const SPACING := 60.0
const DURATION := 0.4


func before_all() -> void:
	if not BladeSim.native_available():
		gut.p("BladeSolverNative not loaded — parity cases report PENDING "
				+ "(GDScript-only checkout; `mise run native:build` to verify).")


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


func _run(meshed: bool, native: bool, dur: float, dt: float, iters: int, vel_ref: float,
		substeps: int, length_scaling: bool, k: int) -> Array:
	BladeSim.use_native = native
	var s: BladeState = _mesh(k) if meshed else _chain(k)
	var traj := BladeSim.simulate(
			s, _drivers(s), dur, dt, iters, vel_ref, substeps, length_scaling)
	return [traj, s]


## Every knob simulate() has, defaulted to the SHIPPED values — substeps=4 and
## length scaling on (#790) — so a case that names nothing extra is still
## exercising the real gameplay configuration, not a pre-#790 one.
func _assert_identical(
		label: String, meshed: bool, dt: float, iters: int, vel_ref: float,
		dur: float = DURATION,
		substeps: int = BladeSim.DEFAULT_SUBSTEPS,
		length_scaling: bool = true,
		blade_k: int = 8) -> void:
	if not BladeSim.native_available():
		pending("%s: no native binary in this checkout — parity unverified. "
				% label + "Build it with `mise run native:build`.")
		return
	var gd: Array = _run(meshed, false, dur, dt, iters, vel_ref, substeps, length_scaling, blade_k)
	var nat: Array = _run(meshed, true, dur, dt, iters, vel_ref, substeps, length_scaling, blade_k)
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

	# prev_samples (#803) is what a severance rewinds onto — a mid-sample pose
	# `_step` rewrote per SUBSTEP, so it is not derivable from `samples` and a
	# backend that got it wrong would start every re-baked tail from a lie
	# while every assertion above stayed green.
	assert_eq(nat_traj.prev_samples.size(), nat_traj.samples.size(),
			"%s: prev_samples parallels samples" % label)
	assert_eq(nat_traj.prev_samples.size(), gd_traj.prev_samples.size(),
			"%s: prev_samples length" % label)
	if nat_traj.prev_samples.size() != gd_traj.prev_samples.size():
		return
	for k3 in gd_traj.prev_samples.size():
		var pa: PackedVector2Array = gd_traj.prev_samples[k3]
		var pb: PackedVector2Array = nat_traj.prev_samples[k3]
		assert_eq(pb, pa, "%s: prev_sample %d" % [label, k3])
		if pb != pa:
			return

	# simulate() advances the BladeState in place; both backends must leave it
	# in the same place, or a caller that re-simulates from it diverges.
	var gd_state: BladeState = gd[1]
	var nat_state: BladeState = nat[1]
	assert_eq(nat_state.positions, gd_state.positions, "%s: state.positions" % label)
	assert_eq(nat_state.prev_positions, gd_state.prev_positions, "%s: state.prev_positions" % label)

	# speed_history (#779) is what speed-scaled damage reads. A backend that
	# returned correct positions and an EMPTY history would pass every
	# assertion above while silently zeroing blade damage, so it is pinned
	# here with the same zero tolerance — including its length, which must
	# parallel samples one-for-one.
	assert_eq(nat_state.speed_history.size(), gd_state.speed_history.size(),
			"%s: speed_history length" % label)
	assert_eq(nat_state.speed_history.size(), nat_traj.samples.size(),
			"%s: speed_history parallels samples" % label)
	if nat_state.speed_history.size() != gd_state.speed_history.size():
		return
	for k2 in gd_state.speed_history.size():
		var sa: PackedFloat32Array = gd_state.speed_history[k2]
		var sb: PackedFloat32Array = nat_state.speed_history[k2]
		assert_eq(sb, sa, "%s: speed_history %d" % [label, k2])
		if sb != sa:
			return


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


func test_substepped_run_matches() -> void:
	# The #790 substep loop: `base_iterations` sweeps SPLIT across `substeps`
	# physics steps at dt/substeps, one sample emitted per dt regardless. Get
	# the split, the sub_dt, or the sample cadence wrong in C++ and only this
	# case notices — a substeps=1 run would stay green throughout.
	_assert_identical("substepped x8", false, 1.0 / 120.0, 16, 0.0, DURATION, 8)


func test_single_substep_matches() -> void:
	# The other end of the same knob, and the pre-#790 shape.
	_assert_identical("substeps=1", false, 1.0 / 120.0, 16, 0.0, DURATION, 1)


func test_substeps_and_adaptive_iterations_compose() -> void:
	# Both budget axes at once: the velocity term is computed per SUBSTEP off
	# that substep's max speed, then divided by the interval's substep count.
	_assert_identical("substepped adaptive", true, 1.0 / 120.0, 16, 400.0, DURATION, 4)


func test_length_scaling_off_matches() -> void:
	# length_factor = 1.0 exactly, rather than the ~1.32 a k=8 chain earns.
	_assert_identical("length off", false, 1.0 / 120.0, 16, 0.0, DURATION,
			BladeSim.DEFAULT_SUBSTEPS, false)


func test_long_blade_past_the_length_ceiling_matches() -> void:
	# A k=48 chain has pivot eccentricity 47, past LENGTH_ECC_CEILING (40) — so
	# length_factor is clamped. The native path takes the factor precomputed,
	# and this pins that the clamped value crosses the boundary intact.
	_assert_identical("k=48 clamped", false, 1.0 / 120.0, 16, 0.0, DURATION,
			BladeSim.DEFAULT_SUBSTEPS, true, 48)


func test_speed_history_is_not_all_zero() -> void:
	# Guards the guard: every speed_history assertion above compares two
	# arrays, so two backends that both returned zeros would agree perfectly.
	# A driven blade MUST be moving.
	if not BladeSim.native_available():
		pending("no native binary in this checkout — parity unverified.")
		return
	var nat: Array = _run(false, true, DURATION, 1.0 / 120.0, 16, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, true, 8)
	var st: BladeState = nat[1]
	assert_gt(st.speed_history.size(), 1, "history has stepped samples")
	var peak := 0.0
	for h: PackedFloat32Array in st.speed_history:
		for v in h:
			peak = maxf(peak, v)
	assert_gt(peak, 1.0, "native backend reports real particle speeds")
	# Sample 0 is the pre-step pose: zero for every particle, by contract.
	var first: PackedFloat32Array = st.speed_history[0]
	for v in first:
		assert_eq(v, 0.0, "speed_history[0] is all zero")


func test_custom_ease_falls_back_to_gdscript() -> void:
	# A non-default ease is outside the transliterated subset. The native path
	# must decline it (return null) rather than silently substitute sine-in-out.
	if not BladeSim.native_available():
		pending("no native binary in this checkout — fallback path unverified.")
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


func test_the_native_path_actually_ran() -> void:
	# Every parity case above would pass VACUOUSLY if _simulate_native quietly
	# returned null for a canonical state — both sides would just be GDScript.
	# Pin that the canonical fixture is inside the transliterated subset, so
	# "identical" means "the C++ produced it".
	if not BladeSim.native_available():
		pending("no native binary in this checkout — parity unverified.")
		return
	assert_eq(BladeSim.backend(), &"native", "native is the selected backend")
	var s := _chain(8)
	s.prev_positions = s.positions.duplicate()
	var traj := BladeSim._simulate_native(
			s, _drivers(s), 0, _steps(DURATION), 1.0 / 120.0, 16, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, 1.4)
	assert_not_null(traj, "the canonical fixture is inside the native subset")
	if traj == null:
		return
	assert_gt(traj.samples.size(), 1, "the C++ loop emitted samples")
	assert_eq(s.speed_history.size(), traj.samples.size(),
			"the C++ loop wrote a parallel speed_history")
	assert_eq(traj.prev_samples.size(), traj.samples.size(),
			"the C++ loop wrote a parallel prev_samples")


# ── #803: continuation ─────────────────────────────────────────────────────
#
# Every case below that continues a run does so through `_simulate_native`
# DIRECTLY for the native arm, never through `simulate_range`: before #803 the
# range call fell back to GDScript for any continued or damped chunk, so a case
# written against it would have compared GDScript to GDScript and passed
# vacuously. `_simulate_native` returning null is a failure here, not a fallback.


static func _steps(dur: float, dt: float = 1.0 / 120.0) -> int:
	return int(ceil(dur / dt))


## The native tail of a split run, or null if the C++ declined the state.
func _native_tail(s: BladeState, d: Array[BladeDriver], offset: int, count: int,
		dt: float = 1.0 / 120.0) -> BladeTrajectory:
	return BladeSim._simulate_native(
			s, d, offset, count, dt, 16, 0.0, BladeSim.DEFAULT_SUBSTEPS,
			BladeSim._length_factor(s.pivot_eccentricity()))


## `a`'s local sample `j` equals `b`'s global sample `offset + j` — samples,
## prev_samples and the state's speed_history alike, bit for bit. The speed
## comparison starts at local sample 1: `speed_history[0]` is all-zero for
## every chunk BY CONTRACT (nothing has stepped yet in this call), so a
## continued chunk's [0] never equals the unbroken run's speeds at the cut.
func _assert_tail_matches(a: BladeTrajectory, a_state: BladeState,
		b: BladeTrajectory, b_state: BladeState, offset: int, what: String) -> void:
	assert_eq(a.samples.size() + offset, b.samples.size(), "%s: covers the rest" % what)
	if a.samples.size() + offset != b.samples.size():
		return
	for j in a.samples.size():
		assert_eq(a.samples[j], b.samples[offset + j], "%s: sample %d" % [what, offset + j])
		assert_eq(a.prev_samples[j], b.prev_samples[offset + j],
				"%s: prev_sample %d" % [what, offset + j])
		if j > 0:
			assert_eq(a_state.speed_history[j], b_state.speed_history[offset + j],
					"%s: speed %d" % [what, offset + j])
		if a.samples[j] != b.samples[offset + j]:
			return


## Parity case 1: chunked == unchunked, on the native backend — the trap the
## issue names. Time inside the C++ chunk must be `(step_offset + s) * dt` with
## an INTEGER offset; a float `t_start` carried across the boundary drifts in
## the last bits and this is what says so.
func test_a_chunked_native_run_is_bit_identical_to_an_unchunked_one() -> void:
	if not BladeSim.native_available():
		pending("no native binary in this checkout — continuation parity unverified.")
		return
	var steps := _steps(DURATION)
	var cut := steps / 3
	BladeSim.use_native = true
	var whole_state := _chain(8)
	var whole := BladeSim.simulate(whole_state, _drivers(whole_state), DURATION)
	var whole_speeds := whole_state.speed_history

	var s := _chain(8)
	var d := _drivers(s)
	var head := BladeSim.simulate_range(s, d, 0, cut)
	for j in head.samples.size():
		assert_eq(head.samples[j], whole.samples[j], "head sample %d" % j)
	var tail := _native_tail(s, d, cut, steps - cut)
	assert_not_null(tail, "the C++ accepted a continued chunk")
	if tail == null:
		return
	whole_state.speed_history = whole_speeds
	_assert_tail_matches(tail, s, whole, whole_state, cut, "native tail")

	# And the same split on GDScript lands on the same bits, so the two
	# backends agree on a CHUNKED run, not only on a whole one.
	BladeSim.use_native = false
	var g := _chain(8)
	var gd := _drivers(g)
	BladeSim.simulate_range(g, gd, 0, cut)
	var g_tail := BladeSim.simulate_range(g, gd, cut, steps - cut)
	_assert_tail_matches(g_tail, g, whole, whole_state, cut, "gdscript tail")


## Parity case 2: per-particle damping — a coasting set behind a dead vertex,
## exactly what a severance writes — agrees bit for bit, and so does a uniform
## array (every particle damped alike). Guarded against vacuity: the damped
## tail must DIFFER from the undamped one, or two zeros would agree perfectly.
func test_per_particle_and_uniform_damping_match_bit_for_bit() -> void:
	if not BladeSim.native_available():
		pending("no native binary in this checkout — damping parity unverified.")
		return
	var steps := _steps(DURATION)
	var cut := 20
	for uniform in [false, true]:
		var label := "uniform" if uniform else "per-particle"
		var undamped: BladeTrajectory = null
		var tails: Array[BladeTrajectory] = []
		var states: Array[BladeState] = []
		for native in [true, false]:
			BladeSim.use_native = native
			var s := _chain(8)
			var d := _drivers(s)
			BladeSim.simulate_range(s, d, 0, cut)
			if uniform:
				for i in s.positions.size():
					s.set_damping(i, BladeState.SEVERED_DRAG)
			else:
				# A severance at vertex 3: corpse frozen, 4..7 coast with drag.
				s.remove_vertex(3)
				for i in range(4, s.positions.size()):
					s.set_damping(i, BladeState.SEVERED_DRAG)
			var tail: BladeTrajectory = _native_tail(s, d, cut, steps - cut) if native \
					else BladeSim.simulate_range(s, d, cut, steps - cut)
			assert_not_null(tail, "%s: the C++ accepted a damped chunk" % label)
			if tail == null:
				return
			tails.append(tail)
			states.append(s)
			if not native:
				# The vacuity guard, on the GDScript arm: same head, same
				# topology, no damping array.
				var u := _chain(8)
				var ud := _drivers(u)
				BladeSim.simulate_range(u, ud, 0, cut)
				if not uniform:
					u.remove_vertex(3)
				undamped = BladeSim.simulate_range(u, ud, cut, steps - cut)
		_assert_tail_matches(tails[0], states[0], tails[1], states[1], 0, label)
		assert_ne(tails[1].samples[-1], undamped.samples[-1],
				"%s: the drag actually bled something" % label)


## Parity case 2b: an all-zero array is bit-identical to no array at all on the
## NATIVE backend too. `1.0 - 0.0 * dt` is exactly 1.0 and `v * 1.0` is `v`, so
## the multiply the array switches on must be a no-op per particle, not merely
## close — or every unsevered swing would diverge the moment the member existed.
func test_all_zero_damping_is_bit_identical_to_none_on_native() -> void:
	if not BladeSim.native_available():
		pending("no native binary in this checkout — damping parity unverified.")
		return
	var steps := _steps(DURATION)
	# Calling the native path directly skips simulate_range's step-0 reset of
	# the Verlet history, so seed it at rest here — the same thing.
	var bare := _chain(8)
	var bare_d := _drivers(bare)
	bare.prev_positions = bare.positions.duplicate()
	var bare_traj := _native_tail(bare, bare_d, 0, steps)
	var zero := _chain(8)
	var zero_d := _drivers(zero)
	zero.prev_positions = zero.positions.duplicate()
	zero.damping.resize(zero.positions.size())
	var zero_traj := _native_tail(zero, zero_d, 0, steps)
	assert_not_null(bare_traj, "bare native run")
	assert_not_null(zero_traj, "zero-damped native run")
	if bare_traj == null or zero_traj == null:
		return
	_assert_tail_matches(zero_traj, zero, bare_traj, bare, 0, "zero damping")


## Parity case 3: a continuation SEEDED from `prev_samples` — a fresh state
## given `samples[k]` and `prev_samples[k]` off a finished bake, which is how
## `MeleeAttackPlan.resolve_against` lands on a severance sample — equals the
## run that never stopped. Both backends; this is the read that replaced the
## head replay.
func test_a_continuation_seeded_from_prev_samples_equals_one_that_never_stopped() -> void:
	if not BladeSim.native_available():
		pending("no native binary in this checkout — continuation parity unverified.")
		return
	var steps := _steps(DURATION)
	var k := 37
	BladeSim.use_native = true
	var whole_state := _chain(8)
	var whole := BladeSim.simulate(whole_state, _drivers(whole_state), DURATION)
	var whole_speeds := whole_state.speed_history
	for native in [true, false]:
		BladeSim.use_native = native
		var s := _chain(8)
		var d := _drivers(s)
		s.positions = whole.samples[k].duplicate()
		s.prev_positions = whole.prev_samples[k].duplicate()
		var tail: BladeTrajectory = _native_tail(s, d, k, steps - k) if native \
				else BladeSim.simulate_range(s, d, k, steps - k)
		assert_not_null(tail, "seeded continuation ran")
		if tail == null:
			return
		whole_state.speed_history = whole_speeds
		_assert_tail_matches(tail, s, whole, whole_state, k,
				"seeded %s" % ("native" if native else "gdscript"))


func test_backend_reports_gdscript_when_forced() -> void:
	BladeSim.use_native = false
	assert_eq(BladeSim.backend(), &"gdscript", "forced backend is reported")
