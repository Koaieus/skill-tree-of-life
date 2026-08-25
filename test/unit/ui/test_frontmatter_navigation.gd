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
	return FrontmatterLayout.hero_slot()


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
	var probe := FrontmatterCamera.new(null, _tree)
	probe.snap_to(_tree.root)
	var parked := FrontmatterLayout.zoom_for(_tree, _tree.root)
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		probe.set_progress(t)
		assert_almost_eq(FrontmatterLayout.zoom_of(probe.transform_at(t)).x, parked, 0.001,
				"a parked camera holds its zoom; nothing may drift it")


func test_a_transition_between_two_authored_zooms_never_pops() -> void:
	# #593. The root menu is looked at closer than the fans below it, so a
	# transition now has a zoom to travel as well as a position. What must hold
	# is that it LANDS on both authored values exactly and moves monotonically
	# between them — a pop at either end is the failure mode, and `apply()`
	# pushes every one of these frames into the edge shader.
	var down := FrontmatterLayout.zoom_for(_tree, MenuGraph.ID_SINGLE_PLAYER)
	var up := FrontmatterLayout.zoom_for(_tree, _tree.root)
	assert_gt(up, down, "the root is the closer of the two")

	var probe := FrontmatterCamera.new(null, _tree)
	probe.snap_to(_tree.root)
	probe.travel_to(MenuGraph.ID_SINGLE_PLAYER)
	var seen: Array[float] = []
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		seen.append(FrontmatterLayout.zoom_of(probe.transform_at(t)).x)
	assert_almost_eq(seen[0], up, 0.001, "it leaves from the root's authored zoom")
	assert_almost_eq(seen[-1], down, 0.001, "and arrives exactly on the fan's")
	for i in range(1, seen.size()):
		assert_true(seen[i] <= seen[i - 1] + 0.001,
				"the zoom only ever travels one way: %s" % [seen])

	# And back, from wherever the outbound trip got to.
	probe.travel_to(_tree.root)
	assert_almost_eq(FrontmatterLayout.zoom_of(probe.transform_at(1.0)).x, up, 0.001,
			"going back lands on the root's authored zoom, not near it")


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


func test_routing_a_leaf_raises_its_panel() -> void:
	# Every leaf's panel landed with #573, so a route both records the ask and
	# gives the layer the stage. Written as the two halves of the contract on
	# purpose — `shown_panel` is what the graph ASKED for, `has_panel` is
	# whether anything can answer, and the layer's visibility follows the
	# second, never the first.
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)
	_root.focus(MenuGraph.ID_LOAD_GAME)
	assert_eq(panels.shown_panel, MenuGraph.PANEL_LOAD, "the ask is recorded")
	assert_true(panels.has_panel(MenuGraph.PANEL_LOAD), "and something answers it")
	assert_true(panels.visible, "so the layer takes the stage")


func test_an_unregistered_panel_id_routes_harmlessly() -> void:
	# `show_panel` no-ops on an unregistered id BY DESIGN — it records the ask
	# and leaves the graph visible rather than erroring, which is what let C3
	# ship its navigation while #573's panels were still empty.
	#
	# Asserted against a FABRICATED id rather than a real leaf's: once every
	# leaf has a panel there is no route left that exercises the miss, and a
	# test that quietly stops testing its own name is worse than no test. This
	# is that guarantee outliving the condition that first motivated it.
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)
	panels.show_panel(&"no_such_panel")
	assert_eq(panels.shown_panel, &"no_such_panel", "the ask is still recorded")
	assert_false(panels.has_panel(&"no_such_panel"), "nothing answers it")
	assert_false(panels.visible, "so the graph keeps the stage")


func test_the_shell_owns_quitting_not_the_exit_panel() -> void:
	# A panel calling `get_tree().quit()` would end the process the instant a
	# test pressed its button — which is why C1's parity test asserts the old
	# menu's quit CONNECTION rather than pressing it. Same reasoning here: the
	# connection is asserted, never fired.
	var panels: FrontmatterPanels = _root.get_node("%PanelLayer").get_child(0)
	# #573 has landed `quit_requested` for real, so the connect is a plain typed
	# one — a rename now fails `mise run check` here instead of silently leaving
	# EXIT wired to nothing. The signal is never EMITTED in this test.
	_root._connect_panels()
	assert_eq(panels.get_signal_connection_list(&"quit_requested").size(), 1,
			"the shell is listening, and it is the only thing listening")
	assert_eq(panels.get_signal_connection_list(&"panel_dismissed").size(), 1,
			"and the dismiss route is wired exactly once, not once per rebuild")


## `build()` clears before it fills, and `%GraphLayer` holds scene-authored
## siblings as well as the views — #572's [BackAffordance] lives there so it
## sits in graph space with the edge it decorates. A `_clear()` that freed every
## child of the layer therefore destroyed the affordance on the FIRST build, and
## the back button never appeared in play.
##
## **The await is the whole test.** `queue_free()` defers to end of frame, so
## everything later in the same frame still ran against a live object and the
## suite stayed green; the node was only gone a frame later. Asserting without
## the await reproduces the original false pass exactly.
func test_a_rebuild_does_not_eat_the_scene_authored_affordances() -> void:
	_root.focus(MenuGraph.ID_SINGLE_PLAYER, true)
	await get_tree().process_frame

	var back: Node = _root.get_node_or_null("%BackAffordance")
	assert_not_null(back, "the affordance survived the build that cleared the layer")
	assert_true(is_instance_valid(back), "and was not queued for deletion")
	assert_eq(back.get_parent(), _root.get_node("%GraphLayer"),
			"still parented in graph space, where it reads against its edge")

	# And a SECOND build must not eat it either — #578's live tab rebuilds in
	# place on every knob change, which is the path that found this.
	_root.build()
	await get_tree().process_frame
	assert_not_null(_root.get_node_or_null("%BackAffordance"), "survives a rebuild too")
	assert_eq(_root.view_for(MenuGraph.ID_ROOT).get_parent(), _root.get_node("%GraphLayer"),
			"and the views really were rebuilt, not merely left alone")


# --- the mouse (#583) ---------------------------------------------------------

func test_hovering_a_view_reaches_the_peek_ahead() -> void:
	# The seam #571 and #575 were built against and nothing drove: a view's own
	# pick region now reports the hover, and both light up with no further
	# wiring.
	_root.view_for(MenuGraph.ID_MULTIPLAYER).hover_entered.emit()
	assert_eq(_root._hover_preview.hovered_id, MenuGraph.ID_MULTIPLAYER)


func test_leaving_a_view_only_clears_ITS_own_hover() -> void:
	# `mouse_exited` on the node you left arrives AFTER `mouse_entered` on the
	# one you moved onto when two hit areas touch. Clearing unconditionally would
	# blank the hover you had just acquired.
	_root.view_for(MenuGraph.ID_MULTIPLAYER).hover_entered.emit()
	_root.view_for(MenuGraph.ID_SINGLE_PLAYER).hover_exited.emit()
	assert_eq(
		_root._hover_preview.hovered_id, MenuGraph.ID_MULTIPLAYER,
		"the stale exit did not clear the live hover"
	)


func test_clicking_a_view_navigates_to_it() -> void:
	_root.view_for(MenuGraph.ID_MULTIPLAYER).activated.emit()
	assert_eq(_root.focus_id, MenuGraph.ID_MULTIPLAYER)


func test_clicking_a_disabled_view_does_nothing() -> void:
	# LOAD GAME, while #23 save/load is parked. Refusing is a better answer than
	# navigating to a node the keyboard already refuses to commit to.
	_root.focus(MenuGraph.ID_SINGLE_PLAYER, true)
	_root.view_for(MenuGraph.ID_LOAD_GAME).activated.emit()
	assert_eq(_root.focus_id, MenuGraph.ID_SINGLE_PLAYER, "the click was refused")


func test_a_click_and_a_keypress_navigate_through_the_same_call() -> void:
	# One navigation path for both devices — the pose snapshot is identical
	# whichever one got there, so `navigation_state()` cannot tell them apart.
	_root.view_for(MenuGraph.ID_MULTIPLAYER).activated.emit()
	var clicked := _root.navigation_state()
	_root.focus(MenuGraph.ID_ROOT, true)
	_root.focus(MenuGraph.ID_MULTIPLAYER, true)
	assert_eq(_root.navigation_state(), clicked)


func test_nothing_above_the_menu_swallows_the_mouse() -> void:
	# GUI picking runs BEFORE physics picking and before `_unhandled_input`, so a
	# full-rect Control anywhere over the graph eats every click on its way down.
	# `MetaRoot` is exactly that — anchors_preset 15 over the whole viewport —
	# and it defaulted to MOUSE_FILTER_STOP, which is why menu clicks never
	# registered even once the views had hit areas.
	var meta: Control = load("res://scenes/meta/meta_root.tscn").instantiate()
	add_child_autofree(meta)
	await wait_frames(2)
	assert_eq(
		meta.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the meta shell is a layout container, not a click target"
	)
	var panels: Control = meta.find_children("*", "FrontmatterPanels", true, false)[0]
	assert_false(panels.visible, "and the panel layer starts hidden, so nor is it")


func test_a_real_click_reaches_a_menu_node_through_the_whole_shell() -> void:
	# [b]The only test here that does not drive a seam.[/b] Every other mouse
	# test emits `activated` or calls `_gui_input` directly, and the shipped
	# defect was that nothing ever CALLED those — the event died higher up. So
	# this one synthesizes a real [InputEventMouseButton] at the node's real
	# position and pushes it through `meta_root.tscn` entire: MetaRoot, the
	# splash, the panel CanvasLayer, the camera, the pick region.
	#
	# It runs in its OWN [SubViewport] at the project's viewport size, not in
	# GUT's: `add_child` here would put the shell under the runner's UI, and the
	# click would land on GUT before it ever reached the menu — a harness
	# artifact indistinguishable from the bug being tested.
	#
	# If anything ever grows a full-rect MOUSE_FILTER_STOP over the graph again,
	# this is the test that fails and none of the others do.
	var host := SubViewport.new()
	host.size = FrontmatterLayout.viewport_size()
	host.handle_input_locally = true
	host.gui_disable_input = false
	add_child_autofree(host)
	var meta: Control = load("res://scenes/meta/meta_root.tscn").instantiate()
	host.add_child(meta)
	await wait_frames(2)
	var frontmatter: FrontmatterRoot = meta.get_node("%Frontmatter")
	frontmatter.reduce_motion = true
	meta.get_node("%Splash").visible = false
	await wait_frames(2)

	var target := MenuGraph.ID_MULTIPLAYER
	var pick: Control = frontmatter.view_for(target).get_node("%PickRegion")
	# Viewport-local, so the camera's canvas transform is included and no camera
	# arithmetic is repeated here.
	var at: Vector2 = pick.get_global_transform_with_canvas() * (pick.size * 0.5)

	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		host.push_input(click, true)
		await wait_frames(2)

	assert_eq(frontmatter.focus_id, target, "the click navigated the menu")
