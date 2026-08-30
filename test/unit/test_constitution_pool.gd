extends GutTest
## v4 StatPool conformance for constitution.tres (#321 wave 1).
const _PACK := preload("res://procgen/pools/constitution.tres")
const _GP := preload("res://procgen/graph_procgen.gd")

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_pack_loads_as_statpack() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	assert_not_null(p)
	assert_eq(p.archetype_stat, &"constitution")
	assert_true(p.pools.size() > 0)


func test_constitution_pool_values() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"constitution" and pp.operation == StatModifier.Operation.ADD_BASE:
			assert_eq(pp.unit_value, 2.0)
			assert_eq(pp.min_tier, 1)
			assert_eq(pp.max_tier, 4)
			assert_eq(pp.to_entries().size(), 4)
			var e0 = pp.to_entries()[0]
			assert_almost_eq((e0.value_range.x + e0.value_range.y) / 2.0, 2.0, 0.001)


func test_universal_pools_are_archetype_empty() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"node_health" or pp.stat_id == &"armor":
			assert_eq(pp.archetype_stat, &"", "pool %s should be universal" % String(pp.stat_id))


## The CON pack's INT pool — asserts the pool's SHAPE, not its magnitudes.
##
## This used to pin `unit_value == -5.0` and `max_tier == 1` outright, so the
## 2026-08-07 playtest retune (softer per-tier bite, -5% → -2%, spread across
## three tiers instead of stopping at one) failed it on three lines while
## nothing was actually wrong. A balance knob under a `.tres` is meant to move;
## a test that pins its value converts every retune into a red suite and teaches
## people to edit the number until it goes green.
##
## What must stay true regardless of tuning: it is a negative-unit_value pool
## and it ladders one entry per tier. #637 (superseded 2026-08-30, retiring
## the 2026-08-07 refund-economics decision) retired the OLD invariant this
## test used to pin — a debuff "refunds cost rather than charging it" — the
## draw now spends `+T` for a negative pool exactly like any other.
func test_intelligence_negative_pool() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"intelligence" and pp.operation == StatModifier.Operation.INCREASE:
			found = true
			assert_lt(pp.unit_value, 0.0, "the INT pool in the CON pack rolls a negative value")
			assert_gte(pp.max_tier, 1, "reachable on at least one tier")
			assert_eq(pp.to_entries().size(), pp.max_tier,
				"one entry per tier up to max_tier")
			for e in pp.to_entries():
				assert_gt(e.cost, 0, "cost is always positive — refund economics retired (#637)")
	assert_true(found, "the CON pack still carries an INT pool at all")


## #637 acceptance 1: min_damage_taken is unchanged in authoring (unit -1.0,
## min_tier 3, range_floor unauthored) and flattens to exactly T3 -1..-1
## (cost 4) and T4 -2..-3 (cost 8) — same math as pre-migration, just with a
## positive cost now. The two ends land ascending in `value_range` — for a
## negative pool the recurrence's near-zero end and the ladder's far end are
## role-ordered by StatPool._tier_magnitude_bounds so `x <= y` holds exactly
## like a positive pool (see docs/domain/procgen-v4.md).
func test_min_damage_taken_flattens_to_exact_migrated_table() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"min_damage_taken":
			found = true
			assert_almost_eq(pp.unit_value, -1.0, 0.0001)
			assert_eq(pp.min_tier, 3)
			assert_true(is_inf(pp.range_floor), "min_damage_taken should not author range_floor (no authoring change, #637)")
			var entries := pp.to_entries()
			assert_eq(entries.size(), 2, "min_tier 3, default max_tier 4 → T3..T4 only")
			assert_eq(entries[0].cost, 4, "T3 cost")
			assert_almost_eq(entries[0].value_range.x, -1.0, 0.001, "T3 low")
			assert_almost_eq(entries[0].value_range.y, -1.0, 0.001, "T3 high (zero-width, pool's first tier)")
			assert_eq(entries[1].cost, 8, "T4 cost")
			assert_almost_eq(entries[1].value_range.x, -3.0, 0.001, "T4 far end (H = unit*V(2) = -1*3)")
			assert_almost_eq(entries[1].value_range.y, -2.0, 0.001, "T4 near end (L = H(T3) + M = -1 + -1)")
	assert_true(found, "constitution pack still carries min_damage_taken")


## #637 acceptance 2: intelligence +% retunes to unit -3.0, range_floor -1.0
## and flattens to exactly T1 -1..-3, T2 -4..-9, T3 -10..-21 — all POSITIVE
## cost. Do not swap the numbers: unit -1.0/floor -3.0 inverts T1 and fails
## well-formedness (see docs/domain/procgen-v4.md).
func test_intelligence_pool_flattens_to_exact_migrated_table() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"intelligence" and pp.operation == StatModifier.Operation.INCREASE:
			found = true
			assert_almost_eq(pp.unit_value, -3.0, 0.0001)
			assert_almost_eq(pp.range_floor, -1.0, 0.0001)
			var entries := pp.to_entries()
			assert_eq(entries.size(), 3, "min_tier 1, max_tier 3")
			var expected_costs := [1, 2, 4]
			var expected_lo := [-3.0, -9.0, -21.0]
			var expected_hi := [-1.0, -4.0, -10.0]
			for i in entries.size():
				assert_eq(entries[i].cost, expected_costs[i], "T%d cost" % (i + 1))
				assert_gt(entries[i].cost, 0, "cost is always positive — refund economics retired (#637)")
				assert_almost_eq(entries[i].value_range.x, expected_lo[i], 0.001, "T%d low (far end)" % (i + 1))
				assert_almost_eq(entries[i].value_range.y, expected_hi[i], 0.001, "T%d high (near end)" % (i + 1))
	assert_true(found, "constitution pack still carries the intelligence +% pool")


## #637 acceptance 8 — owner-pinned arithmetic, NOT a balance decision this
## unit makes (see the issue's open acceptance 8 and this unit's report for
## the real-content-config caveat this narrow check does not cover). Per the
## BudgetPolicy class defaults (procgen/budget/budget_policy.gd:26-27,
## base_min=2/base_max=5) and min_damage_taken's cheapest tier (T3, cost 4),
## two draws would need budget >= 8, which exceeds base_max=5 — so at most
## ONE draw of min_damage_taken can ever land on a node under those defaults.
func test_min_damage_taken_at_most_one_draw_fits_default_budget() -> void:
	var policy := BudgetPolicy.new()
	assert_eq(policy.base_min, 2)
	assert_eq(policy.base_max, 5)
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var min_cost := 999
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"min_damage_taken":
			for e in pp.to_entries():
				min_cost = mini(min_cost, e.cost)
	assert_eq(min_cost, 4, "min_damage_taken's cheapest tier (T3) costs 4")
	assert_true(min_cost * 2 > policy.base_max,
		"two draws (cost %d each) must exceed the class-default max budget (%d) — at most one draw fits" % [min_cost, policy.base_max])




func test_constitution_draw_only_emits_pack_stat_ids() -> void:
	var pool_set := ModifierPoolSet.new()
	pool_set.packs = [_PACK.duplicate(true)]
	var primary := &"constitution"
	var ids: Array = []
	for seed_value in range(1, 25):
		var mods: Array = _GP._roll_modifiers_v4(pool_set, [], primary, primary, [] as Array[StringName], Vector2.ZERO, 0, 8, _rng(seed_value))
		for m in mods:
			if not (m.stat_id in ids):
				ids.append(m.stat_id)
	for sid in ids:
		assert_true(sid in [&"constitution", &"node_health", &"armor", &"intelligence", &"min_damage_taken"], "unexpected: %s" % String(sid))
