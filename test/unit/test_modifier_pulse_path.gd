extends GutTest

## #71 — the allocation pulse reuses Curve2DPath, building a Curve2D through the
## real node world-positions and pinning origin/target to the route endpoints.
## That reduces Curve2DPath's similarity transform to the identity, so the pulse
## traces the EXACT polyline (no shape-warping). These tests guard that property
## — the whole "reuse instead of a new path class" decision rests on it.

func _curve(points: Array) -> Curve2D:
	var c := Curve2D.new()
	for p in points:
		c.add_point(p)
	return c


func test_endpoints_are_exact() -> void:
	var p0 := Vector2(100, 100)
	var p1 := Vector2(300, 140)
	var p2 := Vector2(360, 400)
	var path := Curve2DPath.new()
	path.curve = _curve([p0, p1, p2])
	assert_almost_eq(path.evaluate(0.0, p0, p2), p0, Vector2(0.5, 0.5))
	assert_almost_eq(path.evaluate(1.0, p0, p2), p2, Vector2(0.5, 0.5))


func test_traces_through_waypoint() -> void:
	# Right-angle route, equal-length legs: arc-length midpoint is the bend.
	var p0 := Vector2.ZERO
	var p1 := Vector2(100.0, 0.0)
	var p2 := Vector2(100.0, 100.0)
	var path := Curve2DPath.new()
	path.curve = _curve([p0, p1, p2])
	assert_almost_eq(path.evaluate(0.5, p0, p2), p1, Vector2(2.0, 2.0))
