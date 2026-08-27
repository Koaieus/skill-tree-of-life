extends GutTest

## #633 — BladeTrajectory.sample() was reading samples[k] as the pose at
## (k+1)*dt when BladeSim.simulate only ever appended the pose AFTER
## advancing the solver. Fixed by prepending the pre-step pose so
## samples[k] means "pose at simulated time k*dt", matching the array's own
## docstring. Exercises the fix against a BladeArcDriver, whose closed-form
## position is independently computable, so trajectory samples are checked
## against a hand-rolled reference rather than the sim's own internals.

const DT := 1.0 / 120.0
const DURATION := 0.3
const RADIUS := 100.0
const START_ANGLE := 0.0
const SWEEP := TAU

var _traj: BladeTrajectory


func before_each() -> void:
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(RADIUS, 0.0)]
	var radii: Array[float] = [10.0, 10.0]
	var state := BladeState.build(positions, 0, [], radii)
	var drivers: Array[BladeDriver] = [
		BladeArcDriver.new(1, Vector2.ZERO, RADIUS, START_ANGLE, SWEEP, DURATION)
	]
	_traj = BladeSim.simulate(state, drivers, DURATION, DT)


## Same ease curve as BladeArcDriver._sine_in_out, reproduced independently
## here so this doesn't just check the sim against its own driver code.
static func _eased_pos(t: float) -> Vector2:
	var f := clampf(t / DURATION, 0.0, 1.0)
	var eased := 0.5 - 0.5 * cos(PI * f)
	var angle := START_ANGLE + SWEEP * eased
	return Vector2.from_angle(angle) * RADIUS


func test_sample_zero_returns_the_initial_pose() -> void:
	var pos := _traj.sample(0.0)
	assert_almost_eq(pos[0].distance_to(Vector2.ZERO), 0.0, 0.001,
			"pivot starts at the origin")
	var expected := _eased_pos(0.0)
	assert_almost_eq(pos[1].distance_to(expected), 0.0, 0.001,
			"t=0 must be the pre-step pose, not one sim step in (#633)")


func test_sample_at_each_step_matches_hand_stepped_reference() -> void:
	var steps := _traj.samples.size() - 1
	assert_gt(steps, 0, "fixture must actually run some sim steps")
	for k in range(steps + 1):
		var t := float(k) * DT
		var expected := _eased_pos(t)
		# samples[k] is checked directly first — this is the exact invariant
		# BladeHitScan relies on (attack/melee/sim/blade_hit_scan.gd reads
		# samples[i] at t=i*dt with no interpolation at all).
		assert_almost_eq(_traj.samples[k][1].distance_to(expected), 0.0, 0.01,
				"samples[%d] must literally be the pose at simulated time t=%.5f" % [k, t])
		# sample(t) too — nudged a hair inside the [k, k+1) bin it indexes by,
		# so an fp hair on k*DT/DT can't floor into bin k-1. That divide is
		# unrelated to #633, which is about append ORDER, not this rounding.
		var probe_t := t if k == 0 else t + DT * 1e-6
		var actual := _traj.sample(probe_t)[1]
		assert_almost_eq(actual.distance_to(expected), 0.0, 0.01,
				"sample(%.6f) must be the pose at simulated time t=%.5f (k=%d)" % [probe_t, t, k])


func test_duration_matches_the_last_samples_true_time() -> void:
	var steps := _traj.samples.size() - 1
	assert_almost_eq(_traj.duration(), float(steps) * DT, 0.0001,
			"duration() must report the LAST sample's time, not samples.size()*dt (#633)")
	var at_dur := _traj.sample(_traj.duration())[1]
	var last := _traj.samples[_traj.samples.size() - 1][1]
	assert_almost_eq(at_dur.distance_to(last), 0.0, 0.001,
			"sample(duration()) must return the final sample")


## Mirrors BladeHitScan.scan's own loop shape (attack/melee/sim/blade_hit_scan.gd)
## so a hit stamped at t=i*dt reads the SAME pose sample() renders at that t —
## the acceptance-4 guarantee from #633 (hits and rendered positions agree).
func test_hit_scan_times_agree_with_rendered_positions() -> void:
	var samples := _traj.samples
	for i in range(1, samples.size()):
		var t := float(i) * DT
		var hit := BladeHitEvent.new(t, 1, -1, null)
		var rendered := _traj.sample(hit.t + DT * 1e-6)[1]
		var scanned := samples[i][1]
		assert_almost_eq(rendered.distance_to(scanned), 0.0, 0.01,
				"a hit stamped at t=%.5f must land where playback renders at that same t" % t)
