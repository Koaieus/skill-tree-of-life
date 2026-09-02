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
	# Content invariant, NOT a value pin (#719). The magnitudes here are the
	# owner's to tune between balance passes; pinning them turned a deliberate
	# tuning pass red without catching anything (#717). Formula conformance for
	# whatever this pool authors is swept in test_pool_range_bounds.gd, the
	# ladder itself is pinned on hand-built pools in test_pool_seed_values.gd,
	# and unintended content drift is the procgen goldens' job.
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"constitution" and pp.operation == StatModifier.Operation.ADD_BASE:
			found = true
			assert_eq(pp.to_entries().size(), pp.max_tier - pp.min_tier + 1,
					"constitution.addb: one entry per offered tier")
	assert_true(found, "the pack must carry a constitution addb pool at all")


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
			# Content invariant, not a value pin (#719): min_damage_taken is a
			# DOWNSIDE pool, and that is what must survive any tune — a
			# positive unit here would turn a penalty into a buff. The exact
			# negative-pool table (role-ordered pair, positive cost) is pinned
			# on a hand-built pool in test_pool_seed_values.gd.
			assert_lt(pp.unit_value, 0.0, "min_damage_taken must stay a downside pool")
			var entries := pp.to_entries()
			assert_eq(entries.size(), pp.max_tier - pp.min_tier + 1, "one entry per offered tier")
			for e in entries:
				assert_gt(e.cost, 0, "cost is always positive — refund economics retired (#637)")
				assert_lt(e.value_range.y, 0.0, "every tier stays negative at BOTH ends")
	assert_true(found, "constitution pack still carries min_damage_taken")


## #637's sign guarantee for the CON pack's INT pool, as a content invariant
## rather than a pinned table (#719): an always-negative pool must STAY
## always-negative, so its `range_floor` has to share `unit_value`'s sign and
## not exceed its magnitude — otherwise the range crosses zero and a downside
## pool starts rolling buffs. The exact migrated table (unit -3, floor -1 →
## T1 -3..-1, T2 -9..-4, T3 -21..-10 at costs 1 2 4) is pinned on a hand-built
## pool in test_pool_seed_values.gd, where re-tuning this `.tres` cannot reach
## it. See docs/domain/procgen-v4.md.
func test_intelligence_pool_stays_sign_consistent() -> void:
	var p: StatPack = _PACK.duplicate(true) as StatPack
	var found := false
	for sp in p.pools:
		var pp: StatPool = sp as StatPool
		if pp.stat_id == &"intelligence" and pp.operation == StatModifier.Operation.INCREASE:
			found = true
			assert_lt(pp.unit_value, 0.0, "the INT pool in the CON pack is a downside pool")
			if not is_inf(pp.range_floor):
				assert_eq(signf(pp.range_floor), signf(pp.unit_value),
						"range_floor must share unit_value's sign or the range crosses zero")
				assert_lte(absf(pp.range_floor), absf(pp.unit_value),
						"range_floor must not overshoot the T1 ceiling's magnitude")
			for e in pp.to_entries():
				assert_gt(e.cost, 0, "cost is always positive — refund economics retired (#637)")
				assert_lt(e.value_range.y, 0.0, "every tier stays negative at BOTH ends")
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
	# Every rolled stat_id must be one this pack owns — read OFF the pack, not
	# a hand-listed set (#719). A literal list goes stale the moment a pool is
	# added to the pack: the content change is deliberate and the test fails
	# anyway, blaming the roll for a fact about the fixture. Derived, it
	# asserts what its name says — no cross-pack leakage.
	var owned: Array[StringName] = []
	for sp in (pool_set.packs[0] as StatPack).pools:
		var sid_owned := (sp as StatPool).stat_id
		if not (sid_owned in owned): owned.append(sid_owned)
	for sid in ids: assert_true(sid in owned, "unexpected stat_id rolled: %s (pack owns %s)" % [String(sid), owned])
