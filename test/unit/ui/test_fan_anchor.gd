extends GutTest

## Tooltip V2 (#226) Decision 4 — the derived trace terminus. `FanAnchor` is a
## pure geometry helper (no scene, no node deps) mirroring TraceRouter's own
## test style: assert on the math directly, not on a rendered scene.
##
## The claim under test: the closing leg of a PCB route is always cardinal
## (TraceRouter._pcb's own guarantee), so which panel EDGE a trace arrives at
## is fully determined by that leg's direction — never authored by hand, and
## it must flip automatically when the panel moves across the tie boundary.

const _TRUNK_DIR := Vector2(0.0, -1.0)
const _TRUNK_FRAC := 0.382


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
	assert_almost_eq(anchor.y, rect.get_center().y, 0.01, "anchor sits at the edge's vertical centre")


func test_panel_up_and_left_of_node_arrives_at_right_edge() -> void:
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(-260.0, -260.0), Vector2(160.0, 120.0)) # centre (-180,-200)
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)
	assert_almost_eq(anchor.x, rect.position.x + rect.size.x, 0.01, "arrives from the right -> RIGHT edge")
	assert_almost_eq(anchor.y, rect.get_center().y, 0.01)


func test_panel_almost_directly_above_arrives_at_bottom_edge() -> void:
	# Small horizontal offset so it isn't exactly on the vertical axis, but the
	# separation is dominated by Y (trunk leaves straight up, panel is mostly
	# further up than sideways) -> vertical closing leg -> BOTTOM edge.
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(-20.0, -340.0), Vector2(40.0, 40.0)) # centre (0,-320)
	var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)
	assert_almost_eq(anchor.y, rect.position.y + rect.size.y, 0.01, "arrives from below -> BOTTOM edge")
	assert_almost_eq(anchor.x, rect.get_center().x, 0.01)


func test_panel_below_the_node_arrives_at_top_edge() -> void:
	# Roots direction: trunk leaves downward instead of up.
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(-20.0, 100.0), Vector2(40.0, 60.0)) # centre (0,130)
	var anchor := FanAnchor.derive_anchor(from, rect, Vector2(0.0, 1.0), _TRUNK_FRAC)
	assert_almost_eq(anchor.y, rect.position.y, 0.01, "arrives from above -> TOP edge")
	assert_almost_eq(anchor.x, rect.get_center().x, 0.01)


# --- the axis-flip boundary --------------------------------------------------

func test_boundary_tie_is_deterministic_and_flips_with_a_nudge() -> void:
	# |rem.x| == |rem.y| exactly at this offset (trunk eats some of the
	# vertical separation first, so the remaining rem is not simply the raw
	# centre offset — pick a centre where rem ties by construction).
	var from := Vector2.ZERO
	var dir := Vector2(0.0, -1.0)
	# Choose a centre C such that rem = C - trunk_top has |rem.x| == |rem.y|.
	# trunk_top = from + dir * (_TRUNK_FRAC * |C.y|) for a purely-vertical dir,
	# i.e. trunk_top = (0, -_TRUNK_FRAC*|C.y|). Pick C.y = -200 first, solve C.x.
	var cy := -200.0
	var trunk_top_y := dir.y * (_TRUNK_FRAC * absf(cy))
	var rem_y := cy - trunk_top_y
	var cx := absf(rem_y) # so rem.x (== cx, since trunk_top.x == 0) ties rem.y in magnitude
	var rect_tie := Rect2(Vector2(cx - 20.0, cy - 20.0), Vector2(40.0, 40.0))
	var anchor_tie := FanAnchor.derive_anchor(from, rect_tie, dir, _TRUNK_FRAC)
	# Tie-break in derive_anchor favours the horizontal leg (>=), so this
	# should land on a horizontal-arrival edge (left, since rem.x > 0).
	assert_almost_eq(anchor_tie.x, rect_tie.position.x, 0.01, "tie breaks horizontal by convention")

	# Nudge the panel further away along Y (increase |rem.y| past the tie) and
	# the chosen edge must flip to a vertical arrival (bottom), with ZERO
	# change to how the panel was authored other than its position.
	var rect_past := Rect2(Vector2(cx - 20.0, cy - 20.0 - 80.0), Vector2(40.0, 40.0))
	var anchor_past := FanAnchor.derive_anchor(from, rect_past, dir, _TRUNK_FRAC)
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


# --- #307 C: the edge is derived, WHERE ALONG IT is authored -------------------

func test_slide_moves_the_anchor_along_the_edge_without_changing_which_edge() -> void:
	var from := Vector2.ZERO
	# Clear of the tie boundary, so derive_anchor CONVERGES rather than landing
	# on its documented 2-cycle fallback (which the nearer rect above does).
	var rect := Rect2(Vector2(200.0, -260.0), Vector2(160.0, 120.0))
	for slide in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, slide)
		assert_almost_eq(anchor.x, rect.position.x, 0.01,
			"slide %s must stay on the derived LEFT edge" % slide)
		assert_almost_eq(anchor.y, lerpf(rect.position.y, rect.position.y + rect.size.y, slide), 0.01,
			"slide %s must sit that fraction down the edge (top->bottom)" % slide)


func test_slide_default_reproduces_the_edge_centre() -> void:
	# The whole point of defaulting to 0.5: every call site that predates
	# `slide` keeps its exact previous result.
	var from := Vector2.ZERO
	for rect in [
		Rect2(Vector2(100.0, -260.0), Vector2(160.0, 120.0)),
		Rect2(Vector2(-260.0, -260.0), Vector2(160.0, 120.0)),
		Rect2(Vector2(-45.0, -300.0), Vector2(90.0, 80.0)),
		Rect2(Vector2(-40.0, 120.0), Vector2(80.0, 60.0)),
	]:
		assert_eq(
			FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC),
			FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, 0.5),
			"omitting slide must equal slide == 0.5 for %s" % rect)


func test_slide_on_a_horizontal_edge_runs_left_to_right() -> void:
	var from := Vector2.ZERO
	# Almost directly above -> arrives DOWNWARD is impossible; a panel below the
	# node is the TOP-edge case, where slide must run left->right.
	var rect := Rect2(Vector2(-40.0, 120.0), Vector2(80.0, 60.0))
	var lo := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, 0.0)
	var hi := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, 1.0)
	assert_almost_eq(lo.y, hi.y, 0.01, "both stay on the same horizontal edge")
	assert_almost_eq(lo.x, rect.position.x, 0.01, "slide 0 -> left corner")
	assert_almost_eq(hi.x, rect.position.x + rect.size.x, 0.01, "slide 1 -> right corner")


func test_slid_anchor_is_still_reached_by_a_perpendicular_closing_leg() -> void:
	# The guarantee that must survive sliding: the arrival leg is perpendicular
	# to the edge it lands on, never running alongside it.
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(200.0, -260.0), Vector2(160.0, 120.0))
	for slide in [0.15, 0.5, 0.85]:
		var anchor := FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, slide)
		var pts := _route_to(from, anchor)
		var leg := pts[pts.size() - 1] - pts[pts.size() - 2]
		assert_almost_eq(leg.y, 0.0, 0.01,
			"slide %s: closing leg into a vertical edge must be horizontal" % slide)
		assert_true(leg.x > 0.0, "slide %s: and must arrive rightward into the LEFT edge" % slide)

# --- solve_route: the authored arrival axis -----------------------------------
#
# `derive_anchor` above answers "where does the route WANT to land". These cover
# the other half added for FanUnit.arrival_axis: "land it HERE, and work out the
# trunk that makes that true". The distinction that matters is that the axis is
# a constraint the solver satisfies exactly — not a preference it approximates —
# so every assertion below is on the route TraceRouter actually draws, never on
# the solver's own arithmetic.


func _params(trunk_dir: Vector2 = _TRUNK_DIR, trunk_frac: float = _TRUNK_FRAC) -> Dictionary:
	return {"trunk": trunk_frac, "trunk_dir": trunk_dir}


func _solved_route(from: Vector2, _rect: Rect2, solved: Dictionary, trunk_dir: Vector2 = _TRUNK_DIR) -> PackedVector2Array:
	return TraceRouter.compute_trace_points(from, solved.anchor, TraceRouter.Style.PCB, {
		"trunk": _TRUNK_FRAC, "trunk_dir": trunk_dir, "trunk_px": solved.trunk_px,
	})


func _closing_leg(pts: PackedVector2Array) -> Vector2:
	return pts[pts.size() - 1] - pts[pts.size() - 2]


func test_auto_axis_is_derive_anchor_unchanged() -> void:
	# AUTO must force nothing: it is the existing behaviour verbatim, which is
	# what lets every unit default to it without any of them moving.
	var from := Vector2.ZERO
	for rect in [
		Rect2(Vector2(100.0, -260.0), Vector2(160.0, 120.0)),
		Rect2(Vector2(-260.0, -260.0), Vector2(160.0, 120.0)),
		Rect2(Vector2(-20.0, -340.0), Vector2(40.0, 40.0)),
	]:
		var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.AUTO, 0.5)
		assert_eq(solved.anchor, FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, 0.5),
			"AUTO must equal derive_anchor for %s" % rect)
		assert_almost_eq(float(solved.trunk_px), 0.0, 0.001,
			"AUTO with no authored length must leave the trunk fractional")


func test_forced_horizontal_arrives_sideways_where_auto_would_not() -> void:
	# The shipped Addons geometry, near enough: a panel up and to the right at
	# roughly 45°, which is precisely where AUTO's candidate<->actual iteration
	# 2-cycles and hands back a vertical arrival on a vertical edge.
	var from := Vector2(-108.0, 98.0)
	var rect := Rect2(Vector2(-75.0, -65.0), Vector2(150.0, 130.0))

	var auto_leg := _closing_leg(_route_to(from, FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC)))
	assert_gt(absf(auto_leg.y), absf(auto_leg.x), "precondition: AUTO closes vertically here")

	var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	var leg := _closing_leg(_solved_route(from, rect, solved))
	assert_gt(absf(leg.x), absf(leg.y), "HORIZONTAL must close on x")
	assert_gt(leg.x, 0.0, "and arrive rightward, into the LEFT edge it approaches")
	assert_almost_eq(solved.anchor.x, rect.position.x, 0.01, "anchor sits on the facing (LEFT) edge")
	assert_almost_eq(solved.anchor.y, rect.get_center().y, 0.01, "slide 0.5 keeps it at the edge centre")


func test_the_two_axes_split_the_same_geometry_in_opposite_directions() -> void:
	# One panel, comfortably satisfiable either way, asked for each arrival in
	# turn. This is the knob's whole claim: the SAME placement can be entered
	# from the side or from below, and which one you get is authored rather than
	# discovered. (A panel far enough sideways that AUTO closes horizontally is
	# NOT usable here — past `span - perp` a vertical arrival stops existing at
	# all, which is the fallback case below, not this one.)
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(20.0, -320.0), Vector2(120.0, 100.0))

	var horizontal := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	var h_leg := _closing_leg(_solved_route(from, rect, horizontal))
	assert_gt(absf(h_leg.x), absf(h_leg.y), "HORIZONTAL must close on x")
	assert_gt(h_leg.x, 0.0, "arriving rightward")
	assert_almost_eq(horizontal.anchor.x, rect.position.x, 0.01, "into the facing LEFT edge")

	var vertical := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.VERTICAL, 0.5)
	var v_leg := _closing_leg(_solved_route(from, rect, vertical))
	assert_gt(absf(v_leg.y), absf(v_leg.x), "VERTICAL must close on y")
	assert_lt(v_leg.y, 0.0, "arriving upward")
	assert_almost_eq(vertical.anchor.y, rect.position.y + rect.size.y, 0.01, "into the facing BOTTOM edge")

	assert_gt(float(horizontal.trunk_px), float(vertical.trunk_px),
		"and a sideways arrival is exactly a LONGER run up before the bend")


func test_a_forced_arrival_clears_the_minimum_leg_rather_than_winning_by_a_hair() -> void:
	# Satisfying the inequality alone permits a sub-pixel leg that reads as a
	# corner. MIN_ARRIVAL_LEG is the margin that keeps it visibly perpendicular.
	var from := Vector2(-108.0, 98.0)
	var rect := Rect2(Vector2(-75.0, -65.0), Vector2(150.0, 130.0))
	var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	var leg := _closing_leg(_solved_route(from, rect, solved))
	assert_gte(leg.length(), FanAnchor.MIN_ARRIVAL_LEG - 0.01,
		"closing leg %s must clear MIN_ARRIVAL_LEG" % leg)


func test_authored_trunk_length_is_honoured_when_it_respects_the_axis() -> void:
	var from := Vector2(-108.0, 98.0)
	var rect := Rect2(Vector2(-75.0, -65.0), Vector2(150.0, 130.0))
	var free := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	# Longer than the solver's own minimum, and still inside the span -> mine.
	var desired := float(free.trunk_px) + 10.0
	var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5, desired)
	assert_almost_eq(float(solved.trunk_px), desired, 0.01,
		"an authored length that respects the constraint must be used as-is")
	var leg := _closing_leg(_solved_route(from, rect, solved))
	assert_gt(absf(leg.x), absf(leg.y), "and the arrival still lands on the requested axis")


func test_authored_trunk_length_is_clamped_when_it_fights_the_axis() -> void:
	# Precedence: the axis is a constraint, the length a preference within it.
	# A too-short trunk would close vertically, so it gets pushed up to the
	# shortest one that doesn't — the knob is bounded, never ignored.
	var from := Vector2(-108.0, 98.0)
	var rect := Rect2(Vector2(-75.0, -65.0), Vector2(150.0, 130.0))
	var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5, 5.0)
	assert_gt(float(solved.trunk_px), 5.0, "a constraint-violating length must be clamped up")
	var leg := _closing_leg(_solved_route(from, rect, solved))
	assert_gt(absf(leg.x), absf(leg.y), "the axis wins over the authored length")


func test_solving_twice_is_a_fixed_point() -> void:
	# The driver writes the solved trunk onto the trace and re-solves next frame
	# from that same trace. If solve_route read its own previous answer back the
	# trunk would creep every frame; it must not.
	var from := Vector2(-108.0, 98.0)
	var rect := Rect2(Vector2(-75.0, -65.0), Vector2(150.0, 130.0))
	var once := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	var params_with_solved := _params()
	params_with_solved["trunk_px"] = once.trunk_px
	var twice := FanAnchor.solve_route(from, rect, params_with_solved, FanAnchor.Axis.HORIZONTAL, 0.5)
	assert_eq(twice.anchor, once.anchor, "re-solving must not move the anchor")
	assert_almost_eq(float(twice.trunk_px), float(once.trunk_px), 0.001,
		"re-solving must not creep the trunk — params.trunk_px is ignored by design")


func test_an_unsatisfiable_axis_falls_back_to_auto() -> void:
	# A narrow panel straight up cannot be entered horizontally: the facing edge
	# is only 8px off the pin, so no trunk length leaves a sideways remainder
	# worth MIN_ARRIVAL_LEG. Fall back rather than emitting a route that lies
	# about its own arrival. (Widen it and the constraint becomes satisfiable —
	# the limit is the sideways offset, not "straight up" as such.)
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(-8.0, -340.0), Vector2(16.0, 40.0))
	var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	assert_eq(solved.anchor, FanAnchor.derive_anchor(from, rect, _TRUNK_DIR, _TRUNK_FRAC, 0.5),
		"unsatisfiable HORIZONTAL must land exactly where AUTO would")


func test_forced_axis_respects_a_downward_trunk() -> void:
	# `Roots` sprouts downward, and a radial variant may point anywhere — the
	# solver decomposes in the trunk's own frame rather than assuming "up".
	var down := Vector2(0.0, 1.0)
	var from := Vector2.ZERO
	var rect := Rect2(Vector2(90.0, 140.0), Vector2(140.0, 100.0))
	var solved := FanAnchor.solve_route(from, rect, _params(down), FanAnchor.Axis.HORIZONTAL, 0.5)
	var leg := _closing_leg(_solved_route(from, rect, solved, down))
	assert_gt(absf(leg.x), absf(leg.y), "HORIZONTAL must close on x under a downward trunk too")
	assert_almost_eq(solved.anchor.x, rect.position.x, 0.01, "arriving rightward -> LEFT edge")


func test_forced_axis_never_overshoots_into_the_panel() -> void:
	# The no-overshoot guarantee must survive a solved trunk, which is longer
	# than the fractional one it replaces.
	var from := Vector2(-108.0, 98.0)
	var rect := Rect2(Vector2(-75.0, -65.0), Vector2(150.0, 130.0))
	for slide in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, slide)
		for p in _solved_route(from, rect, solved):
			assert_false(FanAnchor.is_inside(p, rect),
				"slide %s: no route point may land inside the panel" % slide)


# --- the unsatisfiable fallback is REPORTED, never announced -------------------

func test_an_unsatisfiable_forced_axis_reports_itself_in_the_route() -> void:
	# The exact geometry a dragged bench panel produced: a panel almost directly
	# above the pin cannot be entered horizontally. `solve_route` runs once per
	# unit per FRAME, so it must hand this fact back for the driver to announce
	# once — a push_warning here spammed the console at frame rate.
	var from := Vector2(191.83, -112.8)
	var rect := Rect2(Vector2(-88.5, -100.0), Vector2(177.0, 200.0))
	var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	assert_true(bool(solved.unsatisfiable),
		"an unsatisfiable forced axis must be flagged on the returned route")
	assert_false(String(solved.reason).is_empty(),
		"...with the human-readable why, so the driver need not re-derive it")
	var auto_solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.AUTO, 0.5)
	assert_eq(solved.anchor, auto_solved.anchor,
		"and the fallback is still exactly the AUTO answer")


func test_a_satisfiable_forced_axis_is_not_flagged() -> void:
	var from := Vector2(-108.0, 98.0)
	var rect := Rect2(Vector2(-75.0, -65.0), Vector2(150.0, 130.0))
	var solved := FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.HORIZONTAL, 0.5)
	assert_false(bool(solved.unsatisfiable),
		"a satisfiable constraint must not report a fallback")
	assert_true(bool(FanAnchor.solve_route(from, rect, _params(), FanAnchor.Axis.AUTO, 0.5).unsatisfiable) == false,
		"and AUTO — which forces nothing — never can")
