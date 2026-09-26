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


# --- PCB (#215's true 45°-only family) --------------------------------------
# These assert the turn ANGLES, not just endpoints — the check that was missing
# when the earlier styles shipped a non-45° shape past a green endpoint test.

func test_pcb_route_is_trunk_then_exact_45_then_cardinal() -> void:
	var from := Vector2.ZERO
	var to := Vector2(-155, -200)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {"trunk": 0.382})
	assert_eq(pts.size(), 4, "PCB is [from, trunk_top, diag_end, to] for a bent route")
	assert_eq(pts[0], from)
	assert_eq(pts[3], to)
	assert_almost_eq(pts[1].x, from.x, 0.001, "trunk leaves straight up: x unchanged")
	var diag := pts[2] - pts[1]
	assert_almost_eq(absf(diag.x), absf(diag.y), 0.001, "the middle segment is exactly 45°")
	var closing := pts[3] - pts[2]
	assert_true(is_zero_approx(closing.x) or is_zero_approx(closing.y),
		"the closing leg is cardinal (one axis aligned with `to`)")


func test_pcb_trunk_zero_starts_on_the_45_diagonal() -> void:
	var pts := TraceRouter.compute_trace_points(
		Vector2.ZERO, Vector2(-155, -200), TraceRouter.Style.PCB, {"trunk": 0.0})
	assert_eq(pts[0], Vector2.ZERO)
	assert_eq(pts[pts.size() - 1], Vector2(-155, -200))
	var first := pts[1] - pts[0]
	assert_almost_eq(absf(first.x), absf(first.y), 0.001,
		"trunk=0 has no trunk: it starts on the 45° diagonal from the anchor")


func test_pcb_trunk_one_is_a_squared_90_corner() -> void:
	var from := Vector2.ZERO
	var to := Vector2(-155, -200)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {"trunk": 1.0})
	assert_eq(pts.size(), 3, "trunk=1 squares off (no diagonal), deduped to a corner")
	assert_eq(pts[1], Vector2(from.x, to.y), "corner sits at from.x / to.y")


func test_pcb_dedups_zero_length_segments_on_a_straight_up_target() -> void:
	# to directly above from: rem.x == 0 so diag_end coincides with trunk_top.
	var pts := TraceRouter.compute_trace_points(
		Vector2.ZERO, Vector2(0, -120), TraceRouter.Style.PCB, {"trunk": 0.5})
	for i in range(pts.size() - 1):
		assert_false(pts[i].is_equal_approx(pts[i + 1]),
			"no consecutive duplicate points (no zero-length segment)")


func test_pcb_trunk_dir_can_leave_sideways() -> void:
	var from := Vector2.ZERO
	var to := Vector2(200, -40)
	var pts := TraceRouter.compute_trace_points(
		from, to, TraceRouter.Style.PCB, {"trunk": 0.5, "trunk_dir": Vector2(1, 0)})
	assert_almost_eq(pts[1].y, from.y, 0.001,
		"trunk_dir=(1,0) leaves straight right: y unchanged along the trunk")


# --- PCB gable family (#1117): targets below the trunk top ------------------
# The 45°-grid invariant, for EVERY target: each segment heading is a multiple
# of 45°, no consecutive bend exceeds 90° (the 135° double-back is the bug),
# no zero-length segment, and the closing leg is cardinal.

func _assert_on_45_grid_without_doubling_back(pts: PackedVector2Array, label: String) -> void:
	var prev := Vector2.ZERO
	for i in range(pts.size() - 1):
		var seg := pts[i + 1] - pts[i]
		assert_gt(seg.length(), 0.5, "%s: segment %d has length" % [label, i])
		var h := rad_to_deg(seg.angle())
		var off := absf(fmod(absf(h), 45.0))
		assert_true(off < 0.5 or off > 44.5, "%s: segment %d heading %.1f° is on the 45° grid" % [label, i, h])
		if i > 0:
			var turn := absf(rad_to_deg(prev.angle_to(seg)))
			assert_true(turn < 90.5, "%s: bend %d turns %.1f°, never more than 90°" % [label, i, turn])
		prev = seg
	var closing := pts[pts.size() - 1] - pts[pts.size() - 2]
	assert_true(is_zero_approx(closing.x) or is_zero_approx(closing.y),
		"%s: closing leg is cardinal" % label)


func test_pcb_every_bend_is_exactly_45_degrees_for_every_target() -> void:
	var from := Vector2.ZERO
	for xi in range(-8, 9):
		for yi in range(-8, 9):
			var to := Vector2(xi * 50.0, yi * 50.0)
			if absf(to.x) < 2.0 and to.y > -40.0:
				continue # the trunk's own column below the top: outside the family
			var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {"trunk_px": 40.0})
			var label := "to=%s" % to
			assert_eq(pts[0], from, "%s: first == from" % label)
			assert_eq(pts[pts.size() - 1], to, "%s: last == to" % label)
			_assert_on_45_grid_without_doubling_back(pts, label)


func test_pcb_target_at_trunk_top_height_keeps_a_cardinal_closing_leg() -> void:
	# The family boundary: `to` exactly at the trunk top's height is AHEAD
	# (trunk, then one cardinal leg) — the gable would dedup `to` away and end
	# on a diagonal shoulder.
	var to := Vector2(200.0, -40.0)
	var pts := TraceRouter.compute_trace_points(Vector2.ZERO, to, TraceRouter.Style.PCB, {"trunk_px": 40.0})
	assert_eq(pts[pts.size() - 1], to, "last == to")
	assert_eq(pts.size(), 3, "trunk then a squared 90° corner, like trunk == 1")
	_assert_on_45_grid_without_doubling_back(pts, "at trunk-top height")


func test_pcb_below_target_is_a_symmetric_gable() -> void:
	var from := Vector2.ZERO
	var to := Vector2(200.0, 150.0)
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {"trunk_px": 40.0})
	assert_eq(pts.size(), 6, "gable is [from, trunk_top, shoulder_out, run_end, shoulder_back, to]")
	assert_eq(pts[0], from)
	assert_eq(pts[5], to)
	assert_eq(pts[1], Vector2(0.0, -40.0), "trunk is trunk_px, never the along-trunk span")
	var leg2 := pts[2] - pts[1]
	var leg4 := pts[4] - pts[3]
	assert_almost_eq(leg2.length(), leg4.length(), 0.001, "shoulders are equal length")
	assert_almost_eq(leg2.x, leg4.x, 0.001, "shoulders mirror in y: same x run")
	assert_almost_eq(leg2.y, -leg4.y, 0.001, "shoulders mirror in y: opposite rise")
	assert_almost_eq(absf(leg2.x), absf(leg2.y), 0.001, "shoulder is an exact 45°")
	assert_almost_eq(leg2.length(), 40.0 * sqrt(2.0), 0.001, "default shoulder == trunk length")
	var leg3 := pts[3] - pts[2]
	assert_almost_eq(leg3.y, 0.0, 0.001, "run is horizontal")
	assert_almost_eq(leg3.x, 120.0, 0.001, "run = |perp| - 2a")
	var leg5 := pts[5] - pts[4]
	assert_almost_eq(leg5.x, 0.0, 0.001, "closing leg is vertical")
	assert_almost_eq(leg5.y, 190.0, 0.001, "closing leg drops from trunk-top height to `to`")


func test_pcb_below_target_with_narrow_perp_shortens_the_shoulders_and_keeps_a_run() -> void:
	# Shoulder = min(shoulder, |perp| / 3): a third each for the two shoulders
	# and the run, so a narrow offset still keeps a flat run rather than
	# collapsing into an arch.
	var pts := TraceRouter.compute_trace_points(
		Vector2.ZERO, Vector2(60.0, 150.0), TraceRouter.Style.PCB, {"trunk_px": 40.0})
	assert_eq(pts.size(), 6, "narrow perp is still the 6-point gable")
	assert_eq(pts[2], Vector2(20.0, -60.0), "shoulder out: a = |perp| / 3 = 20")
	assert_eq(pts[3], Vector2(40.0, -60.0), "run: b = |perp| - 2a = 20")
	assert_eq(pts[4], Vector2(60.0, -40.0), "shoulder back lands at trunk-top height over `to`")
	assert_eq(pts[5], Vector2(60.0, 150.0))


func test_pcb_gable_shoulder_param_caps_the_shoulder() -> void:
	var pts := TraceRouter.compute_trace_points(
		Vector2.ZERO, Vector2(200.0, 150.0), TraceRouter.Style.PCB, {"trunk_px": 40.0, "shoulder": 10.0})
	assert_eq(pts.size(), 6)
	assert_eq(pts[2], Vector2(10.0, -50.0), "shoulder = min(params.shoulder, |perp| / 3)")
	assert_eq(pts[3], Vector2(190.0, -50.0))


func test_pcb_gable_honours_trunk_dir_sideways() -> void:
	# Trunk leaves right; the target sits BEHIND the trunk top (to the left).
	var from := Vector2.ZERO
	var to := Vector2(-150.0, 200.0)
	var pts := TraceRouter.compute_trace_points(
		from, to, TraceRouter.Style.PCB, {"trunk_px": 40.0, "trunk_dir": Vector2(1.0, 0.0)})
	assert_eq(pts.size(), 6, "same family, rotated")
	assert_eq(pts[1], Vector2(40.0, 0.0), "trunk leaves right by trunk_px")
	assert_eq(pts[pts.size() - 1], to)
	var leg3 := pts[3] - pts[2]
	assert_almost_eq(leg3.x, 0.0, 0.001, "run is perpendicular to the trunk (vertical here)")
	var leg5 := pts[5] - pts[4]
	assert_almost_eq(leg5.y, 0.0, 0.001, "closing leg runs back along -trunk_dir (horizontal)")
	assert_true(leg5.x < 0.0, "closing leg heads left, behind the trunk top")
	_assert_on_45_grid_without_doubling_back(pts, "sideways gable")


# --- PCB minimum segment (#1126): no 90° trunk cut, no sub-pixel stand-in ----
# Every segment but the closing leg is at least MIN_SEGMENT_PX, and no two
# consecutive segments are both cardinal (that pair IS the forbidden 90° cut).
# The closing leg is exempt: AHEAD of the trunk top it is the leftover
# ||rem.x| − |rem.y|| the 45° diagonal cannot absorb without moving the fixed
# trunk — zero on an exact 45° target.

func _is_cardinal(seg: Vector2) -> bool:
	return absf(seg.x) < 0.001 or absf(seg.y) < 0.001


func _assert_min_segments_and_no_cardinal_corner(pts: PackedVector2Array, label: String) -> void:
	for i in range(pts.size() - 2):
		var seg := pts[i + 1] - pts[i]
		assert_true(seg.length() >= TraceRouter.MIN_SEGMENT_PX - 0.001,
			"%s: segment %d is %.2f px, under MIN_SEGMENT_PX" % [label, i, seg.length()])
	for i in range(pts.size() - 2):
		var a := pts[i + 1] - pts[i]
		var b := pts[i + 2] - pts[i + 1]
		var collinear := absf(a.cross(b)) < 0.001
		assert_false(_is_cardinal(a) and _is_cardinal(b) and not collinear,
			"%s: segments %d→%d are a cardinal→cardinal 90° corner" % [label, i, i + 1])


func _pcb_min_segment_targets() -> Array[Vector2]:
	var targets: Array[Vector2] = []
	for xi in range(-8, 9):
		for yi in range(-8, 9):
			targets.append(Vector2(xi * 50.0, yi * 50.0))
	# Rows hugging the fixed 40 px trunk top's height, where the old boundary
	# drew the 90° cut and the diagonal went sub-pixel.
	for x in [-400.0, -200.0, -100.0, -50.0, 50.0, 100.0, 200.0, 400.0]:
		for dy in [-40.0, -11.5, -6.0, -1.0, 0.0, 1.0, 6.0, 11.5, 40.0]:
			targets.append(Vector2(x, -40.0 + dy))
	return targets


func test_pcb_every_segment_clears_the_minimum_for_every_target() -> void:
	var from := Vector2.ZERO
	for params in [{"trunk_px": 40.0}, {"trunk": 0.382}]:
		for to in _pcb_min_segment_targets():
			if absf(to.x) < 2.0 * TraceRouter.MIN_SEGMENT_PX:
				continue # the trunk's own column: outside the family
			var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, params)
			var label := "%s to=%s" % [params, to]
			assert_eq(pts[0], from, "%s: first == from" % label)
			assert_eq(pts[pts.size() - 1], to, "%s: last == to" % label)
			_assert_on_45_grid_without_doubling_back(pts, label)
			_assert_min_segments_and_no_cardinal_corner(pts, label)
