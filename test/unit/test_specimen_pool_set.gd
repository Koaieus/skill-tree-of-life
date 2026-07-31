extends GutTest

## Specimen pack loads, flattens per-node, and the negative-INCREASE clamp
## on the stat pipeline behaves as designed (stat zeros at sum ≤ −100%).
## v4 (#321): specimen set trimmed to strength during the engine landing;
## the other archetype packs are reauthored onto StatPool separately and
## restored to the set in the integration commit.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")
const _GP := preload("res://procgen/graph_procgen.gd")


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_specimen_loads_and_has_strength_pack() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	assert_eq(set.packs.size(), 1, "expected the strength pack (v4 landing state)")
	assert_eq(set.packs[0].archetype_stat, &"strength")


func test_specimen_flatten_for_strength_node_returns_strength_entries() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var primary := set.flatten_for_node(&"strength")
	assert_true(primary.size() > 0)
	for e in primary:
		assert_eq(e.stat_id, &"strength", "flatten_for_node should only return strength entries for a STR node")


func test_specimen_flatten_excludes_non_primary_archetype_pools() -> void:
	# No dexterity pack in the trimmed set; a DEX-primary node draws nothing.
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var none := set.flatten_for_node(&"dexterity")
	assert_eq(none.size(), 0, "no universal + no dexterity pack → empty flatten")


func test_procgen_draw_produces_strength_modifiers() -> void:
	var set: ModifierPoolSet = _SET.duplicate(true) as ModifierPoolSet
	var saw_strength := false
	for seed_value in range(1, 20):
		var rng := _rng(seed_value)
		var mods: Array = _GP._roll_modifiers_v4(
				set, [], &"strength", &"strength", [], Vector2.ZERO, 0, 7, rng)
		for m in mods:
			if m.stat_id == &"strength":
				saw_strength = true
	assert_true(saw_strength, "expected at least one strength roll across 19 seeded draws")


func test_pipeline_clamps_negative_increase_below_minus_100() -> void:
	# Standalone unit-test for the modifier_bins clamp. Build a board with
	# strength=10, stack INCREASE = -120%. Effective value should be 0
	# (not negative).
	var board := preload("res://entity/default_entity_board.tres").duplicate(true) as StatBoard
	board.strength.base_value = 10.0
	var m1 := StatModifier.new()
	m1.stat_id = &"strength"
	m1.operation = StatModifier.Operation.INCREASE
	m1.value = -60.0
	var m2 := StatModifier.new()
	m2.stat_id = &"strength"
	m2.operation = StatModifier.Operation.INCREASE
	m2.value = -60.0
	board.add_modifier(m1)
	board.add_modifier(m2)
	# (1 + (-120)/100) would be -0.2 → clamped to 0 → stat reads 0.
	assert_almost_eq(float(board.strength.get_value()), 0.0, 0.001)