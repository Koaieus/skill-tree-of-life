extends GutTest

## #568 — the frontmatter's menu tree and its pure layout solver.
##
## There were ZERO tests over the menu flow before this file (owner, 2026-08-24:
## [i]"menu of course would need a test for everything inside"[/i]). Everything
## here runs without a rendered frame, which is the point of the model/view
## split in #567: a [Transform2D] is assertable, a tween's third frame is not.
##
## The load-bearing test in this file is
## `test_solve_takes_no_focus_parameter` + `test_solve_is_identical_across_camera_moves`.
## Together they are the machine-checked form of #567's constraint 1, [i]"no
## detaching, ever"[/i] -> "nodes never move". Calling [method
## FrontmatterLayout.solve] twice in a row would prove nothing; these call it
## either side of a run of camera moves, and check the signature cannot grow a
## focus parameter later.

var _tree: MenuGraph


func before_each() -> void:
	_tree = MenuGraph.build()


## Typed-array literal, so a comparison against `children_of()` is like-for-like.
func _ids(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in values:
		out.append(v)
	return out


func _column_step() -> float:
	return FrontmatterLayout.COLUMN_STEP_RATIO * FrontmatterLayout.DESIGN_VIEWPORT.x


func _sibling_gap() -> float:
	return FrontmatterLayout.SIBLING_GAP_RATIO * FrontmatterLayout.DESIGN_VIEWPORT.y


# --- 1. tree shape ----------------------------------------------------------

func test_every_id_is_reachable_from_the_root_exactly_once() -> void:
	# Reachable-exactly-once is both "connected" and "acyclic" in one statement:
	# a cycle would revisit an id, an orphan would never be visited.
	var seen: Array[StringName] = []
	var frontier: Array[StringName] = [_tree.root]
	while not frontier.is_empty():
		var id: StringName = frontier.pop_front()
		assert_false(seen.has(id), "'%s' is reachable twice — this is a tree" % id)
		seen.append(id)
		frontier.append_array(_tree.children_of(id))
	assert_eq(seen.size(), _tree.size(), "every item is reachable from the root")
	for id in _tree.ids():
		assert_true(seen.has(id), "'%s' is reachable" % id)


func test_the_root_is_the_only_parentless_item() -> void:
	assert_eq(_tree.root, MenuGraph.ID_ROOT)
	for id in _tree.ids():
		if id == _tree.root:
			assert_eq(_tree.parent_of(id), &"", "the root has no parent")
		else:
			assert_ne(_tree.parent_of(id), &"", "'%s' has a parent" % id)
			assert_true(_tree.has(_tree.parent_of(id)), "'%s' parent exists" % id)


func test_a_parents_children_all_name_it_back() -> void:
	for id in _tree.ids():
		for child in _tree.children_of(id):
			assert_eq(_tree.parent_of(child), id, "'%s' is a child of '%s'" % [child, id])


func test_every_leaf_names_a_panel_and_no_branch_does() -> void:
	# A node with children navigates; a node without one opens something. A leaf
	# with no panel would be a dead end the player can walk into.
	for id in _tree.ids():
		var item := _tree.get_item(id)
		if item.is_leaf():
			assert_ne(item.panel, &"", "leaf '%s' names a panel" % id)
		else:
			assert_eq(item.panel, &"", "branch '%s' opens nothing" % id)


func test_the_tree_is_the_one_in_the_issue() -> void:
	assert_eq(_tree.children_of(MenuGraph.ID_ROOT), _ids([
		MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_MULTIPLAYER,
		MenuGraph.ID_OPTIONS, MenuGraph.ID_EXIT,
	]))
	assert_eq(_tree.children_of(MenuGraph.ID_SINGLE_PLAYER), _ids([
		MenuGraph.ID_NEW_GAME, MenuGraph.ID_LOAD_GAME,
	]))
	assert_eq(_tree.children_of(MenuGraph.ID_MULTIPLAYER), _ids([
		MenuGraph.ID_LOCAL, MenuGraph.ID_HOST, MenuGraph.ID_JOIN,
	]))
	assert_true(_tree.get_item(MenuGraph.ID_LOAD_GAME).disabled,
			"LOAD GAME is reachable but parked — #23 save/load is not in this milestone")
	assert_false(_tree.get_item(MenuGraph.ID_NEW_GAME).disabled)


func test_path_and_depth_describe_where_a_node_sits() -> void:
	assert_eq(_tree.path_to(MenuGraph.ID_JOIN),
			_ids([MenuGraph.ID_ROOT, MenuGraph.ID_MULTIPLAYER, MenuGraph.ID_JOIN]))
	assert_eq(_tree.depth_of(MenuGraph.ID_ROOT), 0)
	assert_eq(_tree.depth_of(MenuGraph.ID_MULTIPLAYER), 1)
	assert_eq(_tree.depth_of(MenuGraph.ID_JOIN), 2)
	assert_eq(_tree.depth_of(&"nonexistent"), -1)
	assert_eq(_tree.path_to(&"nonexistent"), _ids([]))


func test_siblings_include_self_and_the_root_stands_alone() -> void:
	assert_eq(_tree.siblings_of(MenuGraph.ID_HOST), _ids([
		MenuGraph.ID_LOCAL, MenuGraph.ID_HOST, MenuGraph.ID_JOIN,
	]))
	assert_eq(_tree.siblings_of(MenuGraph.ID_ROOT), _ids([MenuGraph.ID_ROOT]))


# --- 2. layout --------------------------------------------------------------

func test_every_node_has_exactly_one_position() -> void:
	var positions := FrontmatterLayout.solve(_tree)
	assert_eq(positions.size(), _tree.size())
	var occupied: Array[Vector2] = []
	for id in _tree.ids():
		assert_true(positions.has(id), "'%s' was placed" % id)
		var at: Vector2 = positions[id]
		assert_false(occupied.has(at), "'%s' does not share a position" % id)
		occupied.append(at)


func test_depth_sets_the_column() -> void:
	# The option column is one step right of the hero slot, and because nodes
	# never move that step is the WORLD pitch between a parent and its children,
	# not something recomputed per focus.
	var positions := FrontmatterLayout.solve(_tree)
	for id in _tree.ids():
		assert_almost_eq(positions[id].x, _tree.depth_of(id) * _column_step(), 0.001,
				"'%s' sits in its depth's column" % id)


func test_leaf_siblings_are_exactly_a_row_gap_apart() -> void:
	var positions := FrontmatterLayout.solve(_tree)
	for parent in [MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_MULTIPLAYER]:
		var children := _tree.children_of(parent)
		for i in children.size() - 1:
			assert_almost_eq(positions[children[i + 1]].y - positions[children[i]].y,
					_sibling_gap(), 0.001,
					"'%s' spaces its children by the design row gap" % parent)


func test_a_sibling_group_is_evenly_spaced_and_centred_on_its_parent() -> void:
	var positions := FrontmatterLayout.solve(_tree)
	for parent in _tree.ids():
		var children := _tree.children_of(parent)
		if children.is_empty():
			continue
		var pitches: Array[float] = []
		var mean := 0.0
		for i in children.size():
			mean += positions[children[i]].y
			if i > 0:
				pitches.append(positions[children[i]].y - positions[children[i - 1]].y)
		for pitch in pitches:
			assert_almost_eq(pitch, pitches[0], 0.001,
					"'%s' spaces its children evenly" % parent)
			assert_true(pitch >= _sibling_gap() - 0.001,
					"'%s' never packs children tighter than the design gap" % parent)
		assert_almost_eq(mean / children.size(), positions[parent].y, 0.001,
				"'%s' sits level with the middle of its children" % parent)


func test_no_two_nodes_in_a_column_crowd_each_other() -> void:
	# Cousins share a column. Spacing each group at exactly the design gap reads
	# fine one branch at a time and interleaves cousins on screen — under a
	# camera that shows a whole column at once, that is a collision.
	var positions := FrontmatterLayout.solve(_tree)
	var ids := _tree.ids()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if _tree.depth_of(ids[i]) != _tree.depth_of(ids[j]):
				continue
			assert_true(absf(positions[ids[i]].y - positions[ids[j]].y) >= _sibling_gap() - 0.001,
					"'%s' and '%s' share a column and must clear each other" % [ids[i], ids[j]])


func test_the_preview_column_is_the_collapsed_peek_ahead_offset() -> void:
	# #571 reads these: a hovered node's children, stacked tight and small,
	# waiting to grow out to their real positions when it is selected.
	var positions := FrontmatterLayout.solve(_tree)
	var slots := FrontmatterLayout.preview_slots(_tree, MenuGraph.ID_MULTIPLAYER)
	var children := _tree.children_of(MenuGraph.ID_MULTIPLAYER)
	assert_eq(slots.size(), children.size())
	var column := FrontmatterLayout.PREVIEW_COLUMN_RATIO * FrontmatterLayout.DESIGN_VIEWPORT.x
	var gap := FrontmatterLayout.PREVIEW_GAP_RATIO * FrontmatterLayout.DESIGN_VIEWPORT.y
	var origin: Vector2 = positions[MenuGraph.ID_MULTIPLAYER]
	for i in children.size():
		var at: Vector2 = slots[children[i]]
		assert_almost_eq(at.x - origin.x, column, 0.001, "preview column offset")
		assert_almost_eq(at.y - origin.y, (i - 1) * gap, 0.001, "preview stack pitch")
	assert_true(gap < _sibling_gap(), "the peek-ahead stack is tighter than the real one")
	assert_eq(FrontmatterLayout.preview_slots(_tree, MenuGraph.ID_JOIN), {},
			"a leaf has nothing to peek at")


func test_geometry_is_authored_as_ratios_of_a_design_viewport() -> void:
	# Not 1440x900 literals: every constant is a fraction, so the layout keeps
	# its proportions when #578's live tab retunes the viewport.
	assert_almost_eq(FrontmatterLayout.HERO_SLOT_RATIO.x, 190.0 / 1440.0, 0.0001)
	assert_almost_eq(FrontmatterLayout.HERO_SLOT_RATIO.y, 0.5, 0.0001)
	assert_almost_eq(_column_step(), 306.0, 0.001, "hero 190 -> option column 496")
	assert_almost_eq(_sibling_gap(), 132.0, 0.001)
	assert_almost_eq(FrontmatterLayout.PREVIEW_SCALE, 0.42, 0.0001)
	assert_almost_eq(FrontmatterLayout.SPLASH_ZOOM, 2.55, 0.0001)


# --- 3. "nodes never move", machine-checked ---------------------------------

func test_solve_takes_no_focus_parameter() -> void:
	# The signature IS the invariant. If a later change adds a focus argument,
	# "nodes never move" stops being checkable and this test is where it is
	# noticed — not in a review of the tween that started sliding them.
	# `load`, not `preload`: a const preload of a `class_name` script resolves to
	# the TYPE, and asking a type for its method list is a parse error.
	var script: GDScript = load("res://ui/frontmatter/frontmatter_layout.gd")
	var found := false
	for method in script.get_script_method_list():
		if method["name"] != "solve":
			continue
		found = true
		assert_eq(method["args"].size(), 1, "solve() takes the tree and nothing else")
		assert_eq(method["args"][0]["name"], "tree")
	assert_true(found, "FrontmatterLayout.solve exists")


func test_solve_is_identical_across_camera_moves() -> void:
	var before := FrontmatterLayout.solve(_tree).duplicate(true)

	# Everything navigation can do to the camera, in one go: down to a leaf, back
	# up, across to another branch, on to the splash and off it again.
	for focus in [
		MenuGraph.ID_ROOT, MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_NEW_GAME,
		MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_ROOT, MenuGraph.ID_MULTIPLAYER,
		MenuGraph.ID_JOIN, MenuGraph.ID_EXIT,
	]:
		FrontmatterLayout.camera_for(_tree, focus)
		assert_eq(FrontmatterLayout.solve(_tree), before,
				"focusing '%s' moved the camera, not the nodes" % focus)
	FrontmatterLayout.splash_camera(_tree)

	assert_eq(FrontmatterLayout.solve(_tree), before)
	assert_eq(FrontmatterLayout.preview_slots(_tree, MenuGraph.ID_MULTIPLAYER).size(), 3)
	assert_eq(FrontmatterLayout.solve(_tree), before, "peeking ahead moves nothing either")


# --- 4. camera --------------------------------------------------------------

func _assert_lands_on_hero(focus: StringName) -> void:
	var xform := FrontmatterLayout.camera_for(_tree, focus)
	var hero := FrontmatterLayout.slot(FrontmatterLayout.HERO_SLOT_RATIO)
	var landed := FrontmatterLayout.screen_to_world(xform, hero)
	var want: Vector2 = FrontmatterLayout.solve(_tree)[focus]
	assert_almost_eq(landed.x, want.x, 0.001, "'%s' lands on the hero slot" % focus)
	assert_almost_eq(landed.y, want.y, 0.001, "'%s' lands on the hero slot" % focus)


func test_camera_docks_the_focus_in_the_hero_slot_at_every_depth() -> void:
	_assert_lands_on_hero(MenuGraph.ID_ROOT)
	_assert_lands_on_hero(MenuGraph.ID_MULTIPLAYER)
	_assert_lands_on_hero(MenuGraph.ID_JOIN)


func test_navigating_only_changes_where_the_camera_is() -> void:
	var root_cam := FrontmatterLayout.camera_for(_tree, MenuGraph.ID_ROOT)
	var leaf_cam := FrontmatterLayout.camera_for(_tree, MenuGraph.ID_JOIN)
	assert_ne(root_cam.origin, leaf_cam.origin, "the camera travels")
	assert_eq(FrontmatterLayout.zoom_of(root_cam), Vector2.ONE)
	assert_eq(FrontmatterLayout.zoom_of(leaf_cam), Vector2.ONE, "and does not zoom on the way")


func test_going_forward_and_back_returns_the_exact_same_camera() -> void:
	# #567 retires "back-navigation doesn't mirror forward navigation"
	# structurally: back is focus(parent), forward is focus(child), same call.
	var at_multiplayer := FrontmatterLayout.camera_for(_tree, MenuGraph.ID_MULTIPLAYER)
	FrontmatterLayout.camera_for(_tree, MenuGraph.ID_HOST)
	assert_eq(FrontmatterLayout.camera_for(_tree, MenuGraph.ID_MULTIPLAYER), at_multiplayer)


func test_an_unknown_focus_parks_on_the_root() -> void:
	assert_eq(FrontmatterLayout.camera_for(_tree, &"nonexistent"),
			FrontmatterLayout.camera_for(_tree, _tree.root))


func test_the_splash_is_the_same_tree_seen_closer() -> void:
	# #574: the splash is not a screen, it is the root node with the camera
	# parked on it. So it is the same solve() and a different transform.
	var splash := FrontmatterLayout.splash_camera(_tree)
	assert_eq(FrontmatterLayout.zoom_of(splash),
			Vector2.ONE * FrontmatterLayout.SPLASH_ZOOM)
	var slot := FrontmatterLayout.slot(FrontmatterLayout.SPLASH_SLOT_RATIO)
	var landed := FrontmatterLayout.screen_to_world(splash, slot)
	var root_at: Vector2 = FrontmatterLayout.solve(_tree)[_tree.root]
	assert_almost_eq(landed.x, root_at.x, 0.001)
	assert_almost_eq(landed.y, root_at.y, 0.001)


func test_an_empty_tree_solves_to_nothing_rather_than_crashing() -> void:
	assert_eq(FrontmatterLayout.solve(null), {})
	assert_eq(FrontmatterLayout.solve(MenuGraph.new()), {})
	assert_eq(FrontmatterLayout.preview_slots(null, MenuGraph.ID_ROOT), {})


# --- 5. the scene skeleton --------------------------------------------------

## The one piece of this unit that is a scene rather than a function. It is
## asserted here because #570 (the camera) and #573 (the panels) both find their
## way around it by unique name, and a renamed node is a silent `null` in both.
func test_the_frontmatter_skeleton_is_two_layers_the_camera_and_nothing_else() -> void:
	var root: Node2D = preload("res://ui/frontmatter/frontmatter_root.tscn").instantiate()
	add_child_autofree(root)

	assert_true(root is FrontmatterRoot, "the shell script #570 added")
	assert_true(root.get_node("%Camera") is Camera2D)
	assert_true(root.get_node("%GraphLayer") is Node2D)
	assert_gt(root.get_node("%GraphLayer").get_child_count(), 0,
			"the shell fills the graph layer at build; the layer itself is authored empty")

	# A CanvasLayer is immune to the camera transform by design — anchored
	# Controls sharing the camera's canvas get panned AND zoomed, which is the
	# "why is the lobby text blurry and drifting" bug (#567).
	var panel_layer := root.get_node("%PanelLayer")
	assert_true(panel_layer is CanvasLayer)
	assert_true(panel_layer.get_child(0) is FrontmatterPanels,
			"the panel container is instanced here so #573 never edits this scene")
	# Exactly one container, not exactly one child: #575's tooltip is minted at
	# build and parented here too (it needs the same immunity to the camera that
	# the panels need). What must stay true is that the AUTHORED child is the
	# container, and that nothing has quietly grown a second one.
	var containers := 0
	for child in panel_layer.get_children():
		if child is FrontmatterPanels:
			containers += 1
	assert_eq(containers, 1, "one panel container, authored in this scene")


func test_the_panel_seam_answers_for_every_leaf_panel_this_tree_names() -> void:
	# The seam only, not the panels: #573 fills them. What is pinned today is
	# that every leaf routes through `show_panel`/`hide_all` and that an
	# unlanded panel is a no-op rather than a crash.
	# The SCENE, not `FrontmatterPanels.new()`: a bare `new()` type-checks but
	# builds a container with none of its scene's children, so it would go on
	# agreeing with this test after #573 fills the panels in.
	var panels: FrontmatterPanels = preload(
			"res://ui/frontmatter/panels/frontmatter_panels.tscn").instantiate()
	add_child_autofree(panels)
	for id in _tree.ids():
		var item := _tree.get_item(id)
		if item.is_leaf():
			panels.show_panel(item.panel)
			assert_eq(panels.shown_panel, item.panel, "'%s' raises its panel" % id)
	panels.hide_all()
	assert_eq(panels.shown_panel, &"", "and the graph layer gets the stage back")
