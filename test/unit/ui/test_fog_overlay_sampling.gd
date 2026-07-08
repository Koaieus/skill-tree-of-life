extends GutTest

## [method FogOverlay._sample_dark] deliberately mirrors the darkness math in
## `fog.gdshader`, so a visible node sitting in the fade zone dims uniformly
## instead of being bisected by the per-fragment gradient. Nothing in the engine
## enforces that the two stay in lockstep — this pins the GDScript side's
## contract so a future shader edit that forgets its twin fails loudly here.
##
## The shader computes, per pixel:
##   min_d = smooth-union of (distance / radius) over all circles
##   dark  = smoothstep(1 - falloff, 1, min_d)

const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")

var _fog: FogOverlay


func before_each() -> void:
	_fog = _FOG_SCENE.instantiate()
	_fog.falloff = 0.25
	_fog.union_smoothness = 0.12
	add_child_autofree(_fog)
	await get_tree().process_frame


func _source(pos: Vector2, radius: float) -> Dictionary:
	return {"pos": pos, "radius": radius, "motion": 0.0}


func test_no_sources_is_pitch_black() -> void:
	assert_eq(_fog._sample_dark(Vector2.ZERO, []), 1.0,
		"nothing to see means fully dark")


func test_circle_centre_is_fully_clear() -> void:
	var s := [_source(Vector2.ZERO, 100.0)]
	assert_eq(_fog._sample_dark(Vector2.ZERO, s), 0.0)


func test_inside_the_clear_zone_is_fully_clear() -> void:
	# falloff 0.25 ⇒ the fade only starts at 0.75·r.
	var s := [_source(Vector2.ZERO, 100.0)]
	assert_eq(_fog._sample_dark(Vector2(70.0, 0.0), s), 0.0,
		"0.70·r is inside the clear zone")


func test_at_and_beyond_the_radius_is_fully_dark() -> void:
	var s := [_source(Vector2.ZERO, 100.0)]
	assert_eq(_fog._sample_dark(Vector2(100.0, 0.0), s), 1.0, "exactly at the edge")
	assert_eq(_fog._sample_dark(Vector2(400.0, 0.0), s), 1.0, "well beyond the edge")


func test_fade_zone_is_monotonic_and_strictly_between() -> void:
	var s := [_source(Vector2.ZERO, 100.0)]
	var previous := 0.0
	for x in range(76, 100):
		var dark: float = _fog._sample_dark(Vector2(float(x), 0.0), s)
		assert_gt(dark, previous, "darkness increases with distance at x=%d" % x)
		assert_lt(dark, 1.0, "still inside the radius at x=%d" % x)
		previous = dark


func test_single_source_smooth_union_is_exact() -> void:
	# smin against the 1e9 sentinel must return the sample untouched, otherwise
	# a lone circle's field would be biased inward.
	_fog.union_smoothness = 0.4
	var s := [_source(Vector2.ZERO, 100.0)]
	# d = 0.875 sits mid-fade; smoothstep(0.75, 1.0, 0.875) == 0.5.
	assert_almost_eq(_fog._sample_dark(Vector2(87.5, 0.0), s), 0.5, 0.001,
		"one circle's field is unaffected by the union")


func test_overlapping_sources_union_more_clearly_than_either_alone() -> void:
	# The smooth union must dip BELOW the hard nearest-distance at the seam —
	# that dip is what removes the crease that read as a Mach band.
	var a := _source(Vector2.ZERO, 100.0)
	var b := _source(Vector2(120.0, 0.0), 100.0)
	var seam := Vector2(60.0, 0.0)  # equidistant: d == 0.6 from both

	_fog.union_smoothness = 0.0
	var hard: float = _fog._sample_dark(seam, [a, b])
	_fog.union_smoothness = 0.3
	var smooth: float = _fog._sample_dark(seam, [a, b])

	assert_lt(smooth, hard + 0.0001, "the smooth union is never darker than min()")
	# Push the seam into the fade zone so the difference is observable.
	var far_seam := Vector2(60.0, 78.0)
	_fog.union_smoothness = 0.0
	var hard_far: float = _fog._sample_dark(far_seam, [a, b])
	_fog.union_smoothness = 0.3
	var smooth_far: float = _fog._sample_dark(far_seam, [a, b])
	assert_lt(smooth_far, hard_far,
		"at the seam inside the fade zone, smoothing strictly brightens")


func test_zero_falloff_is_a_hard_cut() -> void:
	_fog.falloff = 0.0
	_fog.union_smoothness = 0.0
	var s := [_source(Vector2.ZERO, 100.0)]
	assert_eq(_fog._sample_dark(Vector2(99.0, 0.0), s), 0.0, "clear right up to the edge")
	assert_eq(_fog._sample_dark(Vector2(101.0, 0.0), s), 1.0, "dark immediately past it")


func test_sample_never_produces_nan() -> void:
	# The smooth-min seeds from a finite sentinel; INF would give INF * 0 == NaN
	# on the first fold and silently poison every downstream modulate.
	var s := [_source(Vector2.ZERO, 100.0), _source(Vector2(50.0, 0.0), 80.0)]
	for x in range(-200, 200, 17):
		var dark: float = _fog._sample_dark(Vector2(float(x), 0.0), s)
		assert_false(is_nan(dark), "sample at x=%d is a real number" % x)
