extends GutTest

## #159 Phase 0: TraceRouter is a pure static geometry helper for tooltip fan
## trace lines. No node, no fan orientation, no randomness — just polylines.


func test_straight_is_two_points_endpoints_only() -> void:
	var from := Vector2(0.0, 0.0)
	var to := Vector2(100.0, 40.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.STRAIGHT, {})
	assert_eq(pts.size(), 2, "STRAIGHT must be exactly [from, to]")
	assert_eq(pts[0], from)
	assert_eq(pts[1], to)


func test_elbow_default_corner_bends_at_half_the_dominant_axis() -> void:
	# Dominant axis is X (dx=100 > dy=40). corner_point.y stays from.y (the
	# corner leg is always axis-aligned along the dominant axis); x is the
	# lerp at the default corner fraction (0.5).
	var from := Vector2(0.0, 0.0)
	var to := Vector2(100.0, 40.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.ELBOW, {})
	assert_eq(pts.size(), 3, "ELBOW must be [from, corner, to]")
	assert_eq(pts[0], from)
	assert_eq(pts[2], to)
	assert_eq(pts[1], Vector2(50.0, 0.0), "corner sits at 50% of dx, holding from.y")


func test_elbow_corner_one_is_a_true_axis_aligned_right_angle() -> void:
	# corner == 1.0 is the canonical squared elbow: both legs perpendicular
	# and axis-aligned, satisfying the "one right-angle corner" contract
	# unconditionally (not just for the dominant leg).
	var from := Vector2(10.0, 10.0)
	var to := Vector2(110.0, 70.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.ELBOW, {"corner": 1.0})
	assert_eq(pts.size(), 3)
	assert_eq(pts[0], from)
	assert_eq(pts[2], to)
	var corner: Vector2 = pts[1]
	assert_eq(corner, Vector2(to.x, from.y), "corner snaps fully to to.x, keeping from.y")
	# leg 1 (from -> corner) purely horizontal
	assert_eq(corner.y, from.y)
	# leg 2 (corner -> to) purely vertical
	assert_eq(corner.x, to.x)


func test_elbow_dominant_axis_is_vertical_when_dy_exceeds_dx() -> void:
	var from := Vector2(0.0, 0.0)
	var to := Vector2(20.0, 100.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.ELBOW, {"corner": 0.25})
	assert_eq(pts.size(), 3)
	# dominant axis is Y here: corner.x stays from.x, corner.y is the lerp.
	assert_eq(pts[1], Vector2(0.0, 25.0))


func test_tree_first_and_last_points_match_from_and_to() -> void:
	var from := Vector2(0.0, 0.0)
	var to := Vector2(60.0, 80.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.TREE, {})
	assert_eq(pts.size(), 4, "TREE must be [from, trunk_top, route_point, to]")
	assert_eq(pts[0], from)
	assert_eq(pts[3], to)


func test_tree_trunk_sprouts_upward_by_the_sprout_param() -> void:
	var from := Vector2(0.0, 0.0)
	var to := Vector2(60.0, 80.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.TREE, {"sprout": 24.0})
	assert_eq(pts[1], Vector2(0.0, -24.0), "trunk_top is from + (0, -sprout): upward is -Y")


func test_tree_bend_zero_places_route_point_on_the_direct_diagonal() -> void:
	var from := Vector2(0.0, 0.0)
	var to := Vector2(60.0, 80.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.TREE, {"sprout": 20.0, "bend": 0.0})
	var trunk_top := Vector2(0.0, -20.0)
	var expected_route := trunk_top.lerp(to, 0.5)
	assert_eq(pts[2], expected_route, "bend=0 sits on the trunk_top->to diagonal midpoint")


func test_tree_bend_one_is_the_fully_squared_corner() -> void:
	var from := Vector2(0.0, 0.0)
	var to := Vector2(60.0, 80.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.TREE, {"sprout": 20.0, "bend": 1.0})
	var trunk_top := Vector2(0.0, -20.0)
	assert_eq(pts[2], Vector2(to.x, trunk_top.y), "bend=1 squares off: to.x at trunk height")


func test_tree_default_params_use_sprout_24_and_bend_half() -> void:
	var from := Vector2(5.0, 5.0)
	var to := Vector2(105.0, 5.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.TREE, {})
	var trunk_top := Vector2(5.0, -19.0)
	assert_eq(pts[1], trunk_top, "default sprout is 24.0")
	var diagonal_point := trunk_top.lerp(to, 0.5)
	var squared_point := Vector2(to.x, trunk_top.y)
	var expected_route: Vector2 = diagonal_point.lerp(squared_point, 0.5)
	assert_eq(pts[2], expected_route, "default bend is 0.5")
