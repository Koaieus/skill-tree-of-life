extends GutTest

## Regression guard for GraphProcgen's `_POISSON_AREA_PER_POINT` (#164,
## retuned in #566). The constant has exactly two failure directions and this
## file pins both:
##
##   - TOO SMALL → the disc can't hold `node_count`, the active list exhausts,
##     and the level author silently gets fewer nodes than they asked for.
##     Guarded by `test_auto_scaled_circle_fills_exactly_node_count`.
##   - TOO LARGE → the disc outlasts the `max_points` cap, so
##     `PoissonDiskSampler.sample` exits mid-flood. Because its active list is
##     drained in random order, the unplaced points strand in one contiguous
##     arc: #566's seed-dependent ragged rim. The count is still exactly
##     `node_count`, so ONLY the density test sees this.
##
## The predecessor's ±15% count tolerance is why #566 lived: at the old 1.80
## the count was always exact and the rim was gap-toothed in a quarter of the
## disc. `test_density_is_uniform_across_annuli` is the guard that actually
## fails there (ring means 1.13 centre / 0.86 rim vs 1.01 / 1.01 at 1.60) —
## if you retune the constant, confirm it goes RED at 1.80 before trusting it.
##
## #163's stamp radius↔node-count prediction reads the same constant (it
## predicts a count instead of resampling), so it rides on these too.

const _NODE_RADIUS := 32.0
const _NODE_PADDING := 14.0
const _TOLERANCE := 0.15  # ±15%, stamp-prediction tests only
## Rings x angular sectors for the density scan. 800 points over 60 cells
## leaves ~13 per cell — enough signal, few enough cells to stay fast.
const _RINGS := 5
const _SECTORS := 12


func _min_dist() -> float:
	return 2.0 * _NODE_RADIUS + _NODE_PADDING


## The disc must hold EXACTLY the requested count — not "within 15%". A
## shortfall of even one node means the author asked for N and got N-1 with
## no signal. Measured over 20 seeds x n in [150..3000], 1.60 never
## under-fills; 1.55 does (785/800), which is why it lost the #566 sweep
## despite scoring better on uniformity.
func test_auto_scaled_circle_fills_exactly_node_count() -> void:
	var min_dist := _min_dist()
	for node_count in [60, 300, 800, 1500]:
		var mask := CircularShapeMask.new()
		var area := GraphProcgen.target_area_for_node_count(node_count, min_dist)
		mask.size_for(area, min_dist * 4.0)

		for seed_i in 4:
			var rng := RandomNumberGenerator.new()
			rng.seed = 12345 + seed_i
			var points := PoissonDiskSampler.sample(mask, min_dist, node_count, [], rng)
			assert_eq(
				points.size(), node_count,
				"node_count=%d seed=%d: sampled %d — the disc must hold exactly the requested count (under = mask too small; over = sampler ignored max_points)"
					% [node_count, 12345 + seed_i, points.size()]
			)


## The #566 guard. A disc sized past its own capacity hits `max_points`
## mid-flood, and the random-order active list leaves the shortfall as one
## contiguous arc — invisible to any count assertion. Scan density over
## equal-area annuli x angular sectors: every cell should hold ~the same
## number of points. At the old 1.80 the centre ran 1.13x uniform and the rim
## 0.86x; at 1.60 both sit within 0.02 of 1.0.
func test_density_is_uniform_across_annuli() -> void:
	var min_dist := _min_dist()
	var node_count := 800
	var mask := CircularShapeMask.new()
	mask.size_for(GraphProcgen.target_area_for_node_count(node_count, min_dist), min_dist * 4.0)

	var seeds := 8
	var cells := PackedFloat32Array()
	cells.resize(_RINGS * _SECTORS)
	for seed_i in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4200 + seed_i
		for p in PoissonDiskSampler.sample(mask, min_dist, node_count, [], rng):
			# r² is the equal-area radial coordinate, so every ring holds the
			# same area and an even fill puts the same count in each.
			var ring := mini(_RINGS - 1, int(p.length_squared() / (mask.radius * mask.radius) * _RINGS))
			var sector := int(fposmod(p.angle(), TAU) / TAU * _SECTORS) % _SECTORS
			cells[ring * _SECTORS + sector] += 1.0

	var expected := float(node_count) / float(_RINGS * _SECTORS)
	for ring in _RINGS:
		var total := 0.0
		for sector in _SECTORS:
			total += cells[ring * _SECTORS + sector] / seeds
		var ratio := total / float(_SECTORS) / expected
		assert_almost_eq(
			ratio, 1.0, 0.06,
			"ring %d of %d holds %.2fx the uniform density — the sizing constant is off its measured capacity, so the Poisson flood is truncated by max_points and the shortfall stranded in one region (#566)"
				% [ring, _RINGS, ratio]
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
