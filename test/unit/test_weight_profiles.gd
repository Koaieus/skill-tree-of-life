extends GutTest

## Covers ArchetypeWeightProfile, the forbid-tag filter, and their composition
## through the procgen pick path (`GraphProcgen._v4_weighted_pick`) and the
## real v4 draw (`GraphProcgen._roll_modifiers_v4`).


## Budget-exhaustion roll loop over the surviving pick primitive. Mirrors how
## the per-node draw consumes budget: pick → append → subtract cost → repeat.
## Kept here (rather than in graph_procgen) so archetype-bias / forbid can be
## asserted against a flat entry list in isolation. No debuff
## entries in this suite; negative pools cost budget like any other (refunds retired, #637).
func _roll_pipeline(
		entries: Array[ModifierPoolEntry],
		profiles: Array[Resource],
		archetype: StringName,
		forbid_tags: Array[StringName],
		budget: int,
		rng: RandomNumberGenerator,
) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var ctx := WeightContext.new()
	ctx.archetype = archetype
	ctx.position = Vector2.ZERO
	ctx.node_index = 0
	ctx.forbid_tags = forbid_tags
	var remaining := budget
	while remaining > 0:
		var entry := GraphProcgen._v4_weighted_pick(entries, profiles, ctx, remaining, rng)
		if entry == null:
			break
		out.append(entry.roll(rng))
		remaining -= entry.cost
	return out


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


# ── Composition / end-to-end through the procgen pick path ────────────────


func test_v2_pipeline_archetype_steers_picks_red() -> void:
	# Heavy archetype bias toward STR; with the same equal base weights, RED
	# context should overwhelmingly draw STR. Sample many draws.
	var entries: Array[ModifierPoolEntry] = [
		_entry(&"str_t1", &"strength", [&"str"], 1, 1.0),
		_entry(&"int_t1", &"intelligence", [&"int"], 1, 1.0),
	]
	var arch := ArchetypeWeightProfile.new()
	arch.weights = {&"red": {&"str": 10.0, &"int": 0.1}}
	var profiles: Array[Resource] = [arch]
	var str_hits := 0
	var total := 200
	for i in total:
		var rng := RandomNumberGenerator.new()
		rng.seed = i + 1
		# Budget 1 → exactly one draw per call.
		var rolled := _roll_pipeline(entries, profiles, &"red", [] as Array[StringName], 1, rng)
		assert_eq(rolled.size(), 1)
		if rolled[0].stat_id == &"strength":
			str_hits += 1
	# At 10× vs 0.1× bias (ratio 100:1), STR should hit > 95%.
	assert_gt(str_hits, 190, "expected ≥95%% STR with ×100 bias; got %d/%d" % [str_hits, total])


func test_v2_pipeline_forbid_tags_hard_excludes() -> void:
	# Gold archetype: forbid str/dex/int — only WIS-tagged entries should survive.
	var entries: Array[ModifierPoolEntry] = [
		_entry(&"str_t1", &"strength", [&"str", &"flat"], 1, 10.0),
		_entry(&"dex_t1", &"dexterity", [&"dex", &"flat"], 1, 10.0),
		_entry(&"int_t1", &"intelligence", [&"int", &"flat"], 1, 10.0),
		_entry(&"wis_t1", &"wisdom", [&"wis", &"flat"], 1, 1.0),
	]
	var forbid: Array[StringName] = [&"str", &"dex", &"int"]
	var rolled := _roll_pipeline(entries, [] as Array[Resource], &"gold", forbid, 5, RandomNumberGenerator.new())
	# Every pick lands on wisdom despite its 10x lower base weight.
	assert_eq(rolled.size(), 5, "budget 5 of cost-1 picks must draw five times; got %d" % rolled.size())
	for m in rolled:
		assert_eq(m.stat_id, &"wisdom", "forbid tags must hard-exclude str/dex/int")


func test_v2_pipeline_empty_pool_returns_empty() -> void:
	var entries: Array[ModifierPoolEntry] = []
	var rng := RandomNumberGenerator.new()
	var rolled := _roll_pipeline(entries, [] as Array[Resource], &"red", [] as Array[StringName], 5, rng)
	assert_eq(rolled.size(), 0)


# ── Characterization: v4 fuses duplicate (stat, op) picks ────────────────


## One cost-1 STR ADD_BASE tier, budget 3: the real draw picks it three times
## and aggregation fuses the three picks into ONE modifier. Duplicate
## (stat, op) picks are the draw model, not a defect — a profile that
## forbids them would starve this node down to a single pick.
func test_v4_draw_fuses_duplicate_stat_op_picks_into_one_modifier() -> void:
	var p := StatPool.new()
	p.stat_id = &"strength"
	p.operation = StatModifier.Operation.ADD_BASE
	p.unit_value = 2.0
	p.range_floor = 1.0  # positive floor — no fused no-op, no re-roll path
	p.min_tier = 1
	p.max_tier = 1
	var pack := StatPack.new()
	pack.archetype_stat = &"strength"
	var pools: Array[StatPool] = [p]
	pack.pools = pools
	var pool_set := ModifierPoolSet.new()
	var packs: Array[StatPack] = [pack]
	pool_set.packs = packs
	var arch := ArchetypeWeightProfile.new()
	arch.weights = {&"red": {&"str": 3.0}}
	var profiles: Array[Resource] = [arch]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fp := {}
	var mods: Array[StatModifier] = GraphProcgen._roll_modifiers_v4(
			pool_set, profiles, &"red", &"strength", [] as Array[StringName],
			Vector2.ZERO, 0, 3, rng, fp)
	assert_eq(fp.get("draws", 0), 3, "budget 3 of cost-1 picks must draw three times")
	assert_eq(mods.size(), 1, "three STR ADD_BASE picks must fuse into one modifier; got %d" % mods.size())
	assert_eq(mods[0].stat_id, &"strength")
	assert_eq(mods[0].operation, StatModifier.Operation.ADD_BASE)
