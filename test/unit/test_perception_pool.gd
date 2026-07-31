extends GutTest
## v4 StatPool conformance for perception.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/perception.tres")
const _GP := preload("res://procgen/graph_procgen.gd")

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p)
	assert_eq(p.archetype_stat, &"perception")
	assert_true(p.pools.size() > 0)


func test_perception_pool_values() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"perception" and pp.operation == StatModifier.Operation.ADD_BASE:
			assert_eq(pp.unit_value, 2.0)
			assert_eq(pp.min_tier, 1)
			assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			var e0 = pp.to_entries()[0]
			assert_almost_eq((e0.value_range.x + e0.value_range.y) / 2.0, 2.0, 0.001)


func test_perception_draw_only_emits_pack_stat_ids() -> void:
	var set := ModifierPoolSet.new()
	set.packs = [_PACK.duplicate(true)]
	var primary := &"perception"
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(set, [], primary, primary, [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods:
			if not (m.stat_id in ids):
				ids.append(m.stat_id)
	for sid in ids:
		assert_true(sid in [&"perception", &"vision_range", &"sensor_range"], "unexpected: %s" % String(sid))
