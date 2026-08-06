extends GutTest

## Acceptance for #339 ② — PoissonDiskSampler must warn when an anchor
## silently fails to emit. Anchors are seeded first and respected during
## rejection, but nothing holds anchors apart from EACH OTHER (or the mask
## boundary), so a crowded anchor used to be dropped with no trace.

const _MIN_DIST := 100.0


func _mask() -> CircularShapeMask:
	var mask := CircularShapeMask.new()
	mask.size_for(GraphProcgen.target_area_for_node_count(8, _MIN_DIST), _MIN_DIST * 4.0)
	return mask


func test_crowded_anchor_drops_with_warning() -> void:
	var a1 := Vector2(0, 0)
	var a2 := a1 + Vector2(_MIN_DIST * 0.5, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var points := PoissonDiskSampler.sample(_mask(), _MIN_DIST, 8, [a1, a2], rng)

	assert_true(a1 in points, "first anchor must land")
	assert_false(a2 in points, "second anchor crowds the first — must be dropped")
	assert_push_warning("anchor at (%.1f, %.1f) failed to emit" % [a2.x, a2.y],
			"dropped anchor must be named in a warning")


func test_well_separated_anchors_all_land() -> void:
	var a1 := Vector2(0, 0)
	var a2 := a1 + Vector2(_MIN_DIST * 2.0, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var points := PoissonDiskSampler.sample(_mask(), _MIN_DIST, 8, [a1, a2], rng)

	assert_true(a1 in points, "first anchor must land")
	assert_true(a2 in points, "second anchor is beyond min_dist — must land too")


func test_anchor_outside_mask_warns() -> void:
	# Far outside the mask bounds: rejected by _grid_ok, still worth naming.
	var far := Vector2(99999, 99999)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var points := PoissonDiskSampler.sample(_mask(), _MIN_DIST, 8, [far], rng)

	assert_false(far in points, "outside-mask anchor must not land")
	assert_push_warning("anchor at (%.1f, %.1f) failed to emit" % [far.x, far.y])
