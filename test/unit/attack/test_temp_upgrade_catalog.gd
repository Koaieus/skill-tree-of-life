extends GutTest

## The temp-upgrade catalog scans a folder of addon scenes; the scene is the
## kind, on the wire too. Preloading the `.tres` from a TEST script is not the
## parse cycle the catalog script itself must avoid.

const CATALOG: TempUpgradeCatalog = preload("res://attack/melee/temp_upgrade_catalog.tres")
const _FIXTURES := "res://test/support/addons"
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
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


func test_offered_is_the_temp_placeable_subset() -> void:
	var offered := _paths(CATALOG.offered())
	var expected: Array[String] = []
	for scene in CATALOG.kinds():
		if SkillNodeAddon.temp_placeable_of(scene):
			expected.append(scene.resource_path)
	assert_gt(expected.size(), 1, "fixture check: several kinds are offered")
	offered.sort()
	assert_eq(offered, expected, "offered is exactly the temp-placeable kinds")
	assert_eq(_paths(_fixture_catalog().offered()),
			[_FIXTURES.path_join("second_dot_addon.tscn")] as Array[String])


## The shop's canonical order: by role in enum order, then blade-size price
## ascending, then scene path.
func _order_key(scene: PackedScene) -> Array:
	return [SkillNodeAddon.role_of(scene),
			SkillNodeAddon.temp_costs_of(scene, 0).get(&"blade_size", 0),
			scene.resource_path]


func test_offered_is_grouped_by_role_then_price_then_path() -> void:
	var offered := CATALOG.offered()
	for i in range(1, offered.size()):
		var a := _order_key(offered[i - 1])
		var b := _order_key(offered[i])
		var ordered: bool = a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1]
				or (a[1] == b[1] and a[2] < b[2])))
		assert_true(ordered, "%s must precede %s" % [a, b])


func test_every_addon_def_has_its_role_set() -> void:
	for scene in CATALOG.kinds():
		assert_ne(SkillNodeAddon.role_of(scene), SkillNodeAddon.Role.UNSET,
				"%s has no role tag" % scene.resource_path)


func test_by_kind_returns_the_kinds_entry_itself() -> void:
	for scene in CATALOG.kinds():
		assert_true(CATALOG.by_kind(scene.resource_path) == scene,
				"%s round-trips by identity" % scene.resource_path)
	assert_true(CATALOG.by_kind(_TOXIN.resource_path) == _TOXIN, "a preload is the same object")
	assert_null(CATALOG.by_kind("res://no/such_addon.tscn"))
	assert_null(CATALOG.by_kind(""))


func test_a_melee_plan_carries_a_temp_toxin_across_the_wire_by_kind() -> void:
	var graph := TestWorld.create(self).graph
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
	var alloc := TestWorld.allocator_for(graph)
	for n in nodes:
		alloc.force_allocate(attacker, n)
	attacker.core_location = nodes[0]
	attacker.stat_board.blade_size.base_value = 3.0
	attacker.stat_board.facet(&"poison", StatDef.Role.ASPECT).base_value = 1.0

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
