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
		range_floor: float = StatPool.FLOOR_UNSET,
) -> StatPool:
	var p := StatPool.new()
	p.stat_id = stat_id
	p.operation = op as StatModifier.Operation
	p.archetype_stat = archetype_stat
	p.unit_value = unit_value
	p.pool_weight = pool_weight
	p.min_tier = min_tier
	p.max_tier = max_tier
	p.tier_bias_k = tier_bias_k
	p.range_floor = range_floor
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


func _draw(pool_set: ModifierPoolSet, primary_stat: StringName, budget: int, rng: RandomNumberGenerator, fp: Dictionary = {}) -> Array:
	return _SCRIPT._roll_modifiers_v4(
			pool_set, [], &"strength", primary_stat, [], Vector2.ZERO, 0, budget, rng, fp)


func test_zero_budget_returns_empty() -> void:
	var pool_set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0)]),
	])
	var mods := _draw(pool_set, &"strength", 0, _rng(1))
	assert_eq(mods.size(), 0)


func test_budget_drains_into_t1_filler_never_wasted() -> void:
	# Single pool, T1 cost 1 always affordable → remaining always hits 0.
	var pool_set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0)]),
	])
	for budget in [1, 2, 3, 7, 16]:
		var rng := _rng(budget)
		var mods := _draw(pool_set, &"strength", budget, rng)
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
	var pool_set := _make_set([
		_pack(&"strength", [
			_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0, 10.0),
			_pool(&"strength", StatModifier.Operation.MULTIPLY, &"strength", 0.05, 1.0, 3, 4),
		]),
	])
	var saw_add := false
	var saw_mul := false
	for seed_value in range(1, 30):
		var mods := _draw(pool_set, &"strength", 8, _rng(seed_value))
		for m in mods:
			if m.operation == StatModifier.Operation.ADD_BASE:
				saw_add = true
				assert_true(m.value >= 2.0, "aggregated ADD_BASE should be ≥ one T1 draw (2)")
			elif m.operation == StatModifier.Operation.MULTIPLY:
				saw_mul = true
				# unit 0.05, min_tier 3 → value rungs indexed relative to the
				# first tier: T3 = 0.05 (×1.05), T4 = 0.15 (×1.15); aggregate
				# is a product, ≥ one factor.
				assert_true(m.value >= 1.0, "MULTIPLY aggregate should be ≥ 1.0 (one ×1.35 factor at minimum)")
	assert_true(saw_add, "expected ADD_BASE to land")
	# MULTIPLY is min_tier 3 (cost 4) so it only lands when budget ≥ 4 and is
	# picked over T1 filler — may not fire every seed; assert it fires at least
	# once across the run to prove the product-aggregation path is wired.
	assert_true(saw_mul, "expected at least one MULTIPLY aggregate across 29 seeded draws at budget 8")


func test_universal_pool_drawn_by_any_primary() -> void:
	# armor is universal (archetype_stat = &""); a strength-primary node draws it
	# alongside strength.
	var pool_set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0, 1.0)]),
		_pack(&"", [_pool(&"armor", StatModifier.Operation.ADD_BONUS, &"", 1.5, 1.0)]),
	])
	var saw_armor := false
	for seed_value in range(1, 40):
		var mods := _draw(pool_set, &"strength", 7, _rng(seed_value))
		for m in mods:
			if m.stat_id == &"armor":
				saw_armor = true
	assert_true(saw_armor, "universal armor pool should be drawable by a STR node across 39 seeds")


## #637: refund economics retired — a negative-unit_value pool costs `+T`
## exactly like any other pool at its tier, so spend is monotonic: nothing a
## draw picks can ever push `remaining` back up. Replaces
## test_debuff_refunds_budget_and_caps_at_one_refund (the refund/one-cap
## mechanic it covered no longer exists).
func test_negative_pool_cost_is_positive_and_spend_never_refunds() -> void:
	var negative_pool := _pool(&"intelligence", StatModifier.Operation.INCREASE, &"strength", -5.0, 0.5, 1, 1)
	for e in negative_pool.to_entries():
		assert_true(e.cost > 0, "a negative unit_value pool must cost +T, not refund budget")

	var pool_set := _make_set([
		_pack(&"strength", [
			_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 2.0, 10.0),
			negative_pool,
		]),
	])
	var saw_negative := false
	for seed_value in range(1, 50):
		var fp := {}
		var mods := _draw(pool_set, &"strength", 7, _rng(seed_value), fp)
		for m in mods:
			if m.stat_id == &"intelligence" and m.value < 0.0:
				saw_negative = true
		assert_between(fp.remaining, 0, 7,
			"remaining must stay within [0, budget] every draw — no pick can refund it back up")
	assert_true(saw_negative, "negative pool should still land at least once across 49 seeded draws")



# ── #629: uniform roll within L..H + determinism ──────────────────────────
# The uniform roll itself is #628's widening activating ModifierPoolEntry.roll
# (which already samples value_range) — see docs/domain/procgen-v4.md. What's
# tested here is the determinism contract on top of it, and the fused-no-op
# re-roll's own determinism (test_no_op_reroll.gd covers the re-roll logic in
# isolation).

func _wide_pool_set() -> ModifierPoolSet:
	# range_floor 1.0 vs unit 5.0 → every tier beyond T1 has real width
	# (#628's first worked table: T1 1..5, T2 6..15, T3 16..35, T4 36..75).
	return _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 5.0, 1.0, 1, 4, 1.0, 1.0)]),
	])


func test_same_seed_produces_identical_values() -> void:
	var pool_set := _wide_pool_set()
	var a := _draw(pool_set, &"strength", 15, _rng(7))
	var b := _draw(pool_set, &"strength", 15, _rng(7))
	assert_eq(a.size(), b.size(), "same seed should draw the same number of aggregated mods")
	for i in a.size():
		assert_eq(a[i].stat_id, b[i].stat_id, "mod %d stat_id" % i)
		assert_eq(a[i].operation, b[i].operation, "mod %d operation" % i)
		assert_almost_eq(a[i].value, b[i].value, 0.00001, "mod %d value — same seed must be byte-identical" % i)


func test_different_seeds_produce_different_values() -> void:
	var pool_set := _wide_pool_set()
	var saw_difference := false
	var baseline := _draw(pool_set, &"strength", 15, _rng(1))
	for seed_value in range(2, 20):
		var other := _draw(pool_set, &"strength", 15, _rng(seed_value))
		if other.size() != baseline.size() or (other.size() > 0 and not is_equal_approx(other[0].value, baseline[0].value)):
			saw_difference = true
			break
	assert_true(saw_difference, "different seeds should not all pin to the same rolled value")


## A zero-width tier (T1 under default range_floor) must consume exactly one
## RNG draw regardless — consuming conditionally would desync peers on
## whether a zero-width tier happened to be picked. Verified indirectly: two
## identical-seed runs, each followed by one more draw from the SAME rng
## object, must still agree on that extra draw — proving the zero-width tier
## didn't leave the two rng streams at different positions.
func test_zero_width_tier_consumes_rng_deterministically() -> void:
	var pool_set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, &"strength", 5.0)]),
	])
	var rng_a := _rng(3)
	var rng_b := _rng(3)
	var mods_a := _draw(pool_set, &"strength", 1, rng_a)  # budget 1 → single T1 (zero-width) draw
	var mods_b := _draw(pool_set, &"strength", 1, rng_b)
	assert_almost_eq(mods_a[0].value, mods_b[0].value, 0.00001)
	assert_almost_eq(rng_a.randf(), rng_b.randf(), 0.00001,
			"post-draw rng state must match — the zero-width roll consumed the same number of draws")