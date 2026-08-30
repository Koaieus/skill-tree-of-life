extends GutTest

## #592 (C3) — the menu edge is a sigmoid, not a straight segment: a cubic
## Bezier whose control points are pulled purely horizontally off both
## endpoints, so the curve leaves its parent going right and arrives at its
## child going right, with the vertical travel folded into the middle.
##
## Asserted against [method MenuEdgeView.curve_point] — the pure function that
## FEEDS the [MultiMesh] — never against the [MultiMesh] itself: Godot's
## headless dummy driver no-ops the whole per-instance MultiMesh read/write
## path, so `get_instance_transform_2d()` comes back identity regardless of
## what was pushed. That blind spot is what hid #413's invisible edges from
## every headless probe. See `docs/domain/godot-workflow.md`.

const _EDGE_VIEW := preload("res://ui/frontmatter/menu_edge_view.tscn")


func _make_edge_view() -> MenuEdgeView:
	var edge: MenuEdgeView = _EDGE_VIEW.instantiate()
	add_child_autofree(edge)
	return edge


func test_tangent_is_horizontal_at_both_ends() -> void:
	var edge := _make_edge_view()
	edge.control_pull = 60.0
	edge.set_endpoints(Vector2(0, 0), Vector2(300, 200))
	var eps := 0.001

	var start := edge.curve_point(0.0)
	var near_start := edge.curve_point(eps)
	var dx0 := near_start.x - start.x
	var dy0 := near_start.y - start.y
	assert_gt(absf(dx0), 0.01, "leaving the parent, the curve moves horizontally")
	assert_lt(absf(dy0), absf(dx0) * 0.05,
			"and the vertical delta is negligible next to it — a horizontal tangent")

	var end := edge.curve_point(1.0)
	var near_end := edge.curve_point(1.0 - eps)
	var dx1 := end.x - near_end.x
	var dy1 := end.y - near_end.y
	assert_gt(absf(dx1), 0.01, "arriving at the child, the curve is still moving horizontally")
	assert_lt(absf(dy1), absf(dx1) * 0.05,
			"and the vertical delta is negligible arriving too")


## Same shape check, but with the endpoints swapped top-to-bottom and a
## non-default pull, so the horizontal-tangent property isn't an artefact of
## one particular layout.
func test_tangent_is_horizontal_regardless_of_layout() -> void:
	var edge := _make_edge_view()
	edge.control_pull = 24.0
	edge.set_endpoints(Vector2(120, 400), Vector2(90, 40))
	var eps := 0.001

	var d_start := edge.curve_point(eps) - edge.curve_point(0.0)
	assert_gt(absf(d_start.x), 0.01)
	assert_lt(absf(d_start.y), absf(d_start.x) * 0.05)

	var d_end := edge.curve_point(1.0) - edge.curve_point(1.0 - eps)
	assert_gt(absf(d_end.x), 0.01)
	assert_lt(absf(d_end.y), absf(d_end.x) * 0.05)


## The endpoints spec: `curve_point(0.0)`/`curve_point(1.0)` equal the two live
## view positions EXACTLY, and stay exact across a whole sequence of
## `set_endpoints()` calls standing in for `_push_edges()` driving the curve
## every frame of the 850ms sprout (t=0, mid-flight, t=1). Rebuilding from the
## live endpoints on every call — not caching the curve from build time — is
## exactly what makes that true; a cached curve would still read the OLD
## endpoints here.
func test_curve_endpoints_exactly_match_live_positions_every_frame() -> void:
	var edge := _make_edge_view()

	var moments := [
		[Vector2(10, 20), Vector2(400, 20)],
		[Vector2(80, 55), Vector2(310, 140)],
		[Vector2(150, 90), Vector2(150, 260)],
	]
	for moment in moments:
		var from: Vector2 = moment[0]
		var to: Vector2 = moment[1]
		edge.set_endpoints(from, to)
		assert_eq(edge.curve_point(0.0), from, "t=0 is exactly the parent's live position")
		assert_eq(edge.curve_point(1.0), to, "t=1 is exactly the child's live position")


## `connect_views()` is the other entry point that sets `_from`/`_to` (off two
## [MenuNodeView] positions rather than raw vectors) — same exactness applies.
func test_curve_endpoints_exactly_match_connected_view_positions() -> void:
	const _NODE_VIEW := preload("res://ui/frontmatter/menu_node_view.tscn")
	var from_view: MenuNodeView = _NODE_VIEW.instantiate()
	var to_view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(from_view)
	add_child_autofree(to_view)
	from_view.position = Vector2(20, 30)
	to_view.position = Vector2(220, 130)

	var edge := _make_edge_view()
	edge.connect_views(from_view, to_view)

	assert_eq(edge.curve_point(0.0), from_view.position)
	assert_eq(edge.curve_point(1.0), to_view.position)


## N is an `@export`, tunable for smoothness — and the [MultiMesh] instance
## count must track it, resizing live rather than staying pinned at whatever
## it was built with. `instance_count`/`visible_instance_count` are plain ints
## that round-trip fine under the headless dummy driver (unlike per-instance
## data), so this is a safe scalar read.
func test_curve_segments_is_tunable_and_resizes_the_multimesh() -> void:
	var edge := _make_edge_view()
	edge.set_endpoints(Vector2.ZERO, Vector2(200, 100))

	edge.curve_segments = 8
	assert_eq(edge.multimesh.instance_count, 8)
	assert_eq(edge.multimesh.visible_instance_count, 8)

	edge.curve_segments = 24
	assert_eq(edge.multimesh.instance_count, 24)
	assert_eq(edge.multimesh.visible_instance_count, 24)


## #596 — the sigmoid has to be VISIBLE, not merely present. At the old default
## pull of 60 the curve bowed ~2.6% of its own chord and read as a straight line
## at menu scale; the default is 150 now.
##
## The honest headless proxy for "visibly curved" is peak perpendicular deviation
## from the chord. It is deliberately NOT the midpoint: at t=0.5 both coordinates
## cancel to the chord midpoint for EVERY value of [member
## MenuEdgeView.control_pull], so a midpoint assertion measures nothing and would
## pass at a pull of zero.
##
## This does not prove it looks right — that is an eyeball on a real frame. It
## proves the bow is of a magnitude that CAN read.
func test_default_pull_bows_the_curve_measurably_off_its_chord() -> void:
	var edge := _make_edge_view()
	# Deliberately does NOT set control_pull — the default is what ships, and
	# the default is the thing #596 was about.
	var from := Vector2(0, 0)
	var to := Vector2(300, 200)
	edge.set_endpoints(from, to)

	var chord := to - from
	var chord_len := chord.length()
	var axis := chord / chord_len

	var peak := 0.0
	for i in range(1, 32):
		var t := float(i) / 32.0
		var offset := edge.curve_point(t) - from
		# Component of the offset perpendicular to the chord.
		var along := offset.dot(axis)
		peak = maxf(peak, (offset - axis * along).length())

	assert_gt(peak, chord_len * 0.05,
			"the default sigmoid bows at least 5% of its chord — at pull 60 it "
			+ "was ~2.6% and read as a straight line (#596)")
