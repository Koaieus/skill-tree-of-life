extends GutTest

## Coverage for [VisionCircles] — the shared "is this point inside the union of
## vision circles?" rule, and the uniform grid that answers it.
##
## The index is an optimisation of a predicate that used to be a linear scan, so
## every test here is written the same way: build a set, then assert the indexed
## answer against the brute-force one for the same geometry. If those two ever
## disagree the index is wrong, and no amount of speed makes that acceptable.


func _brute(circles: Array, p: Vector2) -> bool:
	for c in circles:
		var r: float = c[1]
		if p.distance_squared_to(c[0] as Vector2) <= r * r:
			return true
	return false


func _build(circles: Array) -> VisionCircles:
	var vc := VisionCircles.new()
	for c in circles:
		vc.add(c[0], c[1])
	return vc


func _assert_agrees(circles: Array, points: Array, ctx: String) -> void:
	var vc := _build(circles)
	for p in points:
		assert_eq(vc.has_point(p), _brute(circles, p),
			"%s: disagreement at %s" % [ctx, p])


func test_empty_set_sees_nothing() -> void:
	var vc := VisionCircles.new()
	assert_true(vc.is_empty(), "a fresh set is empty")
	assert_eq(vc.size(), 0, "and has no circles")
	assert_false(vc.has_point(Vector2.ZERO), "an empty set contains no point")


func test_single_circle_boundary_is_inclusive() -> void:
	var vc := _build([[Vector2(100.0, 0.0), 50.0]])
	assert_true(vc.has_point(Vector2(150.0, 0.0)), "exactly on the rim is inside")
	assert_false(vc.has_point(Vector2(150.1, 0.0)), "just past the rim is outside")
	assert_true(vc.has_point(Vector2(100.0, 0.0)), "the centre is inside")


func test_zero_radius_circle_still_contains_its_own_centre() -> void:
	# An owned node with no vision must still see itself — the union rule is
	# `distance <= radius`, so a zero-radius circle is not the same as no circle.
	var vc := _build([[Vector2(7.0, -3.0), 0.0]])
	assert_true(vc.has_point(Vector2(7.0, -3.0)), "the centre of a 0-radius circle is inside")
	assert_false(vc.has_point(Vector2(7.5, -3.0)), "nothing else is")


func test_point_outside_the_bounding_box_is_rejected() -> void:
	# The cheap early-out that carries the win: most of a large map is fogged.
	var vc := _build([[Vector2.ZERO, 10.0], [Vector2(100.0, 100.0), 10.0]])
	assert_false(vc.has_point(Vector2(-9999.0, -9999.0)), "far outside is not visible")


func test_agrees_with_brute_force_on_a_scattered_grid() -> void:
	# Circles spread wide enough that many query points land in cells with no
	# circle at all — the case the 3x3 neighbourhood scan has to get right.
	var circles: Array = []
	for i in 40:
		circles.append([Vector2((i % 8) * 300.0, (i / float(8)) * 300.0), 120.0 + (i % 5) * 40.0])
	var points: Array = []
	for x in 30:
		for y in 30:
			points.append(Vector2(x * 90.0 - 200.0, y * 90.0 - 200.0))
	_assert_agrees(circles, points, "scattered grid")


func test_agrees_with_brute_force_on_wildly_mixed_radii() -> void:
	# One huge circle plus pinpricks: the worst case for a grid sized off the
	# largest radius, and the one the cell-count clamp has to survive.
	var circles: Array = [
		[Vector2.ZERO, 5000.0],
		[Vector2(9000.0, 0.0), 1.0],
		[Vector2(-9000.0, 400.0), 2.0],
		[Vector2(0.0, 12000.0), 300.0],
	]
	var points: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260817
	for i in 400:
		points.append(Vector2(rng.randf_range(-12000.0, 12000.0), rng.randf_range(-14000.0, 14000.0)))
	# Plus every centre and a hair off each, so the pinpricks are actually probed.
	for c in circles:
		points.append(c[0])
		points.append((c[0] as Vector2) + Vector2(c[1], 0.0))
		points.append((c[0] as Vector2) + Vector2(c[1] + 0.5, 0.0))
	_assert_agrees(circles, points, "mixed radii")


func test_agrees_with_brute_force_when_every_circle_shares_one_position() -> void:
	# Degenerate bounding box (zero span). The grid must not divide by zero or
	# collapse to no cells.
	var circles: Array = [[Vector2(50.0, 50.0), 10.0], [Vector2(50.0, 50.0), 30.0]]
	_assert_agrees(circles, [
		Vector2(50.0, 50.0), Vector2(75.0, 50.0), Vector2(81.0, 50.0), Vector2(500.0, 500.0),
	], "coincident circles")


func test_adding_after_a_query_invalidates_the_index() -> void:
	# Lazy build: a caller may interleave add() and has_point(). If the stale
	# grid survived, the new circle would be invisible.
	var vc := _build([[Vector2.ZERO, 10.0]])
	assert_false(vc.has_point(Vector2(500.0, 0.0)), "not visible before the second circle")
	vc.add(Vector2(500.0, 0.0), 20.0)
	assert_true(vc.has_point(Vector2(500.0, 0.0)), "visible once its circle is added")
	assert_eq(vc.size(), 2, "both circles are held")


# -- randomized exactness -------------------------------------------------------
#
# The grid's cell is finer than a radius and classifies whole cells as inside
# the union without a scan, so the places it can lie are: a point exactly on a
# rim, a point exactly on a cell border, and a point just outside the bounding
# box. These two tests seed an RNG, build the two shapes a real level produces
# (one radius everywhere; a spread of radii) and probe exactly those places,
# against brute force.


## Points that stress every classification boundary of [param vc]: random
## samples over the grown bounding box, each rim at several angles, a hair
## inside and outside each rim, and every cell corner of the built grid
## (including the far edge). Reads the grid's own layout — this is the unit
## under test, not a neighbour.
func _adversarial_points(circles: Array, vc: VisionCircles, rng: RandomNumberGenerator,
		random_count: int) -> Array:
	var points: Array = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var max_r := 0.0
	for c in circles:
		lo = lo.min(c[0] as Vector2)
		hi = hi.max(c[0] as Vector2)
		max_r = maxf(max_r, c[1])
	var margin := Vector2(max_r, max_r) * 1.2
	for i in random_count:
		points.append(Vector2(
			rng.randf_range(lo.x - margin.x, hi.x + margin.x),
			rng.randf_range(lo.y - margin.y, hi.y + margin.y)))
	for c in circles:
		var centre: Vector2 = c[0]
		var r: float = c[1]
		for k in 8:
			var dir := Vector2.from_angle(k * TAU / 8.0 + 0.1)
			points.append(centre + dir * r)
			points.append(centre + dir * (r + 0.01))
			points.append(centre + dir * (r - 0.01))
		points.append(centre)
	# Build the grid, then walk its cell corners. The far edge of the last
	# column/row and the four bounding-box corners are the clamp paths.
	vc.has_point(lo)
	var cs: float = vc._cell_size
	for row in vc._rows + 1:
		for col in vc._cols + 1:
			points.append(vc._lo + Vector2(col * cs, row * cs))
	points.append(vc._hi)
	points.append(vc._hi + Vector2(0.01, 0.0))
	points.append(vc._lo - Vector2(0.0, 0.01))
	return points


func test_agrees_with_brute_force_on_a_dense_uniform_radius_set() -> void:
	# The real level: one vision radius on every owned node, nodes ~86px
	# apart, radius several times the spacing — so one cell holds many
	# circles and most interior cells are covered outright.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var circles: Array = []
	for i in 160:
		var pos := Vector2((i % 16) * 86.0, float(i >> 4) * 86.0) + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
		circles.append([pos, 260.0])
	var vc := _build(circles)
	var points := _adversarial_points(circles, vc, rng, 1500)
	var disagreements := 0
	for p in points:
		if vc.has_point(p) != _brute(circles, p):
			disagreements += 1
	assert_eq(disagreements, 0, "dense uniform set: %d of %d probes disagree with brute force" % [disagreements, points.size()])


func test_agrees_with_brute_force_on_a_dense_mixed_radius_set() -> void:
	# Scouted marks and owned nodes of differing vision_range: radii from a
	# pinprick to a few cells wide, on the same lattice, plus a handful of
	# zero-radius circles that must still contain their own centre.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261106
	var circles: Array = []
	for i in 120:
		var pos := Vector2((i % 12) * 86.0, float(int(i / 12.0)) * 86.0) + Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0))
		var r: float = [0.0, 1.0, 40.0, 90.0, 170.0, 330.0][rng.randi_range(0, 5)]
		circles.append([pos, r])
	var vc := _build(circles)
	var points := _adversarial_points(circles, vc, rng, 1500)
	var disagreements := 0
	for p in points:
		if vc.has_point(p) != _brute(circles, p):
			disagreements += 1
	assert_eq(disagreements, 0, "dense mixed set: %d of %d probes disagree with brute force" % [disagreements, points.size()])
