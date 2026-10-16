extends GutTest

## TestWorld's own contract: a graph built through it is mirrored by the
## graph's Navigator, and ownership assigned through it reaches the owner,
## the entity's navigator and the SP pool exactly as force_allocate does.


func test_chain_two_entities_one_node_each() -> void:
	var w := TestWorld.create(self)
	var a := w.add_node(&"a", Vector2(0, 0))
	var b := w.add_node(&"b", Vector2(100, 0))
	var c := w.add_node(&"c", Vector2(200, 0))
	w.link(a, b)
	w.link(b, c)
	var red := w.add_entity("Red")
	var blue := w.add_entity("Blue")
	var red_used_before: int = red.stat_board.skill_points.used
	var red_available_before: int = red.stat_board.skill_points.available()
	w.allocate(red, [a])
	w.allocate(blue, [c])

	var nav := w.graph.navigator
	assert_eq(nav.get_mirrored_nodes().size(), 3, "graph navigator mirrors all 3 nodes")
	assert_true(nav.are_adjacent(a, b) and nav.are_adjacent(b, c), "chain edges mirrored")
	assert_false(nav.are_adjacent(a, c), "no shortcut edge")
	assert_eq(a.global_position, Vector2(0, 0))
	assert_eq(c.global_position, Vector2(200, 0))

	assert_eq(a.owned_by, red, "a -> Red")
	assert_eq(c.owned_by, blue, "c -> Blue")
	assert_null(b.owned_by, "b unallocated")
	assert_eq(red.core_location, a, "first allocated node anchors the core")
	assert_eq(red.navigator.get_mirrored_nodes(), [a] as Array[SkillNode])
	assert_eq(blue.navigator.get_mirrored_nodes(), [c] as Array[SkillNode])

	assert_eq(red.stat_board.skill_points.used, red_used_before + 1, "force_allocate claims 1 SP")
	assert_eq(red.stat_board.skill_points.available(), red_available_before,
			"a claim mints, it does not spend")
	assert_true(red.get_parent() == w.graph.entities_container, "entities live in the container")
	assert_eq(w.allocator().graph, w.graph)


func test_entities_are_mutually_hostile_by_default() -> void:
	var w := TestWorld.create(self)
	var red := w.add_entity("Red")
	var blue := w.add_entity("Blue")
	assert_ne(red.faction, blue.faction, "each entity gets its own camp")
