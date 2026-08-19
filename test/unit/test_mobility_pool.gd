extends GutTest
## v4 StatPool conformance for mobility.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/mobility.tres")
const _GP := preload("res://procgen/graph_procgen.gd")

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p)
	assert_eq(p.archetype_stat, &"")
	assert_true(p.pools.size() > 0)


func test_all_pools_are_universal() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		assert_eq(pp.archetype_stat, &"", "pool %s should be universal" % String(pp.stat_id))


func test_movement_points_pool_values() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"movement_points" and pp.operation == StatModifier.Operation.ADD_BASE:
			assert_eq(pp.unit_value, 1.0)
			assert_eq(pp.min_tier, 1)
			assert_eq(pp.max_tier, 2)
			assert_eq(pp.to_entries().size(), 2)
			var e0 = pp.to_entries()[0]
			assert_almost_eq((e0.value_range.x + e0.value_range.y) / 2.0, 1.0, 0.001)


func test_mobility_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var primary := &""
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], primary, primary, [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods:
			if not (m.stat_id in ids):
				ids.append(m.stat_id)
	for sid in ids:
		assert_true(sid in [&"movement_points", &"deallocation_points"], "unexpected: %s" % String(sid))
