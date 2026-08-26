extends GutTest

## #572 / #601 — the hero's incoming edge is the back button, and it is a UI
## element sat on it rather than a thing drawn under the graph camera.
##
## Two of these tests are about something this unit deliberately does NOT do.
## The owner's constraint is that the hero [i]"still has its edge connected to
## the left of it going off-screen, it's lit and all"[/i], and under #567's
## camera that edge is already real and already lit — so
## `test_the_incoming_edge_is_already_lit_at_every_depth` asserts it on the
## edge #570 built, not on anything authored here. If this unit ever grows its
## own stub, that test keeps passing and
## `test_the_affordance_draws_no_edge_of_its_own` is what fails.

const _SCENE := preload("res://ui/frontmatter/back_affordance.tscn")
const _ROOT_SCENE := preload("res://ui/frontmatter/frontmatter_root.tscn")

## Every id below the root, which is exactly "every id that must have an
## affordance". Derived from the tree rather than listed, so a new menu entry
## is covered the day it is added.
var _tree: MenuGraph
var _affordance: BackAffordance


func before_each() -> void:
	_tree = MenuGraph.build()
	_affordance = _SCENE.instantiate()
	add_child_autofree(_affordance)
	_affordance.bind(_tree)


func _below_root() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _tree.ids():
		if id != _tree.root:
			ids.append(id)
	return ids


# --- present below the root, absent at it -----------------------------------

func test_the_root_has_no_parent_and_so_no_affordance() -> void:
	_affordance.apply(_tree.root)
	assert_false(BackAffordance.is_available(_tree, _tree.root))
	assert_false(_affordance.visible, "absent, not disabled")


func test_every_depth_below_the_root_has_one() -> void:
	for id in _below_root():
		_affordance.apply(id)
		assert_true(BackAffordance.is_available(_tree, id), "%s can go back" % id)
		assert_true(_affordance.visible, "%s shows the affordance" % id)
		assert_almost_eq(_affordance.modulate.a, 1.0, 0.0001, "%s: fully applied" % id)


func test_an_unknown_focus_offers_nothing() -> void:
	assert_false(BackAffordance.is_available(_tree, &"not_a_menu_item"))
	_affordance.apply(&"not_a_menu_item")
	assert_false(_affordance.visible)


# --- it is a screen-space Control, not a Node2D under the camera (#601) -----

func test_the_root_is_a_control_reachable_only_through_the_screen_space_layer() -> void:
	var untyped: Node = _affordance
	assert_true(untyped is Control, "the scene root is a Control")
	assert_false(untyped is Node2D, "not the old graph-space Node2D")

	var root: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(root)
	var node: Node = root.get_node("%BackAffordance").get_parent()
	var crossed_canvas_layer := false
	while node != null and node != root:
		assert_false(node is Camera2D, "no ancestor between it and the viewport is the graph camera")
		if node is CanvasLayer:
			crossed_canvas_layer = true
		node = node.get_parent()
	assert_true(crossed_canvas_layer,
			"reparented under the screen-space CanvasLayer, not %GraphLayer")


## Half the hero slot's x, and the hero slot's own y — a screen-space
## constant, not a point derived from a hero/parent segment.
func test_the_anchor_sits_at_half_the_hero_slots_x_and_the_heros_y() -> void:
	var hero := FrontmatterLayout.hero_slot()
	assert_eq(BackAffordance.anchor_for(), Vector2(hero.x * 0.5, hero.y))


## The whole point of the re-root: this position does not answer to the
## camera at all, so it is identical at every depth and in every fan — the
## root fan's own camera_zoom (1.35) included, even though the root itself has
## no affordance to point it at.
func test_the_position_is_identical_at_every_depth_and_every_fan() -> void:
	var root_zoom := FrontmatterLayout.zoom_for(_tree, MenuGraph.ID_ROOT)
	var leaf_zoom := FrontmatterLayout.zoom_for(_tree, MenuGraph.ID_NEW_GAME)
	assert_ne(root_zoom, leaf_zoom, "the two zooms this claim is actually about differ")

	var root: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(root)
	root.reduce_motion = true
	var affordance: BackAffordance = root.get_node("%BackAffordance")
	var expected := BackAffordance.anchor_for()
	for id in _below_root():
		root.focus(id, true)
		assert_eq(affordance.position, expected, "%s: same screen point at every depth" % id)


# --- the edge itself is #570's, and stays that way --------------------------

func test_the_affordance_draws_no_edge_of_its_own() -> void:
	var found: Array[String] = []
	_collect_renderers(_affordance, found)
	assert_eq(found, [] as Array[String], "the edge is #570's; this unit is a label and a hit area")


func _collect_renderers(node: Node, into: Array[String]) -> void:
	if node is MenuEdgeView or node is MultiMeshInstance2D or node is Line2D:
		into.append("%s is a %s" % [node.name, node.get_class()])
	for child in node.get_children():
		_collect_renderers(child, into)


func test_the_incoming_edge_is_already_lit_at_every_depth() -> void:
	var root: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(root)
	root.reduce_motion = true
	for id in _below_root():
		root.focus(id, true)
		var edge := _edge_arriving_at(root, id)
		assert_not_null(edge, "%s has an incoming edge" % id)
		assert_true(edge.lit, "%s's incoming edge renders lit/allocated" % id)


## #570 names each edge for the node it arrives at (`_build_edges`), a tree
## having exactly one incoming edge per node.
func _edge_arriving_at(root: FrontmatterRoot, id: StringName) -> MenuEdgeView:
	var layer := root.get_node("%GraphLayer")
	return layer.get_node_or_null("edge_%s" % id) as MenuEdgeView


# --- pressing it ------------------------------------------------------------

## The acceptance, end to end: the affordance asks, the shell answers, focus
## lands on the parent. The one connect() below is the whole of the wiring.
func test_pressing_it_moves_focus_to_the_parent() -> void:
	var root: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(root)
	root.reduce_motion = true
	_affordance.bind(root.tree)
	_affordance.back_requested.connect(func() -> void: root.back())

	root.focus(MenuGraph.ID_NEW_GAME, true)
	_affordance.apply(root.focus_id)
	_affordance.press()
	assert_eq(root.focus_id, MenuGraph.ID_SINGLE_PLAYER, "up one level")

	_affordance.apply(root.focus_id)
	_affordance.press()
	assert_eq(root.focus_id, MenuGraph.ID_ROOT, "and again")

	_affordance.apply(root.focus_id)
	assert_false(_affordance.visible, "and then there is nowhere left to go")


func test_it_asks_rather_than_navigating() -> void:
	var asked: Array[int] = []
	_affordance.back_requested.connect(func() -> void: asked.append(1))
	_affordance.press()
	assert_eq(asked.size(), 1, "one signal, no navigator held")


# --- reveal and tier --------------------------------------------------------

func test_set_progress_fades_and_grows_it() -> void:
	_affordance.apply(MenuGraph.ID_NEW_GAME, false)
	assert_almost_eq(_affordance.modulate.a, 0.0, 0.0001, "t = 0 is invisible")
	assert_almost_eq(_affordance.scale.x, _affordance.start_scale, 0.0001, "and small")
	_affordance.set_progress(1.0)
	assert_almost_eq(_affordance.modulate.a, 1.0, 0.0001)
	assert_almost_eq(_affordance.scale.x, 1.0, 0.0001)


## The glass backing is a plain child of the root [Control], so the root's own
## transform and modulate already carry it to the screen — one clock, checked
## at the endpoints, never a second curve for the glass.
func test_the_glass_backing_shares_the_labels_reveal_clock() -> void:
	var glass: Control = _affordance.get_node("Glass")
	assert_true(glass is GlassPanel, "the house glass skin backs the button")

	_affordance.apply(MenuGraph.ID_NEW_GAME, false)
	assert_almost_eq(_affordance.modulate.a, 0.0, 0.0001, "t=0: root (and glass with it) invisible")
	assert_almost_eq(_affordance.scale.x, _affordance.start_scale, 0.0001, "t=0: and small")

	_affordance.set_progress(1.0)
	assert_almost_eq(_affordance.modulate.a, 1.0, 0.0001, "t=1: root (and glass with it) full")
	assert_almost_eq(_affordance.scale.x, 1.0, 0.0001, "t=1: and full scale")


func test_hit_sits_over_the_glass_with_every_stylebox_state_emptied() -> void:
	var hit: Button = _affordance.get_node("%Hit")
	for state in ["normal", "pressed", "hover", "disabled", "focus"]:
		assert_true(hit.get_theme_stylebox(state) is StyleBoxEmpty,
				"'%s' is emptied so the glass shows through rather than the theme's own chrome" % state)


## Ghostly [constant Emissive.INERT] rest is retired — owner call, 2026-08-26:
## raise to [constant Emissive.LABEL], hover steps to [constant Emissive.VALUE].
func test_the_label_rests_at_the_label_tier_and_answers_a_step_up() -> void:
	assert_eq(_affordance.rest_stops, Emissive.LABEL, "raised from the old ghostly rest")
	assert_eq(_affordance.rest_color(), Emissive.neutral(Emissive.LABEL))
	_affordance._on_hover(true)
	assert_eq(_affordance.rest_color(), Emissive.neutral(Emissive.VALUE))
	assert_gt(
		_affordance.rest_color().get_luminance(),
		Emissive.neutral(Emissive.LABEL).get_luminance(),
		"pointing at it brightens it",
	)
