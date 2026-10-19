extends GutTest

## #1654 acceptance 1 — a faced Dormant Core ([BlockerCoreClass]) holds its
## aspect grants in the core register, scaled by size; a resistance only where
## the stat exists; sunder by count only; a faceless blocker unchanged.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON := preload("res://entity/blocker/faces/poison_face.tres")
const _GREED := preload("res://entity/blocker/faces/greed_face.tres")
const _SUNDER := preload("res://entity/blocker/faces/sunder_face.tres")
const _FACELESS := preload("res://entity/blocker/blocker_core.tres")
const _LARGE := EntityFactory.BlockerSize.LARGE


func _factory() -> EntityFactory:
	var graph := autofree(_GRAPH_SCENE.instantiate()) as Graph
	add_child(graph)
	var alloc := AllocationSystem.new()
	alloc.graph = graph
	add_child_autofree(alloc)
	var factory := EntityFactory.new()
	autofree(factory)
	factory.graph = graph
	factory.allocation_system = alloc
	return factory


func _spawn(size: EntityFactory.BlockerSize, face: CoreClass, face_seed: int = 1) -> Entity:
	return _factory().spawn_blocker(size, null, [], 0, 0.0, 0, 1, 0.25, face, face_seed)


func _grants(ent: Entity, stat_id: StringName) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for m in ent.core_modifiers:
		if m.stat_id == stat_id:
			out.append(m)
	return out


func test_large_poison_face_grants_count_potency_and_resistance() -> void:
	var ent := _spawn(_LARGE, _POISON)
	assert_eq(ent.core_class, _POISON, "the face overrides the scene's class")
	assert_eq(ent.color, _POISON.identity.tint, "the blocker wears the aspect's tint")
	var count := _grants(ent, &"poison_aspect")
	assert_eq(count.size(), 1, "one count grant")
	if count.size() == 1:
		assert_eq(count[0].operation, StatModifier.Operation.ADD_BASE)
		assert_eq(count[0].value, float(_POISON.count_by_size[2]), "LARGE count")
		assert_true(count[0].loot_pinned, "a face grant is pinned")
	assert_eq(float(ent.stat_board.get_value(&"poison_aspect")), float(_POISON.count_by_size[2]),
			"the sparse board took the grant, not just the register")
	var potency := _grants(ent, &"poison_stacks_per_hit")
	assert_eq(potency.size(), 1, "one potency grant")
	if potency.size() == 1:
		var p := potency[0]
		var additive: bool = p.operation == StatModifier.Operation.ADD_BASE \
				and p.value == _POISON.potency_by_size[2]
		var multiply: bool = p.operation == StatModifier.Operation.MULTIPLY \
				and p.value == _POISON.potency_multiply_value
		assert_true(additive or multiply, "LARGE potency is +N or ×N")
		assert_true(p.loot_pinned)
	var res := _grants(ent, &"poison_resistance")
	assert_eq(res.size(), 1, "poison resistance exists, so it is granted")
	if res.size() == 1:
		assert_eq(res[0].value, _POISON.resistance_by_size[2], "LARGE resistance")


func test_large_potency_rolls_both_ways_across_seeds() -> void:
	var ops := {}
	for s in 64:
		for m in _POISON.grants_for(2, s):
			if m.stat_id == &"poison_stacks_per_hit":
				ops[m.operation] = true
	assert_true(ops.has(StatModifier.Operation.ADD_BASE), "some seeds roll +N")
	assert_true(ops.has(StatModifier.Operation.MULTIPLY), "some seeds roll ×N")


func test_greed_face_grants_no_resistance() -> void:
	var ent := _spawn(_LARGE, _GREED)
	assert_eq(_grants(ent, &"greed_aspect").size(), 1, "greed count granted")
	assert_eq(_grants(ent, &"greed_resistance").size(), 0, "no greed_resistance stat, no grant")


func test_sunder_face_grants_count_only() -> void:
	var ent := _spawn(_LARGE, _SUNDER)
	assert_gt(ent.core_modifiers.size(), 0, "sunder grants something")
	var total := 0.0
	for m in ent.core_modifiers:
		assert_eq(m.stat_id, &"sunder_aspect", "count only")
		total += m.value
	assert_gt(_SUNDER.extra_count_by_size[2], 0, "large sunder grows by count")
	assert_eq(total, float(_SUNDER.count_by_size[2] + _SUNDER.extra_count_by_size[2]))


func test_faceless_blocker_is_unchanged() -> void:
	var ent := _spawn(_LARGE, null)
	assert_eq(ent.core_class, _FACELESS, "the scene's faceless class")
	assert_eq(ent.core_modifiers.size(), 0, "no grants")
	assert_eq(ent.color, Color(0.3, 0.27, 0.42, 1), "the scene's gray")
