extends GutTest

## #569 — the frontmatter draws with the real SkillNode visuals and the real
## edge shader, and with none of the gameplay machinery that normally drives
## them.
##
## The load-bearing tests here are the two tree walks. #567's whole "how real is
## the tree" decision is *menu-local model, stolen visuals*, and the only way
## that stays true is to check it: a stray [SkillNode] would work fine on the
## day it was added and drag [Graph], [Entity] and a [StatBoard] in behind it.
## So the walks are real recursion over the built scene, not a comment.

const _NODE_VIEW := preload("res://ui/frontmatter/menu_node_view.tscn")
const _EDGE_VIEW := preload("res://ui/frontmatter/menu_edge_view.tscn")

## The six archetypes and the `tint_color` each one's primary stat carries.
## Authored here as literals on purpose: this is the table #569 settled after
## the design canvas's own `hue` field disagreed with the repo on two of them,
## and a test that read the colour back out of the same resource it is checking
## would agree with any future drift.
const _EXPECTED_TINTS := {
	&"strength": Color(0.945, 0.271, 0.247),
	&"dexterity": Color(0.318, 0.776, 0.447),
	&"intelligence": Color(0.290, 0.588, 1.000),
	&"wisdom": Color(0.902, 0.733, 0.275),
	&"perception": Color(0.694, 0.404, 0.969),
	&"constitution": Color(0.859, 0.902, 0.949),
}


func _make_node_view(archetype_id: StringName, allocated: bool = false) -> MenuNodeView:
	var view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(view)
	view.archetype = MenuNodeView.archetype_for(archetype_id)
	view.allocated = allocated
	return view


func _make_edge_view() -> MenuEdgeView:
	var edge: MenuEdgeView = _EDGE_VIEW.instantiate()
	add_child_autofree(edge)
	return edge


func _visuals_of(view: MenuNodeView) -> Node2D:
	return view.get_node("%Visuals") as Node2D


# --- the absence that the whole design rests on -----------------------------

## Recursively collects every class this menu must not instantiate, plus every
## one of them reachable as a script variable — [StatBoard] is a [Resource],
## so a walk that only looked at node types would miss the one that arrives
## attached to something else.
func _forbidden_in(root: Node) -> Array[String]:
	var found: Array[String] = []
	if root is Graph:
		found.append("%s is a Graph" % root.name)
	if root is SkillNode:
		found.append("%s is a SkillNode" % root.name)
	if root is Entity:
		found.append("%s is an Entity" % root.name)
	if root is Edge:
		found.append("%s is an Edge" % root.name)
	for property in root.get_property_list():
		if (property["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = root.get(property["name"])
		if value is StatBoard or value is Graph or value is SkillNode or value is Entity:
			found.append("%s.%s holds a %s" % [root.name, property["name"], value.get_class()])
	for child in root.get_children():
		found.append_array(_forbidden_in(child))
	return found


func test_a_node_view_has_no_gameplay_machinery_anywhere_in_it() -> void:
	# It instances `node_visuals_composite.tscn`, which is fed by SkillNode and
	# never reaches up — not `skill_node.tscn`, which works standalone but is
	# gameplay behaviour the menu has no use for.
	var view := _make_node_view(&"strength", true)
	assert_eq(_forbidden_in(view), [] as Array[String])
	assert_gt(view.get_child_count(), 0, "and it is not empty — something is drawing")


func test_an_edge_view_has_no_gameplay_machinery_anywhere_in_it() -> void:
	# `graph/edge.tscn` fails on two counts — SkillNode-typed endpoints, and it
	# delegates its drawing to a Graph-level batched renderer — so the menu owns
	# a thin renderer over the same shader instead.
	var edge := _make_edge_view()
	edge.set_endpoints(Vector2.ZERO, Vector2(306, 0))
	assert_eq(_forbidden_in(edge), [] as Array[String])


func test_the_whole_frontmatter_tree_stays_clean_when_it_is_built() -> void:
	# The walks above are per-view; this is the assembled thing #570 will build,
	# every node and every edge of the real menu graph at once.
	var tree := MenuGraph.build()
	var host := Node2D.new()
	add_child_autofree(host)
	var views: Dictionary = {}
	for id in tree.ids():
		var view: MenuNodeView = _NODE_VIEW.instantiate()
		host.add_child(view)
		view.bind(FrontmatterLayout.look_of(id), id == tree.root)
		views[id] = view
	for id in tree.ids():
		for child_id in tree.children_of(id):
			var edge: MenuEdgeView = _EDGE_VIEW.instantiate()
			host.add_child(edge)
			edge.connect_views(views[id], views[child_id])
	assert_eq(_forbidden_in(host), [] as Array[String])


# --- identity ---------------------------------------------------------------

func test_the_six_archetypes_map_to_the_six_tint_colors() -> void:
	for id in _EXPECTED_TINTS:
		var archetype := MenuNodeView.archetype_for(id)
		assert_not_null(archetype, "'%s' is a menu archetype" % id)
		var want: Color = _EXPECTED_TINTS[id]
		var got := archetype.color
		assert_almost_eq(got.r, want.r, 0.001, "%s red" % id)
		assert_almost_eq(got.g, want.g, 0.001, "%s green" % id)
		assert_almost_eq(got.b, want.b, 0.001, "%s blue" % id)


func test_options_is_purple_and_exit_is_white_the_canvas_hues_lost() -> void:
	# The design canvas gives perception hue 200 (cyan) and constitution 305
	# (magenta). `Archetype.color` reads through to the primary stat's
	# tint_color and the repo wins, so OPTIONS is purple and EXIT near-white.
	var options := MenuNodeView.archetype_for(
			FrontmatterLayout.look_of(MenuGraph.ID_OPTIONS).archetype)
	assert_gt(options.color.b, options.color.g, "perception is purple, not cyan")
	assert_gt(options.color.r, options.color.g, "perception is purple, not cyan")

	var exit := MenuNodeView.archetype_for(
			FrontmatterLayout.look_of(MenuGraph.ID_EXIT).archetype)
	assert_almost_eq(exit.color.r, exit.color.b, 0.15, "constitution is near-white")
	assert_gt(exit.color.g, 0.8, "constitution is near-white, not magenta")


func test_a_node_view_pushes_its_archetype_into_the_real_composite() -> void:
	var view := _make_node_view(&"wisdom", true)
	var visuals := _visuals_of(view)
	var want: Color = _EXPECTED_TINTS[&"wisdom"]
	assert_almost_eq(visuals.archetype_tint.r, want.r, 0.001)
	assert_almost_eq(visuals.archetype_tint.g, want.g, 0.001)
	assert_almost_eq(visuals.archetype_tint.b, want.b, 0.001)
	# The menu has no entities, so both identities collapse onto one colour.
	assert_eq(visuals.entity_tint, visuals.archetype_tint)
	assert_eq(visuals.carve_shape, view.archetype.carve_shape, "the carve comes with it")


func test_allocation_is_the_focus_path_and_the_composite_derives_it() -> void:
	# `allocation_level` is the composite's sole source of truth for `allocated`
	# — assigning `allocated` on it directly would be assigning a derived value.
	var focused := _make_node_view(&"dexterity", true)
	assert_eq(_visuals_of(focused).allocation_level, 1)
	assert_true(_visuals_of(focused).allocated)

	var sibling := _make_node_view(&"dexterity", false)
	assert_eq(_visuals_of(sibling).allocation_level, 0)
	assert_false(_visuals_of(sibling).allocated, "unallocated siblings render unallocated")


func test_radius_reaches_the_children_rather_than_only_redrawing() -> void:
	# `SkillNodeVisual.radius`'s setter only calls queue_redraw() — it does not
	# push down. A plain assignment silently changes nothing, so the view must
	# go through configure().
	var view := _make_node_view(&"strength")
	view.radius = 48.0
	var visuals := _visuals_of(view)
	assert_almost_eq(visuals.radius, 48.0, 0.001)
	assert_almost_eq(visuals.geom_outer_r, 48.0, 0.001)
	assert_almost_eq(visuals.geom_inner_r, 36.0, 0.001, "the rim keeps its 24:32 proportion")
	var pushed := 0
	for child in visuals.get_node("%InnerDisk").get_parent().get_children():
		if not (child is SkillNodeVisual):
			continue
		pushed += 1
		assert_almost_eq((child as SkillNodeVisual).radius, 48.0, 0.001,
				"%s got the new radius" % child.name)
	assert_gt(pushed, 0, "there are children to push to")


func test_binding_an_authored_look_fills_in_everything_at_once() -> void:
	# #591: the caption, the tint and the RADIUS all come off the fan scene's
	# slot in one call. `MenuGraph` carries none of them any more, which is why
	# this reads the look table rather than the tree.
	var look := FrontmatterLayout.look_of(MenuGraph.ID_MULTIPLAYER)
	var view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(view)
	view.bind(look, true)
	assert_eq(view.title, "MULTIPLAYER")
	assert_eq(view.archetype, MenuNodeView.archetype_for(&"dexterity"))
	assert_almost_eq(view.radius, look.radius, 0.001, "the slot sizes the disk")
	assert_true(view.allocated)
	assert_eq(view.get_node("%Title").text, "MULTIPLAYER")


func test_binding_nothing_leaves_the_composites_own_defaults() -> void:
	# An id nothing authors is caught by `solve()`'s 1:1 cross-check; the view
	# is not the place to hear about it, so a null look is inert rather than
	# fatal.
	var view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(view)
	view.bind(null, true)
	assert_eq(view.title, "")
	assert_null(view.archetype)
	assert_true(view.allocated)


func test_an_unbranded_view_renders_the_composites_own_default() -> void:
	var view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(view)
	assert_null(MenuNodeView.archetype_for(&"not_an_archetype"))
	assert_eq(view.display_color(), _visuals_of(view).archetype_tint)


# --- the edge, over the real shader -----------------------------------------

func test_the_edge_transform_is_edges_own_convention() -> void:
	# Copied from `Edge._push_transform()`: origin at the midpoint, x-basis
	# along the segment and scaled to its length. The shader expands local Y
	# into a screen-constant width, so a wrong convention draws a hairline
	# somewhere else rather than nothing at all.
	var a := Vector2(100, 200)
	var b := Vector2(406, 200)
	var xf := MenuEdgeView.segment_transform(a, b)
	assert_almost_eq(xf.origin.x, 253.0, 0.001, "origin is the midpoint")
	assert_almost_eq(xf.origin.y, 200.0, 0.001)
	assert_almost_eq(xf.x.length(), 306.0, 0.001, "x-basis spans the segment")
	assert_almost_eq(xf.get_rotation(), 0.0, 0.001)

	var diagonal := MenuEdgeView.segment_transform(Vector2.ZERO, Vector2(10, 10))
	assert_almost_eq(diagonal.get_rotation(), PI / 4.0, 0.001, "and points along it")
	assert_almost_eq(diagonal.x.length(), Vector2(10, 10).length(), 0.001)


func test_the_edge_view_draws_through_the_shipped_edge_material() -> void:
	var edge := _make_edge_view()
	assert_true(edge.material is ShaderMaterial, "the real edge material, not a new one")
	assert_eq((edge.material as ShaderMaterial).shader,
			load("res://graph/edge_mesh.gdshader"))
	assert_not_null(edge.multimesh)
	# #592: the curve is `curve_segments` chained straight instances, not one —
	# assert against the export rather than a hardcoded count so this doesn't
	# re-pin the old single-segment shape.
	assert_eq(edge.multimesh.instance_count, edge.curve_segments)
	assert_eq(edge.multimesh.visible_instance_count, edge.curve_segments)
	assert_true(edge.multimesh.use_colors and edge.multimesh.use_custom_data,
			"per-endpoint colour is per-instance data, exactly as Graph sends it")
	assert_eq(edge.multimesh.transform_format, MultiMesh.TRANSFORM_2D)


func test_each_end_of_an_edge_takes_its_own_nodes_colour() -> void:
	# The shader mixes COLOR and INSTANCE_CUSTOM.rgb along UV.x, so the
	# along-edge gradient is free — an edge from a red node to a green one
	# really does run red to green.
	var from_view := _make_node_view(&"strength", true)
	var to_view := _make_node_view(&"dexterity", true)
	to_view.position = Vector2(306, 0)
	var edge := _make_edge_view()
	edge.connect_views(from_view, to_view)

	assert_true(edge.lit, "both ends are on the focus path")
	var red := edge.endpoint_color(from_view.display_color())
	var green := edge.endpoint_color(to_view.display_color())
	assert_gt(red.r, red.g, "the from end stays strength-red")
	assert_gt(green.g, green.r, "the to end stays dexterity-green")
	assert_ne(red, green, "there is a gradient to mix")


func test_an_unlit_edge_desaturates_and_dims_instead_of_glowing() -> void:
	var edge := _make_edge_view()
	var base := MenuNodeView.archetype_for(&"strength").color

	edge.lit = true
	var on := edge.endpoint_color(base)
	edge.lit = false
	var off := edge.endpoint_color(base)

	assert_gt(on.r, 1.0, "a lit edge overshoots 1.0 so the bloom pass has something to catch")
	assert_lt(off.r, base.r, "an unlit one darkens")
	assert_lt(off.a, on.a, "and fades")
	assert_lt(absf(off.r - off.g), absf(base.r - base.g), "and desaturates toward its own grey")


func test_the_lift_keeps_the_hue_instead_of_blowing_the_edge_white() -> void:
	# Why the lift is applied to each channel's rise above the colour's own grey
	# floor and not to the raw channels: a flat multiply keeps the ratio, so the
	# weak channels clip alongside the dominant one and the line reads white.
	var edge := _make_edge_view()
	edge.lit = true
	var lifted := edge.endpoint_color(MenuNodeView.archetype_for(&"strength").color)
	assert_gt(lifted.r, 1.0, "the dominant channel blows past 1.0")
	assert_lt(lifted.g, 1.0, "the weak ones do not — the edge stays red, not white")
	assert_lt(lifted.b, 1.0)


func test_the_menu_feeds_the_shader_a_constant_visible_state() -> void:
	# No VisionSystem here, so no fog, sensed or hidden state to carry — and
	# `vision_field_dim` passes VISIBLE straight through while
	# `vision_field_enabled` is false.
	var edge := _make_edge_view()
	edge.set_endpoint_colors(Color.RED, Color.GREEN)
	var custom := edge.multimesh.get_instance_custom_data(0)
	assert_almost_eq(custom.a, Edge.VIS_VISIBLE, 0.001)


func test_endpoints_are_read_in_the_views_parent_space() -> void:
	# Same convention Graph uses when it subtracts its own global_position, so
	# an edge view parked off the origin still lands on the solved positions.
	#
	# Built from `curve_point()` rather than read out of the MultiMesh: Godot's
	# headless dummy driver no-ops the per-instance read/write path entirely
	# (the same blind spot that hid #413's invisible edges from every headless
	# probe), so a read-back assertion here would pass on an identity transform.
	#
	# These endpoints are level, and both control points are pulled along X
	# only, so the whole Bezier collapses onto the straight chord — which is
	# what lets this keep asserting the exact span it always did.
	var edge := _make_edge_view()
	edge.position = Vector2(50, 50)
	edge.set_endpoints(Vector2(50, 50), Vector2(356, 50))
	var xf := edge.segment_transform(
			edge.curve_point(0.0) - edge.position, edge.curve_point(1.0) - edge.position)
	assert_almost_eq(xf.origin.x, 153.0, 0.001, "the midpoint, measured from the view")
	assert_almost_eq(xf.origin.y, 0.0, 0.001)
	assert_almost_eq(xf.x.length(), 306.0, 0.001)


func test_the_camera_zoom_the_shader_reads_is_pushable() -> void:
	# `width` is authored in SCREEN pixels and divided by this global, which only
	# GraphCamera writes in game. #570 owns calling this; the seam is here.
	#
	# The NAME is what is asserted, against the registration in project.godot: a
	# shader reading an unregistered global silently gets the default instead of
	# an error, so a typo here would be invisible forever. The VALUE is not read
	# back — `global_shader_parameter_get` returns null under the headless dummy
	# renderer.
	var registered: Variant = ProjectSettings.get_setting(
			"shader_globals/%s" % MenuEdgeView.CAMERA_ZOOM_UNIFORM)
	assert_not_null(registered, "the shader global the menu pushes is registered")
	assert_eq((registered as Dictionary)["type"], "float")
	MenuEdgeView.push_camera_zoom(2.0)


# --- the pick region (#583) ---------------------------------------------------

func _pick_of(view: MenuNodeView) -> MenuNodePickRegion:
	return view.get_node("%PickRegion") as MenuNodePickRegion


func test_the_hit_area_is_a_control_so_hover_preview_can_disable_it() -> void:
	# [HoverPreview] enforces "a peek-ahead is not clickable" by walking a view's
	# Control descendants. An Area2D would be invisible to that walk, so a
	# collapsed node would stay clickable through its own preview — which is a
	# second picking rule to keep in sync with the first.
	var view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(view)
	var pick := _pick_of(view)
	assert_not_null(pick, "the view has a pick region")
	assert_true(pick is Control, "and it is a Control")
	assert_eq(pick.mouse_filter, Control.MOUSE_FILTER_STOP, "which takes the mouse")
	assert_eq(
		HoverPreview._controls_under(view).find(pick) >= 0, true,
		"and HoverPreview's walk can see it"
	)


func test_the_hit_area_is_a_disk_the_size_of_the_node() -> void:
	var view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(view)
	view.radius = 48.0
	var pick := _pick_of(view)
	assert_almost_eq(pick.radius, 48.0, 0.001, "the hit area follows the radius")
	assert_true(pick._has_point(pick.size * 0.5), "the centre is inside")
	assert_false(pick._has_point(Vector2.ZERO), "a corner of the rect is not")


func test_a_left_click_reaches_the_view_as_one_signal() -> void:
	var view: MenuNodeView = _NODE_VIEW.instantiate()
	add_child_autofree(view)
	watch_signals(view)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_pick_of(view)._gui_input(click)
	assert_signal_emitted(view, "activated")
