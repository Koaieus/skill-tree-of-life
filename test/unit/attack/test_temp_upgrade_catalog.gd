extends GutTest

## The temp-upgrade catalog scans a folder of addon scenes; the scene is the
## kind, on the wire too. Preloading the `.tres` from a TEST script is not the
## parse cycle the catalog script itself must avoid.

const CATALOG: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")
const _FIXTURES := "res://test/fixtures/addons"
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")
const _TOXIN := preload("res://skill_node/addons/defs/toxin_addon.tscn")


func _paths(scenes: Array[PackedScene]) -> Array[String]:
	var out: Array[String] = []
	for s in scenes:
		out.append(s.resource_path)
	return out


func _fixture_catalog() -> TempUpgradeCatalog:
	var c := TempUpgradeCatalog.new()
	c.folder = _FIXTURES
	return c


func test_kinds_are_every_addon_scene_in_the_folder_sorted() -> void:
	var expected: Array[String] = []
	for f in ResourceLoader.list_directory(CATALOG.folder):
		if f.ends_with(".tscn"):
			expected.append(CATALOG.folder.path_join(f))
	expected.sort()
	assert_gt(expected.size(), 0, "fixture check: the folder holds scenes")
	assert_eq(_paths(CATALOG.kinds()), expected)


func test_a_catalog_on_the_fixture_folder_lists_its_addons_and_nothing_else() -> void:
	assert_eq(_paths(_fixture_catalog().kinds()), [
		_FIXTURES.path_join("bare_addon.tscn"),
		_FIXTURES.path_join("second_dot_addon.tscn"),
	] as Array[String], "the non-addon scene is skipped")


func test_offered_is_the_temp_placeable_subset_in_order() -> void:
	assert_eq(_paths(CATALOG.offered()), [
		"res://skill_node/addons/defs/clamp_addon.tscn",
		"res://skill_node/addons/defs/compromiser_addon.tscn",
		"res://skill_node/addons/defs/spike_ring_addon.tscn",
		"res://skill_node/addons/defs/toxin_addon.tscn",
	] as Array[String])
	for scene in CATALOG.kinds():
		assert_eq(CATALOG.offered().has(scene), SkillNodeAddon.temp_placeable_of(scene),
				"%s offered iff temp_placeable" % scene.resource_path)
	assert_eq(_paths(_fixture_catalog().offered()),
			[_FIXTURES.path_join("second_dot_addon.tscn")] as Array[String])


func test_by_kind_returns_the_kinds_entry_itself() -> void:
	for scene in CATALOG.kinds():
		assert_true(CATALOG.by_kind(scene.resource_path) == scene,
				"%s round-trips by identity" % scene.resource_path)
	assert_true(CATALOG.by_kind(_TOXIN.resource_path) == _TOXIN, "a preload is the same object")
	assert_null(CATALOG.by_kind("res://no/such_addon.tscn"))
	assert_null(CATALOG.by_kind(""))


func test_a_melee_plan_carries_a_temp_toxin_across_the_wire_by_kind() -> void:
	var graph := _GRAPH_SCENE.instantiate() as Graph
	add_child_autofree(graph)
	var nodes: Array[SkillNode] = []
	for x in [0, 200]:
		var node := _SKILL_NODE_SCENE.instantiate() as SkillNode
		node.position = Vector2(x, 0)
		graph.add_skill_node(node)
		nodes.append(node)
	graph.add_edge(nodes[0], nodes[1])
	var attacker := Entity.new()
	attacker.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	graph.entities_container.add_child(attacker)
	await get_tree().process_frame
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	for n in nodes:
		alloc.force_allocate(attacker, n)
	attacker.core_location = nodes[0]
	attacker.stat_board.blade_size.base_value = 3.0
	attacker.stat_board.poison_aspect.base_value = 1.0

	var plan := MeleeAttackPlan.new()
	plan.attacker = attacker
	plan.set_pivot(nodes[0])
	plan.toggle_member(nodes[1])
	assert_true(plan.apply_temp_upgrade(nodes[1], _TOXIN),
			"fixture must have placed the toxin for this to mean anything")
	var d := plan.to_dict(graph)
	assert_eq(d.get("temps"), [[graph.get_stable_id(nodes[1]), _TOXIN.resource_path]],
			"a temp crosses as [stable id, kind]")
	plan.reset()

	var back := AttackPlanCodec.from_dict(d, graph, CATALOG) as MeleeAttackPlan
	var kinds: Array[String] = []
	for a in nodes[1].get_addons():
		if a.is_temporary:
			kinds.append(a.get_kind())
	assert_eq(kinds, [_TOXIN.resource_path] as Array[String], "the same kind on the same node")
	back.reset()


func test_the_def_class_is_gone() -> void:
	for entry in ProjectSettings.get_global_class_list():
		assert_ne(entry["class"], &"TempUpgradeDef", "TempUpgradeDef no longer resolves")
	assert_false(ClassDB.class_exists(&"TempUpgradeDef"))
