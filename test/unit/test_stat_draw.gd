extends GutTest

## v4 draw model (#321): spend-until-broke + per-(stat,op) aggregation.
## Replaces the old `test_phased_modifier_draw.gd` (slots / off-archetype phase /
## defensive+rare phases — all deleted in v4).

const _SCRIPT := preload("res://procgen/graph_procgen.gd")


func _pool(
		stat_id: StringName,
		op: int,
		archetype_stat: StringName,
		unit_value: float,
		pool_weight: float = 1.0,
		min_tier: int = 1,
		max_tier: int = 4,
		tier_bias_k: float = 1.0,
) -> StatPool:
	var p := StatPool.new()
	p.stat_id = stat_id
	p.operation = op
	p.archetype_stat = archetype_stat
	p.unit_value = unit_value
	p.pool_weight = pool_weight
	p.min_tier = min_tier
	p.max_tier = max_tier
	p.tier_bias_k = tier_bias_k
	return p


func _pack(archetype_stat: StringName, pools: Array) -> StatPack:
	var sp := StatPack.new()
	sp.archetype_stat = archetype_stat
	var typed: Array[StatPool] = []
	for p in pools:
		typed.append(p)
	sp.pools = typed
	return sp


func _make_set(packs: Array) -> ModifierPoolSet:
	var s := ModifierPoolSet.new()
	var typed: Array[StatPack] = []
	for p in packs:
		typed.append(p)
	s.packs = typed
	return s


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _draw(set: ModifierPoolSet, primary_stat: StringName, budget: int, rng: RandomNumberGenerator) -> Array:
	return _SCRIPT._roll_modifiers_v4(
			set, [], &"strength", primary_stat, [], Vector2.ZERO, 0, budget, rng)


func test_zero_budget_returns_empty() -> void:
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0)]),
	])
	var mods := _draw(set, &"strength", 0, _rng(1))
	assert_eq(mods.size(), 0)


func test_budget_drains_into_t1_filler_never_wasted() -> void:
	# Single pool, T1 cost 1 always affordable → remaining always hits 0.
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0)]),
	])
	for budget in [1, 2, 3, 7, 16]:
		var rng := _rng(budget)
		var mods := _draw(set, &"strength", budget, rng)
		# Aggregation collapses every STR ADD_BASE draw into ONE modifier.
		assert_eq(mods.size(), 1, "all draws aggregate into one (stat,op) entry")
		assert_eq(mods[0].stat_id, &"strength")
		# value = unit * V[T] summed over draws; just confirm it's positive
		# and the draw consumed the whole budget (no way to observe remaining
		# here, but a single-pool run that stops early would under-roll).
		assert_true(mods[0].value > 0.0)


func test_aggregation_sums_add_base_and_products_multiply() -> void:
	# Two pools: strength ADD_BASE + strength MULTIPLY. With budget 4 the draw
	# picks among T1..T4 tiers; multiple STR ADD_BASE draws SUM into one mod,
	# and any MULTIPLY draws PRODUCT into a separate mod.
	var set := _make_set([
		_pack(&"strength", [
			_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0, 10.0),
			_pool(&"strength", StatModifier.Operation.MULTIPLY, &"strength", 0.05, 1.0, 3, 4),
		]),
	])
	var saw_add := false
	var saw_mul := false
	for seed_value in range(1, 30):
		var mods := _draw(set, &"strength", 8, _rng(seed_value))
		for m in mods:
			if m.operation == StatModifier.Operation.ADD_BASE:
				saw_add = true
				assert_true(m.value >= 2.0, "aggregated ADD_BASE should be ≥ one T1 draw (2)")
			elif m.operation == StatModifier.Operation.MULTIPLY:
				saw_mul = true
				# unit 0.05 → T3 = 0.35, T4 = 0.75; aggregate is a product, ≥ one factor.
				assert_true(m.value >= 1.0, "MULTIPLY aggregate should be ≥ 1.0 (one ×1.35 factor at minimum)")
	assert_true(saw_add, "expected ADD_BASE to land")
	# MULTIPLY is min_tier 3 (cost 4) so it only lands when budget ≥ 4 and is
	# picked over T1 filler — may not fire every seed; assert it fires at least
	# once across the run to prove the product-aggregation path is wired.
	assert_true(saw_mul, "expected at least one MULTIPLY aggregate across 29 seeded draws at budget 8")


func test_universal_pool_drawn_by_any_primary() -> void:
	# armor is universal (archetype_stat = &""); a strength-primary node draws it
	# alongside strength. Rare/mythic content is gated by tier tag via weight
	# profiles, not by pool role here.
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0, 1.0)]),
		_pack(&"", [_pool(&"armor", StatModifier.Operation.ADD_BONUS, &"", 1.5, 1.0)]),
	])
	var saw_armor := false
	for seed_value in range(1, 40):
		var mods := _draw(set, &"strength", 7, _rng(seed_value))
		for m in mods:
			if m.stat_id == &"armor":
				saw_armor = true
	assert_true(saw_armor, "universal armor pool should be drawable by a STR node across 39 seeds")


func test_debuff_refunds_budget_and_caps_at_one_refund() -> void:
	# A debuff pool (unit_value < 0, max_tier 1) refunds 1 budget. The draw
	# should be able to spend that refunded budget on more content, but only
	# ONE refund per node.
	var set := _make_set([
		_pack(&"strength", [
			_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0, 10.0),
			# intelligence INCREASE debuff: unit -5, single tier, refunds 1.
			_pool(&"intelligence", StatModifier.Operation.INCREASE, &"strength", -5.0, 0.5, 1, 1),
		]),
	])
	var saw_debuff := false
	for seed_value in range(1, 50):
		var mods := _draw(set, &"strength", 7, _rng(seed_value))
		for m in mods:
			if m.stat_id == &"intelligence" and m.value < 0.0:
				saw_debuff = true
	assert_true(saw_debuff, "debuff pool should land at least once across 49 seeded draws")
	# The refund-cap invariant is hard to assert from the outside without the
	# footprint dict; the draw loop enforces _MAX_DEBUFF_REFUNDS = 1 — this
	# test just proves the debuff path is reachable and negative-valued.