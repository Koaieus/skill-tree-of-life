extends GutTest

## Tooltip V2 (#226) Decision 4 — the derived trace terminus. `FanAnchor` is a
## pure geometry helper (no scene, no node deps) mirroring TraceRouter's own
## test style: assert on the math directly, not on a rendered scene.
##
## The claim under test: the closing leg of a PCB route is always cardinal
## (TraceRouter._pcb's own guarantee), so which panel EDGE a trace arrives at
## is fully determined by that leg's direction — never authored by hand, and
## it must flip automatically when the panel moves across the tie boundary.
## WHERE along that edge is derived too (the point nearest the trunk top,
## clamped off the corners) — the last section covers that.

const _TRUNK_DIR := Vector2(0.0, -1.0)
const _TRUNK_FRAC := 0.382
## The fan-wide trunk length ([member FanAnchorDriver.trunk_length]) as a
## solver input: the trunk top is `from + _TRUNK_DIR * _TRUNK_PX`.
const _TRUNK_PX := 60.0


func _within_slide_window(value: float, lo: float, hi: float) -> bool:
	var t := (value - lo) / (hi - lo)
	return t >= FanAnchor.SLIDE_MIN - 0.001 and t <= FanAnchor.SLIDE_MAX + 0.001


func _route_to(from: Vector2, to: Vector2) -> PackedVector2Array:
	return TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {
		"trunk": _TRUNK_FRAC, "trunk_dir": _TRUNK_DIR,
	})


# --- four quadrants: panel above the node, offset left/right --------------

func test_panel_up_and_right_of_node_arrives_at_left_edge() -> void:
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(100.0, -260.0), Vector2(160.0, 120.0)) # centre (180,-200)
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)
	assert_almost_eq(anchor.x, rect.position.x, 0.01, "arrives from the left -> LEFT edge")
	assert_true(_within_slide_window(anchor.y, rect.position.y, rect.end.y),
		"the derived slide stays inside the edge's [0.1, 0.9] window")


func test_panel_up_and_left_of_node_arrives_at_right_edge() -> void:
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(-260.0, -260.0), Vector2(160.0, 120.0)) # centre (-180,-200)
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)
	assert_almost_eq(anchor.x, rect.position.x + rect.size.x, 0.01, "arrives from the right -> RIGHT edge")
	assert_true(_within_slide_window(anchor.y, rect.position.y, rect.end.y))


func test_panel_almost_directly_above_arrives_at_bottom_edge() -> void:
	# Small horizontal offset so it isn't exactly on the vertical axis, but the
	# separation is dominated by Y (trunk leaves straight up, panel is mostly
	# further up than sideways) -> vertical closing leg -> BOTTOM edge.
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(-20.0, -340.0), Vector2(40.0, 40.0)) # centre (0,-320)
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)
	assert_almost_eq(anchor.y, rect.position.y + rect.size.y, 0.01, "arrives from below -> BOTTOM edge")
	assert_almost_eq(anchor.x, rect.get_center().x, 0.01, "the trunk top is on the rect's centreline")


func test_panel_below_the_node_arrives_at_top_edge() -> void:
	# Roots direction: trunk leaves downward instead of up.
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(-20.0, 100.0), Vector2(40.0, 60.0)) # centre (0,130)
	var anchor := FanAnchor.derive_anchor(from, rect, Vector2(0.0, 1.0), _TRUNK_FRAC)
	assert_almost_eq(anchor.y, rect.position.y, 0.01, "arrives from above -> TOP edge")
	assert_almost_eq(anchor.x, rect.get_center().x, 0.01, "the trunk top is on the rect's centreline")


# --- the axis-flip boundary --------------------------------------------------

func test_boundary_tie_is_deterministic_and_flips_with_a_nudge() -> void:
	# |rem.x| == |rem.y| exactly at this offset, where `rem` is what remains
	# AFTER the trunk, measured from the anchor the derived slide picks (not
	# from the rect's centre): with a fixed trunk the trunk top is (0, -60), a
	# 40-tall rect wholly above it clamps the slide to 0.9 of its LEFT edge, so
	# the anchor is (px, py + 36) and rem = (px, py + 36 + 60). Tie: py = -96 - px.
	var from := Vector2.ZERO
	var dir := Vector2(0.0, -1.0)
	var px := 100.0
	var rect_tie := Rect2(Vector2(px, -96.0 - px), Vector2(40.0, 40.0))
	var anchor_tie := FanAnchor.derive_anchor(from, rect_tie, dir, _TRUNK_FRAC, _TRUNK_PX)
	# Tie-break in derive_anchor favours the horizontal leg (>=), so this
	# should land on a horizontal-arrival edge (left, since rem.x > 0).
	assert_almost_eq(anchor_tie.x, rect_tie.position.x, 0.01, "tie breaks horizontal by convention")
	assert_almost_eq(anchor_tie.y, rect_tie.position.y + 0.9 * rect_tie.size.y, 0.01,
		"and the slide sits at the clamp nearest the trunk top")

	# Nudge the panel further away along Y (increase |rem.y| past the tie) and
	# the chosen edge must flip to a vertical arrival (bottom), with ZERO
	# change to how the panel was authored other than its position.
	var rect_past := Rect2(rect_tie.position - Vector2(0.0, 80.0), rect_tie.size)
	var anchor_past := FanAnchor.derive_anchor(from, rect_past, dir, _TRUNK_FRAC, _TRUNK_PX)
	assert_almost_eq(anchor_past.y, rect_past.position.y + rect_past.size.y, 0.01,
		"nudging past the tie flips the arrival edge to vertical (bottom)")


# --- self-consistency: the ROUTED edge must match the CHOSEN edge -----------
# Regression guard for the bug the orchestrator's review caught: picking the
# edge from a route to the panel's CENTRE, then handing back a different
# point (the edge), can be wrong — moving `to` from centre to the edge changes
# `rem`, which can flip which axis is actually dominant once the route is
# drawn to the edge instead of the centre. A naive centre-only guess is not
# guaranteed to agree with the route TraceRouter actually draws to its own
# answer. This is exactly the shipped NodeStats unit's real geometry.

func _actual_edge_of_route(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float) -> String:
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {
		"trunk": trunk_frac, "trunk_dir": trunk_dir,
	})
	var leg := pts[pts.size() - 1] - pts[pts.size() - 2]
	if absf(leg.x) >= absf(leg.y):
		return "left" if leg.x >= 0.0 else "right"
	return "top" if leg.y >= 0.0 else "bottom"


func _edge_name(anchor: Vector2, rect: Rect2) -> String:
	if is_equal_approx(anchor.x, rect.position.x):
		return "left"
	if is_equal_approx(anchor.x, rect.position.x + rect.size.x):
		return "right"
	if is_equal_approx(anchor.y, rect.position.y):
		return "top"
	return "bottom"


func test_derived_anchor_is_self_consistent_with_the_actually_drawn_route() -> void:
	# The exact geometry shipped in ui/tooltip_fan/units/node_stats_unit.tscn.
	var from := Vector2(-6.0, 0.0)
	var rect := Rect2(Vector2(-345.0, -230.0), Vector2(170.0, 200.0))
	var dir := Vector2(0.0, -1.0)
	var frac := 0.382

	var anchor := FanAnchor.derive_anchor(from, rect, dir, frac)
	var chosen_edge := _edge_name(anchor, rect)
	var routed_edge := _actual_edge_of_route(from, anchor, dir, frac)
	assert_eq(routed_edge, chosen_edge,
		"the route TraceRouter actually draws to the returned anchor must arrive on the SAME edge the anchor sits on")


func test_derived_anchor_is_self_consistent_for_the_mirrored_addons_unit() -> void:
	# Same shape, mirrored: ui/tooltip_fan/units/addons_unit.tscn's geometry.
	var from := Vector2(6.0, 0.0)
	var rect := Rect2(Vector2(185.0, -165.0), Vector2(150.0, 130.0))
	var dir := Vector2(0.0, -1.0)
	var frac := 0.382

	var anchor := FanAnchor.derive_anchor(from, rect, dir, frac)
	var chosen_edge := _edge_name(anchor, rect)
	var routed_edge := _actual_edge_of_route(from, anchor, dir, frac)
	assert_eq(routed_edge, chosen_edge,
		"self-consistency must hold for the mirrored (right-side) unit too")


# --- structural guarantees: exact terminus, no overshoot ---------------------

func test_final_route_terminates_exactly_at_the_derived_anchor() -> void:
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(100.0, -260.0), Vector2(160.0, 120.0))
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)
	var pts := _route_to(from, anchor)
	assert_eq(pts[pts.size() - 1], anchor, "TraceRouter's own contract: last point == to, always")


func test_no_route_point_lies_beyond_the_panel_rect() -> void:
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(100.0, -260.0), Vector2(160.0, 120.0))
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)
	var pts := _route_to(from, anchor)
	for i in range(pts.size()):
		assert_false(FanAnchor.is_inside(pts[i], rect),
			"point %d (%s) must not lie inside the panel it terminates at" % [i, pts[i]])


func test_no_route_point_lies_beyond_the_panel_rect_for_every_quadrant() -> void:
	var from := Vector2.ZERO
	var centers := [
		Vector2(180.0, -200.0), Vector2(-180.0, -200.0),
		Vector2(180.0, 200.0), Vector2(-180.0, 200.0),
	]
	for c in centers:
		var rect := Rect2(c - Vector2(80.0, 60.0), Vector2(160.0, 120.0))
		var dir: Vector2 = Vector2(0.0, -1.0) if c.y < 0.0 else Vector2(0.0, 1.0)
		var anchor := FanAnchor.derive_anchor(from, rect, dir, _TRUNK_FRAC)
		var pts := _route_to(from, anchor)
		for p in pts:
			assert_false(FanAnchor.is_inside(p, rect), "quadrant %s: no overshoot into the panel" % c)


# --- panel_rect_of --------------------------------------------------------

func test_panel_rect_of_reads_the_skins_own_offsets() -> void:
	var scene := preload("res://ui/tooltip_fan/fan_panel.tscn")
	var panel := scene.instantiate() as FanPanel
	add_child(panel)
	autofree(panel)
	panel.position = Vector2(50.0, -30.0)
	await get_tree().process_frame
	var rect := FanAnchor.panel_rect_of(panel)
	var skin := panel.get_skin()
	assert_eq(rect.position, panel.position + skin.position)
	assert_eq(rect.size, skin.size)


# --- the slide is DERIVED off the trunk top, clamped off the corners ---------
#
# `trunk_px` is the fan-wide trunk length ([member FanAnchorDriver.trunk_length]);
# the trunk top is `from + trunk_dir * trunk_px`. A vertical edge's anchor sits
# DIAGONAL_SHARE of the sideways distance ahead of it (the 45° diagonal's
# share), a horizontal edge's at its x — clamped to [0.1, 0.9] of the edge so
# the closing leg keeps a real perpendicular run instead of grazing a corner.


func test_the_slide_lands_a_diagonal_share_ahead_of_the_trunk_top() -> void:
	var from := Vector2.ZERO
	var trunk_top := from + _TRUNK_DIR * _TRUNK_PX # (0, -60)

	# Panel right of the pin, tall enough to hold the target unclamped -> LEFT
	# edge, DIAGONAL_SHARE of the 100 px sideways distance above the trunk top
	# (the trunk top's own height would be a 90° cut off the trunk).
	var rect := Rect2(Vector2(100.0, -200.0), Vector2(160.0, 200.0))
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, _TRUNK_PX)
	assert_almost_eq(anchor.x, rect.position.x, 0.01, "right of the pin -> LEFT edge")
	assert_almost_eq(anchor.y, trunk_top.y - TraceRouter.DIAGONAL_SHARE * 100.0, 0.01,
		"slide lands DIAGONAL_SHARE of the sideways distance ahead of the trunk top")

	# A panel hugging the trunk: the share would be under the minimum segment,
	# so the target floors at MIN_SEGMENT_PX ahead.
	var near := Rect2(Vector2(15.0, -200.0), Vector2(160.0, 200.0))
	var anchor_near := FanAnchor.derive_anchor(from, near, _TRUNK_DIR, _TRUNK_FRAC, _TRUNK_PX)
	assert_almost_eq(anchor_near.x, near.position.x, 0.01, "still the LEFT edge")
	assert_almost_eq(anchor_near.y, trunk_top.y - TraceRouter.MIN_SEGMENT_PX, 0.01,
		"the slide target floors at MIN_SEGMENT_PX ahead of the trunk top")

	# Panel far above the trunk top -> the projection falls off the edge's
	# bottom corner and is clamped to 0.9 of the edge.
	var high := Rect2(Vector2(200.0, -300.0), Vector2(160.0, 120.0))
	var anchor_high := FanAnchor.derive_anchor(from, high, _TRUNK_DIR, _TRUNK_FRAC, _TRUNK_PX)
	assert_almost_eq(anchor_high.x, high.position.x, 0.01, "still the LEFT edge")
	assert_almost_eq(anchor_high.y, high.position.y + 0.9 * high.size.y, 0.01,
		"trunk top below the edge -> clamped to 0.9 of it")

	# Panel wholly below the trunk top and off to the right -> the gable closes
	# down into the TOP edge; the trunk top's x lies left of the edge, so the
	# slide clamps to 0.1 of it.
	var low := Rect2(Vector2(200.0, 20.0), Vector2(160.0, 120.0))
	var anchor_low := FanAnchor.derive_anchor(from, low, _TRUNK_DIR, _TRUNK_FRAC, _TRUNK_PX)
	assert_almost_eq(anchor_low.y, low.position.y, 0.01, "below the trunk top -> TOP edge")
	assert_almost_eq(anchor_low.x, low.position.x + 0.1 * low.size.x, 0.01,
		"trunk top left of the edge -> clamped to 0.1 of it")


func test_a_grown_panel_keeps_a_perpendicular_arrival() -> void:
	# The surviving intent of the forced-axis regression: content that
	# grows a panel past its authored envelope must not turn the arrival into a
	# leg running alongside the edge. NodeStats' shipped geometry, then 200 px
	# taller.
	var from := Vector2(-6.0, 0.0)
	var params := {"trunk": _TRUNK_FRAC, "trunk_dir": _TRUNK_DIR, "trunk_px": _TRUNK_PX}
	for extra in [0.0, 200.0]:
		var rect := Rect2(Vector2(-345.0, -230.0), Vector2(170.0, 200.0 + extra))
		var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, _TRUNK_PX)
		var pts := TraceRouter.compute_trace_points(from, anchor, TraceRouter.Style.PCB, params)
		var leg := pts[pts.size() - 1] - pts[pts.size() - 2]
		var on_vertical_edge := is_equal_approx(anchor.x, rect.position.x) \
			or is_equal_approx(anchor.x, rect.position.x + rect.size.x)
		if on_vertical_edge:
			assert_almost_eq(leg.y, 0.0, 0.01, "grown by %s: closing leg into a vertical edge is horizontal" % extra)
			assert_gt(absf(leg.x), 0.0, "grown by %s: the closing leg has length" % extra)
		else:
			assert_almost_eq(leg.x, 0.0, 0.01, "grown by %s: closing leg into a horizontal edge is vertical" % extra)
			assert_gt(absf(leg.y), 0.0, "grown by %s: the closing leg has length" % extra)


func test_a_side_panel_level_with_the_trunk_top_routes_through_a_real_diagonal() -> void:
	# The owner's forbidden shape: a panel straddling the trunk top's height
	# drew trunk, then a 90° cut straight across (or a sub-pixel diagonal
	# standing in for one). The slide target sits DIAGONAL_SHARE of the
	# sideways distance ahead of the trunk top, so the route bends through 45°.
	var from := Vector2.ZERO
	var trunk_px := 40.0
	var params := {"trunk": _TRUNK_FRAC, "trunk_dir": _TRUNK_DIR, "trunk_px": trunk_px}
	for rect in [Rect2(Vector2(200.0, -100.0), Vector2(160.0, 120.0)),
			Rect2(Vector2(-360.0, -100.0), Vector2(160.0, 120.0))]:
		var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, trunk_px)
		var pts := TraceRouter.compute_trace_points(from, anchor, TraceRouter.Style.PCB, params)
		var label := "rect=%s" % rect
		var has_diagonal := false
		for i in range(pts.size() - 1):
			var seg := pts[i + 1] - pts[i]
			if absf(absf(seg.x) - absf(seg.y)) < 0.01 and seg.length() >= TraceRouter.MIN_SEGMENT_PX:
				has_diagonal = true
			if i > 0:
				var prev := pts[i] - pts[i - 1]
				var both_cardinal := (absf(prev.x) < 0.01 or absf(prev.y) < 0.01) \
					and (absf(seg.x) < 0.01 or absf(seg.y) < 0.01)
				assert_false(both_cardinal, "%s: segments %d→%d are a 90° cardinal cut" % [label, i - 1, i])
		assert_true(has_diagonal, "%s: a 45° segment of at least MIN_SEGMENT_PX (route %s)" % [label, pts])
