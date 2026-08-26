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
	return FrontmatterLayout.column_step()


## The pitch `parent`'s authored fan actually spaces its children at. Read off
## the solved positions rather than off a constant: since #590 there is no one
## sibling gap, each fan authors its own in `ui/frontmatter/layout/`.
func _fan_pitch(parent: StringName) -> float:
	var positions := FrontmatterLayout.solve(_tree)
	var children := _tree.children_of(parent)
	assert_gt(children.size(), 1, "'%s' has a pitch to measure" % parent)
	return positions[children[1]].y - positions[children[0]].y


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
	#
	# Re-pointed by #590: the step is no longer a ratio constant, it is
	# `%HeroSlot`'s authored width in `menu_harness.tscn` — and because every fan
	# is an INHERITED scene of that one base, every fan shares it. The assertion
	# is the one it always was; only where the number comes from moved.
	var positions := FrontmatterLayout.solve(_tree)
	assert_almost_eq(_column_step(), 306.0, 0.001, "hero slot 190 -> option column 496")
	for id in _tree.ids():
		assert_almost_eq(positions[id].x, _tree.depth_of(id) * _column_step(), 0.001,
				"'%s' sits in its depth's column" % id)


func test_leaf_siblings_are_exactly_a_row_gap_apart() -> void:
	# Re-pointed by #590. The old assertion was "every fan uses THE design row
	# gap"; a fan authors its own now, so the surviving half is "within one fan
	# the pitch is uniform", which is what a [VBoxContainer] gives for free and
	# what a future author could still break with a stray slot height.
	var positions := FrontmatterLayout.solve(_tree)
	for parent in [MenuGraph.ID_SINGLE_PLAYER, MenuGraph.ID_MULTIPLAYER]:
		var children := _tree.children_of(parent)
		for i in children.size() - 1:
			assert_almost_eq(positions[children[i + 1]].y - positions[children[i]].y,
					_fan_pitch(parent), 0.001,
					"'%s' spaces its children by its own authored row gap" % parent)
	assert_almost_eq(_fan_pitch(MenuGraph.ID_SINGLE_PLAYER), 132.0, 0.001)
	assert_almost_eq(_fan_pitch(MenuGraph.ID_MULTIPLAYER), 110.0, 0.001)


func test_a_sibling_group_is_ordered_and_never_packed_tighter_than_a_peek_stack() -> void:
	# Re-pointed by #590, which retired "centred on its parent" outright: an
	# authored fan need not be, and the root fan deliberately is not — its four
	# rows are 212/168/132/132 tall so that `SINGLE PLAYER` and `MULTIPLAYER`
	# get the room their peek-ahead stacks need WITHOUT `OPTIONS -> EXIT`
	# inheriting it, which is the defect #589 measured.
	#
	# What survives is everything that is still a rule rather than a taste: a fan
	# runs top-to-bottom in tree order, and no two siblings sit closer than a
	# collapsed peek stack's own pitch. Evenness is asserted per fan by
	# `test_leaf_siblings_are_exactly_a_row_gap_apart`.
	var positions := FrontmatterLayout.solve(_tree)
	for parent in _tree.ids():
		var children := _tree.children_of(parent)
		for i in range(1, children.size()):
			var pitch: float = positions[children[i]].y - positions[children[i - 1]].y
			assert_true(pitch >= FrontmatterLayout.PREVIEW_GAP - 0.001,
					"'%s' never packs children tighter than a peek stack" % parent)


## Where every node actually sits when the menu is focused on [param focus] —
## the test's own copy of [method FrontmatterRoot._target_pose]'s rule, so the
## assertions below are about what is ON SCREEN rather than about `solve()`'s
## homes, which most nodes are not at most of the time.
func _poses_at(focus: StringName) -> Dictionary:
	var homes := FrontmatterLayout.solve(_tree)
	var path := _tree.path_to(focus)
	var poses: Dictionary = {}
	for id: StringName in homes:
		var parent := _tree.parent_of(id)
		if parent == &"" or path.has(parent):
			poses[id] = homes[id]
		else:
			poses[id] = FrontmatterLayout.preview_slots(_tree, parent).get(id, homes[id])
	return poses


func test_no_two_nodes_crowd_each_other_in_any_reachable_focus() -> void:
	# Cousins share a column, and under a camera that shows a whole column at
	# once an interleave is a collision.
	#
	# It is asserted per FOCUS, not over `solve()`'s homes, because only the
	# focus path's fans are grown out at any moment (#570's "grow, don't cut") —
	# everything else is stacked on its parent at the peek-ahead pitch. Asserting
	# it over the homes instead means demanding that subtrees which are never
	# expanded together still clear each other, which is what inflated the root
	# fan to 990 units of a 960-unit viewport.
	#
	# `solve()` stays focus-free; this walks every focus a player can reach and
	# checks the pictures it produces, which is the honest form of the claim.
	for focus in _tree.ids():
		var poses := _poses_at(focus)
		var ids := _tree.ids()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a: Vector2 = poses[ids[i]]
				var b: Vector2 = poses[ids[j]]
				# Only nodes near enough in x to overlap on screen — a home
				# column and the peek-ahead column beside it are 22 units apart,
				# so this cannot be an equality.
				if absf(a.x - b.x) >= _column_step() * 0.5:
					continue
				assert_true(
					absf(a.y - b.y) >= FrontmatterLayout.PREVIEW_GAP - 0.001,
					"at focus '%s', '%s' and '%s' overlap on screen"
						% [focus, ids[i], ids[j]]
				)


func test_every_reachable_focus_fits_on_screen() -> void:
	# The assertion the layout could not make before [method
	# FrontmatterLayout.fits_viewport] existed, and the one that would have
	# caught the shipped bug: at the root the four options spanned +/-495 in a
	# 960-unit viewport, so two of them were simply not drawn anywhere a player
	# could see.
	for focus in _tree.ids():
		assert_true(
			FrontmatterLayout.fits_viewport(_tree, focus),
			"focus '%s' puts a grown-out node off screen" % focus
		)


func test_a_fan_that_is_too_tall_is_reported_as_not_fitting() -> void:
	# fits_viewport has to be able to FAIL, or the test above passes vacuously.
	FrontmatterLayout.set_fan_separation(MenuGraph.ID_ROOT, 900.0)
	assert_false(
		FrontmatterLayout.fits_viewport(_tree, _tree.root),
		"a fan spread a whole viewport apart does not fit"
	)
	FrontmatterLayout.reset_geometry()


func test_the_preview_column_is_the_collapsed_peek_ahead_offset() -> void:
	# #571 reads these: a hovered node's children, stacked tight and small,
	# waiting to grow out to their real positions when it is selected.
	var positions := FrontmatterLayout.solve(_tree)
	var slots := FrontmatterLayout.preview_slots(_tree, MenuGraph.ID_MULTIPLAYER)
	var children := _tree.children_of(MenuGraph.ID_MULTIPLAYER)
	assert_eq(slots.size(), children.size())
	var column := FrontmatterLayout.PREVIEW_COLUMN
	var gap := FrontmatterLayout.PREVIEW_GAP
	var origin: Vector2 = positions[MenuGraph.ID_MULTIPLAYER]
	for i in children.size():
		var at: Vector2 = slots[children[i]]
		assert_almost_eq(at.x - origin.x, column, 0.001, "preview column offset")
		assert_almost_eq(at.y - origin.y, (i - 1) * gap, 0.001, "preview stack pitch")
	assert_true(gap < _fan_pitch(MenuGraph.ID_MULTIPLAYER),
			"the peek-ahead stack is tighter than the real one")
	assert_eq(FrontmatterLayout.preview_slots(_tree, MenuGraph.ID_JOIN), {},
			"a leaf has nothing to peek at")


func test_geometry_is_authored_in_the_harness_scenes_at_the_project_viewport() -> void:
	# Re-pointed by #590. The old version pinned six ratios of a 1440x900 design
	# canvas that was deliberately NOT the 1440x960 project viewport; #589 D4
	# deleted that second size outright, so the same numbers are now asserted
	# where they are now authored — the harness scenes — at the one viewport
	# there is.
	assert_eq(FrontmatterLayout.viewport_size(), Vector2(1440.0, 960.0),
			"the harness is authored at the project viewport, and there is no other")
	var hero := FrontmatterLayout.hero_slot()
	assert_almost_eq(hero.x, 190.0, 0.001, "%HeroSlot is 380 wide, so its centre is 190")
	assert_almost_eq(hero.y, 480.0, 0.001, "and it fills the height, so it is centred")
	assert_almost_eq(_column_step(), 306.0, 0.001, "hero 190 -> option column 496")
	assert_almost_eq(FrontmatterLayout.PREVIEW_SCALE, 0.42, 0.0001)
	assert_almost_eq(FrontmatterLayout.SPLASH_ZOOM, 3.2, 0.0001)
	# #593's per-fan zoom is retired (owner call, 2026-08-26): there are only
	# two zooms in the whole menu, TREE_ZOOM and SPLASH_ZOOM, so the root is
	# seen at the same zoom as everything else and only its radius is bigger.
	assert_almost_eq(FrontmatterLayout.zoom_for(_tree, MenuGraph.ID_ROOT),
			FrontmatterLayout.TREE_ZOOM, 0.0001,
			"root_menu.tscn no longer parks the camera any closer")
	assert_almost_eq(FrontmatterLayout.look_of(MenuGraph.ID_ROOT).radius, 44.0, 0.001,
			"and root_menu.tscn's %HeroSlot draws a bigger disk")


func test_every_menu_id_is_seated_in_exactly_one_authored_slot() -> void:
	# #589 D5: the scenes carry geometry, `MenuGraph` carries topology, and the
	# 1:1 between them is checked at build rather than discovered as a node that
	# never drew. An unseated id has no position at all, which is why
	# `solve()` asserts rather than falling back.
	var seated: Array[StringName] = []
	for hero_id in FrontmatterLayout.fan_ids():
		var fan: MenuFanHarness.Measured = FrontmatterLayout.fans()[hero_id]
		assert_true(_tree.has(hero_id), "'%s' fans out from a known id" % hero_id)
		for slot_id: StringName in fan.slots:
			assert_false(seated.has(slot_id), "'%s' is seated once" % slot_id)
			assert_eq(_tree.parent_of(slot_id), hero_id,
					"'%s' is seated in its own parent's fan" % slot_id)
			seated.append(slot_id)
	for id in _tree.ids():
		if id == _tree.root:
			continue
		assert_true(seated.has(id), "'%s' has an authored slot" % id)
	assert_eq(seated.size(), _tree.size() - 1, "the root is the one node with no slot")


func test_the_look_is_authored_on_the_slots_and_nowhere_else() -> void:
	# #591 / #589 D5. `MenuGraph` is topology and routing; every display string
	# lives in the fan scene, where an author sees it at full-screen scale. The
	# grep is the acceptance in its bluntest form — a caption that crept back
	# into `build()` fails here rather than at a review.
	var source := FileAccess.get_file_as_string("res://ui/frontmatter/menu_graph.gd")
	assert_false(source.is_empty(), "menu_graph.gd is readable")
	for display: String in ["SINGLE PLAYER", "+1 PLAYERS", "SKILL TREE OF LIFE", "wisdom"]:
		assert_false(source.contains(display),
				"'%s' is authored in a fan scene, not in MenuGraph.build()" % display)

	for id in _tree.ids():
		var look := FrontmatterLayout.look_of(id)
		assert_not_null(look, "'%s' has an authored look" % id)
		assert_eq(look.id, id, "a look answers under its own id")
		assert_ne(look.title, "", "'%s' is captioned" % id)
		assert_not_null(MenuNodeView.archetype_for(look.archetype),
				"'%s' names a real archetype" % id)
		assert_gt(look.radius, 0.0, "'%s' has a size" % id)
	assert_null(FrontmatterLayout.look_of(&"nonexistent"))

	# The root is the one node with no seat in anybody's fan — it has no parent
	# — so `root_menu.tscn`'s own `%HeroSlot` is where its look is authored.
	assert_eq(FrontmatterLayout.look_of(MenuGraph.ID_ROOT).title, "SKILL TREE OF LIFE")
	assert_eq(FrontmatterLayout.look_of(MenuGraph.ID_SINGLE_PLAYER).subtitle, "+1 PLAYERS")
	assert_eq(FrontmatterLayout.look_of(MenuGraph.ID_EXIT).subtitle, "",
			"only the two joke nodes carry a slab")


func test_a_decorative_slot_reserves_a_row_without_naming_a_menu_id() -> void:
	# The seam for the owner's pre-authored bonus nodes (#589): a fan may carry
	# scenery, and the 1:1 cross-check has to skip it rather than assert on an
	# id `MenuGraph` has never heard of. Nothing ships one yet, so this measures
	# a harness built here — which is also the cheapest proof that a decorative
	# seat still shapes the fan's pitch like any other slot.
	var harness: MenuFanHarness = preload(
			"res://ui/frontmatter/layout/multiplayer_menu.tscn").instantiate()
	var scenery := MenuSlot.new()
	scenery.menu_id = &"a_bonus_node"
	scenery.decorative = true
	scenery.title = "BONUS"
	scenery.custom_minimum_size = Vector2(0.0, 110.0)
	harness.options_box().add_child(scenery)

	var measured := harness.measure(FrontmatterLayout.viewport_size())
	harness.free()

	assert_false(measured.slots.has(&"a_bonus_node"),
			"scenery is not a seat the tree has to account for")
	assert_true(measured.decor.has(&"a_bonus_node"),
			"but it is placed, so a later unit can draw it")
	assert_eq(measured.looks.size(), 4,
			"and it authors its look off the same exports")
	assert_eq(FrontmatterLayout.decor_slots(_tree), {},
			"no fan ships scenery yet — #591 builds the seam and no content")


func test_the_root_fan_owns_its_own_gaps() -> void:
	# The numeric case #589 makes for authoring: the shipped solver derived 201
	# for the root fan — 52% looser than every fan below it — because
	# `MULTIPLAYER`'s collapsed peek stack had to clear `SINGLE PLAYER`'s, and it
	# then applied that same looseness to `OPTIONS -> EXIT`, which needed none.
	var positions := FrontmatterLayout.solve(_tree)
	var options := _tree.children_of(MenuGraph.ID_ROOT)
	var gaps: Array[float] = []
	for i in range(1, options.size()):
		gaps.append(positions[options[i]].y - positions[options[i - 1]].y)
	assert_eq(gaps.size(), 3)
	assert_almost_eq(gaps[0], 190.0, 0.001, "SINGLE PLAYER -> MULTIPLAYER, authored")
	assert_almost_eq(gaps[1], 150.0, 0.001, "MULTIPLAYER -> OPTIONS")
	assert_almost_eq(gaps[2], 132.0, 0.001,
			"OPTIONS -> EXIT is two leaves, and pays for nobody's peek stack")
	assert_true(gaps[0] < 201.0, "no neighbour's subtree forces the root fan's pitch")


func test_the_harness_is_freed_before_anything_can_animate() -> void:
	# #589 D3. The harness is a `Control` tree in SCREEN space; the menu is
	# `Node2D` views under a `Camera2D` in WORLD space. A harness left alive
	# would re-lay-out on a window resize under a camera that had already baked
	# its numbers — a second layout system racing the first. So: solving reads
	# it and drops it, and a built menu contains no piece of it.
	FrontmatterLayout.solve(_tree)
	for node in get_tree().root.find_children("*", "MenuFanHarness", true, false):
		assert_true(false, "a fan harness is still in the tree: %s" % node)

	var root: FrontmatterRoot = preload(
			"res://ui/frontmatter/frontmatter_root.tscn").instantiate()
	add_child_autofree(root)
	root.build(_tree)
	assert_eq(root.find_children("*", "MenuFanHarness", true, false).size(), 0,
			"build() leaves no harness behind")
	assert_eq(root.find_children("*", "MenuSlot", true, false).size(), 0,
			"nor any of its slots")


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
	var hero := FrontmatterLayout.hero_slot()
	var landed := FrontmatterLayout.screen_to_world(xform, hero)
	var want: Vector2 = FrontmatterLayout.solve(_tree)[focus]
	assert_almost_eq(landed.x, want.x, 0.001, "'%s' lands on the hero slot" % focus)
	assert_almost_eq(landed.y, want.y, 0.001, "'%s' lands on the hero slot" % focus)


func test_camera_docks_the_focus_in_the_hero_slot_at_every_depth() -> void:
	_assert_lands_on_hero(MenuGraph.ID_ROOT)
	_assert_lands_on_hero(MenuGraph.ID_MULTIPLAYER)
	_assert_lands_on_hero(MenuGraph.ID_JOIN)


func test_navigating_moves_the_camera_but_never_the_zoom() -> void:
	# Re-pointed by D1 (#603): #593's per-fan `camera_zoom` is retired (owner
	# call, 2026-08-26 — "there is just" the splash zoom and "zoomed back out
	# to normal"), so this no longer excludes the root: every id, root
	# included, shares TREE_ZOOM. What survives is that navigating moves the
	# camera's ORIGIN and never its zoom.
	var root_cam := FrontmatterLayout.camera_for(_tree, MenuGraph.ID_ROOT)
	var leaf_cam := FrontmatterLayout.camera_for(_tree, MenuGraph.ID_JOIN)
	assert_ne(root_cam.origin, leaf_cam.origin, "the camera travels")
	for cam in [root_cam, leaf_cam]:
		assert_eq(FrontmatterLayout.zoom_of(cam), Vector2.ONE * FrontmatterLayout.TREE_ZOOM,
				"every id is seen at the one tree zoom")
	for id in _tree.ids():
		assert_almost_eq(FrontmatterLayout.zoom_for(_tree, id),
				FrontmatterLayout.TREE_ZOOM, 0.0001,
				"'%s' does not author a zoom of its own — nothing does anymore" % id)
	assert_gt(FrontmatterLayout.SPLASH_ZOOM, FrontmatterLayout.TREE_ZOOM,
			"the splash is still the one thing looked at closer than the tree")


func test_the_root_is_bigger_than_every_other_node() -> void:
	# Split from the old "...and closer..." by D1 (#603, acceptance 5): the
	# root's own `camera_zoom` is gone, so radius is now the ONLY thing making
	# the root read as the hero. There is no id check anywhere in code, which
	# is why this walks every OTHER id rather than naming one.
	var root_look := FrontmatterLayout.look_of(MenuGraph.ID_ROOT)
	for id in _tree.ids():
		if id == _tree.root:
			continue
		assert_gt(root_look.radius, FrontmatterLayout.look_of(id).radius,
				"the root is drawn bigger than '%s'" % id)


func test_an_unknown_focus_parks_on_the_root_at_the_roots_own_zoom() -> void:
	# The zoom has to fall back with the position, or an unknown focus lands on
	# the root's node at somebody else's distance from it.
	assert_almost_eq(FrontmatterLayout.zoom_for(_tree, &"nonexistent"),
			FrontmatterLayout.zoom_for(_tree, _tree.root), 0.0001)
	assert_almost_eq(FrontmatterLayout.zoom_for(null, MenuGraph.ID_ROOT),
			FrontmatterLayout.TREE_ZOOM, 0.0001, "no tree, no authored zoom")


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
