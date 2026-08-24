extends GutTest

## #571 — hovering a menu node peeks ahead at its children.
##
## The load-bearing test here is
## `test_the_peeked_slots_are_the_ones_the_menu_already_parks_children_in`. #571's
## decision is that the preview position is CANONICAL — the children rest there
## whether or not anything was ever hovered, and #570's sprout grows them out of
## exactly those slots. The failure mode that decision exists to prevent is a
## second set of coordinates computed here, which would look right until the
## sprout and the peek disagreed by a few pixels at some depth. So that test
## drives a real [FrontmatterRoot] and asserts the built tree's own view
## positions against [method HoverPreview.preview_positions] — an equality
## between two subsystems, not a restatement of one of them.
##
## Everything else runs over plain [CanvasItem]s. This unit is deliberately
## reachable through two [Callable]s rather than a [FrontmatterRoot] reference,
## and testing it that way is what proves it: it never asks the navigation for
## anything it could accidentally write back.

const _ROOT_SCENE := preload("res://ui/frontmatter/frontmatter_root.tscn")

var _tree: MenuGraph
var _preview: HoverPreview
var _views: Dictionary = {}
var _edges: Dictionary = {}


func before_each() -> void:
	_tree = MenuGraph.build()
	_views = {}
	_edges = {}
	for id in _tree.ids():
		_views[id] = _make_view(String(id))
		if _tree.parent_of(id) != &"":
			_edges[id] = _make_view("edge_%s" % id)
	_preview = HoverPreview.new()
	add_child_autofree(_preview)
	_preview.bind(_tree, _view_for, _edge_for)


func _make_view(name_: String) -> Node2D:
	var view := Node2D.new()
	view.name = name_
	# A Control that really does take the mouse and the focus ring, so
	# "previews are non-interactive" is a claim with something to fail on.
	var button := Button.new()
	button.name = "Hit"
	view.add_child(button)
	add_child_autofree(view)
	return view


func _view_for(id: StringName) -> CanvasItem:
	return _views.get(id) as CanvasItem


func _edge_for(child_id: StringName) -> CanvasItem:
	return _edges.get(child_id) as CanvasItem


func _button_of(id: StringName) -> Button:
	return (_views[id] as Node2D).get_node("Hit") as Button


func _alpha_of(id: StringName) -> float:
	return (_views[id] as CanvasItem).modulate.a


func _assert_same_plan(a: Dictionary, b: Dictionary, what: String) -> void:
	assert_eq(a.size(), b.size(), what)
	for id: StringName in a:
		assert_almost_eq(a[id] as float, b.get(id, -1.0) as float, 0.0001, "%s: %s" % [what, id])


func _assert_band(alphas: Dictionary, ids: Array, expected: float, what: String) -> void:
	for id: StringName in ids:
		assert_almost_eq(alphas[id] as float, expected, 0.0001, "%s: %s" % [what, id])


# --- the banding, as a pure function ----------------------------------------

func test_hovering_a_node_previews_exactly_its_children() -> void:
	var alphas := HoverPreview.plan(_tree, MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER)
	_assert_band(
		alphas,
		[MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOAD_GAME],
		HoverPreview.DEFAULT_PREVIEW_ALPHA,
		"peeked at",
	)
	_assert_band(
		alphas,
		[MenuGraph.ID_LOCAL, MenuGraph.ID_HOST, MenuGraph.ID_JOIN],
		HoverPreview.DEFAULT_HIDDEN_ALPHA,
		"another branch's children stay collapsed",
	)
	assert_eq(
		HoverPreview.previewed(_tree, MenuGraph.ID_SINGLE_PLAYER).size(),
		_tree.children_of(MenuGraph.ID_SINGLE_PLAYER).size(),
		"exactly as many previews as the node has children",
	)


func test_hovering_a_terminal_node_previews_nothing() -> void:
	for leaf: StringName in [MenuGraph.ID_OPTIONS, MenuGraph.ID_EXIT, MenuGraph.ID_JOIN]:
		assert_true(_tree.is_leaf(leaf), "%s is terminal" % leaf)
		assert_eq(HoverPreview.previewed(_tree, leaf).size(), 0, "%s previews nothing" % leaf)
	_assert_same_plan(
		HoverPreview.plan(_tree, MenuGraph.ID_ROOT, MenuGraph.ID_EXIT),
		HoverPreview.plan(_tree, MenuGraph.ID_ROOT, &""),
		"hovering a leaf leaves the picture exactly as it was",
	)


## The "full" band is "this node's parent is on the focus path" — the same
## condition [FrontmatterRoot] uses to decide home vs collapsed. Focused on
## SINGLE PLAYER, that has to include the siblings left behind at the root.
func test_everything_at_its_canonical_home_stays_undimmed() -> void:
	var alphas := HoverPreview.plan(_tree, MenuGraph.ID_SINGLE_PLAYER, &"")
	_assert_band(
		alphas,
		[
			MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_MULTIPLAYER,
			MenuGraph.ID_OPTIONS, MenuGraph.ID_EXIT,
			MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOAD_GAME,
		],
		HoverPreview.FULL_ALPHA,
		"grown out, so never dimmed by a peek",
	)
	_assert_band(
		alphas,
		[MenuGraph.ID_LOCAL, MenuGraph.ID_HOST, MenuGraph.ID_JOIN],
		HoverPreview.DEFAULT_HIDDEN_ALPHA,
		"still collapsed under MULTIPLAYER",
	)


## Hovering something that is already grown out changes nothing: its children
## are grown out too, and band 1 wins over band 2.
func test_hovering_a_node_that_is_already_home_is_a_no_op() -> void:
	_assert_same_plan(
		HoverPreview.plan(_tree, MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_SINGLE_PLAYER),
		HoverPreview.plan(_tree, MenuGraph.ID_SINGLE_PLAYER, &""),
		"a node that is already grown out has nothing to peek at",
	)


# --- the lockstep with the layout solver ------------------------------------

## The one test that spans two units. If this fails, the peek-ahead and the
## sprout have grown two different ideas of where a collapsed child sits.
func test_the_peeked_slots_are_the_ones_the_menu_already_parks_children_in() -> void:
	var root: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(root)
	root.reduce_motion = true
	var live := HoverPreview.new()
	add_child_autofree(live)
	live.bind(root.tree, root.view_for, func(_id: StringName) -> CanvasItem: return null)
	live.apply(root.focus_id, MenuGraph.ID_SINGLE_PLAYER)

	var slots := live.preview_positions()
	var expected_children := root.tree.children_of(MenuGraph.ID_SINGLE_PLAYER)
	assert_eq(slots.size(), expected_children.size(), "one slot per child of the peeked-at node")
	for child_id: StringName in expected_children:
		assert_true(slots.has(child_id), "%s has a peek slot" % child_id)
	for child_id: StringName in slots:
		var view := root.view_for(child_id)
		assert_almost_eq(
			view.position.x, (slots[child_id] as Vector2).x, 0.001,
			"%s is already sitting in its peek slot" % child_id,
		)
		assert_almost_eq(
			view.position.y, (slots[child_id] as Vector2).y, 0.001,
			"%s is already sitting in its peek slot" % child_id,
		)
		assert_almost_eq(
			view.scale.x, FrontmatterLayout.PREVIEW_SCALE, 0.001,
			"%s is already drawn small" % child_id,
		)


## The peek must not be able to move anything — #567 constraint 1, in the one
## place a hover could plausibly have reached for a position.
func test_peeking_never_moves_a_node() -> void:
	var root: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(root)
	root.reduce_motion = true
	var live := HoverPreview.new()
	add_child_autofree(live)
	live.bind(root.tree, root.view_for, func(_id: StringName) -> CanvasItem: return null)

	var before: Dictionary = {}
	for id in root.tree.ids():
		var view := root.view_for(id)
		before[id] = [view.position, view.scale, view.get_parent(), view.z_index]
	for id in root.tree.ids():
		live.apply(root.focus_id, id)
	live.apply(root.focus_id, &"")

	for id in root.tree.ids():
		var view := root.view_for(id)
		assert_eq(
			[view.position, view.scale, view.get_parent(), view.z_index], before[id] as Array,
			"%s is exactly where it was before anything was hovered" % id,
		)


# --- applying it ------------------------------------------------------------

func test_applying_a_peek_fades_the_children_in() -> void:
	_preview.apply(MenuGraph.ID_ROOT, &"")
	assert_almost_eq(_alpha_of(MenuGraph.ID_NEW_GAME), 0.0, 0.0001, "collapsed and unrevealed")

	_preview.apply(MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER)
	assert_almost_eq(
		_alpha_of(MenuGraph.ID_NEW_GAME), _preview.preview_alpha, 0.0001, "faint, not absent"
	)
	assert_almost_eq(
		_alpha_of(MenuGraph.ID_SINGLE_PLAYER), HoverPreview.FULL_ALPHA, 0.0001,
		"the node you are pointing at does not recede",
	)


func test_an_edge_takes_the_alpha_of_the_node_it_arrives_at() -> void:
	_preview.apply(MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER)
	for child_id: StringName in [MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOAD_GAME]:
		assert_almost_eq(
			(_edges[child_id] as CanvasItem).modulate.a, _preview.preview_alpha, 0.0001,
			"a revealed child arrives with its own faint edge",
		)
	assert_almost_eq(
		(_edges[MenuGraph.ID_LOCAL] as CanvasItem).modulate.a, 0.0, 0.0001,
		"and an unrevealed one brings no edge with it",
	)


func test_set_progress_ramps_from_the_alpha_that_was_there_to_the_planned_one() -> void:
	_preview.apply(MenuGraph.ID_ROOT, &"")
	_preview.apply(MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER, false)

	_preview.set_progress(0.0)
	assert_almost_eq(_alpha_of(MenuGraph.ID_NEW_GAME), 0.0, 0.0001, "t = 0 is where it was")
	_preview.set_progress(0.5)
	assert_almost_eq(
		_alpha_of(MenuGraph.ID_NEW_GAME), _preview.preview_alpha * 0.5, 0.0001, "halfway"
	)
	_preview.set_progress(1.0)
	assert_almost_eq(
		_alpha_of(MenuGraph.ID_NEW_GAME), _preview.preview_alpha, 0.0001, "t = 1 is the plan"
	)


func test_previewed_children_are_non_interactive() -> void:
	var authored_filter := _button_of(MenuGraph.ID_NEW_GAME).mouse_filter
	var authored_focus := _button_of(MenuGraph.ID_NEW_GAME).focus_mode
	assert_eq(authored_filter, Control.MOUSE_FILTER_STOP, "the fixture really is clickable")

	_preview.apply(MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER)
	assert_eq(
		_button_of(MenuGraph.ID_NEW_GAME).mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"a preview does not take the mouse",
	)
	assert_eq(
		_button_of(MenuGraph.ID_NEW_GAME).focus_mode, Control.FOCUS_NONE,
		"a preview does not steal focus",
	)
	assert_eq(
		_button_of(MenuGraph.ID_SINGLE_PLAYER).mouse_filter, authored_filter,
		"the option column stays clickable",
	)
	assert_false(HoverPreview.is_interactive(_preview.preview_alpha))
	assert_true(HoverPreview.is_interactive(HoverPreview.FULL_ALPHA))

	_preview.apply(MenuGraph.ID_ROOT, &"")
	assert_eq(
		_button_of(MenuGraph.ID_NEW_GAME).mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"and a collapsed node is not clickable either — it is not on screen",
	)

	# Interactivity tracks visibility, so what restores the authored values is
	# the node being grown out, not the hover ending. Restoring on un-hover
	# would hand the mouse back to a node sitting at alpha 0.
	_preview.apply(MenuGraph.ID_SINGLE_PLAYER, &"")
	assert_eq(
		_button_of(MenuGraph.ID_NEW_GAME).mouse_filter, authored_filter,
		"grown out, so back to what the SCENE authored",
	)
	assert_eq(_button_of(MenuGraph.ID_NEW_GAME).focus_mode, authored_focus)


func test_un_hovering_restores_the_prior_state_exactly() -> void:
	_preview.apply(MenuGraph.ID_ROOT, &"")
	var before := _snapshot()
	_preview.apply(MenuGraph.ID_ROOT, MenuGraph.ID_MULTIPLAYER)
	assert_ne(_snapshot(), before, "the peek did something in the first place")
	_preview.apply(MenuGraph.ID_ROOT, &"")
	assert_eq(_snapshot(), before, "and un-hovering put all of it back")


## An ARRAY, not a Dictionary: Godot compares arrays element-wise, so one
## `assert_eq` really does say "all of it went back".
func _snapshot() -> Array:
	var state: Array = []
	for id in _tree.ids():
		var button := _button_of(id)
		state.append([id, _alpha_of(id), button.mouse_filter, button.focus_mode])
	return state


func test_hover_changed_fires_only_when_the_peek_actually_moves() -> void:
	var seen: Array[StringName] = []
	_preview.hover_changed.connect(func(id: StringName) -> void: seen.append(id))
	_preview.apply(MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER)
	_preview.apply(MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER)
	_preview.apply(MenuGraph.ID_ROOT, &"")
	assert_eq(seen, [MenuGraph.ID_SINGLE_PLAYER, &""] as Array[StringName])
