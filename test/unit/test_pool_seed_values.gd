extends GutTest

## Seed-table conformance for the v4 StatPool content (#326 acceptance).
## Pins the flattened magnitudes + costs from #321's seed table for a
## representative sample of pools, and sweeps EVERY flattened entry in the
## specimen set for legal costs (acceptance 4 — the D11/D4 cost guard).
##
## The seed table (from #321, D6): cost ladder [1,2,4,8], V = [1,3,7,15];
## `value = unit_value × V[t]` unless a per-tier `value_overrides` entry
## replaces it. This file exists because the flatten result is the contract
## the rest of the draw pipeline consumes — if a pool drifts from the table,
## budget math and weight profiles drift with it silently.

const _SET := preload("res://procgen/pools/specimen_pool_set.tres")


## Finds the (first) pool in the set matching archetype affinity + target stat
## + operation. `archetype_stat` must be the pack's archetype (or `&""` for
## the universal mobility pack).
func _find_pool(archetype_stat: StringName, stat_id: StringName, op: int) -> StatPool:
	for pack in _SET.packs:
		if pack.archetype_stat != archetype_stat:
			continue
		for sp in pack.pools:
			var p: StatPool = sp as StatPool
			if p.stat_id == stat_id and int(p.operation) == op:
				return p
	fail_test("pool not found: arch=%s stat=%s op=%d" % [archetype_stat, stat_id, op])
	return null


func test_strength_addb_flattens_to_seed_table() -> void:
	# Seed row: strength .addb, unit 2, T1..T4 → +2 +6 +14 +30 at costs 1 2 4 8.
	# #628: these are now HIGH bounds, not fixed points — "resulting T1..T4"
	# in the seed table was always H, and H is unchanged (acceptance 4: no
	# existing pool rebalances). None of these pools author `range_floor`, so
	# it defaults to `unit_value` (2.0) and the low bounds follow the
	# recurrence L(1) = M, L(t+1) = H(t) + M — T1 stays a zero-width point,
	# T2..T4 gain real width. See test_pool_range_bounds.gd for the formula
	# itself; this file only pins that H didn't move.
	var p := _find_pool(&"strength", &"strength", StatModifier.Operation.ADD_BASE)
	var entries := p.to_entries()
	assert_eq(entries.size(), 4, "strength.addb offers T1..T4")
	var expected_highs := [2.0, 6.0, 14.0, 30.0]
	var expected_lows := [2.0, 4.0, 8.0, 16.0]  # M=2 default: L1=2, L(t+1)=H(t)+2
	var expected_costs := [1, 2, 4, 8]
	for i in entries.size():
		var e: ModifierPoolEntry = entries[i]
		assert_eq(e.cost, expected_costs[i], "strength.addb T%d cost" % [i + 1])
		assert_almost_eq(e.value_range.y, expected_highs[i], 0.001, "strength.addb T%d high (unchanged by #628)" % [i + 1])
		assert_almost_eq(e.value_range.x, expected_lows[i], 0.001, "strength.addb T%d low (default M=unit_value)" % [i + 1])


func test_crit_chance_inc_flattens_with_overrides() -> void:
	# Seed row: crit_chance .inc, unit 5, overrides {3: 50, 4: 100} →
	# +5 +15 +50 +100 at costs 1 2 4 8. #628: these are highs — unchanged, an
	# override replaces H(t) but never L(t). Default M=5 (unit_value); L(3)
	# and L(4) chain off the OVERRIDDEN H(2)/H(3), per the value_overrides
	# guard (acceptance 7) — covered in depth in test_pool_range_bounds.gd.
	var p := _find_pool(&"dexterity", &"crit_chance", StatModifier.Operation.INCREASE)
	var entries := p.to_entries()
	assert_eq(entries.size(), 4, "crit_chance.inc offers T1..T4")
	var expected_highs := [5.0, 15.0, 50.0, 100.0]
	var expected_lows := [5.0, 10.0, 20.0, 55.0]
	var expected_costs := [1, 2, 4, 8]
	for i in entries.size():
		var e: ModifierPoolEntry = entries[i]
		assert_eq(e.cost, expected_costs[i], "crit_chance.inc T%d cost" % [i + 1])
		assert_almost_eq(e.value_range.y, expected_highs[i], 0.001, "crit_chance.inc T%d high (unchanged by #628)" % [i + 1])
		assert_almost_eq(e.value_range.x, expected_lows[i], 0.001, "crit_chance.inc T%d low" % [i + 1])


func test_movement_points_addb_caps_at_t2() -> void:
	# Seed row: movement_points .addb, unit 1, max_tier 2 → +1 +3 at costs 1 2.
	# The cap (not a descending weight curve) is the honest brake (#321 D6).
	# #628: highs unchanged; default M=1 gives L1=1 (zero-width), L2=H1+M=2.
	var p := _find_pool(&"", &"movement_points", StatModifier.Operation.ADD_BASE)
	var entries := p.to_entries()
	assert_eq(entries.size(), 2, "movement_points.addb caps at T2")
	var expected_highs := [1.0, 3.0]
	var expected_lows := [1.0, 2.0]
	var expected_costs := [1, 2]
	for i in entries.size():
		var e: ModifierPoolEntry = entries[i]
		assert_eq(e.cost, expected_costs[i], "movement_points T%d cost" % [i + 1])
		assert_almost_eq(e.value_range.y, expected_highs[i], 0.001, "movement_points T%d high (unchanged by #628)" % [i + 1])
		assert_almost_eq(e.value_range.x, expected_lows[i], 0.001, "movement_points T%d low" % [i + 1])


func test_attribute_mul_starts_at_t3() -> void:
	# Seed row: attribute .mul, unit 0.05, min_tier 3, pool_weight 1 →
	# ×1.05 ×1.15 at costs 4 8 (highs, unchanged by #628). Value rungs are
	# indexed relative to min_tier (the pool's first tier is V1, ×1, whatever
	# it costs); cost stays absolute. The +1 (the "more" excess) is folded
	# into BOTH ends here, so range_floor's default (M=unit_value=0.05) makes
	# T3 (the pool's own first tier) a zero-width ×1.05 point and T4 gain a
	# ×1.10..×1.15 spread.
	var p := _find_pool(&"strength", &"strength", StatModifier.Operation.MULTIPLY)
	var entries := p.to_entries()
	assert_eq(entries.size(), 2, "strength.mul offers T3..T4 only")
	assert_eq(entries[0].cost, 4)
	assert_eq(entries[1].cost, 8)
	assert_almost_eq(entries[0].value_range.y, 1.05, 0.001, "T3 high → ×1.05")
	assert_almost_eq(entries[0].value_range.x, 1.05, 0.001, "T3 low → ×1.05 (zero-width, pool's first tier)")
	assert_almost_eq(entries[1].value_range.y, 1.15, 0.001, "T4 high → ×1.15")
	assert_almost_eq(entries[1].value_range.x, 1.10, 0.001, "T4 low → ×1.10")


func test_min_tier_indexes_value_relative_to_first_tier() -> void:
	# The ladder rule: cost stays absolute, value rungs are indexed relative
	# to the pool's first tier. min_tier=3 → t3 costs 4 but is V1 (×1), t4
	# costs 8 and is V2 (×3). ADD_BASE so the magnitudes read raw. These are
	# HIGHS (unaffected by #628); default range_floor=unit_value makes t3
	# (the pool's first tier) a zero-width point and t4 low = H(t3) + M.
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = StatModifier.Operation.ADD_BASE
	p.unit_value = 1.0
	p.min_tier = 3
	p.max_tier = 4
	var entries := p.to_entries()
	assert_eq(entries.size(), 2, "min_tier=3, max_tier=4 → T3..T4 only")
	assert_eq(entries[0].cost, 4, "t3 cost stays absolute (2^(3-1))")
	assert_almost_eq(entries[0].value_range.y, 1.0, 0.001, "t3 is the pool's first tier → V1 = ×1")
	assert_almost_eq(entries[0].value_range.x, 1.0, 0.001, "t3 is zero-width (default M=unit_value)")
	assert_eq(entries[1].cost, 8, "t4 cost stays absolute (2^(4-1))")
	assert_almost_eq(entries[1].value_range.y, 3.0, 0.001, "t4 is the second rung → V2 = ×3")
	assert_almost_eq(entries[1].value_range.x, 2.0, 0.001, "t4 low = H(t3) + M = 1.0 + 1.0")


func test_every_flattened_entry_cost_is_legal() -> void:
	# #326 acceptance 4 — no unrollable content. Every flattened entry across ALL
	# packs costs a legal ladder rung: 1/2/4/8 for a buff, and the NEGATION of
	# that rung for a debuff (it refunds budget instead of spending it).
	#
	# This used to demand debuffs cost exactly -1, i.e. debuffs were single-tier
	# by decree. `StatPool.to_entries` never implemented that restriction — it
	# has always emitted `-TierLadder.cost(t)` across the pool's whole
	# min_tier..max_tier span — so the assert was pinning a rule only the test
	# believed in, and any debuff pool authored past tier 1 failed it.
	#
	# Laddered debuffs are the intended reading (settled 2026-08-07): the CON
	# pack's INT debuff at unit -2% runs -2% / -6% / -14% across T1..T3 (the
	# value ladder is 1/3/7), refunding -1 / -2 / -4. A deeper debuff hurts more
	# AND refunds more, in lockstep — so a bigger refund is never free budget.
	var legal_rungs: Array[int] = []
	for t in range(TierLadder.MIN_TIER, TierLadder.MAX_TIER + 1):
		legal_rungs.append(TierLadder.cost(t))

	var checked := 0
	var debuffs_seen := 0
	for pack in _SET.packs:
		for sp in pack.pools:
			var p: StatPool = sp as StatPool
			var is_debuff := p.unit_value < 0.0
			for e in p.to_entries():
				checked += 1
				assert_true(legal_rungs.has(absi(e.cost)),
						"%s cost %d is not a ladder rung %s"
						% [String(p.stat_id), e.cost, str(legal_rungs)])
				if is_debuff:
					debuffs_seen += 1
					assert_lt(e.cost, 0,
							"debuff %s must refund, not charge" % String(p.stat_id))
				else:
					assert_gt(e.cost, 0,
							"buff %s must charge, not refund" % String(p.stat_id))
	assert_gt(checked, 20, "sweep should cover the whole specimen set")
	assert_gt(debuffs_seen, 0, "the specimen set still contains a debuff pool at all")
