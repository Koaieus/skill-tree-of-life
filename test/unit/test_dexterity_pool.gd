extends GutTest
## v4 StatPool conformance for dexterity.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/dexterity.tres")
const _GP := preload("res://procgen/graph_procgen.gd")
func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r
func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p); assert_eq(p.archetype_stat, &"dexterity")
	assert_true(p.pools.size() > 0)
func test_dexterity_pool_values() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"dexterity" and pp.operation == StatModifier.Operation.ADD_BASE:
			assert_eq(pp.unit_value, 2.0)
			assert_eq(pp.min_tier, 1); assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			# T1 magnitude = unit*V[0] = 2*1 = 2 (center of value_range)
			assert_almost_eq((pp.to_entries()[0].value_range.x + pp.to_entries()[0].value_range.y) / 2.0, 2.0, 0.001)
func test_crit_chance_carries_t3_t4_overrides() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"crit_chance" and pp.operation == StatModifier.Operation.INCREASE:
			assert_eq(pp.unit_value, 5.0)
			assert_eq(pp.min_tier, 1); assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			assert_eq(pp.value_overrides, {3: 50.0, 4: 100.0})
			# T3 center = override 50; T4 center = override 100 (#321 D11).
			var entries := pp.to_entries()
			for i in entries.size():
				var center := (entries[i].value_range.x + entries[i].value_range.y) / 2.0
				assert_almost_eq(center, [5.0, 15.0, 50.0, 100.0][i], 0.001,
						"crit_chance T%d center" % (i + 1))
func test_draw_only_emits_pack_stat_ids() -> void:
	var set := ModifierPoolSet.new()
	set.packs = [_PACK.duplicate(true)]
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(set, [], &"dexterity", &"dexterity", [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods: if not (m.stat_id in ids): ids.append(m.stat_id)
	# every rolled stat_id must be one this pack owns
	for sid in ids: assert_true(sid in [&"dexterity", &"crit_chance", &"crit_multiplier"], "unexpected stat_id rolled: %s" % String(sid))
