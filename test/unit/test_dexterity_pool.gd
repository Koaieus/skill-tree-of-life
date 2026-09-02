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
			assert_eq(pp.unit_value, 3.0)
			assert_eq(pp.range_floor, 1.0)
			assert_eq(pp.min_tier, 1); assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			# b3975d8 re-tuned this pool (unit 2 → 3) and authored an explicit
			# `range_floor` of 1.0, so T1 is no longer the zero-width fixed
			# point the default M=unit_value used to make it (#628): its high
			# is still unit*V[0] = 3*1 = 3, but its low is now M = 1.
			var e0 := pp.to_entries()[0]
			assert_almost_eq(e0.value_range.x, 1.0, 0.001, "T1 low = M (authored range_floor)")
			assert_almost_eq(e0.value_range.y, 3.0, 0.001, "T1 high = unit x V[0]")
func test_crit_chance_carries_t3_t4_overrides() -> void:
	# #628 widened value_range from a fixed point to a real [L, H] per tier;
	# checking the CENTER only meant something while every range was
	# zero-width (pre-#628), where center == the single value. Post-#628, T2
	# alone has real width (center 12.5, not 15) so a center check silently
	# stopped testing anything meaningful. Assert L and H separately instead,
	# plus the L(t+1) = H(t) + M chain the formula promises (docs/domain/
	# procgen-v4.md) — that's what actually pins #628's behaviour here.
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"crit_chance" and pp.operation == StatModifier.Operation.INCREASE:
			assert_eq(pp.unit_value, 5.0)
			assert_eq(pp.min_tier, 1); assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			assert_eq(pp.value_overrides, {3: 50.0, 4: 100.0})
			var entries := pp.to_entries()
			# Highs are the pre-#628 seed values, exactly unchanged.
			var expected_highs := [5.0, 15.0, 50.0, 100.0]
			for i in entries.size():
				assert_almost_eq(entries[i].value_range.y, expected_highs[i], 0.001,
						"crit_chance T%d high (unchanged by #628)" % (i + 1))
			# T1/T2 carry no override — normal chain off default M (=unit_value=5):
			# L1 = M = 5 (zero-width, min_tier); L2 = H(1) + M = 5 + 5 = 10.
			assert_almost_eq(entries[0].value_range.x, 5.0, 0.001, "T1 low = M")
			assert_almost_eq(entries[1].value_range.x, 10.0, 0.001, "T2 low = H(1) + M")
			# T3/T4 ARE overridden: #629's decision is that an override "pins a
			# tier to an exact value, bypassing the roll entirely" — so each is
			# its own fixed point (low == high == override), not chain-computed.
			assert_almost_eq(entries[2].value_range.x, 50.0, 0.001, "T3 low == override (bypasses the roll)")
			assert_almost_eq(entries[3].value_range.x, 100.0, 0.001, "T4 low == override (bypasses the roll)")
func test_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], &"dexterity", &"dexterity", [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods: if not (m.stat_id in ids): ids.append(m.stat_id)
	# every rolled stat_id must be one this pack owns
	for sid in ids: assert_true(sid in [&"dexterity", &"crit_chance", &"crit_multiplier"], "unexpected stat_id rolled: %s" % String(sid))
