extends GutTest
## v4 StatPool conformance for wisdom.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/wisdom.tres")
const _GP := preload("res://procgen/graph_procgen.gd")
func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = s; return r
func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p); assert_eq(p.archetype_stat, &"wisdom")
	assert_true(p.pools.size() > 0)
func test_wisdom_pool_values() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"wisdom" and pp.operation == StatModifier.Operation.ADD_BASE:
			assert_eq(pp.unit_value, 2.0)
			assert_eq(pp.min_tier, 1); assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			# T1 magnitude = unit*V[0] = 2*1 = 2 (center of value_range)
			assert_almost_eq((pp.to_entries()[0].value_range.x + pp.to_entries()[0].value_range.y) / 2.0, 2.0, 0.001)
func test_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], &"wisdom", &"wisdom", [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods: if not (m.stat_id in ids): ids.append(m.stat_id)
	# every rolled stat_id must be one this pack owns
	for sid in ids: assert_true(sid in [&"wisdom", &"xp_per_turn"], "unexpected stat_id rolled: %s" % String(sid))
