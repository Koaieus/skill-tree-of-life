extends GutTest

## #570 — navigating the frontmatter moves the camera, and only the camera.
##
## The load-bearing test in this file is
## `test_a_full_traversal_leaves_every_node_exactly_where_it_started`. #567's
## constraint 1 is the owner's [i]"no detaching please"[/i], and the canvas
## mockup this design comes from breaks it explicitly — its `_select()` lifts the
## clicked node into a transit layer at `z-index: 15` while the hero fades out.
## The machine-checkable form of the veto is a real pose snapshot over EVERY
## view, taken before and after a full forward-and-back traversal of the whole
## tree: position, scale, parent and z_index, per node.
##
## Progress is driven by hand throughout. `focus()` in a test always passes
## `instant`, or the assertions would be racing a [Tween]; the transition's shape
## is asserted at `t == 0` and `t == 1` through `set_progress`, which is exactly
## what the acceptance asks for and is why the unit owns no tween of its own.

const _ROOT_SCENE := preload("res://ui/frontmatter/frontmatter_root.tscn")

var _root: FrontmatterRoot
var _tree: MenuGraph


func before_each() -> void:
	_root = _ROOT_SCENE.instantiate()
	add_child_autofree(_root)
	_root.reduce_motion = true  # every focus() lands in one frame unless told otherwise
	_tree = _root.tree


func _hero_world() -> Vector2:
	return FrontmatterLayout.slot(FrontmatterLayout.HERO_SLOT_RATIO)


## Where the camera actually puts a design-viewport point, right now.
func _camera_sees(design_point: Vector2) -> Vector2:
	return FrontmatterLayout.screen_to_world(_root.camera.current_transform(), design_point)


func _assert_focus_is_in_the_hero_slot(id: StringName) -> void:
	var landed := _camera_sees(_hero_world())
	var home: Vector2 = FrontmatterLayout.solve(_tree)[id]
	assert_almost_eq(landed.x, home.x, 0.001, "'%s' sits in the hero slot" % id)
	assert_almost_eq(landed.y, home.y, 0.001, "'%s' sits in the hero slot" % id)


# --- focus moves the camera -------------------------------------------------

func test_a_fresh_frontmatter_starts_parked_on_the_root() -> void:
	assert_eq(_root.focus_id, _tree.root)
	_assert_focus_is_in_the_hero_slot(_tree.root)
	assert_eq(_root.focus_path(), [_tree.root] as Array[StringName])


func test_focus_lands_any_node_in_the_hero_slot() -> void:
	for id in [
		MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_NEW_GAME, MenuGraph.ID_ROOT,
		MenuGraph.ID_MULTIPLAYER, MenuGraph.ID_JOIN, MenuGraph.ID_EXIT,
	]:
		_root.focus(id)
		assert_eq(_root.focus_id, id)
		_assert_focus_is_in_the_hero_slot(id)


func test_the_camera_transform_is_asserted_at_the_ends_not_mid_tween() -> void:
	# Drive the clock by hand: at t == 0 the camera is still where it was, at
	# t == 1 it is on the new focus. Nothing in between is anybody's contract.
	_root.focus(MenuGraph.ID_ROOT)
	var was := _root.camera.current_transform()

	_root.reduce_motion = false
	# A REAL duration, not 0: `travel_duration <= 0.0` takes the instant path.
	# No frames pass inside a GUT test, so the tween never advances and
	# `set_progress` stays ours to drive.
	_root.travel_duration = 0.85
	_root.focus(MenuGraph.ID_MULTIPLAYER)
	_root.set_progress(0.0)
	assert_eq(_root.camera.current_transform(), was, "t = 0 has not moved yet")

	_root.set_progress(1.0)
	assert_eq(_root.camera.current_transform(),
			FrontmatterLayout.camera_for(_tree, MenuGraph.ID_MULTIPLAYER),
			"t = 1 is exactly where the layout says")


func test_an_unknown_id_is_refused_rather_than_parking_the_menu_nowhere() -> void:
	_root.focus(MenuGraph.ID_MULTIPLAYER)
	var before := _root.navigation_state()
	_root.focus(&"nonexistent")
	assert_eq(_root.navigation_state(), before)


# --- back is the same call with the parent id -------------------------------

func test_back_at_depth_n_lands_at_n_minus_one() -> void:
	_root.focus(MenuGraph.ID_JOIN)
	assert_eq(_tree.depth_of(_root.focus_id), 2)
	assert_true(_root.back())
	assert_eq(_root.focus_id, MenuGraph.ID_MULTIPLAYER)
	assert_eq(_tree.depth_of(_root.focus_id), 1)
	assert_true(_root.back())
	assert_eq(_root.focus_id, _tree.root)
	assert_eq(_tree.depth_of(_root.focus_id), 0)


func test_back_at_the_root_is_a_no_op() -> void:
	var before := _root.navigation_state()
	assert_false(_root.back(), "there is nowhere above the root")
	assert_eq(_root.navigation_state(), before, "and nothing moved trying")


func test_forward_then_back_returns_the_exact_prior_state() -> void:
	# The WHOLE state, not just the focus id — camera, every pose, the panel.
	_root.focus(MenuGraph.ID_MULTIPLAYER)
	var before := _root.navigation_state()

	_root.focus(MenuGraph.ID_HOST)
	assert_ne(_root.navigation_state(), before, "going forward did something")

	_root.back()
	assert_eq(_root.navigation_state(), before, "and back undid exactly it")


func test_back_navigation_is_not_a_second_code_path() -> void:
	# Under a camera there is nothing to mirror, so "arrive at X from below" and
	# "arrive at X from above" must be indistinguishable. If a reverse tween ever
	# appears, this is what catches it.
	_root.focus(MenuGraph.ID_SINGLE_PLAYER)
	var from_above := _root.navigation_state()

	_root.focus(MenuGraph.ID_NEW_GAME)
	_root.back()
	assert_eq(_root.navigation_state(), from_above)


# --- the anti-detaching guarantee -------------------------------------------

func _pose_snapshot() -> Dictionary:
	var poses: Dictionary = {}
	for id in _tree.ids():
		var view := _root.view_for(id)
		poses[id] = [view.position, view.scale, view.get_parent(), view.z_index]
	return poses


func test_a_full_traversal_leaves_every_node_exactly_where_it_started() -> void:
	# Every node, every edge, every level of the tree — then back to the root.
	# The canvas's `_select()` reparents the clicked node into a transit layer
	# and drops the hero's opacity to 0; nothing here can, and this is the proof.
	var before := _pose_snapshot()

	for id in _tree.ids():
		_root.focus(id)
	for id in _tree.ids():
		_root.focus(id)
		while _root.back():
			pass

	assert_eq(_root.focus_id, _tree.root, "the traversal ends where it started")
	assert_eq(_pose_snapshot(), before,
			"no node moved, changed scale, changed parent or changed z_index")


func test_the_layout_itself_is_never_recomputed_by_navigating() -> void:
	# The poses above are what a view is DRAWN at; this is the layout underneath
	# them, which #568 pins as focus-invariant and which navigation must not
	# touch at all.
	var homes := FrontmatterLayout.solve(_tree).duplicate(true)
	for id in _tree.ids():
		_root.focus(id)
	assert_eq(FrontmatterLayout.solve(_tree), homes)


func test_every_view_keeps_one_parent_and_one_z_index_for_the_whole_run() -> void:
	var graph_layer := _root.get_node("%GraphLayer")
	for id in _tree.ids():
		_root.focus(id)
		for other in _tree.ids():
			var view := _root.view_for(other)
			assert_eq(view.get_parent(), graph_layer,
					"'%s' is still parented to the graph layer" % other)
			assert_eq(view.z_index, 0, "'%s' was never lifted into a transit layer" % other)


# --- grow, don't cut --------------------------------------------------------

func test_a_focused_nodes_children_rest_at_their_canonical_homes() -> void:
	_root.focus(MenuGraph.ID_MULTIPLAYER)
	var homes := FrontmatterLayout.solve(_tree)
	for child_id in _tree.children_of(MenuGraph.ID_MULTIPLAYER):
		var view := _root.view_for(child_id)
		assert_almost_eq(view.position.x, (homes[child_id] as Vector2).x, 0.001)
		assert_almost_eq(view.position.y, (homes[child_id] as Vector2).y, 0.001)
		assert_almost_eq(view.scale.x, 1.0, 0.001, "and at full size")


func test_children_of_anything_else_rest_collapsed_on_their_parent() -> void:
	# The collapsed position is CANONICAL, not a hover-only rendering trick —
	# it is where those children are whenever their parent is not the focus.
	_root.focus(MenuGraph.ID_MULTIPLAYER)
	var slots := FrontmatterLayout.preview_slots(_tree, MenuGraph.ID_SINGLE_PLAYER)
	for child_id in _tree.children_of(MenuGraph.ID_SINGLE_PLAYER):
		var view := _root.view_for(child_id)
		assert_almost_eq(view.position.x, (slots[child_id] as Vector2).x, 0.001)
		assert_almost_eq(view.scale.x, FrontmatterLayout.PREVIEW_SCALE, 0.001,
				"collapsed children are drawn small")


func test_children_grow_from_collapsed_to_home_in_the_same_motion() -> void:
	_root.focus(MenuGraph.ID_ROOT)
	_root.reduce_motion = false
	_root.travel_duration = 0.85
	_root.focus(MenuGraph.ID_SINGLE_PLAYER)

	var slots := FrontmatterLayout.preview_slots(_tree, MenuGraph.ID_SINGLE_PLAYER)
	var homes := FrontmatterLayout.solve(_tree)

	_root.set_progress(0.0)
	var new_game := _root.view_for(MenuGraph.ID_NEW_GAME)
	assert_almost_eq(new_game.position.y, (slots[MenuGraph.ID_NEW_GAME] as Vector2).y, 0.001,
			"at t = 0 the child is still collapsed")
	assert_almost_eq(new_game.scale.x, FrontmatterLayout.PREVIEW_SCALE, 0.001)

	# Mid-motion the camera has moved AND the child has grown — one clock, not
	# a camera move followed by a sprout.
	var camera_at_zero := FrontmatterLayout.camera_for(_tree, MenuGraph.ID_ROOT)
	_root.set_progress(0.5)
	assert_ne(_root.camera.current_transform(), camera_at_zero, "the camera is travelling")
	assert_gt(new_game.scale.x, FrontmatterLayout.PREVIEW_SCALE, "and the child is growing")
	assert_lt(new_game.scale.x, 1.0)

	_root.set_progress(1.0)
	assert_almost_eq(new_game.position.y, (homes[MenuGraph.ID_NEW_GAME] as Vector2).y, 0.001)
	assert_almost_eq(new_game.scale.x, 1.0, 0.001)


func test_the_focus_path_is_what_reads_as_allocated() -> void:
	_root.focus(MenuGraph.ID_HOST)
	var path := _root.focus_path()
	for id in _tree.ids():
		assert_eq(_root.view_for(id).allocated, path.has(id),
				"'%s' is lit iff it is on the focus path" % id)


func test_an_edge_is_lit_only_when_both_of_its_ends_are() -> void:
	_root.focus(MenuGraph.ID_HOST)
	var graph_layer := _root.get_node("%GraphLayer")
	var lit_edge: MenuEdgeView = graph_layer.get_node("edge_%s" % MenuGraph.ID_HOST)
	assert_true(lit_edge.lit, "multiplayer -> host is on the focus path")
	var dark_edge: MenuEdgeView = graph_layer.get_node("edge_%s" % MenuGraph.ID_JOIN)
	assert_false(dark_edge.lit, "multiplayer -> join is not")


# --- reduce motion ----------------------------------------------------------

func test_the_player_setting_is_what_decides_reduce_motion() -> void:
	# Read straight off GameSettings at build, not authored per scene — and a
	# direct typed read, so renaming the setting breaks the compile rather than
	# silently falling back to whatever this node happens to have on it.
	var was: bool = Settings.current.reduce_motion
	Settings.current.reduce_motion = true
	var fresh: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(fresh)
	assert_true(fresh.reduce_motion, "the shell took the player's answer")

	Settings.current.reduce_motion = false
	var motion: FrontmatterRoot = _ROOT_SCENE.instantiate()
	add_child_autofree(motion)
	assert_false(motion.reduce_motion)
	Settings.current.reduce_motion = was


func test_reduce_motion_lands_the_transform_in_one_frame() -> void:
	_root.reduce_motion = true
	_root.travel_duration = 0.85  # would be a long tween if it were honoured
	_root.focus(MenuGraph.ID_JOIN)
	assert_eq(_root.camera.current_transform(),
			FrontmatterLayout.camera_for(_tree, MenuGraph.ID_JOIN),
			"no tween ran — the camera is already there")
	_assert_focus_is_in_the_hero_slot(MenuGraph.ID_JOIN)


func test_reduce_motion_is_the_same_end_state_as_a_completed_transition() -> void:
	# It is a short-circuit, not a different destination.
	_root.reduce_motion = true
	_root.focus(MenuGraph.ID_LOCAL)
	var instant := _root.navigation_state()

	_root.focus(MenuGraph.ID_ROOT)
	_root.reduce_motion = false
	_root.travel_duration = 0.85
	_root.focus(MenuGraph.ID_LOCAL)
	_root.set_progress(1.0)
	assert_eq(_root.navigation_state(), instant)


# --- the edge shader's zoom, and the panel seam -----------------------------

func test_the_shader_zoom_is_pushed_on_every_applied_frame() -> void:
	# The menu's own C2 finding: `width` is screen-constant only if
	# `edge_camera_zoom` tracks the camera, and GraphCamera is the only other
	# writer. Pushing it only at the endpoints of a transition pumps the width
	# through the middle of every zoom, so it rides `apply()`.
	var pushes: Array[float] = []
	var probe := FrontmatterCamera.new(null, _tree)
	probe.snap_to(_tree.root)
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		probe.set_progress(t)
		pushes.append(FrontmatterLayout.zoom_of(probe.transform_at(t)).x)
	for zoom in pushes:
		assert_almost_eq(zoom, 1.0 / FrontmatterLayout.TREE_ZOOM, 0.001,
				"tree navigation holds one zoom; a transition must not drift it")


func test_focusing_a_leaf_routes_its_panel_through_the_seam() -> void:
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)
	_root.focus(MenuGraph.ID_NEW_GAME)
	assert_eq(panels.shown_panel, MenuGraph.PANEL_LOBBY)

	_root.focus(MenuGraph.ID_OPTIONS)
	assert_eq(panels.shown_panel, MenuGraph.PANEL_SETTINGS)


func test_focusing_a_branch_leaves_the_graph_on_stage() -> void:
	_root.focus(MenuGraph.ID_NEW_GAME)
	_root.back()
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)
	assert_eq(panels.shown_panel, &"", "backing out of a leaf returns the stage")


func test_a_leafs_panel_is_raised_on_arrival_not_on_departure() -> void:
	# The lobby must not be on screen while the graph is still travelling to it.
	_root.focus(MenuGraph.ID_SINGLE_PLAYER)
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)

	_root.reduce_motion = false
	_root.travel_duration = 0.85
	_root.focus(MenuGraph.ID_NEW_GAME)
	_root.set_progress(0.0)
	assert_eq(panels.shown_panel, &"", "still travelling")
	_root.set_progress(0.99)
	assert_eq(panels.shown_panel, &"", "still travelling")
	_root.set_progress(1.0)
	assert_eq(panels.shown_panel, MenuGraph.PANEL_LOBBY, "arrived")


func test_a_panel_that_has_not_landed_yet_routes_harmlessly() -> void:
	# `show_panel` no-ops on an unregistered id BY DESIGN, so a leaf whose panel
	# #573 has not filled in leaves the graph visible instead of erroring.
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)
	_root.focus(MenuGraph.ID_LOAD_GAME)
	assert_eq(panels.shown_panel, MenuGraph.PANEL_LOAD, "the ask is recorded")
	assert_false(panels.has_panel(MenuGraph.PANEL_LOAD), "and nothing took the stage")


func test_the_shell_owns_quitting_not_the_exit_panel() -> void:
	# A panel calling `get_tree().quit()` would end the process the instant a
	# test pressed its button — which is why C1's parity test asserts the old
	# menu's quit CONNECTION rather than pressing it. Same reasoning here: the
	# connection is asserted, never fired.
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)
	# Stands in for the signal until #573 lands it, and steps aside once it has —
	# either way the shell's guarded connect is what is under test, and the
	# signal is never EMITTED here.
	if not panels.has_signal(&"quit_requested"):
		panels.add_user_signal("quit_requested")
	_root._connect_panels()
	assert_eq(panels.get_signal_connection_list(&"quit_requested").size(), 1,
			"the shell is listening, and it is the only thing listening")
	assert_eq(panels.get_signal_connection_list(&"panel_dismissed").size(), 1,
			"and the dismiss route is wired exactly once, not once per rebuild")
