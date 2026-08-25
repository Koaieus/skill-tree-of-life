extends GutTest

## #572 — the hero's incoming edge is the back button.
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


# --- it sits ON the edge ----------------------------------------------------

## The anchor has to be a point of the segment, not merely near it — the whole
## point of #572 is that the label reads as part of the edge.
func test_the_anchor_is_a_point_of_the_incoming_edge() -> void:
	var homes := FrontmatterLayout.solve(_tree)
	for id in _below_root():
		var hero: Vector2 = homes[id]
		var parent: Vector2 = homes[_tree.parent_of(id)]
		var anchor := BackAffordance.anchor_for(hero, parent)
		var span := parent - hero
		assert_almost_eq(
			span.normalized().cross((anchor - hero).normalized()), 0.0, 0.0001,
			"%s: the anchor is collinear with the edge" % id,
		)
		var along := hero.distance_to(anchor)
		assert_gt(along, 0.0, "%s: clear of the hero" % id)
		assert_lt(along, span.length(), "%s: short of the parent" % id)


## The distance is derived from the hero slot, not typed in — half of it, which
## is the midpoint of the stretch of edge that is actually on screen.
func test_the_anchor_sits_midway_along_the_visible_run_of_the_edge() -> void:
	var hero_x := FrontmatterLayout.hero_slot().x
	var anchor := BackAffordance.anchor_for(Vector2.ZERO, Vector2(-306.0, 0.0))
	assert_almost_eq(anchor.x, -hero_x * 0.5, 0.001)
	assert_almost_eq(anchor.y, 0.0, 0.001)


func test_a_degenerate_edge_does_not_divide_by_zero() -> void:
	assert_eq(BackAffordance.anchor_for(Vector2(10.0, 10.0), Vector2(10.0, 10.0)), Vector2(10.0, 10.0))


## A column step shorter than the hero slot's x must not push the label out
## past the parent — it lands on the midpoint instead.
func test_a_short_edge_clamps_the_anchor_to_its_midpoint() -> void:
	var anchor := BackAffordance.anchor_for(Vector2.ZERO, Vector2(-40.0, 0.0))
	assert_almost_eq(anchor.x, -20.0, 0.001)


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


## Ghostly is a TIER, not an alpha — `.claude/rules/hdr-color.md`'s house rule
## is that alpha is the fade channel and colour value is the dimmer, and alpha
## here belongs to set_progress.
func test_the_label_rests_at_the_inert_tier_and_answers_a_step_up() -> void:
	assert_eq(_affordance.rest_stops, Emissive.INERT, "never blooms at rest")
	assert_eq(_affordance.rest_color(), Emissive.neutral(Emissive.INERT))
	_affordance._on_hover(true)
	assert_eq(_affordance.rest_color(), Emissive.neutral(Emissive.LABEL))
	assert_gt(
		_affordance.rest_color().get_luminance(),
		Emissive.neutral(Emissive.INERT).get_luminance(),
		"pointing at it brightens it",
	)
