extends GutTest

## #1654 acceptance 1 — a faced Dormant Core ([BlockerCoreClass]) holds its
## aspect grants in the core register, scaled by size; a resistance only where
## the stat exists; sunder by count + stacks, no resistance; a faceless blocker unchanged.

const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _POISON := preload("res://entity/blocker/faces/poison_face.tres")
const _GREED := preload("res://entity/blocker/faces/greed_face.tres")
const _SUNDER := preload("res://entity/blocker/faces/sunder_face.tres")
const _FACELESS := preload("res://entity/blocker/blocker_core.tres")
const _LARGE := EntityFactory.BlockerSize.LARGE
const _SMALL := EntityFactory.BlockerSize.SMALL
const _FACES_DIR := "res://entity/blocker/faces/"


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
		assert_lte(res[0].value, 1.0, "a resistance is a fraction: 1.0 is immune")


## Every shipped face's `resistance_by_size` is a fraction per size (0..1, 1.0 =
## immune) and never shrinks with size. Reads only the array: which faces the
## grant reaches depends on which `<id>_resistance` stats exist.
func test_every_face_resistance_by_size_is_a_non_decreasing_fraction() -> void:
	var visited := 0
	for file in ResourceLoader.list_directory(_FACES_DIR):
		if not file.ends_with(".tres"):
			continue
		var face := load(_FACES_DIR + file) as BlockerCoreClass
		if face == null:
			continue
		visited += 1
		var values := face.resistance_by_size
		for i in values.size():
			assert_between(values[i], 0.0, 1.0, "%s size %d is a fraction" % [file, i])
			if i > 0:
				assert_gte(values[i], values[i - 1], "%s size %d never shrinks" % [file, i])
	assert_gt(visited, 0, "the faces directory holds faces")


func test_small_poison_face_grants_its_resistance() -> void:
	var res := _grants(_spawn(_SMALL, _POISON), &"poison_resistance")
	assert_eq(res.size(), 1, "even a small poison face resists poison")
	if res.size() == 1:
		assert_eq(res[0].value, _POISON.resistance_by_size[0], "SMALL resistance")
		assert_gt(res[0].value, 0.0)


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


func test_sunder_face_grants_count_and_stacks_without_resistance() -> void:
	var ent := _spawn(_LARGE, _SUNDER)
	assert_gt(ent.core_modifiers.size(), 0, "sunder grants something")
	var total := 0.0
	for m in ent.core_modifiers:
		assert_true(m.stat_id in [&"sunder_aspect", &"sunder_stacks_per_hit"],
				"count or stacks, never a resistance")
		if m.stat_id == &"sunder_aspect":
			total += m.value
	assert_gt(_SUNDER.extra_count_by_size[2], 0, "large sunder grows by count")
	assert_eq(total, float(_SUNDER.count_by_size[2] + _SUNDER.extra_count_by_size[2]))


func test_faceless_blocker_is_unchanged() -> void:
	var ent := _spawn(_LARGE, null)
	assert_eq(ent.core_class, _FACELESS, "the scene's faceless class")
	assert_eq(ent.core_modifiers.size(), 0, "no grants")
	assert_eq(ent.color, Color(0.3, 0.27, 0.42, 1), "the scene's gray")
