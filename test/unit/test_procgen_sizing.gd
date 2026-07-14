extends GutTest

## Regression guard for the Poisson auto-scale sizing constants in
## GraphProcgen (issue #164). If the packing-efficiency / safety-margin
## constants drift, this either overflows the shape (Poisson bails near the
## rim before reaching node_count) or undersizes it (active list exhausts
## early) — and #163's stamp radius↔node-count prediction depends on the
## ratio staying accurate, since stamps predict a count instead of resampling.

const _NODE_RADIUS := 32.0
const _NODE_PADDING := 14.0
const _TOLERANCE := 0.15  # ±15% of requested node_count


func _min_dist() -> float:
	return 2.0 * _NODE_RADIUS + _NODE_PADDING


func test_auto_scaled_circle_yields_expected_node_count() -> void:
	var min_dist := _min_dist()
	for node_count in [60, 300, 800, 1500]:
		var mask := CircularShapeMask.new()
		var area := GraphProcgen.target_area_for_node_count(node_count, min_dist)
		mask.size_for(area, min_dist * 4.0)

		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var points := PoissonDiskSampler.sample(mask, min_dist, node_count, [], rng)

		var lower := int(node_count * (1.0 - _TOLERANCE))
		assert_true(
			points.size() >= lower,
			"node_count=%d: sampled only %d points (< %d floor) — mask undersized or margin too tight"
				% [node_count, points.size(), lower]
		)
		assert_true(
			points.size() <= node_count,
			"node_count=%d: sampled %d points, exceeds requested max_points" % [node_count, points.size()]
		)


func test_target_area_and_node_count_round_trip() -> void:
	var min_dist := _min_dist()
	for node_count in [60, 300, 800, 1500]:
		var area := GraphProcgen.target_area_for_node_count(node_count, min_dist)
		var recovered := GraphProcgen.node_count_for_area(area, min_dist)
		assert_eq(recovered, node_count, "area→count inverse should recover the original node_count")


func test_node_count_for_radius_predicts_actual_stamp_yield() -> void:
	# Build one large auto-scaled circle (as GraphProcgen.generate would),
	# then check that node_count_for_radius's prediction for a smaller
	# concentric stamp radius is close to what's actually inside it — this is
	# the exact query #163 needs ("how many nodes does this stamp cover").
	var min_dist := _min_dist()
	var node_count := 1200
	var mask := CircularShapeMask.new()
	var area := GraphProcgen.target_area_for_node_count(node_count, min_dist)
	mask.size_for(area, min_dist * 4.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var points := PoissonDiskSampler.sample(mask, min_dist, node_count, [], rng)
	assert_gt(points.size(), 0, "sanity: sampler produced points")

	var stamp_radius := mask.radius * 0.5
	var predicted := GraphProcgen.node_count_for_radius(stamp_radius, min_dist)
	var actual := 0
	for p in points:
		if p.length() <= stamp_radius:
			actual += 1

	var lower := int(predicted * (1.0 - _TOLERANCE))
	var upper := int(predicted * (1.0 + _TOLERANCE))
	assert_true(
		actual >= lower and actual <= upper,
		"predicted %d nodes in stamp radius %.1f, actual %d — outside ±%d%% tolerance"
			% [predicted, stamp_radius, actual, int(_TOLERANCE * 100)]
	)
