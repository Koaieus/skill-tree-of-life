extends GutTest

## Phased modifier draw (v3): primary → off (cost-capped) → defensive → rare.

const _SCRIPT := preload("res://procgen/graph_procgen.gd")


func _tier(t: int, lo: float, hi: float, cost: int = 1, weight: float = 1.0) -> TierDef:
	var d := TierDef.new()
	d.tier = t
	d.value_range = Vector2(lo, hi)
	d.cost = cost
	d.weight = weight
	return d


func _pool(
		stat_id: StringName,
		op: int,
		role: int,
		archetype_stat: StringName,
		tiers: Array,
) -> TierPool:
	var p := TierPool.new()
	p.stat_id = stat_id
	p.operation = op
	p.role = role
	p.archetype_stat = archetype_stat
	var typed: Array[TierDef] = []
	for t in tiers:
		typed.append(t)
	p.tiers = typed
	return p


func _pack(archetype_stat: StringName, pools: Array, off_weights: Dictionary = {}) -> StatPack:
	var sp := StatPack.new()
	sp.archetype_stat = archetype_stat
	var typed: Array[TierPool] = []
	for p in pools:
		typed.append(p)
	sp.pools = typed
	var typed_w: Dictionary[StatModifier.Operation, float] = {}
	for k in off_weights:
		typed_w[k] = float(off_weights[k])
	sp.off_phase_op_weights = typed_w
	return sp


func _make_set(packs: Array, slot_count: int = 3) -> ModifierPoolSet:
	var s := ModifierPoolSet.new()
	var typed: Array[StatPack] = []
	for p in packs:
		typed.append(p)
	s.packs = typed
	s.slot_count_weights = {slot_count: 1.0}
	return s


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _draw(set: ModifierPoolSet, primary_stat: StringName, budget: int, rng: RandomNumberGenerator) -> Array:
	return _SCRIPT._roll_modifiers_v3(
			set, [], &"strength", primary_stat, [], Vector2.ZERO, 0, budget, rng)


func test_primary_only_when_no_off_pools() -> void:
	var set := _make_set([
		_pack(&"strength", [
			_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength",
				[_tier(1, 1, 3, 1, 10), _tier(2, 5, 9, 3, 5)]),
		]),
	])
	var mods := _draw(set, &"strength", 100, _rng(7))
	for m in mods:
		assert_eq(m.stat_id, &"strength")


func test_phase_3_off_attribute_is_cost_capped() -> void:
	# Primary STR with cost-1 only; DEX off-attribute with cost 5 — filtered out.
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength",
				[_tier(1, 1, 1, 1, 10)])]),
		_pack(&"dexterity", [_pool(&"dexterity", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"dexterity",
				[_tier(3, 10, 10, 5, 10)])]),
	])
	set.primary_share_ratio = 0.6
	set.off_cost_cap_offset = 1
	set.off_cost_cap_factor = 1.0
	var mods := _draw(set, &"strength", 100, _rng(7))
	for m in mods:
		assert_eq(m.stat_id, &"strength", "off-attribute should be filtered by cost cap")


func test_defensive_exempt_from_cost_cap() -> void:
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength",
				[_tier(1, 1, 1, 1, 10)])]),
		_pack(&"", [_pool(&"node_health", StatModifier.Operation.ADD_BASE, TierPool.Role.DEFENSIVE, &"",
				[_tier(1, 2, 4, 5, 100)])]),
	])
	set.primary_share_ratio = 0.6
	set.off_cost_cap_offset = 1
	set.off_cost_cap_factor = 1.0
	var saw_defensive := false
	for trial in 30:
		var mods := _draw(set, &"strength", 100, _rng(trial))
		for m in mods:
			if m.stat_id == &"node_health":
				saw_defensive = true
				break
	assert_true(saw_defensive, "defensive node_health should land at least once in 30 trials despite cost > cap")


func test_slot_count_caps_modifier_count_independent_of_budget() -> void:
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength",
				[_tier(1, 1, 1, 1, 1)])]),
	], 2)
	var mods := _draw(set, &"strength", 10000, _rng(42))
	assert_eq(mods.size(), 2)


func test_zero_budget_returns_empty() -> void:
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength",
				[_tier(1, 1, 1, 1, 1)])]),
	])
	var mods := _draw(set, &"strength", 0, _rng(1))
	assert_eq(mods.size(), 0)


func test_off_cost_cap_factor_tightens_cap() -> void:
	# Primary peak cost 10. With factor=0.5, off cap = floor(10*0.5) - 0 = 5.
	# DEX entries at cost 8 should be filtered out.
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength",
				[_tier(1, 1, 1, 10, 1)])]),
		_pack(&"dexterity", [_pool(&"dexterity", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"dexterity",
				[_tier(1, 1, 1, 8, 1)])]),
	])
	set.off_cost_cap_factor = 0.5
	set.off_cost_cap_offset = 0
	# DEX cost 8 > floor(10*0.5)=5 → filtered.
	for trial in 20:
		var mods := _draw(set, &"strength", 100, _rng(trial))
		for m in mods:
			assert_eq(m.stat_id, &"strength", "DEX off should be filtered by factor=0.5")
