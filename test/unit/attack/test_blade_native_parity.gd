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


# ── The defender half (#813) ──────────────────────────────────────────────────
# Since #811 a BladeSwingClock and a BladeObstacleField travel together and
# cover every swing near ANY defender, so these are not an edge case — they are
# most swings on a shipped map. Everything the pair MUTATES has to cross the
# boundary and come back: the clock's warp accumulator, the field's strain, its
# load-share bank and its armed break, plus one Bank per sample of each for the
# resolve loop's rewind. A backend that returned perfect positions and an empty
# `field.history` would pass every assertion in the first half of this file
# while silently un-arming every bunker break, which is why the cases below
# compare the BANKS bank-for-bank and not just the trajectory.

const _DEF_DURATION := 1.2
const _DEF_SPACING := 60.0
const _DEF_RADIUS := 24.0
const _ZONE_RADIUS := 32.0


## The straight arm test_bunker_deflect.gd uses, at radii the plate can meet.
func _arm(n: int) -> BladeState:
	var positions: Array[Vector2] = []
	var edges: Array[Vector2i] = []
	var radii: Array[float] = []
	for i in n:
		positions.append(Vector2(float(i) * _DEF_SPACING, 0.0))
		radii.append(_DEF_RADIUS)
		if i > 0:
			edges.append(Vector2i(i - 1, i))
	return BladeState.build(positions, 0, edges, radii)


## The same arm welded at every joint — the rigid body that JAMS on a plate
## instead of folding around it, which is the only thing that meters strain.
func _clamped_arm(n: int) -> BladeState:
	var s := _arm(n)
	for i in range(1, n - 1):
		ClampAddon.append_weld_braces(s, i)
	return s


func _arm_drivers(state: BladeState) -> Array[BladeDriver]:
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
				other, pivot, offset.length(), offset.angle(), TAU, _DEF_DURATION))
	return out


## One zone `turns` of a turn round the arc the tip sweeps — the placement
## `.claude/rules/melee-fixtures.md` insists on, read off the blade's own reach
## rather than off its rest span.
func _zone_on_arc(state: BladeState, turns: float, drag: float, deflect: bool,
		reach: float = 1.0) -> BladeObstacleField:
	var f := BladeObstacleField.new()
	var pivot := state.positions[state.pivot_index]
	var r := pivot.distance_to(state.positions[state.positions.size() - 1])
	f.add_defender_zone(pivot + Vector2.from_angle(turns * TAU) * (r * reach),
			_ZONE_RADIUS, drag, deflect)
	return f


## Build one defended run and step it on `native`. Returns the whole mutable
## world afterwards, because "identical" here means the accumulators too.
func _defended_run(native: bool, clamped: bool, k: int, turns: float,
		drag: float, deflect: bool, with_clock: bool, reach: float = 1.0,
		step_offset: int = 0, step_count: int = -1) -> Dictionary:
	BladeSim.use_native = native
	var s: BladeState = _clamped_arm(k) if clamped else _arm(k)
	var field := _zone_on_arc(s, turns, drag, deflect, reach)
	s.obstacles = field
	var clock: BladeSwingClock = BladeSwingClock.new(_DEF_DURATION) if with_clock else null
	var steps := step_count if step_count >= 0 else _steps(_DEF_DURATION)
	var traj := BladeSim.simulate_range(
			s, _arm_drivers(s), step_offset, steps, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	return {traj = traj, state = s, field = field, clock = clock}


func _assert_clock_banks(label: String, gd: BladeSwingClock, nat: BladeSwingClock) -> void:
	assert_eq(nat.history.size(), gd.history.size(), "%s: clock history length" % label)
	if nat.history.size() != gd.history.size():
		return
	for k in gd.history.size():
		var a: BladeSwingClock.Bank = gd.history[k]
		var b: BladeSwingClock.Bank = nat.history[k]
		assert_eq(b.f, a.f, "%s: clock bank %d f" % [label, k])
		assert_eq(b.drag, a.drag, "%s: clock bank %d drag" % [label, k])
		assert_eq(b.last_t, a.last_t, "%s: clock bank %d last_t" % [label, k])
		assert_eq(b.warping, a.warping, "%s: clock bank %d warping" % [label, k])
		assert_eq(b.stalled, a.stalled, "%s: clock bank %d stalled" % [label, k])
		# keys(), not the Dictionary: this pins the ORDER zones were banked in,
		# which is the first-wins tie-break BladeDefenderZones' stable-id
		# ordering exists to make reproducible.
		assert_eq(b.touched.keys(), a.touched.keys(), "%s: clock bank %d touched" % [label, k])


func _assert_field_banks(label: String, gd: BladeObstacleField, nat: BladeObstacleField) -> void:
	assert_eq(nat.history.size(), gd.history.size(), "%s: field history length" % label)
	if nat.history.size() != gd.history.size():
		return
	for k in gd.history.size():
		var a: BladeObstacleField.Bank = gd.history[k]
		var b: BladeObstacleField.Bank = nat.history[k]
		assert_eq(b.strain, a.strain, "%s: field bank %d strain" % [label, k])
		assert_eq(b.driven_last, a.driven_last, "%s: field bank %d driven_last" % [label, k])
		assert_eq(b.driven_last_target, a.driven_last_target,
				"%s: field bank %d driven_last_target" % [label, k])
		assert_eq(b.break_edge, a.break_edge, "%s: field bank %d break_edge" % [label, k])
		assert_eq(b.break_step, a.break_step, "%s: field bank %d break_step" % [label, k])
		assert_eq(b.break_zone, a.break_zone, "%s: field bank %d break_zone" % [label, k])
		assert_eq(b.current_step, a.current_step, "%s: field bank %d current_step" % [label, k])
		assert_eq(b.edge_residual.size(), a.edge_residual.size(),
				"%s: field bank %d residual zones" % [label, k])
		for z in mini(a.edge_residual.size(), b.edge_residual.size()):
			var ad: Dictionary = a.edge_residual[z]
			var bd: Dictionary = b.edge_residual[z]
			# Keys in order, then each load: `_pick_edge` sorts the keys, but a
			# load that landed on the wrong edge picks a different edge to break.
			assert_eq(bd.keys(), ad.keys(), "%s: bank %d zone %d residual keys" % [label, k, z])
			for e_idx in ad.keys():
				assert_eq(bd.get(e_idx), ad.get(e_idx),
						"%s: bank %d zone %d edge %s load" % [label, k, z, e_idx])


func _assert_defended_identical(label: String, clamped: bool, k: int, turns: float,
		drag: float, deflect: bool, with_clock: bool = true,
		reach: float = 1.0) -> void:
	if not BladeSim.native_available():
		pending("%s: no native binary in this checkout — parity unverified." % label)
		return
	_assert_worlds_identical(label,
			_defended_run(false, clamped, k, turns, drag, deflect, with_clock, reach),
			_defended_run(true, clamped, k, turns, drag, deflect, with_clock, reach),
			with_clock)


## Two stepped worlds — trajectory, state, clock, field, banks and the armed
## break — compared at zero tolerance. Split out of the case above so the
## multi-zone case below pins exactly the same surface rather than a subset.
func _assert_worlds_identical(label: String, gd: Dictionary, nat: Dictionary,
		with_clock: bool = true) -> void:
	var gd_traj: BladeTrajectory = gd.traj
	var nat_traj: BladeTrajectory = nat.traj
	assert_eq(nat_traj.samples.size(), gd_traj.samples.size(), "%s: sample count" % label)
	if nat_traj.samples.size() != gd_traj.samples.size():
		return
	for j in gd_traj.samples.size():
		assert_eq(nat_traj.samples[j], gd_traj.samples[j], "%s: sample %d" % [label, j])
		assert_eq(nat_traj.prev_samples[j], gd_traj.prev_samples[j],
				"%s: prev_sample %d" % [label, j])
		if nat_traj.samples[j] != gd_traj.samples[j]:
			return
	var gd_state: BladeState = gd.state
	var nat_state: BladeState = nat.state
	assert_eq(nat_state.positions, gd_state.positions, "%s: state.positions" % label)
	assert_eq(nat_state.prev_positions, gd_state.prev_positions, "%s: state.prev_positions" % label)
	assert_eq(nat_state.speed_history.size(), gd_state.speed_history.size(),
			"%s: speed_history length" % label)
	for j in mini(nat_state.speed_history.size(), gd_state.speed_history.size()):
		assert_eq(nat_state.speed_history[j], gd_state.speed_history[j],
				"%s: speed_history %d" % [label, j])
	if with_clock:
		_assert_clock_banks(label, gd.clock, nat.clock)
	_assert_field_banks(label, gd.field, nat.field)
	# consume_break() stays in GDScript on both paths; what #813 moved is which
	# backend ARMED it. Compare the landing, not just the accumulator.
	var gd_break: BladeObstacleField.Break = (gd.field as BladeObstacleField).consume_break()
	var nat_break: BladeObstacleField.Break = (nat.field as BladeObstacleField).consume_break()
	assert_eq(nat_break == null, gd_break == null, "%s: break armed-ness agrees" % label)
	if gd_break != null and nat_break != null:
		assert_eq(nat_break.edge_idx, gd_break.edge_idx, "%s: break edge" % label)
		assert_eq(nat_break.step, gd_break.step, "%s: break step" % label)


func test_a_dragged_swing_matches_bit_for_bit() -> void:
	# A wall: sensed, banked on the clock, never pushed out of. The clock's `_f`
	# then accumulates in float from the contact substep on, and every arc
	# driver reads it instead of `t / duration` — so this is the one case where
	# the two backends' DRIVERS disagree if the accumulation order slipped.
	_assert_defended_identical("wall drag", false, 4, 0.15, 1.5, false)


func test_an_undragged_clocked_swing_is_still_bit_inert() -> void:
	# The clock exists but its zone sits where the blade never goes, so it never
	# warps and `progress()` keeps declining to answer. #780's acceptance 5 is a
	# bit-exactness claim; it has to survive the backend split too.
	_assert_defended_identical("untouched wall", false, 4, 0.15, 1.5, false, true, 10.0)
	if not BladeSim.native_available():
		return
	var gd := _defended_run(false, false, 4, 0.15, 1.5, false, true, 10.0)
	assert_false((gd.clock as BladeSwingClock).is_warping(),
			"the fixture really is a wall the blade never reaches")


func test_a_plate_pushout_matches_bit_for_bit() -> void:
	# A plate: pushed out of every solver iteration, after the distance
	# constraints. A floppy arm folds around it and banks little.
	_assert_defended_identical("plate pushout", false, 4, 0.15, 0.0, true)


func test_the_strain_bank_and_break_arming_match() -> void:
	# A welded arm cannot fold, so the driver residual accumulates and an edge
	# breaks — the load share, `_pick_edge`'s ascending-keys tie-break and the
	# GLOBAL step the break is stamped with all cross the boundary here.
	_assert_defended_identical("clamped spine break", true, 4, 0.15, 0.0, true)
	if not BladeSim.native_available():
		return
	# Guards the guard: two backends that both armed NOTHING would agree.
	var nat := _defended_run(true, true, 4, 0.15, 0.0, true, true)
	assert_true((nat.field as BladeObstacleField)._break_edge >= 0,
			"the clamped-spine fixture really does arm a break on the native path")


func test_a_zone_that_is_both_wall_and_plate_matches() -> void:
	# One zone of two kinds, latched once (#811) — never disc + capsule, never
	# once per incident edge. The latch lives on the clock, so a native path
	# keeping a second one of its own would double the wall's drag while every
	# position assertion stayed green until the arc had visibly slowed.
	_assert_defended_identical("both kinds", true, 4, 0.15, 1.5, true)


func test_a_defended_chunked_run_equals_an_unchunked_one() -> void:
	# The #803 continuation, now carrying the clock's accumulator and the
	# field's banks across the boundary. A chunk that rebuilt either from
	# scratch would un-bank a wall's drag mid-swing and stop it sheltering what
	# is behind it — and nothing in the trajectory would say so until the second
	# half of the sweep drifted.
	if not BladeSim.native_available():
		pending("no native binary in this checkout — parity unverified.")
		return
	var total := _steps(_DEF_DURATION)
	var head_len := total / 2
	var whole := _defended_run(true, true, 4, 0.15, 1.5, true, true)

	BladeSim.use_native = true
	var s := _clamped_arm(4)
	var field := _zone_on_arc(s, 0.15, 1.5, true)
	s.obstacles = field
	var clock := BladeSwingClock.new(_DEF_DURATION)
	var drivers := _arm_drivers(s)
	var head := BladeSim.simulate_range(s, drivers, 0, head_len, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	var tail := BladeSim.simulate_range(s, drivers, head_len, total - head_len,
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, true, clock)

	var whole_traj: BladeTrajectory = whole.traj
	assert_eq(head.samples[0], whole_traj.samples[0], "chunked: head entry pose")
	for j in head.samples.size():
		assert_eq(head.samples[j], whole_traj.samples[j], "chunked: head sample %d" % j)
	for j in tail.samples.size():
		assert_eq(tail.samples[j], whole_traj.samples[head_len + j],
				"chunked: tail sample %d" % j)
	# The clock is sim state: a chunk boundary must not reset the accumulator.
	assert_eq(clock.drag, (whole.clock as BladeSwingClock).drag, "chunked: banked drag")
	assert_eq(clock.progress(), (whole.clock as BladeSwingClock).progress(),
			"chunked: warped progress")
	assert_eq(field._strain, (whole.field as BladeObstacleField)._strain, "chunked: strain")
	assert_eq(field._break_edge, (whole.field as BladeObstacleField)._break_edge,
			"chunked: armed break survives the boundary")
	# history is CHUNK-LOCAL and rebuilt per call, like speed_history (#803).
	assert_eq(tail.samples.size(), field.history.size(),
			"chunked: field history parallels the tail's samples")
	assert_eq(tail.samples.size(), clock.history.size(),
			"chunked: clock history parallels the tail's samples")


func test_a_traced_field_falls_back_to_gdscript() -> void:
	# `trace` is a diagnostic the classification test and the melee sandbox read,
	# and it is deliberately NOT transliterated — so a traced field must decline
	# the native path rather than silently return no rows.
	if not BladeSim.native_available():
		pending("no native binary in this checkout — fallback path unverified.")
		return
	BladeSim.use_native = true
	var s := _clamped_arm(4)
	var field := _zone_on_arc(s, 0.15, 0.0, true)
	field.trace = true
	s.obstacles = field
	var clock := BladeSwingClock.new(_DEF_DURATION)
	assert_null(BladeSim._simulate_native(s, _arm_drivers(s), 0, _steps(_DEF_DURATION),
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, 1.0, clock, field),
			"a traced field is outside the transliterated subset")
	BladeSim.simulate(s, _arm_drivers(s), _DEF_DURATION, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	assert_gt(field.trace_rows.size(), 0, "the GDScript path still produced trace rows")


func test_the_native_defender_path_actually_ran() -> void:
	# The counterpart of test_the_native_path_actually_ran, and it earns its
	# keep more: every defended case above would pass VACUOUSLY the moment
	# _simulate_native declined the fixture, comparing GDScript to GDScript.
	if not BladeSim.native_available():
		pending("no native binary in this checkout — parity unverified.")
		return
	assert_true(BladeSim._native_field,
			"the built binary has #813's simulate_range_field")
	BladeSim.use_native = true
	var s := _clamped_arm(4)
	var field := _zone_on_arc(s, 0.15, 1.5, true)
	s.obstacles = field
	var clock := BladeSwingClock.new(_DEF_DURATION)
	field.prepare(s, _arm_drivers(s), clock)
	s.prev_positions = s.positions.duplicate()
	var traj := BladeSim._simulate_native(s, _arm_drivers(s), 0, _steps(_DEF_DURATION),
			BladeSim.DEFAULT_DT, BladeSim.DEFAULT_ITERATIONS, 0.0,
			BladeSim.DEFAULT_SUBSTEPS, 1.0, clock, field)
	assert_not_null(traj, "a defended fixture is inside the native subset")
	if traj == null:
		return
	assert_gt(traj.samples.size(), 1, "the C++ loop emitted samples")
	# Every value the pair MUTATES came back — the #779 lesson, applied to the
	# fourteen new ones. A missing key is not an error on either side.
	assert_eq(clock.history.size(), traj.samples.size(), "clock history parallels samples")
	assert_eq(field.history.size(), traj.samples.size(), "field history parallels samples")
	assert_true(clock.is_warping(), "the C++ loop banked the wall's drag on the clock")
	assert_gt(clock.drag, 0.0, "drag crossed back")
	# max_strain() is 0 by the END of a swing that has flowed past the plate —
	# the accumulator resets the first substep nothing is near it. The history
	# is where the metering is visible, and the history is what the resolve
	# loop rewinds onto, so that is what this pins.
	var peak_strain := 0.0
	for b: BladeObstacleField.Bank in field.history:
		for v in b.strain:
			peak_strain = maxf(peak_strain, v)
	assert_gt(peak_strain, 0.0, "the strain the C++ metered crossed back")
	assert_true(field._break_edge >= 0, "the armed break crossed back")
	assert_gt(field.history.size(), 1, "the field banked once per sample")


# ── Multi-zone: where the ORDERING subtleties live ────────────────────────────
# Every case above authors ONE zone, and with one zone the two orderings the
# port's rule file warns about cannot arise at all. Both need a cluster:
#
#   - two particles banking onto the SAME edge in one substep, so the order the
#     contact dictionary is walked in IS the summation order of a shared float;
#   - a particle pushed by zone A and then by zone B, which keeps B's VALUE at
#     A's INSERTION POSITION — the exact behaviour a key-sorted map would get
#     wrong, and the reason `_contact_particles` is a godot Dictionary in the
#     C++ rather than a std::map.
#
# `test_blade_swing_drag.gd` (7 drag zones) and `test_bunker_deflect.gd` are
# multi-zone but assert qualitative thresholds, so they are not a substitute for
# a bank-for-bank comparison.


## The pose the blade really passes through at `frac` of the swing, on a FREE
## swing with no field — so the cluster below can be built on it and is
## guaranteed to be met, rather than placed on the rest span a whipped blade
## never reaches (`.claude/rules/melee-fixtures.md`).
func _probe_pose(clamped: bool, k: int, frac: float) -> PackedVector2Array:
	BladeSim.use_native = false
	var s: BladeState = _clamped_arm(k) if clamped else _arm(k)
	var traj := BladeSim.simulate(s, _arm_drivers(s), _DEF_DURATION, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true)
	return traj.samples[int(float(traj.samples.size() - 1) * frac)]


## Five zones straddling particles 2 and 3 at `pose`: two walls and three
## OVERLAPPING plates. The overlap is the point — one plate wide enough to hold
## both particles gives the shared-edge sum, and plates that overlap each other
## give a particle two zones in one iteration. The walls are in so the drag
## latch and the pushout share one walk over a zone list that is not all plates.
func _cluster_field(pose: PackedVector2Array) -> BladeObstacleField:
	var f := BladeObstacleField.new()
	var a := pose[2]
	var b := pose[3]
	f.add_defender_zone(a.lerp(b, -0.4), 30.0, 0.75, false)
	f.add_defender_zone(a, 30.0, 0.0, true)
	f.add_defender_zone(a.lerp(b, 0.5), 34.0, 0.0, true)
	f.add_defender_zone(b, 30.0, 0.0, true)
	f.add_defender_zone(b.lerp(a, -0.4), 30.0, 0.5, false)
	return f


func _cluster_run(native: bool, pose: PackedVector2Array) -> Dictionary:
	BladeSim.use_native = native
	var s := _clamped_arm(4)
	var field := _cluster_field(pose)
	s.obstacles = field
	var clock := BladeSwingClock.new(_DEF_DURATION)
	var traj := BladeSim.simulate(s, _arm_drivers(s), _DEF_DURATION, BladeSim.DEFAULT_DT,
			BladeSim.DEFAULT_ITERATIONS, 0.0, BladeSim.DEFAULT_SUBSTEPS, true, clock)
	return {traj = traj, state = s, field = field, clock = clock}


## `project()`'s own contact band. Deliberately the HYSTERESIS bound and not the
## bare pushout bound: the pushout ends every iteration with the vertex sitting
## AT `zr + pr - CONTACT_SLOP`, so a sample pose is never strictly inside it and
## a stricter test here would report "no contact" on a blade visibly jammed.
func _in_contact_band(p: Vector2, pr: float, c: Vector2, zr: float) -> bool:
	return p.distance_to(c) < zr + pr - BladeObstacleField.CONTACT_SLOP \
			+ BladeObstacleField.CONTACT_HYSTERESIS


func test_a_multi_zone_cluster_matches_bit_for_bit() -> void:
	if not BladeSim.native_available():
		pending("no native binary in this checkout — parity unverified.")
		return
	var pose := _probe_pose(true, 4, 0.2)
	_assert_worlds_identical("zone cluster",
			_cluster_run(false, pose), _cluster_run(true, pose))


func test_the_cluster_really_produces_both_contact_orderings() -> void:
	# Guards the guard. The case above would agree perfectly on a cluster the
	# blade merely flew past, and then it would pin nothing that a single zone
	# does not already pin. This asserts the two structural preconditions that
	# make the orderings reachable, read off the trajectory the fixture actually
	# produced: an edge with BOTH endpoints in one plate's contact band, and a
	# particle in two plates' bands at once. (Sample granularity, not substep — evidence
	# the geometry is there, not a proof of the substep it happened on.)
	var nat := _cluster_run(BladeSim.native_available(), _probe_pose(true, 4, 0.2))
	var traj: BladeTrajectory = nat.traj
	var state: BladeState = nat.state
	var field: BladeObstacleField = nat.field
	var shared_edge := false
	var double_covered := false
	for sample: PackedVector2Array in traj.samples:
		for i in sample.size():
			var covering := 0
			for z in field.zones.size():
				if not field.zones.deflects_at(z):
					continue
				if _in_contact_band(sample[i], state.radii[i], field.zones.centers[z], field.zones.radii[z]):
					covering += 1
			if covering >= 2:
				double_covered = true
		for z in field.zones.size():
			if not field.zones.deflects_at(z):
				continue
			var c: Vector2 = field.zones.centers[z]
			var zr: float = field.zones.radii[z]
			for e in state.edges:
				if _in_contact_band(sample[e.x], state.radii[e.x], c, zr) \
						and _in_contact_band(sample[e.y], state.radii[e.y], c, zr):
					shared_edge = true
	assert_true(shared_edge,
			"an edge has both endpoints in one plate's contact band, so two particles bank onto it")
	assert_true(double_covered,
			"a particle sits in two plates' bands at once, so its contact zone is overwritten")
	assert_gt(field.zones.size(), 1, "the cluster really is multi-zone")
	assert_gt((nat.clock as BladeSwingClock).touched.size(), 0,
			"a wall banked its drag, so the pushout and the latch shared one walk")
	# Two plates metering in the SAME swing is what makes the per-zone banks
	# distinguishable — one plate would agree no matter how the zone loop is
	# ordered. (Not both walls: the first one's drag warps the clock, so the
	# swing may legitimately never reach the second.)
	var metering := 0
	for b: BladeObstacleField.Bank in field.history:
		var live := 0
		for d: Dictionary in b.edge_residual:
			if not d.is_empty():
				live += 1
		metering = maxi(metering, live)
	assert_gt(metering, 1, "more than one plate banked load in the same swing")
