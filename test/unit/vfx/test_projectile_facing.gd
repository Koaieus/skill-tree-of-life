extends GutTest

## #663. `face_velocity` snapped the rotation to the last frame's travel delta,
## which is right for a smooth path and wrong for a jagged one: [JitterPath] at a
## low `smoothing` is made of hard corners on purpose, so the delta lurches
## sideways for exactly one frame at each noise-segment boundary. An oriented
## visual reading that gets a stable heading punctuated by single-frame spins —
## a glitch, not an arc — which is what made
## [member BoltBody.stretch_along_velocity] unusable on the lightning family.
##
## What is pinned here is the RELATIONSHIP (a smoothed projectile turns less
## violently than a snapping one on the same path), never a particular angle:
## the path's noise is seeded off an arbitrary constant and the owner is free to
## retune amplitude, segments and smoothing.

const FRAME: float = 1.0 / 60.0
const ORIGIN := Vector2.ZERO
const TARGET := Vector2(320.0, 0.0)


func _jagged_path() -> JitterPath:
	var path := JitterPath.new()
	path.amplitude = 12.0
	path.smoothing = 0.1
	path.settle = 0.6
	# Fixed, so both projectiles in a comparison fly the identical squiggle.
	path.seed_source = 20260903
	return path


## Flies one projectile end to end and returns the absolute rotation change it
## made on each frame, in radians.
func _facing_deltas(smoothing_seconds: float) -> Array[float]:
	var proj := Projectile.new()
	proj.path = _jagged_path()
	proj.visual_scene = null
	proj.flight_time = 0.35
	proj.face_velocity = true
	proj.facing_smoothing_seconds = smoothing_seconds
	add_child_autofree(proj)
	proj.launch(ORIGIN, TARGET, 0.0)
	var deltas: Array[float] = []
	var previous: float = proj.rotation
	for _i in 40:
		proj._process(FRAME)
		deltas.append(absf(angle_difference(previous, proj.rotation)))
		previous = proj.rotation
	return deltas


func _sharpest(deltas: Array[float]) -> float:
	var worst: float = 0.0
	for d in deltas:
		worst = maxf(worst, d)
	return worst


func test_snapping_is_still_the_default() -> void:
	var proj := Projectile.new()
	add_child_autofree(proj)
	assert_almost_eq(proj.facing_smoothing_seconds, 0.0, 0.001,
			"every projectile that shipped before this snapped, and still does")


func test_a_jagged_path_makes_a_snapping_projectile_lurch() -> void:
	# The premise of the whole change. If this ever goes quiet the fix below is
	# solving a problem that no longer exists.
	# ~24 degrees at the shipped lightning tuning (amplitude 12, smoothing 0.1,
	# settle 0.6), measured 2026-09-03. Asserted well under that so a retune of
	# the squiggle does not turn this red, but above the couple of degrees a
	# smooth path produces — enough of a margin to mean something either way.
	var sharpest := _sharpest(_facing_deltas(0.0))
	assert_gt(sharpest, deg_to_rad(15.0),
			"a hard corner in the path throws the snapped facing well off the travel line")


func test_smoothing_spends_a_corner_over_several_frames() -> void:
	var snapped := _sharpest(_facing_deltas(0.0))
	var smoothed := _sharpest(_facing_deltas(0.08))
	assert_lt(smoothed, snapped,
			"the same corner on the same seeded squiggle turns less violently when smoothed")


func test_the_filter_seeds_from_the_first_heading_rather_than_easing_in() -> void:
	# Otherwise every smoothed projectile opens by swinging round from whatever
	# rotation the scene left on the node.
	var proj := Projectile.new()
	proj.path = _jagged_path()
	proj.flight_time = 0.35
	proj.face_velocity = true
	proj.facing_smoothing_seconds = 0.08
	proj.rotation = PI
	add_child_autofree(proj)
	proj.launch(ORIGIN, TARGET, 0.0)
	proj._process(FRAME)
	assert_lt(absf(angle_difference(0.0, proj.rotation)), deg_to_rad(60.0),
			"the first frame adopts the travel heading outright, not a blend with the authored PI")
