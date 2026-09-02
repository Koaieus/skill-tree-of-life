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
	# Seed row shape: strength .addb, T1..T4 highs are `unit x V[t]` at costs
	# 1 2 4 8 (V = [1,3,7,15]), lows follow the #628 recurrence L(1) = M,
	# L(t+1) = H(t) + M. The seed table's original numbers (unit 2, default
	# M = unit_value → +2 +6 +14 +30 with a zero-width T1) were re-tuned by
	# `b3975d8 chore: tweak procgen pools`, which raised `unit_value` to 3
	# and authored an explicit `range_floor` of 1.0 — deliberate tuning, so
	# this file re-points onto it rather than pinning the retired values
	# (#717). What it still pins is the LADDER: that both bounds are exactly
	# what the formula says for the values the pool authors today. See
	# test_pool_range_bounds.gd for the formula itself.
	var p := _find_pool(&"strength", &"strength", StatModifier.Operation.ADD_BASE)
	var entries := p.to_entries()
	assert_eq(entries.size(), 4, "strength.addb offers T1..T4")
	assert_eq(p.unit_value, 3.0, "strength.addb unit (b3975d8)")
	assert_eq(p.range_floor, 1.0, "strength.addb authors an explicit M (b3975d8)")
	var expected_highs := [3.0, 9.0, 21.0, 45.0]   # unit 3 x V = [1,3,7,15]
	var expected_lows := [1.0, 4.0, 10.0, 22.0]    # M=1 authored: L1=1, L(t+1)=H(t)+1
	var expected_costs := [1, 2, 4, 8]
	for i in entries.size():
		var e: ModifierPoolEntry = entries[i]
		assert_eq(e.cost, expected_costs[i], "strength.addb T%d cost" % [i + 1])
		assert_almost_eq(e.value_range.y, expected_highs[i], 0.001, "strength.addb T%d high (unchanged by #628)" % [i + 1])
		assert_almost_eq(e.value_range.x, expected_lows[i], 0.001, "strength.addb T%d low (authored M=1)" % [i + 1])


func test_crit_chance_inc_flattens_with_overrides() -> void:
	# Seed row: crit_chance .inc, unit 5, overrides {3: 50, 4: 100} →
	# +5 +15 +50 +100 at costs 1 2 4 8. #628: these are highs — unchanged.
	# #629's decision text: an override "pins a tier to an exact value,
	# bypassing the roll entirely" — so T3/T4 are zero-width fixed points at
	# their override, not chain-computed. T1/T2 have no override and follow
	# the normal chain (default M=5=unit_value): L1=M=5, L2=H(1)+M=10.
	# See test_pool_range_bounds.gd for the guard this bypass still needs
	# (an override can invert a LATER, non-overridden tier's chain).
	var p := _find_pool(&"dexterity", &"crit_chance", StatModifier.Operation.INCREASE)
	var entries := p.to_entries()
	assert_eq(entries.size(), 4, "crit_chance.inc offers T1..T4")
	var expected_highs := [5.0, 15.0, 50.0, 100.0]
	var expected_lows := [5.0, 10.0, 50.0, 100.0]
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
	# ×1.05 ×1.15 at costs 4 8 (highs — the tuning in `b3975d8` left these
	# alone). Value rungs are indexed relative to min_tier (the pool's first
	# tier is V1, ×1, whatever it costs); cost stays absolute. The +1 (the
	# "more" excess) is folded into BOTH ends here. b3975d8 authored an
	# explicit `range_floor` of 0.02 where the default (M=unit_value=0.05)
	# used to make T3 a zero-width ×1.05 point, so T3 now spans
	# ×1.02..×1.05 and T4 ×1.07..×1.15 (L4 = H3 + M = 0.05 + 0.02).
	var p := _find_pool(&"strength", &"strength", StatModifier.Operation.MULTIPLY)
	var entries := p.to_entries()
	assert_eq(entries.size(), 2, "strength.mul offers T3..T4 only")
	assert_eq(p.range_floor, 0.02, "strength.mul authors an explicit M (b3975d8)")
	assert_eq(entries[0].cost, 4)
	assert_eq(entries[1].cost, 8)
	assert_almost_eq(entries[0].value_range.y, 1.05, 0.001, "T3 high → ×1.05")
	assert_almost_eq(entries[0].value_range.x, 1.02, 0.001, "T3 low → ×1.02 (M=0.02, pool's first tier)")
	assert_almost_eq(entries[1].value_range.y, 1.15, 0.001, "T4 high → ×1.15")
	assert_almost_eq(entries[1].value_range.x, 1.07, 0.001, "T4 low → ×1.07 (H3 + M)")


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
	# #637 acceptance 3 — no unrollable content, and refund economics are
	# RETIRED (superseded 2026-08-30, see docs/domain/procgen-v4.md): every
	# flattened entry across ALL packs costs a legal, POSITIVE ladder rung
	# (1/2/4/8), whatever the sign of its rolled value. A negative-unit_value
	# pool used to cost the NEGATION of the rung (refunding budget instead of
	# spending it, settled 2026-08-07) — that mechanic is gone. Cost is `+T`
	# universally now; budget spend is monotonic (no draw ever increases
	# `remaining`).
	#
	# A negative-unit_value pool still rolls a real range (#628/#637 — it is
	# no longer exempt): the CON pack's INT pool at unit -3%/floor -1% runs
	# -1%/-3% / -4%/-9% / -10%/-21% across T1..T3, costing 1/2/4 — exactly
	# like a positive pool at the same tiers.
	var legal_rungs: Array[int] = []
	for t in range(TierLadder.MIN_TIER, TierLadder.MAX_TIER + 1):
		legal_rungs.append(TierLadder.cost(t))

	var checked := 0
	var negative_pool_entries_seen := 0
	for pack in _SET.packs:
		for sp in pack.pools:
			var p: StatPool = sp as StatPool
			var is_negative_pool := p.unit_value < 0.0
			for e in p.to_entries():
				checked += 1
				assert_true(legal_rungs.has(e.cost),
					"%s cost %d is not a ladder rung %s"
					% [String(p.stat_id), e.cost, str(legal_rungs)])
				assert_gt(e.cost, 0,
					"%s cost must be positive — refund economics retired (#637)" % String(p.stat_id))
				if is_negative_pool:
					negative_pool_entries_seen += 1
	assert_gt(checked, 20, "sweep should cover the whole specimen set")
	assert_gt(negative_pool_entries_seen, 0, "the specimen set still contains a negative unit_value pool at all")
