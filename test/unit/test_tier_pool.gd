extends GutTest

## TierPool → ModifierPoolEntry expansion, StatPack grouping, and
## ModifierPoolSet phase filtering with off-phase pack-level suppression.

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


func _make_set(packs: Array) -> ModifierPoolSet:
	var s := ModifierPoolSet.new()
	var typed: Array[StatPack] = []
	for p in packs:
		typed.append(p)
	s.packs = typed
	return s


func test_tier_pool_flattens_to_entries() -> void:
	var p := _pool(&"strength", StatModifier.Operation.ADD_BASE,
			TierPool.Role.PRIMARY, &"strength",
			[_tier(1, 1, 3, 1, 10), _tier(2, 5, 9, 3, 5), _tier(3, 15, 25, 9, 1)])
	var entries := p.to_entries()
	assert_eq(entries.size(), 3)
	assert_eq(entries[0].stat_id, &"strength")
	assert_eq(entries[0].operation, StatModifier.Operation.ADD_BASE)
	assert_almost_eq(entries[0].value_range.x, 1.0, 0.001)
	assert_almost_eq(entries[0].value_range.y, 3.0, 0.001)
	assert_eq(entries[2].cost, 9)
	# Stable id pattern.
	assert_eq(entries[0].id, &"strength_addb_strength_t1")


func test_phase_primary() -> void:
	var set := _make_set([
		_pack(&"strength", [
			_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength", [_tier(1, 1, 3)]),
		]),
		_pack(&"dexterity", [
			_pool(&"dexterity", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"dexterity", [_tier(1, 1, 3)]),
		]),
		_pack(&"", [
			_pool(&"node_health", StatModifier.Operation.ADD_BASE, TierPool.Role.DEFENSIVE, &"", [_tier(1, 2, 4)]),
		]),
	])
	var primary := set.flatten_for_phase(&"primary", &"strength")
	assert_eq(primary.size(), 1)
	assert_eq(primary[0].stat_id, &"strength")


func test_phase_off_excludes_primary_and_empty_affinity() -> void:
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength", [_tier(1, 1, 3)])]),
		_pack(&"dexterity", [_pool(&"dexterity", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"dexterity", [_tier(1, 1, 3)])]),
		_pack(&"intelligence", [_pool(&"intelligence", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"intelligence", [_tier(1, 1, 3)])]),
		_pack(&"", [_pool(&"node_health", StatModifier.Operation.ADD_BASE, TierPool.Role.DEFENSIVE, &"", [_tier(1, 2, 4)])]),
	])
	var off := set.flatten_for_phase(&"off", &"strength")
	# DEX + INT, but NOT STR (primary) and NOT node_health (defensive, empty affinity)
	assert_eq(off.size(), 2)
	for e in off:
		assert_ne(e.stat_id, &"strength")
		assert_ne(e.stat_id, &"node_health")


func test_phase_defensive() -> void:
	var set := _make_set([
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength", [_tier(1, 1, 3)])]),
		_pack(&"", [
			_pool(&"node_health", StatModifier.Operation.ADD_BASE, TierPool.Role.DEFENSIVE, &"", [_tier(1, 2, 4), _tier(2, 5, 8)]),
			_pool(&"armor", StatModifier.Operation.ADD_BASE, TierPool.Role.DEFENSIVE, &"", [_tier(1, 1, 1)]),
		]),
	])
	var uni := set.flatten_for_phase(&"defensive", &"strength")
	# 2 tiers from node_health + 1 from armor.
	assert_eq(uni.size(), 3)


func test_phase_rare() -> void:
	var set := _make_set([
		_pack(&"", [_pool(&"min_damage_taken", StatModifier.Operation.ADD_BASE, TierPool.Role.RARE, &"", [_tier(1, -1, -1, 20, 0.5)])]),
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength", [_tier(1, 1, 3)])]),
	])
	var rare := set.flatten_for_phase(&"rare", &"strength")
	assert_eq(rare.size(), 1)
	assert_eq(rare[0].stat_id, &"min_damage_taken")


func test_off_phase_op_weights_multiply_entry_weight() -> void:
	# wisdom pack with INCREASE weight × 0.05 on off-phase. The MULTIPLY entry
	# is excluded (weight 0). Off-phase from a non-WIS node sees only the
	# scaled ADD_BASE and INCREASE entries, no MULTIPLY.
	var set := _make_set([
		_pack(&"wisdom", [
			_pool(&"wisdom", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"wisdom",
				[_tier(1, 1, 3, 1, 10.0)]),
			_pool(&"wisdom", StatModifier.Operation.INCREASE, TierPool.Role.PRIMARY, &"wisdom",
				[_tier(1, 5, 10, 2, 6.0)]),
			_pool(&"wisdom", StatModifier.Operation.MULTIPLY, TierPool.Role.PRIMARY, &"wisdom",
				[_tier(1, 1.2, 1.3, 30, 2.0)]),
		], {
			StatModifier.Operation.ADD_BASE: 0.2,
			StatModifier.Operation.INCREASE: 0.05,
			StatModifier.Operation.MULTIPLY: 0.0,
		}),
		# Need *another* primary pack so the off-phase query has something to
		# return matching the rule "archetype_stat != primary_stat && != &"".
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength", [_tier(1, 1, 3)])]),
	])
	# Roll from a STR-primary node — off-phase pulls wisdom + strength (no,
	# strength is primary). Wait, primary_stat=&"strength" matches the strength
	# pack, so off picks up wisdom. Verify multiplier applied.
	var off := set.flatten_for_phase(&"off", &"strength")
	# Expect 2 entries (ADD_BASE + INCREASE from wisdom), MULTIPLY excluded.
	assert_eq(off.size(), 2)
	for e in off:
		assert_ne(e.operation, StatModifier.Operation.MULTIPLY, "MULTIPLY should be hard-excluded by 0.0 weight")
		if e.operation == StatModifier.Operation.ADD_BASE:
			# Original weight 10.0 × 0.2 = 2.0
			assert_almost_eq(e.weight, 2.0, 0.001)
		elif e.operation == StatModifier.Operation.INCREASE:
			# Original weight 6.0 × 0.05 = 0.3
			assert_almost_eq(e.weight, 0.3, 0.001)


func test_off_phase_default_weights_pass_through() -> void:
	# StatPack without explicit off_phase_op_weights → no suppression.
	var set := _make_set([
		_pack(&"dexterity", [
			_pool(&"dexterity", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"dexterity",
				[_tier(1, 1, 3, 1, 7.0)]),
		]),
		_pack(&"strength", [_pool(&"strength", StatModifier.Operation.ADD_BASE, TierPool.Role.PRIMARY, &"strength", [_tier(1, 1, 3)])]),
	])
	var off := set.flatten_for_phase(&"off", &"strength")
	assert_eq(off.size(), 1)
	assert_almost_eq(off[0].weight, 7.0, 0.001, "default empty dict should not modify weight")
