extends GutTest

## Measures whether switching the fragment shader's traversal from "global
## circle-index order" (today) to "3x3 tile-gather order" (the #177 tiled
## design) changes the `field_smin` fold's numeric result.
##
## field_smin is NOT associative (overlay-field-rendering.md), so any reorder
## is a candidate for drift. This is deliberately independent of both
## FogOverlay and any CircleTileIndex implementation: it hand-builds the same
## grid VisionSourceIndex already uses (cell size = reach) and buckets
## sources into it in global-index order, mirroring how a tile index would be
## built. It then compares two folds over the SAME reachable subset:
##
##   - global order: ascending source index (today's shader / array order)
##   - tile order: concatenate the 3x3 neighbourhood's per-cell buckets in
##     (dx, dy) scan order — what a tiled shader reading its own neighbourhood
##     would see
##
## Existing tests (test_vision_source_index.gd) already pin that CPU and GPU
## agree with EACH OTHER once both use the same order; this test is the
## orthogonal question: does the new order differ numerically from the OLD
## order, i.e. is "bit-identical to today" (the issue's framing) actually true.

const _K := 0.12  # union_smoothness, matches FogOverlay's default


func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return min(a, b)
	var h: float = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerp(b, a, h) - k * h * (1.0 - h)


func _fold(distances: Array) -> float:
	var min_d: float = 1e9
	for d in distances:
		min_d = _smin(min_d, d, _K)
	return min_d


## Global-index-order fold, restricted to the reachable subset (matches
## today's shader/array traversal exactly per VisionSourceIndex's erasure proof).
func _global_order_fold(world_pos: Vector2, sources: Array, reach: float) -> float:
	var ds: Array = []
	for s in sources:
		var d: float = world_pos.distance_to(s.pos) / maxf(s.radius, 1.0)
		if world_pos.distance_to(s.pos) <= reach:
			ds.append(d)
	return _fold(ds)


## Tile-gather-order fold: bucket sources into cells (cell size = reach) in
## global-index order, then visit the query point's 3x3 neighbourhood in
## (dx, dy) scan order, concatenating each cell's bucket as encountered.
func _tile_order_fold(world_pos: Vector2, sources: Array, reach: float) -> float:
	var cells: Dictionary = {}
	for i in sources.size():
		var s = sources[i]
		var cell := Vector2i(floori(s.pos.x / reach), floori(s.pos.y / reach))
		if not cells.has(cell):
			cells[cell] = []
		(cells[cell] as Array).append(i)

	var centre := Vector2i(floori(world_pos.x / reach), floori(world_pos.y / reach))
	var ds: Array = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var bucket: Array = cells.get(centre + Vector2i(dx, dy), [])
			for i in bucket:
				var s = sources[i]
				if world_pos.distance_to(s.pos) <= reach:
					ds.append(world_pos.distance_to(s.pos) / maxf(s.radius, 1.0))
	return _fold(ds)


func test_measure_max_drift_between_global_and_tile_gather_order() -> void:
	seed(0xC0FFEE)
	var max_drift := 0.0
	var max_drift_at := Vector2.ZERO
	var trials := 0
	for trial in 200:
		var sources: Array = []
		var max_radius := 0.0
		for i in randi_range(3, 40):
			var r: float = randf_range(40.0, 160.0)
			max_radius = maxf(max_radius, r)
			sources.append({
				"pos": Vector2(randf_range(-600.0, 600.0), randf_range(-600.0, 600.0)),
				"radius": r,
			})
		var reach: float = (1.0 + _K) * max_radius
		for probe in 15:
			var p := Vector2(randf_range(-700.0, 700.0), randf_range(-700.0, 700.0))
			var g := _global_order_fold(p, sources, reach)
			var t := _tile_order_fold(p, sources, reach)
			trials += 1
			var drift: float = absf(g - t)
			if drift > max_drift:
				max_drift = drift
				max_drift_at = p

	gut.p("tile-gather vs global-index fold order: max drift = %.6f over %d probes (visible threshold 1/255 = %.6f)"
		% [max_drift, trials, 1.0 / 255.0])
	# The measurement this test was written to produce is recorded in
	# docs/domain/overlay-field-rendering.md: max drift 0.0026 against the
	# 1/255 = 0.0039 visible threshold — under budget, but by only ~30%.
	# That headroom is exactly what's worth guarding, so assert it rather than
	# printing a number nobody re-reads. `field_smin` is not associative, so a
	# future change to tile size, scan order, or union_smoothness can push this
	# over; if it does, the drift became VISIBLE and the doc needs updating too.
	assert_lt(max_drift, 1.0 / 255.0,
		"tile-order fold drifted past the visible threshold at %s — see docs/domain/overlay-field-rendering.md"
			% max_drift_at)
