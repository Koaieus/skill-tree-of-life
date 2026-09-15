extends GutTest

## Pins [OverlayFieldCone.distance] — the closed form — against a brute-force
## `min` over `t`. The closed form is what the GLSL twin transcribes, so a
## wrong derivation here is a wrong shader with no other alarm.
##
## See #897 acceptance 1 / 1b and docs/domain/overlay-field-rendering.md.

const _STEPS := 2000  # brute-force resolution: dt = 5e-4
const _TOL := 1e-3


## d(p) = min over t in [0,1] of |p - c(t)| / r(t). The definition, sampled.
func _brute(p: Vector2, a: Vector2, ra: float, b: Vector2, rb: float) -> float:
	var best := INF
	for i in _STEPS + 1:
		var t := float(i) / float(_STEPS)
		var c := a.lerp(b, t)
		var r: float = lerpf(ra, rb, t)
		best = minf(best, p.distance_to(c) / r)
	return best


func test_closed_form_matches_brute_force_on_random_cones() -> void:
	seed(0xC04E)
	var worst := 0.0
	for _i in 400:
		var a := Vector2(randf_range(-200.0, 200.0), randf_range(-200.0, 200.0))
		var b := Vector2(randf_range(-200.0, 200.0), randf_range(-200.0, 200.0))
		var ra := randf_range(1.0, 60.0)
		var rb := randf_range(1.0, 60.0)
		var p := Vector2(randf_range(-300.0, 300.0), randf_range(-300.0, 300.0))
		var got := OverlayFieldCone.distance(p, a, ra, b, rb)
		var want := _brute(p, a, ra, b, rb)
		worst = maxf(worst, absf(got - want))
		assert_almost_eq(got, want, _TOL,
			"cone d(p) must equal min_t |p-c(t)|/r(t); a=%s ra=%f b=%s rb=%f p=%s" % [a, ra, b, rb, p])
		if worst > _TOL:
			return


## The nested case — one disc entirely inside the other — is where a naive
## "solve dh/dt = 0, clamp to [0,1]" is WRONG: the stationary point can sit on
## the far side of the pole `t = -ra/(rb-ra)`, so the clamp lands on the wrong
## endpoint. Hence the min against both ends in the closed form.
func test_closed_form_matches_brute_force_when_one_disc_contains_the_other() -> void:
	var cases := [
		[Vector2.ZERO, 10.0, Vector2(5.0, 0.0), 1.0, Vector2(20.0, 0.0)],
		[Vector2.ZERO, 10.0, Vector2(5.0, 0.0), 1.0, Vector2(-20.0, 3.0)],
		[Vector2.ZERO, 1.0, Vector2(2.0, 1.0), 40.0, Vector2(9.0, -30.0)],
		[Vector2.ZERO, 30.0, Vector2(1.0, 1.0), 2.0, Vector2(0.5, 0.5)],
	]
	for c in cases:
		var got := OverlayFieldCone.distance(c[4], c[0], c[1], c[2], c[3])
		var want := _brute(c[4], c[0], c[1], c[2], c[3])
		assert_almost_eq(got, want, _TOL, "nested case a=%s ra=%f b=%s rb=%f p=%s" % c)


func test_degenerate_endpoints_are_the_plain_disc_distance() -> void:
	seed(0xD15C)
	for _i in 50:
		var a := Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
		var r := randf_range(1.0, 40.0)
		var p := Vector2(randf_range(-100.0, 100.0), randf_range(-100.0, 100.0))
		assert_almost_eq(OverlayFieldCone.distance(p, a, r, a, r), p.distance_to(a) / r, 1e-6,
			"a == b && ra == rb must be exactly the disc field — every owned node ships as one")


func test_equal_radii_is_the_capsule_distance() -> void:
	var a := Vector2(-40.0, 0.0)
	var b := Vector2(40.0, 0.0)
	var r := 10.0
	# Broadside: perpendicular distance / r.
	assert_almost_eq(OverlayFieldCone.distance(Vector2(0.0, 25.0), a, r, b, r), 2.5, 1e-6,
		"ra == rb is a capsule: perpendicular distance / r")
	# Past the B cap: radial distance from b / r.
	assert_almost_eq(OverlayFieldCone.distance(Vector2(70.0, 0.0), a, r, b, r), 3.0, 1e-6,
		"beyond the cap the capsule is the end disc")


func test_beyond_the_a_side_tangent_point_it_is_the_a_disc_field() -> void:
	# p behind A along the axis: the argmin clamps to t = 0.
	var a := Vector2.ZERO
	var b := Vector2(100.0, 0.0)
	var p := Vector2(-40.0, 10.0)
	assert_almost_eq(OverlayFieldCone.distance(p, a, 12.0, b, 30.0), p.distance_to(a) / 12.0, 1e-6,
		"beyond the A-side tangent points the field is exactly |p - a| / ra")


## Owner decision 9 on #140: no Mach bands. A C1 break at the disc → tangent-line
## seam is exactly the crease `field_smin` exists to avoid, so the primitive
## itself must not introduce one.
func test_field_is_c1_across_the_tangent_seam() -> void:
	var a := Vector2.ZERO
	var b := Vector2(100.0, 0.0)
	var ra := 15.0
	var rb := 40.0
	var step := 0.05
	# A line sweeping past the A cap and along the tangent flank.
	var from := Vector2(-40.0, 26.0)
	var dir := Vector2(1.0, 0.0)
	var slopes: Array = []
	var saw_cap := false
	var saw_flank := false
	for i in 2000:
		var p: Vector2 = from + dir * (float(i) * step)
		var d0 := OverlayFieldCone.distance(p, a, ra, b, rb)
		var d1 := OverlayFieldCone.distance(p + dir * step, a, ra, b, rb)
		slopes.append((d1 - d0) / step)
		# Which branch is active: the cap branch means |p-a|/ra IS the value.
		if is_equal_approx(d0, p.distance_to(a) / ra):
			saw_cap = true
		else:
			saw_flank = true
	assert_true(saw_cap and saw_flank,
		"the sampled line must actually cross the seam, or this test passes vacuously")
	var worst := 0.0
	for i in range(1, slopes.size()):
		worst = maxf(worst, absf(slopes[i] - slopes[i - 1]))
	assert_lt(worst, 0.01,
		"d(p) must be C1 across the disc/tangent seam — a slope jump is a Mach band")
