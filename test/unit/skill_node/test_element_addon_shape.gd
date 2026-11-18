extends GutTest

## The element addon's shape (#1804): an addon whose rider plants an element's
## terrain status grants the rider and nothing else — no stat modifier — and
## costs exactly 1 of that element's count. The directory walk pins every such
## scene #1805 / #1806 / #1807 add; the fixture carries the shape today: its
## rider rides only its own carrier's vertex, and a swing with count 0 cannot
## afford it.

const _DEFS_DIR := "res://skill_node/addons/defs/"
const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")


## The element whose terrain status [param def] is, or null.
func _element_of(def: StatusDef) -> Element:
	if def == null:
		return null
	for e: Element in ElementRoster.shared().elements:
		if e.terrain != null and e.terrain.id == def.id:
			return e
	return null


## The elements [param addon]'s riders plant.
func _planted(addon: SkillNodeAddon) -> Array[Element]:
	var out: Array[Element] = []
	for effect in addon.on_hit_effects:
		if effect is ApplyStatusEffect:
			var e := _element_of((effect as ApplyStatusEffect).def)
			if e != null and not out.has(e):
				out.append(e)
	return out


func _assert_shape(addon: SkillNodeAddon, label: String) -> void:
	var planted := _planted(addon)
	assert_eq(planted.size(), 1, "%s plants one element" % label)
	if planted.is_empty():
		return
	assert_true(addon.entity_modifiers.is_empty(), "%s: no entity stat modifier" % label)
	assert_true(addon.local_modifiers.is_empty(), "%s: no local stat modifier" % label)
	var count_id := planted[0].stat.id
	assert_eq(int(addon.temp_cost_aspects.get(count_id, 0)), 1,
			"%s costs exactly 1 %s" % [label, count_id])


## An element addon as #1805 / #1806 / #1807 author one: Fire's terrain rider
## at power 1, costing 1 fire_element.
func _fixture() -> SkillNodeAddon:
	var fire := ElementRoster.shared().by_id(&"fire")
	var rider := ApplyStatusEffect.new()
	rider.def = fire.terrain
	rider.power = 1.0
	var addon := SkillNodeAddon.new()
	addon.on_hit_effects.append(rider)
	addon.temp_placeable = true
	var costs: Dictionary[StringName, int] = {fire.stat.id: 1}
	addon.temp_cost_aspects = costs
	return addon


func test_every_element_addon_scene_is_rider_only_and_costs_one_count() -> void:
	for file in ResourceLoader.list_directory(_DEFS_DIR):
		if not file.ends_with(".tscn"):
			continue
		var addon := (load(_DEFS_DIR + file) as PackedScene).instantiate() as SkillNodeAddon
		if addon == null:
			continue
		if not _planted(addon).is_empty():
			_assert_shape(addon, file)
		addon.free()
	pass_test("the walk ran (a pin for the element units' scenes)")


func test_the_fixture_has_the_shape() -> void:
	var addon := _fixture()
	_assert_shape(addon, "fixture")
	addon.free()


func test_the_fixture_rides_its_own_vertex_only() -> void:
	var graph: Graph = TestWorld.create(self).graph
	var nodes: Array[SkillNode] = []
	for nm in ["Pivot", "Carrier", "Plain"]:
		var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
		sn.name = nm
		graph.add_skill_node(sn)
		nodes.append(sn)
	await get_tree().process_frame
	nodes[1].add_child(_fixture())
	await get_tree().process_frame
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(50, 0), Vector2(100, 0)]
	var radii: Array[float] = [16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2)]
	var s := BladeState.build(positions, 0, edges, radii)
	BladeVertexFill.new().fill(s, nodes)
	assert_eq((s.vertex_on_hit[1] as Array).size(), 1, "the carrier's vertex carries the rider")
	assert_true((s.vertex_on_hit[0] as Array).is_empty(), "the pivot carries none")
	assert_true((s.vertex_on_hit[2] as Array).is_empty(), "the other member carries none")


func test_a_swing_with_count_zero_cannot_afford_it() -> void:
	var entity := Entity.new()
	entity.stat_board = _BOARD.duplicate(true) as EntityStatBoard
	add_child_autofree(entity)
	var plan := autofree(MeleeAttackPlan.new()) as MeleeAttackPlan
	plan.attacker = entity
	var fire := ElementRoster.shared().by_id(&"fire")
	assert_eq(plan.currency_cap(fire.stat.id), 0, "fixture: no fire_element")
	var addon := _fixture()
	var scene := PackedScene.new()
	assert_eq(scene.pack(addon), OK, "fixture: the addon packs")
	assert_false(plan._affords(scene), "count 0: the swing cannot afford it")
	addon.free()
