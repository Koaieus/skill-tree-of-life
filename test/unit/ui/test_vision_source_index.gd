extends GutTest

## [VisionSourceIndex] exists purely to make `FogOverlay._apply_per_element_dimming`
## sub-quadratic. Its correctness claim is strong and worth pinning: the sources
## it culls are ones the smooth-min fold provably ignores, so the indexed
## darkness must equal the reference darkness *exactly*, not approximately.
##
## If this drifts, fog darkness on a node stops agreeing with the fog painted
## behind it — a node in the fade zone reads brighter or darker than its
## surroundings, with no error anywhere. See #133.

const _FOG_SCENE := preload("res://ui/fog_overlay/fog_overlay.tscn")

var _fog: FogOverlay


func before_each() -> void:
	_fog = _FOG_SCENE.instantiate()
	autofree(_fog)


func _source(pos: Vector2, radius: float, motion: float = 0.0) -> Dictionary:
	return {"pos": pos, "radius": radius, "motion": motion}


func _indexed_dark(world_pos: Vector2, sources: Array) -> float:
	var index := VisionSourceIndex.new()
	index.build(sources, _fog.union_smoothness)
	return _fog._dark_from_distances(index.distances_near(world_pos))


## Independent transcription of fog.gdshader's fragment fold: walk the `circles`
## uniform array front to back, smin-ing as you go. Deliberately does not reuse
## FogOverlay's helpers — that is the whole point.
func _shader_dark(world_pos: Vector2, sources: Array) -> float:
	var min_d := 1e9
	for s in sources:
		var d: float = world_pos.distance_to(s.pos) / maxf(s.radius, 1.0)
		var k: float = _fog.union_smoothness
		var h: float = clampf(0.5 + 0.5 * (d - min_d) / k, 0.0, 1.0)
		min_d = lerpf(d, min_d, h) - k * h * (1.0 - h)
	return smoothstep(1.0 - maxf(_fog.falloff, 1e-4), 1.0, min_d)


func test_empty_source_set_is_pitch_black() -> void:
	assert_eq(_indexed_dark(Vector2.ZERO, []), 1.0,
		"no vision sources → fully dark, same as the reference")


func test_query_far_outside_every_circle_is_pitch_black() -> void:
	# The 3x3 cell query finds nothing; the fold must not read that as "clear".
	var sources := [_source(Vector2.ZERO, 100.0)]
	assert_eq(_indexed_dark(Vector2(5000.0, 5000.0), sources), 1.0)


func test_zero_radius_source_does_not_poison_the_fold() -> void:
	# A degenerate radius divides by zero unless clamped, yielding NaN darkness.
	var sources := [_source(Vector2.ZERO, 0.0), _source(Vector2(50.0, 0.0), 100.0)]
	var dark := _indexed_dark(Vector2(50.0, 0.0), sources)
	assert_false(is_nan(dark), "darkness must never be NaN")
	assert_eq(dark, 0.0, "the real circle still clears its own centre")


func test_matches_reference_on_a_dense_random_field() -> void:
	# The whole point: culling changes no bit of the result.
	seed(0xF06)
	for trial in 40:
		var sources: Array = []
		for i in randi_range(1, 60):
			sources.append(_source(
				Vector2(randf_range(-600.0, 600.0), randf_range(-600.0, 600.0)),
				randf_range(40.0, 160.0)))
		for probe in 20:
			var p := Vector2(randf_range(-700.0, 700.0), randf_range(-700.0, 700.0))
			var reference: float = _fog._sample_dark(p, sources)
			var indexed: float = _indexed_dark(p, sources)
			assert_almost_eq(indexed, reference, 1e-6,
				"indexed darkness must equal the reference at %s over %d sources"
					% [p, sources.size()])


func test_matches_reference_when_radii_vary_wildly() -> void:
	# Reach is derived from the LARGEST radius. A tiny circle next to a huge one
	# must still be found, and the huge one must still reach distant queries.
	seed(0xBEEF)
	var sources := [
		_source(Vector2.ZERO, 800.0),
		_source(Vector2(30.0, 20.0), 5.0),
		_source(Vector2(-400.0, 300.0), 60.0),
	]
	for probe in 200:
		var p := Vector2(randf_range(-1200.0, 1200.0), randf_range(-1200.0, 1200.0))
		assert_almost_eq(_indexed_dark(p, sources), _fog._sample_dark(p, sources), 1e-6,
			"mixed-radius field disagrees at %s" % p)


func test_closest_motion_picks_the_nearest_source() -> void:
	var sources := [
		_source(Vector2(0.0, 0.0), 100.0, 0.25),
		_source(Vector2(120.0, 0.0), 100.0, 0.75),
	]
	var index := VisionSourceIndex.new()
	index.build(sources, _fog.union_smoothness)
	assert_eq(index.closest_motion(Vector2(10.0, 0.0)), 0.25, "nearest is the first source")
	assert_eq(index.closest_motion(Vector2(110.0, 0.0)), 0.75, "nearest is the second source")


func test_indexed_fold_stays_in_lockstep_with_the_shader() -> void:
	# THE invariant. `_apply_per_element_dimming` dims a node by the CPU fold
	# while the fragment shader paints the fog behind it with its own fold. If
	# the two disagree, the node reads brighter or darker than its surroundings
	# and nothing errors.
	#
	# field_smin is not associative, so this pins ORDER, not just membership:
	# folding the same sources by ascending distance instead of array order
	# drifts by up to 0.061 -- 15x a visible 8-bit alpha step.
	seed(0x5EA33)
	for trial in 30:
		var sources: Array = []
		for i in randi_range(2, 12):
			sources.append(_source(
				Vector2(randf_range(-250.0, 250.0), randf_range(-250.0, 250.0)),
				randf_range(80.0, 140.0)))
		for probe in 40:
			var p := Vector2(randf_range(-350.0, 350.0), randf_range(-350.0, 350.0))
			assert_almost_eq(_indexed_dark(p, sources), _shader_dark(p, sources), 1e-5,
				"CPU dimming must equal the shader's fold at %s" % p)
