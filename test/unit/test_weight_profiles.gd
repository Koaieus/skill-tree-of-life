extends GutTest

## Covers ArchetypeWeightProfile + CollisionProfile + their composition through
## the procgen v2 pick path.


func _entry(id: StringName, stat_id: StringName, tags: Array, cost: int = 1, weight: float = 1.0) -> ModifierPoolEntry:
	var e := ModifierPoolEntry.new()
	e.id = id
	e.stat_id = stat_id
	e.operation = StatModifier.Operation.ADD_BASE
	e.value_range = Vector2(1, 1)
	e.cost = cost
	e.weight = weight
	var typed: Array[StringName] = []
	for t in tags:
		typed.append(StringName(t))
	e.tags = typed
	return e


func _modifier(stat_id: StringName, op: int = StatModifier.Operation.ADD_BASE) -> StatModifier:
	var m := StatModifier.new()
	m.stat_id = stat_id
	m.operation = op
	return m


# ── ArchetypeWeightProfile ────────────────────────────────────────────────


func test_archetype_profile_boosts_matching_tags() -> void:
	var p := ArchetypeWeightProfile.new()
	p.weights = {&"red": {&"str": 3.0, &"int": 0.2}}
	var e := _entry(&"str_t1", &"strength", [&"str", &"flat"])
	var ctx := WeightContext.new()
	ctx.archetype = &"red"
	assert_almost_eq(p.multiplier_for(e, ctx), 3.0, 0.0001)


func test_archetype_profile_compresses_unmatched_tags() -> void:
	var p := ArchetypeWeightProfile.new()
	p.weights = {&"red": {&"str": 3.0, &"int": 0.2}}
	var e := _entry(&"int_t1", &"intelligence", [&"int", &"flat"])
	var ctx := WeightContext.new()
	ctx.archetype = &"red"
	assert_almost_eq(p.multiplier_for(e, ctx), 0.2, 0.0001)


func test_archetype_profile_multiplies_multiple_matching_tags() -> void:
	var p := ArchetypeWeightProfile.new()
	p.weights = {&"red": {&"str": 3.0, &"flat": 2.0}}
	var e := _entry(&"str_t1", &"strength", [&"str", &"flat"])
	var ctx := WeightContext.new()
	ctx.archetype = &"red"
	assert_almost_eq(p.multiplier_for(e, ctx), 6.0, 0.0001)


func test_archetype_profile_unknown_archetype_passes_through() -> void:
	var p := ArchetypeWeightProfile.new()
	p.weights = {&"red": {&"str": 3.0}}
	var e := _entry(&"str_t1", &"strength", [&"str"])
	var ctx := WeightContext.new()
	ctx.archetype = &"unknown_archetype"
	assert_almost_eq(p.multiplier_for(e, ctx), 1.0, 0.0001)


# ── CollisionProfile ──────────────────────────────────────────────────────


func test_collision_zeroes_duplicate_stat_op_pair() -> void:
	var p := CollisionProfile.new()
	var ctx := WeightContext.new()
	ctx.already_rolled = [_modifier(&"strength", StatModifier.Operation.ADD_BASE)]
	var e := _entry(&"str_t2", &"strength", [&"str"])  # same stat + ADD_BASE
	assert_eq(p.multiplier_for(e, ctx), 0.0)


func test_collision_allows_same_stat_different_op() -> void:
	var p := CollisionProfile.new()
	var ctx := WeightContext.new()
	ctx.already_rolled = [_modifier(&"strength", StatModifier.Operation.ADD_BASE)]
	var e := _entry(&"str_pct", &"strength", [&"str", &"percent"])
	e.operation = StatModifier.Operation.INCREASE
	assert_eq(p.multiplier_for(e, ctx), 1.0)


func test_collision_allows_different_stat_same_op() -> void:
	var p := CollisionProfile.new()
	var ctx := WeightContext.new()
	ctx.already_rolled = [_modifier(&"strength", StatModifier.Operation.ADD_BASE)]
	var e := _entry(&"dex_t1", &"dexterity", [&"dex"])
	assert_eq(p.multiplier_for(e, ctx), 1.0)


func test_collision_empty_already_rolled_is_passthrough() -> void:
	var p := CollisionProfile.new()
	var ctx := WeightContext.new()
	var e := _entry(&"str_t1", &"strength", [&"str"])
	assert_eq(p.multiplier_for(e, ctx), 1.0)


# ── Composition / end-to-end through the procgen pick path ────────────────


func test_v2_pipeline_collision_prevents_duplicate_stat_op_on_node() -> void:
	# A pool with two STR-ADD_BASE entries + one DEX entry; budget 4 of cost-1
	# entries. With CollisionProfile in play, only ONE STR-ADD_BASE can be drawn;
	# the rest must be DEX (the only other option).
	var pool := ModifierPool.new()
	pool.entries = [
		_entry(&"str_t1", &"strength", [&"str", &"flat"], 1, 10.0),
		_entry(&"str_t2", &"strength", [&"str", &"flat"], 1, 10.0),
		_entry(&"dex_t1", &"dexterity", [&"dex", &"flat"], 1, 1.0),
	]
	var profiles: Array[Resource] = [CollisionProfile.new()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rolled := GraphProcgen._roll_modifiers_v2(pool, profiles, &"red", Vector2.ZERO, 0, 4, rng)
	# Only 2 distinct (stat_id, ADD_BASE) pairs in the pool: strength + dexterity.
	# Collision blocks repeats → max 2 picks even though budget allows 4.
	assert_eq(rolled.size(), 2, "collision should cap at one pick per (stat, op) pair")
	var str_count := 0
	var dex_count := 0
	for m in rolled:
		if m.stat_id == &"strength":
			str_count += 1
		elif m.stat_id == &"dexterity":
			dex_count += 1
	assert_eq(str_count, 1, "CollisionProfile must prevent multiple STR ADD_BASE picks; got %d" % str_count)
	assert_eq(dex_count, 1, "one DEX pick expected; got %d" % dex_count)


func test_v2_pipeline_archetype_steers_picks_red() -> void:
	# Heavy archetype bias toward STR; with the same equal base weights, RED
	# context should overwhelmingly draw STR. Sample many draws.
	var pool := ModifierPool.new()
	pool.entries = [
		_entry(&"str_t1", &"strength", [&"str"], 1, 1.0),
		_entry(&"int_t1", &"intelligence", [&"int"], 1, 1.0),
	]
	var arch := ArchetypeWeightProfile.new()
	arch.weights = {&"red": {&"str": 10.0, &"int": 0.1}}
	# No CollisionProfile — we want repeated independent draws.
	var profiles: Array[Resource] = [arch]
	var str_hits := 0
	var total := 200
	for i in total:
		var rng := RandomNumberGenerator.new()
		rng.seed = i + 1
		# Budget 1 → exactly one draw per call.
		var rolled := GraphProcgen._roll_modifiers_v2(pool, profiles, &"red", Vector2.ZERO, 0, 1, rng)
		assert_eq(rolled.size(), 1)
		if rolled[0].stat_id == &"strength":
			str_hits += 1
	# At 10× vs 0.1× bias (ratio 100:1), STR should hit > 95%.
	assert_gt(str_hits, 190, "expected ≥95%% STR with ×100 bias; got %d/%d" % [str_hits, total])


func test_v2_pipeline_empty_pool_returns_empty() -> void:
	var pool := ModifierPool.new()
	var rng := RandomNumberGenerator.new()
	var rolled := GraphProcgen._roll_modifiers_v2(pool, [], &"red", Vector2.ZERO, 0, 5, rng)
	assert_eq(rolled.size(), 0)
